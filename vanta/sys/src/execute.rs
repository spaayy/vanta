//! Executa o plano de restauração do `vanta-core` com as implementações reais, passo a passo, com progresso,
//! cancelamento e log. Um único pedido de administrador por execução (o lote elevado).

use std::os::windows::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::Arc;

use vanta_core::catalog::SoftwareApp;
use vanta_core::extras::{ExtraKind, approved};
use vanta_core::fs::StdFs;
use vanta_core::install::{
    CancelToken, Cancelled, InstallState, Progress, install_apps_batch, parse_winget_list,
};
use vanta_core::manifest::Manifest;
use vanta_core::path::{file_name, join, parent, resolve_inside_root};
use vanta_core::restore::{
    CONFIG_OWNERS, MicOutcome, PlannedItem, RestoreContext, RestoreOptions, SERVICES_TO_STOP, Step,
    apply_microphone_remap, copy_configs, find_microphone_guid, plan_restore, remap_microphone,
};

use crate::batch::ElevatedInstaller;
use crate::mic::list_endpoints;
use crate::restore_batch::{current_sid, declined, fix_task_xml, map_profile_reg, old_profile_from_origins};
use crate::restore_plan::{
    PlanItem, PlanReg, PlanScript, PlanTask, PlanText, RestorePlan, TaskRoots, hash_source, path_inside,
    read_text, validate_reg, validate_task,
};
use crate::restore_worker::{Kind, Status, WorkerReport, run_plan};
use crate::startup::startup_plan;
use crate::writer::StdWriter;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum NvidiaChoice {
    /// Não instala driver: o perfil NVIDIA ainda é copiado.
    #[default]
    Skip,
    /// Abre o NVCleanstall (o usuário escolhe o driver) e espera ele fechar.
    NvCleanstall,
}

pub struct Hooks<'a> {
    pub progress: &'a mut dyn FnMut(&Progress),
    pub log: &'a mut dyn FnMut(&str),
}

impl Hooks<'_> {
    fn say(&mut self, phase: &str, item: &str, message: &str) {
        (self.log)(&format!("[{phase}] {message}"));
        (self.progress)(&Progress {
            phase: phase.into(),
            item: item.into(),
            completed: 0,
            total: 0,
            message: message.into(),
        });
    }
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct RestoreSummary {
    pub apps_succeeded: usize,
    pub apps_failed: usize,
    pub configurations_succeeded: usize,
    pub extras_succeeded: usize,
    pub failures: Vec<String>,
    pub warnings: Vec<String>,
    pub cancelled: bool,
}

fn kill_processes(names: &[String]) {
    for name in names {
        let _ = Command::new("taskkill")
            .args(["/f", "/im", &format!("{name}.exe")])
            .creation_flags(0x0800_0000)
            .output();
    }
}

/// `NVCleanstall.exe` nas pastas usuais.
pub fn find_nvcleanstall() -> Option<PathBuf> {
    ["ProgramFiles", "ProgramFiles(x86)", "LOCALAPPDATA"]
        .iter()
        .filter_map(|v| std::env::var_os(v).map(PathBuf::from))
        .flat_map(|base| {
            [
                base.join("NVCleanstall\\NVCleanstall.exe"),
                base.join("Programs\\NVCleanstall\\NVCleanstall.exe"),
            ]
        })
        .find(|p| p.is_file())
}

fn apps_from_list(ids: &[String], catalog: &[SoftwareApp]) -> Vec<SoftwareApp> {
    ids.iter()
        .map(|id| {
            catalog
                .iter()
                .find(|a| a.winget_id.as_deref().is_some_and(|w| w.eq_ignore_ascii_case(id)))
                .cloned()
                .unwrap_or_else(|| SoftwareApp {
                    name: id.clone(),
                    winget_id: Some(id.clone()),
                    source: Some("winget".into()),
                    reference: None,
                    default: true,
                    interactive: false,
                    note: None,
                    extra: None,
                    category: "Restaurar".into(),
                })
        })
        .collect()
}

