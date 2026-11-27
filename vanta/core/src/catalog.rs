//! Catálogo de programas (`software.json`): categorias, padrões e fonte de instalação.

use std::collections::HashSet;
use std::fmt;

use serde_json::Value;

use crate::fs::Fs;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SoftwareApp {
    pub name: String,
    pub winget_id: Option<String>,
    pub source: Option<String>,
    pub reference: Option<String>,
    pub default: bool,
    pub interactive: bool,
    pub note: Option<String>,
    pub extra: Option<String>,
    pub category: String,
}

/// Prefixo do id de um programa instalado da última release de um repositório do GitHub.
pub const GITHUB_PREFIX: &str = "github:";

/// `dono/repositorio` do GitHub: letras, dígitos, `.`, `_` e `-`, sem `..` nem barras a mais.
pub fn is_github_repo(text: &str) -> bool {
    let part = |p: &str| {
        !p.is_empty()
            && p != "."
            && p != ".."
            && p.len() <= 100
            && p.chars().all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '-'))
    };
    text.split_once('/').is_some_and(|(owner, repo)| part(owner) && part(repo))
}

/// O `dono/repositorio` de um id `github:dono/repositorio`, se for válido.
pub fn github_repo(id: &str) -> Option<&str> {
    id.strip_prefix(GITHUB_PREFIX).filter(|repo| is_github_repo(repo))
}

