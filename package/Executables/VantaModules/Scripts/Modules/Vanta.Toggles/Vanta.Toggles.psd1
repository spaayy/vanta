@{
    RootModule        = 'Vanta.Toggles.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '5e8d2b7a-1c94-4a6e-8f3b-9d0c4e7a2b51'
    Author            = 'Vanta'
    Description       = 'Vanta toggle engine: loads data-only toggle definitions, runs their machine and user work in the right context, records user setting state, and replays recorded toggles on upgrades and first sign-in.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        # Definitions
        'Get-VantaToggleDefinition'
        'Test-VantaToggleDefinition'
        'Get-VantaToggleStateWork'
        # Engine
        'Invoke-VantaToggle'
        # Machine work of one state, invoked from other privileged callers
        'Invoke-VantaToggleMachineState'
        # State registry (HKLM\SOFTWARE\Vanta\Services, kept for compatibility)
        'Get-VantaToggleState'
        'Get-VantaToggleStateRecords'
        'Set-VantaToggleState'
        # Checked native command invocation and BCD element removal for companion functions
        'Invoke-VantaToggleNativeCommand'
        'Remove-VantaToggleBcdValue'
        # State-store initialisation and replay
        'Initialize-VantaToggleStateStore'
        'Invoke-VantaToggleReapply'
        'Invoke-VantaToggleUserReapply'
        # Verification of recorded states against the machine
        'Test-VantaToggleState'
        'Test-VantaToggleDrift'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
