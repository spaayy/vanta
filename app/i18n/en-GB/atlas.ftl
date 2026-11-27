### Vanta Manager: English (United Kingdom), the source catalog.
###
### Every other language falls back to this file, so it must define every
### message. Ids are stable identifiers, never shown to users. Comments
### above a message say where it appears and what its variables hold.
###
### Conventions for translators:
### - Keep the variables ({ $name }) exactly; reorder them freely.
### - Numbers arrive as numbers and are formatted for the user's region
###   automatically; use plural selectors ({ $count -> [one] ... *[other] ... })
###   with your language's CLDR categories where the count changes the wording.
### - Values marked "text" (versions, build numbers, file names, paths,
###   error details) are inserted as they are and must not be translated.
### - "Vanta", "Vanta", "Windows", "Defender", "Windows Security", "SmartScreen", "GitHub"
###   are product names. Windows feature names should match what Windows
###   shows in your language (for example the four Virus & threat protection
###   switches).
### - Buttons are verb-first and short. Sentences end with a full stop;
###   titles and labels do not.

## Shared

app-name = Vanta Manager
common-done = Done
common-cancel = Cancel
common-back = Back
common-next = Continue
common-dismiss = Dismiss
# Link beside a summary row that jumps back to change that choice.
common-change = Change
common-copy = Copy
# Shown where a list of options is empty.
common-none = None
# Accessible name of the back arrow on the Install and Settings pages.
common-back-to-home = Back to home
# Accessible name of the gear button in the title bar.
common-settings = Settings
common-close-settings = Close settings
common-open-windows-security = Open Windows Security
common-restart-as-administrator = Relaunch as administrator
common-try-again = Try again
common-show-details = Show details
common-hide-details = Hide details
# Accessible name of a button that acts on one card, so two buttons with the same label stay
# distinct: a Show details or Hide details toggle, or PC checks' Check again. $action is the
# button's label; $section is the title of its card.
common-details-a11y = { $action }, { $section }
common-open-log-file = Open log file
# Accessible name of the Copy button beside the install log.
common-copy-install-log = Copy installation log
common-install-log = Installation log
# Row labels in summary cards.
common-windows = Windows
common-options = Options
common-package = Installation files
common-installed-as = Installation type
common-installed = Installed
common-checking = Checking
# Joins two items in a list: "Brave, Firefox". The braces keep the space.
list-separator = { ", " }
# Joins two alternatives: "26100 or 26200".
list-or = { $a } or { $b }
# Joins the last two items of a list: "Tamper Protection and Cloud-delivered protection".
# $a may itself be several items joined with list-separator.
list-and = { $a } and { $b }
# Accessible name of a message bar that announces itself: its title, then its message.
infobar-a11y = { $title }. { $message }

## Window

# Dialog shown when the window is closed while an install runs.
window-close-title = Close while Vanta is installing?
window-close-message = Installation will continue in the background. Open Vanta again to check progress and see the result. Keep your PC on until it finishes.
# Instead of window-close-message when the installation restarts the PC afterwards: only an
# open Vanta window restarts it, so closing the window cancels that.
window-close-message-restart = Installation will continue in the background, but your PC won't restart automatically while Vanta is closed. Open Vanta again to check progress and see the result. Keep your PC on until it finishes.
# The safe answer in every dialog shown when the window is closed, including those for ISO
# and USB creation, updates and Windows Update access.
window-close-keep = Keep open
window-close-close = Close window
# Dialog shown when the window is closed during the final checks, before the
# installer has started; window-close-keep and window-close-close are its buttons.
window-close-preparing-title = Close before installation starts?
window-close-preparing-message = Vanta is still checking your PC and hasn't started installing. If you close now, installation won't start. Open Vanta again to continue.
# Dialog shown when the window is closed while Windows and Store apps update. Its
# message is prepare-close-message; its buttons are window-close-keep and prepare-stop.
prepare-close-title = Updates are still running
# "Stop updating" is prepare-stop, the dialog's other button.
prepare-close-message = Keep Vanta open while updates run. If you choose Stop updating, updates stop after the current step and you can close Vanta then.
# Dialog shown when the window is closed during the restart countdown after a
# successful install. Its buttons are window-close-keep, restart-now and
# window-close-restart-close.
window-close-restart-title = Close Vanta without restarting?
# "Restart now" is restart-now, one of this dialog's three buttons.
window-close-restart-message = Your PC needs to restart to finish setting up Vanta. If you close Vanta now, it won't restart your PC, so restart it yourself when you're ready. Save your work before you choose Restart now.
window-close-restart-close = Close without restarting
# Dialog shown when the window is closed during a setup with Windows Security switches still
# off. $switches names them as Windows Security does, joined like a list. Its buttons are
# window-close-keep, common-open-windows-security and window-close-close.
window-close-protection-title = Close Vanta with protection turned off?
window-close-protection-message = Some protection in Windows Security is still off: { $switches }. If you're not going to finish installing Vanta, turn it back on before you close. If you are, Vanta continues your setup when you open it again.
# The Open button of the file picker for an Vanta package (.vantapkg) file, on Get ready and the
# ISO page. It's a button label, so keep it short.
file-dialog-open-package = Open an Vanta package (.vantapkg)
# Message Windows shows in its restart notification.
shutdown-comment = Vanta is installed. Restarting Windows to finish setup.
# Message Windows shows in its restart notification when "Get ready" restarts
# to finish installing Windows updates.
prepare-shutdown-comment = Vanta is restarting Windows to finish installing updates.

## System

# "Windows 11 Pro 25H2 (build 26200.1234)". All three values are text.
system-description = { $product } { $version } (build { $build })

## Home page

home-not-installed = Welcome to Vanta
# The headline when Vanta Manager can't tell what is installed on this PC.
home-state-unknown = Vanta on this PC
# The headline when Vanta is installed. $version is text.
home-version = Vanta { $version }
# $date is a formatted date.
home-installed-on = Installed { $date }
home-status-checking = Checking for updates
# While startup checks whether another window's installation is running.
home-status-recovering = Checking for an installation in progress
home-status-offline = Couldn't check for updates
home-status-not-checked = Updates not checked yet
home-status-update = Vanta { $version } is available
home-status-up-to-date = Up to date
home-status-newest = Latest version: Vanta { $version }
# An earlier installation of Vanta { $version } stopped before it finished.
home-status-unfinished = Installation of Vanta { $version } isn't finished
home-check-again = Check again
# Primary button while an install is running or waiting.
home-show-install = View progress
home-continue-installing = Continue setup
home-update-to = Update to Vanta { $version }
home-reinstall = Reinstall Vanta
home-install = Install Vanta
home-finish-install = Finish installing Vanta { $version }
home-start-over = Start over
# A bar on Home after an installation finished, until the PC restarts. Its message is
# restart-needed and its button restart-now.
home-restart-title = Your PC needs to restart
home-security-reminder-title = Turn your protection back on
# Instead of home-security-reminder-title when no switch reads off but some couldn't be read
# (with home-security-reminder-unreadable-message).
home-security-reminder-unreadable-title = Make sure your protection is on
# After leaving the install flow. $switches names the switches that read off, as
# Windows Security names them (protection-*), joined with list-separator and list-and.
home-security-reminder-message = Vanta isn't installing anything, but some protection in Windows Security is still off. Open Windows Security and make sure these are on: { $switches }.
# Instead of home-security-reminder-message or installed-security-message when no switch
# reads off but some couldn't be read. $switches names those, joined like a list.
home-security-reminder-unreadable-message = Vanta couldn't read every protection switch. Check that these are on in Windows Security: { $switches }.
home-elevation-title = Vanta needs permission to install
home-state-error-title = Couldn't read your Vanta installation details
# "Check again" is home-check-again, beside the status above the bar. $error is a raw
# error message (text).
home-state-error-message = Your Vanta version, choices and history may not show correctly. Choose Check again to retry. Details: { $error }
home-whats-new = What's new in Vanta { $version }
home-view-release = View release notes on GitHub
home-released = Released { $date }
home-show-less = Show less
home-show-full-notes = Show all release notes
home-your-install = Your Vanta setup
# Vanta is installed, but without the record Vanta Manager keeps (older versions didn't write one).
home-install-unrecorded = This PC has no record of how Vanta was installed, so your choices and installation history can't be shown.
home-history = Installation history
# One history row. $version is text, $mode one of the history-mode-* messages, $date a formatted date and time.
home-history-entry = Vanta { $version } · { $mode } · { $date }
home-how-it-works = Let's get your PC ready for Vanta
home-step-1-detail = Vanta checks your PC, installs pending Windows and Microsoft Store updates, and downloads the installation files. Store apps may close and your PC may need to restart, so save your work first.
# Tester build: the Vanta package is bundled, nothing is downloaded.
home-step-1-detail-bundled = Vanta checks your PC, installs pending Windows and Microsoft Store updates, and prepares the bundled installation files. Store apps may close and your PC may need to restart, so save your work first.
home-step-2-detail = Choose whether to keep Microsoft Defender and processor protections, how Windows updates are installed, and any optional extras.
home-step-3-detail = Turn off four protection switches in Windows Security so they don't block installation. Vanta shows you how.
home-step-4-detail =
    { $minutes ->
        [one] Installing takes about a minute. Then your PC needs to restart.
       *[other] Installing takes about { $minutes } minutes. Then your PC needs to restart.
    }
# Accessible name of a numbered step.
home-step-a11y = Step { $number }: { $title }
home-report-problem = Report a problem

## How an install was done (from the state document)

mode-fresh = First installation
mode-upgrade = Update from an earlier version
mode-reapply = Reinstall of the same version
mode-unknown = Installation
# Lower-case forms used inside a history row.
history-mode-fresh = first installation
history-mode-upgrade = update
history-mode-reapply = reinstall
history-mode-unknown = installation

## Notices on the Home page

notice-settings-reset-title = Vanta is using default app settings
# $error is a raw error message (text).
notice-settings-unreadable = Vanta couldn't read your saved app settings. Your Windows settings haven't changed. Details: { $error }
# $file is a file name (text).
notice-settings-damaged-kept = Your app settings file was damaged and has been reset. A copy of the old file is saved as { $file }. Details: { $error }
notice-settings-damaged = Your app settings file was damaged. Vanta is using defaults for now. Details: { $error }
notice-settings-not-saved-title = Couldn't save app settings
# $error is a raw error message (text).
notice-settings-not-saved = Vanta couldn't save your latest changes, so they may be lost when you close Vanta. If another Vanta window is open, close it, then make the change again. Details: { $error }
notice-session-unreadable-title = Couldn't check the previous installation
# $path is a file path (text).
notice-session-unreadable-message = Vanta couldn't tell whether an earlier installation is still running. If you're not sure, ask the Vanta community for help. Only if you're sure none is running, delete { $path } and try again. Details: { $error }

## Administrator elevation

elevation-declined = Permission wasn't granted. Try again and choose Yes when Windows asks to let Vanta make changes.
elevation-declined-continue = Permission wasn't granted. Try again and choose Yes when Windows asks to let Vanta make changes. Your setup choices are saved.
elevation-draft-not-saved = Vanta couldn't save your setup choices, so it hasn't relaunched. Try again. Details: { $error }
# Shown with the home-start-over button.
elevation-taken-over = Another Vanta window is now using this setup, so Vanta hasn't relaunched. Continue in that window, or choose Start over to set up again here.

## The install flow

step-ready = Get ready
step-options = Your choices
step-security = Windows Security
step-install = Install
install-title = Set up Vanta
# Accessible name of the row of steps.
stepper-label = Vanta setup steps
# Accessible name of one step. $status is one of the stepper-status-* messages.
stepper-step-a11y = Step { $number } of { $total }, { $title }, { $status }
stepper-status-completed = completed
stepper-status-current = current step
stepper-status-upcoming = upcoming step
# A step already visited whose requirements aren't met yet.
stepper-status-attention = needs attention
# Heading above each step's content.
step-heading = Step { $number } of { $total }: { $title }
# Accessible name of the step heading on a screen of Your choices, read when it takes focus.
# $heading is step-heading; $progress is options-progress; $question is the screen's question.
step-heading-choice-a11y = { $heading }. { $progress }: { $question }
# The same on the optional extras screen; $progress is options-progress-extras.
step-heading-extras-a11y = { $heading }. { $progress }
# The same on the first screen of an update or reinstall; $question is update-path-update-title
# or update-path-reinstall-title.
step-heading-update-path-a11y = { $heading }. { $question }

## Step 1: Get ready

