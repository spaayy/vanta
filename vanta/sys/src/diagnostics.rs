//! Diagnóstico do PC para o cartão "Este PC" do Início. Só LÊ: nada é alterado no Windows.
//!
//! Cada leitura que falha vira "desconhecido" (`None` ou [`CoreIsolation::Unknown`]), sem pânico. A leitura real
//! ([`SystemProbe`]) fala com o Windows; a regra (o que cada dado significa) fica em [`diagnose`], que recebe um
//! [`PcProbe`] e por isso é testada com dados simulados.

use std::os::windows::process::CommandExt;
use std::process::Command;

use regex::Regex;
use windows::Win32::Graphics::Gdi::{
    DEVMODEW, ENUM_CURRENT_SETTINGS, ENUM_DISPLAY_SETTINGS_MODE, EnumDisplaySettingsW,
};
use windows::core::PCWSTR;
use windows_registry::LOCAL_MACHINE;

/// Plano de energia ativo.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PowerPlan {
    /// Nome como o Windows mostra (o do plano Vanta é "Vanta").
    pub name: String,
    /// GUID em minúsculas, sem chaves.
    pub guid: String,
    /// O plano ativo é o do Vanta (o nome contém "Vanta", sem diferenciar maiúsculas).
    pub is_vanta: bool,
}

/// Isolamento de núcleo (integridade de memória, HVCI).
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum CoreIsolation {
    On,
    Off,
    #[default]
    Unknown,
}

/// Taxa de atualização do monitor principal, em Hz.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Monitor {
    /// A taxa em uso agora.
    pub current_hz: u32,
    /// A maior taxa que o Windows lista para a resolução em uso.
    pub max_hz: u32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum GpuVendor {
    Nvidia,
    Amd,
    Intel,
    Other,
}

/// Placa de vídeo principal e a versão do driver.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Gpu {
    pub name: String,
    pub vendor: GpuVendor,
    /// A versão do driver como o Windows guarda (ex.: "32.0.16.1088").
    pub driver_version: String,
    /// A versão como o fabricante a mostra: NVIDIA vira "610.88"; nos outros é a do Windows.
    pub driver_label: String,
}

/// Tudo o que o cartão mostra. `None`/`Unknown` = a leitura falhou ou o dado não existe.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct PcDiagnostics {
    pub power_plan: Option<PowerPlan>,
    pub core_isolation: CoreIsolation,
    pub monitor: Option<Monitor>,
    pub gpu: Option<Gpu>,
}

/// Um adaptador de vídeo como o registro o descreve.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Adapter {
    pub name: String,
    pub driver_version: String,
}

/// Uma linha da lista de modos do monitor.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct DisplayMode {
    pub width: u32,
    pub height: u32,
    pub hz: u32,
}

/// De onde vêm os dados brutos. O real é [`SystemProbe`]; os testes usam um simulado.
pub trait PcProbe {
    /// Saída de `powercfg /getactivescheme`.
    fn active_scheme_text(&self) -> Option<String>;
    /// `HypervisorEnforcedCodeIntegrity\Enabled`.
    fn hvci_value(&self) -> Option<u32>;
    /// O modo em uso agora no monitor principal.
    fn current_mode(&self) -> Option<DisplayMode>;
    /// Todos os modos que o Windows lista para o monitor principal.
    fn all_modes(&self) -> Vec<DisplayMode>;
    fn adapters(&self) -> Vec<Adapter>;
}

/// Lê tudo, e o que falhar fica desconhecido. Não entra em pânico.
pub fn diagnose(probe: &dyn PcProbe) -> PcDiagnostics {
    PcDiagnostics {
        power_plan: probe.active_scheme_text().and_then(|text| parse_active_scheme(&text)),
        core_isolation: core_isolation(probe.hvci_value()),
        monitor: monitor(probe.current_mode(), &probe.all_modes()),
        gpu: pick_gpu(&probe.adapters()),
    }
}

/// O diagnóstico do PC de verdade.
pub fn read_system() -> PcDiagnostics {
    // Uma leitura que entrasse em pânico não pode derrubar a tela.
    std::panic::catch_unwind(|| diagnose(&SystemProbe)).unwrap_or_default()
}

