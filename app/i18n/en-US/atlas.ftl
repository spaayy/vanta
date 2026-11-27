### Vanta Manager: English (United States).
###
### An overlay on the en-GB source: only messages whose spelling differs
### (licence/license, colour/color, -ise/-ize, cancelled/canceled). Every
### other message falls through to en-GB, so do not copy messages here that
### read the same in both; this file is a spelling overlay, not a catalog.

## Optional choices
consequence-defender-disable = Also removes SmartScreen. Your PC won't have antivirus protection until you install another antivirus app, and Windows won't warn you before you open unrecognized apps or downloads.
installed-defender-removed-message = Your PC won't have antivirus protection until you install another antivirus app. SmartScreen was removed too, so Windows won't warn you before you open unrecognized apps or downloads.
change-core-isolation-on = Vanta turns virtualization-based security (VBS) back on, unless a policy on this PC controls it. This takes effect after the restart.

## Shared and settings
settings-theme-contrast-note = Vanta is using the colors from your Windows contrast theme.
settings-about-licence = License
settings-about-gpl-link = Read GPL-3.0 license
settings-about-fonts-link = Geist OFL-1.1 license
settings-licences-failed = Couldn't open THIRD-PARTY-NOTICES.txt. Try again, or find it in the licenses folder.

## System checks
detail-activation-no-licence = Windows didn't report a license. You can continue; Vanta won't change your activation status.

## Vanta package options
package-option-disable-core-isolation = Turn off virtualization-based security (VBS)

## Install result
restart-stopped = Automatic restart canceled. Save your work, then restart your PC to finish setting up Vanta.

## ISO creation
iso-review-description = Creating the ISO doesn't install anything on this PC or change your original ISO. Afterward, Vanta can put the new ISO on a USB drive so you can reinstall Windows from it.
iso-cancelled = ISO creation canceled
iso-close-message = Keep this window open until creation or cancellation finishes. Canceling waits for the current operation to reach a safe stopping point.
iso-terms-in-setup = Windows Setup will ask you to accept the license terms.
iso-privacy-defaults = This ISO skips the Microsoft account and privacy screens in Windows setup, and turns off optional data sharing and personalized offers.
iso-account-trailing-dot = The name can't end with a period.
iso-target-this-description = Vanta can add this PC's Wi-Fi and Ethernet drivers to the ISO, so Windows can go online right after it's reinstalled.
iso-edition-selection = Only supported editions are included. During Windows setup, choose an edition you have a Windows license for.

## Windows installation USB
usb-cancelled-title = USB creation canceled

## Windows version update
windows-terms-link = Read the license terms
prepare-needs-terms = Available when you accept the license terms in Windows 11, version { $release }.
ready-banner-terms-title = Accept the license terms to continue
prepare-failed-feature-terms = Accept the license terms for Windows 11, version { $release }, then choose Try again.
prepare-failed-feature-managed = This PC gets updates from an organization's update server, so Vanta can't move it to version { $release }. Vanta didn't change anything.
prepare-failed-feature-policy = Something on this PC keeps changing { $setting } back after Vanta changes it, so Vanta can't update Windows. If an organization manages this PC, ask them. Vanta puts back what it changed when you stop.
options-mode-recommended-detail = Applies the Vanta recommended profile only to the options on this screen (keeps VBS, phishing protection, Store and Snipping Tool; enables Brave and Vanta optimizations without changing earlier choices).