/// O `config.txt` do Equalizer APO já com o GUID novo do microfone, em memória (vai no plano como dados).
fn patched_mic_text(
    items: &[PlannedItem],
    config_path: &str,
    device: &str,
    hooks: &mut Hooks,
) -> Option<PlanText> {
    let folder = parent(config_path)?;
    let source = items.iter().find(|i| i.destination.eq_ignore_ascii_case(&folder))?;
    let guid = find_microphone_guid(&list_endpoints(), device);
    let Some(guid) = guid else {
        hooks.say("Áudio", device, &format!("AVISO: microfone '{device}' não conectado; conecte e rode o Restaurar de novo só com configurações."));
        return None;
    };
    let text = std::fs::read_to_string(join(&source.source, &file_name(config_path))).ok()?;
    let updated = remap_microphone(&text, device, &guid)?;
    hooks.say("Áudio", device, &format!("microfone '{device}' agora é {guid}"));
    Some(PlanText {
        name: "Microfone (Equalizer APO)".into(),
        destination: config_path.to_owned(),
        content: updated.into_bytes(),
    })
}
#[allow(clippy::too_many_arguments)]
pub fn execute_restore(
    manifest: &Manifest,
    ctx: &RestoreContext,
    options: &RestoreOptions,
    nvidia: NvidiaChoice,
    catalog: &[SoftwareApp],
    cancel: &CancelToken,
    hooks: &mut Hooks,
) -> RestoreSummary {
    let mut summary = RestoreSummary::default();
    let plan = plan_restore(manifest, ctx, options);
    summary.failures.extend(plan.rejected.iter().map(|(name, error)| format!("{name}: {error}")));
    let mut pending: Vec<PlannedItem> = Vec::new();
    let mut mic_remaps = Vec::new();
    let mut elevated_items: Vec<PlannedItem> = Vec::new();
    let mut restored_roots: Vec<String> = Vec::new();
    let mut canonical: Vec<String> = Vec::new();

    let result: Result<(), Cancelled> = (|| {
        for step in &plan.steps {
            if cancel.is_cancelled() {
                return Err(Cancelled);
            }
            match step {
                Step::InstallPrograms => {
                    let list = std::fs::read_to_string(join(&ctx.kit_root, "winget.txt")).unwrap_or_default();
                    let ids = parse_winget_list(&list);
                    if ids.is_empty() {
                        summary
                            .warnings
                            .push("winget.txt vazio ou ausente: nenhum programa para instalar.".into());
                        continue;
                    }
                    hooks.say(
                        "Programas",
                        "",
                        &format!(
                            "Instalando {} programa(s) em um lote (1 pedido de administrador)",
                            ids.len()
                        ),
                    );
                    let (tx, rx) = std::sync::mpsc::channel::<Progress>();
                    let installer = ElevatedInstaller {
                        progress: Arc::new(move |p| {
                            let _ = tx.send(p);
                        }),
                        cancel: cancel.clone(),
                    };
                    let apps = apps_from_list(&ids, catalog);
                    let results = std::thread::scope(|scope| {
                        let worker = scope.spawn(|| install_apps_batch(&apps, &installer));
                        while !worker.is_finished() {
                            while let Ok(p) = rx.try_recv() {
                                (hooks.log)(&format!("[Programas] {}", p.message));
                                (hooks.progress)(&p);
                            }
                            std::thread::sleep(std::time::Duration::from_millis(200));
                        }
                        while let Ok(p) = rx.try_recv() {
                            (hooks.log)(&format!("[Programas] {}", p.message));
                            (hooks.progress)(&p);
                        }
                        worker.join().unwrap_or_default()
                    });
                    for r in &results {
                        if r.state == InstallState::Succeeded {
                            summary.apps_succeeded += 1;
                        } else {
                            summary.apps_failed += 1;
                            summary.failures.push(format!("{}: {}", r.app.name, r.message));
                        }
                    }
                }
                Step::CloseApps { processes } => {
                    hooks.say(
                        "Configurações",
                        "",
                        &format!("Fechando {} app(s) que prendem configurações", processes.len()),
                    );
                    kill_processes(processes);
                }
                Step::CopyConfigs { items } | Step::CopyAfterDriver { items } => {
                    restored_roots
                        .extend(items.iter().filter(|i| i.is_folder).map(|i| i.destination.clone()));
                    canonical.extend(items.iter().map(|i| i.destination.clone()));
                    let mut sink = |p: &Progress| (hooks.progress)(p);
                    let outcome = copy_configs(items, options, ctx, &StdFs, &StdWriter, cancel, &mut sink)?;
                    summary.configurations_succeeded += outcome.succeeded;
                    for failure in &outcome.failures {
                        (hooks.log)(&format!("FALHA {failure}"));
                    }
                    for item in items.iter().filter(|i| i.name.starts_with("NathaSystem") && i.is_folder) {
                        // só o que esta execução provadamente restaurou (igual ao do kit), nunca o que já estava lá
                        let restored = crate::startup::restored_nathasystem(
                            Path::new(&item.source),
                            Path::new(&item.destination),
                            &outcome.copied,
                        );
                        match crate::startup::migrate_nathasystem(Path::new(&item.destination), &restored) {
                            Ok(done) if !done.is_empty() => hooks.say(
                                "Configurações",
                                &item.name,
                                &format!("NathaSystem -> VantaSystem: {}", done.join(", ")),
                            ),
                            Ok(_) => {}
                            Err(error) => summary.failures.push(format!(
                                "{}: renomear NathaSystem -> VantaSystem falhou: {error}",
                                item.name
                            )),
                        }
                    }
                    summary.failures.extend(outcome.failures);
                    pending.extend(outcome.deferred);
                }
                Step::InstallNvidiaDriver => {
                    match (nvidia, find_nvcleanstall()) {
                        (NvidiaChoice::Skip, _) => {
                            hooks.say("Driver", "NVIDIA", "Driver NVIDIA: pulado (escolha do usuário).")
                        }
                        (NvidiaChoice::NvCleanstall, None) => summary.warnings.push(
                            "NVCleanstall não está instalado: instale o programa e rode o Restaurar de novo."
                                .into(),
                        ),
                        (NvidiaChoice::NvCleanstall, Some(exe)) => {
                            hooks.say("Driver", "NVIDIA", "No NVCleanstall escolha o driver e instale; feche o programa para continuar.");
                            if let Ok(mut child) = Command::new(exe).spawn() {
                                let _ = child.wait();
                            }
                        }
                    }
                }
                Step::ElevatedBatch { items, remaps } => {
                    restored_roots
                        .extend(items.iter().filter(|i| i.is_folder).map(|i| i.destination.clone()));
                    canonical.extend(items.iter().map(|i| i.destination.clone()));
                    elevated_items.extend(items.iter().cloned());
                    mic_remaps.extend(remaps.iter().cloned());
                }
                Step::RemapMicrophone { remaps } => {
                    for remap in remaps {
                        match apply_microphone_remap(remap, &list_endpoints(), &StdFs, &StdWriter) {
                            MicOutcome::Remapped => hooks.say(
                                "Áudio",
                                &remap.device_name,
                                "Microfone remapeado no Equalizer APO.",
                            ),
                            MicOutcome::DeviceNotFound => summary.warnings.push(format!(
                                "Microfone '{}' não conectado; remapeamento não aplicado.",
                                remap.device_name
                            )),
                            MicOutcome::NoDeviceLine => hooks.say(
                                "Áudio",
                                &remap.device_name,
                                "config.txt sem linha do microfone: nada a trocar.",
                            ),
                            MicOutcome::Failed(error) => summary.failures.push(format!("Microfone: {error}")),
                        }
                    }
                }
            }
        }
        Ok(())
    })();
    if result.is_err() {
        summary.cancelled = true;
        return summary;
    }

    // O lote elevado: pastas protegidas + arquivos presos + microfone + registro + tarefas + início com o Windows, tudo
    // num pedido só. O lado elevado recebe um PLANO (dados conferidos por hash), nunca um script do usuário.
    elevated_items.extend(pending);
    let mut plan = RestorePlan {
        services: SERVICES_TO_STOP.iter().map(|s| (*s).to_owned()).collect(),
        processes: CONFIG_OWNERS.iter().map(|s| (*s).to_owned()).collect(),
        restored_roots,
        allowed_destinations: canonical,
        ..RestorePlan::default()
    };
    // cada arquivo de origem entra no plano com o SHA-256 de agora; o lado elevado só copia o que ainda bate
    for item in &elevated_items {
        match hash_source(Path::new(&item.source), item.is_folder) {
            Ok(files) => plan.items.push(PlanItem {
                name: item.name.clone(),
                source: item.source.clone(),
                destination: item.destination.clone(),
                is_folder: item.is_folder,
                files,
            }),
            Err(error) => {
                summary
                    .failures
                    .push(format!("{}: não foi possível conferir a origem ({error}).", item.name));
            }
        }
    }
    plan.protected_dirs = protected_dirs(&plan.items);
    for remap in &mic_remaps {
        if let Some(text) = patched_mic_text(&elevated_items, &remap.config_path, &remap.device_name, hooks) {
            plan.texts.push(text);
        }
    }
    if options.restore_configurations && options.elevate_protected {
        add_extras(manifest, ctx, &mut plan, &mut summary);
    }
    if !plan.is_empty() {
        hooks.say("Configurações", "", "Pastas do sistema, registro e tarefas (1 pedido de administrador)");
        match run_plan(&plan, cancel) {
            Ok(report) => apply_report(&plan, &report, &mut summary, hooks),
            // recusa do UAC: TUDO o que dependia do lado elevado fica como falha, não só as cópias de pasta
            Err(error) if declined(&error) => summary.failures.extend(
                plan_labels(&plan)
                    .into_iter()
                    .map(|label| format!("{label}: precisa de administrador e o pedido foi recusado.")),
            ),
            Err(error) => summary.failures.push(format!("Lote elevado: {error}")),
        }
    }
    summary
}

