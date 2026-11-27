BeforeAll {
    . (Join-Path $PSScriptRoot 'VantaTestHost.ps1')
    . (Join-Path $script:VantaTestScriptsRoot 'Install\Install-Plan.ps1')
}

Describe 'Vanta install plan' {
    It 'returns the exact ordered <Mode> plan' -TestCases @(
        @{
            Mode = 'Fresh'; Expected = @(
                'Checkpoint/DefaultHiveLoad', 'Checkpoint/PayloadReplacement',
                'Checkpoint/NotificationDisable', 'PreInstall', 'ShellRefresh', 'Environment',
                'Tweak/qol/set-hidden-settings-pages', 'Checkpoint/InitializePath', 'Features', 'Software',
                'Services', 'Components', 'AppxSupport', 'Defaults',
                'Tweaks/networking', 'Tweaks/performance', 'Tweaks/privacy', 'Tweaks/qol',
                'Tweaks/security', 'Tweaks/debloat', 'Tweaks/scripts', 'Tweaks/misc',
                'Tweak/scripts/set-power-settings', 'Checkpoint/WindowsTransition', 'Checkpoint/InstallingUserSetup',
                'Checkpoint/NotificationRestore', 'Checkpoint/DefaultHiveUnload'
            )
        }
        @{
            Mode = 'Upgrade'; Expected = @(
                'Checkpoint/DefaultHiveLoad', 'Checkpoint/PayloadReplacement',
                'Checkpoint/NotificationDisable', 'Checkpoint/LegacyChoices', 'PreInstall', 'ShellRefresh', 'Environment',
                'Checkpoint/InitializePath', 'Features', 'Software', 'Defaults',
                'Tweak/qol/appearance/vanta-theme-upgrade',
                'Tweaks/networking', 'Tweaks/performance', 'Tweaks/privacy', 'Tweaks/qol',
                'Tweaks/security', 'Tweaks/debloat', 'Tweaks/scripts', 'Tweaks/misc',
                'Checkpoint/WindowsTransition', 'Checkpoint/InstallingUserSetup',
                'Checkpoint/NotificationRestore', 'Checkpoint/DefaultHiveUnload'
            )
        }
        @{
            Mode = 'Rebase'; Expected = @(
                'Checkpoint/DefaultHiveLoad', 'Checkpoint/PayloadReplacement',
                'Checkpoint/NotificationDisable', 'Checkpoint/RebaseRecovery', 'Checkpoint/LegacyChoices',
                'PreInstall', 'ShellRefresh', 'Environment',
                'Checkpoint/InitializePath', 'Features', 'Software', 'Services', 'Components', 'AppxSupport', 'Defaults',
                'Tweak/qol/appearance/vanta-theme-upgrade',
                'Tweaks/networking', 'Tweaks/performance', 'Tweaks/privacy', 'Tweaks/qol',
                'Tweaks/security', 'Tweaks/debloat', 'Tweaks/scripts', 'Tweaks/misc',
                'Checkpoint/WindowsTransition', 'Checkpoint/InstallingUserSetup',
                'Checkpoint/NotificationRestore', 'Checkpoint/DefaultHiveUnload'
            )
        }
        # A reinstall of the same version runs the tweak categories and the installing
        # user's setup as well, so a new build's fixes arrive.
        @{
            Mode = 'Reapply'; Expected = @(
                'Checkpoint/DefaultHiveLoad', 'Checkpoint/PayloadReplacement',
                'Checkpoint/NotificationDisable', 'PreInstall', 'ShellRefresh', 'Environment',
                'Checkpoint/InitializePath', 'Features', 'Software', 'Defaults',
                'Tweaks/networking', 'Tweaks/performance', 'Tweaks/privacy', 'Tweaks/qol',
                'Tweaks/security', 'Tweaks/debloat', 'Tweaks/scripts', 'Tweaks/misc',
                'Checkpoint/WindowsTransition', 'Checkpoint/InstallingUserSetup',
                'Checkpoint/NotificationRestore', 'Checkpoint/DefaultHiveUnload'
            )
        }
    ) {
        @((Get-VantaInstallPlan -Mode $Mode).Key) |
            Should -Be $Expected
    }

    It 'adds the Choices step when choosing again on <Mode>' -TestCases @(
        @{
            Mode = 'Upgrade'; Expected = @(
                'Checkpoint/DefaultHiveLoad', 'Checkpoint/PayloadReplacement',
                'Checkpoint/NotificationDisable', 'Checkpoint/LegacyChoices', 'PreInstall', 'ShellRefresh', 'Environment',
                'Checkpoint/InitializePath', 'Features', 'Software', 'Choices', 'Defaults',
                'Tweak/qol/appearance/vanta-theme-upgrade',
                'Tweaks/networking', 'Tweaks/performance', 'Tweaks/privacy', 'Tweaks/qol',
                'Tweaks/security', 'Tweaks/debloat', 'Tweaks/scripts', 'Tweaks/misc',
                'Checkpoint/WindowsTransition', 'Checkpoint/InstallingUserSetup',
                'Checkpoint/NotificationRestore', 'Checkpoint/DefaultHiveUnload'
            )
        }
        @{
            Mode = 'Reapply'; Expected = @(
                'Checkpoint/DefaultHiveLoad', 'Checkpoint/PayloadReplacement',
                'Checkpoint/NotificationDisable', 'PreInstall', 'ShellRefresh', 'Environment',
                'Checkpoint/InitializePath', 'Features', 'Software', 'Choices', 'Defaults',
                'Tweaks/networking', 'Tweaks/performance', 'Tweaks/privacy', 'Tweaks/qol',
                'Tweaks/security', 'Tweaks/debloat', 'Tweaks/scripts', 'Tweaks/misc',
                'Checkpoint/WindowsTransition', 'Checkpoint/InstallingUserSetup',
                'Checkpoint/NotificationRestore', 'Checkpoint/DefaultHiveUnload'
            )
        }
    ) {
        param($Mode, $Expected)
        @((Get-VantaInstallPlan -Mode $Mode -ChooseAgain $true).Key) | Should -Be $Expected
    }

    It 'keeps the <Mode> plan the same with or without choosing again' -TestCases @(
        @{ Mode = 'Fresh' }, @{ Mode = 'Rebase' }
    ) {
        param($Mode)
        @((Get-VantaInstallPlan -Mode $Mode -ChooseAgain $true).Key) |
            Should -Be @((Get-VantaInstallPlan -Mode $Mode).Key)
    }

    It 'runs Choices on <Mode> after the legacy choices and the software, and before every replay or tweak' -TestCases @(
        @{ Mode = 'Upgrade' }, @{ Mode = 'Reapply' }
    ) {
        param($Mode)
        # A new browser and the old choices come first; the replay and the tweaks that
        # keep a recorded choice then apply the records Choices writes.
        $keys = @((Get-VantaInstallPlan -Mode $Mode -ChooseAgain $true).Key)
        $choices = [array]::IndexOf($keys, 'Choices')
        $choices | Should -BeGreaterThan -1
        foreach ($earlier in @('Checkpoint/LegacyChoices', 'Software')) {
            if ($keys -contains $earlier) { [array]::IndexOf($keys, $earlier) | Should -BeLessThan $choices -Because $earlier }
        }
        $later = @($keys | Where-Object { $_ -ceq 'Defaults' -or $_.StartsWith('Tweak', [StringComparison]::Ordinal) })
        $later.Count | Should -BeGreaterThan 8
        foreach ($key in $later) {
            [array]::IndexOf($keys, $key) | Should -BeGreaterThan $choices -Because $key
        }
    }

    It 'gives every step its choose-again modes, empty unless it applies the choices' {
        $steps = @(foreach ($mode in 'Fresh', 'Upgrade', 'Reapply', 'Rebase') {
                Get-VantaInstallPlan -Mode $mode -ChooseAgain $true
            }) | Sort-Object Key -Unique
        foreach ($step in $steps) {
            $expected = if ($step.Key -ceq 'Choices') { @('Upgrade', 'Reapply') } else { @() }
            @($step.ChooseAgainModes) | Should -Be $expected -Because $step.Key
        }
        (@($steps | Where-Object Key -ceq 'Choices')[0]).Modes | Should -HaveCount 0 -Because 'only choosing again runs it'
    }

    It 'replays lifecycle checkpoints and file synchronization' {
        $steps = @(
            Get-VantaInstallPlan -Mode Fresh
            Get-VantaInstallPlan -Mode Upgrade
            Get-VantaInstallPlan -Mode Reapply
            Get-VantaInstallPlan -Mode Rebase
            Get-VantaInstallPlan -Mode Upgrade -ChooseAgain $true
            Get-VantaInstallPlan -Mode Reapply -ChooseAgain $true
        ) | Sort-Object Key -Unique

        @($steps | Where-Object Replay -eq Always | ForEach-Object Key) |
            Should -Be @(
                'Checkpoint/DefaultHiveLoad',
                'Checkpoint/DefaultHiveUnload',
                'Checkpoint/NotificationDisable',
                'Checkpoint/NotificationRestore',
                'Checkpoint/PayloadReplacement'
            )
        foreach ($step in $steps) {
            $step.Replay | Should -BeIn @('Once', 'Always') -Because $step.Key
        }
    }

    It 'captures legacy choices before any phase or tweak runs on upgrade, choosing again <ChooseAgain>' -TestCases @(
        @{ ChooseAgain = $false }
        @{ ChooseAgain = $true }
    ) {
        # The capture reads the live registry, so anything that writes defaults first
        # erases the evidence of the user's earlier choices.
        $keys = @((Get-VantaInstallPlan -Mode Upgrade -ChooseAgain $ChooseAgain).Key)
        $capture = [array]::IndexOf($keys, 'Checkpoint/LegacyChoices')
        $capture | Should -BeGreaterThan -1
        foreach ($key in $keys | Where-Object { -not $_.StartsWith('Checkpoint/', [StringComparison]::Ordinal) }) {
            [array]::IndexOf($keys, $key) | Should -BeGreaterThan $capture -Because $key
        }
    }
}
