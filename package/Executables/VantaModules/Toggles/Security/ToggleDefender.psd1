@{
    Name          = 'ToggleDefender'
    # The menu runs in the administrator window, and its choice reaches the silent TrustedInstaller
    # broker as a fixed internal state.
    Description   = 'Removes or restores Windows Defender through the Vanta NoDefender package.'
    Elevation     = 'TrustedInstaller'
    NoStateRecord = $true
    Script        = 'ToggleDefender.ps1'
    States        = @(
        @{
            Name             = 'Run'
            Launcher         = '7. Security\Defender\Toggle Defender.cmd'
            Reboot           = 'Prompt'
            MachineAction    = 'Invoke-VantaDefenderToggle'
            InteractiveState = 'Select-VantaDefenderToggleState'
        }
        @{
            Name          = 'Disable'
            Internal      = $true
            NoStateRecord = $true
            MachineAction = 'Disable-VantaDefenderToggle'
        }
        @{
            Name          = 'Enable'
            Internal      = $true
            NoStateRecord = $true
            MachineAction = 'Enable-VantaDefenderToggle'
        }
    )
}
