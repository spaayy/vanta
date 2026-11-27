# Companion for the RunWithPriority toggle: adds the Run with priority submenu to the context
# menu of programs. Add-VantaRunWithPriorityContextMenu runs as Administrator when you run Add
# and when an update replays the recorded state.

function Add-VantaRunWithPriorityContextMenu {
    param($Toggle)

    $priorityRoot = 'HKLM:\SOFTWARE\Classes\exefile\Shell\Priority'
    $shellRoot = "$priorityRoot\ExtendedSubCommandsKey\Shell"
    # The verb lives under the machine HKCR view (HKLM\SOFTWARE\Classes). Its command is
    # stored as an expandable string so %SystemRoot% is resolved by the shell at launch
    # time, and the one template is formatted once per priority submenu entry.
    $commandTemplate = '"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "%SystemRoot%\VantaModules\Scripts\Operations\Invoke-VantaPriorityLaunch.ps1" -Priority "{0}" -TargetPath "%1"'
    $menuEntries = @(
        @{ Key = '001flyout'; Label = 'Realtime'; Priority = 'Realtime' }
        @{ Key = '002flyout'; Label = 'High'; Priority = 'High' }
        @{ Key = '003flyout'; Label = 'Above normal'; Priority = 'AboveNormal' }
        @{ Key = '004flyout'; Label = 'Normal'; Priority = 'Normal' }
        @{ Key = '005flyout'; Label = 'Below normal'; Priority = 'BelowNormal' }
        @{ Key = '006flyout'; Label = 'Low'; Priority = 'Low' }
    )

    Remove-VantaRegistryKey -Path $priorityRoot
    Set-VantaRegistryValue -Path $priorityRoot `
        -Name 'MUIVerb' -Type String -Data 'Run with priority'
    Set-VantaRegistryValue -Path $priorityRoot `
        -Name 'MultiSelectModel' -Type String -Data 'Single'

    foreach ($entry in $menuEntries) {
        $menuPath = "$shellRoot\$($entry.Key)"
        Set-VantaRegistryValue -Path $menuPath `
            -Name 'MUIVerb' -Type String -Data $entry.Label
        Set-VantaRegistryValue -Path "$menuPath\command" `
            -Name '' -Type ExpandString `
            -Data ($commandTemplate -f $entry.Priority)
    }
    [void]$Toggle
}
