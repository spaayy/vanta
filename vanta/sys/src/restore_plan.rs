//! O plano que o lado elevado do Restaurar executa: DADOS, nunca um script. O app monta e valida o plano aqui (puro,
//! testado) e o lado elevado (`restore_worker`) o confere de novo antes de agir. Nada do que o usuário ou o kit
//! gravam é executado:
//! - cada arquivo a copiar leva o seu SHA-256 no plano; o lado elevado só copia o que bate (de um retrato já conferido);
//! - o destino de toda cópia está numa lista permitida, derivada dos destinos canônicos do manifesto;
//! - um `.reg` só importa chaves permitidas e nunca sobrescreve um valor que já existe com outro dado;
//! - uma tarefa só roda um programa de um lugar permitido (a ação XML inteira é conferida), e o script dela tem o hash
//!   do que foi copiado.

use std::io::Read;
use std::path::Path;

use regex::Regex;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};

use crate::restore_batch::decode_text;

/// Um arquivo a copiar: caminho relativo à origem, SHA-256 e tamanho no momento em que o plano foi montado.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PlanFile {
    pub rel: String,
    pub sha256: String,
    pub size: u64,
}

/// Uma cópia de arquivo ou pasta (o que o lado elevado faz, arquivo por arquivo conferido).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PlanItem {
    pub name: String,
    pub source: String,
    pub destination: String,
    pub is_folder: bool,
    pub files: Vec<PlanFile>,
}

/// Um arquivo que o app já montou na memória (o `config.txt` do Equalizer APO com o microfone novo).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PlanText {
    pub name: String,
    pub destination: String,
    pub content: Vec<u8>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PlanReg {
    pub label: String,
    pub text: String,
}

/// O script que uma tarefa roda: caminho no destino e o SHA-256 que a cópia conferida tem de ter.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PlanScript {
    pub path: String,
    pub sha256: String,
}

/// Tarefa agendada; nunca substitui uma que já exista com outro conteúdo.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PlanTask {
    pub label: String,
    pub name: String,
    pub xml: String,
    pub scripts: Vec<PlanScript>,
}

/// Entrada `Run` do usuário; nunca substitui uma que já exista com outro valor.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PlanRun {
    pub label: String,
    pub name: String,
    pub command: String,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct RestorePlan {
    pub items: Vec<PlanItem>,
    pub texts: Vec<PlanText>,
    pub registry: Vec<PlanReg>,
    pub tasks: Vec<PlanTask>,
    pub runs: Vec<PlanRun>,
    /// Serviços que prendem arquivos de configuração (parados antes da cópia).
    pub services: Vec<String>,
    /// Processos que prendem arquivos de configuração (fechados antes da cópia).
    pub processes: Vec<String>,
    /// Pastas que o manifesto restaura (o usuário escreve nelas): de onde uma tarefa comum ou entrada `Run` pode rodar.
    pub restored_roots: Vec<String>,
    /// Os destinos canônicos de TODOS os itens do manifesto: o lado elevado só copia para dentro deles.
    pub allowed_destinations: Vec<String>,
    /// Pastas onde só administradores escrevem e de onde uma tarefa com privilégio máximo pode rodar (`C:\Vanta\System`).
    /// O lado elevado as cria ou confere (dono e ACL) antes de copiar para elas.
    pub protected_dirs: Vec<String>,
}

impl RestorePlan {
    pub fn is_empty(&self) -> bool {
        self.items.is_empty()
            && self.texts.is_empty()
            && self.registry.is_empty()
            && self.tasks.is_empty()
            && self.runs.is_empty()
    }

    pub fn to_json(&self) -> String {
        json!({
            "version": 2,
            "items": self.items.iter().map(|i| json!({
                "name": i.name, "source": i.source, "destination": i.destination, "isFolder": i.is_folder,
                "files": i.files.iter().map(|f| json!({"rel": f.rel, "sha256": f.sha256, "size": f.size})).collect::<Vec<Value>>(),
            })).collect::<Vec<Value>>(),
            "texts": self.texts.iter().map(|t| json!({
                "name": t.name, "destination": t.destination, "contentBase64": base64(&t.content)
            })).collect::<Vec<Value>>(),
            "registry": self.registry.iter().map(|r| json!({"label": r.label, "text": r.text})).collect::<Vec<Value>>(),
            "tasks": self.tasks.iter().map(|t| json!({
                "label": t.label, "name": t.name, "xml": t.xml,
                "scripts": t.scripts.iter().map(|s| json!({"path": s.path, "sha256": s.sha256})).collect::<Vec<Value>>(),
            })).collect::<Vec<Value>>(),
            "runs": self.runs.iter().map(|r| json!({"label": r.label, "name": r.name, "command": r.command})).collect::<Vec<Value>>(),
            "services": self.services,
            "processes": self.processes,
            "restoredRoots": self.restored_roots,
            "allowedDestinations": self.allowed_destinations,
            "protectedDirs": self.protected_dirs,
        })
        .to_string()
    }
}

