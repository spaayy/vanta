//! Administrador: saber se o processo já é, e rodar algo com o pedido de elevação do Windows (UAC).

use std::io;
use std::os::windows::ffi::OsStrExt;
use std::path::{Path, PathBuf};

use windows::Win32::Foundation::{CloseHandle, ERROR_CANCELLED, HANDLE, WAIT_OBJECT_0};
use windows::Win32::Security::{GetTokenInformation, TOKEN_ELEVATION, TOKEN_QUERY, TokenElevation};
use windows::Win32::System::SystemInformation::GetSystemDirectoryW;
use windows::Win32::System::Threading::{
    GetCurrentProcess, GetExitCodeProcess, OpenProcessToken, WaitForSingleObject,
};
use windows::Win32::UI::Shell::{SEE_MASK_NOCLOSEPROCESS, SHELLEXECUTEINFOW, ShellExecuteExW};
use windows::Win32::UI::WindowsAndMessaging::{SW_HIDE, SW_SHOWNORMAL};
use windows::core::PCWSTR;

/// O usuário recusou o pedido de administrador.
#[derive(Debug)]
pub struct UacDeclined;

impl std::fmt::Display for UacDeclined {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("O pedido de administrador foi recusado.")
    }
}

impl std::error::Error for UacDeclined {}

/// O processo atual roda como administrador.
pub fn is_elevated() -> bool {
    let mut token = HANDLE::default();
    // SAFETY: chamadas Win32 com ponteiros para variáveis locais válidas durante a chamada.
    unsafe {
        if OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &mut token).is_err() {
            return false;
        }
        let mut elevation = TOKEN_ELEVATION::default();
        let mut returned = 0u32;
        let ok = GetTokenInformation(
            token,
            TokenElevation,
            Some((&raw mut elevation).cast()),
            size_of::<TOKEN_ELEVATION>() as u32,
            &mut returned,
        )
        .is_ok();
        let _ = CloseHandle(token);
        ok && elevation.TokenIsElevated != 0
    }
}

fn wide(text: &str) -> Vec<u16> {
    std::ffi::OsStr::new(text).encode_wide().chain(Some(0)).collect()
}

/// Um processo iniciado com elevação. Fechar o objeto fecha só o handle, não o processo.
pub struct ElevatedProcess(HANDLE);

// SAFETY: o handle de processo pode ser esperado e fechado de qualquer thread.
unsafe impl Send for ElevatedProcess {}

impl ElevatedProcess {
    /// Espera até `millis`; `true` se o processo terminou.
    pub fn wait(&self, millis: u32) -> bool {
        // SAFETY: o handle é válido enquanto `self` existir.
        unsafe { WaitForSingleObject(self.0, millis) == WAIT_OBJECT_0 }
    }

    pub fn exit_code(&self) -> Option<u32> {
        let mut code = 0u32;
        // SAFETY: o handle é válido e `code` vive durante a chamada.
        unsafe { GetExitCodeProcess(self.0, &mut code).ok().map(|()| code) }
    }
}

impl Drop for ElevatedProcess {
    fn drop(&mut self) {
        // SAFETY: handle obtido de ShellExecuteExW, fechado uma vez.
        unsafe {
            let _ = CloseHandle(self.0);
        }
    }
}

/// O que vai para o `ShellExecuteExW`. Separado para poder testar o verbo sem abrir o pedido de UAC.
#[derive(Debug, PartialEq, Eq)]
pub struct LaunchSpec {
    pub verb: &'static str,
    pub file: String,
    pub parameters: String,
    /// Janela visível (reabrir o app) ou oculta (trabalhador do lote).
    pub visible: bool,
}

