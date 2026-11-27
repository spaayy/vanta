//! As telas do Vanta Tools com o visual do Vanta 1: Início, Programas, Restaurar, Ajustes, Preferências e
//! Registros. Os trabalhos em segundo plano (instalar, restaurar, aplicar ajuste) não mudaram.

use std::collections::{HashMap, HashSet};
use std::io::Write as _;
use std::path::PathBuf;
use std::sync::Arc;
use std::sync::mpsc::{Receiver, Sender, channel};
use std::time::Duration;

use gpui::{
    AnyElement, BoxShadow, Context, Entity, FocusHandle, Focusable, FontWeight, HighlightStyle, IntoElement,
    KeyDownEvent, MouseButton, ObjectFit, ParentElement, PromptLevel, Render, Role, ScrollHandle, SharedString, Styled, StyledImage, StyledText,
    Toggled, Window, div, img, linear_color_stop, linear_gradient, point, prelude::*, px,
};
use vanta_core::catalog::{SoftwareApp, SoftwareCatalog};
use vanta_core::install::{CancelToken, InstallState, Progress, SoftwareInstallResult, install_apps_batch_with};
use vanta_core::apps::EstadoApp;
use vanta_core::avancado::Dispositivo;
use vanta_core::diario::Diario;
use vanta_core::energia::OpcaoEnergia;
use vanta_core::niveis::{Ambiente, Deteccao, Nivel, PlanoNivel};
use vanta_core::servicos::{EstadoServico, StartType};
use vanta_core::restore::RestoreOptions;
use vanta_core::tweaks::{RegValue, SystemStore, Tweak, TweakEngine, TweakError, TweakState};
use vanta_core::view::{PROGRAM_CHIPS, StateFilter, area_rank, chip_of, name_matches};
use vanta_sys::batch::ElevatedInstaller;
use vanta_sys::execute::{Hooks, NvidiaChoice, RestoreSummary, execute_restore};
use vanta_sys::niveis::{ProcessExecutor, caminho_diario, detectar, ler_diario};
use vanta_sys::store::RegistryStore;

use super::data::{
    self, Args, CoreIsolation, GpuVendor, KitState, PcDiagnostics, Texts, area_name, describe_plan,
};
use super::kit::{self, Kind, Prefs, TweakCopy, a, c};
use super::theme::*;
use crate::theme::{FONT_DISPLAY, FONT_MONO, FONT_TEXT};
use crate::ui::actions::{FocusNext, FocusPrevious, NavigateBack};
use crate::ui::text_input::TextInput;
use crate::ui::{
    FocusHandles, InfoBar, ScrollbarState, Severity, TitleBar, focus_reveal, focus_ring,
    page_keyboard_scrolling, scrollbar,
};

/// Largura do painel de navegação e margens da página, como no Vanta 1.
const NAV_W: f32 = 248.;
const PAGE_X: f32 = 56.;
const PAGE_TOP: f32 = 36.;
const PAGE_MAX: f32 = 1180.;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) enum Page {
    Home,
    Optimize,
    Programs,
    Restore,
    Power,
    Apps,
    Services,
    Advanced,
    Settings,
    Preferences,
    Logs,
}

impl Page {
    fn index(self) -> usize {
        self as usize
    }
}

pub(super) enum Msg {
    Progress(Progress),
    Log(String),
    RestoreDone(Box<RestoreSummary>),
    InstallDone(Vec<SoftwareInstallResult>),
    PcReady(PcDiagnostics),
    EnvReady(Deteccao, Ambiente),
    AppsLoaded(HashMap<String, EstadoApp>),
    DevicesLoaded(Result<Vec<Dispositivo>, String>),
    PowerDone {
        result: Result<Vec<String>, String>,
        diario: Diario,
        was_undo: bool,
    },
    AppActionDone {
        chave: String,
        is_remove: bool,
        result: Result<(), String>,
        diario: Diario,
        new_state: EstadoApp,
    },
    DeviceActionDone {
        instance_id: String,
        is_disable: bool,
        result: Result<(), String>,
        diario: Diario,
    },
}

#[derive(Default)]
struct Job {
    running: bool,
    fraction: f32,
    current: String,
    log: Vec<String>,
    cancel: CancelToken,
    /// Resultado final: (deu certo, linhas).
    outcome: Option<(bool, Vec<String>)>,
}

impl Job {
    fn start(&mut self) {
        self.running = true;
        self.fraction = 0.;
        self.current.clear();
        self.log.clear();
        self.outcome = None;
        self.cancel = CancelToken::new();
    }

    fn progress(&mut self, p: &Progress) {
        if p.total > 0 {
            self.fraction = p.completed as f32 / p.total as f32;
        }
        self.current.clone_from(&p.message);
    }
}

/// Tom visual do aviso de página: erro ou informação neutra (ex.: serviço ausente pulado).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) enum NoticeKind {
    Error,
    Info,
}

/// Aviso/erro de página isolado por `(page, area)` para nunca vazar ao trocar de aba.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(super) struct PageNotice {
    pub(super) page: Page,
    pub(super) area: Option<String>,
    pub(super) kind: NoticeKind,
    pub(super) message: String,
}

impl PageNotice {
    pub(super) fn matches(&self, page: Page, area: &str) -> bool {
        self.page == page && (page != Page::Settings || self.area.as_deref() == Some(area))
    }
}

pub struct ToolsApp {
    pub(super) page: Page,
    pub(super) area: String,
    pub(super) tweaks: Vec<Tweak>,
    pub(super) states: Vec<TweakState>,
    texts: Texts,
    pub(super) copy: HashMap<String, TweakCopy>,
    catalog: SoftwareCatalog,
    apps: Vec<SoftwareApp>,
    selected: HashSet<usize>,
    category: Option<String>,
    kit: KitState,
    kit_arg: Option<String>,
    restore_apps: bool,
    restore_config: bool,
    nvidia: NvidiaChoice,
    restore_job: Job,
    install_job: Job,
    pub(super) tx: Sender<Msg>,
    rx: Receiver<Msg>,
    pub(super) elevated: bool,
    /// Aviso da página atual isolado por `(Page, area)` (nunca atravessa para outra aba).
    pub(super) notice: Option<PageNotice>,
    scrolls: [ScrollHandle; 11],
    bars: [ScrollbarState; 11],
    /// Teclado: o foco da janela (Tab, Enter, Esc) e um foco estável por controle que o exige.
    root_focus: FocusHandle,
    pub(super) focus: FocusHandles,
    /// Filtros por nome (Programas e Ajustes), a busca da barra de título e o foco do botão que a abre.
    programs_filter: Entity<TextInput>,
    settings_filter: Entity<TextInput>,
    search: Entity<TextInput>,
    search_open: bool,
    search_button_focus: FocusHandle,
    state_filter: StateFilter,
    /// Por que um ajuste não aplicou, por índice: aparece na própria linha.
    pub(super) row_errors: HashMap<usize, String>,
    /// Ajustes abertos (a seta da linha mostra a explicação).
    pub(super) expanded: HashSet<usize>,
    pub(super) pc: Option<PcDiagnostics>,
    pub(super) prefs: Prefs,
    logs: Vec<PathBuf>,
    log_selected: Option<usize>,
    log_text: String,
    /// F4: caixa "Instalar Vencord junto" abaixo do Discord (só ativa quando Discord está marcado).
    install_vencord: bool,
    /// F3: caixa "Não jogo Valorant..." que destrava `vbs-hvci` na área de Segurança.
    core_isolation_unlocked: bool,
    /// Largura útil da página, para a grade de programas caber sem sobra (como o Vanta 1 calcula).
    content_w: f32,
    /// Estado de abertura de `THIRD-PARTY-NOTICES.txt` na seção Sobre e licenças.
    licences_opening: bool,
    licences_failed: bool,
    /// v1.1: estado da página Otimizar (nível ativo, seleção personalizada, planos lidos do registro).
    pub(super) selected_level: Nivel,
    pub(super) level_custom: Option<HashSet<String>>,
    pub(super) level_plans: [PlanoNivel; 3],
    pub(super) ja_feito_open: bool,
    pub(super) pulados_open: bool,
    pub(super) optimize_outcome: Option<(usize, bool)>,
    pub(super) optimize_notice: Option<String>,
    pub(super) optimize_info_notes: Vec<String>,
    pub(super) optimize_errors: Vec<(String, String)>,
    /// v1.1: detecção real, diário persistente e estado das páginas manuais.
    pub(super) env_detected: Option<(Deteccao, Ambiente)>,
    pub(super) diario: Diario,
    pub(super) diario_error: Option<String>,
    pub(super) power_selected: HashSet<OpcaoEnergia>,
    pub(super) power_busy: bool,
    pub(super) power_warnings: Vec<String>,
    pub(super) power_feedback: Option<Result<String, String>>,
    pub(super) service_states: HashMap<&'static str, Result<EstadoServico, String>>,
    pub(super) service_current: HashMap<&'static str, Option<StartType>>,
    pub(super) service_feedback: Option<Result<String, String>>,
    pub(super) app_states: Option<HashMap<String, EstadoApp>>,
    pub(super) apps_loading: bool,
    pub(super) app_busy: Option<String>,
    pub(super) app_feedback: Option<Result<String, String>>,
    pub(super) devices_state: Option<Result<Vec<Dispositivo>, String>>,
    pub(super) devices_loading: bool,
    pub(super) devices_show_all: bool,
    pub(super) device_busy: Option<String>,
    pub(super) device_feedback: Option<Result<String, String>>,
}

const VBS_HVCI_ID: &str = "vbs-hvci";
const DISCORD_WINGET_ID: &str = "Discord.Discord";
const VALORANT_UNLOCK_LABEL: &str = "Não jogo Valorant nem outro jogo com anti-cheat que exige isso";
const GPL_URL: &str = "https://www.gnu.org/licenses/gpl-3.0.html";
const ATLAS_URL: &str = "https://github.com/Atlas-OS/Atlas";
const GEIST_URL: &str = "https://github.com/vercel/geist-font";

/// Só considera HVCI já desligado quando o registro informa explicitamente `DWORD 0`.
/// Chave ausente (`None` / desconhecido) ou `1` (ligado) mantém a trava do Valorant fechada.
fn vbs_hvci_explicitly_disabled(value: Option<RegValue>) -> bool {
    matches!(value, Some(RegValue::Dword(0)))
}

fn read_vbs_hvci_explicitly_disabled(tweak: &Tweak) -> bool {
    let store = RegistryStore::new();
    let Some(edit) = tweak.registry.first() else {
        return false;
    };
    vbs_hvci_explicitly_disabled(store.get_value(&edit.key, &edit.name))
}

fn is_discord(app: &SoftwareApp) -> bool {
    app.winget_id.as_deref().is_some_and(|id| id.eq_ignore_ascii_case(DISCORD_WINGET_ID))
}

/// Mapeia categorias do catálogo para os chips da barra de Programas,
/// incluindo `NVCleanstall` (edição pública) dentro de `Ferramentas`.
fn program_chip(category: &str) -> &str {
    match category {
        "NVCleanstall" => "Ferramentas",
        other => chip_of(other),
    }
}

fn log_dir() -> PathBuf {
    PathBuf::from(std::env::var("LOCALAPPDATA").unwrap_or_default()).join("Vanta").join("Logs")
}

fn open_in_explorer(path: impl AsRef<std::ffi::OsStr>) {
    let _ = std::process::Command::new("explorer.exe").arg(path).spawn();
}

gpui::actions!(vanta_tools, [OpenSearch]);

