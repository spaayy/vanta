//! Instalação em lote com UM pedido de administrador (UAC). O trabalho roda num PowerShell elevado que instala
//! os programas um por vez e, logo depois de cada um, FECHA o que o instalador abriu (o fechamento tem de rodar
//! aí dentro: um processo comum não fecha um elevado). Depois do TeamSpeak ele tira o Overwolf.
//! O resultado e o sinal de cancelamento ficam em `%ProgramData%\Vanta\run\<guid>`, pasta criada pelo lado elevado
//! com ACL (ver [`crate::rundir`]): o app comum só LÊ o resultado e só ESCREVE no arquivo-sinal.

use std::collections::HashSet;
use std::fs;
use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use vanta_core::install::{
    BatchInstaller, BatchResult, CancelToken, DISCORD_ID, Progress, VENCORD_ID, is_success, processes_to_close,
};

use crate::elevate::{is_declined, run_elevated};
use crate::restore_batch::current_sid;
use crate::rundir::{RUN_DIR_PS, is_run_id, is_user_sid, run_dir};

/// Id do winget aceito pelo lote: começa com letra ou dígito, depois letras, dígitos e `. + _ -`.
pub fn is_safe_id(id: &str) -> bool {
    if id.starts_with("github:") {
        return vanta_core::catalog::github_repo(id).is_some();
    }
    let mut chars = id.chars();
    chars.next().is_some_and(|c| c.is_ascii_alphanumeric())
        && id.len() <= 150
        && chars.all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '+' | '_' | '-'))
}

fn ps_list(items: impl IntoIterator<Item = impl AsRef<str>>) -> String {
    items.into_iter().map(|i| format!("'{}'", i.as_ref().replace('\'', "''"))).collect::<Vec<_>>().join(",")
}

/// O instalador de linha de comando OFICIAL do Vencord (github.com/Vencord/Installer, release v1.4.2, ativo
/// `VencordInstallerCli.exe`). O hash é o `digest` sha256 que o GitHub publica para o ativo: baixou outra coisa, não roda.
pub const VENCORD_CLI_URL: &str =
    "https://github.com/Vencord/Installer/releases/download/v1.4.2/VencordInstallerCli.exe";
pub const VENCORD_CLI_SHA256: &str = "15268aba25625797bf562187dd87ddadf42882e079c7b6192880ad3e83353ef5";
/// Parâmetros oficiais do CLI (`-install`, `-branch auto|stable|ptb|canary`): instala o Vencord no Discord estável.
pub const VENCORD_CLI_ARGS: [&str; 3] = ["-install", "-branch", "stable"];

/// Códigos do passo do Vencord no arquivo de resultados (`<código> Vencord`); fora estes, é o código do próprio CLI.
pub const VENCORD_DISCORD_OPEN: i32 = 20;
pub const VENCORD_DOWNLOAD_FAILED: i32 = 21;
pub const VENCORD_HASH_MISMATCH: i32 = 22;

/// O trecho do trabalhador que instala o Vencord: Discord fechado, instalador baixado para a pasta de execução (só
/// administradores escrevem nela), conferido pelo hash e rodado. Devolve o código; nada do usuário entra no texto.
fn vencord_step() -> String {
    r#"function Vencord {
    Add-Content -LiteralPath $results -Value 'start Vencord'
    Get-Process -Name Discord | Where-Object { $_.SessionId -eq $sid } | Stop-Process -Force
    Start-Sleep -Seconds 2
    if (Get-Process -Name Discord | Where-Object { $_.SessionId -eq $sid }) { return @@OPEN@@ }
    $exe = Join-Path $dir 'VencordInstallerCli.exe'
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '@@URL@@' -OutFile $exe -UseBasicParsing -ErrorAction Stop } catch { return @@DOWNLOAD@@ }
    if ((Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash -ne '@@SHA@@') { Remove-Item -LiteralPath $exe -Force; return @@HASH@@ }
    & $exe @@ARGS@@ *> $null
    $c = $LASTEXITCODE
    Remove-Item -LiteralPath $exe -Force
    return $c
}
"#
    .replace("@@OPEN@@", &VENCORD_DISCORD_OPEN.to_string())
    .replace("@@DOWNLOAD@@", &VENCORD_DOWNLOAD_FAILED.to_string())
    .replace("@@HASH@@", &VENCORD_HASH_MISMATCH.to_string())
    .replace("@@URL@@", VENCORD_CLI_URL)
    .replace("@@SHA@@", VENCORD_CLI_SHA256)
    .replace("@@ARGS@@", &VENCORD_CLI_ARGS.join(" "))
}

/// Como a execução termina para o Vencord, a partir do que o trabalhador gravou.
pub fn vencord_result(report: &WorkerReport, discord_ok: bool) -> BatchResult {
    let code = report.done.iter().find(|(id, _)| id == VENCORD_ID).map(|(_, code)| *code);
    let (success, message) = match code {
        Some(0) => (true, "Vencord instalado.".to_owned()),
        Some(VENCORD_DISCORD_OPEN) => (false, "Feche o Discord e instale o Vencord de novo.".to_owned()),
        Some(VENCORD_DOWNLOAD_FAILED) => (false, "Não foi possível baixar o instalador do Vencord.".to_owned()),
        Some(VENCORD_HASH_MISMATCH) => (
            false,
            "O instalador baixado não é o esperado (hash diferente); nada foi executado.".to_owned(),
        ),
        Some(other) => (false, format!("O instalador do Vencord retornou {other}.")),
        None if !discord_ok => (false, "Não executado: o Discord não foi instalado.".to_owned()),
        None => (false, "Não executado (lote cancelado ou interrompido).".to_owned()),
    };
    BatchResult { id: VENCORD_ID.into(), success, message }
}

