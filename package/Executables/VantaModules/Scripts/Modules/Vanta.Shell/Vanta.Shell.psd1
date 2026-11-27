@{
    RootModule        = 'Vanta.Shell.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'c4e7a2d9-5b16-4f83-a9d0-6e1c8b3f7a52'
    Author            = 'Vanta'
    Description       = 'Vanta shell configuration: Settings page visibility, current-user file associations, Send To context-menu items, shell context-menu handler helpers, Start layout, taskbar pins and File Explorer Home pins.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Set-VantaSettingsPageVisibility'
        'Set-VantaFileAssociations'
        'Set-VantaSendToContextMenu'
        'ConvertTo-VantaShellWindowsArgument'
        'Get-VantaTakeOwnershipArgumentPlan'
        'Assert-VantaTakeOwnershipTree'
        'Set-VantaStartLayout'
        'Set-VantaTaskbarPins'
        'Add-VantaMusicVideosToHome'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
