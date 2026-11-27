//! Lado real dos níveis e das páginas manuais da v1.1: detecção do PC, energia, apps, dispositivos e o diário em disco.
//! Tudo que muda o Windows passa por [`Executor`] (o real roda o processo; os testes gravam os comandos).
//! Energia, apps e dispositivos pedem administrador (o Vanta Tools já abre elevado); o erro volta ao chamador por item.

use std::path::{Path, PathBuf};
use std::process::Command;

use vanta_core::apps::{self, Acao, AppAlvo, EstadoApp, LeitorApps};
use vanta_core::avancado::{self, Dispositivo};
use vanta_core::diario::{Diario, Entrada, Status};
use vanta_core::energia::{self, OpcaoEnergia};
use vanta_core::niveis::{Ambiente, Deteccao, SCRIPT_DETECCAO, ler_deteccao};

/// Roda um programa e devolve a saída de texto, ou o erro (código de saída + o que ele disse).
pub trait Executor {
    fn run(&self, program: &str, args: &[String]) -> Result<String, String>;
}

pub struct ProcessExecutor;

impl Executor for ProcessExecutor {
    fn run(&self, program: &str, args: &[String]) -> Result<String, String> {
        use std::os::windows::process::CommandExt;
        let out = Command::new(program)
            .args(args)
            .creation_flags(0x0800_0000) // CREATE_NO_WINDOW
            .output()
            .map_err(|e| format!("{program}: {e}"))?;
        let text = String::from_utf8_lossy(&out.stdout).into_owned();
        if out.status.success() {
            Ok(text)
        } else {
            let err = String::from_utf8_lossy(&out.stderr);
            Err(format!("{program} saiu com {}: {}", out.status.code().unwrap_or(-1), format!("{} {}", text.trim(), err.trim()).trim()))
        }
    }
}

/// Prefixo de todo script: a saída sai em UTF-8 (o Rust lê UTF-8); sem ele o Windows PowerShell usa a página OEM e
/// "Impressão" vira "Impresso" nos nomes de dispositivos.
const UTF8_SAIDA: &str = "[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false); $OutputEncoding = [Console]::OutputEncoding; ";

pub(crate) fn powershell(exec: &dyn Executor, script: &str) -> Result<String, String> {
    let script = format!("{UTF8_SAIDA}{script}");
    exec.run("powershell.exe", &["-NoProfile".into(), "-NonInteractive".into(), "-ExecutionPolicy".into(), "Bypass".into(), "-Command".into(), script])
}

/// Detecta SSD, bateria, PC gerenciado e a edição/build do Windows. Falhou: valores conservadores (ver `ler_deteccao`).
pub fn detectar(exec: &dyn Executor) -> (Deteccao, Ambiente) {
    ler_deteccao(&powershell(exec, SCRIPT_DETECCAO).unwrap_or_default())
}

// ---------- diário em disco ----------

/// `%ProgramData%\Vanta\Tools\niveis.json`.
pub fn caminho_diario() -> PathBuf {
    PathBuf::from(std::env::var("ProgramData").unwrap_or_else(|_| r"C:\ProgramData".into())).join("Vanta").join("Tools").join("niveis.json")
}

pub fn ler_diario(path: &Path) -> Result<Diario, String> {
    match std::fs::read_to_string(path) {
        Ok(text) => Diario::from_json(&text),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(Diario::default()),
        Err(e) => Err(format!("{}: {e}", path.display())),
    }
}

/// Grava por arquivo temporário + troca: uma queda no meio não deixa o diário pela metade.
pub fn gravar_diario(path: &Path, diario: &Diario) -> Result<(), String> {
    let dir = path.parent().ok_or("caminho do diário sem pasta")?;
    std::fs::create_dir_all(dir).map_err(|e| format!("{}: {e}", dir.display()))?;
    let temp = path.with_extension("json.tmp");
    std::fs::write(&temp, diario.to_json()).map_err(|e| format!("{}: {e}", temp.display()))?;
    std::fs::rename(&temp, path).map_err(|e| format!("{}: {e}", path.display()))
}

