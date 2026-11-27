//! Disco em memória para os testes: caminhos do Windows sem diferenciar maiúsculas.

use std::cell::RefCell;
use std::collections::BTreeMap;
use std::io;

use crate::fs::{DirEntry, FileWriter, Fs};
use crate::path::{normalize, parent};

#[derive(Clone, Debug, Default)]
pub struct Node {
    pub content: String,
    pub readonly: bool,
    /// Preso por outro processo (G HUB, por exemplo): não aceita escrita.
    pub locked: bool,
    pub link: bool,
}

#[derive(Default)]
pub struct MemFs {
    files: RefCell<BTreeMap<String, (String, Node)>>,
    dirs: RefCell<BTreeMap<String, String>>,
}

fn key(path: &str) -> String {
    normalize(path).trim_end_matches('\\').to_lowercase()
}

impl MemFs {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn add_dir(&self, path: &str) {
        let mut at = normalize(path).trim_end_matches('\\').to_owned();
        loop {
            self.dirs.borrow_mut().insert(key(&at), at.clone());
            match parent(&at) {
                Some(p) => at = p,
                None => break,
            }
        }
    }

    pub fn add_file(&self, path: &str, content: &str) {
        if let Some(p) = parent(path) {
            self.add_dir(&p);
        }
        self.files
            .borrow_mut()
            .insert(key(path), (normalize(path), Node { content: content.to_owned(), ..Node::default() }));
    }

    pub fn add_link_dir(&self, path: &str) {
        self.add_dir(path);
        self.files.borrow_mut().insert(key(path), (normalize(path), Node { link: true, ..Node::default() }));
    }

    pub fn set_readonly(&self, path: &str, readonly: bool) {
        self.files.borrow_mut().get_mut(&key(path)).unwrap().1.readonly = readonly;
    }

    pub fn set_locked(&self, path: &str) {
        self.files.borrow_mut().get_mut(&key(path)).unwrap().1.locked = true;
    }

    pub fn content(&self, path: &str) -> Option<String> {
        self.files.borrow().get(&key(path)).map(|(_, n)| n.content.clone())
    }

    pub fn all_files(&self) -> Vec<String> {
        self.files.borrow().values().map(|(p, _)| p.clone()).collect()
    }
}

impl Fs for MemFs {
    fn exists(&self, path: &str) -> bool {
        let k = key(path);
        self.files.borrow().contains_key(&k) || self.dirs.borrow().contains_key(&k)
    }

    fn is_dir(&self, path: &str) -> bool {
        self.dirs.borrow().contains_key(&key(path))
    }

    fn read_bytes(&self, path: &str) -> io::Result<Vec<u8>> {
        self.read_to_string(path).map(String::into_bytes)
    }

    fn read_to_string(&self, path: &str) -> io::Result<String> {
        self.files
            .borrow()
            .get(&key(path))
            .map(|(_, n)| n.content.clone())
            .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "arquivo não encontrado"))
    }

    fn read_dir(&self, path: &str) -> io::Result<Vec<DirEntry>> {
        let dir = key(path);
        if !self.dirs.borrow().contains_key(&dir) {
            return Err(io::Error::new(io::ErrorKind::NotFound, "pasta não encontrada"));
        }
        let mut out = Vec::new();
        for (display, node) in self.files.borrow().values() {
            if parent(display).map(|p| key(&p)) == Some(dir.clone()) && !node.link {
                out.push(DirEntry { name: crate::path::file_name(display), is_dir: false, is_link: false });
            }
        }
        for (k, display) in self.dirs.borrow().iter() {
            if parent(display).map(|p| key(&p)) == Some(dir.clone()) && k != &dir {
                let link = self.files.borrow().get(k).is_some_and(|(_, n)| n.link);
                out.push(DirEntry { name: crate::path::file_name(display), is_dir: true, is_link: link });
            }
        }
        out.sort_by(|a, b| a.name.cmp(&b.name));
        Ok(out)
    }
}

impl FileWriter for MemFs {
    fn create_dir_all(&self, path: &str) -> io::Result<()> {
        self.add_dir(path);
        Ok(())
    }

    fn copy_atomic(&self, source: &str, destination: &str) -> io::Result<()> {
        let content = self.read_to_string(source)?;
        if let Some((_, node)) = self.files.borrow().get(&key(destination)) {
            if node.locked {
                return Err(io::Error::new(
                    io::ErrorKind::PermissionDenied,
                    "O arquivo está sendo usado por outro processo.",
                ));
            }
            if node.readonly {
                return Err(io::Error::new(io::ErrorKind::PermissionDenied, "Acesso negado."));
            }
        }
        self.add_file(destination, &content);
        Ok(())
    }

    fn write_atomic(&self, path: &str, contents: &str) -> io::Result<()> {
        if let Some((_, node)) = self.files.borrow().get(&key(path))
            && (node.locked || node.readonly)
        {
            return Err(io::Error::new(io::ErrorKind::PermissionDenied, "Acesso negado."));
        }
        self.add_file(path, contents);
        Ok(())
    }

    fn clear_readonly(&self, path: &str) -> io::Result<()> {
        if let Some((_, node)) = self.files.borrow_mut().get_mut(&key(path)) {
            node.readonly = false;
        }
        Ok(())
    }
}
