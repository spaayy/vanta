#!/usr/bin/env bash
# Builds one release-candidate ZIP for testers on Linux: the production Vanta package,
# the Vanta Manager executable that carries it, notices and a tester note.
# Nothing is tagged or published; the maintainer posts the ZIP by hand.
#
#   tools/release/build-rc.sh --rc N [--allow-dirty] [--edition pessoal|publica]
#
# The package is built by vanta/tools/Build-VantaPackage.ps1 for the edition (default publica: nothing of Nathan's PC)
# and the Manager carries exactly those bytes (VANTA_EMBED_PACKAGE, VANTA_RELEASE_ID). On Windows,
# vanta/tools/Build-VantaEdition.ps1 does the same for both editions and proves the bytes are inside the exe.
#
# Output: artifacts/rc/<version>-rc.N-<edition>/ (one directory per edition) with the ZIP, the .vantapkg and SHA256SUMS.txt.
# A failed run leaves a previous candidate in place.
set -euo pipefail

rc=''
edition='publica'
allow_dirty=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --rc) rc="${2:-}"; shift 2 ;;
        --allow-dirty) allow_dirty=1; shift ;;
        --edition) edition="${2:-}"; shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done
[[ "$rc" =~ ^[1-9][0-9]*$ ]] || { echo 'Pass --rc N with a positive integer.' >&2; exit 2; }
case "$edition" in
    pessoal) edition_name='Pessoal'; tools_name='VantaTools.exe' ;;
    publica) edition_name='Publica'; tools_name='VantaToolsPublico.exe' ;;
    *) echo 'Pass --edition pessoal or publica.' >&2; exit 2 ;;
esac
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
if [[ "$root" == *' '* ]]; then
    echo 'The checkout path must not contain spaces.' >&2
    exit 1
fi
if [[ ${RUSTFLAGS+x} || ${CARGO_ENCODED_RUSTFLAGS+x} ]]; then
    echo 'Unset RUSTFLAGS and CARGO_ENCODED_RUSTFLAGS; the build sets its own (Get-VantaRustFlags.ps1).' >&2
    exit 1
fi
for tool in pwsh cargo git tar sha256sum 7z; do
    command -v "$tool" >/dev/null || { echo "Required tool not found: $tool" >&2; exit 1; }
done
cargo xwin --version >/dev/null 2>&1 || { echo 'cargo-xwin is missing; run tools/release/setup-linux.sh.' >&2; exit 1; }

cd "$root"
dirty=0
if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
    dirty=1
fi
if [[ $dirty -eq 1 && $allow_dirty -eq 0 ]]; then
    echo 'The tree has uncommitted changes. Commit them or pass --allow-dirty for a non-publishable build.' >&2
    exit 1
fi
commit="$(git rev-parse --short HEAD)"
# Matches the commit build.rs records for About and diagnostics.
if [[ $dirty -eq 1 ]]; then
    commit+='-dirty'
fi
# PowerShell, which the build needs anyway, reads the manifest: one line each for the
# version, the supported builds and the versions this one updates. The lists come as
# "a, b and c" for README-RC.txt, and every value is checked to be safe in a sed replacement.
manifest="$(pwsh -NoProfile -NonInteractive -Command '
    $ErrorActionPreference = "Stop"
    $manifest = Get-Content -LiteralPath "package/atlas.json" -Raw | ConvertFrom-Json
    function Join-Item([string[]]$Item) {
        if ($Item.Count -eq 0) { throw "atlas.json has an empty list." }
        if ($Item.Count -eq 1) { return $Item[0] }
        return ($Item[0..($Item.Count - 2)] -join ", ") + " and " + $Item[-1]
    }
    $versionPattern = "^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$"
    $version = [string]$manifest.version
    if ($version -cnotmatch $versionPattern) { throw "atlas.json has no valid version." }
    $builds = @($manifest.supportedBuilds | ForEach-Object {
            if ("$($_.build)" -cnotmatch "^[0-9]+$" -or "$($_.release)" -cnotmatch "^[0-9A-Za-z.]+$") {
                throw "atlas.json has a supportedBuilds entry without a numeric build and a release name."
            }
            "$($_.build) ($($_.release))"
        })
    $sources = @($manifest.updatableFrom | ForEach-Object {
            if ("$_" -cnotmatch $versionPattern) { throw "atlas.json has an updatableFrom entry that is not a version." }
            "$_"
        })
    $version
    Join-Item $builds
    Join-Item $sources
