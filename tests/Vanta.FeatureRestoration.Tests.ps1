BeforeAll {
    . (Join-Path $PSScriptRoot 'VantaTestHost.ps1')
    Import-Module (Join-Path $script:VantaTestModulesRoot 'Vanta.Core\Vanta.Core.psd1') -Force
    Import-Module (Join-Path $script:VantaTestModulesRoot 'Vanta.Toggles\Vanta.Toggles.psd1') -Force
    Import-Module (Join-Path $script:VantaTestModulesRoot 'Vanta.Download\Vanta.Download.psd1') -Force
    $root = Join-Path $script:VantaTestRepoRoot 'package\Executables\VantaModules\Toggles'
    . (Join-Path $root 'Advanced\MicrosoftStore.ps1')
    . (Join-Path $root 'General\Widgets.ps1')
    . (Join-Path $root 'General\SystemRestore.ps1')
}

Describe 'User app restoration outcomes' {
    BeforeEach {
        $script:healthy = $false
        Mock Get-AppxPackage { if ($script:healthy) { [pscustomobject]@{ Status = 'Ok' } } }
        Mock Add-AppxPackage { $script:healthy = $true }
        Mock Import-VantaModule {}
        Mock Get-VantaTrustedWingetPath { 'TestDrive:\winget.exe' }
        Mock Assert-VantaTrustedWingetSource {}
        Mock Invoke-VantaToggleNativeCommand { $script:healthy = $true }
        Mock Start-Process {}
    }

    It 'registers a staged Store family for the current user' {
        Register-VantaMicrosoftStore -Toggle ([pscustomobject]@{ Silent = $true })
        Should -Invoke Add-AppxPackage -Times 1 -Exactly -ParameterFilter {
            $RegisterByFamilyName -and $MainPackage -eq 'Microsoft.WindowsStore_8wekyb3d8bbwe'
        }
        Should -Invoke Get-AppxPackage -Times 2 -Exactly -ParameterFilter { -not $AllUsers }
    }

    It 'does not register Store again when it is already healthy' {
        $script:healthy = $true
        Register-VantaMicrosoftStore -Toggle ([pscustomobject]@{ Silent = $true })
        Should -Not -Invoke Add-AppxPackage
    }

    It 'downloads the exact Store product when its staged package is gone' {
        Mock Add-AppxPackage { throw 'payload unavailable' }
        Register-VantaMicrosoftStore -Toggle ([pscustomobject]@{ Silent = $true })
        Should -Invoke Assert-VantaTrustedWingetSource -Times 1 -Exactly -ParameterFilter { $Name -eq 'msstore' }
        Should -Invoke Invoke-VantaToggleNativeCommand -Times 1 -Exactly -ParameterFilter {
            $FilePath -eq 'TestDrive:\winget.exe' -and $ArgumentList -contains '9WZDNCRFJBMP' -and
            $ArgumentList -contains '--exact' -and $ArgumentList -contains 'msstore' -and
            $AllowedExitCodes.Count -eq 1 -and $AllowedExitCodes[0] -eq 0
        }
    }

    It 'rejects a successful download that leaves no healthy Store package' {
        Mock Add-AppxPackage { throw 'payload unavailable' }
        Mock Invoke-VantaToggleNativeCommand {}
        { Register-VantaMicrosoftStore -Toggle ([pscustomobject]@{ Silent = $true }) } | Should -Throw '*healthy*'
    }

    It 'does not download Store through an untrusted source' {
        Mock Add-AppxPackage { throw 'payload unavailable' }
        Mock Assert-VantaTrustedWingetSource { throw 'untrusted source' }
        { Register-VantaMicrosoftStore -Toggle ([pscustomobject]@{ Silent = $true }) } | Should -Throw '*untrusted source*'
        Should -Not -Invoke Invoke-VantaToggleNativeCommand
    }

    It 'rejects Store registration that leaves no healthy app' {
        Mock Add-AppxPackage {}
        { Register-VantaMicrosoftStore -Toggle ([pscustomobject]@{ Silent = $true }) } | Should -Throw '*healthy*'
    }

    It 'restores Widgets through the exact trusted Store product before opening settings' {
        Install-VantaWidgetsUser -Toggle ([pscustomobject]@{ Silent = $false })
        Should -Invoke Assert-VantaTrustedWingetSource -Times 1 -Exactly -ParameterFilter { $Name -eq 'msstore' }
        Should -Invoke Invoke-VantaToggleNativeCommand -Times 1 -Exactly -ParameterFilter {
            $ArgumentList -contains '9MSSGKG348SP' -and $ArgumentList -contains '--exact' -and $AllowedExitCodes.Count -eq 1 -and $AllowedExitCodes[0] -eq 0
        }
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $FilePath -eq 'ms-settings:taskbar' }
    }

    It 'does not open Widgets settings after an ineffective installation' {
        Mock Invoke-VantaToggleNativeCommand {}
        { Install-VantaWidgetsUser -Toggle ([pscustomobject]@{ Silent = $false }) } | Should -Throw '*not healthy*'
        Should -Not -Invoke Start-Process
    }

    It 'restores the missing feed provider even when the Widgets board is healthy' {
        Mock Get-AppxPackage {
            if ($Name -eq 'MicrosoftWindows.Client.WebExperience' -or $script:healthy) {
                [pscustomobject]@{ Status = 'Ok' }
            }
        }
        Install-VantaWidgetsUser -Toggle ([pscustomobject]@{ Silent = $false })
        Should -Invoke Invoke-VantaToggleNativeCommand -Times 1 -Exactly -ParameterFilter {
            $ArgumentList -contains '9PC1H9VN18CM' -and $ArgumentList -contains '--exact'
        }
        Should -Invoke Start-Process -Times 1 -Exactly
    }

    It 'does not claim complete restoration when the feed provider remains missing' {
        Mock Get-AppxPackage {
            if ($Name -eq 'MicrosoftWindows.Client.WebExperience') { [pscustomobject]@{ Status = 'Ok' } }
        }
        { Install-VantaWidgetsUser -Toggle ([pscustomobject]@{ Silent = $false }) } |
            Should -Throw '*Start Experiences App is not healthy*'
        Should -Not -Invoke Start-Process
    }
}

