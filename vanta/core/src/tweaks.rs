//! Ajustes do Windows (`tweaks.json`): ler o estado e ligar/desligar, sempre por um [`SystemStore`].

use std::collections::HashSet;
use std::fmt;

use serde::Deserialize;
use serde_json::Value;

#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct RegistryEdit {
    #[serde(rename = "chave")]
    pub key: String,
    #[serde(rename = "valor")]
    pub name: String,
    #[serde(rename = "tipo")]
    pub kind: String,
    #[serde(rename = "ligado")]
    pub on: Value,
    #[serde(rename = "desligado")]
    pub off: Value,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub struct ServiceEdit {
    #[serde(rename = "nome")]
    pub name: String,
    #[serde(rename = "ligado")]
    pub on: String,
    #[serde(rename = "desligado")]
    pub off: String,
}

#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct Tweak {
    pub id: String,
    #[serde(rename = "categoria")]
    pub category: String,
    #[serde(rename = "titulo")]
    pub title: String,
    #[serde(rename = "descricao")]
    pub description: String,
    #[serde(rename = "icone", default)]
    pub glyph: Option<String>,
    #[serde(rename = "reinicia", default)]
    pub restart: bool,
    #[serde(rename = "bloqueado", default)]
    pub locked: bool,
    /// Entra na edição pública do Vanta Tools (universal ou "depende do PC" com aviso). Sem o campo, fica fora.
    #[serde(rename = "publico", default)]
    pub public: bool,
    #[serde(rename = "fonte", default)]
    pub source: Option<String>,
    /// Nível de otimização que inclui o ajuste (`leve`, `equilibrado` ou `competitivo`); sem o campo, é só manual.
    #[serde(rename = "nivel", default)]
    pub level: Option<String>,
    /// Condição do PC para valer a pena: `ssd` ou `nvidia`.
    #[serde(rename = "requer", default)]
    pub requires: Option<String>,
    #[serde(rename = "registro", default)]
    pub registry: Vec<RegistryEdit>,
    #[serde(rename = "servicos", default)]
    pub services: Vec<ServiceEdit>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TweakState {
    On,
    Off,
    Mixed,
}

/// Valor de registro como o Windows o guarda.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RegValue {
    /// DWORD: o Windows devolve com sinal; `0xFFFFFFFF` vem como `-1`.
    Dword(i32),
    Qword(i64),
    Text(String),
}

/// Acesso ao registro e aos serviços; o Vanta Tools liga o real, os testes usam um falso.
pub trait SystemStore {
    fn get_value(&self, key: &str, name: &str) -> Option<RegValue>;
    fn set_value(&mut self, key: &str, name: &str, kind: &str, value: RegValue);
    fn delete_value(&mut self, key: &str, name: &str);
    fn get_service_start(&self, service: &str) -> Option<String>;
    fn set_service_start(&mut self, service: &str, start: &str);
    /// Consulta o serviço distinguindo "não existe" de "acesso negado". O padrão trata a leitura como existe/não existe;
    /// o `RegistryStore` real usa o gerenciador de serviços (SCM) e separa os três casos.
    fn service_lookup(&self, service: &str) -> ServiceLookup {
        match self.get_service_start(service) {
            Some(start) => ServiceLookup::Found(start),
            None => ServiceLookup::Missing,
        }
    }
}

/// Resultado de consultar um serviço no SCM.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ServiceLookup {
    /// Existe, com o início atual (`Automatic`, `Manual`, `Disabled`, `Boot` ou `System`).
    Found(String),
    /// O serviço não existe neste Windows.
    Missing,
    /// Existe (ou não se sabe), mas o Windows negou a consulta: não é o mesmo que ausente.
    Denied(String),
}

/// Resultado de aplicar um ajuste: serviços ausentes neste Windows são pulados sem erro e registrados aqui.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ApplyResult {
    /// Serviços do ajuste que não existem no SCM deste Windows (pulados como ausentes).
    pub missing_services: Vec<String>,
    /// Nota legível citando os serviços ausentes pulados; `None` quando todos existiam.
    pub note: Option<String>,
}

