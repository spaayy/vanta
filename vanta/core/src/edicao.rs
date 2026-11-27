//! As duas edições do Vanta Tools. A pessoal é a de hoje (todos os ajustes, "vem do pacote", Restaurar). A pública é a
//! dos amigos: só ajustes marcados `"publico": true`, o catálogo `software-publico.json` (sem item `fonte: pacote`) e
//! nenhuma tela de Restaurar.

use crate::catalog::{SoftwareCatalog, parse_software};
use crate::tweaks::{Tweak, parse_catalog};

const SOFTWARE_PESSOAL: &str = include_str!("../catalog/software.json");
const SOFTWARE_PUBLICO: &str = include_str!("../catalog/software-publico.json");
const TWEAKS: &str = include_str!("../catalog/tweaks.json");

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Edicao {
    /// O Vanta Tools do Nathan: tudo como está.
    #[default]
    Pessoal,
    /// O Vanta Tools dos amigos.
    Publica,
}

impl Edicao {
    /// A edição pública não restaura o kit de ninguém: sem a tela, sem `--page restore`.
    pub fn has_restore(self) -> bool {
        self == Self::Pessoal
    }

    /// Uma tela pedida por nome (`--page`). `restore` só existe na pessoal; o nome é lido sem diferenciar maiúsculas.
    pub fn allows_page(self, page: &str) -> bool {
        self.has_restore() || !page.trim().eq_ignore_ascii_case("restore")
    }

    /// Mostra "Vem do pacote" nos programas sem instalador automático (só faz sentido para o dono do kit).
    pub fn shows_package_origin(self) -> bool {
        self == Self::Pessoal
    }

    pub fn software(self) -> SoftwareCatalog {
        let json = match self {
            Self::Pessoal => SOFTWARE_PESSOAL,
            Self::Publica => SOFTWARE_PUBLICO,
        };
        parse_software(json).unwrap_or_default()
    }