/// O nome de cada parte do plano elevado (cópias, textos, registro, tarefas e entradas de início).
fn plan_labels(plan: &RestorePlan) -> Vec<String> {
    plan.items
        .iter()
        .map(|i| i.name.clone())
        .chain(plan.texts.iter().map(|t| t.name.clone()))
        .chain(plan.registry.iter().map(|r| r.label.clone()))
        .chain(plan.tasks.iter().map(|t| t.label.clone()))
        .chain(plan.runs.iter().map(|r| r.label.clone()))
        .collect()
}

/// As pastas só de administradores que os itens pedem (`C:\Vanta\<pasta>`), sem repetir.
pub fn protected_dirs(items: &[PlanItem]) -> Vec<String> {
    let mut dirs: Vec<String> = Vec::new();
    for item in items {
        let mut parts = item.destination.split('\\');
        if let (Some(drive), Some(vanta), Some(folder)) = (parts.next(), parts.next(), parts.next())
            && drive.len() == 2
            && vanta.eq_ignore_ascii_case("Vanta")
            && !folder.is_empty()
        {
            let dir = format!(r"{drive}\{vanta}\{folder}");
            if !dirs.iter().any(|known| known.eq_ignore_ascii_case(&dir)) {
                dirs.push(dir);
            }
        }
    }
    dirs
}

