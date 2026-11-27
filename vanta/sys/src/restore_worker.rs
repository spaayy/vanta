//! O lado elevado do Restaurar. O app NÃO grava script nenhum para o administrador executar: ele grava só o PLANO
//! (dados, ver `restore_plan`), calcula o SHA-256 dele e chama o PowerShell do diretório de sistema com um programa FIXO
//! (este arquivo) e esse hash na linha de comando. O lado elevado:
//! 1. cria a pasta `%ProgramData%\Vanta\run\<guid>` com ACL e confere os pais (ver `rundir`); recusada = sai (código 3);
//! 2. lê o plano UMA vez, confere o SHA-256 dos bytes lidos e só então interpreta (adulterado = sai, código 4);
//! 3. cria ou aperta (dono e ACL pelo handle) as pastas protegidas do plano (`C:\Vanta\System`);
//! 4. para cada item: confere o destino contra a lista permitida pelo manifesto, copia cada arquivo da origem para um
//!    retrato na pasta protegida LENDO UMA VEZ e conferindo o SHA-256 do plano, e só então copia o retrato ao destino;
//! 5. `.reg` só importa o que não existe com outro dado; tarefa e entrada `Run` só entram se a ação inteira é permitida
//!    e se o script tem o hash do que foi copiado; nada que já exista com outro conteúdo é sobrescrito;
//! 6. grava o resultado na pasta protegida; o app só lê.

use std::fs;
use std::io;
use std::time::Duration;

use vanta_core::install::CancelToken;
use vanta_core::manifest::sha256_hex;

use crate::batch::{MAX_PARAMETERS, elevated_arguments, new_run_id};
use crate::elevate::{is_declined, run_elevated};
use crate::restore_batch::current_sid;
use crate::restore_plan::{RestorePlan, valid_name};
use crate::rundir::{RUN_DIR_PS, is_run_id, is_user_sid, run_dir};

