BeforeAll {
    . (Join-Path $PSScriptRoot 'VantaTestHost.ps1')
    foreach ($module in 'Vanta.Core', 'Vanta.Registry', 'Vanta.Toggles', 'Vanta.Tweaks') {
        Import-Module (Join-Path $script:VantaTestModulesRoot "$module\$module.psd1") -Force
    }
    $script:vantaModulesRoot = Split-Path -Parent $script:VantaTestScriptsRoot
    $script:fileSharing = Get-VantaToggleDefinition -Name FileSharing -TogglesRoot (Join-Path $script:vantaModulesRoot 'Toggles')

    # Runs the Enable user action the way the engine does: with the engine's own
    # $Toggle context, dot-sourced inside Vanta.Toggles under strict mode.
    function Invoke-NetworkPaneChoice {
        param([bool]$Silent)

        InModuleScope Vanta.Toggles {
            $context = New-VantaToggleContext -Definition $d -StateName 'Enable' -Silent:$silent -StateRoot 'HKCU:\TestState'
            Invoke-VantaToggleFunction -Definition $d -FunctionName ([string]$d['States']['Enable']['UserAction']) `
                -Toggle $context -Label 'test'
        } -Parameters @{ d = $script:fileSharing; silent = $Silent }
    }
}

Describe 'Independent Explorer Network choice' {
    BeforeEach {
        Mock Read-VantaYesNo -ModuleName Vanta.Toggles { $false }
        Mock Invoke-VantaToggle -ModuleName Vanta.Toggles {}
    }

    It 'does not change visibility during service replay or when the optional choice is declined' {
        Invoke-NetworkPaneChoice -Silent $true
        Should -Invoke Read-VantaYesNo -ModuleName Vanta.Toggles -Times 0 -Exactly
        Invoke-NetworkPaneChoice -Silent $false
        Should -Invoke Read-VantaYesNo -ModuleName Vanta.Toggles -Times 1 -Exactly
        Should -Invoke Invoke-VantaToggle -ModuleName Vanta.Toggles -Times 0 -Exactly
    }

    It 'uses the recording and replay owner when the user requests Network visibility' {
        Mock Read-VantaYesNo -ModuleName Vanta.Toggles { $true }
        Invoke-NetworkPaneChoice -Silent $false
        Should -Invoke Invoke-VantaToggle -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter {
            $Name -ceq 'NetworkNavigationPane' -and $State -ceq 'Enable' -and $StateRoot -eq 'HKCU:\TestState' -and $NoExplorerRestart -and $DeferPostAction
        }
    }

    It 'keeps the fresh hidden default and detects a failed explicit visibility choice' {
        $path = Join-Path $script:VantaTestScriptsRoot 'Tweaks\qol\explorer\disable-network-navigation-pane.psd1'
        $togglesRoot = Join-Path $script:vantaModulesRoot 'Toggles'
        # Tweak verification looks up recorded toggles under %windir%\VantaModules by
        # default, so the test supplies the package's own definition.
        $script:networkPane = Get-VantaToggleDefinition -Name NetworkNavigationPane -TogglesRoot $togglesRoot
        Mock -ModuleName Vanta.Tweaks Get-VantaToggleDefinition { $script:networkPane } -ParameterFilter { $Name -ceq 'NetworkNavigationPane' }
        Mock -ModuleName Vanta.Tweaks Get-VantaToggleDefinition { throw "No toggle definition named '$Name' was found." }
        Mock -ModuleName Vanta.Toggles Get-VantaToggleStateRecords { @{ NetworkNavigationPane = 1 } }
        Mock -ModuleName Vanta.Registry Get-VantaRegistryValueState {
            [pscustomobject]@{ KeyExists = $true; ValueExists = $true; Kind = 'DWord'; Data = 0 }
        }
        $context = [pscustomobject]@{ IsArm64 = $false; WindowsBuild = 26200; IsUpgrade = $false; Options = @() }
        @(Test-VantaTweak -Path $path -RegistryScope CurrentUser -Context $context).Count | Should -Be 0

        # The recorded choice owns the value, so tweak verification leaves it to the
        # toggle, which finds Network still hidden.
        @(Test-VantaTweak -Path $path -RegistryScope CurrentUser -Context $context -RecordedToggleStates @{ NetworkNavigationPane = 1 }).Count | Should -Be 0
        $toggleDrift = @(Test-VantaToggleDrift -Scope User -TogglesRoot $togglesRoot)
        $toggleDrift.Count | Should -Be 1
        $toggleDrift[0].Toggle | Should -BeExactly 'NetworkNavigationPane'
        $toggleDrift[0].Reason | Should -Be 'value still exists'

        # Without a loadable definition, VerifyWithToggle still expects the recorded choice.
        Mock -ModuleName Vanta.Tweaks Get-VantaToggleDefinition { throw "No toggle definition named '$Name' was found." } -ParameterFilter { $Name -ceq 'NetworkNavigationPane' }
        $drift = @(Test-VantaTweak -Path $path -RegistryScope CurrentUser -Context $context -RecordedToggleStates @{ NetworkNavigationPane = 1 })
        $drift.Count | Should -Be 1
        $drift[0].Reason | Should -Be 'value still exists'

        Mock -ModuleName Vanta.Registry Get-VantaRegistryValueState {
            [pscustomobject]@{ KeyExists = $true; ValueExists = $false; Kind = $null; Data = $null }
        }
        @(Test-VantaTweak -Path $path -RegistryScope CurrentUser -Context $context -RecordedToggleStates @{ NetworkNavigationPane = 1 }).Count | Should -Be 0
        @(Test-VantaToggleDrift -Scope User -TogglesRoot $togglesRoot).Count | Should -Be 0
    }
}
