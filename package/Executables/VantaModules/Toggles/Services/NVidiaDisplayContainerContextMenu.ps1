# Companion for the NVidiaDisplayContainerContextMenu toggle: adds the desktop context menu
# that turns the NVIDIA Display Container LS service on or off.
# Add-VantaNVidiaContainerContextMenu runs as Administrator when you run Add and when an
# update replays the recorded state. Test-VantaNVidiaContainerContextMenuApplicable decides
# during update replay whether the service is still installed.

function Test-VantaNVidiaContainerContextMenuApplicable {
    param($Toggle)

    return Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\NVDisplay.ContainerLocalSystem'
}

function Add-VantaNVidiaContainerContextMenu {
    param($Toggle)

    if (-not (Test-VantaNVidiaContainerContextMenuApplicable -Toggle $Toggle)) {
        throw 'NVIDIA Display Container LS is not installed; its context menu cannot be added and no state was recorded.'
    }

    # The verb lives under the machine HKCR view. Each submenu entry launches the
    # matching VantaDesktop launcher, so the command paths depend on the Windows root.
    $launcherRoot = Join-Path -Path $Toggle.WinDir -ChildPath 'VantaDesktop\6. Advanced Configuration\Services\NVIDIA Display Container'
    $root = 'HKLM:\SOFTWARE\Classes\DesktopBackground\Shell\NVIDIAContainer'
    Set-VantaRegistryValue -Path $root -Name 'Icon' -Type String -Data 'NVIDIA.ico,0'
    Set-VantaRegistryValue -Path $root -Name 'MUIVerb' -Type String -Data 'NVIDIA Container'
    Set-VantaRegistryValue -Path $root -Name 'Position' -Type String -Data 'Bottom'
    Set-VantaRegistryValue -Path $root -Name 'SubCommands' -Type String -Data ''

    foreach ($entry in @(
            @{ Key = 'NVIDIAContainer001'; Label = 'Enable NVIDIA Display Container LS'; Launcher = 'Enable NVIDIA Display Container LS (default).cmd' }
            @{ Key = 'NVIDIAContainer002'; Label = 'Disable NVIDIA Display Container LS'; Launcher = 'Disable NVIDIA Display Container LS.cmd' }
        )) {
        $entryKey = "$root\shell\$($entry.Key)"
        Set-VantaRegistryValue -Path $entryKey -Name 'HasLUAShield' -Type String -Data ''
        Set-VantaRegistryValue -Path $entryKey -Name 'MUIVerb' -Type String -Data $entry.Label
        Set-VantaRegistryValue -Path "$entryKey\command" -Name '' -Type String `
            -Data ('"{0}"' -f (Join-Path -Path $launcherRoot -ChildPath $entry.Launcher))
    }
}
