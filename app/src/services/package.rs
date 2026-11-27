//! The Atlas package: reading its manifest, `vanta.json` (what the install
//! offers and requires), and unpacking an `.vantapkg` file so the front door
//! script can run it. docs/package-format.md, from the repository root,
//! defines the format.
//!
//! Unpacking is transactional and the result immutable. The archive is
//! written to a private staging directory under the package cache,
//! validated there, and only then moved into its final place, which is named
//! after the package's version *and* the archive's content digest
//! (`<cache>/<version>_<digest>`). Two packages that both call themselves
//! 0.6.0 therefore never share a directory: a manifest read from a prepared
//! package always describes the files at that path, whatever another window
//! unpacks later. Identical content is recognised and reused, while it still
//! holds every file it was unpacked with.

use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::io::Read;
use std::path::{Component, Path, PathBuf};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};

use super::files::is_reparse_point;
use super::manager_version::{self, ManagerVersion};
use super::releases::sha256_file;

/// The archive password is public by design; it only stops antivirus engines
/// from scanning the scripts inside the package before they are staged.
pub(crate) const PACKAGE_PASSWORD: &str = "vantapkg";

/// The extension of every Vanta package file.
pub const EXTENSION: &str = "vantapkg";

/// The manifest at the root of every package.
const MANIFEST_FILE: &str = "vanta.json";

/// The checksum list that must sit beside a package; it is checked before
/// the package is opened.
pub const SUMS_FILE: &str = "SHA256SUMS";

/// The manifest format this app reads.
const SCHEMA_VERSION: u32 = 1;

/// The install time a manifest claims when it gives none.
const DEFAULT_ESTIMATED_MINUTES: u32 = 15;

/// The manifest in this repository, used to describe options before any
/// release has been downloaded.
const BUILTIN_MANIFEST: &str = include_str!("../../../vanta/vanta.json");

/// The first Atlas release that includes the front door script this app drives.
pub const FIRST_FRONT_DOOR_VERSION: &str = "0.6.0";

/// Whether an Atlas version is known to predate the front door script. A
/// version that cannot be read is not: the package's own files decide.
pub fn predates_front_door(version: &str) -> bool {
    super::releases::VantaVersion::parse(version).is_some()
        && super::releases::compare_versions(version, FIRST_FRONT_DOOR_VERSION).is_lt()
}

/// The package predates the front door script this app drives. Typed so the
/// UI can explain it in the user's language.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Unsupported {
    pub version: String,
}

impl std::fmt::Display for Unsupported {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "Atlas {} predates the front door script this app runs; this app installs Atlas {FIRST_FRONT_DOOR_VERSION} and later",
            self.version
        )
    }
}

impl std::error::Error for Unsupported {}

/// The package is recent enough to have the front door script but does not
/// contain it: damaged, incomplete, or not an Atlas release.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Incomplete {
    pub version: String,
}

impl std::fmt::Display for Incomplete {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "Atlas {} has no front door script at Executables\\VantaModules\\Scripts\\Entry\\Install-Vanta.ps1",
            self.version
        )
    }
}

impl std::error::Error for Incomplete {}

/// The package needs a newer Atlas Manager than this one: its manifest asks
/// for a later `minimumManagerVersion`, or is in a format only a newer
/// Atlas Manager reads. Typed so the UI can say so in the user's language
/// and offer the download.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ManagerOutdated {
    /// The Atlas Manager version the package asks for, when it names one
    /// that this app can read and doesn't meet.
    pub required: Option<String>,
    /// The manifest's format, when it's newer than the one this app reads.
    pub format: Option<u32>,
}

impl std::fmt::Display for ManagerOutdated {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let current = ManagerVersion::current();
        match &self.required {
            Some(required) => write!(
                f,
                "the package needs Atlas Manager {required} or later, and this is Atlas Manager {current}"
            )?,
            None => write!(f, "the package needs a newer Atlas Manager than this one, {current}")?,
        }
        if let Some(format) = self.format {
            write!(f, "; its vanta.json has format {format}, and this app reads format {SCHEMA_VERSION}")?;
        }
        Ok(())
    }
}

impl std::error::Error for ManagerOutdated {}

/// The file isn't an Atlas package this app opens: it has another extension,
/// or it's an AME Wizard package (`.apbx`) from an Atlas release before 0.6,
/// under any name. Typed so the UI can explain it in the user's language.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NotAPackage {
    /// The file's name, without its folder.
    pub file: String,
}

impl std::fmt::Display for NotAPackage {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "{} is not a Vanta package: Vanta Manager opens only .{EXTENSION} files (.vantapkg and .apbx are refused)",
            self.file
        )
    }
}

impl std::error::Error for NotAPackage {}

impl NotAPackage {
    fn of(path: &Path) -> Self {
        Self { file: super::releases::file_name(path) }
    }
}

/// Opens the package only if `SHA256SUMS` beside it lists it with the digest
/// the file really has. A missing list, a missing line or a different digest
/// refuses the package before any byte of it is read as an archive.
#[cfg_attr(not(test), allow(dead_code))]
pub fn verify_checksum(package: &Path) -> Result<()> {
    verify_checksum_of(package, &sha256_file(package)?)
}

/// [`verify_checksum`] for a digest the caller already computed from the very
/// bytes it is about to open, so the file cannot change in between.
fn verify_checksum_of(package: &Path, actual: &str) -> Result<()> {
    let name = super::releases::file_name(package);
    let dir = package.parent().filter(|dir| !dir.as_os_str().is_empty()).unwrap_or(Path::new("."));
    let sums = fs::read_to_string(dir.join(SUMS_FILE)).with_context(|| {
        format!("{SUMS_FILE} was not found beside {name}; Vanta Manager does not open a package without it")
    })?;
    let expected = sums
        .lines()
        .filter_map(|line| {
            let (digest, listed) = line.trim().split_once(char::is_whitespace)?;
            let listed = listed.trim().trim_start_matches('*');
            listed.eq_ignore_ascii_case(&name).then(|| digest.to_ascii_lowercase())
        })
        .next()
        .with_context(|| format!("{name} is not listed in {SUMS_FILE}"))?;
    anyhow::ensure!(
        expected == actual.to_ascii_lowercase(),
        "the SHA-256 of {name} does not match {SUMS_FILE}: the package was changed or damaged"
    );
    Ok(())
}

/// Refuses a file whose extension isn't `.vantapkg` before anything reads it.
pub fn check_file_name(path: &Path) -> Result<()> {
    if path.extension().is_some_and(|extension| extension.eq_ignore_ascii_case(EXTENSION)) {
        Ok(())
    } else {
        Err(NotAPackage::of(path).into())
    }
}

const STAGING_PREFIX: &str = ".staging-";
/// Written into every published directory: which archive it came from.
const IDENTITY_FILE: &str = ".atlas-package.json";
/// Hex digits of the archive digest in the directory name.
const DIGEST_IN_NAME: usize = 16;

/// What a published directory holds: the version its manifest declares and
/// the SHA-256 of the archive it was unpacked from.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PackageIdentity {
    pub version: String,
    pub sha256: String,
}

impl PackageIdentity {
    /// The directory name for this content: version, then enough of the
    /// digest to tell packages apart, separated so neither is mistaken for
    /// part of the other (a version never contains `_`).
    pub fn directory_name(&self) -> String {
        format!("{}_{}", self.version, &self.sha256[..DIGEST_IN_NAME.min(self.sha256.len())])
    }
}

/// The identity a published directory records, if it has one.
pub fn identity(dir: &Path) -> Option<PackageIdentity> {
    let text = fs::read_to_string(dir.join(IDENTITY_FILE)).ok()?;
    serde_json::from_str(&text).ok()
}

/// The identity file in full: the package's identity, and every file the
/// archive unpacked to (`/`-separated, relative to the directory) with its
/// size, so a copy that has since lost or changed a file can be recognised.
#[derive(Serialize, Deserialize)]
struct Record {
    #[serde(flatten)]
    identity: PackageIdentity,
    files: BTreeMap<String, u64>,
    /// SHA-256 of every file as unpacked. A copy without them (published
    /// before they were recorded) cannot be checked, so it is not trusted.
    #[serde(default)]
    hashes: BTreeMap<String, String>,
}

fn record(dir: &Path) -> Option<Record> {
    let text = fs::read_to_string(dir.join(IDENTITY_FILE)).ok()?;
    serde_json::from_str(&text).ok()
}

/// Whether a published directory still holds every file it was unpacked
/// with, at its unpacked size. Security software that quarantines one script
/// leaves a copy that can never install; one published before the files were
/// recorded can't be checked, so it counts as damaged too.
pub fn intact(dir: &Path) -> bool {
    record(dir).is_some_and(|record| complete(dir, &record))
}

fn complete(dir: &Path, record: &Record) -> bool {
    is_extracted(dir) && first_missing(dir, &record.files).is_none() && hashes_match(dir, record)
}

/// Every recorded file still has the SHA-256 it was unpacked with: the scripts
/// run elevated, so a same-size edit in the cache must not pass.
fn hashes_match(dir: &Path, record: &Record) -> bool {
    record.hashes.len() == record.files.len()
        && record.hashes.iter().all(|(name, expected)| {
            let path = name.split('/').fold(dir.to_path_buf(), |path, part| path.join(part));
            sha256_file(&path).is_ok_and(|actual| actual.eq_ignore_ascii_case(expected))
        })
}

/// The first of `files` that `dir` no longer holds as a regular file of the
/// recorded size.
fn first_missing<'a>(dir: &Path, files: &'a BTreeMap<String, u64>) -> Option<&'a str> {
    files
        .iter()
        .find(|(name, size)| {
            let path = name.split('/').fold(dir.to_path_buf(), |path, part| path.join(part));
            !fs::symlink_metadata(path).is_ok_and(|meta| meta.is_file() && meta.len() == **size)
        })
        .map(|(name, _)| name.as_str())
}

/// What a package's manifest declares, checked.
#[derive(Clone, Debug)]
pub struct Manifest {
    pub version: String,
    /// The Atlas versions this package can update in place.
    pub updatable_from: Vec<String>,
    pub supported_builds: Vec<u32>,
    /// The checks the front door runs before it installs, by id, such as
    /// `plugged-in`.
    pub requirements: Vec<String>,
    pub estimated_minutes: u32,
    /// The questions an install asks, in the order they're asked.
    pub choices: Vec<Choice>,
    /// What only Vanta packages declare (`vanta` in vanta.json); o Vanta Tools (F5) lê.
    #[allow(dead_code)]
    pub vanta: VantaMeta,
}

