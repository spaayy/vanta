//! Manifesto do kit (`manifesto.json`): itens, SHA-256 e localização do pacote nos discos.

use std::fmt;

use serde::Deserialize;
use sha2::{Digest, Sha256};

use crate::fs::Fs;
use crate::path::join;

/// Um item do kit. `kit_path` (`destino` no JSON) é o caminho dentro do pacote; `restore_path` (`origem`)
/// é onde o item volta no Windows, com o perfil do PC antigo.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub struct KitItem {
    #[serde(rename = "tipo", default)]
    pub kind: String,
    #[serde(rename = "nome", default)]
    pub name: String,
    #[serde(rename = "destino", default)]
    pub kit_path: String,
    #[serde(rename = "origem", default)]
    pub restore_path: String,
    /// Código de saída do robocopy da coleta (informativo).
    #[serde(default)]
    pub robocopy: Option<i64>,
    /// Padrões que a coleta incluiu/excluiu (informativo; a guarda os ignora de propósito).
    #[serde(rename = "incluir", default)]
    pub include: Vec<String>,
    #[serde(rename = "excluir", default)]
    pub exclude: Vec<String>,
}

impl KitItem {
    pub fn is_folder(&self) -> bool {
        self.kind.eq_ignore_ascii_case("pasta")
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub struct Manifest {
    #[serde(rename = "data", default)]
    pub collected_at: Option<String>,
    #[serde(rename = "itens", default)]
    pub items: Vec<KitItem>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ManifestError {
    NotFound(String),
    InvalidJson(String),
    MissingItems,
    IncompleteItem,
    Io(String),
}

impl fmt::Display for ManifestError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::NotFound(_) => f.write_str("O pacote não contém manifesto.json."),
            Self::InvalidJson(detail) => write!(f, "O manifesto do pacote contém JSON inválido: {detail}"),
            Self::MissingItems => f.write_str("O manifesto precisa conter a lista 'itens'."),
            Self::IncompleteItem => {
                f.write_str("Cada item do manifesto precisa de nome, tipo, destino e origem.")
            }
            Self::Io(detail) => write!(f, "Não foi possível ler o manifesto: {detail}"),
        }
    }
}

impl std::error::Error for ManifestError {}

/// Interpreta o texto do manifesto e confere os campos de cada item.
pub fn parse(json: &str) -> Result<Manifest, ManifestError> {
    let json = json.trim_start_matches('\u{feff}');
    let value: serde_json::Value =
        serde_json::from_str(json).map_err(|e| ManifestError::InvalidJson(e.to_string()))?;
    if !value.get("itens").is_some_and(serde_json::Value::is_array) {
        return Err(ManifestError::MissingItems);
    }
    let manifest: Manifest =
        serde_json::from_value(value).map_err(|e| ManifestError::InvalidJson(e.to_string()))?;
    if manifest
        .items
        .iter()
        .any(|i| [&i.name, &i.kind, &i.kit_path, &i.restore_path].iter().any(|v| v.trim().is_empty()))
    {
        return Err(ManifestError::IncompleteItem);
    }
    Ok(manifest)
}

/// SHA-256 em hexadecimal minúsculo.
pub fn sha256_hex(bytes: &[u8]) -> String {
    Sha256::digest(bytes).iter().map(|b| format!("{b:02x}")).collect()
}

/// Manifesto lido do disco, com o SHA-256 do arquivo.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LoadedManifest {
    pub manifest: Manifest,
    pub sha256: String,
}

pub fn read(fs: &dyn Fs, manifest_path: &str) -> Result<LoadedManifest, ManifestError> {
    if !fs.exists(manifest_path) {
        return Err(ManifestError::NotFound(manifest_path.to_owned()));
    }
    let bytes = fs.read_bytes(manifest_path).map_err(|e| ManifestError::Io(e.to_string()))?;
    let text = String::from_utf8_lossy(&bytes);
    Ok(LoadedManifest { manifest: parse(&text)?, sha256: sha256_hex(&bytes) })
}

