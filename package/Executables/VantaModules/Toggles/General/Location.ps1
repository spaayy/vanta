# Companion for the Location toggle: turns location services and Find My Device on or off.
# Disable-VantaLocation and Enable-VantaLocation run as Administrator when you run a launcher,
# when the install applies the toggle and when an update replays the recorded state.
# Show-VantaLocationSettings runs in your own unelevated process after Enable, and is replayed
# for each new account at first sign-in.

function Disable-VantaLocation {
    param($Toggle)

    Import-VantaModule -Name Vanta.Privacy
    Set-VantaLocationMachineState -State Disable
}

function Enable-VantaLocation {
    param($Toggle)

    Import-VantaModule -Name Vanta.Privacy
    Set-VantaLocationMachineState -State Enable

    # The Find My Device question is asked only in interactive runs, so a silent run or
    # update replay never waits for an answer; silent runs leave Find My Device as it is.
    if (-not $Toggle.Silent) {
        Import-VantaModule -Name Vanta.Shell
        $findMyDevice = 'HKLM:\SOFTWARE\Policies\Microsoft\FindMyDevice'
        if (Read-VantaYesNo -Question 'Also allow Find My Device, which lets your Microsoft account locate this PC?') {
            foreach ($name in @('AllowFindMyDevice', 'LocationSyncEnabled')) {
                Remove-VantaRegistryValue -Path $findMyDevice -Name $name
            }
            Set-VantaSettingsPageVisibility -Operation unhide -Page findmydevice
        }
    }
}

function Show-VantaLocationSettings {
    param($Toggle)
    if (-not $Toggle.Silent) {
        Write-VantaStep -Text 'Opening Settings > Privacy & security > Location...'
        Start-Process 'ms-settings:privacy-location' -ErrorAction Stop
        Write-VantaManualStep -Text 'In Settings, turn on Location services, then choose which apps may use your location.'
    }
}
