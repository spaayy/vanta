# Vanta.Themes domain: the recent-themes list. Runs as the signed-in user, from the
# per-user setup at first sign-in.

function Set-VantaThemeMru {
    <#
    .SYNOPSIS
        Sets the user's recently used themes to the Vanta theme and the Windows dark
        and light themes.
    .DESCRIPTION
        Writes ThemeMRU, the semicolon-separated list of theme files that Settings
        offers under Personalization > Themes.
    #>
    Stop-ThemeProcesses
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes" -Name "ThemeMRU" -Value "$((@(
        "vanta-dark.theme",
        "dark.theme",
        "aero.theme"
    ) | ForEach-Object { "$env:SystemRoot\resources\Themes\$_" }) -join ';');" -Type String -Force
}
