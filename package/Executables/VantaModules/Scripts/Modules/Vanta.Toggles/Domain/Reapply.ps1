# Vanta.Toggles domain: upgrade and same-version replay.
#
# Recorded choices are declarative machine state. Under strict TrustedInstaller, replay
# resolves each record against the installed definition and re-applies only that
# state's machine work. User work is replayed separately in each account's own
# non-elevated first sign-in process.

# Records listed here replay first, in this order; the rest follow in registry order.
# PowerSaving rebuilds or switches the active power plan, which drops per-plan choices
# such as CpuIdle and Sleep, so it goes first.
$script:VantaToggleReplayFirst = @('PowerSaving')

function New-VantaToggleStaleReplayRecordException {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message
    )

    $exception = [System.IO.InvalidDataException]::new($Message)
    $exception.Data['VantaToggleReplayRecordDisposition'] = 'Stale'
    return $exception
}

function Get-VantaToggleReplayDefinition {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [string]$TogglesRoot
    )

    try {
        $path = Find-VantaToggleDefinitionFile -Name $Name -TogglesRoot $TogglesRoot
    }
    catch {
        # A record whose definition Vanta no longer includes is stale. Any other lookup failure
        # (a missing root, an ambiguous name) is operational and must preserve the record.
        if ($_.Exception.Data['VantaToggleDefinitionMissing'] -eq $true) {
            throw (New-VantaToggleStaleReplayRecordException -Message "has no installed toggle definition named '$Name'.")
        }
        throw
    }

    # Loading or validating an installed definition is operational work. Those failures
    # must preserve the user's record so a corrected Vanta version can replay it later.
    return Import-VantaToggleDefinitionFile -Path $path
}

function Resolve-VantaToggleReplayRecord {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        $Subkey,

        [string]$TogglesRoot
    )

    $properties = Get-ItemProperty -LiteralPath $Subkey.PSPath -ErrorAction Stop
    # This tree also holds product metadata, such as the previous power-scheme GUID.
    # A key without a state value is not a recorded toggle choice.
    if ($null -eq $properties -or -not $properties.PSObject.Properties['state']) {
        return $null
    }
    if ($Subkey.GetValueKind('state') -ne [Microsoft.Win32.RegistryValueKind]::DWord) {
        throw (New-VantaToggleStaleReplayRecordException -Message 'has no REG_DWORD state.')
    }
    $recordedState = [int]$properties.state

    $definition = Get-VantaToggleReplayDefinition -Name ([string]$Subkey.PSChildName) -TogglesRoot $TogglesRoot
    if ($definition.Contains('NoStateRecord') -and [bool]$definition['NoStateRecord']) {
        throw (New-VantaToggleStaleReplayRecordException -Message 'belongs to a definition that no longer records state.')
    }

    $matchingStates = @($definition['States'].Keys | Where-Object {
            $entry = $definition['States'][$_]
            $entry.Contains('StateValue') -and [int]$entry['StateValue'] -eq $recordedState
        })
    if ($matchingStates.Count -ne 1) {
        throw (New-VantaToggleStaleReplayRecordException -Message "state '$recordedState' does not map to exactly one installed state.")
    }

    $stateName = [string]$matchingStates[0]
    $stateEntry = $definition['States'][$stateName]
    if (-not (Test-VantaToggleRecordsState -Definition $definition -StateEntry $stateEntry)) {
        throw (New-VantaToggleStaleReplayRecordException -Message "state '$stateName' no longer records state.")
    }

    return [pscustomobject]@{
        Definition    = $definition
        RecordedState = $recordedState
        StateName     = $stateName
        StateEntry    = $stateEntry
        Work          = Get-VantaToggleStateWork -Definition $definition -StateEntry $stateEntry
    }
}

function Remove-VantaToggleReplayRecord {
    <#
    .SYNOPSIS
        Clears a stale record's state and launcher path, and its key once nothing else
        is left in it.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'This private cleanup runs only inside the strict-TI replay transaction.'
    )]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$KeyPath,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Reason
    )

    # Expected after an update from an older Vanta, whose records this version no
    # longer uses: clearing one changes nothing on the PC, so it isn't a warning.
    Write-VantaLog -Message "Toggle '$Name' $Reason Cleared its old record; the PC itself is unchanged."
    $key = Get-Item -LiteralPath $KeyPath -ErrorAction Stop
    foreach ($valueName in @('state', 'path')) {
        if (@($key.GetValueNames()) -contains $valueName) {
            Remove-ItemProperty -LiteralPath $KeyPath -Name $valueName -Force -ErrorAction Stop
        }
    }
    # The replay engine owns only its state and legacy executable-path values.
    # Keep other values and child keys so stale choices cannot erase restore metadata.
    if (@($key.GetValueNames()).Count -eq 0 -and @($key.GetSubKeyNames()).Count -eq 0) {
        Remove-Item -LiteralPath $KeyPath -Force -ErrorAction Stop
    }
}

