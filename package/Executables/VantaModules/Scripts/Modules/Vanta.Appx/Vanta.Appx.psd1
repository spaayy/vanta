@{
    RootModule        = 'Vanta.Appx.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '9b4e1d73-3c8a-42f5-a6d0-7e2b5c9f1a36'
    Author            = 'Vanta'
    Description       = 'Vanta AppX support: installed and provisioned package removal, snapshot/deprovisioning, cache clearing, Phone Link removal and Xbox Game Bar installation.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Save-VantaAppxSnapshot'
        'Set-VantaAppxDeprovisioned'
        'Get-VantaAppxRemovalDefinition'
        'Invoke-VantaAppxRemovalPlan'
        'Get-VantaAppxProvisionedFamily'
        'Clear-VantaAppxCache'
        'Invoke-VantaUserAppxCacheCleanup'
        'Remove-VantaPhoneLinkAppx'
        'Install-VantaGameBar'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
