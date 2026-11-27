# Run with PowerShell 7; fixtures never use the real Cargo cache or dependency files.
Describe 'Dependency notice release gate' {
BeforeAll {
    $script:exporter = Join-Path $PSScriptRoot '../Export-DependencyNotices.ps1'
}
AfterAll { Remove-Item Function:script:cargo -ErrorAction SilentlyContinue }
BeforeEach {
    $script:fixture = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
    $package = Join-Path $fixture 'package'
    New-Item -ItemType Directory -Force "$fixture/licenses", "$package/nested" | Out-Null
    Set-Content "$fixture/Cargo.lock" 'fixture lock'
    Set-Content "$fixture/licenses/supplements.json" '[]'
    Set-Content "$package/LICENSE" ('Permission and copyright fixture. ' * 4)
    Set-Content "$package/nested/LICENSE-other" ('Additional bundled code notice. ' * 4)
    $metadata = @{ packages = @(@{ name = 'fixture'; version = '1.0.0'; manifest_path = "$package/Cargo.toml"; source = 'registry+fixture'; license = 'MIT'; repository = 'https://example.invalid/fixture' }) } | ConvertTo-Json -Depth 5
    # Capture fixture data lexically: the exporter runs in a child script scope.
    $cargoStub = {
        if ($args[0] -eq 'metadata') { return $metadata }
        return 'fixture v1.0.0'
    }.GetNewClosure()
    Set-Item Function:script:cargo -Value $cargoStub
    $script:LASTEXITCODE = 0
}
    It 'collects nested notices and reproduces the checked output' {
        & $exporter -AppDirectory $fixture
        { & $exporter -AppDirectory $fixture -Check } | Should -Not -Throw
        $inventory = Get-Content "$fixture/licenses/dependency-inventory.json" -Raw | ConvertFrom-Json
        $inventory.packages[0].notices.Count | Should -Be 2
        $inventory.packages[0].normalWindowsDependency | Should -BeTrue
    }
    It 'rejects a stale generated distribution notice' {
        & $exporter -AppDirectory $fixture
        Add-Content "$fixture/licenses/THIRD-PARTY-NOTICES.txt" 'altered'
        { & $exporter -AppDirectory $fixture -Check } | Should -Throw '*Stale dependency notices*'
    }
    It 'retains short copyright notices rather than using a length heuristic' {
        Set-Content "$fixture/package/NOTICE" 'Copyright 2026 Example Authors.'
        & $exporter -AppDirectory $fixture
        $text = Get-Content "$fixture/licenses/THIRD-PARTY-NOTICES.txt" -Raw
        $text | Should -Match 'Copyright 2026 Example Authors\.'
        $inventory = Get-Content "$fixture/licenses/dependency-inventory.json" -Raw | ConvertFrom-Json
        $inventory.packages[0].notices.Count | Should -Be 3
    }
    It 'does not accept a flattened license symlink as license text' {
        Remove-Item "$fixture/package/nested/LICENSE-other"
        Set-Content "$fixture/package/LICENSE" '../LICENSE-MIT'
        & $exporter -AppDirectory $fixture -WarningAction SilentlyContinue
        { & $exporter -AppDirectory $fixture -Check } | Should -Throw '*Unresolved notices*'
    }
    It 'rejects a supplemental notice with a modified hash' {
        Set-Content "$fixture/licenses/supplement.txt" ('Fixture notice ' * 10)
        @(@{ package = 'fixture'; version = '1.0.0'; file = 'supplement.txt'; url = 'https://example.invalid/0123456789012345678901234567890123456789/LICENSE'; sha256 = 'INVALID' }) | ConvertTo-Json | Set-Content "$fixture/licenses/supplements.json"
        { & $exporter -AppDirectory $fixture } | Should -Throw '*Supplement hash mismatch*'
    }
    It 'treats only the three Vanta crates as first party; any other local crate, even inside the repository or app/vendor, is third party' {
        $appDir = Join-Path $fixture 'app'
        New-Item -ItemType Directory -Force "$appDir/licenses", "$fixture/vanta/core", "$fixture/other", "$appDir/vendor/vend", "$appDir/vendor/unlicensed" | Out-Null
        Copy-Item "$fixture/licenses/supplements.json" "$appDir/licenses/"
        Copy-Item "$fixture/Cargo.lock" "$appDir/Cargo.lock"
        Set-Content "$appDir/vendor/vend/LICENSE-MIT" ('Vendored crate licence text. ' * 4)
        $metadata = @{ packages = @(
            @{ name = 'vanta-core'; version = '0.1.0'; manifest_path = "$fixture/vanta/core/Cargo.toml"; source = $null; license = 'GPL-3.0-only'; repository = $null }
            @{ name = 'outsider'; version = '1.0.0'; manifest_path = "$fixture/other/Cargo.toml"; source = $null; license = 'MIT'; repository = $null }
            @{ name = 'vendored'; version = '2.0.0'; manifest_path = "$appDir/vendor/vend/Cargo.toml"; source = $null; license = 'MIT'; repository = $null }
            @{ name = 'vanta-sys'; version = '0.1.0'; manifest_path = "$appDir/vendor/unlicensed/Cargo.toml"; source = $null; license = 'GPL-3.0-only'; repository = $null }
        ) } | ConvertTo-Json -Depth 5
        $cargoStub = { if ($args[0] -eq 'metadata') { return $metadata }; return 'vanta-core v0.1.0 (/x)' }.GetNewClosure()
        Set-Item Function:script:cargo -Value $cargoStub
        & $exporter -AppDirectory $appDir -WarningAction SilentlyContinue
        $inventory = Get-Content "$appDir/licenses/dependency-inventory.json" -Raw | ConvertFrom-Json
        $core = $inventory.packages | Where-Object package -eq 'vanta-core'
        $core.firstParty | Should -BeTrue
        $core.noticeFile | Should -Be 'LICENSE'
        # a Vanta-named crate under app/vendor is NOT first party; neither is an unlisted crate inside the repository
        ($inventory.packages | Where-Object package -eq 'vanta-sys').firstParty | Should -BeNullOrEmpty
        ($inventory.packages | Where-Object package -eq 'outsider').firstParty | Should -BeNullOrEmpty
        ($inventory.packages | Where-Object package -eq 'vendored').notices.Count | Should -Be 1
        (Get-Content "$appDir/licenses/THIRD-PARTY-NOTICES.txt" -Raw) | Should -Match 'Vendored crate licence text'
        # the local crates without a licence file make -Check fail
        $inventory.unresolved | Should -Contain 'outsider 1.0.0'
        $inventory.unresolved | Should -Contain 'vanta-sys 0.1.0'
        $inventory.unresolved | Should -Not -Contain 'vendored 2.0.0'
        { & $exporter -AppDirectory $appDir -Check } | Should -Throw '*Unresolved notices*outsider 1.0.0*'
    }
    It 'adds the checked-in notice of a non-Cargo component and refuses one whose text changed' {
        New-Item -ItemType Directory -Force "$fixture/licenses/supplemental/components" | Out-Null
        $text = Join-Path $fixture 'licenses/supplemental/components/c.txt'
        Set-Content $text ('Component licence text. ' * 4)
        $hash = (Get-FileHash $text -Algorithm SHA256).Hash
        @(@{ name = 'comp'; version = '1'; license = 'MIT'; source = 'somewhere'; file = 'supplemental/components/c.txt'; sha256 = $hash }) | ConvertTo-Json | Set-Content "$fixture/licenses/components.json"
        & $exporter -AppDirectory $fixture
        (Get-Content "$fixture/licenses/THIRD-PARTY-NOTICES.txt" -Raw) | Should -Match 'Component licence text'
        (Get-Content "$fixture/licenses/dependency-inventory.json" -Raw | ConvertFrom-Json).components[0].component | Should -Be 'comp'
        Add-Content $text 'tampered'
        { & $exporter -AppDirectory $fixture } | Should -Throw '*Component notice hash mismatch*'
    }
}
