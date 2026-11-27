# Vanta

[https://github.com/spaayy/vanta](https://github.com/spaayy/vanta)

An open and lightweight modification to Windows 11, designed to optimise performance, privacy and usability.
Vanta is free software under the GPL-3.0: you may use, share and even sell it, as long as the source goes with it.

## Install Vanta

Download `VantaManager.exe` from the [latest release](https://github.com/spaayy/vanta/releases/latest) and run it as administrator. The Vanta package is inside it: it needs no other file and no internet to open.

1. Follow **Get ready**: Vanta checks the PC, updates Windows and the Store apps, and lets you choose how drivers install.
2. Choose **Recommended by Vanta** or **Choose manually** for the five installation choices, then install.

Vanta needs a supported edition and release of Windows 11 (see the [supported Windows releases](docs/windows-release-policy.md#supported-releases)).

## What Vanta changes

| Area | What Vanta does | Read more |
| --- | --- | --- |
| Privacy | Turns off selected Windows telemetry and sets policies that reduce data collection. | [Privacy tweaks](docs/catalog/tweaks.md#privacy) |
| Performance | Reduces background activity and adjusts services and power settings. | [Power-saving policy](docs/power-saving-policy.md), [service startup policy](docs/services-startup-policy.md) |
| Security | Lets you choose how Microsoft Defender and SmartScreen, Windows Update, CPU mitigations and core isolation are set. Everything stays protected by default. | [Install tweaks](docs/catalog/tweaks.md) |
| Usability | Changes interface defaults, and removes Windows ads and selected apps. | [Toggle catalog](docs/catalog/toggles.md) |

Privacy settings in your browser and other apps stay as you set them.
Performance results depend on your hardware and workload.

After installing, **Vanta Tools** (`C:\Vanta\Tools\vanta-tools.exe`) applies and restores individual settings and installs programs.

## Check what Vanta does

- The Vanta package (`.vantapkg`) is a password-protected ZIP file (password `vantapkg`).
  Most of it is PowerShell and data; the [package format](docs/package-format.md) describes its layout.
- The [binary inventory](package/Executables/VantaModules/README.md) lists every executable in the package, with its source and licence.
- The [toggle catalog](docs/catalog/toggles.md) and [install tweak catalog](docs/catalog/tweaks.md) list every toggle and install tweak.
- [Vanta Manager's source code](app/) is in this repository.

## Contribute

Start with the [contributing guide](.github/CONTRIBUTING.md).
The [developer documentation](docs/README.md) explains how Vanta works, and the [Vanta Manager guide](app/README.md) covers the app.

## Licença e código-fonte (Licence and source code)

Vanta is free software under the [GNU General Public License v3.0](LICENSE).
You may use, copy, change and distribute it, commercially too, under the terms of that licence.
The licence text and the [NOTICE](NOTICE) must stay with every copy.

Every release comes with its complete corresponding source, offered in the same place as the binaries, at no extra charge (GPL-3.0 section 6(d)):

- `Vanta-<version>-source.zip`, the public source tree (this repository, version 1.0.0 onward);
- `Vanta-<version>-third-party-sources.zip`, the source of the GPL programs the package carries that Vanta didn't write (ViVe `v0.3.3`, Multi-Choice from the commit that licenses it), from pinned commits, with `vendor/` so Multi-Choice builds offline.

This repository holds the same source, including [Vanta Manager](app/) and the [package](package/).
Vanta Manager's [third-party notices](app/licenses/README.md) list the licences of the code it includes.

Vanta doesn't include Windows and doesn't change Windows activation.
You need your own copy of Windows and a Windows licence.

## Créditos (Credits)

- **AtlasOS**: Vanta is based on AtlasOS 0.6.0 (<https://github.com/Atlas-OS/Atlas>), copyright the AtlasOS contributors, under the GPL-3.0.
  The Atlas credit is part of the licence and stays in every copy.
- **sxsc**: the Windows component packages (CABs) are built with the tooling described in [`tools/sxsc`](tools/sxsc/README.md); their configs are Vanta's own.
- **Geist and Geist Mono**: the interface fonts, by Vercel, under the SIL Open Font License 1.1 (<https://github.com/vercel/geist-font>); the notice is in [`app/licenses/fonts/Geist-OFL.txt`](app/licenses/fonts/Geist-OFL.txt).
- **Third-party code and programs**: the Rust crates in Vanta Manager are listed with their licences in [`THIRD-PARTY-NOTICES.txt`](app/licenses/THIRD-PARTY-NOTICES.txt), and the executables in the package in the [binary inventory](package/Executables/VantaModules/README.md).
  Each keeps its own licence and copyright.

Atlas and the other names above belong to their owners. Vanta isn't affiliated with or endorsed by them.

## Segurança (Security, network and privacy)

Vanta sends no telemetry and has no account.
It reaches the network only to do what you ask:

- Windows Update, Microsoft Store and winget download updates and programs, as they do without Vanta.
- Vanta asks `api.github.com` for public information: the winget package manifests (`microsoft/winget-pkgs`) and the latest winget release, and for the Vencord installer from `github.com` when you choose it.
  These are anonymous, read-only requests to find or fetch a file; no personal data is sent beyond what any HTTPS request carries (your IP address).
- Vanta Manager downloads a Vanta package only when you ask it to.

Nothing else is sent anywhere.

**Windows servicing packages (CBS).** Removing Microsoft Defender and the Windows telemetry components takes two servicing packages (CABs) that must be signed in a way Windows accepts.
Windows refused the only identity Vanta can honestly sign with (a self-signed `CN=Vanta CBS Packages`, error `0x800b0110`), and Vanta never turns on test signing or turns off signature checks.
So:

- **The public edition (`VantaManager.exe`, with its package inside) carries no CAB.** It doesn't offer removing Defender (Defender stays on, the recommended choice), and the telemetry policy and registry tweaks still apply; only the telemetry CAB is left out.
- The source (`source.zip`) carries no CAB and no signer that names Microsoft.

