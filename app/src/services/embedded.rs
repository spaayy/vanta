//! An embedded build carries one Vanta package inside the executable and
//! installs nothing else. The bytes are written to the downloads folder once
//! and then go through the same extraction and caching as a downloaded
//! package, so everything downstream sees an ordinary `.vantapkg` with an exact
//! digest.
//!
//! Without the `embedded-package` feature this module only answers "no".
#![cfg_attr(not(any(test, feature = "embedded-package")), allow(dead_code, unused_imports))]

use std::path::{Path, PathBuf};

use anyhow::{Context, Result};

use super::package;
use super::releases::{partial_path, sha256_bytes, sha256_file, sweep_partials};

#[cfg(feature = "embedded-package")]
mod built {
    include!(concat!(env!("OUT_DIR"), "/embedded.rs"));
    pub const SOURCE_COMMIT: &str = env!("VANTA_SOURCE_COMMIT");
}

/// The release id this build carries: `1.0.0` for a release, `1.0.0-rc.1` for a candidate.
pub fn rc_id() -> Option<&'static str> {
    #[cfg(feature = "embedded-package")]
    {
        Some(built::RELEASE_ID)
    }
    #[cfg(not(feature = "embedded-package"))]
    {
        None
    }
}

/// Whether the id carries a pre-release suffix (`-rc.N`, `-test`...): only then is this a test build and the page shows
/// the test banner. A plain `1.0.0` opens without it.
pub fn is_prerelease() -> bool {
    rc_id().is_some_and(is_prerelease_id)
}

pub(crate) fn is_prerelease_id(id: &str) -> bool {
    id.contains('-')
}

/// The Git commit the tester build was made from, for About and diagnostics.
pub fn source_commit() -> Option<&'static str> {
    #[cfg(feature = "embedded-package")]
    {
        Some(built::SOURCE_COMMIT)
    }
    #[cfg(not(feature = "embedded-package"))]
    {
        None
    }
}

/// SHA-256 of the embedded archive, hashed once.
#[cfg(feature = "embedded-package")]
pub fn sha256() -> &'static str {
    static HASH: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    HASH.get_or_init(|| sha256_bytes(built::PACKAGE))
}

/// Writes the embedded archive under the app's downloads and returns its path.
#[cfg(feature = "embedded-package")]
pub fn materialize(paths: &super::settings::AppPaths) -> Result<PathBuf> {
    materialize_into(
        &paths.downloads().join(format!("Vanta-{}.vantapkg", built::RELEASE_ID)),
        built::PACKAGE,
        sha256(),
    )
}

/// The archive compiled into this build and its digest: the only bytes an
/// elevated install may run without a checksum list, because they are part of
/// the signed executable itself.
#[cfg(feature = "embedded-package")]
pub fn trusted_package() -> Option<(&'static [u8], &'static str)> {
    Some((built::PACKAGE, sha256()))
}

#[cfg(not(feature = "embedded-package"))]
pub fn trusted_package() -> Option<(&'static [u8], &'static str)> {
    None
}

/// Whether `digest` is the digest of the archive compiled into this build, so
/// no `SHA256SUMS` beside it (which anyone could change or race) is needed.
pub(crate) fn is_compiled_digest(digest: &str) -> bool {
    trusted_package().is_some_and(|(_, compiled)| compiled.eq_ignore_ascii_case(digest))
}

/// Whether an unpacked package directory holds exactly the embedded archive.
#[cfg(feature = "embedded-package")]
pub fn holds(dir: &Path) -> bool {
    package_matches(dir, sha256()) && package::intact(dir)
}

/// An unpacked directory was extracted from an archive with this digest.
pub(crate) fn package_matches(dir: &Path, sha256: &str) -> bool {
    package::identity(dir).is_some_and(|identity| identity.sha256.eq_ignore_ascii_case(sha256))
}