/// Para onde um resultado da busca leva.
#[derive(Clone)]
enum Target {
    Page(Page),
    Area(String),
    Tweak(usize),
    App(usize),
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum CheckLevel {
    Loading,
    Ok,
    Warn,
    Bad,
    Unknown,
}

#[derive(Clone, Copy)]
enum CheckFix {
    PowerPlan,
    CoreIsolation,
    DisplayRate,
    RestorePage,
}

/// Uma das 5 linhas do cartão "Este PC" (Vanta 1, HomePage.xaml.cs). Só leitura.
struct PcCheck {
    id: &'static str,
    label: &'static str,
    value: String,
    mono: bool,
    level: CheckLevel,
    problem: Option<String>,
    fix: Option<CheckFix>,
}

fn build_pc_checks(pc: Option<&PcDiagnostics>, kit: &KitState, has_restore: bool) -> Vec<PcCheck> {
    let mut checks = Vec::with_capacity(if has_restore { 5 } else { 4 });

    // 1. Isolamento de núcleo
    let (hvci_value, hvci_level, hvci_problem, hvci_fix) = match pc {
        None => ("lendo…".to_owned(), CheckLevel::Loading, None, None),
        Some(d) => match d.core_isolation {
            CoreIsolation::On => ("Ligado".to_owned(), CheckLevel::Ok, None, None),
            CoreIsolation::Off => (
                "Desligado".to_owned(),
                CheckLevel::Bad,
                Some("Desligado: o Valorant não abre sem ele.".to_owned()),
                Some(CheckFix::CoreIsolation),
            ),
            CoreIsolation::Unknown => ("desconhecido".to_owned(), CheckLevel::Unknown, None, None),
        },
    };
    checks.push(PcCheck {
        id: "hvci",
        label: "Isolamento de núcleo",
        value: hvci_value,
        mono: false,
        level: hvci_level,
        problem: hvci_problem,
        fix: hvci_fix,
    });

    // 2. Taxa do monitor (alerta quando current_hz < max_hz)
    let (hz_value, hz_mono, hz_level, hz_problem, hz_fix) = match pc {
        None => ("lendo…".to_owned(), false, CheckLevel::Loading, None, None),
        Some(d) => match d.monitor {
            Some(mon) if mon.current_hz >= mon.max_hz => {
                (format!("{} Hz", mon.current_hz), true, CheckLevel::Ok, None, None)
            }
            Some(mon) => (
                format!("{} Hz", mon.current_hz),
                true,
                CheckLevel::Warn,
                Some(format!(
                    "O monitor está em {} Hz; o máximo nesta resolução é {} Hz.",
                    mon.current_hz, mon.max_hz
                )),
                Some(CheckFix::DisplayRate),
            ),
            None => ("desconhecido".to_owned(), false, CheckLevel::Unknown, None, None),
        },
    };
    checks.push(PcCheck {
        id: "hz",
        label: "Taxa do monitor",
        value: hz_value,
        mono: hz_mono,
        level: hz_level,
        problem: hz_problem,
        fix: hz_fix,
    });

    // 3. Driver de vídeo (driver_label)
    let (gpu_value, gpu_mono, gpu_level) = match pc {
        None => ("lendo…".to_owned(), false, CheckLevel::Loading),
        Some(d) => match &d.gpu {
            Some(gpu) if !gpu.driver_label.trim().is_empty() => {
                let text = match gpu.vendor {
                    GpuVendor::Nvidia => format!("NVIDIA {}", gpu.driver_label),
                    GpuVendor::Amd => format!("AMD {}", gpu.driver_label),
                    GpuVendor::Intel => format!("Intel {}", gpu.driver_label),
                    GpuVendor::Other => gpu.driver_label.clone(),
                };
                (text, true, CheckLevel::Ok)
            }
            _ => ("desconhecido".to_owned(), false, CheckLevel::Unknown),
        },
    };
    checks.push(PcCheck {
        id: "gpu",
        label: "Driver de vídeo",
        value: gpu_value,
        mono: gpu_mono,
        level: gpu_level,
        problem: None,
        fix: None,
    });

    // 4. Plano de energia (alerta quando não é o Vanta)
    let (power_value, power_level, power_problem, power_fix) = match pc {
        None => ("lendo…".to_owned(), CheckLevel::Loading, None, None),
        Some(d) => match &d.power_plan {
            Some(plan) if plan.is_vanta => ("Plano Vanta".to_owned(), CheckLevel::Ok, None, None),
            Some(_) => (
                "Outro plano".to_owned(),
                CheckLevel::Warn,
                Some(
                    "Outro plano está ativo. O plano Vanta tira a economia de energia do processador."
                        .to_owned(),
                ),
                Some(CheckFix::PowerPlan),
            ),
            None => ("desconhecido".to_owned(), CheckLevel::Unknown, None, None),
        },
    };
    checks.push(PcCheck {
        id: "power",
        label: "Plano de energia",
        value: power_value,
        mono: false,
        level: power_level,
        problem: power_problem,
        fix: power_fix,
    });

    // 5. Pacote de restauração (apenas na edição pessoal)
    if has_restore {
        let (kit_value, kit_level, kit_problem, kit_fix) = match kit {
            KitState::Ready(k) if k.guard.is_clean() => (
                plural(k.loaded.manifest.items.len(), "configuração", "configurações"),
                CheckLevel::Ok,
                None,
                None,
            ),
            KitState::Ready(_) => (
                "Precisa de revisão".to_owned(),
                CheckLevel::Warn,
                Some("O pacote foi achado, mas a conferência de segurança apontou alertas.".to_owned()),
                Some(CheckFix::RestorePage),
            ),
            KitState::Invalid(_) => (
                "Precisa de revisão".to_owned(),
                CheckLevel::Warn,
                Some("O pacote foi achado, mas o manifesto tem problema.".to_owned()),
                Some(CheckFix::RestorePage),
            ),
            KitState::Missing => (
                "Não encontrado".to_owned(),
                CheckLevel::Warn,
                Some("Conecte o disco onde está o pacote.".to_owned()),
                Some(CheckFix::RestorePage),
            ),
        };
        checks.push(PcCheck {
            id: "pkg",
            label: "Pacote de restauração",
            value: kit_value,
            mono: false,
            level: kit_level,
            problem: kit_problem,
            fix: kit_fix,
        });
    }

    // Itens fora do padrão sobem para o topo (como no Vanta 1); os demais seguem na ordem quieta.
    checks.sort_by_key(|item| usize::from(!matches!(item.level, CheckLevel::Bad | CheckLevel::Warn)));
    checks
}

fn plural(n: usize, one: &str, many: &str) -> String {
    format!("{n} {}", if n == 1 { one } else { many })
}

impl ToolsApp {
    pub fn new(args: Args, window: &mut Window, cx: &mut Context<Self>) -> Self {
        let localization = crate::i18n::activate(
            &crate::services::settings::LanguagePreference::Explicit("pt-BR".into()),
            None,
        );
        let accessibility = crate::services::system::AccessibilityPreferences {
            high_contrast: false,
            reduce_motion: false,
            text_scale: 1.0,
            system_colors: None,
        };
        let mut theme = crate::theme::Theme::resolve(
            crate::services::settings::ThemePreference::Dark,
            crate::theme::Appearance::from_window(window.appearance()),
            &accessibility,
        );
        super::theme::apply_vanta1(&mut theme);
        cx.set_global(theme);
        cx.set_global(localization);
        let tweaks = data::load_tweaks();
        let catalog = data::load_software();
        let apps: Vec<SoftwareApp> = catalog.apps().cloned().collect();
        let selected = HashSet::new();
        let (tx, rx) = channel();
        let has_restore = data::edicao().has_restore();
        let page = match args.page.as_deref() {
            Some("optimize") => Page::Optimize,
            Some("programs") => Page::Programs,
            Some("restore") if has_restore => Page::Restore,
            Some("power") => Page::Power,
            Some("apps") => Page::Apps,
            Some("services") => Page::Services,
            Some("advanced") => Page::Advanced,
            Some("settings") => Page::Settings,
            Some("preferences") => Page::Preferences,
            Some("logs") => Page::Logs,
            _ => Page::Home,
        };
        let prefs = Prefs::load();
        let selected_level = Nivel::from_id(&prefs.selected_level).unwrap_or(Nivel::Leve);
        let level_custom = prefs.custom_tweaks.as_ref().map(|items| items.iter().cloned().collect());
        let (diario, diario_error) = match ler_diario(&caminho_diario()) {
            Ok(d) => (d, None),
            Err(err) => (Diario::default(), Some(err)),
        };
        let mut power_selected = HashSet::new();
        power_selected.insert(OpcaoEnergia::PlanoVanta);
        let new_input = |cx: &mut Context<Self>, id: &'static str, label: fn() -> String| {
            let input = cx.new(|cx| {
                let mut input = TextInput::new(cx, id, label, label);
                input.set_plain(true);
                input
            });
            cx.observe(&input, |_, _, cx| cx.notify()).detach();
            input
        };
        let programs_filter = new_input(cx, "programs-filter", || "Filtrar por nome".into());
        let settings_filter = new_input(cx, "settings-filter", || "Filtrar nesta página".into());
        let search = new_input(cx, "global-search", || "O que você quer mudar?".into());
        let mut app = Self {
            page,
            area: tweaks.iter().map(|t| t.category.clone()).min_by_key(|c| area_rank(c)).unwrap_or_default(),
            states: Vec::new(),
            tweaks,
            texts: data::load_texts(),
            copy: kit::tweak_copy(),
            catalog,
            apps,
            selected,
            category: None,
            kit: if has_restore { data::load_kit(args.kit.as_deref()) } else { KitState::Missing },
            kit_arg: args.kit,
            restore_apps: true,
            restore_config: true,
            nvidia: NvidiaChoice::Skip,
            restore_job: Job::default(),
            install_job: Job::default(),
            tx,
            rx,
            elevated: vanta_sys::elevate::is_elevated(),
            notice: None,
            scrolls: Default::default(),
            bars: Default::default(),
            root_focus: cx.focus_handle(),
            focus: FocusHandles::default(),
            programs_filter,
            settings_filter,
            search,
            search_open: false,
            search_button_focus: cx.focus_handle(),
            state_filter: StateFilter::All,
            row_errors: HashMap::new(),
            expanded: HashSet::new(),
            pc: {
                #[cfg(debug_assertions)]
                {
                    match std::env::var("VANTA_TOOLS_PREVIEW_PC").ok().as_deref() {
                        Some("unknown") => Some(PcDiagnostics::default()),
                        _ => None,
                    }
                }
                #[cfg(not(debug_assertions))]
                {
                    None
                }
            },
            prefs,
            logs: Vec::new(),
            log_selected: None,
            log_text: String::new(),
            install_vencord: false,
            core_isolation_unlocked: false,
            content_w: 900.,
            licences_opening: false,
            licences_failed: false,
            selected_level,
            level_custom,
            level_plans: [PlanoNivel::default(), PlanoNivel::default(), PlanoNivel::default()],
            ja_feito_open: false,
            pulados_open: false,
            optimize_outcome: {
                #[cfg(debug_assertions)]
                {
                    if std::env::var("VANTA_TOOLS_PREVIEW_NOTE").ok().as_deref() == Some("1") {
                        Some((17, true))
                    } else {
                        None
                    }
                }
                #[cfg(not(debug_assertions))]
                {
                    None
                }
            },
            optimize_notice: None,
            optimize_info_notes: {
                #[cfg(debug_assertions)]
                {
                    if std::env::var("VANTA_TOOLS_PREVIEW_NOTE").ok().as_deref() == Some("1") {
                        vec!["Serviço ausente neste Windows (pulado): Fax.".to_owned()]
                    } else {
                        Vec::new()
                    }
                }
                #[cfg(not(debug_assertions))]
                {
                    Vec::new()
                }
            },
            optimize_errors: {
                #[cfg(debug_assertions)]
                {
                    if std::env::var("VANTA_TOOLS_PREVIEW_ERRORS").ok().as_deref() == Some("1") {
                        vec![(
                            "Permissão de administrador".to_owned(),
                            "O Windows negou 1 gravação(ões) no registro (serviço Fax: O sistema não pode encontrar o arquivo especificado)".to_owned(),
                        )]
                    } else {
                        Vec::new()
                    }
                }
                #[cfg(not(debug_assertions))]
                {
                    Vec::new()
                }
            },
            env_detected: None,
            diario,
            diario_error,
            power_selected,
            power_busy: false,
            power_warnings: Vec::new(),
            power_feedback: None,
            service_states: HashMap::new(),
            service_current: HashMap::new(),
            service_feedback: None,
            app_states: None,
            apps_loading: false,
            app_busy: None,
            app_feedback: None,
            devices_state: None,
            devices_loading: false,
            devices_show_all: false,
            device_busy: None,
            device_feedback: None,
        };
        if page == Page::Logs {
            app.refresh_logs();
        }
        #[cfg(debug_assertions)]
        if let Ok(raw) = std::env::var("VANTA_TOOLS_PREVIEW_SCROLL")
            && let Ok(y) = raw.parse::<f32>()
        {
            app.scrolls[page.index()].set_offset(point(px(0.), px(-y)));
        }
        window.focus(&app.root_focus, cx);
        app.refresh_states();
        // F3: só inicia destravado se o registro confirmar explicitamente HVCI = 0 (desligado).
        // Quando a chave está ausente (desconhecido) ou ligada (1), a trava começa fechada.
        if let Some(vbs) = app.tweaks.iter().find(|t| t.id == VBS_HVCI_ID)
            && read_vbs_hvci_explicitly_disabled(vbs)
        {
            app.core_isolation_unlocked = true;
        }
        // Só em debug, para conferência visual dos estados "lendo…" e "desconhecido"; não entra no release.
        #[cfg(debug_assertions)]
        let skip_pc_read =
            matches!(std::env::var("VANTA_TOOLS_PREVIEW_PC").ok().as_deref(), Some("loading" | "unknown"));
        #[cfg(not(debug_assertions))]
        let skip_pc_read = false;
        if !skip_pc_read {
            let pc_tx = app.tx.clone();
            data::read_pc_in_background(move |diag| {
                let _ = pc_tx.send(Msg::PcReady(diag));
            });
            let env_tx = app.tx.clone();
            std::thread::spawn(move || {
                let (det, amb) = detectar(&ProcessExecutor);
                let _ = env_tx.send(Msg::EnvReady(det, amb));
            });
        }
        cx.spawn(async move |this, cx| {
            loop {
                cx.background_executor().timer(Duration::from_millis(150)).await;
                if this.update(cx, |this, cx| this.drain(cx)).is_err() {
                    break;
                }
            }
        })
        .detach();
        app
    }

    /// Procura o kit de novo (mesma regra da abertura); só lê.
    fn reload_kit(&mut self, cx: &mut Context<Self>) {
        self.kit = data::load_kit(self.kit_arg.as_deref());
        cx.notify();
    }

    pub(super) fn refresh_states(&mut self) {
        let mut store = RegistryStore::new();
        self.states = self.tweaks.iter().map(|t| TweakEngine::new(&mut store).read(t)).collect();
        self.refresh_level_plans();
    }

    /// Os registros, do mais novo para o mais antigo; abre o mais novo.
    fn refresh_logs(&mut self) {
        let mut files: Vec<(std::time::SystemTime, PathBuf)> = std::fs::read_dir(log_dir())
            .map(|dir| {
                dir.filter_map(Result::ok)
                    .filter(|e| e.path().extension().is_some_and(|x| x.eq_ignore_ascii_case("log")))
                    .filter_map(|e| Some((e.metadata().ok()?.modified().ok()?, e.path())))
                    .collect()
            })
            .unwrap_or_default();
        files.sort_by_key(|x| std::cmp::Reverse(x.0));
        self.logs = files.into_iter().map(|(_, p)| p).collect();
        self.select_log(if self.logs.is_empty() { None } else { Some(0) });
    }

    fn select_log(&mut self, index: Option<usize>) {
        self.log_selected = index;
        self.log_text = index
            .and_then(|i| self.logs.get(i))
            .and_then(|p| std::fs::read(p).ok())
            .map(|bytes| {
                let text = String::from_utf8_lossy(&bytes).into_owned();
                // Arquivo grande: só o fim (o motivo de uma falha fica no fim).
                let lines: Vec<&str> = text.lines().collect();
                lines[lines.len().saturating_sub(1500)..].join("\n")
            })
            .unwrap_or_default();
    }

    pub(super) fn set_page_notice(&mut self, kind: NoticeKind, message: impl Into<String>) {
        self.notice = Some(PageNotice {
            page: self.page,
            area: (self.page == Page::Settings).then(|| self.area.clone()),
            kind,
            message: message.into(),
        });
    }

    pub(super) fn current_page_notice(&self, page: Page) -> Option<&PageNotice> {
        self.notice.as_ref().filter(|n| n.matches(page, &self.area))
    }

    pub(super) fn clear_page_notices(&mut self) {
        self.notice = None;
        self.optimize_notice = None;
        self.optimize_info_notes.clear();
        self.optimize_outcome = None;
        self.optimize_errors.clear();
        self.power_feedback = None;
        self.power_warnings.clear();
        self.service_feedback = None;
        self.app_feedback = None;
        self.device_feedback = None;
    }

    pub(super) fn go_page(&mut self, page: Page) {
        let page = if page == Page::Restore && !data::edicao().has_restore() {
            Page::Home
        } else {
            page
        };
        if self.page != page {
            self.clear_page_notices();
        }
        self.page = page;
        if page == Page::Logs {
            self.refresh_logs();
        }
    }

    pub(super) fn go_settings(&mut self, category: &str) {
        if self.page != Page::Settings || self.area != category {
            self.clear_page_notices();
        }
        self.page = Page::Settings;
        self.area = category.to_owned();
    }

    fn drain(&mut self, cx: &mut Context<Self>) {
        let mut changed = false;
        while let Ok(msg) = self.rx.try_recv() {
            changed = true;
            match msg {
                Msg::Progress(p) => {
                    let job = if p.phase == "Programas" && self.install_job.running {
                        &mut self.install_job
                    } else {
                        &mut self.restore_job
                    };
                    job.progress(&p);
                }
                Msg::Log(line) => self.restore_job.log.push(line),
                Msg::RestoreDone(summary) => {
                    let ok = summary.failures.is_empty() && !summary.cancelled;
                    let mut lines = vec![format!(
                        "{}, {}, {} de registro e tarefas.",
                        plural(summary.apps_succeeded, "programa instalado", "programas instalados"),
                        plural(
                            summary.configurations_succeeded,
                            "configuração restaurada",
                            "configurações restauradas"
                        ),
                        plural(summary.extras_succeeded, "item", "itens")
                    )];
                    if summary.cancelled {
                        lines.push("Cancelado: o que já tinha sido copiado fica; a cópia anterior de cada arquivo foi preservada.".into());
                    }
                    lines.extend(summary.warnings.iter().map(|w| format!("Aviso: {w}")));
                    lines.extend(summary.failures.iter().map(|f| format!("Falha: {f}")));
                    self.restore_job.running = false;
                    self.restore_job.fraction = 1.;
                    self.restore_job.outcome = Some((ok, lines));
                }
                Msg::InstallDone(results) => {
                    let failed: Vec<String> = results
                        .iter()
                        .filter(|r| r.state == InstallState::Failed)
                        .map(|r| format!("{}: {}", r.app.name, r.message))
                        .collect();
                    let ok_count = results.len() - failed.len();
                    let mut lines = vec![format!("{ok_count} de {} instalados.", results.len())];
                    lines.extend(failed.iter().map(|f| format!("Falha: {f}")));
                    self.install_job.running = false;
                    self.install_job.fraction = 1.;
                    self.install_job.outcome = Some((failed.is_empty(), lines));
                }
                Msg::PcReady(diag) => {
                    self.pc = Some(diag);
                    self.refresh_level_plans();
                }
                Msg::EnvReady(det, amb) => {
                    self.env_detected = Some((det, amb));
                    self.refresh_level_plans();
                }
                Msg::AppsLoaded(map) => {
                    self.apps_loading = false;
                    self.app_states = Some(map);
                }
                Msg::DevicesLoaded(result) => {
                    self.devices_loading = false;
                    self.devices_state = Some(result);
                }
                Msg::PowerDone { result, diario, was_undo } => {
                    self.power_busy = false;
                    self.diario = diario;
                    match result {
                        Ok(avisos) => {
                            self.power_warnings = avisos;
                            self.power_feedback = Some(Ok(if was_undo {
                                "Plano anterior restaurado e plano Vanta removido.".to_owned()
                            } else {
                                "Opções de energia aplicadas e registradas no diário.".to_owned()
                            }));
                        }
                        Err(err) => {
                            self.power_feedback = Some(Err(err));
                        }
                    }
                }
                Msg::AppActionDone { chave, is_remove, result, diario, new_state } => {
                    self.app_busy = None;
                    self.diario = diario;
                    self.app_states.get_or_insert_with(HashMap::new).insert(chave.clone(), new_state);
                    self.app_feedback = Some(match result {
                        Ok(()) => Ok(if is_remove {
                            format!("{chave}: removido para o usuário atual e anotado no diário.")
                        } else {
                            format!("{chave}: reinstalação concluída.")
                        }),
                        Err(err) => Err(format!("{chave}: {err}")),
                    });
                }
                Msg::DeviceActionDone { instance_id, is_disable, result, diario } => {
                    self.device_busy = None;
                    self.diario = diario;
                    self.device_feedback = Some(match result {
                        Ok(()) => Ok(if is_disable {
                            format!("Dispositivo {instance_id} desligado e anotado no diário.")
                        } else {
                            format!("Dispositivo {instance_id} religado.")
                        }),
                        Err(err) => Err(format!("{instance_id}: {err}")),
                    });
                    self.devices_state = None;
                    self.load_devices_in_background();
                }
            }
        }
        if changed {
            cx.notify();
        }
    }

    fn start_install(&mut self, cx: &mut Context<Self>) {
        if self.install_job.running {
            return;
        }
        let mut indexes: Vec<usize> = self.selected.iter().copied().collect();
        indexes.sort_unstable();
        let apps: Vec<SoftwareApp> = indexes.iter().map(|&i| self.apps[i].clone()).collect();
        if apps.is_empty() {
            return;
        }
        let vencord = self.install_vencord && apps.iter().any(is_discord);
        self.install_job.start();
        self.install_job.current = "Um pedido de administrador para o lote inteiro".into();
        let (tx, cancel) = (self.tx.clone(), self.install_job.cancel.clone());
        std::thread::spawn(move || {
            let sender = tx.clone();
            let installer = ElevatedInstaller {
                progress: Arc::new(move |p| drop(sender.send(Msg::Progress(p)))),
                cancel,
            };
            let results = install_apps_batch_with(&apps, &installer, vencord);
            let _ = tx.send(Msg::InstallDone(results));
        });
        cx.notify();
    }

