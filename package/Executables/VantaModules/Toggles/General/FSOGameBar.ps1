# Companion for the FSOGameBar toggle: removes the Game Bar overlay package for every user, or
# installs Game Bar again for one account. Remove-VantaGameBarOverlayPackage runs in the
# silent TrustedInstaller broker when you run Disable and when an update replays the recorded
# state. Install-VantaGameBarPackage runs in your own unelevated process when you run Enable,
# and is replayed for each new account at first sign-in.

function Remove-VantaGameBarOverlayPackage {
    param($Toggle)

    # Under TrustedInstaller/SYSTEM, -AllUsers is required on both commands.
    Get-AppxPackage -AllUsers '*xboxgamingoverlay*' -ErrorAction Stop |
        Remove-AppxPackage -AllUsers -Confirm:$false -ErrorAction Stop
}

function Install-VantaGameBarPackage {
    param($Toggle)

    if (-not $Toggle.Silent) {
        Write-VantaStep -Text 'Restoring the Game Bar package...'
    }
    Import-VantaModule -Name Vanta.Appx
    Install-VantaGameBar
}
