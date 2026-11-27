//! O que o Vanta 1 fazia depois de restaurar e que o Restaurar do Vanta 2 também faz: tarefa agendada do ISLC, entradas
//! `Run` (iniciar com o Windows) e o renomeio NathaSystem → VantaSystem (pasta do AutoOptimizer e referências).
//!
//! Regras (achados J do hito):
//! - a tarefa e as entradas só existem para programas que o MANIFESTO conferido do kit carrega (um executável no disco
//!   não basta), com o comando validado ([`crate::restore_plan`]);
//! - nada que já exista é sobrescrito (o lado elevado pula e avisa se há outra entrada/tarefa com o mesmo nome);
//! - o renomeio só toca arquivos que esta execução provadamente restaurou (iguais aos do kit), preserva a codificação
//!   e só apaga o original depois de validar a cópia.

use std::fs;
use std::io::{self, Write};
use std::path::Path;

use crate::restore_batch::encode_utf16_bom;
use crate::restore_plan::{PlanRun, PlanTask, TaskRoots, path_inside, validate_run_command, validate_task};

const OLD: &str = "NathaSystem";
const NEW: &str = "VantaSystem";

/// Troca o nome antigo pelo novo num texto.
pub fn rename_text(text: &str) -> String {
    text.replace(OLD, NEW)
}

/// `NathaSystem.ps1` → `VantaSystem.ps1` (só o prefixo).
pub fn renamed_name(name: &str) -> String {
    name.strip_prefix(OLD).map_or_else(|| name.to_owned(), |rest| format!("{NEW}{rest}"))
}

fn is_text_name(name: &str) -> bool {
    Path::new(name)
        .extension()
        .is_some_and(|e| e.eq_ignore_ascii_case("ps1") || e.eq_ignore_ascii_case("json"))
}

/// Os bytes do arquivo já com o nome novo dentro, na MESMA codificação (UTF-16 LE/BE com BOM, UTF-8 com ou sem BOM).
/// `None` se o texto não é nenhuma delas (ANSI, binário): quem chama só muda o nome do arquivo e deixa os bytes.
pub fn renamed_bytes(bytes: &[u8]) -> Option<Vec<u8>> {
    if let [0xFF, 0xFE, rest @ ..] = bytes {
        if rest.len() % 2 != 0 {
            return None;
        }
        let units: Vec<u16> = rest.as_chunks::<2>().0.iter().map(|c| u16::from_le_bytes(*c)).collect();
        let text = String::from_utf16(&units).ok()?;
        return Some(encode_utf16_bom(&rename_text(&text)));
    }
    if let [0xFE, 0xFF, rest @ ..] = bytes {
        if rest.len() % 2 != 0 {
            return None;
        }
        let units: Vec<u16> = rest.as_chunks::<2>().0.iter().map(|c| u16::from_be_bytes(*c)).collect();
        let text = String::from_utf16(&units).ok()?;
        let mut out = vec![0xFE, 0xFF];
        out.extend(rename_text(&text).encode_utf16().flat_map(u16::to_be_bytes));
        return Some(out);
    }
    let (bom, body) = match bytes {
        [0xEF, 0xBB, 0xBF, rest @ ..] => (true, rest),
        other => (false, other),
    };
    let text = std::str::from_utf8(body).ok()?;
    let mut out = if bom { vec![0xEF, 0xBB, 0xBF] } else { Vec::new() };
    out.extend(rename_text(text).into_bytes());
    Some(out)
}

