//! Dados do Vanta Tools: argumentos, catálogos embutidos, textos em linguagem simples e o kit de restauração.

use std::collections::HashMap;
use std::sync::OnceLock;

pub use vanta_core::edicao::Edicao;

use vanta_core::catalog::{SoftwareApp, SoftwareCatalog};
use vanta_core::fs::StdFs;
use vanta_core::guard::{GuardReport, inspect};
use vanta_core::manifest::{LoadedManifest, PackageHealth, read, summarize};
use vanta_core::path::join;
use vanta_core::restore::{
    RestoreContext, RestoreOptions, RestorePlan, Step, default_protected_roots, plan_restore,
};
use vanta_core::tweaks::Tweak;

use crate::ui::Icon;

// Diagnóstico do PC para o cartão "Este PC" (só leitura; ver `vanta_sys::diagnostics`).
#[allow(unused_imports)] // a tela liga estes tipos
pub use vanta_sys::diagnostics::{CoreIsolation, Gpu, GpuVendor, Monitor, PcDiagnostics, PowerPlan};

/// Lê o diagnóstico do PC numa thread própria e entrega o resultado a `done` (que deve só enviar por um canal ou
/// marcar a tela para redesenhar). A tela nunca espera: enquanto não chega, mostra "lendo…". Uma leitura que
/// falhe vira "desconhecido", nunca pânico.
#[allow(dead_code)] // a tela liga esta função
pub fn read_pc_in_background(done: impl FnOnce(PcDiagnostics) + Send + 'static) {
    std::thread::spawn(move || done(vanta_sys::diagnostics::read_system()));
}

/// A edição deste processo (o `VantaTools` é a pessoal, o `VantaToolsPublico` a pública). Definida uma vez, no início;
/// os carregadores de catálogo e a tela leem daqui, então ninguém precisa carregá-la de mão em mão.
static EDICAO: OnceLock<Edicao> = OnceLock::new();

pub fn set_edicao(edicao: Edicao) {
    let _ = EDICAO.set(edicao);
}

/// A edição em execução (a pessoal enquanto nada definir outra: testes, por exemplo).
pub fn edicao() -> Edicao {
    EDICAO.get().copied().unwrap_or_default()
}

#[derive(Clone, Debug, Default)]
pub struct Args {
    /// A edição pedida a quem criou os argumentos.
    #[allow(dead_code)] // a tela lê a edição por `edicao()`; o campo vale para quem monta `Args` à mão
    pub edicao: Edicao,
    /// `--kit <pasta>`: usa esta pasta como kit em vez de procurar nos discos.
    pub kit: Option<String>,
    /// `--page home|programs|restore|settings`: abre direto nessa tela. Na edição pública `restore` não existe: o
    /// pedido é ignorado e a tela abre no início.
    pub page: Option<String>,
}

impl Args {
    pub fn parse(edicao: Edicao, mut args: impl Iterator<Item = String>) -> Self {
        let mut parsed = Self { edicao, ..Self::default() };
        while let Some(arg) = args.next() {
            match arg.as_str() {
                "--kit" => parsed.kit = args.next(),
                "--page" => parsed.page = args.next().filter(|page| edicao.allows_page(page)),
                _ => {}
            }
        }
        parsed
    }
}

/// Textos em linguagem simples (`textos.json` do Vanta 1): descrição de cada ajuste e de cada programa.
#[derive(Default)]
pub struct Texts {
    pub tweaks: HashMap<String, String>,
    pub programs: HashMap<String, String>,
}

pub fn load_texts() -> Texts {
    let value: serde_json::Value =
        serde_json::from_str(include_str!("../../assets/tools/textos.json")).unwrap_or_default();
    let map = |key: &str| -> HashMap<String, String> {
        value
            .get(key)
            .and_then(|v| v.as_object())
            .map(|o| o.iter().filter_map(|(k, v)| Some((k.clone(), v.as_str()?.to_owned()))).collect())
            .unwrap_or_default()
    };
    Texts { tweaks: map("ajustes"), programs: map("programas") }
}

/// Os ajustes da edição em execução: todos na pessoal; na pública, só os marcados `publico`.
pub fn load_tweaks() -> Vec<Tweak> {
    edicao().tweaks()
}

/// Os programas da edição em execução (a pública não tem nenhum item que "vem do pacote").
pub fn load_software() -> SoftwareCatalog {
    edicao().software()
}

