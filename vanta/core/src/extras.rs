//! O que o Restaurar faz além de copiar pastas (registro, tarefas agendadas, início com o Windows) só vale para
//! artefatos que o MANIFESTO CONFERIDO do kit lista. Uma pasta do kit com um `.reg` ou um `.xml` que o manifesto não
//! lista (e que a guarda, portanto, nunca olhou) não é executada nem importada: vira aviso.

use crate::manifest::{KitItem, Manifest};

/// Registro (`config/registro/<arquivo>.reg`) e tarefa agendada (`estado/tarefas/<arquivo>.xml`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ExtraKind {
    Registry,
    Task,
}

const REGISTRY_DIR: &str = "config/registro/";
const TASK_DIR: &str = "estado/tarefas/";

impl KitItem {
    /// O item é um `.reg` ou uma tarefa `.xml` direto nas pastas de extras do kit (nada de subpasta, `..` ou pasta).
    /// Esses itens não são cópia de configuração: o Restaurar os trata como extras.
    pub fn extra_kind(&self) -> Option<ExtraKind> {
        if self.is_folder() {
            return None;
        }
        let path = self.kit_path.replace('\\', "/");
        let lower = path.to_lowercase();
        let single = |prefix: &str, extension: &str| {
            lower.strip_prefix(prefix).is_some_and(|rest| {
                !rest.is_empty()
                    && !rest.contains('/')
                    && rest.len() > extension.len()
                    && rest.ends_with(extension)
            }) && !lower.split('/').any(|part| part == ".." || part == ".")
        };
        if single(REGISTRY_DIR, ".reg") {
            Some(ExtraKind::Registry)
        } else if single(TASK_DIR, ".xml") {
            Some(ExtraKind::Task)
        } else {
            None
        }
    }
}

/// Os extras que o manifesto aprova, na ordem do manifesto: (caminho no kit, nome do arquivo sem extensão).
pub fn approved(manifest: &Manifest, kind: ExtraKind) -> Vec<(String, String)> {
    manifest
        .items
        .iter()
        .filter(|item| item.extra_kind() == Some(kind))
        .filter_map(|item| {
            let path = item.kit_path.replace('\\', "/");
            let file = path.rsplit('/').next()?.to_owned();
            let stem = file.rsplit_once('.').map_or(file.clone(), |(stem, _)| stem.to_owned());
            Some((path, stem))
        })
        .collect()
}

/// O manifesto lista algo restaurado dentro de uma pasta chamada `component` (sem diferenciar maiúsculas), em
/// `origem` ou `destino`. É a prova de que o kit leva aquele programa: sem ela o Vanta não cria tarefa nem entrada
/// de início para ele só porque o executável existe no disco.
pub fn manifest_carries(manifest: &Manifest, component: &str) -> bool {
    manifest.items.iter().any(|item| {
        [&item.restore_path, &item.kit_path]
            .iter()
            .any(|path| path.split(['\\', '/']).any(|part| part.eq_ignore_ascii_case(component)))
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn item(kind: &str, kit_path: &str, restore_path: &str) -> KitItem {
        KitItem {
            kind: kind.into(),
            name: "n".into(),
            kit_path: kit_path.into(),
            restore_path: restore_path.into(),
            robocopy: None,
            include: vec![],
            exclude: vec![],
        }
    }

    fn manifest(items: Vec<KitItem>) -> Manifest {
        Manifest { collected_at: None, items }
    }

    #[test]
    fn only_a_reg_or_xml_directly_in_the_extras_folders_is_an_extra() {
        assert_eq!(item("arquivo", "config/registro/obs.reg", "x").extra_kind(), Some(ExtraKind::Registry));
        assert_eq!(item("arquivo", r"config\registro\OBS.REG", "x").extra_kind(), Some(ExtraKind::Registry));
        assert_eq!(item("tarefa", "estado/tarefas/Auto.xml", "x").extra_kind(), Some(ExtraKind::Task));
        for not in [
            "config/registro/sub/x.reg",
            "config/registro/x.txt",
            "config/registro/.reg",
            "config/registro/",
            "estado/tarefas/x.reg",
            "config/obs/x.reg",
            "config/registro/../obs/x.reg",
            "../config/registro/x.reg",
        ] {
            assert_eq!(item("arquivo", not, "x").extra_kind(), None, "{not}");
        }
        assert_eq!(item("pasta", "config/registro/x.reg", "x").extra_kind(), None, "uma pasta nunca é extra");
    }

    #[test]
    fn the_approved_lists_come_only_from_the_manifest_and_keep_its_order() {
        let m = manifest(vec![
            item("arquivo", "estado/tarefas/Z.xml", "x"),
            item("arquivo", "config/registro/b.reg", "x"),
            item("pasta", "config/obs", r"C:\Users\Old\obs"),
            item("arquivo", "config/registro/a.reg", "x"),
        ]);
        assert_eq!(
            approved(&m, ExtraKind::Registry),
            [
                ("config/registro/b.reg".to_owned(), "b".to_owned()),
                ("config/registro/a.reg".to_owned(), "a".to_owned())
            ]
        );
        assert_eq!(approved(&m, ExtraKind::Task), [("estado/tarefas/Z.xml".to_owned(), "Z".to_owned())]);
        assert!(
            approved(&manifest(vec![]), ExtraKind::Registry).is_empty(),
            "sem manifesto, nada é aprovado"
        );
    }

    #[test]
    fn a_program_is_carried_only_when_the_manifest_restores_something_inside_its_folder() {
        let m = manifest(vec![
            item("pasta", "config/islc", r"C:\Program Files\ISLC"),
            item("pasta", "config/obs", r"C:\Users\Old\AppData\Roaming\obs-studio"),
        ]);
        assert!(manifest_carries(&m, "islc"));
        assert!(!manifest_carries(&m, "LGHUB"));
        assert!(!manifest_carries(&m, "ISL"), "componente inteiro, não pedaço");
    }
}
