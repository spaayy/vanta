@{
    Name          = 'ConfigVBS'
    Description   = 'Shows the current Virtualisation-Based Security configuration.'
    Elevation     = 'None'
    NoStateRecord = $true
    Script        = 'ConfigVBS.ps1'
    States        = @(
        @{
            Name            = 'Run'
            Launcher        = '7. Security\Core Isolation (VBS)\Current Configuration.cmd'
            Reboot          = 'None'
            Action          = 'Show-VantaVbsConfiguration'
        }
    )
}
