#requires -Version 7.0
<#
.SYNOPSIS
    Gera uma edição do Vanta com o pacote EMBUTIDO no Manager: Vanta-<edição>.vantapkg + VantaManager<Edição>.exe.
.DESCRIPTION
    Pessoal -> Vanta-pessoal.vantapkg (com a fase Perfil e a config de hardware do Nathan) + VantaManagerPessoal.exe + VantaTools.exe dentro.
    Publica -> Vanta-publico.vantapkg (nada do PC do Nathan) + VantaManagerPublico.exe + VantaToolsPublico.exe dentro.
    Passos: 1) compila os exes release com CRT estático; 2) Build-VantaPackage.ps1 -Edition; 3) compila o Manager com
    --features embedded-package (VANTA_EMBED_PACKAGE = o .vantapkg, VANTA_RELEASE_ID = <versão>) e copia para out;
    4) prova que os bytes do pacote estão no .exe, idênticos ao arquivo (mesmo SHA256); 5) SHA256SUMS.
    Nada vai para a rede e nada é publicado.
.PARAMETER Edition
    Pessoal, Publica ou Ambas.
#>
[CmdletBinding()]
param(
    [ValidateSet('Pessoal', 'Publica', 'Ambas')][string]$Edition = 'Ambas',
    [string]$OutputPath
)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
# ValidateSet ignora maiúsculas: "publica" escaparia dos -ceq. Normaliza uma vez, aqui.
$Edition = switch ($Edition.ToLowerInvariant()) { 'pessoal' { 'Pessoal' } 'publica' { 'Publica' } 'ambas' { 'Ambas' } default { throw "Edicao desconhecida: $Edition" } }
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if (-not $OutputPath) { $OutputPath = Join-Path $repo 'vanta\out' }
New-Item -ItemType Directory -Force -Path $OutputPath | Out-Null
$OutputPath = (Resolve-Path $OutputPath).Path
$target = Join-Path $repo 'app\target\x86_64-pc-windows-msvc\release'
$manifest = Get-Content -LiteralPath (Join-Path $repo 'vanta\vanta.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$version = [string]$manifest.version

Add-Type -TypeDefinition @'
using System;
public static class VantaEmbedProof {
    // Offset de `needle` (o pacote inteiro) dentro de `hay` (o exe), ou -1.
    public static int IndexOf(byte[] hay, byte[] needle) {
        int start = 0;
        while (start <= hay.Length - needle.Length) {
            int i = Array.IndexOf(hay, needle[0], start);
            if (i < 0 || i > hay.Length - needle.Length) return -1;
            if (new ReadOnlySpan<byte>(hay, i, needle.Length).SequenceEqual(needle)) return i;
            start = i + 1;
        }
        return -1;
    }
}
'@

function Invoke-Cargo {
    param([string[]]$Arguments, [hashtable]$Environment = @{})
    $saved = @{}
    foreach ($key in $Environment.Keys) { $saved[$key] = [Environment]::GetEnvironmentVariable($key, 'Process'); [Environment]::SetEnvironmentVariable($key, $Environment[$key], 'Process') }
    Push-Location (Join-Path $repo 'app')
    try {
        & cargo @Arguments
        if ($LASTEXITCODE -ne 0) { throw "cargo $($Arguments -join ' ') falhou ($LASTEXITCODE)." }
    }
    finally {
        Pop-Location
        foreach ($key in $saved.Keys) { [Environment]::SetEnvironmentVariable($key, $saved[$key], 'Process') }
    }
}

$crt = @{ CARGO_ENCODED_RUSTFLAGS = (& (Join-Path $PSScriptRoot 'Get-VantaRustFlags.ps1') -Repo $repo); CARGO_INCREMENTAL = '0' }
$editions = if ($Edition -ceq 'Ambas') { @('Pessoal', 'Publica') } else { @($Edition) }
$results = @()

# 1. exes sem pacote embutido: o Manager comum serve de conferência de CRT; os Tools vão dentro de cada pacote
Invoke-Cargo -Environment $crt -Arguments @('build', '--release', '--locked', '--target', 'x86_64-pc-windows-msvc', '--bin', 'VantaManager', '--bin', 'VantaTools', '--bin', 'VantaToolsPublico')
$plainManager = Join-Path $OutputPath 'VantaManager.plain.exe'
Copy-Item -LiteralPath (Join-Path $target 'VantaManager.exe') -Destination $plainManager -Force

foreach ($name in $editions) {
    $slug = if ($name -ceq 'Pessoal') { 'pessoal' } else { 'publico' }
    $label = if ($name -ceq 'Pessoal') { 'Pessoal' } else { '' }   # a edicao publica e o VantaManager.exe, sem versao nem edicao no nome
    $tools = Join-Path $target $(if ($name -ceq 'Pessoal') { 'VantaTools.exe' } else { 'VantaToolsPublico.exe' })
    # So a edicao publica e distribuivel: a pessoal (que leva CABs do CBS) vai para uma pasta propria, fora do SHA256SUMS.
    $editionOut = Join-Path $OutputPath 'build'   # o .vantapkg avulso nao e distribuido: o pacote vai dentro do VantaManager.exe
    New-Item -ItemType Directory -Force -Path $editionOut | Out-Null
    # 2. o pacote da edição
    & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'Build-VantaPackage.ps1') -Edition $name -OutputPath $editionOut -ToolsExe $tools -ManagerExe $plainManager
    if ($LASTEXITCODE -ne 0) { throw "Build-VantaPackage ($name) falhou." }
    $package = Join-Path $editionOut "Vanta-$slug.vantapkg"
    if (-not (Test-Path -LiteralPath $package -PathType Leaf)) { throw "Faltou $package." }
    # 3. o Manager com ESSE pacote dentro
    # O id da versao: 1.0.0 para a publica (sem banner de teste); a pessoal leva sufixo e mostra o banner.
    $rcId = if ($name -ceq 'Pessoal') { "$version-pessoal" } else { $version }
    Invoke-Cargo -Environment ($crt + @{ VANTA_EMBED_PACKAGE = $package; VANTA_RELEASE_ID = $rcId }) -Arguments @('build', '--release', '--locked', '--target', 'x86_64-pc-windows-msvc', '--features', 'embedded-package', '--bin', 'VantaManager')
    $exe = Join-Path $(if ($name -ceq 'Pessoal') { $editionOut } else { $OutputPath }) "VantaManager$label.exe"
    Copy-Item -LiteralPath (Join-Path $target 'VantaManager.exe') -Destination $exe -Force
    # 4. prova: os bytes do pacote estão no exe, idênticos
    $packageBytes = [IO.File]::ReadAllBytes($package)
    $offset = [VantaEmbedProof]::IndexOf([IO.File]::ReadAllBytes($exe), $packageBytes)
    if ($offset -lt 0) { throw "$exe não carrega os bytes de $package." }
    $slice = New-Object byte[] $packageBytes.Length
    $fs = [IO.File]::OpenRead($exe); try { [void]$fs.Seek($offset, 'Begin'); [void]$fs.Read($slice, 0, $slice.Length) } finally { $fs.Dispose() }
    $embeddedHash = [BitConverter]::ToString([Security.Cryptography.SHA256]::HashData($slice)).Replace('-', '')
    $packageHash = (Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash
    if ($embeddedHash -ne $packageHash) { throw "SHA256 embutido ($embeddedHash) difere do pacote ($packageHash)." }
    $results += [pscustomobject]@{ Edition = $name; Package = $package; PackageBytes = $packageBytes.Length; PackageSha256 = $packageHash; Exe = $exe; ExeBytes = (Get-Item $exe).Length; ExeSha256 = (Get-FileHash $exe -Algorithm SHA256).Hash; EmbeddedAtOffset = $offset; RcId = $rcId }
}
Remove-Item -LiteralPath $plainManager -Force
# 5. release completa (so com as duas edicoes): licenses/ e o codigo-fonte do HEAD exato deste build (GPL-3.0 secao 6a)
if ($Edition -ceq 'Ambas') {
    Push-Location $repo
    try {
        if (@(& git status --porcelain --untracked-files=no).Count -gt 0) { throw 'A arvore git tem alteracoes nao commitadas: o source.zip nao corresponderia ao build. Commite antes.' }
        $head = (& git rev-parse HEAD).Trim()
        $licensesDir = Join-Path $OutputPath 'licenses'
        if (Test-Path -LiteralPath $licensesDir) { Remove-Item -LiteralPath $licensesDir -Recurse -Force }
        New-Item -ItemType Directory -Path $licensesDir | Out-Null
        $licenseSources = [ordered]@{
            'LICENSE'                 = 'LICENSE'
            'NOTICE'                  = 'NOTICE'
            'THIRD-PARTY-NOTICES.txt' = 'app/licenses/THIRD-PARTY-NOTICES.txt'
            'Geist-OFL.txt'           = 'app/licenses/fonts/Geist-OFL.txt'
            'BINARY-INVENTORY.md'     = 'package/Executables/VantaModules/README.md'
        }
        foreach ($name in $licenseSources.Keys) { Copy-Item -LiteralPath (Join-Path $repo $licenseSources[$name]) -Destination (Join-Path $licensesDir $name) -Force }
        # the public inventory has no PERSONAL block (private path, internal commit)
        $inventory = Join-Path $licensesDir 'BINARY-INVENTORY.md'
        $inventoryText = [regex]::Replace(([IO.File]::ReadAllText($inventory) -replace "`r`n", "`n"), '(?ms)^[ 	]*<!--[ 	]*[>]{3} PERSONAL[^
]*
.*?^[ 	]*<!--[ 	]*[<]{3} PERSONAL[^
]*
', '')
        [IO.File]::WriteAllText($inventory, $inventoryText, (New-Object Text.UTF8Encoding $false))
        # os 5 avisos juntos, para anexar a Release do GitHub
        $licensesZip = Join-Path $OutputPath 'licenses.zip'
        if (Test-Path -LiteralPath $licensesZip) { Remove-Item -LiteralPath $licensesZip -Force }
        Compress-Archive -Path (Join-Path $licensesDir '*') -DestinationPath $licensesZip -CompressionLevel Optimal
        # o codigo-fonte dos programas GPL de terceiros do pacote (ViVe, Multi-Choice), de commits fixos (GPL-3.0 secao 6(d))
        & pwsh -NoProfile -File (Join-Path $repo 'tools/release/Get-ThirdPartySources.ps1') -OutputPath $OutputPath
        if ($LASTEXITCODE -ne 0) { throw 'Get-ThirdPartySources.ps1 falhou.' }
    }
    finally { Pop-Location }
}
# 6. somas de tudo o que e distribuivel em out (publico, source.zip, third-party-sources e licenses/)
$sums = Join-Path $OutputPath 'SHA256SUMS'
$notDistributed = @((Join-Path $OutputPath 'build*'))
$lines = foreach ($file in (Get-ChildItem -LiteralPath $OutputPath -Recurse -File | Where-Object { $path = $_.FullName; $_.Name -cne 'SHA256SUMS' -and -not @($notDistributed | Where-Object { $path -like $_ }) } | Sort-Object FullName)) {
    $relative = $file.FullName.Substring($OutputPath.Length + 1).Replace([string][char]92, '/')
    (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant() + '  ' + $relative
}
[IO.File]::WriteAllText($sums, ($lines -join "`n") + "`n", (New-Object Text.UTF8Encoding $false))
$results | Format-List
