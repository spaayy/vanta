# Contributing to Vanta

This guide is for anyone who wants to improve Vanta.
It covers the ways to help, the tools you need, where things live and what a pull request needs.
For an overview of taking part, see Contributing in the Vanta documentation.

## Ways to contribute

- **Bug reports:** use the bug report form, and attach a diagnostics ZIP from Vanta Manager.
- **Feature requests:** use the feature request form.
  Developer documentation lives in this repository, under [`docs/`](../docs/README.md).
- **Translations:** Vanta Manager's catalogs live in [`app/i18n`](../app/i18n), and the [translation guidance](../app/docs/translating.md) explains the conventions.
- **Code:** open a pull request against `main`.
  For a larger change, open an issue or a discussion first so you can agree the approach before you build it.

To report a security vulnerability, follow the [security policy](SECURITY.md) instead of opening an issue.

## Prerequisites

| Tool | Needed for |
| --- | --- |
| PowerShell 7 (`pwsh`) | The build tools, the build tests and linting |
| 7-Zip or NanaZip on `PATH` | Creating the `.atlaspkg` archive |
| Windows PowerShell 5.1, built into Windows | The Windows PowerShell tests |
| Pester and PSScriptAnalyzer, at the versions in the [testing guide](../docs/testing.md) | Tests and linting (the Pester 3 built into Windows is too old) |
| rustup and the Visual Studio build tools | Vanta Manager, as the [Vanta Manager guide](../app/README.md) describes |

## Build and test quick start

Build a test Vanta package and verify it from the repository root:

```powershell
./build.cmd                                                              # build package/Vanta Test.atlaspkg
pwsh tools/build/Test-Package.ps1 -Path "package/Vanta Test.atlaspkg"   # verify it
```

On Linux or macOS, run `./build.sh` instead of `./build.cmd`.
The [build guide](../docs/building.md) covers the build options.

Run the Windows PowerShell tests and the build tests in their separate hosts, as [Pester unit tests](../docs/testing.md#pester-unit-tests) describes.
Use unelevated test shells.
Install and configuration checks belong in a disposable VM, never on your own PC.

Lint in PowerShell 7 with the two profiles CI runs, listed under [PSScriptAnalyzer](../docs/testing.md#psscriptanalyzer).

Test Vanta Manager from its folder:

```powershell
cd app
cargo test --locked
```

## Where things live

| Path | What it holds |
| --- | --- |
| `app/` | Vanta Manager, the Rust desktop app ([Vanta Manager guide](../app/README.md)) |
| `package/atlas.json` | The Vanta package manifest, including `supportedBuilds` and `updatableFrom` ([package format](../docs/package-format.md)) |
| `package/Executables/VantaDesktop/` | The VantaDesktop folder's launchers, mostly generated |
| `package/Executables/VantaModules/Scripts/` | The Windows PowerShell that runs on users' PCs |
| `package/Executables/VantaModules/Toggles/` | Data-only VantaDesktop toggle definitions and their companions |
| `services/` | The Vanta reports service and its MCP server |
| `tools/` | Build, development, lab and release tooling, in PowerShell 7 |
| `tests/` | Pester suites |
| `docs/` | Developer documentation ([documentation index](../docs/README.md)) |

The scripts are organised by who invokes them:

- `Entry`: processes started from outside, such as Vanta Manager, launchers and the TrustedInstaller broker.
- `Install`: the install-only plan, phases and tasks.
- `Operations`: scripts that run in their own process and are invoked by path.
- `Modules`: shared libraries.
- `Tweaks`: data-only install tweaks and their companion scripts.
- `Preparation`: the Windows and Microsoft Store update worker, which Vanta Manager also embeds.

The [architecture](../docs/architecture.md) explains how an install runs.
[The front door](../docs/front-door.md) describes `Install-Vanta.ps1`, the script Vanta Manager runs, and how to run it when testing.
[Compatibility code and files](../docs/compatibility.md) lists every file and piece of code kept for an older install or an external consumer, with its removal condition.

## Common tasks

- **Add or change a tweak:** edit the relevant `.psd1` under `package/Executables/VantaModules/Scripts/Tweaks` (schema in that folder's `README.md`) and its entry in `tweaks.manifest.psd1`.
  To turn a tweak off, remove it from `Categories` or `Standalone`, and add its full slug and a reason to `Disabled`.
  Every definition in the Vanta package must be classified exactly once.
- **Add or change an VantaDesktop toggle:** edit the data-only definition `package/Executables/VantaModules/Toggles/<Group>/<Name>.psd1` (schema in that folder's `README.md`).
  Imperative work goes in the function-only companion `<Name>.ps1` beside it.
  Validate with `Test-VantaToggleDefinition -Path package/Executables/VantaModules/Toggles` from the `Vanta.Toggles` module, and regenerate the launchers with `pwsh tools/dev/New-ToggleLaunchers.ps1`.
- **Regenerate the catalog after definition changes:** run `pwsh tools/dev/Export-VantaCatalog.ps1` for the JSON and Markdown references.
  Both generators support `-Validate`, which checks for drift without writing files.
- **Share one implementation between the install and a toggle:** give the install tweak a `Toggle = @(@{ Name; State })` entry instead of duplicating the toggle's machine work.
- **Work on Vanta Manager:** see the [Vanta Manager guide](../app/README.md) for Rust builds, isolated tests and review tools.
- **Bump the version:** run `pwsh tools/build/Set-VantaVersion.ps1 -Version <version>`.

## Commit messages

Use [Conventional Commits](https://www.conventionalcommits.org/): `type(scope): summary`.
The scope is optional and names the area you changed, such as `app`, `toggles` or `preparation`.

| Type | Use it for |
| --- | --- |
| `feat` | A new feature or a change in behaviour |
| `fix` | A bug fix |
| `refactor` | A code change that keeps the behaviour |
| `docs` | Documentation only |
| `test` | Tests only |
| `build` | The build, packaging or dependencies |
| `ci` | GitHub Actions workflows |
| `chore` | Maintenance that fits no other type |
| `revert` | Reverting an earlier commit |

Write the summary in the imperative, in lower case, without a full stop, for example `fix(toggles): check the active power plan in Vanta health`.

## Pull requests

Describe what changed and why, link the issue it resolves, and say how you tested it.
The [pull request template](pull_request_template.md) asks for each of these.

Before you ask for a review, check that:

- CI passes.
- Changes to what Vanta does to a PC have been installed on a disposable VM, as the [testing guide](../docs/testing.md) describes.
- The documentation that describes the behaviour you changed is up to date.
- After changing tweak or toggle definitions, you've run both generators, and then run them again with `-Validate`.
- Scripts under `package/` and `app/resources/` use Windows PowerShell 5.1 syntax, because they run on users' PCs.
  The CI parse gate rejects PowerShell 7-only syntax there.

## Style

Follow the [writing style guide](../docs/style.md) for documentation, code comments and commit messages.
Vanta Manager's interface copy follows the [app writing guide](../app/docs/writing.md).

## Licence of contributions

Vanta is licensed under the [GNU General Public License v3.0](../LICENSE).
By contributing, you agree that your contributions are licensed under the same licence.
If you include third-party code, keep its licence and notices, and list any binary in the [binary inventory](../package/Executables/VantaModules/README.md).

## Code of Conduct

Everyone who takes part in Vanta follows the Vanta Code of Conduct.
