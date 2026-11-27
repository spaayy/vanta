//! Instalação de programas: o plano (downloads em paralelo, uma instalação por vez, o que fechar depois)
//! e a execução pelo winget atrás de [`CommandRunner`] / [`BatchInstaller`].

use std::collections::HashSet;
use std::io;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

use crate::catalog::SoftwareApp;

/// Códigos de saída do winget que contam como sucesso (0, reinício pedido, já instalado, sem atualização).
pub const SUCCESSFUL_WINGET_EXIT_CODES: [i32; 5] = [0, 3010, 1641, -1_978_335_189, -1_978_335_135];

/// Quantos downloads rodam ao mesmo tempo. As instalações são uma por vez.
pub const MAX_PARALLEL_DOWNLOADS: usize = 6;

pub fn is_success(exit_code: i32) -> bool {
    SUCCESSFUL_WINGET_EXIT_CODES.contains(&exit_code)
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CommandResult {
    pub exit_code: i32,
    pub stdout: String,
    pub stderr: String,
}

/// Roda um programa (o winget). O Vanta Tools liga o processo real.
pub trait CommandRunner {
    fn run(&self, executable: &str, arguments: &[String]) -> io::Result<CommandResult>;
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BatchResult {
    pub id: String,
    pub success: bool,
    pub message: String,
}

/// Instalação em lote, num só processo elevado (um pedido de administrador).
pub trait BatchInstaller {
    fn install_batch(&self, ids: &[String], interactive: &HashSet<String>) -> Vec<BatchResult>;

    /// Igual a [`BatchInstaller::install_batch`], e com `vencord` o lote instala o Vencord (instalador oficial, linha de
    /// comando) depois do Discord, só se o Discord for instalado com sucesso nesta mesma execução. Quem não sabe de
    /// Vencord ignora o pedido. O resultado do Vencord volta como um [`BatchResult`] de id [`VENCORD_ID`].
    fn install_batch_with(
        &self,
        ids: &[String],
        interactive: &HashSet<String>,
        vencord: bool,
    ) -> Vec<BatchResult> {
        let _ = vencord;
        self.install_batch(ids, interactive)
    }
}

/// O id do Discord no winget (o Vencord só vai junto com ele).
pub const DISCORD_ID: &str = "Discord.Discord";
/// O id do resultado do Vencord no lote (não é um id do winget: o instalador vem do GitHub do Vencord).
pub const VENCORD_ID: &str = "Vencord";

/// Pedido de cancelamento compartilhado entre a tela e o trabalho.
#[derive(Clone, Default)]
pub struct CancelToken(Arc<AtomicBool>);

impl CancelToken {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn cancel(&self) {
        self.0.store(true, Ordering::SeqCst);
    }

    pub fn is_cancelled(&self) -> bool {
        self.0.load(Ordering::SeqCst)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Cancelled;

impl std::fmt::Display for Cancelled {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("Operação cancelada.")
    }
}

impl std::error::Error for Cancelled {}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Progress {
    pub phase: String,
    pub item: String,
    pub completed: usize,
    pub total: usize,
    pub message: String,
}

/// Argumentos do `winget install`. Programa interativo não leva `--silent`.
pub fn winget_install_args(id: &str, interactive: bool) -> Vec<String> {
    let mut args: Vec<String> =
        ["install", "--id", id, "--exact", "--accept-source-agreements", "--accept-package-agreements"]
            .iter()
            .map(|s| (*s).to_owned())
            .collect();
    if !interactive {
        args.push("--silent".into());
        args.push("--disable-interactivity".into());
    }
    args
}

/// Detalhe do erro em uma linha, com no máximo `limit` caracteres.
pub fn format_diagnostic(stderr: &str, stdout: &str, limit: usize) -> String {
    let text = if stderr.trim().is_empty() { stdout } else { stderr };
    let compact = text.split_whitespace().collect::<Vec<_>>().join(" ");
    compact.chars().take(limit).collect()
}

/// `winget.txt`: um id por linha; linhas vazias e repetidas (sem diferenciar maiúsculas) saem.
pub fn parse_winget_list(text: &str) -> Vec<String> {
    let mut seen = HashSet::new();
    text.lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .filter(|line| seen.insert(line.to_lowercase()))
        .map(str::to_owned)
        .collect()
}

/// Instala a lista do `winget.txt` um programa por vez. Um que falha não impede os outros.
pub fn install_listed(
    ids: &[String],
    runner: &dyn CommandRunner,
    cancel: &CancelToken,
    progress: &mut dyn FnMut(&Progress),
) -> Result<(usize, Vec<String>), Cancelled> {
    let mut succeeded = 0;
    let mut failures = Vec::new();
    for (index, id) in ids.iter().enumerate() {
        if cancel.is_cancelled() {
            return Err(Cancelled);
        }
        progress(&Progress {
            phase: "Programas".into(),
            item: id.clone(),
            completed: index,
            total: ids.len(),
            message: format!("Instalando {id}"),
        });
        match runner.run("winget.exe", &winget_install_args(id, false)) {
            Ok(result) if is_success(result.exit_code) => succeeded += 1,
            Ok(result) => {
                let detail = format_diagnostic(&result.stderr, &result.stdout, 320);
                let detail = if detail.is_empty() { String::new() } else { format!(" Detalhe: {detail}") };
                failures.push(format!("{id}: winget retornou código {}.{detail}", result.exit_code));
            }
            Err(error) => failures.push(format!("{id}: {error}")),
        }
        progress(&Progress {
            phase: "Programas".into(),
            item: id.clone(),
            completed: index + 1,
            total: ids.len(),
            message: format!("{} de {} concluídos", index + 1, ids.len()),
        });
    }
    Ok((succeeded, failures))
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InstallState {
    Succeeded,
    Failed,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SoftwareInstallResult {
    pub app: SoftwareApp,
    pub state: InstallState,
    pub message: String,
}

/// Instala os programas escolhidos do catálogo, um por vez, pelo winget.
pub fn install_apps(
    apps: &[SoftwareApp],
    runner: &dyn CommandRunner,
    cancel: &CancelToken,
    progress: &mut dyn FnMut(&Progress),
) -> Result<Vec<SoftwareInstallResult>, Cancelled> {
    let mut results = Vec::with_capacity(apps.len());
    for (index, app) in apps.iter().enumerate() {
        if cancel.is_cancelled() {
            return Err(Cancelled);
        }
        let report = |completed: usize, message: String, progress: &mut dyn FnMut(&Progress)| {
            progress(&Progress {
                phase: "Programas".into(),
                item: app.name.clone(),
                completed,
                total: apps.len(),
                message,
            });
        };
        if !app.is_installable() {
            results.push(SoftwareInstallResult {
                app: app.clone(),
                state: InstallState::Failed,
                message: "Fonte ainda não tem instalação automática configurada.".into(),
            });
            report(index + 1, format!("Origem não configurada: {}", app.name), progress);
            continue;
        }
        report(index, format!("Instalando {}", app.name), progress);
        let id = app.winget_id.as_deref().unwrap_or_default();
        let (state, message) = match runner.run("winget.exe", &winget_install_args(id, app.interactive)) {
            Ok(r) if is_success(r.exit_code) => (
                InstallState::Succeeded,
                if matches!(r.exit_code, 3010 | 1641) {
                    "Instalado; reinicialização solicitada."
                } else {
                    "Instalado."
                }
                .to_owned(),
            ),
            Ok(r) => {
                let detail = format_diagnostic(&r.stderr, &r.stdout, 280);
                let text = if detail.is_empty() {
                    format!("WinGet encerrou com código {}.", r.exit_code)
                } else {
                    format!("WinGet encerrou com código {}: {detail}", r.exit_code)
                };
                (InstallState::Failed, text)
            }
            Err(error) => (InstallState::Failed, error.to_string()),
        };
        report(index + 1, format!("{}: {message}", app.name), progress);
        results.push(SoftwareInstallResult { app: app.clone(), state, message });
    }
    Ok(results)
}

/// Instala todos os programas de uma vez pelo lote elevado; os sem instalador automático falham à parte.
pub fn install_apps_batch(
    apps: &[SoftwareApp],
    installer: &dyn BatchInstaller,
) -> Vec<SoftwareInstallResult> {
    install_apps_batch_with(apps, installer, false)
}

/// Como [`install_apps_batch`], e com `vencord` o Vencord vai junto com o Discord. Só conta se o Discord está entre
/// os programas escolhidos E instalável; sem ele o pedido é descartado (o lote nunca recebe `vencord` sozinho).
pub fn install_apps_batch_with(
    apps: &[SoftwareApp],
    installer: &dyn BatchInstaller,
    vencord: bool,
) -> Vec<SoftwareInstallResult> {
    let vencord = vencord
        && apps.iter().any(|a| {
            a.is_installable() && a.winget_id.as_deref().is_some_and(|id| id.eq_ignore_ascii_case(DISCORD_ID))
        });
    let mut lookup: Vec<(&str, &SoftwareApp)> = Vec::new();
    for app in apps.iter().filter(|a| a.is_installable()) {
        let id = app.winget_id.as_deref().unwrap_or_default();
        if !lookup.iter().any(|(known, _)| known.eq_ignore_ascii_case(id)) {
            lookup.push((id, app));
        }
    }
    let ids: Vec<String> = lookup.iter().map(|(id, _)| (*id).to_owned()).collect();
    let interactive: HashSet<String> = apps
        .iter()
        .filter(|a| a.is_installable() && a.interactive)
        .filter_map(|a| a.winget_id.clone())
        .collect();
    let mut results: Vec<SoftwareInstallResult> = installer
        .install_batch_with(&ids, &interactive, vencord)
        .into_iter()
        .filter_map(|r| {
            let state = if r.success { InstallState::Succeeded } else { InstallState::Failed };
            if vencord && r.id == VENCORD_ID {
                return Some(SoftwareInstallResult { app: vencord_app(), state, message: r.message });
            }
            let app = lookup.iter().find(|(id, _)| id.eq_ignore_ascii_case(&r.id))?.1.clone();
            Some(SoftwareInstallResult { app, state, message: r.message })
        })
        .collect();
    results.extend(apps.iter().filter(|a| !a.is_installable()).map(|a| SoftwareInstallResult {
        app: a.clone(),
        state: InstallState::Failed,
        message: "Sem instalador automático.".into(),
    }));
    results
}

/// O Vencord como item do resultado (não existe no catálogo: é a opção do Discord).
fn vencord_app() -> SoftwareApp {
    SoftwareApp {
        name: "Vencord".into(),
        winget_id: None,
        source: Some("github".into()),
        reference: Some("Vencord/Installer".into()),
        default: false,
        interactive: false,
        note: None,
        extra: None,
        category: "Comunicação".into(),
    }
}

/// Processos que cada programa abre sozinho ao instalar e que o Vanta fecha logo em seguida.
pub fn processes_to_close(winget_id: &str) -> &'static [&'static str] {
    match winget_id.to_lowercase().as_str() {
        "valve.steam" => &["steam", "steamwebhelper"],
        "discord.discord" => &["Discord"],
        "logitech.ghub" => &["lghub", "lghub_agent", "lghub_system_tray"],
        "obsproject.obsstudio" => &["obs64"],
        "brave.brave" => &["brave"],
        "tailscale.tailscale" => &["tailscale-ipn"],
        "cloudflare.warp" => &["Cloudflare WARP"],
        "multiviewer.multiviewer" => &["MultiViewer"],
        "anthropic.claude" => &["claude"],
        "qbittorrent.qbittorrent" => &["qbittorrent"],
        "skillbrains.lightshot" => &["Lightshot"],
        "techpowerup.nvcleanstall" => &["NVCleanstall"],
        "teamspeaksystems.teamspeakclient" => &["ts3client_win64"],
        "wagnardsoft.islc" => &["Intelligent standby list cleaner ISLC"],
        "handbrake.handbrake" => &["HandBrake"],
        "videolan.vlc" => &["vlc"],
        "notepad++.notepad++" => &["notepad++"],
        "thedocumentfoundation.libreoffice" => &["soffice", "soffice.bin"],
        _ => &[],
    }
}

/// Ação extra depois de instalar um programa.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PostInstall {
    /// O instalador do TeamSpeak traz o Overwolf: tira sem abrir janela de desinstalação.
    RemoveOverwolf,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InstallStep {
    pub id: String,
    pub name: String,
    /// Sem `--silent`: o programa mostra o instalador (Riot, por exemplo).
    pub interactive: bool,
    pub close_after: Vec<String>,
    pub post: Vec<PostInstall>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InstallPlan {
    pub max_parallel_downloads: usize,
    /// Ids a baixar (todos de uma vez, no máximo `max_parallel_downloads` por vez), sem repetir.
    pub downloads: Vec<String>,
    /// Instalação: um por vez, nesta ordem.
    pub steps: Vec<InstallStep>,
    /// Programas sem instalador automático (ficam fora do plano).
    pub not_installable: Vec<SoftwareApp>,
}

impl InstallPlan {
    /// Os ids em lotes de download.
    pub fn download_waves(&self) -> Vec<&[String]> {
        self.downloads.chunks(self.max_parallel_downloads).collect()
    }
}

/// Monta o plano. O Overwolf do TeamSpeak sai logo depois do TeamSpeak.
pub fn plan_install(apps: &[SoftwareApp]) -> InstallPlan {
    let mut seen = HashSet::new();
    let mut downloads = Vec::new();
    let mut steps = Vec::new();
    let mut not_installable = Vec::new();
    for app in apps {
        if !app.is_installable() {
            not_installable.push(app.clone());
            continue;
        }
        let id = app.winget_id.clone().unwrap_or_default();
        if !seen.insert(id.to_lowercase()) {
            continue;
        }
        let post = if id.eq_ignore_ascii_case("TeamSpeakSystems.TeamSpeakClient") {
            vec![PostInstall::RemoveOverwolf]
        } else {
            vec![]
        };
        steps.push(InstallStep {
            close_after: processes_to_close(&id).iter().map(|p| (*p).to_owned()).collect(),
            id: id.clone(),
            name: app.name.clone(),
            interactive: app.interactive,
            post,
        });
        downloads.push(id);
    }
    InstallPlan { max_parallel_downloads: MAX_PARALLEL_DOWNLOADS, downloads, steps, not_installable }
}

#[cfg(test)]
mod tests {
    use std::cell::RefCell;

    use super::*;

    type ExitCode = Box<dyn Fn(&[String]) -> i32>;

    pub struct RecordingRunner {
        pub calls: RefCell<Vec<(String, Vec<String>)>>,
        pub exit_code: ExitCode,
    }

    impl RecordingRunner {
        pub fn new() -> Self {
            Self { calls: RefCell::new(Vec::new()), exit_code: Box::new(|_| 0) }
        }
    }

    impl CommandRunner for RecordingRunner {
        fn run(&self, executable: &str, arguments: &[String]) -> io::Result<CommandResult> {
            self.calls.borrow_mut().push((executable.to_owned(), arguments.to_vec()));
            Ok(CommandResult {
                exit_code: (self.exit_code)(arguments),
                stdout: String::new(),
                stderr: String::new(),
            })
        }
    }

    fn app(name: &str, id: Option<&str>, interactive: bool) -> SoftwareApp {
        SoftwareApp {
            name: name.into(),
            winget_id: id.map(str::to_owned),
            source: id.map(|_| "winget".to_owned()),
            reference: None,
            default: false,
            interactive,
            note: None,
            extra: None,
            category: "Cat".into(),
        }
    }

    // SoftwareInstallCoordinatorTests.InstallsOnlyTheSelectedWingetEntries
    #[test]
    fn installs_only_the_selected_winget_entries() {
        let runner = RecordingRunner::new();
        let brave = app("Brave", Some("Brave.Brave"), false);
        let chrome = app("Chrome", Some("Google.Chrome"), false);
        let _ = brave;
        let results = install_apps(&[chrome], &runner, &CancelToken::new(), &mut |_| {}).unwrap();
        let calls = runner.calls.borrow();
        assert_eq!(calls.len(), 1);
        assert!(calls[0].1.contains(&"Google.Chrome".to_owned()));
        assert!(!calls[0].1.contains(&"Brave.Brave".to_owned()));
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].state, InstallState::Succeeded);
    }

    // SoftwareInstallCoordinatorTests.InteractiveEntriesDoNotReceiveSilentFlags
    #[test]
    fn interactive_entries_do_not_receive_silent_flags() {
        let runner = RecordingRunner::new();
        install_apps(
            &[app("Riot Client", Some("Riot.Client"), true)],
            &runner,
            &CancelToken::new(),
            &mut |_| {},
        )
        .unwrap();
        let calls = runner.calls.borrow();
        assert!(!calls[0].1.contains(&"--silent".to_owned()));
        assert!(!calls[0].1.contains(&"--disable-interactivity".to_owned()));
        assert!(winget_install_args("X.Y", false).contains(&"--silent".to_owned()));
    }

    #[test]
    fn an_app_without_an_installer_fails_without_running_anything() {
        let runner = RecordingRunner::new();
        let results =
            install_apps(&[app("Pessoal", None, false)], &runner, &CancelToken::new(), &mut |_| {}).unwrap();
        assert!(runner.calls.borrow().is_empty());
        assert_eq!(results[0].state, InstallState::Failed);
    }

    #[test]
    fn reboot_codes_succeed_and_a_failure_keeps_the_exit_code_and_detail() {
        assert!(is_success(3010) && is_success(1641) && is_success(0) && !is_success(5));
        let mut runner = RecordingRunner::new();
        runner.exit_code = Box::new(|_| 3010);
        let ok =
            install_apps(&[app("A", Some("A.A"), false)], &runner, &CancelToken::new(), &mut |_| {}).unwrap();
        assert!(ok[0].message.contains("reinicialização"));
        assert_eq!(format_diagnostic("", "  linha 1\n linha 2 ", 5), "linha");
    }

    #[test]
    fn cancelling_stops_before_the_next_install() {
        let runner = RecordingRunner::new();
        let cancel = CancelToken::new();
        let apps = [app("A", Some("A.A"), false), app("B", Some("B.B"), false)];
        let result = install_apps(&apps, &runner, &cancel, &mut |_| cancel.cancel());
        assert_eq!(result, Err(Cancelled));
        assert!(runner.calls.borrow().len() <= 1);
    }

    #[test]
    fn the_winget_list_is_trimmed_and_deduplicated() {
        assert_eq!(
            parse_winget_list("Git.Git\r\n\r\n  discord.discord \r\nGit.GIT\r\nDiscord.Discord\r\n"),
            ["Git.Git", "discord.discord"]
        );
    }

    #[test]
    fn the_plan_has_one_install_at_a_time_and_up_to_six_parallel_downloads() {
        let apps: Vec<SoftwareApp> =
            (0..14).map(|i| app(&format!("P{i}"), Some(&format!("V.P{i}")), false)).collect();
        let plan = plan_install(&apps);
        assert_eq!(plan.max_parallel_downloads, 6);
        assert_eq!(plan.steps.len(), 14, "uma instalação por passo, em fila");
        let waves = plan.download_waves();
        assert_eq!(waves.iter().map(|w| w.len()).collect::<Vec<_>>(), [6, 6, 2]);
        assert!(
            plan.steps.iter().zip(&plan.downloads).all(|(s, d)| &s.id == d),
            "a ordem de instalação é a ordem pedida"
        );
    }

    #[test]
    fn the_plan_closes_what_each_installer_opens_and_removes_overwolf_after_teamspeak() {
        let apps = vec![
            app("TeamSpeak", Some("TeamSpeakSystems.TeamSpeakClient"), false),
            app("Discord", Some("Discord.Discord"), false),
            app("Riot", Some("Riot.Client"), true),
            app("Repetido", Some("discord.discord"), false),
            app("Pessoal", None, false),
        ];
        let plan = plan_install(&apps);
        assert_eq!(plan.steps.len(), 3, "sem repetir e sem o que não tem instalador");
        assert_eq!(plan.not_installable.len(), 1);
        assert_eq!(plan.steps[0].post, [PostInstall::RemoveOverwolf]);
        assert_eq!(plan.steps[0].close_after, ["ts3client_win64"]);
        assert_eq!(plan.steps[1].close_after, ["Discord"]);
        assert!(plan.steps[2].interactive && plan.steps[2].post.is_empty());
        assert!(plan.steps.iter().skip(1).all(|s| s.post.is_empty()));
    }

    #[test]
    fn the_batch_installer_gets_unique_ids_and_the_interactive_ones() {
        struct Batch(RefCell<Vec<(Vec<String>, Vec<String>)>>);
        impl BatchInstaller for Batch {
            fn install_batch(&self, ids: &[String], interactive: &HashSet<String>) -> Vec<BatchResult> {
                let mut i: Vec<String> = interactive.iter().cloned().collect();
                i.sort();
                self.0.borrow_mut().push((ids.to_vec(), i));
                ids.iter()
                    .map(|id| BatchResult { id: id.clone(), success: id != "B.B", message: "x".into() })
                    .collect()
            }
        }
        let batch = Batch(RefCell::new(Vec::new()));
        let apps = [
            app("A", Some("A.A"), true),
            app("B", Some("B.B"), false),
            app("a", Some("a.a"), false),
            app("P", None, false),
        ];
        let results = install_apps_batch(&apps, &batch);
        assert_eq!(batch.0.borrow()[0], (vec!["A.A".to_owned(), "B.B".to_owned()], vec!["A.A".to_owned()]));
        assert_eq!(results.iter().filter(|r| r.state == InstallState::Failed).count(), 2);
    }

    #[test]
    fn vencord_goes_to_the_batch_only_with_discord_chosen_and_comes_back_as_its_own_result() {
        struct Batch(RefCell<Vec<bool>>);
        impl BatchInstaller for Batch {
            fn install_batch(&self, ids: &[String], _: &HashSet<String>) -> Vec<BatchResult> {
                ids.iter().map(|id| BatchResult { id: id.clone(), success: true, message: "ok".into() }).collect()
            }
            fn install_batch_with(&self, ids: &[String], i: &HashSet<String>, vencord: bool) -> Vec<BatchResult> {
                self.0.borrow_mut().push(vencord);
                let mut results = self.install_batch(ids, i);
                if vencord {
                    results.push(BatchResult { id: VENCORD_ID.into(), success: false, message: "Discord aberto".into() });
                }
                results
            }
        }
        let batch = Batch(RefCell::new(Vec::new()));
        let with_discord = [app("Discord", Some("Discord.Discord"), false), app("VLC", Some("VideoLAN.VLC"), false)];
        let without_discord = [app("VLC", Some("VideoLAN.VLC"), false)];
        let package_only = [app("Discord", None, false)];

        let results = install_apps_batch_with(&with_discord, &batch, true);
        let vencord: Vec<_> = results.iter().filter(|r| r.app.name == "Vencord").collect();
        assert_eq!(vencord.len(), 1);
        assert_eq!(vencord[0].state, InstallState::Failed);
        assert_eq!(vencord[0].message, "Discord aberto");
        assert_eq!(results.len(), 3);

        install_apps_batch_with(&with_discord, &batch, false);
        install_apps_batch_with(&without_discord, &batch, true);
        install_apps_batch_with(&package_only, &batch, true);
        install_apps_batch(&with_discord, &batch);
        assert_eq!(*batch.0.borrow(), [true, false, false, false, false], "só o primeiro pedido leva o Vencord");
    }

    #[test]
    fn an_installer_that_does_not_know_vencord_just_installs_the_programs() {
        struct Plain;
        impl BatchInstaller for Plain {
            fn install_batch(&self, ids: &[String], _: &HashSet<String>) -> Vec<BatchResult> {
                ids.iter().map(|id| BatchResult { id: id.clone(), success: true, message: "ok".into() }).collect()
            }
        }
        let results = install_apps_batch_with(&[app("Discord", Some("Discord.Discord"), false)], &Plain, true);
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].app.name, "Discord");
    }
}
