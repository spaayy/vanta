BeforeAll {
    . (Join-Path $PSScriptRoot 'VantaTestHost.ps1')
    foreach ($module in 'Vanta.Core', 'Vanta.Registry', 'Vanta.Toggles', 'Vanta.Tweaks') {
        Import-Module (Join-Path $script:VantaTestModulesRoot "$module\$module.psd1") -Force
    }
    $script:choiceContext = [pscustomobject]@{
        IsArm64 = $false; WindowsBuild = 26200; IsUpgrade = $false
        IsInstallStateBacked = $true; Options = @()
    }
    $script:choiceFile = Join-Path $TestDrive 'choice.psd1'
    $healthPath = Join-Path $script:VantaTestScriptsRoot 'Entry\Test-VantaHealth.ps1'
    $healthAst = [System.Management.Automation.Language.Parser]::ParseFile($healthPath, [ref]$null, [ref]$null)
    foreach ($functionName in 'Get-VantaHealthReport', 'Get-VantaHealthStandaloneTweakPath') {
        $function = $healthAst.Find({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName
        }, $false)
        . ([scriptblock]::Create($function.Extent.Text))
    }
    $script:healthDocument = [pscustomobject]@{
        installedVersion = 'test'; installedAt = 'test'; mode = 'Reapply'
        options = @(); history = @(); toggles = [pscustomobject]@{}
    }
    @'
@{
    Name = 'Choice fixture'
    Registry = @(
        @{ Path = 'HKLM\SOFTWARE\VantaHealthFixture'; Name = 'Location'; Type = 'String'; Data = 'Deny'; VerifyWithToggle = @{ Name = 'Location'; State = 1; Type = 'String'; Data = 'Allow' } }
        @{ Path = 'HKLM\SOFTWARE\VantaHealthFixture'; Name = 'Copilot'; Type = 'DWord'; Data = 1; VerifyWithToggle = @{ Name = 'Copilot'; State = 1; Operation = 'Delete' } }
        @{ Path = 'HKLM\SOFTWARE\VantaHealthFixture'; Name = 'Unrelated'; Type = 'String'; Data = 'Deny' }
    )
}
'@ | Set-Content -LiteralPath $script:choiceFile
}

