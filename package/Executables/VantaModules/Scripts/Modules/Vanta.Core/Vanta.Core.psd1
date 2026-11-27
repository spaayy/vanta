@{
    RootModule        = 'Vanta.Core.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '0b7c9f3e-8a41-4f7e-b6a2-3d5c1e9f2a84'
    Author            = 'Vanta'
    Description       = 'Core Vanta framework: install context, option flags, logging, privilege checks and shared UI helpers.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        # Context
        'Import-VantaDataFile'
        'Import-VantaModule'
        'Get-VantaContext'
        'Test-VantaOption'
        # Native
        'Initialize-VantaNativeType'
        # Logging
        'Write-VantaLog'
        'Start-VantaPhase'
        'Stop-VantaPhase'
        'Set-VantaLogConsoleStyle'
        'Get-VantaLogConsoleStyle'
        'Get-VantaInstallLogPath'
        'Invoke-VantaInstallLogRetention'
        # Privilege
        'Test-VantaAdmin'
        'Test-VantaSystem'
        'Test-VantaTrustedInstaller'
        'Assert-VantaPrivilege'
        'Invoke-VantaTrustedInstaller'
        'Invoke-VantaAsUser'
        'Get-VantaUserSessionHelperStage'
        'Get-VantaUserProcessCommandLine'
        # Process
        'ConvertTo-VantaWindowsArgumentString'
        'Invoke-VantaHiddenProcess'
        # Console presentation (docs/console-presentation.md)
        'Write-VantaTitle'
        'Write-VantaBlankLine'
        'Write-VantaNote'
        'Write-VantaStep'
        'Write-VantaWarning'
        'Write-VantaSuccess'
        'Write-VantaFailure'
        'Write-VantaPartial'
        'Write-VantaNextStep'
        'Write-VantaManualStep'
        'Write-VantaRestartNotice'
        'Write-VantaNotApplied'
        'Write-VantaCompletion'
        'Reset-VantaRunOutcome'
        'Get-VantaRunOutcome'
        'Set-VantaRunOutcome'
        'Read-VantaYesNo'
        'Read-VantaChoice'
        'Wait-VantaContinue'
        'Wait-VantaExit'
        'Read-MessageBox'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
