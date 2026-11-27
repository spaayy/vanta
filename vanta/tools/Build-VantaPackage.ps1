<#
.SYNOPSIS
    Builds the Vanta package (.vantapkg) and its SHA256SUMS.
.DESCRIPTION
    Reuses tools/build/Build-Package.ps1 (untouched) to build the Vanta package tree without a
    password, adds vanta/vanta.json, and writes the archive again as .vantapkg, AES-256 under the
    public Vanta password. SHA256SUMS is written beside it; Vanta Manager checks it before opening.
.PARAMETER OutputPath
    Folder for the .vantapkg and SHA256SUMS. Default: <repo>/vanta/out.
.PARAMETER Password
    Must equal PACKAGE_PASSWORD in app/src/services/package.rs. It is not a secret.
.NOTES
    Exit codes: 0 built and verified, 1 otherwise.
#>
#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$OutputPath,
    [string]$Password = 'vantapkg',
    [string]$ToolsExe,
    [string]$ManagerExe,
    # Pessoal: leva o perfil do PC do Nathan (fase Perfil) e a config de hardware dele (fase Devices) -> Vanta-pessoal.vantapkg.
    # Publica: nenhuma dessas duas coisas, só escolha livre do usuário -> Vanta-publico.vantapkg.
    # Sem -Edition: o pacote de sempre (Vanta-v<versão>.vantapkg, com Devices e sem Perfil).
    [ValidateSet('', 'Pessoal', 'Publica')][string]$Edition = ''
)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
# ValidateSet ignora maiúsculas: "publica" passava e escapava de todos os -ceq 'Publica'. Normaliza uma vez, aqui.
if ($Edition) { $Edition = switch ($Edition.ToLowerInvariant()) { 'pessoal' { 'Pessoal' } 'publica' { 'Publica' } default { throw "Edicao desconhecida: $Edition" } } }

# Leitura dos recursos do PE (RT_VERSION, RT_MANIFEST) e nomes para o 7-Zip: ver VantaPeInfo.ps1.
. (Join-Path $PSScriptRoot 'VantaPeInfo.ps1')

# Windows recusou (0x800b0110) os pacotes CBS assinados com a unica identidade propria que o Vanta pode usar, e
# testsigning nunca e ligado: a edicao PUBLICA sai sem nenhum CAB e sem a opcao defender-disable. So a PESSOAL (nao
# distribuivel) leva CABs, os do commit abaixo, buscados do git so na hora do build: o HEAD e o source.zip nao os carregam.

function Remove-DefenderDisableOption($Manifest) {
    foreach ($choice in @($Manifest.choices)) {
        if ($choice.id -ceq 'defender') {
            $choice.options = @($choice.options | Where-Object { $_.id -cne 'defender-disable' })
        }
    }
}


$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if (-not $OutputPath) { $OutputPath = Join-Path $repo 'vanta\out' }

$toolsName = if ($Edition -ceq 'Publica') { 'VantaToolsPublico' } else { 'VantaTools' }
if (-not $ToolsExe) {
    $prevRustflags = $env:CARGO_ENCODED_RUSTFLAGS
    $prevIncremental = $env:CARGO_INCREMENTAL
    Push-Location (Join-Path $repo 'app')
    try {
        $env:CARGO_ENCODED_RUSTFLAGS = & (Join-Path $PSScriptRoot 'Get-VantaRustFlags.ps1') -Repo $repo
        $env:CARGO_INCREMENTAL = '0'
        & cargo build --release --locked --target x86_64-pc-windows-msvc --bin $toolsName
        if ($LASTEXITCODE -ne 0) { throw "Build de $toolsName com CRT estatico falhou ($LASTEXITCODE)." }
    }
    finally {
        [Environment]::SetEnvironmentVariable('CARGO_ENCODED_RUSTFLAGS', $prevRustflags, 'Process')
        [Environment]::SetEnvironmentVariable('CARGO_INCREMENTAL', $prevIncremental, 'Process')
        Pop-Location
    }
    $ToolsExe = Join-Path $repo "app\target\x86_64-pc-windows-msvc\release\$toolsName.exe"
}
if (-not $ManagerExe) { $ManagerExe = Join-Path $repo 'app\target\x86_64-pc-windows-msvc\release\VantaManager.exe' }
if ($Edition -ceq 'Publica' -and (Split-Path -Leaf $ToolsExe) -ne 'VantaToolsPublico.exe') { throw "A edicao Publica so leva VantaToolsPublico.exe (recebeu $(Split-Path -Leaf $ToolsExe))." }
if (-not (Test-Path -LiteralPath $ToolsExe -PathType Leaf)) { throw "$toolsName.exe nao existe em $ToolsExe." }
if (-not (Test-Path -LiteralPath $ManagerExe -PathType Leaf)) { throw "VantaManager.exe nao existe em $ManagerExe (compile com CARGO_TARGET_X86_64_PC_WINDOWS_MSVC_RUSTFLAGS='-C target-feature=+crt-static' --target x86_64-pc-windows-msvc)." }