')" || { echo 'Cannot read version, supportedBuilds and updatableFrom from package/atlas.json.' >&2; exit 1; }
mapfile -t manifest_fields <<<"${manifest//$'\r'/}"
if [[ ${#manifest_fields[@]} -ne 3 ]]; then
    echo 'Cannot read version, supportedBuilds and updatableFrom from package/atlas.json.' >&2
    exit 1
fi
version="${manifest_fields[0]}"
supported_builds="${manifest_fields[1]}"
updatable_from="${manifest_fields[2]}"
# build.rs refuses a mismatch too, but only after the Vanta package is built and verified.
cargo_version="$(sed -n '/^\[package\]/,/^\[/s/^version *= *"\([^"]*\)".*/\1/p' app/Cargo.toml | head -1)"
if [[ "$cargo_version" != "$version" ]]; then
    echo "app/Cargo.toml is at ${cargo_version:-no version} but package/atlas.json is at $version; bump both." >&2
    exit 1
fi
rc_id="$version-rc.$rc"
final="$root/artifacts/rc/$rc_id-$edition"
work="$root/artifacts/rc/.$rc_id-$edition.building"
rm -rf "$work"
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT

echo "== Vanta $rc_id from $commit"

# 1. The executables and the production Vanta package of the edition. Build-VantaPackage.ps1 builds the package
#    from the checkout (committed tree: use a clean checkout; --allow-dirty marks the build as non-publishable).
export XWIN_CACHE_DIR="$root/artifacts/xwin"
export XWIN_ACCEPT_LICENSE=1
export XWIN_SDK_VERSION="${XWIN_SDK_VERSION:-10.0.26100}"
export XWIN_CRT_VERSION="${XWIN_CRT_VERSION:-14.44.17.14}"
target_dir="app/target/x86_64-pc-windows-msvc/release"
# Static CRT and no host paths in the binaries (see Get-VantaRustFlags.ps1). Build-VantaPackage.ps1 skips the
# Windows-only dumpbin check on Linux, so nothing here needs Assert-StaticCrt.ps1 or dumpbin.exe.
export CARGO_ENCODED_RUSTFLAGS
CARGO_ENCODED_RUSTFLAGS="$(pwsh -NoProfile -File vanta/tools/Get-VantaRustFlags.ps1 -Repo "$root")"
(
    cd app
    pwsh -NoProfile -File tools/Export-DependencyNotices.ps1 -Check
    cargo xwin build --release --locked --target x86_64-pc-windows-msvc \
        --bin VantaManager --bin VantaTools --bin VantaToolsPublico
)
package_name="Vanta-$([[ "$edition" == pessoal ]] && echo pessoal || echo publico).vantapkg"
pwsh -NoProfile -File vanta/tools/Build-VantaPackage.ps1 -Edition "$edition_name" -OutputPath "$work" \
    -ToolsExe "$target_dir/$tools_name" -ManagerExe "$target_dir/VantaManager.exe"
[[ -f "$work/$package_name" ]] || { echo "Missing $work/$package_name" >&2; exit 1; }

# 2. The executable that carries exactly those bytes.
export VANTA_EMBED_PACKAGE="$work/$package_name"
export VANTA_RELEASE_ID="$rc_id"
(
    cd app
    cargo xwin build --release --locked --target x86_64-pc-windows-msvc --features embedded-package --bin VantaManager
)
exe="$target_dir/VantaManager.exe"
[[ -f "$exe" ]] || { echo "Missing $exe" >&2; exit 1; }

# 3. The ZIP: executable, standalone Vanta package, notices and the tester note.
stage="$work/zip"
mkdir -p "$stage"
cp "$exe" "$stage/VantaManager.exe"
cp "$work/$package_name" "$stage/"
cp LICENSE "$stage/LICENSE.txt"
cp app/licenses/THIRD-PARTY-NOTICES.txt "$stage/"
cp app/vendor/gpui-pre/LICENSE-APACHE "$stage/GPUI-LICENSE-APACHE.txt"
sed -e "s/@RC_ID@/$rc_id/g" -e "s/@COMMIT@/$commit/g" -e "s/@SUPPORTED_BUILDS@/$supported_builds/g" \
    -e "s/@UPDATABLE_FROM@/$updatable_from/g" \
    tools/release/README-RC.txt >"$stage/README-RC.txt"
if grep -q '@[A-Z_][A-Z_]*@' "$stage/README-RC.txt"; then
    echo 'README-RC.txt has a placeholder that build-rc.sh does not fill in.' >&2
    exit 1
fi
zip_name="VantaManager-$rc_id-$edition-windows-x64.zip"
(cd "$stage" && 7z a -tzip -bso0 -bsp0 "../$zip_name" .)

# 4. Checksums for what testers receive, in the release workflow's format.
(
    cd "$work"
    cp "zip/VantaManager.exe" "VantaManager.exe"
    sha256sum "$zip_name" "$package_name" "VantaManager.exe" | tee SHA256SUMS.txt
    rm -f "VantaManager.exe"
    rm -rf zip source
)

# 5. Publish the finished directory in one move.
rm -rf "$final"
mv "$work" "$final"
trap - EXIT
echo
echo "== Built Vanta $rc_id"
echo "commit:   $commit"
echo "rustc:    $(cd app && rustc --version)"
echo "cargo-xwin: $(cargo xwin --version)"
echo "sdk/crt:  $XWIN_SDK_VERSION / $XWIN_CRT_VERSION"
echo "output:   $final"
cat "$final/SHA256SUMS.txt"
