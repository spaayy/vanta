# Companion for the InstallSoftware toggle: opens the Vanta software picker.
# Invoke-VantaSoftwarePicker runs in the launcher's own process, as you, when you run the
# launcher; nothing is recorded.

function Invoke-VantaSoftwarePicker {
    param($Toggle)

    [void]$Toggle
    Import-VantaModule -Name Vanta.Software
    if (-not (Show-VantaSoftwarePicker)) {
        throw 'WinGet is not available, so no software was installed. Install App Installer from the Microsoft Store, then try again.'
    }
}
