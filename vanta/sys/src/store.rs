//! `SystemStore` real: registro (HKCU/HKLM) e o início dos serviços. Escrever em HKLM e em serviços exige
//! administrador; sem ele o erro volta em [`RegistryStore::take_errors`] e o ajuste não conta como aplicado.

use vanta_core::tweaks::{RegValue, ServiceLookup, SystemStore};
use windows_registry::{CURRENT_USER, Key, LOCAL_MACHINE};

/// `HKCU\Software\X` → (raiz, `Software\X`). `None` para raiz que não conhecemos.
pub fn split_key(key: &str) -> Option<(&'static Key, &str)> {
    let (root, rest) = key.split_once('\\').unwrap_or((key, ""));
    match root.to_ascii_uppercase().as_str() {
        "HKCU" | "HKEY_CURRENT_USER" => Some((CURRENT_USER, rest)),
        "HKLM" | "HKEY_LOCAL_MACHINE" => Some((LOCAL_MACHINE, rest)),
        _ => None,
    }
}

/// Início do serviço no registro: 2 = Automatic, 3 = Manual, 4 = Disabled (0 e 1 são de boot/sistema).
pub fn start_name(code: u32) -> &'static str {
    match code {
        0 => "Boot",
        1 => "System",
        2 => "Automatic",
        3 => "Manual",
        4 => "Disabled",
        _ => "Unknown",
    }
}

pub fn start_code(name: &str) -> Option<u32> {
    match name.to_ascii_lowercase().as_str() {
        "boot" => Some(0),
        "system" => Some(1),
        "automatic" | "auto" => Some(2),
        "manual" => Some(3),
        "disabled" => Some(4),
        _ => None,
    }
}

#[derive(Default)]
pub struct RegistryStore {
    errors: Vec<String>,
}

impl RegistryStore {
    pub fn new() -> Self {
        Self::default()
    }

    /// Erros de escrita desde a última chamada (ex.: acesso negado em HKLM sem administrador).
    pub fn take_errors(&mut self) -> Vec<String> {
        std::mem::take(&mut self.errors)
    }

    fn fail(&mut self, what: &str, error: impl std::fmt::Display) {
        self.errors.push(format!("{what}: {error}"));
    }
}

impl SystemStore for RegistryStore {
    fn get_value(&self, key: &str, name: &str) -> Option<RegValue> {
        let (root, path) = split_key(key)?;
        let opened = root.open(path).ok()?;
        let value = opened.get_value(name).ok()?;
        if let Ok(v) = u32::try_from(value.clone()) {
            return Some(RegValue::Dword(v as i32));
        }
        if let Ok(v) = u64::try_from(value.clone()) {
            return Some(RegValue::Qword(v as i64));
        }
        String::try_from(value).ok().map(RegValue::Text)
    }

    fn set_value(&mut self, key: &str, name: &str, _kind: &str, value: RegValue) {
        let Some((root, path)) = split_key(key) else { return self.fail(key, "raiz desconhecida") };
        let created = match root.create(path) {
            Ok(created) => created,
            Err(error) => return self.fail(&format!("{key}\\{name}"), error),
        };
        let result = match value {
            RegValue::Dword(v) => created.set_u32(name, v as u32),
            RegValue::Qword(v) => created.set_u64(name, v as u64),
            RegValue::Text(v) => created.set_string(name, &v),
        };
        if let Err(error) = result {
            self.fail(&format!("{key}\\{name}"), error);
        }
    }

    fn delete_value(&mut self, key: &str, name: &str) {
        let Some((root, path)) = split_key(key) else { return };
        if let Ok(opened) = root.options().read().write().open(path) {
            let _ = opened.remove_value(name); // já não existir é o resultado desejado
        }
    }

    fn get_service_start(&self, service: &str) -> Option<String> {
        match scm::query(service) {
            Ok(code) => Some(start_name(code).to_owned()),
            Err(_) => None, // use `service_lookup` quando precisar separar "não existe" de "acesso negado"
        }
    }

    fn service_lookup(&self, service: &str) -> ServiceLookup {
        match scm::query(service) {
            Ok(code) => ServiceLookup::Found(start_name(code).to_owned()),
            Err(scm::ScmError::Missing) => ServiceLookup::Missing,
            Err(scm::ScmError::Denied(why) | scm::ScmError::Other(why)) => ServiceLookup::Denied(why),
        }
    }

    fn set_service_start(&mut self, service: &str, start: &str) {
        let Some(code) = start_code(start) else {
            return self.fail(service, format!("início '{start}' desconhecido"));
        };
        // só o tipo de início muda (`SERVICE_NO_CHANGE` no resto): gatilhos, dependências e o início atrasado ficam
        if let Err(error) = scm::change_start(service, code) {
            let why = match error {
                scm::ScmError::Missing => "o serviço não existe".to_owned(),
                scm::ScmError::Denied(w) | scm::ScmError::Other(w) => w,
            };
            self.fail(&format!("serviço {service}"), why);
        }
    }
}

/// Gerenciador de serviços (SCM) do Windows: ler e mudar o início de um serviço sem mexer no registro à mão.
mod scm {
    use windows::Win32::System::Services::{
        CloseServiceHandle, ChangeServiceConfigW, ENUM_SERVICE_TYPE, OpenSCManagerW, OpenServiceW, QUERY_SERVICE_CONFIGW, QueryServiceConfigW, SC_HANDLE,
        SC_MANAGER_CONNECT, SERVICE_CHANGE_CONFIG, SERVICE_ERROR, SERVICE_QUERY_CONFIG, SERVICE_START_TYPE,
    };
    use windows::core::{HRESULT, PCWSTR};

