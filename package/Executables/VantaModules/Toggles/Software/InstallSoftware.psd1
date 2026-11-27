@{
    Name          = 'InstallSoftware'
    Description   = 'Opens the Vanta software picker.'
    Elevation     = 'None'
    NoStateRecord = $true
    Script        = 'InstallSoftware.ps1'
    States        = @(
        @{
            Name     = 'Run'
            Launcher = '1. Software\Install Software.cmd'
            Reboot   = 'None'
            Action   = 'Invoke-VantaSoftwarePicker'
        }
    )
}
