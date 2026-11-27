fn main() {
    let rc_id = embedded_package();
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("windows") {
        println!("cargo:rerun-if-changed=resources/vanta.ico");
        // File Properties show the RC id on a tester build. The numeric
        // FILEVERSION/PRODUCTVERSION take the Cargo version, with the fourth
        // component set to the candidate number (1.0.0-rc.2 -> 1,0,0,2) so
        // two candidates' executables differ in Explorer and in installers
        // that compare binary versions; a stable build is x,y,z,0.
        let version =
            rc_id.clone().unwrap_or_else(|| std::env::var("CARGO_PKG_VERSION").expect("package version"));
        let numeric_version = ["MAJOR", "MINOR", "PATCH"]
            .map(|part| std::env::var(format!("CARGO_PKG_VERSION_{part}")).unwrap())
            .join(",")
            + &format!(",{}", rc_id.as_deref().map_or(0, rc_number));
        let resources = std::path::Path::new(&std::env::var("CARGO_MANIFEST_DIR").unwrap()).join("resources");
        let path_of = |name: &str| resources.join(name).to_string_lossy().replace('\\', "/");
        // One resource per binary: its own metadata and its own process manifest.
        // VantaManager asks for nothing (it raises itself); VantaTools asks for
        // administrator (and so does VantaToolsPublico, with the same manifest), so any
        // way of opening them raises UAC instead of failing on the system tweaks.
        for (bin, rc_name, manifest) in [
            ("VantaManager", "vanta.rc", "vanta-manager.manifest.xml"),
            ("VantaTools", "vanta-tools.rc", "vanta-tools.manifest.xml"),
            ("VantaToolsPublico", "vanta-tools-publico.rc", "vanta-tools.manifest.xml"),
        ] {
            println!("cargo:rerun-if-changed=resources/{rc_name}");
            println!("cargo:rerun-if-changed=resources/{manifest}");
            let resource = std::fs::read_to_string(resources.join(rc_name))
                .expect("read app resources")
                .replace("@ICON@", &path_of("vanta.ico"))
                .replace("@MANIFEST@", &path_of(manifest))
                .replace("@NUMERIC_VERSION@", &numeric_version)
                .replace("@VERSION@", &version);
            let resource_path = std::path::Path::new(&std::env::var("OUT_DIR").unwrap()).join(rc_name);
            std::fs::write(&resource_path, resource).expect("write app resources");
            embed_resource::compile_for(&resource_path, [bin], embed_resource::NONE)
                .manifest_required()
                .unwrap_or_else(|error| panic!("embed the {bin} resources: {error}"));
        }
    }
}

