### Vanta Manager: German (de), preview translation. Revised on 1 October 2026 from the en-GB source (i18n/en-GB/atlas.ftl).
###
### Conventions for this catalog:
### - Sie-form throughout, "Ihr PC" for the computer, Vanta or Windows as actor.
### - Buttons are short infinitive phrases ("Vanta installieren"); familiar
###   controls keep their Windows names (Zurück, Weiter, Abbrechen, Fertig).
### - "neu starten" / "Neustart" always mean the PC or Windows. Reopening the
###   Vanta Manager with administrator rights is "als Administrator ausführen".
### - Windows feature names follow the German Windows Security app
###   (Manipulationsschutz, Echtzeitschutz, Cloudbasierter Schutz, Automatische
###   Übermittlung von Beispielen, Einstellungen für Viren- & Bedrohungsschutz).
### - Product names stay as they are: Vanta, Windows, Microsoft Defender,
###   Windows-Sicherheit, Windows Update, GitHub, Discord, Vanta Toolbox,
###   Snipping Tool, LocalTest. German quotation marks („ “) mark
###   button and step names quoted inside sentences.
### - The .vantapkg file is the "Vanta-Paket" ("Paket" once that is clear; its file
###   is the "Paketdatei").
### - Plural categories: one, other.

## Shared

app-name = Vanta Manager
common-done = Fertig
common-cancel = Abbrechen
common-back = Zurück
common-next = Weiter
common-dismiss = Schließen
# Link beside a summary row that jumps back to change that choice.
common-change = Ändern
common-copy = Kopieren
# Shown where a list of options is empty.
common-none = Keine
# Accessible name of the back arrow on the Install and Settings pages.
common-back-to-home = Zurück zur Startseite
# Accessible name of the gear button in the title bar.
common-settings = Einstellungen
common-close-settings = Einstellungen schließen
common-open-windows-security = Windows-Sicherheit öffnen
# Reopens the Vanta Manager with administrator rights (UAC). Never the PC.
common-restart-as-administrator = Als Administrator ausführen
common-try-again = Erneut versuchen
common-show-details = Details anzeigen
common-hide-details = Details ausblenden
# Accessible name of a Show details or Hide details toggle. $action is common-show-details or
# common-hide-details; $section is the title of the card it opens.
common-details-a11y = { $action }, { $section }
common-open-log-file = Protokolldatei öffnen
# Accessible name of the Copy button beside the install log.
common-copy-install-log = Installationsprotokoll kopieren
common-install-log = Installationsprotokoll
# Row labels in summary cards.
common-windows = Windows
common-options = Optionen
common-package = Installationsdateien
common-installed-as = Installationsart
common-installed = Installiert
common-checking = Wird geprüft
# Joins two items in a list: "Brave, Firefox". The braces keep the space.
list-separator = { ", " }
# Joins two alternatives: "26100 oder 26200".
list-or = { $a } oder { $b }
list-and = { $a } und { $b }
# Accessible name of a message bar that announces itself: its title, then its message.
infobar-a11y = { $title }. { $message }

## Window

# Dialog shown when the window is closed while an install runs.
window-close-title = Fenster während der Installation schließen?
window-close-message = Die Installation läuft im Hintergrund weiter. Öffnen Sie Vanta erneut, um den Fortschritt und das Ergebnis zu sehen. Lassen Sie Ihren PC eingeschaltet, bis die Installation abgeschlossen ist.
# Instead of window-close-message when the installation restarts the PC afterwards: only an
# open Vanta window restarts it, so closing the window cancels that.
window-close-message-restart = Die Installation läuft im Hintergrund weiter, aber Ihr PC wird nicht automatisch neu gestartet, solange Vanta geschlossen ist. Öffnen Sie Vanta erneut, um den Fortschritt und das Ergebnis zu sehen. Lassen Sie Ihren PC eingeschaltet, bis die Installation abgeschlossen ist.
# The safe answer in every dialog shown when the window is closed, including those for ISO
# and USB creation, updates and Windows Update access.
window-close-keep = Offen lassen
window-close-close = Fenster schließen
# Dialog shown when the window is closed during the final checks, before the
# installer has started; window-close-keep and window-close-close are its buttons.
window-close-preparing-title = Fenster vor Beginn der Installation schließen?
window-close-preparing-message = Vanta prüft gerade Ihren PC und hat mit der Installation noch nicht begonnen. Wenn Sie jetzt schließen, wird die Installation nicht gestartet. Öffnen Sie Vanta erneut, um fortzufahren.
prepare-close-title = Updates laufen noch
# "Stop updating" is prepare-stop, the dialog's other button.
prepare-close-message = Lassen Sie Vanta geöffnet, während Updates laufen. Wenn Sie „Updates anhalten“ wählen, werden die Updates nach dem aktuellen Schritt angehalten und Sie können Vanta danach schließen.
# Dialog shown when the window is closed during the restart countdown after a
# successful install. Its buttons are window-close-keep, restart-now and
# window-close-restart-close.
window-close-restart-title = Vanta ohne Neustart schließen?
# „Jetzt neu starten“ is restart-now, one of this dialog's three buttons.
window-close-restart-message = Ihr PC muss neu gestartet werden, um die Einrichtung von Vanta abzuschließen. Wenn Sie Vanta jetzt schließen, wird Ihr PC nicht neu gestartet. Starten Sie ihn dann selbst neu, sobald Sie bereit sind. Speichern Sie Ihre Arbeit, bevor Sie „Jetzt neu starten“ wählen.
window-close-restart-close = Ohne Neustart schließen
# Dialog shown when the window is closed during a setup with Windows Security switches still
# off. $switches names them as Windows Security does, joined like a list. Its buttons are
# window-close-keep, common-open-windows-security and window-close-close.
window-close-protection-title = Vanta mit ausgeschaltetem Schutz schließen?
window-close-protection-message = Einige Schutzfunktionen in der Windows-Sicherheit sind noch ausgeschaltet: { $switches }. Wenn Sie Vanta nicht fertig installieren möchten, schalten Sie diese Schutzfunktionen vor dem Schließen wieder ein. Wenn Sie Vanta fertig installieren möchten, setzt Vanta die Einrichtung fort, sobald Sie es wieder öffnen.
# The Open button of the file picker for an Vanta package (.vantapkg) file, on Get ready and the
# ISO page. It's a button label, so keep it short.
file-dialog-open-package = Vanta-Paket (.vantapkg) öffnen
# Message Windows shows in its restart notification.
shutdown-comment = Vanta ist installiert. Windows wird neu gestartet, um die Einrichtung abzuschließen.
# Message Windows shows in its restart notification when "Get ready" restarts
# to finish installing Windows updates.
prepare-shutdown-comment = Vanta startet Windows neu, um die Installation der Updates abzuschließen.

## System

# "Windows 11 Pro 25H2 (Build 26200.1234)". All three values are text.
system-description = { $product } { $version } (Build { $build })

## Home page

home-not-installed = Willkommen bei Vanta
# The headline when Vanta Manager can't tell what is installed on this PC.
home-state-unknown = Vanta auf diesem PC
# The headline when Vanta is installed. $version is text.
home-version = Vanta { $version }
# $date is a formatted date.
home-installed-on = Installiert am { $date }
home-status-checking = Es wird nach Updates gesucht
# While startup checks whether another window's installation is running.
home-status-recovering = Suche nach laufender Installation
home-status-offline = Suche nach Updates fehlgeschlagen
home-status-not-checked = Noch nicht nach Updates gesucht
home-status-update = Vanta { $version } ist verfügbar
home-status-up-to-date = Auf dem neuesten Stand
home-status-newest = Neueste Version: Vanta { $version }
# An earlier installation of Vanta { $version } stopped before it finished.
home-status-unfinished = Vanta { $version } ist nicht fertig installiert
home-check-again = Erneut prüfen
# Primary button while an install is running or waiting.
home-show-install = Fortschritt anzeigen
home-continue-installing = Einrichtung fortsetzen
home-update-to = Auf Vanta { $version } aktualisieren
home-reinstall = Vanta neu installieren
home-install = Vanta installieren
home-finish-install = Vanta { $version } fertig installieren
home-start-over = Von vorn beginnen
home-restart-title = Ihr PC muss neu gestartet werden
home-security-reminder-title = Schalten Sie Ihren Schutz wieder ein
# Instead of home-security-reminder-title when no switch reads off but some couldn't be read
# (with home-security-reminder-unreadable-message).
home-security-reminder-unreadable-title = Stellen Sie sicher, dass Ihr Schutz eingeschaltet ist
home-security-reminder-message = Vanta installiert gerade nichts, aber einige Schutzfunktionen in der Windows-Sicherheit sind noch ausgeschaltet. Öffnen Sie die Windows-Sicherheit und stellen Sie sicher, dass diese eingeschaltet sind: { $switches }.
home-security-reminder-unreadable-message = Vanta konnte nicht alle Schutzschalter lesen. Prüfen Sie in der Windows-Sicherheit, ob diese eingeschaltet sind: { $switches }.
home-elevation-title = Vanta benötigt eine Berechtigung für die Installation
home-state-error-title = Ihre Vanta-Installationsdaten konnten nicht gelesen werden
home-state-error-message = Ihre Vanta-Version, Ihre Auswahl und Ihr Verlauf werden möglicherweise nicht richtig angezeigt. Wählen Sie „Erneut prüfen“, um es noch einmal zu versuchen. Details: { $error }
home-whats-new = Neu in Vanta { $version }
home-view-release = Versionshinweise auf GitHub ansehen
home-released = Veröffentlicht am { $date }
home-show-less = Weniger anzeigen
home-show-full-notes = Alle Versionshinweise anzeigen
home-your-install = Ihre Vanta-Installation
# Vanta is installed, but without the record Vanta Manager keeps (older versions didn't write one).
home-install-unrecorded = Auf diesem PC ist nicht erfasst, wie Vanta installiert wurde. Ihre Auswahl und der Installationsverlauf können daher nicht angezeigt werden.
home-history = Installationsverlauf
# One history row. $version is text, $mode one of the history-mode-* messages, $date a formatted date and time.
home-history-entry = Vanta { $version } · { $mode } · { $date }
home-how-it-works = So machen Sie Ihren PC bereit für Vanta
home-step-1-detail = Vanta prüft Ihren PC, installiert ausstehende Updates für Windows und aus dem Microsoft Store und lädt die Installationsdateien herunter. Dabei werden möglicherweise Store-Apps geschlossen und Ihr PC muss eventuell neu gestartet werden. Speichern Sie deshalb zuerst Ihre Arbeit.
# Tester build: the Vanta package is bundled, nothing is downloaded.
home-step-1-detail-bundled = Vanta prüft Ihren PC, installiert ausstehende Updates für Windows und aus dem Microsoft Store und bereitet die mitgelieferten Installationsdateien vor. Dabei werden möglicherweise Store-Apps geschlossen und Ihr PC muss eventuell neu gestartet werden. Speichern Sie deshalb zuerst Ihre Arbeit.
home-step-2-detail = Entscheiden Sie, ob Sie Microsoft Defender und den Prozessorschutz behalten, wie Windows-Updates installiert werden und welche optionalen Extras Sie möchten.
home-step-3-detail = Schalten Sie vier Schutzschalter in der Windows-Sicherheit aus, damit sie die Installation nicht blockieren. Vanta zeigt Ihnen, wie das geht.
home-step-4-detail =
    { $minutes ->
        [one] Die Installation dauert etwa eine Minute. Danach muss Ihr PC neu gestartet werden.
       *[other] Die Installation dauert etwa { $minutes } Minuten. Danach muss Ihr PC neu gestartet werden.
    }
# Accessible name of a numbered step.
home-step-a11y = Schritt { $number }: { $title }
home-report-problem = Problem melden

## How an install was done (from the state document)

mode-fresh = Erstinstallation
mode-upgrade = Update von einer früheren Version
mode-reapply = Neuinstallation derselben Version
mode-unknown = Installation
# Forms used inside a history row. German nouns stay capitalised.
history-mode-fresh = Erstinstallation
history-mode-upgrade = Update
history-mode-reapply = Neuinstallation
history-mode-unknown = Installation

## Notices on the Home page

notice-settings-reset-title = Vanta verwendet die Standardeinstellungen der App
# $error is a raw error message (text).
notice-settings-unreadable = Vanta konnte Ihre gespeicherten App-Einstellungen nicht lesen. Ihre Windows-Einstellungen sind unverändert. Details: { $error }
# $file is a file name (text).
notice-settings-damaged-kept = Die Datei mit Ihren App-Einstellungen war beschädigt und wurde zurückgesetzt. Eine Kopie der alten Datei ist als { $file } gespeichert. Details: { $error }
notice-settings-damaged = Die Datei mit Ihren App-Einstellungen war beschädigt. Vanta verwendet vorerst die Standardeinstellungen. Details: { $error }
notice-settings-not-saved-title = App-Einstellungen konnten nicht gespeichert werden
# $error is a raw error message (text).
notice-settings-not-saved = Vanta konnte Ihre letzten Änderungen nicht speichern. Sie gehen möglicherweise verloren, wenn Sie Vanta schließen. Wenn ein anderes Vanta-Fenster geöffnet ist, schließen Sie es und nehmen Sie die Änderung erneut vor. Details: { $error }
notice-session-unreadable-title = Vorherige Installation konnte nicht geprüft werden
# $path is a file path (text).
notice-session-unreadable-message = Vanta konnte nicht feststellen, ob eine frühere Installation noch läuft. Wenn Sie unsicher sind, bitten Sie die Vanta-Community um Hilfe. Nur wenn Sie sicher sind, dass keine Installation läuft, löschen Sie { $path } und versuchen Sie es erneut. Details: { $error }

## Administrator elevation

elevation-declined = Die Berechtigung wurde nicht erteilt. Versuchen Sie es erneut und wählen Sie „Ja“, wenn Windows fragt, ob Vanta Änderungen an Ihrem Gerät vornehmen darf.
elevation-declined-continue = Die Berechtigung wurde nicht erteilt. Versuchen Sie es erneut und wählen Sie „Ja“, wenn Windows fragt, ob Vanta Änderungen an Ihrem Gerät vornehmen darf. Ihre Auswahl ist gespeichert.
elevation-draft-not-saved = Vanta konnte Ihre Auswahl nicht speichern und wurde deshalb nicht als Administrator neu geöffnet. Versuchen Sie es erneut. Details: { $error }
# Shown with the home-start-over button.
elevation-taken-over = Ein anderes Vanta-Fenster verwendet jetzt diese Einrichtung, daher wurde Vanta nicht als Administrator neu geöffnet. Fahren Sie in dem anderen Fenster fort oder wählen Sie „Von vorn beginnen“, um die Einrichtung hier noch einmal zu durchlaufen.

## The install flow

step-ready = Vorbereiten
step-options = Ihre Auswahl
step-security = Windows-Sicherheit
step-install = Installieren
install-title = Vanta einrichten
# Accessible name of the row of steps.
stepper-label = Schritte der Vanta-Einrichtung
# Accessible name of one step. $status is one of the stepper-status-* messages.
stepper-step-a11y = Schritt { $number } von { $total }, { $title }, { $status }
stepper-status-completed = abgeschlossen
stepper-status-current = aktueller Schritt
stepper-status-upcoming = späterer Schritt
stepper-status-attention = erfordert Aufmerksamkeit
# Heading above each step's content.
step-heading = Schritt { $number } von { $total }: { $title }
# Accessible name of the step heading on a screen of Your choices, read when it takes focus.
# $heading is step-heading; $progress is options-progress; $question is the screen's question.
step-heading-choice-a11y = { $heading }. { $progress }: { $question }
# The same on the optional extras screen; $progress is options-progress-extras.
step-heading-extras-a11y = { $heading }. { $progress }

## Step 1: Get ready

ready-banner-busy-title = Ihr PC wird vorbereitet
ready-banner-busy-message = Vanta prüft Ihren PC und bereitet die Installationsdateien vor.
ready-banner-blocked-title = Ihr PC ist noch nicht bereit
ready-banner-blocked-message = Beheben Sie die markierten Punkte unter „PC-Prüfungen“ und wählen Sie dann „Erneut prüfen“.
ready-banner-no-package-title = Laden Sie Vanta herunter, um fortzufahren
ready-banner-no-package-message = Laden Sie Vanta unter „Installationsdateien“ herunter oder wählen Sie „Paketdatei öffnen“, wenn Sie bereits ein Vanta-Paket (.vantapkg) haben.
# The package tried needs a newer Vanta Manager. The title is also the footer's hint then.
ready-banner-manager-title = Laden Sie einen neueren Vanta Manager herunter, um fortzufahren
# "Download Vanta Manager" is manager-download, the button in Installation files (package-title).
ready-banner-manager-message = Wählen Sie unter „Installationsdateien“ „Vanta Manager herunterladen“ und verwenden Sie dann die neue Version statt dieser.
# Tester build: the bundled Vanta package couldn't be unpacked.
ready-banner-no-package-bundled-title = Bereiten Sie das mitgelieferte Vanta-Paket vor, um fortzufahren
ready-banner-no-package-bundled-message = Das in dieser App enthaltene Vanta-Paket ist noch nicht bereit. Sehen Sie sich die Karte „Installationsdateien“ an.
ready-banner-updates-title = Aktualisieren Sie Windows und die Store-Apps, um fortzufahren
ready-banner-updates-message = Wählen Sie „Updates suchen und installieren“. Wenn die Updates abgeschlossen sind, prüft Vanta Ihren PC erneut.
# While Windows and Store apps update. "Update Windows and Store apps" is prepare-title, the
# card further down the page.
ready-banner-updating-title = Windows und Store-Apps werden aktualisiert
ready-banner-updating-message = Das kann eine Weile dauern. Lassen Sie Vanta geöffnet. Den Fortschritt sehen Sie unter „Windows und Store-Apps aktualisieren“.
# After Stop updating. "Check and install updates" is prepare-start, the card's button.
ready-banner-updates-stopped-title = Aktualisierung angehalten
ready-banner-updates-stopped-message = Wählen Sie „Updates suchen und installieren“ unter „Windows und Store-Apps aktualisieren“, um die Updates abzuschließen.
# Vanta reopened after restarting the PC to continue updating. "Continue updates" is
# prepare-continue, the card's button.
ready-banner-updates-resumed-title = Ihr PC wurde neu gestartet
ready-banner-updates-resumed-message = Wählen Sie „Updates fortsetzen“ unter „Windows und Store-Apps aktualisieren“, um die Updates abzuschließen.
# Under prepare-failed-title or prepare-unconfirmed-title. "Try again" is common-try-again,
# the card's button.
ready-banner-updates-failed-message = Unter „Windows und Store-Apps aktualisieren“ erfahren Sie, was zu tun ist. Wählen Sie danach „Erneut versuchen“.
# Under prepare-reboot-title. "Restart and continue" is prepare-restart, the card's button.
ready-banner-reboot-message = Speichern Sie zuerst Ihre Arbeit und wählen Sie dann „Neu starten und fortfahren“ unter „Windows und Store-Apps aktualisieren“.
ready-banner-warnings-title = Ein paar Punkte zum Prüfen
ready-banner-warnings-message = Sie können fortfahren, aber lesen Sie zuerst die markierten Punkte unter „PC-Prüfungen“.
ready-banner-ok-title = Sie können jetzt Ihre Auswahl treffen
ready-banner-ok-message = Alle Prüfungen sind bestanden und die Installationsdateien sind bereit.