/// Procura `<disco>\MeuPlaybook\pacote` e depois `<disco>\MeuPlaybook` com um `manifesto.json`.
pub fn locate(fs: &dyn Fs, drive_roots: &[String]) -> Option<String> {
    for root in drive_roots.iter().filter(|r| !r.trim().is_empty()) {
        for candidate in [join(root, r"MeuPlaybook\pacote"), join(root, "MeuPlaybook")] {
            if fs.exists(&join(&candidate, "manifesto.json")) {
                return Some(candidate);
            }
        }
    }
    None
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PackageHealth {
    Missing,
    Ready,
    Invalid,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PackageSummary {
    pub health: PackageHealth,
    pub package_path: Option<String>,
    pub configuration_count: usize,
    pub message: String,
}

/// Acha o pacote e diz se o manifesto é válido, sem falhar.
pub fn summarize(fs: &dyn Fs, drive_roots: &[String]) -> PackageSummary {
    let Some(package) = locate(fs, drive_roots) else {
        return PackageSummary {
            health: PackageHealth::Missing,
            package_path: None,
            configuration_count: 0,
            message: "Conecte o disco do pacote ou selecione a pasta manualmente.".into(),
        };
    };
    match read(fs, &join(&package, "manifesto.json")) {
        Ok(loaded) => PackageSummary {
            health: PackageHealth::Ready,
            package_path: Some(package),
            configuration_count: loaded.manifest.items.len(),
            message: "Pacote encontrado e manifesto válido.".into(),
        },
        Err(error) => PackageSummary {
            health: PackageHealth::Invalid,
            package_path: Some(package),
            configuration_count: 0,
            message: error.to_string(),
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testing::MemFs;

    fn package(fs: &MemFs, drive: &str, manifest: &str) -> String {
        let dir = join(drive, r"MeuPlaybook\pacote");
        fs.add_file(&join(&dir, "manifesto.json"), manifest);
        dir
    }

    // PackageLocatorTests.FindsPackageOnMountedKitDrive
    #[test]
    fn finds_package_on_mounted_kit_drive() {
        let fs = MemFs::new();
        let dir = package(&fs, "K:", "{}");
        assert_eq!(locate(&fs, &["K:".into()]), Some(dir));
    }

    // PackageLocatorTests.ReturnsNullWhenNoValidPackageIsMounted
    #[test]
    fn returns_none_when_no_valid_package_is_mounted() {
        let fs = MemFs::new();
        fs.add_dir(r"K:\MeuPlaybook\pacote");
        assert_eq!(locate(&fs, &["K:".into(), "".into()]), None);
    }

    #[test]
    fn falls_back_to_the_playbook_folder_itself() {
        let fs = MemFs::new();
        fs.add_file(r"E:\MeuPlaybook\manifesto.json", "{}");
        assert_eq!(locate(&fs, &["D:".into(), "E:".into()]).as_deref(), Some(r"E:\MeuPlaybook"));
    }

    // PackageManifestReaderTests.ReadsManifestWithItemsAndNames
    #[test]
    fn reads_manifest_with_items_and_names() {
        let json = r#"{
          "data": "2026-11-21",
          "itens": [
            { "tipo": "pasta", "nome": "OBS", "destino": "config/obs", "origem": "C:/Users/Old/AppData/Roaming/obs-studio" },
            { "tipo": "arquivo", "nome": "Git config", "destino": "config/gitconfig", "origem": "C:/Users/Old/.gitconfig" }
          ]
        }"#;
        let fs = MemFs::new();
        fs.add_file(r"K:\manifesto.json", json);
        let loaded = read(&fs, r"K:\manifesto.json").unwrap();
        assert_eq!(loaded.manifest.collected_at.as_deref(), Some("2026-11-21"));
        assert_eq!(loaded.manifest.items.len(), 2);
        assert_eq!(loaded.manifest.items[0].name, "OBS");
        assert_eq!(loaded.manifest.items[1].name, "Git config");
        assert!(loaded.manifest.items[0].is_folder() && !loaded.manifest.items[1].is_folder());
        assert_eq!(loaded.sha256, sha256_hex(json.as_bytes()));
    }

    // PackageManifestReaderTests.RejectsManifestWithoutItems
    #[test]
    fn rejects_manifest_without_items() {
        let error = parse(r#"{ "data": "now" }"#).unwrap_err();
        assert_eq!(error, ManifestError::MissingItems);
        assert!(error.to_string().to_lowercase().contains("itens"));
    }

    #[test]
    fn rejects_incomplete_items_and_bad_json_and_missing_file() {
        assert_eq!(
            parse(r#"{"itens":[{"tipo":"pasta","nome":"x","destino":"a"}]}"#),
            Err(ManifestError::IncompleteItem)
        );
        assert!(matches!(parse("not json"), Err(ManifestError::InvalidJson(_))));
        assert!(matches!(read(&MemFs::new(), r"K:\nada.json"), Err(ManifestError::NotFound(_))));
    }

    #[test]
    fn reads_the_optional_collection_fields() {
        let m = parse(r#"{"itens":[{"tipo":"pasta","nome":"n","destino":"d","origem":"o","robocopy":1,"incluir":["*.ini"],"excluir":["logs"]}]}"#).unwrap();
        assert_eq!(
            (m.items[0].robocopy, m.items[0].include.clone(), m.items[0].exclude.clone()),
            (Some(1), vec!["*.ini".into()], vec!["logs".into()])
        );
    }

    #[test]
    fn a_bom_does_not_break_the_manifest() {
        assert!(parse("\u{feff}{\"itens\":[]}").is_ok());
    }

    // PackageSummaryServiceTests.ReportsReadyPackageAndConfigurationCount
    #[test]
    fn reports_ready_package_and_configuration_count() {
        let fs = MemFs::new();
        let dir = package(
            &fs,
            "K:",
            r#"{ "itens": [
              { "tipo": "pasta", "nome": "OBS", "destino": "config/obs", "origem": "C:/Users/Old/obs" },
              { "tipo": "arquivo", "nome": "Git", "destino": "gitconfig", "origem": "C:/Users/Old/.gitconfig" } ] }"#,
        );
        let summary = summarize(&fs, &["K:".into()]);
        assert_eq!(summary.health, PackageHealth::Ready);
        assert_eq!(summary.package_path, Some(dir));
        assert_eq!(summary.configuration_count, 2);
    }

    // PackageSummaryServiceTests.ReportsInvalidManifestWithoutThrowing
    #[test]
    fn reports_invalid_manifest_without_failing() {
        let fs = MemFs::new();
        let dir = package(&fs, "K:", "not json");
        let summary = summarize(&fs, &["K:".into()]);
        assert_eq!(summary.health, PackageHealth::Invalid);
        assert_eq!(summary.package_path, Some(dir));
        assert!(!summary.message.is_empty());
        assert_eq!(summarize(&MemFs::new(), &["K:".into()]).health, PackageHealth::Missing);
    }
}
