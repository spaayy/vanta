#Requires -Version 7.0
<#
.SYNOPSIS
    Builds Vanta-<version>-third-party-sources.zip: the corresponding source of the GPL programs the package carries
    (ViVe, Multi-Choice) plus the licence text of Newtonsoft.Json, from the fixed commits in third-party-sources.lock.json.
.DESCRIPTION
    Nothing here trusts a moving ref: every item is fetched by its full commit, and the commit, tag and tree ids are
    compared with the lock before anything is written. Downloads live in tools/release/cache (not in git). The zip is
    deterministic: sorted names, fixed timestamps, no machine data, so the same lock gives the same bytes.
    Multi-Choice gets go.mod, go.sum and vendor/ (go mod vendor, with the pinned Go toolchain) so it builds offline.
.PARAMETER OutputPath
    Folder for the zip. Default: <repo>/vanta/out.
.PARAMETER Verify
    After writing the zip, extract it to a clean folder and build Multi-Choice offline (go build -mod=vendor), and ViVe
    when a .NET SDK is installed.
#>
[CmdletBinding()]
param(
    [string]$OutputPath,
    [switch]$Verify
)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$lockPath = Join-Path $PSScriptRoot 'third-party-sources.lock.json'
$cache = Join-Path $PSScriptRoot 'cache'
if (-not $OutputPath) { $OutputPath = Join-Path $repo 'vanta/out' }
New-Item -ItemType Directory -Force -Path $cache, $OutputPath | Out-Null
$lock = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json
$version = [string](Get-Content -LiteralPath (Join-Path $repo 'vanta/vanta.json') -Raw -Encoding UTF8 | ConvertFrom-Json).version
$zipPath = Join-Path (Resolve-Path $OutputPath).Path ($lock.output.Replace('{version}', $version))
$root = "Vanta-$version-third-party-sources"

function Invoke-Git {
    param([string]$GitDir, [string[]]$Arguments)
    $text = & git --git-dir=$GitDir @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git $($Arguments -join ' ') failed: $text" }
    return $text
}

