BeforeAll {
    . (Join-Path $PSScriptRoot 'VantaTestHost.ps1')
    Import-Module (Join-Path $script:VantaTestModulesRoot 'Vanta.Core\Vanta.Core.psd1') -Force
    Import-Module (Join-Path $script:VantaTestModulesRoot 'Vanta.Toggles\Vanta.Toggles.psd1') -Force
    $script:togglesRoot = Join-Path $script:VantaTestRepoRoot 'package\Executables\VantaModules\Toggles'
}

# The machine work runs in the silent TrustedInstaller broker, so the warning before
# force-enabling every mitigation can only come from the administrator window.
Describe 'Enable All Mitigations confirmation' {
    BeforeEach {
        Mock Test-VantaAdmin -ModuleName Vanta.Toggles { $true }
        Mock Test-VantaSystem -ModuleName Vanta.Toggles { $false }
        Mock Test-VantaTrustedInstaller -ModuleName Vanta.Toggles { $false }
        # The preamble itself runs: a definition-wide Warning would gate every state there.
        Mock Write-VantaTitle -ModuleName Vanta.Toggles
        Mock Write-VantaStep -ModuleName Vanta.Toggles
        Mock Invoke-VantaTogglePostAction -ModuleName Vanta.Toggles
        Mock Write-VantaWarning -ModuleName Vanta.Toggles
        $script:confirmed = $false
        $script:confirmedBeforeBroker = $null
        Mock Wait-VantaContinue -ModuleName Vanta.Toggles { $script:confirmed = $true }
        Mock Invoke-VantaTrustedInstaller -ModuleName Vanta.Toggles { $script:confirmedBeforeBroker = $script:confirmed }
    }

    It 'warns and waits in the administrator window before the broker runs' {
        Invoke-VantaToggle -Name Mitigations -State Enable -TogglesRoot $script:togglesRoot

        Should -Invoke Write-VantaWarning -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter {
            ($Text -join ' ') -like '*force-enables every security mitigation*'
        }
        Should -Invoke Wait-VantaContinue -ModuleName Vanta.Toggles -Times 1 -Exactly
        Should -Invoke Invoke-VantaTrustedInstaller -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter {
            $Name -ceq 'Mitigations' -and $State -ceq 'Enable' -and $Silent
        }
        $script:confirmedBeforeBroker | Should -BeTrue
    }

    It 'does not warn during silent replay' {
        Invoke-VantaToggle -Name Mitigations -State Enable -Silent -TogglesRoot $script:togglesRoot

        Should -Not -Invoke Wait-VantaContinue -ModuleName Vanta.Toggles
        Should -Invoke Invoke-VantaTrustedInstaller -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter {
            $State -ceq 'Enable' -and $Silent
        }
    }

    It 'leaves the other states without a confirmation' -ForEach @(
        @{ Choice = 'Disable' }
        @{ Choice = 'WindowsDefault' }
    ) {
        Invoke-VantaToggle -Name Mitigations -State $Choice -TogglesRoot $script:togglesRoot

        Should -Not -Invoke Write-VantaWarning -ModuleName Vanta.Toggles
        Should -Not -Invoke Wait-VantaContinue -ModuleName Vanta.Toggles
        Should -Invoke Invoke-VantaTrustedInstaller -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter {
            $State -ceq $Choice
        }
    }
}
