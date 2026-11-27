# Companion for the HighestMode toggle: sets or removes highestmode in the boot configuration.
# Its functions run as Administrator when you choose a state from the menu and when an update
# replays the recorded state.

# highestmode: https://learn.microsoft.com/windows-hardware/drivers/devtest/bcdedit--set#display-settings

function Disable-VantaHighestMode {
    param($Toggle)

    Remove-VantaToggleBcdValue -WinDir $Toggle.WinDir -Identifier '{globalsettings}' -Element 'highestmode'
}

function Enable-VantaHighestMode {
    param($Toggle)

    $bcdEditPath = [IO.Path]::Combine($Toggle.WinDir, 'System32', 'bcdedit.exe')
    Invoke-VantaToggleNativeCommand -FilePath $bcdEditPath `
        -ArgumentList ([string[]]@('/set', '{globalsettings}', 'highestmode', 'true')) `
        -AllowedExitCodes ([int[]]@(0)) | Out-Null
}
