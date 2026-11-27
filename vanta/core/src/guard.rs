//! Guarda de proibidos: recusa um kit que leve credencial, cookie, dado de IA ou chave, e diz o caminho.
//!
//! Regras por nome (qualquer componente do caminho, sem diferenciar maiúsculas):
//! `id_*`, `*.pem`, `*.ppk`, `Cookies`, `Cookies-journal`, `Login Data*`, `Local State`, `.claude*`, `claude-mem*`,
//! `Brave-Browser`/`BraveSoftware`, `.ssh`, `userdata` (Steam) e `obs-websocket`; mais o conteúdo: um
//! `config.json` dentro de `obs-studio` com `server_password` preenchida. A guarda confere os itens do manifesto
//! (origem e destino) e as árvores deles no kit; não olha `instaladores`.

use std::fmt;

use crate::fs::Fs;
use crate::manifest::Manifest;
use crate::path::{file_name, join, resolve_inside_root};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Rule {
    PrivateKey,
    Cookies,
    BrowserLogins,
    BrowserLocalState,
    ClaudeData,
    ClaudeMem,
    Brave,
    SshFolder,
    SteamUserdata,
    ObsWebsocket,
    ObsWebsocketPassword,
    /// O item aponta para fora da pasta do pacote.
    UnsafeKitPath,
    /// Atalho/junção dentro do kit: a restauração não os segue.
    LinkInKit,
}

impl Rule {
    pub fn describe(self) -> &'static str {
        match self {
            Self::PrivateKey => "chave privada ou certificado (id_*, *.pem, *.ppk)",
            Self::Cookies => "cookies de navegador",
            Self::BrowserLogins => "senhas salvas do navegador (Login Data)",
            Self::BrowserLocalState => "estado local do navegador (Local State, guarda a chave dos cookies)",
            Self::ClaudeData => "dados do Claude (.claude)",
            Self::ClaudeMem => "memória do Claude (claude-mem)",
            Self::Brave => "perfil do Brave",
            Self::SshFolder => "pasta .ssh",
            Self::SteamUserdata => "userdata do Steam (tokens de login)",
            Self::ObsWebsocket => "configuração do websocket do OBS",
            Self::ObsWebsocketPassword => "senha do websocket do OBS",
            Self::UnsafeKitPath => "caminho do item fora da pasta do pacote",
            Self::LinkInKit => "atalho ou junção dentro do kit",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Violation {
    pub rule: Rule,
    /// Caminho relativo ao kit (ou a origem/destino do item, no caso de regra do manifesto).
    pub path: String,
}

impl fmt::Display for Violation {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}: {}", self.path, self.rule.describe())
    }
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct GuardReport {
    pub violations: Vec<Violation>,
    pub scanned_items: usize,
    pub scanned_entries: usize,
}

impl GuardReport {
    pub fn is_clean(&self) -> bool {
        self.violations.is_empty()
    }
}

impl fmt::Display for GuardReport {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        if self.is_clean() {
            return write!(
                f,
                "Kit limpo: {} item(ns), {} entrada(s) conferidas.",
                self.scanned_items, self.scanned_entries
            );
        }
        writeln!(f, "Kit recusado: {} problema(s).", self.violations.len())?;
        for v in &self.violations {
            writeln!(f, "  - {v}")?;
        }
        Ok(())
    }
}

/// Qual regra de nome pega um componente de caminho (um nome de arquivo ou pasta).
pub fn classify_component(component: &str) -> Option<Rule> {
    let n = component.trim().to_lowercase();
    if n.starts_with("id_") || n.ends_with(".pem") || n.ends_with(".ppk") {
        Some(Rule::PrivateKey)
    } else if n == "cookies" || n == "cookies-journal" {
        Some(Rule::Cookies)
    } else if n.starts_with("login data") {
        Some(Rule::BrowserLogins)
    } else if n == "local state" {
        Some(Rule::BrowserLocalState)
    } else if n.starts_with(".claude") {
        Some(Rule::ClaudeData)
    } else if n.starts_with("claude-mem") {
        Some(Rule::ClaudeMem)
    } else if n == "brave-browser" || n == "bravesoftware" {
        Some(Rule::Brave)
    } else if n == ".ssh" {
        Some(Rule::SshFolder)
    } else if n == "userdata" {
        Some(Rule::SteamUserdata)
    } else if n == "obs-websocket" {
        Some(Rule::ObsWebsocket)
    } else {
        None
    }
}

