@{
    RootModule        = 'Vanta.Download.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '5d2f8a1c-7b3e-4c9a-9f61-2e8b4d0c7a15'
    Author            = 'Vanta'
    Description       = 'Size-limited HTTPS downloads, protected staging, contained native execution, GitHub release resolution and trusted WinGet resolution.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'New-VantaProtectedStagingDirectory'
        'Test-VantaProtectedStagingAcl'
        'Invoke-VantaLimitedHttpGet'
        'Invoke-VantaPinnedDownload'
        'Test-VantaProtectedExecutionAcl'
        'Resolve-VantaProtectedExecutionPath'
        'Invoke-VantaContainedProcess'
        'Test-VantaContainedProcessContainmentUnconfirmed'
        'Invoke-VantaGitHubApiJson'
        'Get-VantaLatestGitHubReleaseAsset'
        'Get-VantaTrustedWingetPath'
        'Assert-VantaTrustedWingetSource'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
