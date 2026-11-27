//! Cópia que não deixa arquivo parcial: grava num temporário ao lado e troca. Se algo falha (arquivo preso,
//! sem permissão), a cópia anterior fica exatamente como estava e o temporário some.

use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use vanta_core::fs::FileWriter;

pub struct StdWriter;

fn temp_beside(destination: &Path) -> PathBuf {
    let nanos = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_nanos()).unwrap_or(0);
    let name = format!(".vanta-{}-{nanos}.tmp", std::process::id());
    destination.parent().map_or_else(|| PathBuf::from(&name), |p| p.join(&name))
}

fn replace(temp: &Path, destination: &Path) -> io::Result<()> {
    // Destino somente leitura fazia a troca falhar com "acesso negado".
    if let Ok(meta) = fs::metadata(destination) {
        let mut permissions = meta.permissions();
        if permissions.readonly() {
            #[allow(clippy::permissions_set_readonly_false)]
            permissions.set_readonly(false);
            fs::set_permissions(destination, permissions)?;
        }
    }
    fs::rename(temp, destination)
}

impl FileWriter for StdWriter {
    fn create_dir_all(&self, path: &str) -> io::Result<()> {
        fs::create_dir_all(path)
    }

    fn copy_atomic(&self, source: &str, destination: &str) -> io::Result<()> {
        let destination = Path::new(destination);
        let temp = temp_beside(destination);
        let result = (|| {
            fs::copy(source, &temp)?;
            if let Ok(modified) = fs::metadata(source).and_then(|m| m.modified()) {
                fs::OpenOptions::new().write(true).open(&temp)?.set_modified(modified)?;
            }
            replace(&temp, destination)
        })();
        if result.is_err() {
            let _ = fs::remove_file(&temp);
        }
        result
    }

    fn write_atomic(&self, path: &str, contents: &str) -> io::Result<()> {
        let destination = Path::new(path);
        let temp = temp_beside(destination);
        let result = fs::write(&temp, contents).and_then(|()| replace(&temp, destination));
        if result.is_err() {
            let _ = fs::remove_file(&temp);
        }
        result
    }

    fn clear_readonly(&self, path: &str) -> io::Result<()> {
        match fs::metadata(path) {
            Ok(meta) => {
                let mut permissions = meta.permissions();
                if permissions.readonly() {
                    #[allow(clippy::permissions_set_readonly_false)]
                    permissions.set_readonly(false);
                    fs::set_permissions(path, permissions)?;
                }
                Ok(())
            }
            Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
            Err(error) => Err(error),
        }
    }
}

#[cfg(test)]
mod tests {
    use std::os::windows::fs::OpenOptionsExt;

    use super::*;

    fn p(dir: &tempfile::TempDir, name: &str) -> String {
        dir.path().join(name).to_string_lossy().into_owned()
    }

    fn tmp_files(dir: &tempfile::TempDir) -> usize {
        fs::read_dir(dir.path())
            .unwrap()
            .filter(|e| e.as_ref().unwrap().file_name().to_string_lossy().ends_with(".tmp"))
            .count()
    }

    #[test]
    fn copies_over_an_existing_file_and_keeps_the_modified_time() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(p(&dir, "src.txt"), "novo").unwrap();
        fs::write(p(&dir, "dst.txt"), "anterior").unwrap();
        StdWriter.copy_atomic(&p(&dir, "src.txt"), &p(&dir, "dst.txt")).unwrap();
        assert_eq!(fs::read_to_string(p(&dir, "dst.txt")).unwrap(), "novo");
        let (a, b) = (fs::metadata(p(&dir, "src.txt")).unwrap(), fs::metadata(p(&dir, "dst.txt")).unwrap());
        assert_eq!(a.modified().unwrap(), b.modified().unwrap());
        assert_eq!(tmp_files(&dir), 0);
    }

    #[test]
    fn overwrites_a_read_only_destination() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(p(&dir, "src.txt"), "novo").unwrap();
        fs::write(p(&dir, "dst.txt"), "velho").unwrap();
        let mut permissions = fs::metadata(p(&dir, "dst.txt")).unwrap().permissions();
        permissions.set_readonly(true);
        fs::set_permissions(p(&dir, "dst.txt"), permissions).unwrap();
        StdWriter.copy_atomic(&p(&dir, "src.txt"), &p(&dir, "dst.txt")).unwrap();
        assert_eq!(fs::read_to_string(p(&dir, "dst.txt")).unwrap(), "novo");
    }

    #[test]
    fn a_locked_destination_keeps_the_previous_copy_and_leaves_no_temp_file() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(p(&dir, "src.txt"), "novo").unwrap();
        fs::write(p(&dir, "dst.txt"), "preso").unwrap();
        let _lock = fs::OpenOptions::new().read(true).share_mode(0).open(p(&dir, "dst.txt")).unwrap();
        assert!(StdWriter.copy_atomic(&p(&dir, "src.txt"), &p(&dir, "dst.txt")).is_err());
        drop(_lock);
        assert_eq!(fs::read_to_string(p(&dir, "dst.txt")).unwrap(), "preso");
        assert_eq!(tmp_files(&dir), 0);
    }

    #[test]
    fn a_missing_source_fails_without_touching_the_destination() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(p(&dir, "dst.txt"), "anterior").unwrap();
        assert!(StdWriter.copy_atomic(&p(&dir, "nada.txt"), &p(&dir, "dst.txt")).is_err());
        assert_eq!(fs::read_to_string(p(&dir, "dst.txt")).unwrap(), "anterior");
        assert_eq!(tmp_files(&dir), 0);
    }

    #[test]
    fn write_atomic_replaces_and_create_dir_all_and_clear_readonly_work() {
        let dir = tempfile::tempdir().unwrap();
        let nested = p(&dir, "a\\b\\c");
        StdWriter.create_dir_all(&nested).unwrap();
        let file = format!("{nested}\\cfg.txt");
        StdWriter.write_atomic(&file, "um").unwrap();
        StdWriter.write_atomic(&file, "dois").unwrap();
        assert_eq!(fs::read_to_string(&file).unwrap(), "dois");
        StdWriter.clear_readonly(&p(&dir, "nao-existe")).unwrap();
        assert_eq!(tmp_files(&dir), 0);
    }
}
