# Vanta.Security: security configuration module.
Set-StrictMode -Version 3.0

# No -Force: a nested forced import unloads the caller's copy in Windows PowerShell 5.1.
foreach ($dependencyManifest in @(
    '..\Vanta.Core\Vanta.Core.psd1'
    '..\Vanta.Registry\Vanta.Registry.psd1'
    '..\Vanta.TasksProcs\Vanta.TasksProcs.psd1'
)) {
    $manifestPath = Join-Path -Path $PSScriptRoot -ChildPath $dependencyManifest
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Required Vanta.Security dependency '$manifestPath' is missing."
    }
    Import-Module -Name $manifestPath -ErrorAction Stop
}

$domainRoot = Join-Path -Path $PSScriptRoot -ChildPath 'Domain'

foreach ($domainModule in @(
    'Defender.ps1'
    'Vbs.ps1'
    'Permissions.ps1'
)) {
    $domainPath = Join-Path -Path $domainRoot -ChildPath $domainModule
    if (-not (Test-Path -LiteralPath $domainPath -PathType Leaf)) {
        throw "Required Vanta.Security domain module '$domainPath' is missing."
    }

    . $domainPath
}

Export-ModuleMember -Function @(
    'Get-VantaDefenderState', 'Set-VantaDefenderState', 'Read-VantaDefenderStateChoice',
    'Set-VantaDefenderCoreService', 'Test-VantaDefenderCoreServiceRemoved',
    'Get-VantaVbsConfiguration', 'Set-VantaVbsConfiguration', 'Test-VantaVbsChange',
    'Repair-VantaWindowsTempPermissions'
)
