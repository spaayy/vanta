# Companion for the Copilot toggle: removes the Copilot app, or installs it from Microsoft
# Store and brings back its taskbar button. Remove-VantaCopilotApp and
# Enable-VantaCopilotMachine run as Administrator when you run a launcher and when an update
# replays the recorded state. Enable-VantaCopilotUser runs in your own unelevated process
# after Enable, and is replayed for each new account at first sign-in.
# Test-VantaCopilotEdgeInstalled decides during update replay whether a recorded Enable still
# applies.

function Remove-VantaCopilotApp {
    param($Toggle)

    if (-not $Toggle.Silent) {
        Write-VantaStep -Text 'Removing the Copilot app...'
    }
    Import-VantaModule -Name Vanta.Appx
    Invoke-VantaAppxRemovalPlan -Definition @(
        [pscustomobject]@{
            Name         = 'Microsoft.Copilot*'
            Option       = $null
            IgnoreErrors = $false
        }
    )
}

function Test-VantaCopilotEdgeInstalled {
    param($Toggle)

    $programFilesX86 = [Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFilesX86)
    if ([string]::IsNullOrWhiteSpace($programFilesX86)) {
        throw 'Copilot: the 32-bit Program Files directory is unavailable.'
    }
    return (Test-Path -LiteralPath ([IO.Path]::Combine($programFilesX86, 'Microsoft\Edge\Application\msedge.exe')) -PathType Leaf)
}

function Enable-VantaCopilotMachine {
    param($Toggle)

    if (-not (Test-VantaCopilotEdgeInstalled -Toggle $Toggle)) {
        throw 'Copilot needs Microsoft Edge, which is not installed. Install Edge from 1. Software, then try again.'
    }

    Remove-VantaRegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' -Name 'RemoveMicrosoftCopilotApp'
}

function Enable-VantaCopilotUser {
    param($Toggle)

    # When the taskbar Copilot button is unavailable (24H2+), Copilot is a separate app
    # installed through the trusted WinGet resolver; otherwise re-show the button.
    $available = Get-ItemPropertyValue -LiteralPath 'HKCU:\Software\Microsoft\Windows\Shell\Copilot' `
        -Name 'IsCopilotAvailable' -ErrorAction SilentlyContinue
    $legacyTaskbarAvailable = ($Toggle.WindowsBuild -lt 26100 -and $null -ne $available -and [int]$available -eq 1)
    if ($legacyTaskbarAvailable) {
        Set-VantaRegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' `
            -Name 'ShowCopilotButton' -Type DWord -Data 1
        return
    }

    $installed = @(Get-AppxPackage -Name Microsoft.Copilot -ErrorAction Stop | Where-Object { [string]$_.Status -eq 'Ok' })
    if ($installed.Count -gt 0) { return }

    if (-not $Toggle.Silent) {
        Write-VantaNote -Text 'This Windows version has no Copilot taskbar button, so the Copilot app is installed instead.'
        Write-VantaStep -Text 'Installing the Copilot app from the Microsoft Store. This can take a few minutes...'
    }
    Import-VantaModule -Name Vanta.Download
    $wingetPath = Get-VantaTrustedWingetPath
    Assert-VantaTrustedWingetSource -WingetPath $wingetPath -Name msstore
    [void](Invoke-VantaToggleNativeCommand -FilePath $wingetPath `
            -ArgumentList ([string[]]@(
                    'install', '--exact', '--id', '9NHT9RB2F4HD', '--source', 'msstore',
                    '--uninstall-previous', '--silent', '--accept-source-agreements',
                    '--accept-package-agreements', '--disable-interactivity'
                )) `
            -AllowedExitCodes ([int[]]@(0)))
    if (@(Get-AppxPackage -Name Microsoft.Copilot -ErrorAction Stop | Where-Object { [string]$_.Status -eq 'Ok' }).Count -eq 0) {
        throw 'Copilot installation did not produce a healthy package for this user.'
    }
}
