@{
    Name        = 'DefaultVantaNetwork'
    # Both states use Set-VantaNetworkDefaults in Vanta.Network.
    Description = 'Resets the network adapter settings: Enable applies the Vanta defaults and Disable restores the Windows defaults.'
    Elevation   = 'Admin'
    NoStateRecord = $true
    Script      = 'DefaultVantaNetwork.ps1'
    States      = @(
        @{
            Name            = 'Enable'
            StateValue      = 1
            Launcher        = '9. Troubleshooting\Network\Reset Network to Vanta Default.cmd'
            Reboot          = 'Recommend'
            MachineAction   = 'Set-VantaNetworkDefaultState'
        }
        @{
            Name            = 'Disable'
            StateValue      = 0
            Launcher        = '9. Troubleshooting\Network\Reset Network to Windows Default.cmd'
            Reboot          = 'Recommend'
            MachineAction   = 'Set-VantaNetworkDefaultState'
        }
    )
}
