# Companion of set-power-settings.psd1.
$ErrorActionPreference = 'Stop'
$systemDirectory = [Environment]::SystemDirectory
$powerCfgPath = [IO.Path]::Combine($systemDirectory, 'powercfg.exe')

$disablePowerSaving = [bool](Test-VantaOption -Name 'disable-power-saving')
$disableHibernation = [bool](Test-VantaOption -Name 'disable-hibernation')

# The toggles' machine states apply and record these choices, so the install and the
# VantaDesktop launchers can't drift apart.
Import-VantaModule -Name Vanta.Toggles
if ($disablePowerSaving) {
    Invoke-VantaToggleMachineState -Name PowerSaving -State Disable
}

# Disabling hibernation also makes NTFS accessible outside Windows.
if ($disableHibernation) {
    Invoke-VantaToggleMachineState -Name Hibernation -State Disable
}

# Keep the Balanced power scheme when power saving is retained.
if (-not $disablePowerSaving) {
    $balancedScheme = '381b4222-f694-41f0-9685-ff5bb260df2e'
    $null = Invoke-VantaToggleNativeCommand -FilePath $powerCfgPath `
        -ArgumentList ([string[]]@('/setactive', $balancedScheme)) `
        -AllowedExitCodes ([int[]]@(0))
    $activeOutput = (Invoke-VantaToggleNativeCommand -FilePath $powerCfgPath `
            -ArgumentList ([string[]]@('/getactivescheme')) `
            -AllowedExitCodes ([int[]]@(0)) -PassThru).Output
    $activeText = @($activeOutput) -join "`n"
    $guidMatches = @([regex]::Matches(
            $activeText,
            '(?i)(?<![0-9a-f])[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}(?![0-9a-f])'
        ) | ForEach-Object { $_.Value.ToLowerInvariant() } | Sort-Object -Unique)
    if ($guidMatches.Count -ne 1 -or $guidMatches[0] -cne $balancedScheme) {
        throw 'The Balanced power scheme did not become the active scheme.'
    }
}