// ---------- energia ----------

fn plano_ativo(exec: &dyn Executor) -> Result<String, String> {
    let out = exec.run("powercfg.exe", &["/getactivescheme".into()])?;
    energia::parse_active_scheme(&out).ok_or_else(|| "Não foi possível ler o plano de energia ativo.".to_owned())
}

fn plano_instalado(exec: &dyn Executor, guid: &str) -> bool {
    exec.run("powercfg.exe", &["/query".into(), guid.into(), "SUB_NONE".into()]).is_ok()
}

fn lista_de_planos(exec: &dyn Executor) -> String {
    exec.run("powercfg.exe", &["/list".into()]).unwrap_or_default()
}

fn remover_plano_criado(exec: &dyn Executor, guid: &str) {
    // só chamado para um plano que ACABAMOS de criar nesta execução (autoria conhecida)
    let _ = exec.run("powercfg.exe", &["/delete".into(), guid.into()]);
}

/// Liga as opções de energia. O plano do Vanta é uma cópia do plano ativo, criada com um GUID escolhido pelo Windows e
/// registrado no diário junto com o plano e o modo AC anteriores; ligar de novo reaproveita o plano comprovadamente nosso.
/// Devolve os avisos (por exemplo, o modo "Melhor desempenho" do Windows 11 indisponível).
pub fn energia_ligar(exec: &dyn Executor, opcoes: &[OpcaoEnergia], diario: &mut Diario, gravar: &mut dyn FnMut(&Diario) -> Result<(), String>) -> Result<Vec<String>, String> {
    let ativo = plano_ativo(exec)?;
    let lista = lista_de_planos(exec);
    let registrado = diario.entrada("energia").cloned();
    let proprio = energia::plano_e_nosso(registrado.as_ref().and_then(|e| e.plano_vanta.as_deref()), &lista);
    let (plano, criado_agora) = match proprio {
        Some(guid) => (guid, false),
        None => {
            if !opcoes.contains(&OpcaoEnergia::PlanoVanta) {
                return Err("As opções de CPU precisam do plano Vanta; ligue o plano Vanta primeiro.".to_owned());
            }
            // o diário guarda o plano e o modo anteriores ANTES de qualquer mudança
            let modo = powershell(exec, &energia::script_ler_modo_ac()).ok().map(|t| t.trim().to_ascii_lowercase()).filter(|t| energia::is_guid(t));
            diario.substituir(Entrada {
                id: "energia".into(),
                nivel: None,
                status: Status::EmAndamento,
                registro: vec![],
                servicos: vec![],
                plano_anterior: Some(ativo.clone()),
                plano_vanta: None,
                modo_ac_anterior: modo,
            });
            gravar(diario).map_err(|e| format!("diário: {e}"))?;
            let saida = exec.run("powercfg.exe", &energia::criar(&ativo)?)?;
            let novo = energia::parse_active_scheme(&saida).ok_or("O Windows não informou o GUID do plano criado.")?;
            if let Some(e) = diario.entradas.iter_mut().find(|e| e.id == "energia") {
                e.plano_vanta = Some(novo.clone());
            }
            if let Err(e) = gravar(diario) {
                remover_plano_criado(exec, &novo); // criado agora: é nosso
                return Err(format!("diário: {e}"));
            }
            (novo, true)
        }
    };
    let comandos = energia::configurar(&plano, opcoes)?;
    for c in &comandos.comandos {
        if let Err(e) = exec.run("powercfg.exe", c) {
            if criado_agora {
                let anterior = ativo.clone();
                let _ = exec.run("powercfg.exe", &["/setactive".into(), anterior]);
                remover_plano_criado(exec, &plano);
                diario.entradas.retain(|e| e.id != "energia");
                let _ = gravar(diario);
            }
            return Err(e);
        }
    }
    if let Some(e) = diario.entradas.iter_mut().find(|e| e.id == "energia") {
        e.status = Status::Concluido;
    }
    gravar(diario).map_err(|e| format!("diário: {e}"))?;
    let mut avisos = Vec::new();
    if opcoes.contains(&OpcaoEnergia::PlanoVanta) {
        // sem o modo original no diário não há como restaurá-lo: então o modo não é mudado (nada às cegas)
        let lido = diario.entrada("energia").is_some_and(|e| e.modo_ac_anterior.is_some());
        if !lido {
            avisos.push("O modo de energia AC atual não pôde ser lido; ele não foi alterado, para poder ser restaurado. O plano Vanta foi aplicado.".to_owned());
        } else {
            let ok = energia::script_modo_ac(energia::MODO_MELHOR_DESEMPENHO).ok().and_then(|s| powershell(exec, &s).ok()).is_some_and(|t| t.trim() == "ok");
            if !ok {
                avisos.push("O modo \"Melhor desempenho\" do Windows 11 não está disponível neste PC; o plano Vanta foi aplicado.".to_owned());
            }
        }
    }
    Ok(avisos)
}

