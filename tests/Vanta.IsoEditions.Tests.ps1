BeforeAll {
    . (Join-Path $PSScriptRoot 'VantaTestHost.ps1')
    $source = Join-Path $script:VantaTestRepoRoot 'app\resources\iso\Build-Iso.ps1'
    $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($source, [ref]$null, [ref]$errors)
    if ($errors) { throw ($errors | Out-String) }
    foreach ($name in @('Fail', 'Get-VantaMediaEditions', 'Export-VantaMediaEditions')) {
        $function = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
        . ([scriptblock]::Create($function.Extent.Text))
    }
    # Owned stubs ensure a failed mock never calls DISM on the host.
    function Get-WindowsImage { param($ImagePath, $Index) throw "Unmocked image query: $ImagePath, $Index" }
    function Export-WindowsImage { param($SourceImagePath, $SourceIndex, $DestinationImagePath, $CompressionType, [switch]$CheckIntegrity, $ErrorAction) throw "Unmocked image export: $SourceImagePath, $SourceIndex, $DestinationImagePath, $CompressionType, $CheckIntegrity, $ErrorAction" }
    function Write-Stage { param($Stage) throw "Unmocked stage: $Stage" }
    function Get-VantaWindowsReleaseStatus { param($Version, [switch]$NoRefresh) throw "Unmocked release query: $Version $NoRefresh" }
    function New-ImageFixture([int]$Index, [string]$Edition) {
        [pscustomobject]@{ImageIndex=$Index; ImageName="Windows 11 $Edition"; EditionId=$Edition; Version='10.0.26200.6584'; Architecture=9; InstallationType='Client'}
    }
}