impl ApplyResult {
    pub fn from_missing(missing_services: Vec<String>) -> Self {
        let note = match missing_services.len() {
            0 => None,
            1 => Some(format!("Serviço ausente neste Windows (pulado): {}.", missing_services[0])),
            _ => Some(format!("Serviços ausentes neste Windows (pulados): {}.", missing_services.join(", "))),
        };
        Self { missing_services, note }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TweakError {
    BadJson(String),
    Empty,
    Duplicate(String),
    DoesNothing(String),
    Locked,
    /// O PC não atende à condição do ajuste (edição, build, SSD, PC da empresa...); nada foi gravado.
    NotEligible(String),
    /// O Windows negou o acesso a um serviço do ajuste (precisa de administrador); nada foi gravado.
    ServiceAccess(String),
}

impl fmt::Display for TweakError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::BadJson(detail) => write!(f, "tweaks.json inválido: {detail}"),
            Self::Empty => f.write_str("tweaks.json vazio."),
            Self::Duplicate(id) => write!(f, "Ajuste repetido: {id}."),
            Self::DoesNothing(id) => write!(f, "Ajuste {id} não altera nada."),
            Self::Locked => f.write_str("Este ajuste é fixo no Vanta."),
            Self::NotEligible(reason) => write!(f, "Este ajuste não vale neste PC: {reason}."),
            Self::ServiceAccess(service) => write!(f, "O Windows negou o acesso ao serviço {service} (precisa de administrador)."),
        }
    }
}

impl std::error::Error for TweakError {}

pub fn parse_catalog(json: &str) -> Result<Vec<Tweak>, TweakError> {
    let list: Vec<Tweak> = serde_json::from_str(json.trim_start_matches('\u{feff}'))
        .map_err(|e| TweakError::BadJson(e.to_string()))?;
    if list.is_empty() {
        return Err(TweakError::Empty);
    }
    let mut ids = HashSet::new();
    for tweak in &list {
        if !ids.insert(tweak.id.clone()) {
            return Err(TweakError::Duplicate(tweak.id.clone()));
        }
        if tweak.registry.len() + tweak.services.len() == 0 {
            return Err(TweakError::DoesNothing(tweak.id.clone()));
        }
    }
    Ok(list)
}

fn matches(current: Option<RegValue>, wanted: &Value) -> bool {
    if wanted.is_null() {
        return current.is_none();
    }
    match current {
        None => false,
        Some(RegValue::Dword(i)) => {
            let want = wanted.as_i64();
            want == Some(i64::from(i as u32)) || want == Some(i64::from(i))
        }
        Some(RegValue::Qword(l)) => wanted.as_i64() == Some(l),
        Some(RegValue::Text(s)) => s.eq_ignore_ascii_case(&value_text(wanted)),
    }
}

/// Texto `Chave=valor;Chave=valor;` (como `DirectXUserGlobalSettings`): vários ajustes dividem o mesmo valor.
fn pairs(text: &str) -> Vec<(&str, &str)> {
    text.split(';').filter_map(|p| p.trim().split_once('=')).collect()
}

fn is_pair_list(edit: &RegistryEdit) -> bool {
    edit.kind == "String" && edit.on.as_str().is_some_and(|t| !t.trim().is_empty() && t.split(';').filter(|p| !p.trim().is_empty()).all(|p| p.contains('=')))
}

/// Lê, troca só as chaves do ajuste e devolve o texto novo (None = ficou vazio, apague o valor): o resto do texto fica.
fn merge_pairs(current: Option<RegValue>, edit: &RegistryEdit, enable: bool) -> Option<String> {
    let ours = pairs(edit.on.as_str().unwrap_or_default());
    let current = match current {
        Some(RegValue::Text(t)) => t,
        _ => String::new(),
    };
    let mut kept: Vec<(String, String)> =
        pairs(&current).into_iter().filter(|(k, _)| !ours.iter().any(|(o, _)| o.eq_ignore_ascii_case(k))).map(|(k, v)| (k.to_owned(), v.to_owned())).collect();
    if enable {
        kept.extend(ours.iter().map(|(k, v)| ((*k).to_owned(), (*v).to_owned())));
    }
    (!kept.is_empty()).then(|| kept.iter().map(|(k, v)| format!("{k}={v};")).collect())
}

fn pairs_on(current: Option<RegValue>, edit: &RegistryEdit) -> bool {
    let Some(RegValue::Text(t)) = current else { return false };
    let have = pairs(&t);
    pairs(edit.on.as_str().unwrap_or_default()).iter().all(|(k, v)| have.iter().any(|(hk, hv)| hk.eq_ignore_ascii_case(k) && hv.eq_ignore_ascii_case(v)))
}

fn value_text(value: &Value) -> String {
    value.as_str().map_or_else(|| value.to_string(), str::to_owned)
}