    fn start_restore(&mut self, cx: &mut Context<Self>) {
        let KitState::Ready(kit) = &self.kit else { return };
        if self.restore_job.running || !kit.guard.is_clean() {
            return;
        }
        let (manifest, ctx) = (kit.loaded.manifest.clone(), kit.ctx.clone());
        let options = RestoreOptions {
            install_applications: self.restore_apps,
            restore_configurations: self.restore_config,
            elevate_protected: true,
            install_nvidia_driver: self.nvidia != NvidiaChoice::Skip,
        };
        let (nvidia, catalog) = (self.nvidia, self.apps.clone());
        self.restore_job.start();
        self.restore_job.current = "Preparando…".into();
        let (tx, cancel) = (self.tx.clone(), self.restore_job.cancel.clone());
        let dir = log_dir();
        std::thread::spawn(move || {
            let stamp = chrono::Local::now().format("%Y%m%d_%H%M%S");
            let _ = std::fs::create_dir_all(&dir);
            let mut file = std::fs::OpenOptions::new()
                .create(true)
                .append(true)
                .open(dir.join(format!("restore_{stamp}.log")))
                .ok();
            let mut write = move |line: &str| {
                if let Some(f) = file.as_mut() {
                    let _ = writeln!(f, "{} {line}", chrono::Local::now().format("%H:%M:%S"));
                }
            };
            write(&format!("Vanta Tools: restaurando de {} (elevado: {})", ctx.kit_root, ctx.is_elevated));
            let (ptx, ltx) = (tx.clone(), tx.clone());
            let mut progress = |p: &Progress| drop(ptx.send(Msg::Progress(p.clone())));
            let mut log = |line: &str| {
                write(line);
                let _ = ltx.send(Msg::Log(line.to_owned()));
            };
            let summary = execute_restore(
                &manifest,
                &ctx,
                &options,
                nvidia,
                &catalog,
                &cancel,
                &mut Hooks { progress: &mut progress, log: &mut log },
            );
            let _ = tx.send(Msg::RestoreDone(Box::new(summary)));
        });
        cx.notify();
    }

    fn is_tweak_locked(&self, index: usize) -> bool {
        let t = &self.tweaks[index];
        t.locked && !(t.id == VBS_HVCI_ID && self.core_isolation_unlocked)
    }

    fn toggle_tweak(&mut self, index: usize, cx: &mut Context<Self>) {
        if self.is_tweak_locked(index) {
            return;
        }
        let enable = self.states[index] != TweakState::On;
        self.apply_tweak_value(index, enable, cx);
    }

    fn apply_tweak_value(&mut self, index: usize, enable: bool, cx: &mut Context<Self>) {
        let mut tweak = self.tweaks[index].clone();
        // F3: a trava do `vbs-hvci` é controlada pela caixa de confirmação do Valorant na interface
        // (ou religada automaticamente quando o usuário desmarca a caixa).
        if tweak.id == VBS_HVCI_ID && (self.core_isolation_unlocked || enable) {
            tweak.locked = false;
        }
        let (det, amb) = self.deteccao_e_ambiente();
        let mut store = RegistryStore::new();
        let result = vanta_core::niveis::aplicar_ajuste(&mut store, &tweak, enable, &det, &amb);
        let errors = store.take_errors();
        let format_err = |error: &TweakError| match error {
            TweakError::NotEligible(reason) => format!("Não aplicável neste PC: {reason}."),
            TweakError::ServiceAccess(service) => {
                format!("O Windows negou o acesso ao serviço {service} (abra como administrador).")
            }
            other => other.to_string(),
        };
        let problem = match (&result, errors.is_empty()) {
            (Err(error), _) => Some(format_err(error)),
            (Ok(_), false) => Some("o Windows negou o acesso (precisa de administrador)".to_owned()),
            (Ok(_), true) => None,
        };
        match problem {
            Some(message) => drop(self.row_errors.insert(index, message)),
            None => drop(self.row_errors.remove(&index)),
        }
        match (&result, errors.is_empty()) {
            (Err(error), _) => self.set_page_notice(NoticeKind::Error, format_err(error)),
            (Ok(_), false) => self.set_page_notice(
                NoticeKind::Error,
                format!(
                    "Este ajuste precisa de administrador ({}). Reabra o Vanta Tools como administrador para aplicar.",
                    errors[0]
                ),
            ),
            (Ok(applied), true) => {
                if let Some(note) = applied.note.as_deref() {
                    self.set_page_notice(NoticeKind::Info, note);
                } else {
                    self.notice = None;
                }
            }
        }
        self.refresh_states();
        cx.notify();
    }

    /// "Aplicar padrão Vanta": liga, depois de confirmar, os ajustes da área que estão fora do padrão.
    fn apply_area_defaults(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        let target_area = self.area.clone();
        let pending: Vec<usize> = (0..self.tweaks.len())
            .filter(|&i| {
                self.tweaks[i].category == target_area
                    && !self.tweaks[i].locked
                    && self.states[i] != TweakState::On
            })
            .collect();
        if pending.is_empty() {
            return;
        }
        let detail = format!(
            "Liga {} desta página que {} fora do padrão Vanta. Os que mexem no sistema pedem administrador.",
            plural(pending.len(), "ajuste", "ajustes"),
            if pending.len() == 1 { "está" } else { "estão" }
        );
        let answer = window.prompt(
            PromptLevel::Info,
            "Aplicar o padrão Vanta?",
            Some(&detail),
            &["Aplicar", "Cancelar"],
            cx,
        );
        cx.spawn_in(window, async move |this, cx| {
            if let Ok(0) = answer.await {
                this.update(cx, |this, cx| {
                    let mut failed = 0usize;
                    let mut last_error: Option<String> = None;
                    let mut info_notes: Vec<String> = Vec::new();
                    for i in pending {
                        if this.states[i] != TweakState::On {
                            this.toggle_tweak(i, cx);
                            if let Some(msg) = this.row_errors.get(&i) {
                                failed += 1;
                                last_error = Some(msg.clone());
                            } else if let Some(notice) = &this.notice
                                && notice.kind == NoticeKind::Info
                                && !info_notes.contains(&notice.message)
                            {
                                info_notes.push(notice.message.clone());
                            }
                        }
                    }
                    let next_notice = if failed == 1 {
                        last_error.map(|message| (NoticeKind::Error, message))
                    } else if failed > 1 {
                        Some((
                            NoticeKind::Error,
                            format!(
                                "{failed} ajustes desta área não foram aplicados neste PC (veja o motivo em cada linha)."
                            ),
                        ))
                    } else if !info_notes.is_empty() {
                        Some((NoticeKind::Info, info_notes.join(" ")))
                    } else {
                        None
                    };
                    this.notice = next_notice.map(|(kind, message)| PageNotice {
                        page: Page::Settings,
                        area: Some(target_area.clone()),
                        kind,
                        message,
                    });
                    cx.notify();
                })
                .ok();
            }
        })
        .detach();
    }

    /// (ligados, total) por área, na ordem do Vanta 1.
    fn areas(&self) -> Vec<(String, (usize, usize))> {
        let mut map: HashMap<String, (usize, usize)> = HashMap::new();
        for (tweak, state) in self.tweaks.iter().zip(&self.states) {
            let entry = map.entry(tweak.category.clone()).or_default();
            entry.1 += 1;
            if *state == TweakState::On {
                entry.0 += 1;
            }
        }
        let mut list: Vec<_> = map.into_iter().collect();
        list.sort_by_key(|(category, _)| area_rank(category));
        list
    }

    // ---------- casca ----------

    #[allow(clippy::too_many_arguments)]
    fn nav_item(
        &self,
        id: &'static str,
        label: &str,
        code: &'static str,
        active: bool,
        trailing: Option<String>,
        focus: FocusHandle,
        go: impl Fn(&mut Self) + 'static,
        cx: &mut Context<Self>,
    ) -> gpui::Stateful<gpui::Div> {
        div()
            .id(id)
            .role(Role::Tab)
            .aria_label(label.to_owned())
            .aria_selected(active)
            .track_focus(&focus.tab_index(0).tab_stop(true))
            .relative()
            .h(px(36.))
            .pl(px(12.))
            .pr(px(26.))
            .rounded(px(6.))
            .flex()
            .items_center()
            .gap(px(16.))
            .cursor_pointer()
            .text_color(if active { c(INK) } else { c(INK_MUTED) })
            .when(active, |d| {
                d.bg(c(SURFACE2)).child(
                    div()
                        .absolute()
                        .left(px(0.))
                        .top(px(10.))
                        .w(px(3.))
                        .h(px(16.))
                        .rounded(px(2.))
                        .bg(c(ACCENT_HOVER)),
                )
            })
            .when(!active, |d| d.hover(|s| s.bg(a(0x1B1824B3)).text_color(c(INK))))
            .focus_visible(|s| focus_ring(s, c(0xA78BFE), c(CANVAS)))
            .child(kit::glyph(code, 16.))
            .child(div().flex_1().font_family(FONT_TEXT).text_size(px(14.)).child(label.to_owned()))
            .when_some(trailing, |d, text| {
                d.child(div().font_family(FONT_TEXT).text_size(px(12.)).text_color(c(INK_SUBTLE)).child(text))
            })
            .on_click(cx.listener(move |this, _, _, cx| {
                go(this);
                cx.notify();
            }))
    }

    /// Página com rolagem e as margens do Vanta 1 (56 nas laterais, 36 em cima). `overlay` fica por cima da
    /// rolagem (a barra flutuante de Programas).
    pub(super) fn page_scroll(
        &self,
        page: Page,
        body: AnyElement,
        bottom: f32,
        overlay: Option<AnyElement>,
    ) -> AnyElement {
        let index = page.index();
        div()
            .flex_1()
            .min_w_0()
            .relative()
            .child(
                div()
                    .id(("page-scroll", index))
                    .size_full()
                    .overflow_y_scroll()
                    .track_scroll(&self.scrolls[index])
                    .child(
                        div()
                            .w_full()
                            .min_w_0()
                            .max_w(px(PAGE_MAX))
                            .pl(px(PAGE_X))
                            .pr(px(PAGE_X))
                            .pt(px(PAGE_TOP))
                            .pb(px(bottom))
                            .child(body),
                    ),
            )
            .child(scrollbar(&self.scrolls[index], &self.bars[index]))
            .children(overlay)
            .into_any_element()
    }

    /// Campo de busca do Vanta 1: fundo translúcido, lupa à esquerda, raio 8 px e borda roxa no foco.
    fn search_field(
        &self,
        input: &Entity<TextInput>,
        width: f32,
        window: &Window,
        cx: &Context<Self>,
    ) -> gpui::Div {
        let focused = input.read(cx).focus_handle(cx).is_focused(window);
        div()
            .w(px(width))
            .h(px(36.))
            .px(px(12.))
            .flex()
            .flex_shrink_0()
            .items_center()
            .gap(px(8.))
            .rounded(px(8.))
            .bg(a(SURFACE1))
            .border_1()
            .border_color(if focused { c(ACCENT) } else { c(HAIRLINE) })
            .when(!focused, |d| d.hover(|s| s.border_color(c(HAIRLINE_STRONG))))
            .child(kit::glyph("\u{E721}", 13.).text_color(c(INK_SUBTLE)))
            .child(div().flex_1().min_w_0().child(input.clone()))
    }

    pub(super) fn header(&self, title: &str, lead: &str) -> gpui::Div {
        div()
            .flex()
            .flex_col()
            .gap(px(10.))
            .child(kit::page_title(title.to_owned()))
            .child(kit::lead(lead.to_owned()))
    }

    fn notice_bar(&self, cx: &mut Context<Self>) -> Option<AnyElement> {
        let notice = self.current_page_notice(Page::Settings)?;
        let message = notice.message.clone();
        match notice.kind {
            NoticeKind::Info => {
                Some(InfoBar::new(Severity::Informational, "Informação", message).into_any_element())
            }
            NoticeKind::Error => {
                let elevated = self.elevated;
                Some(
                    InfoBar::new(Severity::Warning, "Não foi possível aplicar", message)
                        .action(
                            crate::ui::Button::new("reopen-admin", "Reabrir como administrador")
                                .disabled(elevated)
                                .on_click(cx.listener(|_, _, _, cx| {
                                    let args: Vec<String> = std::env::args().skip(1).collect();
                                    let relaunched = std::env::current_exe()
                                        .and_then(|exe| vanta_sys::elevate::relaunch_as_admin(&exe, &args));
                                    if relaunched.is_ok() {
                                        cx.quit();
                                    }
                                })),
                        )
                        .into_any_element(),
                )
            }
        }
    }

    fn outcome_bar(job: &Job) -> Option<AnyElement> {
        let (ok, lines) = job.outcome.as_ref()?;
        let (first, rest) = lines.split_first()?;
        Some(
            InfoBar::new(
                if *ok { Severity::Success } else { Severity::Warning },
                first.clone(),
                rest.join("\n"),
            )
            .into_any_element(),
        )
    }

    // ---------- Início ----------

