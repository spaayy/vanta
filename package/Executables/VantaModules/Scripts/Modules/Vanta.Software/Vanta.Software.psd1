@{
    RootModule        = 'Vanta.Software.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '5d2b8f61-9a4c-4e07-8b3d-1c6e9f0a2d84'
    Author            = 'Vanta'
    Description       = 'Vanta software management: CBS package (CAB) install/uninstall, install-time software/browser downloads, the WinGet software picker and OneDrive removal.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Install-VantaCbsPackage'
        'Get-VantaCbsArchitecture'
        'Test-VantaCbsPackagesAvailable'
        'Uninstall-VantaCbsPackage'
        'Update-VantaCbsRepairSource'
        'Get-VantaComponentCleanupBlocker'
        'Install-VantaSoftware'
        'Show-VantaSoftwarePicker'
        'Remove-VantaOneDrive'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