    /// Os ajustes da edição: todos na pessoal; na pública, só os `publico: true` (o que não tem o campo fica de fora).
    pub fn tweaks(self) -> Vec<Tweak> {
        let all = parse_catalog(TWEAKS).unwrap_or_default();
        match self {
            Self::Pessoal => all,
            Self::Publica => all.into_iter().filter(|tweak| tweak.public).collect(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Ajustes que o Cabeça manteve só na edição pessoal (nada disto pode vazar para o público).
    /// Só estes 10 ficam fora da pública: específicos do PC do autor ou arriscados em hardware de terceiros.
    const ONLY_PERSONAL: [&str; 10] = [
        "wu-drivers-off",
        "spooler-off",
        "bluetooth-off",
        "numlock-off",
        "printscreen-snip-off",
        "nagle-off",
        "net-throttle-off",
        "tcp-ports",
        "paging-exec-off",
        "coalescing-off",
    ];

    #[test]
    fn the_public_edition_has_no_package_sourced_program_and_none_of_the_personal_apps() {
        let catalog = Edicao::Publica.software();
        assert!(!catalog.categories.is_empty(), "o catálogo público precisa carregar");
        for app in catalog.apps() {
            assert!(
                !app.source.as_deref().is_some_and(|s| s.eq_ignore_ascii_case("pacote")),
                "{} vem do pacote",
                app.name
            );
        }
        let names: Vec<&str> = catalog.apps().map(|a| a.name.as_str()).collect();
        for personal in ["Riot Client", "Equalizer APO + Peace", "Overview", "BatteryHub-plus", "LMUFFB"] {
            assert!(!names.contains(&personal), "{personal} é da edição pessoal");
        }
        let category = |name: &str| catalog.categories.iter().find(|c| c.name == name);
        assert!(category("Seus apps").is_none(), "sem 'Seus apps'");
        assert!(category("Driver de vídeo").is_none(), "'Driver de vídeo' virou 'NVCleanstall'");
    }

    #[test]
    fn the_public_communication_and_nvidia_categories_are_as_agreed() {
        let catalog = Edicao::Publica.software();
        let communication = catalog.categories.iter().find(|c| c.name == "Comunicação").unwrap();
        let names: Vec<&str> = communication.apps.iter().map(|a| a.name.as_str()).collect();
        assert_eq!(names, ["Discord", "TeamSpeak 3", "ZapFast"]);
        assert_eq!(communication.apps[0].extra.as_deref(), Some("Vencord"));
        assert_eq!(communication.apps[2].reference.as_deref(), Some("crmne/zapfast"));
        let nvidia = catalog.categories.iter().find(|c| c.name == "NVCleanstall").unwrap();
        assert_eq!(nvidia.apps.len(), 1);
        assert_eq!(nvidia.apps[0].winget_id.as_deref(), Some("TechPowerUp.NVCleanstall"));
        assert!(!nvidia.apps[0].name.contains("610"), "a 610.88 fica só na edição pessoal");
        for kept in ["IA", "Dev e terminal", "Rede", "Ferramentas", "Gravação e mídia", "Periféricos e áudio"]
        {
            assert!(catalog.categories.iter().any(|c| c.name == kept), "{kept}");
        }
        let media = catalog.categories.iter().find(|c| c.name == "Gravação e mídia").unwrap();
        assert!(media.apps.iter().any(|a| a.name == "Spotifast"));
    }

    #[test]
    fn the_personal_edition_keeps_the_current_catalogs_untouched() {
        let software = Edicao::Pessoal.software();
        assert_eq!(software, parse_software(include_str!("../catalog/software.json")).unwrap());
        assert!(
            software.apps().any(|a| a.source.as_deref() == Some("pacote")),
            "o pessoal continua com 'pacote'"
        );
        assert!(software.categories.iter().any(|c| c.name == "Seus apps"));
        let nvidia = software.categories.iter().find(|c| c.name == "Driver de vídeo").unwrap();
        assert_eq!(nvidia.apps[0].name, "NVCleanstall (NVIDIA 610.88)");
        let all = parse_catalog(include_str!("../catalog/tweaks.json")).unwrap();
        assert_eq!(Edicao::Pessoal.tweaks(), all, "todos os ajustes, na ordem do arquivo");
        assert_eq!(all.len(), 73);
    }

    #[test]
    fn the_public_edition_only_gets_tweaks_marked_public_and_none_of_the_personal_ones() {
        let all = parse_catalog(include_str!("../catalog/tweaks.json")).unwrap();
        let public = Edicao::Publica.tweaks();
        assert_eq!(public.len(), 63);
        assert!(public.iter().all(|t| t.public), "só publico: true");
        assert_eq!(public.len(), all.iter().filter(|t| t.public).count());
        for id in ONLY_PERSONAL {
            assert!(all.iter().any(|t| t.id == id), "{id} existe no catálogo");
            assert!(!public.iter().any(|t| t.id == id), "{id} vazou para a edição pública");
        }
        for id in
            ["vbs-hvci", "smartscreen", "uac-secure", "motw", "hags-on", "sysmain-off", "search-index-off", "win32-priority", "mpo-off", "timer-global", "windowed-opt-off"]
        {
            assert!(public.iter().any(|t| t.id == id), "{id} devia estar na pública");
        }
    }

    #[test]
    fn a_tweak_without_the_public_field_stays_out_of_the_public_edition() {
        let json = r#"[{"id":"a","categoria":"Geral","titulo":"A","descricao":"a",
            "registro":[{"chave":"HKCU\\X","valor":"V","tipo":"DWORD","ligado":1,"desligado":0}]}]"#;
        let tweak = &parse_catalog(json).unwrap()[0];
        assert!(!tweak.public);
    }

    #[test]
    fn the_public_edition_has_no_restore_route() {
        assert!(Edicao::Pessoal.has_restore());
        assert!(!Edicao::Publica.has_restore());
        for page in ["restore", "Restore", " RESTORE "] {
            assert!(Edicao::Pessoal.allows_page(page), "{page}");
            assert!(!Edicao::Publica.allows_page(page), "{page}");
        }
        for page in ["home", "programs", "settings"] {
            assert!(Edicao::Publica.allows_page(page), "{page}");
        }
        assert!(Edicao::Pessoal.shows_package_origin());
        assert!(!Edicao::Publica.shows_package_origin());
    }
}
