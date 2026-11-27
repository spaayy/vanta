//! Serviços do Windows na página manual: `Automático`, `Manual` ou `Desativado` por serviço, e "Voltar ao padrão do Windows".
//!
//! Só o valor `Start` é escrito (via [`SystemStore::set_service_start`]). `DelayedAutostart`, os gatilhos (`TriggerInfo`) e
//! as dependências ficam como estão, então um serviço com gatilho continua iniciando sob demanda em Manual.

use crate::tweaks::{ServiceLookup, SystemStore};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StartType {
    Auto,
    Manual,
    Disabled,
}

impl StartType {
    /// O nome que o `SystemStore` usa (`Automatic`, `Manual`, `Disabled`).
    pub fn nome(self) -> &'static str {
        match self {
            StartType::Auto => "Automatic",
            StartType::Manual => "Manual",
            StartType::Disabled => "Disabled",
        }
    }

    pub fn from_nome(nome: &str) -> Option<StartType> {
        match nome.to_ascii_lowercase().as_str() {
            "automatic" | "auto" => Some(StartType::Auto),
            "manual" => Some(StartType::Manual),
            "disabled" => Some(StartType::Disabled),
            _ => None,
        }
    }
}

/// Um serviço que a página mostra, com o início de fábrica do Windows.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ServicoGerenciavel {
    pub nome: &'static str,
    pub titulo: &'static str,
    pub padrao: StartType,
    /// Entra no Equilibrado (em Manual). Só os que o Hito aprovou: TrkWks e PcaSvc ficam só na página manual.
    pub equilibrado: bool,
}

pub const SERVICOS: [ServicoGerenciavel; 7] = [
    ServicoGerenciavel { nome: "MapsBroker", titulo: "Mapas baixados", padrao: StartType::Auto, equilibrado: true },
    ServicoGerenciavel { nome: "RetailDemo", titulo: "Modo demonstração de loja", padrao: StartType::Manual, equilibrado: true },
    ServicoGerenciavel { nome: "WMPNetworkSvc", titulo: "Compartilhamento do Media Player", padrao: StartType::Manual, equilibrado: true },
    ServicoGerenciavel { nome: "Fax", titulo: "Fax", padrao: StartType::Manual, equilibrado: true },
    ServicoGerenciavel { nome: "dmwappushservice", titulo: "Mensagens push de operadora (WAP)", padrao: StartType::Manual, equilibrado: false },
    ServicoGerenciavel { nome: "TrkWks", titulo: "Rastreamento de links distribuídos", padrao: StartType::Auto, equilibrado: false },
    ServicoGerenciavel { nome: "PcaSvc", titulo: "Assistente de Compatibilidade de Programas", padrao: StartType::Auto, equilibrado: false },
];

/// Serviços que nenhum nível nem a página manual mexem: impressão, Bluetooth, busca, rede, segurança e o próprio Windows.
pub const NUNCA: [&str; 16] = [
    "Spooler", "bthserv", "BthAvctpSvc", "WSearch", "Dhcp", "Dnscache", "LanmanWorkstation", "LanmanServer", "nsi", "WinDefend", "WdNisSvc",
    "EventLog", "RpcSs", "PlugPlay", "wuauserv", "mpssvc",
];

pub fn gerenciavel(nome: &str) -> Option<&'static ServicoGerenciavel> {
    SERVICOS.iter().find(|s| s.nome.eq_ignore_ascii_case(nome))
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum EstadoServico {
    /// O serviço já está no início pedido: "Já feito pelo Vanta".
    JaFeito,
    Falta { atual: StartType },
    /// Não existe neste Windows (edição ou versão).
    Ausente,
}

pub fn estado(store: &impl SystemStore, nome: &str, alvo: StartType) -> EstadoServico {
    match store.get_service_start(nome).as_deref().and_then(StartType::from_nome) {
        Some(atual) if atual == alvo => EstadoServico::JaFeito,
        Some(atual) => EstadoServico::Falta { atual },
        None => EstadoServico::Ausente,
    }
}

/// Igual a [`estado`], mas "acesso negado" volta como erro em vez de parecer "ausente neste Windows".
pub fn estado_checado(store: &impl SystemStore, nome: &str, alvo: StartType) -> Result<EstadoServico, String> {
    match store.service_lookup(nome) {
        ServiceLookup::Found(start) => Ok(match StartType::from_nome(&start) {
            Some(atual) if atual == alvo => EstadoServico::JaFeito,
            Some(atual) => EstadoServico::Falta { atual },
            None => EstadoServico::Ausente, // Boot/System: não é um início que o Vanta gerencie
        }),
        ServiceLookup::Missing => Ok(EstadoServico::Ausente),
        ServiceLookup::Denied(why) => Err(format!("O Windows negou a leitura do serviço {nome}: {why}")),
    }
}