/// Desfazer da energia: restaura o modo AC que estava antes (PRIMEIRO: se falhar, nada é desfeito e o diário fica) e depois
/// volta ao plano anterior e apaga SÓ o plano comprovadamente do Vanta (GUID no diário + nome na lista de planos). Sem a
/// prova de autoria o plano fica. Só descarta a entrada do diário quando tudo foi confirmado.
pub fn energia_desfazer(exec: &dyn Executor, diario: &mut Diario) -> Result<(), String> {
    let registrado = diario.entrada("energia").cloned().ok_or("A energia não está no diário: nada a desfazer.")?;
    if let Some(modo) = registrado.modo_ac_anterior.as_deref() {
        let confirmado = energia::script_modo_ac(modo)?;
        if !powershell(exec, &confirmado).is_ok_and(|t| t.trim() == "ok") {
            return Err("Não foi possível restaurar o modo de energia AC anterior; nada foi desfeito e o diário foi mantido. Tente de novo.".to_owned());
        }
    }
    let proprio = energia::plano_e_nosso(registrado.plano_vanta.as_deref(), &lista_de_planos(exec));
    let anterior = registrado.plano_anterior.clone();
    let instalado = anterior.as_deref().is_some_and(|g| plano_instalado(exec, g));
    for c in &energia::desfazer(anterior.as_deref(), instalado, proprio.as_deref()).comandos {
        let r = exec.run("powercfg.exe", c);
        if c[0] != "/delete" {
            r?; // o plano Vanta pode já ter sumido: apagar de novo não é erro
        }
    }
    diario.entradas.retain(|e| e.id != "energia");
    Ok(())
}

// ---------- apps ----------

pub struct LeitorReal<'a>(pub &'a dyn Executor);

impl LeitorApps for LeitorReal<'_> {
    fn instalado(&self, app: &AppAlvo) -> Option<bool> {
        if !app.appx.is_empty() {
            let out = powershell(self.0, &format!("@(Get-AppxPackage -Name '{}').Count", app.appx)).ok()?;
            return out.trim().parse::<u32>().ok().map(|n| n > 0);
        }
        let files: &[&str] = match app.chave {
            "onedrive" => &[r"%LOCALAPPDATA%\Microsoft\OneDrive\OneDrive.exe", r"%ProgramFiles%\Microsoft OneDrive\OneDrive.exe"],
            "edge" => &[r"%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe"],
            _ => return None,
        };
        Some(files.iter().any(|f| Path::new(&expand(f)).exists()))
    }
}

fn expand(template: &str) -> String {
    let mut out = String::new();
    let mut rest = template;
    while let Some(i) = rest.find('%') {
        out.push_str(&rest[..i]);
        let Some(j) = rest[i + 1..].find('%') else { break };
        out.push_str(&std::env::var(&rest[i + 1..i + 1 + j]).unwrap_or_default());
        rest = &rest[i + j + 2..];
    }
    out.push_str(rest);
    out
}

