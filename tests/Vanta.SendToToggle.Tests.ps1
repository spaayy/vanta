BeforeAll {
    . (Join-Path $PSScriptRoot 'VantaTestHost.ps1')
    Import-Module (Join-Path $script:VantaTestModulesRoot 'Vanta.Core\Vanta.Core.psd1') -Force
    Import-Module (Join-Path $script:VantaTestModulesRoot 'Vanta.Shell\Vanta.Shell.psd1') -Force
    Import-Module (Join-Path $script:VantaTestModulesRoot 'Vanta.Toggles\Vanta.Toggles.psd1') -Force

    $togglesRoot = Join-Path $script:VantaTestRepoRoot 'package\Executables\VantaModules\Toggles'
    $script:SendTo = Get-VantaToggleDefinition -Name SendToContextMenu -TogglesRoot $togglesRoot

    # Runs the companion as the engine does (dot-sourced into the module scope under
    # strict mode), so module-scoped mocks, including private engine helpers, apply.
    function Invoke-SendToChooser {
        param([bool]$Silent)

        $toggle = [pscustomobject]@{ Name = 'SendToContextMenu'; State = 'Debloat'; Silent = $Silent }
        InModuleScope Vanta.Toggles {
            Invoke-VantaToggleFunction -Definition $d -FunctionName 'Invoke-VantaSendToContextMenuChooser' `
                -Toggle $t -Label 'test'
        } -Parameters @{ d = $script:SendTo; t = $toggle }
    }
}

Describe 'Send To companion' {
    BeforeEach {
        Mock Import-VantaModule -ModuleName Vanta.Toggles
        Mock Write-VantaStep -ModuleName Vanta.Toggles
        Mock Write-VantaLog -ModuleName Vanta.Toggles
        Mock Write-VantaPartial -ModuleName Vanta.Toggles
        Mock Write-VantaNextStep -ModuleName Vanta.Toggles
        Mock Read-VantaYesNo -ModuleName Vanta.Toggles { $true }
        # Like the real function, only the interactive dialog reports whether it applied.
        Mock Set-VantaSendToContextMenu -ModuleName Vanta.Toggles { if (-not $DebloatDefaults) { $true } }
        Mock Invoke-VantaToggleCurrentSessionShellRefresh -ModuleName Vanta.Toggles
        # An elevated window skips the restart question, so the test host's own token
        # mustn't decide these cases.
        Mock Test-VantaAdmin -ModuleName Vanta.Toggles { $false }
        Mock Test-VantaSystem -ModuleName Vanta.Toggles { $false }
    }

    It 'applies the Vanta defaults silently without asking or restarting Explorer' {
        @(Invoke-SendToChooser -Silent $true).Count | Should -Be 0

        Should -Invoke Set-VantaSendToContextMenu -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter { $DebloatDefaults }
        Should -Invoke Read-VantaYesNo -ModuleName Vanta.Toggles -Times 0 -Exactly
        Should -Invoke Invoke-VantaToggleCurrentSessionShellRefresh -ModuleName Vanta.Toggles -Times 0 -Exactly
    }

    It 'restarts Explorer through the engine helper after an applied choice' {
        @(Invoke-SendToChooser -Silent $false).Count | Should -Be 0

        Should -Invoke Read-VantaYesNo -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter { $DefaultYes }
        Should -Invoke Invoke-VantaToggleCurrentSessionShellRefresh -ModuleName Vanta.Toggles -Times 1 -Exactly `
            -ParameterFilter { $Operation -ceq 'ExplorerRefresh' }
        Should -Invoke Write-VantaPartial -ModuleName Vanta.Toggles -Times 0 -Exactly
        Should -Invoke Write-VantaNextStep -ModuleName Vanta.Toggles -Times 0 -Exactly
    }

    It 'gives restart guidance instead of asking when run as <Account>' -ForEach @(
        @{ Account = 'an administrator'; Elevated = 'Test-VantaAdmin' }
        @{ Account = 'SYSTEM'; Elevated = 'Test-VantaSystem' }
    ) {
        Mock $Elevated -ModuleName Vanta.Toggles { $true }

        Invoke-SendToChooser -Silent $false

        Should -Invoke Read-VantaYesNo -ModuleName Vanta.Toggles -Times 0 -Exactly
        Should -Invoke Invoke-VantaToggleCurrentSessionShellRefresh -ModuleName Vanta.Toggles -Times 0 -Exactly
        Should -Invoke Write-VantaNextStep -ModuleName Vanta.Toggles -Times 1 -Exactly
    }

    It 'neither asks nor restarts Explorer when the dialog is cancelled' {
        Mock Set-VantaSendToContextMenu -ModuleName Vanta.Toggles { $false }

        Invoke-SendToChooser -Silent $false

        Should -Invoke Read-VantaYesNo -ModuleName Vanta.Toggles -Times 0 -Exactly
        Should -Invoke Invoke-VantaToggleCurrentSessionShellRefresh -ModuleName Vanta.Toggles -Times 0 -Exactly
    }

    It 'leaves Explorer alone when the restart is declined' {
        Mock Read-VantaYesNo -ModuleName Vanta.Toggles { $false }

        Invoke-SendToChooser -Silent $false

        Should -Invoke Invoke-VantaToggleCurrentSessionShellRefresh -ModuleName Vanta.Toggles -Times 0 -Exactly
    }

    It 'reports a failed Explorer restart as partly done instead of not applied' {
        Mock Invoke-VantaToggleCurrentSessionShellRefresh -ModuleName Vanta.Toggles {
            throw 'Current-session toggle shell refresh exited with code 14.'
        }

        { Invoke-SendToChooser -Silent $false } | Should -Not -Throw

        Should -Invoke Write-VantaPartial -ModuleName Vanta.Toggles -Times 1 -Exactly
        Should -Invoke Write-VantaLog -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter {
            $Level -ceq 'Warning' -and $Message -like '*exited with code 14*'
        }
    }
}
