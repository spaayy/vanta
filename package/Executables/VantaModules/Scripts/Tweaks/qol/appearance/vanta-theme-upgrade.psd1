@{
    Name        = 'Refresh Theme On Upgrade'
    Description  = 'Keeps the Vanta theme as the default for new accounts when Vanta updates. The ThemeFile policy applies it at the next sign-in, without needing the user''s session during the install.'
    OnUpgrade   = 'Only'
    Registry    = @(
        # Set the Vanta theme as the default for new accounts (default-user hive, loaded
        # during install).
        @{ Path = 'HKU\Vanta_DefaultUser\Software\Policies\Microsoft\Windows\Personalization'; Name = 'ThemeFile'; Type = 'ExpandString'; Data = '%windir%\Resources\Themes\vanta-dark.theme' }
    )
}
