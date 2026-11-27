BeforeAll {
    . (Join-Path $PSScriptRoot 'VantaTestHost.ps1')
}

Describe 'File Explorer runtime error repair' {
    It 'removes the same machine search redirects as the install tweak' {
        $tweak = Import-PowerShellDataFile -LiteralPath (Join-Path $script:VantaTestScriptsRoot 'Tweaks\qol\explorer\classic-search.psd1')
        $toggle = Import-PowerShellDataFile -LiteralPath (Join-Path $script:VantaTestRepoRoot `
                'package\Executables\VantaModules\Toggles\Troubleshooting\FixExplorerRuntimeError.psd1')

        $machine = @($tweak.Registry | Where-Object { $_.Path -like 'HKLM:\*' } |
                ForEach-Object { '{0}|{1}' -f $_.Path, $_.Operation })
        $machine.Count | Should -BeGreaterThan 0
        @($toggle.States[0].Registry | ForEach-Object { '{0}|{1}' -f $_.Path, $_.Operation }) |
            Should -Be $machine
    }
}