/// The `vanta` field of vanta.json: the Tools version bundled, where the
/// restore kit's manifest lives, and ready-made sets of choices.
#[derive(Clone, Debug, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
#[allow(dead_code)]
pub struct VantaMeta {
    #[serde(default)]
    pub tools_version: String,
    #[serde(default)]
    pub kit_manifest: String,
    #[serde(default)]
    pub presets: Vec<Preset>,
}

/// A named set of choices, such as `nathan`; each value is one option id or
/// a list of them.
#[derive(Clone, Debug, Deserialize)]
#[allow(dead_code)]
pub struct Preset {
    pub id: String,
    pub label: String,
    #[serde(default)]
    pub choices: std::collections::BTreeMap<String, serde_json::Value>,
}

/// One question an install asks.
#[derive(Clone, Debug)]
pub struct Choice {
    /// A stable name for the question, such as `defender`.
    pub id: String,
    pub kind: ChoiceKind,
    /// The manifest's English text about the question; empty when it has none.
    pub description: String,
    /// An `https://` link to documentation about the question.
    pub learn_more: Option<String>,
    /// Only asked when this option is chosen elsewhere.
    pub depends_on: Option<String>,
    pub options: Vec<ChoiceOption>,
}

/// How many options a [`Choice`] takes.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ChoiceKind {
    /// Exactly one option; `default` names the preselected one.
    Single,
    /// Any number of options, including none.
    Multiple,
}

/// One answer to a [`Choice`].
#[derive(Clone, Debug)]
pub struct ChoiceOption {
    /// The option's id, as install records and the front door know it.
    pub id: String,
    /// The manifest's English label, shown when this app has none of its own.
    pub label: String,
    /// The stem of a PNG in the package's `Images` folder.
    pub image: Option<String>,
    /// The option a single choice starts with.
    pub default: bool,
}

impl ChoiceOption {
    /// Optional artwork belongs to the unpacked package, never the executable.
    pub fn image_path(&self, package: &Path) -> Option<PathBuf> {
        let name = self.image.as_deref()?;
        // A stem in Images, not an arbitrary path or URL.
        if name.is_empty() || !name.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_') {
            return None;
        }
        let path = package.join("Images").join(format!("{name}.png"));
        path.is_file().then_some(path)
    }
}

/// The shipped 1.0.0 manifest has no predecessor, so the update and reinstall logic would have nothing to run on.
/// The unit tests drive that logic with the manifest of a release that has predecessors: 0.6.0, updatable from 0.4.1
/// and 0.5.0. Only `Manifest::shipped` (and the test of it) reads the real values.
#[cfg(test)]
fn historical_manifest() -> String {
    let mut value: serde_json::Value = serde_json::from_str(BUILTIN_MANIFEST).expect("vanta.json is JSON");
    value["version"] = "0.6.0".into();
    value["minimumManagerVersion"] = "0.6.0".into();
    value["updatableFrom"] = serde_json::json!(["0.4.1", "0.5.0"]);
    value.to_string()
}

impl Manifest {
    pub fn builtin() -> Manifest {
        #[cfg(test)]
        return parse(&historical_manifest()).expect("the historical test manifest parses");
        #[cfg(not(test))]
        parse(BUILTIN_MANIFEST).expect("the repository's package/vanta.json parses")
    }

    /// The manifest shipped in this build (1.0.0, updatable from nothing).
    #[cfg(test)]
    pub fn shipped() -> Manifest {
        parse(BUILTIN_MANIFEST).expect("the repository's package/vanta.json parses")
    }

    /// Option ids selected by default, in choice order.
    pub fn default_options(&self) -> Vec<String> {
        self.choices
            .iter()
            .flat_map(|choice| choice.options.iter().filter(|o| o.default).map(|o| o.id.clone()))
            .collect()
    }

    /// The manifest's label for an option id, if this manifest declares it.
    pub fn option_label(&self, id: &str) -> Option<&str> {
        self.choices
            .iter()
            .flat_map(|choice| choice.options.iter())
            .find(|option| option.id == id)
            .map(|option| option.label.as_str())
    }
}

/// Orders `choices` (indexes into `all`) so a choice asked only when an
/// option is chosen comes straight after the choice that offers that option:
/// the browser picker follows the apps that ask to "choose one below". A
/// choice whose option is offered by no choice in `choices` keeps its place,
/// as do choices that depend on each other in a loop.
pub fn follow_parents(all: &[Choice], choices: Vec<usize>) -> Vec<usize> {
    let parent = |index: usize| {
        let option = all[index].depends_on.as_ref()?;
        choices.iter().copied().find(|&candidate| {
            candidate != index && all[candidate].options.iter().any(|offered| &offered.id == option)
        })
    };
    let mut ordered = Vec::with_capacity(choices.len());
    for &index in choices.iter().filter(|&&index| parent(index).is_none()) {
        place_with_children(index, &choices, &parent, &mut ordered);
    }
    let rest: Vec<usize> = choices.iter().copied().filter(|index| !ordered.contains(index)).collect();
    ordered.extend(rest);
    ordered
}

/// Appends `index`, then the choices that depend on it, each followed by its own.
fn place_with_children(
    index: usize,
    choices: &[usize],
    parent: &dyn Fn(usize) -> Option<usize>,
    out: &mut Vec<usize>,
) {
    if out.contains(&index) {
        return;
    }
    out.push(index);
    for &child in choices.iter().filter(|&&child| parent(child) == Some(index)) {
        place_with_children(child, choices, parent, out);
    }
}

/// The manifest of an already unpacked package directory.
pub fn read_manifest(dir: &Path) -> Result<Manifest> {
    let path = dir.join(MANIFEST_FILE);
    let text = fs::read_to_string(&path).with_context(|| format!("read {}", path.display()))?;
    parse(&text)
}

/// The fields [`parse`] reads before the rest: what a package asks of the
/// Atlas Manager that opens it. A package for a newer Atlas Manager may
/// change everything else, and is still refused for the right reason.
#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Requirement {
    schema_version: u32,
    #[serde(default)]
    minimum_manager_version: Option<serde_json::Value>,
}

/// `vanta.json` as it's written, before [`parse`] checks it, once
/// [`Requirement`] has checked its format. Fields this app doesn't use are
/// ignored, so a later format that only adds fields still reads.
#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ManifestFile {
    version: String,
    /// The oldest Atlas Manager that can install the package, as
    /// `major.minor.patch`.
    minimum_manager_version: String,
    #[serde(default)]
    supported_builds: Vec<SupportedBuild>,
    #[serde(default)]
    updatable_from: Vec<String>,
    #[serde(default)]
    requirements: Vec<String>,
    estimated_minutes: Option<u32>,
    #[serde(default)]
    choices: Vec<ChoiceFile>,
    #[serde(default)]
    vanta: VantaMeta,
}

/// Only `build` is checked; `release` names it for readers.
#[derive(Deserialize)]
struct SupportedBuild {
    build: u32,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ChoiceFile {
    id: String,
    kind: ChoiceKind,
    default: Option<String>,
    depends_on: Option<String>,
    description: Option<String>,
    learn_more: Option<String>,
    options: Vec<OptionFile>,
}

#[derive(Deserialize)]
struct OptionFile {
    id: String,
    label: String,
    image: Option<String>,
}

/// Reads and checks a manifest: this Atlas Manager is one the package
/// accepts, the format is the one this app reads, every choice and option id
/// is declared once, every choice has options, and every single choice names
/// one of its own options as its default. A package for a newer Atlas
/// Manager is refused with [`ManagerOutdated`].
pub fn parse(json: &str) -> Result<Manifest> {
    parse_for(json, &ManagerVersion::current())
}

/// [`parse`], as the Atlas Manager `manager` would.
fn parse_for(json: &str, manager: &ManagerVersion) -> Result<Manifest> {
    let json = json.trim_start_matches('\u{feff}');
    let requirement: Requirement = serde_json::from_str(json).context("read vanta.json")?;
    let format = requirement.schema_version;
    let newer_format = (format > SCHEMA_VERSION).then_some(format);
    // Only a version this app can read, and doesn't meet, is named: a newer
    // format may write it differently.
    let required = requirement
        .minimum_manager_version
        .as_ref()
        .and_then(serde_json::Value::as_str)
        .filter(|text| manager_version::parse_plain(text).is_some_and(|minimum| !manager.meets(minimum)));
    if required.is_some() || newer_format.is_some() {
        return Err(ManagerOutdated { required: required.map(str::to_owned), format: newer_format }.into());
    }
    anyhow::ensure!(
        format == SCHEMA_VERSION,
        "vanta.json has format {format}, and this app reads format {SCHEMA_VERSION}"
    );
    let file: ManifestFile = serde_json::from_str(json).context("read vanta.json")?;
    anyhow::ensure!(
        manager_version::parse_plain(&file.minimum_manager_version).is_some(),
        "vanta.json gives minimumManagerVersion {:?}, which isn't major.minor.patch",
        file.minimum_manager_version
    );
    let mut choice_ids = BTreeSet::new();
    let mut option_ids = BTreeSet::new();
    let mut choices = Vec::with_capacity(file.choices.len());
    for choice in file.choices {
        let id = choice.id;
        anyhow::ensure!(choice_ids.insert(id.clone()), "vanta.json declares the choice {id:?} twice");
        anyhow::ensure!(!choice.options.is_empty(), "the choice {id:?} in vanta.json has no options");
        for option in &choice.options {
            anyhow::ensure!(
                option_ids.insert(option.id.clone()),
                "vanta.json declares the option {:?} twice",
                option.id
            );
        }
        let default = match choice.kind {
            ChoiceKind::Single => {
                let default = choice
                    .default
                    .with_context(|| format!("the choice {id:?} in vanta.json has no default"))?;
                anyhow::ensure!(
                    choice.options.iter().any(|option| option.id == default),
                    "the choice {id:?} in vanta.json defaults to {default:?}, which isn't one of its options"
                );
                Some(default)
            }
            ChoiceKind::Multiple => None,
        };
        choices.push(Choice {
            id,
            kind: choice.kind,
            description: choice.description.unwrap_or_default(),
            learn_more: choice.learn_more.filter(|url| url.starts_with("https://")),
            depends_on: choice.depends_on,
            options: choice
                .options
                .into_iter()
                .map(|option| ChoiceOption {
                    default: default.as_deref() == Some(option.id.as_str()),
                    id: option.id,
                    label: option.label,
                    image: option.image,
                })
                .collect(),
        });
    }
    Ok(Manifest {
        version: file.version.trim().to_owned(),
        updatable_from: file.updatable_from,
        supported_builds: file.supported_builds.into_iter().map(|build| build.build).collect(),
        requirements: file.requirements,
        estimated_minutes: file.estimated_minutes.unwrap_or(DEFAULT_ESTIMATED_MINUTES),
        choices,
        vanta: file.vanta,
    })
}

/// Checks that a package version can name a cache directory: the same shape
/// `Get-VantaPackageVersion` accepts (`major.minor.patch` with an optional
/// `-suffix` of letters, digits, dots and dashes), which rules out empty,
/// relative, rooted and separator-bearing values.
pub fn validate_version(version: &str) -> Result<&str> {
    const MAX_LEN: usize = 64;
    let text = version.trim();
    anyhow::ensure!(!text.is_empty(), "the package has no version");
    anyhow::ensure!(text.len() <= MAX_LEN, "the package version {text:?} is too long");
    let (core, suffix) = match text.split_once('-') {
        Some((core, suffix)) => (core, Some(suffix)),
        None => (text, None),
    };
    let parts: Vec<&str> = core.split('.').collect();
    let core_ok =
        parts.len() == 3 && parts.iter().all(|p| !p.is_empty() && p.bytes().all(|b| b.is_ascii_digit()));
    anyhow::ensure!(core_ok, "the package version {text:?} is not major.minor.patch");
    if let Some(suffix) = suffix {
        let suffix_ok =
            !suffix.is_empty() && suffix.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'.' || b == b'-');
        anyhow::ensure!(suffix_ok, "the package version {text:?} has an invalid suffix");
    }
    // Windows drops trailing dots from directory names, which would make the
    // published path differ from the version.
    anyhow::ensure!(!text.ends_with('.'), "the package version {text:?} ends with a dot");
    Ok(text)
}

