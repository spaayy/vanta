# Companion for the CpuIdle toggle: sets the processor idle disable power setting with
# powercfg. Its functions run as Administrator when you run a launcher and when an update
# replays the recorded state. Test-VantaCpuIdleDisableSupported decides during update replay
# whether a recorded Disable still applies.

function Test-VantaCpuIdleDisableSupported {
    param($Toggle)

    foreach ($cpu in Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop) {
        if ([int]$cpu.NumberOfLogicalProcessors -gt [int]$cpu.NumberOfCores) {
            return $false
        }
    }
    return $true
}

function Disable-VantaCpuIdle {
    param($Toggle)

    $powercfg = "$($Toggle.WinDir)\System32\powercfg.exe"
    $idleGuid = '5d76a2ca-e8c0-402f-a133-2158492d58ad'

    # Reject a manual request; upgrades use the same check to skip an old unsupported choice.
    if (-not (Test-VantaCpuIdleDisableSupported -Toggle $Toggle)) {
        throw 'Hyper-Threading or SMT is enabled on this processor, and disabling idle states would make overall CPU performance much worse. Nothing was changed; consider disabling C-states in the BIOS instead.'
    }

    if (-not $Toggle.Silent) {
        Write-VantaNote -Text @(
            'This turns processor idle states off while on AC power, which raises power use and heat.'
            'Task Manager may then show misleadingly high CPU use. The CPU clock speed is not fixed.'
        )
    }

    Invoke-VantaToggleNativeCommand -FilePath $powercfg `
        -ArgumentList ([string[]]@('/setacvalueindex', 'scheme_current', 'sub_processor', $idleGuid, '1')) `
        -AllowedExitCodes ([int[]]@(0)) | Out-Null
    Invoke-VantaToggleNativeCommand -FilePath $powercfg `
        -ArgumentList ([string[]]@('/setactive', 'scheme_current')) `
        -AllowedExitCodes ([int[]]@(0)) | Out-Null
}

function Enable-VantaCpuIdle {
    param($Toggle)

    $powercfg = "$($Toggle.WinDir)\System32\powercfg.exe"
    Invoke-VantaToggleNativeCommand -FilePath $powercfg `
        -ArgumentList ([string[]]@('/setacvalueindex', 'scheme_current', 'sub_processor', '5d76a2ca-e8c0-402f-a133-2158492d58ad', '0')) `
        -AllowedExitCodes ([int[]]@(0)) | Out-Null
    Invoke-VantaToggleNativeCommand -FilePath $powercfg `
        -ArgumentList ([string[]]@('/setactive', 'scheme_current')) `
        -AllowedExitCodes ([int[]]@(0)) | Out-Null
}
