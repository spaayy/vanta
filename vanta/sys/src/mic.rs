//! Pontos de áudio do Windows (para achar o microfone pelo nome no destino).

use vanta_core::restore::AudioEndpoint;

use crate::niveis::{Executor, ProcessExecutor, powershell};

const ENDPOINTS_SCRIPT: &str = "Get-PnpDevice -Class AudioEndpoint -PresentOnly -ErrorAction SilentlyContinue | Select-Object FriendlyName,InstanceId | ConvertTo-Json -Compress";

/// Interpreta a saída JSON de `Get-PnpDevice ... | Select FriendlyName, InstanceId | ConvertTo-Json`
/// (um objeto quando há um só, uma lista quando há vários).
pub fn parse_endpoints(json: &str) -> Vec<AudioEndpoint> {
    let Ok(value) = serde_json::from_str::<serde_json::Value>(json.trim_start_matches('\u{feff}')) else {
        return Vec::new();
    };
    let list = match value {
        serde_json::Value::Array(items) => items,
        object @ serde_json::Value::Object(_) => vec![object],
        _ => Vec::new(),
    };
    list.iter()
        .filter_map(|item| {
            Some(AudioEndpoint {
                friendly_name: item.get("FriendlyName")?.as_str()?.to_owned(),
                instance_id: item.get("InstanceId")?.as_str()?.to_owned(),
            })
        })
        .collect()
}

fn list_endpoints_with(exec: &dyn Executor) -> Vec<AudioEndpoint> {
    powershell(exec, ENDPOINTS_SCRIPT)
        .map(|out| parse_endpoints(&out))
        .unwrap_or_default()
}

/// Lista os pontos de áudio presentes (PowerShell em UTF-8, sem janela). Vazia se o comando falhar.
pub fn list_endpoints() -> Vec<AudioEndpoint> {
    list_endpoints_with(&ProcessExecutor)
}

#[cfg(test)]
mod tests {
    use std::cell::RefCell;

    use super::*;

    #[test]
    fn one_object_or_a_list_both_parse() {
        let one = r#"{"FriendlyName":"Microfone (fifine)","InstanceId":"SWD\\MMDEVAPI\\{0.0.1.00000000}.{aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee}"}"#;
        assert_eq!(parse_endpoints(one).len(), 1);
        let many = format!("[{one},{one}]");
        assert_eq!(parse_endpoints(&many)[1].friendly_name, "Microfone (fifine)");
        assert!(
            parse_endpoints("").is_empty()
                && parse_endpoints("null").is_empty()
                && parse_endpoints("{}").is_empty()
        );
    }

    struct FakeExec {
        response: String,
        seen: RefCell<Vec<String>>,
    }

    impl Executor for FakeExec {
        fn run(&self, program: &str, args: &[String]) -> Result<String, String> {
            self.seen.borrow_mut().push(format!("{program} {}", args.join(" ")));
            Ok(self.response.clone())
        }
    }

    #[test]
    fn powershell_output_is_utf8_so_accents_in_mic_names_survive() {
        // caminho real do PowerShell usado pelo mic.rs preserva acentos (ex.: "Fila de Impressão da Raiz")
        let script = r#"[pscustomobject]@{FriendlyName='Microfone (Fila de Impressão da Raiz)';InstanceId='SWD\MMDEVAPI\1'} | ConvertTo-Json -Compress"#;
        let out = powershell(&ProcessExecutor, script).unwrap();
        let parsed = parse_endpoints(&out);
        assert_eq!(parsed.len(), 1);
        assert_eq!(parsed[0].friendly_name, "Microfone (Fila de Impressão da Raiz)");

        // list_endpoints_with usa o mesmo prefixo UTF-8 de niveis::powershell
        let fake = FakeExec {
            response: r#"{"FriendlyName":"Microfone de Estúdio — Fila de Impressão da Raiz","InstanceId":"SWD\\MMDEVAPI\\2"}"#.into(),
            seen: RefCell::new(Vec::new()),
        };
        let endpoints = list_endpoints_with(&fake);
        assert_eq!(endpoints.len(), 1);
        assert_eq!(endpoints[0].friendly_name, "Microfone de Estúdio — Fila de Impressão da Raiz");
        let log = fake.seen.borrow().join("\n");
        assert!(log.contains("[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)"));
        assert!(log.contains("Get-PnpDevice -Class AudioEndpoint"));
    }
}
