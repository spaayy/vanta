# Vanta.Toggles: user-facing toggle engine.
Set-StrictMode -Version 3.0

# No -Force: a nested forced import unloads the caller's copy in Windows PowerShell 5.1.
foreach ($dependencyManifest in @(
    '..\Vanta.Core\Vanta.Core.psd1'
    '..\Vanta.Registry\Vanta.Registry.psd1'
    '..\Vanta.Services\Vanta.Services.psd1'
    '..\Vanta.TasksProcs\Vanta.TasksProcs.psd1'
    '..\Vanta.State\Vanta.State.psd1'
)) {
    $manifestPath = Join-Path -Path $PSScriptRoot -ChildPath $dependencyManifest
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Required Vanta.Toggles dependency '$manifestPath' is missing."
    }
    Import-Module -Name $manifestPath -ErrorAction Stop
}

$domainRoot = Join-Path -Path $PSScriptRoot -ChildPath 'Domain'

foreach ($domainModule in @(
    'State.ps1'
    'LegacyState.ps1'
    'Interaction.ps1'
    'Native.ps1'
    'Definition.ps1'
    'Engine.ps1'
    'Reapply.ps1'
    'Verify.ps1'
)) {
    $domainPath = Join-Path -Path $domainRoot -ChildPath $domainModule
    if (-not (Test-Path -LiteralPath $domainPath -PathType Leaf)) {
        throw "Required Vanta.Toggles domain module '$domainPath' is missing."
    }

    . $domainPath
}

Export-ModuleMember -Function @(
    'Get-VantaToggleDefinition', 'Test-VantaToggleDefinition', 'Get-VantaToggleStateWork',
    'Invoke-VantaToggle', 'Invoke-VantaToggleMachineState',
    'Get-VantaToggleState', 'Get-VantaToggleStateRecords', 'Set-VantaToggleState',
    'Invoke-VantaToggleNativeCommand', 'Remove-VantaToggleBcdValue',
    'Initialize-VantaToggleStateStore',
    'Invoke-VantaToggleReapply', 'Invoke-VantaToggleUserReapply',
    'Test-VantaToggleState', 'Test-VantaToggleDrift'
)