Describe 'Health expectations for explicitly applied machine choices' {
    BeforeEach {
        Mock -ModuleName Vanta.Registry Get-VantaRegistryValueState {
            param($Name)
            switch ($Name) {
                'Location' { [pscustomobject]@{ KeyExists = $true; ValueExists = $true; Kind = 'String'; Data = 'Allow' } }
                'Copilot' { [pscustomobject]@{ KeyExists = $true; ValueExists = $false; Kind = $null; Data = $null } }
                'Unrelated' { [pscustomobject]@{ KeyExists = $true; ValueExists = $true; Kind = 'String'; Data = 'Deny' } }
            }
        }
    }

    It 'returns an empty table when no toggle state was recorded' {
        $records = Get-VantaToggleStateRecords -StateRoot (Join-Path $TestDrive 'missing-state')
        $records | Should -BeOfType [hashtable]
        $records.Count | Should -Be 0
    }

    It 'builds the entry-point report using public commands and forwards the recorded choices' {
        Mock Test-VantaToggleDrift { @() }
        Mock Get-VantaToggleStateRecords { @{ Location = 1; Copilot = 1 } }
        Mock Test-VantaTweakCategory { @() }
        Mock Test-VantaTweakCategory -ParameterFilter { $RegistryScope -eq 'CurrentUser' } {
            [pscustomobject]@{ Tweak = 'user-fixture'; Kind = 'Registry'; Target = 'HKCU\Fixture'; Reason = 'value is missing' }
        }
        $report = Get-VantaHealthReport -Context $script:choiceContext -Document $script:healthDocument -Categories privacy
        $report.healthy | Should -BeFalse
        @($report.tweakDrift).Count | Should -Be 1
        $report.tweakDrift[0].Tweak | Should -Be 'user-fixture'
        Should -Invoke Get-VantaToggleStateRecords -Times 1 -Exactly
        Should -Invoke Test-VantaToggleDrift -Times 1 -Exactly -ParameterFilter {
            @($Scope) -contains 'Machine' -and @($Scope) -contains 'User'
        }
        Should -Invoke Test-VantaTweakCategory -Times 3 -Exactly
        foreach ($scope in 'Machine', 'ProtectedCurrentUser', 'CurrentUser') {
            Should -Invoke Test-VantaTweakCategory -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'privacy' -and $RegistryScope -ceq $scope -and
                $RecordedToggleStates.Location -eq 1 -and $RecordedToggleStates.Copilot -eq 1
            }
        }
    }

    It 'is not healthy when only a recorded toggle state drifted' {
        Mock Test-VantaToggleDrift {
            [pscustomobject]@{ Toggle = 'Location'; State = 1; Scope = 'Machine'; Kind = 'Registry'; Target = 'HKLM\Fixture'; Reason = 'value data differs' }
        }
        Mock Get-VantaToggleStateRecords { @{} }
        Mock Test-VantaTweakCategory { @() }
        $report = Get-VantaHealthReport -Context $script:choiceContext -Document $script:healthDocument -Categories privacy
        $report.healthy | Should -BeFalse
        @($report.toggleDrift).Count | Should -Be 1
        @($report.tweakDrift).Count | Should -Be 0
    }

    It 'checks the Standalone tweaks the install plan ran, in machine scope with the recorded choices' {
        $manifest = @{ Standalone = @(
                @{ Slug = 'scripts/fresh-only'; ParentModes = @('Fresh') }
                @{ Slug = 'qol/nested/upgrade-only'; ParentModes = @('Upgrade') }
            ) }
        $root = Join-Path $TestDrive 'Tweaks'
        @(Get-VantaHealthStandaloneTweakPath -Context $script:choiceContext -Manifest $manifest -TweaksRoot $root) |
            Should -Be @(Join-Path $root 'scripts\fresh-only.psd1')
        $upgraded = $script:choiceContext.PSObject.Copy()
        $upgraded.IsUpgrade = $true
        @(Get-VantaHealthStandaloneTweakPath -Context $upgraded -Manifest $manifest -TweaksRoot $root) |
            Should -Be @(Join-Path $root 'qol\nested\upgrade-only.psd1')

        # The fixture's HKLM entries drift only when read in machine scope.
        Mock Test-VantaToggleDrift { @() }
        Mock Test-VantaTweakCategory { @() }
        Mock Get-VantaToggleStateRecords { @{} }
        $report = Get-VantaHealthReport -Context $script:choiceContext -Document $script:healthDocument -Categories privacy `
            -StandaloneTweakPaths $script:choiceFile
        $report.healthy | Should -BeFalse
        @($report.tweakDrift | Where-Object Tweak -eq 'Choice fixture').Count | Should -Be 2

        Mock Get-VantaToggleStateRecords { @{ Location = 1; Copilot = 1 } }
        $report = Get-VantaHealthReport -Context $script:choiceContext -Document $script:healthDocument -Categories privacy `
            -StandaloneTweakPaths $script:choiceFile
        $report.healthy | Should -BeTrue
    }

    It 'reports <Expected> drifted values when the recorded choices are <Label>' -TestCases @(
        @{ Label = 'absent'; Recorded = @{}; Expected = 2 }
        @{ Label = 'enabled'; Recorded = @{ Location = 1; Copilot = 1 }; Expected = 0 }
        @{ Label = 'in another state'; Recorded = @{ Location = 0; Copilot = 0 }; Expected = 2 }
    ) {
        $drift = @(Test-VantaTweak -Path $script:choiceFile -Context $script:choiceContext -RecordedToggleStates $Recorded)
        $drift.Count | Should -Be $Expected
        if ($Expected) {
            @($drift.Reason) | Should -Contain 'value data differs'
            @($drift.Reason) | Should -Contain 'value is missing'
        }
    }

    It 'still detects a wrong override value and unrelated drift' {
        Mock -ModuleName Vanta.Registry Get-VantaRegistryValueState {
            [pscustomobject]@{ KeyExists = $true; ValueExists = $true; Kind = 'String'; Data = 'Wrong' }
        }
        $drift = @(Test-VantaTweak -Path $script:choiceFile -Context $script:choiceContext -RecordedToggleStates @{ Location = 1; Copilot = 1 })
        $drift.Count | Should -Be 3
        ($drift | Where-Object Target -like '*\Copilot').Reason | Should -Be 'value still exists'
    }

    It 'passes recorded choices through manifest category verification' {
        $root = Join-Path $TestDrive 'tree'
        New-Item (Join-Path $root 'Cat') -ItemType Directory -Force | Out-Null
        Copy-Item $script:choiceFile (Join-Path $root 'Cat\choice.psd1')
        "@{ Categories = @( @{ Name = 'Cat'; Tweaks = @('choice') } ) }" | Set-Content (Join-Path $root 'tweaks.manifest.psd1')
        @(Test-VantaTweakCategory -Name Cat -TweaksRoot $root -Context $script:choiceContext -RecordedToggleStates @{ Location = 1; Copilot = 1 }).Count | Should -Be 0
    }

    It 'validates the supported override declarations' {
        @(Test-VantaTweakSchema -Path $script:choiceFile).Count | Should -Be 0
    }

    It 'rejects malformed or scope-ambiguous override metadata' -TestCases @(
        @{ Replacement = "VerifyWithToggle = 'Location'" }
        @{ Replacement = "VerifyWithToggle = @{ Name = 'Location'; State = '1'; Type = 'String'; Data = 'Allow' }" }
        @{ Replacement = "VerifyWithToggle = @{ Name = 'Location'; State = 1; Operation = 'DeleteKey' }" }
        @{ Replacement = "VerifyWithToggle = @{ Name = 'Location'; State = 1; Type = 'String' }" }
        @{ Replacement = "SkipVerification = 'Ignore'; VerifyWithToggle = @{ Name = 'Location'; State = 1; Type = 'String'; Data = 'Allow' }" }
    ) {
        param($Replacement)
        $invalid = Join-Path $TestDrive 'invalid.psd1'
        (Get-Content $script:choiceFile -Raw).Replace("VerifyWithToggle = @{ Name = 'Location'; State = 1; Type = 'String'; Data = 'Allow' }", $Replacement) | Set-Content $invalid
        (@(Test-VantaTweakSchema -Path $invalid).Problem -join "`n") | Should -BeLike '*VerifyWithToggle*'
    }

    It 'verifies a replayed current-user choice in the requested user scope' {
        $userFile = Join-Path $TestDrive 'user.psd1'
        (Get-Content $script:choiceFile -Raw).Replace('HKLM\', 'HKCU\') | Set-Content $userFile
        @(Test-VantaTweakSchema -Path $userFile).Count | Should -Be 0
        @(Test-VantaTweak -Path $userFile -RegistryScope CurrentUser -Context $script:choiceContext).Count | Should -Be 2
        @(Test-VantaTweak -Path $userFile -RegistryScope CurrentUser -Context $script:choiceContext -RecordedToggleStates @{ Location = 1; Copilot = 1 }).Count | Should -Be 0
        Should -Invoke -ModuleName Vanta.Registry Get-VantaRegistryValueState -ParameterFilter { $Path -like 'HKLM*' } -Times 0 -Exactly
    }

    It 'rejects an override on a registry scope health cannot verify' {
        # The default-user hive is a valid tweak target, so only the override rule rejects this.
        $invalid = Join-Path $TestDrive 'default-user.psd1'
        (Get-Content $script:choiceFile -Raw).Replace(
            "Path = 'HKLM\SOFTWARE\VantaHealthFixture'; Name = 'Location'",
            "Path = 'HKU\Vanta_DefaultUser\SOFTWARE\VantaHealthFixture'; Name = 'Location'") | Set-Content $invalid
        (@(Test-VantaTweakSchema -Path $invalid).Problem -join "`n") | Should -BeLike '*VerifyWithToggle*'
    }
}