/// Um argumento na linha de comando do Windows: entre aspas se tiver espaço ou aspas.
pub fn quote_arg(arg: &str) -> String {
    if !arg.is_empty() && !arg.contains([' ', '\t', '"']) {
        return arg.to_owned();
    }
    let mut out = String::from("\"");
    let mut backslashes = 0usize;
    for c in arg.chars() {
        match c {
            '\\' => backslashes += 1,
            '"' => {
                out.push_str(&"\\".repeat(backslashes * 2 + 1));
                out.push('"');
                backslashes = 0;
            }
            _ => {
                out.push_str(&"\\".repeat(backslashes));
                out.push(c);
                backslashes = 0;
            }
        }
    }
    out.push_str(&"\\".repeat(backslashes * 2));
    out.push('"');
    out
}

/// Reabrir o próprio programa como administrador: mesmo `exe`, mesmos argumentos, janela visível, verbo `runas`.
/// Não aplica nada: só pede ao Windows que abra de novo.
pub fn relaunch_spec(exe: &Path, args: &[String]) -> LaunchSpec {
    LaunchSpec {
        verb: "runas",
        file: exe.to_string_lossy().into_owned(),
        parameters: args.iter().map(|a| quote_arg(a)).collect::<Vec<_>>().join(" "),
        visible: true,
    }
}

/// Reabre `exe` com `args` como administrador (UAC). O chamador fecha a janela atual se der certo.
pub fn relaunch_as_admin(exe: &Path, args: &[String]) -> io::Result<()> {
    shell_execute(&relaunch_spec(exe, args), None).map(drop)
}

/// Inicia `file parameters` com o verbo `runas` (pede UAC) e janela oculta.
pub fn run_elevated(file: &str, parameters: &str, working_dir: Option<&Path>) -> io::Result<ElevatedProcess> {
    let spec = LaunchSpec {
        verb: "runas",
        file: file.to_owned(),
        parameters: parameters.to_owned(),
        visible: false,
    };
    shell_execute(&spec, working_dir)
}

fn shell_execute(spec: &LaunchSpec, working_dir: Option<&Path>) -> io::Result<ElevatedProcess> {
    let verb = wide(spec.verb);
    let file = wide(&spec.file);
    let parameters = wide(&spec.parameters);
    let dir = working_dir.map(|d| wide(&d.to_string_lossy()));
    let mut info = SHELLEXECUTEINFOW {
        cbSize: size_of::<SHELLEXECUTEINFOW>() as u32,
        fMask: SEE_MASK_NOCLOSEPROCESS,
        lpVerb: PCWSTR(verb.as_ptr()),
        lpFile: PCWSTR(file.as_ptr()),
        lpParameters: PCWSTR(parameters.as_ptr()),
        lpDirectory: dir.as_ref().map_or(PCWSTR::null(), |d| PCWSTR(d.as_ptr())),
        nShow: if spec.visible { SW_SHOWNORMAL.0 } else { SW_HIDE.0 },
        ..Default::default()
    };
    // SAFETY: `info` e os buffers apontados vivem até o fim da chamada.
    match unsafe { ShellExecuteExW(&mut info) } {
        Ok(()) if !info.hProcess.is_invalid() => Ok(ElevatedProcess(info.hProcess)),
        Ok(()) => Err(io::Error::other("O Windows não devolveu o processo elevado.")),
        Err(error) if error.code() == ERROR_CANCELLED.to_hresult() => Err(io::Error::other(UacDeclined)),
        Err(error) => Err(io::Error::other(error)),
    }
}

/// O PowerShell do diretório de sistema que o próprio Windows informa (`GetSystemDirectory`). Nunca vem de variável de
/// ambiente (quem pede a elevação controla o ambiente) nem do nome simples (a busca no PATH acharia outro programa).
/// Se o Windows não informa o diretório ou o arquivo não existe, falha: o pedido de administrador não é feito.
pub fn system_powershell() -> io::Result<PathBuf> {
    powershell_in(&system_directory()?)
}

/// O diretório de sistema (`C:\Windows\System32`) como o Windows informa (`GetSystemDirectory`).
pub fn system_directory() -> io::Result<String> {
    let mut buffer = [0u16; 260];
    // SAFETY: o buffer vive durante a chamada e o tamanho dele é passado junto.
    let length = unsafe { GetSystemDirectoryW(Some(&mut buffer)) } as usize;
    if length == 0 || length >= buffer.len() {
        return Err(io::Error::other(
            "O Windows não informou o diretório de sistema; o pedido de administrador não foi feito.",
        ));
    }
    Ok(String::from_utf16_lossy(&buffer[..length]))
}

