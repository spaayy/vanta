@{
    RootModule        = 'VantaBuild.psm1'
    ModuleVersion     = '2.0.0'
    GUID              = 'e1b1a9c2-42f3-4c1d-9a06-7c2f8b7f7a10'
    Author            = 'Vanta'
    Description       = 'Build tooling for the Vanta package (.atlaspkg packaging, manifest checks and test-build staging).'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Resolve-SevenZip'
        'Invoke-SevenZip'
        'Get-VantaPackagePassword'
        'Get-VantaPackageVersion'
        'Test-VantaManifest'
        'ConvertTo-VantaManifestJson'
        'Get-AvailableArchiveName'
        'Get-VantaPackageFilePath'
        'Compare-VantaPackageFilePath'
        'New-StagedVantaManifest'
        'Set-OemVersionStamp'
        'New-VantaPackage'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