Describe 'System Restore enable outcome' {
    It 'enables Windows volume protection and propagates failure' {
        Mock Enable-ComputerRestore { throw 'protection unavailable' }
        { Enable-VantaWindowsVolumeProtection -Toggle ([pscustomobject]@{ Silent = $true }) } | Should -Throw '*protection unavailable*'
        Should -Invoke Enable-ComputerRestore -Times 1 -Exactly -ParameterFilter {
            $Drive -eq [IO.Path]::GetPathRoot([Environment]::GetFolderPath('Windows')) -and $ErrorAction -eq 'Stop'
        }
    }
}

Describe 'Explicit enable state scope' {
    BeforeAll {
        Import-Module (Join-Path $script:VantaTestModulesRoot 'Vanta.Privacy\Vanta.Privacy.psd1') -Force
        Import-Module (Join-Path $script:VantaTestModulesRoot 'Vanta.Shell\Vanta.Shell.psd1') -Force
        . (Join-Path $root 'General\Location.ps1')
    }
    BeforeEach {
        Mock Import-VantaModule {}
        Mock Set-VantaLocationMachineState {}
        Mock Remove-VantaRegistryValue {}
        Mock Set-VantaRegistryValue {}
        Mock Set-VantaSettingsPageVisibility {}
        Mock Read-VantaYesNo { $false }
        Mock Start-Process {}
    }
    It 'preserves Find My Device when its separate change is declined' {
        Enable-VantaLocation -Toggle ([pscustomobject]@{ Silent = $false })
        Should -Invoke Set-VantaLocationMachineState -Times 1 -Exactly -ParameterFilter { $State -ceq 'Enable' }
        Should -Invoke Read-VantaYesNo -Times 1 -Exactly
        Should -Not -Invoke Remove-VantaRegistryValue
        Should -Not -Invoke Set-VantaRegistryValue
        Should -Not -Invoke Set-VantaSettingsPageVisibility
        Should -Not -Invoke Start-Process
    }
    It 'unlocks only the two Vanta Find My Device restrictions after acceptance' {
        Mock Read-VantaYesNo { $true }
        Enable-VantaLocation -Toggle ([pscustomobject]@{ Silent = $false })
        Should -Invoke Set-VantaLocationMachineState -Times 1 -Exactly -ParameterFilter { $State -ceq 'Enable' }
        Should -Invoke Remove-VantaRegistryValue -Times 2 -Exactly -ParameterFilter {
            $Path -eq 'HKLM:\SOFTWARE\Policies\Microsoft\FindMyDevice' -and $Name -in @('AllowFindMyDevice','LocationSyncEnabled')
        }
        Should -Invoke Set-VantaSettingsPageVisibility -Times 1 -Exactly -ParameterFilter {
            $Operation -eq 'unhide' -and $Page -eq 'findmydevice'
        }
        Should -Not -Invoke Set-VantaRegistryValue
    }
    It 'never asks about Find My Device in a silent or upgrade re-apply' {
        Mock Read-VantaYesNo { throw 'Silent re-apply must not prompt.' }
        Enable-VantaLocation -Toggle ([pscustomobject]@{ Silent = $true })
        Should -Invoke Set-VantaLocationMachineState -Times 1 -Exactly -ParameterFilter { $State -ceq 'Enable' }
        Should -Invoke Read-VantaYesNo -Times 0 -Exactly
        Should -Not -Invoke Remove-VantaRegistryValue
        Should -Not -Invoke Set-VantaSettingsPageVisibility
    }
}