/// The front door script inside an extracted package. The package keeps
/// `vanta.json` at its root and Atlas's files under `Executables`; the
/// script finds the root from its own location.
pub fn front_door(dir: &Path) -> PathBuf {
    dir.join("Executables").join("VantaModules").join("Scripts").join("Entry").join("Install-Vanta.ps1")
}

/// Drops the `\\?\` prefix `canonicalize` adds: PowerShell's path cmdlets
/// cannot parse it, and these paths are handed to PowerShell.
pub fn plain_path(path: PathBuf) -> PathBuf {
    let Some(text) = path.to_str() else { return path };
    let Some(rest) = text.strip_prefix(r"\\?\") else { return path };
    if let Some(unc) = rest.strip_prefix(r"UNC\") {
        return PathBuf::from(format!(r"\\{unc}"));
    }
    PathBuf::from(rest)
}

pub fn is_extracted(dir: &Path) -> bool {
    dir.join(MANIFEST_FILE).is_file() && front_door(dir).is_file()
}

/// Unpacks an `.vantapkg` file beneath `root`, a directory this app owns.
/// Any other file is refused with [`NotAPackage`] before it's read. The package is
/// written and validated in a private staging directory first, then
/// published as `<root>/<version>_<digest>`. That directory is never written
/// again: an archive with the same content is recognised by its digest and
/// the existing directory returned as it is, unless it has lost a file since,
/// when the archive is unpacked again under the next free name; different
/// content of the same version gets a directory of its own, leaving the
/// first untouched.
///
/// Published directories are never removed: another window, a draft or an
/// install record may still point at one, and removing it would defeat the
/// identity scheme.
pub fn extract_into(
    package: &Path,
    root: &Path,
    mut progress: impl FnMut(usize, usize),
) -> Result<(PathBuf, Manifest)> {
    check_file_name(package)?;
    // The archive is read once: the digest checked, the digest recorded and the
    // bytes unpacked are the same bytes. The tests build packages without a
    // checksum list; every real run has one, except the archive compiled into
    // an embedded build, whose digest is part of the executable.
    let bytes = fs::read(package).with_context(|| format!("open {}", package.display()))?;
    let digest = super::releases::sha256_bytes(&bytes);
    if !cfg!(test) && !super::embedded::is_compiled_digest(&digest) {
        verify_checksum_of(package, &digest)?;
    }
    let mut archive = zip::ZipArchive::new(std::io::Cursor::new(bytes.as_slice())).context("read the package archive")?;

    // Read the manifest first so the target directory carries the real version.
    let manifest = {
        // An AME Wizard package keeps its manifest in playbook.conf instead,
        // whatever the file is called.
        if archive.index_for_name(MANIFEST_FILE).is_none()
            && archive.index_for_name("playbook.conf").is_some()
        {
            return Err(NotAPackage::of(package).into());
        }
        let mut entry = archive
            .by_name_decrypt(MANIFEST_FILE, PACKAGE_PASSWORD.as_bytes())
            .context("the package has no readable vanta.json")?;
        let mut text = String::new();
        entry.read_to_string(&mut text).context("read vanta.json")?;
        parse(&text)?
    };
    let version = validate_version(&manifest.version)?.to_owned();
    let identity = PackageIdentity { version: version.clone(), sha256: digest };

    fs::create_dir_all(root).with_context(|| format!("create {}", root.display()))?;
    let root = plain_path(root.canonicalize().with_context(|| format!("resolve {}", root.display()))?);
    sweep_leftovers(&root);

    let target = root.join(identity.directory_name());
    anyhow::ensure!(
        target.parent() == Some(root.as_path()) && is_plain_component(&target),
        "the package version {version:?} does not name a cache directory"
    );
    // The same bytes were unpacked before and every file is still there:
    // the directory is immutable, so it holds exactly this package.
    if let Some(published) = find_published(&root, &identity) {
        let total = archive.len();
        progress(total, total);
        return Ok((published, manifest));
    }

    let staging = create_unique_dir(&root, &format!("{STAGING_PREFIX}{version}-"))?;
    let result = (|| -> Result<PathBuf> {
        let files = extract_entries(&mut archive, &staging, &mut progress)?;
        if !is_extracted(&staging) {
            let version = version.clone();
            return Err(if predates_front_door(&version) {
                Unsupported { version }.into()
            } else {
                Incomplete { version }.into()
            });
        }
        // Security software may remove a file as soon as it has been written.
        if let Some(name) = first_missing(&staging, &files) {
            anyhow::bail!(
                "{} was removed or changed right after it was unpacked, probably by security software",
                name.replace('/', "\\")
            );
        }
        reject_reparse_points(&staging)?;
        let mut hashes = BTreeMap::new();
        for name in files.keys() {
            let path = name.split('/').fold(staging.clone(), |path, part| path.join(part));
            hashes.insert(name.clone(), sha256_file(&path)?);
        }
        let record = Record { identity: identity.clone(), files, hashes };
        fs::write(staging.join(IDENTITY_FILE), serde_json::to_string_pretty(&record)?)
            .context("record the package identity")?;
        publish(&staging, &root, &identity)
    })();
    if result.is_err() {
        let _ = fs::remove_dir_all(&staging);
    }
    result.map(|published| (published, manifest))
}

/// Unpacks authenticated archive `bytes` into a brand-new directory that only
/// SYSTEM and Administrators can reach from the moment it exists (`sddl` is
/// applied by `CreateDirectory` itself, with no window in between), and returns
/// it. The bytes must hash to `expected_sha256`, which the caller takes from a
/// trusted source (the digest compiled into the executable), never from
/// anything stored under the user's profile. The elevated install runs from
/// this copy, so a process of the same user cannot change a script after it
/// was checked.
pub fn stage_protected(
    bytes: &[u8],
    expected_sha256: &str,
    parent: &Path,
    sddl: &str,
    owners: &[StageOwner],
) -> Result<PathBuf> {
    let actual = super::releases::sha256_bytes(bytes);
    anyhow::ensure!(
        actual.eq_ignore_ascii_case(expected_sha256),
        "the package bytes do not match the trusted digest: refusing to stage them"
    );
    let dir = parent.join(format!("{STAGE_PREFIX}{}", unique_suffix()));
    super::files::create_protected_dir(&dir, sddl)?;
    let result = (|| -> Result<()> {
        let mut archive = zip::ZipArchive::new(std::io::Cursor::new(bytes)).context("read the package archive")?;
        extract_entries(&mut archive, &dir, &mut |_, _| {})?;
        anyhow::ensure!(is_extracted(&dir), "the staged package is incomplete");
        reject_reparse_points(&dir)?;
        set_stage_owners(&dir, owners)
    })();
    if let Err(error) = result {
        let _ = fs::remove_dir_all(&dir);
        return Err(error);
    }
    Ok(dir)
}

/// Names of the protected directories [`stage_protected`] creates.
pub const STAGE_PREFIX: &str = "VantaStage-";
/// Written inside every stage, where only administrators can write: who is using it.
const STAGE_MARKER: &str = ".vanta-stage.json";

/// A process that is using a stage, told apart from a later one that reuses its
/// PID by its start time.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct StageOwner {
    pub pid: u32,
    pub start: u64,
}

#[derive(Serialize, Deserialize)]
struct StageMarker {
    schema: u32,
    owners: Vec<StageOwner>,
}

/// Records which processes use `dir` (the Manager, then the install it started).
pub fn set_stage_owners(dir: &Path, owners: &[StageOwner]) -> Result<()> {
    let marker = StageMarker { schema: 1, owners: owners.to_vec() };
    fs::write(dir.join(STAGE_MARKER), serde_json::to_vec(&marker)?).context("record who uses the staged package")
}

fn stage_owners(dir: &Path) -> Option<Vec<StageOwner>> {
    let marker: StageMarker = serde_json::from_slice(&fs::read(dir.join(STAGE_MARKER)).ok()?).ok()?;
    (marker.schema == 1).then_some(marker.owners)
}