# Card title and accessible name of the list of checks.
ready-this-pc = PC-Prüfungen
ready-check-again = Erneut prüfen
ready-checks-passed =
    { $count ->
        [one] { $count } Prüfung bestanden
       *[other] { $count } Prüfungen bestanden
    }

package-title = Installationsdateien
# $received and $total are formatted numbers of megabytes (text).
package-downloading = Vanta { $version } wird heruntergeladen · { $received } von { $total } MB
package-unpacking-progress =
    { $total ->
        [one] Wird entpackt · { $done } von { $total } Datei
       *[other] Wird entpackt · { $done } von { $total } Dateien
    }
package-unpacking = Wird entpackt
package-looking = Die neueste Vanta-Version wird gesucht.
# Tester build: the bundled Vanta package is being unpacked, nothing is downloaded.
package-looking-bundled = Das mitgelieferte Vanta-Paket wird vorbereitet.
package-none = Laden Sie Vanta herunter, um die Installationsdateien zu erhalten. Wenn Sie bereits ein Vanta-Paket (.vantapkg) haben, öffnen Sie stattdessen dieses.
# The GitHub release check failed. „Neueste Version herunterladen“ is package-download-newest,
# the button offered in this state; it checks again.
package-release-failed = Vanta konnte nicht nach der neuesten Version suchen. Prüfen Sie Ihre Internetverbindung und wählen Sie dann „Neueste Version herunterladen“ oder öffnen Sie ein gespeichertes Vanta-Paket (.vantapkg).
# Short status words beside the card title.
package-status-downloading = Wird heruntergeladen
package-status-unpacking = Wird entpackt
package-status-failed = Vorbereitung fehlgeschlagen
package-status-ready = Bereit
package-status-checking = Wird geprüft
package-status-preparing = Wird vorbereitet
package-status-missing = Nicht heruntergeladen
# Accessible name of the progress bar.
package-progress = Fortschritt der Installationsdateien
package-download-again = Erneut herunterladen
package-download-version = Vanta { $version } herunterladen
package-download-newest = Neueste Version herunterladen
package-cancel-download = Download abbrechen
package-open-file = Paketdatei öffnen
# Where the package came from. $file is a file name, $path a folder path (text).
package-from-release = Vanta { $version } wurde von GitHub heruntergeladen und ist bereit zur Installation.
package-from-file = Vanta { $version } wurde aus { $file } geladen und ist bereit zur Installation.
package-unpacked = Vanta { $version } ist bereit zur Installation.
package-none-yet = Keine Installationsdateien ausgewählt
acquire-no-asset = Für Vanta { $version } gibt es keine Paketdatei zum Herunterladen. Öffnen Sie ein gespeichertes Vanta-Paket (.vantapkg), um fortzufahren.
# Shown for a package older than Vanta 0.6.0, and for a file that isn't an Vanta package, such as an
# .apbx file from an Vanta release before 0.6.
acquire-unsupported = Diese App kann Vanta 0.6.0 und neuer aus Vanta-Paketen (.vantapkg) installieren.
# A package new enough to include the installer script that this app drives, but without it.
acquire-incomplete = In Vanta { $version } fehlen Dateien, die diese App zur Installation benötigt. Laden Sie es erneut herunter oder öffnen Sie ein anderes Vanta-Paket (.vantapkg).
acquire-failed = Die Installationsdateien konnten nicht vorbereitet werden. Laden Sie sie erneut herunter oder öffnen Sie ein anderes Vanta-Paket (.vantapkg). Details: { $error }
# The download received nothing for a minute and was stopped.
acquire-stalled = Der Download reagiert nicht mehr. Prüfen Sie Ihre Internetverbindung und laden Sie die Dateien dann erneut herunter oder öffnen Sie ein gespeichertes Vanta-Paket (.vantapkg).
# Tester build: the bundled Vanta package couldn't be unpacked. Try again is the only control offered.
acquire-failed-bundled = Das mitgelieferte Vanta-Paket konnte nicht vorbereitet werden. Wählen Sie „Erneut versuchen“. Details: { $error }
# The Vanta package asks for a newer Vanta Manager than this one. $version is the version it asks for,
# such as 0.7.0. "Download Vanta Manager" is manager-download, the button beside the message.
acquire-manager-outdated = Dieses Vanta-Paket erfordert Vanta Manager { $version } oder neuer. Wählen Sie „Vanta Manager herunterladen“ und verwenden Sie dann die neue Version statt dieser.
# The same, for a package that doesn't say which version it needs.
acquire-manager-outdated-any = Dieses Vanta-Paket erfordert einen neueren Vanta Manager. Wählen Sie „Vanta Manager herunterladen“ und verwenden Sie dann die neue Version statt dieser.

## Newer Vanta Manager

# Opens the latest Vanta release on GitHub in the browser, where Vanta Manager is downloaded.
manager-download = Vanta Manager herunterladen
# A note on Home and in Settings that a newer Vanta Manager has been released. $version is its
# version, such as 0.7.0. The note doesn't stop anything; manager-download is its button.
manager-update-title = Vanta Manager { $version } ist verfügbar
manager-update-message = Vanta Manager kann sich nicht selbst aktualisieren. Laden Sie die neue Version herunter und verwenden Sie sie statt dieser.

## System checks

check-administrator = Berechtigung zur Installation
check-supported-build = Windows-Kompatibilität
check-pending-updates = Windows-Updates
check-pending-reboot = Ausstehender Neustart
check-third-party-antivirus = Andere Antivirensoftware
check-internet = Internetverbindung
check-power = Stromversorgung
check-activation = Windows-Aktivierung
# Accessible name of a check row. $state is one of the check-state-* messages.
check-a11y = { $title }: { $state }
check-state-checking = wird geprüft
check-state-passed = in Ordnung
check-state-warning = Hinweis beachten
check-state-failed-blocking = vor der Installation zu beheben
check-state-failed = Hinweis beachten
check-state-unknown = konnte nicht geprüft werden
check-fix-windows-update = Windows Update öffnen
check-fix-network = Netzwerkeinstellungen öffnen
check-fix-power = Energieeinstellungen öffnen
check-fix-activation = Aktivierung öffnen
check-fix-apps = Installierte Apps öffnen
# Check box the user ticks when the Windows Update scan could not run.
check-ack-updates = Ich habe in Windows Update nachgesehen: Es warten keine Updates auf die Installation

detail-admin-ok = Vanta hat die Berechtigung, die für die Installation nötigen Änderungen vorzunehmen.
detail-admin-missing = Führen Sie Vanta als Administrator aus. Fragt Windows um Erlaubnis, wählen Sie „Ja“.
# $builds is a list of build numbers such as "26100 oder 26200"; $build is this PC's (text).
detail-build-unsupported = Diese Vanta-Version benötigt Windows-Build { $builds }. Ihr PC hat Build { $build }. Installieren Sie eine unterstützte Windows-Version, bevor Sie fortfahren.
detail-build-missing = Dieses Vanta-Paket gibt keine unterstützten Windows-Builds an. Verwenden Sie einen vollständigen Build des Pakets statt eines LocalTest-Builds.
detail-updates-none = Es warten keine Windows-Updates auf die Installation.
# $titles lists up to two update names (text); $count is the total.
detail-updates-pending =
    { $count ->
        [1] Dieses Update steht aus: { $titles }. Vanta installiert es unter „Windows und Store-Apps aktualisieren“.
        [2] Diese Updates stehen aus: { $titles }. Vanta installiert sie unter „Windows und Store-Apps aktualisieren“.
       *[other] { $count } Updates stehen aus, darunter { $titles }. Vanta installiert sie unter „Windows und Store-Apps aktualisieren“.
    }
detail-updates-unknown = Windows-Updates konnten nicht geprüft werden. Öffnen Sie Windows Update und bestätigen Sie unten, falls keine Updates warten. ({ $error })
detail-reboot-none = Windows benötigt derzeit keinen Neustart.
detail-reboot-pending = Windows muss neu gestartet werden, um frühere Änderungen abzuschließen. Wenn Sie „Updates suchen und installieren“ wählen, bittet Vanta Sie zuerst um einen Neustart.
# $reasons: the pending-restart markers Windows set, from the prepare-reason-* names.
detail-reboot-pending-reasons = Windows muss neu gestartet werden, um frühere Änderungen abzuschließen ({ $reasons }). Wenn Sie „Updates suchen und installieren“ wählen, bittet Vanta Sie zuerst um einen Neustart.
# Warning, not a block: $files lists up to three file paths Windows will replace or remove at the next restart.
detail-reboot-file-renames = Sie können fortfahren. Windows muss beim nächsten Neustart Dateien ersetzen oder entfernen ({ $files }). Manche Apps, etwa Xbox Gaming Services, verursachen das nach jedem Neustart.
detail-reboot-unknown = Es konnte nicht geprüft werden, ob Windows einen Neustart benötigt. Starten Sie Ihren PC neu, öffnen Sie Vanta erneut und prüfen Sie noch einmal. ({ $error })
detail-antivirus-none = Es wurde keine andere Antivirensoftware gefunden.
# $products is a list of product names (text).
detail-antivirus-found = Andere Antivirensoftware als Microsoft Defender kann die Installation blockieren. Deinstallieren Sie { $products } und wählen Sie dann „Erneut prüfen“.
# Warning, not a block: Security Center still lists the product but its files are gone.
detail-antivirus-stale = Die Windows-Sicherheit führt { $products } noch auf, aber die Dateien sind nicht mehr vorhanden, die Software ist also nicht mehr installiert. Vanta kann trotzdem installiert werden.
detail-antivirus-unknown = Andere Antivirensoftware konnte nicht geprüft werden. Wählen Sie „Erneut prüfen“. Wenn die Prüfung weiterhin fehlschlägt, starten Sie Ihren PC neu und prüfen Sie erneut. ({ $error })
detail-internet-ok = Sie sind verbunden. Halten Sie die Verbindung aufrecht, während Vanta Software herunterlädt und installiert.
detail-internet-missing = Stellen Sie eine Internetverbindung her und prüfen Sie dann erneut.
detail-power-mains = Ihr PC ist an das Stromnetz angeschlossen. Lassen Sie ihn angeschlossen, bis die Installation abgeschlossen ist.
detail-power-battery = Schließen Sie Ihren PC ans Stromnetz an, damit er während der gesamten Installation eingeschaltet bleibt.
detail-power-unknown = Vanta konnte nicht feststellen, ob Ihr PC am Stromnetz angeschlossen ist. Wenn es ein Laptop ist, schließen Sie ihn ans Stromnetz an und wählen Sie dann „Erneut prüfen“. Wenn das immer wieder passiert, wählen Sie „Bericht senden“.
detail-activation-ok = Windows ist aktiviert. Vanta ändert daran nichts.
detail-activation-missing = Windows ist nicht aktiviert. Sie können fortfahren, aber Vanta aktiviert Windows nicht für Sie.
detail-activation-no-licence = Windows hat keine Lizenz gemeldet. Sie können fortfahren; Vanta ändert den Aktivierungsstatus nicht.
detail-activation-unknown = Die Windows-Aktivierung konnte nicht geprüft werden. Sie können fortfahren; Vanta ändert den Aktivierungsstatus nicht. ({ $error })

## Step 2: Options

options-progress = Auswahl { $number } von { $total }
options-progress-extras = Auswahl { $number } von { $total }: optionale Extras
options-change-later = Microsoft Defender, Prozessorschutz und Update-Einstellungen können Sie später im Vanta-Ordner auf Ihrem Desktop ändern.
# Short names for each decision (summary rows) and the question each screen asks.
screen-defender-title = Microsoft Defender
screen-defender-question = Microsoft Defender behalten?
screen-mitigations-title = Prozessorschutz
screen-mitigations-question = Prozessorschutz von Windows beibehalten?
screen-updates-title = Windows Update
screen-updates-question = Wie soll Windows Updates installieren?
screen-browser-title = Browser
screen-power-title = Energie und Sicherheit
screen-apps-title = Apps
screen-optional-apps-title = Optionale Apps
screen-choose-one-title = Option wählen
screen-extras-title = Optionale Extras
# Question for a required choice this app has no specific wording for.
screen-generic-question = Wählen Sie eine Option für { $title }
learn-more-defender = Mehr über Microsoft Defender erfahren
learn-more-mitigations = Mehr über Prozessorschutz erfahren
learn-more-updates = Mehr über Windows Update erfahren
learn-more-browser = Mehr über Browser erfahren
learn-more-power = Mehr über Energie und Sicherheit erfahren
learn-more-apps = Mehr über Apps erfahren
learn-more-eclean = Wie eclean mit Vanta zusammenarbeitet
learn-more-generic = Einrichtungsanleitung lesen
# One line under the chosen answer: what it means for the PC.
consequence-defender-enable = Behält den integrierten Virenschutz von Windows bei, der hilft, Ihren PC vor Viren und anderen Bedrohungen zu schützen.
consequence-defender-disable = Entfernt auch SmartScreen. Ihr PC hat keinen Virenschutz, bis Sie eine andere Antivirensoftware installieren, und Windows warnt Sie nicht mehr, bevor Sie nicht erkannte Apps oder Downloads öffnen.
consequence-mitigations-default = Behält den Standardschutz von Windows gegen Prozessorschwachstellen und gegen Angriffe bei, die Fehler in Apps ausnutzen.
consequence-mitigations-disable = Schaltet auch den Exploit-Schutz für Apps aus, etwa den Ablaufsteuerungsschutz (CFG). Das verringert die Sicherheit. Ein möglicher Leistungsunterschied hängt von Ihrem Prozessor ab.
consequence-auto-updates-disable = Öffnen Sie regelmäßig Windows Update, um Updates zu installieren. Update-Benachrichtigungen bleiben eingeschaltet.
consequence-auto-updates-default = Windows installiert Updates automatisch, einschließlich Sicherheitskorrekturen.

## Vanta package text
## Labels and descriptions for the Vanta package's options and choices, by
## their ids in the package's vanta.json. The app shows these in place of the
## package's own English text; an option or choice that a newer package adds,
## which has no message here, shows the package's English.

package-option-defender-enable = Microsoft Defender behalten
package-option-defender-disable = Microsoft Defender entfernen
package-option-mitigations-default = Prozessorschutz behalten
package-option-mitigations-disable = Prozessorschutz ausschalten
package-option-auto-updates-disable = Updates selbst installieren
package-option-auto-updates-default = Updates automatisch installieren
package-option-disable-hibernation = Ruhezustand ausschalten

package-option-disable-phishing-protection = Turn off Enhanced Phishing Protection (Windows stops warning when you type your password into a known phishing site)
package-option-disable-gamebar = Turn off Game Bar and game capture
package-option-remove-store = Remove the Microsoft Store (App Installer and winget stay)
package-option-vanta-power = Use the Vanta power plan (desktop PCs only; skipped on laptops)
package-option-vanta-memory = Use the Vanta memory profile (memory compression on, page combining and app pre-launch off)
package-option-tools-on-logon = Open Vanta Tools the next time I sign in
package-option-disable-power-saving = Energiesparen ausschalten
package-option-disable-core-isolation = Virtualisierungsbasierte Sicherheit (VBS) ausschalten
package-option-remove-snipping-tool = Snipping Tool entfernen
package-option-uninstall-edge = Microsoft Edge entfernen
package-option-install-another-browser = Browser installieren
package-option-install-eclean = eclean installieren
package-option-browser-brave = Brave
package-option-browser-librewolf = LibreWolf
package-option-browser-firefox = Firefox
package-option-browser-chrome = Chrome
package-choice-defender-description = Microsoft Defender ist der in Windows integrierte Virenschutz. Entfernen Sie ihn nur, wenn Sie die Risiken kennen und eine andere Antivirensoftware verwenden möchten. Unabhängig von Ihrer Wahl schaltet Vanta die Intelligente App-Steuerung, den Erweiterten Phishingschutz und „Mein Gerät suchen“ aus.

