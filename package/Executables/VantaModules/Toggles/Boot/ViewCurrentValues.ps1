# Companion for the ViewCurrentValues toggle: prints the current boot configuration with
# bcdedit. Show-VantaBootValues runs as Administrator when you run the launcher; nothing is
# recorded.

function Show-VantaBootValues {
    param($Toggle)

    $bcdEditPath = [IO.Path]::Combine($Toggle.WinDir, 'System32', 'bcdedit.exe')
    $output = Invoke-VantaToggleNativeCommand -FilePath $bcdEditPath `
        -ArgumentList ([string[]]@('/enum', '{current}')) `
        -AllowedExitCodes ([int[]]@(0))
    Write-VantaNote -Text ([string[]]@($output | Select-Object -Skip 3 | ForEach-Object { [string]$_ }))
}