    const ERROR_ACCESS_DENIED: u32 = 5;
    const ERROR_SERVICE_DOES_NOT_EXIST: u32 = 1060;
    const ERROR_INVALID_NAME: u32 = 123;
    const NO_CHANGE: u32 = 0xFFFF_FFFF;

    #[derive(Debug, PartialEq, Eq)]
    pub enum ScmError {
        /// O serviço não existe (nome desconhecido neste Windows).
        Missing,
        /// O Windows negou o acesso (falta administrador).
        Denied(String),
        Other(String),
    }

    fn classify(error: &windows::core::Error) -> ScmError {
        let code = error.code();
        if code == HRESULT::from_win32(ERROR_SERVICE_DOES_NOT_EXIST) || code == HRESULT::from_win32(ERROR_INVALID_NAME) {
            ScmError::Missing
        } else if code == HRESULT::from_win32(ERROR_ACCESS_DENIED) {
            ScmError::Denied(error.message())
        } else {
            ScmError::Other(error.message())
        }
    }

    /// Fecha o handle ao sair, qualquer que seja o caminho.
    struct Handle(SC_HANDLE);

    impl Drop for Handle {
        fn drop(&mut self) {
            // SAFETY: o handle veio de OpenSCManagerW/OpenServiceW e é fechado uma única vez, aqui.
            unsafe {
                let _ = CloseServiceHandle(self.0);
            }
        }
    }

    fn open(name: &str, access: u32) -> Result<Handle, ScmError> {
        let wide: Vec<u16> = name.encode_utf16().chain(std::iter::once(0)).collect();
        // SAFETY: chamadas Win32 com ponteiros para buffers vivos até o fim da chamada.
        unsafe {
            let manager = Handle(OpenSCManagerW(PCWSTR::null(), PCWSTR::null(), SC_MANAGER_CONNECT).map_err(|e| classify(&e))?);
            let service = OpenServiceW(manager.0, PCWSTR(wide.as_ptr()), access).map_err(|e| classify(&e))?;
            Ok(Handle(service))
        }
    }

    /// O tipo de início atual (0 boot, 1 system, 2 automático, 3 manual, 4 desativado).
    pub fn query(name: &str) -> Result<u32, ScmError> {
        let service = open(name, SERVICE_QUERY_CONFIG)?;
        let mut needed = 0u32;
        // SAFETY: primeira chamada só pergunta o tamanho (buffer nulo); a segunda usa um buffer alinhado de `needed` bytes.
        unsafe {
            let _ = QueryServiceConfigW(service.0, None, 0, &mut needed);
            if needed == 0 {
                return Err(ScmError::Other("QueryServiceConfig não informou o tamanho".into()));
            }
            let mut buffer = vec![0u64; (needed as usize).div_ceil(8)];
            let config = buffer.as_mut_ptr().cast::<QUERY_SERVICE_CONFIGW>();
            QueryServiceConfigW(service.0, Some(config), needed, &mut needed).map_err(|e| classify(&e))?;
            Ok((*config).dwStartType.0)
        }
    }

    /// Muda só o tipo de início (2 automático, 3 manual, 4 desativado).
    pub fn change_start(name: &str, start: u32) -> Result<(), ScmError> {
        let service = open(name, SERVICE_CHANGE_CONFIG)?;
        // SAFETY: `SERVICE_NO_CHANGE` em tudo que não é o início; strings nulas = não mudar.
        unsafe {
            ChangeServiceConfigW(
                service.0,
                ENUM_SERVICE_TYPE(NO_CHANGE),
                SERVICE_START_TYPE(start),
                SERVICE_ERROR(NO_CHANGE),
                PCWSTR::null(),
                PCWSTR::null(),
                None,
                PCWSTR::null(),
                PCWSTR::null(),
                PCWSTR::null(),
                PCWSTR::null(),
            )
            .map_err(|e| classify(&e))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn keys_split_into_root_and_path() {
        assert!(split_key(r"HKCU\Software\X").is_some_and(|(_, p)| p == r"Software\X"));
        assert!(split_key(r"hklm\SOFTWARE\Y").is_some_and(|(_, p)| p == r"SOFTWARE\Y"));
        assert!(split_key(r"HKU\x").is_none());
    }

    #[test]
    fn service_start_names_round_trip() {
        for (code, name) in [(2, "Automatic"), (3, "Manual"), (4, "Disabled")] {
            assert_eq!(start_name(code), name);
            assert_eq!(start_code(name), Some(code));
        }
        assert_eq!(start_code("auto"), Some(2));
        assert_eq!(start_code("nada"), None);
    }

    #[test]
    fn reading_a_value_that_does_not_exist_is_none_and_never_writes() {
        let store = RegistryStore::new();
        assert_eq!(store.get_value(r"HKCU\Software\VantaNaoExiste-0001", "x"), None);
        assert_eq!(store.get_service_start("VantaServicoQueNaoExiste"), None);
        assert_eq!(store.service_lookup("VantaServicoQueNaoExiste"), ServiceLookup::Missing, "inexistente não é acesso negado");
        // um serviço que existe em todo Windows e qualquer usuário pode consultar
        assert!(matches!(store.service_lookup("EventLog"), ServiceLookup::Found(start) if start == "Automatic"));
        assert_eq!(store.get_service_start("EventLog").as_deref(), Some("Automatic"));
    }
}
