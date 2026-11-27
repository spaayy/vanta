# The Microsoft Defender install choice (defender-enable or defender-disable), applied
# through Vanta's NoDefender servicing package. Shared by the Components phase (Fresh and
# Rebase) and the Choices phase (Choose again). Runs as TrustedInstaller; the phase
# imports Vanta.Core, Vanta.Software and Vanta.Security.
#
# It changes only what differs from the choice, so a resumed or repeated run redoes
# nothing, and it never installs a package that is already installed.

function Get-VantaServicingPackageState {
    <#
    .SYNOPSIS
        The servicing state of an Vanta package, from the CBS registry: 'Installed'
        (CurrentState 112), 'InstallPending' (96), 'UninstallPending' (5), or $null when
        no version of it is installed or on its way. With several versions the first of
        those states found wins.
    .NOTES
        The Choices phase decides from Get-VantaTransitionDefenderPackageState
        (WindowsTransition.ps1), which reads the same values; keep the two in step.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        # Tests point these at a scratch key.
        [ValidateNotNull()]
        [Microsoft.Win32.RegistryKey]$BaseKey = [Microsoft.Win32.Registry]::LocalMachine,

        [ValidateNotNullOrEmpty()]
        [string]$PackagesPath = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\Packages'
    )

    $packages = $BaseKey.OpenSubKey($PackagesPath, $false)
    if ($null -eq $packages) {
        return $null
    }
    $states = New-Object 'Collections.Generic.List[int]'
    try {
        # $Name is the Z-Vanta-* name; the legacy Z-Atlas-* package of an older build counts as the same package.
        $legacyName = $Name -replace '^Z-Vanta-', 'Z-Atlas-'
        foreach ($keyName in @($packages.GetSubKeyNames() | Where-Object { $_ -like "$Name~*" -or $_ -like "$legacyName~*" })) {
            $package = $packages.OpenSubKey($keyName, $false)
            if ($null -eq $package) { continue }
            try {
                if (@($package.GetValueNames()) -contains 'CurrentState' -and
                    $package.GetValueKind('CurrentState') -eq [Microsoft.Win32.RegistryValueKind]::DWord) {
                    $states.Add([int]$package.GetValue('CurrentState'))
                }
            }
            finally {
                $package.Dispose()
            }
        }
    }
    finally {
        $packages.Dispose()
    }

    if ($states.Contains(112)) { return 'Installed' }
    if ($states.Contains(96)) { return 'InstallPending' }
    if ($states.Contains(5)) { return 'UninstallPending' }
    return $null
}

function Test-VantaDefenderServicePresent {
    # The WinDefend service key exists while Microsoft Defender is on this PC.
    $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\CurrentControlSet\Services\WinDefend', $false)
    if ($null -eq $key) {
        return $false
    }
    $key.Dispose()
    return $true
}