pub fn estado_app(exec: &dyn Executor, chave: &str) -> Result<EstadoApp, String> {
    let app = apps::achar(chave).map_err(|e| e.to_string())?;
    Ok(apps::estado(&LeitorReal(exec), app))
}

fn rodar(exec: &dyn Executor, acao: &Acao) -> Result<(), String> {
    exec.run(acao.programa, &acao.args).map(|_| ())
}

/// Remove o app só para o usuário atual e anota no diário (para o "Reinstalar app").
pub fn app_remover(exec: &dyn Executor, chave: &str, diario: &mut Diario, gravar: &mut dyn FnMut(&Diario) -> Result<(), String>) -> Result<(), String> {
    let app = apps::achar(chave).map_err(|e| e.to_string())?;
    let id = format!("app:{}", app.chave);
    diario.substituir(Entrada { id: id.clone(), nivel: None, status: Status::EmAndamento, registro: vec![], servicos: vec![], plano_anterior: None, plano_vanta: None, modo_ac_anterior: None });
    gravar(diario).map_err(|e| format!("diário: {e}"))?;
    let result = rodar(exec, &apps::remover(app));
    if result.is_ok() {
        if let Some(e) = diario.entradas.iter_mut().find(|e| e.id == id) {
            e.status = Status::Concluido;
        }
    } else {
        diario.entradas.retain(|e| e.id != id);
    }
    let _ = gravar(diario);
    result
}

pub fn app_reinstalar(exec: &dyn Executor, chave: &str, diario: &mut Diario) -> Result<(), String> {
    let app = apps::achar(chave).map_err(|e| e.to_string())?;
    rodar(exec, &apps::reinstalar(app))?;
    diario.entradas.retain(|e| e.id != format!("app:{}", app.chave));
    Ok(())
}

// ---------- dispositivos (Avançado) ----------

pub fn dispositivos(exec: &dyn Executor) -> Result<Vec<Dispositivo>, String> {
    powershell(exec, avancado::SCRIPT_INVENTARIO).map(|t| avancado::parse_inventario(&t))
}

/// Desliga UM dispositivo escolhido, depois de conferir o `InstanceId` no inventário lido agora; anota para o rollback.
pub fn dispositivo_desligar(exec: &dyn Executor, instance_id: &str, diario: &mut Diario, gravar: &mut dyn FnMut(&Diario) -> Result<(), String>) -> Result<(), String> {
    let inventario = dispositivos(exec)?;
    let script = avancado::desligar(instance_id, &inventario).map_err(|e| e.to_string())?;
    let id = format!("pnp:{instance_id}");
    diario.substituir(Entrada { id: id.clone(), nivel: None, status: Status::EmAndamento, registro: vec![], servicos: vec![], plano_anterior: None, plano_vanta: None, modo_ac_anterior: None });
    gravar(diario).map_err(|e| format!("diário: {e}"))?;
    match powershell(exec, &script) {
        Ok(_) => {
            if let Some(e) = diario.entradas.iter_mut().find(|e| e.id == id) {
                e.status = Status::Concluido;
            }
            gravar(diario).map_err(|e| format!("diário: {e}"))
        }
        Err(e) => {
            diario.entradas.retain(|x| x.id != id);
            let _ = gravar(diario);
            Err(e)
        }
    }
}

pub fn dispositivo_religar(exec: &dyn Executor, instance_id: &str, diario: &mut Diario) -> Result<(), String> {
    let script = avancado::religar(instance_id).map_err(|e| e.to_string())?;
    powershell(exec, &script)?;
    diario.entradas.retain(|e| e.id != format!("pnp:{instance_id}"));
    Ok(())
}

#[cfg(test)]
mod tests {
    use std::cell::RefCell;

    use super::*;

    const ANTERIOR: &str = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c";