function Get-Sha256Hex([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }

function Get-PinnedRepository {
    <# A bare repository in the cache holding exactly the pinned commit (and the tag, when the lock names one). #>
    param($Item)
    $gitDir = Join-Path $cache "$($Item.id).git"
    if (-not (Test-Path -LiteralPath $gitDir)) { & git init --bare --quiet $gitDir; if ($LASTEXITCODE) { throw 'git init failed.' } }
    $have = & git --git-dir=$gitDir cat-file -t $Item.commit 2>$null
    if ($have -cne 'commit') { $null = Invoke-Git $gitDir @('fetch', '--quiet', '--depth', '1', $Item.repository, $Item.commit) }
    $actual = (Invoke-Git $gitDir @('rev-parse', "$($Item.commit)^{commit}")).Trim()
    if ($actual -cne $Item.commit) { throw "$($Item.id): the fetched commit is $actual, the lock says $($Item.commit)." }
    $tag = $Item.PSObject.Properties['tag']
    if ($tag) {
        $null = Invoke-Git $gitDir @('fetch', '--quiet', '--depth', '1', $Item.repository, "refs/tags/$($tag.Value):refs/tags/$($tag.Value)")
        $tagCommit = (Invoke-Git $gitDir @('rev-parse', "refs/tags/$($tag.Value)^{commit}")).Trim()
        if ($tagCommit -cne $Item.commit) { throw "$($Item.id): tag $($tag.Value) is commit $tagCommit, the lock says $($Item.commit)." }
    }
    return $gitDir
}

function Expand-GitTree {
    param([string]$GitDir, [string]$TreeIsh, [string]$Destination)
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    $zip = Join-Path $cache ([guid]::NewGuid().ToString('N') + '.zip')
    try {
        $null = Invoke-Git $GitDir @('archive', '--format=zip', "--output=$zip", $TreeIsh)
        Expand-Archive -LiteralPath $zip -DestinationPath $Destination -Force
    }
    finally { Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue }
}

function Get-GoToolchain {
    $zip = Join-Path $cache (Split-Path -Leaf ([uri]$lock.goToolchain.url).AbsolutePath)
    if (-not (Test-Path -LiteralPath $zip) -or (Get-Sha256Hex $zip) -ne $lock.goToolchain.sha256.ToUpperInvariant()) {
        Invoke-WebRequest -Uri $lock.goToolchain.url -OutFile $zip -UseBasicParsing
    }
    if ((Get-Sha256Hex $zip) -ne $lock.goToolchain.sha256.ToUpperInvariant()) { throw "The Go toolchain download does not match the lock ($($lock.goToolchain.version))." }
    $dir = Join-Path $cache "go-toolchain-$($lock.goToolchain.version)"
    if (-not (Test-Path -LiteralPath (Join-Path $dir 'go/bin/go.exe'))) { Expand-Archive -LiteralPath $zip -DestinationPath $dir -Force }
    return (Join-Path $dir 'go')
}

function Invoke-Go {
    param([string]$GoRoot, [string]$WorkDir, [string[]]$Arguments, [hashtable]$Environment = @{})
    $saved = @{}
    $env = @{ GOROOT = $GoRoot; GOTOOLCHAIN = 'local'; GOFLAGS = ''; GOPATH = (Join-Path $cache 'gopath'); GOCACHE = (Join-Path $cache 'gocache') }
    foreach ($key in $Environment.Keys) { $env[$key] = $Environment[$key] }
    foreach ($key in $env.Keys) { $saved[$key] = [Environment]::GetEnvironmentVariable($key, 'Process'); [Environment]::SetEnvironmentVariable($key, $env[$key], 'Process') }
    Push-Location $WorkDir
    try {
        $output = & (Join-Path $GoRoot 'bin/go.exe') @Arguments 2>&1
        if ($LASTEXITCODE -ne 0) { throw "go $($Arguments -join ' ') failed: $output" }
        return $output
    }
    finally {
        Pop-Location
        foreach ($key in $saved.Keys) { [Environment]::SetEnvironmentVariable($key, $saved[$key], 'Process') }
    }
}

$stage = Join-Path ([IO.Path]::GetTempPath()) ('vanta-tps-' + [guid]::NewGuid().ToString('N'))
$content = Join-Path $stage $root
New-Item -ItemType Directory -Force -Path $content | Out-Null
try {
    $provenance = [System.Collections.Generic.List[string]]::new()
    $provenance.Add("# Vanta ${version}: third-party sources`n`nProject: https://github.com/spaayy/vanta. The corresponding source of the GPL programs in the Vanta package, and the licence text of one MIT library. Every item is the exact commit named here (GPL-3.0 section 6(d): this file is offered in the same place as the binaries, at no extra charge).`n")
    foreach ($item in $lock.items) {
        $gitDir = Get-PinnedRepository $item
        $target = Join-Path $content $item.target
        $licenseOnly = $item.PSObject.Properties['licenseOnly']
        if ($licenseOnly) {
            New-Item -ItemType Directory -Force -Path $target | Out-Null
            $licensePath = Join-Path $target "LICENSE.md"
            $bytes = & git --git-dir=$gitDir show "$($item.commit):$($licenseOnly.Value)"
            $null = Invoke-Git $gitDir @('cat-file', '-e', "$($item.commit):$($licenseOnly.Value)")
            [IO.File]::WriteAllText($licensePath, (($bytes -join "`n") + "`n"), (New-Object Text.UTF8Encoding $false))
            $expectedLicense = $item.licenseSha256.ToUpperInvariant()
            # the checked-in copy used by THIRD-PARTY-NOTICES.txt is the same file: compare with the lock hash by content
            $normalized = (Get-Content -LiteralPath $licensePath -Raw).Replace("`r`n", "`n").TrimEnd()
            $notice = Join-Path $repo 'app/licenses/supplemental/components/Newtonsoft.Json-13.0.3-LICENSE.md'
            if ((Get-Sha256Hex $notice) -ne $expectedLicense) { throw "$($item.id): the checked-in notice does not match the lock hash." }
            if ($normalized -cne (Get-Content -LiteralPath $notice -Raw).Replace("`r`n", "`n").TrimEnd()) { throw "$($item.id): the licence at the pinned commit differs from the notice in app/licenses." }
            $provenance.Add("## $($item.name)`n`n- Repository: $($item.repository)`n- Tag: $($item.tag), commit ``$($item.commit)```n- Licence: $($item.license) (text only; the licence does not require the source)`n")
            continue
        }
        $treeIsh = if ($item.path) { "$($item.commit):$($item.path)" } else { $item.commit }
        Expand-GitTree $gitDir $treeIsh $target
        $proofText = ''
        if ($item.PSObject.Properties['treeProof']) {
            # The binary comes from the release tag; the licence is at a later commit. Prove the code is the same tree.
            $proof = $item.treeProof
            $null = Invoke-Git $gitDir @('fetch', '--quiet', '--depth', '1', $item.repository, "refs/tags/$($proof.tag):refs/tags/$($proof.tag)")
            $tagCommit = (Invoke-Git $gitDir @('rev-parse', "refs/tags/$($proof.tag)^{commit}")).Trim()
            $tagTree = (Invoke-Git $gitDir @('rev-parse', "refs/tags/$($proof.tag):$($item.path)")).Trim()
            $licensedTree = (Invoke-Git $gitDir @('rev-parse', "$($item.commit):$($item.path)")).Trim()
            if ($tagCommit -cne $proof.tagCommit) { throw "$($item.id): tag $($proof.tag) moved: $tagCommit, the lock says $($proof.tagCommit)." }
            if ($tagTree -cne $licensedTree -or $licensedTree -cne $proof.tree) {
                throw "$($item.id): $($proof.tag):$($item.path) is $tagTree but $($item.commit):$($item.path) is $licensedTree (lock: $($proof.tree)); the licensed tree is not the distributed one."
            }
            $proofText = "- Tree proof: ``$($proof.tag):$($item.path)`` = ``$($item.commit):$($item.path)`` = ``$licensedTree`` (the tag has no LICENSE file; the pinned commit adds the GPL-3.0 and keeps this tree identical)`n"
        }
        if ($item.licenseFile -and -not (Test-Path -LiteralPath (Join-Path $target $item.licenseFile))) {
            # Multi-Choice: the LICENSE is at the repository root of the licensed commit, not inside multichoice/.
            $text = & git --git-dir=$gitDir show "$($item.commit):$($item.licenseFile)"
            if ($LASTEXITCODE -ne 0) { throw "$($item.id): $($item.licenseFile) is missing at $($item.commit)." }
            [IO.File]::WriteAllText((Join-Path $target $item.licenseFile), (($text -join "`n") + "`n"), (New-Object Text.UTF8Encoding $false))
        }
        $goText = ''
        if ($item.PSObject.Properties['goVendor'] -and $item.goVendor) {
            $goRoot = Get-GoToolchain
            $sumBefore = Get-Sha256Hex (Join-Path $target 'go.sum')
            $null = Invoke-Go -GoRoot $goRoot -WorkDir $target -Arguments @('mod', 'vendor')
            if ((Get-Sha256Hex (Join-Path $target 'go.sum')) -ne $sumBefore) { throw "$($item.id): go mod vendor changed go.sum; the pinned dependency hashes are not the committed ones." }
            if (-not (Test-Path -LiteralPath (Join-Path $target 'vendor/modules.txt'))) { throw "$($item.id): go mod vendor produced no vendor/modules.txt." }
            $goText = "- Go modules: ``go.mod``, ``go.sum`` and ``vendor/`` (made with $($lock.goToolchain.version) by ``go mod vendor``, ``go.sum`` unchanged). Build offline: ``go build -mod=vendor``.`n"
        }
        $head = "## $($item.name)`n`n- Repository: $($item.repository)`n"
        if ($item.PSObject.Properties['tag']) { $head += "- Tag: $($item.tag)`n" }
        $provenance.Add($head + "- Commit: ``$($item.commit)```n- Licence: $($item.license) (``$($item.target)/$($item.licenseFile)``)`n" + $proofText + $goText)
    }
    [IO.File]::WriteAllText((Join-Path $content 'PROVENANCE.md'), (($provenance -join "`n")), (New-Object Text.UTF8Encoding $false))

    # Deterministic zip: ordinal sorted names, fixed timestamp, forward slashes.
    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    $stamp = [DateTimeOffset]::new(2000, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
    $files = @(Get-ChildItem -LiteralPath $stage -Recurse -File | ForEach-Object { [pscustomobject]@{ Full = $_.FullName; Name = $_.FullName.Substring($stage.Length + 1).Replace([string][char]92, '/') } })
    $names = [string[]]$files.Name
    [Array]::Sort($names, [StringComparer]::Ordinal)
    $byName = @{}; foreach ($f in $files) { $byName[$f.Name] = $f.Full }
    $archive = [IO.Compression.ZipFile]::Open($zipPath, 'Create')
    try {
        foreach ($name in $names) {
            $entry = $archive.CreateEntry($name, [IO.Compression.CompressionLevel]::SmallestSize)
            $entry.LastWriteTime = $stamp
            $in = [IO.File]::OpenRead($byName[$name]); $out = $entry.Open()
            try { $in.CopyTo($out) } finally { $out.Dispose(); $in.Dispose() }
        }
    }
    finally { $archive.Dispose() }
    Write-Host ("Built {0}  {1:N0} bytes  SHA-256 {2}" -f $zipPath, (Get-Item -LiteralPath $zipPath).Length, (Get-Sha256Hex $zipPath))

    if ($Verify) {
        $clean = Join-Path ([IO.Path]::GetTempPath()) ('vanta-tps-verify-' + [guid]::NewGuid().ToString('N'))
        try {
            Expand-Archive -LiteralPath $zipPath -DestinationPath $clean
            $goRoot = Get-GoToolchain
            $mc = Join-Path $clean "$root/Multi-Choice"
            $exe = Join-Path $clean 'multichoice-check.exe'
            $null = Invoke-Go -GoRoot $goRoot -WorkDir $mc -Arguments @('build', '-mod=vendor', '-o', $exe, '.') -Environment @{ GOPROXY = 'off'; GOFLAGS = '-mod=vendor'; GOOS = 'windows'; GOARCH = 'amd64' }
            Write-Host ("Multi-Choice builds offline from the zip: {0:N0} bytes" -f (Get-Item -LiteralPath $exe).Length)
            $sdks = @(& dotnet --list-sdks 2>$null)
            if ($LASTEXITCODE -eq 0 -and $sdks.Count) {
                $project = Get-ChildItem -LiteralPath (Join-Path $clean "$root/ViVe-v0.3.3") -Recurse -Filter ViVeTool.csproj | Select-Object -First 1
                if ($project) { & dotnet build $project.FullName -c Release; if ($LASTEXITCODE) { throw 'ViVeTool did not build.' } }
            }
            else { Write-Warning 'No .NET SDK is installed: ViVe was not built (its source is in the zip).' }
        }
        finally { Remove-Item -LiteralPath $clean -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
finally { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