function Set-VantaDefenderChoice {
    <#
    .SYNOPSIS
        Applies the Microsoft Defender choice where this PC differs from it, and returns
        $true when it changed Defender. Disable installs Vanta's NoDefender package and
        turns Defender's core service off at the next startup; Enable puts the core
        service back, then takes off the NoDefender package.
    .DESCRIPTION
        Only Vanta's own package can be taken off: a Defender that is missing without it
        stays missing, with a warning. NoTelemetry goes on with a Defender change when it
        isn't installed. A package still waiting for a restart can't be reversed before
        it: a removal Vanta can't make is a warning, and a Defender it can't bring back
        fails the install.

        -Fresh is for the Components phase, which puts Vanta's components on a Windows
        that has none of them: a first installation, or a Windows that rebuilt itself.
        NoTelemetry then goes on with either choice, and Disable always sets up the core
        service, as the first installation always has.

        Package failures throw. Install-VantaCbsPackage arms the Safe Mode retry first,
        and a Defender that can't be brought back fails the install, or Vanta would
        report success to a user who chose to keep Defender and has no antivirus.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Enable', 'Disable')]
        [string]$State,

        [switch]$Fresh
    )

    # Z-Vanta-* ships; Z-Atlas-* is the legacy name an uninstall must still match (Unmatched patterns only warn).
    $defenderPattern = '*Z-[AV]*-NoDefender-Package*'
    $telemetryPattern = '*Z-[AV]*-NoTelemetry-Package*'
    $defender = Get-VantaServicingPackageState -Name 'Z-Vanta-NoDefender-Package'
    # A package waiting for the restart is already on its way; installing it again would
    # only repeat the servicing work.
    $telemetryMissing = (Get-VantaServicingPackageState -Name 'Z-Vanta-NoTelemetry-Package') -cnotin @('Installed', 'InstallPending')
    $changed = $false

    # This package may carry no CBS package for this PC: the public edition carries none (Windows refused the only
    # identity Vanta can sign with, and testsigning is never turned on), and none is shipped for ARM64. Then NoTelemetry
    # is simply not installed (the policy and registry tweaks stay) and removing Defender isn't available.
    # Putting Defender back still works.
    if (-not (Test-VantaCbsPackagesAvailable)) {
        Write-VantaLog -Message "This edition carries no Windows servicing packages for this PC, so NoTelemetry is not installed; the telemetry policy tweaks still apply."
        $telemetryMissing = $false
        if ($State -ceq 'Disable' -and $null -eq $defender) {
            Write-VantaLog -Level Warning -Message "Removing Microsoft Defender isn't available in this edition, so Defender stays on."
            return $false
        }
    }

    if ($State -ceq 'Disable') {
        if ($null -eq $defender) {
            $packages = @($defenderPattern)
            if ($telemetryMissing) { $packages += $telemetryPattern }
            Write-VantaLog -Message "Removing Microsoft Defender with Vanta's NoDefender package."
            Install-VantaCbsPackage -Packages $packages -NonInteractive | Out-Null
            $telemetryMissing = $false
            $changed = $true
        }
        elseif ($defender -ceq 'UninstallPending') {
            Write-VantaLog -Level Warning -Message `
                "Vanta's NoDefender package is still waiting for a restart to come off, so Microsoft Defender comes back at the restart and this installation can't remove it. Restart Windows, then use Toggle Defender in the Vanta folder to remove it."
        }
        # CBS doesn't show the core service, so it is read: a run that stopped after the
        # package went on, or an earlier Vanta that never turned it off, left it failing
        # at every startup.
        if ($changed -or ($defender -cin @('Installed', 'InstallPending') -and
                ($Fresh -or -not (Test-VantaDefenderCoreServiceRemoved)))) {
            Set-VantaDefenderCoreService -State Removed
        }
    }
    elseif ($defender -ceq 'Installed') {
        # The core service goes back first, while Defender is still removed and Tamper
        # Protection can't refuse the write.
        Write-VantaLog -Message "Bringing Microsoft Defender back: removing Vanta's NoDefender package."
        Set-VantaDefenderCoreService -State Restored
        $restore = Uninstall-VantaCbsPackage -Packages @($defenderPattern)
        if ($telemetryMissing) {
            Install-VantaCbsPackage -Packages @($telemetryPattern) -NonInteractive | Out-Null
            $telemetryMissing = $false
        }
        if (@($restore.FailedPackages).Count -gt 0) {
            throw "Microsoft Defender couldn't be restored: $(@($restore.FailedPackages) -join ', ')"
        }
        $changed = $true
    }
    elseif ($defender -ceq 'InstallPending') {
        # Defender goes at the restart whatever this run does, so carrying on would
        # report success to a user who chose to keep it.
        throw "Microsoft Defender couldn't be restored: Vanta's NoDefender package is still waiting for a restart to finish installing. Restart Windows, then run the installation again."
    }
    elseif ($null -eq $defender -and -not (Test-VantaDefenderServicePresent)) {
        Write-VantaLog -Level Warning -Message `
            "Microsoft Defender isn't on this PC and no Vanta package removed it, so Vanta can't bring it back."
    }

    if ($Fresh -and $telemetryMissing) {
        Install-VantaCbsPackage -Packages @($telemetryPattern) -NonInteractive | Out-Null
    }
    return $changed
}
