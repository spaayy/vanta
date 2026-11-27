# Vanta.Registry: registry engine module.
Set-StrictMode -Version 3.0

$coreManifest = Join-Path -Path $PSScriptRoot -ChildPath '..\Vanta.Core\Vanta.Core.psd1'
if (-not (Test-Path -LiteralPath $coreManifest -PathType Leaf)) {
    throw "Required Vanta.Core manifest '$coreManifest' is missing."
}
# No -Force: a nested forced import unloads the caller's copy in Windows PowerShell 5.1.
Import-Module -Name $coreManifest -ErrorAction Stop

$domainRoot = Join-Path -Path $PSScriptRoot -ChildPath 'Domain'

foreach ($domainModule in @(
    'Paths.ps1'
    'Values.ps1'
    'Keys.ps1'
    'RegFile.ps1'
    'Entries.ps1'
    'UserPaths.ps1'
    'ExecutionPolicy.ps1'
    'Verify.ps1'
)) {
    $domainPath = Join-Path -Path $domainRoot -ChildPath $domainModule
    if (-not (Test-Path -LiteralPath $domainPath -PathType Leaf)) {
        throw "Required Vanta.Registry domain module '$domainPath' is missing."
    }

    . $domainPath
}

Export-ModuleMember -Function @(
    'Resolve-VantaRegistryPath', 'Initialize-VantaRegistryIdentityContext',
    'Set-VantaRegistryValue', 'Set-VantaMachineDwordPolicy', 'Remove-VantaRegistryValue', 'New-VantaRegistryKey', 'Remove-VantaRegistryKey',
    'Import-VantaRegFile', 'Invoke-VantaRegistryEntries', 'Test-VantaRegistryEntries', 'Get-VantaRegistryValueState',
    'Test-VantaArchMatch', 'Get-VantaRegistryEntryTargetScope',
    'Get-UserPath',
    'Set-VantaWindowsPowerShellExecutionPolicy'
)