/// "Esquema de Energia GUID: <guid>  (Nome)" em qualquer idioma: só o GUID e o parêntese importam.
pub fn parse_active_scheme(text: &str) -> Option<PowerPlan> {
    let pattern = Regex::new(r"([0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12})\s*\(([^)]*)\)").ok()?;
    let found = pattern.captures(text)?;
    let name = found[2].trim().to_owned();
    Some(PowerPlan { is_vanta: name.to_lowercase().contains("vanta"), guid: found[1].to_lowercase(), name })
}

/// 1 = ligado, 0 = desligado; sem o valor, o Windows não disse: desconhecido.
pub fn core_isolation(value: Option<u32>) -> CoreIsolation {
    match value {
        Some(1) => CoreIsolation::On,
        Some(0) => CoreIsolation::Off,
        _ => CoreIsolation::Unknown,
    }
}

/// A taxa em uso e a maior para a resolução em uso. 0 ou 1 Hz é "padrão do hardware" no Windows: não é leitura.
pub fn monitor(current: Option<DisplayMode>, modes: &[DisplayMode]) -> Option<Monitor> {
    let current = current.filter(|mode| mode.hz > 1)?;
    let max_hz = modes
        .iter()
        .filter(|mode| mode.width == current.width && mode.height == current.height)
        .map(|mode| mode.hz)
        .chain([current.hz])
        .max()
        .unwrap_or(current.hz);
    Some(Monitor { current_hz: current.hz, max_hz })
}

fn vendor_of(name: &str) -> GpuVendor {
    let name = name.to_lowercase();
    if name.contains("nvidia") || name.contains("geforce") || name.contains("quadro") {
        GpuVendor::Nvidia
    } else if name.contains("amd") || name.contains("radeon") {
        GpuVendor::Amd
    } else if name.contains("intel") {
        GpuVendor::Intel
    } else {
        GpuVendor::Other
    }
}

/// O Windows guarda o driver NVIDIA como "32.0.16.1088"; a NVIDIA o chama de 610.88: os 5 últimos dígitos do
/// terceiro e quarto números, com o ponto antes dos dois últimos.
pub fn nvidia_label(windows_version: &str) -> Option<String> {
    let parts: Vec<&str> = windows_version.trim().split('.').collect();
    if parts.len() != 4
        || parts.iter().any(|part| part.is_empty() || !part.bytes().all(|b| b.is_ascii_digit()))
    {
        return None;
    }
    let digits = format!("{}{}", parts[2], parts[3]);
    let tail = digits.get(digits.len().checked_sub(5)?..)?;
    Some(format!("{}.{}", &tail[..3], &tail[3..]))
}

/// A placa principal: uma dedicada (NVIDIA, depois AMD) antes da integrada; o adaptador básico da Microsoft e os
/// virtuais não contam.
pub fn pick_gpu(adapters: &[Adapter]) -> Option<Gpu> {
    let real = |adapter: &&Adapter| {
        let name = adapter.name.to_lowercase();
        !adapter.name.trim().is_empty()
            && !adapter.driver_version.trim().is_empty()
            && !name.contains("basic")
            && !name.contains("remote")
            && !name.contains("virtual")
            && !name.contains("hyper-v")
    };
    let rank = |adapter: &&Adapter| match vendor_of(&adapter.name) {
        GpuVendor::Nvidia => 0,
        GpuVendor::Amd => 1,
        GpuVendor::Intel => 2,
        GpuVendor::Other => 3,
    };
    let best = adapters.iter().filter(real).min_by_key(rank)?;
    let vendor = vendor_of(&best.name);
    let driver_label = match vendor {
        GpuVendor::Nvidia => nvidia_label(&best.driver_version),
        _ => None,
    }
    .unwrap_or_else(|| best.driver_version.clone());
    Some(Gpu {
        name: best.name.trim().to_owned(),
        vendor,
        driver_version: best.driver_version.clone(),
        driver_label,
    })
}

/// Leitura real. Tudo só leitura; falha vira `None`/vazio.
pub struct SystemProbe;

fn devmode(index: ENUM_DISPLAY_SETTINGS_MODE) -> Option<DisplayMode> {
    let mut mode = DEVMODEW { dmSize: size_of::<DEVMODEW>() as u16, ..Default::default() };
    // SAFETY: `mode` vive durante a chamada e `dmSize` diz o tamanho da estrutura; o nome nulo é o monitor principal.
    let ok = unsafe { EnumDisplaySettingsW(PCWSTR::null(), index, &mut mode) }.as_bool();
    ok.then_some(DisplayMode {
        width: mode.dmPelsWidth,
        height: mode.dmPelsHeight,
        hz: mode.dmDisplayFrequency,
    })
}

