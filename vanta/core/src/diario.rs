//! Diário dos níveis (`%ProgramData%\Vanta\Tools\niveis.json`): o valor ANTERIOR de tudo que o Vanta Tools mudou, para o
//! Desfazer devolver o que a pessoa tinha (não o padrão do Windows). Gravado antes ("em_andamento") e fechado no fim.

use serde::{Deserialize, Serialize};

use crate::tweaks::{ApplyResult, RegValue, SystemStore, Tweak, TweakEngine, TweakError};

pub const VERSAO: u32 = 1;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "tipo", content = "valor")]
pub enum ValorSalvo {
    Dword(i32),
    Qword(i64),
    Text(String),
}

impl From<RegValue> for ValorSalvo {
    fn from(v: RegValue) -> Self {
        match v {
            RegValue::Dword(i) => Self::Dword(i),
            RegValue::Qword(i) => Self::Qword(i),
            RegValue::Text(t) => Self::Text(t),
        }
    }
}

impl From<ValorSalvo> for RegValue {
    fn from(v: ValorSalvo) -> Self {
        match v {
            ValorSalvo::Dword(i) => Self::Dword(i),
            ValorSalvo::Qword(i) => Self::Qword(i),
            ValorSalvo::Text(t) => Self::Text(t),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RegistroAntes {
    pub chave: String,
    pub nome: String,
    /// `DWORD`, `QWORD` ou `String`, como no `tweaks.json`.
    pub kind: String,
    /// `None` = o valor não existia (o Desfazer apaga).
    pub antes: Option<ValorSalvo>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ServicoAntes {
    pub nome: String,
    pub antes: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Status {
    EmAndamento,
    Concluido,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Entrada {
    /// Id do ajuste (`tweaks.json`), `energia`, `app:<chave>` ou `pnp:<InstanceId>`.
    pub id: String,
    pub nivel: Option<String>,
    pub status: Status,
    #[serde(default)]
    pub registro: Vec<RegistroAntes>,
    #[serde(default)]
    pub servicos: Vec<ServicoAntes>,
    /// Energia: o GUID do plano que estava ativo.
    #[serde(default)]
    pub plano_anterior: Option<String>,
    /// Energia: o GUID do plano que o PRÓPRIO Vanta criou (comprovação de autoria; só ele pode ser apagado).
    #[serde(default)]
    pub plano_vanta: Option<String>,
    /// Energia: o modo de energia AC do Windows 11 (GUID) que estava ativo, quando foi possível ler.
    #[serde(default)]
    pub modo_ac_anterior: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Diario {
    pub versao: u32,
    pub entradas: Vec<Entrada>,
}

impl Default for Diario {
    fn default() -> Self {
        Self { versao: VERSAO, entradas: Vec::new() }
    }
}

impl Diario {
    /// Lê o arquivo; vazio ou ausente vira diário vazio. JSON quebrado ou de versão futura é erro (não se perde o diário).
    pub fn from_json(text: &str) -> Result<Self, String> {
        if text.trim().is_empty() {
            return Ok(Self::default());
        }
        let d: Self = serde_json::from_str(text.trim_start_matches('\u{feff}')).map_err(|e| format!("niveis.json inválido: {e}"))?;
        if d.versao > VERSAO {
            return Err(format!("niveis.json é de uma versão mais nova ({}).", d.versao));
        }
        Ok(d)
    }

    pub fn to_json(&self) -> String {
        serde_json::to_string_pretty(self).unwrap_or_default() + "\n"
    }

    pub fn entrada(&self, id: &str) -> Option<&Entrada> {
        self.entradas.iter().find(|e| e.id == id)
    }

    /// Há algo que não fechou (queda no meio): o Desfazer ainda sabe o que voltar.
    pub fn pendentes(&self) -> Vec<&str> {
        self.entradas.iter().filter(|e| e.status == Status::EmAndamento).map(|e| e.id.as_str()).collect()
    }

    pub fn substituir(&mut self, entrada: Entrada) {
        self.entradas.retain(|e| e.id != entrada.id);
        self.entradas.push(entrada);
    }
}

/// O que o ajuste muda hoje, antes de mudar.
pub fn capturar<S: SystemStore>(store: &S, tweak: &Tweak, nivel: Option<&str>) -> Entrada {
    Entrada {
        id: tweak.id.clone(),
        nivel: nivel.map(str::to_owned),
        status: Status::EmAndamento,
        registro: tweak
            .registry
            .iter()
            .map(|e| RegistroAntes { chave: e.key.clone(), nome: e.name.clone(), kind: e.kind.clone(), antes: store.get_value(&e.key, &e.name).map(Into::into) })
            .collect(),
        servicos: tweak.services.iter().map(|s| ServicoAntes { nome: s.name.clone(), antes: store.get_service_start(&s.name) }).collect(),
        plano_anterior: None,
        plano_vanta: None,
        modo_ac_anterior: None,
    }
}

/// Igual a [`aplicar`], mas confere a elegibilidade (`niveis::elegibilidade`) de cada ajuste antes de gravar o diário e o
/// registro: o que o PC não comporta volta como erro e nada é mudado.
#[allow(clippy::too_many_arguments)]
pub fn aplicar_em<S: SystemStore>(
    store: &mut S,
    tweaks: &[Tweak],
    ids: &[String],
    nivel: Option<&str>,
    det: &crate::niveis::Deteccao,
    amb: &crate::niveis::Ambiente,
    diario: &mut Diario,
    gravar: &mut dyn FnMut(&Diario) -> Result<(), String>,
) -> Vec<(String, Result<ApplyResult, String>)> {
    let mut out = Vec::new();
    let mut permitidos = Vec::new();
    for id in ids {
        match tweaks.iter().find(|t| t.id == *id).map(|t| crate::niveis::elegibilidade(t, det, amb)) {
            Some(Err(motivo)) => out.push((id.clone(), Err(format!("não vale neste PC: {motivo}")))),
            _ => permitidos.push(id.clone()), // desconhecido: `aplicar` reporta
        }
    }
    out.extend(aplicar(store, tweaks, &permitidos, nivel, diario, gravar));
    out
}

/// Liga os ajustes (ids do plano) gravando o diário ANTES de cada um e fechando depois. `gravar` persiste o diário
/// (arquivo); se ele falhar, o ajuste não é aplicado. Um ajuste que falha não para os outros.
pub fn aplicar<S: SystemStore>(
    store: &mut S,
    tweaks: &[Tweak],
    ids: &[String],
    nivel: Option<&str>,
    diario: &mut Diario,
    gravar: &mut dyn FnMut(&Diario) -> Result<(), String>,
) -> Vec<(String, Result<ApplyResult, String>)> {
    let mut out = Vec::new();
    for id in ids {
        let Some(tweak) = tweaks.iter().find(|t| t.id == *id) else {
            out.push((id.clone(), Err("ajuste desconhecido".to_owned())));
            continue;
        };
        // com diário fechado, o "antes" original é o que vale (não o estado já mudado)
        let entrada = match diario.entrada(id) {
            Some(e) if e.status == Status::Concluido => e.clone(),
            _ => capturar(store, tweak, nivel),
        };
        diario.substituir(Entrada { status: Status::EmAndamento, ..entrada });
        if let Err(error) = gravar(diario) {
            diario.entradas.retain(|e| e.id != *id);
            out.push((id.clone(), Err(format!("diário: {error}"))));
            continue;
        }
        let result = TweakEngine::new(store).apply(tweak, true).map_err(|e: TweakError| e.to_string());
        if result.is_ok() {
            if let Some(e) = diario.entradas.iter_mut().find(|e| e.id == *id) {
                e.status = Status::Concluido;
            }
        } else {
            diario.entradas.retain(|e| e.id != *id);
        }
        let _ = gravar(diario);
        out.push((id.clone(), result));
    }
    out
}

/// Desfazer: devolve o valor anterior (apaga o que não existia, volta o início do serviço) e tira a entrada do diário.
pub fn desfazer<S: SystemStore>(store: &mut S, diario: &mut Diario, id: &str) -> Result<(), String> {
    let Some(entrada) = diario.entrada(id).cloned() else {
        return Err(format!("{id} não está no diário: nada a desfazer."));
    };
    for r in &entrada.registro {
        match r.antes.clone() {
            Some(v) => store.set_value(&r.chave, &r.nome, &r.kind, v.into()),
            None => store.delete_value(&r.chave, &r.nome),
        }
    }
    for s in &entrada.servicos {
        if let Some(antes) = &s.antes {
            store.set_service_start(&s.nome, antes);
        }
    }
    diario.entradas.retain(|e| e.id != id);
    Ok(())
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;

    use super::*;
    use crate::tweaks::parse_catalog;

    #[derive(Default)]
    struct Fake(HashMap<String, RegValue>, HashMap<String, String>);

    impl SystemStore for Fake {
        fn get_value(&self, k: &str, n: &str) -> Option<RegValue> {
            self.0.get(&format!("{k}|{n}")).cloned()
        }
        fn set_value(&mut self, k: &str, n: &str, _: &str, v: RegValue) {
            self.0.insert(format!("{k}|{n}"), v);
        }
        fn delete_value(&mut self, k: &str, n: &str) {
            self.0.remove(&format!("{k}|{n}"));
        }
        fn get_service_start(&self, s: &str) -> Option<String> {
            self.1.get(s).cloned()
        }
        fn set_service_start(&mut self, s: &str, v: &str) {
            self.1.insert(s.to_owned(), v.to_owned());
        }
    }

    fn catalog() -> Vec<Tweak> {
        parse_catalog(
            r#"[{"id":"t","categoria":"x","titulo":"T","descricao":"d","registro":[
              {"chave":"HKCU\\A","valor":"a","tipo":"DWORD","ligado":0,"desligado":1},
              {"chave":"HKCU\\A","valor":"b","tipo":"String","ligado":"x","desligado":null}],
              "servicos":[{"nome":"Fax","ligado":"Disabled","desligado":"Manual"}]}]"#,
        )
        .unwrap()
    }

    #[test]
    fn undo_returns_the_previous_values_not_the_windows_defaults() {
        let t = catalog();
        let mut store = Fake::default();
        store.set_value(r"HKCU\A", "a", "DWORD", RegValue::Dword(7)); // valor do usuário (nem 0 nem 1)
        store.set_service_start("Fax", "Automatic"); // o usuário tinha Automático
        let mut d = Diario::default();
        let mut saves = 0;
        let r = aplicar(&mut store, &t, &["t".into()], Some("leve"), &mut d, &mut |_| {
            saves += 1;
            Ok(())
        });
        assert!(r[0].1.is_ok() && saves == 2, "grava antes e fecha depois");
        assert_eq!(store.get_value(r"HKCU\A", "a"), Some(RegValue::Dword(0)));
        assert_eq!(d.entrada("t").unwrap().status, Status::Concluido);
        desfazer(&mut store, &mut d, "t").unwrap();
        assert_eq!(store.get_value(r"HKCU\A", "a"), Some(RegValue::Dword(7)));
        assert_eq!(store.get_value(r"HKCU\A", "b"), None, "o que não existia é apagado");
        assert_eq!(store.get_service_start("Fax").as_deref(), Some("Automatic"));
        assert!(d.entradas.is_empty() && desfazer(&mut store, &mut d, "t").is_err());
    }

    #[test]
    fn a_failed_journal_write_blocks_the_change_and_the_first_write_is_pending() {
        let t = catalog();
        let mut store = Fake::default();
        let mut d = Diario::default();
        let mut first: Option<Status> = None;
        aplicar(&mut store, &t, &["t".into()], None, &mut d, &mut |dia| {
            first.get_or_insert(dia.entrada("t").map(|e| e.status).unwrap());
            Ok(())
        });
        assert_eq!(first, Some(Status::EmAndamento));
        let mut store2 = Fake::default();
        let mut d2 = Diario::default();
        let r = aplicar(&mut store2, &t, &["t".into()], None, &mut d2, &mut |_| Err("disco cheio".into()));
        assert!(r[0].1.as_ref().unwrap_err().contains("disco cheio"));
        assert_eq!(store2.get_value(r"HKCU\A", "a"), None, "sem diário, nada é mudado");
    }

    #[test]
    fn apply_with_eligibility_refuses_what_the_pc_cannot_take_before_the_journal_or_registry() {
        use crate::niveis::{Ambiente, Deteccao};
        let mut t = catalog();
        t[0].requires = Some("pro,build26100".into());
        let det = Deteccao { ssd: true, nvidia: false, bateria: false, gerenciado: false };
        let mut store = Fake::default();
        let mut d = Diario::default();
        let r = aplicar_em(&mut store, &t, &["t".into()], None, &det, &Ambiente { pro: false, build: 26300 }, &mut d, &mut |_| Ok(()));
        assert!(r[0].1.as_ref().unwrap_err().contains("Pro"));
        assert!(store.0.is_empty() && d.entradas.is_empty(), "nada gravado nem anotado");
        let r = aplicar_em(&mut store, &t, &["t".into()], None, &det, &Ambiente { pro: true, build: 26300 }, &mut d, &mut |_| Ok(()));
        assert!(r[0].1.is_ok() && !store.0.is_empty());
    }

    #[test]
    fn the_file_round_trips_and_a_pending_entry_is_reported() {
        let mut d = Diario::default();
        d.entradas.push(Entrada {
            id: "energia".into(),
            nivel: None,
            status: Status::EmAndamento,
            registro: vec![],
            servicos: vec![],
            plano_anterior: Some("8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c".into()),
            plano_vanta: Some("1c0ffee0-0000-4000-8000-000000000001".into()),
            modo_ac_anterior: None,
        });
        let back = Diario::from_json(&d.to_json()).unwrap();
        assert_eq!(back, d);
        assert_eq!(back.pendentes(), ["energia"]);
        assert_eq!(Diario::from_json("").unwrap(), Diario::default());
        assert!(Diario::from_json("{ quebrado").is_err());
        assert!(Diario::from_json(r#"{"versao":99,"entradas":[]}"#).unwrap_err().contains("mais nova"));
    }
}
