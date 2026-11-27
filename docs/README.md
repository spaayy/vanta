# Vanta documentation

This index lists the documentation kept in this repository, grouped by who it's for.
User guides live on the Vanta documentation site, and Vanta Manager has its own documentation in [the Vanta Manager README](../app/README.md).

## Using Vanta

- [Updating Vanta](upgrading.md): how Vanta Manager updates an installed Vanta and what the update keeps.
- [Moving Windows to a newer release](windows-transition.md): how Vanta Manager moves Windows to a newer release before it installs or updates Vanta.
- [Reporting problems](diagnostics.md): how to send a report or export diagnostics, and what the export contains.
- [Windows release policy](windows-release-policy.md): which Windows releases Vanta installs on, and how it checks them.

## How Vanta works

- [Architecture](architecture.md): how the Vanta package, its scripts and Vanta Manager fit together.
- [Vanta package format](package-format.md): the `.atlaspkg` file Vanta Manager installs, its manifest and the rules for choices.
- [The front door](front-door.md): how Vanta Manager starts an install through `Install-Vanta.ps1`, and the install modes.
- [Install state](install-state.md): what Vanta records about an install and how an interrupted install resumes.
- [Preparation](preparation.md): how Vanta Manager brings Windows and Microsoft Store apps up to date before Vanta changes anything.
- [Compatibility code and files](compatibility.md): the files and code Vanta keeps only for older installs, earlier releases and other programs, and when each can go.
- [Power-saving policy](power-saving-policy.md): what the **Turn off power saving** choice changes and what it leaves alone.
- [Service and driver startup policy](services-startup-policy.md): why Vanta leaves service startup values at Windows defaults, and the exceptions.
- [Console presentation](console-presentation.md): how Vanta launchers and helpers word and format what they print.

## Contributing

- [Writing style](style.md): the house style for documentation, comments and commit messages.
- [Building](building.md): how to build and verify the Vanta package and cross-build Vanta Manager.
- [Testing](testing.md): the automated checks, the lab VM run and the checks to repeat for a release.
- [VantaDesktop toggles](catalog/toggles.md): the generated reference of every toggle and its launchers.
- [Install tweaks](catalog/tweaks.md): the generated reference of every tweak the install runs.

## Releasing

- [Releasing Vanta](releasing.md): the steps from a version bump to a published release.
- [Publication contents](publication.md): what belongs in Git, what stays local, and what to review before a release.
- [Release verification matrix](release-verification-matrix.md): the evidence every release needs before it's published.