/// Base64 padrão (o plano leva bytes de arquivo como texto).
pub fn base64(bytes: &[u8]) -> String {
    const TABLE: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
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

// ---------------------------------------------------------------------------------------------------------------
// Arquivos e hashes

/// SHA-256 de um arquivo, lido em blocos.
pub fn sha256_file(path: &Path) -> std::io::Result<(String, u64)> {
    let mut file = std::fs::File::open(path)?;
    let mut hasher = Sha256::new();
    let mut buffer = vec![0u8; 1 << 20];
    let mut total = 0u64;
    loop {
        let read = file.read(&mut buffer)?;
        if read == 0 {
            break;
        }
        hasher.update(&buffer[..read]);
        total += read as u64;
    }
    Ok((hasher.finalize().iter().map(|b| format!("{b:02x}")).collect(), total))
}

fn is_reparse(path: &Path) -> bool {
    use std::os::windows::fs::MetadataExt;
    std::fs::symlink_metadata(path).is_ok_and(|m| m.file_attributes() & 0x400 != 0)
}

/// Todos os arquivos de `source` (pasta, recursivo) ou o arquivo único, com SHA-256. Recusa ponto de reanálise
/// (junção ou link) em qualquer nível: o que o plano lista é o que existe de verdade ali.
pub fn hash_source(source: &Path, is_folder: bool) -> std::io::Result<Vec<PlanFile>> {
    if is_reparse(source) {
        return Err(std::io::Error::other(format!("{} é uma junção ou link", source.display())));
    }
    if !is_folder {
        let (sha256, size) = sha256_file(source)?;
        let name = source.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
        return Ok(vec![PlanFile { rel: name, sha256, size }]);
    }
    let mut files = Vec::new();
    let mut pending = vec![(source.to_path_buf(), String::new())];
    while let Some((dir, prefix)) = pending.pop() {
        for entry in std::fs::read_dir(&dir)? {
            let entry = entry?;
            let path = entry.path();
            let name = entry.file_name().to_string_lossy().into_owned();
            let rel = if prefix.is_empty() { name } else { format!(r"{prefix}\{name}") };
            if is_reparse(&path) {
                return Err(std::io::Error::other(format!("{} é uma junção ou link", path.display())));
            }
            if entry.file_type()?.is_dir() {
                pending.push((path, rel));
            } else {
                let (sha256, size) = sha256_file(&path)?;
                files.push(PlanFile { rel, sha256, size });
            }
        }
    }
    files.sort_by(|a, b| a.rel.cmp(&b.rel));
    Ok(files)
}

// ---------------------------------------------------------------------------------------------------------------
// Caminhos

/// Caminho absoluto com letra de unidade, sem `..`, sem UNC e sem caracteres de comando.
pub fn valid_abs_path(path: &str) -> bool {
    let bytes = path.as_bytes();
    let drive = bytes.len() >= 3 && bytes[0].is_ascii_alphabetic() && bytes[1] == b':' && bytes[2] == b'\\';
    drive
        && !path.chars().any(|c| c.is_control() || matches!(c, '"' | '<' | '>' | '|' | '*' | '?'))
        && !path.split('\\').any(|part| part == ".." || part == ".")
        && !path.contains("\\\\")
}

/// Caminho relativo dentro de uma origem: sem unidade, sem `..`, sem começar com barra, sem caracteres de comando.
pub fn valid_rel_path(rel: &str) -> bool {
    !rel.is_empty()
        && !rel.starts_with('\\')
        && !rel.contains(':')
        && !rel.contains("\\\\")
        && !rel.chars().any(|c| c.is_control() || matches!(c, '"' | '<' | '>' | '|' | '*' | '?'))
        && !rel.split('\\').any(|part| part.is_empty() || part == ".." || part == ".")
}

pub fn path_inside(path: &str, root: &str) -> bool {
    let (p, r) = (path.to_lowercase(), root.trim_end_matches('\\').to_lowercase());
    !r.is_empty() && (p == r || p.starts_with(&format!("{r}\\")))
}

/// Destino de uma cópia elevada: dentro de um destino canônico do manifesto, fundo o bastante para não ser a raiz de uma
/// unidade nem uma pasta de topo, e fora de `\Windows`.
pub fn destination_allowed(destination: &str, allowed: &[String]) -> bool {
    let depth = destination.split('\\').filter(|part| !part.is_empty()).count();
    valid_abs_path(destination)
        && depth >= 3
        && !Regex::new(r"(?i)^[A-Za-z]:\\Windows(\\|$)").expect("regex fixa").is_match(destination)
        && allowed.iter().any(|root| path_inside(destination, root))
}

/// Confere o plano inteiro (o app usa antes de gravar; o lado elevado repete o essencial).
pub fn validate_plan(plan: &RestorePlan, program_data: &str) -> Result<(), String> {
    let run_root = format!(r"{}\Vanta", program_data.trim_end_matches('\\'));
    for allowed in &plan.allowed_destinations {
        if !valid_abs_path(allowed) {
            return Err(format!("destino permitido inválido: {allowed}"));
        }
    }
    let bad_target =
        |path: &str| !destination_allowed(path, &plan.allowed_destinations) || path_inside(path, &run_root);
    for item in &plan.items {
        if !valid_abs_path(&item.source) {
            return Err(format!("{}: caminho de origem inválido.", item.name));
        }
        if bad_target(&item.destination) {
            return Err(format!(
                "{}: o destino {} não está na lista permitida pelo manifesto.",
                item.name, item.destination
            ));
        }
        for file in &item.files {
            if !valid_rel_path(&file.rel) {
                return Err(format!("{}: arquivo com caminho inválido ({}).", item.name, file.rel));
            }
            if file.sha256.len() != 64 || !file.sha256.chars().all(|c| c.is_ascii_hexdigit()) {
                return Err(format!("{}: {} sem SHA-256 válido.", item.name, file.rel));
            }
        }
    }
    for text in &plan.texts {
        if bad_target(&text.destination) {
            return Err(format!(
                "{}: o destino {} não está na lista permitida.",
                text.name, text.destination
            ));
        }
    }
    for dir in &plan.protected_dirs {
        // a pasta é de um destino permitido: contém um arquivo permitido (C:\Vanta\System\x.ps1) ou está dentro de uma pasta permitida
        if !valid_abs_path(dir)
            || !plan.allowed_destinations.iter().any(|root| path_inside(dir, root) || path_inside(root, dir))
        {
            return Err(format!("pasta protegida fora da lista permitida: {dir}"));
        }
    }
    for reg in &plan.registry {
        validate_reg(&reg.text).map_err(|why| format!("{}: {why}", reg.label))?;
    }
    for task in &plan.tasks {
        if !valid_name(&task.name) {
            return Err(format!("{}: nome de tarefa inválido.", task.label));
        }
        for script in &task.scripts {
            if !valid_abs_path(&script.path) || script.sha256.len() != 64 {
                return Err(format!("{}: script da tarefa inválido.", task.label));
            }
        }
    }
    for run in &plan.runs {
        if !valid_name(&run.name) {
            return Err(format!("{}: nome de entrada de início inválido.", run.label));
        }
    }
    if let Some(root) = plan.restored_roots.iter().find(|root| !valid_abs_path(root)) {
        return Err(format!("pasta restaurada inválida: {root}"));
    }
    for name in plan.services.iter().chain(&plan.processes) {
        if !valid_name(name) || name.contains(' ') {
            return Err(format!("nome de serviço ou processo inválido: {name}"));
        }
    }
    Ok(())
}

/// Nome de tarefa, entrada, serviço ou processo: letras, números, espaço, `_`, `.`, `-`, `+`.
pub fn valid_name(name: &str) -> bool {
    !name.is_empty()
        && name.len() <= 80
        && !name.starts_with(' ')
        && !name.ends_with(' ')
        && name.chars().all(|c| c.is_ascii_alphanumeric() || matches!(c, ' ' | '_' | '.' | '-' | '+'))
}

// ---------------------------------------------------------------------------------------------------------------
// Registro

/// Chaves que um `.reg` do kit pode tocar: as do usuário e `HKLM\SOFTWARE`, menos tudo o que inicia, executa,
/// redireciona ou muda política (Run, RunOnce, Winlogon, serviços, políticas, associações de arquivo, IFEO, AppInit).
/// Nenhuma exclusão (de chave, de valor nomeado ou do valor padrão `@=-`).
pub fn validate_reg(text: &str) -> Result<(), String> {
    let first = text.trim_start_matches('\u{feff}').lines().map(str::trim).find(|l| !l.is_empty());
    if !first.is_some_and(|l| l == "Windows Registry Editor Version 5.00" || l == "REGEDIT4") {
        return Err("não parece um arquivo .reg (falta o cabeçalho).".into());
    }
    let denied = Regex::new(
        r"(?i)\\(run|runonce|runservices|runonceex|policies|services|winlogon|classes|image file execution options|appinit_dlls|appcertdlls|silentprocessexit|session manager|lsa|safeboot)(\\|$)",
    )
    .expect("regex fixa");
    let mut keys = 0usize;
    for line in text.lines().map(str::trim) {
        if let Some(rest) = line.strip_prefix('[') {
            let key = rest.trim_end_matches(']');
            if key.starts_with('-') {
                return Err(format!("apaga chave inteira ({key}); recusado."));
            }
            let upper = key.to_uppercase();
            let allowed = upper.starts_with("HKEY_CURRENT_USER\\")
                || upper.starts_with("HKEY_LOCAL_MACHINE\\SOFTWARE\\");
            if !allowed {
                return Err(format!("chave fora de HKCU e HKLM\\SOFTWARE: {key}"));
            }
            if denied.is_match(key) || denied.is_match(&format!("{key}\\")) {
                return Err(format!("chave que inicia ou redireciona programas: {key}"));
            }
            keys += 1;
        } else if line.ends_with("=-") && (line.starts_with('"') || line.starts_with('@')) {
            return Err(format!("apaga um valor ({line}); recusado."));
        }
    }
    if keys == 0 {
        return Err("o arquivo .reg não tem nenhuma chave.".into());
    }
    Ok(())
}

// ---------------------------------------------------------------------------------------------------------------
// Tarefas agendadas

/// De onde uma tarefa do kit pode rodar um programa.
pub struct TaskRoots<'a> {
    /// Program Files e Program Files (x86): só administradores escrevem lá.
    pub program_files: Vec<String>,
    /// Pastas só de administradores onde o Vanta instala scripts (`C:\Vanta\System`): valem para tarefa com privilégio máximo.
    pub privileged: Vec<String>,
    /// Pastas que o manifesto restaura (o usuário escreve nelas): só valem para tarefa SEM privilégio máximo.
    pub restored: Vec<String>,
    /// Onde um programa de início do usuário (entrada `Run`, sem privilégio extra) também pode estar.
    pub user_programs: Vec<String>,
    /// `<diretório de sistema>\WindowsPowerShell\v1.0\powershell.exe`, o único PowerShell aceito.
    pub powershell: String,
    /// `<diretório de sistema>\cmd.exe`, aceito só em tarefa sem privilégio máximo, para rodar um `.bat` do usuário.
    pub cmd: String,
    /// Perfil do usuário que restaura: o `.bat` de uma tarefa comum tem de estar nele.
    pub user_profile: String,
    /// Valor de uma variável de ambiente do usuário (`LOCALAPPDATA`, `USERPROFILE`, ...).
    pub env: &'a dyn Fn(&str) -> Option<String>,
}