/// Puts `bytes` at `destination` unless an identical file is already there.
/// Each caller writes its own temporary file and renames it into place, so
/// two instances (or startup and the ISO page) racing here both end with one
/// valid file; whoever loses the rename verifies and reuses the winner's.
pub(crate) fn materialize_into(destination: &Path, bytes: &[u8], sha256: &str) -> Result<PathBuf> {
    let intact = |path: &Path| {
        std::fs::metadata(path).is_ok_and(|meta| meta.len() == bytes.len() as u64)
            && sha256_file(path).is_ok_and(|actual| actual.eq_ignore_ascii_case(sha256))
    };
    if intact(destination) {
        return Ok(destination.to_path_buf());
    }
    let dir = destination.parent().context("the embedded package needs a parent directory")?;
    std::fs::create_dir_all(dir).with_context(|| format!("create {}", dir.display()))?;
    sweep_partials(dir);
    let partial = partial_path(dir, &super::releases::file_name(destination));
    let result = std::fs::write(&partial, bytes)
        .with_context(|| format!("write {}", partial.display()))
        .and_then(|()| {
            std::fs::rename(&partial, destination)
                .with_context(|| format!("move {} into place", destination.display()))
        });
    if result.is_err() {
        let _ = std::fs::remove_file(&partial);
        // Another writer may have won; its file is as good as ours.
        if intact(destination) {
            return Ok(destination.to_path_buf());
        }
    }
    result.map(|()| destination.to_path_buf())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::services::test_support::{TempDir, package};

    const BYTES: &[u8] = b"not really an archive, but bytes are bytes";

    #[test]
    fn a_valid_cached_file_is_kept_and_a_corrupt_one_is_replaced() {
        let temp = TempDir::new("embedded-cache");
        let destination = temp.path().join("Downloads/Vanta-test.vantapkg");
        let digest = sha256_bytes(BYTES);
        assert_eq!(materialize_into(&destination, BYTES, &digest).unwrap(), destination);
        let written = std::fs::metadata(&destination).unwrap().modified().unwrap();
        std::thread::sleep(std::time::Duration::from_millis(20));
        materialize_into(&destination, BYTES, &digest).unwrap();
        assert_eq!(std::fs::metadata(&destination).unwrap().modified().unwrap(), written, "not rewritten");

        std::fs::write(&destination, b"same length but not the same bytes,corrupt").unwrap();
        materialize_into(&destination, BYTES, &digest).unwrap();
        assert_eq!(std::fs::read(&destination).unwrap(), BYTES);
        std::fs::write(&destination, b"short").unwrap();
        materialize_into(&destination, BYTES, &digest).unwrap();
        assert_eq!(std::fs::read(&destination).unwrap(), BYTES);
        assert!(
            std::fs::read_dir(destination.parent().unwrap()).unwrap().count() == 1,
            "no partial files remain"
        );
    }

    #[test]
    fn concurrent_callers_end_with_one_valid_file() {
        let temp = TempDir::new("embedded-race");
        let destination = temp.path().join("Vanta-race.vantapkg");
        let digest = sha256_bytes(BYTES);
        let workers: Vec<_> = (0..8)
            .map(|_| {
                let destination = destination.clone();
                let digest = digest.clone();
                std::thread::spawn(move || materialize_into(&destination, BYTES, &digest).unwrap())
            })
            .collect();
        for worker in workers {
            assert_eq!(worker.join().unwrap(), destination);
        }
        assert_eq!(std::fs::read(&destination).unwrap(), BYTES);
        assert_eq!(std::fs::read_dir(temp.path()).unwrap().count(), 1, "no partial files remain");
    }

    #[test]
    fn only_a_suffix_makes_a_prerelease() {
        assert!(!is_prerelease_id("1.0.0"));
        for id in ["1.0.0-rc.1", "1.0.0-test", "1.0.0-pessoal"] {
            assert!(is_prerelease_id(id), "{id}");
        }
    }

    #[test]
    fn a_package_matches_only_the_archive_it_was_unpacked_from() {
        let temp = TempDir::new("embedded-identity");
        let package = package::write(&temp.path().join("package.vantapkg"), &package::valid("0.6.0"));
        let digest = sha256_file(&package).unwrap();
        let (dir, _) =
            crate::services::package::extract_into(&package, &temp.path().join("Packages"), |_, _| {})
                .unwrap();
        assert!(package_matches(&dir, &digest));
        assert!(package_matches(&dir, &digest.to_uppercase()));
        assert!(!package_matches(&dir, &sha256_bytes(BYTES)));
        assert!(!package_matches(temp.path(), &digest), "a directory without an identity never matches");
    }
}
