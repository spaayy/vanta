@{
    RootModule        = 'Vanta.Security.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '3e7a9c14-5b2d-4f86-a1c7-8d0e6b4f2a93'
    Author            = 'Vanta'
    Description       = 'Vanta security configuration: Windows Defender package state and its core service, documented Virtualization-Based Security and memory-integrity configuration, and the Windows TEMP permission repair.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Get-VantaDefenderState'
        'Set-VantaDefenderState'
        'Read-VantaDefenderStateChoice'
        'Set-VantaDefenderCoreService'
        'Test-VantaDefenderCoreServiceRemoved'
        'Get-VantaVbsConfiguration'
        'Set-VantaVbsConfiguration'
        'Test-VantaVbsChange'
        'Repair-VantaWindowsTempPermissions'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