ready-banner-busy-title = Getting your PC ready
ready-banner-busy-message = Vanta is checking your PC and preparing the installation files.
ready-banner-blocked-title = Your PC isn't ready yet
ready-banner-blocked-message = Fix the items marked in PC checks, then choose Check again.
ready-banner-no-package-title = Download Vanta to continue
# "Installation files" is package-title, the first card; "Open package file" is package-open-file.
ready-banner-no-package-message = Download Vanta in Installation files, or choose Open package file if you already have an Vanta package (.vantapkg).
# The package tried needs a newer Vanta Manager. The title is also the footer's hint then.
ready-banner-manager-title = Download a newer Vanta Manager to continue
# "Download Vanta Manager" is manager-download, the button in Installation files (package-title).
ready-banner-manager-message = Choose Download Vanta Manager in Installation files, then use the new version instead of this one.
# Tester build: the bundled Vanta package couldn't be unpacked.
ready-banner-no-package-bundled-title = Prepare the bundled Vanta package to continue
ready-banner-no-package-bundled-message = The Vanta package included with this app isn't ready yet. Check the Installation files card.
# Shown while updating Windows and Store apps is the next task (Get ready's last card,
# Update Windows and Store apps).
ready-banner-updates-title = Update Windows and Store apps to continue
# "Check and install updates" is prepare-start, the button on the update card.
ready-banner-updates-message = Choose Check and install updates. When the updates finish, Vanta checks your PC again.
# While Windows and Store apps update. "Update Windows and Store apps" is prepare-title, the
# card further down the page.
ready-banner-updating-title = Updating Windows and Store apps
ready-banner-updating-message = This can take a while. Keep Vanta open. You can follow progress in Update Windows and Store apps.
# After Stop updating. "Check and install updates" is prepare-start, the card's button.
ready-banner-updates-stopped-title = Updating stopped
ready-banner-updates-stopped-message = Choose Check and install updates in Update Windows and Store apps to finish.
# Vanta reopened after restarting the PC to continue updating. "Continue updates" is
# prepare-continue, the card's button.
ready-banner-updates-resumed-title = Your PC has restarted
ready-banner-updates-resumed-message = Choose Continue updates in Update Windows and Store apps to finish updating.
# Under prepare-failed-title or prepare-unconfirmed-title. "Try again" is common-try-again,
# the card's button.
ready-banner-updates-failed-message = See Update Windows and Store apps for what to do, then choose Try again.
# Under prepare-reboot-title. "Restart and continue" is prepare-restart, the card's button.
ready-banner-reboot-message = Save your work first, then choose Restart and continue in Update Windows and Store apps.

ready-banner-warnings-title = A few things to review
ready-banner-warnings-message = You can continue, but read the items marked in PC checks first.
ready-banner-ok-title = You're ready to make your choices
ready-banner-ok-message = The checks passed and your installation files are ready.

# Card title and accessible name of the list of checks.
ready-this-pc = PC checks
ready-check-again = Check again
# The one line that stands for every check that passed; common-show-details opens them.
ready-checks-passed =
    { $count ->
        [one] { $count } check passed
       *[other] { $count } checks passed
    }

package-title = Installation files
# $received and $total are formatted numbers of megabytes (text).
package-downloading = Downloading Vanta { $version } · { $received } of { $total } MB
package-unpacking-progress =
    { $total ->
        [one] Unpacking · { $done } of { $total } file
       *[other] Unpacking · { $done } of { $total } files
    }
package-unpacking = Unpacking
package-looking = Checking for the latest Vanta version.
# Tester build: the bundled Vanta package is being unpacked, nothing is downloaded.
package-looking-bundled = Preparing the bundled Vanta package.
package-none = Download Vanta to get the installation files. If you already have an Vanta package (.vantapkg), open it instead.
# The GitHub release check failed. "Download latest version" is package-download-newest,
# the button offered in this state; it checks again.
package-release-failed = Vanta couldn't check for the latest version. Check your internet connection, then choose Download latest version, or open a saved Vanta package (.vantapkg).
# Short status words beside the card title.
package-status-downloading = Downloading
package-status-unpacking = Unpacking
package-status-failed = Couldn't prepare files
package-status-ready = Ready
package-status-checking = Checking
package-status-preparing = Preparing
package-status-missing = Not downloaded
# Accessible name of the progress bar.
package-progress = Installation file progress
package-download-again = Download again
package-download-version = Download Vanta { $version }
package-download-newest = Download latest version
package-cancel-download = Cancel download
package-open-file = Open package file
# Where the package came from. $file is a file name (text).
package-from-release = Vanta { $version } downloaded from GitHub and ready to install.
package-from-file = Vanta { $version } loaded from { $file } and ready to install.
package-unpacked = Vanta { $version } is ready to install.
package-none-yet = No installation files selected
acquire-no-asset = Vanta { $version } has no package file to download. Open a saved Vanta package (.vantapkg) to continue.
# Shown for a package older than Vanta 0.6.0, and for a file that isn't an Vanta package, such as an
# .apbx file from an Vanta release before 0.6.
acquire-unsupported = This app can install Vanta 0.6.0 and later, from Vanta packages (.vantapkg).
# A package new enough to include the installer script that this app drives, but without it.
acquire-incomplete = Vanta { $version } is missing files this app needs to install it. Download it again, or open another Vanta package (.vantapkg).
acquire-failed = Couldn't prepare the installation files. Try downloading again, or open another Vanta package (.vantapkg). Details: { $error }
# The download received nothing for a minute and was stopped.
acquire-stalled = The download stopped responding. Check your internet connection, then download again, or open a saved Vanta package (.vantapkg).
# Tester build: the bundled Vanta package couldn't be unpacked. Try again is the only control offered.
acquire-failed-bundled = Couldn't prepare the bundled Vanta package. Choose Try again. Details: { $error }
# The Vanta package asks for a newer Vanta Manager than this one. $version is the version it asks for,
# such as 0.7.0. "Download Vanta Manager" is manager-download, the button beside the message.
acquire-manager-outdated = This Vanta package needs Vanta Manager { $version } or later. Choose Download Vanta Manager, then use the new version instead of this one.
# The same, for a package that doesn't say which version it needs.
acquire-manager-outdated-any = This Vanta package needs a newer Vanta Manager. Choose Download Vanta Manager, then use the new version instead of this one.

## Newer Vanta Manager

# Opens the latest Vanta release on GitHub in the browser, where Vanta Manager is downloaded.
manager-download = Download Vanta Manager
# A note on Home and in Settings that a newer Vanta Manager has been released. $version is its
# version, such as 0.7.0. The note doesn't stop anything; manager-download is its button.
manager-update-title = Vanta Manager { $version } is available
manager-update-message = Vanta Manager can't update itself. Download the new version and use it instead of this one.

## System checks

check-administrator = Permission to install
check-supported-build = Windows compatibility
check-pending-updates = Windows updates
check-pending-reboot = Pending restart
check-third-party-antivirus = Other antivirus software
check-internet = Internet connection
check-power = Power supply
check-activation = Windows activation
# Accessible name of a check row. $state is one of the check-state-* messages.
check-a11y = { $title }: { $state }
check-state-checking = checking
check-state-passed = passed
check-state-warning = needs attention
check-state-failed-blocking = action needed before installing
check-state-failed = needs attention
check-state-unknown = couldn't be checked
check-fix-windows-update = Open Windows Update
check-fix-network = Open network settings
check-fix-power = Open power settings
check-fix-activation = Open activation settings
# Opens Installed apps in Windows Settings, from the Other antivirus software check.
check-fix-apps = Open installed apps
# Check box the user ticks when the Windows Update scan could not run.
check-ack-updates = I've checked Windows Update: no updates are waiting to install

detail-admin-ok = Vanta has permission to make the changes needed for installation.
detail-admin-missing = Relaunch Vanta as administrator, then choose Yes when Windows asks for permission.
# $builds is a list of build numbers such as "26100 or 26200"; $build is this PC's (text).
detail-build-unsupported = This Vanta version requires Windows build { $builds }. Your PC has build { $build }. Install a supported Windows version before continuing.
detail-build-missing = This Vanta package doesn't list any supported Windows builds. Use a full build of the package instead of a LocalTest build.
detail-updates-none = No Windows updates are waiting to install.
# $titles lists up to two update names (text); $count is the total. "Update Windows and
# Store apps" is prepare-title, the card that installs them.
detail-updates-pending =
    { $count ->
        [1] This update is waiting: { $titles }. Vanta installs it in Update Windows and Store apps.
        [2] These updates are waiting: { $titles }. Vanta installs them in Update Windows and Store apps.
       *[other] { $count } updates are waiting, including { $titles }. Vanta installs them in Update Windows and Store apps.
    }
detail-updates-unknown = Couldn't check for Windows updates. Open Windows Update, then confirm below if no updates are waiting. ({ $error })
detail-reboot-none = Windows doesn't need a restart right now.
# "Check and install updates" is prepare-start, the button on the update card, which
# then asks for the restart before updating.
detail-reboot-pending = Windows needs to restart to finish earlier changes. When you choose Check and install updates, Vanta asks you to restart first.
# $reasons: the pending-restart markers Windows set, from the prepare-reason-* names.
detail-reboot-pending-reasons = Windows needs to restart to finish earlier changes ({ $reasons }). When you choose Check and install updates, Vanta asks you to restart first.
# Warning, not a block: $files lists up to three file paths Windows will replace or remove at the next restart.
detail-reboot-file-renames = You can continue. Windows has files to replace or remove at the next restart ({ $files }). Some apps, such as Xbox Gaming Services, do this after every restart.
detail-reboot-unknown = Couldn't check whether Windows needs a restart. Restart your PC, then reopen Vanta and check again. ({ $error })
detail-antivirus-none = No other antivirus software was detected.
# $products is a list of product names (text). The row offers check-fix-apps.
detail-antivirus-found = Antivirus apps other than Microsoft Defender can block installation. Uninstall { $products }, then choose Check again.
# Warning, not a block: Security Center still lists the product but its files are gone.
detail-antivirus-stale = Windows Security still lists { $products }, but its files are gone, so it isn't installed any more. Vanta can install anyway.
detail-antivirus-unknown = Couldn't check for other antivirus software. Choose Check again. If it keeps failing, restart your PC and check again. ({ $error })
detail-internet-ok = You're connected. Keep this connection available while Vanta downloads and installs software.
detail-internet-missing = Connect to the internet, then check again.
detail-power-mains = Your PC is plugged in. Keep it connected until installation finishes.
detail-power-battery = Plug your PC into a power supply so it stays on throughout installation.
detail-power-unknown = Vanta couldn't tell whether your PC is plugged in. If it's a laptop, plug it in, then choose Check again. If this keeps happening, choose Send a report.
detail-activation-ok = Windows is activated. Vanta won't change this.
detail-activation-missing = Windows isn't activated. You can continue, but Vanta won't activate Windows for you.
detail-activation-no-licence = Windows didn't report a licence. You can continue; Vanta won't change your activation status.
detail-activation-unknown = Couldn't check Windows activation. You can continue; Vanta won't change your activation status. ({ $error })

## Step 2: Options

options-progress = Choice { $number } of { $total }
options-progress-extras = Choice { $number } of { $total }: optional extras
# Beside "Choice N of M" on every screen of Your choices. It names only what the Vanta
# folder can change back; other choices, such as removing Microsoft Edge, can't be undone there.
options-change-later = You can change Microsoft Defender, processor protections and update settings later from the Vanta folder on your desktop.
# Short names for each decision (summary rows) and the question each screen asks.
screen-defender-title = Microsoft Defender
screen-defender-question = Keep Microsoft Defender?
screen-mitigations-title = Processor protections
screen-mitigations-question = Keep Windows' processor protections?
screen-updates-title = Windows Update
screen-updates-question = How should Windows install updates?
screen-browser-title = Browser
screen-power-title = Power and security
screen-apps-title = Apps
screen-optional-apps-title = Optional apps
screen-choose-one-title = Choose an option
screen-extras-title = Optional extras
# Question for a required choice this app has no specific wording for.
screen-generic-question = Choose an option for { $title }
learn-more-defender = Learn more about Microsoft Defender
learn-more-mitigations = Learn more about processor protections
learn-more-updates = Learn more about Windows Update
learn-more-browser = Learn more about browsers
learn-more-power = Learn more about power and security
learn-more-apps = Learn more about apps
learn-more-eclean = How eclean works with Vanta
learn-more-generic = Read the setup guide
# One line under the chosen answer: what it means for the PC.
consequence-defender-enable = Keeps Windows' built-in antivirus to help protect your PC from viruses and other threats.
consequence-defender-disable = Also removes SmartScreen. Your PC won't have antivirus protection until you install another antivirus app, and Windows won't warn you before you open unrecognised apps or downloads.
consequence-mitigations-default = Keeps Windows' default protections against processor flaws and attacks that exploit bugs in apps.
# Under Turn off processor protections. "Exploit protection" is the Windows Security page
# of that name; use the name Windows shows in your language.
consequence-mitigations-disable = Also turns off Exploit protection for apps, such as Control Flow Guard. This reduces security. Any performance difference depends on your processor.
consequence-auto-updates-disable = Open Windows Update regularly to install updates. Update notifications stay on.
consequence-auto-updates-default = Windows will install updates automatically, including security fixes.

## Step 2 on an update or reinstall of the installed Vanta