fn to_registry(value: &Value, kind: &str) -> RegValue {
    match kind {
        // 4294967295 vira -1: os 32 bits de baixo, como o Windows grava
        "DWORD" => RegValue::Dword(value.as_i64().unwrap_or(0) as i32),
        "QWORD" => RegValue::Qword(value.as_i64().unwrap_or(0)),
        _ => RegValue::Text(value_text(value)),
    }
}

pub struct TweakEngine<'a, S: SystemStore> {
    store: &'a mut S,
}

impl<'a, S: SystemStore> TweakEngine<'a, S> {
    pub fn new(store: &'a mut S) -> Self {
        Self { store }
    }

    pub fn read(&self, tweak: &Tweak) -> TweakState {
        let mut on = 0;
        // serviço que não existe neste Windows (ex.: Fax no 26H2) não conta: nada a ligar nem a desligar nele
        let present = tweak.services.iter().filter(|s| self.store.service_lookup(&s.name) != ServiceLookup::Missing).count();
        let total = tweak.registry.len() + present;
        for edit in &tweak.registry {
            let current = self.store.get_value(&edit.key, &edit.name);
            if if is_pair_list(edit) { pairs_on(current, edit) } else { matches(current, &edit.on) } {
                on += 1;
            }
        }
        for service in &tweak.services {
            if self
                .store
                .get_service_start(&service.name)
                .is_some_and(|s| s.eq_ignore_ascii_case(&service.on))
            {
                on += 1;
            }
        }
        if total == 0 {
            TweakState::Off
        } else if on == total {
            TweakState::On
        } else if on == 0 {
            TweakState::Off
        } else {
            TweakState::Mixed
        }
    }

    pub fn apply(&mut self, tweak: &Tweak, enable: bool) -> Result<ApplyResult, TweakError> {
        if tweak.locked {
            return Err(TweakError::Locked);
        }
        // antes de gravar qualquer coisa: serviço com acesso negado barra o ajuste inteiro (nada fica pela metade)
        for service in &tweak.services {
            if matches!(self.store.service_lookup(&service.name), ServiceLookup::Denied(_)) {
                return Err(TweakError::ServiceAccess(service.name.clone()));
            }
        }
        for edit in &tweak.registry {
            if is_pair_list(edit) {
                match merge_pairs(self.store.get_value(&edit.key, &edit.name), edit, enable) {
                    Some(text) => self.store.set_value(&edit.key, &edit.name, &edit.kind, RegValue::Text(text)),
                    None => self.store.delete_value(&edit.key, &edit.name),
                }
                continue;
            }
            let target = if enable { &edit.on } else { &edit.off };
            if target.is_null() {
                self.store.delete_value(&edit.key, &edit.name);
            } else {
                self.store.set_value(&edit.key, &edit.name, &edit.kind, to_registry(target, &edit.kind));
            }
        }
        let mut missing_services = Vec::new();
        for service in &tweak.services {
            match self.store.service_lookup(&service.name) {
                ServiceLookup::Missing => {
                    missing_services.push(service.name.clone());
                    continue; // ausente no SCM: registrado e pulado, sem erro
                }
                ServiceLookup::Denied(_) | ServiceLookup::Found(_) => {}
            }
            self.store.set_service_start(&service.name, if enable { &service.on } else { &service.off });
        }
        Ok(ApplyResult::from_missing(missing_services))
    }
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;

    use super::*;

