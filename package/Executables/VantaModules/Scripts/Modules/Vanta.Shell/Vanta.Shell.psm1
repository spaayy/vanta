# Vanta.Shell: shell configuration module.
Set-StrictMode -Version 3.0

# No -Force: a nested forced import unloads the caller's copy in Windows PowerShell 5.1.
foreach ($dependencyManifest in @(
    '..\Vanta.Core\Vanta.Core.psd1'
    '..\Vanta.Registry\Vanta.Registry.psd1'
    '..\Vanta.Shortcuts\Vanta.Shortcuts.psd1'
)) {
    $manifestPath = Join-Path -Path $PSScriptRoot -ChildPath $dependencyManifest
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Required Vanta.Shell dependency '$manifestPath' is missing."
    }
    Import-Module -Name $manifestPath -ErrorAction Stop
}

$domainRoot = Join-Path -Path $PSScriptRoot -ChildPath 'Domain'

foreach ($domainModule in @(
    'SettingsPages.ps1'
    'FileAssociations.ps1'
    'SendTo.ps1'
    'ContextMenu.ps1'
    'Start.ps1'
    'Taskbar.ps1'
    'Home.ps1'
)) {
    $domainPath = Join-Path -Path $domainRoot -ChildPath $domainModule
    if (-not (Test-Path -LiteralPath $domainPath -PathType Leaf)) {
        throw "Required Vanta.Shell domain module '$domainPath' is missing."
    }

    . $domainPath
}

Export-ModuleMember -Function @(
    'Set-VantaSettingsPageVisibility',
    'Set-VantaFileAssociations',
    'Set-VantaSendToContextMenu',
    'ConvertTo-VantaShellWindowsArgument', 'Get-VantaTakeOwnershipArgumentPlan', 'Assert-VantaTakeOwnershipTree',
    'Set-VantaStartLayout',
    'Set-VantaTaskbarPins',
    'Add-VantaMusicVideosToHome'
)
