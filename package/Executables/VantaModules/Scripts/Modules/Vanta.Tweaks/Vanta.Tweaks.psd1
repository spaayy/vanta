@{
    RootModule        = 'Vanta.Tweaks.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '2b60d6d6-e806-4cf0-95ad-3f133cef973e'
    Author            = 'Vanta'
    Description       = 'Vanta tweak engine: loads declarative tweak .psd1 data files, evaluates applicability gates and applies scoped registry, machine, exact-user, and post-user-registry refresh actions.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Get-VantaTweakManifest'
        'Test-VantaTweakManifest'
        'Test-VantaTweakApplicable'
        'Get-VantaTweakCategoryPostUserRegistryRefresh'
        'Invoke-VantaTweak'
        'Invoke-VantaTweakCategory'
        'Test-VantaTweakSchema'
        'Test-VantaTweak'
        'Test-VantaTweakCategory'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