/// Funções do lado elevado (validações, leitura do plano, cópia conferida). Testadas em `powershell.exe` sem administrador.
pub const WORKER_FUNCS_PS: &str = r#"function Test-VantaPath {
    param([string]$Path)
    return ($Path -match '^[A-Za-z]:\\' -and $Path -notmatch '["<>|*?\x00-\x1f]' -and $Path -notmatch '(^|\\)\.\.?(\\|$)' -and $Path -notmatch '\\\\')
}
function Test-VantaRelPath {
    param([string]$Path)
    return ($Path -and $Path -notmatch '^\\' -and $Path -notmatch ':' -and $Path -notmatch '["<>|*?\x00-\x1f]' -and $Path -notmatch '(^|\\)\.\.?(\\|$)' -and $Path -notmatch '\\\\' -and $Path -notmatch '\\$')
}
function Test-VantaName {
    param([string]$Name)
    return ($Name -match '^[A-Za-z0-9_.+-]([A-Za-z0-9 _.+-]{0,78}[A-Za-z0-9_.+-])?$')
}
function Test-VantaInRoots {
    param([string]$Path, [string[]]$Roots)
    foreach ($root in $Roots) { if ($root -and ($Path -ieq $root.TrimEnd('\') -or $Path.StartsWith($root.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase))) { return $true } }
    return $false
}
function Test-VantaDestination {
    <# O destino está dentro de um destino canônico do manifesto (lista do plano), tem ao menos 3 níveis e não é \Windows. #>
    param([string]$Path, [string[]]$Allowed)
    if (-not (Test-VantaPath $Path)) { return $false }
    if (@($Path.Split('\') | Where-Object { $_ }).Count -lt 3) { return $false }
    if ($Path -match '(?i)^[A-Za-z]:\\Windows(\\|$)') { return $false }
    return (Test-VantaInRoots -Path $Path -Roots $Allowed)
}
function Test-VantaRegText {
    <# $null se o .reg só toca HKCU e HKLM\SOFTWARE, sem apagar (chave, valor nomeado ou padrão) e sem o que inicia ou redireciona programas; senão o motivo. #>
    param([string]$Text)
    $first = @($Text.TrimStart([char]0xFEFF) -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })[0]
    if ($first -ne 'Windows Registry Editor Version 5.00' -and $first -ne 'REGEDIT4') { return 'sem cabeçalho de .reg' }
    $keys = 0
    foreach ($raw in ($Text -split "`r?`n")) {
        $line = $raw.Trim()
        if ($line.StartsWith('[')) {
            $key = $line.TrimStart('[').TrimEnd(']')
            if ($key.StartsWith('-')) { return "apaga chave inteira: $key" }
            if ($key -notmatch '^(?i)(HKEY_CURRENT_USER\\|HKEY_LOCAL_MACHINE\\SOFTWARE\\|HKEY_USERS\\S-1-5-21-[0-9-]+\\)') { return "chave fora de HKCU e HKLM\SOFTWARE: $key" }
            if (($key + '\') -match '(?i)\\(run|runonce|runservices|runonceex|policies|services|winlogon|classes|image file execution options|appinit_dlls|appcertdlls|silentprocessexit|session manager|lsa|safeboot)\\') { return "chave que inicia ou redireciona programas: $key" }
            $keys++
        }
        elseif (($line.StartsWith('"') -or $line.StartsWith('@')) -and $line.EndsWith('=-')) { return "apaga um valor: $line" }
    }
    if ($keys -eq 0) { return 'nenhuma chave' }
    return $null
}
function Get-VantaRegSections {
    <# As chaves de um .reg e, de cada uma, os valores (nome em minúsculas -> linha inteira, com as continuações juntas). #>
    param([string]$Text)
    $sections = New-Object Collections.Generic.List[object]
    $current = $null; $pending = ''
    foreach ($raw in ($Text -split "`r?`n")) {
        $line = $raw.TrimEnd()
        if ($pending) { $line = $pending + $line.TrimStart(); $pending = '' }
        if ($line.EndsWith('\') -and $line -match '^(@|"(?:[^"\\]|\\.)*")=(hex|dword)') { $pending = $line.Substring(0, $line.Length - 1); continue }
        if ($line.StartsWith('[') -and $line.EndsWith(']')) {
            $current = [pscustomobject]@{ Key = $line.Substring(1, $line.Length - 2); Values = @{}; Order = (New-Object Collections.Generic.List[string]) }
            $sections.Add($current)
            continue
        }
        if ($current -and $line -match '^(?<n>@|"(?:[^"\\]|\\.)*")=') {
            $name = $Matches['n'].ToLowerInvariant()
            if (-not $current.Values.ContainsKey($name)) { $current.Order.Add($name) }
            $current.Values[$name] = $line
        }
    }
    return , $sections
}
function Select-VantaNewRegValues {
    <# Dos valores da seção nova, fica só o que NÃO existe na chave atual. Existe igual: nada a fazer. Existe com outro dado: pula
       e devolve o nome em Skipped (nunca sobrescreve). #>
    param($Section, [string]$ExistingText)
    $existing = @{}
    foreach ($s in (Get-VantaRegSections $ExistingText)) { if ($s.Key -ieq $Section.Key) { $existing = $s.Values; break } }
    $lines = @(); $skipped = @()
    foreach ($name in $Section.Order) {
        $line = $Section.Values[$name]
        if ($existing.ContainsKey($name)) {
            if ($existing[$name] -cne $line) { $skipped += $name }
            continue
        }
        $lines += $line
    }
    return [pscustomobject]@{ Lines = $lines; Skipped = $skipped }
}
function Test-VantaTaskXml {
    <# $null se a tarefa só inicia programas (<Exec>) de lugares permitidos, sem variável de ambiente, como o usuário que restaura,
       e (PowerShell) só com -File exato de um script que está no plano com hash; senão o motivo. Com privilégio máximo, só de
       Program Files e das pastas só de administradores. #>
    param([string]$Xml, [string]$Sid, [string[]]$SafeRoots, [string[]]$PrivilegedRoots, [string[]]$RestoredRoots, [string[]]$Scripts, [string]$PowerShell, [string]$Cmd, [string]$UserProfile)
    if ($Xml -match '(?i)<!DOCTYPE|<!ENTITY|<!\[CDATA\[') { return 'DOCTYPE, entidade ou CDATA' }
    if ($Xml -match '(?i)<(ComHandler|SendEmail|ShowMessage|GroupId)') { return 'ação que não inicia um programa' }
    foreach ($m in [regex]::Matches($Xml, '<UserId>([^<]*)</UserId>')) {
        $who = $m.Groups[1].Value.Trim()
        if ($who -and $who -ne $Sid) { return "roda como '$who'" }
    }
    $elevated = $Xml -match '(?i)<RunLevel>HighestAvailable</RunLevel>'
    $actions = [regex]::Match($Xml, '(?s)<Actions[^>]*>(.*?)</Actions>')
    if (-not $actions.Success) { return 'sem <Actions>' }
    $body = $actions.Groups[1].Value
    if ([regex]::Replace($body, '(?s)<Exec>.*?</Exec>', '') -match '<[A-Za-z]') { return 'ação além de <Exec>' }
    $execs = [regex]::Matches($body, '(?s)<Exec>(.*?)</Exec>')
    if ($execs.Count -eq 0) { return 'sem ação <Exec>' }
    $safe = @($SafeRoots) + @($PrivilegedRoots)
    if (-not $elevated) { $safe += @($RestoredRoots) }
    foreach ($e in $execs) {
        $b = $e.Groups[1].Value
        if ([regex]::Replace($b, '(?s)<(Command|Arguments|WorkingDirectory)>.*?</\1>', '') -match '<[A-Za-z]') { return 'elemento extra no <Exec>' }
        $commands = [regex]::Matches($b, '(?s)<Command>(.*?)</Command>')
        if ($commands.Count -ne 1) { return 'precisa de exatamente um <Command>' }
        $raw = [Net.WebUtility]::HtmlDecode($commands[0].Groups[1].Value.Trim()).Trim('"')
        $args = [Net.WebUtility]::HtmlDecode([regex]::Match($b, '(?s)<Arguments>(.*?)</Arguments>').Groups[1].Value).Trim()
        if ($raw -match '%' -or $args -match '%') { return 'usa variável de ambiente' }
        if (-not (Test-VantaPath $raw) -or -not $raw.EndsWith('.exe', [StringComparison]::OrdinalIgnoreCase)) { return "comando sem caminho completo de .exe: $raw" }
        if ($raw -ieq $PowerShell) {
            $m = [regex]::Match($args, '(?i)^(?:-NoProfile |-NonInteractive |-NoLogo |-ExecutionPolicy (?:Bypass|RemoteSigned|AllSigned) |-WindowStyle (?:Hidden|Minimized) )*-File "([^"]+)"$')
            if (-not $m.Success) { return 'o PowerShell não usa exatamente -File "<script>"' }
            $script = $m.Groups[1].Value
            if (-not (Test-VantaPath $script) -or -not $script.EndsWith('.ps1', [StringComparison]::OrdinalIgnoreCase)) { return "script inválido: $script" }
            if (-not (Test-VantaInRoots -Path $script -Roots $safe)) { return "script fora de lugar permitido: $script" }
            if (@($Scripts | Where-Object { $_ -ieq $script }).Count -eq 0) { return "script sem hash no plano: $script" }
        }
        elseif ($raw -ieq $Cmd) {
            if ($elevated) { return 'cmd.exe em tarefa com privilégio máximo' }
            $m = [regex]::Match($args, '(?i)^/c "([^"&|<>^%]+\.(?:bat|cmd))"$')
            if (-not $m.Success) { return 'o cmd.exe não usa exatamente /c "<arquivo .bat>"' }
            $bat = $m.Groups[1].Value
            if (-not (Test-VantaPath $bat) -or -not $bat.StartsWith($UserProfile.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { return "arquivo fora do perfil do usuário: $bat" }
        }
        elseif (-not (Test-VantaInRoots -Path $raw -Roots $safe)) { return "programa fora de lugar permitido: $raw" }
    }
    return $null
}
function Get-VantaTaskIdentity {
    <# O que torna duas tarefas "a mesma": a ação inteira (sem espaços de formatação) e o nível de execução. #>
    param([string]$Xml)
    $actions = [regex]::Match($Xml, '(?s)<Actions[^>]*>(.*?)</Actions>').Groups[1].Value
    $level = if ($Xml -match '(?i)<RunLevel>HighestAvailable</RunLevel>') { 'highest' } else { 'least' }
    return ($level + '|' + ([regex]::Replace($actions, '\s+', ' ').Trim()))
}
function Read-VantaPlan {
    <# Lê o plano UMA vez, confere o SHA-256 dos bytes lidos e interpreta A PARTIR DA MEMÓRIA (nada é relido do disco). #>
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Sha256)
    $bytes = [IO.File]::ReadAllBytes($Path)
    $sha = [Security.Cryptography.SHA256]::Create()
    $hash = ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '').ToLowerInvariant()
    if ($hash -ne $Sha256.ToLowerInvariant()) { throw 'o plano foi alterado depois de gerado' }
    return [pscustomobject]@{ Plan = ([Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json); Bytes = $bytes }
}
function Copy-VantaVerified {
    <# Copia cada arquivo listado da origem para o RETRATO (pasta protegida), lendo uma vez com ninguém escrevendo (FileShare.Read)
       e conferindo o SHA-256 e o tamanho do plano. Devolve $null se tudo confere, ou o motivo. Nada sai do retrato sem conferir. #>
    param([string]$Source, [bool]$IsFolder, $Files, [string]$DestLeaf, [string]$Stage)
    $sha = [Security.Cryptography.SHA256]::Create()
    foreach ($file in @($Files)) {
        $rel = [string]$file.rel
        if (-not (Test-VantaRelPath $rel)) { return "caminho-relativo-recusado:$rel" }
        $src = if ($IsFolder) { Join-Path $Source $rel } else { $Source }
        $cur = $Source
        $levels = if ($IsFolder) { @($rel -split '\\') } else { @() }
        try {
            if (([IO.File]::GetAttributes($Source) -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return 'link-na-origem' }
            foreach ($part in $levels) { $cur = Join-Path $cur $part; if (([IO.File]::GetAttributes($cur) -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return "link-na-origem:$rel" } }
        } catch { return "origem-ilegivel:$rel" }
        $target = if ($IsFolder) { Join-Path $Stage $rel } else { Join-Path $Stage $DestLeaf }
        $null = New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent)
        $total = [int64]0
        try {
            $in = [IO.File]::Open($src, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
            try {
                $out = [IO.File]::Open($target, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
                try {
                    $sha.Initialize()
                    $buffer = New-Object byte[] 1048576
                    while (($n = $in.Read($buffer, 0, $buffer.Length)) -gt 0) {
                        $null = $sha.TransformBlock($buffer, 0, $n, $null, 0)
                        $out.Write($buffer, 0, $n)
                        $total += $n
                    }
                    $null = $sha.TransformFinalBlock($buffer, 0, 0)
                }
                finally { $out.Dispose() }
            }
            finally { $in.Dispose() }
        } catch { return "leitura-falhou:$rel" }
        $hash = ([BitConverter]::ToString($sha.Hash) -replace '-', '').ToLowerInvariant()
        if ($hash -ne ([string]$file.sha256).ToLowerInvariant() -or $total -ne [int64]$file.size) {
            Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
            return "hash-diferente:$rel"
        }
    }
    return $null
}
"#;

/// O programa do lado elevado, com o id da execução, o SID, o caminho do plano e o hash dele. Nada de texto do usuário
/// entra sem validação: id, SID, hash e nomes são conferidos aqui, e o caminho do plano entra entre aspas simples.
pub fn build_restore_script(
    run_id: &str,
    user_sid: &str,
    plan_path: &str,
    plan_sha256: &str,
) -> Result<String, String> {
    if !is_run_id(run_id) || !is_user_sid(user_sid) {
        return Err("Identificação da execução inválida.".into());
    }
    if plan_sha256.len() != 64 || !plan_sha256.chars().all(|c| c.is_ascii_hexdigit()) {
        return Err("Hash do plano inválido.".into());
    }
    if plan_path.contains(['\r', '\n', '\0']) {
        return Err("Caminho do plano inválido.".into());
    }
    let plan_path = plan_path.replace('\'', "''");
    Ok(format!(
        r#"$ErrorActionPreference = 'Stop'
{run_dir_ps}
{funcs}
try {{ $dir = New-VantaRunDir -Base $env:ProgramData -Guid '{run_id}' -UserSid '{user_sid}' }} catch {{ exit 3 }}
$results = Join-Path $dir 'resultados.txt'
function Say([string]$line) {{ Add-Content -LiteralPath $results -Value $line }}
function Test-Cancelled {{ return (Test-VantaCancelled) }}
$ErrorActionPreference = 'Continue'
try {{ $loaded = Read-VantaPlan -Path '{plan_path}' -Sha256 '{plan_sha256}'; $plan = $loaded.Plan }} catch {{ Say 'ERRO plano-adulterado-ou-ilegivel'; Say 'FIM'; exit 4 }}
[IO.File]::WriteAllBytes((Join-Path $dir 'plano.json'), $loaded.Bytes)
$sid = '{user_sid}'
$pf = $env:ProgramFiles; $pf86 = ${{env:ProgramFiles(x86)}}
$systemDirectory = [Environment]::SystemDirectory
$powerShellExe = Join-Path $systemDirectory 'WindowsPowerShell\v1.0\powershell.exe'
$cmdExe = Join-Path $systemDirectory 'cmd.exe'
$profilePath = [string](Get-ItemProperty -LiteralPath "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid" -Name ProfileImagePath -ErrorAction SilentlyContinue).ProfileImagePath
$allowed = @($plan.allowedDestinations)
$vantaArea = (Join-Path $env:ProgramData 'Vanta')
function Test-Target([string]$path) {{ return ((Test-VantaDestination -Path $path -Allowed $allowed) -and -not $path.StartsWith($vantaArea, [StringComparison]::OrdinalIgnoreCase)) }}
function Copy-FromStage([string]$stage, [string]$to, [bool]$folder, [string]$leaf) {{
    if ($folder) {{ $a = @($stage, $to, '/E') }} else {{ $a = @($stage, (Split-Path $to -Parent), $leaf) }}
    $a += @('/R:1', '/W:1', '/NP', '/NJH', '/NJS', '/XJ')
    & robocopy.exe @a *> $null
    return ($LASTEXITCODE -lt 8)
}}

# pastas só de administradores (C:\Vanta\System): criadas ou apertadas (dono e ACL pelo handle) ANTES de copiar para elas
$blocked = @()
foreach ($protectedDir in @($plan.protectedDirs)) {{
    $path = [string]$protectedDir
    if ($path -notmatch '^[A-Za-z]:\\Vanta\\[A-Za-z0-9_. -]+$' -or -not (Test-VantaInRoots -Path $path -Roots $allowed)) {{ $blocked += $path; Say "falha pasta-protegida caminho-recusado"; continue }}
    try {{
        $drive = $path.Substring(0, 2)
        foreach ($level in @("$drive\Vanta", $path)) {{ Use-VantaProtectedDir -Path $level -UserSid $sid }}
    }} catch {{ $blocked += $path; Say ('falha pasta-protegida ' + ($_.Exception.Message -replace '[\r\n]+', ' ')) }}
}}

foreach ($name in @($plan.services)) {{ if (Test-VantaName $name) {{ & sc.exe stop $name *> $null }} }}
foreach ($name in @($plan.processes)) {{ if (Test-VantaName $name) {{ Get-Process -Name $name -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue }} }}

$items = @($plan.items)
for ($i = 0; $i -lt $items.Count; $i++) {{
    if (Test-Cancelled) {{ break }}
    $it = $items[$i]; $destination = [string]$it.destination; $source = [string]$it.source
    if (-not (Test-VantaPath $source)) {{ Say "falha item $i origem-recusada"; continue }}
    if (-not (Test-Target $destination)) {{ Say "falha item $i destino-nao-permitido"; continue }}
    $inBlocked = @($blocked | Where-Object {{ Test-VantaInRoots -Path $destination -Roots @($_) }}).Count -gt 0
    if ($inBlocked) {{ Say "falha item $i pasta-protegida-recusada"; continue }}
    $stage = Join-Path $dir "item-$i"; $null = New-Item -ItemType Directory -Path $stage
    $leaf = Split-Path $destination -Leaf
    $bad = Copy-VantaVerified -Source $source -IsFolder ([bool]$it.isFolder) -Files $it.files -DestLeaf $leaf -Stage $stage
    if ($bad) {{ Say "falha item $i $bad"; continue }}
    if (Copy-FromStage $stage $destination ([bool]$it.isFolder) $leaf) {{ Say "ok item $i" }} else {{ Say "falha item $i robocopy" }}
}}

$texts = @($plan.texts)
for ($i = 0; $i -lt $texts.Count; $i++) {{
    if (Test-Cancelled) {{ break }}
    $tx = $texts[$i]; $destination = [string]$tx.destination
    if (-not (Test-Target $destination)) {{ Say "falha texto $i destino-nao-permitido"; continue }}
    $stage = Join-Path $dir "texto-$i"; $null = New-Item -ItemType Directory -Path $stage
    $leaf = Split-Path $destination -Leaf
    [IO.File]::WriteAllBytes((Join-Path $stage $leaf), [Convert]::FromBase64String([string]$tx.contentBase64))
    if (Copy-FromStage $stage $destination $false $leaf) {{ Say "ok texto $i" }} else {{ Say "falha texto $i robocopy" }}
}}

$regs = @($plan.registry)
for ($i = 0; $i -lt $regs.Count; $i++) {{
    if (Test-Cancelled) {{ break }}
    $text = [string]$regs[$i].text
    $why = Test-VantaRegText $text
    if ($why) {{ Say "falha registro $i $why"; continue }}
    if (-not (Test-Path -LiteralPath "Registry::HKEY_USERS\$sid")) {{ Say "pulada registro $i hive-do-usuario-nao-carregado"; continue }}
    $text = [regex]::Replace($text, '(?im)^\[HKEY_CURRENT_USER\\', "[HKEY_USERS\$sid\")
    $kept = New-Object Text.StringBuilder
    $null = $kept.AppendLine('Windows Registry Editor Version 5.00')
    $count = 0
    foreach ($section in (Get-VantaRegSections $text)) {{
        $existingText = ''
        $probe = Join-Path $dir "existente-$i.reg"
        & reg.exe export $section.Key $probe /y *> $null
        if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $probe)) {{ $existingText = [IO.File]::ReadAllText($probe); Remove-Item -LiteralPath $probe -Force }}
        $new = Select-VantaNewRegValues -Section $section -ExistingText $existingText
        foreach ($skipped in @($new.Skipped)) {{ Say ('aviso registro ' + $i + ' valor-existente-com-outro-dado:' + $section.Key + '|' + $skipped) }}
        if (@($new.Lines).Count -gt 0) {{
            $null = $kept.AppendLine(''); $null = $kept.AppendLine('[' + $section.Key + ']')
            foreach ($line in @($new.Lines)) {{ $null = $kept.AppendLine($line); $count++ }}
        }}
    }}
    if ($count -eq 0) {{ Say "ok registro $i sem-mudanca"; continue }}
    $enc = New-Object Text.UnicodeEncoding($false, $true)
    $file = Join-Path $dir "registro-$i.reg"
    [IO.File]::WriteAllBytes($file, ($enc.GetPreamble() + $enc.GetBytes($kept.ToString())))
    & reg.exe import $file *> $null
    if ($LASTEXITCODE -eq 0) {{ Say "ok registro $i" }} else {{ Say "falha registro $i reg-import" }}
}}

$safeRoots = @($pf, $pf86)
$tasks = @($plan.tasks)
for ($i = 0; $i -lt $tasks.Count; $i++) {{
    if (Test-Cancelled) {{ break }}
    $task = $tasks[$i]; $taskName = [string]$task.name; $xml = [string]$task.xml
    if (-not (Test-VantaName $taskName)) {{ Say "falha tarefa $i nome-recusado"; continue }}
    $planScripts = @($task.scripts | ForEach-Object {{ [string]$_.path }})
    $why = Test-VantaTaskXml -Xml $xml -Sid $sid -SafeRoots $safeRoots -PrivilegedRoots @($plan.protectedDirs) -RestoredRoots @($plan.restoredRoots) -Scripts $planScripts -PowerShell $powerShellExe -Cmd $cmdExe -UserProfile $profilePath
    if ($why) {{ Say "falha tarefa $i $why"; continue }}
    # o script da tarefa tem de ser, no disco, exatamente o que foi copiado e conferido
    $scriptProblem = $null
    foreach ($script in @($task.scripts)) {{
        $actual = $null
        try {{ $actual = (Get-FileHash -LiteralPath ([string]$script.path) -Algorithm SHA256).Hash.ToLowerInvariant() }} catch {{ }}
        if ($actual -ne ([string]$script.sha256).ToLowerInvariant()) {{ $scriptProblem = [string]$script.path }}
    }}
    if ($scriptProblem) {{ Say "pulada tarefa $i script-nao-confere:$scriptProblem"; continue }}
    $existing = & schtasks.exe /Query /TN $taskName /XML 2>$null
    if ($LASTEXITCODE -eq 0) {{
        if ((Get-VantaTaskIdentity ($existing -join "`n")) -ceq (Get-VantaTaskIdentity $xml)) {{ Say "ok tarefa $i ja-presente" }} else {{ Say "pulada tarefa $i ja-existe-outra-com-esse-nome" }}
        continue
    }}
    $enc = New-Object Text.UnicodeEncoding($false, $true)
    $file = Join-Path $dir "tarefa-$i.xml"
    [IO.File]::WriteAllBytes($file, ($enc.GetPreamble() + $enc.GetBytes($xml)))
    & schtasks.exe /Create /TN $taskName /XML $file *> $null
    if ($LASTEXITCODE -eq 0) {{ Say "ok tarefa $i" }} else {{ Say "falha tarefa $i schtasks" }}
}}

$runRoots = @($pf, $pf86) + @($plan.restoredRoots) + @($plan.protectedDirs)
$runs = @($plan.runs)
for ($i = 0; $i -lt $runs.Count; $i++) {{
    if (Test-Cancelled) {{ break }}
    $entry = $runs[$i]; $entryName = [string]$entry.name; $command = [string]$entry.command
    if (-not (Test-VantaName $entryName) -or $command -notmatch '^"[A-Za-z]:\\[^"]+\.exe"( [^&|<>`\r\n]*)?$') {{ Say "falha inicio $i comando-recusado"; continue }}
    $exe = $command.Substring(1, $command.IndexOf('"', 1) - 1)
    if (-not (Test-VantaPath $exe) -or -not (Test-VantaInRoots -Path $exe -Roots $runRoots)) {{ Say "falha inicio $i fora-de-lugar-permitido"; continue }}
    if (-not (Test-Path -LiteralPath "Registry::HKEY_USERS\$sid")) {{ Say "pulada inicio $i hive-do-usuario-nao-carregado"; continue }}
    $key = "Registry::HKEY_USERS\$sid\Software\Microsoft\Windows\CurrentVersion\Run"
    if (-not (Test-Path -LiteralPath $key)) {{ $null = New-Item -Path $key }}
    $current = (Get-ItemProperty -LiteralPath $key -Name $entryName -ErrorAction SilentlyContinue).$entryName
    if ($null -ne $current -and [string]$current -ne $command) {{ Say "pulada inicio $i ja-existe-outra-entrada-com-esse-nome"; continue }}
    if ($null -ne $current) {{ Say "ok inicio $i ja-presente"; continue }}
    New-ItemProperty -LiteralPath $key -Name $entryName -Value $command -PropertyType String | Out-Null
    Say "ok inicio $i"
}}
Say 'FIM'
"#,
        run_dir_ps = RUN_DIR_PS,
        funcs = WORKER_FUNCS_PS,
    ))
}

/// O que o lado elevado reportou de um item.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Status {
    Ok,
    Failed,
    Skipped,
    /// O item foi aplicado, mas com um aviso (ex.: um valor de registro que já existia com outro dado foi mantido).
    Warning,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    Item,
    Text,
    Registry,
    Task,
    Run,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ResultLine {
    pub status: Status,
    pub kind: Kind,
    pub index: usize,
    /// Motivo (falha ou pulada), "ja-presente" ou o aviso.
    pub detail: String,
}

#[derive(Debug, Default, PartialEq, Eq)]
pub struct WorkerReport {
    pub lines: Vec<ResultLine>,
    pub finished: bool,
    pub error: Option<String>,
    /// Falhas que não são de um item (ex.: uma pasta protegida recusada).
    pub general: Vec<String>,
}

impl WorkerReport {
    /// O resultado principal de um item (o primeiro que não é aviso).
    pub fn find(&self, kind: Kind, index: usize) -> Option<&ResultLine> {
        self.lines.iter().find(|l| l.kind == kind && l.index == index && l.status != Status::Warning)
    }

    pub fn warnings(&self, kind: Kind, index: usize) -> impl Iterator<Item = &ResultLine> {
        self.lines.iter().filter(move |l| l.kind == kind && l.index == index && l.status == Status::Warning)
    }
}

/// Lê o arquivo de resultados: `ok|falha|pulada|aviso <tipo> <índice> [motivo]`, `falha pasta-protegida <motivo>`,
/// `ERRO <texto>` e `FIM`.
pub fn parse_results(text: &str) -> WorkerReport {
    let mut report = WorkerReport::default();
    for line in text.lines().map(|l| l.trim_start_matches('\u{feff}').trim()).filter(|l| !l.is_empty()) {
        if line == "FIM" {
            report.finished = true;
        } else if let Some(error) = line.strip_prefix("ERRO ") {
            report.error = Some(error.to_owned());
        } else if let Some(reason) = line.strip_prefix("falha pasta-protegida") {
            report.general.push(format!("pasta protegida: {}", reason.trim()));
        } else {
            let mut parts = line.splitn(4, ' ');
            let (Some(status), Some(kind), Some(index)) = (parts.next(), parts.next(), parts.next()) else {
                continue;
            };
            let status = match status {
                "ok" => Status::Ok,
                "falha" => Status::Failed,
                "pulada" => Status::Skipped,
                "aviso" => Status::Warning,
                _ => continue,
            };
            let kind = match kind {
                "item" => Kind::Item,
                "texto" => Kind::Text,
                "registro" => Kind::Registry,
                "tarefa" => Kind::Task,
                "inicio" => Kind::Run,
                _ => continue,
            };
            let Ok(index) = index.parse::<usize>() else { continue };
            report.lines.push(ResultLine {
                status,
                kind,
                index,
                detail: parts.next().unwrap_or_default().to_owned(),
            });
        }
    }
    report
}

/// Roda o plano com UM pedido de administrador e devolve o relatório.
pub fn run_plan(plan: &RestorePlan, cancel: &CancelToken) -> io::Result<WorkerReport> {
    let sid =
        current_sid().ok_or_else(|| io::Error::other("Não foi possível identificar o usuário atual."))?;
    let program_data = std::env::var("ProgramData").unwrap_or_else(|_| r"C:\ProgramData".into());
    crate::restore_plan::validate_plan(plan, &program_data).map_err(io::Error::other)?;
    let run_id = new_run_id();
    let dir = run_dir(&program_data, &run_id);
    let (results, signal) = (dir.join("resultados.txt"), dir.join("cancelar.sinal"));
    let json = plan.to_json();
    let plan_path = std::env::temp_dir().join(format!("Vanta-plano-{run_id}.json"));
    fs::write(&plan_path, json.as_bytes())?;
    let finish = |outcome: io::Result<WorkerReport>| {
        let _ = fs::remove_file(&plan_path);
        outcome
    };
    let script =
        match build_restore_script(&run_id, &sid, &plan_path.to_string_lossy(), &sha256_hex(json.as_bytes()))
        {
            Ok(script) => script,
            Err(message) => return finish(Err(io::Error::other(message))),
        };
    let powershell = match crate::elevate::system_powershell() {
        Ok(path) => path.to_string_lossy().into_owned(),
        Err(error) => return finish(Err(error)),
    };
    let args = elevated_arguments(&script);
    if args.len() > MAX_PARAMETERS {
        return finish(Err(io::Error::other(
            "O programa do lado elevado ficou grande demais para a linha de comando do Windows.",
        )));
    }
    let process = match run_elevated(&powershell, &args, None) {
        Ok(process) => process,
        Err(error) => return finish(Err(error)),
    };
    // Depois de iniciado o lote não é interrompido no meio de um item: cancelar vale para o que ainda não começou.
    while !process.wait(400) {
        if cancel.is_cancelled() {
            crate::rundir::signal_cancel(&signal);
        }
        std::thread::sleep(Duration::from_millis(100));
    }
    let report = parse_results(&decode_results(&results));
    if report.lines.is_empty() && report.error.is_none() && process.exit_code() == Some(3) {
        return finish(Err(io::Error::other(
            "O lado elevado recusou a pasta de execução (ponto de reanálise, dono ou permissões inesperados).",
        )));
    }
    finish(Ok(report))
}

fn decode_results(path: &std::path::Path) -> String {
    fs::read(path).map(|bytes| crate::restore_batch::decode_text(&bytes)).unwrap_or_default()
}

/// Recusa do UAC reconhecida (reexporta para quem chama).
pub fn declined(error: &io::Error) -> bool {
    is_declined(error)
}

/// Nome seguro para mostrar (serviço/processo).
pub fn safe_name(name: &str) -> bool {
    valid_name(name)
}

#[cfg(test)]
mod tests {
    use std::process::Command;

    use super::*;

    const GUID: &str = "0f8fad5b-d9cb-469f-a165-70867728950e";
    const USER: &str = "S-1-5-21-111-222-333-1001";
    const HASH: &str = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";

    fn powershell(script: &str) -> (bool, String) {
        // o script vai por arquivo (UTF-8 com BOM): a linha de comando tem limite e o PowerShell 5.1 lê sem BOM como ANSI
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("t.ps1");
        let mut bytes = vec![0xEF, 0xBB, 0xBF];
        // The child writes in the console's OEM code page; the tests read UTF-8, so say so.
        bytes.extend(b"[Console]::OutputEncoding=[Text.Encoding]::UTF8
");
        bytes.extend(script.as_bytes());
        fs::write(&file, bytes).unwrap();
        let out = Command::new("powershell.exe")
            .args(["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File"])
            .arg(&file)
            .output()
            .unwrap();
        (
            out.status.success(),
            format!("{}{}", String::from_utf8_lossy(&out.stdout), String::from_utf8_lossy(&out.stderr)),
        )
    }

    #[test]
    fn the_worker_is_a_fixed_program_that_runs_no_script_from_the_user() {
        let script =
            build_restore_script(GUID, USER, r"C:\Users\x\AppData\Local\Temp\Vanta-plano-1.json", HASH)
                .unwrap();
        let lower = script.to_lowercase();
        assert!(
            !lower.contains("lote-elevado")
                && !lower.contains("cmd.exe /c")
                && !lower.contains("& $plan")
                && !lower.contains("invoke-expression")
                && !lower.contains("iex ")
        );
        assert!(
            script.contains("New-VantaRunDir -Base $env:ProgramData") && script.contains("catch { exit 3 }")
        );
        assert!(script.contains(&format!("-Sha256 '{HASH}'")), "o hash do plano vai na linha de comando");
        assert!(
            !lower.contains("$env:temp") && !lower.contains("vantabatch-"),
            "nada no temporário do usuário"
        );
        // o PowerShell e o cmd que o lado elevado reconhece vêm do diretório de sistema da API, não do ambiente
        assert!(
            script.contains("[Environment]::SystemDirectory")
                && !script.contains("$env:SystemRoot")
                && !script.contains("$env:windir")
        );
        // a ordem: pasta protegida, plano conferido, pastas protegidas do plano, e só então a cópia do retrato
        let run = script.find("New-VantaRunDir").unwrap();
        let read = script.find("Read-VantaPlan -Path").unwrap();
        let protect = script.find("Use-VantaProtectedDir -Path $level").unwrap();
        let verify = script.find("Copy-VantaVerified -Source").unwrap();
        let copy = script.find("Copy-FromStage $stage $destination").unwrap();
        assert!(run < read && read < protect && protect < verify && verify < copy);
        // cada item é conferido contra a lista de destinos permitidos antes de qualquer leitura
        assert!(script.find("Test-Target $destination").unwrap() < verify);
        assert!(!script.contains("/XF"), "o que vale é o hash de cada arquivo, não uma lista de extensões");
    }

    #[test]
    fn invalid_ids_sids_and_hashes_never_reach_the_script() {
        assert!(build_restore_script("..\\x", USER, "p", HASH).is_err());
        assert!(build_restore_script(GUID, "S-1-5-21-1;calc", "p", HASH).is_err());
        assert!(build_restore_script(GUID, USER, "p", "abc").is_err());
        assert!(build_restore_script(GUID, USER, "p\nq", HASH).is_err());
        let quoted = build_restore_script(GUID, USER, "C:\\a'b.json", HASH).unwrap();
        assert!(quoted.contains("C:\\a''b.json"), "aspas simples dobradas");
    }

    #[test]
    fn the_worker_script_is_valid_powershell_and_its_packed_command_fits_the_windows_limit() {
        let script = build_restore_script(GUID, USER, r"C:\Users\x\Temp\plano.json", HASH).unwrap();
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("worker.ps1");
        fs::write(&file, &script).unwrap();
        let check = format!(
            "$e=$null; [void][System.Management.Automation.Language.Parser]::ParseFile('{}', [ref]$null, [ref]$e); if ($e) {{ $e[0].Message; exit 1 }}",
            file.display()
        );
        let out = Command::new("powershell.exe").args(["-NoProfile", "-Command", &check]).output().unwrap();
        assert!(out.status.success(), "{}", String::from_utf8_lossy(&out.stdout));
        let args = elevated_arguments(&script);
        assert!(args.len() < MAX_PARAMETERS, "{} caracteres: passa do limite do ShellExecute", args.len());
    }

    #[test]
    fn the_elevated_side_rereads_the_plan_once_and_refuses_one_that_changed() {
        let dir = tempfile::tempdir().unwrap();
        let plan = dir.path().join("plano.json");
        let json = r#"{"version":2,"items":[]}"#;
        fs::write(&plan, json).unwrap();
        let good = sha256_hex(json.as_bytes());
        let run = |hash: &str| {
            powershell(&format!(
                "{WORKER_FUNCS_PS}\ntry {{ $r = Read-VantaPlan -Path '{}' -Sha256 '{hash}'; 'LIDO v' + $r.Plan.version }} catch {{ 'RECUSADO: ' + $_.Exception.Message }}",
                plan.display()
            ))
            .1
        };
        assert!(run(&good).contains("LIDO v2"), "{}", run(&good));
        fs::write(&plan, r#"{"version":2,"items":[{"source":"C:\\x","destination":"C:\\Windows\\y"}]}"#)
            .unwrap();
        assert!(run(&good).contains("RECUSADO: o plano foi alterado"), "{}", run(&good));
        assert!(run(&"0".repeat(64)).contains("RECUSADO"));
    }

    #[test]
    fn a_source_file_that_changed_after_the_plan_is_not_copied() {
        let source = tempfile::tempdir().unwrap();
        let stage = tempfile::tempdir().unwrap();
        fs::create_dir_all(source.path().join("sub")).unwrap();
        fs::write(source.path().join("a.ini"), "alpha").unwrap();
        fs::write(source.path().join(r"sub\b.dll"), "binario").unwrap();
        let files = crate::restore_plan::hash_source(source.path(), true).unwrap();
        let json = files
            .iter()
            .map(|f| format!("@{{ rel = '{}'; sha256 = '{}'; size = {} }}", f.rel, f.sha256, f.size))
            .collect::<Vec<_>>()
            .join(", ");
        let run = |stage: &std::path::Path| {
            powershell(&format!(
                "{WORKER_FUNCS_PS}\n$files = @({json})\n$r = Copy-VantaVerified -Source '{}' -IsFolder $true -Files $files -DestLeaf 'x' -Stage '{}'\nif ($r) {{ 'RECUSADO: ' + $r }} else {{ 'COPIADO' }}",
                source.path().display(),
                stage.display()
            ))
            .1
        };
        // tudo confere: o retrato fica com os bytes conferidos (inclusive uma .dll: o que vale é o hash)
        assert!(run(stage.path()).contains("COPIADO"), "{}", run(stage.path()));
        assert_eq!(fs::read(stage.path().join("a.ini")).unwrap(), b"alpha");
        assert_eq!(fs::read(stage.path().join(r"sub\b.dll")).unwrap(), b"binario");
        // um arquivo muda depois de o plano ser gerado: recusado, e o que não confere sai do retrato
        fs::write(source.path().join("a.ini"), "alterado").unwrap();
        let stage2 = tempfile::tempdir().unwrap();
        let out = run(stage2.path());
        assert!(out.contains("RECUSADO: hash-diferente:a.ini"), "{out}");
        assert!(!stage2.path().join("a.ini").exists(), "nada que não confere fica no retrato");
        // o mesmo tamanho com conteúdo diferente também não passa
        fs::write(source.path().join("a.ini"), "ALPHA").unwrap();
        assert!(run(tempfile::tempdir().unwrap().path()).contains("hash-diferente"));
    }

    #[test]
    fn a_junction_or_a_bad_relative_path_in_the_source_is_refused() {
        let source = tempfile::tempdir().unwrap();
        let elsewhere = tempfile::tempdir().unwrap();
        fs::write(elsewhere.path().join("segredo.txt"), "x").unwrap();
        let made = Command::new("cmd.exe")
            .args([
                "/c",
                "mklink",
                "/J",
                &source.path().join("atalho").to_string_lossy(),
                &elsewhere.path().to_string_lossy(),
            ])
            .output()
            .unwrap();
        assert!(made.status.success());
        let stage = tempfile::tempdir().unwrap();
        let hash = sha256_hex(b"x");
        let (_, out) = powershell(&format!(
            "{WORKER_FUNCS_PS}\n$f = @(@{{ rel = 'atalho\\segredo.txt'; sha256 = '{hash}'; size = 1 }})\nCopy-VantaVerified -Source '{}' -IsFolder $true -Files $f -DestLeaf 'x' -Stage '{}'\n$g = @(@{{ rel = '..\\fora.txt'; sha256 = '{hash}'; size = 1 }})\nCopy-VantaVerified -Source '{}' -IsFolder $true -Files $g -DestLeaf 'x' -Stage '{}'",
            source.path().display(),
            stage.path().display(),
            source.path().display(),
            stage.path().display()
        ));
        assert!(out.contains("link-na-origem:atalho") && out.contains("caminho-relativo-recusado"), "{out}");
        assert_eq!(fs::read_dir(stage.path()).unwrap().count(), 0);
    }

    #[test]
    fn the_elevated_side_checks_paths_destinations_names_registry_and_tasks_again() {
        let script = format!(
            r#"{WORKER_FUNCS_PS}
$out = @()
$out += 'path1=' + (Test-VantaPath 'C:\Users\a\b.txt')
foreach ($bad in 'C:\a\..\b', '\\srv\x', 'C:\a|b', 'rel\x', 'C:\a\\b') {{ $out += 'pathbad=' + (Test-VantaPath $bad) }}
$allowed = @('C:\Program Files\ISLC', 'C:\Vanta\System', 'C:\Windows\Fonts')
$out += 'dest1=' + (Test-VantaDestination 'C:\Program Files\ISLC\cfg\a.ini' $allowed)
foreach ($bad in 'C:\Program Files\Outro\a.ini', 'C:\Program Files', 'C:\Vanta', 'C:\Windows\Fonts\a.ttf', 'C:\Program Files\ISLC\..\x') {{ $out += 'destbad=' + (Test-VantaDestination $bad $allowed) }}
$out += 'name1=' + (Test-VantaName 'notepad++')
foreach ($bad in 'a"b', 'x; calc', ' x', '') {{ $out += 'namebad=' + (Test-VantaName $bad) }}
$hdr = "Windows Registry Editor Version 5.00`r`n"
$out += 'reg1=[' + (Test-VantaRegText ($hdr + "[HKEY_CURRENT_USER\Software\Obs]`r`n")) + ']'
$out += 'reg2=' + (Test-VantaRegText ($hdr + "[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run]`r`n"))
$out += 'reg3=' + (Test-VantaRegText ($hdr + "[HKEY_LOCAL_MACHINE\SYSTEM\X]`r`n"))
$out += 'reg4=' + (Test-VantaRegText ($hdr + "[-HKEY_CURRENT_USER\Software\Obs]`r`n"))
$out += 'reg5=' + (Test-VantaRegText ($hdr + "[HKEY_CURRENT_USER\Software\Obs]`r`n@=-`r`n"))
$out += 'reg6=' + (Test-VantaRegText ($hdr + "[HKEY_CURRENT_USER\Software\Obs]`r`n`"a`"=-`r`n"))
$sid = '{USER}'
$ps = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'; $cmd = 'C:\Windows\System32\cmd.exe'
$safe = @('C:\Program Files'); $priv = @('C:\Vanta\System'); $rest = @('C:\Users\a\AppData\Local\VantaSystem'); $scripts = @('C:\Vanta\System\VantaSystem.ps1')
function T($xml) {{ Test-VantaTaskXml -Xml $xml -Sid $sid -SafeRoots $safe -PrivilegedRoots $priv -RestoredRoots $rest -Scripts $scripts -PowerShell $ps -Cmd $cmd -UserProfile 'C:\Users\a' }}
function X($level, $command, $arguments) {{ '<Task><Principals><Principal><UserId>{USER}</UserId>' + $level + '</Principal></Principals><Actions><Exec><Command>' + $command + '</Command><Arguments>' + $arguments + '</Arguments></Exec></Actions></Task>' }}
$high = '<RunLevel>HighestAvailable</RunLevel>'
$out += 'task1=[' + (T (X $high 'C:\Program Files\ISLC\x.exe' '-minimized')) + ']'
$out += 'task2=[' + (T (X $high $ps '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File &quot;C:\Vanta\System\VantaSystem.ps1&quot;')) + ']'
$out += 'task3=' + (T (X $high $ps '-File &quot;C:\Users\a\AppData\Local\VantaSystem\a.ps1&quot;'))
$out += 'task4=' + (T (X $high $ps '-File &quot;C:\Vanta\System\Outro.ps1&quot;'))
$out += 'task5=' + (T (X $high $ps '-File &quot;C:\Vanta\System\VantaSystem.ps1&quot; extra'))
$out += 'task6=' + (T (X '' 'powershell.exe' '-File x'))
$out += 'task7=' + (T (X '' $cmd '/c &quot;C:\Users\a\AppData\Local\Overview\estudar.bat&quot;'))
$out += 'task8=' + (T (X $high $cmd '/c &quot;C:\Users\a\estudar.bat&quot;'))
$out += 'task9=' + (T (X '' $cmd '/c &quot;C:\Temp\x.bat&quot;'))
$out += 'task10=' + (T '<Task><Actions><Exec><Command>C:\Program Files\x.exe</Command></Exec><Other/></Actions></Task>')
$out += 'task11=' + (T '<Task><Actions><Exec><Command>C:\Program Files\x.exe</Command><Env>1</Env></Exec></Actions></Task>')
$out += 'task12=' + (T (X '' 'C:\Program Files\x.exe' '%TEMP%'))
$out += 'task13=' + (T ('<Task><Principals><Principal><UserId>S-1-5-18</UserId></Principal></Principals><Actions><Exec><Command>C:\Program Files\x.exe</Command></Exec></Actions></Task>'))
$out"#
        );
        let (ok, out) = powershell(&script);
        assert!(ok, "{out}");
        assert!(out.contains("path1=True"), "{out}");
        assert_eq!(out.matches("pathbad=False").count(), 5, "{out}");
        assert!(out.contains("dest1=True"), "{out}");
        assert_eq!(out.matches("destbad=False").count(), 5, "{out}");
        assert!(out.contains("name1=True"), "{out}");
        assert_eq!(out.matches("namebad=False").count(), 4, "{out}");
        assert!(out.contains("reg1=[]"), "{out}");
        for (n, why) in [
            ("reg2", "chave que inicia"),
            ("reg3", "chave fora de HKCU"),
            ("reg4", "apaga chave"),
            ("reg5", "apaga um valor"),
            ("reg6", "apaga um valor"),
        ] {
            assert!(out.contains(&format!("{n}={why}")), "{n}: {out}");
        }
        assert!(out.contains("task1=[]") && out.contains("task2=[]"), "{out}");
        for (n, why) in [
            ("task3", "script fora de lugar permitido"),
            ("task4", "script sem hash no plano"),
            ("task5", "o PowerShell não usa exatamente -File"),
            ("task6", "comando sem caminho completo"),
            ("task8", "cmd.exe em tarefa com privilégio máximo"),
            ("task9", "arquivo fora do perfil"),
            ("task10", "ação além de <Exec>"),
            ("task11", "elemento extra"),
            ("task12", "usa variável de ambiente"),
            ("task13", "roda como"),
        ] {
            assert!(out.contains(&format!("{n}={why}")), "{n}: {out}");
        }
        assert!(
            out.contains("task7=\r\n") || out.contains("task7=\n") || out.contains("task7=["),
            "a tarefa de usuário com cmd.exe passa: {out}"
        );
    }

    #[test]
    fn an_existing_registry_value_with_another_data_is_never_overwritten() {
        let script = format!(
            r#"{WORKER_FUNCS_PS}
$new = "Windows Registry Editor Version 5.00`r`n`r`n[HKEY_CURRENT_USER\Software\Obs]`r`n`"Igual`"=dword:00000001`r`n`"Outro`"=dword:00000002`r`n`"Novo`"=`"x`"`r`n@=`"padrao`"`r`n`"Bin`"=hex:01,02,`\`r`n  03,04`r`n"
$old = "Windows Registry Editor Version 5.00`r`n`r`n[HKEY_CURRENT_USER\Software\Obs]`r`n`"Igual`"=dword:00000001`r`n`"Outro`"=dword:00000009`r`n@=`"meu`"`r`n`"Bin`"=hex:01,02,`\`r`n  03,04`r`n`r`n[HKEY_CURRENT_USER\Software\Outra]`r`n`"x`"=dword:1`r`n"
$section = (Get-VantaRegSections $new)[0]
$r = Select-VantaNewRegValues -Section $section -ExistingText $old
'lines=' + (@($r.Lines) -join ' || ')
'skipped=' + (@($r.Skipped) -join ',')
$none = Select-VantaNewRegValues -Section $section -ExistingText ''
'semchave=' + @($none.Lines).Count + ' skipped=' + @($none.Skipped).Count"#
        );
        let (ok, out) = powershell(&script);
        assert!(ok, "{out}");
        assert!(
            out.contains("lines=\"Novo\"=\"x\"\r\n") || out.contains("lines=\"Novo\"=\"x\""),
            "só o valor novo entra: {out}"
        );
        assert!(!out.contains("lines=\"Novo\"=\"x\" ||"), "nada mais além do novo: {out}");
        assert!(
            out.contains("skipped=\"outro\",@") || out.contains("skipped=\"outro\"") && out.contains("@"),
            "{out}"
        );
        assert!(out.contains("semchave=5 skipped=0"), "chave que não existe: tudo entra: {out}");
    }

    #[test]
    fn the_results_are_read_line_by_line() {
        let report = parse_results(
            "\u{feff}ok item 0\r\nfalha item 1 robocopy\r\npulada tarefa 0 ja-existe-outra-com-esse-nome\r\nok inicio 2 ja-presente\r\naviso registro 3 valor-existente-com-outro-dado:k|\"a\"\r\nfalha pasta-protegida dono nao confiavel\r\nlixo\r\nFIM\r\n",
        );
        assert!(report.finished && report.error.is_none());
        assert_eq!(report.find(Kind::Item, 0).unwrap().status, Status::Ok);
        let failed = report.find(Kind::Item, 1).unwrap();
        assert_eq!((failed.status, failed.detail.as_str()), (Status::Failed, "robocopy"));
        assert_eq!(report.find(Kind::Task, 0).unwrap().status, Status::Skipped);
        assert_eq!(report.find(Kind::Run, 2).unwrap().detail, "ja-presente");
        assert!(report.find(Kind::Registry, 3).is_none(), "um aviso não é o resultado do item");
        assert_eq!(report.warnings(Kind::Registry, 3).count(), 1);
        assert_eq!(report.general, ["pasta protegida: dono nao confiavel"]);
        assert_eq!(parse_results("ERRO plano").error.as_deref(), Some("plano"));
    }
}