# The first screen of Your choices when updating the installed Vanta. $version is the Vanta
# version being installed, such as 0.6.1.
update-path-update-title = How do you want to update to Vanta { $version }?
# The same screen when installing again the Vanta version this PC already has.
update-path-reinstall-title = How do you want to reinstall Vanta { $version }?
# The two answers on that screen, each with the detail line under it. Other messages
# name the answers too, so keep each the same everywhere.
update-path-keep = Keep my choices
update-path-keep-detail = Vanta keeps every choice as this PC has it now and changes none of them. This is the quicker way.
update-path-choose = Choose again
update-path-choose-detail = Go through every choice again, starting from how this PC is set up now. Vanta applies each one as a new installation would. Your apps, files, Start menu, taskbar and theme stay as they are, and so do settings you changed in the Vanta folder that these choices don't cover.
# Heading of the list under the two answers: one row per choice, as this PC has it now.
update-path-now-title = Your choices on this PC now
# The value of a row in that list for a choice nothing on the PC shows. Keep my choices
# then asks it.
update-path-unknown = Vanta can't tell this from your PC, so it asks you
option-detected-off = Detected as off on the current system. Nothing was chosen, so the safe default (keep on) is selected: choose it yourself.
# Above that list. $choices lists choice names, such as "Microsoft Defender and Processor
# protections", joined with list-and.
update-path-differs = Vanta's record of your last installation doesn't match this PC for { $choices }. This list shows what the PC has now.
# A bar on the screens Keep my choices still asks. $missing lists their names, such as
# "Keyboard languages", joined with list-and.
keep-choices-title = Keeping your choices
keep-choices-partial = Vanta keeps what this PC has now. It can't tell these from your PC, so choose them: { $missing }
# A bar on every screen after the first one once Choose again is selected.
choose-again-title = Choosing again
choose-again-detail = Each choice starts from how this PC is set up now. Vanta applies what you choose during the installation.
# A short tag, on a line of its own, under the answer this PC has now, on the screens of
# Choose again.
option-now = On this PC now
# Under an answer on a screen of Choose again, instead of what it usually means, when
# choosing it changes this PC.
change-defender-enable = Vanta brings Microsoft Defender back. After the restart, turn its protection on in Windows Security.
change-mitigations-default = Vanta turns processor protections back on, as Windows sets them. This takes effect after the restart.
# Under Keep processor protections when every protection is turned on: Vanta leaves them
# all on rather than going back to the Windows defaults.
change-mitigations-all-on = All processor protections are turned on now. Keeping protections leaves them all on.
change-auto-updates-default = Vanta lets Windows install updates automatically again.
# Under Turn off hibernation, Turn off power saving and Turn off VBS when the box is cleared
# while this PC has them off.
change-hibernation-on = Vanta turns hibernation back on.
change-power-saving-on = Vanta turns power saving back on and goes back to your earlier power plan, or to Balanced if there isn't one.
change-core-isolation-on = Vanta turns virtualisation-based security (VBS) back on, unless a policy on this PC controls it. This takes effect after the restart.
# Under Remove Snipping Tool when it's ticked while this PC still has the app.
change-remove-snipping-tool = Removes Snipping Tool for everyone on this PC. Vanta can't put it back later, but you can install it again from Microsoft Store.
# Under a box Choose again shows ticked and can't clear, saying why. Install or Remove Edge
# is a file name in the Vanta folder, in English on every PC.
fixed-uninstall-edge = Microsoft Edge is already removed, and updating Vanta can't put it back. To install it again, use Install or Remove Edge in the Vanta folder.
# The same for an app Vanta installed. $app is its name, such as Vanta Toolbox or Brave.
# "Installed apps" is the page of that name in Windows Settings.
fixed-installed = { $app } is installed. Vanta doesn't uninstall apps; to remove it, go to Installed apps in Windows Settings.
# Under the browser chosen when another browser Vanta offers is already installed.
# $installed and $browser are browser names, such as Brave and Firefox.
browser-also = { $installed } stays installed, and Vanta installs { $browser } as well.

## Vanta package text
## Labels and descriptions for the Vanta package's options and choices, by
## their ids in the package's vanta.json. The app shows these in place of the
## package's own English text; an option or choice that a newer package adds,
## which has no message here, shows the package's English.

package-option-defender-enable = Keep Microsoft Defender
package-option-defender-disable = Remove Microsoft Defender
package-option-mitigations-default = Keep processor protections
package-option-mitigations-disable = Turn off processor protections
package-option-auto-updates-disable = Install updates myself
package-option-auto-updates-default = Install updates automatically
package-option-disable-hibernation = Turn off hibernation

package-option-disable-phishing-protection = Turn off Enhanced Phishing Protection (Windows stops warning when you type your password into a known phishing site)
package-option-disable-gamebar = Turn off Game Bar and game capture
package-option-remove-store = Remove the Microsoft Store (App Installer and winget stay)
package-option-vanta-power = Use the Vanta power plan (desktop PCs only; skipped on laptops)
package-option-vanta-memory = Use the Vanta memory profile (memory compression on, page combining and app pre-launch off)
package-option-tools-on-logon = Open Vanta Tools the next time I sign in
package-option-disable-power-saving = Turn off power saving
package-option-disable-core-isolation = Turn off virtualisation-based security (VBS)
package-option-remove-snipping-tool = Remove Snipping Tool
package-option-uninstall-edge = Remove Microsoft Edge
package-option-install-another-browser = Install a browser
package-option-install-eclean = Install eclean
package-option-browser-brave = Brave
package-option-browser-librewolf = LibreWolf
package-option-browser-firefox = Firefox
package-option-browser-chrome = Chrome
package-choice-defender-description = Microsoft Defender is the antivirus built into Windows. Remove it only if you understand the risks and plan to use another antivirus app. Whichever you choose, Vanta turns off Smart App Control, Enhanced Phishing Protection and Find my device.

package-choice-protections-description = Windows protections that stay on unless you turn them off. Nothing here is turned off by default.
package-choice-vanta-description = Vanta extras. All are off unless you tick them.
package-choice-mitigations-description = These protections, also called security mitigations, help defend against processor flaws, such as Spectre and Meltdown, and against attacks that exploit bugs in apps. Keeping the Windows defaults is recommended.
package-choice-auto-updates-description = Choose how Windows installs updates after Vanta finishes installing (unlike Step 1, which prepares this PC beforehand). You can have Windows install them automatically or install them yourself. Either way, Vanta keeps Windows on its current version, which gets security fixes only until Microsoft ends support for it. Vanta also turns off automatic updates for Microsoft Store apps, so update them in Microsoft Store.
package-choice-browser-description = Choose a browser to install. Vanta won't change your browser settings.

## Step 3: Windows Security

security-banner-reading-title = Checking Windows Security
security-banner-reading-message = Vanta is checking the four protection switches below.
security-banner-off-title = The four protection switches are off
# Shown instead of the switch list when Microsoft Defender isn't on this PC and the user
# chose to remove it.
security-banner-absent-title = Microsoft Defender isn't installed on this PC
security-banner-absent-message = There's nothing to turn off on this step. Choose Continue.
# Instead of security-banner-absent-title when Vanta's own package removed Microsoft Defender
# and it stays removed. Its message is security-banner-absent-message.
security-banner-removed-title = Vanta removed Microsoft Defender from this PC
# When Vanta's own package removed Microsoft Defender and this installation brings it back.
# "Continue" is common-next.
security-banner-restore-title = Vanta brings Microsoft Defender back in this installation
security-banner-restore-message = Defender isn't running yet, so there's nothing to turn off on this step. After the restart, turn its protection on in Windows Security. Choose Continue.
# A warning that doesn't stop the step: the user chose to keep Microsoft Defender, but it
# isn't on this PC and Vanta didn't remove it. Home and the "Vanta is installed" window use
# the same title.
security-banner-missing-title = Microsoft Defender is missing
security-banner-missing-message = Vanta didn't remove it, so it can't bring it back. You can continue, but your PC has no antivirus until you install another antivirus app or repair Windows.
security-banner-off-message = Choose Continue to review your setup and install Vanta.

security-banner-on-title = Turn off antivirus protection in Windows Security
security-banner-on-message = Microsoft Defender can block the changes Vanta makes. Choose Open Windows Security and turn off each switch listed below. If you keep Microsoft Defender, turn the switches back on after installation finishes.
# The page name in Windows Security.
security-list-title = Virus & threat protection settings
security-switch-off = Off
security-switch-on = On
security-switch-unreadable = Couldn't check
security-switch-reading = Checking
security-all-off = All off
# Accessible name of a switch row. $state is one of the security-switch-* messages.
security-a11y = { $title }: { $state }
# Parts of the summary "2 still on, 1 can't be read".
security-count-still-on = { $count } still on
security-count-unreadable = { $count } can't be read
security-count-join = { $a }, { $b }
security-unknown-title = Confirm the switches Vanta couldn't read
security-unknown-message = Make sure all four switches are off in Windows Security, then confirm below.
security-acknowledge = I've checked Windows Security and all four switches are off
security-unknown-unelevated-title = Vanta needs permission to check protection
security-unknown-unelevated-message = Relaunch Vanta as administrator so it can check Microsoft Defender's settings.
# The four switches, named as Windows Security names them.
protection-tamper = Tamper Protection
protection-tamper-why = Turn this off so Defender doesn't block Vanta from changing its security settings.
protection-realtime = Real-time protection
protection-realtime-why = Turn this off so Defender doesn't block Vanta installation files while scanning them.
protection-cloud = Cloud-delivered protection
protection-cloud-why = Turn this off so online threat checks don't block Vanta installation files.
protection-samples = Automatic sample submission
protection-samples-why = Stop Defender from automatically sending Vanta files to Microsoft for analysis.

## Step 4: Install

# Accessible name of the progress bar.
install-progress = Installation progress
# The installation's progress shown beside the bar. $percent is a whole number from 0 to 99.
install-percent = { $percent }%
outcome-succeeded-title = Vanta is installed
outcome-lost-title = Couldn't confirm the installation result
outcome-failed-title = Installation didn't finish
outcome-requirements = Your PC didn't meet the installation requirements. No installation changes were made. Return to Get ready and run the checks again.
# The -resumed variants follow a retry of an installation an earlier attempt had already started applying.
outcome-requirements-resumed = Your PC didn't meet the installation requirements, so this attempt stopped. An earlier attempt already started making changes. Return to Get ready and run the checks again.
outcome-not-elevated = Vanta didn't have administrator permission. No installation changes were made. Relaunch Vanta as administrator, then try again.
outcome-not-elevated-resumed = Vanta didn't have administrator permission, so this attempt stopped. An earlier attempt already started making changes. Relaunch Vanta as administrator, then try again.
# The installer's live check found Windows or Store updates unfinished. Get ready offers the
# update check again; "Check and install updates" is prepare-start, its button in that state.
outcome-preparation-stale = Vanta couldn't confirm that Windows and Store apps are up to date, so installation stopped before changing Windows. Return to Get ready and choose Check and install updates.
outcome-preparation-stale-resumed = Vanta couldn't confirm that Windows and Store apps are up to date, so this attempt stopped, but an earlier attempt already started making changes. Return to Get ready and choose Check and install updates.
outcome-failed-preflight = Installation stopped before changing anything. You can try again. If it stops again, choose Send a report.
outcome-failed-staging = Installation stopped while preparing files, before changing Windows. You can try again. If it stops again, choose Send a report.
outcome-failed-applying = Some changes may already have been made. You can try again. If you stop here, turn the protections you turned off back on in Windows Security, if they're still available.
# The -defender-removed variants replace the advice to turn protections back on once Microsoft
# Defender has been removed, so there's nothing to turn back on. "Send a report" is report-title, in
# the diagnostics under the bar.
outcome-failed-applying-defender-removed = Some changes may already have been made. You can try again. If installation stops again, choose Send a report.
outcome-failed-resumed = This attempt stopped early, but an earlier attempt already started making changes. You can try again. If you stop here, turn the protections you turned off back on in Windows Security, if they're still available.
outcome-failed-resumed-defender-removed = This attempt stopped early, but an earlier attempt already started making changes. You can try again. If installation stops again, choose Send a report.
# The -repeated variants follow a retry of an installation already part-way through that stopped
# with the same error as the attempt before it, so they point to a report rather than another try.
# "Send a report" is report-title.
outcome-failed-repeated = This attempt stopped with the same error as the one before it, and some changes may already have been made. Trying again without changing anything is unlikely to help. Choose Send a report so the Vanta team can find the cause. If you stop here, turn the protections you turned off back on in Windows Security, if they're still available.
outcome-failed-repeated-defender-removed = This attempt stopped with the same error as the one before it, and some changes may already have been made. Trying again without changing anything is unlikely to help. Choose Send a report so the Vanta team can find the cause.
# $apps holds the package names Windows gives the apps, such as MSTeams (text), joined with list-and.
outcome-failed-repeated-apps = Windows still wouldn't remove { $apps }, so this attempt stopped with the same error as the one before it. Some changes may already have been made. Trying again without changing anything is unlikely to help. Choose Send a report so the Vanta team can find the cause. If you stop here, turn the protections you turned off back on in Windows Security, if they're still available.
outcome-failed-repeated-apps-defender-removed = Windows still wouldn't remove { $apps }, so this attempt stopped with the same error as the one before it. Some changes may already have been made. Trying again without changing anything is unlikely to help. Choose Send a report so the Vanta team can find the cause.
outcome-not-started = The installer didn't start in time. No installation changes were made. You can try again.
outcome-lost = The installer stopped without reporting a result, and some changes may already have been made. You can try again. If you stop here, turn the protections you turned off back on in Windows Security, if they're still available.
# Instead of outcome-lost once Defender is gone, as for the -defender-removed variants above.
outcome-lost-defender-removed = The installer stopped without reporting a result, and some changes may already have been made. You can try again. If it stops again, choose Send a report.
restart-now-message = Windows is restarting to finish setting up Vanta.
# "Restart later" is restart-dont-now, the button under it.
restart-countdown =
    { $seconds ->
        [one] Windows restarts in { $seconds } second to finish setting up Vanta. To save your work first, choose Restart later.
       *[other] Windows restarts in { $seconds } seconds to finish setting up Vanta. To save your work first, choose Restart later.
    }
