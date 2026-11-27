//! File helpers the services share: JSON documents read and replaced whole,
//! and telling a link from the file or directory it stands in for.

use std::fs;
use std::io::ErrorKind;
use std::os::windows::fs::MetadataExt;
use std::path::Path;

use anyhow::{Context, Result};
use serde::Serialize;
use serde::de::DeserializeOwned;
use windows::Win32::Storage::FileSystem::FILE_ATTRIBUTE_REPARSE_POINT;

/// A JSON document, or `None` when there is no file. A leading byte order
/// mark is accepted, as Windows PowerShell writes one.
pub fn read_json<T: DeserializeOwned>(path: &Path) -> Result<Option<T>> {
    let text = match fs::read_to_string(path) {
        Ok(text) => text,
        Err(error) if error.kind() == ErrorKind::NotFound => return Ok(None),
        Err(error) => return Err(error).with_context(|| format!("read {}", path.display())),
    };
    serde_json::from_str(text.trim_start_matches('\u{feff}'))
        .map(Some)
        .with_context(|| format!("parse {}", path.display()))
}

/// Writes `value` beside `path` and renames it into place, so a reader (this
/// app in another window, or Atlas's scripts) never finds half a document. The
/// temporary file is removed if anything fails.
pub fn write_json_atomically(path: &Path, value: &impl Serialize) -> Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).with_context(|| format!("create {}", parent.display()))?;
    }
    let mut name = path.file_name().context("a file name")?.to_os_string();
    name.push(format!(".{}.tmp", std::process::id()));
    let temp = path.with_file_name(name);
    let written = serde_json::to_vec_pretty(value)
        .map_err(anyhow::Error::from)
        .and_then(|bytes| fs::write(&temp, bytes).with_context(|| format!("write {}", temp.display())))
        .and_then(|()| fs::rename(&temp, path).with_context(|| format!("write {}", path.display())));
    if written.is_err() {
        let _ = fs::remove_file(&temp);
    }
    written
}

/// Creates the new directory `path` with the security descriptor `sddl` already
/// on it (one `CreateDirectory` call, so there is no moment in which it is
/// reachable by anyone else), and fails if it already exists.
pub fn create_protected_dir(path: &Path, sddl: &str) -> Result<()> {
    use windows::Win32::Foundation::{HLOCAL, LocalFree};
    use windows::Win32::Security::Authorization::{
        ConvertStringSecurityDescriptorToSecurityDescriptorW, SDDL_REVISION_1,
    };
    use windows::Win32::Security::{PSECURITY_DESCRIPTOR, SECURITY_ATTRIBUTES};
    use windows::Win32::Storage::FileSystem::CreateDirectoryW;
    use windows::core::PCWSTR;

    let wide = |text: &std::ffi::OsStr| -> Vec<u16> {
        use std::os::windows::ffi::OsStrExt;
        text.encode_wide().chain(std::iter::once(0)).collect()
    };
    let sddl_wide = wide(std::ffi::OsStr::new(sddl));
    let path_wide = wide(path.as_os_str());
    let mut descriptor = PSECURITY_DESCRIPTOR::default();
    // SAFETY: both buffers are NUL-terminated and outlive the calls; the
    // descriptor Windows allocates is freed with LocalFree once the directory exists.
    unsafe {
        ConvertStringSecurityDescriptorToSecurityDescriptorW(
            PCWSTR(sddl_wide.as_ptr()),
            SDDL_REVISION_1,
            &mut descriptor,
            None,
        )
        .context("read the security descriptor")?;
        let attributes = SECURITY_ATTRIBUTES {
            nLength: std::mem::size_of::<SECURITY_ATTRIBUTES>() as u32,
            lpSecurityDescriptor: descriptor.0,
            bInheritHandle: false.into(),
        };
        let created = CreateDirectoryW(PCWSTR(path_wide.as_ptr()), Some(&attributes));
        let _ = LocalFree(Some(HLOCAL(descriptor.0)));
        created.with_context(|| format!("create {}", path.display()))
    }
}

/// Whether an SDDL string (owner and DACL) describes exactly what
/// [`create_protected_dir`] makes for a Vanta stage: owned by Administrators or
/// SYSTEM, the DACL protected from inheritance, and only SYSTEM and
/// Administrators with full control over the folder and what is inside it.
pub fn sddl_is_vanta_stage(sddl: &str) -> bool {
    let Some(owner_at) = sddl.find("O:") else { return false };
    let Some(dacl_at) = sddl.find("D:") else { return false };
    let owner_part = &sddl[owner_at + 2..];
    let owner_end = ["G:", "D:"].iter().filter_map(|mark| owner_part.find(mark)).min().unwrap_or(owner_part.len());
    if !matches!(&owner_part[..owner_end], "BA" | "SY" | "S-1-5-32-544" | "S-1-5-18") {
        return false;
    }
    let dacl = &sddl[dacl_at + 2..];
    let flags_end = dacl.find('(').unwrap_or(dacl.len());
    if !dacl[..flags_end].contains('P') {
        return false;
    }
    let mut aces: Vec<&str> = dacl[flags_end..].split(['(', ')']).filter(|ace| !ace.is_empty()).collect();
    aces.sort_unstable();
    aces == ["A;OICI;FA;;;BA", "A;OICI;FA;;;SY"]
}

