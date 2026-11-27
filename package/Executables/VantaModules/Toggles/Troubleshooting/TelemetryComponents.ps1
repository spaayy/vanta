# Companion for the TelemetryComponents toggle: adds or removes the Vanta NoTelemetry package.
# Select-VantaTelemetryComponentsState runs first, in the administrator window: it shows the
# menu and picks an internal state. That state's function then runs in the silent
# TrustedInstaller broker. Nothing is recorded.

function Select-VantaTelemetryComponentsState {
    param($Toggle)

    if ($Toggle.Silent) {
        throw 'Choosing whether to add or remove the NoTelemetry package needs an interactive window.'
    }
    Import-VantaModule -Name Vanta.Privacy
    return Read-VantaTelemetryPackageChoice
}

function Invoke-VantaTelemetryComponentsMenu {
    param($Toggle)

    # Reached only by a direct silent request for the public state, which has no
    # choice to apply; the interactive path never runs this action.
    [void]$Toggle
    throw 'Telemetry Components needs an interactive window to choose between adding and removing the NoTelemetry package.'
}

function Add-VantaTelemetryPackageToggle {
    param($Toggle)

    Import-VantaModule -Name Vanta.Privacy
    Set-VantaTelemetryPackageState -State Installed -Silent:$Toggle.Silent
}

function Remove-VantaTelemetryPackageToggle {
    param($Toggle)

    Import-VantaModule -Name Vanta.Privacy
    Set-VantaTelemetryPackageState -State Removed -Silent:$Toggle.Silent
}
