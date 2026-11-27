# ADR 0001: Fonts, GPL distribution, Git history and the legacy test suite

- Status: accepted
- Context: Vanta is a GPL-3.0 fork of AtlasOS 0.6.0. It is not sold today, but must be ready to be shared or sold.

## Fonts: Geist (OFL) instead of Fontshare

Clash Grotesk and General Sans come under the Fontshare licence, which allows embedding them in an app but not redistributing the font files.
The `.ttf` files were committed to the repository, so shipping the source would break that licence.
The interface moves to Geist (display, text) and Geist Mono (mono), by Vercel, under the SIL OFL 1.1, which allows redistribution and sale with the notice.
The notice is `app/licenses/fonts/Geist-OFL.txt`; the credit is in `NOTICE` and the About screens.

## Distribution under the GPL-3.0

Every release carries `Vanta-<version>-source.zip`, made by `git archive` at the commit the binaries were built from, and `Vanta-<version>-third-party-sources.zip` with the source of the GPL programs the package carries (ViVe, Multi-Choice), from pinned commits (`tools/release/third-party-sources.lock.json`). Both are offered in the same place as the binaries, at no extra charge: GPL-3.0 section 6(d), the section for conveying by download (6(a) is for a physical medium).
`LICENSE` (the GPL text) is never edited.
`NOTICE` and `THIRD-PARTY-NOTICES.txt` accompany every binary.
The project's own crates (`vanta-manager`, `vanta-core`, `vanta-sys`) are identified by a general rule (no registry source, manifest inside the repository) and carry the repository `LICENSE`; they get no third-party section.
Optional third-party installs (such as eclean) are not part of the Recommended preset.

## Git history

The history is kept as it is; no rebase, no reset.

- The F5d commits (`95d673b3`, `29f5e994`, `fb07aee1`) stay as made.
- `204eb7f2` was committed with `git add -u` and so also contains four files of the Design work. It compiles and nothing was lost; it is recorded here instead of rewritten.
- The Fontshare font files remain in older commits. The source is therefore distributed through `source.zip`, not by publishing this history. If the repository is ever made public, start a new one from `source.zip`.

## Legacy Atlas test suite retired

The Atlas Pester suite inherited with the fork had 85 failures caused by the environment (`#requires` for PowerShell 7 run under 5.1, system language), not by Vanta code.
It is retired in favour of the Vanta suite (`vanta/tests`, 165/165), which covers what Vanta uses. The Rust suites (`app`, `vanta/core`, `vanta/sys`) run with no failures.

## CBS packages: no CAB in the public edition, personal edition not distributable

The two CBS packages used to be signed with an identity that names Microsoft, which presents Vanta's work as Microsoft's.
Plan A signed them as `CN=Vanta CBS Packages, O=Vanta` (self-signed, a new certificate per build, private key deleted right after signing). On a clean VM Windows refused them with `0x800b0110` (`CERT_E_WRONG_USAGE`), without test signing, so that route is closed. Turning on test signing or switching off signature verification is never done.
The alternative plan applies:

- **Public edition:** no CAB at all, and no `defender-disable` option in its manifest. NoTelemetry isn't installed (its policy and registry tweaks stay); Defender stays on. `Test-VantaCbsPackagesAvailable` makes the install skip the CAB steps whenever a package carries none (this also covers ARM64, for which no CAB was ever tested).
- The Plan A build script was removed; the attempt stays in the history (`b79c8c04`).

## Version 1.0.0 and the public repository

The first public release is 1.0.0 (the 0.6.0 builds were only tests on a VM): `updatableFrom` is empty, and `VantaManager.exe` carries its package. The source lives at https://github.com/spaayy/vanta; it is made from the public source tree (`tools/release/Export-PublicSource.ps1`), in one new commit, so none of the older history (with the earlier font files) is published. The test banner shows only for a pre-release id (`-rc.N`, `-test`).