/// O script do trabalhador elevado. Os ids, o id da execução e o SID são validados; nenhum texto do usuário entra
/// no script sem aspas. A pasta de execução é criada AQUI, no lado elevado.
pub fn build_worker_script(
    ids: &[String],
    interactive: &HashSet<String>,
    run_id: &str,
    user_sid: &str,
    local_app_data: &str,
    vencord: bool,
) -> Result<String, String> {
    if ids.len() > 200 || ids.iter().any(|id| !is_safe_id(id)) {
        return Err("Lista de programas inválida.".into());
    }
    if !is_run_id(run_id) || !is_user_sid(user_sid) {
        return Err("Identificação da execução inválida.".into());
    }
    // O Vencord só vai junto com o Discord, e só depois de ele instalar com sucesso (a chamada fica no `if` do sucesso).
    let vencord = vencord && ids.iter().any(|id| id == DISCORD_ID);
    let (vencord_fn, vencord_call) = if vencord {
        (
            vencord_step(),
            format!(
                "if ($id -eq '{DISCORD_ID}') {{ $vc = Vencord; Add-Content -LiteralPath $results -Value ([string]$vc + ' {VENCORD_ID}') }}"
            ),
        )
    } else {
        (String::new(), String::new())
    };
    let gui: Vec<&String> = ids.iter().filter(|id| !processes_to_close(id).is_empty()).collect();
    // Só os processos que ESTE programa abre ao instalar (lista fixa do catálogo); nada além deles é fechado.
    let closing = ids
        .iter()
        .filter(|id| !processes_to_close(id).is_empty())
        .map(|id| format!("'{}'=@({})", id.replace('\'', "''"), ps_list(processes_to_close(id))))
        .collect::<Vec<_>>()
        .join(";");
    let interactive_ids: Vec<&String> = ids.iter().filter(|id| interactive.contains(*id)).collect();
    Ok(format!(
        r#"$ErrorActionPreference='Stop'
{run_dir_ps}
try {{ $dir = New-VantaRunDir -Base $env:ProgramData -Guid '{run_id}' -UserSid '{user_sid}' }} catch {{ exit 3 }}
$results = Join-Path $dir 'resultados.txt'
$ErrorActionPreference='SilentlyContinue'
$sid=(Get-Process -Id $PID).SessionId
$lad='{lad}'; $pf=$env:ProgramFiles; $pf86=${{env:ProgramFiles(x86)}}
$skip='winget','WindowsPackageManagerServer','msiexec','powershell','pwsh','conhost','OpenConsole','WindowsTerminal','explorer'
$pkg=Get-AppxPackage -Name Microsoft.DesktopAppInstaller | Where-Object PublisherId -eq '8wekyb3d8bbwe' | Select-Object -First 1
$winget=Join-Path $pkg.InstallLocation 'winget.exe'
$trusted=[IO.Path]::Combine([Environment]::GetFolderPath('ProgramFiles'),'WindowsApps') + '\'
if (!$winget.StartsWith($trusted,[StringComparison]::OrdinalIgnoreCase)) {{ Add-Content -LiteralPath $results -Value 'ERRO winget-nao-encontrado'; Add-Content -LiteralPath $results -Value 'FIM'; exit 1 }}
$gui=@({gui}); $interactive=@({interactive}); $close=@{{{closing}}}
function GithubInstalar($repo) {{
    # Última release do repositório: só HTTPS e hosts do GitHub em cada redirecionamento, sha256 obrigatório, nome local gerado por nós.
    try {{
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $h = @{{ 'User-Agent' = 'VantaManager'; 'Accept' = 'application/vnd.github+json' }}
        $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" -Headers $h -UseBasicParsing -ErrorAction Stop
        $a = EscolherAsset $rel.assets
        if (-not $a) {{ return 30 }}
        # O digest sha256 da API é OBRIGATÓRIO: sem ele (ou malformado) nada é baixado nem executado.
        if ($a.digest -notmatch '^sha256:([0-9a-fA-F]{{64}})$') {{ return 34 }}
        $esperado = $Matches[1]
        # Só .msi/.exe, com nome simples; o arquivo local nunca usa o nome vindo da URL.
        if ($a.name -notmatch '^[A-Za-z0-9._()+-]{{1,150}}\.(msi|exe)$') {{ return 35 }}
        $ext = [IO.Path]::GetExtension($a.name).ToLowerInvariant()
        $f = Join-Path $dir ('github-' + [guid]::NewGuid().ToString('N') + $ext)
        $hosts = 'github.com','objects.githubusercontent.com','release-assets.githubusercontent.com'
        # Redirecionamentos seguidos à mão: CADA salto tem de ser https e de um host do GitHub.
        $url = $a.browser_download_url
        for ($salto = 0; $salto -le 5; $salto++) {{
            $u = [Uri]$url
            if ($u.Scheme -ne 'https' -or $u.Host -notin $hosts) {{ return 31 }}
            $req = [Net.HttpWebRequest]::Create($u); $req.AllowAutoRedirect = $false; $req.UserAgent = 'VantaManager'
            $resp = $req.GetResponse()
            try {{
                $code = [int]$resp.StatusCode
                if ($code -ge 300 -and $code -lt 400) {{ $url = [Uri]::new($u, $resp.Headers['Location']).AbsoluteUri; continue }}
                if ($code -ne 200) {{ return 36 }}
                $out = [IO.File]::Create($f)
                try {{ $resp.GetResponseStream().CopyTo($out) }} finally {{ $out.Dispose() }}
            }} finally {{ $resp.Close() }}
            break
        }}
        if (-not (Test-Path -LiteralPath $f)) {{ return 37 }}
        if ((Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash -ne $esperado) {{ Remove-Item -LiteralPath $f -Force; return 32 }}
        if ($ext -eq '.msi') {{ $p = Start-Process msiexec.exe -ArgumentList '/i',('"'+$f+'"'),'/qn','/norestart' -Wait -PassThru }}
        else {{ $p = Start-Process -FilePath $f -ArgumentList '/S' -Wait -PassThru }}
        Remove-Item -LiteralPath $f -Force
        return $p.ExitCode
    }} catch {{
        # 403/429 da API (ou do download) é a cota por IP do GitHub: tem código próprio para a mensagem ser clara.
        $http = 0; try {{ $http = [int]$_.Exception.Response.StatusCode }} catch {{ }}
        if ($http -eq 403 -or $http -eq 429) {{ return 38 }}
        return 33
    }}
}}
function EscolherAsset($assets) {{
    # Prefere instalador (.msi, depois .exe) de Windows x64; ignora o que é de outro sistema, ARM ou portátil/zip.
    $ok = @($assets | Where-Object {{ $_.name -match '\.(msi|exe)$' -and $_.name -notmatch '(?i)(arm|aarch|linux|mac|darwin|portable|\.blockmap)' }})
    $pref = @($ok | Where-Object {{ $_.name -match '(?i)(setup|install|x64|win)' }})
    if ($pref.Count) {{ $ok = $pref }}
    $ok = @($ok | Sort-Object @{{ Expression = {{ if ($_.name -like '*.msi') {{ 0 }} else {{ 1 }} }} }}, name)
    if ($ok.Count) {{ return $ok[0] }}
    return $null
}}
function Fechar($since,$rounds,$names) {{
    if (-not $names) {{ return }}
    $killed=0; $quiet=0
    for ($i=0; $i -lt $rounds; $i++) {{
        Start-Sleep -Milliseconds 1000
        $n=@(Get-Process | Where-Object {{ $_.SessionId -eq $sid -and $_.Id -ne $PID -and $_.StartTime -ge $since -and $_.Name -notin $skip -and $_.Name -in $names -and $_.Path -and ($_.Path -like "$pf\*" -or $_.Path -like "$pf86\*" -or $_.Path -like "$lad\*") }})
        if ($n.Count) {{ $n | Stop-Process -Force; $killed+=$n.Count; $quiet=0 }} elseif ($killed -gt 0) {{ $quiet++; if ($quiet -ge 2) {{ break }} }}
    }}
}}
function EstadoOverwolf {{
    # Cada item é um texto. QUALQUER erro de consulta (terminante ou não) interrompe a coleta inteira e o chamador não
    # limpa nada: o modo silencioso do resto do script não vale aqui.
    $ErrorActionPreference='Stop'
    $e=@()
    foreach ($d in "$pf86\Overwolf","$pf\Overwolf","$lad\Overwolf") {{ if (Test-Path -LiteralPath $d -ErrorAction Stop) {{ $e+="d|$d" }} }}
    foreach ($k in 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run','HKLM:\Software\Microsoft\Windows\CurrentVersion\Run','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run') {{
        if (-not (Test-Path -LiteralPath $k -ErrorAction Stop)) {{ continue }}
        foreach ($p in (Get-ItemProperty -LiteralPath $k -ErrorAction Stop).PSObject.Properties) {{ if ($p.Name -like '*Overwolf*') {{ $e+="r|$k|$($p.Name)" }} }}
    }}
    foreach ($u in 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall','HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall') {{
        if (-not (Test-Path -LiteralPath $u -ErrorAction Stop)) {{ continue }}
        foreach ($k in Get-ChildItem -LiteralPath $u -ErrorAction Stop) {{ if ((Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction Stop).DisplayName -like 'Overwolf*') {{ $e+="u|$($k.PSPath)" }} }}
    }}
    foreach ($t in Get-ScheduledTask -ErrorAction Stop) {{ if ($t.TaskName -like '*Overwolf*') {{ $e+="t|$($t.TaskPath)|$($t.TaskName)" }} }}
    foreach ($r in "$env:PUBLIC\Desktop","$env:USERPROFILE\Desktop","$env:ProgramData\Microsoft\Windows\Start Menu\Programs") {{
        if (-not (Test-Path -LiteralPath $r -ErrorAction Stop)) {{ continue }}
        foreach ($f in Get-ChildItem -LiteralPath $r -Recurse -Filter '*Overwolf*' -ErrorAction Stop) {{ $e+="l|$($f.FullName)" }}
    }}
    $e
}}
function AntesOverwolf {{
    # O inventário de antes da instalação; $null quando não foi possível lê-lo (então nada será removido depois).
    try {{ return ,@(EstadoOverwolf) }} catch {{ return $null }}
}}
function NovosOverwolf($antes,$depois) {{
    # Item a item: só entra o que NÃO estava antes. Itens iguais antes e depois nunca viram remoção.
    $conhecidos=@{{}}
    foreach ($i in @($antes)) {{ $conhecidos[[string]$i]=$true }}
    foreach ($i in @($depois)) {{ if (-not $conhecidos.ContainsKey([string]$i)) {{ [string]$i }} }}
}}
function SemOverwolf($antes) {{
    if ($null -eq $antes) {{ return }}
    try {{ $depois=@(EstadoOverwolf) }} catch {{ return }}
    $novos=@(NovosOverwolf $antes $depois)
    if (-not $novos.Count) {{ return }}
    Get-Process | Where-Object {{ ($_.Name -like 'Overwolf*' -or $_.Path -like '*\Overwolf\*') -and $_.StartTime -ge $since }} | Stop-Process -Force
    foreach ($i in $novos) {{
        $p=$i.Split('|')
        switch ($p[0]) {{
            'r' {{ Remove-ItemProperty -LiteralPath $p[1] -Name $p[2] }}
            't' {{ Unregister-ScheduledTask -TaskPath $p[1] -TaskName $p[2] -Confirm:$false }}
            default {{ Remove-Item -LiteralPath $p[1] -Recurse -Force }}
        }}
    }}
}}
{vencord_fn}foreach ($id in @({ids})) {{
    if (Test-VantaCancelled) {{ break }}
    Add-Content -LiteralPath $results -Value ('start ' + $id)
    $since=Get-Date
    $overwolfAntes = $null
    if ($id -eq 'TeamSpeakSystems.TeamSpeakClient') {{ $overwolfAntes = AntesOverwolf }}
    $mode = if ($interactive -contains $id) {{ @('--interactive') }} else {{ @('--silent','--disable-interactivity') }}
    if ($id -like 'github:*') {{ $code = GithubInstalar $id.Substring(7) }}
    else {{
        & $winget install --id $id --exact --source winget @mode --no-upgrade --accept-source-agreements --accept-package-agreements *> $null
        $code=$LASTEXITCODE
    }}
    if ($code -in 0,3010,1641,-1978335189,-1978335135) {{
        # Só tira o que NASCEU nesta instalação do TeamSpeak (comparado ao estado de antes); o que já existia é do usuário.
        if ($id -eq 'TeamSpeakSystems.TeamSpeakClient') {{ SemOverwolf $overwolfAntes }}
        Fechar $since $(if ($gui -contains $id) {{ 10 }} else {{ 1 }}) $close[$id]
        {vencord_call}
    }}
    Add-Content -LiteralPath $results -Value ([string]$code + ' ' + $id)
}}
Add-Content -LiteralPath $results -Value 'FIM'
"#,
        run_dir_ps = RUN_DIR_PS,
        lad = local_app_data.replace('\'', "''"),
        gui = ps_list(gui),
        closing = closing,
        interactive = ps_list(interactive_ids),
        ids = ps_list(ids),
        vencord_fn = vencord_fn,
        vencord_call = vencord_call,
    ))
}

