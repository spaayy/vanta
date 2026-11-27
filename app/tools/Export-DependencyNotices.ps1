#Requires -Version 7.2
# Source inputs come from Cargo's locked Windows resolution;
# this command never downloads license text or silently invents missing notices.
[CmdletBinding()]
param(
    [switch]$Check,
    [string]$AppDirectory = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$app = [IO.Path]::GetFullPath($AppDirectory)
function Get-NoticeHash([string]$Text) {
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Text.Replace("`r`n", "`n"))))
}
Push-Location $app
try {
    $metadataText = & cargo metadata --locked --format-version 1 --filter-platform x86_64-pc-windows-msvc
    if ($LASTEXITCODE) { throw 'Cargo metadata failed.' }
    $metadata = $metadataText | ConvertFrom-Json
    $normal = @(& cargo tree --locked --target x86_64-pc-windows-msvc --edges normal,no-proc-macro --prefix none --format '{p}' | ForEach-Object { $_ -replace ' \(\*\)$', '' })
    if ($LASTEXITCODE) { throw 'Cargo dependency tree failed.' }
    $supplements = Get-Content (Join-Path $app 'licenses/supplements.json') -Raw | ConvertFrom-Json
    $sections = [System.Collections.Generic.List[string]]::new()
    $inventory = [System.Collections.Generic.List[object]]::new()
    $unresolved = [System.Collections.Generic.List[string]]::new()
    $sections.Add("VANTA THIRD-PARTY NOTICES`n`nThis conservative inventory includes the locked Windows dependency resolution, including build and development packages. Inclusion does not assert that a package is linked into VantaManager.exe. Original license and notice texts follow; SPDX expressions are metadata, not a substitute for those texts. Generated with app/tools/Export-DependencyNotices.ps1.`n")
    $firstPartyNames = @('vanta-manager', 'vanta-app', 'vanta-core', 'vanta-sys')
    $repoRoot = [IO.Path]::GetFullPath((Join-Path $app '..')).TrimEnd([char]92, [char]47) + [IO.Path]::DirectorySeparatorChar
    foreach ($package in ($metadata.packages | Sort-Object name, version)) {
        # Only the Vanta's own three crates are first party: named in this fixed list, local (no registry/git source)
        # and inside the repository but NOT under app/vendor (those are third-party code with licences of their own).
        $manifestPath = [IO.Path]::GetFullPath($package.manifest_path)
        $vendorRoot = [IO.Path]::GetFullPath((Join-Path $app 'vendor')).TrimEnd([char]92, [char]47) + [IO.Path]::DirectorySeparatorChar
        if ($package.name -in $firstPartyNames -and $null -eq $package.source -and
            $manifestPath.StartsWith($repoRoot, [StringComparison]::OrdinalIgnoreCase) -and
            -not $manifestPath.StartsWith($vendorRoot, [StringComparison]::OrdinalIgnoreCase)) {
            $isNormalLocal = $normal.Where({ $_ -like "$($package.name) v$($package.version) (*)" }).Count -gt 0
            $inventory.Add([ordered]@{ package = $package.name; version = $package.version; source = $null; firstParty = $true; license = $package.license; normalWindowsDependency = $isNormalLocal; noticeFile = 'LICENSE'; notices = @() })
            continue
        }
        $root = Split-Path $package.manifest_path
        $files = @(Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object {
            $_.Name -match '^(licen[cs]e|copying|notice|copyright)([._-]|$)' -and
            $_.FullName -notmatch '[\\/]\.git[\\/]'
        } | Sort-Object FullName)
        $texts = [System.Collections.Generic.List[object]]::new()
        foreach ($file in $files) {
            $body = [IO.File]::ReadAllText($file.FullName)
            # Crate archives sometimes contain flattened symlinks. They are not licenses.
            if ([string]::IsNullOrWhiteSpace($body) -or $body.Trim() -match '^\.\.?[/\\][^\r\n]+$') { continue }
            $texts.Add([ordered]@{ path = $file.FullName.Substring($root.Length + 1).Replace('\', '/'); sha256 = (Get-NoticeHash $body); text = $body.Replace("`r`n", "`n").TrimEnd() })
        }
        foreach ($extra in @($supplements | Where-Object { $_.package -eq $package.name -and $_.version -eq $package.version })) {
            $file = Join-Path $app "licenses/$($extra.file)"
            if ((Get-FileHash $file -Algorithm SHA256).Hash -ne $extra.sha256) { throw "Supplement hash mismatch: $file" }
            if ($extra.url -notmatch '/[0-9a-f]{40}/') { throw "Supplement source must pin a commit: $($extra.url)" }
            $texts.Add([ordered]@{ path = $extra.url; sha256 = $extra.sha256; text = [IO.File]::ReadAllText($file).Replace("`r`n", "`n").TrimEnd() })
        }
        if (-not $texts.Count -or -not $package.license) {
            $unresolved.Add("$($package.name) $($package.version)")
            $sections.Add("`nUNRESOLVED NOTICE: $($package.name) $($package.version). Declared license: $($package.license). This development inventory is not approved for executable distribution.`n")
        }
        $isNormal = $normal -contains "$($package.name) v$($package.version)"
        if ($null -eq $package.source) { $isNormal = $normal.Where({ $_ -like "$($package.name) v$($package.version) (*)" }).Count -gt 0 }
        $inventory.Add([ordered]@{ package = $package.name; version = $package.version; source = $package.source; license = $package.license; normalWindowsDependency = $isNormal; notices = @($texts | ForEach-Object { [ordered]@{ path = $_.path; sha256 = $_.sha256 } }) })
        $sections.Add("`n========================================================================`n$($package.name) $($package.version)`nDeclared license: $($package.license)`nRepository: $($package.repository)`n")
        foreach ($notice in $texts) { $sections.Add("`n--- $($notice.path) ---`n$($notice.text)`n") }
    }
    # Components that are not Cargo crates but ship in the package (Go modules linked into multichoice.exe, the DLL
    # inside ViVeTool): their licence texts are checked in under licenses/supplemental/components and hashed here.
    $componentsFile = Join-Path $app 'licenses/components.json'
    $components = @(if (Test-Path -LiteralPath $componentsFile) { Get-Content $componentsFile -Raw | ConvertFrom-Json })
    $componentInventory = [System.Collections.Generic.List[object]]::new()
    if ($components.Count) { $sections.Add("`n========================================================================`nNON-CARGO COMPONENTS DISTRIBUTED WITH THE VANTA PACKAGE`n") }
    foreach ($component in $components) {
        $file = Join-Path $app "licenses/$($component.file)"
        if (-not (Test-Path -LiteralPath $file) -or (Get-FileHash $file -Algorithm SHA256).Hash -ne $component.sha256) { throw "Component notice hash mismatch: $file" }
        $text = [IO.File]::ReadAllText($file).Replace("`r`n", "`n").TrimEnd()
        $componentInventory.Add([ordered]@{ component = $component.name; version = $component.version; license = $component.license; source = $component.source; notice = [ordered]@{ path = $component.file; sha256 = $component.sha256 } })
        $sections.Add("`n========================================================================`n$($component.name) $($component.version)`nDeclared license: $($component.license)`nSource: $($component.source)`n`n--- $($component.file) ---`n$text`n")
    }
    $outputs = @{
        'THIRD-PARTY-NOTICES.txt' = ($sections -join "`n") + "`n"
        'dependency-inventory.json' = (ConvertTo-Json -Depth 10 -InputObject ([ordered]@{ cargoLockSha256 = (Get-NoticeHash ([IO.File]::ReadAllText((Join-Path $app 'Cargo.lock')))); hashEncoding = 'UTF-8 with LF line endings; supplemental hashes retain downloaded bytes'; target = 'x86_64-pc-windows-msvc'; scope = 'conservative locked target resolution, including build and development packages'; unresolved = @($unresolved); components = @($componentInventory); packages = @($inventory) })) + "`n"
    }
    if ($unresolved.Count) {
        $message = "Unresolved notices: $($unresolved -join ', '). Review corresponding sources; do not substitute generic license templates."
        if ($Check) { throw $message }
        Write-Warning $message
    }
    foreach ($name in $outputs.Keys) {
        $path = Join-Path $app "licenses/$name"
        $expected = $outputs[$name].Replace("`r`n", "`n")
        if ($Check) {
            if (-not (Test-Path $path) -or [IO.File]::ReadAllText($path).Replace("`r`n", "`n") -cne $expected) { throw "Stale dependency notices: run app/tools/Export-DependencyNotices.ps1 ($name)." }
        } else { [IO.File]::WriteAllText($path, $expected, [Text.UTF8Encoding]::new($false)) }
    }
    Write-Output "Verified notices for $($inventory.Count) resolved dependency packages."
} finally { Pop-Location }