package-choice-protections-description = Windows protections that stay on unless you turn them off. Nothing here is turned off by default.
package-choice-vanta-description = Vanta extras. All are off unless you tick them.
package-choice-mitigations-description = Diese Schutzfunktionen, auch Mitigationen genannt, helfen, Ihren PC vor Prozessorschwachstellen wie Spectre und Meltdown und vor Angriffen zu schützen, die Fehler in Apps ausnutzen. Es wird empfohlen, die Standardeinstellungen von Windows beizubehalten.
package-choice-auto-updates-description = Wählen Sie, wie Windows nach Abschluss der Vanta-Installation Updates installiert (anders als in Schritt 1, der diesen PC vorher vorbereitet). Sie können Windows Updates automatisch installieren lassen oder selbst installieren. In beiden Fällen hält Vanta Windows auf der aktuellen Version, die Sicherheitskorrekturen nur erhält, bis Microsoft den Support dafür beendet. Vanta schaltet außerdem automatische Updates für Microsoft Store-Apps aus; aktualisieren Sie diese im Microsoft Store.
package-choice-browser-description = Wählen Sie einen Browser, der installiert werden soll. Vanta ändert Ihre Browsereinstellungen nicht.

## Step 3: Windows Security

security-banner-reading-title = Windows-Sicherheit wird geprüft
security-banner-reading-message = Vanta prüft die vier Schutzschalter unten.
security-banner-off-title = Alle vier Schutzschalter sind aus
# Shown instead of the switch list when Microsoft Defender isn't on this PC and the user
# chose to remove it.
security-banner-absent-title = Microsoft Defender ist auf diesem PC nicht installiert
security-banner-absent-message = In diesem Schritt müssen Sie nichts ausschalten. Wählen Sie „Weiter“.
security-banner-off-message = Wählen Sie „Weiter“, um Ihre Einrichtung zu überprüfen und Vanta zu installieren.
security-banner-on-title = Virenschutz in der Windows-Sicherheit ausschalten
security-banner-on-message = Microsoft Defender kann die Änderungen blockieren, die Vanta vornimmt. Wählen Sie „Windows-Sicherheit öffnen“ und schalten Sie jeden unten aufgeführten Schalter aus. Wenn Sie Microsoft Defender behalten, schalten Sie die Schalter nach Abschluss der Installation wieder ein.
# The page name in Windows Security.
security-list-title = Einstellungen für Viren- & Bedrohungsschutz
security-switch-off = Aus
security-switch-on = Ein
security-switch-unreadable = Nicht lesbar
security-switch-reading = Wird geprüft
security-all-off = Alle aus
# Accessible name of a switch row. $state is one of the security-switch-* messages.
security-a11y = { $title }: { $state }
# Parts of the summary "2 noch eingeschaltet und 1 nicht lesbar".
security-count-still-on = { $count } noch eingeschaltet
security-count-unreadable = { $count } nicht lesbar
security-count-join = { $a } und { $b }
security-unknown-title = Bestätigen Sie die Schalter, die Vanta nicht lesen konnte
security-unknown-message = Stellen Sie sicher, dass in der Windows-Sicherheit alle vier Schalter aus sind, und bestätigen Sie das dann unten.
security-acknowledge = Ich habe in der Windows-Sicherheit nachgesehen und alle vier Schalter sind aus
security-unknown-unelevated-title = Vanta benötigt eine Berechtigung, um den Schutz zu prüfen
security-unknown-unelevated-message = Führen Sie Vanta als Administrator aus, damit es die Einstellungen von Microsoft Defender lesen kann.
# The four switches, named as the German Windows Security app names them.
protection-tamper = Manipulationsschutz
protection-tamper-why = Schalten Sie diesen Schutz aus, damit Defender Vanta nicht daran hindert, die Sicherheitseinstellungen von Defender zu ändern.
protection-realtime = Echtzeitschutz
protection-realtime-why = Schalten Sie diesen Schutz aus, damit Defender die Vanta-Installationsdateien beim Prüfen nicht blockiert.
protection-cloud = Cloudbasierter Schutz
protection-cloud-why = Schalten Sie diesen Schutz aus, damit Online-Bedrohungsprüfungen die Vanta-Installationsdateien nicht blockieren.
protection-samples = Automatische Übermittlung von Beispielen
protection-samples-why = Muss aus sein, damit Defender Vanta-Dateien nicht automatisch zur Analyse an Microsoft sendet.

## Step 4: Install

# Accessible name of the progress bar.
install-progress = Installationsfortschritt
# The installation's progress shown beside the bar. $percent is a whole number from 0 to 99.
install-percent = { $percent } %
outcome-succeeded-title = Vanta ist installiert
outcome-lost-title = Installationsergebnis konnte nicht bestätigt werden
outcome-failed-title = Installation nicht abgeschlossen
outcome-requirements = Ihr PC hat die Voraussetzungen für die Installation nicht erfüllt. Die Installation hat nichts geändert. Gehen Sie zurück zu „Vorbereiten“ und führen Sie die Prüfungen erneut aus.
# The -resumed variants follow a retry of an installation an earlier attempt had already started applying.
outcome-requirements-resumed = Ihr PC hat die Voraussetzungen für die Installation nicht erfüllt, daher wurde dieser Versuch abgebrochen. Ein früherer Versuch hat bereits mit Änderungen begonnen. Gehen Sie zurück zu „Vorbereiten“ und führen Sie die Prüfungen erneut aus.
outcome-not-elevated = Vanta hatte keine Administratorrechte. Die Installation hat nichts geändert. Führen Sie Vanta als Administrator aus und versuchen Sie es dann erneut.
outcome-not-elevated-resumed = Vanta hatte keine Administratorrechte, daher wurde dieser Versuch abgebrochen. Ein früherer Versuch hat bereits mit Änderungen begonnen. Führen Sie Vanta als Administrator aus und versuchen Sie es dann erneut.
# The installer's live check found Windows or Store updates unfinished. „Vorbereiten“ offers the
# update check again; „Updates suchen und installieren“ is prepare-start, its button in that state.
outcome-preparation-stale = Vanta konnte nicht bestätigen, dass Windows und die Store-Apps auf dem neuesten Stand sind, daher wurde die Installation abgebrochen, bevor Windows geändert wurde. Gehen Sie zurück zu „Vorbereiten“ und wählen Sie „Updates suchen und installieren“.
outcome-preparation-stale-resumed = Vanta konnte nicht bestätigen, dass Windows und die Store-Apps auf dem neuesten Stand sind, daher wurde dieser Versuch abgebrochen. Ein früherer Versuch hat jedoch bereits mit Änderungen begonnen. Gehen Sie zurück zu „Vorbereiten“ und wählen Sie „Updates suchen und installieren“.
outcome-failed-preflight = Die Installation ist abgebrochen, bevor etwas geändert wurde. Sie können es erneut versuchen. Wenn sie wieder abbricht, wählen Sie „Bericht senden“.
outcome-failed-staging = Die Installation ist beim Vorbereiten der Dateien abgebrochen, bevor Windows geändert wurde. Sie können es erneut versuchen. Wenn sie wieder abbricht, wählen Sie „Bericht senden“.
outcome-failed-applying = Einige Änderungen wurden möglicherweise bereits vorgenommen. Sie können es erneut versuchen. Wenn Sie hier aufhören, schalten Sie die zuvor ausgeschalteten Schutzfunktionen in der Windows-Sicherheit wieder ein, sofern sie noch verfügbar sind.
outcome-failed-applying-defender-removed = Einige Änderungen wurden möglicherweise bereits vorgenommen. Sie können es erneut versuchen. Wenn die Installation wieder abbricht, wählen Sie „Bericht senden“.
outcome-failed-resumed = Dieser Versuch wurde vorzeitig abgebrochen, aber ein früherer Versuch hat bereits mit Änderungen begonnen. Sie können es erneut versuchen. Wenn Sie hier aufhören, schalten Sie die zuvor ausgeschalteten Schutzfunktionen in der Windows-Sicherheit wieder ein, sofern sie noch verfügbar sind.
outcome-failed-resumed-defender-removed = Dieser Versuch wurde vorzeitig abgebrochen, aber ein früherer Versuch hat bereits mit Änderungen begonnen. Sie können es erneut versuchen. Wenn die Installation wieder abbricht, wählen Sie „Bericht senden“.
outcome-failed-repeated = Dieser Versuch wurde mit demselben Fehler abgebrochen wie der vorherige, und einige Änderungen wurden möglicherweise bereits vorgenommen. Es erneut zu versuchen, ohne etwas zu ändern, hilft wahrscheinlich nicht. Wählen Sie „Bericht senden“, damit das Vanta-Team die Ursache finden kann. Wenn Sie hier aufhören, schalten Sie die zuvor ausgeschalteten Schutzfunktionen in der Windows-Sicherheit wieder ein, sofern sie noch verfügbar sind.
outcome-failed-repeated-defender-removed = Dieser Versuch wurde mit demselben Fehler abgebrochen wie der vorherige, und einige Änderungen wurden möglicherweise bereits vorgenommen. Es erneut zu versuchen, ohne etwas zu ändern, hilft wahrscheinlich nicht. Wählen Sie „Bericht senden“, damit das Vanta-Team die Ursache finden kann.
outcome-failed-repeated-apps = Windows hat { $apps } weiterhin nicht entfernt, daher wurde dieser Versuch mit demselben Fehler abgebrochen wie der vorherige. Einige Änderungen wurden möglicherweise bereits vorgenommen. Es erneut zu versuchen, ohne etwas zu ändern, hilft wahrscheinlich nicht. Wählen Sie „Bericht senden“, damit das Vanta-Team die Ursache finden kann. Wenn Sie hier aufhören, schalten Sie die zuvor ausgeschalteten Schutzfunktionen in der Windows-Sicherheit wieder ein, sofern sie noch verfügbar sind.
outcome-failed-repeated-apps-defender-removed = Windows hat { $apps } weiterhin nicht entfernt, daher wurde dieser Versuch mit demselben Fehler abgebrochen wie der vorherige. Einige Änderungen wurden möglicherweise bereits vorgenommen. Es erneut zu versuchen, ohne etwas zu ändern, hilft wahrscheinlich nicht. Wählen Sie „Bericht senden“, damit das Vanta-Team die Ursache finden kann.
outcome-not-started = Das Installationsprogramm ist nicht rechtzeitig gestartet. Die Installation hat nichts geändert. Sie können es erneut versuchen.
outcome-lost = Das Installationsprogramm wurde beendet, ohne ein Ergebnis zu melden, und einige Änderungen wurden möglicherweise bereits vorgenommen. Sie können es erneut versuchen. Wenn Sie hier aufhören, schalten Sie die zuvor ausgeschalteten Schutzfunktionen in der Windows-Sicherheit wieder ein, sofern sie noch verfügbar sind.
outcome-lost-defender-removed = Das Installationsprogramm wurde beendet, ohne ein Ergebnis zu melden, und einige Änderungen wurden möglicherweise bereits vorgenommen. Sie können es erneut versuchen. Wenn das Installationsprogramm wieder abbricht, wählen Sie „Bericht senden“.
restart-now-message = Windows wird neu gestartet, um die Einrichtung von Vanta abzuschließen.
restart-countdown =
    { $seconds ->
        [one] Windows startet in { $seconds } Sekunde neu, um die Einrichtung von Vanta abzuschließen. Wenn Sie zuerst Ihre Arbeit speichern möchten, wählen Sie „Später neu starten“.
       *[other] Windows startet in { $seconds } Sekunden neu, um die Einrichtung von Vanta abzuschließen. Wenn Sie zuerst Ihre Arbeit speichern möchten, wählen Sie „Später neu starten“.
    }
restart-stopped = Automatischer Neustart abgebrochen. Speichern Sie Ihre Arbeit und starten Sie dann Ihren PC neu, um die Einrichtung von Vanta abzuschließen.
restart-needed = Speichern Sie Ihre Arbeit und starten Sie dann Ihren PC neu, um die Einrichtung von Vanta abzuschließen.
restart-dont-now = Später neu starten
restart-now = Jetzt neu starten
restart-start-failed = Vanta konnte Ihren PC nicht neu starten. Speichern Sie Ihre Arbeit und starten Sie den PC dann über das Startmenü neu. Details: { $error }
preflight-title = Installation wurde nicht gestartet
preflight-invalid-options = Vanta konnte diese Auswahl nicht verwenden. Gehen Sie zurück zu „Ihre Auswahl“, überprüfen Sie sie und versuchen Sie es dann erneut. Details: { $error }
# $problems is a sentence or two built from preflight-problem and preflight-security.
preflight-changed = Der Zustand Ihres PCs hat sich seit den letzten Prüfungen geändert. Beheben Sie Folgendes, bevor Sie es erneut versuchen. { $problems }
preflight-problem = { $title }: { $detail }
# $summary is the Windows Security summary such as "2 noch eingeschaltet".
preflight-security = Windows-Sicherheit: { $summary }.
preflight-busy = Ein anderes Vanta-Fenster startet gerade eine Installation. Warten Sie einen Moment und wählen Sie dann erneut „Vanta installieren“.
# Shown with the home-start-over button.
preflight-taken-over = Ein anderes Vanta-Fenster verwendet jetzt diese Einrichtung, daher wurde die Installation nicht gestartet. Fahren Sie in dem anderen Fenster fort oder wählen Sie „Von vorn beginnen“, um die Einrichtung hier noch einmal zu durchlaufen.
preflight-record-unreadable = Vanta konnte nicht prüfen, ob die vorherige Installation noch läuft, und hat deshalb keine neue gestartet. Gehen Sie zurück zu „Vorbereiten“, um zu sehen, wie es weitergeht. Details: { $error }
preflight-refused = Das Installationsprogramm konnte nicht gestartet werden. Die Installation hat nichts geändert. Wählen Sie „Vanta installieren“, um es erneut zu versuchen. Wenn das immer wieder passiert, wählen Sie „Bericht senden“. Details: { $error }
# Instead of preflight-refused when retrying an installation an earlier attempt had already started applying.
preflight-refused-resumed = Das Installationsprogramm konnte nicht gestartet werden, daher wurde dieser Versuch abgebrochen. Ein früherer Versuch hat bereits mit Änderungen begonnen. Wählen Sie „Vanta installieren“, um es erneut zu versuchen. Wenn das immer wieder passiert, wählen Sie „Bericht senden“. Details: { $error }
go-to-ready = Zurück zu „Vorbereiten“
go-to-options = Zurück zu „Ihre Auswahl“
# Replaces Weiter on a choice opened from a Change link on the Install step, while Weiter leads straight back there.
go-to-install = Zurück zu „Installieren“
output-problem-title = Installationsfortschritt konnte nicht gelesen werden
output-problem-message = Vanta konnte das Protokoll nicht lesen. Das bedeutet nicht, dass die Installation gestoppt wurde. Lassen Sie Ihren PC eingeschaltet und versuchen Sie, die Protokolldatei zu öffnen. Details: { $error }
install-elevate-title = Vanta benötigt eine Berechtigung für die Installation
install-no-package-title = Wählen Sie zuerst Ihre Installationsdateien
install-no-package-message = Gehen Sie zurück zu „Vorbereiten“, um Vanta herunterzuladen oder ein gespeichertes Vanta-Paket (.vantapkg) zu öffnen.
# Tester build variant of install-no-package-message.
install-no-package-bundled-message = Gehen Sie zurück zu „Vorbereiten“, um das in dieser App enthaltene Vanta-Paket vorzubereiten.
# Step 4 when step 1 is incomplete for this session (checks or Windows updates), with go-to-ready as the button.
install-not-ready-title = Schließen Sie zuerst „Vorbereiten“ ab
install-not-ready-message = Vanta muss die Prüfung Ihres PCs und die Windows-Updates abschließen, bevor es installieren kann.
install-security-title = Virenschutz vor der Installation prüfen
install-security-reading = Die vier Schutzschalter werden noch einmal geprüft.
install-security-message = { $summary }. Öffnen Sie die Windows-Sicherheit und stellen Sie sicher, dass alle vier Schalter aus sind, bevor Sie installieren.
summary-try-again = Vor dem nächsten Versuch überprüfen
summary-ready = Ihre Vanta-Einrichtung überprüfen
summary-activation = Aktivierung
summary-activation-ok = Aktiviert. Vanta ändert daran nichts.
summary-activation-missing = Nicht aktiviert. Sie können fortfahren, aber Vanta aktiviert Windows nicht.
summary-activation-unknown = Vanta ändert den Aktivierungsstatus von Windows nicht.
summary-duration = Geschätzte Dauer
summary-duration-value =
    { $minutes ->
        [one] { $minutes } Minute, dann ein Neustart
       *[other] { $minutes } Minuten, dann ein Neustart
    }
summary-restart-checkbox = PC nach der Installation automatisch neu starten
summary-show-command = Installationsbefehl anzeigen
summary-hide-command = Installationsbefehl ausblenden
summary-copy-command-a11y = Installationsbefehl kopieren
summary-command-unavailable = Der Installationsbefehl konnte nicht erstellt werden. Details: { $error }
summary-not-chosen = Noch nicht gewählt
# Accessible name of a Change link. $title is a screen-*-title message.
summary-change-a11y = { $title } ändern
footer-still-checking = Installation wird vorbereitet
footer-fix-items = Beheben Sie die Punkte unter „PC-Prüfungen“, um fortzufahren
footer-need-package = Laden Sie Vanta herunter oder öffnen Sie ein Vanta-Paket, um fortzufahren
# Tester build variant of footer-need-package.
footer-need-package-bundled = Bereiten Sie das mitgelieferte Vanta-Paket vor, um fortzufahren
footer-reading-security = Schutzschalter werden geprüft
footer-security-pending = Stellen Sie alle vier Schalter auf „Aus“, um fortzufahren
footer-security-confirm = Bestätigen Sie die Schalter, die Vanta nicht lesen konnte, um fortzufahren
footer-install-ready = Speichern Sie zuerst Ihre Arbeit und schließen Sie Ihre Apps
button-install = Vanta installieren
log-earlier-lines =
    { $count ->
        [one] { $count } frühere Zeile steht in der Protokolldatei.
       *[other] { $count } frühere Zeilen stehen in der Protokolldatei.
    }
# Appended when the log is copied. $path is a file path (text).
log-full-log-note = (vollständiges Protokoll: { $path })

## The installing view