restart-stopped = Automatic restart cancelled. Save your work, then restart your PC to finish setting up Vanta.
restart-needed = Save your work, then restart your PC to finish setting up Vanta.
restart-dont-now = Restart later
restart-now = Restart now
restart-start-failed = Vanta couldn't restart your PC. Save your work, then restart it from the Start menu. Details: { $error }
preflight-title = Installation hasn't started
preflight-invalid-options = Vanta couldn't use these setup choices. Return to Your choices and review them, then try again. Details: { $error }
# $problems is a sentence or two built from preflight-problem and preflight-security.
preflight-changed = Your PC's status changed after the earlier checks. Resolve the following before trying again. { $problems }
preflight-problem = { $title }: { $detail }
# $summary is the Windows Security summary such as "2 still on".
preflight-security = Windows Security: { $summary }.
# "Install Vanta" is button-install: after a refusal the footer's button always reads it.
preflight-busy = Another Vanta window is starting an installation. Wait a moment, then choose Install Vanta again.
# Shown with the home-start-over button.
preflight-taken-over = Another Vanta window is now using this setup, so installation hasn't started. Continue in that window, or choose Start over to set up again here.
preflight-record-unreadable = Vanta couldn't check whether the previous installation is still running, so it hasn't started another one. Return to Get ready to see what to do next. Details: { $error }

# "Install Vanta" is button-install: after a refusal the footer's button always reads it.
# "Send a report" is report-title, in the diagnostics under the bar.
preflight-refused = Couldn't start the installer. No installation changes were made. Choose Install Vanta to try again. If it keeps happening, choose Send a report. Details: { $error }
# Instead of preflight-refused when retrying an installation an earlier attempt had already
# started applying. "Install Vanta" is button-install, as for preflight-refused.
preflight-refused-resumed = Couldn't start the installer, so this attempt stopped. An earlier attempt already started making changes. Choose Install Vanta to try again. If it keeps happening, choose Send a report. Details: { $error }
go-to-ready = Return to Get ready
# Button on the preflight banner when the setup choices could not be used; leads to step 2.
go-to-options = Return to Your choices
# Replaces Continue on a choice opened from a Change link on the Install step, while Continue leads straight back there.
go-to-install = Return to Install
output-problem-title = Couldn't read installation progress
output-problem-message = Vanta couldn't read the log. This doesn't mean installation has stopped. Keep your PC on and try opening the log file. Details: { $error }
install-elevate-title = Vanta needs permission to install
install-no-package-title = Choose your installation files first
install-no-package-message = Return to Get ready to download Vanta or open a saved Vanta package (.vantapkg).
# Tester build variant of install-no-package-message.
install-no-package-bundled-message = Return to Get ready to prepare the Vanta package included with this app.
# Step 4 when step 1 is incomplete for this session (checks or Windows updates), with go-to-ready as the button.
install-not-ready-title = Finish Get ready first
install-not-ready-message = Vanta needs to finish checking your PC and updating Windows before it can install.
install-security-title = Check antivirus protection before installing
install-security-reading = Checking the four protection switches again.
install-security-message = { $summary }. Open Windows Security and make sure all four switches are off before installing.
summary-try-again = Review before trying again
summary-ready = Review your Vanta setup
summary-activation = Activation
summary-activation-ok = Activated. Vanta won't change this.
summary-activation-missing = Not activated. You can continue, but Vanta won't activate Windows.
summary-activation-unknown = Vanta won't change your Windows activation status.
summary-duration = Estimated time
summary-duration-value =
    { $minutes ->
        [one] { $minutes } minute, then a restart
       *[other] { $minutes } minutes, then a restart
    }
summary-restart-checkbox = Restart my PC automatically after installation
summary-show-command = Show installation command
summary-hide-command = Hide installation command
# Accessible name of the Copy button under the installation command.
summary-copy-command-a11y = Copy installation command
summary-command-unavailable = Couldn't prepare the installation command. Details: { $error }
summary-not-chosen = No choice made yet
# Accessible name of a Change link. $title is a screen-*-title message.
summary-change-a11y = Change { $title }
# The summary's first row on an update or reinstall. Its value is update-path-keep or
# update-path-choose.
summary-update-path = How Vanta updates
footer-still-checking = Preparing for installation

footer-fix-items = Fix the items in PC checks to continue
footer-need-package = Download Vanta or open an Vanta package to continue
# Tester build variant of footer-need-package.
footer-need-package-bundled = Prepare the bundled Vanta package to continue
footer-reading-security = Checking the protection switches
# Windows Security footer hints: while a switch is on, then while only switches Vanta
# couldn't read are left to confirm.
footer-security-pending = Turn off all four switches to continue
footer-security-confirm = To continue, confirm the switches Vanta couldn't read
# Beside Install Vanta while automatic restart is on: the PC restarts when installation finishes.
footer-install-ready = Save your work and close your apps first
button-install = Install Vanta
log-earlier-lines =
    { $count ->
        [one] { $count } earlier line is in the log file.
       *[other] { $count } earlier lines are in the log file.
    }
# Appended when the log is copied. $path is a file path (text).
log-full-log-note = (full log: { $path })

## The installing view

installing-checking-title = One last check
installing-checking-line = Vanta is checking your PC before making changes. This may take a moment.
installing-title = Installing Vanta
installing-phase-preflight = Checking your PC and preparing the installation files.
installing-phase-staging = Getting the installation files ready. Keep your PC on.
installing-phase-applying = Keep your PC on and plugged in while Vanta sets up Windows.
installing-phase-done = Finishing the installation. Keep your PC on.
installing-installed-title = Vanta is installed
# $time is a formatted clock time.
installing-started-just-now = Started at { $time }, less than a minute ago
installing-started-minutes =
    { $minutes ->
        [one] Started at { $time }, a minute ago
       *[other] Started at { $time }, { $minutes } minutes ago
    }
# Under the progress bar while installing, when the PC is set to restart by itself after.
installing-restart-auto = Your PC restarts automatically when installation finishes. Save your work in other apps before then.

## The "Vanta is installed" window after the restart

installed-title-version = Vanta { $version } is installed
installed-title = Vanta is installed
installed-ready = You're all set. Your PC is ready to use with Vanta.
# After an installation that kept Microsoft Defender, under home-security-reminder-title.
# $switches names the switches that read off, as Windows Security names them, joined like a list.
installed-security-message = You kept Microsoft Defender, but some of its protection is still off. Open Windows Security and make sure these are on: { $switches }.
# After an installation that removed Microsoft Defender.
installed-defender-removed-title = Microsoft Defender was removed
# After an installation that removed Microsoft Defender (and SmartScreen with it).
installed-defender-removed-message = Your PC won't have antivirus protection until you install another antivirus app. SmartScreen was removed too, so Windows won't warn you before you open unrecognised apps or downloads.
# Home and the "Vanta is installed" window, after an installation that kept Microsoft Defender,
# when it is missing and no Vanta package removed it. Its title is security-banner-missing-title;
# "Report a problem" is home-report-problem, its button.
installed-defender-missing-message = You chose to keep Microsoft Defender, but it's missing, and Vanta didn't remove it. If you don't use another antivirus app, install one to protect your PC. If you didn't remove Defender yourself, choose Report a problem.
# Home and the "Vanta is installed" window, when Vanta's record kept Microsoft Defender but
# Vanta's own package still removes it. "Choose again" is update-path-choose. 7. Security,
# Defender and Toggle Defender are folder and file names in the Vanta folder, and Enable
# Windows Defender is an answer Toggle Defender offers; all of them are in English on every PC.
installed-defender-not-restored-title = Microsoft Defender is still removed
installed-defender-not-restored-message = You chose to keep Microsoft Defender, but an earlier Vanta update didn't bring it back, so your PC has no antivirus. To bring it back, update or reinstall Vanta and select Choose again, or open 7. Security > Defender in the Vanta folder on your desktop, run Toggle Defender, choose Enable Windows Defender and restart your PC.
# The "Vanta is installed" window, when what the installation recorded for some choices isn't
# what was chosen. $choices lists their names, such as "Microsoft Defender", joined with
# list-and. "Open log file" is common-open-log-file, its button.
choices-not-applied-title = Some choices didn't take effect
choices-not-applied-message = Vanta recorded what this PC has now for { $choices }. The installation log says why.

## Settings

settings-title = Settings
settings-theme = App theme
settings-theme-system = Match Windows
settings-theme-light = Light
settings-theme-dark = Dark
settings-theme-contrast-note = Vanta is using the colours from your Windows contrast theme.
settings-theme-mica-note = To show the translucent background, choose the same light or dark theme as Windows.
settings-language = Language
settings-language-system = Match Windows
# What the closed language box shows while Match Windows is chosen. $language is the
# name, in its own language, of the language Match Windows gives, for example
# "English (United Kingdom)". Use your language's brackets.
settings-language-system-selected = { settings-language-system } ({ $language })
# Under the language box while a particular language is chosen: what Match Windows
# would give instead. $language is a language's own name.
settings-language-system-detail = With Match Windows: { $language }

# A short tag after each language in the list that is translated but not yet reviewed
# by a native speaker.
settings-language-preview-tag = Preview
# Under the language box, once, explaining the Preview tag.
settings-language-preview-note = Preview translations haven't been reviewed by a native speaker yet.
# A bar at the top of the content while a preview translation is in use, until the user
# dismisses it (common-dismiss names its close button). $language is the language's own
# name; preview-notice-switch and preview-notice-language are its links.
preview-notice = { $language } is a preview translation and may contain mistakes.
preview-notice-switch = Switch to English
preview-notice-language = Change language
# $tag is a language tag (text).
settings-language-unavailable = { $tag } isn't available in this version of Vanta. English is shown for now, and your language choice is saved.
# $languages is the Windows display-language list (text).
settings-language-windows-unmatched = Vanta doesn't yet support your Windows display languages ({ $languages }). English is shown for now.
settings-language-windows-unavailable = Couldn't check your Windows display language. Vanta is using English for now. Details: { $error }
# $locale is the regional format's own name, for example "English (United Kingdom)".
settings-language-formats = Numbers, dates and times follow your Windows regional format ({ $locale }).
# Instead of settings-language-formats when the regional format writes dates or times
# right to left. $locale is the format's English name, for example "Arabic (Saudi Arabia)".
settings-language-formats-numbers-only = Numbers follow your Windows regional format ({ $locale }). Dates and times use a standard format because Vanta can't show right-to-left text yet.
settings-language-contribute = Help translate Vanta
settings-usage-analytics = Share screen visits, ISO builds and install outcomes with Vanta
settings-restart-label = Restart my PC automatically after installation
settings-restart-locked = You can change this after installation finishes.
settings-restart-description = When this is on, your PC restarts within 10 seconds after installation finishes, which closes your open apps. Save your work before you install.
# Card title over Send a report and Export diagnostics.
settings-help = Help and feedback
settings-about = About
settings-about-app = Vanta Manager
settings-about-version = Version
settings-about-licence = Licence
settings-about-licence-value = Vanta © contributors, GPL-3.0
settings-about-gpl-link = Read GPL-3.0 licence
settings-about-based-on = Based on
settings-about-based-on-value = Based on AtlasOS 0.6.0 (GPL-3.0)
settings-about-atlas-link = AtlasOS on GitHub
settings-about-fonts = Fonts
settings-about-fonts-value = Geist and Geist Mono (OFL-1.1, Vercel)
settings-about-fonts-link = Geist OFL-1.1 licence
settings-about-source = Source code
# $version is the Vanta release version (text).
settings-about-source-value = Complete corresponding source code comes with every release in Vanta-{ $version }-source.zip and Vanta-{ $version }-third-party-sources.zip.
settings-about-source-link = Repository on GitHub
settings-about-releases-link = Releases on GitHub
settings-about-network = Network
settings-about-network-value = Vanta queries api.github.com only to fetch winget manifests and releases, with no personal data sent.
# Link that opens the third-party licence notices.
settings-view-licences = Open THIRD-PARTY-NOTICES.txt
# Under the links when Windows could not open the notices.
settings-licences-failed = Couldn't open THIRD-PARTY-NOTICES.txt. Try again, or find it in the licences folder.
settings-open-data-folder = Open app folder

## Optional choices: explanations shown before selection.

consequence-disable-hibernation = Frees the disk space used to save your session during hibernation. Hibernate and Fast Startup will be unavailable.
consequence-disable-power-saving = Disables power-saving features. Your PC may use more power, run hotter and have shorter battery life.
consequence-disable-core-isolation = Turns off an extra layer of Windows security, including memory integrity. This reduces protection and may affect apps or games that require it.
consequence-remove-snipping-tool = Removes the Windows app for taking screenshots and screen recordings.
consequence-uninstall-edge = Removes the Microsoft Edge browser. Make sure you have another browser, or choose one below.
# Instead of consequence-uninstall-edge when Vanta is installed on this PC, which has the
# user's Edge data. "choose one below" refers to the browser choice under it.
consequence-uninstall-edge-data = Removes Microsoft Edge and deletes your Edge bookmarks, history and saved passwords on this PC. Anything not synced to your Microsoft account is lost. Make sure you have another browser, or choose one below.
# Under Remove Microsoft Edge in the Install step's summary, with a caution glyph.
caution-uninstall-edge = Deletes your Edge bookmarks, history and saved passwords on this PC.
consequence-install-another-browser = Choose a browser below and Vanta will install it for you.
consequence-install-toolbox = Add Vanta Toolbox to help manage your Vanta settings. Toolbox is in beta, so some features may be unfinished.
consequence-install-eclean = A maintenance tool from the team behind Vanta, for keeping your PC tidy after setup. Review junk files and startup apps. Requires an account and an internet connection.

# Introduction on the home page before Vanta is installed.
home-intro = Vanta adjusts Windows to reduce background activity and distractions. Install Vanta on a fresh installation of Windows, before you add your own apps and files.