/// With the `embedded-package` feature, bakes the Vanta package (`.vantapkg`) named by
/// `VANTA_EMBED_PACKAGE` and the id in `VANTA_RELEASE_ID` into the executable and
/// returns the id. Either missing fails the build: an embedded build must never
/// quietly become a plain one. The id is the plain version for a release, `<version>-rc.N` for a candidate, or
/// `<version>` for the public release, `<version>-pessoal` for the personal build.
fn embedded_package() -> Option<String> {
    std::env::var_os("CARGO_FEATURE_EMBEDDED_PACKAGE")?;
    println!("cargo:rerun-if-env-changed=VANTA_EMBED_PACKAGE");
    println!("cargo:rerun-if-env-changed=VANTA_RELEASE_ID");
    let rc_id = std::env::var("VANTA_RELEASE_ID").ok().filter(|id| !id.trim().is_empty());
    let Some(rc_id) = rc_id else {
        panic!("embedded-package builds need VANTA_RELEASE_ID, a semantic version such as 1.0.0 or 1.0.0-rc.1")
    };
    assert!(is_semver(&rc_id), "VANTA_RELEASE_ID {rc_id:?} is not a semantic version (MAJOR.MINOR.PATCH[-pre.release])");
    // The version resource's numbers, Settings and diagnostics take Cargo's version. An
    // id for another version would give the executable two versions.
    let version = std::env::var("CARGO_PKG_VERSION").expect("package version");
    assert!(
        rc_id == version || (rc_id.starts_with(&format!("{version}-")) && rc_id.len() > version.len() + 1),
        "VANTA_RELEASE_ID {rc_id:?} must be {version} or start with {version}-, the version in app/Cargo.toml"
    );
    let package = std::env::var_os("VANTA_EMBED_PACKAGE")
        .map(std::path::PathBuf::from)
        .and_then(|path| path.canonicalize().ok())
        .filter(|path| path.is_file());
    let Some(package) = package else {
        panic!("embedded-package builds need VANTA_EMBED_PACKAGE to name a readable Vanta package")
    };
    let extension = package.extension().unwrap_or_default();
    assert!(
        extension.eq_ignore_ascii_case("vantapkg"),
        "VANTA_EMBED_PACKAGE must name a Vanta package (.vantapkg), not {}",
        package.display()
    );
    println!("cargo:rerun-if-changed={}", package.display());
    let root = std::path::Path::new(&std::env::var("CARGO_MANIFEST_DIR").unwrap()).join("..");
    println!("cargo:rerun-if-changed={}", root.join(".git/HEAD").display());
    println!("cargo:rerun-if-changed={}", root.join(".git/index").display());
    println!("cargo:rustc-env=VANTA_SOURCE_COMMIT={}", source_commit(&root));
    let generated = format!(
        "pub const RELEASE_ID: &str = {rc_id:?};\npub static PACKAGE: &[u8] = include_bytes!({:?});\n",
        package.to_string_lossy().replace('\\', "/")
    );
    let out = std::path::Path::new(&std::env::var("OUT_DIR").unwrap()).join("embedded.rs");
    std::fs::write(&out, generated).expect("write the embedded package binding");
    Some(rc_id)
}

/// Strict semantic versioning: `MAJOR.MINOR.PATCH` without leading zeros, then an optional `-` and dot-separated
/// pre-release identifiers of `[0-9A-Za-z-]` (numeric ones without leading zeros). Build metadata (`+`) isn't accepted.
fn is_semver(id: &str) -> bool {
    let (core, pre) = match id.split_once('-') {
        Some((core, pre)) => (core, Some(pre)),
        None => (id, None),
    };
    let numeric = |part: &str| !part.is_empty() && part.bytes().all(|b| b.is_ascii_digit()) && (part == "0" || !part.starts_with('0'));
    let parts: Vec<&str> = core.split('.').collect();
    if parts.len() != 3 || !parts.iter().all(|part| numeric(part)) {
        return false;
    }
    pre.is_none_or(|pre| {
        pre.split('.').all(|identifier| {
            !identifier.is_empty()
                && identifier.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-')
                && (!identifier.bytes().all(|b| b.is_ascii_digit()) || numeric(identifier))
        })
    })
}

/// The candidate number of an RC id such as `0.6.0-rc.12`, for the version
/// resource's fourth component; any other id (`1.0.0`, `1.0.0-pessoal`) has none, so 0.
/// A candidate number the 16-bit field cannot hold fails the build rather than
/// misnumbering the executable.
fn rc_number(rc_id: &str) -> u16 {
    let Some((_, suffix)) = rc_id.split_once("-rc.") else { return 0 };
    let number: u16 =
        suffix.parse().ok().filter(|number| *number > 0 && !suffix.starts_with('0')).unwrap_or_else(|| {
            panic!("VANTA_RELEASE_ID {rc_id:?} needs a candidate number from 1 to 65535 after -rc.")
        });
    number
}

/// Short commit, with `-dirty` when the tree has changes; `unknown` without Git.
fn source_commit(root: &std::path::Path) -> String {
    let git = |args: &[&str]| {
        std::process::Command::new("git")
            .args(args)
            .current_dir(root)
            .output()
            .ok()
            .filter(|output| output.status.success())
            .map(|output| String::from_utf8_lossy(&output.stdout).trim().to_owned())
    };
    match git(&["rev-parse", "--short", "HEAD"]) {
        Some(commit) => match git(&["status", "--porcelain", "--untracked-files=no"]) {
            Some(status) if status.is_empty() => commit,
            _ => format!("{commit}-dirty"),
        },
        None => "unknown".to_owned(),
    }
}