installing-checking-title = Eine letzte Prüfung
installing-checking-line = Vanta prüft Ihren PC, bevor Änderungen vorgenommen werden. Das kann einen Moment dauern.
installing-title = Vanta wird installiert
installing-phase-preflight = Ihr PC wird geprüft und die Installationsdateien werden vorbereitet.
installing-phase-staging = Die Installationsdateien werden bereitgestellt. Lassen Sie Ihren PC eingeschaltet.
installing-phase-applying = Windows wird mit Ihrer Auswahl eingerichtet. Lassen Sie Ihren PC eingeschaltet und am Stromnetz.
installing-phase-done = Die Installation wird abgeschlossen. Lassen Sie Ihren PC eingeschaltet.
installing-installed-title = Vanta ist installiert
# $time is a formatted clock time.
installing-started-just-now = Gestartet um { $time }, vor weniger als einer Minute
installing-started-minutes =
    { $minutes ->
        [one] Gestartet um { $time }, vor einer Minute
       *[other] Gestartet um { $time }, vor { $minutes } Minuten
    }
installing-restart-auto = Ihr PC wird automatisch neu gestartet, wenn die Installation abgeschlossen ist. Speichern Sie bis dahin Ihre Arbeit in anderen Apps.

## The "Vanta is installed" window after the restart

installed-title-version = Vanta { $version } ist installiert
installed-title = Vanta ist installiert
installed-ready = Alles erledigt. Ihr PC ist mit Vanta einsatzbereit.
installed-security-message = Sie haben Microsoft Defender behalten, aber einige seiner Schutzfunktionen sind noch ausgeschaltet. Öffnen Sie die Windows-Sicherheit und stellen Sie sicher, dass diese eingeschaltet sind: { $switches }.
installed-defender-removed-title = Microsoft Defender wurde entfernt
installed-defender-removed-message = Ihr PC hat keinen Virenschutz, bis Sie eine andere Antivirensoftware installieren. SmartScreen wurde ebenfalls entfernt, daher warnt Windows Sie nicht mehr, bevor Sie nicht erkannte Apps oder Downloads öffnen.
# Home and the "Vanta is installed" window, after an installation that kept Microsoft Defender,
# when it is missing and no Vanta package removed it. Its title is security-banner-missing-title;
# "Report a problem" is home-report-problem, its button.
installed-defender-missing-message = Sie haben sich entschieden, Microsoft Defender zu behalten, aber er fehlt, und Vanta hat ihn nicht entfernt. Wenn Sie keine andere Antivirensoftware verwenden, installieren Sie eine, um Ihren PC zu schützen. Wenn Sie Defender nicht selbst entfernt haben, wählen Sie „Problem melden“.

## Settings

settings-title = Einstellungen
settings-theme = App-Design
settings-theme-system = Wie Windows
settings-theme-light = Hell
settings-theme-dark = Dunkel
settings-theme-contrast-note = Vanta verwendet die Farben Ihres Windows-Kontrastdesigns.
settings-theme-mica-note = Der durchscheinende Hintergrund wird angezeigt, wenn Sie dasselbe helle oder dunkle Design wie Windows wählen.
settings-language = Sprache
settings-language-system = Wie Windows
settings-language-system-selected = { settings-language-system } ({ $language })
# Under "Wie Windows": which language that gives. $language is a language's own name.
settings-language-system-detail = Bei „Wie Windows“: { $language }
# A short tag under each language that is translated but not yet reviewed by a native speaker.
settings-language-preview-tag = Vorschau
# Under the language list, once, explaining the Vorschau tag.
settings-language-preview-note = Vorschau-Übersetzungen wurden noch nicht muttersprachlich geprüft.
preview-notice = { $language } ist eine Vorschau-Übersetzung und kann Fehler enthalten.
preview-notice-switch = Zu Englisch wechseln
preview-notice-language = Sprache ändern
# $tag is a language tag (text).
settings-language-unavailable = { $tag } ist in dieser Version von Vanta nicht verfügbar. Vorerst wird Englisch angezeigt; Ihre Sprachauswahl bleibt gespeichert.
# $languages is the Windows display-language list (text).
settings-language-windows-unmatched = Vanta unterstützt Ihre Windows-Anzeigesprachen ({ $languages }) noch nicht. Vorerst wird Englisch angezeigt.
settings-language-windows-unavailable = Ihre Windows-Anzeigesprache konnte nicht ermittelt werden. Vanta verwendet vorerst Englisch. Details: { $error }
# $locale is the regional format's own name, for example "Deutsch (Deutschland)".
settings-language-formats = Zahlen, Datum und Uhrzeit folgen Ihrem regionalen Format in Windows ({ $locale }).
# Instead of settings-language-formats when the regional format writes dates or times
# right to left. $locale is the format's English name, for example "Arabic (Saudi Arabia)".
settings-language-formats-numbers-only = Zahlen folgen Ihrem regionalen Format in Windows ({ $locale }). Datum und Uhrzeit werden in einem Standardformat angezeigt, da Vanta noch keinen Text von rechts nach links darstellen kann.
settings-language-contribute = Beim Übersetzen von Vanta auf GitHub helfen
settings-usage-analytics = Seitenaufrufe, ISO-Erstellungen und Installationsergebnisse mit Vanta teilen
settings-restart-label = PC nach der Installation automatisch neu starten
settings-restart-locked = Sie können das ändern, sobald die Installation abgeschlossen ist.
settings-restart-description = Wenn diese Option eingeschaltet ist, wird Ihr PC innerhalb von 10 Sekunden nach Abschluss der Installation neu gestartet. Dabei werden Ihre geöffneten Apps geschlossen. Speichern Sie Ihre Arbeit, bevor Sie installieren.
settings-help = Hilfe und Feedback
settings-about = Info
settings-about-app = Vanta Manager
settings-about-version = Version
settings-about-licence = Lizenz
settings-about-licence-value = Vanta © Mitwirkende, GPL-3.0
settings-about-gpl-link = GPL-3.0-Lizenz lesen
settings-about-based-on = Basiert auf
settings-about-based-on-value = Basiert auf AtlasOS 0.6.0 (GPL-3.0)
settings-about-atlas-link = AtlasOS auf GitHub
settings-about-fonts = Schriftarten
settings-about-fonts-value = Geist und Geist Mono (OFL-1.1, Vercel)
settings-about-fonts-link = Geist OFL-1.1-Lizenz
settings-about-source = Quellcode
# $version is the Vanta release version (text).
settings-about-source-value = Der vollständige zugehörige Quellcode liegt jeder Veröffentlichung in Vanta-{ $version }-source.zip und Vanta-{ $version }-third-party-sources.zip bei.
settings-about-source-link = Repository auf GitHub
settings-about-releases-link = Veröffentlichungen auf GitHub
settings-about-network = Netzwerk
settings-about-network-value = Vanta fragt api.github.com nur ab, um winget-Manifeste und -Versionen zu laden; es werden keine personenbezogenen Daten gesendet.
# Link that opens the third-party licence notices.
settings-view-licences = THIRD-PARTY-NOTICES.txt öffnen
# Under the links when Windows could not open the notices.
settings-licences-failed = THIRD-PARTY-NOTICES.txt konnte nicht geöffnet werden. Versuchen Sie es erneut oder suchen Sie die Datei im Lizenzordner.
settings-open-data-folder = App-Ordner öffnen

## Optional choices: explanations shown before selection.

consequence-disable-hibernation = Gibt den Speicherplatz frei, in dem Ihre Sitzung im Ruhezustand gespeichert wird. Ruhezustand und Schnellstart stehen dann nicht mehr zur Verfügung.
consequence-disable-power-saving = Schaltet Energiesparfunktionen aus. Ihr PC verbraucht dann möglicherweise mehr Strom, wird wärmer und hält im Akkubetrieb kürzer durch.
consequence-disable-core-isolation = Schaltet eine zusätzliche Sicherheitsebene von Windows aus, einschließlich der Speicherintegrität. Das verringert den Schutz und kann Apps oder Spiele beeinträchtigen, die darauf angewiesen sind.
consequence-remove-snipping-tool = Entfernt die Windows-App für Screenshots und Bildschirmaufnahmen.
consequence-uninstall-edge = Entfernt den Browser Microsoft Edge. Stellen Sie sicher, dass Sie einen anderen Browser haben, oder wählen Sie unten einen aus.
# Instead of consequence-uninstall-edge when Vanta is installed on this PC, which has the
# user's Edge data. "choose one below" refers to the browser choice under it.
consequence-uninstall-edge-data = Entfernt Microsoft Edge und löscht Ihre Favoriten, Ihren Verlauf und Ihre gespeicherten Kennwörter in Edge auf diesem PC. Alles, was nicht mit Ihrem Microsoft-Konto synchronisiert ist, geht verloren. Stellen Sie sicher, dass Sie einen anderen Browser haben, oder wählen Sie unten einen aus.
# Under Remove Microsoft Edge in the Install step's summary, with a caution glyph.
caution-uninstall-edge = Löscht Ihre Favoriten, Ihren Verlauf und Ihre gespeicherten Kennwörter in Edge auf diesem PC.
consequence-install-another-browser = Wählen Sie unten einen Browser aus; Vanta installiert ihn für Sie.
consequence-install-toolbox = Mit Vanta Toolbox verwalten Sie Ihre Vanta-Einstellungen. Toolbox ist in der Betaphase, einige Funktionen sind daher möglicherweise noch nicht fertig.
consequence-install-eclean = Ein Wartungstool vom Team hinter Vanta, mit dem Sie Ihren PC nach der Einrichtung aufräumen können. Prüfen Sie überflüssige Dateien und Autostart-Apps. Erfordert ein Konto und eine Internetverbindung.

# Introduction on the home page before Vanta is installed.
home-intro = Vanta passt Windows so an, dass weniger im Hintergrund läuft und weniger ablenkt. Installieren Sie Vanta direkt nach einer Neuinstallation von Windows, bevor Sie eigene Apps und Dateien hinzufügen.

