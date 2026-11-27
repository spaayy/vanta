//! Apps do Windows que o Vanta Tools pode remover e reinstalar, um a um e só no usuário atual (Hito 3315).
//!
//! A Microsoft Store e o App Installer (winget) NUNCA saem: não há remoção nem "reparo" por `wsreset -i`. Nenhum nível
//! remove app. Os ids vêm desta tabela (fonte + id exatos); nada de texto livre chega à linha de comando.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Fonte {
    Winget,
    Msstore,
}

impl Fonte {
    pub fn id(self) -> &'static str {
        match self {
            Fonte::Winget => "winget",
            Fonte::Msstore => "msstore",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct AppAlvo {
    pub chave: &'static str,
    pub nome: &'static str,
    pub fonte: Fonte,
    /// O id exato no `winget` (na fonte `msstore` é o ProductId).
    pub id: &'static str,
    /// Nome do pacote Appx (`Get-AppxPackage -Name`), quando o app é Appx; vazio se não for.
    pub appx: &'static str,
    /// Aviso mostrado antes de remover.
    pub aviso: &'static str,
}

pub const APPS: [AppAlvo; 5] = [
    AppAlvo { chave: "outlook", nome: "Outlook (novo)", fonte: Fonte::Msstore, id: "9NRX63209R7B", appx: "Microsoft.OutlookForWindows", aviso: "Quem usa Outlook para trabalho perde o app novo; o Outlook clássico e o da web seguem funcionando." },
    AppAlvo { chave: "xbox", nome: "Xbox e Game Pass", fonte: Fonte::Msstore, id: "9MV0B5HZVK9Z", appx: "Microsoft.GamingApp", aviso: "Game Pass, Minecraft e jogos com login Xbox podem parar. Os serviços de jogos ficam até o login e os jogos serem testados." },
    AppAlvo { chave: "teams", nome: "Microsoft Teams", fonte: Fonte::Winget, id: "Microsoft.Teams", appx: "MSTeams", aviso: "Reuniões e chats de trabalho do Teams deixam de abrir neste PC." },
    AppAlvo { chave: "onedrive", nome: "OneDrive", fonte: Fonte::Winget, id: "Microsoft.OneDrive", appx: "", aviso: "Pare a sincronização antes: arquivos só na nuvem deixam de abrir neste PC." },
    AppAlvo { chave: "edge", nome: "Microsoft Edge", fonte: Fonte::Winget, id: "Microsoft.Edge", appx: "", aviso: "O WebView2 fica. Escolha antes outro navegador." },
];

/// Pacotes que nunca saem, com o motivo.
pub const PROTEGIDOS: [(&str, &str); 3] = [
    ("Microsoft.WindowsStore", "A Microsoft Store fica instalada em todos os perfis."),
    ("Microsoft.DesktopAppInstaller", "O App Installer (winget) é o que instala e restaura os apps."),
    ("Microsoft.WebView2", "O WebView2 é usado por outros programas."),
];

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ErroApp {
    Protegido(String),
    Desconhecido(String),
}

impl std::fmt::Display for ErroApp {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ErroApp::Protegido(m) => f.write_str(m),
            ErroApp::Desconhecido(k) => write!(f, "App desconhecido: {k}"),
        }
    }
}

/// O app pela chave da tela. A Store e o App Installer voltam como `Protegido` (com o motivo).
pub fn achar(chave: &str) -> Result<&'static AppAlvo, ErroApp> {
    let lower = chave.to_ascii_lowercase();
    if lower == "store" || lower == "microsoftstore" {
        return Err(ErroApp::Protegido(PROTEGIDOS[0].1.to_owned()));
    }
    if lower == "winget" || lower == "appinstaller" {
        return Err(ErroApp::Protegido(PROTEGIDOS[1].1.to_owned()));
    }
    APPS.iter().find(|a| a.chave == lower).ok_or_else(|| ErroApp::Desconhecido(chave.to_owned()))
}

/// O que executar: programa e argumentos. Escopo do usuário atual; sem `-AllUsers`, sem `/force`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Acao {
    pub programa: &'static str,
    pub args: Vec<String>,
}

fn args(list: &[&str]) -> Vec<String> {
    list.iter().map(|a| (*a).to_owned()).collect()
}