/// Os arquivos `NathaSystem*` que esta execução restaurou: existem na pasta do kit (`source`) e a cópia em `destination`
/// tem exatamente os mesmos bytes. Um arquivo que só existe no destino (do usuário) ou que a cópia deixou diferente
/// (falha parcial) fica de fora. Só conta o que está em `copied` (destinos que esta execução registrou como copiados).
pub fn restored_nathasystem(source: &Path, destination: &Path, copied: &[String]) -> Vec<String> {
    let was_copied = |name: &str| {
        let wanted = destination.join(name).to_string_lossy().replace('/', "\\").to_lowercase();
        copied.iter().any(|c| c.replace('/', "\\").to_lowercase() == wanted)
    };
    let mut names: Vec<String> = fs::read_dir(source)
        .into_iter()
        .flatten()
        .flatten()
        .filter(|e| e.file_type().is_ok_and(|t| t.is_file()))
        .map(|e| e.file_name().to_string_lossy().into_owned())
        .filter(|name| name.starts_with(OLD) && was_copied(name))
        .filter(|name| match (fs::read(source.join(name)), fs::read(destination.join(name))) {
            (Ok(from), Ok(to)) => from == to,
            _ => false,
        })
        .collect();
    names.sort();
    names
}

fn not_validated(name: &str) -> io::Error {
    io::Error::other(format!(
        "{name}: a cópia {} não passou na conferência; o original foi mantido.",
        renamed_name(name)
    ))
}

/// Migra, dentro de `dir`, os arquivos de `restored` para o nome novo. A cópia nova é escrita ao lado, conferida
/// (relida e comparada) e só então o original é apagado; nunca sobrescreve um arquivo que já exista; qualquer falha
/// deixa o original intacto e remove só a cópia que acabou de criar. Devolve os nomes novos.
pub fn migrate_nathasystem(dir: &Path, restored: &[String]) -> io::Result<Vec<String>> {
    let mut done = Vec::new();
    for name in restored {
        // só nome simples com o prefixo antigo: nada de caminho vindo de fora
        if !name.starts_with(OLD) || name.contains(['\\', '/', ':']) {
            continue;
        }
        let original = dir.join(name);
        let target = dir.join(renamed_name(name));
        if !original.is_file() || target.exists() {
            continue; // sumiu, ou já migrado: não sobrescreve
        }
        let bytes = fs::read(&original)?;
        let bytes_before = bytes.clone();
        let new_bytes =
            if is_text_name(name) { renamed_bytes(&bytes).unwrap_or_else(|| bytes.clone()) } else { bytes };
        let staging = dir.join(format!("{}.vanta-migrando", renamed_name(name)));
        // create_new: nunca segue nem reaproveita um arquivo/link que já estivesse nesse nome
        fs::OpenOptions::new().write(true).create_new(true).open(&staging)?.write_all(&new_bytes)?;
        if !fs::read(&staging).is_ok_and(|written| written == new_bytes)
            || target.exists()
            || fs::rename(&staging, &target).is_err()
        {
            let _ = fs::remove_file(&staging);
            return Err(not_validated(name));
        }
        if !fs::read(&target).is_ok_and(|written| written == new_bytes) {
            let _ = fs::remove_file(&target);
            return Err(not_validated(name));
        }
        if !fs::read(&original).is_ok_and(|now| now == bytes_before) {
            let _ = fs::remove_file(&target); // o original mudou durante a migração: mantém os dois lados como estavam
            return Err(not_validated(name));
        }
        fs::remove_file(&original)?;
        done.push(renamed_name(name));
    }
    Ok(done)
}

fn xml_escape(text: &str) -> String {
    text.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;").replace('"', "&quot;")
}

/// Tarefa do ISLC: ao entrar, minimizada, com privilégio máximo, também na bateria e sem limite de tempo.
pub fn islc_task_xml(exe: &str, sid: &str) -> String {
    format!(
        "<?xml version=\"1.0\" encoding=\"UTF-16\"?>\r\n\
<Task version=\"1.2\" xmlns=\"http://schemas.microsoft.com/windows/2004/02/mit/task\">\r\n\
  <Triggers><LogonTrigger><Enabled>true</Enabled><UserId>{sid}</UserId></LogonTrigger></Triggers>\r\n\
  <Principals><Principal id=\"Author\"><UserId>{sid}</UserId><LogonType>InteractiveToken</LogonType><RunLevel>HighestAvailable</RunLevel></Principal></Principals>\r\n\
  <Settings><MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy><DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries><StopIfGoingOnBatteries>false</StopIfGoingOnBatteries><ExecutionTimeLimit>PT0S</ExecutionTimeLimit><Enabled>true</Enabled></Settings>\r\n\
  <Actions Context=\"Author\"><Exec><Command>{exe}</Command><Arguments>-minimized</Arguments></Exec></Actions>\r\n\
</Task>\r\n",
        sid = xml_escape(sid),
        exe = xml_escape(exe)
    )
}

