//! Caminhos do Windows como texto: puros, sem tocar no disco (portam `PackagePathResolver` e `UserPathMapper`).

use std::fmt;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PathError {
    /// O caminho do item precisa ser relativo ao pacote.
    NotRelative,
    /// O caminho do item sai da pasta do pacote.
    EscapesRoot,
}

impl fmt::Display for PathError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::NotRelative => f.write_str("O caminho do item precisa ser relativo ao pacote."),
            Self::EscapesRoot => f.write_str("O caminho do item sai da pasta do pacote."),
        }
    }
}

impl std::error::Error for PathError {}

/// Troca `/` por `\`.
pub fn normalize(path: &str) -> String {
    path.replace('/', "\\")
}

/// Junta dois pedaços com uma só barra entre eles.
pub fn join(base: &str, rest: &str) -> String {
    let base = normalize(base);
    let rest = normalize(rest);
    format!("{}\\{}", base.trim_end_matches('\\'), rest.trim_start_matches('\\'))
}

/// Pasta pai (`None` na raiz ou sem barra).
pub fn parent(path: &str) -> Option<String> {
    let path = normalize(path);
    let trimmed = path.trim_end_matches('\\');
    trimmed.rfind('\\').map(|i| trimmed[..i].to_owned()).filter(|p| !p.is_empty())
}

/// Último componente.
pub fn file_name(path: &str) -> String {
    let path = normalize(path);
    path.trim_end_matches('\\').rsplit('\\').next().unwrap_or("").to_owned()
}

fn is_rooted(path: &str) -> bool {
    let bytes = path.as_bytes();
    path.starts_with('\\')
        || path.starts_with('/')
        || (bytes.len() >= 2 && bytes[1] == b':' && bytes[0].is_ascii_alphabetic())
}

/// Resolve `relative` dentro de `root`, recusando caminho absoluto e `..` que escape da raiz.
pub fn resolve_inside_root(root: &str, relative: &str) -> Result<String, PathError> {
    if is_rooted(relative) {
        return Err(PathError::NotRelative);
    }
    let mut parts: Vec<&str> = Vec::new();
    for part in relative.split(['\\', '/']) {
        match part {
            "" | "." => {}
            ".." => {
                if parts.pop().is_none() {
                    return Err(PathError::EscapesRoot);
                }
            }
            other => parts.push(other),
        }
    }
    if parts.is_empty() {
        return Err(PathError::EscapesRoot); // a própria raiz não é um item do pacote
    }
    Ok(join(root.trim_end_matches(['\\', '/']), &parts.join("\\")))
}

/// Troca o perfil do PC antigo pelo do atual. Outro usuário de prefixo parecido (`Nathan2`) não é trocado.
pub fn remap_user_path(path: &str, old_profile: &str, current_profile: &str) -> String {
    let path = normalize(path);
    let source = normalize(old_profile).trim_end_matches('\\').to_owned();
    let destination = normalize(current_profile).trim_end_matches('\\').to_owned();
    if source.is_empty() || path.len() < source.len() || !path.is_char_boundary(source.len()) {
        return path;
    }
    if !path[..source.len()].eq_ignore_ascii_case(&source) {
        return path;
    }
    match path[source.len()..].chars().next() {
        None | Some('\\') => format!("{destination}{}", &path[source.len()..]),
        Some(_) => path,
    }
}

/// `path` começa com `prefix` como pasta (sem diferenciar maiúsculas).
pub fn starts_with_dir(path: &str, prefix: &str) -> bool {
    let path = normalize(path);
    let prefix = normalize(prefix);
    let prefix = prefix.trim_end_matches('\\');
    path.len() > prefix.len()
        && path.is_char_boundary(prefix.len())
        && path[..prefix.len()].eq_ignore_ascii_case(prefix)
        && path.as_bytes()[prefix.len()] == b'\\'
}

#[cfg(test)]
mod tests {
    use super::*;

    // UserPathMapperTests.RemapsOldProfileDirectoryToCurrentProfile
    #[test]
    fn remaps_old_profile_directory_to_current_profile() {
        let result =
            remap_user_path(r"C:\Users\Old\AppData\Roaming\obs-studio", r"C:\Users\Old", r"C:\Users\New");
        assert_eq!(result, r"C:\Users\New\AppData\Roaming\obs-studio");
    }

    // UserPathMapperTests.DoesNotRemapAnotherUsersSimilarPrefix
    #[test]
    fn does_not_remap_another_users_similar_prefix() {
        let input = r"C:\Users\Nathan2\Documents\file.txt";
        assert_eq!(remap_user_path(input, r"C:\Users\Nathan", r"C:\Users\New"), input);
    }

    #[test]
    fn remap_accepts_forward_slashes_and_the_profile_itself() {
        assert_eq!(
            remap_user_path("C:/Users/Old/a.txt", r"C:\Users\Old\", r"C:\Users\New"),
            r"C:\Users\New\a.txt"
        );
        assert_eq!(remap_user_path(r"c:\users\old", r"C:\Users\Old", r"C:\Users\New"), r"C:\Users\New");
    }

    // PackagePathResolverTests.ResolvesPackageRelativeFile
    #[test]
    fn resolves_package_relative_file() {
        let file = resolve_inside_root(r"K:\MeuPlaybook\pacote", r"config\obs\profile.json").unwrap();
        assert_eq!(file, r"K:\MeuPlaybook\pacote\config\obs\profile.json");
        assert_eq!(resolve_inside_root(r"K:\pacote\", "config/a.txt").unwrap(), r"K:\pacote\config\a.txt");
    }

    // PackagePathResolverTests.RejectsPathOutsidePackage (..\outside.txt)
    #[test]
    fn rejects_path_outside_package_with_dotdot() {
        assert_eq!(resolve_inside_root(r"K:\pacote", r"..\outside.txt"), Err(PathError::EscapesRoot));
        assert_eq!(resolve_inside_root(r"K:\pacote", r"config\..\..\x"), Err(PathError::EscapesRoot));
    }

    // PackagePathResolverTests.RejectsPathOutsidePackage (C:\outside.txt)
    #[test]
    fn rejects_path_outside_package_when_absolute() {
        assert_eq!(resolve_inside_root(r"K:\pacote", r"C:\outside.txt"), Err(PathError::NotRelative));
        assert_eq!(resolve_inside_root(r"K:\pacote", r"\outside.txt"), Err(PathError::NotRelative));
    }

    #[test]
    fn a_dotdot_that_stays_inside_is_fine() {
        assert_eq!(
            resolve_inside_root(r"K:\pacote", r"config\x\..\a.txt").unwrap(),
            r"K:\pacote\config\a.txt"
        );
    }

    #[test]
    fn helpers_split_and_join() {
        assert_eq!(parent(r"C:\a\b\c.txt").as_deref(), Some(r"C:\a\b"));
        assert_eq!(file_name("C:/a/b/c.txt"), "c.txt");
        assert!(starts_with_dir(r"C:\Program Files\EqualizerAPO\config", r"c:\program files"));
        assert!(!starts_with_dir(r"C:\Program Files (x86)\x", r"C:\Program Files"));
    }
}
