# Companion for the Bluetooth toggle: disables or enables every Bluetooth device and removes
# or restores the Bluetooth Send to entry. The device functions run as Administrator when you
# run a launcher and when an update replays the recorded state. The Send to functions run in
# your own unelevated process afterwards, and is replayed for each new account at first
# sign-in.

function Disable-VantaBluetoothDevices {
    param($Toggle)

    if (-not $Toggle.Silent) {
        Write-VantaStep -Text 'Disabling Bluetooth devices. This can take a minute...'
    }
    Import-VantaModule -Name Vanta.Hardware
    Set-VantaDeviceState -State Disable -Devices '*Bluetooth*' -AllowNoMatch -Silent
}

function Enable-VantaBluetoothDevices {
    param($Toggle)

    if (-not $Toggle.Silent) {
        Write-VantaStep -Text 'Enabling Bluetooth devices...'
    }
    Import-VantaModule -Name Vanta.Hardware
    Set-VantaDeviceState -State Enable -Devices '*Bluetooth*' -AllowNoMatch -Silent
}

function Remove-VantaBluetoothSendTo {
    param($Toggle)

    Import-VantaModule -Name Vanta.Shell
    Set-VantaSendToContextMenu -Disable @('Bluetooth')
}

function Set-VantaBluetoothSendTo {
    param($Toggle)

    Import-VantaModule -Name Vanta.Shell
    $enableSendTo = $false
    if (-not $Toggle.Silent) {
        $enableSendTo = Read-VantaYesNo -Question "Add 'Bluetooth File Transfer' to the Send To context menu?"
    }
    if ($enableSendTo) {
        Set-VantaSendToContextMenu -Enable @('Bluetooth')
    }
    else {
        Set-VantaSendToContextMenu -Disable @('Bluetooth')
    }
}