    fn home(&mut self, cx: &mut Context<Self>) -> AnyElement {
        let hour: u32 = chrono::Timelike::hour(&chrono::Local::now());
        let greeting = match hour {
            5..=11 => "Bom dia",
            12..=17 => "Boa tarde",
            _ => "Boa noite",
        };
        // O Vanta 1 cumprimenta pelo primeiro nome.
        let user = std::env::var("USERNAME").unwrap_or_default();
        let first_name = user.split_whitespace().next().unwrap_or("").to_owned();
        let areas = self.areas();
        let (on, total) = areas.iter().fold((0, 0), |acc, (_, v)| (acc.0 + v.0, acc.1 + v.1));
        let strong = format!("{on} de {total} ajustes");
        let has_restore = data::edicao().has_restore();
        let kit_tail = if !has_restore {
            String::new()
        } else {
            match &self.kit {
                KitState::Ready(kit) => {
                    format!(
                        " O pacote de restauração tem {} prontas.",
                        plural(kit.loaded.manifest.items.len(), "configuração", "configurações")
                    )
                }
                KitState::Invalid(_) => " O pacote de restauração tem um problema.".into(),
                KitState::Missing => " Conecte o disco do pacote para restaurar.".into(),
            }
        };
        let head = "O padrão Vanta está aplicado em ";
        let sentence = format!("{head}{strong}.{kit_tail}");
        let bold = HighlightStyle {
            color: Some(c(INK)),
            font_weight: Some(FontWeight::SEMIBOLD),
            ..Default::default()
        };
        let state_line = div()
            .font_family(FONT_TEXT)
            .text_size(px(16.))
            .line_height(px(25.))
            .text_color(c(INK_MUTED))
            .max_w(px(540.))
            .child(
                StyledText::new(sentence).with_highlights([(head.len()..head.len() + strong.len(), bold)]),
            );
        let kit_path = if has_restore {
            match &self.kit {
                KitState::Ready(kit) => Some(kit.path.clone()),
                _ => None,
            }
        } else {
            None
        };

        let hero = div()
            .flex()
            .flex_col()
            .gap(px(16.))
            .max_w(px(540.))
            .child(kit::hero(format!("{greeting}, {first_name}.")))
            .child(div().flex().flex_col().gap(px(10.)).child(state_line).when_some(
                kit_path.clone(),
                |d, path| {
                    d.child(
                        div()
                            .flex()
                            .items_center()
                            .gap(px(8.))
                            .text_color(c(INK_SUBTLE))
                            .child(kit::glyph("\u{E8B7}", 13.))
                            .child(kit::mono(path, 13.)),
                    )
                },
            ))
            .child(
                div()
                    .flex()
                    .gap(px(10.))
                    .mt(px(8.))
                    .when(has_restore, |d| {
                        d.child(
                            kit::button(
                                "home-restore",
                                "Restaurar meu PC",
                                Kind::Primary,
                                Some("\u{E777}"),
                                false,
                            )
                            .on_click(cx.listener(|this, _, _, cx| {
                                this.go_page(Page::Restore);
                                cx.notify();
                            })),
                        )
                    })
                    .child(
                        kit::button(
                            "home-optimize",
                            "Otimizar Windows",
                            if has_restore { Kind::Secondary } else { Kind::Primary },
                            Some("\u{E945}"),
                            false,
                        )
                        .on_click(cx.listener(|this, _, _, cx| {
                            this.go_page(Page::Optimize);
                            cx.notify();
                        })),
                    )
                    .child(
                        kit::button(
                            "home-programs",
                            "Escolher programas",
                            Kind::Secondary,
                            Some("\u{E719}"),
                            false,
                        )
                        .on_click(cx.listener(|this, _, _, cx| {
                            this.go_page(Page::Programs);
                            cx.notify();
                        })),
                    )
                    .when_some(kit_path, |d, path| {
                        d.child(
                            kit::button(
                                "home-open-kit",
                                "Abrir pacote",
                                Kind::Ghost,
                                Some("\u{E838}"),
                                false,
                            )
                            .on_click(move |_, _, _| open_in_explorer(&path)),
                        )
                    }),
            );

        // Este PC: alimentado em segundo plano por `read_pc_in_background`.
        let checks = build_pc_checks(self.pc.as_ref(), &self.kit, has_restore);
        let row_total = checks.len();
        let ok_count = checks.iter().filter(|item| item.level == CheckLevel::Ok).count();
        let pc_caption = if self.pc.is_none() {
            "lendo…".to_owned()
        } else {
            format!("{ok_count} de {row_total} em ordem")
        };
        let mut rows: Vec<AnyElement> = Vec::with_capacity(row_total * 2);
        for (i, check) in checks.into_iter().enumerate() {
            let first = i == 0;
            let last = i + 1 == row_total;
            if !first {
                rows.push(div().h(px(1.)).mx(px(20.)).bg(c(HAIRLINE)).into_any_element());
            }
            if matches!(check.level, CheckLevel::Bad | CheckLevel::Warn) {
                let icon_color = if check.level == CheckLevel::Bad { c(ERR) } else { c(WARN) };
                let fix_button = check.fix.map(|fix| {
                    let btn = kit::button(
                        format!("home-fix-{}", check.id),
                        "Verificar",
                        Kind::Secondary,
                        None,
                        false,
                    )
                    .self_center();
                    match fix {
                        CheckFix::PowerPlan => btn.on_click(|_, _, _| open_in_explorer("powercfg.cpl")),
                        CheckFix::CoreIsolation => {
                            btn.on_click(|_, _, _| open_in_explorer("windowsdefender://coreisolation"))
                        }
                        CheckFix::DisplayRate => {
                            btn.on_click(|_, _, _| open_in_explorer("ms-settings:display-advanced"))
                        }
                        CheckFix::RestorePage => btn.on_click(cx.listener(|this, _, _, cx| {
                            this.go_page(Page::Restore);
                            cx.notify();
                        })),
                    }
                });
                rows.push(
                    div()
                        .flex()
                        .items_start()
                        .gap(px(14.))
                        .pl(px(20.))
                        .pr(px(16.))
                        .py(px(16.))
                        .bg(a(0xFBBF2414))
                        .when(first, |d| d.rounded_t(px(11.)))
                        .when(last, |d| d.rounded_b(px(11.)))
                        .child(kit::glyph("\u{E7BA}", 16.).text_color(icon_color).mt(px(2.)))
                        .child(
                            div()
                                .flex_1()
                                .min_w_0()
                                .flex()
                                .flex_col()
                                .gap(px(3.))
                                .child(
                                    div()
                                        .flex()
                                        .items_baseline()
                                        .flex_wrap()
                                        .gap(px(8.))
                                        .child(
                                            div()
                                                .font_family(FONT_TEXT)
                                                .font_weight(FontWeight::SEMIBOLD)
                                                .text_size(px(14.5))
                                                .text_color(c(INK))
                                                .child(check.label),
                                        )
                                        .child(
                                            div()
                                                .font_family(if check.mono { FONT_MONO } else { FONT_TEXT })
                                                .text_size(px(if check.mono { 13. } else { 14. }))
                                                .text_color(c(INK_MUTED))
                                                .child(check.value),
                                        ),
                                )
                                .when_some(check.problem, |d, text| {
                                    d.child(kit::body(text).text_color(c(INK_MUTED)))
                                }),
                        )
                        .when_some(fix_button, |d, btn| d.child(btn))
                        .into_any_element(),
                );
            } else {
                let value_el = match check.level {
                    CheckLevel::Ok if check.mono => {
                        kit::mono(check.value, 13.5).text_color(c(INK)).into_any_element()
                    }
                    CheckLevel::Ok => div()
                        .font_family(FONT_TEXT)
                        .font_weight(FontWeight::SEMIBOLD)
                        .text_size(px(14.))
                        .text_color(c(INK))
                        .child(check.value)
                        .into_any_element(),
                    CheckLevel::Loading | CheckLevel::Unknown => div()
                        .font_family(FONT_TEXT)
                        .text_size(px(13.5))
                        .text_color(c(INK_SUBTLE))
                        .child(check.value)
                        .into_any_element(),
                    CheckLevel::Warn | CheckLevel::Bad => unreachable!(),
                };
                let status_el = match check.level {
                    CheckLevel::Ok => div()
                        .flex()
                        .items_center()
                        .gap(px(6.))
                        .child(kit::glyph("\u{E73E}", 11.).text_color(c(OK)))
                        .child(kit::caption("Certo"))
                        .into_any_element(),
                    CheckLevel::Loading => div()
                        .flex()
                        .items_center()
                        .gap(px(6.))
                        .child(kit::glyph("\u{E823}", 11.).text_color(c(INK_FAINT)))
                        .into_any_element(),
                    CheckLevel::Unknown => div()
                        .flex()
                        .items_center()
                        .gap(px(6.))
                        .child(kit::glyph("\u{E9CE}", 11.).text_color(c(INK_SUBTLE)))
                        .child(kit::caption("Sem leitura"))
                        .into_any_element(),
                    CheckLevel::Warn | CheckLevel::Bad => unreachable!(),
                };
                rows.push(
                    div()
                        .flex()
                        .items_center()
                        .gap(px(16.))
                        .px(px(20.))
                        .h(px(49.))
                        .when(first, |d| d.rounded_t(px(11.)))
                        .when(last, |d| d.rounded_b(px(11.)))
                        .hover(|s| s.bg(a(0x1B182499)))
                        .child(
                            div()
                                .flex_1()
                                .font_family(FONT_TEXT)
                                .text_size(px(14.))
                                .text_color(c(INK_MUTED))
                                .child(check.label),
                        )
                        .child(value_el)
                        .child(div().w(px(104.)).flex().justify_end().child(status_el))
                        .into_any_element(),
                );
            }
        }

        let missing: usize = areas.iter().map(|(_, (on, total))| total - on).sum();
        let area_rows: Vec<AnyElement> = areas
            .iter()
            .map(|(category, (on, total))| {
                let (category, on, total) = (category.clone(), *on, *total);
                let id: gpui::SharedString = format!("home-area-{category}").into();
                let target = category.clone();
                div()
                    .id(id)
                    .role(Role::Link)
                    .aria_label(area_name(&category))
                    .tab_index(0)
                    .flex()
                    .flex_col()
                    .gap(px(10.))
                    .px(px(14.))
                    .py(px(12.))
                    .rounded(px(8.))
                    .cursor_pointer()
                    .hover(|s| s.bg(a(0x1B1824B3)))
                    .focus_visible(|s| focus_ring(s, c(0xA78BFE), c(CANVAS)))
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .gap(px(10.))
                            .child(kit::row_title(area_name(&category)).flex_1())
                            .when(on < total, |d| d.child(kit::caption(format!("faltam {}", total - on))))
                            .child(kit::mono(format!("{on}/{total}"), 13.).text_color(c(INK)))
                            .child(kit::glyph("\u{E76C}", 10.).text_color(c(INK_SUBTLE))),
                    )
                    .child(kit::meter(on as f32 / total.max(1) as f32, None))
                    .on_click(cx.listener(move |this, _, _, cx| {
                        this.go_settings(&target);
                        cx.notify();
                    }))
                    .into_any_element()
            })
            .collect();