    /// Grava os comandos e responde como um PC: plano ativo, plano Vanta (existe ou não), inventário.
    struct Fake {
        calls: RefCell<Vec<String>>,
        /// Planos de energia do PC: (guid, nome).
        planos: RefCell<Vec<(String, String)>>,
        ativo: RefCell<String>,
        falha: Option<&'static str>,
        modo_ac: &'static str,
    }

    const NOVO: &str = "5d1b9a3e-0a52-4c1e-9d37-2f6f1c0a7b11";
    const ATLAS: &str = "11111111-1111-1111-1111-111111111111";

    impl Fake {
        /// Um PC com o plano do usuário ativo e, ocupando o GUID fixo antigo do Vanta, o plano do Atlas.
        fn new(ativo: &str, _legado: bool) -> Self {
            let planos = vec![(ativo.to_owned(), "Meu plano".to_owned()), (ATLAS.to_owned(), "Atlas Power Scheme".to_owned())];
            Self { calls: RefCell::default(), planos: RefCell::new(planos), ativo: RefCell::new(ativo.into()), falha: None, modo_ac: "00000000-0000-0000-0000-000000000000" }
        }
        fn log(&self) -> String {
            self.calls.borrow().join("\n")
        }
        fn tem(&self, guid: &str) -> bool {
            self.planos.borrow().iter().any(|(g, _)| g == guid)
        }
    }

    impl Executor for Fake {
        fn run(&self, program: &str, args: &[String]) -> Result<String, String> {
            let line = format!("{program} {}", args.join(" "));
            self.calls.borrow_mut().push(line.clone());
            if self.falha.is_some_and(|f| line.contains(f)) {
                return Err("falhou".into());
            }
            let a: Vec<&str> = args.iter().map(String::as_str).collect();
            match a.first().copied() {
                Some("/getactivescheme") => return Ok(format!("Power Scheme GUID: {}  (Plano)", self.ativo.borrow())),
                Some("/list") => {
                    let ativo = self.ativo.borrow().clone();
                    return Ok(self.planos.borrow().iter().map(|(g, n)| format!("Power Scheme GUID: {g}  ({n}){}\n", if *g == ativo { " *" } else { "" })).collect());
                }
                Some("/query") => return if self.tem(a[1]) { Ok(String::new()) } else { Err("nao existe".into()) },
                Some("/duplicatescheme") => {
                    self.planos.borrow_mut().push((NOVO.to_owned(), "Meu plano (copia)".to_owned()));
                    return Ok(format!("Power Scheme GUID: {NOVO}  (Meu plano (copia))"));
                }
                Some("/changename") => {
                    if let Some(p) = self.planos.borrow_mut().iter_mut().find(|(g, _)| g == a[1]) {
                        p.1 = a[2].to_owned();
                    }
                    return Ok(String::new());
                }
                Some("/setactive") => {
                    *self.ativo.borrow_mut() = a[1].to_owned();
                    return Ok(String::new());
                }
                Some("/delete") => {
                    self.planos.borrow_mut().retain(|(g, _)| g != a[1]);
                    return Ok(String::new());
                }
                _ => {}
            }
            if line.contains("]::PowerGetUserConfiguredACPowerMode") {
                return Ok(format!("{}\n", self.modo_ac));
            }
            if line.contains("]::PowerSetUserConfiguredACPowerMode") {
                return Ok("ok".into());
            }
            if line.contains("Get-PnpDevice") {
                return Ok("ROOT\\MEDIA\\0000\tSpeaker legado\tMEDIA\tOK\nPCI\\VEN_10DE&DEV_1\\4&2\tGPU\tDisplay\tOK\n".into());
            }
            if line.contains("Get-AppxPackage") {
                return Ok("0\n".into());
            }
            Ok(String::new())
        }
    }

    fn ok_gravar() -> impl FnMut(&Diario) -> Result<(), String> {
        |_| Ok(())
    }

