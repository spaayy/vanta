@{
    Name = 'Register user upgrade migration'
    Description = 'Updates existing accounts to the installed version at their next sign-in, keeping their desktop layout.'
    OnUpgrade = 'Only'
    Registry = @(
        @{ Path = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; Name = 'VantaUserUpgrade'; Type = 'ExpandString'; Data = '"%windir%\System32\wscript.exe" "%windir%\VantaModules\Scripts\Entry\Invoke-VantaUserUpgradeHidden.vbs"' }
    )
}
