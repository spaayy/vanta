# Companion for the SuperFetch toggle: turns SysMain and ReadyBoost off or on.
# Set-VantaSuperFetchMachineState runs as Administrator when you run a launcher and when an
# update replays the recorded state.

function Set-VantaSuperFetchMachineState {
    param($Toggle)

    $enable = $Toggle.State -ceq 'Enable'

    # ReadyBoost is a volume lower filter; add or remove only its own entry.
    $classKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{71a27cdd-812a-11d0-bec7-08002be2092f}'
    $properties = Get-ItemProperty -LiteralPath $classKey -ErrorAction Stop
    [string[]]$lowerFilters = if ($properties.PSObject.Properties.Name -contains 'LowerFilters') {
        @($properties.LowerFilters)
    }
    else {
        $null
    }

    if ($enable) {
        if ($null -eq $lowerFilters) {
            Set-VantaRegistryValue -Path $classKey -Name 'LowerFilters' `
                -Type MultiString -Data ([string[]]@('rdyboost'))
        }
        elseif ($lowerFilters -notcontains 'rdyboost') {
            Set-VantaRegistryValue -Path $classKey -Name 'LowerFilters' `
                -Type MultiString -Data ([string[]](@($lowerFilters) + 'rdyboost'))
        }
    }
    elseif ($null -ne $lowerFilters) {
        $lowerFilters = @($lowerFilters | Where-Object { $_ -and $_ -ne 'rdyboost' })
        if ($lowerFilters.Count -eq 0) {
            Remove-VantaRegistryValue -Path $classKey -Name 'LowerFilters'
        }
        else {
            Set-VantaRegistryValue -Path $classKey -Name 'LowerFilters' `
                -Type MultiString -Data ([string[]]$lowerFilters)
        }
    }

    $readyBoostStart = if ($enable) { 0 } else { 4 }
    Set-VantaServiceStartup -Name 'rdyboost' -StartupType $readyBoostStart

    $readyBoostTab = 'HKLM:\SOFTWARE\Classes\Drive\shellex\PropertySheetHandlers\{55B3A0BD-4D28-42fe-8CFB-FA3EDFF969B8}'
    if ($enable) {
        New-VantaRegistryKey -Path $readyBoostTab
    }
    else {
        Remove-VantaRegistryKey -Path $readyBoostTab
    }

    $sysMainStart = if ($enable) { 2 } else { 4 }
    Set-VantaServiceStartup -Name 'SysMain' -StartupType $sysMainStart
}
