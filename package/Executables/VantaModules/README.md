# Binary inventory

This file lists every executable, archive and Windows component package in the Vanta package, with its SHA-256 hash, source and licence.
It's for reviewers who verify those binaries and for maintainers who replace one.

Every `.exe`, `.dll`, `.cab` and `.zip` file under `package/Executables` has an entry here.
No test checks this, so compare the list with the files whenever you add, replace or remove a binary.

Paths start at `package/Executables`.
Hashes are upper-case SHA-256, as `Get-FileHash` prints them; on Linux, upper-case the output of `sha256sum`.

On an installed PC, `%windir%\VantaModules\LICENSE` holds the project licence (GPL-3.0; Vanta is based on AtlasOS 0.6.0, whose credit stays), and the Licenses phase writes the notices to `C:\Vanta\Licenses`: `LICENSE`, `NOTICE`, `THIRD-PARTY-NOTICES.txt`, `Geist-OFL.txt` and this file as `BINARY-INVENTORY.md`.
Third-party components keep their own licences, listed with each entry.
The source of the GPL programs below that Vanta didn't write (ViVe, Multi-Choice) is in `Vanta-<version>-third-party-sources.zip`, offered in the same place as the binaries, at no extra charge (GPL-3.0 section 6(d)); `tools/release/Get-ThirdPartySources.ps1` builds it from the commits pinned in `tools/release/third-party-sources.lock.json`.

## Multi-Choice

| Path | SHA-256 |
| --- | --- |
| `VantaModules/Tools/multichoice.exe` | `6AB2FF0163AFE0FAC4E7506F9A63293421A1880076944339700A59A06578927D` |