## ISO creation
iso-home-title = Windows installation media
iso-home-description = Create a Windows installation file (ISO) that includes Vanta, then use it to reinstall Windows on this PC or another one.
iso-open = Create an Vanta ISO
iso-title = Create an Vanta ISO
iso-recommended = Recommended
# "Relaunch as administrator" is common-restart-as-administrator.
iso-admin-description = Vanta needs administrator permission to read your Windows ISO and create the new one. Choose Relaunch as administrator, then choose Yes when Windows asks.
iso-source = Windows ISO
# Link under the Windows ISO field. It opens Microsoft's Windows 11 download page in the browser.
iso-download-recommended = Download from Microsoft (recommended)
iso-source-question = Where should Windows come from?
iso-use-local = Choose an ISO file
iso-package-latest-label = Latest
iso-package-latest = Latest Vanta package
iso-package-unavailable = Choose an Vanta package for this version of Manager.
iso-save-name = Save as { $name }
iso-source-download = Download Windows 11 from Microsoft
iso-download-arch = Architecture
iso-download-languages = Loading languages…
iso-download-list-error = Couldn’t load the Windows languages. Try again or download the ISO from Microsoft’s website.
iso-download-file-error = Couldn’t save the ISO. Check your connection and free space, then choose a new filename and try again.
iso-download-website = Open Microsoft’s download page
iso-download-progress = Downloading Windows · { $received } of { $total }
iso-download-starting = Preparing the Windows download…
iso-output = Save the new ISO to
iso-no-file = No file selected
# Accessible name of the Browse or Save as button beside a file field: $action is
# that button's text and $field the field's label.
iso-pick-a11y = { $action }: { $field }
iso-inspect = Check files
# The question above the three ways to set up Vanta from the ISO (iso-mode-*).
iso-mode-title = How do you want to set up Vanta?
iso-mode-interactive = Make Vanta choices after sign-in
iso-mode-interactive-description = After you sign in, Vanta opens and guides you through updates, your choices and installing Vanta.
iso-mode-before = Make Vanta choices now
iso-mode-before-description = Vanta saves your choices in the ISO. After you sign in, Vanta opens and guides you through updates, then you install Vanta with these choices.
iso-package-unsupported-title = Choose a newer Vanta package
# "Make Vanta choices after sign-in" is iso-mode-interactive.
iso-package-unsupported = This Vanta package can't save Vanta choices in the ISO. Choose a newer package, or choose Make Vanta choices after sign-in.
# Shown when Check files refuses the Vanta package; $minimum as for iso-package.
iso-failed-package-unsupported = This Vanta package can't be used to create an ISO. Choose a package for Vanta { $minimum } or newer.
# Tester build: the bundled package cannot be swapped, so the only way on is the after-sign-in
# mode. Also the Your choices footer hint for any package that can't save choices.
iso-package-unsupported-bundled-title = Vanta choices can't be saved in this ISO
# "Make Vanta choices after sign-in" is iso-mode-interactive.
iso-package-unsupported-bundled = The Vanta package included with this app doesn't support ISO setup. Choose Make Vanta choices after sign-in instead.
iso-atlas-options = Vanta choices
iso-review = Review ISO
iso-review-description = Creating the ISO doesn't install anything on this PC or change your original ISO. Afterwards, Vanta can put the new ISO on a USB drive so you can reinstall Windows from it.
iso-review-files = Files
# Titles of the ISO steps in its stepper and step headings. The other two are
# iso-review-files ("Files") and step-options ("Your choices").
iso-step-windows = Windows setup
iso-step-review = Review
iso-review-package = Vanta package
iso-review-output = New ISO
iso-review-editions = Editions
iso-edition = Windows edition
iso-edition-auto = Choose during Windows Setup
iso-accept-terms = I accept the Microsoft Software License Terms for Windows
iso-architecture-x64 = x64
iso-architecture-arm64 = Arm64
# A file size; $size is a formatted number (text). Megabytes below a gigabyte.
size-megabytes = { $size } MB
size-gigabytes = { $size } GB
iso-review-account = Account name
iso-review-target = Install on
iso-review-drivers = Drivers
iso-create = Create ISO
# Heading above the list of stages (iso-stage-*) while the ISO is being created.
iso-progress-title = Creating your ISO
iso-stage-inspect = Checking your Windows ISO
iso-stage-copy = Copying Windows files
iso-stage-add-atlas = Adding Vanta
iso-stage-master = Writing the ISO file
iso-stage-verify = Checking the new ISO
iso-stage-cleanup = Finishing up
# Accessible name of one stage while the ISO is created. No "Step": the screen reader adds
# "4 of 6". $status is stepper-status-completed or one of the three below.
iso-stage-a11y = { $title }, { $status }
iso-stage-status-current = in progress
# The stage where creating the ISO stopped with an error.
iso-stage-status-failed = failed
iso-stage-status-not-started = not started
iso-progress-description = Keep Vanta open. Large images can take a while to process.
iso-cancel = Cancel creation
iso-cancelling = Waiting for a safe point to cancel
iso-cancelled = ISO creation cancelled
# "Open log folder" is iso-diagnostics, the button on the same bar.
iso-cancelled-description = Your original ISO is unchanged. If any temporary files were left behind, choose Open log folder to see where they are.
iso-complete = Your ISO is ready
# "Create installation USB" is usb-title, the button below it.
iso-complete-description = Then choose Create installation USB, and back up your files before you reinstall Windows.
iso-open-folder = Show in folder
iso-failed = Couldn't finish creating the ISO
# "Create ISO" is iso-create; "Send a report" is report-title.
iso-failed-description = Make sure your files are still where you chose them and the drive you're saving to is connected, then choose Create ISO. If it keeps failing, choose Send a report.
# Title while the Check files step fails; the messages below say why.
iso-check-failed = Couldn't check the files
# "Check files" is iso-inspect; "Send a report" is report-title.
iso-check-failed-description = Make sure the ISO and Vanta package are still where you chose them and have finished downloading, then choose Check files. If it keeps failing, choose Send a report.
# Title of the bar that asks for administrator permission. Its message is iso-admin-description,
# or elevation-declined after Windows refused the relaunch (UAC declined).
iso-elevation-title = Vanta needs permission to create an ISO
# Typed reasons reported by the image worker.
iso-failed-output-exists = A file with that name already exists. Choose Save as and enter a new filename.
iso-failed-destination = Vanta can't save the new ISO there. Choose Save as and pick a folder on this PC, such as Downloads. Network locations and drives formatted as FAT32 or exFAT, like many USB drives, can't be used.
iso-failed-space = There isn't enough free space on the destination drive. Free up space, or save the new ISO to another drive.
# Home and LTSC are the editions ISO creation drops; the others are examples it keeps.
iso-failed-edition = This ISO contains no supported Windows editions. Windows Home and LTSC aren't supported. Use an ISO that includes another edition, such as Pro, Education or Enterprise.
iso-failed-customised = This ISO already contains custom setup files, such as autounattend.xml. Choose an unmodified Windows ISO from Microsoft.
iso-failed-windows-unsupported = This Windows image isn't supported by the Vanta package. Use an unmodified 64-bit Windows 11 ISO for a version this package supports.
iso-failed-network-architecture = This PC's network drivers don't match this ISO's architecture. Go back and turn off Include this PC's network drivers, or choose an ISO for this PC.
# Shown instead of the messages that point at diagnostics when the folder the
# worker runs from couldn't be created. "Export diagnostics" is diagnostics-export.
iso-failed-unstaged = Vanta couldn't prepare its working folder, so nothing was changed. Try again. If it keeps failing, choose Export diagnostics for a bug report.
# The Vanta package file was replaced between Check files and Create ISO. "Change" is
# common-change beside "Files" (iso-review-files); "Check files" is iso-inspect.
iso-failed-package-changed = The Vanta package changed after the files were checked. Choose Change next to Files, then choose Check files.
# Opens the folder with an ISO or USB job's raw logs.
iso-diagnostics = Open log folder
iso-close-title = ISO creation is still running
iso-close-message = Keep this window open until creation or cancellation finishes. Cancelling waits for the current operation to reach a safe stopping point.
# On the ISO and USB pages while Vanta updates Windows, or puts back Windows Update settings,
# from another page. Their controls are unavailable until it finishes.
iso-locked = Vanta is busy with Windows Update. You can continue here once it finishes.
prepare-title = Update Windows and Store apps
# Notepad, Paint and Windows Terminal are examples of Store apps that may be open. Use their
# names as Windows shows them in your language.
prepare-description = Before installing, Vanta updates Windows, Microsoft Store and your Store apps. Store apps you have open, such as Notepad, Paint or Windows Terminal, may close while they update, so save your work in them first. Your PC may also need to restart.
prepare-complete = Vanta found no more Windows or Store updates to install.
# Title of the bar on the update card when Windows needs a restart; prepare-reboot is its message.
prepare-reboot-title = Restart your PC to continue
prepare-reboot = Your PC needs to restart to finish installing updates. Vanta saves your choices so far and opens again after you sign in.
# $reasons: the pending-restart markers Windows set, from the prepare-reason-* names.
prepare-reboot-reasons = Your PC needs to restart to finish installing updates ({ $reasons }). Vanta saves your choices so far and opens again after you sign in.
# Under the restart message, before its button, which restarts the PC without a countdown.
prepare-reboot-save-work = Save your work and close your apps first. Your PC restarts immediately when you choose Restart and continue.
# Shown instead of another restart when Windows asks for one again right after restarting.
prepare-restart-persists = Your PC restarted, but Windows still says it needs a restart ({ $reasons }), so restarting again probably won't help. Choose Open Windows Update and finish anything waiting there, then choose Try again. If nothing is waiting, choose Send a report.
# Names of the markers Windows sets when it wants a restart. They complete
# "Your PC needs to restart to finish installing updates (…)"; keep them short and lower
# case where the language allows.
prepare-reason-servicing = Windows servicing
prepare-reason-windows-update = Windows Update
prepare-reason-file-renames = files waiting to be replaced
prepare-reason-update-agent = the Windows Update service
prepare-reason-unknown = reason not reported
# Under prepare-failed-title. "Try again" is common-try-again, the button beside it;
# "Send a report" is report-title, in the diagnostics under it.
prepare-failed = Choose Try again. If it fails again, finish the remaining updates in Windows Update or Microsoft Store, or choose Send a report.
# Title of the error bar on the update card; the cause is its message.
prepare-failed-title = Some updates couldn't finish
# The update run ended without writing any result, for example after Vanta was closed
# while it ran. "Try again" is common-try-again, the button beside it.
prepare-ended-unconfirmed = Updating stopped before it reported a result, so Vanta can't confirm that Windows and Store apps are up to date. Choose Try again to check for updates.
# Title of the bar over prepare-ended-unconfirmed: not called a failure, as none was reported.
prepare-unconfirmed-title = Couldn't confirm the update result
prepare-affected-app = the affected app
prepare-app-in-use = Close { $app }, then try again. Windows can't update it while it's open. If you can't find its window, close it in Task Manager. If it still fails, restart your PC and try again before you open { $app }.
prepare-install-busy = Another installation or a required restart is blocking updates. Let other installations finish, restart your PC if Windows asks you to, then try again.
# Updates failed with 0x80073712, and Vanta's own repair of the component store (DISM) didn't
# fix it. "Try again" is common-try-again; the Vanta ISO is iso-open, the button beside it.
prepare-failed-component-store = Windows reports damage to its component store that stops updates from installing, and Vanta couldn't repair it. Restart your PC, then choose Try again. If updates still fail, back up your files and reinstall Windows with an Vanta ISO.
# Windows records damage to its component store that it can't repair, so Vanta stops before
# any update. The Vanta ISO is iso-open, the button beside it.
prepare-failed-component-store-unrepairable = Windows reports damage to its component store that it can't repair, which stops updates from installing. Back up your files, then reinstall Windows with an Vanta ISO.
# Causes the update worker names. The worker's own English message is shown below as a detail.
prepare-failed-session-owner = Vanta is running as a different account from the one signed in to Windows. Sign in to Windows with an administrator account, open Vanta from that account, then try again.
prepare-failed-store-missing = Microsoft Store isn't set up for your account. Open Microsoft Store once, or reinstall it if it's missing, then try again.
prepare-failed-store-battery = Microsoft Store paused updates to save battery. Plug in your PC, then try again.
prepare-failed-store-network = Microsoft Store paused updates until your PC has an unmetered connection. Connect to unmetered Wi-Fi or Ethernet, then try again.
prepare-failed-store-timeout = Store apps haven't finished updating. Finish the remaining downloads in Microsoft Store, then try again.
prepare-failed-store-passes = Microsoft Store kept offering new updates. Finish the remaining updates in Microsoft Store, then try again.
prepare-failed-manual-updates = Some Windows updates need to be finished in Windows Update. Open Windows Update, finish them, then try again.
prepare-failed-windows-passes = Windows Update kept offering new updates. Finish the remaining updates in Windows Update, then try again.
# Vanta Manager runs from a folder that links to another place (a junction or symbolic
# link). "Linked folder" and "local folder" as in usb-failed-location. Vanta keeps using
# the folder it was opened from, so trying again in the same window can't help.
prepare-failed-source-linked = Vanta Manager is in a linked folder. Close Vanta, move Vanta Manager to a local folder on this PC, then open it from there.
prepare-error-code = Error code: { $code }
prepare-open-store = Open Microsoft Store
# "Check and install updates" is prepare-start, its button in this state.
prepare-cancelled = Updating stopped. Some updates may already have been installed. Choose Check and install updates to finish before you continue.
prepare-windows-search = Checking Windows Update…
prepare-percent = { $percent }% of this stage
prepare-count = Updates completed: { $completed } of { $total }
prepare-bytes = Downloaded { $downloaded } of approximately { $total } MB
prepare-elapsed = Elapsed: { $minutes } min { $seconds } s
prepare-progress-waiting = Waiting for the update service. A percentage isn't available for this step.
prepare-progress-unchanged = No progress for { $minutes } min. Large updates can take a while, so keep Vanta open. For details, choose Open log folder.
prepare-report-delayed = Windows hasn't reported progress for { $seconds } s. Updates may still be running, so keep Vanta open.
prepare-windows-download = Downloading Windows updates…
prepare-windows-install = Installing Windows updates…
# Shown while DISM repairs Windows' component store, before updates or after one failed on it.
# DISM reports no progress, so no percentage shows with it.
prepare-windows-repair = Repairing Windows first, because it reports damage that can stop updates from installing. This can take half an hour or more.
prepare-store-search = Checking Microsoft Store…
prepare-store-install = Updating Microsoft Store and its apps…
prepare-stop-description = Vanta stops after the current step finishes. Keep Vanta open until then.
prepare-stop = Stop updating
prepare-restart = Restart and continue
prepare-start = Check and install updates
# Under the preparation button while it is unavailable. $check is the check-supported-build title.
prepare-blocked-source = Unavailable because this installation can't continue. See the message at the top of the page.
# Under the update button while it is unavailable. $check is the title of the check
# that must pass first: check-supported-build or check-administrator.
prepare-needs-build-check = Available when { $check } passes in PC checks.
# Under the preparation button, and under the Administrator check, while the installation files are still downloading or unpacking.
prepare-wait-for-package = Available when the installation files are ready.
iso-username = Local account name
iso-account-description = Windows setup creates a local account with this name, so you don't need a Microsoft account. Windows asks you to choose a password the first time you sign in.
iso-username-placeholder = Your name
# Beside the unavailable Continue button while the local account name is empty.
iso-account-empty = Enter a local account name to continue
# Keep the list of symbols exactly: Windows refuses them in account names.
iso-account-invalid = Use up to 20 characters, with no space at the start or end and none of these: " / \ [ ] : ; | = , + * ? < > @
iso-account-trailing-dot = The name can't end with a full stop.
iso-account-reserved = Windows uses this name for a built-in account. Choose another name.
# The answer file on the ISO hides these Windows setup screens.
iso-terms-in-setup = Windows Setup will ask you to accept the licence terms.
iso-privacy-defaults = This ISO skips the Microsoft account and privacy screens in Windows setup, and turns off optional data sharing and personalised offers.
prepare-drivers = How should drivers be installed?
prepare-drivers-auto = Get drivers through Windows Update
prepare-drivers-auto-detail = Windows finds drivers for your hardware. Recommended for most PCs.
prepare-drivers-manual = Install drivers myself
prepare-drivers-manual-detail = Windows Update won't install drivers, so you'll need to get them from your PC or device maker. Drivers already installed are kept.
# Get ready: under the drivers question, above its two answers.
prepare-drivers-description = Drivers let Windows use your hardware, such as graphics, sound and Wi-Fi. If you change this after updating, Vanta needs to check for updates again.
prepare-network-needed = Updates need an internet connection that isn't metered. Connect to Wi-Fi or Ethernet, then choose Try again. If you don't see any Wi-Fi networks, install your network driver first.
# Connected, but Windows found no internet access (a captive portal, or DNS or firewall filtering).
prepare-network-limited = Windows reports that this network has no internet access. Sign in to the network if it asks you to, or check your router and any DNS or firewall filtering, then try again.
# "Metered connection" is the switch's name in Windows network settings.
prepare-network-metered = This connection is metered or has a data limit. Connect to an unmetered network, or turn off Metered connection in network settings, then try again.
prepare-network-settings = Open network settings
iso-target-title = Which PC will you reinstall Windows on?
iso-target-this = This PC
# Under This PC (iso-target-this), before it's chosen.
iso-target-this-description = Vanta can add this PC's Wi-Fi and Ethernet drivers to the ISO, so Windows can go online straight after it's reinstalled.
iso-target-other = A different PC
iso-copy-network = Include this PC's network drivers
iso-network-detail = Reuse this PC's Wi-Fi and Ethernet drivers during Windows setup. You'll reconnect to Wi-Fi after reinstalling.
iso-network-source = Network driver source
iso-network-installed = Use installed drivers
iso-network-updated = Check Windows Update first
iso-network-updated-detail = Download matching drivers offered by Windows Update and keep installed drivers as a fallback. Requires an unmetered connection.
iso-stage-network-drivers = Preparing network drivers
iso-network-failed = Network drivers couldn't be prepared. Check the diagnostics, or go back and change the network driver option.
# Under iso-complete when Include this PC's network drivers was chosen but the adapters use
# drivers that come with Windows, so none were added.
iso-network-inbox = This PC's network adapters use drivers that come with Windows, so the ISO doesn't need to include them.
iso-mode-desktop = Finish setup before the desktop
iso-mode-desktop-description = Vanta saves your choices in the ISO. After you sign in, Vanta finishes updates and installation before the Windows desktop opens.
desktop-setup-description = Finish setting up your PC. Your Vanta choices are saved; you can return to Windows if you need to.
desktop-setup-exit = Continue in Windows

