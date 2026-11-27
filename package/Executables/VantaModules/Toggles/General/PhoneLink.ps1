# Companion for the PhoneLink toggle: turns the Phone Link service, cross-device resume and
# app on or off. The machine functions run as Administrator when you run a launcher, when the
# install applies Disable and when an update replays the recorded state.
# Enable-VantaPhoneLinkUser runs in your own unelevated process after Enable, and is replayed
# for each new account at first sign-in.

function Disable-VantaPhoneLinkMachine {
    param($Toggle)

    Import-VantaModule -Name Vanta.Shell
    Set-VantaSettingsPageVisibility -Operation hide -Page mobile-devices -NoProcessCleanup

    # Limit cleanup to the initiating Windows session; another signed-in user's
    # RuntimeBroker or Phone Link process must remain untouched.
    $sessionId = [Diagnostics.Process]::GetCurrentProcess().SessionId
    if ($sessionId -gt 0) {
        Stop-VantaProcess `
            -Name @('RuntimeBroker', 'PhoneExperienceHost') `
            -SessionId $sessionId `
            -StopOnError `
            -WaitTimeoutMilliseconds 10000
    }
    Import-VantaModule -Name Vanta.Appx
    Remove-VantaPhoneLinkAppx

    if (-not $Toggle.Silent) {
        if (Read-VantaYesNo -Question 'Also turn off automatic updates for Microsoft Store apps?') {
            Set-VantaRegistryValue `
                -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsStore\WindowsUpdate' `
                -Name 'AutoDownload' -Type DWord -Data 2
        }
    }
}

function Enable-VantaPhoneLinkMachine {
    param($Toggle)

    # These settings affect other products too. Replay must not infer consent to
    # change them from the recorded Phone Link choice.
    if (-not $Toggle.Silent) {
        if (Read-VantaYesNo -Question 'Allow Microsoft account sign-in on this PC? Phone Link usually needs it.') {
            Remove-VantaRegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name NoConnectedUser
        }
        if (Read-VantaYesNo -Question 'Allow Windows consumer features? This can also bring back suggested apps.') {
            Remove-VantaRegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Name DisableWindowsConsumerFeatures
        }
        if (Read-VantaYesNo -Question 'Turn on automatic updates for all Microsoft Store apps?') {
            Set-VantaRegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsStore\WindowsUpdate' -Name AutoDownload -Type DWord -Data 4
        }
    }
    Import-VantaModule -Name Vanta.Shell
    Set-VantaSettingsPageVisibility -Operation unhide -Page mobile-devices -NoProcessCleanup
}

function Enable-VantaPhoneLinkUser {
    param($Toggle)

    if ($Toggle.Silent) {
        return
    }
    Write-VantaStep -Text 'Opening Settings > Bluetooth & devices > Mobile devices...'
    Start-Process 'ms-settings:mobile-devices' -ErrorAction Stop
    Write-VantaNextStep -Text 'Link your phone from the Mobile devices page that just opened.'
}