/// O SHA-256 que o plano tem para o arquivo `script` (de um item de pasta ou de arquivo único que o copia).
fn script_hash(items: &[PlanItem], script: &str) -> Option<String> {
    items.iter().find_map(|item| {
        if item.is_folder {
            let rest = script.get(item.destination.len()..)?.strip_prefix('\\')?;
            path_inside(script, &item.destination).then(|| {
                item.files.iter().find(|f| f.rel.eq_ignore_ascii_case(rest)).map(|f| f.sha256.clone())
            })?
        } else {
            script
                .eq_ignore_ascii_case(&item.destination)
                .then(|| item.files.first().map(|f| f.sha256.clone()))?
        }
    })
}

/// Importa só os `.reg` e as tarefas que o manifesto conferido lista, e as entradas de início de programas cujo caminho
/// exato o manifesto cobre.
pub fn add_extras(
    manifest: &Manifest,
    ctx: &RestoreContext,
    plan: &mut RestorePlan,
    summary: &mut RestoreSummary,
) {
    let origins: Vec<String> = manifest.items.iter().map(|i| i.restore_path.clone()).collect();
    let (Some(old), Some(sid)) = (old_profile_from_origins(&origins), current_sid()) else { return };
    let env = |name: &str| std::env::var(name).ok();
    let program_files = std::env::var("ProgramFiles").unwrap_or_else(|_| r"C:\Program Files".into());
    let program_files_x86 =
        std::env::var("ProgramFiles(x86)").unwrap_or_else(|_| r"C:\Program Files (x86)".into());
    let local = std::env::var("LOCALAPPDATA").unwrap_or_default();
    // o diretório de sistema vem da API do Windows (como o lançador), nunca de uma variável de ambiente
    let system_directory = crate::elevate::system_directory().unwrap_or_default();
    let roots = TaskRoots {
        program_files: vec![program_files.clone(), program_files_x86],
        privileged: plan.protected_dirs.clone(),
        restored: plan.restored_roots.clone(),
        user_programs: vec![format!(r"{local}\Programs")],
        powershell: format!(r"{system_directory}\WindowsPowerShell\v1.0\powershell.exe"),
        cmd: format!(r"{system_directory}\cmd.exe"),
        user_profile: ctx.current_profile.clone(),
        env: &env,
    };
    let approved_reg = approved(manifest, ExtraKind::Registry);
    let approved_task = approved(manifest, ExtraKind::Task);
    for (kit_path, stem) in &approved_reg {
        let label = format!("registro {stem}");
        match resolve_inside_root(&ctx.kit_root, kit_path)
            .map_err(|e| e.to_string())
            .and_then(|path| read_text(Path::new(&path)).map_err(|e| e.to_string()))
        {
            Ok(text) => {
                let text = map_profile_reg(&text, &old, &ctx.current_profile);
                match validate_reg(&text) {
                    Ok(()) => plan.registry.push(PlanReg { label, text }),
                    Err(why) => summary.failures.push(format!("{label}: recusado ({why})")),
                }
            }
            Err(why) => summary.failures.push(format!("{label}: {why}")),
        }
    }
    for (kit_path, stem) in &approved_task {
        let name = crate::startup::renamed_name(stem);
        let label = format!("tarefa {name}");
        match resolve_inside_root(&ctx.kit_root, kit_path)
            .map_err(|e| e.to_string())
            .and_then(|path| read_text(Path::new(&path)).map_err(|e| e.to_string()))
        {
            Ok(text) => {
                let xml = crate::startup::rename_text(&fix_task_xml(&text, &sid, &old, &ctx.current_profile));
                match validate_task(&xml, &sid, &roots) {
                    Ok((_, scripts)) => {
                        // o script que a tarefa roda tem de ser um dos arquivos que este plano copia, com o hash dele
                        let mut hashed = Vec::new();
                        let mut missing = None;
                        for script in scripts {
                            match script_hash(&plan.items, &script) {
                                Some(sha256) => hashed.push(PlanScript { path: script, sha256 }),
                                None => missing = Some(script),
                            }
                        }
                        match missing {
                            None => plan.tasks.push(PlanTask { label, name, xml, scripts: hashed }),
                            Some(script) => summary.failures.push(format!(
                                "{label}: recusada (o script {script} não é um dos arquivos que o plano copia e confere)"
                            )),
                        }
                    }
                    Err(why) => summary.failures.push(format!("{label}: recusada ({why})")),
                }
            }
            Err(why) => summary.failures.push(format!("{label}: {why}")),
        }
    }
    // arquivos nas pastas de extras do kit que o manifesto NÃO lista: a guarda nunca os olhou, então não são usados
    for (dir, extension, approved) in
        [("config/registro", "reg", &approved_reg), ("estado/tarefas", "xml", &approved_task)]
    {
        for name in unlisted_files(&ctx.kit_root, dir, extension, approved) {
            summary.warnings.push(format!("{dir}/{name}: não está no manifesto do kit; ignorado."));
        }
    }
    let exists = |path: &Path| path.exists();
    let startup = startup_plan(&plan.allowed_destinations, &sid, &local, &program_files, &roots, &exists);
    plan.tasks.extend(startup.tasks);
    plan.runs.extend(startup.runs);
    summary.warnings.extend(startup.warnings);
}