fn is_stage_name(path: &Path) -> bool {
    path.file_name().is_some_and(|name| name.to_string_lossy().starts_with(STAGE_PREFIX))
}

/// Removes exactly the stage of one finished session, and only a directory
/// that is a stage (by name and by the marker only an administrator can write).
pub fn remove_stage(dir: &Path) {
    let is_link = fs::symlink_metadata(dir).map(|meta| is_reparse_point(&meta)).unwrap_or(true);
    if is_stage_name(dir) && !is_link && stage_owners(dir).is_some() {
        let _ = fs::remove_dir_all(dir);
    }
}

/// Recovers what earlier installs left under `parent`: a directory goes only if
/// it proves it is the Vanta's (its name, its marker and `provenance`: owned by
/// and writable only by SYSTEM and Administrators) and every process it names
/// has ended (`state`). A directory in use by another session or user, one whose
/// state cannot be read, one without a marker or the right ACL and a link are
/// all left alone.
pub fn sweep_stages(
    parent: &Path,
    state: impl Fn(StageOwner) -> super::system::Liveness,
    provenance: impl Fn(&Path) -> bool,
) {
    use super::system::Liveness;
    let Ok(entries) = fs::read_dir(parent) else { return };
    for entry in entries.flatten() {
        let path = entry.path();
        if !is_stage_name(&path) || !provenance(&path) {
            continue;
        }
        // Gone only when Windows says so for every process it names; "alive" and "cannot tell" both keep it.
        match stage_owners(&path) {
            Some(owners) if !owners.is_empty() && owners.iter().all(|owner| state(*owner) == Liveness::Ended) => {
                remove_stage(&path)
            }
            _ => {}
        }
    }
}

fn unique_suffix() -> String {
    let nanos = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_nanos()).unwrap_or(0);
    format!("{:x}-{:x}", std::process::id(), nanos)
}

/// The directories one identity may be published under: its name, and a
/// few numbered alternatives for when that name is occupied by something
/// that is not this package (a damaged remnant, say).
fn candidates(root: &Path, identity: &PackageIdentity) -> Vec<PathBuf> {
    let name = identity.directory_name();
    std::iter::once(root.join(&name)).chain((2..=9).map(|n| root.join(format!("{name}-{n}")))).collect()
}

/// A complete published copy of exactly this package, if there is one. A
/// damaged copy is passed over and left as it is.
fn find_published(root: &Path, identity: &PackageIdentity) -> Option<PathBuf> {
    candidates(root, identity).into_iter().find(|dir| holds(dir, identity))
}

fn holds(dir: &Path, identity: &PackageIdentity) -> bool {
    record(dir).is_some_and(|record| record.identity == *identity && complete(dir, &record))
}

/// Whether the path ends in an ordinary name, not `..`, a root or a drive.
fn is_plain_component(path: &Path) -> bool {
    matches!(path.components().next_back(), Some(Component::Normal(_)))
}

/// Writes every entry under `staging` and returns the files written, as the
/// identity file records them. A name the archive repeats keeps the size it
/// was last written with.
fn extract_entries<R: Read + std::io::Seek>(
    archive: &mut zip::ZipArchive<R>,
    staging: &Path,
    progress: &mut impl FnMut(usize, usize),
) -> Result<BTreeMap<String, u64>> {
    let total = archive.len();
    let mut files = BTreeMap::new();
    for index in 0..total {
        let mut entry = archive
            .by_index_decrypt(index, PACKAGE_PASSWORD.as_bytes())
            .with_context(|| format!("read entry {index}"))?;
        let entry_name = entry.name().with_context(|| format!("decode entry {index} name"))?;
        let Some(relative) = entry.enclosed_name() else {
            anyhow::bail!("the package contains an unsafe path: {entry_name}");
        };
        check_entry_components(&relative).with_context(|| format!("unsafe entry {entry_name}"))?;
        let path = staging.join(&relative);
        anyhow::ensure!(path.starts_with(staging), "the package contains an unsafe path: {entry_name}");
        if entry.is_dir() {
            fs::create_dir_all(&path)?;
        } else {
            if let Some(parent) = path.parent() {
                fs::create_dir_all(parent)?;
            }
            let mut output = fs::File::create(&path).with_context(|| format!("create {}", path.display()))?;
            std::io::copy(&mut entry, &mut output).with_context(|| format!("write {}", path.display()))?;
            let name =
                relative.components().map(|part| part.as_os_str().to_string_lossy()).collect::<Vec<_>>();
            files.insert(name.join("/"), entry.size());
        }
        progress(index + 1, total);
    }
    Ok(files)
}

/// Beyond `enclosed_name()`: every component must be an ordinary name with no
/// drive, stream or device syntax, because the files are later run elevated.
fn check_entry_components(relative: &Path) -> Result<()> {
    const DEVICES: [&str; 22] = [
        "CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
        "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9",
    ];
    for component in relative.components() {
        let Component::Normal(name) = component else {
            anyhow::bail!("path component {component:?} is not a plain name");
        };
        let name = name.to_string_lossy();
        anyhow::ensure!(!name.is_empty(), "empty path component");
        anyhow::ensure!(!name.contains(':'), "path component {name:?} contains a colon");
        anyhow::ensure!(
            !name.ends_with('.') && !name.ends_with(' '),
            "path component {name:?} has a trailing dot or space"
        );
        let stem = name.split('.').next().unwrap_or_default().to_ascii_uppercase();
        anyhow::ensure!(!DEVICES.contains(&stem.as_str()), "path component {name:?} is a device name");
    }
    Ok(())
}

/// A junction or symbolic link inside the package could redirect the
/// elevated installer; the front door refuses them too.
fn reject_reparse_points(dir: &Path) -> Result<()> {
    for entry in fs::read_dir(dir).with_context(|| format!("list {}", dir.display()))? {
        let entry = entry?;
        let path = entry.path();
        let metadata = fs::symlink_metadata(&path)?;
        if is_reparse_point(&metadata) {
            anyhow::bail!("the package contains a link at {}", path.display());
        }
        if metadata.is_dir() {
            reject_reparse_points(&path)?;
        }
    }
    Ok(())
}

/// Publishes the validated staging directory under the package's name, or
/// the first free numbered alternative. A published directory is never
/// replaced, moved or removed here: if another extractor of the same bytes
/// published first (between this extractor's reuse check and its rename),
/// that copy is the package and this staging directory is simply dropped; a
/// path occupied by anything else is left alone and the next name tried.
fn publish(staging: &Path, root: &Path, identity: &PackageIdentity) -> Result<PathBuf> {
    // A move refused while nothing sits at the destination is a lock on the
    // staging tree (a scanner reading the freshly unpacked files), not an
    // occupied name; it is retried for a while before being reported as such.
    const LOCK_ATTEMPTS: u32 = 40;
    const LOCK_PAUSE: Duration = Duration::from_millis(500);
    let mut locked_attempts = 0;
    for candidate in candidates(root, identity) {
        if holds(&candidate, identity) {
            let _ = fs::remove_dir_all(staging);
            return Ok(candidate);
        }
        loop {
            match move_without_replacing(staging, &candidate) {
                Ok(()) => return Ok(candidate),
                // Taken (at the check, or since): by a concurrent extractor of
                // the same bytes (reuse it) or by something else (next name).
                Err(Occupied) if candidate.exists() => {
                    if holds(&candidate, identity) {
                        let _ = fs::remove_dir_all(staging);
                        return Ok(candidate);
                    }
                    break;
                }
                Err(Occupied) => {
                    locked_attempts += 1;
                    if locked_attempts >= LOCK_ATTEMPTS {
                        anyhow::bail!(
                            "the unpacked package under {} could not be moved into place: Windows refused the move for {} seconds, so another program is probably still reading it",
                            staging.display(),
                            (LOCK_PAUSE * LOCK_ATTEMPTS).as_secs()
                        );
                    }
                    std::thread::sleep(LOCK_PAUSE);
                }
                Err(Failed(error)) => {
                    return Err(error).with_context(|| format!("publish {}", candidate.display()));
                }
            }
        }
    }
    anyhow::bail!(
        "every directory name for {} under {} is occupied",
        identity.directory_name(),
        root.display()
    )
}

use MoveOutcome::{Failed, Occupied};

enum MoveOutcome {
    /// Something already sits at the destination; it was left as it was.
    Occupied,
    Failed(std::io::Error),
}

/// Moves a directory to a path that must not exist yet. `std::fs::rename`
/// replaces an existing file or empty directory on Windows, so publication
/// uses the move without the replace flag: whatever occupies the
/// destination, however briefly it has been there, is never overwritten.
fn move_without_replacing(from: &Path, to: &Path) -> std::result::Result<(), MoveOutcome> {
    use windows::Win32::Foundation::{
        ERROR_ACCESS_DENIED, ERROR_ALREADY_EXISTS, ERROR_FILE_EXISTS, WIN32_ERROR,
    };
    use windows::Win32::Storage::FileSystem::{MOVE_FILE_FLAGS, MoveFileExW};
    use windows::core::HSTRING;
    let (from, to) = (HSTRING::from(from.as_os_str()), HSTRING::from(to.as_os_str()));
    match unsafe { MoveFileExW(&from, &to, MOVE_FILE_FLAGS(0)) } {
        Ok(()) => Ok(()),
        Err(error) => match WIN32_ERROR((error.code().0 & 0xFFFF) as u32) {
            ERROR_ALREADY_EXISTS | ERROR_FILE_EXISTS | ERROR_ACCESS_DENIED => Err(Occupied),
            code => Err(Failed(std::io::Error::from_raw_os_error(code.0 as i32))),
        },
    }
}

fn unique_path(root: &Path, prefix: &str) -> PathBuf {
    let nanos = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_nanos()).unwrap_or_default();
    root.join(format!("{prefix}{}-{nanos:x}", std::process::id()))
}

fn create_unique_dir(root: &Path, prefix: &str) -> Result<PathBuf> {
    for _ in 0..16 {
        let path = unique_path(root, prefix);
        match fs::create_dir(&path) {
            Ok(()) => return Ok(path),
            Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => continue,
            Err(error) => return Err(error).with_context(|| format!("create {}", path.display())),
        }
    }
    anyhow::bail!("could not create a staging directory under {}", root.display())
}

