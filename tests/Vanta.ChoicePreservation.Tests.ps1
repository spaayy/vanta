BeforeAll {
    . (Join-Path $PSScriptRoot 'VantaTestHost.ps1')
    Import-Module (Join-Path $script:VantaTestModulesRoot 'Vanta.Core\Vanta.Core.psd1') -Force
    Import-Module (Join-Path $script:VantaTestModulesRoot 'Vanta.Toggles\Vanta.Toggles.psd1') -Force
    Import-Module (Join-Path $script:VantaTestModulesRoot 'Vanta.Shell\Vanta.Shell.psd1') -Force
    Import-Module (Join-Path $script:VantaTestModulesRoot 'Vanta.Search\Vanta.Search.psd1') -Force
    $script:choiceRoot = Join-Path $script:VantaTestRepoRoot 'package\Executables\VantaModules\Toggles'

    # Runs a state's machine action the way the engine does: with the engine's own
    # $Toggle context, dot-sourced inside Vanta.Toggles under strict mode, so
    # module-scoped mocks apply and a strict-mode failure shows up here too.
    function Invoke-MachineAction {
        param(
            [Parameter(Mandatory = $true)][string]$Toggle,
            [Parameter(Mandatory = $true)][string]$State,
            [bool]$Silent = $true
        )

        $definition = Get-VantaToggleDefinition -Name $Toggle -TogglesRoot $script:choiceRoot
        InModuleScope Vanta.Toggles {
            $context = New-VantaToggleContext -Definition $d -StateName $s -Silent:$silent -StateRoot 'HKCU:\Unused'
            Invoke-VantaToggleFunction -Definition $d -FunctionName ([string]$d['States'][$s]['MachineAction']) `
                -Toggle $context -Label 'test'
        } -Parameters @{ d = $definition; s = $State; silent = $Silent }
    }
}

Describe 'Independent choices survive toggle replay' {
    BeforeEach {
        Mock Write-VantaLog -ModuleName Vanta.Toggles
        Mock Write-VantaStep -ModuleName Vanta.Toggles
        Mock Write-VantaWarning -ModuleName Vanta.Toggles
        Mock Write-VantaSuccess -ModuleName Vanta.Toggles
        Mock Import-VantaModule -ModuleName Vanta.Toggles
        Mock Read-VantaYesNo -ModuleName Vanta.Toggles { throw 'Silent work must not prompt.' }
        Mock Set-VantaRegistryValue -ModuleName Vanta.Toggles
        Mock Remove-VantaRegistryValue -ModuleName Vanta.Toggles
        Mock Set-VantaSettingsPageVisibility -ModuleName Vanta.Toggles
        Mock Get-Service -ModuleName Vanta.Toggles { [pscustomobject]@{ Status = 'Stopped' } }
        Mock Set-VantaIndexingMachineState -ModuleName Vanta.Toggles
        Mock Set-VantaToggleState -ModuleName Vanta.Toggles
    }

    It 'preserves search location and disabled indexing in silent Web Search enable' {
        Invoke-MachineAction -Toggle WebSearch -State Enable
        Should -Invoke Set-VantaRegistryValue -ModuleName Vanta.Toggles -Times 0 -Exactly
        Should -Invoke Remove-VantaRegistryValue -ModuleName Vanta.Toggles -Times 0 -Exactly
        Should -Invoke Set-VantaIndexingMachineState -ModuleName Vanta.Toggles -Times 0 -Exactly
        Should -Invoke Read-VantaYesNo -ModuleName Vanta.Toggles -Times 0 -Exactly
        Should -Invoke Set-VantaToggleState -ModuleName Vanta.Toggles -Times 0 -Exactly
    }

    It 'records indexing only after an explicit successful indexing change' {
        Mock Read-VantaYesNo -ModuleName Vanta.Toggles { $true }
        Invoke-MachineAction -Toggle WebSearch -State Enable -Silent $false
        Should -Invoke Set-VantaIndexingMachineState -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter {
            $State -eq 'Full' -and $PreservePowerModes
        }
        Should -Invoke Set-VantaToggleState -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'Indexing' -and $State -eq 2 -and $StateRoot -ceq 'HKCU:\Unused'
        }
    }

    It 'preserves power-mode handling when full indexing is replayed' {
        Invoke-MachineAction -Toggle Indexing -State Enable
        Should -Invoke Set-VantaIndexingMachineState -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter {
            $State -eq 'Full' -and $PreservePowerModes
        }
        Should -Not -Invoke Read-VantaYesNo -ModuleName Vanta.Toggles
    }

    It 'preserves independent account consumer and Store policies in silent Phone Link enable' {
        $definition = Get-VantaToggleDefinition -Name PhoneLink -TogglesRoot $script:choiceRoot
        @($definition.States.Enable.Registry | Where-Object {
            $_.Name -in @('NoConnectedUser', 'DisableWindowsConsumerFeatures', 'AutoDownload')
        }) | Should -HaveCount 0
        Invoke-MachineAction -Toggle PhoneLink -State Enable
        Should -Invoke Set-VantaRegistryValue -ModuleName Vanta.Toggles -Times 0 -Exactly
        Should -Invoke Remove-VantaRegistryValue -ModuleName Vanta.Toggles -Times 0 -Exactly
        Should -Invoke Read-VantaYesNo -ModuleName Vanta.Toggles -Times 0 -Exactly
    }

    It 'does not change hibernation when its optional change is declined' {
        Mock Read-VantaYesNo -ModuleName Vanta.Toggles { $false }
        Mock Test-Path -ModuleName Vanta.Toggles { $true } -ParameterFilter { $LiteralPath -like '*\powercfg.exe' }
        Mock Invoke-VantaToggleNativeCommand -ModuleName Vanta.Toggles
        Mock Invoke-VantaToggleMachineState -ModuleName Vanta.Toggles
        Invoke-MachineAction -Toggle Sleep -State Disable -Silent $false
        Should -Invoke Read-VantaYesNo -ModuleName Vanta.Toggles -Times 1 -Exactly
        Should -Invoke Invoke-VantaToggleMachineState -ModuleName Vanta.Toggles -Times 0 -Exactly
    }

    It 'does not change broader policies when every Phone Link enable dependency is declined' {
        Mock Read-VantaYesNo -ModuleName Vanta.Toggles { $false }
        Invoke-MachineAction -Toggle PhoneLink -State Enable -Silent $false
        Should -Invoke Read-VantaYesNo -ModuleName Vanta.Toggles -Times 3 -Exactly
        Should -Invoke Set-VantaRegistryValue -ModuleName Vanta.Toggles -Times 0 -Exactly
        Should -Invoke Remove-VantaRegistryValue -ModuleName Vanta.Toggles -Times 0 -Exactly
    }

    It 'does not record indexing if the explicitly requested change fails' {
        Mock Read-VantaYesNo -ModuleName Vanta.Toggles { $true }
        Mock Set-VantaIndexingMachineState -ModuleName Vanta.Toggles { throw 'indexing failed' }
        { Invoke-MachineAction -Toggle WebSearch -State Enable -Silent $false } | Should -Throw '*indexing failed*'
        Should -Invoke Set-VantaToggleState -ModuleName Vanta.Toggles -Times 0 -Exactly
    }

    It 'retains user tracking preferences when recent items are unlocked' {
        $definition = Get-VantaToggleDefinition -Name RecentItems -TogglesRoot $script:choiceRoot
        @($definition.States.Enable.Registry | Where-Object {
            $_.Name -in @('Start_TrackProgs', 'Start_TrackDocs')
        }) | Should -HaveCount 0
    }

    It 'leaves administrator update policies outside the unpause operation' {
        $definition = Get-VantaToggleDefinition -Name PauseUpdates -TogglesRoot $script:choiceRoot
        @($definition.States.Disable.Registry | Where-Object {
            $_.Path -like '*\Policies\Microsoft\Windows\WindowsUpdate'
        }) | Should -HaveCount 0
    }

    It 'rejects old full-network-repair records before resolving any executable work' {
        $definition = Get-VantaToggleDefinition -Name DefaultVantaNetwork -TogglesRoot $script:choiceRoot
        InModuleScope Vanta.Toggles -Parameters @{ root = $script:choiceRoot; definition = $definition } {
            foreach ($state in $definition.States.Values) {
                Test-VantaToggleRecordsState -Definition $definition -StateEntry $state | Should -BeFalse
            }
            Mock Get-ItemProperty { [pscustomobject]@{ state = 0 } }
            Mock Get-VantaToggleReplayDefinition { $definition }
            Mock Get-VantaToggleStateWork { throw 'Network repair must never resolve to replay work.' }
            $key = [pscustomobject]@{ PSPath = 'HKCU:\Unused'; PSChildName = 'DefaultVantaNetwork' }
            $key | Add-Member ScriptMethod GetValueKind {
                param($name)
                if ($name -ne 'state') { throw 'Unexpected registry value queried.' }
                [Microsoft.Win32.RegistryValueKind]::DWord
            }
            try {
                Resolve-VantaToggleReplayRecord -Subkey $key -TogglesRoot $root
                throw 'Expected a stale record.'
            }
            catch {
                $_.Exception.Data['VantaToggleReplayRecordDisposition'] | Should -BeExactly 'Stale' -Because $_.Exception.Message
            }
            Should -Invoke Get-VantaToggleStateWork -Times 0 -Exactly
        }
    }
}