    const JSON: &str = r#"[{ "id":"t","categoria":"Jogos","titulo":"T","descricao":"d",
       "registro":[
         {"chave":"HKCU\\A","valor":"x","tipo":"DWORD","ligado":4294967295,"desligado":null},
         {"chave":"HKCU\\A","valor":"y","tipo":"String","ligado":"Off","desligado":"On"}],
       "servicos":[{"nome":"S","ligado":"Disabled","desligado":"Manual"}] }]"#;

    #[derive(Default)]
    struct FakeStore {
        values: HashMap<String, RegValue>,
        services: HashMap<String, String>,
    }

    impl SystemStore for FakeStore {
        fn get_value(&self, key: &str, name: &str) -> Option<RegValue> {
            self.values.get(&format!("{key}|{name}")).cloned()
        }
        fn set_value(&mut self, key: &str, name: &str, _kind: &str, value: RegValue) {
            self.values.insert(format!("{key}|{name}"), value);
        }
        fn delete_value(&mut self, key: &str, name: &str) {
            self.values.remove(&format!("{key}|{name}"));
        }
        fn get_service_start(&self, service: &str) -> Option<String> {
            self.services.get(service).cloned()
        }
        fn set_service_start(&mut self, service: &str, start: &str) {
            self.services.insert(service.to_owned(), start.to_owned());
        }
    }

    fn load() -> Tweak {
        parse_catalog(JSON).unwrap().remove(0)
    }

    #[test]
    fn a_shared_settings_string_keeps_the_keys_of_other_tweaks() {
        let json = r#"[{"id":"w","categoria":"Jogos","titulo":"T","descricao":"d","registro":[{"chave":"HKCU\\D","valor":"S","tipo":"String","ligado":"SwapEffectUpgradeEnable=0;","desligado":null}]}]"#;
        let tweak = parse_catalog(json).unwrap().remove(0);
        let mut store = FakeStore::default();
        store.values.insert(r"HKCU\D|S".into(), RegValue::Text("VRROptimizeEnable=0;SwapEffectUpgradeEnable=1;".into()));
        assert_eq!(TweakEngine::new(&mut store).read(&tweak), TweakState::Off);
        TweakEngine::new(&mut store).apply(&tweak, true).unwrap();
        assert_eq!(store.values[r"HKCU\D|S"], RegValue::Text("VRROptimizeEnable=0;SwapEffectUpgradeEnable=0;".into()));
        assert_eq!(TweakEngine::new(&mut store).read(&tweak), TweakState::On);
        TweakEngine::new(&mut store).apply(&tweak, false).unwrap();
        assert_eq!(store.values[r"HKCU\D|S"], RegValue::Text("VRROptimizeEnable=0;".into()));
        store.values.insert(r"HKCU\D|S".into(), RegValue::Text("SwapEffectUpgradeEnable=0;".into()));
        TweakEngine::new(&mut store).apply(&tweak, false).unwrap();
        assert!(!store.values.contains_key(r"HKCU\D|S"));
    }

    #[test]
    fn a_service_missing_from_this_windows_is_ignored_without_error() {
        let json = r#"[{"id":"s","categoria":"x","titulo":"T","descricao":"d","servicos":[
            {"nome":"MapsBroker","ligado":"Manual","desligado":"Automatic"},
            {"nome":"Fax","ligado":"Manual","desligado":"Manual"}]}]"#;
        let tweak = parse_catalog(json).unwrap().remove(0);
        let mut store = FakeStore::default();
        store.services.insert("MapsBroker".into(), "Automatic".into()); // sem Fax
        assert_eq!(TweakEngine::new(&mut store).read(&tweak), TweakState::Off);
        let applied = TweakEngine::new(&mut store).apply(&tweak, true).unwrap();
        assert_eq!(applied.missing_services, vec!["Fax"]);
        let note = applied.note.as_deref().expect("nota cita o serviço ausente");
        assert!(note.contains("Fax") && note.contains("ausente"), "nota inesperada: {note}");
        assert!(!store.services.contains_key("Fax"), "o serviço ausente não é criado");
        assert_eq!(TweakEngine::new(&mut store).read(&tweak), TweakState::On, "o ausente não trava o ajuste em \"falta aplicar\"");
        // quando todos existem, a nota fica vazia
        store.services.insert("Fax".into(), "Manual".into());
        let full = TweakEngine::new(&mut store).apply(&tweak, true).unwrap();
        assert!(full.missing_services.is_empty() && full.note.is_none());
        // só serviços ausentes: nada a fazer, registra ambos como ausentes e não conta como ligado
        let mut vazio = FakeStore::default();
        assert_eq!(TweakEngine::new(&mut vazio).read(&tweak), TweakState::Off);
        let empty_res = TweakEngine::new(&mut vazio).apply(&tweak, true).unwrap();
        assert!(vazio.services.is_empty());
        assert_eq!(empty_res.missing_services, vec!["MapsBroker", "Fax"]);
        assert!(empty_res.note.as_deref().unwrap().contains("Fax"));
    }

    /// Loja que nega a consulta de um serviço (como o SCM sem administrador) e conta as gravações.
    struct Denying {
        inner: FakeStore,
        writes: usize,
    }

    impl SystemStore for Denying {
        fn get_value(&self, k: &str, n: &str) -> Option<RegValue> {
            self.inner.get_value(k, n)
        }
        fn set_value(&mut self, k: &str, n: &str, kind: &str, v: RegValue) {
            self.writes += 1;
            self.inner.set_value(k, n, kind, v);
        }
        fn delete_value(&mut self, k: &str, n: &str) {
            self.writes += 1;
            self.inner.delete_value(k, n);
        }
        fn get_service_start(&self, _: &str) -> Option<String> {
            None // o que a leitura antiga fazia: acesso negado parecia "ausente"
        }
        fn set_service_start(&mut self, s: &str, v: &str) {
            self.writes += 1;
            self.inner.set_service_start(s, v);
        }
        fn service_lookup(&self, _: &str) -> ServiceLookup {
            ServiceLookup::Denied("acesso negado".into())
        }
    }

    #[test]
    fn a_denied_service_blocks_the_whole_tweak_and_is_not_taken_as_missing() {
        let json = r#"[{"id":"m","categoria":"x","titulo":"T","descricao":"d",
            "registro":[{"chave":"HKCU\\A","valor":"a","tipo":"DWORD","ligado":1,"desligado":0}],
            "servicos":[{"nome":"MapsBroker","ligado":"Manual","desligado":"Automatic"}]}]"#;
        let tweak = parse_catalog(json).unwrap().remove(0);
        let mut store = Denying { inner: FakeStore::default(), writes: 0 };
        let r = TweakEngine::new(&mut store).apply(&tweak, true);
        assert_eq!(r, Err(TweakError::ServiceAccess("MapsBroker".into())));
        assert_eq!(store.writes, 0, "nada gravado antes de descobrir o acesso negado");
        assert!(r.unwrap_err().to_string().contains("administrador"));
        // para ler, o serviço negado conta como presente (não "ausente"): o ajuste não aparece como ligado
        assert_ne!(TweakEngine::new(&mut store).read(&tweak), TweakState::On);
    }

    // TweakEngineTests.ApplyOnThenOffRoundTripsState
    #[test]
    fn apply_on_then_off_round_trips_state() {
        let mut store = FakeStore::default();
        let tweak = load();
        assert_eq!(TweakEngine::new(&mut store).read(&tweak), TweakState::Off);
        TweakEngine::new(&mut store).apply(&tweak, true).unwrap();
        assert_eq!(store.values[r"HKCU\A|x"], RegValue::Dword(-1));
        assert_eq!(TweakEngine::new(&mut store).read(&tweak), TweakState::On);
        TweakEngine::new(&mut store).apply(&tweak, false).unwrap();
        assert!(!store.values.contains_key(r"HKCU\A|x"));
        assert_eq!(TweakEngine::new(&mut store).read(&tweak), TweakState::Off);
    }

    // TweakEngineTests.PartialMatchIsMixed
    #[test]
    fn partial_match_is_mixed() {
        let mut store = FakeStore::default();
        store.values.insert(r"HKCU\A|y".into(), RegValue::Text("Off".into()));
        assert_eq!(TweakEngine::new(&mut store).read(&load()), TweakState::Mixed);
    }

    // TweakEngineTests.ShippedCatalogLoads
    #[test]
    fn shipped_catalog_loads() {
        let list = parse_catalog(include_str!("../catalog/tweaks.json")).unwrap();
        assert!(list.len() > 40, "{}", list.len());
    }

    #[test]
    fn locked_tweaks_refuse_to_change_and_bad_catalogs_are_rejected() {
        let mut tweak = load();
        tweak.locked = true;
        assert_eq!(TweakEngine::new(&mut FakeStore::default()).apply(&tweak, true), Err(TweakError::Locked));
        assert!(matches!(parse_catalog("[]"), Err(TweakError::Empty)));
        let body = &JSON[1..JSON.len() - 1];
        let twice = format!("[{body},{body}]");
        assert!(matches!(parse_catalog(&twice), Err(TweakError::Duplicate(_))), "{twice}");
        let nothing = r#"[{"id":"n","categoria":"c","titulo":"t","descricao":"d"}]"#;
        assert!(matches!(parse_catalog(nothing), Err(TweakError::DoesNothing(_))));
    }

    #[test]
    fn dwords_compare_signed_and_unsigned_and_service_start_ignores_case() {
        let mut store = FakeStore::default();
        store.values.insert(r"HKCU\A|x".into(), RegValue::Dword(-1));
        store.services.insert("S".into(), "disabled".into());
        store.values.insert(r"HKCU\A|y".into(), RegValue::Text("OFF".into()));
        assert_eq!(TweakEngine::new(&mut store).read(&load()), TweakState::On);
    }
}
