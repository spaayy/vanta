# Vanta.Network: network adapter defaults and File Sharing configuration module.
Set-StrictMode -Version 3.0

# No -Force: a nested forced import unloads the caller's copy in Windows PowerShell 5.1.
foreach ($dependencyManifest in @(
    '..\Vanta.Core\Vanta.Core.psd1'
    '..\Vanta.Registry\Vanta.Registry.psd1'
    '..\Vanta.Services\Vanta.Services.psd1'
    '..\Vanta.Toggles\Vanta.Toggles.psd1'
)) {
    $manifestPath = Join-Path -Path $PSScriptRoot -ChildPath $dependencyManifest
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Required Vanta.Network dependency '$manifestPath' is missing."
    }
    Import-Module -Name $manifestPath -ErrorAction Stop
}

$domainRoot = Join-Path -Path $PSScriptRoot -ChildPath 'Domain'

foreach ($domainModule in @(
    'Defaults.ps1'
    'FileSharing.ps1'
)) {
    $domainPath = Join-Path -Path $domainRoot -ChildPath $domainModule
    if (-not (Test-Path -LiteralPath $domainPath -PathType Leaf)) {
        throw "Required Vanta.Network domain module '$domainPath' is missing."
    }

    . $domainPath
}

Export-ModuleMember -Function @(
    'Set-VantaNetworkDefaults', 'Enable-VantaFileSharing', 'Disable-VantaFileSharing'
)