impl PcProbe for SystemProbe {
    fn active_scheme_text(&self) -> Option<String> {
        // CREATE_NO_WINDOW: sem janela de console piscando.
        let output =
            Command::new("powercfg").arg("/getactivescheme").creation_flags(0x0800_0000).output().ok()?;
        output.status.success().then(|| String::from_utf8_lossy(&output.stdout).into_owned())
    }

    fn hvci_value(&self) -> Option<u32> {
        LOCAL_MACHINE
            .open(r"SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity")
            .ok()?
            .get_u32("Enabled")
            .ok()
    }

    fn current_mode(&self) -> Option<DisplayMode> {
        devmode(ENUM_CURRENT_SETTINGS)
    }

    fn all_modes(&self) -> Vec<DisplayMode> {
        (0..4096).map_while(|index| devmode(ENUM_DISPLAY_SETTINGS_MODE(index))).collect()
    }

    fn adapters(&self) -> Vec<Adapter> {
        let Ok(class) = LOCAL_MACHINE
            .open(r"SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}")
        else {
            return Vec::new();
        };
        let Ok(keys) = class.keys() else { return Vec::new() };
        keys.filter(|name| name.len() == 4 && name.bytes().all(|b| b.is_ascii_digit()))
            .filter_map(|name| {
                let key = class.open(&name).ok()?;
                Some(Adapter {
                    name: key.get_string("DriverDesc").ok()?,
                    driver_version: key.get_string("DriverVersion").ok()?,
                })
            })
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[derive(Default)]
    struct Fake {
        scheme: Option<String>,
        hvci: Option<u32>,
        current: Option<DisplayMode>,
        modes: Vec<DisplayMode>,
        adapters: Vec<Adapter>,
    }

    impl PcProbe for Fake {
        fn active_scheme_text(&self) -> Option<String> {
            self.scheme.clone()
        }
        fn hvci_value(&self) -> Option<u32> {
            self.hvci
        }
        fn current_mode(&self) -> Option<DisplayMode> {
            self.current
        }
        fn all_modes(&self) -> Vec<DisplayMode> {
            self.modes.clone()
        }
        fn adapters(&self) -> Vec<Adapter> {
            self.adapters.clone()
        }
    }

    fn mode(width: u32, height: u32, hz: u32) -> DisplayMode {
        DisplayMode { width, height, hz }
    }

    fn adapter(name: &str, version: &str) -> Adapter {
        Adapter { name: name.into(), driver_version: version.into() }
    }

    #[test]
    fn the_active_plan_is_read_in_any_language_and_the_vanta_plan_is_recognised() {
        let en = "Power Scheme GUID: 381B4222-F694-41F0-9685-FF5BB260DF2E  (Balanced)";
        let pt = "GUID do Esquema de Energia: 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c  (Vanta)";
        let plan = parse_active_scheme(en).unwrap();
        assert_eq!(
            plan,
            PowerPlan {
                name: "Balanced".into(),
                guid: "381b4222-f694-41f0-9685-ff5bb260df2e".into(),
                is_vanta: false
            }
        );
        let vanta = parse_active_scheme(pt).unwrap();
        assert!(
            vanta.is_vanta && vanta.name == "Vanta" && vanta.guid == "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
        );
        assert!(
            parse_active_scheme("Vanta Gamer (8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c)").is_none(),
            "sem GUID antes do nome"
        );
        assert!(parse_active_scheme("").is_none() && parse_active_scheme("erro qualquer").is_none());
    }

    #[test]
    fn core_isolation_is_unknown_unless_windows_said_so() {
        assert_eq!(core_isolation(Some(1)), CoreIsolation::On);
        assert_eq!(core_isolation(Some(0)), CoreIsolation::Off);
        assert_eq!(core_isolation(None), CoreIsolation::Unknown);
        assert_eq!(core_isolation(Some(7)), CoreIsolation::Unknown);
    }

    #[test]
    fn the_monitor_gives_the_rate_in_use_and_the_best_one_for_that_resolution() {
        let modes =
            [mode(2560, 1440, 60), mode(2560, 1440, 360), mode(3840, 2160, 600), mode(2560, 1440, 144)];
        assert_eq!(
            monitor(Some(mode(2560, 1440, 60)), &modes),
            Some(Monitor { current_hz: 60, max_hz: 360 })
        );
        assert_eq!(monitor(Some(mode(2560, 1440, 360)), &[]), Some(Monitor { current_hz: 360, max_hz: 360 }));
        assert_eq!(
            monitor(Some(mode(1920, 1080, 0)), &modes),
            None,
            "0 Hz é o padrão do hardware, não uma leitura"
        );
        assert_eq!(monitor(Some(mode(1920, 1080, 1)), &modes), None);
        assert_eq!(monitor(None, &modes), None);
    }

    #[test]
    fn the_nvidia_driver_is_shown_the_way_nvidia_numbers_it() {
        assert_eq!(nvidia_label("32.0.16.1088").as_deref(), Some("610.88"));
        assert_eq!(nvidia_label("31.0.15.6188").as_deref(), Some("561.88"));
        assert_eq!(nvidia_label("30.0.14.9729").as_deref(), Some("497.29"));
        for bad in ["", "1.2.3", "a.b.c.d", "32.0.16.", "32.0.1.8"] {
            assert_eq!(nvidia_label(bad), None, "{bad:?}");
        }
    }

    #[test]
    fn the_main_card_is_the_dedicated_one_and_virtual_adapters_are_ignored() {
        let list = [
            adapter("Microsoft Basic Display Adapter", "10.0.26100.1"),
            adapter("Intel(R) UHD Graphics", "31.0.101.5333"),
            adapter("NVIDIA GeForce RTX 5090", "32.0.16.1088"),
        ];
        let gpu = pick_gpu(&list).unwrap();
        assert_eq!(gpu.vendor, GpuVendor::Nvidia);
        assert_eq!(
            (gpu.name.as_str(), gpu.driver_version.as_str(), gpu.driver_label.as_str()),
            ("NVIDIA GeForce RTX 5090", "32.0.16.1088", "610.88")
        );
        let amd = pick_gpu(&[adapter("AMD Radeon RX 7900", "31.0.24033.1003")]).unwrap();
        assert_eq!((amd.vendor, amd.driver_label.as_str()), (GpuVendor::Amd, "31.0.24033.1003"));
        assert_eq!(pick_gpu(&[adapter("Microsoft Basic Display Adapter", "10.0.1")]), None);
        assert_eq!(pick_gpu(&[adapter("NVIDIA GeForce", "")]), None, "sem versão não é leitura");
        assert_eq!(pick_gpu(&[]), None);
    }

    #[test]
    fn a_probe_that_reads_nothing_gives_all_unknown_and_never_fails() {
        let nothing = diagnose(&Fake::default());
        assert_eq!(nothing, PcDiagnostics::default());
        assert_eq!(nothing.core_isolation, CoreIsolation::Unknown);
    }

    #[test]
    fn a_full_probe_fills_every_field_and_one_failure_does_not_hide_the_rest() {
        let probe = Fake {
            scheme: Some("Power Scheme GUID: 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c  (Vanta)".into()),
            hvci: Some(1),
            current: Some(mode(2560, 1440, 360)),
            modes: vec![mode(2560, 1440, 360)],
            adapters: vec![adapter("NVIDIA GeForce RTX 5090", "32.0.16.1088")],
        };
        let all = diagnose(&probe);
        assert!(all.power_plan.as_ref().is_some_and(|p| p.is_vanta));
        assert_eq!(all.core_isolation, CoreIsolation::On);
        assert_eq!(all.monitor, Some(Monitor { current_hz: 360, max_hz: 360 }));
        assert_eq!(all.gpu.as_ref().map(|g| g.driver_label.as_str()), Some("610.88"));
        let partial = diagnose(&Fake { scheme: None, ..probe });
        assert!(partial.power_plan.is_none() && partial.gpu.is_some() && partial.monitor.is_some());
    }

    #[test]
    fn the_real_probe_returns_without_panicking_or_changing_anything() {
        // Só garante que a leitura real termina e devolve um valor (o conteúdo depende do PC).
        let found = read_system();
        eprintln!("{found:#?}");
    }
}
