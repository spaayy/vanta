# Vanta.Toggles domain: verification of recorded toggle states.
#
# A toggle's declarative work can be read back as well as applied. Test-VantaToggleState
# reports every Registry, Services or ScheduledTasks declaration of one state that no
# longer holds on this machine; Test-VantaToggleDrift does that for every recorded
# state. The built-in power-plan action has a read-only probe as well; other
# companion functions are imperative and are not verified here.

function Get-VantaPowerPlanValue {
    param([string]$Path, [string]$Name)
    $value = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop
    return $value.$Name
}

function Test-VantaPowerPlanDrift {
    param([string]$StateName)
    # The Vanta plan's GUID (recorded by Set-VantaPowerSavingState, never a fixed one) and, below, its AC settings must match what
    # Set-VantaPowerSavingState (Vanta.Hardware) applies.
    $root = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes'
    $vanta = $null
    try { $vanta = [string](Get-VantaPowerPlanValue -Path 'HKLM:\SOFTWARE\Vanta\Services\PowerSaving' -Name VantaPowerSchemeGuid) } catch { $vanta = $null }
    $issue = {
        param([string]$Target, [string]$Reason)
        [pscustomobject]@{
            Toggle = 'PowerSaving'; State = $StateName; Scope = 'Machine'; Kind = 'PowerPlan'
            Target = $Target; Reason = $Reason
        }
    }
    try {
        $active = [string](Get-VantaPowerPlanValue -Path $root -Name ActivePowerScheme)
        if ($active -notmatch '^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$') {
            throw 'the active power scheme is not a GUID'
        }
        if ($StateName -ceq 'Enable') {
            if ($vanta -and $active -ieq $vanta) { & $issue $active 'the Vanta plan is active while power saving is recorded as enabled' }
            return
        }
        if (-not $vanta) {
            & $issue $active 'no Vanta plan is recorded while power saving is recorded as disabled'
            return
        }
        if ($active -ine $vanta) {
            & $issue $active 'the Vanta plan is not active while power saving is recorded as disabled'
            return
        }
        foreach ($setting in @(
                @('0012ee47-9041-4b5d-9b77-535fba8b1442', 'fc7372b6-ab2d-43ee-8797-15e9841f2cca', 0),
                @('54533251-82be-4824-96c1-47b60b740d00', '3b04d4fd-1cc7-4f23-ab1c-d1337819c4bb', 0),
                @('54533251-82be-4824-96c1-47b60b740d00', '4d2b0152-7d5c-498b-88e2-34345392a2c5', 200))) {
            $path = "$root\$vanta\$($setting[0])\$($setting[1])"
            $actual = Get-VantaPowerPlanValue -Path $path -Name ACSettingIndex
            if ($null -eq $actual -or $actual -ne $setting[2]) {
                & $issue $path "ACSettingIndex differs (expected $($setting[2]), found $actual)"
            }
        }
    }
    catch { & $issue $root "power-plan verification failed: $($_.Exception.Message)" }
}

function Test-VantaToggleState {
    <#
    .SYNOPSIS
        Returns the drift of one toggle state's declarative work for one scope.
    .OUTPUTS
        One object per drifted declaration: Toggle, State, Scope, Kind, Target, Reason.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Definition,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$StateName,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Machine', 'User')]
        [string]$Scope
    )

    if (-not $Definition['States'].Contains($StateName)) {
        throw "Toggle '$($Definition['Name'])' does not define state '$StateName'."
    }
    $stateEntry = $Definition['States'][$StateName]
    $toggleName = [string]$Definition['Name']
    $drift = @()

    if (Test-VantaToggleStateHasKey -StateEntry $stateEntry -Key 'Registry') {
        $registryScope = if ($Scope -ceq 'Machine') { 'Machine' } else { 'CurrentUser' }
        foreach ($item in @(Test-VantaRegistryEntries -Entries @($stateEntry['Registry'] | ForEach-Object { [hashtable]$_ }) -Scope $registryScope)) {
            $drift += [pscustomobject]@{
                Toggle = $toggleName; State = $StateName; Scope = $Scope; Kind = 'Registry'
                Target = "$($item.Path)\$($item.Name)"; Reason = $item.Reason
            }
        }
    }

    if ($Scope -ceq 'Machine') {
        if ($toggleName -ceq 'PowerSaving' -and
            [string]$stateEntry['MachineAction'] -ceq 'Invoke-VantaPowerSavingToggle') {
            $drift += @(Test-VantaPowerPlanDrift -StateName $StateName)
        }
        if (Test-VantaToggleStateHasKey -StateEntry $stateEntry -Key 'Services') {
            foreach ($item in @(Test-VantaServiceEntries -Entries @($stateEntry['Services'] | ForEach-Object { [hashtable]$_ }))) {
                $drift += [pscustomobject]@{
                    Toggle = $toggleName; State = $StateName; Scope = $Scope; Kind = 'Service'
                    Target = $item.Service; Reason = "$($item.Reason) (expected $($item.Expected), found $($item.Actual))"
                }
            }
        }
        if (Test-VantaToggleStateHasKey -StateEntry $stateEntry -Key 'ScheduledTasks') {
            foreach ($item in @(Test-VantaScheduledTaskEntries -Entries @($stateEntry['ScheduledTasks'] | ForEach-Object { [hashtable]$_ }))) {
                $drift += [pscustomobject]@{
                    Toggle = $toggleName; State = $StateName; Scope = $Scope; Kind = 'ScheduledTask'
                    Target = $item.Task; Reason = "$($item.Reason) (expected $($item.Expected), found $($item.Actual))"
                }
            }
        }
    }

    return $drift
}

function Test-VantaToggleDrift {
    <#
    .SYNOPSIS
        Verifies every recorded toggle state against the installed definitions and
        returns the drift. Machine scope needs no particular identity to read; User
        scope reads the calling account's own hive and is meaningful only from that
        user's session.
    #>
    param(
        [ValidateSet('Machine', 'User')]
        [string[]]$Scope = @('Machine'),

        [ValidateNotNullOrEmpty()]
        [string]$StateRoot = $script:VantaToggleDefaultStateRoot,

        [string]$TogglesRoot
    )

    $drift = @()
    $records = Get-VantaToggleStateRecords -StateRoot $StateRoot
    foreach ($name in @($records.Keys | Sort-Object)) {
        $recordedValue = [int]$records[$name]
        try {
            $definition = Get-VantaToggleDefinition -Name $name -TogglesRoot $TogglesRoot
        }
        catch {
            $drift += [pscustomobject]@{
                Toggle = $name; State = [string]$recordedValue; Scope = 'Machine'; Kind = 'Definition'
                Target = $name; Reason = "recorded state has no loadable definition: $($_.Exception.Message)"
            }
            continue
        }
        $stateName = @($definition['States'].Keys | Where-Object {
                $entry = $definition['States'][$_]
                $entry.Contains('StateValue') -and [int]$entry['StateValue'] -eq $recordedValue
            }) | Select-Object -First 1
        if ($null -eq $stateName) {
            $drift += [pscustomobject]@{
                Toggle = $name; State = [string]$recordedValue; Scope = 'Machine'; Kind = 'Definition'
                Target = $name; Reason = "recorded value $recordedValue matches no installed state"
            }
            continue
        }
        foreach ($oneScope in $Scope) {
            $drift += @(Test-VantaToggleState -Definition $definition -StateName ([string]$stateName) -Scope $oneScope)
        }
    }
    return $drift
}
