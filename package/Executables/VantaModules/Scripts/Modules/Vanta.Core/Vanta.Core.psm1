# Vanta.Core: core framework module.
$domainRoot = Join-Path -Path $PSScriptRoot -ChildPath 'Domain'

foreach ($domainModule in @(
    'Data.ps1'
    'Context.ps1'
    'Logging.ps1'
    'Native.ps1'
    'TrustedInstallerProcess.ps1'
    'Privilege.ps1'
    'Process.ps1'
    'Ui.ps1'
    'RunAsUser.ps1'
)) {
    $domainPath = Join-Path -Path $domainRoot -ChildPath $domainModule
    if (-not (Test-Path -LiteralPath $domainPath -PathType Leaf)) {
        throw "Required Vanta.Core domain module '$domainPath' is missing."
    }

    . $domainPath
}

Export-ModuleMember -Function @(
    'Import-VantaDataFile', 'Import-VantaModule',
    'Initialize-VantaNativeType',
    'Get-VantaContext', 'Test-VantaOption',
    'Write-VantaLog', 'Start-VantaPhase', 'Stop-VantaPhase',
    'Set-VantaLogConsoleStyle', 'Get-VantaLogConsoleStyle', 'Get-VantaInstallLogPath', 'Invoke-VantaInstallLogRetention',
    'Test-VantaAdmin', 'Test-VantaSystem', 'Test-VantaTrustedInstaller', 'Assert-VantaPrivilege', 'Invoke-VantaTrustedInstaller', 'Invoke-VantaAsUser', 'Get-VantaUserSessionHelperStage', 'Get-VantaUserProcessCommandLine',
    'ConvertTo-VantaWindowsArgumentString', 'Invoke-VantaHiddenProcess',
    'Write-VantaTitle', 'Write-VantaBlankLine', 'Write-VantaNote', 'Write-VantaStep', 'Write-VantaWarning',
    'Write-VantaSuccess', 'Write-VantaFailure', 'Write-VantaPartial', 'Write-VantaNextStep',
    'Write-VantaManualStep', 'Write-VantaRestartNotice', 'Write-VantaNotApplied',
    'Write-VantaCompletion', 'Reset-VantaRunOutcome', 'Get-VantaRunOutcome', 'Set-VantaRunOutcome',
    'Read-VantaYesNo', 'Read-VantaChoice', 'Wait-VantaContinue', 'Wait-VantaExit',
    'Read-MessageBox'
)