/// Define o início de um serviço da lista (nunca um da lista `NUNCA`). Devolve o início anterior para o diário.
pub fn definir(store: &mut impl SystemStore, nome: &str, alvo: StartType) -> Result<StartType, String> {
    if NUNCA.iter().any(|n| n.eq_ignore_ascii_case(nome)) {
        return Err(format!("O serviço {nome} é protegido e não é mexido pelo Vanta."));
    }
    if gerenciavel(nome).is_none() {
        return Err(format!("O serviço {nome} não está na lista do Vanta."));
    }
    let atual = match store.service_lookup(nome) {
        ServiceLookup::Found(start) => StartType::from_nome(&start).ok_or_else(|| format!("O serviço {nome} tem um início ({start}) que o Vanta não altera."))?,
        ServiceLookup::Missing => return Err(format!("O serviço {nome} não existe neste Windows.")),
        ServiceLookup::Denied(why) => return Err(format!("O Windows negou o acesso ao serviço {nome} (precisa de administrador): {why}")),
    };
    store.set_service_start(nome, alvo.nome());
    Ok(atual)
}

/// "Voltar ao padrão do Windows" de um serviço da lista.
pub fn voltar_ao_padrao(store: &mut impl SystemStore, nome: &str) -> Result<StartType, String> {
    let s = gerenciavel(nome).ok_or_else(|| format!("O serviço {nome} não está na lista do Vanta."))?;
    definir(store, nome, s.padrao)
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;

    use super::*;
    use crate::tweaks::RegValue;

    #[derive(Default)]
    struct Fake {
        services: HashMap<String, String>,
        writes: Vec<String>,
    }

    impl SystemStore for Fake {
        fn get_value(&self, _: &str, _: &str) -> Option<RegValue> {
            None
        }
        fn set_value(&mut self, key: &str, name: &str, _: &str, _: RegValue) {
            self.writes.push(format!("{key}|{name}"));
        }
        fn delete_value(&mut self, key: &str, name: &str) {
            self.writes.push(format!("{key}|{name}"));
        }
        fn get_service_start(&self, s: &str) -> Option<String> {
            self.services.get(s).cloned()
        }
        fn set_service_start(&mut self, s: &str, start: &str) {
            self.writes.push(format!("Start:{s}"));
            self.services.insert(s.to_owned(), start.to_owned());
        }
    }

    fn pc() -> Fake {
        let mut f = Fake::default();
        for (n, s) in [("MapsBroker", "Automatic"), ("Fax", "Manual"), ("TrkWks", "Automatic"), ("Spooler", "Automatic")] {
            f.services.insert(n.into(), s.into());
        }
        f
    }

    #[test]
    fn only_the_start_value_is_written_so_triggers_and_delayed_start_stay() {
        let mut f = pc();
        assert_eq!(definir(&mut f, "MapsBroker", StartType::Manual), Ok(StartType::Auto));
        assert_eq!(f.writes, vec!["Start:MapsBroker"], "nenhum outro valor (DelayedAutostart, TriggerInfo) é escrito");
        assert_eq!(voltar_ao_padrao(&mut f, "MapsBroker"), Ok(StartType::Manual));
        assert_eq!(f.services["MapsBroker"], "Automatic");
    }

    #[test]
    fn already_done_is_read_from_the_real_start() {
        let mut f = pc();
        assert_eq!(estado(&f, "Fax", StartType::Manual), EstadoServico::JaFeito);
        assert_eq!(estado(&f, "MapsBroker", StartType::Manual), EstadoServico::Falta { atual: StartType::Auto });
        assert_eq!(estado(&f, "RetailDemo", StartType::Manual), EstadoServico::Ausente);
        definir(&mut f, "MapsBroker", StartType::Manual).unwrap();
        assert_eq!(estado(&f, "MapsBroker", StartType::Manual), EstadoServico::JaFeito);
    }

    #[test]
    fn protected_and_unlisted_services_are_refused() {
        let mut f = pc();
        assert!(definir(&mut f, "Spooler", StartType::Disabled).unwrap_err().contains("protegido"));
        assert!(definir(&mut f, "wuauserv", StartType::Disabled).is_err());
        assert!(definir(&mut f, "AlgumOutro", StartType::Manual).unwrap_err().contains("não está na lista"));
        assert!(definir(&mut f, "RetailDemo", StartType::Manual).unwrap_err().contains("não existe"));
        assert!(f.writes.is_empty());
        assert!(SERVICOS.iter().all(|s| !NUNCA.iter().any(|n| n.eq_ignore_ascii_case(s.nome))));
    }

    #[test]
    fn trkwks_pcasvc_and_dmwappush_are_not_in_the_automatic_balanced_list() {
        let auto: Vec<&str> = SERVICOS.iter().filter(|s| s.equilibrado).map(|s| s.nome).collect();
        assert_eq!(auto, ["MapsBroker", "RetailDemo", "WMPNetworkSvc", "Fax"]);
        assert_eq!(StartType::from_nome("auto"), Some(StartType::Auto));
    }
}