    #[test]
    fn power_on_creates_a_vanta_owned_plan_records_proof_and_off_deletes_only_that_plan() {
        let f = Fake::new(ANTERIOR, false);
        let mut d = Diario::default();
        let avisos = energia_ligar(&f, &[OpcaoEnergia::PlanoVanta], &mut d, &mut ok_gravar()).unwrap();
        assert!(avisos.is_empty());
        let e = d.entrada("energia").unwrap();
        assert_eq!((e.plano_anterior.as_deref(), e.plano_vanta.as_deref(), e.status), (Some(ANTERIOR), Some(NOVO), Status::Concluido));
        assert_eq!(e.modo_ac_anterior.as_deref(), Some("00000000-0000-0000-0000-000000000000"), "modo AC anterior guardado");
        assert!(f.log().contains(&format!("/duplicatescheme {ANTERIOR}\n")) || f.log().contains(&format!("/duplicatescheme {ANTERIOR}")));
        assert!(!f.log().contains(&format!("{ATLAS} ")) || !f.log().contains("/setacvalueindex 11111111"), "nunca mexe no GUID fixo antigo");
        assert!(!f.log().contains("/setdcvalueindex") && !f.log().contains("/delete"));
        assert_eq!(*f.ativo.borrow(), NOVO);
        // ligar de novo reaproveita o plano comprovadamente nosso (não cria outro) e não perde o plano anterior
        let antes = f.log().matches("/duplicatescheme").count();
        energia_ligar(&f, &[OpcaoEnergia::PlanoVanta, OpcaoEnergia::CpuMinima100], &mut d, &mut ok_gravar()).unwrap();
        assert_eq!(f.log().matches("/duplicatescheme").count(), antes);
        assert_eq!(d.entrada("energia").unwrap().plano_anterior.as_deref(), Some(ANTERIOR));
        assert!(f.log().contains("893dee8e"));
        // desfazer: volta ao plano do usuário, apaga o NOSSO e preserva o do Atlas
        energia_desfazer(&f, &mut d).unwrap();
        assert_eq!(*f.ativo.borrow(), ANTERIOR);
        assert!(!f.tem(NOVO) && f.tem(ATLAS) && f.tem(ANTERIOR), "o plano do Atlas e o do usuário continuam");
        assert!(d.entrada("energia").is_none());
    }

    #[test]
    fn undo_without_proof_never_deletes_a_plan_even_one_with_the_old_fixed_guid() {
        let f = Fake::new(ANTERIOR, false);
        // diário (de uma versão antiga) aponta para o GUID fixo que hoje é o plano do Atlas
        let mut d = Diario::default();
        d.entradas.push(Entrada { id: "energia".into(), nivel: None, status: Status::Concluido, registro: vec![], servicos: vec![], plano_anterior: Some(ANTERIOR.into()), plano_vanta: Some(ATLAS.into()), modo_ac_anterior: None });
        energia_desfazer(&f, &mut d).unwrap();
        assert!(f.tem(ATLAS), "o plano do Atlas não é apagado");
        assert!(!f.log().contains("/delete"));
        assert_eq!(*f.ativo.borrow(), ANTERIOR);
        // sem entrada no diário: nada a desfazer
        assert!(energia_desfazer(&f, &mut Diario::default()).is_err());
    }

    #[test]
    fn the_previous_ac_mode_is_restored_when_it_was_read() {
        let mut f = Fake::new(ANTERIOR, false);
        f.modo_ac = "961cc777-2547-4f9d-8174-7d86181b8a7a";
        let mut d = Diario::default();
        energia_ligar(&f, &[OpcaoEnergia::PlanoVanta], &mut d, &mut ok_gravar()).unwrap();
        assert_eq!(d.entrada("energia").unwrap().modo_ac_anterior.as_deref(), Some("961cc777-2547-4f9d-8174-7d86181b8a7a"));
        energia_desfazer(&f, &mut d).unwrap();
        assert!(f.log().matches("961cc777-2547-4f9d-8174-7d86181b8a7a").count() >= 1, "o modo anterior é regravado");
    }