/// Remove só para o usuário atual: Appx → `Remove-AppxPackage` (sem `-AllUsers`); o resto → `winget uninstall`.
pub fn remover(app: &AppAlvo) -> Acao {
    if app.appx.is_empty() {
        let mut a = args(&["uninstall", "--id", app.id, "--exact", "--source", app.fonte.id(), "--scope", "user", "--silent", "--disable-interactivity"]);
        if app.fonte == Fonte::Msstore {
            a.retain(|x| x != "--scope" && x != "user");
        }
        return Acao { programa: "winget.exe", args: a };
    }
    Acao {
        programa: "powershell.exe",
        args: args(&["-NoProfile", "-NonInteractive", "-Command", &format!("Get-AppxPackage -Name '{}' | Remove-AppxPackage -ErrorAction Stop", app.appx)]),
    }
}

/// "Reinstalar app": instala de novo pela fonte exata. Dados e configurações do app NÃO voltam (o texto da tela diz isso).
pub fn reinstalar(app: &AppAlvo) -> Acao {
    Acao {
        programa: "winget.exe",
        args: args(&["install", "--id", app.id, "--exact", "--source", app.fonte.id(), "--silent", "--accept-package-agreements", "--accept-source-agreements", "--disable-interactivity"]),
    }
}

/// O texto do botão de volta: não promete restaurar dados.
pub const ROTULO_REINSTALAR: &str = "Reinstalar app";
pub const NOTA_REINSTALAR: &str = "Instala de novo o app. Os dados e as configurações que ele tinha neste usuário não voltam.";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EstadoApp {
    Instalado,
    /// Já está removido: entra em "Já feito pelo Vanta".
    Removido,
    Desconhecido,
}

/// Lê se o app está instalado. O Vanta Tools liga o real (`Get-AppxPackage`, registro); os testes usam um falso.
pub trait LeitorApps {
    fn instalado(&self, app: &AppAlvo) -> Option<bool>;
}

pub fn estado(leitor: &dyn LeitorApps, app: &AppAlvo) -> EstadoApp {
    match leitor.instalado(app) {
        Some(true) => EstadoApp::Instalado,
        Some(false) => EstadoApp::Removido,
        None => EstadoApp::Desconhecido,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    struct Fake(Option<bool>);
    impl LeitorApps for Fake {
        fn instalado(&self, _: &AppAlvo) -> Option<bool> {
            self.0
        }
    }

    #[test]
    fn the_store_and_the_app_installer_can_never_be_removed() {
        for key in ["store", "Store", "MicrosoftStore", "winget", "AppInstaller"] {
            assert!(matches!(achar(key), Err(ErroApp::Protegido(_))), "{key}");
        }
        assert!(APPS.iter().all(|a| !a.id.contains("WindowsStore") && !a.id.contains("DesktopAppInstaller")));
        assert_eq!(achar("nada"), Err(ErroApp::Desconhecido("nada".into())));
    }

    #[test]
    fn exact_ids_and_sources_come_from_the_table() {
        let get = |k| achar(k).unwrap();
        assert_eq!((get("outlook").fonte, get("outlook").id), (Fonte::Msstore, "9NRX63209R7B"));
        assert_eq!((get("xbox").fonte, get("xbox").id), (Fonte::Msstore, "9MV0B5HZVK9Z"));
        for (k, id) in [("teams", "Microsoft.Teams"), ("onedrive", "Microsoft.OneDrive"), ("edge", "Microsoft.Edge")] {
            assert_eq!((get(k).fonte, get(k).id), (Fonte::Winget, id));
        }
    }

    #[test]
    fn removal_is_current_user_only_and_never_forced() {
        for app in &APPS {
            let r = remover(app);
            let text = r.args.join(" ");
            assert!(!text.contains("-AllUsers") && !text.contains("/force") && !text.contains("--force") && !text.contains("wsreset"), "{text}");
        }
        let outlook = remover(achar("outlook").unwrap());
        assert_eq!(outlook.programa, "powershell.exe");
        assert!(outlook.args[3].contains("Get-AppxPackage -Name 'Microsoft.OutlookForWindows' | Remove-AppxPackage"));
        let onedrive = remover(achar("onedrive").unwrap());
        assert_eq!(onedrive.programa, "winget.exe");
        assert!(onedrive.args.windows(2).any(|w| w == ["--scope", "user"]));
        let back = reinstalar(achar("xbox").unwrap());
        assert_eq!(back.args[..6], ["install", "--id", "9MV0B5HZVK9Z", "--exact", "--source", "msstore"]);
        assert!(NOTA_REINSTALAR.contains("não voltam") && ROTULO_REINSTALAR == "Reinstalar app");
    }

    #[test]
    fn a_removed_app_is_already_done() {
        let app = achar("teams").unwrap();
        assert_eq!(estado(&Fake(Some(false)), app), EstadoApp::Removido);
        assert_eq!(estado(&Fake(Some(true)), app), EstadoApp::Instalado);
        assert_eq!(estado(&Fake(None), app), EstadoApp::Desconhecido);
    }
}