function Test-VantaToggleReplayApplicable {
    <#
    .SYNOPSIS
        Evaluates a state's optional ReplayApplicable companion function. Returns $true
        when the state declares none.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Definition,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$StateName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$StateRoot
    )

    $stateEntry = $Definition['States'][$StateName]
    if (-not (Test-VantaToggleStateHasKey -StateEntry $stateEntry -Key 'ReplayApplicable')) {
        return $true
    }

    $toggle = New-VantaToggleContext -Definition $Definition -StateName $StateName -Silent -NoExplorerRestart -StateRoot $StateRoot
    return [bool](Invoke-VantaToggleFunction -Definition $Definition -FunctionName ([string]$stateEntry['ReplayApplicable']) `
            -Toggle $toggle -Label 'replay applicability check')
}

function Invoke-VantaToggleReapply {
    <#
    .SYNOPSIS
        Replays the machine work of every recorded state from the installed definitions,
        except the toggles -Exclude names.
    #>
    param(
        [ValidateNotNullOrEmpty()]
        [string]$StateRoot = $script:VantaToggleDefaultStateRoot,

        # Overridable for tests; defaults to the installed Toggles directory.
        [string]$TogglesRoot,

        # Toggles this install has just set to the states chosen for it, as the Choices
        # step does when an update chooses again. Their records stay as they are,
        # unreplayed, and still reach the state document.
        [AllowEmptyCollection()]
        [string[]]$Exclude = @()
    )

    Assert-VantaPrivilege -TrustedInstaller
    if (-not (Test-Path -LiteralPath $StateRoot)) {
        Write-VantaLog -Level Warning -Message "Registry path '$StateRoot' not found, skipping."
        return
    }

    Protect-VantaToggleStateRoot -StateRoot $StateRoot -IncludeChildren
    Repair-VantaLegacyToggleAlias -StateRoot $StateRoot
    $failures = @()

    $subkeys = @(Get-ChildItem -LiteralPath $StateRoot -ErrorAction Stop)
    $replayOrder = @(foreach ($firstName in $script:VantaToggleReplayFirst) {
            $subkeys | Where-Object { [string]$_.PSChildName -ieq $firstName }
        }) + @($subkeys | Where-Object { $script:VantaToggleReplayFirst -notcontains [string]$_.PSChildName })

    foreach ($subkey in $replayOrder) {
        $name = [string]$subkey.PSChildName
        # A key without a state holds only metadata, so this install didn't apply it.
        if ($Exclude -icontains $name -and @($subkey.GetValueNames()) -icontains 'state') {
            Write-VantaLog -Message "Toggle '$name' was applied by this installation's choices, so it isn't replayed."
            continue
        }

        try {
            Repair-VantaLegacyContextMenuState -Key $subkey
            Repair-VantaLegacyVerboseMessagesState -Key $subkey
            Repair-VantaLegacyToggleState -Key $subkey
            $replay = Resolve-VantaToggleReplayRecord -Subkey $subkey -TogglesRoot $TogglesRoot
        }
        catch {
            if ($_.Exception.Data['VantaToggleReplayRecordDisposition'] -ceq 'Stale') {
                Remove-VantaToggleReplayRecord -Name $name -KeyPath $subkey.PSPath -Reason $_.Exception.Message
            }
            else {
                $failureMessage = $_.Exception.Message
                Write-VantaLog -Level Warning -Message `
                    "Resolving toggle '$name' for re-apply failed; preserving its record: $failureMessage" -ErrorRecord $_
                $failures += [pscustomobject]@{ Name = $name; Message = [string]$failureMessage }
            }
            continue
        }

        if ($null -eq $replay) {
            Remove-VantaToggleLegacyPath -KeyPath $subkey.PSPath
            continue
        }

        Remove-VantaToggleLegacyPath -KeyPath $subkey.PSPath

        $definition = $replay.Definition
        $stateName = $replay.StateName
        if ((Get-VantaToggleElevation -Definition $definition) -cnotin @('Admin', 'TrustedInstaller')) {
            Write-VantaLog -Level Warning -Message `
                "Toggle '$name' state '$stateName' is not an elevated toggle; leaving its record unchanged."
            continue
        }
        if (-not $replay.Work.Machine) {
            # A record with only user work exists to drive first sign-in replay.
            Write-VantaLog -Message "Toggle '$name' state '$stateName' has no machine work to re-apply."
            continue
        }

        try {
            $isReplayApplicable = Test-VantaToggleReplayApplicable -Definition $definition -StateName $stateName -StateRoot $StateRoot
        }
        catch {
            $failureMessage = $_.Exception.Message
            Write-VantaLog -Level Warning -Message `
                "Checking replay applicability for toggle '$name' failed; preserving its record: $failureMessage" -ErrorRecord $_
            $failures += [pscustomobject]@{ Name = $name; Message = [string]$failureMessage }
            continue
        }
        if (-not $isReplayApplicable) {
            Remove-VantaToggleReplayRecord -Name $name -KeyPath $subkey.PSPath `
                -Reason "state '$stateName' is no longer applicable."
            continue
        }

        Write-VantaLog -Message "Re-applying toggle '$name' machine state '$stateName'."
        try {
            Invoke-VantaToggleInProcess -Definition $definition -StateName $stateName -Scope Machine `
                -Silent -NoExplorerRestart -SkipPreamble -StateRoot $StateRoot
        }
        catch {
            $failureMessage = $_.Exception.Message
            Write-VantaLog -Level Warning -Message "Re-applying toggle '$name' failed: $failureMessage" -ErrorRecord $_
            $failures += [pscustomobject]@{ Name = $name; Message = [string]$failureMessage }
        }
    }

    # Stale records were removed above; the document must reflect the surviving set.
    Sync-VantaToggleStateDocument -StateRoot $StateRoot

    if ($failures.Count -gt 0) {
        $failureDetails = @($failures | ForEach-Object { "'$($_.Name)': $($_.Message)" }) -join '; '
        throw "Upgrade toggle re-apply failed for $($failures.Count) toggle(s): $failureDetails"
    }
}