/// Base64 do texto em UTF-16LE, o formato do `powershell -EncodedCommand`.
pub fn encode_command(script: &str) -> String {
    const TABLE: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let bytes: Vec<u8> = script.encode_utf16().flat_map(u16::to_le_bytes).collect();
    let mut out = String::with_capacity(bytes.len().div_ceil(3) * 4);
    for chunk in bytes.chunks(3) {
        let n = (u32::from(chunk[0]) << 16)
            | (u32::from(*chunk.get(1).unwrap_or(&0)) << 8)
            | u32::from(*chunk.get(2).unwrap_or(&0));
        out.push(TABLE[(n >> 18) as usize & 63] as char);
        out.push(TABLE[(n >> 12) as usize & 63] as char);
        out.push(if chunk.len() > 1 { TABLE[(n >> 6) as usize & 63] as char } else { '=' });
        out.push(if chunk.len() > 2 { TABLE[n as usize & 63] as char } else { '=' });
    }
    out
}

/// O carregador: um texto pequeno que descomprime o programa (Deflate) e o executa. Só tem letras, dígitos, `+/=` e a sintaxe
/// fixa do PowerShell: nada nele precisa de escape.
/// O `ShellExecute` aceita no máximo 32 767 caracteres de parâmetros, e o programa por extenso em UTF-16 + base64 passa
/// disso. O carregador só descomprime o que o app mesmo montou; nada vem de fora.
pub fn pack_command(script: &str) -> String {
    use std::io::Write;

    use flate2::Compression;
    use flate2::write::DeflateEncoder;

    let mut encoder = DeflateEncoder::new(Vec::new(), Compression::best());
    let _ = encoder.write_all(script.as_bytes());
    let packed = encoder.finish().unwrap_or_default();
    let loader = format!(
        "$b=[Convert]::FromBase64String('{}');$m=New-Object IO.MemoryStream(,$b);$d=New-Object IO.Compression.DeflateStream($m,[IO.Compression.CompressionMode]::Decompress);$r=New-Object IO.StreamReader($d,[Text.Encoding]::UTF8);& ([scriptblock]::Create($r.ReadToEnd()))",
        crate::restore_plan::base64(&packed)
    );
    loader
}

