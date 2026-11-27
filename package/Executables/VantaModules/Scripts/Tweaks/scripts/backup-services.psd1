@{
    OnUpgrade   = 'Skip'
    OnRebase    = 'Run'
    Name        = 'Backup Vanta Services and Drivers'
    Description  = 'Backs up the startup settings of the Vanta services and drivers after the other tweaks, so their defaults can be restored later.'
    Script       = 'backup-services.ps1'
}
