# Vanta.Tweaks: declarative tweak engine module.
Set-StrictMode -Version 3.0

# No -Force: a nested forced import unloads the caller's copy in Windows PowerShell 5.1.
foreach ($dependencyManifest in @(
    '..\Vanta.Core\Vanta.Core.psd1'
    '..\Vanta.Registry\Vanta.Registry.psd1'
    '..\Vanta.Services\Vanta.Services.psd1'
    '..\Vanta.TasksProcs\Vanta.TasksProcs.psd1'
    '..\Vanta.Toggles\Vanta.Toggles.psd1'
)) {
    $manifestPath = Join-Path -Path $PSScriptRoot -ChildPath $dependencyManifest
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Required Vanta.Tweaks dependency '$manifestPath' is missing."
    }
    Import-Module -Name $manifestPath -ErrorAction Stop
}

$script:VantaTweakPostUserRegistryRefreshOperations = @(
    'ShellRefresh'
    'ExplorerRefresh'
    'SearchShellRefresh'
    'StartMenuRefresh'
    'ExplorerAndSettingsRefresh'
)

$domainRoot = Join-Path -Path $PSScriptRoot -ChildPath 'Domain'

foreach ($domainModule in @(
    'Manifest.ps1'
    'Applicability.ps1'
    'Invoke.ps1'
    'Schema.ps1'
    'Verify.ps1'
)) {
    $domainPath = Join-Path -Path $domainRoot -ChildPath $domainModule
    if (-not (Test-Path -LiteralPath $domainPath -PathType Leaf)) {
        throw "Required Vanta.Tweaks domain module '$domainPath' is missing."
    }

    . $domainPath
}

Export-ModuleMember -Function @(
    'Get-VantaTweakManifest', 'Test-VantaTweakManifest', 'Test-VantaTweakApplicable',
    'Get-VantaTweakCategoryPostUserRegistryRefresh',
    'Invoke-VantaTweak', 'Invoke-VantaTweakCategory',
    'Test-VantaTweakSchema',
    'Test-VantaTweak', 'Test-VantaTweakCategory'
)