# Windows installation USB
usb-title = Create installation USB
usb-existing = Create a USB from an existing ISO
usb-description = Put an ISO on a USB drive so you can reinstall Windows from it. Use an ISO created by Vanta to install Vanta at the same time.
# Button that opens the file picker for an ISO, and the Open button of that picker, on the USB
# and ISO pages.
usb-choose-iso = Choose ISO
usb-drive = USB drive
# $min and $max are formatted numbers (text), in gigabytes and terabytes.
# "Refresh" is usb-refresh.
usb-empty = No USB drives found. Connect a USB drive of at least { $min } GB, then choose Refresh. Drives larger than { $max } TB, read-only drives and the drive Windows is running from aren't shown.
usb-refresh = Refresh
# Shown when the drive list could not be read.
usb-scan-failed = Check that the drive is connected, then choose Refresh. For details, choose Open log folder.
usb-scan-failed-title = Couldn't list USB drives
# Parts of a drive's detail line, joined by usb-detail-separator; empty parts are left out.
# The separator also joins an ISO's architecture and size under its name.
# $size is a formatted number of gigabytes (text); $volumes and $serial are text.
usb-drive-size = { $size } GB
usb-drive-serial = Serial: { $serial }
usb-detail-separator = { " · " }
usb-review = Review USB
usb-erase-title = Erase this USB drive?
usb-erase-description = Everything on { $drive } ({ $size } GB) will be permanently erased, including all files and partitions. Copy anything you want to keep to another drive first. Your ISO will be kept.
usb-layout = Vanta uses up to 32 GB of the drive and leaves the rest unused. The USB drive works on PCs that start in UEFI mode, which Windows 11 requires.
usb-ack = I understand that everything on this USB drive will be erased
usb-write = Erase and create USB
usb-stage-prepare = Preparing installation files…
usb-stage-format = Formatting USB…
usb-stage-copy = Copying installation files…
usb-stage-verify = Verifying USB…
usb-working = Keep Vanta open and the USB drive connected. If you cancel, an unfinished USB drive can't be used to install Windows.
# Titles of the error bar, the success bar and the close prompt while a USB is being written.
usb-failed-title = Couldn't finish creating the USB
usb-complete-title = Your USB is ready
usb-close-title = USB creation is still running
# After erasing may have begun.
usb-failed = The drive may already have been erased, so it can't be used to install Windows yet. Make sure it's connected, then choose Review USB to try again. If you reconnected it, choose Refresh and select it again first.
# Before anything on the drive was changed: in general, then for the reasons the writer reports.
usb-failed-unchanged = Your USB drive wasn't changed. Choose Open log folder to see what failed, then choose Review USB to try again.
usb-failed-iso = This ISO can't be used to create an installation USB. Choose an ISO created by Vanta, or a Windows 11 ISO from Microsoft for a version Vanta supports. Your USB drive wasn't changed.
usb-failed-location = The ISO or Vanta Manager is on this USB drive, a network location or a linked folder. Move it to a local folder on this PC, then try again. Your USB drive wasn't changed.
usb-failed-space = There isn't enough free space on the Windows drive to prepare the installation files. Free up space, then try again. Your USB drive wasn't changed.
usb-failed-fit = The installation files don't fit on this USB drive. Use a larger drive, then try again. Your USB drive wasn't changed.
# The drive no longer matched the list, before anything was erased. "Refresh" is
# usb-refresh; "Review USB" is usb-review.
usb-failed-drive-changed = The USB drive was removed, reconnected or replaced after the list was read. Choose Refresh, select the drive again, then choose Review USB. Your USB drive wasn't changed.
usb-cancelled = The drive may contain unfinished installation files. Create it again before using it to install Windows.
usb-cancelled-title = USB creation cancelled
usb-cancelled-unchanged = Your USB drive wasn't changed.
# "Eject USB" is usb-eject. F12, F11 and Esc are key names.
usb-complete = Vanta checked every file. Choose Eject USB, then back up the files on the PC you want to reinstall. Plug the drive into that PC, then start it from the USB drive using its boot menu (often F12, F11 or Esc as the PC starts).
usb-eject = Eject USB
usb-ejected = You can unplug the USB drive now. Back up the files on the PC you want to reinstall. Then start that PC from the USB drive using its boot menu (often F12, F11 or Esc as it starts).
usb-eject-failed = Close any files or windows that are using it, then try again.
usb-eject-failed-title = Couldn't eject the USB
ready-fresh-title = Vanta is made for a fresh installation of Windows
ready-fresh-description = If you've already been using Windows on this PC, back up your files and reinstall Windows before you continue. Check that Windows compatibility passes in PC checks first, so you reinstall a supported version.
# Home, LTSC and Server are the editions the check refuses; the others are examples of
# editions it accepts. Keep edition names as Windows shows them.
detail-edition-unsupported = Windows 11 Home, LTSC and Server editions aren't supported. Use another edition, such as Pro, Education or Enterprise. If Windows couldn't identify your edition, resolve that before continuing.
install-source-title = Installation unavailable
install-source-unsupported = Vanta { $source } can't be updated to { $target } directly. To use this version, back up your files and reinstall Windows.
# Before a package is chosen, so the version on offer isn't known yet.
install-source-unsupported-any = Vanta { $source } can't be updated directly. To use a newer version, back up your files and reinstall Windows.
# "Open package file" is package-open-file. $folder is a folder path (text).
install-source-resume = An installation of Vanta { $target } didn't finish, and only the Vanta { $target } package can finish it. Choose Open package file and select that Vanta package (.vantapkg). If Vanta downloaded it, it's in { $folder }.
# Tester build: only the bundled Vanta package can be installed.
install-source-resume-bundled = An installation of Vanta { $target } didn't finish. This test build can only install its bundled Vanta package, so finish that installation with the Vanta { $target } package in a release build of Vanta Manager.
# "Send a report" is report-title, a button offered with this message.
install-source-unknown = Vanta couldn't confirm what's already installed on this PC, so it won't install anything for now. Choose Send a report so the Vanta team can help.
# $problem is one of the install-source-* messages, or the outcome-* advice for a failed
# installation; $error is a raw error message or the installer's last error line (text).
install-source-details = { $problem } Details: { $error }
iso-edition-selection = Only supported editions are included. During Windows setup, choose an edition you have a Windows licence for.
detail-windows-preview = Insider builds aren't supported. Use a public release of Windows 11.
detail-windows-release-unknown = Vanta couldn't verify this Windows build as a public release. Connect to the internet and check again.
# $build is this PC's Windows build and update number, such as 26300.9807 (text).
detail-windows-release-unlisted = Build { $build } isn't in Microsoft's list of public Windows 11 releases, so Vanta can't install on it yet. Release Preview and other preview builds aren't supported. Choose Check again once Microsoft lists this build.
iso-release-unknown = Vanta couldn't confirm that this ISO is a public release of Windows 11 that the Vanta package supports. Connect to the internet, then choose Check files again. If it still fails, download the ISO from Microsoft again.
iso-release-unlisted = The Windows 11 build in this ISO isn't in Microsoft's list of public releases. Release Preview and other preview builds aren't supported. Download the ISO from Microsoft, or choose Check files again once Microsoft lists this build.
prepare-previous-worker = Updates started earlier are still running. Vanta will wait for them to finish, then you can check for updates again.

ready-used-windows-title = Windows on this PC looks used
# Its buttons are iso-open, which opens ISO creation, and ready-used-windows-dismiss.
# OneDrive, Desktop, Documents and Pictures: use the names Windows shows in your language.
ready-used-windows-description = Windows on this PC was installed at least a week ago or already has several apps. Installing Vanta here is unsupported and strongly discouraged: apps and settings you already have may not work as expected, and Vanta removes OneDrive, so files in it stop syncing and your Desktop, Documents and Pictures may look empty. Back up your files and reinstall Windows first, or continue only if you accept the risk.
ready-used-windows-dismiss = Continue anyway

