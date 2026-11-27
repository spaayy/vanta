@{
    RootModule        = 'Vanta.Registry.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '543dae25-b8af-44b3-8a92-a151695f97f0'
    Author            = 'Vanta'
    Description       = 'Vanta registry engine: token-bound HKCU operations, install-bound protected user policies, fixed default-user targeting and declarative registry entry application.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        # Path resolution and explicit identity binding
        'Resolve-VantaRegistryPath'
        'Initialize-VantaRegistryIdentityContext'
        # Values and keys
        'Set-VantaRegistryValue'
        'Set-VantaMachineDwordPolicy'
        'Remove-VantaRegistryValue'
        'New-VantaRegistryKey'
        'Remove-VantaRegistryKey'
        # .reg import and declarative entries
        'Import-VantaRegFile'
        'Invoke-VantaRegistryEntries'
        'Test-VantaRegistryEntries'
        'Get-VantaRegistryValueState'
        # Entry gates shared with the tweak engine and its schema validation
        'Test-VantaArchMatch'
        'Get-VantaRegistryEntryTargetScope'
        # Windows PowerShell execution policy
        'Set-VantaWindowsPowerShellExecutionPolicy'
        # Known-folder helper
        'Get-UserPath'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
