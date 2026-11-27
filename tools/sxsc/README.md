# CBS package configs

This folder holds the configs for the two CBS packages (CABs) in the Vanta package, and the script that builds and signs them.
It's for maintainers who change which Windows components the packages replace, or who rebuild the CABs.

| Config | Package | Architecture |
| --- | --- | --- |
| `Vanta-Defender-Remover.yaml` | `Z-Vanta-NoDefender-Package` | amd64 |
| `Vanta-NoTelemetry.yaml` | `Z-Vanta-NoTelemetry-Package` | amd64 |

Only x64 configs are kept: there is no ARM64 machine to prove an ARM64 package on, so the ARM64 configs and CABs were removed (they remain in the Git history). A package without a CAB for the PC's architecture skips the CAB steps and doesn't offer removing Defender.

The NoDefender package covers Microsoft Defender, SmartScreen and their related components.
The NoTelemetry package covers telemetry, compatibility appraisal and feedback components.
Each config names its package and lists the Windows components it updates, with the architecture and version of each, and any registry values an update sets.
Built CABs aren't kept in the repository.

## The shipped CABs

None are shipped. A self-signed `CN=Vanta CBS Packages, O=Vanta` build was tried and Windows refused it (`0x800b0110`); test signing is never turned on. The public edition therefore carries no CAB, and the personal edition (not distributable) is built with CABs read from an older commit at build time (see `vanta/tools/Build-VantaPackage.ps1`).
The configs here remain for anyone who wants to rebuild a package for their own machine with their own signer.

## How CI builds candidate CABs

The workflow below is the upstream candidate build and still uses the upstream certificate script; its CABs are for review only and must not be shipped. Build the shipped ones with the script above.


The Build Vanta package workflow, `.github/workflows/build.yml`, builds CABs when a push changes a config in this folder.
It rebuilds all four in these cases:

- a manual run (`workflow_dispatch`);
- a push that deletes a config;
- a file named `regenAllConfigs` in this folder;
- a push with no usable previous commit to compare with, such as the first push of a branch or a force push.

For the selected configs, the workflow:

1. Fetches the builder, Atlas-OS/sxsc, at the full commit SHA in `SXSC_REF`, and stops if the checked-out commit differs.
2. Creates a signing certificate, then runs the builder's `sxsc.py` and `start-build.ps1` for each config.
3. Regenerates `Vanta-CbsHashes.psd1` in its workspace, so the CI Vanta package from the same run carries the new CABs.
4. Uploads the CABs with a `SHA256SUMS.txt` as the artifact `Vanta-CAB-candidates-<commit>`, which GitHub keeps for seven days.

The workflow has read-only access to the repository, so it never commits CABs.
To change the builder, set `SXSC_REF` to the full SHA of the new commit.

The signing certificate changes with every build, so Vanta can't pin its thumbprint.
Vanta pins each CAB's SHA-256 in `Vanta-CbsHashes.psd1` instead, and refuses to install a CAB that's missing from that file or doesn't match its hash.

## Accept candidate CABs

1. Download the `Vanta-CAB-candidates-<commit>` artifact, and check each CAB against its `SHA256SUMS.txt`.
2. Test the `Vanta-CI-<commit>` artifact from the same run, which is built with those CABs, on a disposable VM of each architecture you changed.
3. Replace the CABs in `package/Executables/VantaModules/Packages`.
4. Regenerate `package/Executables/VantaModules/Packages/Vanta-CbsHashes.psd1` with the command in its header comment.
5. Update the SHA-256 values in the CBS component packages section of the [binary inventory](../../package/Executables/VantaModules/README.md).
6. Run `tests/Vanta.PackageLayout.Tests.ps1`, which fails if `Vanta-CbsHashes.psd1` and the CABs in the folder differ.

Commit the CABs, `Vanta-CbsHashes.psd1` and the binary inventory together, so the tests pass at every commit.