# On the update card after the PC restarts mid-update. "Continue updates" is prepare-continue,
# the button beside this message.
prepare-resumed = Your PC restarted, and Vanta restored your choices so far. Choose Continue updates to finish updating before you install Vanta.
prepare-continue = Continue updates
prepare-saving-restart = Saving your choices and arranging to reopen Vanta after Windows restarts…
prepare-restart-save-failed = Your choices couldn't be saved. Try again before restarting.
prepare-restart-registration-failed = Your choices are saved, but Vanta couldn't arrange to open again after the restart. Try again, or restart your PC yourself and open Vanta after you sign in.
# The same cause as prepare-failed-source-linked, met while arranging the restart. Both ways
# on need the move, because Vanta keeps using the folder it was opened from.
prepare-restart-source-linked = Your choices are saved, but Vanta can't arrange to open again after the restart while Vanta Manager is in a linked folder. Close Vanta and move Vanta Manager to a local folder on this PC. Then open it from there, or restart your PC yourself and open it from there after you sign in.
prepare-restart-failed = Vanta couldn't restart your PC. Try again, or restart it from the Start menu. Your choices are saved, and Vanta opens again after you sign in.
diagnostics-export = Export diagnostics
diagnostics-exporting = Collecting diagnostics…
diagnostics-privacy = Send a report privately to the Vanta team, or export a diagnostics ZIP to share when you ask for help. Vanta removes your user name, PC name and email addresses from it.
# Title of the result bar after an export; its button is iso-open-folder.
diagnostics-saved = Diagnostics ZIP created
diagnostics-failed-title = Couldn't export diagnostics
# $error is the raw error (text).
diagnostics-failed = Check that your PC has free disk space, then try again. Details: { $error }

## Tester builds (embedded-package feature)

# A bar at the top of the content on a release-candidate build.
rc-banner = Vanta { $release } test build. This app installs only the bundled Vanta package.
home-status-bundled = Test build { $release }
home-status-ready = Ready to install
package-bundled = Vanta { $version } included with this app is ready to install.
rc-about-release = Test build
rc-about-commit = Source commit
rc-about-package = Bundled Vanta package (SHA-256)
iso-package-bundled = The Vanta package included with this app

check-user-account = User account
detail-user-account-ok = UAC is enabled and your account is ready for installation.
detail-user-account-not-ready = Turn on User Account Control (UAC), restart your PC, then try again. If you use the built-in Administrator account, sign in with another administrator account.
detail-user-account-work-or-school = Vanta can't be installed from a work or school (Microsoft Entra ID) account. Sign in with a local account or a Microsoft account, then try again.
detail-user-account-unknown = Vanta couldn't check your user account. Restart your PC, then reopen Vanta and check again. If this keeps happening, choose Send a report. Windows reported: { $error }

footer-prepare-required = Finish updating Windows and Store apps to continue
footer-prepare-stopping = Stopping updates after the current step…
resume-choices-title = Continuing your previous installation
resume-choices-detail = To finish that installation, Vanta restored the choices you made last time. You can't change them in Your choices until it's done.

## Voluntary reports
report-title = Send a report
report-received = Report received
# Under the report's reference, which has a line of its own with a Copy button.
report-reference = Keep this reference if you contact the Vanta team about this report. If you left contact details, the team may use them to reply, but a reply isn't guaranteed.
# Accessible name of the Copy button beside the report reference.
report-copy-reference = Copy report reference
report-another = Send another report
# Label of the choice between the two kinds of report.
report-kind = What would you like to send?
report-kind-issue = An issue
report-kind-suggestion = A suggestion
# Under "Your message", above the box, which also reads it out. $min and $max are
# numbers: the message lengths the report service accepts.
report-intro = Describe what happened or what you'd like to change ({ $min }–{ $max } characters). Don't include passwords in your message.
report-message = Your message
report-message-placeholder = I was trying to…
report-contact = Contact details (optional)
report-contact-placeholder = Email or Discord username
report-attach = Include diagnostics
# Under Include diagnostics. Part of the privacy notice the user agrees to: it says
# exactly what Vanta removes, so keep every item.
report-attach-description = Logs and system details that help find the cause. Vanta removes your user name, PC name, email addresses and known passwords or keys. Error details, hardware models and app names are kept. You can review the ZIP before sending.
# Button that collects diagnostics again after they couldn't be prepared or sent.
report-prepare = Prepare diagnostics
report-review = Review ZIP
report-prepare-failed-title = Couldn't prepare diagnostics
# $error is a raw error message (text).
report-prepare-failed = Prepare diagnostics again, or turn off Include diagnostics to send your report without them. Details: { $error }
# The privacy notice the user agrees to, with report-attach-description. Changing it means a
# new PRIVACY_VERSION in the app, the report service and the website, deployed together.
report-privacy = Vanta Manager does not send reports: nothing leaves this PC. Your message and diagnostics stay here.
report-consent = I agree to send this report and any included diagnostics to the Vanta team
# Under "Report wasn't sent", with Try again and the report website.
report-failed = Your message is still here. Check your internet connection, then choose Try again, or send your report from the report website.
report-failed-busy = The report service is busy. Your message is still here. Try again later.
# With the report website and, when diagnostics were included, Review ZIP.
report-failed-outdated = This version of Vanta Manager can no longer send reports. Your message is still here: copy it into the report website. If you included diagnostics, choose Review ZIP and attach the ZIP there too.
report-failed-diagnostics = The prepared diagnostics can't be sent. Your message is still here. Prepare diagnostics again, or turn off Include diagnostics.
# Link under a report that wasn't sent.
report-sending = Sending…
report-send = Send report

# Under the message box when Send report finds it too short or too long. $min and $max
# are numbers: the message lengths the report service accepts.
report-validation-message = Enter { $min }–{ $max } characters.

# Under the contact box. $max is a number: the longest contact details the report
# service accepts.
report-validation-contact = Keep contact details within { $max } characters.

# Under the agreement check box when Send report is chosen without it.
report-validation-consent = Confirm you agree to send this report.

report-failed-title = Report wasn't sent

## Windows version update
# Vanta moves Windows to a newer release before installing, through Windows Update.
# $release is the target release (26H2) and $current the release the PC has (24H2);
# say "Windows 11, version" before them as Microsoft does. $version is an Vanta version.

# Home, under the update button, when the update also moves Windows.
home-plan-intro = This update has two parts. Your files and apps stay. If updating Windows undoes any of Vanta's changes, Vanta puts them back.
home-plan-windows-title = Windows 11, version { $release }
home-plan-windows-detail = Vanta installs it from Windows Update. Your PC restarts to finish it.
# The same step where moving is optional.
home-plan-windows-optional = Recommended. Vanta installs it from Windows Update. Your PC restarts to finish it.
home-plan-atlas-title = Vanta { $version }
home-plan-atlas-detail = Vanta updates its files and keeps the choices you made. Your PC restarts at the end.
# $date and $until are dates.
home-end-of-updates-title = Windows 11, version { $current } stops getting security updates on { $date }
home-end-of-updates-past-title = Windows 11, version { $current } no longer gets security updates
home-end-of-updates-message = Updating to Vanta { $version } also moves this PC to Windows 11, version { $release }, which gets security updates until { $until }.

# Home, when this Windows can't take the Vanta version at all. $product is Windows'
# own name for the edition, such as Windows 11 Home.
install-windows-edition = Vanta { $version } works with Windows 11 Pro, Enterprise and Education. This PC has { $product }, so Vanta can't install on it.
# The same, on a version whose security updates end. $date is a date.
install-windows-edition-ending = Vanta { $version } works with Windows 11 Pro, Enterprise and Education. This PC has { $product }, so Vanta can't install on it. Windows 11, version { $current } stops getting security updates on { $date }. Windows Update can move this PC to a newer version.
# $releases lists the supported releases, such as "25H2 or 26H2".
install-windows-no-path = Vanta { $version } needs Windows 11, version { $releases }, and Windows Update can't move this PC there from the Windows it has. To use Vanta { $version }, back up your files and reinstall Windows with an Vanta ISO.

# Home, when Vanta changed Windows Update settings for an update and hasn't put them back.
home-update-access-title = Windows Update settings are changed for the Vanta update
# When the last check found no offer yet.
home-update-access-not-offered = Vanta turned on Windows Update to move this PC to Windows 11, version { $release }, and Windows Update hasn't offered it yet. Choose Check again, or Put back settings.
home-update-access-before = Vanta turned on Windows Update to move this PC to Windows 11, version { $release }, and hasn't finished. Continue the update, or choose Put back settings.
home-update-access-after = This PC has Windows 11, version { $release }. Finish installing Vanta, or choose Put back settings.
home-update-access-plain = Vanta turned on Windows Update to install updates and hasn't finished. Continue the update, or choose Put back settings.
home-update-access-unreadable = Vanta can't read its record of the Windows Update settings it changed, so it won't change or put back anything. Choose Send a report so the Vanta team can help.
# $error is the raw error.
home-update-access-failed = Vanta couldn't put the settings back. Try again, or choose Send a report. Details: { $error }
home-update-access-install-active = Finish installing Vanta first. Its last step puts these settings back.
home-continue-update = Continue update
home-put-back = Put back settings
home-putting-back = Putting back settings…

# Get ready: the Windows version card.
windows-card-title = Windows 11, version { $release }
windows-card-required = Vanta { $version } needs a newer version of Windows. When Vanta updates Windows below, it also installs Windows 11, version { $release } from Windows Update.
windows-card-question = Which version of Windows should this PC use?
windows-choice-move = Update to Windows 11, version { $release }
# $date is when the new version stops getting security updates.
windows-choice-move-detail = Recommended. Security updates until { $date }. One more restart.
windows-choice-keep = Keep Windows 11, version { $current }
windows-choice-keep-detail = Your PC stays on this version. Windows Update won't move it to a newer version, so moving later takes another update in Vanta Manager.
windows-card-facts = What changes
windows-fact-keep = Your files and apps stay. If the update undoes any of Vanta's changes, Vanta puts them back when it installs.
windows-fact-restart = Your PC restarts at least once more to finish it.
# Also after home-plan-windows-detail on Home: how long Windows Update can take to offer the
# new version, which Vanta waits for by itself.
transition-offer-expectation = Windows Update usually offers it within minutes but can take up to 2 hours; Vanta waits and checks for you.
windows-fact-stays = Afterwards, Windows stays on version { $release } and doesn't move to a newer version on its own.
windows-fact-removed = Version { $release } doesn't include Windows PowerShell 2.0 or the WMIC tool.
# How to undo the move: Windows may switch the new version on in place, which Update history
# can uninstall, or reinstall itself, which Go back undoes for 10 days. Update history, Go back,
# Recovery and System are Windows' own labels; use them as your language's Windows shows them.
windows-card-undo = To undo it later, uninstall the update from Update history in Windows Update. If Windows reinstalled itself to update, choose Go back under Recovery in System settings instead, within 10 days. Vanta { $version } doesn't support version { $current }, so don't undo it once Vanta { $version } is installed.
windows-card-undo-optional = To undo it later, uninstall the update from Update history in Windows Update. If Windows reinstalled itself to update, choose Go back under Recovery in System settings instead, within 10 days.
windows-terms = I accept the Microsoft Software License Terms for Windows 11, version { $release }
windows-terms-link = Read the licence terms
# Cancel is the flow's own button; Stop updating confirms it (prepare-stop).
windows-card-locked = To keep version { $current }, choose Cancel, then Stop updating.

# Get ready: the update card while Windows moves.
prepare-description-transition = Before installing, Vanta installs the updates Windows is waiting for, then Windows 11, version { $release }, then updates Microsoft Store and your Store apps. Store apps you have open may close while they update, so save your work in them first. Your PC restarts at least once.
prepare-start-transition = Update Windows to version { $release }
prepare-needs-terms = Available when you accept the licence terms in Windows 11, version { $release }.
ready-banner-not-offered-message = See Update Windows and Store apps for what you can do now.
ready-banner-transition-failed-message = See Update Windows and Store apps for what to do next.
ready-banner-terms-title = Accept the licence terms to continue
ready-banner-terms-message = They're in Windows 11, version { $release }, further down this page. Then choose Update Windows to version { $release }.

# The bar that names each Windows Update setting Vanta turns on for the update.
access-notice-title = Vanta turns Windows Update on for now
access-off = Windows Update is turned off on this PC. Vanta turns it back on while it updates Windows.
access-paused = Windows updates are paused on this PC. Vanta unpauses them while it updates Windows.
access-delayed = Monthly updates are delayed on this PC. Vanta removes the delay while it updates Windows.
# After the lines above. "As you chose" applies when an Vanta setting the user chose set them.
access-back-chosen = When Vanta { $version } is installed, these settings go back as you chose them.
access-back = When Vanta { $version } is installed, these settings go back as they were.
access-back-stop = If you stop before then, Vanta puts them back.

# The restart that finishes the new version.
prepare-reboot-transition = Windows 11, version { $release } is installed. Choose Restart and continue to finish installing it. Vanta opens again after you sign in.
prepare-reboot-commit = Windows needs one more restart to finish installing version { $release }. Vanta opens again after you sign in.
prepare-restart-commit-failed = Windows couldn't get version { $release } ready to finish at restart, so your PC didn't restart. Choose Restart and continue to try again.
prepare-reason-feature-update = the new Windows version
prepare-reason-feature-commit = finishing the new Windows version
prepare-resumed-transition = Your PC restarted. Choose Continue updates so Vanta can check that Windows 11, version { $release } finished and install any updates left.
# Under the progress bar while Windows Update has yet to offer the new version.
prepare-waiting-offer = Waiting for Windows Update to offer Windows 11, version { $release }. This usually takes a few minutes but can take up to 2 hours. You can keep using your PC; leave Vanta open.
# After a restart for the updates Windows installs before the new version.
prepare-resumed-before-move = Your PC restarted to finish installing updates. Choose Continue updates so Vanta can install any updates left, then Windows 11, version { $release }.