/// O nome da área na tela (a categoria do `tweaks.json` em português do dia a dia).
pub fn area_name(category: &str) -> &'static str {
    match category {
        "Geral" => "Privacidade e sistema",
        "Interface" => "Aparência",
        "Windows" => "Recursos do Windows",
        "Jogos" => "Jogos",
        "Avancado" => "Avançado",
        "Seguranca" => "Segurança",
        _ => "Outros",
    }
}

/// O ícone de cada área.
pub fn area_icon(category: &str) -> Icon {
    match category {
        "Geral" => Icon::Lock,
        "Interface" => Icon::Personalize,
        "Windows" => Icon::Apps,
        "Jogos" => Icon::Game,
        "Avancado" => Icon::Equalizer,
        "Seguranca" => Icon::Shield,
        _ => Icon::Settings,
    }
}

/// O que a tela de Restaurar mostra do kit.
pub struct KitInfo {
    pub path: String,
    pub loaded: LoadedManifest,
    pub guard: GuardReport,
    pub plan: RestorePlan,
    pub ctx: RestoreContext,
}

pub enum KitState {
    Missing,
    Invalid(String),
    Ready(Box<KitInfo>),
}

fn drive_roots() -> Vec<String> {
    ('C'..='Z').map(|c| format!("{c}:\\")).filter(|d| std::path::Path::new(d).exists()).collect()
}

/// Acha o kit (argumento, depois discos), confere o manifesto, passa a guarda e monta o plano. Só lê.
pub fn load_kit(explicit: Option<&str>) -> KitState {
    let path = match explicit {
        Some(path) => path.trim_end_matches('\\').to_owned(),
        None => {
            let summary = summarize(&StdFs, &drive_roots());
            match (summary.health, summary.package_path) {
                (PackageHealth::Missing, _) | (_, None) => return KitState::Missing,
                (_, Some(path)) => path,
            }
        }
    };
    let loaded = match read(&StdFs, &join(&path, "manifesto.json")) {
        Ok(loaded) => loaded,
        Err(error) => return KitState::Invalid(format!("{path}: {error}")),
    };
    let guard = inspect(&StdFs, &path, &loaded.manifest);
    let origins: Vec<String> = loaded.manifest.items.iter().map(|i| i.restore_path.clone()).collect();
    let ctx = RestoreContext {
        kit_root: path.clone(),
        old_profile: vanta_sys::restore_batch::old_profile_from_origins(&origins).unwrap_or_default(),
        current_profile: std::env::var("USERPROFILE").unwrap_or_default(),
        is_elevated: vanta_sys::elevate::is_elevated(),
        protected_roots: default_protected_roots(
            &std::env::var("SystemDrive").unwrap_or_else(|_| "C:".into()),
        ),
    };
    let plan = plan_restore(&loaded.manifest, &ctx, &RestoreOptions::default());
    KitState::Ready(Box::new(KitInfo { path, loaded, guard, plan, ctx }))
}

/// As linhas do plano em português, uma por passo.
pub fn describe_plan(plan: &RestorePlan) -> Vec<String> {
    plan.steps
        .iter()
        .map(|step| match step {
            Step::InstallPrograms => "Instalar os programas da lista do kit (winget, um por vez)".to_owned(),
            Step::CloseApps { processes } => {
                format!("Fechar {} app(s) que prendem configurações", processes.len())
            }
            Step::CopyConfigs { items } => {
                format!("Copiar {} configuração(ões) para o seu usuário", items.len())
            }
            Step::InstallNvidiaDriver => "Driver NVIDIA (depois dele, o perfil NVIDIA)".to_owned(),
            Step::ElevatedBatch { items, remaps } => format!(
                "Pastas do sistema, registro e tarefas em UM pedido de administrador ({} pasta(s){})",
                items.len(),
                if remaps.is_empty() { "" } else { ", microfone Fifine remapeado" }
            ),
            Step::CopyAfterDriver { items } => {
                format!("Copiar {} item(ns) que dependem do driver", items.len())
            }
            Step::RemapMicrophone { .. } => "Remapear o microfone Fifine no Equalizer APO".to_owned(),
        })
        .collect()
}

pub fn app_description<'a>(texts: &'a Texts, app: &SoftwareApp) -> Option<&'a str> {
    if !edicao().shows_package_origin() && app.name == "OBS Studio" {
        return Some("Grava e transmite tela e jogos.");
    }
    texts.programs.get(&app.name).map(String::as_str)
}