## ISO creation
iso-home-title = Windows-Installationsmedium
iso-home-description = Erstellen Sie eine Windows-Installationsdatei (ISO) mit Vanta und installieren Sie damit Windows auf diesem oder einem anderen PC neu.
iso-open = Vanta-ISO erstellen
iso-title = Vanta-ISO erstellen
iso-recommended = Empfohlen
iso-admin-description = Vanta benötigt Administratorrechte, um Ihre Windows-ISO zu lesen und die neue zu erstellen. Wählen Sie „Als Administrator ausführen“ und dann „Ja“, wenn Windows nachfragt.
iso-source = Windows-ISO
iso-download-recommended = Von Microsoft herunterladen (empfohlen)
iso-source-question = Woher soll Windows kommen?
iso-use-local = ISO-Datei auswählen
iso-package-latest-label = Aktuell
iso-package-latest = Neuestes Vanta-Paket
iso-package-unavailable = Wähle ein Vanta-Paket für diese Manager-Version.
iso-save-name = Speichern als { $name }
iso-source-download = Windows 11 bei Microsoft herunterladen
iso-download-arch = Architektur
iso-download-languages = Sprachen werden geladen…
iso-download-list-error = Die Windows-Sprachen konnten nicht geladen werden. Versuche es erneut oder lade die ISO von Microsoft herunter.
iso-download-file-error = Die ISO konnte nicht gespeichert werden. Prüfe die Verbindung und den freien Speicherplatz und versuche es mit einem neuen Dateinamen erneut.
iso-download-website = Microsofts Downloadseite öffnen
iso-download-progress = Windows wird heruntergeladen · { $received } von { $total }
iso-download-starting = Windows-Download wird vorbereitet…
iso-output = Neue ISO speichern unter
iso-no-file = Keine Datei ausgewählt
# Accessible name of the Browse or Save as button beside a file field: $action is
# that button's text and $field the field's label.
iso-pick-a11y = { $action }: { $field }
iso-inspect = Dateien prüfen
iso-mode-title = Wie möchten Sie Vanta einrichten?
iso-mode-interactive = Vanta-Auswahl nach der Anmeldung treffen
iso-mode-interactive-description = Nach der Anmeldung öffnet sich Vanta und führt Sie durch die Updates, Ihre Auswahl und die Installation von Vanta.
iso-mode-before = Vanta-Auswahl jetzt treffen
iso-mode-before-description = Vanta speichert Ihre Auswahl in der ISO. Nach der Anmeldung öffnet sich Vanta und führt Sie durch die Updates. Danach installieren Sie Vanta mit dieser Auswahl.
iso-package-unsupported-title = Neueres Vanta-Paket wählen
# „Vanta-Auswahl nach der Anmeldung treffen“ is iso-mode-interactive.
iso-package-unsupported = Dieses Vanta-Paket kann keine Vanta-Auswahl in der ISO speichern. Wählen Sie ein neueres Paket oder „Vanta-Auswahl nach der Anmeldung treffen“.
# Shown when Check files refuses the Vanta package; $minimum as for iso-package.
iso-failed-package-unsupported = Mit diesem Vanta-Paket kann keine ISO erstellt werden. Wählen Sie ein Paket für Vanta { $minimum } oder neuer.
# Tester build: the bundled Vanta package cannot be swapped, so the only way on is the after-sign-in mode.
iso-package-unsupported-bundled-title = Vanta-Auswahl kann nicht in dieser ISO gespeichert werden
# „Vanta-Auswahl nach der Anmeldung treffen“ is iso-mode-interactive.
iso-package-unsupported-bundled = Das in dieser App enthaltene Vanta-Paket unterstützt die ISO-Einrichtung nicht. Wählen Sie stattdessen „Vanta-Auswahl nach der Anmeldung treffen“.
iso-atlas-options = Vanta-Auswahl
iso-review = ISO überprüfen
iso-review-description = Beim Erstellen der ISO wird nichts auf diesem PC installiert und Ihre ursprüngliche ISO bleibt unverändert. Danach kann Vanta die neue ISO auf ein USB-Laufwerk übertragen, damit Sie Windows davon neu installieren können.
iso-review-files = Dateien
iso-step-windows = Windows-Einrichtung
iso-step-review = Überprüfung
iso-review-package = Vanta-Paket
iso-review-output = Neue ISO
iso-review-editions = Editionen
iso-edition = Windows-Edition
iso-edition-auto = Während der Windows-Installation auswählen
iso-accept-terms = Ich akzeptiere die Microsoft-Software-Lizenzbedingungen für Windows
iso-architecture-x64 = x64
iso-architecture-arm64 = Arm64
# A file size; $size is a formatted number (text). Megabytes below a gigabyte.
size-megabytes = { $size } MB
size-gigabytes = { $size } GB
iso-review-account = Kontoname
iso-review-target = Installation auf
iso-review-drivers = Treiber
iso-create = ISO erstellen
iso-progress-title = Ihre ISO wird erstellt
iso-stage-inspect = Ihre Windows-ISO wird geprüft
iso-stage-copy = Windows-Dateien werden kopiert
iso-stage-add-atlas = Vanta wird hinzugefügt
iso-stage-master = ISO-Datei wird geschrieben
iso-stage-verify = Neue ISO wird geprüft
iso-stage-cleanup = Wird abgeschlossen
# Accessible name of one stage while the ISO is created. No "Step": the screen reader adds
# "4 of 6". $status is stepper-status-completed or one of the three below.
iso-stage-a11y = { $title }, { $status }
iso-stage-status-current = läuft
# The stage where creating the ISO stopped with an error.
iso-stage-status-failed = fehlgeschlagen
iso-stage-status-not-started = noch nicht gestartet
iso-progress-description = Lassen Sie Vanta geöffnet. Die Verarbeitung großer Abbilder kann einige Zeit dauern.
iso-cancel = Erstellung abbrechen
iso-cancelling = Warten auf einen sicheren Abbruchpunkt
iso-cancelled = ISO-Erstellung abgebrochen
iso-cancelled-description = Ihre ursprüngliche ISO ist unverändert. Falls temporäre Dateien zurückgeblieben sind, wählen Sie „Protokollordner öffnen“, um zu sehen, wo sie liegen.
iso-complete = Ihre ISO ist fertig
iso-complete-description = Wählen Sie dann „Installations-USB erstellen“ und sichern Sie Ihre Dateien, bevor Sie Windows neu installieren.
iso-open-folder = Im Ordner anzeigen
iso-failed = ISO-Erstellung konnte nicht abgeschlossen werden
iso-failed-description = Stellen Sie sicher, dass Ihre Dateien noch am gewählten Ort liegen und das Laufwerk, auf dem Sie speichern, angeschlossen ist, und wählen Sie dann „ISO erstellen“. Wenn es weiterhin fehlschlägt, wählen Sie „Bericht senden“.
# Title while the Check files step fails; the messages below say why.
iso-check-failed = Dateien konnten nicht geprüft werden
iso-check-failed-description = Stellen Sie sicher, dass die ISO und das Vanta-Paket noch am gewählten Ort liegen und vollständig heruntergeladen sind, und wählen Sie dann „Dateien prüfen“. Wenn es weiterhin fehlschlägt, wählen Sie „Bericht senden“.
# Title of the bar that asks for administrator permission. Its message is iso-admin-description,
# or elevation-declined after Windows refused the relaunch (UAC declined).
iso-elevation-title = Vanta benötigt eine Berechtigung zum Erstellen einer ISO
# Typed reasons reported by the image worker.
iso-failed-output-exists = Eine Datei mit diesem Namen ist bereits vorhanden. Wählen Sie „Speichern unter“ und geben Sie einen neuen Dateinamen ein.
iso-failed-destination = Vanta kann die neue ISO dort nicht speichern. Wählen Sie „Speichern unter“ und dann einen Ordner auf diesem PC, etwa „Downloads“. Netzwerkorte und mit FAT32 oder exFAT formatierte Laufwerke können nicht verwendet werden. Das betrifft viele USB-Laufwerke.
iso-failed-space = Auf dem Ziellaufwerk ist nicht genügend freier Speicherplatz vorhanden. Geben Sie Speicherplatz frei oder speichern Sie die neue ISO auf einem anderen Laufwerk.
# Home and LTSC are the editions ISO creation drops; the others are examples it keeps.
iso-failed-edition = Diese ISO enthält keine unterstützten Windows-Editionen. Windows Home und LTSC werden nicht unterstützt. Verwenden Sie eine ISO mit einer anderen Edition, etwa Pro, Education oder Enterprise.
iso-failed-customised = Diese ISO enthält bereits angepasste Setup-Dateien wie autounattend.xml. Wählen Sie eine unveränderte Windows-ISO von Microsoft.
iso-failed-windows-unsupported = Dieses Windows-Abbild wird vom Vanta-Paket nicht unterstützt. Verwenden Sie eine unveränderte 64-Bit-ISO einer Windows-11-Version, die dieses Paket unterstützt.
iso-failed-network-architecture = Die Netzwerktreiber dieses PCs passen nicht zur Architektur dieser ISO. Gehen Sie zurück und deaktivieren Sie „Netzwerktreiber dieses PCs einbinden“ oder wählen Sie eine ISO für diesen PC.
iso-failed-unstaged = Vanta konnte seinen Arbeitsordner nicht vorbereiten, daher wurde nichts geändert. Versuchen Sie es erneut. Wenn der Fehler weiterhin auftritt, wählen Sie „Diagnose exportieren“ für einen Fehlerbericht.
iso-failed-package-changed = Das Vanta-Paket wurde nach der Prüfung der Dateien geändert. Wählen Sie „Ändern“ neben „Dateien“ und dann „Dateien prüfen“.
iso-diagnostics = Protokollordner öffnen
iso-close-title = Die ISO wird noch erstellt
iso-close-message = Lassen Sie dieses Fenster geöffnet, bis die Erstellung oder der Abbruch abgeschlossen ist. Beim Abbrechen wird gewartet, bis der laufende Vorgang sicher beendet werden kann.
# On the ISO and USB pages while Vanta updates Windows, or puts back Windows Update settings,
# from another page. Their controls are unavailable until it finishes.
iso-locked = Vanta ist gerade mit Windows Update beschäftigt. Sobald das abgeschlossen ist, können Sie hier fortfahren.
prepare-title = Windows und Store-Apps aktualisieren
prepare-description = Vor der Installation aktualisiert Vanta Windows, den Microsoft Store und Ihre Store-Apps. Geöffnete Store-Apps wie Editor, Paint oder Windows-Terminal werden beim Aktualisieren möglicherweise geschlossen. Speichern Sie deshalb vorher Ihre Arbeit darin. Möglicherweise muss Ihr PC auch neu gestartet werden.
prepare-complete = Vanta hat keine weiteren Windows- oder Store-Updates zum Installieren gefunden.
prepare-reboot-title = Starten Sie Ihren PC neu, um fortzufahren
prepare-reboot = Ihr PC muss neu gestartet werden, um die Installation der Updates abzuschließen. Vanta speichert Ihre bisherige Auswahl und öffnet sich nach der Anmeldung wieder.
# $reasons: the pending-restart markers Windows set, from the prepare-reason-* names.
prepare-reboot-reasons = Ihr PC muss neu gestartet werden, um die Installation der Updates abzuschließen ({ $reasons }). Vanta speichert Ihre bisherige Auswahl und öffnet sich nach der Anmeldung wieder.
# Under the restart message: the button restarts Windows without a countdown.
prepare-reboot-save-work = Speichern Sie zuerst Ihre Arbeit und schließen Sie Ihre Apps. Ihr PC wird sofort neu gestartet, wenn Sie „Neu starten und fortfahren“ wählen.
# Shown instead of another restart when Windows asks for one again right after restarting.
prepare-restart-persists = Ihr PC wurde neu gestartet, aber Windows meldet weiterhin, dass ein Neustart nötig ist ({ $reasons }). Ein weiterer Neustart hilft daher wahrscheinlich nicht. Wählen Sie „Windows Update öffnen“, schließen Sie dort alles ab, was noch aussteht, und wählen Sie dann „Erneut versuchen“. Wenn nichts aussteht, wählen Sie „Bericht senden“.
# Names of the markers Windows sets when it wants a restart. They complete
# "Ihr PC muss neu gestartet werden, um die Installation der Updates abzuschließen (…)";
# keep them short.
prepare-reason-servicing = Windows-Wartung
prepare-reason-windows-update = Windows Update
prepare-reason-file-renames = noch zu ersetzende Dateien
prepare-reason-update-agent = der Windows Update-Dienst
prepare-reason-unknown = Grund nicht gemeldet
prepare-failed = Wählen Sie „Erneut versuchen“. Wenn es wieder fehlschlägt, schließen Sie die restlichen Updates in Windows Update oder im Microsoft Store ab oder wählen Sie „Bericht senden“.
prepare-failed-title = Einige Updates konnten nicht abgeschlossen werden
# The update run ended without writing any result, for example after Vanta was closed
# while it ran. „Erneut versuchen“ is common-try-again, the button beside it.
prepare-ended-unconfirmed = Die Aktualisierung wurde beendet, bevor ein Ergebnis gemeldet wurde. Vanta kann daher nicht bestätigen, dass Windows und die Store-Apps auf dem neuesten Stand sind. Wählen Sie „Erneut versuchen“, um nach Updates zu suchen.
prepare-unconfirmed-title = Update-Ergebnis konnte nicht bestätigt werden
# „Updates suchen und installieren“ is prepare-start, its button in this state.
prepare-cancelled = Die Aktualisierung wurde angehalten. Einige Updates wurden möglicherweise bereits installiert. Wählen Sie „Updates suchen und installieren“, um die Updates abzuschließen, bevor Sie fortfahren.
prepare-windows-search = Windows Update wird geprüft…
prepare-windows-download = Windows-Updates werden heruntergeladen…
prepare-windows-install = Windows-Updates werden installiert…
prepare-windows-repair = Zuerst wird Windows repariert, weil es Schäden meldet, die die Installation von Updates verhindern können. Das kann eine halbe Stunde oder länger dauern.
prepare-store-search = Microsoft Store wird geprüft…
prepare-store-install = Microsoft Store und seine Apps werden aktualisiert…
prepare-stop-description = Vanta hält an, sobald der aktuelle Schritt abgeschlossen ist. Lassen Sie Vanta bis dahin geöffnet.
prepare-stop = Updates anhalten
prepare-restart = Neu starten und fortfahren
prepare-start = Updates suchen und installieren
# Under the preparation button while it is unavailable. $check is the check-supported-build title.
prepare-blocked-source = Nicht verfügbar, weil diese Installation nicht fortgesetzt werden kann. Beachten Sie die Meldung oben auf der Seite.
prepare-needs-build-check = Verfügbar, sobald die Prüfung „{ $check }“ unter „PC-Prüfungen“ bestanden ist.
# Under the preparation button, and under the Administrator check, while the installation files are still downloading or unpacking.
prepare-wait-for-package = Verfügbar, sobald die Installationsdateien bereit sind.
iso-username = Name des lokalen Kontos
iso-account-description = Bei der Windows-Einrichtung wird ein lokales Konto mit diesem Namen erstellt, Sie brauchen also kein Microsoft-Konto. Bei der ersten Anmeldung fordert Windows Sie auf, ein Kennwort festzulegen.
iso-username-placeholder = Ihr Name
iso-account-empty = Geben Sie einen Namen für das lokale Konto ein, um fortzufahren
iso-account-invalid = Verwenden Sie bis zu 20 Zeichen, ohne Leerzeichen am Anfang oder Ende und ohne diese Zeichen: " / \ [ ] : ; | = , + * ? < > @
iso-account-trailing-dot = Der Name darf nicht mit einem Punkt enden.
iso-account-reserved = Windows verwendet diesen Namen für ein integriertes Konto. Wählen Sie einen anderen Namen.
iso-terms-in-setup = Windows Setup fragt während der Installation nach deiner Zustimmung zu den Lizenzbedingungen.
iso-privacy-defaults = Diese ISO überspringt bei der Windows-Einrichtung die Seiten für Microsoft-Konto und Datenschutz und schaltet die optionale Datenfreigabe und personalisierte Angebote aus.
prepare-drivers = Wie sollen Treiber installiert werden?
prepare-drivers-auto = Treiber über Windows Update beziehen
prepare-drivers-auto-detail = Windows sucht passende Treiber für Ihre Hardware. Für die meisten PCs empfohlen.
prepare-drivers-manual = Treiber selbst installieren
prepare-drivers-manual-detail = Windows Update installiert keine Treiber. Sie müssen sie daher vom Hersteller Ihres PCs oder Geräts beziehen. Bereits installierte Treiber bleiben erhalten.
prepare-drivers-description = Mit Treibern kann Windows Ihre Hardware nutzen, etwa Grafik, Sound und WLAN. Wenn Sie dies nach dem Aktualisieren ändern, muss Vanta erneut nach Updates suchen.
prepare-network-needed = Für Updates ist eine nicht getaktete Internetverbindung erforderlich. Verbinden Sie sich mit einem WLAN oder über Ethernet und wählen Sie dann „Erneut versuchen“. Wenn Sie keine WLAN-Netzwerke sehen, installieren Sie zuerst Ihren Netzwerktreiber.
# Connected, but Windows found no internet access (a captive portal, or DNS or firewall filtering).
prepare-network-limited = Windows meldet, dass dieses Netzwerk keinen Internetzugang hat. Melden Sie sich beim Netzwerk an, falls Sie dazu aufgefordert werden, oder prüfen Sie Ihren Router sowie DNS- oder Firewall-Filter. Versuchen Sie es dann erneut.
# „Getaktete Verbindung“ is the switch's name in Windows network settings.
prepare-network-metered = Diese Verbindung ist getaktet oder hat ein Datenlimit. Verbinden Sie sich mit einem nicht getakteten Netzwerk oder schalten Sie „Getaktete Verbindung“ in den Netzwerkeinstellungen aus. Versuchen Sie es dann erneut.
prepare-network-settings = Netzwerkeinstellungen öffnen
iso-target-title = Auf welchem PC möchten Sie Windows neu installieren?
iso-target-this = Auf diesem PC
# Under This PC (iso-target-this), before it's chosen.
iso-target-this-description = Vanta kann die WLAN- und Ethernet-Treiber dieses PCs in die ISO einbinden, damit Windows direkt nach der Neuinstallation online gehen kann.
iso-target-other = Auf einem anderen PC
iso-copy-network = Netzwerktreiber dieses PCs einbinden
iso-network-detail = Verwendet die WLAN- und Ethernet-Treiber dieses PCs bei der Windows-Installation. Verbinden Sie sich danach erneut mit dem WLAN.
iso-network-source = Quelle der Netzwerktreiber
iso-network-installed = Installierte Treiber verwenden
iso-network-updated = Zuerst bei Windows Update suchen
iso-network-updated-detail = Lädt passende Treiber von Windows Update herunter und behält installierte Treiber als Reserve. Erfordert eine nicht getaktete Verbindung.
iso-stage-network-drivers = Netzwerktreiber werden vorbereitet
iso-network-failed = Die Netzwerktreiber konnten nicht vorbereitet werden. Prüfen Sie die Diagnoseinformationen oder gehen Sie zurück und ändern Sie die Netzwerktreiberoption.
# Under iso-complete when Include this PC's network drivers was chosen but the adapters use
# drivers that come with Windows, so none were added.
iso-network-inbox = Die Netzwerkadapter dieses PCs verwenden Treiber, die in Windows enthalten sind. Die ISO muss sie daher nicht einbinden.
iso-mode-desktop = Einrichtung vor dem Desktop abschließen
iso-mode-desktop-description = Vanta speichert Ihre Auswahl in der ISO. Nach der Anmeldung schließt Vanta Updates und Installation ab, bevor der Windows-Desktop geöffnet wird.
desktop-setup-description = Schließen Sie die Einrichtung Ihres PCs ab. Ihre Vanta-Auswahl ist gespeichert. Bei Bedarf können Sie zu Windows wechseln.
desktop-setup-exit = In Windows fortfahren

# Windows installation USB
usb-title = Installations-USB erstellen
usb-existing = USB aus einer vorhandenen ISO erstellen
usb-description = Übertragen Sie eine ISO auf ein USB-Laufwerk, um Windows davon neu zu installieren. Verwenden Sie eine mit Vanta erstellte ISO, um Vanta gleich mit zu installieren.
# Button that opens the file picker for an ISO, and the Open button of that picker, on the USB
# and ISO pages.
usb-choose-iso = ISO auswählen
usb-drive = USB-Laufwerk
# $min and $max are formatted numbers (text), in gigabytes and terabytes.
usb-empty = Keine USB-Laufwerke gefunden. Schließen Sie ein USB-Laufwerk mit mindestens { $min } GB an und wählen Sie dann „Aktualisieren“. Laufwerke über { $max } TB, schreibgeschützte Laufwerke und das Laufwerk, von dem Windows läuft, werden nicht angezeigt.
usb-refresh = Aktualisieren
# Shown when the drive list could not be read.
usb-scan-failed = Prüfen Sie, ob das Laufwerk angeschlossen ist, und wählen Sie dann „Aktualisieren“. Wählen Sie für Details „Protokollordner öffnen“.
usb-scan-failed-title = USB-Laufwerke konnten nicht aufgelistet werden
# Parts of a drive's detail line, joined by usb-detail-separator; empty parts are left out.
# $size is a formatted number of gigabytes (text); $volumes and $serial are text.
usb-drive-size = { $size } GB
usb-drive-serial = Seriennummer: { $serial }
usb-detail-separator = { " · " }
usb-review = USB-Auswahl prüfen
usb-erase-title = Dieses USB-Laufwerk löschen?
usb-erase-description = Der gesamte Inhalt von { $drive } ({ $size } GB) wird dauerhaft gelöscht, einschließlich aller Dateien und Partitionen. Kopieren Sie zuerst alles, was Sie behalten möchten, auf ein anderes Laufwerk. Ihre ISO bleibt erhalten.
usb-layout = Vanta belegt bis zu 32 GB des Laufwerks und lässt den Rest ungenutzt. Das USB-Laufwerk funktioniert auf PCs, die im UEFI-Modus starten. Diesen Modus setzt Windows 11 voraus.
usb-ack = Mir ist bewusst, dass der gesamte Inhalt dieses USB-Laufwerks gelöscht wird
usb-write = Löschen und USB erstellen
usb-stage-prepare = Installationsdateien werden vorbereitet…
usb-stage-format = USB wird formatiert…
usb-stage-copy = Installationsdateien werden kopiert…
usb-stage-verify = USB wird überprüft…
usb-working = Lassen Sie Vanta geöffnet und das USB-Laufwerk angeschlossen. Wenn Sie abbrechen, kann das unfertige USB-Laufwerk nicht zur Windows-Installation verwendet werden.
# Titles of the error bar, the success bar and the close prompt while a USB is being written.
usb-failed-title = USB-Erstellung konnte nicht abgeschlossen werden
usb-complete-title = Ihr USB-Stick ist bereit
usb-close-title = Der USB-Stick wird noch erstellt
# After erasing may have begun.
usb-failed = Das Laufwerk wurde möglicherweise bereits gelöscht und kann daher noch nicht zur Windows-Installation verwendet werden. Stellen Sie sicher, dass es angeschlossen ist, und wählen Sie dann „USB-Auswahl prüfen“, um es erneut zu versuchen. Wenn Sie es neu angeschlossen haben, wählen Sie zuerst „Aktualisieren“ und dann erneut das Laufwerk.
# Before anything on the drive was changed: in general, then for the reasons the writer reports.
usb-failed-unchanged = Ihr USB-Laufwerk wurde nicht verändert. Wählen Sie „Protokollordner öffnen“, um die Ursache zu sehen, und dann „USB-Auswahl prüfen“, um es erneut zu versuchen.
usb-failed-iso = Mit dieser ISO kann kein Installations-USB erstellt werden. Wählen Sie eine mit Vanta erstellte ISO oder eine Windows-11-ISO von Microsoft für eine Version, die Vanta unterstützt. Ihr USB-Laufwerk wurde nicht verändert.
usb-failed-location = Die ISO oder der Vanta Manager befindet sich auf diesem USB-Laufwerk, an einem Netzwerkort oder in einem verknüpften Ordner. Verschieben Sie die Datei in einen lokalen Ordner auf diesem PC und versuchen Sie es dann erneut. Ihr USB-Laufwerk wurde nicht verändert.
usb-failed-space = Auf dem Windows-Laufwerk ist nicht genügend Speicherplatz frei, um die Installationsdateien vorzubereiten. Geben Sie Speicherplatz frei und versuchen Sie es dann erneut. Ihr USB-Laufwerk wurde nicht verändert.
usb-failed-fit = Die Installationsdateien passen nicht auf dieses USB-Laufwerk. Verwenden Sie ein größeres Laufwerk und versuchen Sie es dann erneut. Ihr USB-Laufwerk wurde nicht verändert.
usb-failed-drive-changed = Das USB-Laufwerk wurde entfernt, neu angeschlossen oder ersetzt, nachdem die Liste gelesen wurde. Wählen Sie „Aktualisieren“, wählen Sie das Laufwerk erneut aus und wählen Sie dann „USB-Auswahl prüfen“. Ihr USB-Laufwerk wurde nicht verändert.
usb-cancelled = Das Laufwerk enthält möglicherweise unvollständige Installationsdateien. Erstellen Sie es vor der Windows-Installation erneut.
usb-cancelled-title = USB-Erstellung abgebrochen
usb-cancelled-unchanged = Ihr USB-Laufwerk wurde nicht verändert.
usb-complete = Vanta hat alle Dateien geprüft. Wählen Sie „USB auswerfen“ und sichern Sie dann die Dateien auf dem PC, auf dem Sie Windows neu installieren möchten. Schließen Sie das Laufwerk an diesen PC an und starten Sie ihn über sein Boot-Menü vom USB-Laufwerk (oft mit F12, F11 oder Esc beim Starten des PCs).
usb-eject = USB auswerfen
usb-ejected = Sie können das USB-Laufwerk jetzt abziehen. Sichern Sie die Dateien auf dem PC, auf dem Sie Windows neu installieren möchten. Starten Sie diesen PC dann über sein Boot-Menü vom USB-Laufwerk (oft mit F12, F11 oder Esc beim Starten).
usb-eject-failed = Schließen Sie alle Dateien und Fenster, die das Laufwerk verwenden, und versuchen Sie es dann erneut.
usb-eject-failed-title = USB konnte nicht ausgeworfen werden
ready-fresh-title = Vanta ist für eine Neuinstallation von Windows gedacht
ready-fresh-description = Wenn Sie Windows auf diesem PC bereits verwenden, sichern Sie Ihre Dateien und installieren Sie Windows neu, bevor Sie fortfahren. Stellen Sie vorher sicher, dass die Prüfung „Windows-Kompatibilität“ unter „PC-Prüfungen“ bestanden ist, damit Sie eine unterstützte Version neu installieren.
# Home, LTSC and Server are the editions the check refuses; the others are examples of
# editions it accepts. Keep edition names as Windows shows them.
detail-edition-unsupported = Die Editionen Home, LTSC und Server von Windows 11 werden nicht unterstützt. Verwenden Sie eine andere Edition, etwa Pro, Education oder Enterprise. Wenn Windows Ihre Edition nicht erkennen konnte, klären Sie das, bevor Sie fortfahren.
install-source-title = Installation nicht möglich
install-source-unsupported = Vanta { $source } kann nicht direkt auf { $target } aktualisiert werden. Um diese Version zu verwenden, sichern Sie Ihre Dateien und installieren Sie Windows neu.
# Before a package is chosen, so the version on offer isn't known yet.
install-source-unsupported-any = Vanta { $source } kann nicht direkt aktualisiert werden. Um eine neuere Version zu verwenden, sichern Sie Ihre Dateien und installieren Sie Windows neu.
# „Paketdatei öffnen“ is package-open-file. $folder is a folder path (text).
install-source-resume = Eine Installation von Vanta { $target } wurde nicht abgeschlossen und kann nur mit dem Paket für Vanta { $target } abgeschlossen werden. Wählen Sie „Paketdatei öffnen“ und dann dieses Vanta-Paket (.vantapkg). Falls Vanta es heruntergeladen hat, finden Sie es in { $folder }.
# Tester build: only the bundled Vanta package can be installed.
install-source-resume-bundled = Eine Installation von Vanta { $target } wurde nicht abgeschlossen. Diese Testversion kann nur ihr mitgeliefertes Vanta-Paket installieren. Schließen Sie die Installation daher mit dem Paket für Vanta { $target } in einer regulären Version von Vanta Manager ab.
install-source-unknown = Vanta konnte nicht feststellen, was auf diesem PC bereits installiert ist, und installiert deshalb vorerst nichts. Wählen Sie „Bericht senden“, damit das Vanta-Team helfen kann.
# $problem is one of the install-source-* messages; $error is a raw error message (text).
install-source-details = { $problem } Details: { $error }
iso-edition-selection = Es werden nur unterstützte Editionen übernommen. Wählen Sie bei der Windows-Installation eine Edition, für die Sie eine Windows-Lizenz haben.
detail-windows-preview = Insider-Builds werden nicht unterstützt. Verwenden Sie eine regulär veröffentlichte Version von Windows 11.
detail-windows-release-unknown = Vanta konnte nicht bestätigen, dass dieser Windows-Build regulär veröffentlicht wurde. Stellen Sie eine Internetverbindung her und prüfen Sie erneut.
# $build is this PC's Windows build and update number, such as 26300.9807 (text).
detail-windows-release-unlisted = Build { $build } steht nicht in Microsofts Liste der regulär veröffentlichten Versionen von Windows 11, daher lässt sich Vanta darauf noch nicht installieren. Release-Preview-Builds und andere Vorschau-Builds werden nicht unterstützt. Wählen Sie „Erneut prüfen“, sobald Microsoft diesen Build aufführt.
iso-release-unknown = Vanta konnte nicht bestätigen, dass diese ISO eine regulär veröffentlichte Version von Windows 11 enthält, die das Vanta-Paket unterstützt. Stellen Sie eine Internetverbindung her und wählen Sie dann erneut „Dateien prüfen“. Wenn es weiterhin fehlschlägt, laden Sie die ISO erneut von Microsoft herunter.
iso-release-unlisted = Der Windows-11-Build in dieser ISO steht nicht in Microsofts Liste der regulär veröffentlichten Versionen. Release-Preview-Builds und andere Vorschau-Builds werden nicht unterstützt. Laden Sie die ISO von Microsoft herunter oder wählen Sie erneut „Dateien prüfen“, sobald Microsoft diesen Build aufführt.
prepare-previous-worker = Zuvor gestartete Updates laufen noch. Vanta wartet, bis sie abgeschlossen sind. Danach können Sie erneut nach Updates suchen.