/// `<diretório de sistema>\WindowsPowerShell\v1.0\powershell.exe`, só se o arquivo existe.
pub fn powershell_in(system_dir: &str) -> io::Result<PathBuf> {
    let path =
        PathBuf::from(system_dir.trim_end_matches('\\')).join(r"WindowsPowerShell\v1.0\powershell.exe");
    if path.is_file() {
        Ok(path)
    } else {
        Err(io::Error::other(format!("O PowerShell do sistema não foi encontrado em {}.", path.display())))
    }
}

/// `true` se o erro é a recusa do UAC.
pub fn is_declined(error: &io::Error) -> bool {
    error.get_ref().is_some_and(|inner| inner.is::<UacDeclined>())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn asking_if_elevated_does_not_fail() {
        let _ = is_elevated();
    }

    #[test]
    fn a_declined_prompt_is_recognised() {
        assert!(is_declined(&io::Error::other(UacDeclined)));
        assert!(!is_declined(&io::Error::other("outro erro")));
    }

    #[test]
    fn reopening_as_administrator_asks_runas_with_a_visible_window_and_the_same_arguments() {
        let spec = relaunch_spec(
            Path::new(r"C:\Program Files\Vanta\VantaTools.exe"),
            &["--kit".into(), r"D:\Meu Kit".into(), "--page".into(), "restore".into()],
        );
        assert_eq!(spec.verb, "runas");
        assert!(spec.visible, "o app reaberto tem de aparecer");
        assert_eq!(spec.file, r"C:\Program Files\Vanta\VantaTools.exe");
        assert_eq!(spec.parameters, r#"--kit "D:\Meu Kit" --page restore"#);
        assert_eq!(relaunch_spec(Path::new("a.exe"), &[]).parameters, "", "sem argumentos, nada a mais");
    }

    #[test]
    fn the_elevated_powershell_comes_from_the_windows_system_directory_not_from_the_environment() {
        let real = system_powershell().unwrap();
        assert!(real.is_absolute() && real.ends_with(r"WindowsPowerShell\v1.0\powershell.exe"), "{real:?}");
        // um ambiente adulterado não muda nada: a resposta vem da API do Windows
        let before = std::env::var_os("SystemRoot");
        // SAFETY: a variável só é lida por esta função de teste; restaurada logo depois.
        unsafe { std::env::set_var("SystemRoot", r"C:\Temp\falso") };
        let with_fake_env = system_powershell().unwrap();
        match before {
            // SAFETY: idem.
            Some(value) => unsafe { std::env::set_var("SystemRoot", value) },
            None => unsafe { std::env::remove_var("SystemRoot") },
        }
        assert_eq!(real, with_fake_env);
        // sem o arquivo, falha em vez de cair no nome simples
        let dir = tempfile::tempdir().unwrap();
        assert!(powershell_in(&dir.path().to_string_lossy()).is_err());
        let ps = dir.path().join(r"WindowsPowerShell\v1.0");
        std::fs::create_dir_all(&ps).unwrap();
        std::fs::write(ps.join("powershell.exe"), "x").unwrap();
        assert!(powershell_in(&dir.path().to_string_lossy()).is_ok());
    }

    #[test]
    fn arguments_are_quoted_the_way_windows_parses_them() {
        assert_eq!(quote_arg("simples"), "simples");
        assert_eq!(quote_arg("com espaço"), "\"com espaço\"");
        assert_eq!(quote_arg(r#"a"b"#), r#""a\"b""#);
        assert_eq!(quote_arg(r"C:\pasta com espaço\"), r#""C:\pasta com espaço\\""#);
        assert_eq!(quote_arg(""), "\"\"");
    }
}