    #[test]
    fn an_unreadable_ac_mode_is_never_changed_blindly() {
        let mut f = Fake::new(ANTERIOR, false);
        f.modo_ac = "indisponivel";
        let mut d = Diario::default();
        let avisos = energia_ligar(&f, &[OpcaoEnergia::PlanoVanta], &mut d, &mut ok_gravar()).unwrap();
        assert!(avisos.iter().any(|a| a.contains("não pôde ser lido")));
        assert_eq!(d.entrada("energia").unwrap().modo_ac_anterior, None);
        assert!(!f.log().contains("]::PowerSetUserConfiguredACPowerMode"), "o modo não foi mudado");
        assert_eq!(*f.ativo.borrow(), NOVO, "o plano Vanta foi aplicado mesmo assim");
        // desfazer sem modo anterior não força nenhum modo
        let g = f.log().matches("]::PowerSet").count();
        energia_desfazer(&f, &mut d).unwrap();
        assert_eq!(f.log().matches("]::PowerSet").count(), g);
    }

    #[test]
    fn a_failed_ac_mode_restore_keeps_the_journal_and_reports_the_error() {
        let mut f = Fake::new(ANTERIOR, false);
        f.modo_ac = "961cc777-2547-4f9d-8174-7d86181b8a7a";
        let mut d = Diario::default();
        energia_ligar(&f, &[OpcaoEnergia::PlanoVanta], &mut d, &mut ok_gravar()).unwrap();
        assert_eq!(*f.ativo.borrow(), NOVO);
        f.falha = Some("]::PowerSetUserConfiguredACPowerMode");
        let antes = f.log().matches("/setactive").count();
        let erro = energia_desfazer(&f, &mut d).unwrap_err();
        assert!(erro.contains("modo de energia AC") && erro.contains("diário foi mantido"), "{erro}");
        assert!(d.entrada("energia").is_some(), "o diário continua");
        assert_eq!(f.log().matches("/setactive").count(), antes, "o plano não foi mexido antes de o modo ser restaurado");
        assert_eq!(*f.ativo.borrow(), NOVO);
        // sem a falha, tentar de novo conclui
        f.falha = None;
        energia_desfazer(&f, &mut d).unwrap();
        assert_eq!(*f.ativo.borrow(), ANTERIOR);
        assert!(d.entrada("energia").is_none());
    }

    #[test]
    fn a_failed_journal_write_stops_before_any_powercfg_change_and_a_failed_step_rolls_back() {
        let f = Fake::new(ANTERIOR, false);
        let mut d = Diario::default();
        let r = energia_ligar(&f, &[OpcaoEnergia::PlanoVanta], &mut d, &mut |_| Err("disco cheio".into()));
        assert!(r.unwrap_err().contains("disco cheio"));
        assert!(!f.log().contains("/duplicatescheme"));
        let cpu_sozinha = Fake::new(ANTERIOR, false);
        assert!(energia_ligar(&cpu_sozinha, &[OpcaoEnergia::CpuMinima100], &mut Diario::default(), &mut ok_gravar()).is_err(), "CPU 100% pede o plano Vanta");
        // uma falha no meio: volta ao plano anterior e apaga só o que acabou de ser criado
        let mut g = Fake::new(ANTERIOR, false);
        g.falha = Some("/setacvalueindex");
        let mut d2 = Diario::default();
        assert!(energia_ligar(&g, &[OpcaoEnergia::PlanoVanta], &mut d2, &mut ok_gravar()).is_err());
        assert_eq!(*g.ativo.borrow(), ANTERIOR);
        assert!(!g.tem(NOVO) && g.tem(ATLAS) && d2.entrada("energia").is_none());
    }