ready-used-windows-title = Windows auf diesem PC wurde offenbar schon genutzt
ready-used-windows-description = Windows wurde auf diesem PC vor mindestens einer Woche installiert oder enthält bereits mehrere Apps. Die Installation von Vanta wird hier nicht unterstützt und es wird dringend davon abgeraten: Vorhandene Apps und Einstellungen funktionieren möglicherweise nicht wie erwartet, und Vanta entfernt OneDrive. Dateien darin werden dann nicht mehr synchronisiert, und Ihre Ordner „Desktop“, „Dokumente“ und „Bilder“ wirken möglicherweise leer. Sichern Sie zuerst Ihre Dateien und installieren Sie Windows neu, oder fahren Sie nur fort, wenn Sie das Risiko in Kauf nehmen.
ready-used-windows-dismiss = Trotzdem fortfahren

prepare-resumed = Ihr PC wurde neu gestartet und Vanta hat Ihre bisherige Auswahl wiederhergestellt. Wählen Sie „Updates fortsetzen“, um die Updates abzuschließen, bevor Sie Vanta installieren.
prepare-continue = Updates fortsetzen
prepare-saving-restart = Ihre Auswahl wird gespeichert und Vanta wird so eingerichtet, dass es nach dem Neustart von Windows wieder geöffnet wird…
prepare-restart-save-failed = Ihre Auswahl konnte nicht gespeichert werden. Versuchen Sie es vor dem Neustart erneut.
prepare-restart-registration-failed = Ihre Auswahl ist gespeichert, aber Vanta konnte nicht einrichten, dass es sich nach dem Neustart wieder öffnet. Versuchen Sie es erneut oder starten Sie Ihren PC selbst neu und öffnen Sie Vanta nach der Anmeldung.
prepare-restart-source-linked = Ihre Auswahl ist gespeichert, aber solange sich der Vanta Manager in einem verknüpften Ordner befindet, kann Vanta nicht einrichten, dass es sich nach dem Neustart wieder öffnet. Schließen Sie Vanta und verschieben Sie den Vanta Manager in einen lokalen Ordner auf diesem PC. Öffnen Sie ihn dann von dort aus oder starten Sie Ihren PC selbst neu und öffnen Sie ihn nach der Anmeldung von dort aus.
prepare-restart-failed = Vanta konnte Ihren PC nicht neu starten. Versuchen Sie es erneut oder starten Sie ihn über das Startmenü neu. Ihre Auswahl ist gespeichert und Vanta öffnet sich nach der Anmeldung wieder.
diagnostics-export = Diagnose exportieren
diagnostics-exporting = Diagnosedaten werden gesammelt…
diagnostics-privacy = Senden Sie einen Bericht vertraulich an das Vanta-Team oder exportieren Sie eine Diagnose-ZIP-Datei, die Sie weitergeben können, wenn Sie um Hilfe bitten. Vanta entfernt daraus Ihren Benutzernamen, Ihren PC-Namen und E-Mail-Adressen.
# Title of the result bar after an export; its button is iso-open-folder.
diagnostics-saved = Diagnose-ZIP erstellt
diagnostics-failed-title = Diagnose konnte nicht exportiert werden
# $error is the raw error (text).
diagnostics-failed = Prüfen Sie, ob auf Ihrem PC genügend Speicherplatz frei ist, und versuchen Sie es dann erneut. Details: { $error }

## Tester builds (embedded-package feature)

# One line of chrome under the title bar on a release-candidate build.
rc-banner = Testversion von Vanta { $release }. Diese App installiert nur das mitgelieferte Vanta-Paket.
home-status-bundled = Testversion { $release }
home-status-ready = Bereit zur Installation
package-bundled = Das in dieser App enthaltene Vanta { $version } ist bereit zur Installation.
rc-about-release = Testversion
rc-about-commit = Quell-Commit
rc-about-package = Mitgeliefertes Vanta-Paket (SHA-256)
iso-package-bundled = Das in dieser App enthaltene Vanta-Paket
prepare-percent = { $percent } % dieser Phase
prepare-count = Abgeschlossene Updates: { $completed } von { $total }
prepare-bytes = { $downloaded } von ungefähr { $total } MB heruntergeladen
prepare-elapsed = Verstrichen: { $minutes } Min. { $seconds } Sek.
prepare-progress-waiting = Warten auf den Updatedienst. Für diesen Schritt ist keine Prozentangabe verfügbar.
prepare-progress-unchanged = Seit { $minutes } Min. kein Fortschritt. Große Updates können eine Weile dauern. Lassen Sie Vanta daher geöffnet. Wählen Sie für Details „Protokollordner öffnen“.
prepare-report-delayed = Windows hat seit { $seconds } Sek. keinen Fortschritt gemeldet. Möglicherweise laufen noch Updates. Lassen Sie Vanta daher geöffnet.

prepare-affected-app = die betroffene App
prepare-app-in-use = Schließen Sie { $app } und versuchen Sie es dann erneut. Windows kann die App nicht aktualisieren, solange sie geöffnet ist. Wenn Sie ihr Fenster nicht finden, beenden Sie sie im Task-Manager. Wenn es weiterhin fehlschlägt, starten Sie Ihren PC neu und versuchen Sie es erneut, bevor Sie { $app } öffnen.
prepare-install-busy = Eine andere Installation oder ein erforderlicher Neustart blockiert Updates. Warten Sie, bis andere Installationen abgeschlossen sind, starten Sie Ihren PC neu, wenn Windows Sie dazu auffordert, und versuchen Sie es dann erneut.
prepare-failed-component-store = Windows meldet Schäden an seinem Komponentenspeicher, die die Installation von Updates verhindern, und Vanta konnte sie nicht reparieren. Starten Sie Ihren PC neu und wählen Sie dann „Erneut versuchen“. Wenn Updates weiterhin fehlschlagen, sichern Sie Ihre Dateien und installieren Sie Windows mit einer Vanta-ISO neu.
prepare-failed-component-store-unrepairable = Windows meldet Schäden an seinem Komponentenspeicher, die es nicht reparieren kann, und kann deshalb keine Updates installieren. Sichern Sie Ihre Dateien und installieren Sie Windows dann mit einer Vanta-ISO neu.
# Causes the update worker names. The worker's own English message is shown below as a detail.
prepare-failed-session-owner = Vanta läuft unter einem anderen Konto als dem, das bei Windows angemeldet ist. Melden Sie sich mit einem Administratorkonto bei Windows an, öffnen Sie Vanta unter diesem Konto und versuchen Sie es dann erneut.
prepare-failed-store-missing = Der Microsoft Store ist für Ihr Konto nicht eingerichtet. Öffnen Sie den Microsoft Store einmal oder installieren Sie ihn neu, falls er fehlt. Versuchen Sie es dann erneut.
prepare-failed-store-battery = Der Microsoft Store hat Updates angehalten, um Akku zu sparen. Schließen Sie Ihren PC ans Stromnetz an und versuchen Sie es dann erneut.
prepare-failed-store-network = Der Microsoft Store hat Updates angehalten, bis Ihr PC eine nicht getaktete Verbindung hat. Verbinden Sie sich über ein nicht getaktetes WLAN oder Ethernet und versuchen Sie es dann erneut.
prepare-failed-store-timeout = Die Store-Apps wurden noch nicht fertig aktualisiert. Schließen Sie die restlichen Downloads im Microsoft Store ab und versuchen Sie es dann erneut.
prepare-failed-store-passes = Der Microsoft Store hat immer wieder neue Updates angeboten. Schließen Sie die restlichen Updates im Microsoft Store ab und versuchen Sie es dann erneut.
prepare-failed-manual-updates = Einige Windows-Updates müssen in Windows Update abgeschlossen werden. Öffnen Sie Windows Update, schließen Sie die Updates dort ab und versuchen Sie es dann erneut.
prepare-failed-windows-passes = Windows Update hat immer wieder neue Updates angeboten. Schließen Sie die restlichen Updates in Windows Update ab und versuchen Sie es dann erneut.
prepare-failed-source-linked = Der Vanta Manager befindet sich in einem verknüpften Ordner. Schließen Sie Vanta, verschieben Sie den Vanta Manager in einen lokalen Ordner auf diesem PC und öffnen Sie ihn dann von dort aus.
prepare-error-code = Fehlercode: { $code }
prepare-open-store = Microsoft Store öffnen

check-user-account = Benutzerkonto
detail-user-account-ok = Die Benutzerkontensteuerung ist aktiviert und Ihr Konto ist für die Installation bereit.
detail-user-account-not-ready = Aktivieren Sie die Benutzerkontensteuerung (UAC), starten Sie Ihren PC neu und versuchen Sie es dann erneut. Wenn Sie das integrierte Administratorkonto verwenden, melden Sie sich mit einem anderen Administratorkonto an.
detail-user-account-work-or-school = Vanta kann nicht unter einem Geschäfts-, Schul- oder Unikonto (Microsoft Entra ID) installiert werden. Melden Sie sich mit einem lokalen Konto oder einem Microsoft-Konto an und versuchen Sie es dann erneut.
detail-user-account-unknown = Vanta konnte Ihr Benutzerkonto nicht prüfen. Starten Sie Ihren PC neu, öffnen Sie Vanta erneut und prüfen Sie noch einmal. Wenn das immer wieder passiert, wählen Sie „Bericht senden“. Windows meldet: { $error }

footer-prepare-required = Schließen Sie die Updates für Windows und Store-Apps ab, um fortzufahren
footer-prepare-stopping = Updates werden nach dem aktuellen Schritt angehalten…
resume-choices-title = Vorherige Installation fortsetzen
resume-choices-detail = Um diese Installation abzuschließen, hat Vanta Ihre Auswahl vom letzten Mal wiederhergestellt. Unter „Ihre Auswahl“ können Sie sie erst ändern, wenn die Installation abgeschlossen ist.

## Voluntary reports
report-title = Bericht senden
report-received = Bericht erhalten
report-reference = Bewahren Sie diese Referenz auf, falls Sie das Vanta-Team zu diesem Bericht kontaktieren. Wenn Sie Kontaktdaten angegeben haben, kann das Team Ihnen darüber antworten, eine Antwort ist aber nicht garantiert.
# Accessible name of the Copy button beside the report reference.
report-copy-reference = Berichtsreferenz kopieren
report-another = Weiteren Bericht senden
# Label of the choice between the two kinds of report.
report-kind = Was möchten Sie senden?
report-kind-issue = Ein Problem
report-kind-suggestion = Einen Vorschlag
# $min and $max are numbers: the message lengths the report service accepts.
report-intro = Beschreiben Sie, was passiert ist oder was Sie sich anders wünschen ({ $min }–{ $max } Zeichen). Geben Sie in Ihrer Nachricht keine Kennwörter an.
report-message = Ihre Nachricht
report-message-placeholder = Ich wollte…
report-contact = Kontaktdaten (optional)
report-contact-placeholder = E-Mail oder Discord-Benutzername
report-attach = Diagnosedaten beifügen
report-attach-description = Protokolle und Systemdetails, die bei der Suche nach der Ursache helfen. Vanta entfernt Ihren Benutzernamen, Ihren PC-Namen, E-Mail-Adressen und bekannte Kennwörter oder Schlüssel. Fehlerdetails, Hardwaremodelle und App-Namen bleiben erhalten. Sie können die ZIP-Datei vor dem Senden prüfen.
report-prepare = Diagnosedaten vorbereiten
report-review = ZIP prüfen
report-prepare-failed-title = Diagnosedaten konnten nicht vorbereitet werden
# $error is a raw error message (text).
report-prepare-failed = Wählen Sie erneut „Diagnosedaten vorbereiten“ oder deaktivieren Sie „Diagnosedaten beifügen“, um Ihren Bericht ohne sie zu senden. Details: { $error }
report-privacy = Vanta Manager does not send reports: nothing leaves this PC. Your message and diagnostics stay here.
report-consent = Ich stimme zu, diesen Bericht und alle beigefügten Diagnosedaten an das Vanta-Team zu senden
report-failed = Ihre Nachricht bleibt erhalten. Prüfen Sie Ihre Internetverbindung und wählen Sie dann „Erneut versuchen“ oder senden Sie Ihren Bericht über die Berichtswebsite.
report-failed-busy = Der Berichtsdienst ist ausgelastet. Ihre Nachricht bleibt erhalten. Versuchen Sie es später erneut.
report-failed-outdated = Diese Version von Vanta Manager kann keine Berichte mehr senden. Ihre Nachricht bleibt erhalten: Kopieren Sie sie und fügen Sie sie auf der Berichtswebsite ein. Wenn Sie Diagnosedaten beigefügt haben, wählen Sie „ZIP prüfen“ und hängen Sie die ZIP-Datei dort ebenfalls an.
report-failed-diagnostics = Die vorbereiteten Diagnosedaten können nicht gesendet werden. Ihre Nachricht bleibt erhalten. Wählen Sie erneut „Diagnosedaten vorbereiten“ oder deaktivieren Sie „Diagnosedaten beifügen“.
# Link under a report that wasn't sent.
report-sending = Wird gesendet…
report-send = Bericht senden

# $min and $max are numbers: the message lengths the report service accepts.
report-validation-message = Geben Sie { $min }–{ $max } Zeichen ein.