Describe 'Supported editions in mixed Microsoft media' {
    BeforeEach {
        $script:Images = @((New-ImageFixture 1 Core), (New-ImageFixture 2 CoreSingleLanguage), (New-ImageFixture 3 Professional), (New-ImageFixture 4 ProfessionalN), (New-ImageFixture 5 Education))
        $script:Exported = [Collections.Generic.List[object]]::new()
        Mock Get-WindowsImage {
            param($ImagePath, $Index)
            if ($ImagePath -eq 'source') {
                if ($Index) { $script:Images | Where-Object ImageIndex -eq $Index } else { $script:Images }
            } else {
                if ($Index) { $script:Exported[$Index - 1] } else { $script:Exported }
            }
        }
        Mock Export-WindowsImage {
            param($SourceIndex)
            $original = $script:Images | Where-Object ImageIndex -eq $SourceIndex
            $copy = New-ImageFixture ($script:Exported.Count + 1) $original.EditionId
            $script:Exported.Add($copy)
        }
        Mock Write-Stage {}
        Mock Get-VantaWindowsReleaseStatus { 'Released' }
    }
    It 'keeps every supported edition without selecting a default' {
        $result = @(Get-VantaMediaEditions source @(26200))
        ($result.EditionId -join ',') | Should -Be 'Professional,ProfessionalN,Education'
        ($result.ImageIndex -join ',') | Should -Be '3,4,5'
    }
    It 'accepts supported 26H2 editions and passes their full revision to the release check' {
        foreach ($image in $script:Images) { $image.Version = '10.0.26300.9457' }
        $result = @(Get-VantaMediaEditions source @(26200,26300))
        ($result.EditionId -join ',') | Should -Be 'Professional,ProfessionalN,Education'
        Should -Invoke Get-VantaWindowsReleaseStatus -Times 5 -Exactly -ParameterFilter { $Version -eq [version]'10.0.26300.9457' }
    }
    It 'does not retain Home-only or LTSC media' {
        $script:Images = @((New-ImageFixture 1 Core), (New-ImageFixture 2 EnterpriseS))
        @(Get-VantaMediaEditions source @(26200)) | Should -HaveCount 0
    }
    It 'rejects unidentified editions instead of assuming support' {
        $script:Images[0].EditionId = ''
        { Get-VantaMediaEditions source @(26200) } | Should -Throw '*no edition identity*'
    }
    It 'rejects a wrong build even on an otherwise supported edition' {
        $script:Images[2].Version = '10.0.26100.1'
        { Get-VantaMediaEditions source @(26200) } | Should -Throw '*Unsupported Windows image*'
    }
    It 'retains supported ARM64 editions' {
        foreach ($image in $script:Images) { $image.Architecture = 12 }
        $result = @(Get-VantaMediaEditions source @(26200))
        ($result.EditionId -join ',') | Should -Be 'Professional,ProfessionalN,Education'
        @($result | Where-Object Architecture -ne 12) | Should -HaveCount 0
    }
    It 'rejects mixed architectures instead of building mismatched setup media' {
        $script:Images[2].Architecture = 12
        { Get-VantaMediaEditions source @(26200) } | Should -Throw '*Mixed x64 and ARM64*'
    }
    It 'rejects a wrong architecture' {
        $script:Images[2].Architecture = 0
        { Get-VantaMediaEditions source @(26200) } | Should -Throw '*Unsupported Windows image*'
    }
    It 'rejects an unverified full version at the first image' {
        Mock Get-VantaWindowsReleaseStatus { 'Unknown' }
        { Get-VantaMediaEditions source @(26200) } | Should -Throw '*could not be verified as a public release*'
        Should -Invoke Get-VantaWindowsReleaseStatus -Times 1 -Exactly -ParameterFilter { $Version -eq [version]'10.0.26200.6584' }
    }
    It 'names a build Microsoft does not list apart from one it could not check' {
        Mock Get-VantaWindowsReleaseStatus { 'Unlisted' }
        { Get-VantaMediaEditions source @(26200) } | Should -Throw "*not in Microsoft's list of public Windows 11 releases*"
        Should -Invoke Get-VantaWindowsReleaseStatus -Times 1 -Exactly
    }
    It 'checks releases against the bundled catalog alone when asked' {
        $null = Get-VantaMediaEditions source @(26200) -OfflineReleaseCheck
        Should -Invoke Get-VantaWindowsReleaseStatus -Times 5 -Exactly -ParameterFilter { $NoRefresh }
        $null = Get-VantaMediaEditions source @(26200)
        Should -Invoke Get-VantaWindowsReleaseStatus -Times 5 -Exactly -ParameterFilter { -not $NoRefresh }
    }
    It 'rejects server media' {
        $script:Images[2].InstallationType = 'Server'
        { Get-VantaMediaEditions source @(26200) } | Should -Throw '*client*'
    }
    It 'exports the original supported indices and verifies their new contiguous indices' {
        $selected = @(Get-VantaMediaEditions source @(26200))
        Export-VantaMediaEditions source (Join-Path $TestDrive 'output.wim') $selected
        ($script:Exported.EditionId -join ',') | Should -Be 'Professional,ProfessionalN,Education'
        Should -Invoke Export-WindowsImage -Times 3 -Exactly -ParameterFilter { $CheckIntegrity -and $CompressionType -eq 'Max' -and $SourceImagePath -eq 'source' }
        Should -Invoke Export-WindowsImage -Times 0 -Exactly -ParameterFilter { $SourceIndex -in @(1,2) }
    }
    It 'does not append to an existing image' {
        $destination = Join-Path $TestDrive 'existing.wim'
        Set-Content -LiteralPath $destination 'fixture'
        { Export-VantaMediaEditions source $destination @(Get-VantaMediaEditions source @(26200)) } | Should -Throw '*already exists*'
        Should -Invoke Export-WindowsImage -Times 0 -Exactly
    }
    It 'fails when the export produces a different edition' {
        Mock Export-WindowsImage { $script:Exported.Add((New-ImageFixture ($script:Exported.Count + 1) Core)) }
        { Export-VantaMediaEditions source (Join-Path $TestDrive 'wrong.wim') @(Get-VantaMediaEditions source @(26200)) } | Should -Throw '*does not match*'
    }
    It 'verifies ARM64 architecture after exporting supported editions' {
        foreach ($image in $script:Images) { $image.Architecture = 12 }
        Mock Export-WindowsImage {
            param($SourceIndex)
            $original = $script:Images | Where-Object ImageIndex -eq $SourceIndex
            $copy = New-ImageFixture ($script:Exported.Count + 1) $original.EditionId
            $copy.Architecture = 12
            $script:Exported.Add($copy)
        }
        { Export-VantaMediaEditions source (Join-Path $TestDrive 'arm.wim') @(Get-VantaMediaEditions source @(26200)) } | Should -Not -Throw
    }
    It 'rejects an export that changes architecture' {
        foreach ($image in $script:Images) { $image.Architecture = 12 }
        { Export-VantaMediaEditions source (Join-Path $TestDrive 'wrong-arch.wim') @(Get-VantaMediaEditions source @(26200)) } | Should -Throw '*does not match*'
    }
    It 'stops exporting after cancellation between editions' {
        # The first checkpoint passes: only a check repeated before each edition stops the second export.
        $script:StageCalls = 0
        Mock Write-Stage { $script:StageCalls++; if ($script:StageCalls -gt 1) { throw 'Cancelled at a safe checkpoint.' } }
        { Export-VantaMediaEditions source (Join-Path $TestDrive 'cancelled.wim') @(Get-VantaMediaEditions source @(26200)) } | Should -Throw '*Cancelled*'
        Should -Invoke Export-WindowsImage -Times 1 -Exactly
    }
}
