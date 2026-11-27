@{
    RootModule        = 'Vanta.Services.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '7a1f4c92-6e3b-4d18-9c5a-2f8e0b7d4a61'
    Author            = 'Vanta'
    Description       = 'Vanta service and driver configuration: checked startup changes, service stopping, strict default-services backup validation, and typed restoration.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Set-VantaServiceStartup'
        'Stop-VantaService'
        'Invoke-VantaServiceEntries'
        'Test-VantaServiceEntries'
        'Restore-VantaServicesBackup'
        'Export-VantaServicesBackup'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