/// The folder under the app data folder where earlier versions of Atlas
/// Manager unpacked packages. Nothing reads what's in it.
const OLD_CACHE: &str = "Playbooks";

/// Removes [`OLD_CACHE`] from `app_data`, the app's own data folder, if it's
/// there, and says whether it was. A junction or symbolic link inside it is
/// removed itself and never followed, so nothing outside `app_data` is
/// touched. Removal goes on past an entry it can't remove, then reports the
/// first failure.
pub fn remove_old_cache(app_data: &Path) -> std::io::Result<bool> {
    let old = app_data.join(OLD_CACHE);
    match fs::symlink_metadata(&old) {
        Ok(_) => remove_tree(&old).map(|()| true),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(false),
        Err(error) => Err(error),
    }
}

/// Removes `path` and, when it's a directory and not a link, everything in it.
fn remove_tree(path: &Path) -> std::io::Result<()> {
    use std::os::windows::fs::MetadataExt;
    use windows::Win32::Storage::FileSystem::FILE_ATTRIBUTE_DIRECTORY;
    let metadata = fs::symlink_metadata(path)?;
    let directory = metadata.file_attributes() & FILE_ATTRIBUTE_DIRECTORY.0 != 0;
    let mut first_error = None;
    if directory && !is_reparse_point(&metadata) {
        for entry in fs::read_dir(path)? {
            if let Err(error) = entry.and_then(|entry| remove_tree(&entry.path())) {
                first_error.get_or_insert(error);
            }
        }
    }
    // A directory link goes with RemoveDirectory, like an empty directory;
    // what it points to stays.
    let removed = if directory { fs::remove_dir(path) } else { fs::remove_file(path) };
    match first_error {
        Some(error) => Err(error),
        None => removed,
    }
}

