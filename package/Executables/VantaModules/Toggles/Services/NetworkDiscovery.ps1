# Companion for the NetworkDiscovery toggle: turns on SMB and then the network discovery
# services for Enable. Enable-VantaNetworkDiscoveryServices runs as Administrator when you run
# Enable, when File Sharing applies it and when an update replays the recorded state.

function Enable-VantaNetworkDiscoveryServices {
    param($Toggle)

    # Lanman Workstation (SMB) is a machine dependency. The closed service-defaults
    # reset already applies it immediately before NetworkDiscovery.
    if (-not $Toggle.ResetServices) {
        Invoke-VantaToggleMachineState -Name 'LanmanWorkstation' -State 'Enable' -StateRoot $Toggle.StateRoot
    }

    Set-VantaServiceStartup -Name 'eventlog' -StartupType 2
    foreach ($serviceName in @('fdPHost', 'FDResPub', 'lmhosts', 'netman', 'NlaSvc', 'SSDPSRV')) {
        Set-VantaServiceStartup -Name $serviceName -StartupType 3
    }
}