        let section_head = |title: &str, note: String| {
            div()
                .flex()
                .items_center()
                .justify_between()
                .child(kit::section_title(title.to_owned()))
                .child(kit::caption(note))
        };
        let columns = div()
            .flex()
            .flex_wrap()
            .items_start()
            .gap(px(20.))
            .mt(px(38.))
            .child(
                div()
                    .flex_grow(7.)
                    .flex_shrink(1.)
                    .flex_basis(px(420.))
                    .min_w(px(360.))
                    .flex()
                    .flex_col()
                    .gap(px(12.))
                    .child(section_head("Este PC", pc_caption))
                    .child(kit::panel().w_full().min_w_0().children(rows)),
            )
            .child(
                div()
                    .flex_grow(5.)
                    .flex_shrink(1.)
                    .flex_basis(px(300.))
                    .min_w(px(280.))
                    .max_w(px(420.))
                    .flex()
                    .flex_col()
                    .gap(px(12.))
                    .child(section_head("Padrão Vanta por área", format!("{missing} fora do padrão")))
                    .child(kit::panel().w_full().min_w_0().p(px(6.)).children(area_rows)),
            );
        let body = div().pt(px(18.)).flex().flex_col().child(hero).child(columns).into_any_element();
        self.page_scroll(Page::Home, body, 28., None)
    }

    // ---------- Programas ----------

    fn chip(&self, i: usize, label: &str, active: bool, focus: FocusHandle) -> gpui::Stateful<gpui::Div> {
        div()
            .id(("chip", i))
            .role(Role::RadioButton)
            .aria_label(label.to_owned())
            .aria_selected(active)
            .track_focus(&focus.tab_index(0).tab_stop(true))
            .h(px(34.))
            .px(px(14.))
            .flex()
            .items_center()
            .rounded(px(17.))
            .border_1()
            .border_color(if active { c(0x575070) } else { c(0x2E2A3A) })
            .bg(if active { c(0x2B2739) } else { a(0x120F18E6) })
            .text_color(if active { c(INK) } else { c(0xC9C5D6) })
            .font_family(FONT_TEXT)
            .font_weight(FontWeight::MEDIUM)
            .text_size(px(13.5))
            .whitespace_nowrap()
            .cursor_pointer()
            .when(!active, |d| d.hover(|s| s.border_color(c(0x443E58)).text_color(c(INK))))
            .focus_visible(|s| focus_ring(s, c(0xA78BFA), c(CANVAS)))
            .child(label.to_owned())
    }

    fn program_card(&self, i: usize, width: f32, cx: &mut Context<Self>) -> AnyElement {
        let app = &self.apps[i];
        let on = self.selected.contains(&i);
        let installable = app.is_installable();
        let busy = self.install_job.running;
        let note = data::app_description(&self.texts, app).unwrap_or_default().to_owned();
        let letter: String =
            app.name.chars().next().map(|ch| ch.to_uppercase().collect()).unwrap_or_default();
        let tile = div()
            .size(px(40.))
            .flex_shrink_0()
            .flex()
            .items_center()
            .justify_center()
            .rounded(px(10.))
            .bg(c(SURFACE2))
            .border_1()
            .border_color(c(HAIRLINE))
            .map(|d| match kit::logo(&app.name, 20.) {
                Some(logo) => d.child(logo),
                None => d.child(
                    div()
                        .font_family(FONT_DISPLAY)
                        .font_weight(FontWeight::MEDIUM)
                        .text_size(px(17.))
                        .text_color(c(INK_MUTED))
                        .child(letter),
                ),
            });
        let discord = is_discord(app);
        let mut badges: Vec<AnyElement> = Vec::new();
        if !installable {
            if data::edicao().shows_package_origin() {
                badges.push(kit::badge("\u{E8B7}", "Vem do pacote").into_any_element());
            }
        } else if app.interactive {
            badges.push(kit::badge("\u{E8B0}", "Pede cliques").into_any_element());
        }
        if let Some(extra) = app.extra.clone().filter(|e| !e.is_empty()) {
            badges.push(kit::badge("\u{E710}", extra).into_any_element());
        }
        let (bg, border, hover_bg, hover_border) = if on {
            (a(0x7C4EE01A), c(ACCENT), a(0x7C4EE026), c(ACCENT))
        } else {
            (a(SURFACE1), c(HAIRLINE), c(SURFACE2), c(HAIRLINE_STRONG))
        };
        let name = app.name.clone();
        let card = div()
            .id(("app", i))
            .w(px(width))
            .h(px(116.))
            .p(px(14.))
            .pl(px(16.))
            .rounded(px(12.))
            .border_1()
            .border_color(border)
            .bg(bg)
            .flex()
            .flex_col()
            .when(installable, |d| {
                d.role(Role::CheckBox)
                    .aria_label(name.clone())
                    .aria_toggled(if on { Toggled::True } else { Toggled::False })
                    .tab_index(0)
                    .cursor_pointer()
                    .hover(move |s| s.bg(hover_bg).border_color(hover_border))
                    .focus_visible(|s| focus_ring(s, c(0xA78BFE), c(CANVAS)))
                    .on_click(cx.listener(move |this, _, _, cx| {
                        if busy {
                            return;
                        }
                        if this.selected.remove(&i) {
                            if discord {
                                this.install_vencord = false;
                            }
                        } else {
                            this.selected.insert(i);
                        }
                        cx.notify();
                    }))
            })
            .child(
                div()
                    .flex()
                    .items_start()
                    .gap(px(14.))
                    .child(tile)
                    .child(
                        div()
                            .flex_1()
                            .min_w_0()
                            .flex()
                            .flex_col()
                            .gap(px(3.))
                            .child(kit::row_title(app.name.clone()).truncate())
                            .child(
                                div()
                                    .font_family(FONT_TEXT)
                                    .text_size(px(13.))
                                    .line_height(px(18.))
                                    .text_color(c(INK_MUTED))
                                    .line_clamp(2)
                                    .text_ellipsis()
                                    .child(note),
                            ),
                    )
                    .when(installable, |d| d.child(kit::check_box(on, false))),
            )
            .child(div().flex_1())
            .child(div().pl(px(54.)).flex().gap(px(14.)).children(badges));

        if discord && on {
            let vencord_on = self.install_vencord;
            let vencord_note = self
                .texts
                .programs
                .get("Vencord")
                .cloned()
                .unwrap_or_else(|| {
                    "Mod do Discord com temas e plugins. Não é oficial e vai contra os termos do Discord; use por sua conta."
                        .to_owned()
                });
            let (v_bg, v_border) = if vencord_on {
                (a(0x7C4EE014), c(ACCENT))
            } else {
                (a(SURFACE1), c(HAIRLINE))
            };
            let vencord_box = div()
                .id("app-vencord-extra")
                .role(Role::CheckBox)
                .aria_label("Instalar Vencord junto")
                .aria_toggled(if vencord_on { Toggled::True } else { Toggled::False })
                .tab_index(0)
                .cursor_pointer()
                .w(px(width))
                .px(px(14.))
                .py(px(10.))
                .rounded(px(10.))
                .border_1()
                .border_color(v_border)
                .bg(v_bg)
                .hover(|s| s.bg(c(SURFACE2)).border_color(c(HAIRLINE_STRONG)))
                .focus_visible(|s| focus_ring(s, c(0xA78BFE), c(CANVAS)))
                .on_click(cx.listener(move |this, _, _, cx| {
                    if busy {
                        return;
                    }
                    this.install_vencord = !this.install_vencord;
                    cx.notify();
                }))
                .on_key_down(cx.listener(move |this, event: &KeyDownEvent, _, cx| {
                    if !busy && matches!(event.keystroke.key.as_str(), "enter" | "space") {
                        this.install_vencord = !this.install_vencord;
                        cx.notify();
                    }
                }))
                .flex()
                .items_start()
                .gap(px(10.))
                .child(div().pt(px(2.)).child(kit::check_box(vencord_on, busy)))
                .child(
                    div()
                        .flex_1()
                        .min_w_0()
                        .flex()
                        .flex_col()
                        .gap(px(2.))
                        .child(
                            div()
                                .font_family(FONT_TEXT)
                                .font_weight(FontWeight::MEDIUM)
                                .text_size(px(13.5))
                                .text_color(c(INK))
                                .child("Instalar Vencord junto"),
                        )
                        .child(
                            div()
                                .font_family(FONT_TEXT)
                                .text_size(px(12.))
                                .line_height(px(17.))
                                .text_color(c(INK_MUTED))
                                .child(vencord_note),
                        ),
                );
            div()
                .w(px(width))
                .flex()
                .flex_col()
                .gap(px(8.))
                .child(card)
                .child(vencord_box)
                .into_any_element()
        } else {
            card.into_any_element()
        }
    }

    fn programs(&mut self, window: &Window, cx: &mut Context<Self>) -> AnyElement {
        let chip_names: Vec<Option<&'static str>> = std::iter::once(None)
            .chain(
                PROGRAM_CHIPS
                    .iter()
                    .copied()
                    .filter(|chip| self.catalog.categories.iter().any(|cat| program_chip(&cat.name) == *chip))
                    .map(Some),
            )
            .collect();
        let chip_focus: Vec<FocusHandle> =
            (0..chip_names.len()).map(|i| self.focus.get(&format!("chip-{i}"), cx)).collect();
        let chips: Vec<AnyElement> = chip_names
            .into_iter()
            .zip(chip_focus)
            .enumerate()
            .map(|(i, (name, focus))| {
                let active = self.category.as_deref() == name;
                self.chip(i, name.unwrap_or("Todos"), active, focus)
                    .on_click(cx.listener(move |this, _, _, cx| {
                        this.category = name.map(str::to_owned);
                        cx.notify();
                    }))
                    .into_any_element()
            })
            .collect();

        // Grade do Vanta 1: cartão de no mínimo 280 px, 12 de vão, colunas que enchem a largura.
        let width = self.content_w;
        let cols = (((width + 12.) / (280. + 12.)).floor() as usize).max(1);
        let card_w = ((width - 12. * (cols as f32 - 1.)) / cols as f32).floor();

        let filter = self.programs_filter.read(cx).value().to_owned();
        let mut sections: Vec<AnyElement> = Vec::new();
        let mut index = 0usize;
        let categories: Vec<(String, usize, usize)> = self
            .catalog
            .categories
            .iter()
            .map(|cat| {
                let first = index;
                index += cat.apps.len();
                (cat.name.clone(), first, index)
            })
            .collect();
        for (name, first, end) in categories {
            if self.category.as_ref().is_some_and(|c| c != program_chip(&name)) {
                continue;
            }
            let shown: Vec<usize> =
                (first..end).filter(|i| name_matches(&self.apps[*i].name, &filter)).collect();
            if shown.is_empty() {
                continue;
            }
            let marked = (first..end).filter(|i| self.selected.contains(i)).count();
            let cards: Vec<AnyElement> = shown.iter().map(|&i| self.program_card(i, card_w, cx)).collect();
            sections.push(
                div()
                    .flex()
                    .flex_col()
                    .gap(px(14.))
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .gap(px(10.))
                            .child(kit::section_title(name.clone()))
                            .child(kit::caption(plural(end - first, "opção", "opções")))
                            .child(div().flex_1())
                            .when(marked > 0, |d| {
                                d.child(kit::caption(plural(marked, "marcado", "marcados")))
                            }),
                    )
                    .child(div().flex().flex_wrap().gap(px(12.)).children(cards))
                    .into_any_element(),
            );
        }
        if sections.is_empty() {
            sections.push(
                div()
                    .pt(px(48.))
                    .flex()
                    .flex_col()
                    .items_center()
                    .gap(px(10.))
                    .child(
                        div()
                            .size(px(56.))
                            .flex()
                            .items_center()
                            .justify_center()
                            .rounded(px(14.))
                            .bg(c(SURFACE2))
                            .border_1()
                            .border_color(c(HAIRLINE))
                            .text_color(c(INK_MUTED))
                            .child(kit::glyph("\u{E721}", 20.)),
                    )
                    .child(kit::section_title(format!("Nenhum programa com “{}”", filter.trim())))
                    .child(
                        kit::body("Confira a grafia ou procure em todas as categorias.")
                            .text_color(c(INK_MUTED)),
                    )
                    .child(
                        kit::button("apps-clear-filter", "Limpar filtro", Kind::Secondary, None, false)
                            .on_click(cx.listener(|this, _, _, cx| {
                                this.programs_filter.update(cx, |input, cx| input.set_value("", cx));
                                this.category = None;
                                cx.notify();
                            })),
                    )
                    .into_any_element(),
            );
        }

        let header = div()
            .flex()
            .flex_wrap()
            .items_end()
            .justify_between()
            .gap(px(24.))
            .child(div().flex_1().min_w(px(380.)).child(self.header(
                "Programas",
                "Escolha os programas que deseja instalar. Cada categoria tem alternativas, e o Vanta instala um por vez pelo winget ou pelo GitHub.",
            )))
            .child(self.search_field(&self.programs_filter, 260., window, cx));
        let mut body = div()
            .flex()
            .flex_col()
            .child(header)
            .child(div().mt(px(28.)).flex().flex_wrap().gap(px(8.)).children(chips));
        if let Some(bar) = Self::outcome_bar(&self.install_job) {
            body = body.child(div().mt(px(16.)).child(bar));
        }
        body = body.child(div().mt(px(32.)).flex().flex_col().gap(px(36.)).children(sections));

        // A barra flutuante do Vanta 1: o único lugar com sombra.
        let count = self.selected.len();
        let job = &self.install_job;
        let status = if job.running && !job.current.is_empty() {
            job.current.clone()
        } else {
            "Instala um por vez pelo winget ou GitHub".into()
        };
        let vencord_active = self.install_vencord
            && self.selected.iter().any(|&i| self.apps.get(i).is_some_and(is_discord));
        let count_line = StyledText::new(format!(
            "{count} {}{}",
            if count == 1 { "programa marcado" } else { "programas marcados" },
            if vencord_active { " (+ Vencord)" } else { "" }
        ))
        .with_highlights([(
            0..count.to_string().len(),
            HighlightStyle { font_weight: Some(FontWeight::SEMIBOLD), ..Default::default() },
        )]);
        let running = job.running;
        let fraction = job.fraction;
        let bar = div()
            .absolute()
            .left(px(PAGE_X))
            .bottom(px(24.))
            .occlude()
            .on_mouse_down(MouseButton::Left, |_, _, cx| cx.stop_propagation())
            .on_mouse_down(MouseButton::Right, |_, _, cx| cx.stop_propagation())
            .flex()
            .items_center()
            .gap(px(6.))
            .pl(px(20.))
            .pr(px(12.))
            .py(px(12.))
            .rounded(px(14.))
            .bg(c(SURFACE3))
            .border_1()
            .border_color(c(HAIRLINE_STRONG))
            .shadow(vec![BoxShadow {
                color: a(0x00000073),
                offset: point(px(0.), px(12.)),
                blur_radius: px(32.),
                spread_radius: px(0.),
                inset: false,
            }])
            .child(
                div()
                    .min_w(px(240.))
                    .mr(px(18.))
                    .flex()
                    .flex_col()
                    .gap(px(4.))
                    .child(
                        div().font_family(FONT_TEXT).text_size(px(14.5)).text_color(c(INK)).child(count_line),
                    )
                    .child(kit::caption(status).max_w(px(320.)).truncate())
                    .when(running, |d| d.child(div().mt(px(4.)).child(kit::meter(fraction, Some(240.))))),
            )
            .child(kit::button("apps-clear", "Limpar", Kind::Ghost, None, running).on_click(cx.listener(
                |this, _, _, cx| {
                    this.selected.clear();
                    this.install_vencord = false;
                    cx.notify();
                },
            )))
            .child(if running {
                kit::button("apps-cancel", "Cancelar", Kind::Secondary, Some("\u{E711}"), false)
                    .on_click(cx.listener(|this, _, _, cx| {
                        this.install_job.cancel.cancel();
                        this.install_job.current = "Cancelando depois do programa atual…".into();
                        cx.notify();
                    }))
                    .into_any_element()
            } else {
                kit::button(
                    "apps-install",
                    if count == 0 { "Instalar".to_owned() } else { format!("Instalar {count}") },
                    Kind::Primary,
                    Some("\u{E896}"),
                    count == 0,
                )
                .on_click(cx.listener(|this, _, _, cx| this.start_install(cx)))
                .into_any_element()
            })
            .into_any_element();
        self.page_scroll(Page::Programs, body.into_any_element(), 140., Some(bar))
    }

    // ---------- Restaurar ----------

    fn restore(&mut self, cx: &mut Context<Self>) -> AnyElement {
        #[derive(Clone, Copy, PartialEq)]
        enum Mark {
            Done,
            Current,
            Todo,
            Error,
        }
        let step =
            |number: &'static str, mark: Mark, last: bool, content: gpui::Div| {
                let circle = div()
                    .size(px(30.))
                    .flex_shrink_0()
                    .flex()
                    .items_center()
                    .justify_center()
                    .rounded(px(15.))
                    .border_1()
                    .border_color(match mark {
                        Mark::Current => c(ACCENT),
                        Mark::Error => c(ERR),
                        _ => c(HAIRLINE_STRONG),
                    })
                    .bg(c(CANVAS))
                    .map(|d| match mark {
                        Mark::Done => d.child(kit::glyph("\u{E73E}", 13.).text_color(c(OK))),
                        Mark::Error => d.child(kit::glyph("\u{E711}", 12.).text_color(c(ERR))),
                        Mark::Current => d.child(
                            div()
                                .font_family(FONT_TEXT)
                                .font_weight(FontWeight::MEDIUM)
                                .text_size(px(13.))
                                .text_color(c(INK))
                                .child(number),
                        ),
                        Mark::Todo => d.child(
                            div()
                                .font_family(FONT_TEXT)
                                .font_weight(FontWeight::MEDIUM)
                                .text_size(px(13.))
                                .text_color(c(INK_SUBTLE))
                                .child(number),
                        ),
                    });
                div()
                    .flex()
                    .gap(px(18.))
                    .child(div().w(px(30.)).flex().flex_col().items_center().child(circle).when(!last, |d| {
                        d.child(div().mt(px(4.)).w(px(1.5)).flex_1().bg(c(HAIRLINE_STRONG)))
                    }))
                    .child(content.flex_1().min_w_0().pt(px(4.)).when(!last, |d| d.pb(px(18.))))
            };
        let busy = self.restore_job.running;
        let ready_clean = matches!(&self.kit, KitState::Ready(k) if k.guard.is_clean());

        // 1 · Pacote
        let (pkg_mark, pkg_content) = match &self.kit {
            KitState::Ready(kit) => {
                let clean = kit.guard.is_clean();
                let path = kit.path.clone();
                let mut col = div()
                    .flex()
                    .flex_col()
                    .gap(px(6.))
                    .child(kit::row_title("Pacote"))
                    .child(kit::mono(kit.path.clone(), 13.).text_color(c(INK)))
                    .child(
                        div()
                            .flex()
                            .items_start()
                            .gap(px(7.))
                            .child(div().pt(px(3.)).child(kit::glyph("\u{E73E}", 12.).text_color(c(OK))))
                            .child(
                                kit::body("Pacote encontrado e manifesto válido.")
                                    .flex_1()
                                    .min_w_0()
                                    .text_color(c(INK_MUTED)),
                            ),
                    )
                    .child(
                        div()
                            .flex()
                            .items_start()
                            .gap(px(7.))
                            .child(
                                div().pt(px(3.)).child(
                                    kit::glyph(if clean { "\u{E73E}" } else { "\u{EA39}" }, 12.)
                                        .text_color(if clean { c(OK) } else { c(ERR) }),
                                ),
                            )
                            .child(
                                kit::body(if clean {
                                    format!(
                                        "Guarda: nada de chave, cookie ou dado de IA em {} conferidas.",
                                        plural(kit.guard.scanned_entries, "entrada", "entradas")
                                    )
                                } else {
                                    format!(
                                        "Guarda: o kit foi recusado ({}).",
                                        plural(kit.guard.violations.len(), "problema", "problemas")
                                    )
                                })
                                .flex_1()
                                .min_w_0()
                                .text_color(if clean {
                                    c(INK_MUTED)
                                } else {
                                    c(ERR)
                                }),
                            ),
                    );
                if !clean {
                    col = col.children(
                        kit.guard
                            .violations
                            .iter()
                            .take(6)
                            .map(|v| kit::mono(v.to_string(), 11.).pl(px(19.)).into_any_element()),
                    );
                }
                let content = div().flex().items_start().gap(px(12.)).child(col.flex_1().min_w_0()).child(
                    kit::button("kit-open", "Abrir pasta", Kind::Ghost, Some("\u{E838}"), false)
                        .on_click(move |_, _, _| open_in_explorer(&path)),
                );
                (if clean { Mark::Done } else { Mark::Error }, content)
            }
            KitState::Missing | KitState::Invalid(_) => {
                let (title, text, mark) = match &self.kit {
                    KitState::Invalid(why) => ("O manifesto do pacote não abriu", why.clone(), Mark::Error),
                    _ => (
                        "Pacote não encontrado",
                        "Conecte o disco do pacote (a pasta MeuPlaybook\\pacote) ou abra o Vanta Tools com --kit <pasta>.".into(),
                        Mark::Current,
                    ),
                };
                let color = if mark == Mark::Error { c(ERR) } else { c(WARN) };
                let content = div()
                    .flex()
                    .flex_col()
                    .gap(px(8.))
                    .child(kit::row_title("Pacote"))
                    .child(
                        div()
                            .flex()
                            .items_start()
                            .gap(px(7.))
                            .child(
                                kit::glyph(if mark == Mark::Error { "\u{EA39}" } else { "\u{E7BA}" }, 12.)
                                    .text_color(color)
                                    .mt(px(4.)),
                            )
                            .child(
                                div()
                                    .flex_1()
                                    .min_w_0()
                                    .flex()
                                    .flex_col()
                                    .child(kit::body(title).text_color(color))
                                    .child(kit::mono(text, 12.)),
                            ),
                    )
                    .child(
                        div().flex().child(
                            kit::button(
                                "kit-search",
                                "Procurar de novo",
                                Kind::Secondary,
                                Some("\u{E72C}"),
                                false,
                            )
                            .on_click(cx.listener(|this, _, _, cx| this.reload_kit(cx))),
                        ),
                    );
                (mark, content)
            }
        };

        // 2 · O que restaurar
        let configs = match &self.kit {
            KitState::Ready(kit) => plural(kit.loaded.manifest.items.len(), "configuração", "configurações"),
            _ => "As configurações".into(),
        };
        let option = |id: &'static str, label: &'static str, detail: String, on: bool| {
            div()
                .id(id)
                .role(Role::CheckBox)
                .aria_label(label)
                .aria_toggled(if on { Toggled::True } else { Toggled::False })
                .aria_disabled(busy)
                .flex_1()
                .min_w(px(220.))
                .px(px(14.))
                .py(px(12.))
                .rounded(px(10.))
                .bg(c(SURFACE2))
                .border_1()
                .border_color(c(HAIRLINE))
                .flex()
                .flex_col()
                .gap(px(2.))
                .when(!busy, |d| {
                    d.tab_index(0)
                        .cursor_pointer()
                        .hover(|s| s.border_color(c(HAIRLINE_STRONG)))
                        .focus_visible(|s| focus_ring(s, c(0xA78BFE), c(CANVAS)))
                })
                .when(busy, |d| d.opacity(0.6))
                .child(
                    div()
                        .flex()
                        .items_center()
                        .gap(px(8.))
                        .child(kit::check_box(on, false))
                        .child(kit::row_title(label)),
                )
                .child(kit::body(detail).pl(px(28.)))
        };
        let nv = |id: &'static str, label: &'static str, on: bool| {
            div()
                .id(id)
                .role(Role::RadioButton)
                .aria_label(label)
                .aria_selected(on)
                .flex()
                .items_center()
                .gap(px(10.))
                .py(px(4.))
                .rounded(px(6.))
                .when(!busy, |d| {
                    d.tab_index(0).cursor_pointer().focus_visible(|s| focus_ring(s, c(0xA78BFE), c(CANVAS)))
                })
                .child(kit::radio_dot(on))
                .child(div().font_family(FONT_TEXT).text_size(px(13.5)).text_color(c(INK_MUTED)).child(label))
        };
        let what = div()
            .flex()
            .flex_col()
            .gap(px(12.))
            .child(kit::row_title("O que restaurar"))
            .child(
                div()
                    .flex()
                    .flex_wrap()
                    .gap(px(12.))
                    .child(
                        option(
                            "opt-apps",
                            "Instalar os programas",
                            "Os da lista winget.txt do pacote, um por vez. Os já instalados são pulados."
                                .into(),
                            self.restore_apps,
                        )
                        .on_click(cx.listener(move |this, _, _, cx| {
                            if !busy {
                                this.restore_apps = !this.restore_apps;
                                cx.notify();
                            }
                        })),
                    )
                    .child(
                        option(
                            "opt-config",
                            "Copiar as configurações",
                            format!("{configs} do pacote, mais registro e tarefas do Windows."),
                            self.restore_config,
                        )
                        .on_click(cx.listener(move |this, _, _, cx| {
                            if !busy {
                                this.restore_config = !this.restore_config;
                                cx.notify();
                            }
                        })),
                    ),
            )
            .child(
                div()
                    .flex()
                    .flex_col()
                    .gap(px(4.))
                    .pt(px(4.))
                    .child(kit::caption("Driver NVIDIA"))
                    .child(
                        nv(
                            "nv-skip",
                            "Pular o driver (o perfil NVIDIA é copiado do mesmo jeito)",
                            self.nvidia == NvidiaChoice::Skip,
                        )
                        .on_click(cx.listener(move |this, _, _, cx| {
                            if !busy {
                                this.nvidia = NvidiaChoice::Skip;
                                cx.notify();
                            }
                        })),
                    )
                    .child(
                        nv(
                            "nv-clean",
                            "Abrir o NVCleanstall para eu escolher o driver",
                            self.nvidia != NvidiaChoice::Skip,
                        )
                        .on_click(cx.listener(move |this, _, _, cx| {
                            if !busy {
                                this.nvidia = NvidiaChoice::NvCleanstall;
                                cx.notify();
                            }
                        })),
                    ),
            );

        // 3 · Revisar e iniciar
        let plan: Vec<AnyElement> = match &self.kit {
            KitState::Ready(kit) => describe_plan(&kit.plan)
                .into_iter()
                .enumerate()
                .map(|(i, line)| {
                    div()
                        .flex()
                        .gap(px(10.))
                        .child(kit::mono(format!("{}", i + 1), 12.).w(px(14.)).text_color(c(INK_SUBTLE)))
                        .child(kit::body(line).text_color(c(INK_MUTED)))
                        .into_any_element()
                })
                .collect(),
            _ => Vec::new(),
        };
        let job = &self.restore_job;
        let tail: Vec<AnyElement> = job
            .log
            .iter()
            .rev()
            .take(8)
            .rev()
            .map(|line| kit::mono(line.clone(), 11.).into_any_element())
            .collect();
        let start_disabled = !ready_clean || busy || !(self.restore_apps || self.restore_config);
        let review = div()
            .flex()
            .flex_col()
            .gap(px(10.))
            .child(kit::row_title("Revisar e iniciar"))
            .child(
                kit::body("Você vê a ordem antes. Alguns instaladores demoram alguns minutos, e o andamento aparece aqui.")
                    .text_color(c(INK_MUTED)),
            )
            .when(!plan.is_empty(), |d| d.child(div().flex().flex_col().gap(px(2.)).children(plan)))
            .when(busy || job.outcome.is_some(), |d| {
                d.child(
                    div()
                        .flex()
                        .flex_col()
                        .gap(px(8.))
                        .pt(px(4.))
                        .child(kit::meter(job.fraction, None))
                        .child(kit::body(job.current.clone()).text_color(c(INK)))
                        .when(!tail.is_empty(), |d| d.child(div().flex().flex_col().gap(px(1.)).children(tail))),
                )
            })
            .child(
                div()
                    .flex()
                    .gap(px(10.))
                    .mt(px(6.))
                    .child(
                        kit::button("restore-start", "Iniciar restauração", Kind::Primary, Some("\u{E777}"), start_disabled)
                            .on_click(cx.listener(|this, _, _, cx| this.start_restore(cx))),
                    )
                    .when(busy, |d| {
                        d.child(kit::button("restore-cancel", "Cancelar", Kind::Secondary, Some("\u{E711}"), false).on_click(
                            cx.listener(|this, _, _, cx| {
                                this.restore_job.cancel.cancel();
                                this.restore_job.current = "Cancelando: o que já começou termina antes.".into();
                                cx.notify();
                            }),
                        ))
                    }),
            );

        let what_mark = if !matches!(self.kit, KitState::Ready(_)) {
            Mark::Todo
        } else if busy || job.outcome.is_some() {
            Mark::Done
        } else {
            Mark::Current
        };
        let review_mark =
            if job.outcome.as_ref().is_some_and(|(ok, _)| *ok) { Mark::Done } else { Mark::Todo };
        let steps = kit::panel()
            .flex_1()
            .min_w(px(420.))
            .max_w(px(720.))
            .px(px(24.))
            .py(px(18.))
            .flex()
            .flex_col()
            .child(step("1", pkg_mark, false, pkg_content))
            .child(step("2", what_mark, false, what))
            .child(step("3", review_mark, true, review));
        let side_line = |text: &'static str| {
            div()
                .flex()
                .items_start()
                .gap(px(10.))
                .child(kit::glyph("\u{E711}", 10.).text_color(c(INK_SUBTLE)).mt(px(5.)))
                .child(
                    div()
                        .font_family(FONT_TEXT)
                        .text_size(px(13.5))
                        .line_height(px(20.))
                        .text_color(c(INK_MUTED))
                        .child(text),
                )
        };
        let side = div()
            .w(px(320.))
            .flex_shrink_0()
            .pt(px(10.))
            .flex()
            .flex_col()
            .gap(px(10.))
            .child(
                div()
                    .font_family(FONT_TEXT)
                    .font_weight(FontWeight::SEMIBOLD)
                    .text_size(px(15.))
                    .text_color(c(INK))
                    .child("O que esta tela não faz"),
            )
            .child(side_line("Não instala o Riot Vanguard."))
            .child(side_line("Não troca o driver de vídeo sem você escolher."))
            .child(side_line("Não traz contas, históricos nem dados pessoais."))
            .child(
                kit::body(
                    "Pastas do sistema, registro e tarefas pedem administrador uma vez, para o lote inteiro.",
                )
                .mt(px(6.)),
            );
        let mut body = div()
            .flex()
            .flex_col()
            .child(self.header(
                "Restaurar",
                "Traz de volta seus programas e configurações a partir do pacote. Nada começa antes de você confirmar, e dá para cancelar a qualquer momento.",
            ))
            .child(div().mt(px(20.)).flex().flex_wrap().items_start().gap(px(24.)).child(steps).child(side));
        if let Some(bar) = Self::outcome_bar(&self.restore_job) {
            body = body.child(div().mt(px(20.)).max_w(px(720.)).child(bar));
        }
        self.page_scroll(Page::Restore, body.into_any_element(), 72., None)
    }

    // ---------- Ajustes ----------

    fn settings(&mut self, window: &Window, cx: &mut Context<Self>) -> AnyElement {
        let filter = self.settings_filter.read(cx).value().to_owned();
        let in_area: Vec<usize> =
            (0..self.tweaks.len()).filter(|&i| self.tweaks[i].category == self.area).collect();
        let on_count = in_area.iter().filter(|&&i| self.states[i] == TweakState::On).count();
        let off_count = in_area.len() - on_count;
        let pending =
            in_area.iter().filter(|&&i| !self.tweaks[i].locked && self.states[i] != TweakState::On).count();

        let segments = [
            (StateFilter::All, "Todos", in_area.len()),
            (StateFilter::On, "Ativos", on_count),
            (StateFilter::Off, "Inativos", off_count),
        ];
        let segment_focus: Vec<FocusHandle> =
            (0..segments.len()).map(|i| self.focus.get(&format!("segment-{i}"), cx)).collect();
        let segment_items: Vec<AnyElement> = segments
            .iter()
            .zip(segment_focus)
            .enumerate()
            .map(|(i, ((value, label, count), focus))| {
                let (value, active) = (*value, self.state_filter == *value);
                div()
                    .id(("segment", i))
                    .role(Role::RadioButton)
                    .aria_label(format!("{label} {count}"))
                    .aria_selected(active)
                    .track_focus(&focus.tab_index(0).tab_stop(true))
                    .h(px(30.))
                    .px(px(12.))
                    .flex()
                    .items_center()
                    .gap(px(8.))
                    .rounded(px(7.))
                    .border_1()
                    .border_color(if active { c(HAIRLINE_STRONG) } else { a(0x00000000) })
                    .bg(if active { c(SURFACE3) } else { a(0x00000000) })
                    .text_color(if active { c(INK) } else { c(INK_SUBTLE) })
                    .font_family(FONT_TEXT)
                    .font_weight(FontWeight::MEDIUM)
                    .text_size(px(13.))
                    .cursor_pointer()
                    .when(!active, |d| d.hover(|s| s.text_color(c(INK))))
                    .focus_visible(|s| focus_ring(s, c(0xA78BFA), c(CANVAS)))
                    .child(*label)
                    .child(div().text_size(px(12.)).opacity(0.8).child(count.to_string()))
                    .on_click(cx.listener(move |this, _, _, cx| {
                        this.state_filter = value;
                        cx.notify();
                    }))
                    .into_any_element()
            })
            .collect();

        let summary = StyledText::new(format!("{on_count} de {} no padrão Vanta", in_area.len()))
            .with_highlights([(
                0..format!("{on_count} de {}", in_area.len()).len(),
                HighlightStyle {
                    color: Some(c(INK)),
                    font_weight: Some(FontWeight::SEMIBOLD),
                    ..Default::default()
                },
            )]);
        let header = div()
            .flex()
            .flex_col()
            .gap(px(10.))
            .child(kit::page_title(area_name(&self.area)))
            .child(kit::lead(kit::area_lead(&self.area)))
            .child(
                div()
                    .flex()
                    .flex_wrap()
                    .items_center()
                    .gap(px(20.))
                    .mt(px(4.))
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .gap(px(10.))
                            .child(kit::meter(on_count as f32 / in_area.len().max(1) as f32, Some(72.)))
                            .child(
                                div()
                                    .font_family(FONT_TEXT)
                                    .text_size(px(13.))
                                    .text_color(c(INK_MUTED))
                                    .child(summary),
                            ),
                    )
                    .when(!self.elevated, |d| {
                        d.child(
                            div()
                                .flex()
                                .items_center()
                                .gap(px(7.))
                                .text_color(c(INK_SUBTLE))
                                .child(kit::glyph("\u{EA18}", 13.))
                                .child(kit::caption(
                                    "Itens do sistema pedem permissão de administrador na hora",
                                )),
                        )
                    }),
            );
        let toolbar = div()
            .mt(px(32.))
            .mb(px(12.))
            .flex()
            .flex_wrap()
            .items_center()
            .gap(px(12.))
            .child(
                div()
                    .flex()
                    .gap(px(2.))
                    .p(px(3.))
                    .rounded(px(10.))
                    .bg(c(0x131119))
                    .border_1()
                    .border_color(c(HAIRLINE))
                    .children(segment_items),
            )
            .child(self.search_field(&self.settings_filter, 300., window, cx))
            .child(div().flex_1())
            .child(
                kit::button(
                    "apply-defaults",
                    if pending == 0 {
                        "Aplicar padrão Vanta".to_owned()
                    } else {
                        format!("Aplicar padrão Vanta ({pending})")
                    },
                    Kind::Secondary,
                    Some("\u{E73E}"),
                    pending == 0,
                )
                .on_click(cx.listener(|this, _, window, cx| this.apply_area_defaults(window, cx))),
            );

        let visible: Vec<usize> = in_area
            .iter()
            .copied()
            .filter(|&i| {
                let title = self
                    .copy
                    .get(&self.tweaks[i].id)
                    .map_or(self.tweaks[i].title.as_str(), |t| t.title.as_str());
                self.state_filter.keeps(self.states[i])
                    && (name_matches(title, &filter) || name_matches(&self.tweaks[i].title, &filter))
            })
            .collect();
        let rows: Vec<AnyElement> =
            visible.iter().enumerate().map(|(position, &i)| self.tweak_row(position, i, cx)).collect();
        let list = if rows.is_empty() {
            kit::body("Nenhum ajuste com esse filtro.").mt(px(14.)).pl(px(4.)).into_any_element()
        } else {
            kit::panel().py(px(4.)).children(rows).into_any_element()
        };
        let keys = div()
            .mt(px(16.))
            .pl(px(2.))
            .flex()
            .gap(px(18.))
            .child(
                div()
                    .flex()
                    .items_center()
                    .gap(px(6.))
                    .child(kit::keycap("Tab"))
                    .child(kit::caption("navegar")),
            )
            .child(
                div()
                    .flex()
                    .items_center()
                    .gap(px(6.))
                    .child(kit::keycap("Enter"))
                    .child(kit::caption("liga ou desliga")),
            )
            .child(
                div()
                    .flex()
                    .items_center()
                    .gap(px(6.))
                    .child(kit::keycap("Esc"))
                    .child(kit::caption("volta ao Início")),
            );
        let mut body = div().flex().flex_col().child(header);
        if let Some(bar) = self.notice_bar(cx) {
            body = body.child(div().mt(px(16.)).child(bar));
        }
        let body = body.child(toolbar).child(list).child(keys);
        self.page_scroll(Page::Settings, body.into_any_element(), 72., None)
    }

    pub(super) fn tweak_row(&self, position: usize, i: usize, cx: &mut Context<Self>) -> AnyElement {
        let t = &self.tweaks[i];
        let state = self.states[i];
        let copy = self.copy.get(&t.id).cloned().unwrap_or_else(|| TweakCopy {
            title: t.title.clone(),
            summary: self.texts.tweaks.get(&t.id).cloned().unwrap_or_else(|| t.description.clone()),
            ..Default::default()
        });
        let error = self.row_errors.get(&i).cloned();
        let open = self.expanded.contains(&i);
        let label = copy.title.clone();
        let is_vbs = t.id == VBS_HVCI_ID;
        let locked = self.is_tweak_locked(i);
        let status: Option<AnyElement> = if locked {
            Some(
                div()
                    .flex()
                    .items_center()
                    .gap(px(6.))
                    .text_color(c(INK_SUBTLE))
                    .child(kit::glyph("\u{E72E}", 11.))
                    .child(kit::caption("Travado"))
                    .into_any_element(),
            )
        } else {
            match state {
                TweakState::Mixed => Some(
                    div()
                        .flex()
                        .items_center()
                        .gap(px(6.))
                        .text_color(c(WARN))
                        .child(kit::glyph("\u{E7BA}", 11.))
                        .child(kit::caption("Em parte").text_color(c(WARN)))
                        .into_any_element(),
                ),
                TweakState::Off => Some(kit::caption("Fora do padrão").into_any_element()),
                TweakState::On => None,
            }
        };
        let has_detail = !copy.explanation.is_empty() || !copy.gain.is_empty() || !copy.caution.is_empty();
        let detail_line = |label: &'static str, text: String, color: u32| {
            div()
                .w_full()
                .min_w_0()
                .flex()
                .gap(px(8.))
                .child(div().w(px(64.)).flex_shrink_0().child(kit::caption(label).text_color(c(color))))
                .child(
                    div()
                        .flex_1()
                        .min_w_0()
                        .font_family(FONT_TEXT)
                        .text_size(px(13.))
                        .line_height(px(20.))
                        .text_color(c(INK_MUTED))
                        .child(text),
                )
        };
        div()
            .id(("tweak", i))
            .mx(px(20.))
            .when(position > 0, |d| d.border_t_1().border_color(c(HAIRLINE)))
            .child(
                div()
                    .flex()
                    .items_center()
                    .gap(px(16.))
                    .py(px(14.))
                    .when(error.is_some(), |d| d.bg(a(0xF871711A)).rounded(px(8.)).px(px(10.)))
                    .child(
                        div()
                            .flex_1()
                            .min_w_0()
                            .flex()
                            .flex_col()
                            .gap(px(2.))
                            .child(
                                div()
                                    .font_family(FONT_TEXT)
                                    .font_weight(FontWeight::MEDIUM)
                                    .text_size(px(15.))
                                    .line_height(px(22.))
                                    .text_color(c(INK))
                                    .child(copy.title.clone()),
                            )
                            .child(
                                div()
                                    .font_family(FONT_TEXT)
                                    .text_size(px(13.))
                                    .line_height(px(19.))
                                    .text_color(c(INK_MUTED))
                                    .child(copy.summary.clone()),
                            )
                            .when_some(error.clone(), |d, message| {
                                d.child(
                                    div()
                                        .w_full()
                                        .min_w_0()
                                        .flex()
                                        .items_start()
                                        .gap(px(6.))
                                        .pt(px(4.))
                                        .text_color(c(ERR))
                                        .child(div().pt(px(2.)).child(kit::glyph("\u{EA39}", 12.)))
                                        .child(
                                            kit::caption(format!("Não aplicou: {message}"))
                                                .flex_1()
                                                .min_w_0()
                                                .text_color(c(ERR)),
                                        ),
                                )
                            }),
                    )
                    .when(error.is_some(), |d| {
                        d.child(
                            kit::button(("retry", i), "Tentar de novo", Kind::Ghost, Some("\u{E72C}"), false)
                                .on_click(cx.listener(move |this, _, _, cx| this.toggle_tweak(i, cx))),
                        )
                    })
                    .children(status)
                    .child(
                        kit::toggle(("tw", i), label.clone(), state == TweakState::On, locked)
                            .on_click(cx.listener(move |this, _, _, cx| this.toggle_tweak(i, cx))),
                    )
                    .child(
                        div()
                            .id(("tw-more", i))
                            .role(Role::Button)
                            .aria_label(format!("Detalhes de {label}"))
                            .aria_expanded(open)
                            .size(px(28.))
                            .flex()
                            .items_center()
                            .justify_center()
                            .rounded(px(6.))
                            .text_color(c(INK_SUBTLE))
                            .when(has_detail, |d| {
                                d.tab_index(0)
                                    .cursor_pointer()
                                    .hover(|s| s.bg(a(0x1B1824CC)).text_color(c(INK)))
                                    .focus_visible(|s| focus_ring(s, c(0xA78BFE), c(CANVAS)))
                                    .on_click(cx.listener(move |this, _, _, cx| {
                                        if !this.expanded.remove(&i) {
                                            this.expanded.insert(i);
                                        }
                                        cx.notify();
                                    }))
                            })
                            .when(!has_detail, |d| d.opacity(0.3))
                            .child(kit::glyph(if open { "\u{E70E}" } else { "\u{E70D}" }, 11.)),
                    ),
            )
            .when(is_vbs, |d| {
                let unlocked = self.core_isolation_unlocked;
                d.child(
                    div()
                        .id("vbs-valorant-unlock")
                        .role(Role::CheckBox)
                        .aria_label(VALORANT_UNLOCK_LABEL)
                        .aria_toggled(if unlocked { Toggled::True } else { Toggled::False })
                        .tab_index(0)
                        .cursor_pointer()
                        .flex()
                        .items_center()
                        .gap(px(10.))
                        .px(px(10.))
                        .py(px(8.))
                        .mb(px(10.))
                        .rounded(px(8.))
                        .bg(if unlocked { a(0x7C4EE014) } else { a(0xFFFFFF06) })
                        .border_1()
                        .border_color(if unlocked { c(ACCENT) } else { c(HAIRLINE) })
                        .hover(|s| s.border_color(c(HAIRLINE_STRONG)))
                        .focus_visible(|s| focus_ring(s, c(0xA78BFE), c(CANVAS)))
                        .on_click(cx.listener(move |this, _, _, cx| {
                            let next = !this.core_isolation_unlocked;
                            this.core_isolation_unlocked = next;
                            if !next && this.states.get(i).is_some_and(|s| *s != TweakState::On) {
                                this.apply_tweak_value(i, true, cx);
                            } else {
                                cx.notify();
                            }
                        }))
                        .on_key_down(cx.listener(move |this, event: &KeyDownEvent, _, cx| {
                            if matches!(event.keystroke.key.as_str(), "enter" | "space") {
                                let next = !this.core_isolation_unlocked;
                                this.core_isolation_unlocked = next;
                                if !next && this.states.get(i).is_some_and(|s| *s != TweakState::On) {
                                    this.apply_tweak_value(i, true, cx);
                                } else {
                                    cx.notify();
                                }
                            }
                        }))
                        .child(kit::check_box(unlocked, false))
                        .child(
                            div()
                                .flex_1()
                                .min_w_0()
                                .font_family(FONT_TEXT)
                                .text_size(px(13.))
                                .text_color(c(INK_MUTED))
                                .child(VALORANT_UNLOCK_LABEL),
                        ),
                )
            })
            .when(open, |d| {
                d.child(
                    div()
                        .flex()
                        .flex_col()
                        .gap(px(8.))
                        .pb(px(16.))
                        .pr(px(80.))
                        .when(!copy.explanation.is_empty(), |d| {
                            d.child(detail_line("Como", copy.explanation.clone(), INK_SUBTLE))
                        })
                        .when(!copy.gain.is_empty(), |d| d.child(detail_line("Ganho", copy.gain.clone(), OK)))
                        .when(!copy.caution.is_empty(), |d| {
                            d.child(detail_line("Cuidado", copy.caution.clone(), WARN))
                        }),
                )
            })
            .into_any_element()
    }

    // ---------- Preferências ----------

    fn preferences(&mut self, cx: &mut Context<Self>) -> AnyElement {
        let pref_w = self.content_w.min(868.);
        let card_w = ((pref_w - 16.) / 2.).floor().max(200.);
        let card_h = (card_w * 0.5625).floor();
        let cards: Vec<AnyElement> = kit::BACKGROUNDS
            .iter()
            .enumerate()
            .map(|(i, (key, name, _))| {
                let selected = self.prefs.background == *key;
                let key = (*key).to_owned();
                div()
                    .id(("bg", i))
                    .role(Role::RadioButton)
                    .aria_label(*name)
                    .aria_selected(selected)
                    .tab_index(0)
                    .w(px(card_w))
                    .flex()
                    .flex_col()
                    .gap(px(8.))
                    .cursor_pointer()
                    .focus_visible(|s| focus_ring(s, c(0xA78BFE), c(CANVAS)))
                    .child(
                        div()
                            .relative()
                            .w_full()
                            .h(px(card_h))
                            .rounded(px(12.))
                            .border_2()
                            .border_color(if selected { c(ACCENT_HOVER) } else { c(HAIRLINE_STRONG) })
                            .child(
                                img(kit::background_image(&key))
                                    .size_full()
                                    .rounded(px(10.))
                                    .object_fit(ObjectFit::Cover),
                            )
                            .when(selected, |d| {
                                d.child(
                                    div()
                                        .absolute()
                                        .top(px(12.))
                                        .right(px(12.))
                                        .size(px(24.))
                                        .rounded(px(12.))
                                        .flex()
                                        .items_center()
                                        .justify_center()
                                        .bg(c(ACCENT))
                                        .text_color(c(0xFFFFFF))
                                        .child(kit::glyph("\u{E73E}", 11.)),
                                )
                            }),
                    )
                    .child(
                        div()
                            .font_family(FONT_TEXT)
                            .font_weight(FontWeight::SEMIBOLD)
                            .text_size(px(14.5))
                            .text_color(c(INK))
                            .child(*name),
                    )
                    .on_click(cx.listener(move |this, _, _, cx| {
                        this.prefs.background.clone_from(&key);
                        this.prefs.save();
                        cx.notify();
                    }))
                    .into_any_element()
            })
            .collect();
        let dim = self.prefs.dim;
        let body = div()
            .max_w(px(868.))
            .flex()
            .flex_col()
            .gap(px(24.))
            .child(self.header("Fundo do app", "Um fundo para o Vanta inteiro. Troque quando quiser; ele vale para todas as páginas."))
            .child(div().flex().flex_wrap().gap(px(16.)).children(cards))
            .child(
                kit::panel()
                    .pl(px(20.))
                    .pr(px(16.))
                    .py(px(16.))
                    .flex()
                    .items_center()
                    .gap(px(16.))
                    .child(
                        div()
                            .flex_1()
                            .flex()
                            .flex_col()
                            .gap(px(3.))
                            .child(kit::row_title("Escurecer o fundo nas páginas de trabalho"))
                            .child(kit::body(if data::edicao().has_restore() {
                                "Em Programas, Restaurar e Ajustes, uma camada escura cobre o lado do texto. O Início sempre mostra a imagem inteira."
                            } else {
                                "Em Programas e Ajustes, uma camada escura cobre o lado do texto. O Início sempre mostra a imagem inteira."
                            })),
                    )
                    .child(kit::toggle("dim-toggle", "Escurecer o fundo nas páginas de trabalho", dim, false).on_click(
                        cx.listener(|this, _, _, cx| {
                            this.prefs.dim = !this.prefs.dim;
                            this.prefs.save();
                            cx.notify();
                        }),
                    )),
            )
            .child(self.about_section(cx));
        self.page_scroll(Page::Preferences, body.into_any_element(), 72., None)
    }

    fn open_licences(&mut self, cx: &mut Context<Self>) {
        if self.licences_opening {
            return;
        }
        self.licences_opening = true;
        self.licences_failed = false;
        cx.notify();
        cx.spawn(async move |this, cx| {
            let result = cx.background_executor().spawn(async { crate::services::licenses::open() }).await;
            if let Err(error) = &result {
                log::error!("Não foi possível abrir os avisos de licença: {error:#}");
            }
            this.update(cx, |this, cx| {
                this.licences_opening = false;
                this.licences_failed = result.is_err();
                cx.notify();
            })
            .ok();
        })
        .detach();
    }

    fn about_row(label: &'static str, value: impl Into<SharedString>, action: Option<AnyElement>) -> gpui::Div {
        div()
            .flex()
            .flex_wrap()
            .items_start()
            .gap_x(px(16.))
            .gap_y(px(6.))
            .py(px(12.))
            .border_t_1()
            .border_color(c(HAIRLINE))
            .child(
                div()
                    .w(px(148.))
                    .flex_shrink_0()
                    .font_family(FONT_TEXT)
                    .font_weight(FontWeight::MEDIUM)
                    .text_size(px(12.5))
                    .line_height(px(20.))
                    .text_color(c(INK_MUTED))
                    .child(label),
            )
            .child(
                div()
                    .flex_1()
                    .min_w(px(240.))
                    .flex()
                    .flex_wrap()
                    .items_start()
                    .justify_between()
                    .gap_x(px(12.))
                    .gap_y(px(4.))
                    .child(
                        div()
                            .flex_1()
                            .min_w(px(200.))
                            .font_family(FONT_TEXT)
                            .text_size(px(13.))
                            .line_height(px(20.))
                            .text_color(c(INK))
                            .child(value.into()),
                    )
                    .when_some(action, |d, el| d.child(el)),
            )
    }

    fn about_section(&self, cx: &mut Context<Self>) -> gpui::Div {
        let version = env!("CARGO_PKG_VERSION");
        let edition = match data::edicao() {
            data::Edicao::Pessoal => "Vanta Tools · Edição pessoal",
            data::Edicao::Publica => "Vanta Tools",
        };
        let notices_label = if self.licences_opening {
            "Abrindo THIRD-PARTY-NOTICES.txt…"
        } else {
            "Abrir THIRD-PARTY-NOTICES.txt"
        };
        div()
            .flex()
            .flex_col()
            .gap(px(14.))
            .pt(px(8.))
            .child(kit::section_title("Sobre e licenças"))
            .child(
                kit::panel()
                    .px(px(20.))
                    .py(px(16.))
                    .flex()
                    .flex_col()
                    .child(
                        div()
                            .pb(px(12.))
                            .flex()
                            .flex_wrap()
                            .items_baseline()
                            .justify_between()
                            .gap(px(8.))
                            .child(kit::row_title(format!("Vanta Manager {version}")))
                            .child(kit::caption(edition)),
                    )
                    .when_some(crate::services::embedded::source_commit(), |d, commit| {
                        d.child(Self::about_row("Commit de origem", commit, None))
                    })
                    .child(Self::about_row(
                        "Licença",
                        "Vanta © colaboradores, GPL-3.0.",
                        Some(
                            kit::link("tools-about-gpl", "Ler licença GPL-3.0", true)
                                .on_click(|_, _, cx| cx.open_url(GPL_URL))
                                .into_any_element(),
                        ),
                    ))
                    .child(Self::about_row(
                        "Projeto base",
                        "Baseado no AtlasOS 0.6.0 (GPL-3.0).",
                        Some(
                            kit::link("tools-about-atlas", "Atlas-OS/Atlas no GitHub", true)
                                .on_click(|_, _, cx| cx.open_url(ATLAS_URL))
                                .into_any_element(),
                        ),
                    ))
                    .child(Self::about_row(
                        "Fontes",
                        "Geist e Geist Mono (OFL-1.1, Vercel).",
                        Some(
                            kit::link("tools-about-fonts", "vercel/geist-font", true)
                                .on_click(|_, _, cx| cx.open_url(GEIST_URL))
                                .into_any_element(),
                        ),
                    ))
                    .child(Self::about_row(
                        "Código-fonte",
                        format!(
                            "O código-fonte completo acompanha cada distribuição em Vanta-{version}-source.zip e Vanta-{version}-third-party-sources.zip."
                        ),
                        Some(
                            kit::link("tools-about-source", "Repositório no GitHub", true)
                                .on_click(|_, _, cx| cx.open_url(crate::services::releases::REPOSITORY_URL))
                                .into_any_element(),
                        ),
                    ))
                    .child(Self::about_row(
                        "Rede e privacidade",
                        "O Vanta consulta api.github.com apenas para buscar manifestos e versões do winget, sem enviar dados pessoais.",
                        None,
                    ))
                    .child(
                        div()
                            .pt(px(12.))
                            .border_t_1()
                            .border_color(c(HAIRLINE))
                            .flex()
                            .flex_col()
                            .gap(px(6.))
                            .child(
                                div()
                                    .flex()
                                    .flex_wrap()
                                    .items_center()
                                    .gap(px(12.))
                                    .child(
                                        kit::link("tools-about-notices", notices_label, false)
                                            .when(self.licences_opening, |d| d.opacity(0.6))
                                            .on_click(cx.listener(|this, _, _, cx| this.open_licences(cx))),
                                    )
                                    .child(
                                        kit::link("tools-about-releases", "Lançamentos no GitHub", true)
                                            .on_click(|_, _, cx| cx.open_url(crate::services::releases::LATEST_RELEASE_URL)),
                                    ),
                            )
                            .when(self.licences_failed, |d| {
                                d.child(kit::body(
                                    "Não foi possível abrir THIRD-PARTY-NOTICES.txt. Tente novamente ou procure o arquivo em C:\\Vanta\\Licenses.",
                                ))
                            }),
                    ),
            )
    }

    // ---------- Registros ----------

    fn logs_page(&mut self, cx: &mut Context<Self>) -> AnyElement {
        let files: Vec<AnyElement> = self
            .logs
            .iter()
            .enumerate()
            .map(|(i, path)| {
                let selected = self.log_selected == Some(i);
                let name = path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
                div()
                    .id(("log", i))
                    .role(Role::Tab)
                    .aria_label(name.clone())
                    .aria_selected(selected)
                    .tab_index(0)
                    .px(px(12.))
                    .py(px(10.))
                    .rounded(px(8.))
                    .font_family(FONT_TEXT)
                    .font_weight(FontWeight::MEDIUM)
                    .text_size(px(13.))
                    .text_color(if selected { c(INK) } else { c(INK_MUTED) })
                    .when(selected, |d| d.bg(c(SURFACE2)))
                    .when(!selected, |d| d.hover(|s| s.bg(a(0x1B1824B3)).text_color(c(INK))))
                    .cursor_pointer()
                    .focus_visible(|s| focus_ring(s, c(0xA78BFE), c(CANVAS)))
                    .truncate()
                    .child(name)
                    .on_click(cx.listener(move |this, _, _, cx| {
                        this.select_log(Some(i));
                        cx.notify();
                    }))
                    .into_any_element()
            })
            .collect();
        let title = self
            .log_selected
            .and_then(|i| self.logs.get(i))
            .and_then(|p| p.file_name())
            .map_or_else(|| "Escolha um arquivo".to_owned(), |n| n.to_string_lossy().into_owned());
        let text = if self.logs.is_empty() { "Nenhum log ainda.".to_owned() } else { self.log_text.clone() };
        let scroll = &self.scrolls[Page::Logs.index()];
        let body = div()
            .size_full()
            .max_w(px(1240.))
            .pl(px(PAGE_X))
            .pr(px(PAGE_X))
            .pt(px(PAGE_TOP))
            .pb(px(40.))
            .flex()
            .flex_col()
            .gap(px(24.))
            .child(self.header("Registros", "Tudo o que o Vanta fez fica anotado aqui, com data e hora. Se algo falhar, o motivo está no arquivo."))
            .child(
                div()
                    .flex_1()
                    .min_h_0()
                    .flex()
                    .gap(px(16.))
                    .child(
                        kit::panel()
                            .w(px(300.))
                            .flex_shrink_0()
                            .p(px(6.))
                            .child(div().id("log-files").size_full().overflow_y_scroll().flex().flex_col().gap(px(2.)).children(files)),
                    )
                    .child(
                        kit::panel()
                            .flex_1()
                            .min_w_0()
                            .flex()
                            .flex_col()
                            .child(
                                div()
                                    .flex()
                                    .items_center()
                                    .gap(px(8.))
                                    .pl(px(18.))
                                    .pr(px(10.))
                                    .py(px(10.))
                                    .border_b_1()
                                    .border_color(c(HAIRLINE))
                                    .child(kit::mono(title, 12.).flex_1().truncate())
                                    .child(
                                        kit::button("logs-open", "Abrir pasta", Kind::Ghost, Some("\u{E838}"), false).on_click(|_, _, _| {
                                            let _ = std::fs::create_dir_all(log_dir());
                                            open_in_explorer(log_dir());
                                        }),
                                    ),
                            )
                            .child(
                                div()
                                    .flex_1()
                                    .min_h_0()
                                    .relative()
                                    .child(
                                        div()
                                            .id("log-body")
                                            .size_full()
                                            .overflow_y_scroll()
                                            .track_scroll(scroll)
                                            .px(px(18.))
                                            .pt(px(14.))
                                            .pb(px(18.))
                                            .child(kit::mono(text, 12.).line_height(px(19.))),
                                    )
                                    .child(scrollbar(scroll, &self.bars[Page::Logs.index()])),
                            ),
                    ),
            );
        div().flex_1().min_w_0().child(body).into_any_element()
    }

    // ---------- busca (Ctrl+K) ----------

    fn open_search(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        self.search_open = true;
        self.search.update(cx, |input, cx| input.set_value("", cx));
        let handle = self.search.read(cx).focus_handle(cx);
        window.focus(&handle, cx);
        cx.notify();
    }

    fn close_search(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if self.search_open {
            self.search_open = false;
            window.focus(&self.root_focus, cx);
            cx.notify();
        }
    }

    /// O que a busca acha para `query`: páginas, áreas, ajustes e programas, no máximo 8.
    fn search_hits(&self, query: &str) -> Vec<(String, String, Target)> {
        let mut hits: Vec<(String, String, Target)> = Vec::new();
        let has_restore = data::edicao().has_restore();
        for (label, page) in [
            ("Início", Page::Home),
            ("Otimizar", Page::Optimize),
            ("Programas", Page::Programs),
            ("Restaurar", Page::Restore),
            ("Energia", Page::Power),
            ("Apps", Page::Apps),
            ("Serviços", Page::Services),
            ("Avançado", Page::Advanced),
            ("Preferências", Page::Preferences),
            ("Sobre e licenças", Page::Preferences),
            ("Registros", Page::Logs),
        ] {
            if page == Page::Restore && !has_restore {
                continue;
            }
            if name_matches(label, query) {
                hits.push((label.to_owned(), "Página".to_owned(), Target::Page(page)));
            }
        }
        let mut categories: Vec<&String> = self.tweaks.iter().map(|t| &t.category).collect();
        categories.sort_by_key(|c| area_rank(c));
        categories.dedup();
        for category in categories {
            if name_matches(area_name(category), query) {
                hits.push((
                    area_name(category).to_owned(),
                    "Ajustes".to_owned(),
                    Target::Area(category.clone()),
                ));
            }
        }
        if !query.trim().is_empty() {
            for (i, t) in self.tweaks.iter().enumerate() {
                let title = self.copy.get(&t.id).map_or(t.title.as_str(), |c| c.title.as_str());
                if name_matches(title, query) || name_matches(&t.title, query) {
                    hits.push((title.to_owned(), area_name(&t.category).to_owned(), Target::Tweak(i)));
                }
            }
            for (i, app) in self.apps.iter().enumerate() {
                if name_matches(&app.name, query) {
                    hits.push((app.name.clone(), "Programas".to_owned(), Target::App(i)));
                }
            }
        }
        hits.truncate(8);
        hits
    }

    fn go(&mut self, target: &Target, window: &mut Window, cx: &mut Context<Self>) {
        match target {
            Target::Page(page) => self.go_page(*page),
            Target::Area(category) => {
                if category == "Avancado" {
                    self.go_page(Page::Advanced);
                } else {
                    self.go_settings(category);
                    self.settings_filter.update(cx, |input, cx| input.set_value("", cx));
                    self.state_filter = StateFilter::All;
                }
            }
            Target::Tweak(i) => {
                let category = self.tweaks[*i].category.clone();
                self.go_settings(&category);
                self.state_filter = StateFilter::All;
                let title = self
                    .copy
                    .get(&self.tweaks[*i].id)
                    .map_or_else(|| self.tweaks[*i].title.clone(), |c| c.title.clone());
                self.settings_filter.update(cx, |input, cx| input.set_value(title, cx));
            }
            Target::App(i) => {
                self.go_page(Page::Programs);
                self.category = None;
                let name = self.apps[*i].name.clone();
                self.programs_filter.update(cx, |input, cx| input.set_value(name, cx));
            }
        }
        self.close_search(window, cx);
    }

    fn search_button(&self, cx: &mut Context<Self>) -> gpui::Stateful<gpui::Div> {
        div()
            .id("title-search")
            .role(Role::Button)
            .aria_label("Buscar ajustes, programas e páginas")
            .track_focus(&self.search_button_focus.clone().tab_index(0).tab_stop(true))
            .w(px(460.))
            .max_w_full()
            .h(px(34.))
            .px(px(12.))
            .flex()
            .items_center()
            .gap(px(10.))
            .rounded(px(9.))
            .border_1()
            .border_color(c(HAIRLINE))
            .bg(a(0x131119E6))
            .cursor_pointer()
            .hover(|s| s.border_color(c(HAIRLINE_STRONG)))
            .focus_visible(|s| focus_ring(s, c(0xA78BFE), c(CANVAS)))
            .child(kit::glyph("\u{E721}", 13.).text_color(c(INK_SUBTLE)))
            .child(kit::caption("Buscar ajustes, programas e páginas").text_size(px(13.)).flex_1())
            .child(div().flex().gap(px(4.)).child(kit::keycap("Ctrl")).child(kit::keycap("K")))
            .on_click(cx.listener(|this, _, window, cx| this.open_search(window, cx)))
    }

    fn search_overlay(&mut self, cx: &mut Context<Self>) -> AnyElement {
        let query = self.search.read(cx).value().to_owned();
        let hits = self.search_hits(&query);
        let rows: Vec<AnyElement> = hits
            .into_iter()
            .enumerate()
            .map(|(i, (label, hint, target))| {
                let code = match &target {
                    Target::Page(_) => "\u{E8A5}",
                    Target::Area(category) => kit::area_glyph(category),
                    Target::Tweak(_) => "\u{E9E9}",
                    Target::App(_) => "\u{E719}",
                };
                div()
                    .id(("hit", i))
                    .role(Role::Button)
                    .aria_label(label.clone())
                    .flex()
                    .items_center()
                    .gap(px(12.))
                    .h(px(44.))
                    .px(px(12.))
                    .rounded(px(8.))
                    .cursor_pointer()
                    .when(i == 0, |d| d.bg(c(SURFACE2)))
                    .hover(|d| d.bg(c(SURFACE2)))
                    .child(kit::glyph(code, 16.).text_color(c(INK_SUBTLE)))
                    .child(
                        div()
                            .flex_1()
                            .font_family(FONT_TEXT)
                            .text_size(px(14.))
                            .text_color(c(INK))
                            .child(label),
                    )
                    .child(kit::caption(hint))
                    .on_click(cx.listener(move |this, _, window, cx| this.go(&target, window, cx)))
                    .into_any_element()
            })
            .collect();
        let empty = rows.is_empty();
        let hint = |key: &'static str, text: &'static str| {
            div().flex().items_center().gap(px(6.)).child(kit::keycap(key)).child(kit::caption(text))
        };
        div()
            .absolute()
            .top_0()
            .left_0()
            .size_full()
            .child(
                div()
                    .id("search-scrim")
                    .absolute()
                    .top_0()
                    .left_0()
                    .size_full()
                    .bg(a(0x0B0A10BD))
                    .on_click(cx.listener(|this, _, window, cx| this.close_search(window, cx))),
            )
            .child(
                div().absolute().top(px(72.)).left_0().w_full().flex().justify_center().child(
                    div()
                        .id("search-panel")
                        .w(px(680.))
                        .rounded(px(14.))
                        .bg(c(SURFACE3))
                        .border_1()
                        .border_color(c(HAIRLINE_STRONG))
                        .shadow(vec![BoxShadow {
                            color: a(0x00000073),
                            offset: point(px(0.), px(12.)),
                            blur_radius: px(32.),
                            spread_radius: px(0.),
                            inset: false,
                        }])
                        .on_click(|_, _, cx| cx.stop_propagation())
                        .child(
                            div()
                                .flex()
                                .items_center()
                                .gap(px(12.))
                                .pl(px(18.))
                                .pr(px(12.))
                                .py(px(10.))
                                .child(kit::glyph("\u{E721}", 16.).text_color(c(INK_SUBTLE)))
                                .child(div().flex_1().child(self.search.clone()))
                                .child(kit::keycap("Esc")),
                        )
                        .child(div().h(px(1.)).bg(c(HAIRLINE)))
                        .child(
                            div()
                                .px(px(6.))
                                .py(px(6.))
                                .flex()
                                .flex_col()
                                .gap(px(2.))
                                .when(empty, |d| {
                                    d.child(kit::body("Nada com esse nome.").px(px(12.)).py(px(10.)))
                                })
                                .children(rows),
                        )
                        .child(
                            div()
                                .flex()
                                .gap(px(18.))
                                .px(px(16.))
                                .py(px(10.))
                                .border_t_1()
                                .border_color(c(HAIRLINE))
                                .child(hint("Tab", "navegar"))
                                .child(hint("Enter", "abrir"))
                                .child(hint("Esc", "fechar")),
                        ),
                ),
            )
            .into_any_element()
    }
}

