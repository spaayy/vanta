@{
    Name          = 'VantaHealth'
    Description   = 'Reports what Vanta installed and which recorded toggle states or install tweaks have changed since. It changes nothing.'
    Elevation     = 'Admin'
    NoStateRecord = $true
    Script        = 'VantaHealth.ps1'
    States        = @(
        @{
            Name          = 'Run'
            Launcher      = '9. Troubleshooting\Check Vanta Health.cmd'
            Reboot        = 'None'
            MachineAction = 'Show-VantaHealthReport'
        }
    )
}
