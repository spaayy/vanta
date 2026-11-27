//! O que o antigo atalho "Restaurar completo" fazia além de copiar pastas: importar o registro dos apps (`.reg`) e
//! registrar as tarefas agendadas, com o usuário antigo trocado pelo de agora. Tudo vira linhas do MESMO script
//! elevado que copia as pastas protegidas: um único pedido de administrador.

use std::io;

use regex::Regex;

use crate::elevate::is_declined;

/// Texto de um arquivo do Windows: UTF-16 (com BOM), UTF-8 com ou sem BOM.
pub fn decode_text(bytes: &[u8]) -> String {
    if let [0xFF, 0xFE, rest @ ..] = bytes {
        let units: Vec<u16> = rest.as_chunks::<2>().0.iter().map(|c| u16::from_le_bytes(*c)).collect();
        return String::from_utf16_lossy(&units);
    }
    String::from_utf8_lossy(bytes).trim_start_matches('\u{feff}').to_owned()
}

/// UTF-16LE com BOM, o que o `reg import` e o `schtasks /XML` leem sem reclamar.
pub fn encode_utf16_bom(text: &str) -> Vec<u8> {
    let mut out = vec![0xFF, 0xFE];
    out.extend(text.encode_utf16().flat_map(u16::to_le_bytes));
    out
}

/// A pasta do usuário do PC antigo, achada nas origens do manifesto (`C:\Users\<nome>`), sem Public nem Default.
pub fn old_profile_from_origins(origins: &[String]) -> Option<String> {
    let pattern = Regex::new(r"^[A-Za-z]:\\Users\\[^\\]+").ok()?;
    origins
        .iter()
        .filter_map(|o| pattern.find(&o.replace('/', "\\")).map(|m| m.as_str().to_owned()))
        .find(|p| !p.to_lowercase().ends_with("\\public") && !p.to_lowercase().ends_with("\\default"))
}

fn replace_ci(text: &str, from: &str, to: &str) -> String {
    match Regex::new(&format!("(?i){}", regex::escape(from))) {
        Ok(re) => re.replace_all(text, regex::NoExpand(to)).into_owned(),
        Err(_) => text.to_owned(),
    }
}

/// Troca o perfil antigo pelo atual num texto comum.
pub fn map_profile(text: &str, old: &str, new: &str) -> String {
    replace_ci(text, old, new)
}

/// Num `.reg` as barras são dobradas: `C:\\Users\\Old`.
pub fn map_profile_reg(text: &str, old: &str, new: &str) -> String {
    replace_ci(text, &old.replace('\\', "\\\\"), &new.replace('\\', "\\\\"))
}

/// Tarefa agendada: o SID e o `UserId` do PC antigo viram os de agora (contas de sistema `S-1-5-18/19/20` ficam).
pub fn fix_task_xml(xml: &str, sid: &str, old: &str, new: &str) -> String {
    let sids = Regex::new(r"S-1-5-21-\d+-\d+-\d+-\d+").expect("regex fixa");
    let users = Regex::new(r"<UserId>([^<]+)</UserId>").expect("regex fixa");
    let step = sids.replace_all(xml, regex::NoExpand(sid)).into_owned();
    let step = users
        .replace_all(&step, |caps: &regex::Captures| {
            if caps[1].starts_with("S-1-5-") { caps[0].to_owned() } else { format!("<UserId>{sid}</UserId>") }
        })
        .into_owned();
    replace_ci(&step, old, new)
}

/// SID do usuário atual (`whoami /user`).
pub fn current_sid() -> Option<String> {
    let output = std::process::Command::new("whoami").args(["/user", "/fo", "csv", "/nh"]).output().ok()?;
    let text = String::from_utf8_lossy(&output.stdout);
    Regex::new(r"S-1-5-21-\d+-\d+-\d+-\d+").ok()?.find(&text).map(|m| m.as_str().to_owned())
}

/// Recusa do UAC reconhecida (reexporta para quem chama).
pub fn declined(error: &io::Error) -> bool {
    is_declined(error)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn utf16_with_bom_and_utf8_both_decode_and_the_encoder_round_trips() {
        let reg = "Windows Registry Editor Version 5.00\r\n[HKEY_CURRENT_USER\\Software\\X]\r\n\"p\"=\"C:\\\\Users\\\\Old\\\\a\"\r\n";
        assert_eq!(decode_text(&encode_utf16_bom(reg)), reg);
        assert_eq!(decode_text("\u{feff}olá".as_bytes()), "olá");
        assert_eq!(decode_text(b"ascii"), "ascii");
        assert_eq!(&encode_utf16_bom("A")[..], &[0xFF, 0xFE, 0x41, 0x00]);
    }

    #[test]
    fn the_old_profile_is_found_in_the_manifest_origins() {
        let origins = [
            r"C:\Users\Public\x".to_owned(),
            r"C:\Program Files\EqualizerAPO".to_owned(),
            r"C:\Users\Vanta\AppData\Roaming\obs".to_owned(),
        ];
        assert_eq!(old_profile_from_origins(&origins).as_deref(), Some(r"C:\Users\Vanta"));
        assert_eq!(old_profile_from_origins(&[r"D:\x".to_owned()]), None);
    }

    #[test]
    fn reg_files_use_doubled_backslashes() {
        let text = r#""p"="C:\\Users\\Vanta\\AppData\\x" "q"="c:\\users\\vanta\\y""#;
        let out = map_profile_reg(text, r"C:\Users\Vanta", r"C:\Users\Novo$1");
        assert_eq!(out, r#""p"="C:\\Users\\Novo$1\\AppData\\x" "q"="C:\\Users\\Novo$1\\y""#);
    }

    #[test]
    fn task_xml_gets_the_current_sid_and_keeps_system_accounts() {
        let xml = "<Task><UserId>S-1-5-21-1-2-3-1001</UserId><UserId>PC\\antigo</UserId><UserId>S-1-5-18</UserId><Command>C:\\Users\\Vanta\\a.exe</Command></Task>";
        let out = fix_task_xml(xml, "S-1-5-21-9-9-9-1002", r"C:\Users\Vanta", r"C:\Users\Novo");
        assert_eq!(out.matches("<UserId>S-1-5-21-9-9-9-1002</UserId>").count(), 2);
        assert!(
            out.contains("<UserId>S-1-5-18</UserId>")
                && out.contains(r"C:\Users\Novo\a.exe")
                && !out.contains("antigo")
        );
    }
}