# dumpbin quando existe; senão (Linux) o leitor de PE do próprio script confere os imports.
. (Join-Path $PSScriptRoot 'Assert-StaticCrt.ps1')
$crtCheck = Assert-StaticCrt -Path @($ToolsExe, $ManagerExe)
foreach ($entry in $crtCheck) {
    Write-Host ("CRT estatico OK: {0} ({1} DLLs, 0 VCRUNTIME/MSVCP/api-ms-win-crt)" -f (Split-Path -Leaf $entry.Path), $entry.Imports.Count)
}
$vantaJson = Join-Path $repo 'vanta\vanta.json'
$manifest = Get-Content -LiteralPath $vantaJson -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $manifest.vanta) { throw 'vanta.json has no "vanta" field.' }
$version = [string]$manifest.version

$sevenZip = foreach ($name in '7z', '7zz') {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) { $cmd.Source; break }
}
if (-not $sevenZip) { throw '7z (7-Zip or NanaZip) must be on PATH.' }

$work = Join-Path ([IO.Path]::GetTempPath()) ('vanta-pkg-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
try {
    # 1. the Vanta tree, as the repository's own script builds and checks it, without a password
    $plain = Join-Path $work 'plain'
    New-Item -ItemType Directory -Path $plain | Out-Null
    & pwsh -NoProfile -File (Join-Path $repo 'tools\build\Build-Package.ps1') `
        -NoPassword -NoExplorer -ReplaceExisting -OutputPath $plain -FileName 'stage'
    if ($LASTEXITCODE -ne 0) { throw "Build-Package.ps1 failed with exit code $LASTEXITCODE." }
    $stage = Join-Path $plain 'stage.atlaspkg'
    if (-not (Test-Path -LiteralPath $stage)) { throw "Expected $stage was not written." }

    # 2. unpack, add vanta.json, pack again
    $tree = Join-Path $work 'tree'
    & $sevenZip x -y "-o$tree" $stage | Out-Null
    if ($LASTEXITCODE -ne 0) { throw '7z could not unpack the staged package.' }
    if ($Edition -ceq 'Publica') {
        $publicManifest = Get-Content -LiteralPath $vantaJson -Raw -Encoding UTF8 | ConvertFrom-Json
        $publicManifest.vanta.PSObject.Properties.Remove('kitManifest')
        $publicManifest.vanta.PSObject.Properties.Remove('presets')
        Remove-DefenderDisableOption $publicManifest
        [IO.File]::WriteAllText((Join-Path $tree 'vanta.json'), ((ConvertTo-Json -InputObject $publicManifest -Depth 20) + "`n"), (New-Object Text.UTF8Encoding $false))
    }
    else {
        Copy-Item -LiteralPath $vantaJson -Destination (Join-Path $tree 'vanta.json')
    }

    # 2b. atlas.json do pacote = as mesmas escolhas, sem o campo "vanta": os scripts do Vanta validam -Option contra ele
    $packageManifest = Get-Content -LiteralPath $vantaJson -Raw -Encoding UTF8 | ConvertFrom-Json
    $packageManifest.PSObject.Properties.Remove('vanta')
    if ($Edition -ceq 'Publica') { Remove-DefenderDisableOption $packageManifest }
    [IO.File]::WriteAllText((Join-Path $tree 'atlas.json'), ((ConvertTo-Json -InputObject $packageManifest -Depth 20) + "`n"), (New-Object Text.UTF8Encoding $false))

    # 2c. fases Vanta (vanta/modules) dentro de VantaModules, e o gancho no orquestrador (só na árvore de staging)
    $modulesRoot = Join-Path $tree 'Executables\VantaModules'
    # CABs: nenhum na publica (nem na sem edicao); na pessoal, os do commit antigo e o manifesto de hashes gerado aqui.
    $packagesDir = Join-Path $modulesRoot 'Packages'
    if (Test-Path -LiteralPath $packagesDir) { Get-ChildItem -LiteralPath $packagesDir -File | Where-Object { $_.Extension -in '.cab', '.psd1' } | Remove-Item -Force }
    $vantaModules = Join-Path $modulesRoot 'Vanta'
    New-Item -ItemType Directory -Force -Path $vantaModules | Out-Null
    foreach ($folder in 'Phases', 'Data', 'Tools', 'Scripts') {
        Copy-Item -LiteralPath (Join-Path $repo "vanta\modules\$folder") -Destination $vantaModules -Recurse -Force
    }
    # avisos de licença que a fase Licenses grava em C:\Vanta\Licenses (os mesmos arquivos vão em vanta/out/licenses)
    $licensesOut = Join-Path $vantaModules 'Licenses'
    New-Item -ItemType Directory -Force -Path $licensesOut | Out-Null
    $licenseSources = [ordered]@{
        'LICENSE'                 = 'LICENSE'
        'NOTICE'                  = 'NOTICE'
        'THIRD-PARTY-NOTICES.txt' = 'app/licenses/THIRD-PARTY-NOTICES.txt'
        'Geist-OFL.txt'           = 'app/licenses/fonts/Geist-OFL.txt'
        'BINARY-INVENTORY.md'     = 'package/Executables/VantaModules/README.md'
    }
    foreach ($name in $licenseSources.Keys) {
        $source = Join-Path $repo $licenseSources[$name]
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "$($licenseSources[$name]) nao existe (aviso de licenca do pacote)." }
        Copy-Item -LiteralPath $source -Destination (Join-Path $licensesOut $name) -Force
    }
    # the public inventory carries no PERSONAL block (private path, internal commit); only the personal edition keeps it
    if ($Edition -cne 'Pessoal') {
        $inventory = Join-Path $licensesOut 'BINARY-INVENTORY.md'
        $text = [IO.File]::ReadAllText($inventory) -replace "`r`n", "`n"
        $text = [regex]::Replace($text, '(?ms)^[ 	]*<!--[ 	]*[>]{3} PERSONAL[^
]*
.*?^[ 	]*<!--[ 	]*[<]{3} PERSONAL[^
]*
', '')
        [IO.File]::WriteAllText($inventory, $text, (New-Object Text.UTF8Encoding $false))
    }
    if ($Edition) {
        # Get-VantaEdition lê isto (a tarefa elevada do Tools só existe na pessoal)
        [IO.File]::WriteAllText((Join-Path $vantaModules 'edition.txt'), $(if ($Edition -ceq 'Pessoal') { 'pessoal' } else { 'publico' }) + "`n", (New-Object Text.UTF8Encoding $false))
    }
    if ($Edition -ceq 'Pessoal') {
        Copy-Item -LiteralPath (Join-Path $repo 'vanta\modules\Personal') -Destination $vantaModules -Recurse -Force
    }
    elseif ($Edition -ceq 'Publica') {
    }
    # o Tools de verdade: vai como vanta-tools.exe, com o hash gravado em tools.sha256 (a fase Atalhos so confia nesse par)
    $toolsDir = Join-Path $vantaModules 'Tools'
    Copy-Item -LiteralPath $ToolsExe -Destination (Join-Path $toolsDir 'vanta-tools.exe') -Force
    $toolsHash = (Get-FileHash -LiteralPath (Join-Path $toolsDir 'vanta-tools.exe') -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText((Join-Path $toolsDir 'tools.sha256'), "$toolsHash  vanta-tools.exe`n", (New-Object Text.UTF8Encoding $false))

    # icone da pasta da Area de Trabalho e notificacoes: sobrescrito apenas no staging (ADR-2: package/ intocado)
    $vantaFolderIco = Join-Path $repo 'app\resources\vanta-folder.ico'
    if (-not (Test-Path -LiteralPath $vantaFolderIco -PathType Leaf)) { throw "vanta-folder.ico nao existe em $vantaFolderIco." }
    $stagedFolderIco = Join-Path $modulesRoot 'Other\vanta-folder.ico'
    if (-not (Test-Path -LiteralPath $stagedFolderIco -PathType Leaf)) { throw "vanta-folder.ico nao encontrado no staging em $stagedFolderIco." }
    Copy-Item -LiteralPath $vantaFolderIco -Destination $stagedFolderIco -Force
    # wallpaper e tela de bloqueio do Vanta (arte do Design em app/resources/wallpapers): obrigatórios no pacote
    $wallpapersOut = Join-Path $modulesRoot 'Wallpapers'
    New-Item -ItemType Directory -Force -Path $wallpapersOut | Out-Null
    foreach ($art in 'vanta-wallpaper-dark.png', 'vanta-lockscreen-dark.png') {
        $artSource = Join-Path $repo "app\resources\wallpapers\$art"
        if (Test-Path -LiteralPath $artSource -PathType Leaf) { Copy-Item -LiteralPath $artSource -Destination $wallpapersOut -Force }
        else { throw "$art nao existe em app\resources\wallpapers." }
    }
    $expectedFolderIcoHash = (Get-FileHash -LiteralPath $vantaFolderIco -Algorithm SHA256).Hash.ToLowerInvariant()
    Copy-Item -LiteralPath (Join-Path $repo 'vanta\modules\Invoke-VantaPhase.ps1') -Destination (Join-Path $modulesRoot 'Scripts\Install\Phases') -Force
    . (Join-Path $PSScriptRoot 'Add-VantaHook.ps1')
    Add-VantaHook -ScriptsRoot (Join-Path $modulesRoot 'Scripts')
    foreach ($file in @(Get-ChildItem -LiteralPath $vantaModules -Recurse -Filter *.ps1) + (Get-Item (Join-Path $modulesRoot 'Scripts\Install\Phases\Invoke-VantaPhase.ps1')) +
        (Get-Item (Join-Path $modulesRoot 'Scripts\Install\Install-Plan.ps1')) + (Get-Item (Join-Path $modulesRoot 'Scripts\Entry\Invoke-VantaInstall.ps1')) + (Get-Item (Join-Path $modulesRoot 'Scripts\Install\Invoke-VantaInstallSession.ps1'))) {
        $errors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$errors)
        if ($errors) { throw "Erro de sintaxe em $($file.FullName): $($errors[0].Message)" }
    }

    New-Item -ItemType Directory -Force -Path $OutputPath | Out-Null
    $name = switch ($Edition) { 'Pessoal' { 'Vanta-pessoal.vantapkg' } 'Publica' { 'Vanta-publico.vantapkg' } default { "Vanta-v$version.vantapkg" } }
    $out = Join-Path (Resolve-Path $OutputPath).Path $name
    if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Force }
    Push-Location $tree
    try { & $sevenZip a -tzip -mem=AES256 "-p$Password" -mx=5 $out '*' | Out-Null }
    finally { Pop-Location }
    if ($LASTEXITCODE -ne 0) { throw '7z could not write the package.' }

    # 3. verify: opens with the password, has both manifests, and no Vanta package name inside
    # O 7-Zip lista com "/" no Linux; os testes abaixo escrevem os caminhos com "\".
    $listing = (& $sevenZip l -slt "-p$Password" $out | Out-String).Replace('/', '\')
    foreach ($required in 'Path = vanta.json', 'Path = atlas.json', 'Method = AES-256', 'Phases\Invoke-VantaPhase.ps1', 'Vanta\Phases\Store.ps1', 'Vanta\Tools\vanta-tools.exe', 'Vanta\Tools\tools.sha256', 'Vanta\Licenses\NOTICE', 'Vanta\Licenses\Geist-OFL.txt', 'Vanta\Licenses\THIRD-PARTY-NOTICES.txt', 'Vanta\Phases\Licenses.ps1') {
        if ($listing -notmatch [regex]::Escape($required)) { throw "The package listing lacks '$required'." }
    }
    # a edição decide o que PODE e o que NÃO PODE estar no pacote (o público não leva nada pessoal)
    $personal = @(); $hardware = @()
    $mustHave = if ($Edition -ceq 'Pessoal') { $personal + $hardware } elseif ($Edition -ceq '') { $hardware } else { @() }
    foreach ($item in $mustHave) {
        if ($listing -notmatch [regex]::Escape($item)) { throw "O pacote ($Edition) devia levar '$item'." }
    }
    if ($Edition -ceq '') {
        foreach ($item in $personal) { if ($listing -match [regex]::Escape($item)) { throw "O pacote sem edição não pode levar '$item'." } }
    }
    if ($Edition -ceq 'Publica') {
        if ($listing -match '(?im)^Path = .*\\Packages\\[^\\]*\.(cab|psd1)\s*$') { throw 'O pacote publico nao pode levar CABs nem o manifesto de hashes dos CABs.' }
        foreach ($item in $personal + $hardware + 'Vanta\Personal\') {
            if ($listing -match [regex]::Escape($item)) { throw "O pacote público não pode levar '$item' (é do PC do Nathan)." }
        }
    }
    & $sevenZip t "-p$Password" $out | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'The package failed the 7z integrity test.' }

    # 3b. segunda árvore: o gancho e o icone da pasta conferidos de novo no pacote FINAL (extraído), não só no staging
    $final = Join-Path $work 'final'
    $finalNames = ConvertTo-SevenZipName @('Executables\VantaModules\Vanta\edition.txt', 'Executables\VantaModules\Vanta\Tools\vanta-tools.exe', 'Executables\VantaModules\Vanta\Tools\tools.sha256', 'vanta.json')
    & $sevenZip x -y "-p$Password" "-o$final" $out $finalNames | Out-Null
    if ($LASTEXITCODE -ne 0) { throw '7z could not extract the edition files from the final package.' }
    $hookNames = @('Executables\VantaModules\Scripts\Entry\Invoke-VantaInstall.ps1', 'Executables\VantaModules\Scripts\Install\Install-Plan.ps1', 'Executables\VantaModules\Scripts\Tweaks\tweaks.manifest.psd1', 'Executables\VantaModules\Scripts\Install\Invoke-VantaInstallSession.ps1', 'Executables\VantaModules\Other\vanta-folder.ico', 'Executables\VantaModules\Wallpapers\vanta-wallpaper-dark.png', 'Executables\VantaModules\Wallpapers\vanta-lockscreen-dark.png')
    & $sevenZip x -y "-p$Password" "-o$final" $out (ConvertTo-SevenZipName $hookNames) | Out-Null
    if ($LASTEXITCODE -ne 0) { throw '7z could not extract the hook files from the final package.' }
    $problems = @(Get-VantaHookProblems -ScriptsRoot (Join-Path $final 'Executables\VantaModules\Scripts'))
    if ($problems.Count -gt 0) { throw ("O gancho não confere no pacote final:`n - " + ($problems -join "`n - ")) }
    $finalFolderIco = Join-Path $final 'Executables\VantaModules\Other\vanta-folder.ico'
    $finalFolderIcoHash = (Get-FileHash -LiteralPath $finalFolderIco -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($finalFolderIcoHash -ne $expectedFolderIcoHash) {
        throw "vanta-folder.ico no pacote final ($finalFolderIcoHash) difere de app/resources/vanta-folder.ico ($expectedFolderIcoHash)."
    }
    # 3b2. a edição no pacote FINAL: o que vale é o que o 7-Zip extraiu, não o que este script achou que gravou
    $finalVanta = Join-Path $final 'Executables\VantaModules\Vanta'
    $finalTools = Join-Path $finalVanta 'Tools\vanta-tools.exe'
    $toolsInPackage = (Get-FileHash -LiteralPath $finalTools -Algorithm SHA256).Hash.ToLowerInvariant()
    $toolsGiven = (Get-FileHash -LiteralPath $ToolsExe -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($toolsInPackage -ne $toolsGiven) { throw "vanta-tools.exe no pacote final ($toolsInPackage) difere de $(Split-Path -Leaf $ToolsExe) ($toolsGiven)." }
    if ((Get-Content -LiteralPath (Join-Path $finalVanta 'Tools\tools.sha256') -Raw) -notmatch "^$toolsInPackage\s+vanta-tools\.exe\s*$") { throw 'tools.sha256 do pacote final nao confere com o vanta-tools.exe.' }
    # Campos de versão e manifesto lidos do exe EXTRAÍDO do pacote final (não uma busca de texto no arquivo todo).
    $info = Get-VantaToolsExeInfo -Path $finalTools
    $expectedName = if ($Edition -ceq 'Publica') { 'VantaToolsPublico' } else { 'VantaTools' }
    if ($info.InternalName -cne $expectedName) { throw "InternalName do vanta-tools.exe no pacote final e '$($info.InternalName)'; esperado '$expectedName'." }
    if ($info.OriginalFilename -cne "$expectedName.exe") { throw "OriginalFilename do vanta-tools.exe no pacote final e '$($info.OriginalFilename)'; esperado '$expectedName.exe'." }
    if ($info.ExecutionLevel -cne 'requireAdministrator') { throw "O manifesto do vanta-tools.exe no pacote final pede '$($info.ExecutionLevel)'; esperado requireAdministrator." }
    if ($Edition) {
        $slug = if ($Edition -ceq 'Pessoal') { 'pessoal' } else { 'publico' }
        $editionInPackage = (Get-Content -LiteralPath (Join-Path $finalVanta 'edition.txt') -Raw).Trim()
        if ($editionInPackage -cne $slug) { throw "edition.txt do pacote final diz '$editionInPackage'; esperado '$slug'." }
    }
    if ($Edition -ceq 'Publica') {
        $finalManifest = Get-Content -LiteralPath (Join-Path $final 'vanta.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($field in 'kitManifest', 'presets') {
            if ($finalManifest.vanta.PSObject.Properties.Name -contains $field) { throw "vanta.json do pacote publico ainda tem '$field' (e do PC do Nathan)." }
        }
    }
    # 3c. wallpapers Vanta no pacote final (mesmo SHA256 da arte) e nenhum outro PNG em Wallpapers
    foreach ($art in 'vanta-wallpaper-dark.png', 'vanta-lockscreen-dark.png') {
        $inPkg = (Get-FileHash -LiteralPath (Join-Path $final "Executables\VantaModules\Wallpapers\$art") -Algorithm SHA256).Hash
        $source = (Get-FileHash -LiteralPath (Join-Path $repo "app\resources\wallpapers\$art") -Algorithm SHA256).Hash
        if ($inPkg -ne $source) { throw "$art no pacote final difere de app/resources/wallpapers." }
    }
    $extraArt = @([regex]::Matches($listing, '(?im)^Path = .*\\Wallpapers\\([^\\\r\n]+)\r?$') | ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ -notin @('vanta-wallpaper-dark.png', 'vanta-lockscreen-dark.png') })
    if ($extraArt.Count -gt 0) { throw ('O pacote traz wallpapers que nao sao do Vanta: ' + ($extraArt -join ', ')) }
    # 4. SHA256SUMS beside it
    $hash = (Get-FileHash -LiteralPath $out -Algorithm SHA256).Hash.ToLowerInvariant()
    $sums = Join-Path (Split-Path $out) 'SHA256SUMS'
    # uma linha por pacote: gerar uma edição não apaga a linha da outra
    $lines = @(if (Test-Path -LiteralPath $sums) { Get-Content -LiteralPath $sums | Where-Object { $_ -and ($_ -notmatch ('  ' + [regex]::Escape($name) + '$')) } })
    $lines += "$hash  $name"
    [IO.File]::WriteAllText($sums, (($lines | Sort-Object) -join "`n") + "`n", (New-Object Text.UTF8Encoding $false))

    Write-Host ("Built {0}  {1:N0} bytes" -f $out, (Get-Item -LiteralPath $out).Length) -ForegroundColor Green
    Write-Host "SHA256SUMS: $hash  $name"
}
catch {
    Write-Error $_
    exit 1
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
