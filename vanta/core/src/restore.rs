//! Plano de restauração do kit (sem executar) e a cópia das configurações atrás de [`Fs`]/[`FileWriter`].
//!
//! O plano diz, em ordem: instalar programas, fechar apps que prendem arquivos, copiar o que é do usuário,
//! instalar o driver NVIDIA, copiar as pastas protegidas num ÚNICO lote elevado (um pedido de administrador),
//! o que só vale depois do driver, e remapear o microfone Fifine do Equalizer APO pelo nome no destino.

use crate::fs::{FileWriter, Fs};
use crate::install::{CancelToken, Cancelled, CommandRunner, Progress, install_listed, parse_winget_list};
use crate::manifest::{KitItem, Manifest};
use crate::path::{PathError, join, parent, remap_user_path, resolve_inside_root, starts_with_dir};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RestoreOptions {
    pub install_applications: bool,
    pub restore_configurations: bool,
    /// Permite o lote com administrador para pastas protegidas.
    pub elevate_protected: bool,
    /// O usuário escolheu instalar o driver NVIDIA (o plano o põe antes do que depende dele).
    pub install_nvidia_driver: bool,
}

impl Default for RestoreOptions {
    fn default() -> Self {
        Self {
            install_applications: true,
            restore_configurations: true,
            elevate_protected: true,
            install_nvidia_driver: false,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RestoreContext {
    /// Pasta do pacote (onde está o `manifesto.json`).
    pub kit_root: String,
    pub old_profile: String,
    pub current_profile: String,
    /// O processo já roda como administrador.
    pub is_elevated: bool,
    /// Pastas que exigem administrador para escrever.
    pub protected_roots: Vec<String>,
}

/// Program Files, Program Files (x86), Windows, ProgramData e `\Vanta` (onde só administradores escrevem) do disco de sistema.
pub fn default_protected_roots(system_drive: &str) -> Vec<String> {
    let d = system_drive.trim_end_matches(['\\', ':']);
    ["Program Files", "Program Files (x86)", "Windows", "ProgramData", "Vanta"]
        .iter()
        .map(|p| format!("{d}:\\{p}"))
        .collect()
}

/// O destino fica em pasta protegida e o processo não é administrador.
pub fn needs_elevation(destination: &str, protected_roots: &[String], is_elevated: bool) -> bool {
    !is_elevated && protected_roots.iter().any(|root| starts_with_dir(destination, root))
}

/// Apps que prendem os próprios arquivos de configuração (o G HUB tem um serviço que roda como sistema).
pub const CONFIG_OWNERS: [&str; 16] = [
    "lghub",
    "lghub_agent",
    "lghub_system_tray",
    "lghub_updater",
    "Discord",
    "steam",
    "steamwebhelper",
    "brave",
    "claude",
    "obs64",
    "ts3client_win64",
    "qbittorrent",
    "notepad++",
    "vlc",
    "HandBrake",
    "MultiViewer",
];

/// Serviço que é parado antes de copiar o G HUB.
pub const SERVICES_TO_STOP: [&str; 1] = ["LGHUBUpdaterService"];

const OWNER_TABLE: [(&str, &[&str]); 12] = [
    ("lghub", &["lghub", "lghub_agent", "lghub_system_tray", "lghub_updater"]),
    ("g hub", &["lghub", "lghub_agent", "lghub_system_tray", "lghub_updater"]),
    ("discord", &["Discord"]),
    ("vencord", &["Discord"]),
    ("steam", &["steam", "steamwebhelper"]),
    ("brave", &["brave"]),
    ("obs-studio", &["obs64"]),
    ("ts3client", &["ts3client_win64"]),
    ("teamspeak", &["ts3client_win64"]),
    ("qbittorrent", &["qbittorrent"]),
    ("notepad++", &["notepad++"]),
    ("multiviewer", &["MultiViewer"]),
];

/// Processos que prendem o que o item restaura (pelo nome do item e pelo destino).
pub fn owners_for(name: &str, restore_path: &str) -> Vec<String> {
    let hay = format!("{} {}", name.to_lowercase(), restore_path.to_lowercase());
    let mut found: Vec<String> = Vec::new();
    let mut add = |processes: &[&str]| {
        for p in processes {
            if !found.iter().any(|f| f.eq_ignore_ascii_case(p)) {
                found.push((*p).to_owned());
            }
        }
    };
    for (needle, processes) in OWNER_TABLE {
        if hay.contains(needle) {
            add(processes);
        }
    }
    if name.to_lowercase().starts_with("obs") {
        add(&["obs64"]);
    }
    if hay.contains("\\vlc") || name.eq_ignore_ascii_case("vlc") {
        add(&["vlc"]);
    }
    if hay.contains("handbrake") {
        add(&["HandBrake"]);
    }
    found
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MicRemap {
    /// `config.txt` do Equalizer APO, no destino.
    pub config_path: String,
    /// Trecho do nome do microfone (`fifine`).
    pub device_name: String,
    /// O arquivo fica em pasta protegida e o processo não é administrador: o remapeamento vai dentro do lote elevado.
    pub needs_elevation: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PlannedItem {
    pub name: String,
    /// Origem no kit (caminho completo).
    pub source: String,
    /// Destino no Windows, já com o perfil atual.
    pub destination: String,
    pub is_folder: bool,
    pub protected: bool,
    pub close: Vec<String>,
    /// Só vale depois do driver NVIDIA instalado.
    pub after_nvidia_driver: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Step {
    InstallPrograms,
    CloseApps {
        processes: Vec<String>,
    },
    CopyConfigs {
        items: Vec<PlannedItem>,
    },
    InstallNvidiaDriver,
    /// O único lote com administrador: todas as pastas protegidas, de qualquer fase.
    ElevatedBatch {
        items: Vec<PlannedItem>,
        remaps: Vec<MicRemap>,
    },
    CopyAfterDriver {
        items: Vec<PlannedItem>,
    },
    RemapMicrophone {
        remaps: Vec<MicRemap>,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct RestorePlan {
    pub steps: Vec<Step>,
    /// Itens cujo caminho no manifesto sai do kit: não entram no plano, viram falha.
    pub rejected: Vec<(String, PathError)>,
}

impl RestorePlan {
    pub fn position(&self, wanted: impl Fn(&Step) -> bool) -> Option<usize> {
        self.steps.iter().position(wanted)
    }

    pub fn elevated_batches(&self) -> usize {
        self.steps.iter().filter(|s| matches!(s, Step::ElevatedBatch { .. })).count()
    }
}

fn is_nvidia(item: &KitItem, destination: &str) -> bool {
    item.name.to_lowercase().starts_with("nvidia")
        || destination.to_lowercase().contains("\\nvidia corporation\\")
}

fn is_equalizer_config(destination: &str) -> bool {
    destination.to_lowercase().contains("\\equalizerapo\\config")
}

/// Monta o plano de restauração do manifesto. Não toca no disco.
pub fn plan_restore(manifest: &Manifest, ctx: &RestoreContext, options: &RestoreOptions) -> RestorePlan {
    let mut plan = RestorePlan::default();
    let mut normal = Vec::new();
    let mut after_driver = Vec::new();
    let mut elevated = Vec::new();
    let mut remaps = Vec::new();
    let mut closing: Vec<String> = Vec::new();

    if options.restore_configurations {
        for item in manifest.items.iter().filter(|item| item.extra_kind().is_none()) {
            let source = match resolve_inside_root(&ctx.kit_root, &item.kit_path) {
                Ok(source) => source,
                Err(error) => {
                    plan.rejected.push((item.name.clone(), error));
                    continue;
                }
            };
            let destination = remap_user_path(&item.restore_path, &ctx.old_profile, &ctx.current_profile);
            let protected = options.elevate_protected
                && needs_elevation(&destination, &ctx.protected_roots, ctx.is_elevated);
            let close = owners_for(&item.name, &destination);
            for process in &close {
                if !closing.iter().any(|c| c.eq_ignore_ascii_case(process)) {
                    closing.push(process.clone());
                }
            }
            let planned = PlannedItem {
                name: item.name.clone(),
                source,
                is_folder: item.is_folder(),
                protected,
                close,
                after_nvidia_driver: is_nvidia(item, &destination),
                destination: destination.clone(),
            };
            let remap_needs_admin = needs_elevation(&destination, &ctx.protected_roots, ctx.is_elevated);
            // Sem permissão de administrador não há como gravar em Program Files: o remapeamento fica de fora.
            if is_equalizer_config(&destination)
                && item.is_folder()
                && (!remap_needs_admin || options.elevate_protected)
            {
                remaps.push(MicRemap {
                    config_path: join(&destination, "config.txt"),
                    device_name: "fifine".into(),
                    needs_elevation: remap_needs_admin,
                });
            }
            if protected {
                elevated.push(planned);
            } else if planned.after_nvidia_driver {
                after_driver.push(planned);
            } else {
                normal.push(planned);
            }
        }
    }

    if options.install_applications {
        plan.steps.push(Step::InstallPrograms);
    }
    if !closing.is_empty() {
        plan.steps.push(Step::CloseApps { processes: closing });
    }
    if !normal.is_empty() {
        plan.steps.push(Step::CopyConfigs { items: normal });
    }
    // O driver vem antes de tudo o que depende dele: o lote elevado (que pode levar o perfil NVIDIA) e as cópias pós-driver.
    let depends_on_driver = after_driver.iter().chain(&elevated).any(|i| i.after_nvidia_driver);
    if options.install_nvidia_driver && depends_on_driver {
        plan.steps.push(Step::InstallNvidiaDriver);
    }
    let (elevated_remaps, user_remaps): (Vec<_>, Vec<_>) =
        remaps.into_iter().partition(|r| r.needs_elevation);
    if !elevated.is_empty() || !elevated_remaps.is_empty() {
        plan.steps.push(Step::ElevatedBatch { items: elevated, remaps: elevated_remaps });
    }
    if !after_driver.is_empty() {
        plan.steps.push(Step::CopyAfterDriver { items: after_driver });
    }
    if !user_remaps.is_empty() {
        plan.steps.push(Step::RemapMicrophone { remaps: user_remaps });
    }
    plan
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AudioEndpoint {
    pub friendly_name: String,
    /// Ex.: `SWD\MMDEVAPI\{0.0.1.00000000}.{3d6f1c2a-...}`: `{0.0.1.` é captura (microfone).
    pub instance_id: String,
}

fn is_guid(text: &str) -> bool {
    let parts: Vec<&str> = text.split('-').collect();
    parts.len() == 5
        && parts
            .iter()
            .zip([8, 4, 4, 4, 12])
            .all(|(p, n)| p.len() == n && p.chars().all(|c| c.is_ascii_hexdigit()))
}

/// O GUID `{...}` do microfone cujo nome contém `device_name`, escolhendo só entradas de captura.
pub fn find_microphone_guid(endpoints: &[AudioEndpoint], device_name: &str) -> Option<String> {
    let wanted = device_name.to_lowercase();
    endpoints
        .iter()
        .filter(|e| e.friendly_name.to_lowercase().contains(&wanted) && e.instance_id.contains("{0.0.1."))
        .find_map(|e| {
            let start = e.instance_id.rfind(".{")? + 2;
            let end = e.instance_id[start..].find('}')? + start;
            let guid = &e.instance_id[start..end];
            is_guid(guid).then(|| guid.to_lowercase())
        })
}

/// Troca o GUID da linha `Device: <nome> {guid}` do `config.txt` do Equalizer APO. `None` se não há essa linha.
pub fn remap_microphone(config: &str, device_name: &str, new_guid: &str) -> Option<String> {
    let wanted = device_name.to_lowercase();
    let mut changed = false;
    let mut out = Vec::new();
    for line in config.split_inclusive('\n') {
        let lower = line.to_lowercase();
        let trimmed = lower.trim_start();
        if trimmed.starts_with("device:")
            && trimmed.contains(&wanted)
            && let (Some(open), Some(close)) = (line.rfind('{'), line.rfind('}'))
            && open < close
            && is_guid(&line[open + 1..close])
        {
            out.push(format!("{}{{{new_guid}}}{}", &line[..open], &line[close + 1..]));
            changed = true;
            continue;
        }
        out.push(line.to_owned());
    }
    changed.then(|| out.concat())
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MicOutcome {
    Remapped,
    /// Microfone não conectado: vira AVISO, não falha.
    DeviceNotFound,
    /// O `config.txt` não tem a linha do microfone (nada a trocar).
    NoDeviceLine,
    Failed(String),
}

/// Aplica o remapeamento no disco: lê o `config.txt`, troca o GUID e grava de volta de forma atômica.
pub fn apply_microphone_remap(
    remap: &MicRemap,
    endpoints: &[AudioEndpoint],
    fs: &dyn Fs,
    writer: &dyn FileWriter,
) -> MicOutcome {
    let Some(guid) = find_microphone_guid(endpoints, &remap.device_name) else {
        return MicOutcome::DeviceNotFound;
    };
    let Ok(config) = fs.read_to_string(&remap.config_path) else {
        return MicOutcome::Failed(format!("{} não pôde ser lido.", remap.config_path));
    };
    let Some(updated) = remap_microphone(&config, &remap.device_name, &guid) else {
        return MicOutcome::NoDeviceLine;
    };
    match writer.write_atomic(&remap.config_path, &updated) {
        Ok(()) => MicOutcome::Remapped,
        Err(error) => MicOutcome::Failed(error.to_string()),
    }
}
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct ConfigOutcome {
    pub succeeded: usize,
    pub failures: Vec<String>,
    /// Pastas em que algum arquivo ficou preso e o processo não é administrador: tentar de novo no lote elevado.
    pub deferred: Vec<PlannedItem>,
    /// Destino de CADA arquivo que esta execução copiou com sucesso (quem pós-processa só mexe no que está aqui).
    pub copied: Vec<String>,
}

fn copy_folder(
    source: &str,
    destination: &str,
    fs: &dyn Fs,
    writer: &dyn FileWriter,
    cancel: &CancelToken,
    skipped: &mut Vec<String>,
    copied: &mut Vec<String>,
) -> Result<(), String> {
    writer.create_dir_all(destination).map_err(|e| e.to_string())?;
    for entry in fs.read_dir(source).map_err(|e| e.to_string())? {
        if cancel.is_cancelled() {
            return Err("cancelado".into());
        }
        if entry.is_link {
            return Err("Atalhos e links dentro do pacote não são copiados.".into());
        }
        let from = join(source, &entry.name);
        let to = join(destination, &entry.name);
        if entry.is_dir {
            copy_folder(&from, &to, fs, writer, cancel, skipped, copied)?;
        } else if let Err(error) = copy_file(&from, &to, writer) {
            skipped.push(format!("{to} ({error})")); // arquivo preso ou negado: segue com o resto
        } else {
            copied.push(to);
        }
    }
    Ok(())
}

fn copy_file(source: &str, destination: &str, writer: &dyn FileWriter) -> std::io::Result<()> {
    writer.clear_readonly(destination)?; // destino somente leitura fazia a troca falhar com "acesso negado"
    writer.copy_atomic(source, destination)
}

/// Copia os itens de configuração para o perfil atual. Cancelar para antes do próximo arquivo, sem deixar parcial.
pub fn copy_configs(
    items: &[PlannedItem],
    options: &RestoreOptions,
    ctx: &RestoreContext,
    fs: &dyn Fs,
    writer: &dyn FileWriter,
    cancel: &CancelToken,
    progress: &mut dyn FnMut(&Progress),
) -> Result<ConfigOutcome, Cancelled> {
    let mut outcome = ConfigOutcome::default();
    let total = items.len();
    for (index, item) in items.iter().enumerate() {
        if cancel.is_cancelled() {
            return Err(Cancelled);
        }
        progress(&Progress {
            phase: "Configurações".into(),
            item: item.name.clone(),
            completed: index,
            total,
            message: format!("Restaurando {}", item.name),
        });
        if cancel.is_cancelled() {
            return Err(Cancelled);
        }
        let mut deferred = false;
        if !fs.exists(&item.source) {
            outcome.failures.push(format!("{}: O item de origem não está no pacote.", item.name));
        } else if !fs.is_dir(&item.source) {
            let result = parent(&item.destination)
                .ok_or_else(|| "O destino não tem uma pasta pai válida.".to_owned())
                .and_then(|dir| writer.create_dir_all(&dir).map_err(|e| e.to_string()))
                .and_then(|()| copy_file(&item.source, &item.destination, writer).map_err(|e| e.to_string()));
            match result {
                Ok(()) => {
                    outcome.succeeded += 1;
                    outcome.copied.push(item.destination.clone());
                }
                Err(error) => outcome.failures.push(format!("{}: {error}", item.name)),
            }
        } else {
            let mut skipped = Vec::new();
            match copy_folder(
                &item.source,
                &item.destination,
                fs,
                writer,
                cancel,
                &mut skipped,
                &mut outcome.copied,
            ) {
                Err(error) if cancel.is_cancelled() && error == "cancelado" => return Err(Cancelled),
                Err(error) => outcome.failures.push(format!("{}: {error}", item.name)),
                Ok(()) if !skipped.is_empty() && options.elevate_protected && !ctx.is_elevated => {
                    outcome.deferred.push(item.clone()); // ex.: G HUB, preso pelo serviço dele: tenta de novo com admin
                    deferred = true;
                }
                Ok(()) if !skipped.is_empty() => outcome.failures.push(format!(
                    "{}: {} arquivo(s) não copiado(s), ex.: {}",
                    item.name,
                    skipped.len(),
                    skipped[0]
                )),
                Ok(()) => outcome.succeeded += 1,
            }
        }
        let message = if deferred {
            format!("{} vai no lote com administrador", item.name)
        } else {
            format!("{} de {total} concluídos", index + 1)
        };
        progress(&Progress {
            phase: "Configurações".into(),
            item: item.name.clone(),
            completed: index + 1,
            total,
            message,
        });
    }
    Ok(outcome)
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct RestoreResult {
    pub apps_succeeded: usize,
    pub configurations_succeeded: usize,
    pub failures: Vec<String>,
    /// O que ficou para o lote elevado (pastas protegidas e arquivos presos), para o Vanta Tools executar.
    pub elevated_pending: Vec<PlannedItem>,
}

/// O que a restauração precisa do mundo: disco (leitura e escrita) e o programa que instala (winget).
#[derive(Clone, Copy)]
pub struct RestoreDeps<'a> {
    pub fs: &'a dyn Fs,
    pub writer: &'a dyn FileWriter,
    pub runner: &'a dyn CommandRunner,
}

/// Executa o que dá sem administrador: programas e cópias do usuário. O lote elevado e o driver ficam com o Vanta Tools.
pub fn run_restore(
    manifest: &Manifest,
    ctx: &RestoreContext,
    options: &RestoreOptions,
    deps: &RestoreDeps,
    cancel: &CancelToken,
    progress: &mut dyn FnMut(&Progress),
) -> Result<RestoreResult, Cancelled> {
    let RestoreDeps { fs, writer, runner } = *deps;
    let mut result = RestoreResult::default();
    let plan = plan_restore(manifest, ctx, options);
    result.failures.extend(plan.rejected.iter().map(|(name, error)| format!("{name}: {error}")));
    for step in &plan.steps {
        match step {
            Step::InstallPrograms => {
                let list = join(&ctx.kit_root, "winget.txt");
                if fs.exists(&list) {
                    let ids = parse_winget_list(&fs.read_to_string(&list).unwrap_or_default());
                    let (ok, failed) = install_listed(&ids, runner, cancel, progress)?;
                    result.apps_succeeded = ok;
                    result.failures.extend(failed);
                } else {
                    result.failures.push("A lista winget.txt não foi encontrada no pacote.".into());
                }
            }
            Step::CopyConfigs { items } | Step::CopyAfterDriver { items } => {
                let outcome = copy_configs(items, options, ctx, fs, writer, cancel, progress)?;
                result.configurations_succeeded += outcome.succeeded;
                result.failures.extend(outcome.failures);
                result.elevated_pending.extend(outcome.deferred);
            }
            Step::ElevatedBatch { items, .. } => result.elevated_pending.extend(items.iter().cloned()),
            Step::CloseApps { .. } | Step::InstallNvidiaDriver | Step::RemapMicrophone { .. } => {}
        }
    }
    Ok(result)
}

#[cfg(test)]
mod tests {
    use std::cell::RefCell;
    use std::io;

    use super::*;
    use crate::install::CommandResult;
    use crate::manifest::parse;
    use crate::testing::MemFs;

    const KIT: &str = r"K:\MeuPlaybook\pacote";
    const OLD: &str = r"C:\Users\Old";
    const NEW: &str = r"C:\Users\New";

    type ExitCode = Box<dyn Fn(&[String]) -> i32>;

    struct Runner {
        calls: RefCell<Vec<(String, Vec<String>)>>,
        code: ExitCode,
    }

    impl Runner {
        fn ok() -> Self {
            Self { calls: RefCell::new(Vec::new()), code: Box::new(|_| 0) }
        }
    }

    impl CommandRunner for Runner {
        fn run(&self, executable: &str, arguments: &[String]) -> io::Result<CommandResult> {
            self.calls.borrow_mut().push((executable.to_owned(), arguments.to_vec()));
            Ok(CommandResult {
                exit_code: (self.code)(arguments),
                stdout: String::new(),
                stderr: String::new(),
            })
        }
    }

    fn ctx(elevated: bool) -> RestoreContext {
        RestoreContext {
            kit_root: KIT.into(),
            old_profile: OLD.into(),
            current_profile: NEW.into(),
            is_elevated: elevated,
            protected_roots: default_protected_roots("C"),
        }
    }

    fn run(
        fs: &MemFs,
        manifest: &str,
        options: &RestoreOptions,
        runner: &Runner,
        cancel: &CancelToken,
        progress: &mut dyn FnMut(&Progress),
    ) -> Result<RestoreResult, Cancelled> {
        run_restore(
            &parse(manifest).unwrap(),
            &ctx(false),
            options,
            &RestoreDeps { fs, writer: fs, runner },
            cancel,
            progress,
        )
    }

    #[test]
    fn registry_and_task_files_are_extras_not_configuration_copies() {
        let manifest = parse(
            r#"{"itens":[
              {"tipo":"pasta","nome":"OBS","destino":"config/obs","origem":"C:/Users/Old/AppData/Roaming/obs"},
              {"tipo":"arquivo","nome":"Reg OBS","destino":"config/registro/obs.reg","origem":"C:/Users/Old/obs.reg"},
              {"tipo":"arquivo","nome":"Tarefa","destino":"estado/tarefas/Auto.xml","origem":"C:/Users/Old/Auto.xml"}]}"#,
        )
        .unwrap();
        let plan = plan_restore(&manifest, &ctx(false), &RestoreOptions::default());
        let copied: Vec<&str> = plan
            .steps
            .iter()
            .flat_map(|step| match step {
                Step::CopyConfigs { items } | Step::CopyAfterDriver { items } => {
                    items.iter().map(|i| i.name.as_str()).collect()
                }
                Step::ElevatedBatch { items, .. } => items.iter().map(|i| i.name.as_str()).collect(),
                _ => Vec::new(),
            })
            .collect();
        assert_eq!(copied, ["OBS"], "o .reg e a tarefa não viram cópia para a pasta de origem");
        assert!(plan.rejected.is_empty());
    }
    // RestoreCoordinatorTests.CancelCopyAndRestartWithConfigurationsOnly
    #[test]
    fn cancel_copy_and_restart_with_configurations_only() {
        let fs = MemFs::new();
        let manifest = r#"{"itens":[{"tipo":"arquivo","nome":"Preferências","destino":"config/a.txt","origem":"C:/Users/Old/a.txt"}]}"#;
        fs.add_file(&format!(r"{KIT}\config\a.txt"), "novo");
        let destination = format!(r"{NEW}\a.txt");
        fs.add_file(&destination, "anterior");
        let runner = Runner::ok();
        let options = RestoreOptions { install_applications: false, ..RestoreOptions::default() };
        let cancel = CancelToken::new();
        let result = run(&fs, manifest, &options, &runner, &cancel, &mut |_| cancel.cancel());
        assert_eq!(result, Err(Cancelled));
        assert_eq!(fs.content(&destination).as_deref(), Some("anterior"));
        assert!(fs.all_files().iter().all(|f| !f.ends_with(".tmp")), "{:?}", fs.all_files());
        let retry = run(&fs, manifest, &options, &runner, &CancelToken::new(), &mut |_| {}).unwrap();
        assert!(retry.failures.is_empty(), "{:?}", retry.failures);
        assert_eq!(fs.content(&destination).as_deref(), Some("novo"));
        assert!(runner.calls.borrow().is_empty());
    }

    // RestoreCoordinatorTests.InstallsListedAppsAndRestoresProfileConfig
    #[test]
    fn installs_listed_apps_and_restores_profile_config() {
        let fs = MemFs::new();
        let manifest = r#"{ "data": "2026-11-21", "itens": [
          { "tipo": "arquivo", "nome": "OBS config", "destino": "config/obs/settings.json", "origem": "C:/Users/Old/AppData/Roaming/obs/settings.json" } ] }"#;
        fs.add_file(&format!(r"{KIT}\config\obs\settings.json"), "profile-data");
        fs.add_file(&format!(r"{KIT}\winget.txt"), "Git.Git\r\nDiscord.Discord\r\n");
        let runner = Runner::ok();
        let result =
            run(&fs, manifest, &RestoreOptions::default(), &runner, &CancelToken::new(), &mut |_| {})
                .unwrap();
        assert_eq!(result.apps_succeeded, 2);
        assert_eq!(result.configurations_succeeded, 1);
        assert!(result.failures.is_empty(), "{:?}", result.failures);
        assert_eq!(
            fs.content(&format!(r"{NEW}\AppData\Roaming\obs\settings.json")).as_deref(),
            Some("profile-data")
        );
        assert!(runner.calls.borrow().iter().all(|(exe, _)| exe == "winget.exe"));
    }

    // RestoreCoordinatorTests.FolderCopyOverwritesReadOnlyAndSkipsOnlyTheLockedFile
    #[test]
    fn folder_copy_overwrites_read_only_and_skips_only_the_locked_file() {
        let fs = MemFs::new();
        let manifest = r#"{"itens":[{"tipo":"pasta","nome":"G HUB","destino":"config/lghub","origem":"C:/Users/Old/lghub"}]}"#;
        for (file, content) in [("a.json", "novo-a"), ("b.db", "novo-b"), ("c.json", "novo-c")] {
            fs.add_file(&format!(r"{KIT}\config\lghub\{file}"), content);
        }
        let dir = format!(r"{NEW}\lghub");
        fs.add_file(&format!(r"{dir}\a.json"), "velho");
        fs.set_readonly(&format!(r"{dir}\a.json"), true);
        fs.add_file(&format!(r"{dir}\b.db"), "preso");
        fs.set_locked(&format!(r"{dir}\b.db"));
        let options = RestoreOptions {
            install_applications: false,
            elevate_protected: false,
            ..RestoreOptions::default()
        };
        let result = run(&fs, manifest, &options, &Runner::ok(), &CancelToken::new(), &mut |_| {}).unwrap();
        assert_eq!(fs.content(&format!(r"{dir}\a.json")).as_deref(), Some("novo-a"));
        assert_eq!(fs.content(&format!(r"{dir}\c.json")).as_deref(), Some("novo-c"));
        assert_eq!(fs.content(&format!(r"{dir}\b.db")).as_deref(), Some("preso"));
        assert_eq!(result.failures.len(), 1);
        assert!(result.failures[0].contains("b.db"), "{}", result.failures[0]);
    }

    #[test]
    fn a_locked_file_goes_to_the_elevated_batch_when_elevation_is_allowed() {
        let fs = MemFs::new();
        let manifest = r#"{"itens":[{"tipo":"pasta","nome":"G HUB","destino":"config/lghub","origem":"C:/Users/Old/lghub"}]}"#;
        fs.add_file(&format!(r"{KIT}\config\lghub\b.db"), "novo");
        fs.add_file(&format!(r"{NEW}\lghub\b.db"), "preso");
        fs.set_locked(&format!(r"{NEW}\lghub\b.db"));
        let options = RestoreOptions { install_applications: false, ..RestoreOptions::default() };
        let result = run(&fs, manifest, &options, &Runner::ok(), &CancelToken::new(), &mut |_| {}).unwrap();
        assert!(result.failures.is_empty());
        assert_eq!(result.configurations_succeeded, 0);
        assert_eq!(result.elevated_pending.len(), 1);
        assert_eq!(result.elevated_pending[0].name, "G HUB");
    }

    // RestoreCoordinatorTests.ProgramFilesNeedsElevationOnlyWhenNotAdmin
    #[test]
    fn program_files_needs_elevation_only_when_not_admin() {
        let roots = default_protected_roots("C");
        assert!(!needs_elevation(r"C:\Users\x\AppData\a.txt", &roots, false));
        let pf = r"C:\Program Files\EqualizerAPO\config";
        assert!(needs_elevation(pf, &roots, false));
        assert!(!needs_elevation(pf, &roots, true));
        assert!(needs_elevation(r"C:\ProgramData\NVIDIA Corporation\Drs", &roots, false));
        assert!(needs_elevation(r"c:\program files (x86)\Steam\x", &roots, false));
        assert!(!needs_elevation(r"C:\Program Filesx\a", &roots, false));
    }

    // RestoreCoordinatorTests.ContinuesAfterOneAppFailsAndReportsItsExitCode
    #[test]
    fn continues_after_one_app_fails_and_reports_its_exit_code() {
        let fs = MemFs::new();
        fs.add_file(&format!(r"{KIT}\winget.txt"), "Bad.Package\r\nGood.Package\r\n");
        let mut runner = Runner::ok();
        runner.code = Box::new(|args| if args.contains(&"Bad.Package".to_owned()) { 5 } else { 0 });
        let options = RestoreOptions { restore_configurations: false, ..RestoreOptions::default() };
        let result =
            run(&fs, r#"{ "itens": [] }"#, &options, &runner, &CancelToken::new(), &mut |_| {}).unwrap();
        assert_eq!(result.apps_succeeded, 1);
        assert_eq!(result.failures.len(), 1);
        assert!(
            result.failures[0].contains("Bad.Package") && result.failures[0].contains('5'),
            "{}",
            result.failures[0]
        );
    }

    #[test]
    fn a_missing_winget_list_is_a_failure_and_a_missing_source_item_too() {
        let fs = MemFs::new();
        let manifest =
            r#"{"itens":[{"tipo":"arquivo","nome":"X","destino":"config/x","origem":"C:/Users/Old/x"}]}"#;
        let result =
            run(&fs, manifest, &RestoreOptions::default(), &Runner::ok(), &CancelToken::new(), &mut |_| {})
                .unwrap();
        assert_eq!(result.failures.len(), 2);
        assert!(
            result.failures[0].contains("winget.txt") && result.failures[1].contains("não está no pacote")
        );
    }

    #[test]
    fn links_inside_the_kit_are_not_copied() {
        let fs = MemFs::new();
        fs.add_file(&format!(r"{KIT}\config\a\ok.txt"), "x");
        fs.add_link_dir(&format!(r"{KIT}\config\a\junction"));
        let manifest =
            r#"{"itens":[{"tipo":"pasta","nome":"A","destino":"config/a","origem":"C:/Users/Old/a"}]}"#;
        let options = RestoreOptions { install_applications: false, ..RestoreOptions::default() };
        let result = run(&fs, manifest, &options, &Runner::ok(), &CancelToken::new(), &mut |_| {}).unwrap();
        assert!(result.failures[0].contains("links"), "{:?}", result.failures);
    }

    fn manifest_of(items: &[(&str, &str, &str, &str)]) -> Manifest {
        let list: Vec<String> = items
            .iter()
            .map(|(kind, name, kit, origin)| {
                format!(
                    r#"{{"tipo":"{kind}","nome":"{name}","destino":"{}","origem":"{}"}}"#,
                    kit.replace('\\', "\\\\"),
                    origin.replace('\\', "\\\\")
                )
            })
            .collect();
        parse(&format!(r#"{{"itens":[{}]}}"#, list.join(","))).unwrap()
    }

    fn real_shape() -> Manifest {
        manifest_of(&[
            ("pasta", "OBS", r"config\obs-studio", r"C:\Users\Old\AppData\Roaming\obs-studio"),
            (
                "pasta",
                "Equalizer APO config",
                r"config\equalizerapo\config",
                r"C:\Program Files\EqualizerAPO\config",
            ),
            ("pasta", "ISLC", r"config\islc", r"C:\Program Files\ISLC"),
            ("pasta", "G HUB (local)", r"config\lghub\local", r"C:\Users\Old\AppData\Local\LGHUB"),
            ("pasta", "NVIDIA perfis (Drs)", r"config\nvidia\Drs", r"C:\ProgramData\NVIDIA Corporation\Drs"),
            (
                "pasta",
                "Windows Terminal",
                r"config\terminal",
                r"C:\Users\Old\AppData\Local\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState",
            ),
            ("arquivo", "LMUFFB", r"avulsos\LMUFFB\LMUFFB.exe", r"C:\AutoOptimizer\LMUFFB.exe"),
        ])
    }

    #[test]
    fn protected_destinations_go_in_one_elevated_batch_and_the_rest_stays_with_the_user() {
        let plan = plan_restore(&real_shape(), &ctx(false), &RestoreOptions::default());
        assert_eq!(plan.elevated_batches(), 1, "um só pedido de administrador: {:?}", plan.steps);
        let Some(Step::ElevatedBatch { items, .. }) =
            plan.steps.iter().find(|s| matches!(s, Step::ElevatedBatch { .. }))
        else {
            panic!()
        };
        let names: Vec<_> = items.iter().map(|i| i.name.as_str()).collect();
        assert_eq!(names, ["Equalizer APO config", "ISLC", "NVIDIA perfis (Drs)"]);
        assert!(items.iter().all(|i| i.protected));
        let Some(Step::CopyConfigs { items }) =
            plan.steps.iter().find(|s| matches!(s, Step::CopyConfigs { .. }))
        else {
            panic!()
        };
        assert!(items.iter().all(|i| !i.protected && !i.after_nvidia_driver));
        assert_eq!(items.len(), 4);
        assert_eq!(items[0].destination, r"C:\Users\New\AppData\Roaming\obs-studio", "perfil remapeado");
        assert_eq!(items[0].source, r"K:\MeuPlaybook\pacote\config\obs-studio");
    }

    #[test]
    fn an_elevated_process_needs_no_separate_batch() {
        let plan = plan_restore(&real_shape(), &ctx(true), &RestoreOptions::default());
        assert_eq!(plan.elevated_batches(), 0);
        assert!(plan.steps.iter().all(|s| !matches!(s, Step::ElevatedBatch { .. })));
        let flat: Vec<_> = plan
            .steps
            .iter()
            .filter(|s| matches!(s, Step::CopyConfigs { .. } | Step::CopyAfterDriver { .. }))
            .collect();
        assert_eq!(flat.len(), 2, "cópias normais e pós-driver");
    }

    #[test]
    fn refusing_elevation_keeps_protected_items_in_the_normal_flow() {
        let options = RestoreOptions { elevate_protected: false, ..RestoreOptions::default() };
        assert_eq!(plan_restore(&real_shape(), &ctx(false), &options).elevated_batches(), 0);
    }

    #[test]
    fn nvidia_comes_after_the_driver_and_never_before() {
        let options = RestoreOptions { install_nvidia_driver: true, ..RestoreOptions::default() };
        let plan = plan_restore(&real_shape(), &ctx(false), &options);
        let driver = plan.position(|s| matches!(s, Step::InstallNvidiaDriver)).expect("driver no plano");
        let batch = plan.position(|s| matches!(s, Step::ElevatedBatch { .. })).unwrap();
        let normal = plan.position(|s| matches!(s, Step::CopyConfigs { .. })).unwrap();
        assert!(
            normal < driver && driver < batch,
            "{:?}",
            plan.steps
                .iter()
                .map(|s| format!("{s:?}").chars().take(18).collect::<String>())
                .collect::<Vec<_>>()
        );
        for step in &plan.steps {
            if let Step::CopyConfigs { items } = step {
                assert!(items.iter().all(|i| !i.name.to_lowercase().contains("nvidia")));
            }
        }
        let user_flow = plan_restore(&real_shape(), &ctx(true), &options);
        let driver = user_flow.position(|s| matches!(s, Step::InstallNvidiaDriver)).unwrap();
        let after = user_flow.position(|s| matches!(s, Step::CopyAfterDriver { .. })).unwrap();
        assert!(driver < after);
    }

    #[test]
    fn apps_are_installed_before_anything_is_copied_and_owners_are_closed_before_copying() {
        let plan = plan_restore(&real_shape(), &ctx(false), &RestoreOptions::default());
        assert_eq!(plan.steps[0], Step::InstallPrograms);
        let Step::CloseApps { processes } = &plan.steps[1] else { panic!("{:?}", plan.steps[1]) };
        assert!(processes.contains(&"obs64".to_owned()) && processes.contains(&"lghub".to_owned()));
        assert!(
            plan.position(|s| matches!(s, Step::CloseApps { .. })).unwrap()
                < plan.position(|s| matches!(s, Step::CopyConfigs { .. })).unwrap()
        );
        let only_configs = RestoreOptions { install_applications: false, ..RestoreOptions::default() };
        assert!(
            !plan_restore(&real_shape(), &ctx(false), &only_configs).steps.contains(&Step::InstallPrograms)
        );
        let only_apps = RestoreOptions { restore_configurations: false, ..RestoreOptions::default() };
        assert_eq!(plan_restore(&real_shape(), &ctx(false), &only_apps).steps, [Step::InstallPrograms]);
    }

    #[test]
    fn items_that_escape_the_kit_are_rejected_not_planned() {
        let m = manifest_of(&[
            ("pasta", "Fora", r"..\x", r"C:\Users\Old\x"),
            ("pasta", "Dentro", "config/y", r"C:\Users\Old\y"),
        ]);
        let plan = plan_restore(
            &m,
            &ctx(false),
            &RestoreOptions { install_applications: false, ..RestoreOptions::default() },
        );
        assert_eq!(plan.rejected.len(), 1);
        assert_eq!(plan.rejected[0].0, "Fora");
        let fs = MemFs::new();
        let runner = Runner::ok();
        let result = run_restore(
            &m,
            &ctx(false),
            &RestoreOptions { install_applications: false, ..RestoreOptions::default() },
            &RestoreDeps { fs: &fs, writer: &fs, runner: &runner },
            &CancelToken::new(),
            &mut |_| {},
        )
        .unwrap();
        assert!(result.failures[0].contains("Fora"));
    }

    #[test]
    fn the_elevated_step_lists_the_protected_items_as_data_and_the_ghub_owners_are_known() {
        let plan = plan_restore(&real_shape(), &ctx(false), &RestoreOptions::default());
        let Some(Step::ElevatedBatch { items, .. }) =
            plan.steps.iter().find(|s| matches!(s, Step::ElevatedBatch { .. }))
        else {
            panic!()
        };
        assert_eq!(items.len(), 3);
        assert!(
            items.iter().any(|i| i.source == r"K:\MeuPlaybook\pacote\config\islc"
                && i.destination == r"C:\Program Files\ISLC")
        );
        // o lado elevado recebe este plano como DADOS (vanta-sys); nada aqui monta script
        assert!(SERVICES_TO_STOP.contains(&"LGHUBUpdaterService") && CONFIG_OWNERS.contains(&"lghub"));
    }
    #[test]
    fn the_equalizer_apo_item_carries_a_fifine_remap_that_follows_elevation() {
        let plan = plan_restore(&real_shape(), &ctx(false), &RestoreOptions::default());
        let Some(Step::ElevatedBatch { remaps, .. }) =
            plan.steps.iter().find(|s| matches!(s, Step::ElevatedBatch { .. }))
        else {
            panic!()
        };
        assert_eq!(
            remaps,
            &[MicRemap {
                config_path: r"C:\Program Files\EqualizerAPO\config\config.txt".into(),
                device_name: "fifine".into(),
                needs_elevation: true
            }]
        );
        let admin = plan_restore(&real_shape(), &ctx(true), &RestoreOptions::default());
        let step = admin
            .steps
            .iter()
            .find_map(|s| if let Step::RemapMicrophone { remaps } = s { Some(remaps) } else { None })
            .unwrap();
        assert!(!step[0].needs_elevation);
        assert!(
            admin.position(|s| matches!(s, Step::RemapMicrophone { .. })).unwrap()
                > admin.position(|s| matches!(s, Step::CopyConfigs { .. })).unwrap()
        );
    }

    const EAPO: &str = "Preamp: -3 dB\r\nDevice: fifine Microphone {0.0.1.00000000}.{aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee}\r\nInclude: peace.txt\r\nDevice: Speakers {11111111-2222-3333-4444-555555555555}\r\n";

    #[test]
    fn the_microphone_is_found_by_name_among_capture_endpoints_only() {
        let endpoints = [
            AudioEndpoint {
                friendly_name: "Speakers (fifine)".into(),
                instance_id: r"SWD\MMDEVAPI\{0.0.0.00000000}.{00000000-0000-0000-0000-000000000001}".into(),
            },
            AudioEndpoint {
                friendly_name: "Microphone (FIFINE K669)".into(),
                instance_id: r"SWD\MMDEVAPI\{0.0.1.00000000}.{3D6F1C2A-0000-4000-8000-0123456789AB}".into(),
            },
        ];
        assert_eq!(
            find_microphone_guid(&endpoints, "fifine").as_deref(),
            Some("3d6f1c2a-0000-4000-8000-0123456789ab")
        );
        assert_eq!(find_microphone_guid(&endpoints, "rode"), None);
        assert_eq!(find_microphone_guid(&endpoints[..1], "fifine"), None);
    }

    #[test]
    fn only_the_fifine_line_changes_and_the_rest_of_the_config_is_untouched() {
        let new = remap_microphone(EAPO, "fifine", "3d6f1c2a-0000-4000-8000-0123456789ab").unwrap();
        assert!(
            new.contains(
                "Device: fifine Microphone {0.0.1.00000000}.{3d6f1c2a-0000-4000-8000-0123456789ab}\r\n"
            ),
            "{new}"
        );
        assert!(new.contains("Preamp: -3 dB\r\n") && new.contains("Include: peace.txt\r\n"));
        assert!(new.contains("Device: Speakers {11111111-2222-3333-4444-555555555555}"));
        assert_eq!(
            remap_microphone("Preamp: 0 dB\r\n", "fifine", "3d6f1c2a-0000-4000-8000-0123456789ab"),
            None
        );
        assert_eq!(remap_microphone(EAPO, "rode", "3d6f1c2a-0000-4000-8000-0123456789ab"), None);
    }

    #[test]
    fn a_missing_microphone_is_a_warning_not_a_failure() {
        let fs = MemFs::new();
        fs.add_file(r"C:\Program Files\EqualizerAPO\config\config.txt", EAPO);
        let remap = MicRemap {
            config_path: r"C:\Program Files\EqualizerAPO\config\config.txt".into(),
            device_name: "fifine".into(),
            needs_elevation: false,
        };
        assert_eq!(apply_microphone_remap(&remap, &[], &fs, &fs), MicOutcome::DeviceNotFound);
    }

    #[test]
    fn the_remap_rewrites_the_config_file_with_the_new_guid() {
        let fs = MemFs::new();
        let path = r"C:\Program Files\EqualizerAPO\config\config.txt";
        fs.add_file(path, EAPO);
        let remap =
            MicRemap { config_path: path.into(), device_name: "fifine".into(), needs_elevation: false };
        let endpoints = [AudioEndpoint {
            friendly_name: "Microphone (fifine)".into(),
            instance_id: r"SWD\MMDEVAPI\{0.0.1.00000000}.{3d6f1c2a-0000-4000-8000-0123456789ab}".into(),
        }];
        assert_eq!(apply_microphone_remap(&remap, &endpoints, &fs, &fs), MicOutcome::Remapped);
        assert!(fs.content(path).unwrap().contains("{3d6f1c2a-0000-4000-8000-0123456789ab}"));
        fs.set_locked(path);
        assert!(matches!(apply_microphone_remap(&remap, &endpoints, &fs, &fs), MicOutcome::Failed(_)));
        let without = MemFs::new();
        without.add_file(path, "Preamp: 0 dB\r\n");
        assert_eq!(apply_microphone_remap(&remap, &endpoints, &without, &without), MicOutcome::NoDeviceLine);
    }

    #[test]
    fn config_owners_are_closed_by_item_name_and_destination() {
        assert_eq!(
            owners_for("G HUB (local)", r"C:\Users\New\AppData\Local\LGHUB"),
            ["lghub", "lghub_agent", "lghub_system_tray", "lghub_updater"]
        );
        assert_eq!(owners_for("Vencord", r"C:\Users\New\AppData\Roaming\Vencord"), ["Discord"]);
        assert_eq!(owners_for("OBS", r"C:\Users\New\AppData\Roaming\obs-studio"), ["obs64"]);
        assert_eq!(owners_for("VLC", r"C:\Users\New\AppData\Roaming\vlc"), ["vlc"]);
        assert!(owners_for("Windows Terminal", r"C:\Users\New\x").is_empty());
        assert!(CONFIG_OWNERS.contains(&"lghub_updater"));
    }

    #[test]
    fn default_protected_roots_cover_program_files_windows_and_programdata() {
        assert_eq!(
            default_protected_roots("c:"),
            [r"c:\Program Files", r"c:\Program Files (x86)", r"c:\Windows", r"c:\ProgramData", r"c:\Vanta"]
        );
    }
}
