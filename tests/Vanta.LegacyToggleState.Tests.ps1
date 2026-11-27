BeforeAll {
    . (Join-Path $PSScriptRoot 'VantaTestHost.ps1')
    Import-Module (Join-Path $script:VantaTestModulesRoot 'Vanta.Toggles\Vanta.Toggles.psd1') -Force
}

Describe 'Legacy toggle migration' {
    BeforeEach {
        $script:LegacyRoot = 'HKCU:\Software\VantaRewriteTest\LegacyToggleMigration'
        New-Item -Path $script:LegacyRoot -Force | Out-Null
    }
    AfterEach {
        Remove-Item -LiteralPath $script:LegacyRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Historical inputs from the 0.5.0-hotfix launchers (6cbd1a34), not current
    # definitions: several launchers wrote the same value for opposite choices.
    It 'preserves <Name> from legacy <Launcher>' -ForEach @(
        @{ Name = 'LockScreen'; Value = 1; Launcher = 'Hide Lock Screen.cmd'; Expected = 0 }
        @{ Name = 'LockScreen'; Value = 1; Launcher = 'Show Lock Screen (default).cmd'; Expected = 1 }
        @{ Name = 'HideAppBrowserControl'; Value = 0; Launcher = 'Show App and Browser Control.cmd'; Expected = 1 }
        @{ Name = 'HideAppBrowserControl'; Value = 0; Launcher = 'Hide App and Browser Control (default).cmd'; Expected = 0 }
        @{ Name = 'VbsState'; Value = 0; Launcher = 'Enable VBS.cmd'; Expected = 1 }
        @{ Name = 'VbsState'; Value = 0; Launcher = 'Disable VBS.cmd'; Expected = 0 }
        @{ Name = 'ContextMenuTerminals'; Value = 0; Launcher = 'Add Terminals.cmd'; Expected = 1 }
        @{ Name = 'ContextMenuTerminals'; Value = 1; Launcher = 'Add Terminals (no Windows Terminal).cmd'; Expected = 2 }
        @{ Name = 'ContextMenuTerminals'; Value = 0; Launcher = 'Remove Terminals Context Menu (default).cmd'; Expected = 0 }
    ) {
        InModuleScope Vanta.Toggles -Parameters @{ Root = $script:LegacyRoot; Name = $Name; Value = $Value; Launcher = $Launcher; Expected = $Expected } {
            param($Root, $Name, $Value, $Launcher, $Expected)
            Mock Get-VantaLegacyToggleObservedState { $null }
            $path = Join-Path $Root $Name
            New-Item -Path $path -Force | Out-Null
            New-ItemProperty -LiteralPath $path -Name state -Value $Value -PropertyType DWord -Force | Out-Null
            New-ItemProperty -LiteralPath $path -Name path -Value "C:\Windows\VantaDesktop\$Launcher" -PropertyType String -Force | Out-Null
            Initialize-VantaToggleStateStore -StateRoot $Root
            (Get-VantaToggleState -Name $Name -StateRoot $Root).State | Should -Be $Expected
            @((Get-Item -LiteralPath $path).GetValueNames()) | Should -Not -Contain path
            Initialize-VantaToggleStateStore -StateRoot $Root
            (Get-VantaToggleState -Name $Name -StateRoot $Root).State | Should -Be $Expected
        }
    }

    It 'keeps a later Toolbox <Name> choice despite its stale launcher path' -ForEach @(
        @{ Name = 'VbsState'; Value = 0; Launcher = 'Enable VBS.cmd'; Observed = 0 }
        @{ Name = 'ContextMenuTerminals'; Value = 0; Launcher = 'Add Terminals.cmd'; Observed = 0 }
        @{ Name = 'ContextMenuTerminals'; Value = 2; Launcher = 'Add Terminals.cmd'; Observed = 2 }
        @{ Name = 'OldContextMenu'; Value = 0; Launcher = 'Old Context Menu (default).cmd'; Observed = 0 }
    ) {
        InModuleScope Vanta.Toggles -Parameters @{ Root = $script:LegacyRoot; Name = $Name; Value = $Value; Launcher = $Launcher; Observed = $Observed } {
            param($Root, $Name, $Value, $Launcher, $Observed)
            Mock Get-VantaLegacyToggleObservedState { $Observed }
            $path = Join-Path $Root $Name
            New-Item -Path $path -Force | Out-Null
            New-ItemProperty -LiteralPath $path -Name state -Value $Value -PropertyType DWord -Force | Out-Null
            New-ItemProperty -LiteralPath $path -Name path -Value "C:\Windows\VantaDesktop\$Launcher" -PropertyType String -Force | Out-Null
            Initialize-VantaToggleStateStore -StateRoot $Root
            (Get-VantaToggleState -Name $Name -StateRoot $Root).State | Should -Be $Observed
        }
    }

    It 'moves either old verbose-message name without losing its choice' -ForEach @(
        @{ Value = 0 }
        @{ Value = 1 }
    ) {
        Set-VantaToggleState -Name VerboseStatusMessage -State $Value -StateRoot $script:LegacyRoot
        Initialize-VantaToggleStateStore -StateRoot $script:LegacyRoot
        (Get-VantaToggleState -Name VerboseMessages -StateRoot $script:LegacyRoot).State | Should -Be $Value
        Get-VantaToggleState -Name VerboseStatusMessage -StateRoot $script:LegacyRoot | Should -BeNullOrEmpty
    }

    It 'resolves two legacy verbose records using the last applied policy' -ForEach @(
        @{ Observed = 0 }
        @{ Observed = 1 }
    ) {
        InModuleScope Vanta.Toggles -Parameters @{ Root = $script:LegacyRoot; Observed = $Observed } {
            param($Root, $Observed)
            Mock Get-VantaLegacyToggleObservedState { $Observed }
            Set-VantaToggleState -Name VerboseStatusMessage -State 1 -StateRoot $Root
            Set-VantaToggleState -Name VerboseMessages -State 1 -StateRoot $Root
            New-ItemProperty -LiteralPath (Join-Path $Root VerboseMessages) -Name path -Value 'C:\Windows\VantaDesktop\Disable Verbose Messages (default).cmd' -PropertyType String | Out-Null
            Initialize-VantaToggleStateStore -StateRoot $Root
            (Get-VantaToggleState -Name VerboseMessages -StateRoot $Root).State | Should -Be $Observed
        }
    }

    It 'moves the CPU menu choice and recovers the actual automatic-update policy' -ForEach @(
        @{ Launcher = 'Add Idle Toggle in Desktop Context Menu.cmd'; Expected = 1 }
        @{ Launcher = 'Remove Idle Toggle in Desktop Context Menu (default).cmd'; Expected = 0 }
    ) {
        InModuleScope Vanta.Toggles -Parameters @{ Root = $script:LegacyRoot; Launcher = $Launcher; Expected = $Expected } {
            param($Root, $Launcher, $Expected)
            Mock Get-VantaLegacyToggleObservedState { 0 } -ParameterFilter { $Name -eq 'AutomaticUpdates' }
            Set-VantaToggleState -Name AutomaticUpdates -State 1 -StateRoot $Root
            New-ItemProperty -LiteralPath (Join-Path $Root AutomaticUpdates) -Name path -Value "C:\Windows\VantaDesktop\$Launcher" -PropertyType String | Out-Null
            New-ItemProperty -LiteralPath (Join-Path $Root AutomaticUpdates) -Name extra -Value 'keep' -PropertyType String | Out-Null
            Initialize-VantaToggleStateStore -StateRoot $Root
            (Get-VantaToggleState -Name CpuIdleContextMenu -StateRoot $Root).State | Should -Be $Expected
            (Get-VantaToggleState -Name AutomaticUpdates -StateRoot $Root).State | Should -Be 0
            (Get-ItemProperty -LiteralPath (Join-Path $Root AutomaticUpdates)).extra | Should -Be 'keep'
        }
    }

    It 'keeps every current recorded state unchanged without a legacy path' {
        $definitions = Get-ChildItem (Join-Path $script:VantaTestRepoRoot 'package\Executables\VantaModules\Toggles') -Recurse -Filter '*.psd1'
        foreach ($file in $definitions) {
            $definition = Import-PowerShellDataFile $file.FullName
            foreach ($state in $definition.States) {
                if (-not $state.ContainsKey('StateValue')) { continue }
                Set-VantaToggleState -Name $definition.Name -State $state.StateValue -StateRoot $script:LegacyRoot
                Initialize-VantaToggleStateStore -StateRoot $script:LegacyRoot
                (Get-VantaToggleState -Name $definition.Name -StateRoot $script:LegacyRoot).State | Should -Be $state.StateValue -Because "$($definition.Name)/$($state.Name)"
            }
        }
    }

    It 'keeps a modern canonical choice when an old alias survives' {
        Set-VantaToggleState -Name VerboseMessages -State 0 -StateRoot $script:LegacyRoot
        Set-VantaToggleState -Name VerboseStatusMessage -State 1 -StateRoot $script:LegacyRoot
        Initialize-VantaToggleStateStore -StateRoot $script:LegacyRoot
        (Get-VantaToggleState -Name VerboseMessages -StateRoot $script:LegacyRoot).State | Should -Be 0
        Get-VantaToggleState -Name VerboseStatusMessage -StateRoot $script:LegacyRoot | Should -BeNullOrEmpty
    }

    It 'skips a saved NVIDIA menu choice when its driver has been removed' {
        InModuleScope Vanta.Toggles -Parameters @{ Root = $script:LegacyRoot; TogglesRoot = (Join-Path $script:VantaTestRepoRoot 'package\Executables\VantaModules\Toggles') } {
            param($Root, $TogglesRoot)
            Mock Assert-VantaPrivilege {}
            Mock Test-Path { $false } -ParameterFilter { $LiteralPath -eq 'HKLM:\SYSTEM\CurrentControlSet\Services\NVDisplay.ContainerLocalSystem' }
            Mock Invoke-VantaToggleInProcess { throw 'No menu work should run without the driver.' }
            Set-VantaToggleState -Name NVidiaDisplayContainerContextMenu -State 1 -StateRoot $Root
            $replayArguments = @{ StateRoot = $Root; TogglesRoot = $TogglesRoot }
            { Invoke-VantaToggleReapply @replayArguments } | Should -Not -Throw
            Get-VantaToggleState -Name NVidiaDisplayContainerContextMenu -StateRoot $Root | Should -BeNullOrEmpty
            Should -Invoke Invoke-VantaToggleInProcess -Times 0
        }
    }

    It 'ignores unknown paths, invalid values and non-DWORD legacy state' {
        foreach ($record in @(
            @{ Name = 'LockScreen'; Value = 1; Kind = 'DWord'; Launcher = 'unknown.cmd' }
            @{ Name = 'LockScreen'; Value = 9; Kind = 'DWord'; Launcher = 'Hide Lock Screen.cmd' }
            @{ Name = 'VbsState'; Value = '0'; Kind = 'String'; Launcher = 'Enable VBS.cmd' }
        )) {
            $path = Join-Path $script:LegacyRoot $record.Name
            New-Item -Path $path -Force | Out-Null
            New-ItemProperty -LiteralPath $path -Name state -Value $record.Value -PropertyType $record.Kind -Force | Out-Null
            New-ItemProperty -LiteralPath $path -Name path -Value "C:\Untrusted\$($record.Launcher)" -PropertyType String -Force | Out-Null
            Initialize-VantaToggleStateStore -StateRoot $script:LegacyRoot
            (Get-ItemProperty -LiteralPath $path).state | Should -Be $record.Value
            Remove-Item -LiteralPath $path -Recurse -Force
        }
    }
}
