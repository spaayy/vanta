//! I/O do núcleo, atrás de traits. O núcleo só chama estas funções; quem liga o disco real é o Vanta Tools.
//! [`StdFs`] só LÊ. Escrever (copiar) fica com quem implementar [`FileWriter`].

use std::io;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DirEntry {
    pub name: String,
    pub is_dir: bool,
    /// Atalho/junção/link simbólico: o núcleo nunca os segue.
    pub is_link: bool,
}

/// Leitura do disco.
pub trait Fs {
    fn exists(&self, path: &str) -> bool;
    fn is_dir(&self, path: &str) -> bool;
    fn read_bytes(&self, path: &str) -> io::Result<Vec<u8>>;
    fn read_to_string(&self, path: &str) -> io::Result<String>;
    fn read_dir(&self, path: &str) -> io::Result<Vec<DirEntry>>;
}

/// Escrita no disco, só para a restauração de configurações.
pub trait FileWriter {
    fn create_dir_all(&self, path: &str) -> io::Result<()>;
    /// Copia `source` para `destination` sem deixar arquivo parcial: ou o destino fica com o conteúdo novo,
    /// ou fica como estava. Falha com [`io::ErrorKind::PermissionDenied`] se o destino é somente leitura ou está preso.
    fn copy_atomic(&self, source: &str, destination: &str) -> io::Result<()>;
    /// Grava contents em path de forma atômica (o arquivo antigo fica intacto se a gravação falhar).
    fn write_atomic(&self, path: &str, contents: &str) -> io::Result<()>;
    /// Tira o atributo somente leitura de um arquivo que já existe (não faz nada se ele não existe).
    fn clear_readonly(&self, path: &str) -> io::Result<()>;
}

/// Leitura com a biblioteca padrão (para a varredura do kit real).
pub struct StdFs;

impl Fs for StdFs {
    fn exists(&self, path: &str) -> bool {
        std::fs::symlink_metadata(path).is_ok()
    }

    fn is_dir(&self, path: &str) -> bool {
        std::fs::metadata(path).map(|m| m.is_dir()).unwrap_or(false)
    }

    fn read_bytes(&self, path: &str) -> io::Result<Vec<u8>> {
        std::fs::read(path)
    }

    fn read_to_string(&self, path: &str) -> io::Result<String> {
        let bytes = self.read_bytes(path)?;
        Ok(String::from_utf8_lossy(&bytes).trim_start_matches('\u{feff}').to_owned())
    }

    fn read_dir(&self, path: &str) -> io::Result<Vec<DirEntry>> {
        let mut entries = Vec::new();
        for entry in std::fs::read_dir(path)? {
            let entry = entry?;
            let kind = entry.file_type()?;
            entries.push(DirEntry {
                name: entry.file_name().to_string_lossy().into_owned(),
                is_dir: kind.is_dir(),
                is_link: kind.is_symlink() || is_reparse(&entry),
            });
        }
        entries.sort_by(|a, b| a.name.cmp(&b.name));
        Ok(entries)
    }
}

#[cfg(windows)]
fn is_reparse(entry: &std::fs::DirEntry) -> bool {
    use std::os::windows::fs::MetadataExt;
    entry.metadata().map(|m| m.file_attributes() & 0x400 != 0).unwrap_or(false)
}

#[cfg(not(windows))]
fn is_reparse(_entry: &std::fs::DirEntry) -> bool {
    false
}