impl SoftwareApp {
    /// Têm instalação automática o `winget` com id e o `github` com `dono/repositorio` válido (o id vira
    /// `github:dono/repositorio`, que o lote instala pela última release).
    pub fn is_installable(&self) -> bool {
        let id = self.winget_id.as_deref().filter(|id| !id.trim().is_empty());
        match self.source.as_deref() {
            Some(s) if s.eq_ignore_ascii_case("winget") => id.is_some(),
            Some(s) if s.eq_ignore_ascii_case("github") => id.is_some_and(|id| github_repo(id).is_some()),
            _ => false,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SoftwareCategory {
    pub name: String,
    pub apps: Vec<SoftwareApp>,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct SoftwareCatalog {
    pub categories: Vec<SoftwareCategory>,
}

impl SoftwareCatalog {
    pub fn apps(&self) -> impl Iterator<Item = &SoftwareApp> {
        self.categories.iter().flat_map(|c| c.apps.iter())
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CatalogError {
    NotFound(String),
    NotAList,
    BadJson(String),
    MissingField(&'static str),
    DuplicateWingetId(String),
    NoItems(String),
}

impl fmt::Display for CatalogError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::NotFound(_) => f.write_str("O catálogo de programas não foi encontrado."),
            Self::NotAList => f.write_str("O catálogo de programas precisa ser uma lista JSON."),
            Self::BadJson(detail) => write!(f, "O catálogo de programas contém JSON inválido: {detail}"),
            Self::MissingField(name) => write!(f, "Campo obrigatório ausente ou inválido: {name}."),
            Self::DuplicateWingetId(id) => {
                write!(f, "O ID WinGet '{id}' aparece mais de uma vez no catálogo.")
            }
            Self::NoItems(name) => write!(f, "A categoria '{name}' precisa ter uma lista 'itens'."),
        }
    }
}

impl std::error::Error for CatalogError {}

/// Campo sem diferenciar maiúsculas.
fn field<'a>(object: &'a Value, name: &str) -> Option<&'a Value> {
    object.as_object()?.iter().find(|(k, _)| k.eq_ignore_ascii_case(name)).map(|(_, v)| v)
}

fn text(object: &Value, name: &str) -> Option<String> {
    field(object, name).and_then(Value::as_str).map(|s| s.trim().to_owned())
}

fn required(object: &Value, name: &'static str) -> Result<String, CatalogError> {
    text(object, name).filter(|s| !s.is_empty()).ok_or(CatalogError::MissingField(name))
}

fn flag(object: &Value, name: &str) -> bool {
    field(object, name).and_then(Value::as_bool).unwrap_or(false)
}

fn read_app(
    item: &Value,
    category: &str,
    grouped: bool,
    seen: &mut HashSet<String>,
) -> Result<SoftwareApp, CatalogError> {
    let name = required(item, "nome")?;
    let mut winget_id = text(item, "winget");
    let mut source = text(item, "fonte");
    let reference = text(item, "ref");
    // O formato plano usa fonte=winget + ref; o primeiro catálogo usa o campo winget.
    if source.as_deref().is_none_or(str::is_empty) && winget_id.as_deref().is_some_and(|s| !s.is_empty()) {
        source = Some("winget".into());
    }
    if !grouped && source.as_deref().is_some_and(|s| s.eq_ignore_ascii_case("winget")) && winget_id.is_none()
    {
        winget_id = reference.clone();
    }
    // fonte=github + ref=dono/repositorio: o id do item é `github:dono/repositorio` (nada de winget).
    if source.as_deref().is_some_and(|s| s.eq_ignore_ascii_case("github"))
        && winget_id.is_none()
        && let Some(repo) = reference.as_deref().filter(|r| is_github_repo(r))
    {
        winget_id = Some(format!("{GITHUB_PREFIX}{repo}"));
    }
    if let Some(id) = winget_id.as_deref().filter(|s| !s.is_empty())
        && !seen.insert(id.to_lowercase())
    {
        return Err(CatalogError::DuplicateWingetId(id.to_owned()));
    }
    Ok(SoftwareApp {
        name,
        winget_id,
        source,
        reference,
        default: flag(item, "padrao"),
        interactive: flag(item, "interativo"),
        note: text(item, "nota"),
        extra: text(item, "extra"),
        category: category.to_owned(),
    })
}

pub fn parse_software(json: &str) -> Result<SoftwareCatalog, CatalogError> {
    let value: Value = serde_json::from_str(json.trim_start_matches('\u{feff}'))
        .map_err(|e| CatalogError::BadJson(e.to_string()))?;
    let Some(groups) = value.as_array() else { return Err(CatalogError::NotAList) };
    let mut categories: Vec<SoftwareCategory> = Vec::new();
    let mut seen = HashSet::new();
    for group in groups {
        if let Some(items) = field(group, "itens") {
            let name = required(group, "categoria")?;
            let list = items.as_array().ok_or_else(|| CatalogError::NoItems(name.clone()))?;
            let apps =
                list.iter().map(|i| read_app(i, &name, true, &mut seen)).collect::<Result<Vec<_>, _>>()?;
            categories.push(SoftwareCategory { name, apps });
        } else {
            let app = read_app(group, &required(group, "grupo")?, false, &mut seen)?;
            match categories.iter_mut().find(|c| c.name.eq_ignore_ascii_case(&app.category)) {
                Some(category) => category.apps.push(app),
                None => categories.push(SoftwareCategory { name: app.category.clone(), apps: vec![app] }),
            }
        }
    }
    Ok(SoftwareCatalog { categories })
}

pub fn read_software(fs: &dyn Fs, path: &str) -> Result<SoftwareCatalog, CatalogError> {
    if !fs.exists(path) {
        return Err(CatalogError::NotFound(path.to_owned()));
    }
    parse_software(&fs.read_to_string(path).map_err(|e| CatalogError::BadJson(e.to_string()))?)
}

#[cfg(test)]
mod tests {
    use super::*;

    // SoftwareCatalogReaderTests.ReadsGroupsDefaultsAndInstallerSourceWithoutInventingUnavailablePackages
    #[test]
    fn a_github_app_is_installable_with_a_valid_repository_only() {
        let catalog = parse_software(
            r#"[{"categoria":"A","itens":[
                {"nome":"ZapFast","fonte":"github","ref":"crmne/zapfast"},
                {"nome":"Ruim","fonte":"github","ref":"../x"},
                {"nome":"Sem","fonte":"github"}]}]"#,
        )
        .unwrap();
        let apps: Vec<_> = catalog.apps().collect();
        assert!(apps[0].is_installable());
        assert_eq!(apps[0].winget_id.as_deref(), Some("github:crmne/zapfast"));
        assert!(!apps[1].is_installable() && !apps[2].is_installable());
        assert_eq!(github_repo("github:crmne/spotifast"), Some("crmne/spotifast"));
        for bad in ["github:a/../b", "github:a", "github:a/b/c", "github:/b", "winget:a/b", "github:a b/c"] {
            assert_eq!(github_repo(bad), None, "{bad}");
        }
    }

    #[test]
    fn reads_groups_defaults_and_installer_source_without_inventing_unavailable_packages() {
        let catalog = parse_software(
            r#"[
              { "categoria": "Navegadores", "itens": [
                { "nome": "Brave", "winget": "Brave.Brave", "padrao": true },
                { "nome": "Chrome", "winget": "Google.Chrome" },
                { "nome": "App pessoal", "fonte": "pacote", "padrao": false }
              ] }
            ]"#,
        )
        .unwrap();
        assert_eq!(catalog.categories.len(), 1);
        assert_eq!(catalog.categories[0].name, "Navegadores");
        assert_eq!(catalog.categories[0].apps.len(), 3);
        assert!(catalog.categories[0].apps[0].default);
        assert_eq!(catalog.categories[0].apps[0].winget_id.as_deref(), Some("Brave.Brave"));
        assert!(!catalog.categories[0].apps[2].is_installable());
        assert!(catalog.categories[0].apps[1].is_installable());
    }

    // SoftwareCatalogReaderTests.RejectsAnApplicationWithoutAName
    #[test]
    fn rejects_an_application_without_a_name() {
        let error = parse_software(r#"[{ "categoria": "Apps", "itens": [ { "winget": "Vendor.App" } ] }]"#)
            .unwrap_err();
        assert_eq!(error, CatalogError::MissingField("nome"));
    }

    // SoftwareCatalogReaderTests.RejectsDuplicateWingetIds
    #[test]
    fn rejects_duplicate_winget_ids() {
        let error = parse_software(
            r#"[{ "categoria": "Apps", "itens": [
              { "nome": "Primeiro", "winget": "Vendor.App" },
              { "nome": "Segundo", "winget": "vendor.app" } ] }]"#,
        )
        .unwrap_err();
        assert!(matches!(error, CatalogError::DuplicateWingetId(_)));
    }

    #[test]
    fn reads_the_flat_format_and_rejects_non_lists() {
        let catalog = parse_software(
            r#"[{"nome":"Git","grupo":"Dev","fonte":"winget","ref":"Git.Git"},{"nome":"Node","grupo":"dev","winget":"OpenJS.NodeJS"}]"#,
        )
        .unwrap();
        assert_eq!(catalog.categories.len(), 1);
        assert_eq!(catalog.categories[0].apps[0].winget_id.as_deref(), Some("Git.Git"));
        assert_eq!(parse_software("{}").unwrap_err(), CatalogError::NotAList);
    }

    #[test]
    fn the_shipped_software_catalog_loads() {
        let catalog = parse_software(include_str!("../catalog/software.json")).unwrap();
        assert!(catalog.apps().count() > 10);
        assert!(catalog.apps().any(|a| a.winget_id.as_deref() == Some("OBSProject.OBSStudio")));
    }
}
