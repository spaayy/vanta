@{
    RootModule        = 'Vanta.State.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '8c1f6d2e-4b7a-4e39-9d5c-1a2f3b4c5d6e'
    Author            = 'Vanta'
    Description       = 'The Vanta machine state document: installed version, install history, what the PC has for each install choice and the recorded VantaDesktop toggle states.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Get-VantaStatePath'
        'Get-VantaState'
        'Update-VantaState'
        'Set-VantaStateInstall'
        'Set-VantaStateToggle'
        'Set-VantaStateChoice'
        'Sync-VantaStateToggles'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
