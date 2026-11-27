# Vanta.Software: software management module.
Set-StrictMode -Version 3.0

# No -Force: a nested forced import unloads the caller's copy in Windows PowerShell 5.1.
foreach ($dependencyManifest in @(
    '..\Vanta.Core\Vanta.Core.psd1'
    '..\Vanta.Shortcuts\Vanta.Shortcuts.psd1'
    '..\Vanta.Download\Vanta.Download.psd1'
)) {
    $manifestPath = Join-Path -Path $PSScriptRoot -ChildPath $dependencyManifest
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Required Vanta.Software dependency '$manifestPath' is missing."
    }
    Import-Module -Name $manifestPath -ErrorAction Stop
}

$domainRoot = Join-Path -Path $PSScriptRoot -ChildPath 'Domain'

foreach ($domainModule in @(
    'CbsPackages.ps1'
    'Installers.ps1'
    'NanaZipStore.ps1'
    'SoftwarePicker.ps1'
    'OneDrive.ps1'
)) {
    $domainPath = Join-Path -Path $domainRoot -ChildPath $domainModule
    if (-not (Test-Path -LiteralPath $domainPath -PathType Leaf)) {
        throw "Required Vanta.Software domain module '$domainPath' is missing."
    }

    . $domainPath
}

Export-ModuleMember -Function @(
    'Install-VantaCbsPackage', 'Uninstall-VantaCbsPackage', 'Get-VantaCbsArchitecture', 'Test-VantaCbsPackagesAvailable', 'Update-VantaCbsRepairSource', 'Get-VantaComponentCleanupBlocker',
    'Install-VantaSoftware', 'Show-VantaSoftwarePicker', 'Remove-VantaOneDrive'
)