/// Arquivos com `extension` em `kit_root\dir` que o manifesto não aprovou.
fn unlisted_files(kit_root: &str, dir: &str, extension: &str, approved: &[(String, String)]) -> Vec<String> {
    let folder = Path::new(kit_root).join(dir.replace('/', "\\"));
    let mut names: Vec<String> = std::fs::read_dir(folder)
        .into_iter()
        .flatten()
        .flatten()
        .map(|e| e.file_name().to_string_lossy().into_owned())
        .filter(|name| Path::new(name).extension().is_some_and(|e| e.eq_ignore_ascii_case(extension)))
        .filter(|name| {
            let listed = format!("{dir}/{name}");
            !approved.iter().any(|(path, _)| path.eq_ignore_ascii_case(&listed))
        })
        .collect();
    names.sort();
    names
}

/// Conta o que o lado elevado reportou e diz o que ficou de fora e por quê.
fn apply_report(plan: &RestorePlan, report: &WorkerReport, summary: &mut RestoreSummary, hooks: &mut Hooks) {
    let reason = |detail: &str| match detail {
        "" => String::new(),
        other => format!(" ({other})"),
    };
    let not_run = |report: &WorkerReport| {
        report.error.clone().map_or_else(
            || "não executado (cancelado ou interrompido).".to_owned(),
            |error| format!("o lado elevado parou: {error}"),
        )
    };
    let mut handle = |kind: Kind, index: usize, label: &str, destination: &str, is_item: bool| match report
        .find(kind, index)
    {
        Some(line) if line.status == Status::Ok => {
            if is_item {
                summary.configurations_succeeded += 1;
            } else {
                summary.extras_succeeded += 1;
            }
            (hooks.log)(&format!("ok {label}"));
        }
        Some(line) if line.status == Status::Skipped => {
            summary.warnings.push(format!("{label}: não foi aplicado{}.", reason(&line.detail)));
        }
        Some(line) => summary.failures.push(if is_item {
            format!(
                "{label}: a cópia para {destination} falhou mesmo como administrador{}.",
                reason(&line.detail)
            )
        } else {
            format!("{label}: não foi aplicado{}.", reason(&line.detail))
        }),
        None => summary.failures.push(format!("{label}: {}", not_run(report))),
    };
    for (index, item) in plan.items.iter().enumerate() {
        handle(Kind::Item, index, &item.name, &item.destination, true);
    }
    for (index, text) in plan.texts.iter().enumerate() {
        handle(Kind::Text, index, &text.name, &text.destination, true);
    }
    for (index, reg) in plan.registry.iter().enumerate() {
        handle(Kind::Registry, index, &reg.label, "", false);
    }
    for (index, task) in plan.tasks.iter().enumerate() {
        handle(Kind::Task, index, &task.label, "", false);
    }
    for (index, run) in plan.runs.iter().enumerate() {
        handle(Kind::Run, index, &run.label, "", false);
    }
    // o item foi aplicado, mas algo foi mantido como estava (ex.: um valor de registro que já existia com outro dado)
    let labels = plan_labels(plan);
    let offsets = [
        (Kind::Item, 0),
        (Kind::Text, plan.items.len()),
        (Kind::Registry, plan.items.len() + plan.texts.len()),
        (Kind::Task, plan.items.len() + plan.texts.len() + plan.registry.len()),
        (Kind::Run, plan.items.len() + plan.texts.len() + plan.registry.len() + plan.tasks.len()),
    ];
    for (kind, offset) in offsets {
        for line in report.lines.iter().filter(|l| l.kind == kind && l.status == Status::Warning) {
            let label = labels.get(offset + line.index).map_or("item", String::as_str);
            let detail = line.detail.strip_prefix("valor-existente-com-outro-dado:").map_or_else(
                || line.detail.clone(),
                |rest| format!("o valor {rest} já existia com outro dado e foi mantido"),
            );
            summary.warnings.push(format!("{label}: {detail}."));
        }
    }
    for general in &report.general {
        summary.failures.push(format!("Lote elevado: {general}"));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_winget_list_becomes_catalog_apps_keeping_the_interactive_flag() {
        let catalog = vec![SoftwareApp {
            name: "Riot Client".into(),
            winget_id: Some("Riot.Client".into()),
            source: Some("winget".into()),
            reference: None,
            default: true,
            interactive: true,
            note: None,
            extra: None,
            category: "Jogos".into(),
        }];
        let apps = apps_from_list(&["riot.client".into(), "Git.Git".into()], &catalog);
        assert!(apps[0].interactive && apps[0].name == "Riot Client");
        assert!(!apps[1].interactive && apps[1].is_installable() && apps[1].name == "Git.Git");
    }

    #[test]
    fn nvidia_defaults_to_skipping_the_driver() {
        assert_eq!(NvidiaChoice::default(), NvidiaChoice::Skip);
    }

    fn plan_with_everything() -> RestorePlan {
        RestorePlan {
            items: vec![
                PlanItem {
                    name: "A".into(),
                    source: r"D:\k\a".into(),
                    destination: r"C:\Program Files\A".into(),
                    is_folder: true,
                    files: vec![],
                },
                PlanItem {
                    name: "B".into(),
                    source: r"D:\k\b".into(),
                    destination: r"C:\Program Files\B".into(),
                    is_folder: true,
                    files: vec![],
                },
            ],
            registry: vec![PlanReg { label: "registro x".into(), text: String::new() }],
            tasks: vec![
                PlanTask {
                    label: "tarefa ISLC".into(),
                    name: "ISLC".into(),
                    xml: String::new(),
                    scripts: vec![],
                },
                PlanTask {
                    label: "tarefa Auto".into(),
                    name: "Auto".into(),
                    xml: String::new(),
                    scripts: vec![],
                },
            ],
            runs: vec![crate::restore_plan::PlanRun {
                label: "inicio LGHUB".into(),
                name: "LGHUB".into(),
                command: String::new(),
            }],
            ..RestorePlan::default()
        }
    }

    fn run_report(text: &str, plan: &RestorePlan) -> (RestoreSummary, Vec<String>) {
        let mut summary = RestoreSummary::default();
        let mut log = Vec::new();
        let mut progress = |_: &Progress| {};
        let mut sink = |line: &str| log.push(line.to_owned());
        apply_report(
            plan,
            &crate::restore_worker::parse_results(text),
            &mut summary,
            &mut Hooks { progress: &mut progress, log: &mut sink },
        );
        (summary, log)
    }

    #[test]
    fn the_report_counts_what_ran_and_says_why_the_rest_was_left_out() {
        let plan = plan_with_everything();
        let (summary, log) = run_report(
            "ok item 0\nfalha item 1 robocopy\nok registro 0\nok tarefa 0 ja-presente\npulada tarefa 1 ja-existe-outra-com-esse-nome\npulada inicio 0 ja-existe-outra-entrada-com-esse-nome\nFIM\n",
            &plan,
        );
        assert_eq!(summary.configurations_succeeded, 1);
        assert_eq!(summary.extras_succeeded, 2, "registro e tarefa já presente");
        assert_eq!(summary.failures.len(), 1);
        assert!(
            summary.failures[0].starts_with("B: a cópia para C:\\Program Files\\B falhou")
                && summary.failures[0].contains("robocopy")
        );
        assert_eq!(
            summary.warnings.len(),
            2,
            "o que já existia com outro conteúdo não é sobrescrito: aviso, não falha"
        );
        assert!(
            summary
                .warnings
                .iter()
                .any(|w| w.contains("tarefa Auto") && w.contains("ja-existe-outra-com-esse-nome"))
        );
        assert_eq!(log.len(), 3);
    }

    #[test]
    fn an_interrupted_or_refused_run_leaves_every_item_as_not_executed() {
        let plan = plan_with_everything();
        let (summary, _) = run_report("ERRO plano-adulterado-ou-ilegivel\nFIM\n", &plan);
        assert_eq!(summary.configurations_succeeded + summary.extras_succeeded, 0);
        assert_eq!(summary.failures.len(), 6, "{:?}", summary.failures);
        assert!(summary.failures.iter().all(|f| f.contains("o lado elevado parou: plano-adulterado")));
        let (cancelled, _) = run_report("ok item 0\n", &plan);
        assert_eq!(cancelled.failures.len(), 5);
        assert!(cancelled.failures[0].contains("cancelado ou interrompido"));
    }

    #[test]
    fn registry_and_task_files_the_manifest_does_not_list_are_found_and_not_used() {
        let kit = tempfile::tempdir().unwrap();
        std::fs::create_dir_all(kit.path().join(r"config\registro")).unwrap();
        std::fs::create_dir_all(kit.path().join(r"estado\tarefas")).unwrap();
        for file in [
            r"config\registro\listado.reg",
            r"config\registro\intruso.reg",
            r"estado\tarefas\Auto.xml",
            r"estado\tarefas\leia.txt",
        ] {
            std::fs::write(kit.path().join(file), "x").unwrap();
        }
        let approved = vec![("config/registro/listado.reg".to_owned(), "listado".to_owned())];
        assert_eq!(
            unlisted_files(&kit.path().to_string_lossy(), "config/registro", "reg", &approved),
            ["intruso.reg"]
        );
        assert_eq!(unlisted_files(&kit.path().to_string_lossy(), "estado/tarefas", "xml", &[]), ["Auto.xml"]);
        assert!(unlisted_files(&kit.path().to_string_lossy(), "nao/existe", "reg", &[]).is_empty());
    }
}