/// Removes staging directories left by an interrupted run. Recent ones may
/// belong to another running instance.
fn sweep_leftovers(root: &Path) {
    const MIN_AGE: Duration = Duration::from_secs(60 * 60);
    let Ok(entries) = fs::read_dir(root) else { return };
    for entry in entries.flatten() {
        let name = entry.file_name();
        let name = name.to_string_lossy();
        if !name.starts_with(STAGING_PREFIX) {
            continue;
        }
        let old = entry
            .metadata()
            .and_then(|m| m.modified())
            .ok()
            .and_then(|modified| SystemTime::now().duration_since(modified).ok())
            .is_some_and(|age| age > MIN_AGE);
        if old {
            let _ = fs::remove_dir_all(entry.path());
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::services::test_support::{TempDir, package};

    #[test]
    fn browser_artwork_is_optional_and_resolved_from_the_package() {
        let temp = TempDir::new("browser-artwork");
        let manifest = Manifest::builtin();
        let brave =
            manifest.choices.iter().flat_map(|c| &c.options).find(|o| o.id == "browser-brave").unwrap();
        assert_eq!(brave.image.as_deref(), Some("brave"));
        assert_eq!(brave.image_path(temp.path()), None);
        fs::create_dir(temp.path().join("Images")).unwrap();
        let path = temp.path().join("Images/brave.png");
        fs::write(&path, b"artwork").unwrap();
        assert_eq!(brave.image_path(temp.path()), Some(path));
        for name in [None, Some("../brave"), Some(r"C:\brave"), Some("https://example.com/logo"), Some("")] {
            let mut option = brave.clone();
            option.image = name.map(str::to_owned);
            assert_eq!(option.image_path(temp.path()), None);
        }
    }

    fn choice(option: &str, depends_on: Option<&str>) -> Choice {
        Choice {
            id: format!("{option}-choice"),
            kind: ChoiceKind::Multiple,
            description: String::new(),
            learn_more: None,
            depends_on: depends_on.map(str::to_owned),
            options: vec![ChoiceOption {
                id: option.into(),
                label: option.into(),
                image: None,
                default: false,
            }],
        }
    }

    #[test]
    fn dependent_choices_follow_their_parents_in_manifest_order() {
        let choices = [
            choice("a", None),
            choice("b-child", Some("a")),
            choice("c", None),
            choice("d-grandchild", Some("b-child")),
            choice("e-child", Some("a")),
            choice("f-elsewhere", Some("not-on-these-choices")),
        ];
        assert_eq!(follow_parents(&choices, (0..6).collect()), [0, 1, 3, 4, 2, 5]);
        // Choices that depend on each other keep their manifest order, after the rest.
        let looped = [choice("x", Some("y")), choice("y", Some("x")), choice("z", None)];
        assert_eq!(follow_parents(&looped, vec![0, 1, 2]), [2, 0, 1]);
    }

    /// The repository's manifest reads as docs/package-format.md describes it.
    #[test]
    fn the_builtin_manifest_carries_the_vanta_field() {
        let vanta = Manifest::builtin().vanta;
        assert!(!vanta.tools_version.is_empty() && vanta.kit_manifest.ends_with("manifesto.json"));
        let preset = vanta.presets.iter().find(|preset| preset.id == "nathan").unwrap();
        assert!(!preset.label.is_empty() && preset.choices.contains_key("vanta"));
        // O preset não força Defender, mitigações nem proteção contra phishing.
        assert!(!preset.choices.contains_key("defender") && !preset.choices.contains_key("mitigations"));
    }

    /// The directory an elevated install runs from is created protected, holds
    /// exactly the authenticated bytes, and is refused for any other digest.
    #[test]
    fn a_protected_stage_holds_only_the_trusted_bytes() {
        let temp = TempDir::new("package-stage");
        let package = package::write(&temp.path().join("a.vantapkg"), &package::valid("0.6.0"));
        let bytes = fs::read(&package).unwrap();
        let digest = sha256_file(&package).unwrap();
        // Everyone may use the directory here so the test runs unelevated; the ACL itself is checked below.
        let me = StageOwner { pid: std::process::id(), start: 7 };
        let dir = stage_protected(&bytes, &digest, temp.path(), "D:P(A;OICI;FA;;;WD)", &[me]).unwrap();
        assert!(dir.file_name().unwrap().to_string_lossy().starts_with(STAGE_PREFIX));
        assert!(is_extracted(&dir) && front_door(&dir).is_file());
        let wrong = "0".repeat(64);
        assert!(stage_protected(&bytes, &wrong, temp.path(), "D:P(A;OICI;FA;;;WD)", &[me]).is_err());
        assert_eq!(fs::read_dir(temp.path()).unwrap().count(), 2, "a refused stage leaves nothing behind");

        // Recovery removes only a proven, idle stage: not one in use, not one without the marker, not a stranger's name.
        let unmarked = temp.path().join(format!("{STAGE_PREFIX}unmarked"));
        fs::create_dir(&unmarked).unwrap();
        let stranger = temp.path().join("OtherDir");
        fs::create_dir(&stranger).unwrap();
        use crate::services::system::Liveness;
        let proven = |_: &Path| true;
        sweep_stages(temp.path(), |_| Liveness::Alive, proven);
        assert!(dir.exists(), "a stage whose owner is alive is left alone");
        sweep_stages(temp.path(), |_| Liveness::Unknown("denied".into()), proven);
        assert!(dir.exists(), "a stage whose state cannot be read is preserved");
        sweep_stages(temp.path(), |_| Liveness::Ended, |_| false);
        assert!(dir.exists(), "a stage without the protected owner and ACL is not accepted");
        sweep_stages(temp.path(), |owner| if owner.start == 7 { Liveness::Ended } else { Liveness::Alive }, proven);
        assert!(!dir.exists(), "an idle, proven stage with its marker is recovered");
        assert!(unmarked.exists() && stranger.exists(), "nothing unproven is removed");
        // The real classification meets the real sweep: the Manager that started the install is gone (Windows says no
        // such process) while the installer runs in another session, whose query is denied. Denied is not an end.
        use windows::Win32::Foundation::{ERROR_ACCESS_DENIED, ERROR_INVALID_PARAMETER};
        let across_profiles = |owner: StageOwner| {
            if owner.pid == me.pid {
                crate::services::system::liveness_from_open_error(owner.pid, Some(ERROR_INVALID_PARAMETER), || None, true)
            } else {
                crate::services::system::liveness_from_open_error(owner.pid, Some(ERROR_ACCESS_DENIED), || Some(true), true)
            }
        };
        let busy = stage_protected(&bytes, &digest, temp.path(), "D:P(A;OICI;FA;;;WD)", &[me]).unwrap();
        set_stage_owners(&busy, &[me, StageOwner { pid: me.pid + 1, start: 8 }]).unwrap();
        sweep_stages(temp.path(), across_profiles, proven);
        assert!(busy.exists(), "manager gone + installer of another session with a denied query: the stage stays");
        set_stage_owners(&busy, &[me]).unwrap();
        sweep_stages(temp.path(), across_profiles, proven);
        assert!(!busy.exists(), "control: when every owner is proven gone, it is recovered");
        let again = stage_protected(&bytes, &digest, temp.path(), "D:P(A;OICI;FA;;;WD)", &[me]).unwrap();
        remove_stage(&unmarked);
        assert!(unmarked.exists(), "remove_stage needs the marker too");
        remove_stage(&again);
        assert!(!again.exists(), "the exact stage of a finished session goes");
        assert!(set_stage_owners(&temp.path().join("gone"), &[me]).is_err(), "a failed record makes hand_over abort the start");

        let guarded = temp.path().join(format!("{STAGE_PREFIX}acl"));
        crate::services::files::create_protected_dir(&guarded, "D:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)").unwrap();
        assert!(crate::services::files::create_protected_dir(&guarded, "D:P(A;OICI;FA;;;SY)").is_err(), "never reuses an existing directory");
        let listing = std::process::Command::new("icacls").arg(&guarded).output().unwrap();
        let listing = String::from_utf8_lossy(&listing.stdout).to_lowercase();
        // Windows localises the account names; the entries are what count: two, full control, nobody else.
        assert_eq!(listing.matches("(oi)(ci)(f)").count(), 2, "{listing}");
        assert_eq!(listing.matches("(oi)").count(), 2, "{listing}");
    }

    #[test]
    fn a_package_is_opened_only_when_sha256sums_lists_its_digest() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("Vanta.vantapkg");
        std::fs::write(&file, b"bytes").unwrap();
        assert!(verify_checksum(&file).is_err(), "no list");
        let digest = sha256_file(&file).unwrap();
        std::fs::write(
            dir.path().join(SUMS_FILE),
            format!(
                "{digest}  Other.vantapkg
"
            ),
        )
        .unwrap();
        assert!(verify_checksum(&file).is_err(), "not listed");
        std::fs::write(
            dir.path().join(SUMS_FILE),
            format!(
                "{}  Vanta.vantapkg
",
                "0".repeat(64)
            ),
        )
        .unwrap();
        assert!(verify_checksum(&file).is_err(), "wrong digest");
        std::fs::write(
            dir.path().join(SUMS_FILE),
            format!(
                "{digest} *Vanta.vantapkg
"
            ),
        )
        .unwrap();
        verify_checksum(&file).unwrap();
    }

    #[test]
    fn atlas_and_ame_packages_are_refused_with_a_clear_message() {
        for name in ["Vanta-v0.6.0.atlaspkg", "VantaPlaybook.apbx"] {
            let message = check_file_name(Path::new(name)).unwrap_err().to_string();
            assert!(message.contains("not a Vanta package") && message.contains(".vantapkg"), "{message}");
        }
    }

    #[test]
    fn the_builtin_manifest_declares_every_field_the_app_reads() {
        let manifest = Manifest::shipped();
        assert_eq!(
            manifest.version,
            env!("CARGO_PKG_VERSION"),
            "app/Cargo.toml and package/vanta.json agree"
        );
        // 1.0.0 is the first release: it declares what it supports and updates nothing.
        assert_eq!(manifest.version, "1.0.0");
        assert!(!manifest.supported_builds.is_empty() && manifest.updatable_from.is_empty());
        assert!(!manifest.requirements.is_empty());
        let defender = &manifest.choices[0];
        assert_eq!((defender.id.as_str(), defender.kind), ("defender", ChoiceKind::Single));
        assert!(!defender.description.is_empty());
        assert!(defender.learn_more.as_deref().is_some_and(|url| url.starts_with("https://")));
        assert_eq!(manifest.default_options().first().map(String::as_str), Some("defender-enable"));
        let browser = manifest.choices.iter().find(|choice| choice.id == "browser").unwrap();
        assert_eq!(browser.depends_on.as_deref(), Some("install-another-browser"));
        for choice in manifest.choices.iter().filter(|choice| choice.kind == ChoiceKind::Multiple) {
            assert!(choice.options.iter().all(|option| !option.default), "{}", choice.id);
        }
    }

    #[test]
    fn a_manifest_that_breaks_the_format_is_refused() {
        let manifest = |choices: &str| {
            format!(
                r#"{{"schemaVersion": 1, "version": "0.6.0", "minimumManagerVersion": "0.6.0", "supportedBuilds": [], "choices": [{choices}]}}"#
            )
        };
        let single = r#"{"id": "a", "kind": "single", "default": "a-one", "options": [{"id": "a-one", "label": "One"}]}"#;
        let parsed = parse(&manifest(single)).unwrap();
        assert_eq!(parsed.default_options(), ["a-one"]);
        assert_eq!(parsed.estimated_minutes, DEFAULT_ESTIMATED_MINUTES);
        // A byte order mark and fields this app doesn't read are accepted.
        assert!(
            parse(
                &format!("\u{feff}{}", manifest(single)).replace("\"choices\"", "\"later\": 1, \"choices\"")
            )
            .is_ok()
        );
        for (broken, words) in [
            (manifest(single).replace("\"schemaVersion\": 1", "\"schemaVersion\": 0"), "format 0"),
            (manifest(single).replace(r#""minimumManagerVersion": "0.6.0", "#, ""), "minimumManagerVersion"),
            (
                manifest(single)
                    .replace(r#""minimumManagerVersion": "0.6.0""#, r#""minimumManagerVersion": "0.6""#),
                "major.minor.patch",
            ),
            (
                manifest(single)
                    .replace(r#""minimumManagerVersion": "0.6.0""#, r#""minimumManagerVersion": 6"#),
                "expected a string",
            ),
            (manifest(&single.replace(r#""default": "a-one", "#, "")), "no default"),
            (
                manifest(&single.replace(r#""default": "a-one""#, r#""default": "b""#)),
                "isn't one of its options",
            ),
            (manifest(&format!("{single}, {single}")), "choice \"a\" twice"),
            (manifest(r#"{"id": "b", "kind": "multiple", "options": []}"#), "no options"),
            (
                manifest(&format!(r#"{single}, {}"#, single.replace(r#""id": "a","#, r#""id": "b","#))),
                "option \"a-one\" twice",
            ),
            (manifest(&single.replace("single", "radio")), "vanta.json"),
            (r#"<Playbook><Version>0.6.0</Version></Playbook>"#.to_owned(), "vanta.json"),
        ] {
            let error = format!("{:#}", parse(&broken).unwrap_err());
            assert!(error.contains(words), "{broken}: {error}");
        }
        // A link that isn't https:// is not offered.
        let link = single.replace(r#""kind""#, r#""learnMore": "http://example.com", "kind""#);
        assert_eq!(parse(&manifest(&link)).unwrap().choices[0].learn_more, None);
    }

    /// A manifest in the shape a later Atlas Manager might read: `format`,
    /// the Atlas Manager it asks for (any JSON), and a choice this app
    /// can't read.
    fn later_manifest(format: u32, minimum: serde_json::Value) -> String {
        serde_json::json!({
            "schemaVersion": format,
            "version": "0.7.0",
            "minimumManagerVersion": minimum,
            "choices": [{ "id": "speed", "kind": "slider", "range": [1, 10] }],
        })
        .to_string()
    }

    fn outdated(json: &str, manager: &ManagerVersion) -> Option<ManagerOutdated> {
        parse_for(json, manager).unwrap_err().downcast_ref::<ManagerOutdated>().cloned()
    }

    #[test]
    fn a_package_that_needs_a_newer_atlas_manager_is_refused() {
        let manager = ManagerVersion::new("0.6.0", false);
        // Before anything else in it is read, so a change this app can't
        // read doesn't hide the reason.
        assert_eq!(
            outdated(&later_manifest(1, "0.7.0".into()), &manager),
            Some(ManagerOutdated { required: Some("0.7.0".into()), format: None })
        );
        let error = parse_for(&later_manifest(1, "0.6.1".into()), &manager).unwrap_err();
        assert!(error.to_string().contains("Atlas Manager 0.6.1 or later"), "{error:#}");
        // The version this app is, or an earlier one, is met; a tester build
        // meets what the release of its base version meets.
        let current = |minimum: &str| {
            let mut text = package::manifest("0.6.0", &[26300]);
            text = text.replace(
                r#""minimumManagerVersion":"0.6.0""#,
                &format!(r#""minimumManagerVersion":"{minimum}""#),
            );
            assert!(text.contains(minimum), "{text}");
            text
        };
        for minimum in ["0.6.0", "0.5.0", "0.0.1"] {
            assert!(parse_for(&current(minimum), &manager).is_ok(), "{minimum}");
            assert!(parse_for(&current(minimum), &ManagerVersion::new("0.6.0", true)).is_ok(), "{minimum}");
        }
        assert!(outdated(&current("0.6.1"), &ManagerVersion::new("0.6.0", true)).is_some());

        // Nothing of such a package is unpacked.
        let temp = TempDir::new("package-newer-manager");
        let root = temp.path().join("Packages");
        let mut contents = package::valid("0.7.0");
        contents.entries[0].data = current("99.0.0").into_bytes();
        let file = package::write(&temp.path().join("Vanta-v99.vantapkg"), &contents);
        let error = extract_into(&file, &root, |_, _| {}).unwrap_err();
        assert_eq!(
            error.downcast_ref::<ManagerOutdated>(),
            Some(&ManagerOutdated { required: Some("99.0.0".into()), format: None })
        );
        assert!(fs::read_dir(&root).map_or(true, |mut entries| entries.next().is_none()), "nothing unpacked");
    }

    /// A manifest format newer than this app reads is refused as a package
    /// that needs a newer Atlas Manager, naming the version when it can.
    #[test]
    fn a_newer_manifest_format_is_refused_the_same_way() {
        let manager = ManagerVersion::new("0.6.0", false);
        assert_eq!(
            outdated(&later_manifest(2, "0.7.0".into()), &manager),
            Some(ManagerOutdated { required: Some("0.7.0".into()), format: Some(2) })
        );
        // A minimum this app can't read, or one it already meets, isn't named.
        for minimum in
            [serde_json::json!({ "major": 1 }), "0.7".into(), "0.6.0".into(), serde_json::Value::Null]
        {
            assert_eq!(
                outdated(&later_manifest(2, minimum.clone()), &manager),
                Some(ManagerOutdated { required: None, format: Some(2) }),
                "{minimum}"
            );
        }
        let error = parse_for(&later_manifest(3, serde_json::Value::Null), &manager).unwrap_err();
        assert!(error.to_string().contains("format 3"), "{error:#}");
    }

    /// Any file but an `.vantapkg`, and an AME Wizard package under any name,
    /// is refused before anything is unpacked.
    #[test]
    fn only_atlas_packages_are_opened() {
        let temp = TempDir::new("package-kinds");
        let root = temp.path().join("Packages");
        for name in ["Vanta.apbx", "Vanta.zip", "Atlas", "Vanta.vantapkg.apbx"] {
            let file = package::write(&temp.path().join(name), &package::valid("0.6.0"));
            let error = extract_into(&file, &root, |_, _| {}).unwrap_err();
            assert_eq!(
                error.downcast_ref::<NotAPackage>(),
                Some(&NotAPackage { file: name.into() }),
                "{name}"
            );
        }
        let upper = package::write(&temp.path().join("Vanta.VANTAPKG"), &package::valid("0.6.0"));
        assert!(extract_into(&upper, &root, |_, _| {}).is_ok(), "the extension is matched in any case");
        let renamed = package::write(&temp.path().join("renamed.vantapkg"), &package::ame_wizard("0.5.0"));
        let error = extract_into(&renamed, &root, |_, _| {}).unwrap_err();
        assert_eq!(
            error.downcast_ref::<NotAPackage>(),
            Some(&NotAPackage { file: "renamed.vantapkg".into() })
        );
        assert!(package::leftovers(&root).is_empty());
    }

    #[test]
    fn versions_that_name_a_cache_directory_are_accepted() {
        for version in ["0.6.0", " 0.6.0 ", "0.5.0-hotfix", "10.20.30-rc.1", "0.6.0-a-b.c"] {
            assert!(validate_version(version).is_ok(), "{version:?}");
        }
        assert_eq!(validate_version(" 0.6.0 ").unwrap(), "0.6.0");
    }

    #[test]
    fn versions_that_could_escape_the_cache_are_rejected() {
        for version in [
            "",
            " ",
            ".",
            "..",
            "../x",
            "..\\..\\unrelated",
            "C:\\audit-example\\unrelated",
            "/0.6.0",
            "\\0.6.0",
            "0.6.0/x",
            "0.6.0\\x",
            "0.6",
            "0.6.0.1",
            "v0.6.0",
            "0.6.0-",
            "0.6.0-.",
            "0.6.0-x/y",
            "0.6.0-x\\y",
            "0.6.0-a b",
        ] {
            assert!(validate_version(version).is_err(), "{version:?} must be rejected");
        }
    }

    #[test]
    fn entry_components_with_windows_special_syntax_are_rejected() {
        assert!(check_entry_components(Path::new("Executables/a.ps1")).is_ok());
        for bad in ["Executables/file:stream", "CON", "Executables/nul.txt", "Executables/trailing.", "x/aux"]
        {
            assert!(check_entry_components(Path::new(bad)).is_err(), "{bad:?}");
        }
    }

    #[test]
    fn a_valid_package_is_published_under_its_version_and_digest() {
        let temp = TempDir::new("package-valid");
        let package = package::write(&temp.path().join("valid.vantapkg"), &package::valid("0.6.0"));
        let root = temp.path().join("Packages");
        let mut seen = Vec::new();
        let (dir, manifest) = extract_into(&package, &root, |done, total| seen.push((done, total))).unwrap();
        // Progress once per entry, ending at the total.
        let total = seen.last().unwrap().1;
        assert_eq!(seen.len(), total);
        assert_eq!(seen.last(), Some(&(total, total)));
        assert_eq!(manifest.version, "0.6.0");
        let digest = sha256_file(&package).unwrap();
        assert_eq!(dir, plain_path(root.canonicalize().unwrap()).join(format!("0.6.0_{}", &digest[..16])));
        assert!(is_extracted(&dir));
        assert_eq!(identity(&dir), Some(PackageIdentity { version: "0.6.0".into(), sha256: digest }));
        assert!(package::leftovers(&root).is_empty());
    }

    #[test]
    fn an_escaping_version_never_touches_anything_outside_the_cache() {
        let temp = TempDir::new("package-escape");
        let root = temp.path().join("Packages");
        let outside = temp.path().join("unrelated");
        fs::create_dir_all(&outside).unwrap();
        fs::write(outside.join("keep.txt"), "keep").unwrap();
        for version in ["", "..", "..\\..\\unrelated", &outside.display().to_string()] {
            let package = package::write(&temp.path().join("escape.vantapkg"), &package::valid(version));
            let error = extract_into(&package, &root, |_, _| {}).unwrap_err();
            assert!(error.to_string().contains("version"), "{version:?}: {error:#}");
        }
        assert!(outside.join("keep.txt").is_file());
        assert!(package::leftovers(&root).is_empty());
    }

    #[test]
    fn only_versions_before_the_front_door_predate_it() {
        for version in ["0.5.0", "0.5.0-hotfix", "v0.4", "0.3.2"] {
            assert!(predates_front_door(version), "{version}");
        }
        // Suffixes sort after their base release (Atlas tags hotfixes that way).
        for version in ["0.6.0", "0.6.0-rc.1", "v0.7.0", "1.0.0", "next"] {
            assert!(!predates_front_door(version), "{version}");
        }
    }

    #[test]
    fn failed_extractions_keep_the_previous_package_and_leave_nothing_behind() {
        let temp = TempDir::new("package-replace");
        let root = temp.path().join("Packages");
        let good = package::write(&temp.path().join("good.vantapkg"), &package::valid("0.6.0"));
        let (dir, _) = extract_into(&good, &root, |_, _| {}).unwrap();
        let marker = front_door(&dir);
        let before = fs::read(&marker).unwrap();

        // No front door: fails validation after extraction. An older package
        // predates it; a current one is incomplete.
        let old = package::write(&temp.path().join("old.vantapkg"), &package::without_front_door("0.5.0"));
        let error = extract_into(&old, &root, |_, _| {}).unwrap_err();
        assert_eq!(error.downcast_ref::<Unsupported>(), Some(&Unsupported { version: "0.5.0".into() }));
        for version in ["0.6.0", "0.6.1"] {
            let damaged =
                package::write(&temp.path().join("damaged.vantapkg"), &package::without_front_door(version));
            let error = extract_into(&damaged, &root, |_, _| {}).unwrap_err();
            assert_eq!(error.downcast_ref::<Incomplete>(), Some(&Incomplete { version: version.into() }));
        }
        // Traversal entry: fails during extraction.
        let unsafe_entry = package::write(
            &temp.path().join("unsafe.vantapkg"),
            &package::with_entry("0.6.0", "../escape.txt"),
        );
        assert!(extract_into(&unsafe_entry, &root, |_, _| {}).is_err());
        // Corrupt data: fails mid-copy.
        let corrupt = package::write(&temp.path().join("corrupt.vantapkg"), &package::corrupted("0.6.0"));
        assert!(extract_into(&corrupt, &root, |_, _| {}).is_err());

        assert_eq!(fs::read(&marker).unwrap(), before, "the previous package must survive");
        assert!(!temp.path().join("escape.txt").exists());
        assert!(package::leftovers(&root).is_empty());
    }

    /// Two windows can each prepare "0.6.0"; neither may change what the
    /// other has read and is about to run.
    #[test]
    fn different_content_of_the_same_version_never_shares_a_directory() {
        let temp = TempDir::new("package-same");
        let root = temp.path().join("Packages");
        let first =
            package::write(&temp.path().join("a.vantapkg"), &package::valid_with_builds("0.6.0", &[26200]));
        let (dir_a, manifest_a) = extract_into(&first, &root, |_, _| {}).unwrap();
        let door_a = fs::read(front_door(&dir_a)).unwrap();
        let second =
            package::write(&temp.path().join("b.vantapkg"), &package::valid_with_builds("0.6.0", &[99999]));
        let (dir_b, manifest_b) = extract_into(&second, &root, |_, _| {}).unwrap();
        assert_ne!(dir_a, dir_b, "same version, different bytes: different directories");
        assert_eq!(manifest_a.supported_builds, vec![26200]);
        assert_eq!(manifest_b.supported_builds, vec![99999]);
        // What A read still describes what is at A's path.
        assert_eq!(read_manifest(&dir_a).unwrap().supported_builds, vec![26200]);
        assert_eq!(fs::read(front_door(&dir_a)).unwrap(), door_a);
        assert!(package::leftovers(&root).is_empty());

        // The same bytes again are recognised and reused, not re-unpacked.
        fs::write(dir_a.join("marker.txt"), "still here").unwrap();
        let mut reported = Vec::new();
        let (dir_again, _) = extract_into(&first, &root, |done, total| reported.push((done, total))).unwrap();
        assert_eq!(dir_again, dir_a);
        assert!(dir_a.join("marker.txt").is_file(), "a reused directory is not touched");
        assert_eq!(reported.len(), 1, "reuse reports completion once");

        // A damaged copy under the right name is neither reused nor touched:
        // the package is published under the next name.
        fs::remove_file(front_door(&dir_b)).unwrap();
        fs::write(dir_b.join("remnant.txt"), "left behind").unwrap();
        let (dir_b2, _) = extract_into(&second, &root, |_, _| {}).unwrap();
        assert_ne!(dir_b2, dir_b);
        assert_eq!(
            dir_b2,
            plain_path(root.canonicalize().unwrap())
                .join(format!("{}-2", dir_b.file_name().unwrap().to_string_lossy()))
        );
        assert!(is_extracted(&dir_b2));
        assert!(dir_b.join("remnant.txt").is_file(), "the occupied path is left as it was");
        assert_eq!(extract_into(&second, &root, |_, _| {}).unwrap().0, dir_b2);
        assert!(package::leftovers(&root).is_empty());
    }

    /// Security software can quarantine one script from a published copy.
    /// That copy is never handed out again: the same archive is unpacked
    /// under the next name, and the damaged copy is left as it is.
    #[test]
    fn a_published_copy_that_lost_or_changed_a_file_is_unpacked_again() {
        let temp = TempDir::new("package-damaged");
        let root = temp.path().join("Packages");
        let package = package::write(&temp.path().join("a.vantapkg"), &package::valid("0.6.0"));
        let (dir, _) = extract_into(&package, &root, |_, _| {}).unwrap();
        assert!(intact(&dir));
        let files = record(&dir).unwrap().files;
        assert_eq!(files.len(), 3, "every file is recorded: {files:?}");
        assert_eq!(files[package::FRONT_DOOR], fs::metadata(front_door(&dir)).unwrap().len());

        let script = dir.join("Executables/VantaModules/Scripts/Initialize-VantaPowerShell.ps1");
        fs::remove_file(&script).unwrap();
        assert!(is_extracted(&dir) && !intact(&dir), "the front door alone does not make a package");
        let (again, _) = extract_into(&package, &root, |_, _| {}).unwrap();
        assert_eq!(again, PathBuf::from(format!("{}-2", dir.display())));
        assert!(intact(&again) && script.parent().unwrap().is_dir() && !script.exists());
        assert_eq!(extract_into(&package, &root, |_, _| {}).unwrap().0, again, "the new copy is reused");

        // The same size with other bytes is no better: the hash decides.
        let script = again.join("Executables/VantaModules/Scripts/Initialize-VantaPowerShell.ps1");
        let original = fs::read(&script).unwrap();
        let mut forged = original.clone();
        forged[0] ^= 1;
        fs::write(&script, &forged).unwrap();
        assert!(!intact(&again), "same size, other content");
        fs::write(&script, &original).unwrap();
        assert!(intact(&again));

        // A file cut short is no better than a missing one.
        let script = again.join("Executables/VantaModules/Scripts/Initialize-VantaPowerShell.ps1");
        fs::write(&script, "#").unwrap();
        assert!(!intact(&again));
        assert_eq!(
            extract_into(&package, &root, |_, _| {}).unwrap().0,
            PathBuf::from(format!("{}-3", dir.display()))
        );
        assert!(package::leftovers(&root).is_empty());
    }

    /// A directory published before files were recorded can't be checked,
    /// so it is not reused or resumed; its archive is unpacked again.
    #[test]
    fn a_copy_without_a_file_record_is_not_trusted() {
        let temp = TempDir::new("package-unrecorded");
        let root = temp.path().join("Packages");
        let package = package::write(&temp.path().join("a.vantapkg"), &package::valid("0.6.0"));
        let (dir, _) = extract_into(&package, &root, |_, _| {}).unwrap();
        let recorded = identity(&dir).unwrap();
        fs::write(dir.join(IDENTITY_FILE), serde_json::to_string(&recorded).unwrap()).unwrap();
        assert_eq!(identity(&dir), Some(recorded), "the identity still reads");
        assert!(is_extracted(&dir) && !intact(&dir));
        let (again, _) = extract_into(&package, &root, |_, _| {}).unwrap();
        assert_ne!(again, dir);
        assert!(intact(&again));
    }

    /// A path occupied by something that is not the package (a stray file, an
    /// empty directory) is never replaced, whatever `rename` would do.
    #[test]
    fn an_occupied_publication_name_is_left_untouched_and_the_next_used() {
        let temp = TempDir::new("package-occupied");
        let root = temp.path().join("Packages");
        let package = package::write(&temp.path().join("a.vantapkg"), &package::valid("0.6.0"));
        let digest = sha256_file(&package).unwrap();
        let name = format!("0.6.0_{}", &digest[..16]);
        fs::create_dir_all(&root).unwrap();
        // A regular file with content sits where the package would go.
        fs::write(root.join(&name), b"preserve me").unwrap();
        let (published, _) = extract_into(&package, &root, |_, _| {}).unwrap();
        assert_eq!(published, plain_path(root.canonicalize().unwrap()).join(format!("{name}-2")));
        assert_eq!(fs::read(root.join(&name)).unwrap(), b"preserve me");
        assert!(is_extracted(&published));

        // An empty directory is not a package either, and stays empty.
        let temp = TempDir::new("package-occupied-dir");
        let root = temp.path().join("Packages");
        let package = package::write(&temp.path().join("a.vantapkg"), &package::valid("0.6.0"));
        // A fresh archive carries fresh timestamps, so its digest and name differ.
        let name = format!("0.6.0_{}", &sha256_file(&package).unwrap()[..16]);
        fs::create_dir_all(root.join(&name)).unwrap();
        let (published, _) = extract_into(&package, &root, |_, _| {}).unwrap();
        assert_eq!(published, plain_path(root.canonicalize().unwrap()).join(format!("{name}-2")));
        assert_eq!(fs::read_dir(root.join(&name)).unwrap().count(), 0, "the empty directory is untouched");
        // The move itself refuses an occupied destination of either kind.
        let staging = temp.path().join("staging");
        fs::create_dir_all(&staging).unwrap();
        assert!(matches!(move_without_replacing(&staging, &root.join(&name)), Err(Occupied)));
        assert!(matches!(move_without_replacing(&staging, &published), Err(Occupied)));
        let file = temp.path().join("file.txt");
        fs::write(&file, "x").unwrap();
        assert!(matches!(move_without_replacing(&staging, &file), Err(Occupied)));
        assert!(staging.is_dir(), "a refused move leaves the source in place");
        assert!(package::leftovers(&root).is_empty());
    }

    /// Two extractors of the same archive both pass the reuse check before
    /// either has published. The second must adopt the first's directory,
    /// not replace it.
    #[test]
    fn a_concurrent_extractor_of_the_same_bytes_reuses_the_winner_and_replaces_nothing() {
        let temp = TempDir::new("package-concurrent");
        let root = temp.path().join("Packages");
        let package = package::write(&temp.path().join("a.vantapkg"), &package::valid("0.6.0"));
        // The second extractor's staging, prepared before the first publishes.
        let scratch = temp.path().join("Scratch");
        let (staged, _) = extract_into(&package, &scratch, |_, _| {}).unwrap();
        fs::create_dir_all(&root).unwrap();
        let root = plain_path(root.canonicalize().unwrap());
        let staging = root.join(format!("{STAGING_PREFIX}0.6.0-test"));
        fs::rename(&staged, &staging).unwrap();
        // The first extractor publishes and its caller starts using the path.
        let (winner, _) = extract_into(&package, &root, |_, _| {}).unwrap();
        fs::write(winner.join("in-use.txt"), "held by the first caller").unwrap();
        let door_before = fs::metadata(front_door(&winner)).unwrap().modified().unwrap();
        // The second extractor now publishes its finished staging.
        let identity = identity(&winner).unwrap();
        let published = publish(&staging, &root, &identity).unwrap();
        assert_eq!(published, winner, "the loser adopts the winner's directory");
        assert!(winner.join("in-use.txt").is_file(), "nothing in the winner's directory was replaced");
        assert_eq!(fs::metadata(front_door(&winner)).unwrap().modified().unwrap(), door_before);
        assert!(!staging.exists(), "only the loser's private staging goes");
        assert!(package::leftovers(&root).is_empty());
    }

    #[test]
    fn a_move_refused_by_an_open_handle_is_retried_rather_than_called_occupied() {
        let temp = TempDir::new("package-locked");
        let package = package::write(&temp.path().join("valid.vantapkg"), &package::valid("0.6.0"));
        let root = temp.path().join("Packages");
        fs::create_dir_all(&root).unwrap();
        let staging = create_unique_dir(&root, &format!("{STAGING_PREFIX}0.6.0-")).unwrap();
        // A tree that would publish, with one of its files held open the way a
        // scanner holds a freshly written file.
        fs::write(staging.join("scanned.txt"), "contents").unwrap();
        let held = fs::File::open(staging.join("scanned.txt")).unwrap();
        let identity = PackageIdentity { version: "0.6.0".into(), sha256: sha256_file(&package).unwrap() };
        let expected = root.join(identity.directory_name());
        assert!(
            matches!(move_without_replacing(&staging, &expected), Err(Occupied)),
            "a held file refuses the move"
        );
        let publisher = {
            let (staging, root, identity) = (staging.clone(), root.clone(), identity.clone());
            std::thread::spawn(move || publish(&staging, &root, &identity))
        };
        std::thread::sleep(Duration::from_millis(1200));
        drop(held);
        let published = publisher.join().unwrap().unwrap();
        assert_eq!(published, expected);
        assert!(published.join("scanned.txt").is_file());
    }

    /// Creates a directory junction at `link` to `target`, as any user can.
    fn junction(link: &Path, target: &Path) {
        let status = std::process::Command::new("cmd")
            .args(["/d", "/c", "mklink", "/J"])
            .arg(link)
            .arg(target)
            .stdout(std::process::Stdio::null())
            .status()
            .unwrap();
        assert!(status.success(), "create the junction {}", link.display());
    }

    /// The old package folder goes, with everything really in it, and
    /// nothing else: not the current packages, and not what a junction
    /// inside it, or the folder itself as a junction, points to.
    #[test]
    fn the_old_package_folder_is_removed_without_leaving_the_app_data_folder() {
        let temp = TempDir::new("package-old-cache");
        let app_data = temp.path().join("App");
        let outside = temp.path().join("Outside");
        fs::create_dir_all(outside.join("nested")).unwrap();
        fs::write(outside.join("nested/keep.txt"), "keep").unwrap();
        let current = package::write(&temp.path().join("a.vantapkg"), &package::valid("0.6.0"));
        let (published, _) = extract_into(&current, &app_data.join("Packages"), |_, _| {}).unwrap();

        assert!(!remove_old_cache(&app_data).unwrap(), "nothing to remove");
        let old = app_data.join(OLD_CACHE);
        fs::create_dir_all(old.join("0.6.0/Executables/VantaModules")).unwrap();
        fs::write(old.join("0.6.0/vanta.json"), "{}").unwrap();
        fs::write(old.join("0.6.0/Executables/VantaModules/a.ps1"), "#").unwrap();
        junction(&old.join("0.6.0").join("Executables").join("linked"), &outside);
        assert!(old.join("0.6.0/Executables/linked/nested/keep.txt").is_file(), "the junction resolves");
        assert!(remove_old_cache(&app_data).unwrap());
        assert!(!old.exists());
        assert!(outside.join("nested/keep.txt").is_file(), "what the junction points to stays");
        assert!(intact(&published), "the current packages stay");

        // The old folder itself a junction: only the link goes.
        junction(&old, &outside);
        assert!(remove_old_cache(&app_data).unwrap());
        assert!(fs::symlink_metadata(&old).is_err());
        assert!(outside.join("nested/keep.txt").is_file());
        assert!(!remove_old_cache(&app_data).unwrap());
    }

    #[test]
    fn plain_path_drops_only_the_verbatim_prefix() {
        assert_eq!(plain_path(PathBuf::from(r"\\?\C:\Users\x")), PathBuf::from(r"C:\Users\x"));
        assert_eq!(plain_path(PathBuf::from(r"\\?\UNC\server\share\x")), PathBuf::from(r"\\server\share\x"));
        assert_eq!(plain_path(PathBuf::from(r"C:\Users\x")), PathBuf::from(r"C:\Users\x"));
        assert_eq!(plain_path(PathBuf::from(r"\\server\share")), PathBuf::from(r"\\server\share"));
        // What PowerShell receives must not start with the prefix.
        let temp = TempDir::new("package-plain");
        let package = package::write(&temp.path().join("valid.vantapkg"), &package::valid("0.6.0"));
        let (dir, _) = extract_into(&package, &temp.path().join("Packages"), |_, _| {}).unwrap();
        assert!(!dir.to_string_lossy().starts_with(r"\\?\"), "{}", dir.display());
    }
}