# $max is a number: the longest contact details the report service accepts.
report-validation-contact = Die Kontaktdaten dürfen höchstens { $max } Zeichen lang sein.

report-validation-consent = Bestätigen Sie, dass Sie dem Senden dieses Berichts zustimmen.

report-failed-title = Bericht nicht gesendet

## Windows version update
home-plan-intro = Dieses Update besteht aus zwei Teilen. Ihre Dateien und Apps bleiben erhalten. Wenn das Windows-Update Änderungen von Vanta rückgängig macht, stellt Vanta sie wieder her.
home-plan-windows-title = Windows 11, Version { $release }
home-plan-windows-detail = Vanta installiert sie über Windows Update. Ihr PC wird neu gestartet, um die Installation abzuschließen.
home-plan-windows-optional = Empfohlen. Vanta installiert sie über Windows Update. Ihr PC wird neu gestartet, um die Installation abzuschließen.
home-plan-atlas-title = Vanta { $version }
home-plan-atlas-detail = Vanta aktualisiert seine Dateien und behält Ihre Auswahl bei. Am Ende wird Ihr PC neu gestartet.
# $date and $until are dates.
home-end-of-updates-title = Für Windows 11, Version { $current }, enden die Sicherheitsupdates am { $date }
home-end-of-updates-past-title = Windows 11, Version { $current }, erhält keine Sicherheitsupdates mehr
home-end-of-updates-message = Mit dem Update auf Vanta { $version } wird dieser PC auch auf Windows 11, Version { $release }, umgestellt. Diese Version erhält Sicherheitsupdates bis zum { $until }.
# $product is Windows' own name for the edition, such as Windows 11 Home.
install-windows-edition = Vanta { $version } funktioniert mit Windows 11 Pro, Enterprise und Education. Auf diesem PC ist { $product } installiert, daher kann Vanta hier nicht installiert werden.
install-windows-edition-ending = Vanta { $version } funktioniert mit Windows 11 Pro, Enterprise und Education. Auf diesem PC ist { $product } installiert, daher kann Vanta hier nicht installiert werden. Für Windows 11, Version { $current }, enden die Sicherheitsupdates am { $date }. Windows Update kann diesen PC auf eine neuere Version umstellen.
# $releases lists the supported releases, such as "25H2 oder 26H2".
install-windows-no-path = Vanta { $version } benötigt Windows 11, Version { $releases }, und Windows Update kann diesen PC von seiner jetzigen Windows-Version aus nicht dorthin umstellen. Um Vanta { $version } zu verwenden, sichern Sie Ihre Dateien und installieren Sie Windows mit einer Vanta-ISO neu.
# Home, when Vanta changed Windows Update settings for an update and hasn't put them back.
# "Put back" is "wiederherstellen" throughout; „Einstellungen wiederherstellen“ is home-put-back.
home-update-access-title = Windows Update-Einstellungen wurden für das Vanta-Update geändert
home-update-access-not-offered = Vanta hat Windows Update eingeschaltet, um diesen PC auf Windows 11, Version { $release }, umzustellen, aber Windows Update hat diese Version noch nicht angeboten. Wählen Sie „Erneut prüfen“ oder „Einstellungen wiederherstellen“.
home-update-access-before = Vanta hat Windows Update eingeschaltet, um diesen PC auf Windows 11, Version { $release }, umzustellen, und ist damit noch nicht fertig. Setzen Sie das Update fort oder wählen Sie „Einstellungen wiederherstellen“.
home-update-access-after = Auf diesem PC läuft Windows 11, Version { $release }. Schließen Sie die Installation von Vanta ab oder wählen Sie „Einstellungen wiederherstellen“.
home-update-access-plain = Vanta hat Windows Update eingeschaltet, um Updates zu installieren, und ist damit noch nicht fertig. Setzen Sie das Update fort oder wählen Sie „Einstellungen wiederherstellen“.
home-update-access-unreadable = Vanta kann seine Aufzeichnung der geänderten Windows Update-Einstellungen nicht lesen. Daher ändert Vanta nichts und stellt auch nichts wieder her. Wählen Sie „Bericht senden“, damit das Vanta-Team helfen kann.
# $error is the raw error.
home-update-access-failed = Vanta konnte die Einstellungen nicht wiederherstellen. Wählen Sie „Erneut versuchen“ oder „Bericht senden“. Details: { $error }
home-update-access-install-active = Schließen Sie zuerst die Installation von Vanta ab. In ihrem letzten Schritt stellt Vanta diese Einstellungen wieder her.
home-continue-update = Update fortsetzen
home-put-back = Einstellungen wiederherstellen
home-putting-back = Einstellungen werden wiederhergestellt…
# Get ready: the Windows version card.
windows-card-title = Windows 11, Version { $release }
windows-card-required = Vanta { $version } benötigt eine neuere Windows-Version. Wenn Vanta Windows weiter unten aktualisiert, installiert es dabei auch Windows 11, Version { $release }, über Windows Update.
windows-card-question = Welche Windows-Version soll dieser PC verwenden?
windows-choice-move = Auf Windows 11, Version { $release }, aktualisieren
# $date is when the new version stops getting security updates.
windows-choice-move-detail = Empfohlen. Sicherheitsupdates bis zum { $date }. Ein zusätzlicher Neustart.
windows-choice-keep = Windows 11, Version { $current }, behalten
windows-choice-keep-detail = Ihr PC bleibt auf dieser Version. Windows Update stellt ihn nicht auf eine neuere Version um. Für einen späteren Wechsel ist daher ein weiteres Update in Vanta Manager nötig.
windows-card-facts = Was sich ändert
windows-fact-keep = Ihre Dateien und Apps bleiben erhalten. Wenn das Update Änderungen von Vanta rückgängig macht, stellt Vanta sie bei der Installation wieder her.
windows-fact-restart = Ihr PC wird mindestens ein weiteres Mal neu gestartet, um das Update abzuschließen.
# Also after home-plan-windows-detail on Home: how long Windows Update can take to offer the
# new version, which Vanta waits for by itself. „sie“ is the new version.
transition-offer-expectation = Windows Update bietet sie meist innerhalb weniger Minuten an, manchmal dauert es aber bis zu 2 Stunden. Vanta wartet darauf und sieht regelmäßig für Sie nach.
windows-fact-stays = Danach bleibt Windows auf Version { $release } und wechselt nicht von selbst auf eine neuere Version.
windows-fact-removed = Version { $release } enthält weder Windows PowerShell 2.0 noch das WMIC-Tool.
# Updateverlauf, System, Wiederherstellung and Zurück are the German Windows 11 labels
# (Einstellungen > Windows Update > Updateverlauf; Einstellungen > System > Wiederherstellung > Zurück).
windows-card-undo = Um das Update später rückgängig zu machen, deinstallieren Sie es in Windows Update unter „Updateverlauf“. Falls Windows sich für das Update neu installiert hat, wählen Sie stattdessen innerhalb von 10 Tagen in den Einstellungen unter „System“ > „Wiederherstellung“ die Option „Zurück“. Vanta { $version } unterstützt Version { $current } nicht. Machen Sie das Update daher nicht rückgängig, sobald Vanta { $version } installiert ist.
windows-card-undo-optional = Um das Update später rückgängig zu machen, deinstallieren Sie es in Windows Update unter „Updateverlauf“. Falls Windows sich für das Update neu installiert hat, wählen Sie stattdessen innerhalb von 10 Tagen in den Einstellungen unter „System“ > „Wiederherstellung“ die Option „Zurück“.
windows-terms = Ich akzeptiere die Microsoft-Software-Lizenzbedingungen für Windows 11, Version { $release }
windows-terms-link = Lizenzbedingungen lesen
# „Abbrechen“ is the flow's own button (common-cancel); „Updates anhalten“ confirms it (prepare-stop).
windows-card-locked = Um Version { $current } zu behalten, wählen Sie „Abbrechen“ und dann „Updates anhalten“.
# Get ready: the update card while Windows moves.
prepare-description-transition = Vor der Installation installiert Vanta zuerst die ausstehenden Windows-Updates, dann Windows 11, Version { $release }, und aktualisiert danach den Microsoft Store und Ihre Store-Apps. Geöffnete Store-Apps werden beim Aktualisieren möglicherweise geschlossen. Speichern Sie deshalb vorher Ihre Arbeit darin. Ihr PC wird mindestens einmal neu gestartet.
prepare-start-transition = Windows auf Version { $release } aktualisieren
prepare-needs-terms = Verfügbar, sobald Sie unter „Windows 11, Version { $release }“ die Lizenzbedingungen akzeptieren.
ready-banner-not-offered-message = Unter „Windows und Store-Apps aktualisieren“ erfahren Sie, was Sie jetzt tun können.
ready-banner-transition-failed-message = Unter „Windows und Store-Apps aktualisieren“ erfahren Sie, wie es weitergeht.
ready-banner-terms-title = Akzeptieren Sie die Lizenzbedingungen, um fortzufahren
ready-banner-terms-message = Sie finden sie weiter unten auf dieser Seite unter „Windows 11, Version { $release }“. Wählen Sie danach „Windows auf Version { $release } aktualisieren“.
# The bar that names each Windows Update setting Vanta turns on for the update.
access-notice-title = Vanta schaltet Windows Update vorübergehend ein
access-off = Windows Update ist auf diesem PC ausgeschaltet. Vanta schaltet es wieder ein, während es Windows aktualisiert.
access-paused = Windows-Updates sind auf diesem PC ausgesetzt. Vanta setzt sie fort, während es Windows aktualisiert.
access-delayed = Monatliche Updates sind auf diesem PC zurückgestellt. Vanta hebt die Zurückstellung auf, während es Windows aktualisiert.
access-back-chosen = Sobald Vanta { $version } installiert ist, sind diese Einstellungen wieder so, wie Sie sie gewählt haben.
access-back = Sobald Vanta { $version } installiert ist, sind diese Einstellungen wieder so wie vorher.
access-back-stop = Wenn Sie vorher abbrechen, stellt Vanta sie wieder her.
# The restart that finishes the new version.
prepare-reboot-transition = Windows 11, Version { $release }, ist installiert. Wählen Sie „Neu starten und fortfahren“, um die Installation abzuschließen. Vanta öffnet sich nach der Anmeldung wieder.
prepare-reboot-commit = Windows muss noch einmal neu gestartet werden, um die Installation von Version { $release } abzuschließen. Vanta öffnet sich nach der Anmeldung wieder.
prepare-restart-commit-failed = Windows konnte Version { $release } nicht für den Abschluss beim Neustart vorbereiten, daher wurde Ihr PC nicht neu gestartet. Wählen Sie „Neu starten und fortfahren“, um es erneut zu versuchen.
prepare-reason-feature-update = die neue Windows-Version
prepare-reason-feature-commit = Abschluss der neuen Windows-Version
prepare-resumed-transition = Ihr PC wurde neu gestartet. Wählen Sie „Updates fortsetzen“, damit Vanta prüft, ob die Installation von Windows 11, Version { $release }, abgeschlossen ist, und noch ausstehende Updates installiert.
# Under the progress bar while Windows Update has yet to offer the new version.
prepare-waiting-offer = Es wird gewartet, bis Windows Update Windows 11, Version { $release }, anbietet. Das dauert meist nur wenige Minuten, manchmal aber bis zu 2 Stunden. Sie können Ihren PC weiter verwenden, lassen Sie Vanta aber geöffnet.
# After a restart for the updates Windows installs before the new version.
prepare-resumed-before-move = Ihr PC wurde neu gestartet, um die Installation der Updates abzuschließen. Wählen Sie „Updates fortsetzen“, damit Vanta die noch ausstehenden Updates und danach Windows 11, Version { $release }, installiert.
# Outcomes of moving Windows. Each says what changed and what to do next.
prepare-not-offered-title = Warten, bis Windows Update Windows 11, Version { $release }, anbietet
prepare-transition-failed-title = Windows konnte nicht auf Version { $release } umgestellt werden
prepare-failed-feature-not-offered = Es kann eine Weile dauern, bis Windows Update einem PC Windows 11, Version { $release }, anbietet. Auf Ihrem PC ist weiterhin Version { $current } installiert.
prepare-offer-rechecking = Vanta prüft alle 10 Minuten erneut und fährt von selbst fort, sobald Windows Update die neue Version anbietet. Sie können auch „Erneut prüfen“ wählen.
# Under the progress bar while Vanta waits, updated as time passes: how long it has waited,
# then when it looks again, or that it's looking now. Shown together on one line.
prepare-offer-waited =
    { $minutes ->
        [one] Vanta wartet seit { $minutes } Minute.
       *[other] Vanta wartet seit { $minutes } Minuten.
    }
prepare-offer-next-check =
    { $minutes ->
        [one] Nächste Prüfung in { $minutes } Minute.
       *[other] Nächste Prüfung in { $minutes } Minuten.
    }
