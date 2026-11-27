@{
    RootModule        = 'Vanta.InstallState.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'f2e6d327-ce7f-4692-a1f6-64bf95d25088'
    Author            = 'Vanta'
    Description       = 'Compact persistent state for an Vanta installation run.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Get-VantaInstallStatePath'
        'Get-VantaInstallState'
        'Get-VantaInstallWorkRoot'
        'Start-VantaInstallState'
        'Set-VantaInstallOptions'
        'Set-VantaInstallUser'
        'Commit-VantaInstallState'
        'Invoke-VantaInstallStep'
        'Complete-VantaInstallState'
        'Get-VantaPackageManifest'
        'Get-VantaPackageVersion'
        'Get-VantaPackageChoice'
        'Get-VantaPackageSupportedBuild'
        'Get-VantaInstalledVersion'
        'Resolve-VantaInstallMode'
        'Resolve-VantaInstallChoices'
        'Compare-VantaInstallOption'
        'Resolve-VantaKeptOption'
        'Get-VantaRecordedOption'
        'Repair-VantaToolboxRecord'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
