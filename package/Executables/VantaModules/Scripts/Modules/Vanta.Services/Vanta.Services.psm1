# Vanta.Services: service and driver configuration module.
Set-StrictMode -Version 3.0

$coreManifest = Join-Path -Path $PSScriptRoot -ChildPath '..\Vanta.Core\Vanta.Core.psd1'
if (-not (Test-Path -LiteralPath $coreManifest -PathType Leaf)) {
    throw "Required Vanta.Core manifest '$coreManifest' is missing."
}
# No -Force: a nested forced import unloads the caller's copy in Windows PowerShell 5.1.
Import-Module -Name $coreManifest -ErrorAction Stop

$domainRoot = Join-Path -Path $PSScriptRoot -ChildPath 'Domain'

foreach ($domainModule in @(
    'Startup.ps1'
    'Backup.ps1'
    'Entries.ps1'
)) {
    $domainPath = Join-Path -Path $domainRoot -ChildPath $domainModule
    if (-not (Test-Path -LiteralPath $domainPath -PathType Leaf)) {
        throw "Required Vanta.Services domain module '$domainPath' is missing."
    }

    . $domainPath
}

Export-ModuleMember -Function @(
    'Set-VantaServiceStartup', 'Stop-VantaService', 'Invoke-VantaServiceEntries', 'Test-VantaServiceEntries',
    'Restore-VantaServicesBackup', 'Export-VantaServicesBackup'
)
