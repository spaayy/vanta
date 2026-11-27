BeforeAll {
    . (Join-Path $PSScriptRoot 'VantaTestHost.ps1')
    $modulesRoot = $script:VantaTestModulesRoot

    Import-Module (Join-Path $modulesRoot 'Vanta.Core\Vanta.Core.psd1') -Force
    Import-Module (Join-Path $modulesRoot 'Vanta.Toggles\Vanta.Toggles.psd1') -Force

    $script:VantaModulesPath = Join-Path $script:VantaTestRepoRoot 'package\Executables\VantaModules'
    $script:NVidiaServiceKey = 'HKLM:\SYSTEM\CurrentControlSet\Services\NVDisplay.ContainerLocalSystem'
}

# Runs the real reset core against the installed Services definitions and their real
# applicability checks; only the work each default would do is replaced.
Describe 'Invoke-VantaServiceDefaultsReset' {
    BeforeEach {
        $script:applied = [Collections.Generic.List[string]]::new()
        Mock Assert-VantaPrivilege -ModuleName Vanta.Toggles
        Mock Write-VantaLog -ModuleName Vanta.Toggles
        Mock Get-VantaContext -ModuleName Vanta.Toggles {
            [pscustomobject]@{
                WinDir           = [Environment]::GetFolderPath('Windows')
                VantaModulesPath = $script:VantaModulesPath
                WindowsBuild     = 26100
            }
        }
        Mock Invoke-VantaToggleScopedWork -ModuleName Vanta.Toggles {
            $script:applied.Add("$($Toggle.Name):$($Toggle.State)")
        }
        Mock Invoke-VantaToggleFunction -ModuleName Vanta.Toggles -ParameterFilter { $Label -eq 'context action' }
        Mock Set-VantaToggleState -ModuleName Vanta.Toggles
    }

    It 'skips the NVIDIA service default on a PC without the NVIDIA driver and applies the rest' {
        Mock Test-Path -ModuleName Vanta.Toggles { $false } -ParameterFilter { $LiteralPath -eq $script:NVidiaServiceKey }

        InModuleScope Vanta.Toggles { Invoke-VantaServiceDefaultsReset }

        $script:applied | Should -Be @(
            'Bluetooth:Enable'
            'LanmanWorkstation:Enable'
            'NetworkDiscovery:Enable'
            'NVidiaDisplayContainerContextMenu:Disable'
            'Printing:Enable'
            'SuperFetch:Enable'
        )
        Should -Invoke Set-VantaToggleState -ModuleName Vanta.Toggles -Times 0 -Exactly -ParameterFilter {
            $Name -eq 'NVidiaDisplayContainer'
        }
        Should -Invoke Set-VantaToggleState -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'SuperFetch' -and $State -eq 1
        }
    }

    It 'applies the NVIDIA service default when the driver is installed' {
        Mock Test-Path -ModuleName Vanta.Toggles { $true } -ParameterFilter { $LiteralPath -eq $script:NVidiaServiceKey }

        InModuleScope Vanta.Toggles { Invoke-VantaServiceDefaultsReset }

        $script:applied | Should -Contain 'NVidiaDisplayContainer:Enable'
        $script:applied.Count | Should -Be 7
    }
}