function Invoke-VantaToggleUserReapply {
    <#
    .SYNOPSIS
        Replays the user work of every recorded state for the current non-elevated user.
    #>
    param(
        [ValidateNotNullOrEmpty()]
        [string]$StateRoot = $script:VantaToggleDefaultStateRoot,

        # Overridable for tests; defaults to the installed Toggles directory.
        [string]$TogglesRoot
    )

    if ((Test-VantaSystem) -or (Test-VantaAdmin)) {
        throw "Per-user toggle replay requires the affected user's non-elevated context."
    }
    if (-not (Test-Path -LiteralPath $StateRoot)) {
        Write-VantaLog -Level Warning -Message "Registry path '$StateRoot' not found, skipping per-user replay."
        return
    }

    $failures = @()
    foreach ($subkey in @(Get-ChildItem -LiteralPath $StateRoot -ErrorAction Stop)) {
        $name = [string]$subkey.PSChildName

        try {
            $replay = Resolve-VantaToggleReplayRecord -Subkey $subkey -TogglesRoot $TogglesRoot
        }
        catch {
            Write-VantaLog -Level Warning -Message `
                "Skipping per-user replay for toggle '$name': $($_.Exception.Message)" -ErrorRecord $_
            continue
        }
        if ($null -eq $replay -or -not $replay.Work.User) {
            continue
        }

        Write-VantaLog -Message "Re-applying toggle '$name' user state '$($replay.StateName)'."
        try {
            Invoke-VantaToggleInProcess -Definition $replay.Definition -StateName $replay.StateName -Scope User `
                -Silent -NoExplorerRestart -SkipPreamble -StateRoot $StateRoot
        }
        catch {
            $failureMessage = $_.Exception.Message
            Write-VantaLog -Level Warning -Message "Re-applying toggle '$name' user state failed: $failureMessage" -ErrorRecord $_
            $failures += [pscustomobject]@{ Name = $name; Message = [string]$failureMessage }
        }
    }

    if ($failures.Count -gt 0) {
        $failureDetails = @($failures | ForEach-Object { "'$($_.Name)': $($_.Message)" }) -join '; '
        throw "User toggle re-apply failed for $($failures.Count) toggle(s): $failureDetails"
    }
}