/// Os parâmetros do PowerShell elevado: o carregador em texto simples entre aspas (o `-EncodedCommand` dobraria o tamanho
/// por causa do UTF-16). O `ShellExecute` aceita no máximo 32 767 caracteres de parâmetros.
pub fn elevated_arguments(script: &str) -> String {
    format!(
        "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command \"{}\"",
        pack_command(script)
    )
}

/// Limite de parâmetros do `ShellExecute`, com folga.
pub const MAX_PARAMETERS: usize = 30_000;

#[derive(Debug, Default, PartialEq, Eq)]
pub struct WorkerReport {
    pub started: Vec<String>,
    pub done: Vec<(String, i32)>,
    pub finished: bool,
    pub error: Option<String>,
}

/// Lê o arquivo de resultados do trabalhador: `start <id>`, `<código> <id>`, `ERRO <texto>` e `FIM`.
pub fn parse_results(text: &str) -> WorkerReport {
    let mut report = WorkerReport::default();
    for line in text.lines().map(|l| l.trim_start_matches('\u{feff}').trim()).filter(|l| !l.is_empty()) {
        if line == "FIM" {
            report.finished = true;
        } else if let Some(id) = line.strip_prefix("start ") {
            report.started.push(id.to_owned());
        } else if let Some(error) = line.strip_prefix("ERRO ") {
            report.error = Some(error.to_owned());
        } else if let Some((code, id)) = line.split_once(' ')
            && let Ok(code) = code.parse::<i32>()
        {
            report.done.push((id.to_owned(), code));
        }
    }
    report
}

/// O que cada código de `GithubInstalar` quer dizer (nada disso é do WinGet).
pub fn github_message(code: i32) -> String {
    match code {
        30 => "A última versão no GitHub não tem instalador .msi ou .exe para Windows x64.".into(),
        31 => "O download saiu dos endereços permitidos do GitHub; nada foi executado.".into(),
        32 => "O instalador baixado não é o esperado (hash diferente); nada foi executado.".into(),
        33 => "Não foi possível consultar ou baixar do GitHub (sem rede ou serviço indisponível). Tente instalar de novo em alguns minutos.".into(),
        34 => "A versão no GitHub não informa o hash SHA-256; por segurança nada foi baixado.".into(),
        35 => "O nome do instalador no GitHub não é aceito; nada foi executado.".into(),
        36 | 37 => "O GitHub não entregou o arquivo do instalador. Tente instalar de novo.".into(),
        38 => "O GitHub limitou as consultas (cota da API excedida, HTTP 403). Aguarde cerca de uma hora ou troque de rede e instale de novo.".into(),
        other => format!("O instalador retornou {other}."),
    }
}