fn xml_unescape(text: &str) -> String {
    text.replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&apos;", "'")
        .replace("&amp;", "&")
}

fn under_any(path: &str, roots: &[String]) -> bool {
    roots.iter().any(|root| path_inside(path, root))
}

/// O que `-File "<script>"` aceita antes dele: só estas opções, e nada depois do script.
fn powershell_file_argument(args: &str) -> Option<String> {
    let pattern = Regex::new(
        r#"(?i)^(?:-NoProfile |-NonInteractive |-NoLogo |-ExecutionPolicy (?:Bypass|RemoteSigned|AllSigned) |-WindowStyle (?:Hidden|Minimized) )*-File "([^"]+)"$"#,
    )
    .expect("regex fixa");
    pattern.captures(args.trim()).map(|c| c[1].to_owned())
}

/// `/c "<arquivo .bat ou .cmd>"`, e nada mais.
fn cmd_batch_argument(args: &str) -> Option<String> {
    let pattern = Regex::new(r#"(?i)^/c "([^"&|<>^%]+\.(?:bat|cmd))"$"#).expect("regex fixa");
    pattern.captures(args.trim()).map(|c| c[1].to_owned())
}

/// Confere a ação XML INTEIRA de uma tarefa do kit. Devolve os programas que ela roda e os scripts que ela executa
/// (para o lado elevado conferir o hash). `Err` com o motivo, em português.
pub fn validate_task(xml: &str, sid: &str, roots: &TaskRoots) -> Result<(Vec<String>, Vec<String>), String> {
    let lower = xml.to_lowercase();
    if lower.contains("<!doctype") || lower.contains("<!entity") || lower.contains("<![cdata[") {
        return Err("o XML tem DOCTYPE, entidade ou CDATA; recusada.".into());
    }
    for forbidden in ["<comhandler", "<sendemail", "<showmessage", "<groupid"] {
        if lower.contains(forbidden) {
            return Err(format!(
                "usa {} em vez de iniciar um programa; recusada.",
                forbidden.trim_start_matches('<')
            ));
        }
    }
    let users = Regex::new(r"<UserId>([^<]*)</UserId>").expect("regex fixa");
    for caps in users.captures_iter(xml) {
        let who = xml_unescape(caps[1].trim());
        let system = matches!(
            who.to_uppercase().as_str(),
            "SYSTEM"
                | "NT AUTHORITY\\SYSTEM"
                | "LOCAL SERVICE"
                | "NETWORK SERVICE"
                | "LOCALSERVICE"
                | "NETWORKSERVICE"
        ) || who.starts_with("S-1-5-18")
            || who.starts_with("S-1-5-19")
            || who.starts_with("S-1-5-20");
        if system || (who != sid && !who.is_empty()) {
            return Err(format!("roda como '{who}', não como o usuário que restaurou; recusada."));
        }
    }
    // a ação inteira: <Actions> só com <Exec>, e cada <Exec> só com Command, Arguments e WorkingDirectory
    let actions = Regex::new(r"(?s)<Actions[^>]*>(.*?)</Actions>").expect("regex fixa");
    let Some(actions_body) = actions.captures(xml).map(|c| c[1].to_owned()) else {
        return Err("a tarefa não tem <Actions>.".into());
    };
    let exec = Regex::new(r"(?s)<Exec>(.*?)</Exec>").expect("regex fixa");
    let leftover = exec.replace_all(&actions_body, "").into_owned();
    if Regex::new(r"<[A-Za-z]").expect("regex fixa").is_match(&leftover) {
        return Err("a ação tem algo além de <Exec>; recusada.".into());
    }
    let command = Regex::new(r"(?s)<Command>(.*?)</Command>").expect("regex fixa");
    let arguments = Regex::new(r"(?s)<Arguments>(.*?)</Arguments>").expect("regex fixa");
    let working = Regex::new(r"(?s)<WorkingDirectory>(.*?)</WorkingDirectory>").expect("regex fixa");
    let any_element = Regex::new(r"<[A-Za-z]").expect("regex fixa");
    let elevated = lower.contains("<runlevel>highestavailable</runlevel>");
    let mut programs = Vec::new();
    let mut scripts = Vec::new();
    for block in exec.captures_iter(&actions_body) {
        let body = &block[1];
        let inner = command.replace_all(body, "");
        let inner = arguments.replace_all(&inner, "");
        let inner = working.replace_all(&inner, "");
        if any_element.is_match(&inner) {
            return Err(
                "a ação <Exec> tem elementos além de Command, Arguments e WorkingDirectory; recusada.".into(),
            );
        }
        if command.captures_iter(body).count() != 1 || arguments.captures_iter(body).count() > 1 {
            return Err("a ação <Exec> precisa de exatamente um <Command>.".into());
        }
        if let Some(dir) = working.captures(body) {
            let dir = xml_unescape(dir[1].trim());
            if dir.contains('%') {
                return Err("o diretório de trabalho usa variável de ambiente; recusada.".into());
            }
            if !dir.is_empty() && !valid_abs_path(&dir) {
                return Err(format!("diretório de trabalho inválido: {dir}"));
            }
        }
        let raw =
            xml_unescape(command.captures(body).map_or("", |c| c.get(1).map_or("", |m| m.as_str())).trim())
                .trim_matches('"')
                .to_owned();
        // variável de ambiente nunca: quem pede a tarefa não pode escolher o programa por ela
        if raw.contains('%') {
            return Err(format!("o comando '{raw}' usa variável de ambiente; recusada."));
        }
        let exe = raw.clone();
        if !valid_abs_path(&exe) || !exe.to_lowercase().ends_with(".exe") {
            let bare = raw.to_lowercase();
            let interpreter = [
                "cmd.exe",
                "powershell.exe",
                "pwsh.exe",
                "wscript.exe",
                "cscript.exe",
                "mshta.exe",
                "rundll32.exe",
            ]
            .contains(&bare.as_str());
            return Err(if interpreter {
                format!(
                    "o interpretador '{raw}' sem caminho completo não é aceito (a busca no PATH poderia achar outro programa)."
                )
            } else {
                format!("o comando '{raw}' não é o caminho completo de um .exe.")
            });
        }
        let args = arguments.captures(body).map(|c| xml_unescape(c[1].trim())).unwrap_or_default();
        if args.contains('%') {
            return Err("os argumentos usam variável de ambiente; recusada.".into());
        }
        // onde um programa ou script pode estar: só de administradores se a tarefa tem privilégio máximo
        let safe: Vec<String> = if elevated {
            roots.program_files.iter().chain(&roots.privileged).cloned().collect()
        } else {
            roots.program_files.iter().chain(&roots.privileged).chain(&roots.restored).cloned().collect()
        };
        if exe.eq_ignore_ascii_case(&roots.powershell) {
            let Some(script_raw) = powershell_file_argument(&args) else {
                return Err("o PowerShell da tarefa não usa exatamente `-File \"<script>\"` (com só as opções -NoProfile, -NonInteractive, -NoLogo, -ExecutionPolicy e -WindowStyle antes); recusada.".into());
            };
            let script = script_raw.clone();
            if !valid_abs_path(&script)
                || !script.to_lowercase().ends_with(".ps1")
                || !under_any(&script, &safe)
            {
                return Err(if elevated {
                    format!(
                        "a tarefa roda com privilégio máximo e o script '{script_raw}' não está em Program Files nem em uma pasta só de administradores; recusada."
                    )
                } else {
                    format!("o script '{script_raw}' não está numa pasta permitida; recusada.")
                });
            }
            scripts.push(script);
        } else if exe.eq_ignore_ascii_case(&roots.cmd) {
            if elevated {
                return Err("o cmd.exe não roda numa tarefa com privilégio máximo; recusada.".into());
            }
            let Some(batch) = cmd_batch_argument(&args) else {
                return Err(
                    "o cmd.exe da tarefa não usa exatamente `/c \"<arquivo .bat ou .cmd>\"`; recusada."
                        .into(),
                );
            };
            if !valid_abs_path(&batch) || !path_inside(&batch, &roots.user_profile) {
                return Err(format!(
                    "o arquivo '{batch}' não está no perfil do usuário que restaura; recusada."
                ));
            }
        } else if !under_any(&exe, &safe) {
            return Err(format!("o programa '{raw}' não está em Program Files nem numa pasta permitida."));
        }
        programs.push(exe);
    }
    if programs.is_empty() {
        return Err("a tarefa não tem nenhuma ação <Exec>.".into());
    }
    Ok((programs, scripts))
}

/// Entrada `Run`: `"<exe>" [argumentos]`, com o .exe em Program Files, numa pasta que o manifesto restaura ou nos
/// programas do usuário.
pub fn validate_run_command(command: &str, roots: &TaskRoots) -> Result<(), String> {
    let rest = command.strip_prefix('"').ok_or("o comando não começa com aspas.")?;
    let (exe, args) = rest.split_once('"').ok_or("faltam as aspas que fecham o caminho.")?;
    if !valid_abs_path(exe) || !exe.to_lowercase().ends_with(".exe") {
        return Err(format!("'{exe}' não é o caminho completo de um .exe."));
    }
    if !(under_any(exe, &roots.program_files)
        || under_any(exe, &roots.restored)
        || under_any(exe, &roots.user_programs))
    {
        return Err(format!("'{exe}' não está em Program Files nem numa pasta que o manifesto restaura."));
    }
    if args.chars().any(|c| matches!(c, '&' | '|' | '<' | '>' | '\r' | '\n' | '`')) {
        return Err("os argumentos têm caracteres de comando.".into());
    }
    Ok(())
}

/// O texto de um `.reg`/`.xml` do kit: UTF-16 ou UTF-8, como o Windows grava.
pub fn read_text(path: &Path) -> std::io::Result<String> {
    Ok(decode_text(&std::fs::read(path)?))
}

#[cfg(test)]
mod tests {
    use super::*;

    const SID: &str = "S-1-5-21-1-2-3-1001";

    fn env(name: &str) -> Option<String> {
        match name.to_uppercase().as_str() {
            "LOCALAPPDATA" => Some(r"C:\Users\user\AppData\Local".into()),
            "USERPROFILE" => Some(r"C:\Users\user".into()),
            "PROGRAMFILES" => Some(r"C:\Program Files".into()),
            _ => None,
        }
    }

    fn roots() -> TaskRoots<'static> {
        TaskRoots {
            program_files: vec![r"C:\Program Files".into(), r"C:\Program Files (x86)".into()],
            privileged: vec![r"C:\Vanta\System".into()],
            restored: vec![r"C:\Users\user\AppData\Local\VantaSystem".into()],
            user_programs: vec![],
            powershell: r"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe".into(),
            cmd: r"C:\Windows\System32\cmd.exe".into(),
            user_profile: r"C:\Users\user".into(),
            env: &env,
        }
    }

    fn task(user: &str, command: &str, args: &str) -> String {
        format!(
            "<Task><Principals><Principal><UserId>{user}</UserId></Principal></Principals><Actions><Exec><Command>{command}</Command><Arguments>{args}</Arguments></Exec></Actions></Task>"
        )
    }

    fn elevated_task(command: &str, args: &str) -> String {
        format!(
            "<Task><Principals><Principal><UserId>{SID}</UserId><RunLevel>HighestAvailable</RunLevel></Principal></Principals><Actions><Exec><Command>{command}</Command><Arguments>{args}</Arguments></Exec></Actions></Task>"
        )
    }

    const PS: &str = r"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe";

    #[test]
    fn paths_must_be_absolute_with_a_drive_and_free_of_dots_and_command_characters() {
        for ok in [r"C:\Program Files\X", r"d:\a\b.txt", r"C:\Users\Someone\AppData"] {
            assert!(valid_abs_path(ok), "{ok}");
        }
        for bad in [
            r"\\srv\share\x",
            r"C:x",
            r"C:\a\..\b",
            r"C:\a\.\b",
            "C:\\a\"b",
            "C:\\a|b",
            "C:\\a\nb",
            r"relativo\x",
            "",
            r"C:\a\\b",
        ] {
            assert!(!valid_abs_path(bad), "{bad:?}");
        }
        for ok in ["a.txt", r"sub\b.ini"] {
            assert!(valid_rel_path(ok), "{ok}");
        }
        for bad in ["", r"\a", r"..\a", r"a\..\b", "C:a", r"a\\b", "a|b", r"a\", "a\nb"] {
            assert!(!valid_rel_path(bad), "{bad:?}");
        }
    }

    #[test]
    fn a_destination_must_be_inside_one_the_manifest_lists_deep_enough_and_outside_windows() {
        let allowed = vec![
            r"C:\Program Files\ISLC".to_owned(),
            r"C:\Vanta\System".to_owned(),
            r"C:\Windows\Fonts".to_owned(),
        ];
        assert!(destination_allowed(r"C:\Program Files\ISLC", &allowed));
        assert!(destination_allowed(r"C:\Program Files\ISLC\cfg\a.ini", &allowed));
        assert!(
            destination_allowed(r"c:\vanta\system\VantaSystem.ps1", &allowed),
            "sem diferenciar maiúsculas"
        );
        for bad in [
            r"C:\Program Files\Outro",
            r"C:\Program Files\ISLCx",
            r"C:\Program Files",
            r"C:\Vanta",
            r"C:\Windows\System32\drivers\x.sys",
            r"C:\Windows\Fonts\a.ttf", // mesmo listado, \Windows nunca
            r"C:\Program Files\ISLC\..\Outro",
            r"\\srv\x\y\z",
        ] {
            assert!(!destination_allowed(bad, &allowed), "{bad}");
        }
    }

    #[test]
    fn the_plan_is_checked_destination_hash_and_the_vanta_run_area() {
        let file = PlanFile { rel: "a.ini".into(), sha256: "0".repeat(64), size: 1 };
        let mut plan = RestorePlan {
            items: vec![PlanItem {
                name: "OBS".into(),
                source: r"D:\kit\config\obs".into(),
                destination: r"C:\Users\user\AppData\Roaming\obs".into(),
                is_folder: true,
                files: vec![file.clone()],
            }],
            allowed_destinations: vec![r"C:\Users\user\AppData\Roaming\obs".into()],
            ..RestorePlan::default()
        };
        assert!(validate_plan(&plan, r"C:\ProgramData").is_ok());
        plan.items[0].destination = r"C:\Program Files\Outro".into();
        assert!(validate_plan(&plan, r"C:\ProgramData").unwrap_err().contains("não está na lista permitida"));
        plan.items[0].destination = r"C:\Users\user\AppData\Roaming\obs\sub".into();
        assert!(validate_plan(&plan, r"C:\ProgramData").is_ok(), "dentro de um destino canônico");
        plan.allowed_destinations.push(r"C:\ProgramData\Vanta\run".into());
        plan.items[0].destination = r"C:\ProgramData\Vanta\run\x".into();
        assert!(validate_plan(&plan, r"C:\ProgramData").is_err(), "a área do Vanta nunca é destino");
        plan.items[0].destination = r"C:\Users\user\AppData\Roaming\obs".into();
        // pasta protegida: é a pasta de um destino permitido (arquivo único C:\Vanta\System\x.ps1), nunca outra
        plan.allowed_destinations.push(r"C:\Vanta\System\VantaSystem.ps1".into());
        plan.protected_dirs = vec![r"C:\Vanta\System".into()];
        assert!(validate_plan(&plan, r"C:\ProgramData").is_ok(), "a pasta do arquivo permitido");
        plan.protected_dirs = vec![r"C:\Vanta\Outra".into()];
        assert!(validate_plan(&plan, r"C:\ProgramData").unwrap_err().contains("pasta protegida"));
        plan.protected_dirs.clear();
        plan.items[0].files = vec![PlanFile { rel: r"..\x".into(), ..file.clone() }];
        assert!(validate_plan(&plan, r"C:\ProgramData").is_err(), "caminho relativo com ..");
        plan.items[0].files = vec![PlanFile { sha256: "xyz".into(), ..file }];
        assert!(validate_plan(&plan, r"C:\ProgramData").unwrap_err().contains("SHA-256"));
        plan.items.clear();
        plan.tasks.push(PlanTask {
            label: "t".into(),
            name: "a\" /f".into(),
            xml: String::new(),
            scripts: vec![],
        });
        assert!(validate_plan(&plan, r"C:\ProgramData").is_err(), "nome de tarefa com aspas");
        plan.tasks.clear();
        plan.processes.push("lghub; calc".into());
        assert!(validate_plan(&plan, r"C:\ProgramData").is_err());
    }

    #[test]
    fn every_source_file_is_listed_with_its_sha256_and_a_junction_inside_the_source_is_refused() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::create_dir_all(dir.path().join("sub")).unwrap();
        std::fs::write(dir.path().join("a.ini"), "alpha").unwrap();
        std::fs::write(dir.path().join(r"sub\b.ini"), "beta").unwrap();
        let files = hash_source(dir.path(), true).unwrap();
        assert_eq!(files.iter().map(|f| f.rel.as_str()).collect::<Vec<_>>(), ["a.ini", r"sub\b.ini"]);
        assert_eq!(files[0].sha256, "8ed3f6ad685b959ead7022518e1af76cd816f8e8ec7ccdda1ed4018e8f2223f8");
        assert_eq!(files[0].size, 5);
        let single = hash_source(&dir.path().join("a.ini"), false).unwrap();
        assert_eq!(single, vec![PlanFile { rel: "a.ini".into(), sha256: files[0].sha256.clone(), size: 5 }]);
        // uma junção dentro da origem: a lista não pode sair de lá
        let elsewhere = tempfile::tempdir().unwrap();
        std::fs::write(elsewhere.path().join("segredo.txt"), "x").unwrap();
        let made = std::process::Command::new("cmd.exe")
            .args([
                "/c",
                "mklink",
                "/J",
                &dir.path().join("atalho").to_string_lossy(),
                &elsewhere.path().to_string_lossy(),
            ])
            .output()
            .unwrap();
        assert!(made.status.success());
        assert!(hash_source(dir.path(), true).unwrap_err().to_string().contains("junção ou link"));
    }

    #[test]
    fn a_reg_file_may_only_touch_user_and_software_keys_and_never_what_starts_programs_or_deletes() {
        let ok = "Windows Registry Editor Version 5.00\r\n\r\n[HKEY_CURRENT_USER\\Software\\Obs]\r\n\"a\"=dword:1\r\n@=\"x\"\r\n";
        assert!(validate_reg(ok).is_ok());
        assert!(
            validate_reg(
                &ok.replace("HKEY_CURRENT_USER", "HKEY_LOCAL_MACHINE")
                    .replace("Software\\Obs", "SOFTWARE\\Obs")
            )
            .is_ok()
        );
        for bad in [
            "[HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Run]",
            "[HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\RunOnce]",
            "[HKEY_LOCAL_MACHINE\\SYSTEM\\CurrentControlSet\\Services\\x]",
            "[HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Winlogon]",
            "[HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Image File Execution Options\\a.exe]",
            "[HKEY_CURRENT_USER\\Software\\Classes\\.txt\\shell\\open\\command]",
            "[HKEY_CURRENT_USER\\Software\\Policies\\Microsoft]",
            "[HKEY_USERS\\.DEFAULT\\Software\\X]",
            "[-HKEY_CURRENT_USER\\Software\\Obs]",
            "[HKEY_CURRENT_USER\\Software\\Obs]\r\n\"a\"=-",
            "[HKEY_CURRENT_USER\\Software\\Obs]\r\n@=-",
        ] {
            let text = format!("Windows Registry Editor Version 5.00\r\n\r\n{bad}\r\n");
            assert!(validate_reg(&text).is_err(), "{bad}");
        }
        assert!(validate_reg("[HKEY_CURRENT_USER\\Software\\Obs]").unwrap_err().contains("cabeçalho"));
        assert!(
            validate_reg("Windows Registry Editor Version 5.00\r\n").unwrap_err().contains("nenhuma chave")
        );
    }

    #[test]
    fn a_task_may_only_run_a_program_from_a_safe_place_as_the_restoring_user() {
        let isl = r"C:\Program Files\ISLC\Intelligent standby list cleaner ISLC.exe";
        let (programs, scripts) = validate_task(&task(SID, isl, "-minimized"), SID, &roots()).unwrap();
        assert_eq!((programs, scripts), (vec![isl.to_owned()], vec![]));
        let auto = task(
            SID,
            PS,
            "-NoProfile -File &quot;C:\\Users\\user\\AppData\\Local\\VantaSystem\\AutoOptimizer\\VantaSystem.ps1&quot;",
        );
        let (_, scripts) = validate_task(&auto, SID, &roots()).unwrap();
        assert_eq!(scripts, [r"C:\Users\user\AppData\Local\VantaSystem\AutoOptimizer\VantaSystem.ps1"]);
        for (bad, why) in [
            (task("S-1-5-18", isl, ""), "SYSTEM"),
            (task("SYSTEM", isl, ""), "SYSTEM"),
            (task("S-1-5-21-9-9-9-9", isl, ""), "outro usuário"),
            (task(SID, r"C:\Windows\System32\cmd.exe", "/c calc"), "cmd com argumento solto"),
            (task(SID, r"C:\Temp\x.exe", ""), "fora de lugar seguro"),
            (task(SID, "calc.exe", ""), "sem caminho completo"),
            (task(SID, "%TEMP%\\x.exe", ""), "variável sem valor"),
            (task(SID, PS, "-Command calc"), "-Command"),
            (task(SID, PS, "-File C:\\Temp\\x.ps1"), "sem aspas e fora"),
            (task(SID, PS, "-File \"C:\\Users\\user\\AppData\\Local\\VantaSystem\\a.ps1\" -Command calc"), "texto depois do script"),
            (task(SID, PS, "-NoProfile -Bypass -File \"C:\\Users\\user\\AppData\\Local\\VantaSystem\\a.ps1\""), "opção fora da lista"),
            (task(SID, PS, "-File \"C:\\Users\\user\\AppData\\Local\\VantaSystem\\a.ps1\" arg"), "argumento extra"),
            ("<Task><Actions><ComHandler><ClassId>{x}</ClassId></ComHandler></Actions></Task>".to_owned(), "COM"),
            ("<Task><Actions></Actions></Task>".to_owned(), "sem ação"),
            ("<!DOCTYPE x [<!ENTITY a \"b\">]><Task><Actions><Exec><Command>C:\\Program Files\\x.exe</Command></Exec></Actions></Task>".to_owned(), "DOCTYPE"),
        ] {
            assert!(validate_task(&bad, SID, &roots()).is_err(), "{why}");
        }
    }

    #[test]
    fn the_whole_action_is_checked_not_only_the_first_command() {
        let isl = r"C:\Program Files\ISLC\x.exe";
        // uma segunda ação que roda outra coisa
        let two = format!(
            "<Task><Actions><Exec><Command>{isl}</Command></Exec><Exec><Command>C:\\Temp\\mau.exe</Command></Exec></Actions></Task>"
        );
        assert!(validate_task(&two, SID, &roots()).unwrap_err().contains("não está em Program Files"));
        // elemento estranho na ação ou dentro do <Exec>
        let extra = format!("<Task><Actions><Exec><Command>{isl}</Command></Exec><Other/></Actions></Task>");
        assert!(validate_task(&extra, SID, &roots()).unwrap_err().contains("além de <Exec>"));
        let inner =
            format!("<Task><Actions><Exec><Command>{isl}</Command><Env>x</Env></Exec></Actions></Task>");
        assert!(validate_task(&inner, SID, &roots()).unwrap_err().contains("além de Command"));
        let twice = format!(
            "<Task><Actions><Exec><Command>{isl}</Command><Command>C:\\Temp\\y.exe</Command></Exec></Actions></Task>"
        );
        assert!(validate_task(&twice, SID, &roots()).unwrap_err().contains("exatamente um"));
        let dir = format!(
            "<Task><Actions><Exec><Command>{isl}</Command><WorkingDirectory>relativo</WorkingDirectory></Exec></Actions></Task>"
        );
        assert!(validate_task(&dir, SID, &roots()).unwrap_err().contains("diretório de trabalho"));
    }

    #[test]
    fn a_task_with_maximum_privilege_may_only_run_from_program_files_or_the_vanta_system_folder() {
        let script = |path: &str| {
            format!("-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File &quot;{path}&quot;")
        };
        // C:\Vanta\System (só administradores) é permitido; a pasta restaurada (usuário escreve) não
        let ok =
            validate_task(&elevated_task(PS, &script(r"C:\Vanta\System\VantaSystem.ps1")), SID, &roots())
                .unwrap();
        assert_eq!(ok.1, [r"C:\Vanta\System\VantaSystem.ps1"]);
        let refused = validate_task(
            &elevated_task(
                PS,
                &script(r"C:\Users\user\AppData\Local\VantaSystem\AutoOptimizer\VantaSystem.ps1"),
            ),
            SID,
            &roots(),
        )
        .unwrap_err();
        assert!(
            refused.contains("privilégio máximo") && refused.contains("só de administradores"),
            "{refused}"
        );
        assert!(
            validate_task(&elevated_task(PS, &script(r"C:\AutoOptimizer\NathaSystem.ps1")), SID, &roots())
                .is_err()
        );
        assert!(
            validate_task(
                &task(SID, PS, &script(r"C:\Users\user\AppData\Local\VantaSystem\a.ps1")),
                SID,
                &roots()
            )
            .is_ok(),
            "comum: aceita"
        );
        assert!(validate_task(&elevated_task(r"C:\Program Files\ISLC\x.exe", ""), SID, &roots()).is_ok());
        assert!(
            validate_task(
                &elevated_task(r"C:\Users\user\AppData\Local\VantaSystem\x.exe", ""),
                SID,
                &roots()
            )
            .is_err()
        );
        assert!(
            validate_task(
                &elevated_task(r"C:\Windows\System32\cmd.exe", r#"/c "C:\Users\user\a.bat""#),
                SID,
                &roots()
            )
            .unwrap_err()
            .contains("cmd.exe não roda")
        );
    }

    #[test]
    fn a_user_task_may_run_a_batch_file_of_the_user_profile_through_the_full_path_cmd() {
        let cmd = r"C:\Windows\System32\cmd.exe";
        let bat = r"/c &quot;C:\Users\user\AppData\Local\Overview\estudar_vods.bat&quot;";
        assert!(validate_task(&task(SID, cmd, bat), SID, &roots()).is_ok());
        for (args, why) in [
            (r#"/c "C:\Users\user\a.bat" & calc"#.to_owned(), "encadeado"),
            (r#"/c "C:\Users\user\a.exe""#.to_owned(), "não é .bat"),
            (r#"/c "C:\Temp\a.bat""#.to_owned(), "fora do perfil"),
            (r#"/k "C:\Users\user\a.bat""#.to_owned(), "/k"),
            (r#"/c "%TEMP%\a.bat""#.to_owned(), "variável sem valor"),
            (r#"/c "C:\Users\user\a.bat" extra"#.to_owned(), "argumento extra"),
        ] {
            assert!(validate_task(&task(SID, cmd, &args), SID, &roots()).is_err(), "{why}");
        }
    }

    #[test]
    fn a_script_interpreter_without_a_full_path_is_refused_for_the_right_reason() {
        for bare in ["cmd.exe", "powershell.exe", "wscript.exe"] {
            let why = validate_task(&task(SID, bare, "/c x"), SID, &roots()).unwrap_err();
            assert!(why.contains("interpretador") && why.contains("PATH"), "{why}");
        }
        let other = validate_task(&task(SID, "meuapp.exe", ""), SID, &roots()).unwrap_err();
        assert!(other.contains("não é o caminho completo"), "{other}");
    }

    #[test]
    fn a_run_entry_must_be_a_quoted_exe_in_program_files_or_a_restored_folder() {
        let r = roots();
        assert!(
            validate_run_command(
                r#""C:\Program Files\LGHUB\system_tray\lghub_system_tray.exe" --minimized"#,
                &r
            )
            .is_ok()
        );
        assert!(validate_run_command(r#""C:\Users\user\AppData\Local\VantaSystem\x.exe""#, &r).is_ok());
        for bad in [
            r#"C:\Program Files\x.exe"#,
            r#""C:\Temp\x.exe""#,
            r#""C:\Program Files\x.exe" & calc"#,
            r#""C:\Program Files\x.bat""#,
            r#""C:\Program Files\..\x.exe""#,
        ] {
            assert!(validate_run_command(bad, &r).is_err(), "{bad}");
        }
    }

    #[test]
    fn the_plan_json_carries_data_only_with_file_hashes_and_the_allowed_destinations() {
        let plan = RestorePlan {
            items: vec![PlanItem {
                name: "ISLC".into(),
                source: r"D:\kit\islc".into(),
                destination: r"C:\Program Files\ISLC".into(),
                is_folder: true,
                files: vec![PlanFile { rel: "a.ini".into(), sha256: "ab".repeat(32), size: 7 }],
            }],
            texts: vec![PlanText {
                name: "mic".into(),
                destination: r"C:\Program Files\EqualizerAPO\config\config.txt".into(),
                content: b"Device: x".to_vec(),
            }],
            services: vec!["LGHUBUpdaterService".into()],
            allowed_destinations: vec![r"C:\Program Files\ISLC".into()],
            protected_dirs: vec![r"C:\Vanta\System".into()],
            ..RestorePlan::default()
        };
        let json = plan.to_json();
        let value: Value = serde_json::from_str(&json).unwrap();
        assert_eq!(value["version"], 2);
        assert_eq!(value["items"][0]["files"][0]["sha256"], "ab".repeat(32));
        assert_eq!(value["texts"][0]["contentBase64"], "RGV2aWNlOiB4");
        assert_eq!(value["allowedDestinations"][0], r"C:\Program Files\ISLC");
        assert_eq!(value["protectedDirs"][0], r"C:\Vanta\System");
        assert!(!json.contains(".cmd"), "o plano não leva script");
        assert_eq!(base64(b""), "");
        assert_eq!(base64(b"ab"), "YWI=");
    }
}
