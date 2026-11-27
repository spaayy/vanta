# Companion for the RecentItems toggle: hides or shows the General privacy page in Settings
# and explains the change. Set-VantaRecentItemsSettingsPage runs as Administrator when you run
# a launcher, when the install applies Disable and when an update replays the recorded state.
# Show-VantaRecentItemsMessage runs in your own unelevated process afterwards, and is replayed
# for each new account at first sign-in.

function Set-VantaRecentItemsSettingsPage {
    param($Toggle)

    Import-VantaModule -Name Vanta.Shell
    switch -CaseSensitive ([string]$Toggle.State) {
        'Disable' {
            Set-VantaSettingsPageVisibility -Operation hide -Page privacy-general -NoProcessCleanup
        }
        'Enable' {
            Set-VantaSettingsPageVisibility -Operation unhide -Page privacy-general -NoProcessCleanup
        }
        default { throw "RecentItems: unsupported state '$($Toggle.State)'." }
    }
}

function Show-VantaRecentItemsMessage {
    param($Toggle)

    if ($Toggle.Silent) {
        return
    }

    switch -CaseSensitive ([string]$Toggle.State) {
        'Disable' {
            Write-VantaNote -Text 'App and document tracking features are disabled and their settings page is hidden.'
        }
        'Enable' {
            Write-VantaNextStep -Text 'Configure app and document tracking in File Explorer options and in the Start and General privacy settings pages.'
        }
        default { throw "RecentItems: unsupported state '$($Toggle.State)'." }
    }
}