- Version: v0.4
- Source: the [multichoice-v0.4 release](https://github.com/Atlas-OS/utilities/releases/download/multichoice-v0.4/multichoice-compressed.exe) of [Atlas-OS/utilities](https://github.com/Atlas-OS/utilities), renamed from `multichoice-compressed.exe`
- Licence: [GNU General Public License v3.0](https://github.com/Atlas-OS/utilities/blob/17ec216d607a439ba4b90977bfebd597db1d5799/LICENSE), at commit `17ec216d607a439ba4b90977bfebd597db1d5799`.
  The `multichoice-v0.4` tag has no `LICENSE` file; that commit adds the GPL-3.0 and its `multichoice/` tree (`42ed56e924739bebddddb07316b18e827cd1a872`) is identical to the tag's, which `Get-ThirdPartySources.ps1` proves before it builds the source archive.
  The author named in the tag is `spddl`; the Go modules linked in (Walk, win, x/sys, govaluate) and the Go runtime have their notices in `THIRD-PARTY-NOTICES.txt`.
- Binary: the official compressed executable of that release, not a Vanta build; its source tree is identical to the one in `Vanta-<version>-third-party-sources.zip`, with `go.mod`, `go.sum` and `vendor/` so it builds offline (`go build -mod=vendor`).
- Used by: the `SendToContextMenu` toggle, which shows its Send To choice dialog with this tool (`Vanta.Shell/Domain/SendTo.ps1`)

## SetTimerResolution and MeasureSleep

| Path | SHA-256 |
| --- | --- |
| `VantaModules/Tools/SetTimerResolution.exe` | `67592C7DA1728E2084A5F1E17AA4312E49F3D48DF21ADB0844E66259D4489EBD` |
| `VantaDesktop/3. General Configuration/Timer Resolution/! MeasureSleep.exe` | `952C19EA42CC8733BCCC07624E952266054FFB6AB50A80090B60A76C3A71E7E4` |
| `VantaModules/Sources/TimerResolution-source.zip` | `0C546BC247E6D66AA94048DFB161F45837E0DDB9CD591BC1C28F0536234B2306` |

- Version: TimerResolution v1.0.0 with Atlas patches.
  SetTimerResolution comes from [commit edf6102](https://github.com/valleyofdoom/TimerResolution/tree/edf6102dbe9cd84fd973f00b0add44d3e9d62801) and MeasureSleep from [commit 79b5c6a](https://github.com/valleyofdoom/TimerResolution/tree/79b5c6a8b2015cd1376b60753cd2c9bd5fe1326f).
- Source: Vanta builds both executables with the [timer build recipe](../../../tools/timer/README.md).
  `tools/timer/accepted-build.json` records the accepted source, compiler and output hashes.
  `TimerResolution-source.zip` is the corresponding source for both: the patched C++, the args header, the patches, the pinned inputs, the build recipe and both licence texts.
- Licence: GNU General Public License v3.0.
  The header-only [args 6.4.6](https://github.com/Taywee/args/tree/e3e6e46699f1ce487a42fd64838f53daeb5aa89b) library uses the MIT License.
- Used by: the `TimerResolution` toggle, whose Enable state registers the `Force Timer Resolution` scheduled task that runs SetTimerResolution.
  MeasureSleep sits in the Vanta desktop folder for people to run themselves.

## ViVeTool

| Path | SHA-256 |
| --- | --- |
| `VantaModules/Tools/ViVeTool-v0.3.3.zip` | `59D1E792EDCC001A319C16435A03D203975BF50EB38BD55CA34370900606F9F0` |
| `VantaModules/Tools/ViVeTool-v0.3.3-ARM64CLR.zip` | `37708C95C5053539CD068460E28E565D6B25A33C87F09B6B91A4F82A18E30132` |

- Version: v0.3.3
- Source: the [x64 archive](https://github.com/thebookisclosed/ViVe/releases/download/v0.3.3/ViVeTool-v0.3.3.zip) and the [Arm64 archive](https://github.com/thebookisclosed/ViVe/releases/download/v0.3.3/ViVeTool-v0.3.3-ARM64CLR.zip) from the v0.3.3 release of [thebookisclosed/ViVe](https://github.com/thebookisclosed/ViVe)
- Licence: [GNU General Public License v3.0](https://github.com/thebookisclosed/ViVe/blob/97195a452776534c2c5973afd5b70e4ac9d3e3a9/LICENSE), at the `v0.3.3` tag commit `97195a452776534c2c5973afd5b70e4ac9d3e3a9`.
  The corresponding source of that commit is in `Vanta-<version>-third-party-sources.zip`.
- Contents of each archive: `ViVeTool.exe`, `Albacore.ViVe.dll`, `FeatureDictionary.pfs` and `Newtonsoft.Json.dll` 13.0.3 (SHA-256 `E1E27AF7B07EEEDF5CE71A9255F0422816A6FC5849A483C6714E1B472044FA9D`, identical in both archives, product version `13.0.3+0a2e291c0d9c0c7675d445703e51750363a549ef`).
  Newtonsoft.Json is [MIT-licensed](https://github.com/JamesNK/Newtonsoft.Json/blob/0a2e291c0d9c0c7675d445703e51750363a549ef/LICENSE.md) by James Newton-King; its full text is in `THIRD-PARTY-NOTICES.txt`.
- Used by: `Scripts/Operations/Update-ClientCbs.ps1`, which the "Modify Client.CBS" install tweak runs to turn off Windows feature IDs

## StoreFixer

| Path | SHA-256 |
| --- | --- |
| `VantaModules/Tools/StoreFixer.exe` | `A87F5E85FA2BF1461FBB0DEB1070C184C46F0924EE805F3D0F0D42D3504F67FA` |

- Version: 0.0.4
- Source: the [StoreFixer 0.0.4 release asset](https://github.com/TheyCreeper/StoreFixer/releases/download/0.0.4/StoreFixer.exe) from [TheyCreeper/StoreFixer](https://github.com/TheyCreeper/StoreFixer), byte-identical to the file in the Vanta package
- Licence: [CC0 1.0 Universal](https://github.com/TheyCreeper/StoreFixer/blob/0.0.4/LICENSE)
- Used by: the `FixMSStoreIssues` troubleshooting toggle

## CBS component packages

The public edition carries **no** CBS package, and the repository holds none: a self-signed `CN=Vanta CBS Packages, O=Vanta` build was refused by Windows (`0x800b0110`), and Vanta never turns on test signing.

- Version: 5.0.0.0, the package version in each file name. No ARM64 CAB exists.
- Builder: the [Atlas-OS/sxsc](https://github.com/Atlas-OS/sxsc) builder, pinned by full commit SHA in `SXSC_REF` in `.github/workflows/build.yml`; see the [CAB build guide](../../../tools/sxsc/README.md).
- Licence: built from configs in this repository, which the [project licence](../../../LICENSE) covers.
- Used by: `Install-VantaCbsPackage` (Vanta.Software), which checks each CAB against `Vanta-CbsHashes.psd1` and its signer exactly (`Assert-VantaCbsCertificate`). A package without CABs skips these steps (`Test-VantaCbsPackagesAvailable`).

## Replace a binary

1. Replace the file under `package/Executables`.
2. Hash it and update its entry here: path, SHA-256, version and source.

   ```powershell
   Get-FileHash -Algorithm SHA256 -LiteralPath <path>
   ```

3. CABs are not kept in the repository; `Build-VantaPackage.ps1` writes the hash manifest it ships with a personal package.
   The install refuses any CAB whose name or hash isn't in that file.
4. For the timer tools, rebuild and accept the build as the [timer build recipe](../../../tools/timer/README.md) describes.
   `tests/Vanta.TimerProvenance.Tests.ps1` fails when the executables or the source archive differ from `tools/timer/accepted-build.json`.
5. Compare this inventory with the binaries in the package, since no test does.

   ```powershell
   Get-ChildItem -LiteralPath package/Executables -Recurse -File -Include *.exe, *.dll, *.cab, *.zip |
       Get-FileHash -Algorithm SHA256
   ```
