BeforeAll {
    . (Join-Path $PSScriptRoot 'VantaTestHost.ps1')
    Import-Module (Join-Path $script:VantaTestModulesRoot 'Vanta.Core\Vanta.Core.psd1') -Force
    Import-Module (Join-Path $script:VantaTestModulesRoot 'Vanta.Toggles\Vanta.Toggles.psd1') -Force
    Import-Module (Join-Path $script:VantaTestModulesRoot 'Vanta.Search\Vanta.Search.psd1') -Force
    $script:indexRoot = Join-Path $script:VantaTestRepoRoot 'package\Executables\VantaModules\Toggles'
}
Describe 'Interactive indexing across the TrustedInstaller boundary' {
    BeforeEach {
        Mock Test-VantaAdmin -ModuleName Vanta.Toggles { $true }
        Mock Test-VantaSystem -ModuleName Vanta.Toggles { $false }
        Mock Test-VantaTrustedInstaller -ModuleName Vanta.Toggles { $false }
        Mock Show-VantaTogglePreamble -ModuleName Vanta.Toggles {}
        Mock Invoke-VantaTogglePostAction -ModuleName Vanta.Toggles {}
        Mock Invoke-VantaTrustedInstaller -ModuleName Vanta.Toggles {}
        Mock Read-VantaYesNo -ModuleName Vanta.Toggles { $true }
    }
    It 'passes the yes choice as a fixed state to a silent broker' {
        Invoke-VantaToggle -Name Indexing -State Enable -TogglesRoot $script:indexRoot
        Should -Invoke Invoke-VantaTrustedInstaller -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter {
            $Name -ceq 'Indexing' -and $State -ceq 'EnableRespectPowerModes' -and $Silent
        }
        Should -Invoke Read-VantaYesNo -ModuleName Vanta.Toggles -Times 1 -Exactly
    }
    It 'passes the no choice without substituting the preserved value' {
        Mock Read-VantaYesNo -ModuleName Vanta.Toggles { $false }
        Invoke-VantaToggle -Name Indexing -State Enable -TogglesRoot $script:indexRoot
        Should -Invoke Invoke-VantaTrustedInstaller -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter {
            $State -ceq 'EnableIgnorePowerModes' -and $Silent
        }
    }
    It 'does not prompt or select an explicit power choice during silent replay' {
        Invoke-VantaToggle -Name Indexing -State Enable -Silent -TogglesRoot $script:indexRoot
        Should -Not -Invoke Read-VantaYesNo -ModuleName Vanta.Toggles
        Should -Invoke Invoke-VantaTrustedInstaller -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter { $State -ceq 'Enable' -and $Silent }
    }
    It 'keeps the administrator relaunch interactive' {
        Mock Test-VantaAdmin -ModuleName Vanta.Toggles { $false }
        Mock Invoke-VantaToggleElevatedChild -ModuleName Vanta.Toggles {}
        Invoke-VantaToggle -Name Indexing -State Enable -TogglesRoot $script:indexRoot
        # Invoke-Toggle.ps1 reads any of these spellings as silent, and the child must
        # still get the public state so it asks the power-mode question itself.
        Should -Invoke Invoke-VantaToggleElevatedChild -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter {
            $stateIndex = [array]::IndexOf($ArgumentList, '-State')
            @($ArgumentList | Where-Object { $_ -match '^[/-](silent|quiet)$' }).Count -eq 0 -and
                $stateIndex -ge 0 -and $ArgumentList[$stateIndex + 1].Trim('"') -ceq 'Enable'
        }
        Should -Not -Invoke Read-VantaYesNo -ModuleName Vanta.Toggles
    }
    It 'rejects an unrecognized selector result before dispatch' {
        Mock Invoke-VantaToggleFunction -ModuleName Vanta.Toggles { 'UnknownState' }
        { Invoke-VantaToggle -Name Indexing -State Enable -TogglesRoot $script:indexRoot } | Should -Throw '*exactly one installed state name*'
        Should -Not -Invoke Invoke-VantaTrustedInstaller -ModuleName Vanta.Toggles
    }
    It 'does not dispatch after a cancelled selector' {
        Mock Read-VantaYesNo -ModuleName Vanta.Toggles { throw 'selection cancelled' }
        { Invoke-VantaToggle -Name Indexing -State Enable -TogglesRoot $script:indexRoot } | Should -Throw '*selection cancelled*'
        Should -Not -Invoke Invoke-VantaTrustedInstaller -ModuleName Vanta.Toggles
    }
}
Describe 'Selected indexing records reflect completed work' {
    BeforeAll {
        $script:indexing = Get-VantaToggleDefinition -Name Indexing -TogglesRoot $script:indexRoot

        # Runs the broker's machine action for a fixed internal state the way the
        # engine does: dot-sourced inside Vanta.Toggles under strict mode.
        function Invoke-SelectedIndexing {
            param([Parameter(Mandatory = $true)][string]$State)

            InModuleScope Vanta.Toggles {
                $context = New-VantaToggleContext -Definition $d -StateName $s -Silent -StateRoot 'HKCU:\Unused'
                Invoke-VantaToggleFunction -Definition $d -FunctionName ([string]$d['States'][$s]['MachineAction']) `
                    -Toggle $context -Label 'test'
            } -Parameters @{ d = $script:indexing; s = $State }
        }
    }
    BeforeEach {
        Mock Write-VantaLog -ModuleName Vanta.Toggles
        Mock Import-VantaModule -ModuleName Vanta.Toggles
        Mock Set-VantaIndexingMachineState -ModuleName Vanta.Toggles
        Mock Set-VantaToggleState -ModuleName Vanta.Toggles
    }
    It 'applies the explicit value and keeps the existing replay record' -ForEach @(
        @{ Choice = 'EnableRespectPowerModes'; Value = 1 }
        @{ Choice = 'EnableIgnorePowerModes'; Value = 0 }
    ) {
        Invoke-SelectedIndexing -State $Choice
        Should -Invoke Set-VantaIndexingMachineState -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter {
            $State -ceq 'Full' -and $RespectPowerModes -eq $Value -and -not $PreservePowerModes
        }
        Should -Invoke Set-VantaToggleState -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter {
            $Name -ceq 'Indexing' -and $State -eq 2 -and $StateRoot -ceq 'HKCU:\Unused'
        }
    }
    It 'does not overwrite a record if preset application fails' {
        Mock Set-VantaIndexingMachineState -ModuleName Vanta.Toggles { throw 'preset failed' }
        { Invoke-SelectedIndexing -State EnableRespectPowerModes } | Should -Throw '*preset failed*'
        Should -Not -Invoke Set-VantaToggleState -ModuleName Vanta.Toggles
    }
}
