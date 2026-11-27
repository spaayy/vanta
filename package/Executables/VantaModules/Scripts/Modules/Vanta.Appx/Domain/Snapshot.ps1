# Vanta.Appx domain: package snapshot and deprovisioning.
#
# The PowerShell AppX removal plan is bracketed by these two functions:
# Save-VantaAppxSnapshot records the installed package families beforehand, and
# Set-VantaAppxDeprovisioned compares afterwards, registering every removed family
# under the Deprovisioned key so Windows Update doesn't reinstall it. Families the
# plan matched are registered too: one still listed for another account, or still
# provisioned, never leaves the inventory, so the comparison alone misses it.
# https://learn.microsoft.com/windows/application-management/remove-provisioned-apps-during-update

function Get-VantaAppxSnapshotPath {
    <#
    .SYNOPSIS
        Returns the path of the AppX package snapshot.
    .DESCRIPTION
        During an install the snapshot lives with the install's own work, which file
        replacement leaves alone and only completion removes, so a resumed AppX step
        finds the snapshot its interrupted attempt saved (Save-VantaAppxSnapshot).
    #>
    $context = Get-VantaContext
    if ($context.IsInstallStateBacked) {
        return Join-Path -Path $context.WinDir -ChildPath 'VantaOS\Install\work\VantaPackagesOld.txt'
    }
    return Join-Path -Path $context.VantaModulesPath -ChildPath 'VantaPackagesOld.txt'
}

function Get-VantaAppxRemovedPackage {
    <#
    .SYNOPSIS
        Returns the package family names present in the snapshot but no longer
        installed (pure diff helper, kept separate for testability).
    #>
    param(
        [AllowEmptyCollection()]
        [string[]]$Snapshot = @(),

        [AllowEmptyCollection()]
        [string[]]$Current = @()
    )

    return @($Snapshot | Where-Object { $_ -and ($Current -notcontains $_) })
}

function Save-VantaAppxSnapshot {
    <#
    .SYNOPSIS
        Saves the family names of all currently installed AppX packages, so removed
        packages can be deprovisioned afterwards by Set-VantaAppxDeprovisioned.
        During an install, a snapshot already there was saved by an attempt that
        stopped before deprovisioning, so the families it lists are kept: the ones
        that attempt removed are no longer installed, and this inventory alone would
        miss them.
    #>
    param(
        [ValidateNotNullOrEmpty()]
        [string]$Path = (Get-VantaAppxSnapshotPath)
    )

    $parentPath = Split-Path -Parent $Path
    if ($parentPath -and -not (Test-Path -LiteralPath $parentPath -PathType Container)) {
        New-Item -Path $parentPath -ItemType Directory -Force | Out-Null
    }

    # The removal plan operates across every existing user. Snapshot the same
    # all-user Bundle/Main inventory so deprovision markers do not depend on which
    # account happened to start the Vanta installation.
    $current = @(@(Get-AppxPackage -AllUsers -PackageTypeFilter Bundle, Main -ErrorAction Stop).PackageFamilyName |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $gone = @()
    if ((Test-Path -LiteralPath $Path -PathType Leaf) -and (Get-VantaContext).IsInstallStateBacked) {
        $gone = @(Get-Content -LiteralPath $Path -ErrorAction Stop |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $current -notcontains $_ })
    }
    @($current + $gone) | Sort-Object -Unique | Set-Content -LiteralPath $Path -Encoding ASCII
    if ($gone.Count -gt 0) {
        Write-VantaLog -Message "Saved the AppX package snapshot to '$Path', keeping the families an interrupted attempt's snapshot listed that are gone now: $(@($gone | Sort-Object -Unique) -join ', ')."
    }
    else {
        Write-VantaLog -Message "Saved the AppX package snapshot to '$Path'."
    }
}

function Set-VantaAppxDeprovisioned {
    <#
    .SYNOPSIS
        Registers every package family that was removed since Save-VantaAppxSnapshot,
        and every family the removal plans matched, under the AppX Deprovisioned key,
        then deletes the snapshot. Throws when the snapshot is missing, as running
        without it would deprovision nothing silently.
    #>
    param(
        [ValidateNotNullOrEmpty()]
        [string]$SnapshotPath = (Get-VantaAppxSnapshotPath),

        [ValidateNotNullOrEmpty()]
        [string]$DeprovisionedKeyPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Deprovisioned',

        # Overridable for tests. The live all-user inventory is read only after the
        # required snapshot has been validated, so a missing snapshot cannot trigger
        # unrelated package enumeration first.
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$CurrentPackages,

        # Overridable for tests; by default, the families this session's removal
        # plans matched in either inventory.
        [AllowEmptyCollection()]
        [string[]]$MatchedFamilies = @($script:VantaAppxMatchedFamilies)
    )

    if (-not (Test-Path -LiteralPath $SnapshotPath -PathType Leaf)) {
        throw "AppX package snapshot '$SnapshotPath' was not found. Save-VantaAppxSnapshot must run before deprovisioning."
    }

    if (-not $PSBoundParameters.ContainsKey('CurrentPackages')) {
        $CurrentPackages = @(
            (Get-AppxPackage -AllUsers -PackageTypeFilter Bundle, Main -ErrorAction Stop).PackageFamilyName |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                Sort-Object -Unique
        )
    }

    # No -Force on an existing key: recreating it would destroy every entry already
    # registered (the Components phase's Edge keys, OEM entries from the factory image).
    if (-not (Test-Path -LiteralPath $DeprovisionedKeyPath)) {
        New-Item -Path $DeprovisionedKeyPath -Force | Out-Null
    }

    $oldPackages = @(Get-Content -LiteralPath $SnapshotPath -ErrorAction Stop)
    $registered = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($family in (Get-VantaAppxRemovedPackage -Snapshot $oldPackages -Current $CurrentPackages)) {
        if (-not $registered.Add($family)) { continue }
        New-Item -Path $DeprovisionedKeyPath -Name $family -Force | Out-Null
        Write-VantaLog -Message "Deprovisioned removed AppX package family '$family'."
    }
    foreach ($family in @($MatchedFamilies | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        if (-not $registered.Add($family)) { continue }
        New-Item -Path $DeprovisionedKeyPath -Name $family -Force | Out-Null
        Write-VantaLog -Message "Deprovisioned AppX package family '$family', which the removal plan matched."
    }

    Remove-Item -LiteralPath $SnapshotPath -Force -ErrorAction Stop
    $script:VantaAppxMatchedFamilies.Clear()
}