/// A primeira regra que algum componente do caminho (barras `\` ou `/`) violar.
pub fn classify_path(path: &str) -> Option<Rule> {
    path.split(['\\', '/']).filter(|c| !c.is_empty()).find_map(classify_component)
}

fn has_component(path: &str, wanted: &str) -> bool {
    path.split(['\\', '/']).any(|c| c.eq_ignore_ascii_case(wanted))
}

fn obs_password_is_set(json: &str) -> bool {
    serde_json::from_str::<serde_json::Value>(json.trim_start_matches('\u{feff}'))
        .ok()
        .and_then(|v| v.get("server_password").and_then(|p| p.as_str().map(|s| !s.is_empty())))
        .unwrap_or(false)
}

/// Confere o manifesto e as árvores dos itens no kit. Pastas proibidas não são percorridas por dentro.
pub fn inspect(fs: &dyn Fs, kit_root: &str, manifest: &Manifest) -> GuardReport {
    let mut report = GuardReport::default();
    for item in &manifest.items {
        report.scanned_items += 1;
        for declared in [&item.restore_path, &item.kit_path] {
            if let Some(rule) = classify_path(declared) {
                report.violations.push(Violation { rule, path: declared.clone() });
            }
        }
        let Ok(root) = resolve_inside_root(kit_root, &item.kit_path) else {
            report.violations.push(Violation { rule: Rule::UnsafeKitPath, path: item.kit_path.clone() });
            continue;
        };
        if !fs.exists(&root) {
            continue; // item ausente no kit: a restauração avisa; a guarda só olha o que existe
        }
        let relative_root = item.kit_path.replace('/', "\\");
        if fs.is_dir(&root) {
            walk(fs, &root, &relative_root, &mut report);
        } else {
            report.scanned_entries += 1;
            check_file(fs, &root, &relative_root, &mut report);
        }
    }
    report
}

fn check_file(fs: &dyn Fs, absolute: &str, relative: &str, report: &mut GuardReport) {
    if file_name(absolute).eq_ignore_ascii_case("config.json")
        && has_component(relative, "obs-studio")
        && fs.read_to_string(absolute).is_ok_and(|text| obs_password_is_set(&text))
    {
        report.violations.push(Violation { rule: Rule::ObsWebsocketPassword, path: relative.to_owned() });
    }
}