# Outcomes of moving Windows. Each says what changed and what to do next.
prepare-not-offered-title = Waiting for Windows Update to offer Windows 11, version { $release }
prepare-transition-failed-title = Windows couldn't move to version { $release }
prepare-failed-feature-not-offered = Windows Update can take a while to offer Windows 11, version { $release } to a PC. Your PC still has version { $current }.
# Added after the message above while Vanta looks again by itself.
prepare-offer-rechecking = Vanta checks again every 10 minutes and continues by itself as soon as Windows Update offers it. You can also choose Check again.
# Under the progress bar while Vanta waits, updated as time passes: how long it has waited,
# then when it looks again, or that it's looking now.
prepare-offer-waited =
    { $minutes ->
        [one] Waiting for { $minutes } minute.
       *[other] Waiting for { $minutes } minutes.
    }
prepare-offer-next-check =
    { $minutes ->
        [one] Next check in { $minutes } minute.
       *[other] Next check in { $minutes } minutes.
    }
prepare-offer-checking-now = Checking now.
# Added instead while Vanta isn't looking again by itself.
prepare-offer-check-again = Choose Check again to look now.
# After 2 hours of looking again without an offer.
prepare-offer-wait-ended-title = Windows Update hasn't offered Windows 11, version { $release } yet
prepare-offer-wait-ended = Windows Update didn't offer Windows 11, version { $release } within 2 hours, so Vanta stopped waiting and put your Windows Update settings back. Choose Check again later. If you can't wait, back up your files and reinstall Windows with an Vanta ISO.
# Instead of the message above when putting the settings back at the end of the wait failed.
# $error is the raw error.
prepare-offer-wait-put-back-failed = Windows Update didn't offer Windows 11, version { $release } within 2 hours, and Vanta couldn't put your Windows Update settings back. Choose Put back settings to try again. Details: { $error }
# $missing lists the hardware this PC lacks, from the two messages below.
prepare-failed-feature-hardware = This PC doesn't meet the Windows 11 hardware requirements ({ $missing }), so Windows Update won't move it to version { $release }. Your PC still has version { $current }. To use Vanta { $version }, back up your files and reinstall Windows with an Vanta ISO.
hardware-tpm = TPM 2.0
hardware-uefi = UEFI firmware
prepare-failed-feature-hidden = Windows 11, version { $release } is hidden in Windows Update on this PC. Show it again with the tool you used to hide it, then choose Try again.
# $needed and $free are whole gigabytes; $drive is a drive such as C:.
prepare-failed-feature-disk-space = Windows needs at least { $needed } GB free on drive { $drive } for this update, and it has { $free } GB. Vanta didn't change anything. Free up space, then choose Try again.
prepare-failed-feature-servicing = Windows reports damage to its component store that it can't repair, so Vanta didn't change anything. Repair Windows, then choose Try again.
prepare-failed-feature-managed = This PC gets updates from an organisation's update server, so Vanta can't move it to version { $release }. Vanta didn't change anything.
# $setting is the technical name of a Windows Update policy value or service, such as
# NoAutoUpdate or BITS, shown as it is.
prepare-failed-feature-policy = Something on this PC keeps changing { $setting } back after Vanta changes it, so Vanta can't update Windows. If an organisation manages this PC, ask them. Vanta puts back what it changed when you stop.
prepare-failed-feature-blocked = A setting Vanta didn't change keeps Windows Update from running: { $setting }. Change it so Windows Update can run, then choose Try again.
prepare-failed-feature-rolled-back = Windows couldn't finish installing version { $release } during the restart and went back to version { $current }. Your files and apps aren't affected. Choose Try again, or choose Send a report.
prepare-failed-feature-components-lost = Some of Vanta's changes are gone after the Windows update, and Windows shows no sign of having reinstalled itself, so Vanta can't tell what happened. Vanta { $version } wasn't installed. Choose Send a report so the Vanta team can help.
prepare-failed-feature-build = This PC's Windows version changed while Vanta was updating it. Choose Put back settings, then start again from Home.
prepare-failed-feature-journal = Vanta can't read its record of the Windows Update settings it changed, so it won't change or put back anything. Choose Send a report so the Vanta team can help.
# $setting is the name of a Windows Update policy value, such as TargetReleaseVersionInfo.
prepare-failed-feature-pin = A Windows Update policy on this PC, { $setting }, has a value Vanta can't record, so Vanta didn't change anything. Choose Send a report so the Vanta team can help.
prepare-failed-feature-terms = Accept the licence terms for Windows 11, version { $release }, then choose Try again.
prepare-failed-feature-failed = Windows couldn't install version { $release }. Your PC still has version { $current }. Choose Try again. If it fails again, choose Send a report.
prepare-check-again = Check again
prepare-keep-version = Keep version { $current }

# Asked before leaving the update with Windows Update settings changed.
stop-update-title = Stop updating to Vanta { $version }?
# stop-update-title for a first install or a reinstall, which so far has only updated Windows.
stop-update-title-windows = Stop updating Windows?
stop-update-before = Vanta puts back the Windows Update settings it changed. Updates Windows already installed stay installed, and your PC keeps Windows 11, version { $current }.
stop-update-after = Your PC keeps Windows 11, version { $release }. Vanta puts back the Windows Update settings it changed.
stop-update-access = Vanta puts back the Windows Update settings it changed. Updates Windows already installed stay installed.
stop-update-keep = Keep updating
# Dialog shown when the window is closed while Windows Update is turned on for an update; its
# buttons are window-close-keep and window-close-put-back.
window-close-update-access-title = Close Vanta?
window-close-update-access-message = Vanta puts back the Windows Update settings it changed before closing. You can start the update again from Home.
window-close-put-back = Put back and close
# When putting the settings back before closing failed. The reason comes first, then this
# message; the buttons are window-close-keep and window-close-close.
window-close-put-back-failed-title = Close without putting the settings back?
window-close-put-back-failed-message = If you close Vanta now, the Windows Update settings stay as Vanta changed them. When you open Vanta again, Home offers to put them back.

# The "Vanta is installed" window, when the user's choice turned Windows Update off again.
installed-update-off-again = Windows Update is off again, as you chose. While it's off, your PC doesn't get security updates.
installed-update-paused-again = Windows updates are paused again, as you chose. While they're paused, your PC doesn't get security updates.

# PC checks: Windows compatibility on a version Vanta moves from.
detail-build-transition = This PC has Windows 11, version { $current }, which this version of Vanta doesn't support. Vanta moves Windows to version { $release } when it updates Windows below.

# The first lines of a report about a Windows update that didn't finish; technical
# details follow in English.
report-transition-intro = Updating Windows for Vanta didn't finish. Details for the Vanta team:

# When Windows reinstalled itself while it moved to a newer version, instead of
# switching the new version on in place. Vanta then puts all of its changes back.
mode-rebase = Reinstall after a Windows update
history-mode-rebase = reinstall after a Windows update
ready-rebase-title = Windows reinstalled itself while it updated
# $previous is the Vanta version the PC had before.
ready-rebase-message = Windows 11, version { $release } replaced the Windows this PC had, so some of Vanta's changes are gone. Vanta { $version } puts them back, with the choices you made for Vanta { $previous }.
# Your choices after Windows reinstalled itself during a move, which put the choices of the
# Vanta it had back. "Reinstall Vanta" is home-reinstall; "Choose again" is update-path-choose.
rebase-choices-title = Your choices from Vanta { $previous }
rebase-choices-detail = Vanta uses the choices you made for Vanta { $previous }, so there's nothing to choose here. To change them afterwards, choose Reinstall Vanta, then select Choose again.
# $missing lists the choices, such as "Microsoft Defender, Mitigations".
rebase-choices-partial = Vanta uses the choices you made for Vanta { $previous }. It couldn't find these, so check them: { $missing }
# Asked before any restart Vanta makes while other people are signed in to the PC.
restart-other-title = Someone else is signed in to this PC
restart-others-title = Other people are signed in to this PC
# $names lists their account names, such as "Alex and Sam".
restart-others-message = Restarting closes their apps, and they lose unsaved work. Signed in: { $names }.
restart-others-keep = Don't restart
restart-others-restart = Restart anyway
# Microsoft Store itself, before the Store apps. Get ready's status line while it updates or is repaired.
prepare-store-self-update = Updating Microsoft Store first. It's out of date on this PC.
prepare-store-repair = Repairing Microsoft Store. This can take a few minutes.
# Under prepare-complete, once Get ready has finished.
prepare-store-updated = Microsoft Store was out of date, so Vanta updated it before your apps.
prepare-store-bootstrapped = Microsoft Store couldn't update itself, so Vanta installed the latest App Installer and Microsoft Store from Microsoft.
prepare-store-repaired = Microsoft Store wasn't working, so Vanta repaired it.
prepare-store-skipped-removed = Microsoft Store is turned off on this PC, so Vanta skipped Store app updates.
# "Repair Microsoft Store" is prepare-repair-store; "Send a report" is report-title. The Vanta
# ISO is iso-open, a button beside them.
prepare-failed-store-repair-failed = Microsoft Store can't install or update apps on this PC, and Vanta couldn't repair it. Vanta needs it working, because installing Vanta while it's broken can leave the Store and its apps broken. Choose Repair Microsoft Store to try again. If it still doesn't work, back up your files and reinstall Windows with an Vanta ISO, or choose Send a report.
prepare-repair-store = Repair Microsoft Store

screen-keyboard-title = Keyboard languages
screen-keyboard-question = Do you use multiple keyboard languages?
package-option-keyboard-shortcuts = Yes, with keyboard shortcuts
package-option-keyboard-selector = Yes, with the taskbar selector
package-option-keyboard-single = No, I use one keyboard layout
consequence-keyboard-shortcuts = Alt+Shift switches languages; Ctrl+Shift switches layouts.
consequence-keyboard-selector = Turn off Alt+Shift and Ctrl+Shift to avoid accidental switches while gaming.
package-choice-keyboard-description = Choose how you switch keyboard languages.
consequence-keyboard-single = { consequence-keyboard-selector }

# Selection mode bar at the top of the Your choices screens.
options-mode-title = Selection mode
options-mode-recommended = Recommended by Vanta
options-mode-manual = Choose manually
options-mode-recommended-detail = Applies the Vanta recommended profile only to the options on this screen (keeps VBS, phishing protection, Store and Snipping Tool; enables Brave and Vanta optimisations without changing earlier choices).
options-mode-manual-detail = Starts with all optional extras unticked so you can pick one by one, or apply Recommended by Vanta in one click.
options-mode-proceed = Continue with Recommended
prepare-ready-title = All set — click Continue below
prepare-ready-detail = Windows is ready for the next step. You can continue now.
option-recommended-label = { $label } (recommended)
option-core-isolation-unlock = I don't play Valorant or other games with anti-cheat that requires this
option-why-disable-hibernation = Benefit: frees several GB of SSD space and ensures a clean cold boot. Caution: disables hibernation and Fast Startup on laptops.
option-why-disable-power-saving = Benefit: prevents CPU clock drops and latency spikes while gaming. Caution: uses more power and shortens laptop battery life.
option-why-disable-core-isolation = Benefit: can slightly reduce CPU overhead on some PCs. Caution: lowers protection against malicious drivers and blocks strict anti-cheat games (such as Valorant/Vanguard).
option-why-disable-phishing-protection = What it does: turns off Windows warnings when typing your Windows password into unsafe sites or apps. Benefit: no meaningful FPS gain. Caution: reduces protection against password theft.
option-why-disable-gamebar = What it does: disables the Xbox Game Bar overlay and background recording (Game DVR). Benefit: frees GPU and disk overhead during games. Caution: Win+G and Game Bar clips stop working.
option-why-remove-store = What it does: removes the Microsoft Store app while keeping App Installer and winget. Benefit: fewer background updates and processes. Caution: you won't be able to install Store apps or Game Pass titles.
option-why-vanta-power = What it does: activates the Vanta power plan tuned for desktop PCs. Benefit: keeps the processor responsive without power-saving throttling in games. Caution: applies to desktops only; skipped on laptops.
option-why-vanta-memory = What it does: keeps memory compression on while turning off page combining and app pre-launch. Benefit: cuts background disk activity and helps frame-time stability. Caution: large apps may take slightly longer on first launch.
option-why-tools-on-logon = What it does: opens Vanta Tools automatically on your next sign-in after setup. Benefit: lets you install apps and fine-tune settings right away. Caution: one-time convenience with no lasting impact.
option-why-remove-snipping-tool = What it does: uninstalls Windows' built-in Snipping Tool. Benefit: removes a stock app if you prefer ShareX or Lightshot. Caution: Win+Shift+S stops working unless you install another capture tool.
option-why-uninstall-edge = Benefit: removes Edge's background updaters and services. Caution: make sure another browser is installed or selected below.
option-why-install-another-browser = Benefit: gives you a browser ready right after setup, especially useful if you remove Edge. Caution: requires an internet connection during setup.
option-why-install-eclean = Benefit: helps clean temporary files and review startup apps after setup. Caution: optional and requires an account and internet connection.
option-why-browser-brave = What it does: installs Brave, a Chromium browser with built-in ad and tracker blocking. Benefit: faster, cleaner browsing out of the box. Caution: optional Web3 features can be ignored in settings.
option-why-browser-librewolf = What it does: installs LibreWolf, a privacy-hardened Firefox fork with no telemetry. Benefit: strong anti-tracking protection by default. Caution: some sites may need cookie or fingerprinting exceptions.
option-why-browser-firefox = What it does: installs Mozilla Firefox, an independent non-Chromium browser. Benefit: strong privacy and broad extension support. Caution: a few Chromium-only web apps may behave differently.
option-why-browser-chrome = What it does: installs Google Chrome with Google account sync. Benefit: widest compatibility with websites and web apps. Caution: uses more memory and collects more data than privacy-focused browsers.
