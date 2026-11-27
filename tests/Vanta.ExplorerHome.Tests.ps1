Describe 'File Explorer Home configuration' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'VantaTestHost.ps1')
        Import-Module -Name (Join-Path $script:VantaTestModulesRoot 'Vanta.Core\Vanta.Core.psd1') -Force
        Import-Module -Name (Join-Path $script:VantaTestModulesRoot 'Vanta.Toggles\Vanta.Toggles.psd1') -Force
        $script:homeToggle = Get-VantaToggleDefinition -Name Home `
            -TogglesRoot (Join-Path $script:VantaTestRepoRoot 'package\Executables\VantaModules\Toggles')
    }

    It 'round-trips the per-user navigation-tree override in the Home toggle' {
        $pinPath = 'HKCU:\Software\Classes\CLSID\{f874310e-b6b7-47dc-bc84-b9e6b38f5903}'
        $disable = $script:homeToggle.States['Disable']
        $enable = $script:homeToggle.States['Enable']

        $disablePin = @($disable['Registry'] | Where-Object {
                $_.Path -ceq $pinPath -and $_.Name -ceq 'System.IsPinnedToNameSpaceTree'
            })
        $disablePin | Should -HaveCount 1
        $disablePin[0].Type | Should -BeExactly 'DWord'
        $disablePin[0].Data | Should -Be 0

        $enablePin = @($enable['Registry'] | Where-Object {
                $_.Path -ceq $pinPath -and $_.Name -ceq 'System.IsPinnedToNameSpaceTree'
            })
        $enablePin | Should -HaveCount 1
        $enablePin[0].Operation | Should -BeExactly 'Delete'

        # The pin is per-user work beside the machine namespace key, so the engine runs
        # it in the launching user's own process and replays it at first sign-in.
        foreach ($state in @($disable, $enable)) {
            $work = Get-VantaToggleStateWork -Definition $script:homeToggle -StateEntry $state
            $work.Machine | Should -BeTrue
            $work.User | Should -BeTrue
        }
    }
}
