BeforeAll {
    . (Join-Path $PSScriptRoot 'VantaTestHost.ps1')
    Import-Module (Join-Path $script:VantaTestModulesRoot 'Vanta.Core\Vanta.Core.psd1') -Force
    # The companion calls these after Import-VantaModule (mocked below); load the real
    # modules once so the mocks have a command to shadow inside Vanta.Toggles.
    Import-Module (Join-Path $script:VantaTestModulesRoot 'Vanta.Services\Vanta.Services.psd1') -Force
    Import-Module (Join-Path $script:VantaTestModulesRoot 'Vanta.Shell\Vanta.Shell.psd1') -Force
    Import-Module (Join-Path $script:VantaTestModulesRoot 'Vanta.Toggles\Vanta.Toggles.psd1') -Force
    $togglesRoot = Join-Path $script:VantaTestRepoRoot 'package\Executables\VantaModules\Toggles'
    $script:printing = Get-VantaToggleDefinition -Name Printing -TogglesRoot $togglesRoot

    # Runs the machine action the way the engine does: with the engine's own $Toggle
    # context, dot-sourced inside Vanta.Toggles under strict mode.
    function Invoke-PrintingMachineAction {
        param([bool]$Silent = $true)

        InModuleScope Vanta.Toggles {
            $context = New-VantaToggleContext -Definition $d -StateName 'Enable' -Silent:$silent -StateRoot 'HKCU:\Unused'
            Invoke-VantaToggleFunction -Definition $d -FunctionName ([string]$d['States']['Enable']['MachineAction']) `
                -Toggle $context -Label 'test'
        } -Parameters @{ d = $script:printing; silent = $Silent }
    }
}

Describe 'Enable Printing with optional tools that cannot be added' {
    BeforeEach {
        Mock Write-VantaLog -ModuleName Vanta.Toggles
        Mock Write-VantaStep -ModuleName Vanta.Toggles
        Mock Write-VantaPartial -ModuleName Vanta.Toggles
        Mock Import-VantaModule -ModuleName Vanta.Toggles
        Mock Set-VantaServiceStartup -ModuleName Vanta.Toggles
        Mock Set-VantaSettingsPageVisibility -ModuleName Vanta.Toggles
        Mock Read-VantaYesNo -ModuleName Vanta.Toggles { throw 'Silent work must not prompt.' }
        # Windows Update is off: every capability download fails, the features enable.
        Mock Invoke-VantaToggleNativeCommand -ModuleName Vanta.Toggles {
            if ($ArgumentList -contains '/Add-Capability') {
                throw 'DISM exited with code 0x800f0954.'
            }
        }
    }

    It 'still enables printing during silent replay and logs the missing console' {
        Invoke-PrintingMachineAction

        Should -Invoke Invoke-VantaToggleNativeCommand -ModuleName Vanta.Toggles -Times 4 -Exactly -ParameterFilter {
            $ArgumentList -contains '/Enable-Feature'
        }
        Should -Invoke Write-VantaLog -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter {
            $Level -eq 'Warning' -and $Message -like '*Print.Management.Console*0x800f0954*' -and -not $NoConsole
        }
        Should -Not -Invoke Write-VantaPartial -ModuleName Vanta.Toggles
    }

    It 'reports each optional tool it could not add as partly done' {
        Mock Read-VantaYesNo -ModuleName Vanta.Toggles { $true }

        Invoke-PrintingMachineAction -Silent $false

        Should -Invoke Write-VantaPartial -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter {
            ($Text -join ' ') -like '*the Print Management console*'
        }
        Should -Invoke Write-VantaPartial -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter {
            ($Text -join ' ') -like '*Windows Fax and Scan*'
        }
        # The partial line already tells the user; the diagnostic goes to the log only.
        Should -Invoke Write-VantaLog -ModuleName Vanta.Toggles -Times 2 -Exactly -ParameterFilter {
            $Level -eq 'Warning' -and $NoConsole
        }
    }

    It 'still fails when a printing feature cannot be enabled' {
        Mock Invoke-VantaToggleNativeCommand -ModuleName Vanta.Toggles {
            if ($ArgumentList -contains '/FeatureName:Printing-Foundation-Features') {
                throw 'feature failed'
            }
        }

        { Invoke-PrintingMachineAction } | Should -Throw '*feature failed*'
        Should -Not -Invoke Invoke-VantaToggleNativeCommand -ModuleName Vanta.Toggles -ParameterFilter {
            $ArgumentList -contains '/Add-Capability'
        }
    }
}