    #[test]
    fn apps_are_removed_for_the_current_user_and_the_store_is_refused() {
        let f = Fake::new(ANTERIOR, false);
        let mut d = Diario::default();
        app_remover(&f, "outlook", &mut d, &mut ok_gravar()).unwrap();
        assert!(f.log().contains("Remove-AppxPackage") && !f.log().contains("-AllUsers"));
        assert_eq!(d.entrada("app:outlook").unwrap().status, Status::Concluido);
        assert!(app_remover(&f, "store", &mut d, &mut ok_gravar()).unwrap_err().contains("Microsoft Store"));
        app_reinstalar(&f, "outlook", &mut d).unwrap();
        assert!(f.log().contains("install --id 9NRX63209R7B --exact --source msstore") && d.entrada("app:outlook").is_none());
        assert_eq!(estado_app(&f, "teams").unwrap(), EstadoApp::Removido);
        let mut falha = Fake::new(ANTERIOR, false);
        falha.falha = Some("Remove-AppxPackage");
        assert!(app_remover(&falha, "teams", &mut d, &mut ok_gravar()).is_err() && d.entrada("app:teams").is_none());
    }

    #[test]
    fn a_device_is_disabled_only_after_the_inventory_check_and_can_be_enabled_again() {
        let f = Fake::new(ANTERIOR, false);
        let mut d = Diario::default();
        dispositivo_desligar(&f, "ROOT\\MEDIA\\0000", &mut d, &mut ok_gravar()).unwrap();
        assert!(f.log().contains("Disable-PnpDevice -InstanceId 'ROOT\\MEDIA\\0000' -Confirm:$false") && !f.log().to_lowercase().contains("-force"));
        assert!(d.entrada("pnp:ROOT\\MEDIA\\0000").is_some());
        assert!(dispositivo_desligar(&f, "PCI\\VEN_10DE&DEV_1\\4&2", &mut d, &mut ok_gravar()).unwrap_err().contains("Display"));
        assert!(dispositivo_desligar(&f, "ROOT\\NAO\\0", &mut d, &mut ok_gravar()).unwrap_err().contains("inventário"));
        dispositivo_religar(&f, "ROOT\\MEDIA\\0000", &mut d).unwrap();
        assert!(f.log().contains("Enable-PnpDevice") && d.entradas.is_empty());
    }

    #[test]
    fn the_journal_file_survives_a_round_trip_and_a_missing_file_is_empty() {
        let dir = std::env::temp_dir().join(format!("vanta-niveis-{}", std::process::id()));
        let path = dir.join("Vanta").join("Tools").join("niveis.json");
        assert_eq!(ler_diario(&path).unwrap(), Diario::default());
        let mut d = Diario::default();
        d.entradas.push(Entrada { id: "energia".into(), nivel: None, status: Status::EmAndamento, registro: vec![], servicos: vec![], plano_anterior: Some(ANTERIOR.into()), plano_vanta: None, modo_ac_anterior: None });
        gravar_diario(&path, &d).unwrap();
        assert_eq!(ler_diario(&path).unwrap(), d);
        assert!(!path.with_extension("json.tmp").exists());
        std::fs::write(&path, "{ quebrado").unwrap();
        assert!(ler_diario(&path).is_err(), "diário quebrado não é apagado em silêncio");
        std::fs::remove_dir_all(&dir).unwrap();
        assert!(caminho_diario().ends_with(r"Vanta\Tools\niveis.json"));
    }

    #[test]
    fn powershell_output_is_utf8_so_accents_in_device_names_survive() {
        let out = powershell(&ProcessExecutor, "'Fila de Impressão da Raiz ção'").unwrap();
        assert_eq!(out.trim(), "Fila de Impressão da Raiz ção");
        // todo script do Vanta passa pelo mesmo prefixo
        let f = Fake::new(ANTERIOR, false);
        dispositivos(&f).unwrap();
        assert!(f.log().contains("[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)"));
    }

    #[test]
    fn the_real_detection_runs_on_this_pc_and_reads_a_build() {
        let (_, amb) = detectar(&ProcessExecutor);
        assert!(amb.build >= 19041, "build lida: {}", amb.build);
        assert_eq!(expand("%SystemDrive%\\x").chars().nth(1), Some(':'));
    }
}