prepare-offer-checking-now = Prüfung läuft.
prepare-offer-check-again = Wählen Sie „Erneut prüfen“, um jetzt nachzusehen.
prepare-offer-wait-ended-title = Windows Update hat Windows 11, Version { $release }, noch nicht angeboten
prepare-offer-wait-ended = Windows Update hat Windows 11, Version { $release }, nicht innerhalb von 2 Stunden angeboten. Vanta hat daher aufgehört zu warten und Ihre Windows Update-Einstellungen wiederhergestellt. Wählen Sie später „Erneut prüfen“. Wenn Sie nicht warten können, sichern Sie Ihre Dateien und installieren Sie Windows mit einer Vanta-ISO neu.
# Instead of the message above when putting the settings back at the end of the wait failed.
# $error is the raw error.
prepare-offer-wait-put-back-failed = Windows Update hat Windows 11, Version { $release }, nicht innerhalb von 2 Stunden angeboten, und Vanta konnte Ihre Windows Update-Einstellungen nicht wiederherstellen. Wählen Sie „Einstellungen wiederherstellen“, um es erneut zu versuchen. Details: { $error }
# $missing lists the hardware this PC lacks, from hardware-tpm and hardware-uefi.
prepare-failed-feature-hardware = Dieser PC erfüllt die Hardwareanforderungen von Windows 11 nicht ({ $missing }), daher stellt Windows Update ihn nicht auf Version { $release } um. Auf Ihrem PC ist weiterhin Version { $current } installiert. Um Vanta { $version } zu verwenden, sichern Sie Ihre Dateien und installieren Sie Windows mit einer Vanta-ISO neu.
hardware-tpm = TPM 2.0
hardware-uefi = UEFI-Firmware
prepare-failed-feature-hidden = Windows 11, Version { $release }, ist in Windows Update auf diesem PC ausgeblendet. Blenden Sie die Version mit dem Tool wieder ein, mit dem Sie sie ausgeblendet haben, und wählen Sie dann „Erneut versuchen“.
# $needed and $free are whole gigabytes; $drive is a drive such as C:.
prepare-failed-feature-disk-space = Windows benötigt für dieses Update mindestens { $needed } GB freien Speicherplatz auf Laufwerk { $drive }, dort sind aber nur { $free } GB frei. Vanta hat nichts geändert. Geben Sie Speicherplatz frei und wählen Sie dann „Erneut versuchen“.
prepare-failed-feature-servicing = Windows meldet Schäden an seinem Komponentenspeicher, die es nicht reparieren kann. Vanta hat daher nichts geändert. Reparieren Sie Windows und wählen Sie dann „Erneut versuchen“.
prepare-failed-feature-managed = Dieser PC erhält Updates vom Updateserver einer Organisation, daher kann Vanta ihn nicht auf Version { $release } umstellen. Vanta hat nichts geändert.
# $setting is the technical name of a Windows Update policy value or service, such as
# NoAutoUpdate or BITS, shown as it is.
prepare-failed-feature-policy = Etwas auf diesem PC macht die Änderungen von Vanta an { $setting } immer wieder rückgängig, daher kann Vanta Windows nicht aktualisieren. Wenn dieser PC von einer Organisation verwaltet wird, wenden Sie sich an diese. Wenn Sie abbrechen, stellt Vanta wieder her, was es geändert hat.
prepare-failed-feature-blocked = Eine Einstellung, die Vanta nicht geändert hat, verhindert, dass Windows Update ausgeführt wird: { $setting }. Ändern Sie sie so, dass Windows Update ausgeführt werden kann, und wählen Sie dann „Erneut versuchen“.
prepare-failed-feature-rolled-back = Windows konnte die Installation von Version { $release } beim Neustart nicht abschließen und ist zu Version { $current } zurückgekehrt. Ihre Dateien und Apps sind nicht betroffen. Wählen Sie „Erneut versuchen“ oder „Bericht senden“.
prepare-failed-feature-components-lost = Einige Änderungen von Vanta sind nach dem Windows-Update nicht mehr vorhanden, aber nichts deutet darauf hin, dass Windows sich neu installiert hat. Vanta kann daher nicht feststellen, was passiert ist. Vanta { $version } wurde nicht installiert. Wählen Sie „Bericht senden“, damit das Vanta-Team helfen kann.
prepare-failed-feature-build = Die Windows-Version dieses PCs hat sich geändert, während Vanta sie aktualisiert hat. Wählen Sie „Einstellungen wiederherstellen“ und beginnen Sie dann auf der Startseite von vorn.
prepare-failed-feature-journal = Vanta kann seine Aufzeichnung der geänderten Windows Update-Einstellungen nicht lesen. Daher ändert Vanta nichts und stellt auch nichts wieder her. Wählen Sie „Bericht senden“, damit das Vanta-Team helfen kann.
# $setting is the name of a Windows Update policy value, such as TargetReleaseVersionInfo.
prepare-failed-feature-pin = Eine Windows Update-Richtlinie auf diesem PC, { $setting }, hat einen Wert, den Vanta nicht aufzeichnen kann. Vanta hat daher nichts geändert. Wählen Sie „Bericht senden“, damit das Vanta-Team helfen kann.
prepare-failed-feature-terms = Akzeptieren Sie die Lizenzbedingungen für Windows 11, Version { $release }, und wählen Sie dann „Erneut versuchen“.
prepare-failed-feature-failed = Windows konnte Version { $release } nicht installieren. Auf Ihrem PC ist weiterhin Version { $current } installiert. Wählen Sie „Erneut versuchen“. Wenn es wieder fehlschlägt, wählen Sie „Bericht senden“.
prepare-check-again = Erneut prüfen
prepare-keep-version = Version { $current } behalten
# Asked before leaving the update with Windows Update settings changed.
stop-update-title = Update auf Vanta { $version } abbrechen?
stop-update-title-windows = Aktualisierung von Windows abbrechen?
stop-update-before = Vanta stellt die geänderten Windows Update-Einstellungen wieder her. Updates, die Windows bereits installiert hat, bleiben installiert, und Ihr PC behält Windows 11, Version { $current }.
stop-update-after = Ihr PC behält Windows 11, Version { $release }. Vanta stellt die geänderten Windows Update-Einstellungen wieder her.
stop-update-access = Vanta stellt die geänderten Windows Update-Einstellungen wieder her. Updates, die Windows bereits installiert hat, bleiben installiert.
stop-update-keep = Weiter aktualisieren
# Dialog shown when the window is closed while Windows Update is turned on for an update; its
# buttons are window-close-keep and window-close-put-back.
window-close-update-access-title = Vanta schließen?
window-close-update-access-message = Vanta stellt vor dem Schließen die geänderten Windows Update-Einstellungen wieder her. Sie können das Update auf der Startseite erneut starten.
window-close-put-back = Wiederherstellen und schließen
# When putting the settings back before closing failed. The reason comes first, then this
# message; the buttons are window-close-keep and window-close-close.
window-close-put-back-failed-title = Schließen, ohne die Einstellungen wiederherzustellen?
window-close-put-back-failed-message = Wenn Sie Vanta jetzt schließen, bleiben die Windows Update-Einstellungen so, wie Vanta sie geändert hat. Wenn Sie Vanta wieder öffnen, bietet die Startseite an, sie wiederherzustellen.
# The "Vanta is installed" window, when the user's choice turned Windows Update off again.
installed-update-off-again = Windows Update ist wie von Ihnen gewählt wieder ausgeschaltet. Solange es ausgeschaltet ist, erhält Ihr PC keine Sicherheitsupdates.
installed-update-paused-again = Windows-Updates sind wie von Ihnen gewählt wieder ausgesetzt. Solange sie ausgesetzt sind, erhält Ihr PC keine Sicherheitsupdates.
# PC checks: Windows compatibility on a version Vanta moves from.
detail-build-transition = Auf diesem PC läuft Windows 11, Version { $current }. Diese Vanta-Version unterstützt sie nicht. Vanta stellt Windows auf Version { $release } um, wenn es Windows weiter unten aktualisiert.
# The first lines of a report; technical details follow in English.
report-transition-intro = Die Windows-Aktualisierung für Vanta wurde nicht abgeschlossen. Details für das Vanta-Team:
# When Windows reinstalled itself while it moved to a newer version. German nouns stay capitalised.
mode-rebase = Neuinstallation nach einem Windows-Update
history-mode-rebase = Neuinstallation nach Windows-Update
ready-rebase-title = Windows hat sich beim Update neu installiert
# $previous is the Vanta version the PC had before.
ready-rebase-message = Windows 11, Version { $release }, hat das bisherige Windows auf diesem PC ersetzt, daher fehlen einige Änderungen von Vanta. Vanta { $version } stellt sie mit der Auswahl wieder her, die Sie für Vanta { $previous } getroffen haben.
update-path-update-title = Wie möchten Sie auf Vanta { $version } aktualisieren?
update-path-reinstall-title = Wie möchten Sie Vanta { $version } neu installieren?
update-path-keep = Auswahl beibehalten
update-path-keep-detail = Vanta behält jede Auswahl so bei, wie sie jetzt auf diesem PC eingestellt ist, und ändert keine davon. Das ist der schnellere Weg.
update-path-choose = Neu auswählen
update-path-choose-detail = Gehen Sie jede Auswahl noch einmal durch, ausgehend davon, wie dieser PC jetzt eingerichtet ist. Vanta wendet jede so an wie bei einer Erstinstallation. Ihre Apps und Dateien, das Startmenü, die Taskleiste und das Design bleiben unverändert, ebenso Einstellungen, die Sie im Vanta-Ordner geändert haben und die von dieser Auswahl nicht erfasst werden.
update-path-now-title = Ihre aktuelle Auswahl auf diesem PC
update-path-unknown = Vanta kann das auf Ihrem PC nicht erkennen und fragt Sie daher
option-detected-off = Auf dem aktuellen System als ausgeschaltet erkannt. Es wurde nichts gewählt, daher ist die sichere Vorgabe (eingeschaltet lassen) ausgewählt: Treffen Sie die Wahl selbst.
update-path-differs = Bei { $choices } stimmt das, was Vanta zu Ihrer letzten Installation aufgezeichnet hat, nicht mit diesem PC überein. Die Liste zeigt den aktuellen Stand des PCs.
keep-choices-title = Ihre Auswahl wird beibehalten
keep-choices-partial = Vanta behält bei, was jetzt auf diesem PC eingestellt ist. Diese Punkte kann Vanta auf Ihrem PC nicht erkennen. Wählen Sie sie daher selbst: { $missing }
choose-again-title = Sie treffen Ihre Auswahl neu
choose-again-detail = Jede Auswahl ist so voreingestellt, wie dieser PC jetzt eingerichtet ist. Vanta wendet Ihre Auswahl während der Installation an.
option-now = Aktuell auf diesem PC
change-defender-enable = Vanta stellt Microsoft Defender wieder her. Schalten Sie nach dem Neustart seinen Schutz in der Windows-Sicherheit ein.
change-mitigations-default = Vanta schaltet den Prozessorschutz wieder so ein, wie Windows ihn standardmäßig einstellt. Das wird nach dem Neustart wirksam.
change-mitigations-all-on = Alle Prozessorschutzfunktionen sind jetzt eingeschaltet. Wenn Sie den Prozessorschutz behalten, bleiben sie alle eingeschaltet.
change-auto-updates-default = Vanta lässt Windows wieder automatisch Updates installieren.
change-hibernation-on = Vanta schaltet den Ruhezustand wieder ein.
change-power-saving-on = Vanta schaltet das Energiesparen wieder ein und kehrt zu Ihrem früheren Energiesparplan zurück oder, falls es keinen gibt, zu „Ausbalanciert“.
change-core-isolation-on = Vanta schaltet die virtualisierungsbasierte Sicherheit (VBS) wieder ein, sofern keine Richtlinie auf diesem PC sie steuert. Das wird nach dem Neustart wirksam.
change-remove-snipping-tool = Entfernt das Snipping Tool für alle Benutzer dieses PCs. Vanta kann es später nicht wiederherstellen, aber Sie können es aus dem Microsoft Store erneut installieren.
fixed-uninstall-edge = Microsoft Edge wurde bereits entfernt, und ein Update von Vanta kann Edge nicht wiederherstellen. Um Edge erneut zu installieren, verwenden Sie „Install or Remove Edge“ im Vanta-Ordner.
fixed-installed = { $app } ist installiert. Vanta deinstalliert keine Apps. Zum Entfernen öffnen Sie „Installierte Apps“ in den Windows-Einstellungen.
browser-also = { $installed } bleibt installiert, und Vanta installiert zusätzlich { $browser }.
summary-update-path = Art des Updates
step-heading-update-path-a11y = { $heading }. { $question }
security-banner-removed-title = Vanta hat Microsoft Defender von diesem PC entfernt
security-banner-restore-title = Vanta stellt Microsoft Defender bei dieser Installation wieder her
security-banner-restore-message = Defender läuft noch nicht, daher müssen Sie in diesem Schritt nichts ausschalten. Schalten Sie nach dem Neustart seinen Schutz in der Windows-Sicherheit ein. Wählen Sie „Weiter“.
security-banner-missing-title = Microsoft Defender fehlt
security-banner-missing-message = Vanta hat ihn nicht entfernt und kann ihn daher nicht wiederherstellen. Sie können fortfahren, aber Ihr PC hat keinen Virenschutz, bis Sie eine andere Antivirensoftware installieren oder Windows reparieren.
installed-defender-not-restored-title = Microsoft Defender ist weiterhin entfernt
installed-defender-not-restored-message = Sie haben sich entschieden, Microsoft Defender zu behalten, aber ein früheres Vanta-Update hat ihn nicht wiederhergestellt, daher hat Ihr PC keinen Virenschutz. Um ihn wiederherzustellen, aktualisieren Sie Vanta oder installieren Sie es neu und wählen Sie dabei „Neu auswählen“. Sie können auch im Vanta-Ordner auf Ihrem Desktop „7. Security“ > „Defender“ öffnen, „Toggle Defender“ ausführen, „Enable Windows Defender“ wählen und Ihren PC neu starten.
choices-not-applied-title = Ein Teil Ihrer Auswahl wurde nicht übernommen
choices-not-applied-message = Für { $choices } hat Vanta aufgezeichnet, was jetzt auf diesem PC eingestellt ist. Den Grund finden Sie im Installationsprotokoll.
rebase-choices-title = Ihre Auswahl aus Vanta { $previous }
rebase-choices-detail = Vanta verwendet die Auswahl, die Sie für Vanta { $previous } getroffen haben. Hier müssen Sie daher nichts auswählen. Um Ihre Auswahl danach zu ändern, wählen Sie „Vanta neu installieren“ und dann „Neu auswählen“.
# $missing lists the choices, such as "Microsoft Defender, Prozessorschutz".
rebase-choices-partial = Vanta verwendet die Auswahl, die Sie für Vanta { $previous } getroffen haben. Diese Punkte konnte Vanta nicht finden. Prüfen Sie sie daher: { $missing }
# Asked before any restart Vanta makes while other people are signed in to the PC.
restart-other-title = Eine andere Person ist an diesem PC angemeldet
restart-others-title = Andere Personen sind an diesem PC angemeldet
# $names lists their account names, such as "Alex und Sam".
restart-others-message = Durch den Neustart werden ihre Apps geschlossen, und ihre nicht gespeicherte Arbeit geht verloren. Angemeldet: { $names }.
restart-others-keep = Nicht neu starten
restart-others-restart = Trotzdem neu starten
# Microsoft Store itself, before the Store apps. Get ready's status line while it updates or is repaired.
prepare-store-self-update = Zuerst wird der Microsoft Store aktualisiert. Er ist auf diesem PC veraltet.
prepare-store-repair = Der Microsoft Store wird repariert. Das kann einige Minuten dauern.
# Under prepare-complete, once Get ready has finished.
prepare-store-updated = Der Microsoft Store war veraltet, daher hat Vanta ihn vor Ihren Apps aktualisiert.
prepare-store-bootstrapped = Der Microsoft Store konnte sich nicht selbst aktualisieren, daher hat Vanta den neuesten App-Installer und den Microsoft Store von Microsoft installiert.
prepare-store-repaired = Der Microsoft Store funktionierte nicht, daher hat Vanta ihn repariert.
prepare-store-skipped-removed = Der Microsoft Store ist auf diesem PC ausgeschaltet, daher hat Vanta die Updates für Store-Apps übersprungen.
# „Microsoft Store reparieren“ is prepare-repair-store; „Bericht senden“ is report-title.
prepare-failed-store-repair-failed = Der Microsoft Store kann auf diesem PC keine Apps installieren oder aktualisieren, und Vanta konnte ihn nicht reparieren. Vanta braucht einen funktionierenden Store, denn wenn Vanta installiert wird, während er defekt ist, können der Store und seine Apps defekt bleiben. Wählen Sie „Microsoft Store reparieren“, um es erneut zu versuchen. Wenn er weiterhin nicht funktioniert, sichern Sie Ihre Dateien und installieren Sie Windows mit einer Vanta-ISO neu, oder wählen Sie „Bericht senden“.
prepare-repair-store = Microsoft Store reparieren

screen-keyboard-title = Tastatursprachen
screen-keyboard-question = Verwenden Sie mehrere Tastatursprachen?
package-option-keyboard-shortcuts = Ja, mit Tastenkombinationen
package-option-keyboard-selector = Ja, mit der Auswahl in der Taskleiste
package-option-keyboard-single = Nein, ich verwende nur ein Tastaturlayout
consequence-keyboard-shortcuts = Alt+Shift wechselt die Sprache; Ctrl+Shift wechselt das Layout.
consequence-keyboard-selector = Alt+Shift und Ctrl+Shift ausschalten, um versehentliche Wechsel beim Spielen zu vermeiden.
package-choice-keyboard-description = Wählen Sie, wie Sie die Tastatursprache wechseln.
consequence-keyboard-single = { consequence-keyboard-selector }

# Auswahlmodus-Leiste oben auf dem Bildschirm für Ihre Auswahl.
options-mode-title = Auswahlmodus
options-mode-recommended = Von Vanta empfohlen
options-mode-manual = Manuell auswählen
options-mode-recommended-detail = Wendet das empfohlene Vanta-Profil nur auf die Optionen dieser Seite an (behält VBS, Phishing-Schutz, Store und Snipping Tool bei; aktiviert Brave und Vanta-Optimierungen, ohne vorherige Schritte zu ändern).
options-mode-manual-detail = Beginnt mit allen deaktivierten Zusatzoptionen zur Einzelauswahl oder wendet „Von Vanta empfohlen“ mit einem Klick an.
options-mode-proceed = Mit Empfehlung fortfahren
prepare-ready-title = Alles bereit — klicken Sie unten auf Weiter
prepare-ready-detail = Windows ist für den nächsten Schritt bereit. Sie können jetzt fortfahren.
option-recommended-label = { $label } (empfohlen)
option-core-isolation-unlock = Ich spiele kein Valorant oder andere Spiele mit Anti-Cheat, das dies erfordert
option-why-disable-hibernation = Vorteil: gibt mehrere GB SSD-Speicher frei und sorgt für saubere Neustarts. Hinweis: deaktiviert Ruhezustand und Schnellstart auf Laptops.
option-why-disable-power-saving = Vorteil: verhindert Taktabfälle und Latenzspitzen in Spielen. Hinweis: höherer Stromverbrauch und kürzere Akkulaufzeit auf Laptops.
option-why-disable-core-isolation = Vorteil: kann die CPU-Last auf manchen PCs leicht senken. Hinweis: geringerer Schutz vor schädlichen Treibern; Spiele mit strengem Anti-Cheat (z. B. Valorant/Vanguard) starten nicht.
option-why-disable-phishing-protection = Funktion: deaktiviert Warnungen beim Eingeben Ihres Windows-Passworts auf unsicheren Websites. Vorteil: kein spürbarer FPS-Gewinn. Hinweis: geringerer Schutz vor Passwortdiebstahl.
option-why-disable-gamebar = Funktion: deaktiviert das Xbox Game Bar-Overlay und Hintergrundaufnahmen (Game DVR). Vorteil: weniger GPU- und Festplattenlast im Spiel. Hinweis: Win+G und Clips funktionieren nicht mehr.
option-why-remove-store = Funktion: entfernt die Microsoft Store-App, behält aber App Installer und winget. Vorteil: weniger Hintergrund-Updates. Hinweis: keine Store-Apps oder Game Pass-Spiele über den Store.
option-why-vanta-power = Funktion: aktiviert den optimierten Vanta-Energiesparplan für Desktop-PCs. Vorteil: reaktionsschnelle CPU ohne Drosselung beim Spielen. Hinweis: nur für Desktops; auf Laptops übersprungen.
option-why-vanta-memory = Funktion: lässt Speicherkomprimierung aktiv und deaktiviert Page Combining sowie App-Vorabladen. Vorteil: weniger Hintergrund-Festplattenlast und stabilere Frametimes. Hinweis: große Apps starten beim ersten Mal etwas langsamer.
option-why-tools-on-logon = Funktion: öffnet Vanta Tools automatisch bei der nächsten Anmeldung. Vorteil: Programme und Feineinstellungen sofort griffbereit. Hinweis: einmaliger Komfort ohne dauerhafte Auswirkungen.
option-why-remove-snipping-tool = Funktion: entfernt das Windows-Snipping Tool. Vorteil: spart eine Standard-App, wenn Sie ShareX oder Lightshot nutzen. Hinweis: Win+Umschalt+S funktioniert ohne Ersatz nicht mehr.
option-why-uninstall-edge = Vorteil: entfernt Hintergrunddienste und Updater von Edge. Hinweis: stellen Sie sicher, dass unten ein anderer Browser gewählt oder bereits installiert ist.
option-why-install-another-browser = Vorteil: ein Browser ist sofort nach der Einrichtung bereit, besonders wichtig beim Entfernen von Edge. Hinweis: erfordert Internetverbindung.
option-why-install-eclean = Vorteil: hilft beim Bereinigen temporärer Dateien und Autostart-Apps. Hinweis: optional, erfordert Konto und Internet.
option-why-browser-brave = Funktion: installiert Brave (Chromium) mit integriertem Werbe- und Trackerblocker. Vorteil: schnelles, aufgeräumtes Surfen ohne Erweiterungen. Hinweis: optionale Krypto-Funktionen können ignoriert werden.
option-why-browser-librewolf = Funktion: installiert LibreWolf, eine datenschutzgehärtete Firefox-Variante ohne Telemetrie. Vorteil: maximaler Tracking-Schutz. Hinweis: manche Websites benötigen Ausnahmen für Cookies.
option-why-browser-firefox = Funktion: installiert Mozilla Firefox, unabhängig von Chromium. Vorteil: guter Datenschutz und breite Erweiterungsunterstützung. Hinweis: einzelne Chromium-Web-Apps können abweichen.
option-why-browser-chrome = Funktion: installiert Google Chrome mit Google-Konto-Synchronisierung. Vorteil: höchste Website-Kompatibilität. Hinweis: höherer RAM-Verbrauch und mehr Datensammlung.
