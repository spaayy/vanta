@{
    RootModule        = 'Vanta.TasksProcs.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '1c9e7b34-2d5f-4a86-b0e1-6f4d8c2a9b73'
    Author            = 'Vanta'
    Description       = 'Vanta scheduled-task and process helpers with session-aware stopping and Explorer recovery.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Disable-VantaScheduledTask'
        'Enable-VantaScheduledTask'
        'Remove-VantaScheduledTask'
        'Invoke-VantaScheduledTaskEntries'
        'Test-VantaScheduledTaskEntries'
        'Get-VantaScheduledTaskState'
        'Stop-VantaProcess'
        'Wait-VantaExplorerShellRecovery'
        'Stop-VantaProcessUnderRoot'
        'Stop-VantaScheduledTaskUnderRoot'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