/// O que o Restaurar acrescenta ao plano elevado para iniciar com o Windows, e o que deixou de fora.
#[derive(Debug, Default, PartialEq, Eq)]
pub struct StartupPlan {
    pub tasks: Vec<PlanTask>,
    pub runs: Vec<PlanRun>,
    pub warnings: Vec<String>,
}

struct Artifact {
    name: &'static str,
    exe: String,
    args: &'static str,
}

/// O caminho exato do artefato está dentro de um destino canônico que o manifesto restaura (a pasta do programa que o
/// kit leva), e não apenas um componente de nome parecido.
pub fn manifest_covers(destinations: &[String], exe: &str) -> bool {
    destinations.iter().any(|destination| path_inside(exe, destination))
}

/// Tarefa do ISLC e entradas `Run` (BatteryHub, G HUB) só quando o CAMINHO EXATO do executável está dentro de um destino
/// do manifesto (`destinations`), o programa está instalado e o comando é validado. Nada é criado só porque o executável
/// existe no disco nem porque o nome de uma pasta se parece.
pub fn startup_plan(
    destinations: &[String],
    sid: &str,
    local_app_data: &str,
    program_files: &str,
    roots: &TaskRoots,
    exists: &dyn Fn(&Path) -> bool,
) -> StartupPlan {
    let mut plan = StartupPlan::default();
    let islc = Artifact {
        name: "ISLC",
        exe: format!(r"{program_files}\ISLC\Intelligent standby list cleaner ISLC.exe"),
        args: "",
    };
    if manifest_covers(destinations, &islc.exe) {
        if exists(Path::new(&islc.exe)) {
            let xml = islc_task_xml(&islc.exe, sid);
            match validate_task(&xml, sid, roots) {
                Ok(_) => plan.tasks.push(PlanTask {
                    label: "inicia com o Windows: ISLC (tarefa, minimizado)".into(),
                    name: islc.name.into(),
                    xml,
                    scripts: vec![],
                }),
                Err(why) => plan.warnings.push(format!("ISLC: tarefa não criada ({why})")),
            }
        } else {
            plan.warnings.push(
                "ISLC está no manifesto, mas o programa não está instalado: a tarefa de início não foi criada."
                    .into(),
            );
        }
    } else if exists(Path::new(&islc.exe)) {
        plan.warnings.push("ISLC: o executável está instalado, mas o caminho dele não consta no manifesto do kit; tarefa de início não criada.".into());
    }
    let runs = [
        Artifact {
            name: "WirelessBattery",
            exe: format!(r"{local_app_data}\Programs\BatteryHub-plus\BatteryHub.exe"),
            args: "",
        },
        Artifact {
            name: "LGHUB",
            exe: format!(r"{program_files}\LGHUB\system_tray\lghub_system_tray.exe"),
            args: " --minimized",
        },
    ];
    for artifact in runs {
        if !manifest_covers(destinations, &artifact.exe) {
            if exists(Path::new(&artifact.exe)) {
                plan.warnings.push(format!(
                    "{}: o executável está instalado, mas o caminho dele não consta no manifesto do kit; entrada de início não criada.",
                    artifact.name
                ));
            }
            continue;
        }
        if !exists(Path::new(&artifact.exe)) {
            plan.warnings.push(format!(
                "{} está no manifesto, mas não está instalado: entrada de início não criada.",
                artifact.name
            ));
            continue;
        }
        let command = format!("\"{}\"{}", artifact.exe, artifact.args);
        match validate_run_command(&command, roots) {
            Ok(()) => plan.runs.push(PlanRun {
                label: format!("inicia com o Windows: {}", artifact.name),
                name: artifact.name.into(),
                command,
            }),
            Err(why) => {
                plan.warnings.push(format!("{}: entrada de início não criada ({why})", artifact.name));
            }
        }
    }
    plan
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::restore_batch::decode_text;

    const SID: &str = "S-1-5-21-1-2-3-1001";

    fn env(name: &str) -> Option<String> {
        (name.to_uppercase() == "LOCALAPPDATA").then(|| r"C:\Users\n\AppData\Local".to_owned())
    }

    fn roots() -> TaskRoots<'static> {
        TaskRoots {
            program_files: vec![r"C:\Program Files".into(), r"C:\Program Files (x86)".into()],
            privileged: vec![r"C:\Vanta\System".into()],
            restored: vec![],
            user_programs: vec![r"C:\Users\n\AppData\Local\Programs".into()],
            powershell: r"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe".into(),
            cmd: r"C:\Windows\System32\cmd.exe".into(),
            user_profile: r"C:\Users\n".into(),
            env: &env,
        }
    }

    #[test]
    fn names_and_text_are_renamed_but_only_the_prefix_of_a_name() {
        assert_eq!(renamed_name("NathaSystem.ps1"), "VantaSystem.ps1");
        assert_eq!(renamed_name("OutroNathaSystem.txt"), "OutroNathaSystem.txt");
        assert_eq!(
            rename_text("& C:\\AutoOptimizer\\NathaSystem.ps1 # NathaSystem log"),
            "& C:\\AutoOptimizer\\VantaSystem.ps1 # VantaSystem log"
        );
    }

    #[test]
    fn the_rename_keeps_the_encoding_of_the_file() {
        assert_eq!(renamed_bytes(b"$a = 'NathaSystem'").unwrap(), b"$a = 'VantaSystem'");
        assert_eq!(
            renamed_bytes(b"\xEF\xBB\xBF$a = 'NathaSystem'").unwrap(),
            b"\xEF\xBB\xBF$a = 'VantaSystem'"
        );
        let out = renamed_bytes(&encode_utf16_bom("$a = 'NathaSystem' # ç")).unwrap();
        assert!(out.starts_with(&[0xFF, 0xFE]) && decode_text(&out) == "$a = 'VantaSystem' # ç");
        let mut be = vec![0xFE, 0xFF];
        be.extend("NathaSystem".encode_utf16().flat_map(u16::to_be_bytes));
        let out = renamed_bytes(&be).unwrap();
        let mut expected = vec![0xFE, 0xFF];
        expected.extend("VantaSystem".encode_utf16().flat_map(u16::to_be_bytes));
        assert_eq!(out, expected);
        assert_eq!(renamed_bytes(b"\xE7\xE3o NathaSystem"), None, "ANSI não é UTF-8: os bytes ficam");
        assert_eq!(renamed_bytes(&[0xFF, 0xFE, 0x41]), None, "UTF-16 truncado");
    }

    #[test]
    fn only_files_this_run_restored_are_migrated_and_the_original_stays_until_the_copy_is_valid() {
        let source = tempfile::tempdir().unwrap();
        let dest = tempfile::tempdir().unwrap();
        for (name, bytes) in [
            ("NathaSystem.ps1", &b"\xEF\xBB\xBF$log = 'NathaSystem.log'"[..]),
            ("NathaSystem.log", b"antigo"),
        ] {
            fs::write(source.path().join(name), bytes).unwrap();
            fs::write(dest.path().join(name), bytes).unwrap();
        }
        fs::write(dest.path().join("NathaSystem_pessoal.ps1"), b"meu script NathaSystem").unwrap();
        fs::write(source.path().join("NathaSystem.json"), b"{\"a\":\"NathaSystem\"}").unwrap();
        fs::write(dest.path().join("NathaSystem.json"), b"{\"a\":\"incompleto\"}").unwrap();
        fs::write(dest.path().join("LMUFFB.exe"), b"nao mexe").unwrap();
        let all = ["NathaSystem.ps1", "NathaSystem.log", "NathaSystem.json"]
            .map(|n| dest.path().join(n).to_string_lossy().into_owned());
        // o .log igual ao do kit, mas que esta execução NÃO copiou (já estava lá): não entra
        let restored = restored_nathasystem(source.path(), dest.path(), &[all[0].clone(), all[2].clone()]);
        assert_eq!(restored, ["NathaSystem.ps1"], "só o que a execução registrou como copiado");
        let restored = restored_nathasystem(source.path(), dest.path(), &all);
        assert_eq!(
            restored,
            ["NathaSystem.log", "NathaSystem.ps1"],
            "só o que a execução provadamente restaurou"
        );
        let done = migrate_nathasystem(dest.path(), &restored).unwrap();
        assert_eq!(done, ["VantaSystem.log", "VantaSystem.ps1"]);
        assert_eq!(
            fs::read(dest.path().join("VantaSystem.ps1")).unwrap(),
            b"\xEF\xBB\xBF$log = 'VantaSystem.log'",
            "BOM preservado"
        );
        assert_eq!(
            fs::read(dest.path().join("VantaSystem.log")).unwrap(),
            b"antigo",
            "o que não é texto só muda de nome"
        );
        assert!(
            !dest.path().join("NathaSystem.ps1").exists() && !dest.path().join("NathaSystem.log").exists()
        );
        for untouched in ["NathaSystem_pessoal.ps1", "NathaSystem.json", "LMUFFB.exe"] {
            assert!(dest.path().join(untouched).exists(), "{untouched}");
        }
        assert!(
            !dest.path().join("VantaSystem_pessoal.ps1").exists()
                && !dest.path().join("VantaSystem.json").exists()
        );
        assert!(
            !fs::read_dir(dest.path())
                .unwrap()
                .flatten()
                .any(|e| e.file_name().to_string_lossy().ends_with(".vanta-migrando"))
        );
    }

    #[test]
    fn an_existing_target_is_never_overwritten_and_a_non_utf8_script_keeps_its_bytes() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("NathaSystem.ps1"), b"\xE7\xE3o").unwrap(); // ANSI
        fs::write(dir.path().join("NathaSystem_depois.txt"), b"x").unwrap();
        fs::write(dir.path().join("VantaSystem_depois.txt"), b"ja existe").unwrap();
        let names = vec![
            "NathaSystem.ps1".to_owned(),
            "NathaSystem_depois.txt".to_owned(),
            "..\\NathaSystem.ps1".to_owned(),
        ];
        let done = migrate_nathasystem(dir.path(), &names).unwrap();
        assert_eq!(done, ["VantaSystem.ps1"]);
        assert_eq!(fs::read(dir.path().join("VantaSystem.ps1")).unwrap(), b"\xE7\xE3o");
        assert_eq!(
            fs::read(dir.path().join("VantaSystem_depois.txt")).unwrap(),
            b"ja existe",
            "não sobrescreve"
        );
        assert!(dir.path().join("NathaSystem_depois.txt").exists());
        assert!(migrate_nathasystem(dir.path(), &names).unwrap().is_empty(), "rodar de novo não muda nada");
    }

    #[test]
    fn the_islc_task_runs_minimized_at_logon_with_highest_privileges_and_escapes_xml() {
        let xml = islc_task_xml(r"C:\Program Files\ISLC\Intelligent standby list cleaner ISLC.exe", SID);
        for expected in [
            "<LogonTrigger>",
            "<UserId>S-1-5-21-1-2-3-1001</UserId>",
            "<RunLevel>HighestAvailable</RunLevel>",
            "<LogonType>InteractiveToken</LogonType>",
            "<DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>",
            "<StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>",
            "<ExecutionTimeLimit>PT0S</ExecutionTimeLimit>",
            "<Arguments>-minimized</Arguments>",
            r"<Command>C:\Program Files\ISLC\Intelligent standby list cleaner ISLC.exe</Command>",
        ] {
            assert!(xml.contains(expected), "{expected}");
        }
        assert!(islc_task_xml("C:\\a&b<c>.exe", "S").contains("a&amp;b&lt;c&gt;.exe"));
    }

    #[test]
    fn startup_entries_need_the_exact_artifact_path_inside_a_manifest_destination() {
        let all = |_: &Path| true;
        let destinations = vec![
            r"C:\Program Files\ISLC".to_owned(),
            r"C:\Users\n\AppData\Local\Programs\BatteryHub-plus".to_owned(),
            r"C:\Program Files\LGHUB".to_owned(),
        ];
        let plan = startup_plan(
            &destinations,
            SID,
            r"C:\Users\n\AppData\Local",
            r"C:\Program Files",
            &roots(),
            &all,
        );
        assert_eq!(plan.tasks.len(), 1);
        assert!(plan.tasks[0].name == "ISLC" && plan.tasks[0].xml.contains("-minimized"));
        assert_eq!(
            plan.runs.iter().map(|r| r.name.as_str()).collect::<Vec<_>>(),
            ["WirelessBattery", "LGHUB"]
        );
        assert_eq!(
            plan.runs[1].command,
            "\"C:\\Program Files\\LGHUB\\system_tray\\lghub_system_tray.exe\" --minimized"
        );
        assert!(plan.warnings.is_empty(), "{:?}", plan.warnings);
        // uma pasta com nome parecido, em outro lugar, não vale (o caminho exato é que conta)
        let lookalike = vec![
            r"C:\Users\Old\AppData\Roaming\ISLC".to_owned(),
            r"C:\Users\Old\AppData\Local\LGHUB".to_owned(),
            r"C:\Program Files\ISLCx".to_owned(),
        ];
        let none =
            startup_plan(&lookalike, SID, r"C:\Users\n\AppData\Local", r"C:\Program Files", &roots(), &all);
        assert!(none.tasks.is_empty() && none.runs.is_empty());
        assert_eq!(
            none.warnings.len(),
            3,
            "o instalado sem prova no manifesto vira aviso: {:?}",
            none.warnings
        );
        // o manifesto cobre, mas o programa não está instalado: aviso, nada criado
        let missing = startup_plan(
            &destinations,
            SID,
            r"C:\Users\n\AppData\Local",
            r"C:\Program Files",
            &roots(),
            &|_: &Path| false,
        );
        assert!(missing.tasks.is_empty() && missing.runs.is_empty());
        assert_eq!(missing.warnings.len(), 3);
        assert!(manifest_covers(&destinations, r"c:\program files\islc\x.exe"));
        assert!(!manifest_covers(&destinations, r"C:\Program Files\OutroISLC\x.exe"));
    }

    #[test]
    fn a_startup_command_outside_a_safe_place_is_left_out_with_a_warning() {
        let destinations = vec![r"D:\Programas\ISLC".to_owned()];
        let plan = startup_plan(&destinations, SID, "L", r"D:\Programas", &roots(), &|_: &Path| true);
        assert!(plan.tasks.is_empty());
        assert!(plan.warnings.iter().any(|w| w.contains("ISLC: tarefa não criada")), "{:?}", plan.warnings);
    }
}

#[cfg(test)]
mod staging_tests {
    use super::*;

    #[test]
    fn a_staging_file_that_already_exists_is_never_reused_and_the_original_stays() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("NathaSystem.ps1"), b"a").unwrap();
        fs::write(dir.path().join("VantaSystem.ps1.vanta-migrando"), b"intruso").unwrap();
        let error = migrate_nathasystem(dir.path(), &["NathaSystem.ps1".to_owned()]);
        assert!(error.is_err(), "create_new recusa o nome já ocupado");
        assert_eq!(fs::read(dir.path().join("NathaSystem.ps1")).unwrap(), b"a");
        assert_eq!(fs::read(dir.path().join("VantaSystem.ps1.vanta-migrando")).unwrap(), b"intruso");
        assert!(!dir.path().join("VantaSystem.ps1").exists());
    }
}
