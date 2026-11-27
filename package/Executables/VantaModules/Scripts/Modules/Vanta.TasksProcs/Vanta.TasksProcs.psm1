# Vanta.TasksProcs: scheduled task and process helper module.
Set-StrictMode -Version 3.0

$coreManifestPath = Join-Path $PSScriptRoot '..\Vanta.Core\Vanta.Core.psd1'
if (-not [IO.File]::Exists($coreManifestPath)) {
    throw "Required Vanta.Core manifest is missing: '$coreManifestPath'."
}
# No -Force: a nested forced import unloads the caller's copy in Windows PowerShell 5.1.
Import-Module -Name $coreManifestPath -ErrorAction Stop

$domainRoot = Join-Path -Path $PSScriptRoot -ChildPath 'Domain'

foreach ($domainModule in @(
    'ScheduledTasks.ps1'
    'Processes.ps1'
)) {
    $domainPath = Join-Path -Path $domainRoot -ChildPath $domainModule
    if (-not [IO.File]::Exists($domainPath)) {
        throw "Required Vanta.TasksProcs domain module '$domainPath' is missing."
    }

    . $domainPath
}

Export-ModuleMember -Function @(
    'Disable-VantaScheduledTask', 'Enable-VantaScheduledTask', 'Remove-VantaScheduledTask',
    'Invoke-VantaScheduledTaskEntries', 'Test-VantaScheduledTaskEntries', 'Get-VantaScheduledTaskState',
    'Stop-VantaProcess', 'Wait-VantaExplorerShellRecovery',
    'Stop-VantaProcessUnderRoot', 'Stop-VantaScheduledTaskUnderRoot'
)
