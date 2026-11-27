BeforeAll {
    . (Join-Path $PSScriptRoot 'VantaTestHost.ps1')
    $script:executablesRoot = Join-Path -Path $PSScriptRoot -ChildPath '..\package\Executables'
}

Describe 'CBS package hash manifest stays in lockstep with the included CABs' {
    # Assert-VantaCbsHash checks every CAB against this manifest before install, so a stale
    # entry would reject the real package on every machine.
    It 'records the correct SHA256 for every included .cab and lists no stale entries' {
        $pkgDir = Join-Path -Path $script:executablesRoot -ChildPath 'VantaModules\Packages'
        $manifestPath = Join-Path -Path $pkgDir -ChildPath 'Vanta-CbsHashes.psd1'
        # The repository carries no CAB (the personal build adds its own at build time): nothing to compare.
        if (-not (Test-Path -LiteralPath $pkgDir)) { return }
        Test-Path -LiteralPath $manifestPath -PathType Leaf | Should -BeTrue
        $manifest = Import-PowerShellDataFile -LiteralPath $manifestPath

        $cabs = @(Get-ChildItem -LiteralPath $pkgDir -Filter '*.cab' -File)
        $cabs.Count | Should -BeGreaterThan 0

        foreach ($cab in $cabs) {
            $manifest.Keys | Should -Contain $cab.Name
            (Get-FileHash -LiteralPath $cab.FullName -Algorithm SHA256).Hash | Should -Be $manifest[$cab.Name]
        }
        foreach ($listed in $manifest.Keys) {
            $cabs.Name | Should -Contain $listed
        }
    }
}
