# Companion for the SystemRestore toggle: turns on System Restore protection for the Windows
# drive. Enable-VantaWindowsVolumeProtection runs as Administrator when you run Enable and
# when an update replays the recorded state.

function Enable-VantaWindowsVolumeProtection {
    param($Toggle)

    $windowsVolume = [IO.Path]::GetPathRoot([Environment]::GetFolderPath('Windows'))
    if ([string]::IsNullOrWhiteSpace($windowsVolume)) {
        throw 'The Windows volume could not be resolved.'
    }
    Enable-ComputerRestore -Drive $windowsVolume -ErrorAction Stop
    if (-not $Toggle.Silent) {
        Write-VantaNote -Text "System Protection is on for $windowsVolume. No restore point was created."
    }
}
