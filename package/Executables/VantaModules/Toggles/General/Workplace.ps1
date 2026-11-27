# Companion for the Workplace toggle: hides or shows the Access work or school page in
# Settings. Its functions run as Administrator when you run a launcher and when an update
# replays the recorded state.

function Hide-VantaWorkplaceSettingsPage {
    param($Toggle)

    Import-VantaModule -Name Vanta.Shell
    Set-VantaSettingsPageVisibility -Operation hide -Page workplace
}

function Show-VantaWorkplaceSettingsPage {
    param($Toggle)

    Import-VantaModule -Name Vanta.Shell
    Set-VantaSettingsPageVisibility -Operation unhide -Page workplace

    if (-not $Toggle.Silent) {
        Write-VantaStep -Text 'Opening Settings > Accounts > Access work or school...'
        Start-Process 'ms-settings:workplace'
    }
}
