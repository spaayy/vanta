# Companion for the KernelParameters toggle: sets or removes optionsedit in the boot
# configuration. Its functions run as Administrator when you choose a state from the menu and
# when an update replays the recorded state.

function Disable-VantaKernelParameters {
    param($Toggle)

    Remove-VantaToggleBcdValue -WinDir $Toggle.WinDir -Identifier '{globalsettings}' -Element 'optionsedit'
}

function Enable-VantaKernelParameters {
    param($Toggle)

    $bcdEditPath = [IO.Path]::Combine($Toggle.WinDir, 'System32', 'bcdedit.exe')
    Invoke-VantaToggleNativeCommand -FilePath $bcdEditPath `
        -ArgumentList ([string[]]@('/set', '{globalsettings}', 'optionsedit', 'true')) `
        -AllowedExitCodes ([int[]]@(0)) | Out-Null
}