/// Anota o resultado do lote em `%LOCALAPPDATA%\Vanta\Logs\instalacao_<segundos>.log`, a pasta que a página Registros lista.
/// Só escreve se algo falhou; sem a pasta ou sem permissão, segue sem erro (o log não pode derrubar a instalação).
pub fn write_install_log(local_app_data: &str, results: &[BatchResult]) {
    if local_app_data.is_empty() || results.iter().all(|r| r.success) {
        return;
    }
    let dir = std::path::Path::new(local_app_data).join("Vanta").join("Logs");
    let secs = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_or(0, |d| d.as_secs());
    let text: String = results
        .iter()
        .map(|r| format!("{} {}: {}
", if r.success { "OK   " } else { "FALHA" }, r.id, r.message))
        .collect();
    let _ = std::fs::create_dir_all(&dir).and_then(|()| std::fs::write(dir.join(format!("instalacao_{secs}.log")), text));
}

/// Transforma o que o trabalhador reportou em resultado por id; o que não rodou vira falha.
pub fn results_for(ids: &[String], report: &WorkerReport, declined: Option<&str>) -> Vec<BatchResult> {
    ids.iter()
        .map(|id| {
            if let Some(message) = declined {
                return BatchResult { id: id.clone(), success: false, message: message.to_owned() };
            }
            match report.done.iter().find(|(done, _)| done == id) {
                Some((_, code)) if is_success(*code) => {
                    BatchResult {
                        id: id.clone(), success: true, message: "Instalado ou já presente.".into()
                    }
                }
                Some((_, code)) => BatchResult {
                    id: id.clone(),
                    success: false,
                    message: if vanta_core::catalog::github_repo(id).is_some() {
                        github_message(*code)
                    } else {
                        format!("WinGet retornou {code}.")
                    },
                },
                None => BatchResult {
                    id: id.clone(),
                    success: false,
                    message: report
                        .error
                        .clone()
                        .unwrap_or_else(|| "Não executado (lote cancelado ou interrompido).".into()),
                },
            }
        })
        .collect()
}

/// Id da execução: 128 bits de entropia do sistema em formato GUID. A pasta é criada pelo lado elevado e a execução
/// falha se ela já existir, então um id previsível não ajudaria ninguém.
pub fn new_run_id() -> String {
    use std::hash::{BuildHasher, Hasher, RandomState};
    let mut bytes = [0u8; 16];
    for (i, chunk) in bytes.chunks_mut(8).enumerate() {
        let mut hasher = RandomState::new().build_hasher();
        hasher.write_u64(
            SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_nanos() as u64).unwrap_or(0) ^ i as u64,
        );
        hasher.write_u32(std::process::id());
        chunk.copy_from_slice(&hasher.finish().to_le_bytes());
    }
    let h: String = bytes.iter().map(|b| format!("{b:02x}")).collect();
    format!("{}-{}-{}-{}-{}", &h[0..8], &h[8..12], &h[12..16], &h[16..20], &h[20..32])
}

/// Instalador em lote real: um UAC, progresso pelo arquivo de resultados, cancelamento pelo arquivo-sinal.
pub struct ElevatedInstaller {
    pub progress: Arc<dyn Fn(Progress) + Send + Sync>,
    pub cancel: CancelToken,
}

impl BatchInstaller for ElevatedInstaller {
    fn install_batch(&self, ids: &[String], interactive: &HashSet<String>) -> Vec<BatchResult> {
        self.install_batch_with(ids, interactive, false)
    }

    fn install_batch_with(
        &self,
        ids: &[String],
        interactive: &HashSet<String>,
        vencord: bool,
    ) -> Vec<BatchResult> {
        // O passo do Vencord só existe com o Discord no lote; sem ele o pedido some aqui também.
        let vencord = vencord && ids.iter().any(|id| id == DISCORD_ID);
        if ids.is_empty() {
            return Vec::new();
        }
        let fail = |message: &str| {
            let mut results = results_for(ids, &WorkerReport::default(), Some(message));
            if vencord && !ids.is_empty() {
                results.push(BatchResult { id: VENCORD_ID.into(), success: false, message: message.to_owned() });
            }
            results
        };
        let Some(sid) = current_sid() else {
            return fail("Não foi possível identificar o usuário atual.");
        };
        let program_data = std::env::var("ProgramData").unwrap_or_else(|_| r"C:\ProgramData".into());
        let run_id = new_run_id();
        let dir = run_dir(&program_data, &run_id);
        let (results, signal) = (dir.join("resultados.txt"), dir.join("cancelar.sinal"));
        let local = std::env::var("LOCALAPPDATA").unwrap_or_default();
        let script = match build_worker_script(ids, interactive, &run_id, &sid, &local, vencord) {
            Ok(script) => script,
            Err(message) => return fail(&message),
        };
        let powershell = match crate::elevate::system_powershell() {
            Ok(path) => path.to_string_lossy().into_owned(),
            Err(error) => return fail(&error.to_string()),
        };
        let args = elevated_arguments(&script);
        if args.len() > MAX_PARAMETERS {
            return fail(
                "O programa do lado elevado ficou grande demais para a linha de comando do Windows.",
            );
        }
        let process = match run_elevated(&powershell, &args, None) {
            Ok(process) => process,
            Err(error) if is_declined(&error) => return fail("O pedido de administrador foi recusado."),
            Err(error) => return fail(&error.to_string()),
        };
        let total = ids.len() + usize::from(vencord);
        let mut seen = 0usize;
        loop {
            let finished = process.wait(400);
            if self.cancel.is_cancelled() {
                crate::rundir::signal_cancel(&signal);
            }
            let report = parse_results(&fs::read_to_string(&results).unwrap_or_default());
            if let Some(id) = report.started.last().filter(|_| report.started.len() > report.done.len()) {
                (self.progress)(Progress {
                    phase: "Programas".into(),
                    item: id.clone(),
                    completed: report.done.len(),
                    total,
                    message: format!("Instalando {id}"),
                });
            }
            while seen < report.done.len() {
                let (id, code) = &report.done[seen];
                seen += 1;
                let note = if is_success(*code) { "instalado" } else { "falhou" };
                (self.progress)(Progress {
                    phase: "Programas".into(),
                    item: id.clone(),
                    completed: seen,
                    total,
                    message: format!("{id}: {note}"),
                });
            }
            if finished {
                break;
            }
            std::thread::sleep(Duration::from_millis(100));
        }
        let report = parse_results(&fs::read_to_string(&results).unwrap_or_default());
        if report.started.is_empty() && report.error.is_none() && process.exit_code() == Some(3) {
            return fail(
                "O lado elevado recusou a pasta de execução (ponto de reanálise ou acesso inesperado).",
            );
        }
        let mut results = results_for(ids, &report, None);
        if vencord {
            let discord_ok = results.iter().any(|r| r.id == DISCORD_ID && r.success);
            results.push(vencord_result(&report, discord_ok));
        }
        write_install_log(&local, &results);
        results
    }
}

#[cfg(test)]
mod tests {
    use std::process::Command;

    use super::*;

    const GUID: &str = "0f8fad5b-d9cb-469f-a165-70867728950e";
    const USER: &str = "S-1-5-21-111-222-333-1001";

    fn script(ids: &[&str], interactive: &[&str]) -> String {
        let ids: Vec<String> = ids.iter().map(|s| (*s).to_owned()).collect();
        let interactive: HashSet<String> = interactive.iter().map(|s| (*s).to_owned()).collect();
        build_worker_script(&ids, &interactive, GUID, USER, r"C:\Users\x\AppData\Local", false).unwrap()
    }

    #[test]
    fn ids_are_validated_before_they_reach_the_script() {
        assert!(is_safe_id("Valve.Steam") && is_safe_id("Notepad++.Notepad++") && is_safe_id("7zip.7zip"));
        for bad in ["", ".x", "a b", "a;b", "x'y", "a$(calc)", "a`b", "../x"] {
            assert!(!is_safe_id(bad), "{bad:?}");
        }
        let injected = vec!["Git.Git'; calc; '".to_owned()];
        assert!(build_worker_script(&injected, &HashSet::new(), GUID, USER, "l", false).is_err());
        let many: Vec<String> = (0..201).map(|i| format!("A.B{i}")).collect();
        assert!(build_worker_script(&many, &HashSet::new(), GUID, USER, "l", false).is_err());
        let one = vec!["A.B".to_owned()];
        assert!(build_worker_script(&one, &HashSet::new(), "..\\x", USER, "l", false).is_err(), "id de execução");
        assert!(build_worker_script(&one, &HashSet::new(), GUID, "S-1-5-21-1;calc", "l", false).is_err(), "SID");
    }

    /// A comparação do Overwolf roda no PowerShell de verdade: dois itens iguais antes e depois nunca viram remoção
    /// (o `return ,$e` antigo entregava o inventário como UM objeto e apagava o primeiro item que já existia).
    #[test]
    fn overwolf_items_that_were_already_there_are_never_removed() {
        let s = script(&["TeamSpeakSystems.TeamSpeakClient"], &[]);
        let start = s.find("function NovosOverwolf").expect("função de comparação");
        let end = start + s[start..].find("function SemOverwolf").expect("fim da função");
        let function = &s[start..end];
        assert!(!s.contains("return ,$e"), "o inventário não volta embrulhado em um único objeto");
        let run = |antes: &str, depois: &str| -> Vec<String> {
            let program = format!("{function}
$n=@(NovosOverwolf @({antes}) @({depois})); $n.Count; $n");
            let out = std::process::Command::new("powershell.exe")
                .args(["-NoProfile", "-NonInteractive", "-Command", &program])
                .output()
                .expect("powershell.exe");
            assert!(out.status.success(), "{}", String::from_utf8_lossy(&out.stderr));
            String::from_utf8_lossy(&out.stdout).lines().map(|l| l.trim().to_owned()).filter(|l| !l.is_empty()).collect()
        };
        let same = "'d|C:/Overwolf','r|HKCU:/Run|Overwolf'";
        assert_eq!(run(same, same), ["0"], "dois itens idênticos preexistentes: zero remoções");
        assert_eq!(run("'d|C:/Overwolf'", "'d|C:/Overwolf'"), ["0"], "um item idêntico: zero remoções");
        assert_eq!(run("", "'d|C:/Overwolf','t|/|Overwolf'"), ["2", "d|C:/Overwolf", "t|/|Overwolf"], "só o que nasceu");
        assert_eq!(run("'d|C:/Overwolf'", "'d|C:/Overwolf','l|C:/Desk/Overwolf.lnk'"), ["1", "l|C:/Desk/Overwolf.lnk"]);
        assert!(s.contains("try { return ,@(EstadoOverwolf) } catch { return $null }") && s.contains("if ($null -eq $antes) { return }"), "inventário que falha aborta a limpeza");
    }

    /// Uma consulta que falha (mesmo sem lançar, como um erro não terminante) interrompe o inventário, antes ou depois
    /// da instalação, e nesses casos não sobra nenhum candidato de remoção.
    #[test]
    fn a_failed_overwolf_inventory_aborts_the_cleanup_before_and_after_the_install() {
        let s = script(&["TeamSpeakSystems.TeamSpeakClient"], &[]);
        let start = s.find("function EstadoOverwolf").expect("inventário");
        let end = s.find("foreach ($id in").expect("laço principal");
        let functions = &s[start..end];
        assert!(functions.contains("$ErrorActionPreference='Stop'"), "o inventário não herda o SilentlyContinue do script");
        assert!(!functions[..functions.find("function NovosOverwolf").unwrap()].contains("SilentlyContinue"));
        assert!(functions.matches("Test-Path").count() == functions.matches("Test-Path -LiteralPath $d -ErrorAction Stop").count()
            + functions.matches("Test-Path -LiteralPath $k -ErrorAction Stop").count()
            + functions.matches("Test-Path -LiteralPath $u -ErrorAction Stop").count()
            + functions.matches("Test-Path -LiteralPath $r -ErrorAction Stop").count(),
            "todo Test-Path pede -ErrorAction Stop");
        // `states` lists what each call of Get-ScheduledTask does: "ok:<a>,<b>" (tasks named Overwolf-a, Overwolf-b) or
        // "fail" (a NON-terminating error, like the one the old SilentlyContinue swallowed). The real functions run.
        let run = |states: &[&str]| -> Vec<String> {
            let calls = states.iter().map(|s| format!("'{s}'")).collect::<Vec<_>>().join(",");
            let program = format!(
                "$ErrorActionPreference='SilentlyContinue'
$none=Join-Path $env:TEMP 'vanta-no-such-dir'; $pf=$none; $pf86=$none; $lad=$none;                  $env:PUBLIC=$none; $env:USERPROFILE=$none; $env:ProgramData=$none; $since=Get-Date
                 $global:calls=@({calls}); $global:n=0; $global:removed=@()
                 function Get-ScheduledTask {{ [CmdletBinding()] param(); $c=$global:calls[$global:n]; $global:n++;                    if ($c -eq 'fail') {{ Write-Error 'consulta falhou'; return }};                    foreach ($x in $c.Substring(3).Split(',') | Where-Object {{ $_ }}) {{ [pscustomobject]@{{ TaskName='Overwolf-'+$x; TaskPath='/' }} }} }}
                 function Remove-Item {{ param([Parameter(ValueFromRemainingArguments=$true)]$a) $global:removed += 'remove' }}
                 function Remove-ItemProperty {{ param([Parameter(ValueFromRemainingArguments=$true)]$a) $global:removed += 'removeprop' }}
                 function Unregister-ScheduledTask {{ param([Parameter(ValueFromRemainingArguments=$true)]$a) $global:removed += 'task' }}
                 function Stop-Process {{ param([Parameter(ValueFromRemainingArguments=$true)]$a) }}
                 function Get-Process {{ @() }}
{functions}
                 $antes=AntesOverwolf; if ($null -eq $antes) {{ 'antes=null' }} else {{ 'antes=ok' }}
                 SemOverwolf $antes; 'removidos=' + $global:removed.Count"
            );
            let out = std::process::Command::new("powershell.exe")
                .args(["-NoProfile", "-NonInteractive", "-Command", &program])
                .output()
                .expect("powershell.exe");
            assert!(out.status.success(), "{}", String::from_utf8_lossy(&out.stderr));
            String::from_utf8_lossy(&out.stdout).lines().map(|l| l.trim().to_owned()).filter(|l| !l.is_empty()).collect()
        };
        // A falha ANTES: o inventário de antes não existe, então nada que apareça depois pode ser removido.
        assert_eq!(run(&["fail", "ok:a"]), ["antes=null", "removidos=0"]);
        // A falha DEPOIS: o de antes existe, o de depois falha, e o que já existia não vira candidato.
        assert_eq!(run(&["ok:a", "fail"]), ["antes=ok", "removidos=0"]);
        // Controles: igual antes e depois, zero; um item novo, uma remoção.
        assert_eq!(run(&["ok:a,b", "ok:a,b"]), ["antes=ok", "removidos=0"]);
        assert_eq!(run(&["ok:a", "ok:a,b"]), ["antes=ok", "removidos=1"]);
    }

    /// Programas do GitHub: o id passa pela validação, o lote tem o instalador da última release e a escolha do
    /// asset roda no PowerShell de verdade (instalador de Windows x64; nada de ARM, Linux, zip ou portátil).
    #[test]
    fn github_apps_are_validated_and_their_asset_is_chosen_by_the_real_function() {
        assert!(is_safe_id("github:crmne/zapfast") && is_safe_id("Git.Git"));
        for bad in ["github:a/../b", "github:a", "github:a/b;calc", "github:/b"] {
            assert!(!is_safe_id(bad), "{bad}");
        }
        let ids = vec!["github:crmne/zapfast".to_owned(), "Git.Git".to_owned()];
        let s = build_worker_script(&ids, &HashSet::new(), GUID, USER, "l", false).unwrap();
        assert!(s.contains("function GithubInstalar") && s.contains("api.github.com/repos/$repo/releases/latest"));
        assert!(s.contains("GithubInstalar $id.Substring(7)") && s.contains("'github:crmne/zapfast','Git.Git'"));
        assert!(s.contains("digest -notmatch") && s.contains("AllowAutoRedirect = $false") && s.contains("[guid]::NewGuid()"), "sha256 obrigatório, redirecionamentos validados e nome local próprio");
        assert!(!s.contains("WebClient") && !s.contains("GetFileName($u.AbsolutePath)"), "nada de download automático nem nome da URL");
        let start = s.find("function EscolherAsset").unwrap();
        let end = start + s[start..].find("function Fechar").unwrap();
        let function = &s[start..end];
        let program = format!(
            "{function}\n$a=@(@{{name='App-linux.tar.gz'}},@{{name='App-arm64-setup.exe'}},@{{name='App-portable.exe'}},@{{name='App-x64-setup.exe'}},@{{name='App.msi'}})|ForEach-Object {{[pscustomobject]$_}}; (EscolherAsset $a).name; (EscolherAsset @([pscustomobject]@{{name='a.zip'}})) -eq $null"
        );
        let out = std::process::Command::new("powershell.exe").args(["-NoProfile", "-NonInteractive", "-Command", &program]).output().unwrap();
        let lines: Vec<String> = String::from_utf8_lossy(&out.stdout).lines().map(|l| l.trim().to_owned()).filter(|l| !l.is_empty()).collect();
        assert_eq!(lines, ["App-x64-setup.exe", "True"], "{lines:?} {}", String::from_utf8_lossy(&out.stderr));
    }

    #[test]
    fn github_failures_are_explained_without_blaming_winget_and_are_logged() {
        let ids = vec!["github:crmne/zapfast".to_owned(), "Git.Git".to_owned()];
        let report = WorkerReport { done: vec![(ids[0].clone(), 38), (ids[1].clone(), 5)], ..WorkerReport::default() };
        let out = results_for(&ids, &report, None);
        assert!(out[0].message.contains("cota da API") && out[0].message.contains("HTTP 403") && !out[0].message.contains("WinGet"));
        assert_eq!(out[1].message, "WinGet retornou 5.");
        assert!(github_message(33).contains("Tente") && github_message(34).contains("SHA-256"));
        let dir = std::env::temp_dir().join(format!("vanta-log-{}", std::process::id()));
        write_install_log(dir.to_str().unwrap(), &out);
        let logs: Vec<_> = std::fs::read_dir(dir.join("Vanta").join("Logs")).unwrap().collect();
        assert_eq!(logs.len(), 1);
        let text = std::fs::read_to_string(logs[0].as_ref().unwrap().path()).unwrap();
        assert!(text.contains("FALHA github:crmne/zapfast: O GitHub limitou"));
        std::fs::remove_dir_all(&dir).unwrap();
        // tudo certo: nada é escrito
        let empty = std::env::temp_dir().join(format!("vanta-log-ok-{}", std::process::id()));
        write_install_log(empty.to_str().unwrap(), &[BatchResult { id: "a".into(), success: true, message: String::new() }]);
        assert!(!empty.exists());
        assert!(script(&["github:a/b"], &[]).contains("return 38"));
    }

    #[test]
    fn the_worker_closes_what_the_installer_opened_inside_the_elevated_batch() {
        let s = script(&["Discord.Discord", "Git.Git"], &["Riot.Client"]);
        assert!(
            s.contains("function Fechar") && s.contains("Fechar $since"),
            "o fechamento roda dentro do lote elevado"
        );
        assert!(s.contains("'Discord.Discord','Git.Git'"), "um por vez, na ordem pedida");
        assert!(s.contains("$gui=@('Discord.Discord')"), "só quem abre janela espera os 10 s");
        assert!(
            s.contains("TeamSpeakSystems.TeamSpeakClient') { SemOverwolf $overwolfAntes }"),
            "Overwolf sai depois do TeamSpeak, só o que nasceu nesta instalação"
        );
        assert!(s.contains("$close=@{'Discord.Discord'=@('Discord')}"), "só fecha o que o catálogo lista, e nada para Git");
        assert!(s.contains("--silent") && s.contains("--interactive"));
        assert_eq!(s.matches("winget install").count(), 1, "o mesmo laço instala todos: um lote, um UAC");
    }

    #[test]
    fn the_run_folder_is_created_by_the_elevated_side_under_programdata_and_never_in_temp() {
        let s = script(&["Git.Git"], &[]);
        assert!(
            s.contains(&format!("New-VantaRunDir -Base $env:ProgramData -Guid '{GUID}' -UserSid '{USER}'"))
        );
        assert!(s.contains("catch { exit 3 }"), "pasta recusada: o lado elevado sai sem escrever nada");
        assert!(s.contains("Join-Path $dir 'resultados.txt'") && s.contains("Test-VantaCancelled"));
        let lower = s.to_lowercase();
        assert!(
            !lower.contains("$env:temp") && !lower.contains("\\temp\\") && !lower.contains("vantabatch-"),
            "nenhum caminho do usuário"
        );
        assert!(
            !s.contains("Get-Content -LiteralPath $cancel") && s.contains("Open-VantaCancelStream"),
            "o sinal é o CONTEÚDO do arquivo (o usuário não cria arquivo na pasta)"
        );
    }

    fn script_with_vencord(ids: &[&str], vencord: bool) -> String {
        let ids: Vec<String> = ids.iter().map(|s| (*s).to_owned()).collect();
        build_worker_script(&ids, &HashSet::new(), GUID, USER, r"C:\Users\x\AppData\Local", vencord).unwrap()
    }

    #[test]
    fn the_vencord_step_exists_only_with_the_flag_and_discord_in_the_batch() {
        for (ids, flag) in [(vec!["Discord.Discord"], false), (vec!["Git.Git"], true)] {
            let s = script_with_vencord(&ids, flag);
            assert!(!s.contains("Vencord"), "{ids:?} {flag}");
        }
        let s = script_with_vencord(&["Git.Git", "Discord.Discord"], true);
        assert!(s.contains("function Vencord"));
        assert!(s.find("function Vencord").unwrap() < s.find("foreach ($id in").unwrap(), "definida antes do laço");
    }

    #[test]
    fn the_vencord_step_uses_the_official_cli_pinned_by_hash_and_runs_only_after_discord_succeeded() {
        let s = script_with_vencord(&["Discord.Discord"], true);
        assert!(s.contains(VENCORD_CLI_URL) && s.contains("github.com/Vencord/Installer/releases/download/v1.4.2/"));
        assert!(s.contains(VENCORD_CLI_SHA256) && s.contains("Get-FileHash") && s.contains("-ne '"));
        assert!(s.contains("& $exe -install -branch stable"), "parâmetros oficiais do CLI");
        // o instalador cai na pasta de execução (ACL só de administradores), nunca em %TEMP%
        assert!(s.contains("Join-Path $dir 'VencordInstallerCli.exe'"));
        // só depois do sucesso do Discord: a chamada vem depois do `if ($code -in ...)` e do Fechar
        let success = s.find("if ($code -in 0,3010").unwrap();
        let close = s.find("Fechar $since").unwrap();
        let call = s.find("$vc = Vencord").unwrap();
        let log_code = s.find("Add-Content -LiteralPath $results -Value ([string]$code + ' ' + $id)").unwrap();
        assert!(success < close && close < call && call < log_code, "{success} {close} {call} {log_code}");
        // Discord fechado antes de patchar
        let stop = s.find("Stop-Process -Force\n    Start-Sleep -Seconds 2").unwrap();
        assert!(stop < s.find("Invoke-WebRequest").unwrap());
        assert!(s.contains(&format!("return {VENCORD_DISCORD_OPEN}")), "Discord ainda aberto: não roda");
    }

    #[test]
    fn the_vencord_script_is_valid_powershell() {
        let s = script_with_vencord(&["Discord.Discord", "Git.Git"], true);
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("worker.ps1");
        fs::write(&file, &s).unwrap();
        let check = format!(
            "$e=$null; [void][System.Management.Automation.Language.Parser]::ParseFile('{}', [ref]$null, [ref]$e); if ($e) {{ $e[0].Message; exit 1 }}",
            file.display()
        );
        let out = Command::new("powershell.exe").args(["-NoProfile", "-Command", &check]).output().unwrap();
        assert!(out.status.success(), "{}", String::from_utf8_lossy(&out.stdout));
        let packed = elevated_arguments(&s);
        assert!(packed.len() <= MAX_PARAMETERS, "{}", packed.len());
    }

    #[test]
    fn the_vencord_outcome_is_read_from_the_results_file() {
        let result = |text: &str, discord_ok: bool| vencord_result(&parse_results(text), discord_ok);
        let ok = result("start Vencord\n0 Vencord\nFIM\n", true);
        assert!(ok.success && ok.id == "Vencord");
        for (code, needle) in [(20, "Feche o Discord"), (21, "baixar"), (22, "hash"), (5, "retornou 5")] {
            let r = result(&format!("{code} Vencord\n"), true);
            assert!(!r.success && r.message.contains(needle), "{code}: {}", r.message);
        }
        assert!(result("FIM\n", false).message.contains("Discord não foi instalado"));
        assert!(result("0 Discord.Discord\n", true).message.contains("Não executado"));
    }

    #[test]
    fn interactive_ids_are_listed_for_the_worker() {
        assert!(script(&["Riot.Client"], &["Riot.Client"]).contains("$interactive=@('Riot.Client')"));
        assert!(script(&["Git.Git"], &[]).contains("$interactive=@()"));
    }

    #[test]
    fn the_worker_script_is_valid_powershell() {
        let s = script(&["Discord.Discord", "TeamSpeakSystems.TeamSpeakClient"], &["Riot.Client"]);
        // o texto passa de 32 mil caracteres em base64: confere pelo arquivo, não pela linha de comando
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("worker.ps1");
        fs::write(&file, &s).unwrap();
        let check = format!(
            "$e=$null; [void][System.Management.Automation.Language.Parser]::ParseFile('{}', [ref]$null, [ref]$e); if ($e) {{ $e[0].Message; exit 1 }}",
            file.display()
        );
        let out = Command::new("powershell.exe").args(["-NoProfile", "-Command", &check]).output().unwrap();
        assert!(out.status.success(), "{}", String::from_utf8_lossy(&out.stdout));
    }

    #[test]
    fn the_encoded_command_round_trips() {
        assert_eq!(encode_command("A"), "QQA=");
        assert_eq!(encode_command("Ab"), "QQBiAA==");
        assert_eq!(encode_command("abc"), "YQBiAGMA");
    }

    #[test]
    fn run_ids_look_like_guids_and_do_not_repeat() {
        let (a, b) = (new_run_id(), new_run_id());
        assert!(is_run_id(&a) && is_run_id(&b) && a != b, "{a} {b}");
    }

    #[test]
    fn results_are_read_line_by_line_and_missing_ones_fail() {
        let report = parse_results("\u{feff}start A.A\r\n0 A.A\r\nstart B.B\r\n5 B.B\r\nstart C.C\r\n");
        assert_eq!(report.started, ["A.A", "B.B", "C.C"]);
        assert_eq!(report.done, [("A.A".to_owned(), 0), ("B.B".to_owned(), 5)]);
        assert!(!report.finished);
        let ids: Vec<String> = ["A.A", "B.B", "C.C"].iter().map(|s| (*s).to_owned()).collect();
        let out = results_for(&ids, &report, None);
        assert!(out[0].success && !out[1].success && out[1].message.contains('5') && !out[2].success);
        assert!(parse_results("FIM").finished);
        assert_eq!(parse_results("ERRO sem-winget").error.as_deref(), Some("sem-winget"));
    }

    #[test]
    fn a_declined_prompt_fails_every_program_with_the_reason() {
        let ids = vec!["A.A".to_owned()];
        let out =
            results_for(&ids, &WorkerReport::default(), Some("O pedido de administrador foi recusado."));
        assert!(!out[0].success && out[0].message.contains("recusado"));
    }

    #[test]
    fn the_packed_loader_runs_the_script_keeps_exit_codes_and_fits_the_command_line() {
        let script = "$x = 'dentro'; Write-Output ('saida=' + $x + ' ç'); exit 7";
        let out = Command::new("powershell.exe")
            .args(["-NoProfile", "-NonInteractive", "-Command", &pack_command(script)])
            .output()
            .unwrap();
        assert_eq!(out.status.code(), Some(7), "o exit do programa vira o código do processo");
        assert!(
            String::from_utf8_lossy(&out.stdout).contains("saida=dentro"),
            "{}",
            String::from_utf8_lossy(&out.stdout)
        );
        let big = build_worker_script(&["A.B".to_owned()], &HashSet::new(), GUID, USER, "l", false).unwrap();
        assert!(elevated_arguments(&big).len() < MAX_PARAMETERS);
    }
}