/// Whether the directory at `path` really is a protected Vanta stage: its owner
/// and its DACL, read from the file system, pass [`sddl_is_vanta_stage`]. A
/// directory a standard user made (or any one that cannot be read) is not.
pub fn is_protected_vanta_dir(path: &Path) -> bool {
    use windows::Win32::Foundation::{HLOCAL, LocalFree};
    use windows::Win32::Security::Authorization::{
        ConvertSecurityDescriptorToStringSecurityDescriptorW, GetNamedSecurityInfoW, SDDL_REVISION_1, SE_FILE_OBJECT,
    };
    use windows::Win32::Security::{DACL_SECURITY_INFORMATION, OWNER_SECURITY_INFORMATION, PSECURITY_DESCRIPTOR};
    use windows::core::{PCWSTR, PWSTR};

    use std::os::windows::ffi::OsStrExt;
    let wide: Vec<u16> = path.as_os_str().encode_wide().chain(std::iter::once(0)).collect();
    let mut descriptor = PSECURITY_DESCRIPTOR::default();
    // SAFETY: `wide` is NUL-terminated; the descriptor and the string Windows allocates are freed with LocalFree.
    unsafe {
        let status = GetNamedSecurityInfoW(
            PCWSTR(wide.as_ptr()),
            SE_FILE_OBJECT,
            OWNER_SECURITY_INFORMATION | DACL_SECURITY_INFORMATION,
            None,
            None,
            None,
            None,
            &mut descriptor,
        );
        if status.0 != 0 {
            return false;
        }
        let mut text = PWSTR::null();
        let converted = ConvertSecurityDescriptorToStringSecurityDescriptorW(
            descriptor,
            SDDL_REVISION_1,
            OWNER_SECURITY_INFORMATION | DACL_SECURITY_INFORMATION,
            &mut text,
            None,
        );
        let ok = converted.is_ok() && text.to_string().is_ok_and(|sddl| sddl_is_vanta_stage(&sddl));
        if !text.is_null() {
            let _ = LocalFree(Some(HLOCAL(text.0.cast())));
        }
        let _ = LocalFree(Some(HLOCAL(descriptor.0)));
        ok
    }
}

/// A junction, symbolic link or other reparse point, from metadata read
/// without following it.
pub fn is_reparse_point(metadata: &fs::Metadata) -> bool {
    metadata.file_attributes() & FILE_ATTRIBUTE_REPARSE_POINT.0 != 0
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::services::test_support::TempDir;

    #[test]
    fn only_a_protected_system_and_administrators_directory_is_a_vanta_stage() {
        let good = "O:BAD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)";
        assert!(sddl_is_vanta_stage(good));
        assert!(sddl_is_vanta_stage("O:SYD:PAI(A;OICI;FA;;;BA)(A;OICI;FA;;;SY)"));
        assert!(!sddl_is_vanta_stage("O:BAD:(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)"), "inheritance not blocked");
        assert!(!sddl_is_vanta_stage("O:S-1-5-21-1-2-3-1001D:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)"), "a user owns it");
        assert!(!sddl_is_vanta_stage("O:BAD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;FA;;;BU)"), "another principal");
        assert!(!sddl_is_vanta_stage("O:BAD:P(A;OICI;FA;;;SY)(A;OICI;0x1200a9;;;BA)"), "not full control");
        assert!(!sddl_is_vanta_stage("O:BAD:P(A;OICI;FA;;;SY)"), "missing administrators");
        assert!(!sddl_is_vanta_stage("nothing"));
        let temp = TempDir::new("files-provenance");
        assert!(!is_protected_vanta_dir(temp.path()), "an ordinary folder is not a stage");
        assert!(!is_protected_vanta_dir(&temp.path().join("missing")));
    }

    #[test]
    fn a_write_that_cannot_be_renamed_into_place_leaves_no_temporary_file() {
        let temp = TempDir::new("files-atomic");
        let path = temp.path().join("session.json");
        // A directory in the way makes the final rename fail.
        fs::create_dir(&path).unwrap();
        assert!(write_json_atomically(&path, &serde_json::json!({"id": "s"})).is_err());
        let names: Vec<_> =
            fs::read_dir(temp.path()).unwrap().flatten().map(|entry| entry.file_name()).collect();
        assert_eq!(names, ["session.json"], "only the directory remains");
    }
}