fn walk(fs: &dyn Fs, absolute: &str, relative: &str, report: &mut GuardReport) {
    let Ok(entries) = fs.read_dir(absolute) else { return };
    for entry in entries {
        report.scanned_entries += 1;
        let child_abs = join(absolute, &entry.name);
        let child_rel = join(relative, &entry.name);
        if entry.is_link {
            report.violations.push(Violation { rule: Rule::LinkInKit, path: child_rel });
            continue;
        }
        if let Some(rule) = classify_component(&entry.name) {
            report.violations.push(Violation { rule, path: child_rel });
            continue; // não entra no que já está barrado
        }
        if entry.is_dir {
            walk(fs, &child_abs, &child_rel, report);
        } else {
            check_file(fs, &child_abs, &child_rel, report);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::manifest::parse;
    use crate::testing::MemFs;

    const KIT: &str = r"K:\MeuPlaybook\pacote";

    fn manifest(items: &[(&str, &str, &str)]) -> Manifest {
        let list: Vec<String> = items
            .iter()
            .map(|(name, kit, origin)| {
                format!(
                    r#"{{"tipo":"pasta","nome":"{name}","destino":"{}","origem":"{}"}}"#,
                    kit.replace('\\', "\\\\"),
                    origin.replace('\\', "\\\\")
                )
            })
            .collect();
        parse(&format!(r#"{{"itens":[{}]}}"#, list.join(","))).unwrap()
    }

    #[test]
    fn every_forbidden_name_is_caught_whatever_its_case() {
        for (name, rule) in [
            ("id_rsa", Rule::PrivateKey),
            ("ID_ED25519.pub", Rule::PrivateKey),
            ("server.PEM", Rule::PrivateKey),
            ("putty.ppk", Rule::PrivateKey),
            ("Cookies", Rule::Cookies),
            ("cookies-journal", Rule::Cookies),
            ("Login Data", Rule::BrowserLogins),
            ("Login Data For Account", Rule::BrowserLogins),
            ("Local State", Rule::BrowserLocalState),
            (".claude", Rule::ClaudeData),
            (".claude.json", Rule::ClaudeData),
            ("claude-mem", Rule::ClaudeMem),
            ("BraveSoftware", Rule::Brave),
            ("Brave-Browser", Rule::Brave),
            (".ssh", Rule::SshFolder),
            ("userdata", Rule::SteamUserdata),
            ("obs-websocket", Rule::ObsWebsocket),
        ] {
            assert_eq!(classify_component(name), Some(rule), "{name}");
        }
    }

    #[test]
    fn ordinary_names_are_not_caught() {
        for name in [
            "settings.json",
            "config.txt",
            "idle.png",
            "Brave.Brave",
            "claude.exe",
            "state.json",
            "pem",
            "mycookies.txt",
        ] {
            assert_eq!(classify_component(name), None, "{name}");
        }
        assert_eq!(classify_path(r"config\obs-studio\basic\scenes\a.json"), None);
        assert_eq!(classify_path("config/git/.ssh/known_hosts"), Some(Rule::SshFolder));
    }

    #[test]
    fn a_clean_kit_passes_and_counts_what_it_read() {
        let fs = MemFs::new();
        fs.add_file(&format!(r"{KIT}\config\vlc\vlcrc"), "x");
        fs.add_file(&format!(r"{KIT}\config\vlc\skins\a.vlt"), "x");
        fs.add_file(&format!(r"{KIT}\config\git\.gitconfig"), "x");
        let m = manifest(&[
            ("VLC", r"config\vlc", r"C:\Users\Old\AppData\Roaming\vlc"),
            ("Git", r"config\git\.gitconfig", r"C:\Users\Old\.gitconfig"),
        ]);
        let report = inspect(&fs, KIT, &m);
        assert!(report.is_clean(), "{report}");
        assert_eq!((report.scanned_items, report.scanned_entries), (2, 4));
    }

    #[test]
    fn a_forbidden_file_is_refused_with_its_kit_path() {
        let fs = MemFs::new();
        fs.add_file(&format!(r"{KIT}\config\git\.ssh\id_ed25519"), "KEY");
        fs.add_file(&format!(r"{KIT}\config\git\gitconfig"), "x");
        fs.add_file(&format!(r"{KIT}\config\app\Network\Cookies"), "x");
        let m = manifest(&[
            ("Git", r"config\git", r"C:\Users\Old\git"),
            ("App", r"config\app", r"C:\Users\Old\app"),
        ]);
        let report = inspect(&fs, KIT, &m);
        let found: Vec<_> = report.violations.iter().map(|v| (v.rule, v.path.as_str())).collect();
        assert_eq!(
            found,
            [(Rule::SshFolder, r"config\git\.ssh"), (Rule::Cookies, r"config\app\Network\Cookies")]
        );
        assert!(report.to_string().contains(r"config\git\.ssh"));
    }

    #[test]
    fn a_forbidden_folder_is_reported_once_and_not_entered() {
        let fs = MemFs::new();
        for n in 0..50 {
            fs.add_file(&format!(r"{KIT}\config\steam\userdata\123\f{n}.vdf"), "x");
        }
        let report = inspect(&fs, KIT, &manifest(&[("Steam", r"config\steam", r"C:\Steam")]));
        assert_eq!(report.violations.len(), 1);
        assert_eq!(report.scanned_entries, 1);
    }

    #[test]
    fn obs_websocket_folder_and_password_are_refused() {
        let fs = MemFs::new();
        fs.add_file(
            &format!(r"{KIT}\config\obs-studio\plugin_config\obs-websocket\config.json"),
            r#"{"server_password":"x"}"#,
        );
        let report =
            inspect(&fs, KIT, &manifest(&[("OBS", r"config\obs-studio", r"C:\Users\Old\obs-studio")]));
        assert_eq!(report.violations[0].rule, Rule::ObsWebsocket);
    }

    #[test]
    fn an_obs_config_with_a_password_is_refused_but_an_empty_one_is_not() {
        let with_password = MemFs::new();
        with_password.add_file(
            &format!(r"{KIT}\config\obs-studio\ws\config.json"),
            r#"{"server_enabled":true,"server_password":"s3cret"}"#,
        );
        let m = manifest(&[("OBS", r"config\obs-studio", r"C:\Users\Old\obs-studio")]);
        let report = inspect(&with_password, KIT, &m);
        assert_eq!(
            report.violations,
            [Violation {
                rule: Rule::ObsWebsocketPassword,
                path: r"config\obs-studio\ws\config.json".into()
            }]
        );

        let empty = MemFs::new();
        empty.add_file(
            &format!(r"{KIT}\config\obs-studio\ws\config.json"),
            "\u{feff}{\"server_password\":\"\"}",
        );
        assert!(inspect(&empty, KIT, &m).is_clean());
        let other = MemFs::new();
        other.add_file(&format!(r"{KIT}\config\other\config.json"), r#"{"server_password":"x"}"#);
        assert!(
            inspect(&other, KIT, &manifest(&[("O", r"config\other", r"C:\o")])).is_clean(),
            "só vale dentro do OBS"
        );
    }

    #[test]
    fn the_manifest_itself_is_checked_even_when_the_kit_lacks_the_item() {
        let m = manifest(&[(
            "Brave",
            r"config\brave",
            r"C:\Users\Old\AppData\Local\BraveSoftware\Brave-Browser\User Data",
        )]);
        let report = inspect(&MemFs::new(), KIT, &m);
        assert_eq!(report.violations.len(), 1);
        assert_eq!(report.violations[0].rule, Rule::Brave);
        assert!(report.violations[0].path.contains("BraveSoftware"));
    }

    #[test]
    fn an_item_that_escapes_the_kit_is_refused() {
        let m = manifest(&[("Fora", r"..\outside", r"C:\x")]);
        let report = inspect(&MemFs::new(), KIT, &m);
        assert_eq!(report.violations, [Violation { rule: Rule::UnsafeKitPath, path: r"..\outside".into() }]);
    }

    #[test]
    fn links_inside_the_kit_are_refused() {
        let fs = MemFs::new();
        fs.add_file(&format!(r"{KIT}\config\a\ok.txt"), "x");
        fs.add_link_dir(&format!(r"{KIT}\config\a\junction"));
        let report = inspect(&fs, KIT, &manifest(&[("A", r"config\a", r"C:\a")]));
        assert_eq!(
            report.violations,
            [Violation { rule: Rule::LinkInKit, path: r"config\a\junction".into() }]
        );
    }

    #[test]
    fn installers_are_not_scanned() {
        let fs = MemFs::new();
        fs.add_file(&format!(r"{KIT}\instaladores\winget\Brave.Brave\BraveBrowserSetup.exe"), "x");
        fs.add_file(&format!(r"{KIT}\instaladores\x\Cookies"), "x");
        fs.add_file(&format!(r"{KIT}\config\a\a.ini"), "x");
        assert!(inspect(&fs, KIT, &manifest(&[("A", r"config\a", r"C:\a")])).is_clean());
    }
}