impl Render for ToolsApp {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        window.set_rem_size(px(16.));
        let viewport = f32::from(window.viewport_size().width);
        // Área útil da página: janela menos navegação, margens e a barra de rolagem.
        self.content_w = (viewport.min(NAV_W + PAGE_MAX) - NAV_W - 2. * PAGE_X).max(280.);
        let areas = self.areas();
        let nav_focus = |this: &mut Self, id: &str, cx: &mut Context<Self>| this.focus.get(id, cx);
        let home_focus = nav_focus(self, "nav-home", cx);
        let optimize_focus = nav_focus(self, "nav-optimize", cx);
        let programs_focus = nav_focus(self, "nav-programs", cx);
        let restore_focus = nav_focus(self, "nav-restore", cx);
        let power_focus = nav_focus(self, "nav-power", cx);
        let apps_focus = nav_focus(self, "nav-apps", cx);
        let services_focus = nav_focus(self, "nav-services", cx);
        let advanced_focus = nav_focus(self, "nav-advanced", cx);
        let prefs_focus = nav_focus(self, "nav-prefs", cx);
        let logs_focus = nav_focus(self, "nav-logs", cx);
        let areas: Vec<_> = areas.into_iter().filter(|(cat, _)| cat != "Avancado").collect();
        let area_focus: Vec<FocusHandle> =
            areas.iter().map(|(c, _)| nav_focus(self, &format!("nav-{c}"), cx)).collect();
        let area_items: Vec<AnyElement> = areas
            .iter()
            .zip(area_focus)
            .map(|((category, (on, total)), focus)| {
                let category = category.clone();
                let label = area_name(&category).to_owned();
                let id: &'static str = Box::leak(format!("nav-{category}").into_boxed_str());
                let active = self.page == Page::Settings && self.area == category;
                self.nav_item(
                    id,
                    &label,
                    kit::area_glyph(&category),
                    active,
                    Some(format!("{on}/{total}")),
                    focus,
                    move |this| {
                        this.go_settings(&category);
                    },
                    cx,
                )
                .into_any_element()
            })
            .collect();
        let has_restore = data::edicao().has_restore();
        let page = self.page;
        let content = match page {
            Page::Home => self.home(cx),
            Page::Optimize => self.optimize(cx),
            Page::Programs => self.programs(window, cx),
            Page::Restore if has_restore => self.restore(cx),
            Page::Restore => self.home(cx),
            Page::Power | Page::Apps | Page::Services | Page::Advanced => self.manual_page(page, cx),
            Page::Settings => self.settings(window, cx),
            Page::Preferences => self.preferences(cx),
            Page::Logs => self.logs_page(cx),
        };
        let (power_on, power_total) = self.manual_counts(Page::Power);
        let (apps_on, apps_total) = self.manual_counts(Page::Apps);
        let (services_on, services_total) = self.manual_counts(Page::Services);
        let (adv_on, adv_total) = self.manual_counts(Page::Advanced);
        let optimize_tag = if self.is_selected_level_custom() {
            Some("Pers.".to_owned())
        } else {
            None
        };
        let nav = div()
            .w(px(NAV_W))
            .flex_shrink_0()
            .flex()
            .flex_col()
            .gap(px(4.))
            .pl(px(5.))
            .pr(px(3.))
            .pt(px(19.))
            .pb(px(7.))
            .child(self.nav_item(
                "nav-home",
                "Início",
                "\u{E80F}",
                page == Page::Home,
                None,
                home_focus,
                |t| t.go_page(Page::Home),
                cx,
            ))
            .child(self.nav_item(
                "nav-optimize",
                "Otimizar",
                "\u{E945}",
                page == Page::Optimize,
                optimize_tag,
                optimize_focus,
                |t| t.go_page(Page::Optimize),
                cx,
            ))
            .child(self.nav_item(
                "nav-programs",
                "Programas",
                "\u{E719}",
                page == Page::Programs,
                None,
                programs_focus,
                |t| t.go_page(Page::Programs),
                cx,
            ))
            .when(has_restore, |d| {
                d.child(self.nav_item(
                    "nav-restore",
                    "Restaurar",
                    "\u{E777}",
                    page == Page::Restore,
                    None,
                    restore_focus,
                    |t| t.go_page(Page::Restore),
                    cx,
                ))
            })
            .child(
                div()
                    .pl(px(12.))
                    .pt(px(22.))
                    .pb(px(10.))
                    .font_family(FONT_TEXT)
                    .font_weight(FontWeight::MEDIUM)
                    .text_size(px(12.))
                    .text_color(c(INK_SUBTLE))
                    .child("Manuais"),
            )
            .child(self.nav_item(
                "nav-power",
                "Energia",
                "\u{E83F}",
                page == Page::Power,
                Some(format!("{power_on}/{power_total}")),
                power_focus,
                |t| t.go_page(Page::Power),
                cx,
            ))
            .child(self.nav_item(
                "nav-apps",
                "Apps",
                "\u{E71D}",
                page == Page::Apps,
                Some(format!("{apps_on}/{apps_total}")),
                apps_focus,
                |t| t.go_page(Page::Apps),
                cx,
            ))
            .child(self.nav_item(
                "nav-services",
                "Serviços",
                "\u{E912}",
                page == Page::Services,
                Some(format!("{services_on}/{services_total}")),
                services_focus,
                |t| t.go_page(Page::Services),
                cx,
            ))
            .child(self.nav_item(
                "nav-advanced",
                "Avançado",
                "\u{E9E9}",
                page == Page::Advanced,
                Some(format!("{adv_on}/{adv_total}")),
                advanced_focus,
                |t| t.go_page(Page::Advanced),
                cx,
            ))
            .child(
                div()
                    .pl(px(12.))
                    .pt(px(22.))
                    .pb(px(10.))
                    .font_family(FONT_TEXT)
                    .font_weight(FontWeight::MEDIUM)
                    .text_size(px(12.))
                    .text_color(c(INK_SUBTLE))
                    .child("Ajustes"),
            )
            .children(area_items)
            .child(div().flex_1())
            .child(self.nav_item(
                "nav-prefs",
                "Preferências",
                "\u{E713}",
                page == Page::Preferences,
                None,
                prefs_focus,
                |t| t.go_page(Page::Preferences),
                cx,
            ))
            .child(self.nav_item(
                "nav-logs",
                "Registros",
                "\u{E9F9}",
                page == Page::Logs,
                None,
                logs_focus,
                |t| t.go_page(Page::Logs),
                cx,
            ));
        let brand = div()
            .w(px(NAV_W))
            .flex_shrink_0()
            .flex()
            .items_center()
            .gap(px(10.))
            .pl(px(22.))
            .child(kit::mark(22.))
            .child(
                div()
                    .font_family(FONT_DISPLAY)
                    .font_weight(FontWeight::SEMIBOLD)
                    .text_size(px(20.))
                    .text_color(c(INK))
                    .child("Vanta"),
            );
        // Os 3 papéis de parede oficiais do Visual Vanta já têm respiro escuro (#0B0A10) na esquerda/centro,
        // então o Início exibe a arte inteira sem escurecer.
        let layer_opacity = if page == Page::Home {
            0.
        } else if self.prefs.dim {
            1.
        } else {
            0.
        };
        // A foto cobre a janela presa ao canto superior direito (UniformToFill + Right/Top do Vanta 1).
        let viewport_h = f32::from(window.viewport_size().height);
        let scale = (viewport / 2560.).max(viewport_h / 1440.);
        let (photo_w, photo_h) = ((2560. * scale).ceil(), (1440. * scale).ceil());
        let work_layer = div()
            .absolute()
            .top_0()
            .left_0()
            .size_full()
            .opacity(layer_opacity)
            .flex()
            .child(div().h_full().w(gpui::relative(0.5)).bg(linear_gradient(
                90.,
                linear_color_stop(a(0x0B0A10F7), 0.),
                linear_color_stop(a(0x0B0A10D8), 1.),
            )))
            .child(div().h_full().flex_1().bg(linear_gradient(
                90.,
                linear_color_stop(a(0x0B0A10D8), 0.),
                linear_color_stop(a(0x0B0A1080), 1.),
            )));
        div()
            .id("vanta-tools-root")
            .track_focus(&self.root_focus)
            .on_action(|_: &FocusNext, window, cx| {
                window.focus_next(cx);
                focus_reveal::request(window, cx);
            })
            .on_action(|_: &FocusPrevious, window, cx| {
                window.focus_prev(cx);
                focus_reveal::request(window, cx);
            })
            .on_action(cx.listener(|this, _: &OpenSearch, window, cx| this.open_search(window, cx)))
            .on_key_down(cx.listener(|this, event: &gpui::KeyDownEvent, window, cx| {
                if this.search_open && event.keystroke.key == "enter" {
                    let query = this.search.read(cx).value().to_owned();
                    if let Some((_, _, target)) = this.search_hits(&query).into_iter().next() {
                        this.go(&target, window, cx);
                    }
                }
            }))
            .on_action(cx.listener(|this, _: &NavigateBack, window, cx| {
                if this.search_open {
                    this.close_search(window, cx);
                } else if this.page != Page::Home {
                    this.go_page(Page::Home);
                    cx.notify();
                }
            }))
            .relative()
            .map(page_keyboard_scrolling)
            .size_full()
            .bg(c(CANVAS))
            .text_color(c(INK))
            .font_family(FONT_TEXT)
            .child(
                img(kit::background_image(&self.prefs.background))
                    .absolute()
                    .top_0()
                    .right_0()
                    .w(px(photo_w))
                    .h(px(photo_h))
                    .object_fit(ObjectFit::Cover),
            )
            .when(layer_opacity > 0., |d| d.child(work_layer))
            .child(
                div()
                    .absolute()
                    .top_0()
                    .left_0()
                    .size_full()
                    .flex()
                    .flex_col()
                    .child(TitleBar::new("Vanta Tools").brand(brand).center(self.search_button(cx)))
                    .child(div().flex_1().min_h_0().flex().child(nav).child(content)),
            )
            .when(self.search_open, |root| root.child(self.search_overlay(cx)))
    }
}
