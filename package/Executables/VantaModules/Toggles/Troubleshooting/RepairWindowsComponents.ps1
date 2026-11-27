# Companion for the RepairWindowsComponents toggle: repairs Windows components with DISM
# RestoreHealth and system files with SFC. Repair-VantaWindowsComponents runs as Administrator
# when you run the launcher; nothing is recorded.

function Repair-VantaWindowsComponents {
    param($Toggle)

    $system32 = Join-Path -Path $Toggle.WinDir -ChildPath 'System32'

    if (-not $Toggle.Silent) {
        Write-VantaStep -Text 'Repairing the component store with DISM. This can take a long time...'
    }
    [void](Invoke-VantaToggleNativeCommand -FilePath (Join-Path -Path $system32 -ChildPath 'dism.exe') `
            -ArgumentList ([string[]]@('/Online', '/Cleanup-Image', '/RestoreHealth', '/NoRestart')) `
            -AllowedExitCodes ([int[]]@(0)))

    if (-not $Toggle.Silent) {
        Write-VantaStep -Text 'Repairing system files with SFC. This can take a while...'
    }
    [void](Invoke-VantaToggleNativeCommand -FilePath (Join-Path -Path $system32 -ChildPath 'sfc.exe') `
            -ArgumentList ([string[]]@('/scannow')) `
            -AllowedExitCodes ([int[]]@(0)))
}
