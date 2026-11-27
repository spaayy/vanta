### Vanta Manager: Turkish (tr). Preview translation, revised on 1 October 2026 from the en-GB source (i18n/en-GB/atlas.ftl).
###
### Conventions for translators:
### - Keep the variables ({ $name }) exactly; reorder them freely.
### - Numbers arrive as numbers and are formatted for the user's region
###   automatically. Turkish nouns do not change after a number, so the
###   [one] and *[other] branches usually carry the same text.
### - Values marked "text" (versions, build numbers, file names, paths,
###   error details) are inserted as they are and must not be translated.
###   Never attach a Turkish suffix directly to a variable (vowel harmony
###   cannot be known); attach it to a following noun instead
###   ("{ $version } sürümünü", "{ $file } dosyasından").
### - Product names stay as they are: Vanta, Vanta, Windows, Microsoft
###   Defender, Windows Güvenliği, Windows Update, GitHub, Discord.
###   Windows feature names follow the Turkish Windows interface (for
###   example the four Virüs ve tehdit koruması switches).
### - Formal "siz" throughout, as in Microsoft Turkish. Buttons are short
###   imperatives. Sentences end with a full stop; titles and labels do not.
### - "Yeniden aç" = relaunch the Vanta Manager. "Yeniden başlat" = restart the PC.
### - The .vantapkg file is the "Vanta paketi" ("paket" once that is clear;
###   the button is "Paket dosyası aç").
### - A Windows build is a "derleme", as Windows says ("İS Derlemesi").
###   Diagnostics are "tanılama verileri" everywhere.

## Shared

app-name = Vanta Manager
common-done = Bitti
common-cancel = İptal
common-back = Geri
common-next = Devam et
common-dismiss = Kapat
# Link beside a summary row that jumps back to change that choice.
common-change = Değiştir
common-copy = Kopyala
# Shown where a list of options is empty.
common-none = Yok
# Accessible name of the back arrow on the Install and Settings pages.
common-back-to-home = Giriş sayfasına dön
# Accessible name of the gear button in the title bar.
common-settings = Ayarlar
common-close-settings = Ayarları kapat
common-open-windows-security = Windows Güvenliği'ni aç
common-restart-as-administrator = Yönetici olarak yeniden aç
common-try-again = Yeniden dene
common-show-details = Ayrıntıları göster
common-hide-details = Ayrıntıları gizle
# Accessible name of a Show details or Hide details toggle. $action is common-show-details or
# common-hide-details; $section is the title of the card it opens.
common-details-a11y = { $action }, { $section }
common-open-log-file = Günlük dosyasını aç
# Accessible name of the Copy button beside the install log.
common-copy-install-log = Kurulum günlüğünü kopyala
common-install-log = Kurulum günlüğü
# Row labels in summary cards.
common-windows = Windows
common-options = Seçenekler
common-package = Kurulum dosyaları
common-installed-as = Kurulum türü
common-installed = Kuruldu
common-checking = Denetleniyor
# Joins two items in a list: "Brave, Firefox". The braces keep the space.
list-separator = { ", " }
# Joins two alternatives: "26100 veya 26200".
list-or = { $a } veya { $b }
list-and = { $a } ve { $b }
# Accessible name of a message bar that announces itself: its title, then its message.
infobar-a11y = { $title }. { $message }

## Window

# Dialog shown when the window is closed while an install runs.
window-close-title = Vanta kurulurken pencere kapatılsın mı?
window-close-message = Kurulum arka planda devam eder. İlerlemeyi ve sonucu görmek için Vanta'ı yeniden açın. Kurulum bitene kadar bilgisayarınızı açık tutun.
# Instead of window-close-message when the installation restarts the PC afterwards: only an
# open Vanta window restarts it, so closing the window cancels that.
window-close-message-restart = Kurulum arka planda devam eder, ancak Vanta kapalıyken bilgisayarınız otomatik olarak yeniden başlamaz. İlerlemeyi ve sonucu görmek için Vanta'ı yeniden açın. Kurulum bitene kadar bilgisayarınızı açık tutun.
# The safe answer in every dialog shown when the window is closed, including those for ISO
# and USB creation, updates and Windows Update access.
window-close-keep = Açık tut
window-close-close = Pencereyi kapat
# Dialog shown when the window is closed during the final checks, before the
# installer has started; window-close-keep and window-close-close are its buttons.
window-close-preparing-title = Kurulum başlamadan pencere kapatılsın mı?
window-close-preparing-message = Vanta bilgisayarınızı hâlâ denetliyor ve kuruluma henüz başlamadı. Şimdi kapatırsanız kurulum başlamaz. Devam etmek için Vanta'ı yeniden açın.
prepare-close-title = Güncellemeler hâlâ sürüyor
# "Stop updating" is prepare-stop, the dialog's other button.
prepare-close-message = Güncellemeler sürerken Vanta'ı açık tutun. Güncellemeyi durdur'u seçerseniz güncellemeler geçerli adımdan sonra durur ve ardından Vanta'ı kapatabilirsiniz.
# Dialog shown when the window is closed during the restart countdown after a
# successful install. Its buttons are window-close-keep, restart-now and
# window-close-restart-close.
window-close-restart-title = Vanta yeniden başlatmadan kapatılsın mı?
# "Şimdi yeniden başlat" is restart-now, one of this dialog's three buttons.
window-close-restart-message = Vanta kurulumunu tamamlamak için bilgisayarınızın yeniden başlatılması gerekiyor. Vanta'ı şimdi kapatırsanız Vanta bilgisayarınızı yeniden başlatmaz; hazır olduğunuzda kendiniz yeniden başlatın. Şimdi yeniden başlat'ı seçmeden önce çalışmanızı kaydedin.
window-close-restart-close = Yeniden başlatmadan kapat
# Dialog shown when the window is closed during a setup with Windows Security switches still
# off. $switches names them as Windows Security does, joined like a list. Its buttons are
# window-close-keep, common-open-windows-security and window-close-close.
window-close-protection-title = Koruma kapalıyken Vanta kapatılsın mı?
window-close-protection-message = Windows Güvenliği'ndeki bazı korumalar hâlâ kapalı: { $switches }. Vanta'ı kurmayı bitirmeyecekseniz, kapatmadan önce bunları yeniden açın. Bitirecekseniz, Vanta'ı yeniden açtığınızda Vanta kurulumunuza kaldığı yerden devam eder.
# The Open button of the file picker for an Vanta package (.vantapkg) file, on Get ready and the
# ISO page. It's a button label, so keep it short.
file-dialog-open-package = Vanta paketi aç (.vantapkg)
# Message Windows shows in its restart notification.
shutdown-comment = Vanta kuruldu. Kurulumu tamamlamak için Windows yeniden başlatılıyor.
# Message Windows shows in its restart notification when "Get ready" restarts
# to finish installing Windows updates.
prepare-shutdown-comment = Vanta, güncelleştirmelerin yüklenmesini tamamlamak için Windows'u yeniden başlatıyor.

## System

# "Windows 11 Pro 25H2 (derleme 26200.1234)". All three values are text.
system-description = { $product } { $version } (derleme { $build })

## Home page

home-not-installed = Vanta'a hoş geldiniz
# The headline when Vanta Manager can't tell what is installed on this PC.
home-state-unknown = Bu bilgisayardaki Vanta
# The headline when Vanta is installed. $version is text.
home-version = Vanta { $version }
# $date is a formatted date.
home-installed-on = { $date } tarihinde kuruldu
home-status-checking = Güncelleştirmeler denetleniyor
# While startup checks whether another window's installation is running.
home-status-recovering = Devam eden bir kurulum aranıyor
home-status-offline = Güncelleştirmeler denetlenemedi
home-status-not-checked = Güncelleştirmeler henüz denetlenmedi
home-status-update = Vanta { $version } kullanılabilir
home-status-up-to-date = Güncel
home-status-newest = En son sürüm: Vanta { $version }
# An earlier installation of Vanta { $version } stopped before it finished.
home-status-unfinished = Vanta { $version } kurulumu tamamlanmadı
home-check-again = Yeniden denetle
# Primary button while an install is running or waiting.
home-show-install = İlerlemeyi görüntüle
home-continue-installing = Kuruluma devam et
home-update-to = Vanta { $version } sürümüne güncelleştir
home-reinstall = Vanta'ı yeniden kur
home-install = Vanta'ı kur
home-finish-install = Vanta { $version } kurulumunu tamamla
home-start-over = Baştan başla
home-restart-title = Bilgisayarınızın yeniden başlatılması gerekiyor
home-security-reminder-title = Korumayı yeniden açın
# Instead of home-security-reminder-title when no switch reads off but some couldn't be read
# (with home-security-reminder-unreadable-message).
home-security-reminder-unreadable-title = Korumanızın açık olduğundan emin olun
home-security-reminder-message = Vanta şu anda hiçbir şey kurmuyor, ancak Windows Güvenliği'ndeki bazı korumalar hâlâ kapalı. Windows Güvenliği'ni açın ve şunların açık olduğundan emin olun: { $switches }.
home-security-reminder-unreadable-message = Vanta koruma anahtarlarının hepsini okuyamadı. Windows Güvenliği'nde şunların açık olduğunu denetleyin: { $switches }.
home-elevation-title = Vanta'ın kurulum için izne ihtiyacı var
home-state-error-title = Vanta kurulum bilgileriniz okunamadı
home-state-error-message = Vanta sürümünüz, seçimleriniz ve kurulum geçmişiniz doğru gösterilmeyebilir. Yeniden denemek için Yeniden denetle'yi seçin. Ayrıntılar: { $error }
home-whats-new = Vanta { $version } sürümündeki yenilikler
home-view-release = Sürüm notlarını GitHub'da görüntüle
home-released = { $date } tarihinde yayımlandı
home-show-less = Daha az göster
home-show-full-notes = Tüm sürüm notlarını göster
home-your-install = Vanta kurulumunuz
# Vanta is installed, but without the record Vanta Manager keeps (older versions didn't write one).
home-install-unrecorded = Bu bilgisayarda Vanta'ın nasıl kurulduğuna dair bir kayıt yok, bu yüzden seçimleriniz ve kurulum geçmişi gösterilemiyor.
home-history = Kurulum geçmişi
# One history row. $version is text, $mode one of the history-mode-* messages, $date a formatted date and time.
home-history-entry = Vanta { $version } · { $mode } · { $date }
home-how-it-works = Bilgisayarınızı Vanta için hazırlayalım
home-step-1-detail = Vanta bilgisayarınızı denetler, bekleyen Windows ve Microsoft Store güncellemelerini yükler ve kurulum dosyalarını indirir. Store uygulamaları kapanabilir ve bilgisayarınızın yeniden başlatılması gerekebilir; bu yüzden önce çalışmanızı kaydedin.
# Tester build: the Vanta package is bundled, nothing is downloaded.
home-step-1-detail-bundled = Vanta bilgisayarınızı denetler, bekleyen Windows ve Microsoft Store güncellemelerini yükler ve birlikte gelen kurulum dosyalarını hazırlar. Store uygulamaları kapanabilir ve bilgisayarınızın yeniden başlatılması gerekebilir; bu yüzden önce çalışmanızı kaydedin.
home-step-2-detail = Microsoft Defender'ı ve işlemci korumalarını tutup tutmayacağınızı, Windows güncelleştirmelerinin nasıl yükleneceğini ve isteğe bağlı ek özellikleri seçin.
home-step-3-detail = Kurulumu engellememeleri için Windows Güvenliği'ndeki dört koruma anahtarını kapatın. Vanta size nasıl yapacağınızı gösterir.
home-step-4-detail =
    { $minutes ->
        [one] Kurulum yaklaşık bir dakika sürer. Ardından bilgisayarınızın yeniden başlatılması gerekir.
       *[other] Kurulum yaklaşık { $minutes } dakika sürer. Ardından bilgisayarınızın yeniden başlatılması gerekir.
    }
# Accessible name of a numbered step.
home-step-a11y = { $number }. adım: { $title }
home-report-problem = Sorun bildir

## How an install was done (from the state document)

mode-fresh = İlk kurulum
mode-upgrade = Önceki sürümden güncelleştirme
mode-reapply = Aynı sürümün yeniden kurulumu
mode-unknown = Kurulum
# Lower-case forms used inside a history row.
history-mode-fresh = ilk kurulum
history-mode-upgrade = güncelleştirme
history-mode-reapply = yeniden kurulum
history-mode-unknown = kurulum

## Notices on the Home page

notice-settings-reset-title = Vanta varsayılan uygulama ayarlarını kullanıyor
# $error is a raw error message (text).
notice-settings-unreadable = Vanta kayıtlı uygulama ayarlarınızı okuyamadı. Windows ayarlarınız değişmedi. Ayrıntılar: { $error }
# $file is a file name (text).
notice-settings-damaged-kept = Uygulama ayarları dosyanız hasarlıydı ve sıfırlandı. Eski dosyanın bir kopyası { $file } adıyla kaydedildi. Ayrıntılar: { $error }
notice-settings-damaged = Uygulama ayarları dosyanız hasarlı. Vanta şimdilik varsayılan ayarları kullanıyor. Ayrıntılar: { $error }
notice-settings-not-saved-title = Uygulama ayarları kaydedilemedi
# $error is a raw error message (text).
notice-settings-not-saved = Vanta son değişikliklerinizi kaydedemedi; Vanta'ı kapattığınızda bu değişiklikler kaybolabilir. Başka bir Vanta penceresi açıksa kapatın, sonra değişikliği yeniden yapın. Ayrıntılar: { $error }
notice-session-unreadable-title = Önceki kurulum denetlenemedi
# $path is a file path (text).
notice-session-unreadable-message = Vanta, önceki bir kurulumun hâlâ sürüp sürmediğini anlayamadı. Emin değilseniz Vanta topluluğundan yardım isteyin. Yalnızca çalışan bir kurulum olmadığından eminseniz { $path } dosyasını silin ve yeniden deneyin. Ayrıntılar: { $error }

## Administrator elevation

elevation-declined = İzin verilmedi. Yeniden deneyin ve Windows, Vanta'ın değişiklik yapmasına izin vermenizi istediğinde Evet'i seçin.
elevation-declined-continue = İzin verilmedi. Yeniden deneyin ve Windows, Vanta'ın değişiklik yapmasına izin vermenizi istediğinde Evet'i seçin. Kurulum seçimleriniz kaydedildi.
elevation-draft-not-saved = Vanta kurulum seçimlerinizi kaydedemedi, bu yüzden yeniden açılmadı. Yeniden deneyin. Ayrıntılar: { $error }
# Shown with the home-start-over button.
elevation-taken-over = Başka bir Vanta penceresi bu kurulumu devraldı, bu yüzden Vanta yeniden açılmadı. O pencerede devam edin veya kurulumu burada baştan yapmak için Baştan başla'yı seçin.

## The install flow

step-ready = Hazırlık
step-options = Seçimleriniz
step-security = Windows Güvenliği
step-install = Kurulum
install-title = Vanta kurulumu
# Accessible name of the row of steps.
stepper-label = Vanta kurulum adımları
# Accessible name of one step. $status is one of the stepper-status-* messages.
stepper-step-a11y = Adım { $number } / { $total }, { $title }, { $status }
stepper-status-completed = tamamlandı
stepper-status-current = geçerli adım
stepper-status-upcoming = sonraki adım
stepper-status-attention = dikkat gerektiriyor
# Heading above each step's content.
step-heading = Adım { $number } / { $total }: { $title }
# Accessible name of the step heading on a screen of Your choices, read when it takes focus.
# $heading is step-heading; $progress is options-progress; $question is the screen's question.
step-heading-choice-a11y = { $heading }. { $progress }: { $question }
# The same on the optional extras screen; $progress is options-progress-extras.
step-heading-extras-a11y = { $heading }. { $progress }

## Step 1: Get ready

ready-banner-busy-title = Bilgisayarınız hazırlanıyor
ready-banner-busy-message = Vanta bilgisayarınızı denetliyor ve kurulum dosyalarını hazırlıyor.
ready-banner-blocked-title = Bilgisayarınız henüz hazır değil
ready-banner-blocked-message = Bilgisayar denetimlerinde işaretlenen sorunları giderin, ardından Yeniden denetle'yi seçin.
ready-banner-no-package-title = Devam etmek için Vanta'ı indirin
ready-banner-no-package-message = Vanta'ı Kurulum dosyaları kartından indirin veya bir Vanta paketiniz (.vantapkg) varsa Paket dosyası aç'ı seçin.
# The package tried needs a newer Vanta Manager. The title is also the footer's hint then.
ready-banner-manager-title = Devam etmek için Vanta Manager'ın daha yeni bir sürümünü indirin
# "Download Vanta Manager" is manager-download, the button in Installation files (package-title).
ready-banner-manager-message = Kurulum dosyaları kartında Vanta Manager'ı indir'i seçin, ardından bu sürüm yerine yeni sürümü kullanın.
# Tester build: the bundled Vanta package couldn't be unpacked.
ready-banner-no-package-bundled-title = Devam etmek için birlikte gelen Vanta paketini hazırlayın
ready-banner-no-package-bundled-message = Bu uygulamayla gelen Vanta paketi henüz hazır değil. Kurulum dosyaları kartını denetleyin.
ready-banner-updates-title = Devam etmek için Windows ve Store uygulamalarını güncelleyin
ready-banner-updates-message = Güncellemeleri denetle ve yükle'yi seçin. Güncellemeler bittiğinde Vanta bilgisayarınızı yeniden denetler.
# While Windows and Store apps update. "Update Windows and Store apps" is prepare-title, the
# card further down the page.
ready-banner-updating-title = Windows ve Store uygulamaları güncelleniyor
ready-banner-updating-message = Bu biraz zaman alabilir. Vanta'ı açık tutun. İlerlemeyi Windows ve Store güncellemeleri kartında izleyebilirsiniz.
# After Stop updating. "Check and install updates" is prepare-start, the card's button.
ready-banner-updates-stopped-title = Güncelleme durduruldu
ready-banner-updates-stopped-message = Bitirmek için Windows ve Store güncellemeleri kartında Güncellemeleri denetle ve yükle'yi seçin.
# Vanta reopened after restarting the PC to continue updating. "Continue updates" is
# prepare-continue, the card's button.
ready-banner-updates-resumed-title = Bilgisayarınız yeniden başlatıldı
ready-banner-updates-resumed-message = Güncellemeyi bitirmek için Windows ve Store güncellemeleri kartında Güncellemelere devam et'i seçin.
# Under prepare-failed-title or prepare-unconfirmed-title. "Try again" is common-try-again,
# the card's button.
ready-banner-updates-failed-message = Ne yapmanız gerektiğini görmek için Windows ve Store güncellemeleri kartına bakın, ardından Yeniden dene'yi seçin.
# Under prepare-reboot-title. "Restart and continue" is prepare-restart, the card's button.
ready-banner-reboot-message = Önce çalışmanızı kaydedin, ardından Windows ve Store güncellemeleri kartında Yeniden başlat ve devam et'i seçin.
ready-banner-warnings-title = Gözden geçirmeniz gereken birkaç nokta var
ready-banner-warnings-message = Devam edebilirsiniz, ancak önce Bilgisayar denetimlerinde işaretlenen öğeleri okuyun.
ready-banner-ok-title = Seçimlerinizi yapmaya hazırsınız
ready-banner-ok-message = Denetimler geçti ve kurulum dosyalarınız hazır.

# Card title and accessible name of the list of checks.
ready-this-pc = Bilgisayar denetimleri
ready-check-again = Yeniden denetle
ready-checks-passed =
    { $count ->
        [one] { $count } denetim geçti
       *[other] { $count } denetim geçti
    }

package-title = Kurulum dosyaları
# $received and $total are formatted numbers of megabytes (text).
package-downloading = Vanta { $version } indiriliyor · { $received } / { $total } MB
package-unpacking-progress =
    { $total ->
        [one] Paket açılıyor · { $done } / { $total } dosya
       *[other] Paket açılıyor · { $done } / { $total } dosya
    }
package-unpacking = Paket açılıyor
package-looking = En son Vanta sürümü denetleniyor.
# Tester build: the bundled Vanta package is being unpacked, nothing is downloaded.
package-looking-bundled = Birlikte gelen Vanta paketi hazırlanıyor.
package-none = Kurulum dosyalarını almak için Vanta'ı indirin. Elinizde bir Vanta paketi (.vantapkg) varsa bunun yerine onu açın.
# The GitHub release check failed. "En son sürümü indir" is package-download-newest,
# the button offered in this state; it checks again.
package-release-failed = Vanta en son sürümü denetleyemedi. İnternet bağlantınızı denetleyin, sonra En son sürümü indir'i seçin veya kayıtlı bir Vanta paketi (.vantapkg) açın.
# Short status words beside the card title.
package-status-downloading = İndiriliyor
package-status-unpacking = Açılıyor
package-status-failed = Dosyalar hazırlanamadı
package-status-ready = Hazır
package-status-checking = Denetleniyor
package-status-preparing = Hazırlanıyor
package-status-missing = İndirilmedi
# Accessible name of the progress bar.
package-progress = Kurulum dosyalarının ilerlemesi
package-download-again = Yeniden indir
package-download-version = Vanta { $version } sürümünü indir
package-download-newest = En son sürümü indir
package-cancel-download = İndirmeyi iptal et
package-open-file = Paket dosyası aç
# Where the package came from. $file is a file name, $path a folder path (text).
package-from-release = Vanta { $version } GitHub'dan indirildi ve kuruluma hazır.
package-from-file = Vanta { $version }, { $file } dosyasından yüklendi ve kuruluma hazır.
package-unpacked = Vanta { $version } kuruluma hazır.
package-none-yet = Kurulum dosyası seçilmedi
acquire-no-asset = Vanta { $version } sürümü için indirilebilecek bir paket dosyası yok. Devam etmek için kayıtlı bir Vanta paketi (.vantapkg) açın.
# Shown for a package older than Vanta 0.6.0, and for a file that isn't an Vanta package, such as an
# .apbx file from an Vanta release before 0.6.
acquire-unsupported = Bu uygulama Vanta 0.6.0 ve sonraki sürümleri Vanta paketlerinden (.vantapkg) kurabilir.
# A package new enough to include the installer script that this app drives, but without it.
acquire-incomplete = Vanta { $version } sürümünde bu uygulamanın kurulum için ihtiyaç duyduğu dosyalar eksik. Sürümü yeniden indirin veya başka bir Vanta paketi (.vantapkg) açın.
acquire-failed = Kurulum dosyaları hazırlanamadı. Yeniden indirmeyi deneyin veya başka bir Vanta paketi (.vantapkg) açın. Ayrıntılar: { $error }
# The download received nothing for a minute and was stopped.
acquire-stalled = İndirme yanıt vermeyi durdurdu. İnternet bağlantınızı denetleyin, sonra yeniden indirin veya kayıtlı bir Vanta paketi (.vantapkg) açın.
# Tester build: the bundled Vanta package couldn't be unpacked. Try again is the only control offered.
acquire-failed-bundled = Birlikte gelen Vanta paketi hazırlanamadı. Yeniden dene'yi seçin. Ayrıntılar: { $error }
# The Vanta package asks for a newer Vanta Manager than this one. $version is the version it asks for,
# such as 0.7.0. "Download Vanta Manager" is manager-download, the button beside the message.
acquire-manager-outdated = Bu Vanta paketi için Vanta Manager { $version } sürümü veya sonrası gerekiyor. Vanta Manager'ı indir'i seçin, ardından bu sürüm yerine yeni sürümü kullanın.
# The same, for a package that doesn't say which version it needs.
acquire-manager-outdated-any = Bu Vanta paketi için Vanta Manager'ın daha yeni bir sürümü gerekiyor. Vanta Manager'ı indir'i seçin, ardından bu sürüm yerine yeni sürümü kullanın.

## Newer Vanta Manager

# Opens the latest Vanta release on GitHub in the browser, where Vanta Manager is downloaded.
manager-download = Vanta Manager'ı indir
# A note on Home and in Settings that a newer Vanta Manager has been released. $version is its
# version, such as 0.7.0. The note doesn't stop anything; manager-download is its button.
manager-update-title = Vanta Manager { $version } sürümü kullanılabilir
manager-update-message = Vanta Manager kendini güncelleyemez. Yeni sürümü indirin ve bu sürüm yerine onu kullanın.

## System checks

check-administrator = Kurulum izni
check-supported-build = Windows uyumluluğu
check-pending-updates = Windows güncelleştirmeleri
check-pending-reboot = Bekleyen yeniden başlatma
check-third-party-antivirus = Diğer virüsten koruma yazılımları
check-internet = İnternet bağlantısı
check-power = Güç kaynağı
check-activation = Windows etkinleştirmesi
# Accessible name of a check row. $state is one of the check-state-* messages.
check-a11y = { $title }: { $state }
check-state-checking = denetleniyor
check-state-passed = geçti
check-state-warning = dikkat gerektiriyor
check-state-failed-blocking = kurulumdan önce işlem gerekiyor
check-state-failed = dikkat gerektiriyor
check-state-unknown = denetlenemedi
check-fix-windows-update = Windows Update'i aç
check-fix-network = Ağ ayarlarını aç
check-fix-power = Güç ayarlarını aç
check-fix-activation = Etkinleştirme ayarlarını aç
check-fix-apps = Yüklü uygulamaları aç
# Check box the user ticks when the Windows Update scan could not run.
check-ack-updates = Windows Update'i denetledim: yüklenmeyi bekleyen güncelleştirme yok

detail-admin-ok = Vanta, kurulum için gereken değişiklikleri yapma iznine sahip.
detail-admin-missing = Vanta'ı yönetici olarak yeniden açın, ardından Windows izin istediğinde Evet'i seçin.
# $builds is a list of build numbers such as "26100 veya 26200"; $build is this PC's (text).
detail-build-unsupported = Bu Vanta sürümü için Windows { $builds } derlemesi gerekiyor. Bilgisayarınızda { $build } derlemesi var. Devam etmeden önce desteklenen bir Windows sürümü yükleyin.
detail-build-missing = Bu Vanta paketi desteklenen hiçbir Windows derlemesini listelemiyor. LocalTest sürümü yerine paketin tam sürümünü kullanın.
detail-updates-none = Yüklenmeyi bekleyen Windows güncelleştirmesi yok.
# $titles lists up to two update names (text); $count is the total. "Windows ve Store
# güncellemeleri" is prepare-title, the card that installs them.
detail-updates-pending =
    { $count ->
        [1] Bu güncelleştirme bekliyor: { $titles }. Vanta bunu Windows ve Store güncellemeleri kartında yükler.
        [2] Bu güncelleştirmeler bekliyor: { $titles }. Vanta bunları Windows ve Store güncellemeleri kartında yükler.
       *[other] { $titles } dahil { $count } güncelleştirme bekliyor. Vanta bunları Windows ve Store güncellemeleri kartında yükler.
    }
detail-updates-unknown = Windows güncelleştirmeleri denetlenemedi. Windows Update'i açın; bekleyen güncelleştirme yoksa aşağıda onaylayın. ({ $error })
detail-reboot-none = Windows'un şu anda yeniden başlatılması gerekmiyor.
detail-reboot-pending = Önceki değişiklikleri tamamlamak için Windows'un yeniden başlatılması gerekiyor. Güncellemeleri denetle ve yükle'yi seçtiğinizde Vanta önce yeniden başlatmanızı ister.
# $reasons: the pending-restart markers Windows set, from the prepare-reason-* names.
detail-reboot-pending-reasons = Önceki değişiklikleri tamamlamak için Windows'un yeniden başlatılması gerekiyor ({ $reasons }). Güncellemeleri denetle ve yükle'yi seçtiğinizde Vanta önce yeniden başlatmanızı ister.
# Warning, not a block: $files lists up to three file paths Windows will replace or remove at the next restart.
detail-reboot-file-renames = Devam edebilirsiniz. Windows'un bir sonraki yeniden başlatmada değiştireceği veya kaldıracağı dosyalar var ({ $files }). Xbox Gaming Services gibi bazı uygulamalar bunu her yeniden başlatmadan sonra yapar.
detail-reboot-unknown = Windows'un yeniden başlatılması gerekip gerekmediği denetlenemedi. Bilgisayarınızı yeniden başlatın, ardından Vanta'ı yeniden açıp yeniden denetleyin. ({ $error })
detail-antivirus-none = Başka bir virüsten koruma yazılımı algılanmadı.
# $products is a list of product names (text).
detail-antivirus-found = Microsoft Defender dışındaki virüsten koruma uygulamaları kurulumu engelleyebilir. { $products } yazılımını kaldırın, ardından Yeniden denetle'yi seçin.
# Warning, not a block: Security Center still lists the product but its files are gone.
detail-antivirus-stale = Windows Güvenliği { $products } yazılımını hâlâ listeliyor, ancak dosyaları artık yok; yani artık yüklü değil. Vanta yine de kurulabilir.
detail-antivirus-unknown = Diğer virüsten koruma yazılımları denetlenemedi. Yeniden denetle'yi seçin. Sorun devam ederse bilgisayarınızı yeniden başlatın ve yeniden denetleyin. ({ $error })
detail-internet-ok = İnternete bağlısınız. Vanta yazılımları indirip kurarken bu bağlantıyı açık tutun.
detail-internet-missing = İnternete bağlanın, sonra yeniden denetleyin.
detail-power-mains = Bilgisayarınız fişe takılı. Kurulum bitene kadar takılı bırakın.
detail-power-battery = Kurulum boyunca açık kalması için bilgisayarınızı fişe takın.
detail-power-unknown = Vanta, bilgisayarınızın fişe takılı olup olmadığını anlayamadı. Dizüstü bilgisayar kullanıyorsanız fişe takın, ardından Yeniden denetle'yi seçin. Bu durum devam ederse Rapor gönder'i seçin.
detail-activation-ok = Windows etkin. Vanta bunu değiştirmez.
detail-activation-missing = Windows etkin değil. Devam edebilirsiniz, ancak Vanta Windows'u sizin için etkinleştirmez.
detail-activation-no-licence = Windows bir lisans bildirmedi. Devam edebilirsiniz; Vanta etkinleştirme durumunuzu değiştirmez.
detail-activation-unknown = Windows etkinleştirmesi denetlenemedi. Devam edebilirsiniz; Vanta etkinleştirme durumunuzu değiştirmez. ({ $error })

## Step 2: Options

options-progress = Seçim { $number } / { $total }
options-progress-extras = Seçim { $number } / { $total }: isteğe bağlı ek özellikler
options-change-later = Microsoft Defender, işlemci korumaları ve güncelleştirme ayarlarını daha sonra masaüstünüzdeki Vanta klasöründen değiştirebilirsiniz.
# Short names for each decision (summary rows) and the question each screen asks.
screen-defender-title = Microsoft Defender
screen-defender-question = Microsoft Defender kalsın mı?
screen-mitigations-title = İşlemci korumaları
screen-mitigations-question = Windows'un işlemci korumaları açık kalsın mı?
screen-updates-title = Windows Update
screen-updates-question = Windows güncelleştirmeleri nasıl yüklesin?
screen-browser-title = Tarayıcı
screen-power-title = Güç ve güvenlik
screen-apps-title = Uygulamalar
screen-optional-apps-title = İsteğe bağlı uygulamalar
screen-choose-one-title = Bir seçenek belirleyin
screen-extras-title = İsteğe bağlı ek özellikler
# Question for a required choice this app has no specific wording for.
screen-generic-question = { $title } için bir seçenek belirleyin
learn-more-defender = Microsoft Defender hakkında daha fazla bilgi
learn-more-mitigations = İşlemci korumaları hakkında daha fazla bilgi
learn-more-updates = Windows Update hakkında daha fazla bilgi
learn-more-browser = Tarayıcılar hakkında daha fazla bilgi
learn-more-power = Güç ve güvenlik hakkında daha fazla bilgi
learn-more-apps = Uygulamalar hakkında daha fazla bilgi
learn-more-eclean = eclean, Vanta ile nasıl çalışır?
learn-more-generic = Kurulum kılavuzunu oku
# One line under the chosen answer: what it means for the PC.
consequence-defender-enable = Bilgisayarınızı virüslerden ve diğer tehditlerden korumaya yardımcı olan yerleşik Windows virüsten koruma yazılımını tutar.
consequence-defender-disable = SmartScreen'i de kaldırır. Başka bir virüsten koruma uygulaması yükleyene kadar bilgisayarınızda virüsten koruma olmaz ve Windows, tanınmayan uygulamaları veya indirilen dosyaları açmadan önce sizi uyarmaz.
consequence-mitigations-default = Windows'un işlemci açıklarına ve uygulamalardaki hatalardan yararlanan saldırılara karşı varsayılan korumalarını tutar.
consequence-mitigations-disable = Uygulamalar için Denetim akışı koruması (CFG) gibi Açıktan yararlanma koruması ayarlarını da kapatır. Bu, güvenliği azaltır. Performansta bir fark olup olmayacağı işlemcinize bağlıdır.
consequence-auto-updates-disable = Güncelleştirmeleri yüklemek için Windows Update'i düzenli olarak açın. Güncelleştirme bildirimleri açık kalır.
consequence-auto-updates-default = Windows, güvenlik düzeltmeleri dahil güncelleştirmeleri otomatik olarak yükler.

## Vanta package text
## Labels and descriptions for the Vanta package's options and choices, by
## their ids in the package's vanta.json. The app shows these in place of the
## package's own English text; an option or choice that a newer package adds,
## which has no message here, shows the package's English.

package-option-defender-enable = Microsoft Defender'ı tut
package-option-defender-disable = Microsoft Defender'ı kaldır
package-option-mitigations-default = İşlemci korumalarını tut
package-option-mitigations-disable = İşlemci korumalarını kapat
package-option-auto-updates-disable = Güncelleştirmeleri kendim yükleyeceğim
package-option-auto-updates-default = Güncelleştirmeleri otomatik olarak yükle
package-option-disable-hibernation = Hazırda bekletmeyi kapat

package-option-disable-phishing-protection = Turn off Enhanced Phishing Protection (Windows stops warning when you type your password into a known phishing site)
package-option-disable-gamebar = Turn off Game Bar and game capture
package-option-remove-store = Remove the Microsoft Store (App Installer and winget stay)
package-option-vanta-power = Use the Vanta power plan (desktop PCs only; skipped on laptops)
package-option-vanta-memory = Use the Vanta memory profile (memory compression on, page combining and app pre-launch off)
package-option-tools-on-logon = Open Vanta Tools the next time I sign in
package-option-disable-power-saving = Güç tasarrufunu kapat
package-option-disable-core-isolation = Sanallaştırma tabanlı güvenliği (VBS) kapat
package-option-remove-snipping-tool = Ekran Alıntısı Aracı'nı kaldır
package-option-uninstall-edge = Microsoft Edge'i kaldır
package-option-install-another-browser = Tarayıcı yükle
package-option-install-eclean = eclean yükle
package-option-browser-brave = Brave
package-option-browser-librewolf = LibreWolf
package-option-browser-firefox = Firefox
package-option-browser-chrome = Chrome
package-choice-defender-description = Microsoft Defender, Windows'un yerleşik virüsten koruma yazılımıdır. Yalnızca riskleri anlıyorsanız ve başka bir virüsten koruma uygulaması kullanacaksanız kaldırın. Hangisini seçerseniz seçin, Vanta şunları kapatır: Akıllı Uygulama Denetimi, Gelişmiş Kimlik Avı Koruması ve Cihazımı bul.

package-choice-protections-description = Windows protections that stay on unless you turn them off. Nothing here is turned off by default.
package-choice-vanta-description = Vanta extras. All are off unless you tick them.
package-choice-mitigations-description = Güvenlik risk azaltmaları olarak da bilinen bu korumalar, Spectre ve Meltdown gibi işlemci açıklarına ve uygulamalardaki hatalardan yararlanan saldırılara karşı korunmaya yardımcı olur. Windows varsayılanlarını tutmanız önerilir.
package-choice-auto-updates-description = Vanta kurulumu tamamlandıktan sonra Windows'un güncelleştirmeleri nasıl yükleyeceğini seçin (bu bilgisayarı önceden hazırlayan Adım 1'den farklı olarak). Windows'un bunları otomatik olarak yüklemesine izin verebilir veya kendiniz yükleyebilirsiniz. Her iki durumda da Vanta, Windows'u geçerli sürümünde tutar ve bu sürüm yalnızca Microsoft desteği sona erene kadar güvenlik düzeltmeleri alır. Vanta ayrıca Microsoft Store uygulamalarının otomatik güncelleştirmelerini kapatır; bunları Microsoft Store üzerinden güncelleyin.
package-choice-browser-description = Yüklenecek bir tarayıcı seçin. Vanta tarayıcı ayarlarınızı değiştirmez.

## Step 3: Windows Security

security-banner-reading-title = Windows Güvenliği denetleniyor
security-banner-reading-message = Vanta aşağıdaki dört koruma anahtarını denetliyor.
security-banner-off-title = Dört koruma anahtarı da kapalı
# Shown instead of the switch list when Microsoft Defender isn't on this PC and the user
# chose to remove it.
security-banner-absent-title = Microsoft Defender bu bilgisayarda yüklü değil
security-banner-absent-message = Bu adımda kapatılacak bir şey yok. Devam et'i seçin.
security-banner-off-message = Kurulumunuzu gözden geçirmek ve Vanta'ı kurmak için Devam et'i seçin.
security-banner-on-title = Windows Güvenliği'nde virüsten korumayı kapatın
security-banner-on-message = Microsoft Defender, Vanta'ın yaptığı değişiklikleri engelleyebilir. Windows Güvenliği'ni aç'ı seçin ve aşağıda listelenen her anahtarı kapatın. Microsoft Defender'ı tutarsanız kurulum bittikten sonra anahtarları yeniden açın.
# The page name in Windows Security.
security-list-title = Virüs ve tehdit koruması ayarları
security-switch-off = Kapalı
security-switch-on = Açık
security-switch-unreadable = Okunamıyor
security-switch-reading = Denetleniyor
security-all-off = Tümü kapalı
# Accessible name of a switch row. $state is one of the security-switch-* messages.
security-a11y = { $title }: { $state }
# Parts of the summary "2 tanesi hâlâ açık, 1 tanesi okunamıyor".
security-count-still-on = { $count } tanesi hâlâ açık
security-count-unreadable = { $count } tanesi okunamıyor
security-count-join = { $a }, { $b }
security-unknown-title = Vanta'ın okuyamadığı anahtarları onaylayın
security-unknown-message = Windows Güvenliği'nde dört anahtarın da kapalı olduğundan emin olun, ardından aşağıda onaylayın.
security-acknowledge = Windows Güvenliği'ni denetledim ve dört anahtar da kapalı
security-unknown-unelevated-title = Vanta'ın korumayı denetlemek için izne ihtiyacı var
security-unknown-unelevated-message = Microsoft Defender ayarlarını denetleyebilmesi için Vanta'ı yönetici olarak yeniden açın.
# The four switches, named as Windows Security names them in Turkish.
protection-tamper = Kurcalama Koruması
protection-tamper-why = Vanta'ın Defender'ın güvenlik ayarlarını değiştirebilmesi için bunu kapatın.
protection-realtime = Gerçek zamanlı koruma
protection-realtime-why = Defender'ın Vanta kurulum dosyalarını tararken engellememesi için bunu kapatın.
protection-cloud = Bulut tabanlı koruma
protection-cloud-why = Çevrimiçi tehdit denetimlerinin Vanta kurulum dosyalarını engellememesi için bunu kapatın.
protection-samples = Otomatik örnek gönderimi
protection-samples-why = Defender'ın Vanta dosyalarını analiz için Microsoft'a otomatik olarak göndermesini durdurun.

## Step 4: Install

# Accessible name of the progress bar.
install-progress = Kurulum ilerlemesi
# The installation's progress shown beside the bar. $percent is a whole number from 0 to 99.
install-percent = %{ $percent }
outcome-succeeded-title = Vanta kuruldu
outcome-lost-title = Kurulum sonucu doğrulanamadı
outcome-failed-title = Kurulum tamamlanmadı
outcome-requirements = Bilgisayarınız kurulum gereksinimlerini karşılamadı. Kurulum hiçbir değişiklik yapmadı. Hazırlık adımına dönüp denetimleri yeniden çalıştırın.
# The -resumed variants follow a retry of an installation an earlier attempt had already started applying.
outcome-requirements-resumed = Bilgisayarınız kurulum gereksinimlerini karşılamadığı için bu deneme durdu. Önceki bir deneme değişiklik yapmaya zaten başlamıştı. Hazırlık adımına dönüp denetimleri yeniden çalıştırın.
outcome-not-elevated = Vanta'ın yönetici izni yoktu. Kurulum hiçbir değişiklik yapmadı. Vanta'ı yönetici olarak yeniden açın, ardından yeniden deneyin.
outcome-not-elevated-resumed = Vanta'ın yönetici izni olmadığı için bu deneme durdu. Önceki bir deneme değişiklik yapmaya zaten başlamıştı. Vanta'ı yönetici olarak yeniden açın, ardından yeniden deneyin.
# The installer's live check found Windows or Store updates unfinished. Get ready offers the
# update check again; "Güncellemeleri denetle ve yükle" is prepare-start, its button in that state.
outcome-preparation-stale = Vanta, Windows ve Store uygulamalarının güncel olduğunu doğrulayamadı, bu yüzden kurulum Windows'u değiştirmeden durdu. Hazırlık adımına dönüp Güncellemeleri denetle ve yükle'yi seçin.
outcome-preparation-stale-resumed = Vanta, Windows ve Store uygulamalarının güncel olduğunu doğrulayamadığı için bu deneme durdu, ancak önceki bir deneme değişiklik yapmaya zaten başlamıştı. Hazırlık adımına dönüp Güncellemeleri denetle ve yükle'yi seçin.
outcome-failed-preflight = Kurulum, hiçbir şey değiştirilmeden durdu. Yeniden deneyebilirsiniz. Yine durursa Rapor gönder'i seçin.
outcome-failed-staging = Kurulum, dosyalar hazırlanırken ve Windows değiştirilmeden önce durdu. Yeniden deneyebilirsiniz. Yine durursa Rapor gönder'i seçin.
outcome-failed-applying = Bazı değişiklikler yapılmış olabilir. Yeniden deneyebilirsiniz. Burada duracaksanız, kapattığınız korumaları hâlâ mevcutsa Windows Güvenliği'nde yeniden açın.
outcome-failed-applying-defender-removed = Bazı değişiklikler yapılmış olabilir. Yeniden deneyebilirsiniz. Kurulum yine durursa Rapor gönder'i seçin.
outcome-failed-resumed = Bu deneme erken durdu, ancak önceki bir deneme değişiklik yapmaya zaten başlamıştı. Yeniden deneyebilirsiniz. Burada duracaksanız, kapattığınız korumaları hâlâ mevcutsa Windows Güvenliği'nde yeniden açın.
outcome-failed-resumed-defender-removed = Bu deneme erken durdu, ancak önceki bir deneme değişiklik yapmaya zaten başlamıştı. Yeniden deneyebilirsiniz. Kurulum yine durursa Rapor gönder'i seçin.
outcome-failed-repeated = Bu deneme öncekiyle aynı hatayla durdu ve bazı değişiklikler yapılmış olabilir. Hiçbir şeyi değiştirmeden yeniden denemenin işe yaraması pek olası değil. Vanta ekibinin nedeni bulabilmesi için Rapor gönder'i seçin. Burada duracaksanız, kapattığınız korumaları hâlâ mevcutsa Windows Güvenliği'nde yeniden açın.
outcome-failed-repeated-defender-removed = Bu deneme öncekiyle aynı hatayla durdu ve bazı değişiklikler yapılmış olabilir. Hiçbir şeyi değiştirmeden yeniden denemenin işe yaraması pek olası değil. Vanta ekibinin nedeni bulabilmesi için Rapor gönder'i seçin.
outcome-failed-repeated-apps = Windows şunları yine kaldırmadı: { $apps }. Bu nedenle bu deneme de öncekiyle aynı hatayla durdu. Bazı değişiklikler yapılmış olabilir. Hiçbir şeyi değiştirmeden yeniden denemenin işe yaraması pek olası değil. Vanta ekibinin nedeni bulabilmesi için Rapor gönder'i seçin. Burada duracaksanız, kapattığınız korumaları hâlâ mevcutsa Windows Güvenliği'nde yeniden açın.
outcome-failed-repeated-apps-defender-removed = Windows şunları yine kaldırmadı: { $apps }. Bu nedenle bu deneme de öncekiyle aynı hatayla durdu. Bazı değişiklikler yapılmış olabilir. Hiçbir şeyi değiştirmeden yeniden denemenin işe yaraması pek olası değil. Vanta ekibinin nedeni bulabilmesi için Rapor gönder'i seçin.
outcome-not-started = Yükleyici zamanında başlamadı. Kurulum hiçbir değişiklik yapmadı. Yeniden deneyebilirsiniz.
outcome-lost = Yükleyici bir sonuç bildirmeden durdu ve bazı değişiklikler yapılmış olabilir. Yeniden deneyebilirsiniz. Burada duracaksanız, kapattığınız korumaları hâlâ mevcutsa Windows Güvenliği'nde yeniden açın.
outcome-lost-defender-removed = Yükleyici bir sonuç bildirmeden durdu ve bazı değişiklikler yapılmış olabilir. Yeniden deneyebilirsiniz. Yine durursa Rapor gönder'i seçin.
restart-now-message = Vanta kurulumunu tamamlamak için Windows yeniden başlatılıyor.
restart-countdown =
    { $seconds ->
        [one] Vanta kurulumunu tamamlamak için Windows { $seconds } saniye içinde yeniden başlatılacak. Önce çalışmanızı kaydetmek için Daha sonra yeniden başlat'ı seçin.
       *[other] Vanta kurulumunu tamamlamak için Windows { $seconds } saniye içinde yeniden başlatılacak. Önce çalışmanızı kaydetmek için Daha sonra yeniden başlat'ı seçin.
    }
restart-stopped = Otomatik yeniden başlatma iptal edildi. Çalışmanızı kaydedin, sonra Vanta kurulumunu tamamlamak için bilgisayarınızı yeniden başlatın.
restart-needed = Çalışmanızı kaydedin, sonra Vanta kurulumunu tamamlamak için bilgisayarınızı yeniden başlatın.
restart-dont-now = Daha sonra yeniden başlat
restart-now = Şimdi yeniden başlat
restart-start-failed = Vanta bilgisayarınızı yeniden başlatamadı. Çalışmanızı kaydedin, ardından Başlat menüsünden yeniden başlatın. Ayrıntılar: { $error }
preflight-title = Kurulum başlamadı
preflight-invalid-options = Vanta bu kurulum seçimlerini kullanamadı. Seçimleriniz adımına dönüp gözden geçirin, sonra yeniden deneyin. Ayrıntılar: { $error }
# $problems is a sentence or two built from preflight-problem and preflight-security.
preflight-changed = Bilgisayarınızın durumu önceki denetimlerden sonra değişti. Yeniden denemeden önce şunları çözün. { $problems }
preflight-problem = { $title }: { $detail }
# $summary is the Windows Security summary such as "2 tanesi hâlâ açık".
preflight-security = Windows Güvenliği: { $summary }.
preflight-busy = Başka bir Vanta penceresi kurulum başlatıyor. Biraz bekleyin, ardından Vanta'ı kur'u yeniden seçin.
# Shown with the home-start-over button.
preflight-taken-over = Başka bir Vanta penceresi bu kurulumu devraldı, bu yüzden kurulum başlamadı. O pencerede devam edin veya kurulumu burada baştan yapmak için Baştan başla'yı seçin.
preflight-record-unreadable = Vanta önceki kurulumun hâlâ sürüp sürmediğini denetleyemedi, bu yüzden yeni bir kurulum başlatmadı. Ne yapmanız gerektiğini görmek için Hazırlık adımına dönün. Ayrıntılar: { $error }
preflight-refused = Yükleyici başlatılamadı. Kurulum hiçbir değişiklik yapmadı. Yeniden denemek için Vanta'ı kur'u seçin. Bu durum devam ederse Rapor gönder'i seçin. Ayrıntılar: { $error }
# Instead of preflight-refused when retrying an installation an earlier attempt had already started applying.
preflight-refused-resumed = Yükleyici başlatılamadığı için bu deneme durdu. Önceki bir deneme değişiklik yapmaya zaten başlamıştı. Yeniden denemek için Vanta'ı kur'u seçin. Bu durum devam ederse Rapor gönder'i seçin. Ayrıntılar: { $error }
go-to-ready = Hazırlık adımına dön
go-to-options = Seçimleriniz adımına dön
# Replaces Continue on a choice opened from a Change link on the Install step, while Continue leads straight back there.
go-to-install = Kurulum adımına dön
output-problem-title = Kurulum ilerlemesi okunamadı
output-problem-message = Vanta günlüğü okuyamadı. Bu, kurulumun durduğu anlamına gelmez. Bilgisayarınızı açık tutun ve günlük dosyasını açmayı deneyin. Ayrıntılar: { $error }
install-elevate-title = Vanta'ın kurulum için izne ihtiyacı var
install-no-package-title = Önce kurulum dosyalarınızı seçin
install-no-package-message = Vanta'ı indirmek veya kayıtlı bir Vanta paketi (.vantapkg) açmak için Hazırlık adımına dönün.
# Tester build variant of install-no-package-message.
install-no-package-bundled-message = Bu uygulamayla gelen Vanta paketini hazırlamak için Hazırlık adımına dönün.
# Step 4 when step 1 is incomplete for this session (checks or Windows updates), with go-to-ready as the button.
install-not-ready-title = Önce Hazırlık adımını tamamlayın
install-not-ready-message = Vanta'ın kuruluma başlayabilmesi için önce bilgisayarınızı denetlemeyi ve Windows'u güncellemeyi bitirmesi gerekiyor.
install-security-title = Kurulumdan önce virüsten korumayı denetleyin
install-security-reading = Dört koruma anahtarı yeniden denetleniyor.
install-security-message = { $summary }. Kurulumdan önce Windows Güvenliği'ni açın ve dört anahtarın da kapalı olduğundan emin olun.
summary-try-again = Yeniden denemeden önce gözden geçirin
summary-ready = Vanta kurulumunuzu gözden geçirin
summary-activation = Etkinleştirme
summary-activation-ok = Etkin. Vanta bunu değiştirmez.
summary-activation-missing = Etkin değil. Devam edebilirsiniz, ancak Vanta Windows'u etkinleştirmez.
summary-activation-unknown = Vanta Windows etkinleştirme durumunuzu değiştirmez.
summary-duration = Tahmini süre
summary-duration-value =
    { $minutes ->
        [one] { $minutes } dakika, ardından yeniden başlatma
       *[other] { $minutes } dakika, ardından yeniden başlatma
    }
summary-restart-checkbox = Kurulumdan sonra bilgisayarımı otomatik olarak yeniden başlat
summary-show-command = Kurulum komutunu göster
summary-hide-command = Kurulum komutunu gizle
summary-copy-command-a11y = Kurulum komutunu kopyala
summary-command-unavailable = Kurulum komutu hazırlanamadı. Ayrıntılar: { $error }
summary-not-chosen = Henüz seçim yapılmadı
# Accessible name of a Change link. $title is a screen-*-title message.
summary-change-a11y = { $title } seçimini değiştir
footer-still-checking = Kuruluma hazırlanıyor
footer-fix-items = Devam etmek için Bilgisayar denetimlerindeki sorunları giderin
footer-need-package = Devam etmek için Vanta'ı indirin veya bir Vanta paketi açın
# Tester build variant of footer-need-package.
footer-need-package-bundled = Devam etmek için birlikte gelen Vanta paketini hazırlayın
footer-reading-security = Koruma anahtarları denetleniyor
footer-security-pending = Devam etmek için dört anahtarı da kapatın
footer-security-confirm = Devam etmek için Vanta'ın okuyamadığı anahtarları onaylayın
footer-install-ready = Önce çalışmanızı kaydedip uygulamalarınızı kapatın
button-install = Vanta'ı kur
log-earlier-lines =
    { $count ->
        [one] Önceki { $count } satır günlük dosyasında.
       *[other] Önceki { $count } satır günlük dosyasında.
    }
# Appended when the log is copied. $path is a file path (text).
log-full-log-note = (günlüğün tamamı: { $path })

## The installing view

installing-checking-title = Son bir denetim
installing-checking-line = Vanta değişiklik yapmadan önce bilgisayarınızı denetliyor. Bu biraz sürebilir.
installing-title = Vanta kuruluyor
installing-phase-preflight = Bilgisayarınız denetleniyor ve kurulum dosyaları hazırlanıyor.
installing-phase-staging = Kurulum dosyaları kopyalanıyor. Bilgisayarınızı açık tutun.
installing-phase-applying = Windows seçimlerinize göre ayarlanıyor. Bilgisayarınızı açık ve fişe takılı tutun.
installing-phase-done = Kurulum tamamlanıyor. Bilgisayarınızı açık tutun.
installing-installed-title = Vanta kuruldu
# $time is a formatted clock time.
installing-started-just-now = Başlangıç: { $time }, bir dakikadan kısa süre önce
installing-started-minutes =
    { $minutes ->
        [one] Başlangıç: { $time }, bir dakika önce
       *[other] Başlangıç: { $time }, { $minutes } dakika önce
    }
installing-restart-auto = Kurulum bittiğinde bilgisayarınız otomatik olarak yeniden başlar. Bundan önce diğer uygulamalardaki çalışmalarınızı kaydedin.

## The "Vanta is installed" window after the restart

installed-title-version = Vanta { $version } kuruldu
installed-title = Vanta kuruldu
installed-ready = Her şey tamam. Bilgisayarınız Vanta ile kullanıma hazır.
installed-security-message = Microsoft Defender'ı tuttunuz, ancak bazı korumaları hâlâ kapalı. Windows Güvenliği'ni açın ve şunların açık olduğundan emin olun: { $switches }.
installed-defender-removed-title = Microsoft Defender kaldırıldı
installed-defender-removed-message = Başka bir virüsten koruma uygulaması yükleyene kadar bilgisayarınızda virüsten koruma olmaz. SmartScreen de kaldırıldı, bu yüzden Windows, tanınmayan uygulamaları veya indirilen dosyaları açmadan önce sizi uyarmaz.
# Home and the "Vanta is installed" window, after an installation that kept Microsoft Defender,
# when it is missing and no Vanta package removed it. Its title is security-banner-missing-title;
# "Report a problem" is home-report-problem, its button.
installed-defender-missing-message = Microsoft Defender'ı tutmayı seçtiniz, ancak Defender bilgisayarınızda yok ve onu Vanta kaldırmadı. Başka bir virüsten koruma uygulaması kullanmıyorsanız bilgisayarınızı korumak için bir tane yükleyin. Defender'ı kendiniz kaldırmadıysanız Sorun bildir'i seçin.

## Settings

settings-title = Ayarlar
settings-theme = Uygulama teması
settings-theme-system = Windows ile aynı
settings-theme-light = Açık
settings-theme-dark = Koyu
settings-theme-contrast-note = Vanta, Windows kontrast temanızın renklerini kullanıyor.
settings-theme-mica-note = Yarı saydam arka planı görmek için Windows ile aynı açık veya koyu temayı seçin.
settings-language = Dil
settings-language-system = Windows ile aynı
settings-language-system-selected = { settings-language-system } ({ $language })
# Under "Match Windows": which language that gives. $language is a language's own name.
settings-language-system-detail = Windows ile aynı seçildiğinde: { $language }
# A short tag under each language that is translated but not yet reviewed by a native speaker.
settings-language-preview-tag = Önizleme
# Under the language list, once, explaining the Preview tag.
settings-language-preview-note = Önizleme çevirileri henüz o dili anadili olarak konuşan biri tarafından incelenmedi.
preview-notice = { $language } çevirisi bir önizlemedir ve hatalar içerebilir.
preview-notice-switch = İngilizceye geç
preview-notice-language = Dili değiştir
# $tag is a language tag (text).
settings-language-unavailable = { $tag } bu Vanta sürümünde kullanılamıyor. Şimdilik İngilizce gösteriliyor; dil seçiminiz kaydedildi.
# $languages is the Windows display-language list (text).
settings-language-windows-unmatched = Vanta, Windows görüntüleme dillerinizi ({ $languages }) henüz desteklemiyor. Şimdilik İngilizce gösteriliyor.
settings-language-windows-unavailable = Windows görüntüleme diliniz denetlenemedi. Vanta şimdilik İngilizce kullanıyor. Ayrıntılar: { $error }
# $locale is the regional format's own name, for example "Türkçe (Türkiye)".
settings-language-formats = Sayılar, tarihler ve saatler Windows bölgesel biçiminizi izler ({ $locale }).
# Instead of settings-language-formats when the regional format writes dates or times
# right to left. $locale is the format's English name, for example "Arabic (Saudi Arabia)".
settings-language-formats-numbers-only = Sayılar Windows bölgesel biçiminizi izler ({ $locale }). Vanta sağdan sola yazılan metni henüz gösteremediği için tarihler ve saatler standart bir biçimde gösterilir.
settings-language-contribute = Vanta'ın çevirisine GitHub'da katkıda bulun
settings-usage-analytics = Ziyaret edilen ekranları, ISO oluşturma işlemlerini ve kurulum sonuçlarını Vanta ile paylaş
settings-restart-label = Kurulumdan sonra bilgisayarımı otomatik olarak yeniden başlat
settings-restart-locked = Bunu kurulum bittikten sonra değiştirebilirsiniz.
settings-restart-description = Bu ayar açıkken bilgisayarınız kurulum bittikten sonra 10 saniye içinde yeniden başlar ve açık uygulamalarınız kapanır. Kurulumdan önce çalışmanızı kaydedin.
settings-help = Yardım ve geri bildirim
settings-about = Hakkında
settings-about-app = Vanta Manager
settings-about-version = Sürüm
settings-about-licence = Lisans
settings-about-licence-value = Vanta © katkıda bulunanlar, GPL-3.0
settings-about-gpl-link = GPL-3.0 lisansını oku
settings-about-based-on = Temel alınan proje
settings-about-based-on-value = AtlasOS 0.6.0 (GPL-3.0) tabanlı
settings-about-atlas-link = GitHub'da AtlasOS
settings-about-fonts = Yazı tipleri
settings-about-fonts-value = Geist ve Geist Mono (OFL-1.1, Vercel)
settings-about-fonts-link = Geist OFL-1.1 lisansı
settings-about-source = Kaynak kodu
# $version is the Vanta release version (text).
settings-about-source-value = Eksiksiz karşılık gelen kaynak kodu her sürümle birlikte Vanta-{ $version }-source.zip ve Vanta-{ $version }-third-party-sources.zip içinde sunulur.
settings-about-source-link = GitHub deposu
settings-about-releases-link = GitHub sürümleri
settings-about-network = Ağ
settings-about-network-value = Vanta yalnızca winget bildirimlerini ve sürümlerini almak için api.github.com adresini sorgular; kişisel veri göndermez.
# Link that opens the third-party licence notices.
settings-view-licences = THIRD-PARTY-NOTICES.txt dosyasını aç
# Under the links when Windows could not open the notices.
settings-licences-failed = THIRD-PARTY-NOTICES.txt açılamadı. Yeniden deneyin veya lisanslar klasöründe bulun.
settings-open-data-folder = Uygulama klasörünü aç

## Optional choices: explanations shown before selection.

consequence-disable-hibernation = Hazırda bekletme sırasında oturumunuzu kaydetmek için kullanılan disk alanını boşaltır. Hazırda bekletme ve Hızlı Başlatma kullanılamaz hale gelir.
consequence-disable-power-saving = Güç tasarrufu özelliklerini kapatır. Bilgisayarınız daha fazla güç tüketebilir, daha çok ısınabilir ve pil ömrü kısalabilir.
consequence-disable-core-isolation = Bellek bütünlüğü dahil ek bir Windows güvenlik katmanını kapatır. Bu, korumayı azaltır ve bu katmana ihtiyaç duyan uygulama veya oyunları etkileyebilir.
consequence-remove-snipping-tool = Ekran görüntüsü ve ekran kaydı almak için kullanılan Windows uygulamasını kaldırır.
consequence-uninstall-edge = Microsoft Edge tarayıcısını kaldırır. Başka bir tarayıcınız olduğundan emin olun veya aşağıdan birini seçin.
# Instead of consequence-uninstall-edge when Vanta is installed on this PC, which has the
# user's Edge data. "choose one below" refers to the browser choice under it.
consequence-uninstall-edge-data = Microsoft Edge'i kaldırır ve bu bilgisayardaki Edge yer işaretlerinizi, geçmişinizi ve kayıtlı parolalarınızı siler. Microsoft hesabınızla eşitlenmemiş olan her şey kaybolur. Başka bir tarayıcınız olduğundan emin olun veya aşağıdan birini seçin.
# Under Remove Microsoft Edge in the Install step's summary, with a caution glyph.
caution-uninstall-edge = Bu bilgisayardaki Edge yer işaretlerinizi, geçmişinizi ve kayıtlı parolalarınızı siler.
consequence-install-another-browser = Aşağıdan bir tarayıcı seçin; Vanta onu sizin için yükler.
consequence-install-toolbox = Vanta ayarlarınızı yönetmenize yardımcı olması için Vanta Toolbox'ı ekleyin. Toolbox beta aşamasında olduğu için bazı özellikler henüz tamamlanmamış olabilir.
consequence-install-eclean = Kurulumdan sonra bilgisayarınızı düzenli tutmak için Vanta ekibinden bir bakım aracı. Gereksiz dosyaları ve başlangıç uygulamalarını inceleyin. Hesap ve internet bağlantısı gerektirir.

# Introduction on the home page before Vanta is installed.
home-intro = Vanta, arka plan etkinliğini ve dikkat dağıtan öğeleri azaltmak için Windows'ta ayarlamalar yapar. Vanta'ı, kendi uygulamalarınızı ve dosyalarınızı eklemeden önce temiz bir Windows kurulumuna kurun.

## ISO creation
iso-home-title = Windows yükleme medyası
iso-home-description = Vanta içeren bir Windows kurulum dosyası (ISO) oluşturun, ardından bu dosyayla Windows'u bu bilgisayara veya başka bir bilgisayara yeniden yükleyin.
iso-open = Vanta ISO'su oluştur
iso-title = Vanta ISO'su oluştur
iso-recommended = Önerilen
iso-admin-description = Vanta'ın Windows ISO'nuzu okuyup yenisini oluşturabilmesi için yönetici izni gerekiyor. Yönetici olarak yeniden aç'ı seçin, ardından Windows sorduğunda Evet'i seçin.
iso-source = Windows ISO'su
iso-download-recommended = Microsoft’tan indir (önerilen)
iso-source-question = Windows’u nereden almak istersiniz?
iso-use-local = ISO dosyası seç
iso-package-latest-label = En güncel
iso-package-latest = En son Vanta paketi
iso-package-unavailable = Manager’ın bu sürümü için bir Vanta paketi seçin.
iso-save-name = { $name } olarak kaydet
iso-source-download = Windows 11'i Microsoft'tan indir
iso-download-arch = Mimari
iso-download-languages = Diller yükleniyor…
iso-download-list-error = Windows dilleri yüklenemedi. Tekrar deneyin veya ISO’yu Microsoft’un sitesinden indirin.
iso-download-file-error = ISO kaydedilemedi. Bağlantıyı ve boş alanı kontrol edip yeni bir dosya adıyla tekrar deneyin.
iso-download-website = Microsoft indirme sayfasını aç
iso-download-progress = Windows indiriliyor · { $received } / { $total }
iso-download-starting = Windows indirmesi hazırlanıyor…
iso-output = Yeni ISO'nun kaydedileceği konum
iso-no-file = Dosya seçilmedi
# Accessible name of the Browse or Save as button beside a file field: $action is
# that button's text and $field the field's label.
iso-pick-a11y = { $action }: { $field }
iso-inspect = Dosyaları denetle
iso-mode-title = Vanta'ı nasıl kurmak istiyorsunuz?
iso-mode-interactive = Vanta seçimlerini oturum açtıktan sonra yap
iso-mode-interactive-description = Oturum açtıktan sonra Vanta açılır ve güncellemelerde, seçimlerinizde ve Vanta'ın kurulumunda size yol gösterir.
iso-mode-before = Vanta seçimlerini şimdi yap
iso-mode-before-description = Vanta seçimlerinizi ISO'ya kaydeder. Oturum açtıktan sonra Vanta açılır ve güncellemelerde size yol gösterir, ardından Vanta'ı bu seçimlerle kurarsınız.
iso-package-unsupported-title = Daha yeni bir Vanta paketi seçin
# "Vanta seçimlerini oturum açtıktan sonra yap" is iso-mode-interactive.
iso-package-unsupported = Bu Vanta paketi, Vanta seçimlerini ISO'ya kaydedemez. Daha yeni bir paket seçin veya Vanta seçimlerini oturum açtıktan sonra yap seçeneğini belirleyin.
# Shown when Check files refuses the Vanta package; $minimum as for iso-package.
iso-failed-package-unsupported = Bu Vanta paketi ISO oluşturmak için kullanılamaz. Vanta { $minimum } veya daha yeni bir sürüme ait bir paket seçin.
# Tester build: the bundled Vanta package cannot be swapped, so the only way on is the after-sign-in mode.
iso-package-unsupported-bundled-title = Vanta seçimleri bu ISO'ya kaydedilemez
# "Vanta seçimlerini oturum açtıktan sonra yap" is iso-mode-interactive.
iso-package-unsupported-bundled = Bu uygulamayla gelen Vanta paketi ISO kurulumunu desteklemiyor. Bunun yerine Vanta seçimlerini oturum açtıktan sonra yap seçeneğini belirleyin.
iso-atlas-options = Vanta seçimleri
iso-review = ISO'yu gözden geçir
iso-review-description = ISO oluşturmak bu bilgisayara hiçbir şey kurmaz ve orijinal ISO'nuzu değiştirmez. Ardından Vanta, Windows'u yeniden yükleyebilmeniz için yeni ISO'yu bir USB sürücüsüne yazabilir.
iso-review-files = Dosyalar
iso-step-windows = Windows kurulumu
iso-step-review = İnceleme
iso-review-package = Vanta paketi
iso-review-output = Yeni ISO
iso-review-editions = Sürümler
iso-edition = Windows sürümü
iso-edition-auto = Windows kurulumu sırasında seç
iso-accept-terms = Windows için Microsoft Yazılımı Lisans Koşullarını kabul ediyorum
iso-architecture-x64 = x64
iso-architecture-arm64 = Arm64
# A file size; $size is a formatted number (text). Megabytes below a gigabyte.
size-megabytes = { $size } MB
size-gigabytes = { $size } GB
iso-review-account = Hesap adı
iso-review-target = Yükleme hedefi
iso-review-drivers = Sürücüler
iso-create = ISO oluştur
iso-progress-title = ISO'nuz oluşturuluyor
iso-stage-inspect = Windows ISO'nuz denetleniyor
iso-stage-copy = Windows dosyaları kopyalanıyor
iso-stage-add-atlas = Vanta ekleniyor
iso-stage-master = ISO dosyası yazılıyor
iso-stage-verify = Yeni ISO denetleniyor
iso-stage-cleanup = Tamamlanıyor
# Accessible name of one stage while the ISO is created. No "Step": the screen reader adds
# "4 of 6". $status is stepper-status-completed or one of the three below.
iso-stage-a11y = { $title }, { $status }
iso-stage-status-current = devam ediyor
# The stage where creating the ISO stopped with an error.
iso-stage-status-failed = başarısız oldu
iso-stage-status-not-started = henüz başlamadı
iso-progress-description = Vanta'ı açık tutun. Büyük görüntülerin işlenmesi zaman alabilir.
iso-cancel = Oluşturmayı iptal et
iso-cancelling = İptal için güvenli bir durma noktası bekleniyor
iso-cancelled = ISO oluşturma iptal edildi
iso-cancelled-description = Orijinal ISO'nuz değişmedi. Geride geçici dosyalar kaldıysa nerede olduklarını görmek için Günlük klasörünü aç'ı seçin.
iso-complete = ISO'nuz hazır
iso-complete-description = Ardından Kurulum USB’si oluştur’u seçin ve Windows’u yeniden yüklemeden önce dosyalarınızı yedekleyin.
iso-open-folder = Klasörde göster
iso-failed = ISO oluşturma tamamlanamadı
iso-failed-description = Dosyalarınızın hâlâ seçtiğiniz yerde olduğundan ve kaydettiğiniz sürücünün bağlı olduğundan emin olun, ardından ISO oluştur'u seçin. Sorun devam ederse Rapor gönder'i seçin.
# Title while the Check files step fails; the messages below say why.
iso-check-failed = Dosyalar denetlenemedi
iso-check-failed-description = ISO'nun ve Vanta paketinin hâlâ seçtiğiniz yerde olduğundan ve indirilmelerinin bittiğinden emin olun, ardından Dosyaları denetle'yi seçin. Sorun devam ederse Rapor gönder'i seçin.
# Title of the bar that asks for administrator permission. Its message is iso-admin-description,
# or elevation-declined after Windows refused the relaunch (UAC declined).
iso-elevation-title = Vanta'ın ISO oluşturmak için izne ihtiyacı var
# Typed reasons reported by the image worker.
iso-failed-output-exists = Bu adda bir dosya zaten var. Farklı kaydet'i seçip yeni bir dosya adı girin.
iso-failed-destination = Vanta yeni ISO'yu oraya kaydedemiyor. Farklı kaydet'i seçin ve bu bilgisayarda İndirilenler gibi bir klasör seçin. Ağ konumları ve birçok USB sürücüsü gibi FAT32 ya da exFAT olarak biçimlendirilmiş sürücüler kullanılamaz.
iso-failed-space = Hedef sürücüde yeterli boş alan yok. Alan boşaltın veya yeni ISO'yu başka bir sürücüye kaydedin.
# Home and LTSC are the editions ISO creation drops; the others are examples it keeps.
iso-failed-edition = Bu ISO desteklenen bir Windows sürümü içermiyor. Windows Home ve LTSC desteklenmez. Pro, Education veya Enterprise gibi başka bir sürüm içeren bir ISO kullanın.
iso-failed-customised = Bu ISO zaten autounattend.xml gibi özel kurulum dosyaları içeriyor. Microsoft'tan alınmış, değiştirilmemiş bir Windows ISO'su seçin.
iso-failed-windows-unsupported = Bu Windows görüntüsü Vanta paketi tarafından desteklenmiyor. Bu paketin desteklediği bir Windows 11 sürümünün değiştirilmemiş, 64 bit ISO’sunu kullanın.
iso-failed-network-architecture = Bu bilgisayarın ağ sürücüleri bu ISO'nun mimarisiyle eşleşmiyor. Geri dönüp Bu bilgisayarın ağ sürücülerini ekle seçeneğini kapatın veya bu bilgisayar için bir ISO seçin.
iso-failed-unstaged = Vanta çalışma klasörünü hazırlayamadı, bu yüzden hiçbir şey değiştirilmedi. Yeniden deneyin. Sorun devam ederse hata raporu için Tanılama verilerini dışa aktar’ı seçin.
iso-failed-package-changed = Dosyalar denetlendikten sonra Vanta paketi değişti. Dosyalar’ın yanındaki Değiştir’i, ardından Dosyaları denetle’yi seçin.
iso-diagnostics = Günlük klasörünü aç
iso-close-title = ISO oluşturma devam ediyor
iso-close-message = Oluşturma veya iptal işlemi bitene kadar bu pencereyi açık tutun. İptal işlemi, mevcut işlemin güvenle durdurulabileceği noktayı bekler.
# On the ISO and USB pages while Vanta updates Windows, or puts back Windows Update settings,
# from another page. Their controls are unavailable until it finishes.
iso-locked = Vanta şu anda Windows Update ile meşgul. Bu iş bittiğinde buradan devam edebilirsiniz.
# Card title. Turkish uses a noun phrase so that other messages can name the card
# ("Windows ve Store güncellemeleri kartında"); an imperative title reads as an instruction there.
prepare-title = Windows ve Store güncellemeleri
prepare-description = Vanta, kurulumdan önce Windows’u, Microsoft Store’u ve Store uygulamalarınızı günceller. Not Defteri, Paint veya Windows Terminal gibi açık Store uygulamaları güncellenirken kapanabilir; bu yüzden önce bu uygulamalardaki çalışmanızı kaydedin. Bilgisayarınızın yeniden başlatılması da gerekebilir.
prepare-complete = Vanta, yüklenecek başka Windows veya Store güncellemesi bulmadı.
prepare-reboot-title = Devam etmek için bilgisayarınızı yeniden başlatın
prepare-reboot = Güncellemelerin yüklenmesini tamamlamak için bilgisayarınızın yeniden başlatılması gerekiyor. Vanta şimdiye kadarki seçimlerinizi kaydeder ve oturum açtıktan sonra yeniden açılır.
# $reasons: the pending-restart markers Windows set, from the prepare-reason-* names.
prepare-reboot-reasons = Güncellemelerin yüklenmesini tamamlamak için bilgisayarınızın yeniden başlatılması gerekiyor ({ $reasons }). Vanta şimdiye kadarki seçimlerinizi kaydeder ve oturum açtıktan sonra yeniden açılır.
# Under the restart message: the button restarts Windows without a countdown.
prepare-reboot-save-work = Önce çalışmanızı kaydedin ve uygulamalarınızı kapatın. Yeniden başlat ve devam et’i seçtiğiniz anda bilgisayarınız yeniden başlar.
# Shown instead of another restart when Windows asks for one again right after restarting.
prepare-restart-persists = Bilgisayarınız yeniden başladı, ancak Windows hâlâ yeniden başlatılması gerektiğini bildiriyor ({ $reasons }); bu yüzden yeniden başlatmak büyük olasılıkla işe yaramaz. Windows Update'i aç'ı seçin ve orada bekleyenleri tamamlayın, ardından Yeniden dene'yi seçin. Bekleyen bir şey yoksa Rapor gönder'i seçin.
# Names of the markers Windows sets when it wants a restart. They complete
# "Güncellemelerin yüklenmesini tamamlamak için bilgisayarınızın yeniden başlatılması gerekiyor (…)";
# keep them short and lower case where the language allows.
prepare-reason-servicing = Windows bileşen bakımı
prepare-reason-windows-update = Windows Update
prepare-reason-file-renames = değiştirilmeyi bekleyen dosyalar
prepare-reason-update-agent = Windows Update hizmeti
prepare-reason-unknown = neden bildirilmedi
prepare-failed = Yeniden dene’yi seçin. Yine başarısız olursa kalan güncellemeleri Windows Update’te veya Microsoft Store’da tamamlayın ya da Rapor gönder’i seçin.
prepare-failed-title = Bazı güncellemeler tamamlanamadı
# The update run ended without writing any result, for example after Vanta was closed
# while it ran. "Yeniden dene" is common-try-again, the button beside it.
prepare-ended-unconfirmed = Güncelleme bir sonuç bildirmeden durdu, bu yüzden Vanta, Windows ve Store uygulamalarının güncel olduğunu doğrulayamıyor. Güncellemeleri denetlemek için Yeniden dene’yi seçin.
prepare-unconfirmed-title = Güncelleme sonucu doğrulanamadı
# "Güncellemeleri denetle ve yükle" is prepare-start, its button in this state.
prepare-cancelled = Güncelleme durdu. Bazı güncellemeler yüklenmiş olabilir. Devam etmeden önce güncellemeyi bitirmek için Güncellemeleri denetle ve yükle’yi seçin.
prepare-windows-search = Windows güncellemeleri denetleniyor…
prepare-windows-download = Windows güncellemeleri indiriliyor…
prepare-windows-install = Windows güncellemeleri yükleniyor…
prepare-windows-repair = Önce Windows onarılıyor, çünkü Windows güncelleştirmelerin yüklenmesini engelleyebilecek bir hasar bildiriyor. Bu yarım saat veya daha uzun sürebilir.
prepare-store-search = Microsoft Store denetleniyor…
prepare-store-install = Microsoft Store ve uygulamaları güncelleniyor…
prepare-stop-description = Vanta, geçerli adım bittikten sonra durur. O zamana kadar Vanta’ı açık tutun.
prepare-stop = Güncellemeyi durdur
prepare-restart = Yeniden başlat ve devam et
prepare-start = Güncellemeleri denetle ve yükle
# Under the update button while it is unavailable because this installation can't continue.
prepare-blocked-source = Bu kurulum devam edemediği için kullanılamıyor. Sayfanın üst kısmındaki iletiye bakın.
# Under the update button while it is unavailable. $check is the title of the check
# that must pass first: check-supported-build or check-administrator.
prepare-needs-build-check = Bilgisayar denetimlerinde { $check } denetimi geçtiğinde kullanılabilir.
# Under the preparation button, and under the Administrator check, while the installation files are still downloading or unpacking.
prepare-wait-for-package = Kurulum dosyaları hazır olduğunda kullanılabilir.
iso-username = Yerel hesap adı
iso-account-description = Windows kurulumu bu adla yerel bir hesap oluşturur, böylece Microsoft hesabına ihtiyacınız olmaz. Windows, ilk kez oturum açtığınızda bir parola belirlemenizi ister.
iso-username-placeholder = Adınız
iso-account-empty = Devam etmek için bir yerel hesap adı girin
iso-account-invalid = En fazla 20 karakter kullanın. Başta veya sonda boşluk olmamalı ve şunların hiçbiri bulunmamalı: " / \ [ ] : ; | = , + * ? < > @
iso-account-trailing-dot = Ad nokta ile bitemez.
iso-account-reserved = Windows bu adı yerleşik bir hesap için kullanıyor. Başka bir ad seçin.
iso-terms-in-setup = Windows Kurulumu lisans koşullarını kabul etmenizi isteyecek.
iso-privacy-defaults = Bu ISO, Windows kurulumundaki Microsoft hesabı ve gizlilik ekranlarını atlar; isteğe bağlı veri paylaşımını ve kişiselleştirilmiş teklifleri kapatır.
prepare-drivers = Sürücüler nasıl yüklensin?
prepare-drivers-auto = Sürücüleri Windows Update’ten al
prepare-drivers-auto-detail = Windows, donanımınız için sürücüleri bulur. Çoğu bilgisayar için önerilir.
prepare-drivers-manual = Sürücüleri kendim yükleyeceğim
prepare-drivers-manual-detail = Windows Update sürücü yüklemez; bu yüzden sürücüleri bilgisayarınızın veya cihazınızın üreticisinden edinmeniz gerekir. Yüklü sürücüler korunur.
prepare-drivers-description = Sürücüler, Windows’un grafik, ses ve Wi-Fi gibi donanımlarınızı kullanmasını sağlar. Güncellemeden sonra bunu değiştirirseniz Vanta’ın güncellemeleri yeniden denetlemesi gerekir.
prepare-network-needed = Güncellemeler için tarifeli olmayan bir internet bağlantısı gerekir. Wi-Fi’ye veya Ethernet’e bağlanın, ardından Yeniden dene’yi seçin. Hiç Wi-Fi ağı görmüyorsanız önce ağ sürücünüzü yükleyin.
# Connected, but Windows found no internet access (a captive portal, or DNS or firewall filtering).
prepare-network-limited = Windows, bu ağın internet erişimi olmadığını bildiriyor. Ağ sizden oturum açmanızı isterse oturum açın veya yönlendiricinizi ve varsa DNS ya da güvenlik duvarı filtrelemesini denetleyin, ardından tekrar deneyin.
# "Tarifeli bağlantı" is the switch's name in Windows network settings.
prepare-network-metered = Bu bağlantı tarifeli veya bir veri sınırına sahip. Tarifeli olmayan bir ağa bağlanın veya ağ ayarlarında Tarifeli bağlantı seçeneğini kapatın, ardından tekrar deneyin.
prepare-network-settings = Ağ ayarlarını aç
iso-target-title = Windows’u hangi bilgisayara yeniden yükleyeceksiniz?
iso-target-this = Bu bilgisayara
# Under This PC (iso-target-this), before it's chosen.
iso-target-this-description = Vanta, bu bilgisayarın Wi-Fi ve Ethernet sürücülerini ISO’ya ekleyebilir; böylece Windows yeniden yüklendikten hemen sonra internete bağlanabilir.
iso-target-other = Başka bir bilgisayara
iso-copy-network = Bu bilgisayarın ağ sürücülerini ekle
iso-network-detail = Windows kurulumu sırasında bu bilgisayarın Wi-Fi ve Ethernet sürücülerini kullanır. Kurulumdan sonra Wi-Fi’ye yeniden bağlanmanız gerekir.
iso-network-source = Ağ sürücüsü kaynağı
iso-network-installed = Yüklü sürücüleri kullan
iso-network-updated = Önce Windows Update’i denetle
iso-network-updated-detail = Windows Update’in sunduğu uygun sürücüleri indirir ve yüklü sürücüleri yedek olarak saklar. Tarifeli olmayan bir bağlantı gerekir.
iso-stage-network-drivers = Ağ sürücüleri hazırlanıyor
iso-network-failed = Ağ sürücüleri hazırlanamadı. Tanılama verilerini denetleyin veya geri dönüp ağ sürücüsü seçeneğini değiştirin.
# Under iso-complete when Include this PC's network drivers was chosen but the adapters use
# drivers that come with Windows, so none were added.
iso-network-inbox = Bu bilgisayarın ağ bağdaştırıcıları Windows ile birlikte gelen sürücüleri kullanıyor, bu yüzden ISO’nun bunları içermesi gerekmiyor.
iso-mode-desktop = Masaüstünden önce kurulumu tamamla
iso-mode-desktop-description = Vanta seçimlerinizi ISO’ya kaydeder. Oturum açtıktan sonra Vanta, Windows masaüstü açılmadan önce güncellemeleri ve kurulumu tamamlar.
desktop-setup-description = Bilgisayarınızın kurulumunu tamamlayın. Vanta seçimleriniz kaydedildi; gerekirse Windows’a dönebilirsiniz.
desktop-setup-exit = Windows’ta devam et

# Windows installation USB
usb-title = Kurulum USB’si oluştur
usb-existing = Mevcut bir ISO’dan USB oluştur
usb-description = Windows’u yeniden yükleyebilmeniz için bir ISO’yu USB sürücüsüne yazın. Vanta’ı aynı anda kurmak için Vanta ile oluşturulmuş bir ISO kullanın.
# Button that opens the file picker for an ISO, and the Open button of that picker, on the USB
# and ISO pages.
usb-choose-iso = ISO seç
usb-drive = USB sürücüsü
# $min and $max are formatted numbers (text), in gigabytes and terabytes.
usb-empty = USB sürücüsü bulunamadı. En az { $min } GB boyutunda bir USB sürücüsü bağlayın, ardından Yenile’yi seçin. { $max } TB üzerindeki sürücüler, salt okunur sürücüler ve Windows’un çalıştığı sürücü gösterilmez.
usb-refresh = Yenile
# Shown when the drive list could not be read.
usb-scan-failed = Sürücünün bağlı olduğundan emin olun, ardından Yenile’yi seçin. Ayrıntılar için Günlük klasörünü aç’ı seçin.
usb-scan-failed-title = USB sürücüleri listelenemedi
# Parts of a drive's detail line, joined by usb-detail-separator; empty parts are left out.
# $size is a formatted number of gigabytes (text); $volumes and $serial are text.
usb-drive-size = { $size } GB
usb-drive-serial = Seri numarası: { $serial }
usb-detail-separator = { " · " }
usb-review = USB’yi gözden geçir
usb-erase-title = Bu USB sürücüsü silinsin mi?
usb-erase-description = { $drive } ({ $size } GB) üzerindeki tüm dosyalar ve bölümler dahil her şey kalıcı olarak silinecek. Saklamak istediğiniz her şeyi önce başka bir sürücüye kopyalayın. ISO dosyanız silinmeyecek.
usb-layout = Vanta sürücüde en fazla 32 GB alan kullanır ve kalan alanı kullanmaz. USB sürücüsü, Windows 11’in gerektirdiği UEFI modunda başlayan bilgisayarlarda çalışır.
usb-ack = Bu USB sürücüsündeki her şeyin silineceğini anlıyorum
usb-write = Sil ve USB oluştur
usb-stage-prepare = Kurulum dosyaları hazırlanıyor…
usb-stage-format = USB biçimlendiriliyor…
usb-stage-copy = Kurulum dosyaları kopyalanıyor…
usb-stage-verify = USB doğrulanıyor…
usb-working = Vanta’ı açık, USB sürücüsünü bağlı tutun. İptal ederseniz tamamlanmamış bir USB sürücüsüyle Windows yüklenemez.
# Titles of the error bar, the success bar and the close prompt while a USB is being written.
usb-failed-title = USB oluşturma tamamlanamadı
usb-complete-title = USB’niz hazır
usb-close-title = USB oluşturma devam ediyor
# After erasing may have begun.
usb-failed = Sürücü zaten silinmiş olabilir, bu yüzden henüz Windows yüklemek için kullanılamaz. Sürücünün bağlı olduğundan emin olun, ardından yeniden denemek için USB’yi gözden geçir’i seçin. Sürücüyü yeniden bağladıysanız önce Yenile’yi seçip sürücüyü yeniden seçin.
# Before anything on the drive was changed: in general, then for the reasons the writer reports.
usb-failed-unchanged = USB sürücünüz değiştirilmedi. Neyin başarısız olduğunu görmek için Günlük klasörünü aç’ı seçin, ardından yeniden denemek için USB’yi gözden geçir’i seçin.
usb-failed-iso = Bu ISO ile kurulum USB’si oluşturulamaz. Vanta ile oluşturulmuş bir ISO veya Microsoft’tan alınmış, Vanta’ın desteklediği bir sürüme ait Windows 11 ISO’su seçin. USB sürücünüz değiştirilmedi.
usb-failed-location = ISO dosyası veya Vanta Manager bu USB sürücüsünde, bir ağ konumunda ya da bağlantılı bir klasörde. Dosyayı bu bilgisayardaki yerel bir klasöre taşıyın, ardından yeniden deneyin. USB sürücünüz değiştirilmedi.
usb-failed-space = Windows sürücüsünde kurulum dosyalarını hazırlamak için yeterli boş alan yok. Alan boşaltın, ardından yeniden deneyin. USB sürücünüz değiştirilmedi.
usb-failed-fit = Kurulum dosyaları bu USB sürücüsüne sığmıyor. Daha büyük bir sürücü kullanın, ardından yeniden deneyin. USB sürücünüz değiştirilmedi.
usb-failed-drive-changed = USB sürücüsü, liste okunduktan sonra çıkarıldı, yeniden bağlandı veya yerine başka bir sürücü takıldı. Yenile’yi seçin, sürücüyü yeniden seçin, ardından USB’yi gözden geçir’i seçin. USB sürücünüz değiştirilmedi.
usb-cancelled = Sürücüde eksik kurulum dosyaları bulunabilir. Windows yüklemeden önce USB’yi yeniden oluşturun.
usb-cancelled-title = USB oluşturma iptal edildi
usb-cancelled-unchanged = USB sürücünüz değiştirilmedi.
usb-complete = Vanta her dosyayı denetledi. USB’yi çıkar’ı seçin, ardından Windows’u yeniden yükleyeceğiniz bilgisayardaki dosyaları yedekleyin. Sürücüyü o bilgisayara takın, ardından bilgisayarı önyükleme menüsünü kullanarak USB sürücüsünden başlatın (bilgisayar açılırken genellikle F12, F11 veya Esc).
usb-eject = USB’yi çıkar
usb-ejected = USB sürücüsünü artık çıkarabilirsiniz. Windows’u yeniden yükleyeceğiniz bilgisayardaki dosyaları yedekleyin. Ardından o bilgisayarı önyükleme menüsünü kullanarak USB sürücüsünden başlatın (açılırken genellikle F12, F11 veya Esc).
usb-eject-failed = Sürücüyü kullanan dosyaları veya pencereleri kapatıp yeniden deneyin.
usb-eject-failed-title = USB çıkarılamadı
ready-fresh-title = Vanta, temiz bir Windows kurulumu için tasarlandı
ready-fresh-description = Bu bilgisayarda Windows’u zaten kullanıyorsanız devam etmeden önce dosyalarınızı yedekleyin ve Windows’u yeniden yükleyin. Desteklenen bir sürümü yeniden yüklemek için önce Bilgisayar denetimlerinde Windows uyumluluğu denetiminin geçtiğinden emin olun.
# Home, LTSC and Server are the editions the check refuses; the others are examples of
# editions it accepts. Keep edition names as Windows shows them.
detail-edition-unsupported = Windows 11 Home, LTSC ve Server sürümleri desteklenmez. Pro, Education veya Enterprise gibi başka bir sürüm kullanın. Windows sürümünüzü belirleyemediyse devam etmeden önce bu sorunu çözün.
install-source-title = Kurulum kullanılamıyor
install-source-unsupported = Vanta { $source }, doğrudan { $target } sürümüne güncellenemez. Bu sürümü kullanmak için dosyalarınızı yedekleyin ve Windows'u yeniden yükleyin.
# Before a package is chosen, so the version on offer isn't known yet.
install-source-unsupported-any = Vanta { $source } doğrudan güncellenemez. Daha yeni bir sürümü kullanmak için dosyalarınızı yedekleyin ve Windows'u yeniden yükleyin.
# "Paket dosyası aç" is package-open-file. $folder is a folder path (text).
install-source-resume = Vanta { $target } kurulumu yarım kaldı ve bu kurulumu yalnızca Vanta { $target } paketi tamamlayabilir. Paket dosyası aç'ı seçip o Vanta paketini (.vantapkg) seçin. Dosyayı Vanta indirdiyse { $folder } klasöründedir.
# Tester build: only the bundled Vanta package can be installed.
install-source-resume-bundled = Vanta { $target } kurulumu yarım kaldı. Bu test sürümü yalnızca birlikte gelen Vanta paketini kurabilir, bu yüzden bu kurulumu Vanta Manager'ın bir yayın sürümünde Vanta { $target } paketiyle tamamlayın.
install-source-unknown = Vanta bu bilgisayarda neyin kurulu olduğunu doğrulayamadı, bu yüzden şimdilik hiçbir şey kurmayacak. Vanta ekibinin yardımcı olabilmesi için Rapor gönder'i seçin.
# $problem is one of the install-source-* messages; $error is a raw error message (text).
install-source-details = { $problem } Ayrıntılar: { $error }
iso-edition-selection = Yalnızca desteklenen sürümler dahil edilir. Windows kurulumu sırasında Windows lisansınızın bulunduğu sürümü seçin.
detail-windows-preview = Insider derlemeleri desteklenmiyor. Windows 11’in genel kullanıma sunulan bir sürümünü kullanın.
detail-windows-release-unknown = Vanta, bu Windows derlemesinin genel kullanıma sunulduğunu doğrulayamadı. İnternete bağlanıp yeniden denetleyin.
# $build is this PC's Windows build and update number, such as 26300.9807 (text).
detail-windows-release-unlisted = { $build } derlemesi, Microsoft’un genel kullanıma sunulan Windows 11 sürümleri listesinde yer almıyor; bu nedenle Vanta henüz bu derlemeye kurulamaz. Release Preview derlemeleri ve diğer önizleme derlemeleri desteklenmiyor. Microsoft bu derlemeyi listeye eklediğinde Yeniden denetle’yi seçin.
iso-release-unknown = Vanta, bu ISO’nun Vanta paketinin desteklediği ve genel kullanıma sunulmuş bir Windows 11 sürümü olduğunu doğrulayamadı. İnternete bağlanın, ardından Dosyaları denetle’yi yeniden seçin. Sorun devam ederse ISO’yu Microsoft’tan yeniden indirin.
iso-release-unlisted = Bu ISO’daki Windows 11 derlemesi, Microsoft’un genel kullanıma sunulan sürümler listesinde yer almıyor. Release Preview derlemeleri ve diğer önizleme derlemeleri desteklenmiyor. ISO’yu Microsoft’tan indirin ya da Microsoft bu derlemeyi listeye eklediğinde Dosyaları denetle’yi yeniden seçin.
prepare-previous-worker = Daha önce başlayan güncellemeler hâlâ sürüyor. Vanta bunların bitmesini bekleyecek, ardından güncellemeleri yeniden denetleyebilirsiniz.

ready-used-windows-title = Bu bilgisayardaki Windows kullanılmış görünüyor
ready-used-windows-description = Bu bilgisayardaki Windows en az bir hafta önce yüklenmiş veya zaten birkaç uygulama içeriyor. Vanta’ı buraya kurmak desteklenmez ve kesinlikle önerilmez: mevcut uygulamalarınız ve ayarlarınız beklendiği gibi çalışmayabilir; ayrıca Vanta OneDrive’ı kaldırır, bu yüzden OneDrive’daki dosyaların eşitlenmesi durur ve Masaüstü, Belgeler ve Resimler klasörleriniz boş görünebilir. Önce dosyalarınızı yedekleyip Windows’u yeniden yükleyin veya yalnızca riski kabul ediyorsanız devam edin.
ready-used-windows-dismiss = Yine de devam et

prepare-resumed = Bilgisayarınız yeniden başladı ve Vanta şimdiye kadarki seçimlerinizi geri yükledi. Vanta’ı kurmadan önce güncellemeyi bitirmek için Güncellemelere devam et’i seçin.
prepare-continue = Güncellemelere devam et
prepare-saving-restart = Seçimleriniz kaydediliyor ve Windows yeniden başlatıldıktan sonra Vanta’ın açılması ayarlanıyor…
prepare-restart-save-failed = Seçimleriniz kaydedilemedi. Yeniden başlatmadan önce tekrar deneyin.
prepare-restart-registration-failed = Seçimleriniz kaydedildi, ancak Vanta yeniden başlatmadan sonra kendini açılacak şekilde ayarlayamadı. Tekrar deneyin veya bilgisayarınızı kendiniz yeniden başlatıp oturum açtıktan sonra Vanta’ı açın.
prepare-restart-source-linked = Seçimleriniz kaydedildi, ancak Vanta Manager bağlantılı bir klasördeyken Vanta yeniden başlatmadan sonra kendini açılacak şekilde ayarlayamaz. Vanta’ı kapatın ve Vanta Manager’ı bu bilgisayardaki yerel bir klasöre taşıyın. Ardından oradan açın veya bilgisayarınızı kendiniz yeniden başlatıp oturum açtıktan sonra oradan açın.
prepare-restart-failed = Vanta bilgisayarınızı yeniden başlatamadı. Tekrar deneyin veya Başlat menüsünden yeniden başlatın. Seçimleriniz kaydedildi ve Vanta, oturum açtıktan sonra yeniden açılır.
diagnostics-export = Tanılama verilerini dışa aktar
diagnostics-exporting = Tanılama verileri toplanıyor…
diagnostics-privacy = Vanta ekibine özel olarak rapor gönderin veya yardım isterken paylaşmak için bir tanılama ZIP dosyası dışa aktarın. Vanta bu dosyadan kullanıcı adınızı, bilgisayar adınızı ve e-posta adreslerini kaldırır.
# Title of the result bar after an export; its button is iso-open-folder.
diagnostics-saved = Tanılama ZIP dosyası oluşturuldu
diagnostics-failed-title = Tanılama verileri dışa aktarılamadı
# $error is the raw error (text).
diagnostics-failed = Bilgisayarınızda yeterli boş disk alanı olduğundan emin olun, ardından yeniden deneyin. Ayrıntılar: { $error }

## Tester builds (embedded-package feature)

# One line of chrome under the title bar on a release-candidate build.
rc-banner = Vanta { $release } test sürümü. Bu uygulama yalnızca birlikte gelen Vanta paketini kurar.
home-status-bundled = Test sürümü { $release }
home-status-ready = Kuruluma hazır
package-bundled = Bu uygulamayla gelen Vanta { $version } kuruluma hazır.
rc-about-release = Test sürümü
rc-about-commit = Kaynak commit
rc-about-package = Birlikte gelen Vanta paketi (SHA-256)
iso-package-bundled = Bu uygulamayla gelen Vanta paketi
prepare-percent = Bu aşamanın %{ $percent } kadarı
prepare-count = Tamamlanan güncellemeler: { $completed } / { $total }
prepare-bytes = Yaklaşık { $total } MB verinin { $downloaded } MB kadarı indirildi
prepare-elapsed = Geçen süre: { $minutes } dk { $seconds } sn
prepare-progress-waiting = Güncelleme hizmeti bekleniyor. Bu adım için yüzde bilgisi mevcut değil.
prepare-progress-unchanged = { $minutes } dk boyunca ilerleme olmadı. Büyük güncellemeler zaman alabilir, bu yüzden Vanta’ı açık tutun. Ayrıntılar için Günlük klasörünü aç’ı seçin.
prepare-report-delayed = Windows { $seconds } sn boyunca ilerleme bildirmedi. Güncellemeler hâlâ sürüyor olabilir, bu yüzden Vanta’ı açık tutun.

prepare-affected-app = etkilenen uygulamayı
prepare-app-in-use = Önce { $app } ve pencerelerini kapatın, ardından tekrar deneyin. Uygulama açıkken Windows onu güncelleyemez. Penceresini bulamıyorsanız uygulamayı Görev Yöneticisi’nden kapatın. Yine başarısız olursa bilgisayarınızı yeniden başlatın ve uygulamayı açmadan önce tekrar deneyin.
prepare-install-busy = Başka bir kurulum veya gerekli bir yeniden başlatma güncellemeleri engelliyor. Diğer kurulumların bitmesini bekleyin, Windows isterse bilgisayarınızı yeniden başlatın, ardından tekrar deneyin.
prepare-failed-component-store = Windows, bileşen deposunda güncelleştirmelerin yüklenmesini engelleyen bir hasar bildiriyor ve Vanta bunu onaramadı. Bilgisayarınızı yeniden başlatın, ardından Yeniden dene'yi seçin. Güncelleştirmeler yine başarısız olursa dosyalarınızı yedekleyin ve Windows'u bir Vanta ISO'suyla yeniden yükleyin.
prepare-failed-component-store-unrepairable = Windows, bileşen deposunda onaramadığı bir hasar bildiriyor, bu yüzden güncelleştirmeleri yükleyemiyor. Dosyalarınızı yedekleyin, ardından Windows'u bir Vanta ISO'suyla yeniden yükleyin.
# Causes the update worker names. The worker's own English message is shown below as a detail.
prepare-failed-session-owner = Vanta, Windows’ta oturum açmış hesaptan farklı bir hesapla çalışıyor. Windows’ta bir yönetici hesabıyla oturum açın, Vanta’ı o hesaptan açın ve tekrar deneyin.
prepare-failed-store-missing = Microsoft Store hesabınız için ayarlanmamış. Microsoft Store’u bir kez açın veya eksikse yeniden yükleyin, ardından tekrar deneyin.
prepare-failed-store-battery = Microsoft Store, pil tasarrufu için güncellemeleri duraklattı. Bilgisayarınızı fişe takın, ardından tekrar deneyin.
prepare-failed-store-network = Microsoft Store, bilgisayarınız tarifeli olmayan bir bağlantı kullanana kadar güncellemeleri duraklattı. Tarifeli olmayan bir Wi-Fi veya Ethernet ağına bağlanın, ardından tekrar deneyin.
prepare-failed-store-timeout = Store uygulamalarının güncellenmesi tamamlanmadı. Kalan indirmeleri Microsoft Store’da tamamlayın, ardından tekrar deneyin.
prepare-failed-store-passes = Microsoft Store yeni güncellemeler sunmaya devam etti. Kalan güncellemeleri Microsoft Store’da tamamlayın, ardından tekrar deneyin.
prepare-failed-manual-updates = Bazı Windows güncellemelerinin Windows Update’te tamamlanması gerekiyor. Windows Update’i açıp bunları tamamlayın, ardından tekrar deneyin.
prepare-failed-windows-passes = Windows Update yeni güncellemeler sunmaya devam etti. Kalan güncellemeleri Windows Update’te tamamlayın, ardından tekrar deneyin.
prepare-failed-source-linked = Vanta Manager bağlantılı bir klasörde. Vanta’ı kapatın, Vanta Manager’ı bu bilgisayardaki yerel bir klasöre taşıyın, ardından oradan açın.
prepare-error-code = Hata kodu: { $code }
prepare-open-store = Microsoft Store’u aç

check-user-account = Kullanıcı hesabı
detail-user-account-ok = UAC açık ve hesabınız kuruluma hazır.
detail-user-account-not-ready = Kullanıcı Hesabı Denetimi’ni (UAC) açın, bilgisayarınızı yeniden başlatın ve tekrar deneyin. Yerleşik Administrator hesabını kullanıyorsanız başka bir yönetici hesabıyla oturum açın.
detail-user-account-work-or-school = Vanta, iş veya okul hesabından (Microsoft Entra ID) kurulamaz. Yerel bir hesapla veya Microsoft hesabıyla oturum açın, ardından tekrar deneyin.
detail-user-account-unknown = Vanta kullanıcı hesabınızı denetleyemedi. Bilgisayarınızı yeniden başlatın, ardından Vanta'ı yeniden açıp yeniden denetleyin. Bu durum devam ederse Rapor gönder'i seçin. Windows bildirimi: { $error }

footer-prepare-required = Devam etmek için Windows ve Store uygulamalarını güncellemeyi bitirin
footer-prepare-stopping = Güncellemeler geçerli adımdan sonra durduruluyor…
resume-choices-title = Önceki kurulumunuza devam ediliyor
resume-choices-detail = Vanta, o kurulumu tamamlamak için geçen sefer yaptığınız seçimleri geri yükledi. Kurulum bitene kadar bunları Seçimleriniz adımında değiştiremezsiniz.

## Voluntary reports
report-title = Rapor gönder
report-received = Rapor alındı
report-reference = Bu rapor hakkında Vanta ekibiyle iletişime geçerseniz kullanmak için bu referansı saklayın. İletişim bilgisi bıraktıysanız ekip size yanıt vermek için bu bilgileri kullanabilir, ancak yanıt verileceği garanti edilmez.
# Accessible name of the Copy button beside the report reference.
report-copy-reference = Rapor referansını kopyala
report-another = Başka bir rapor gönder
# Label of the choice between the two kinds of report.
report-kind = Ne göndermek istiyorsunuz?
report-kind-issue = Bir sorun
report-kind-suggestion = Bir öneri
# $min and $max are numbers: the message lengths the report service accepts.
report-intro = Ne olduğunu veya neyin değişmesini istediğinizi açıklayın ({ $min }–{ $max } karakter). Mesajınıza parola yazmayın.
report-message = Mesajınız
report-message-placeholder = Şunu yapmaya çalışıyordum…
report-contact = İletişim bilgileri (isteğe bağlı)
report-contact-placeholder = E-posta veya Discord kullanıcı adı
report-attach = Tanılama verilerini ekle
report-attach-description = Sorunun nedenini bulmaya yardımcı olan günlükler ve sistem ayrıntıları. Vanta kullanıcı adınızı, bilgisayar adınızı, e-posta adreslerini ve bilinen parolaları veya anahtarları kaldırır. Hata ayrıntıları, donanım modelleri ve uygulama adları kaldırılmaz. Göndermeden önce ZIP’i inceleyebilirsiniz.
report-prepare = Tanılama verilerini hazırla
report-review = ZIP’i incele
report-prepare-failed-title = Tanılama verileri hazırlanamadı
# $error is a raw error message (text).
report-prepare-failed = Tanılama verilerini yeniden hazırlayın veya raporunuzu tanılama verileri olmadan göndermek için Tanılama verilerini ekle seçeneğini kapatın. Ayrıntılar: { $error }
report-privacy = Vanta Manager does not send reports: nothing leaves this PC. Your message and diagnostics stay here.
report-consent = Bu raporu ve varsa eklenen tanılama verilerini Vanta ekibine göndermeyi kabul ediyorum
report-failed = Mesajınız hâlâ burada. İnternet bağlantınızı denetleyin, ardından Yeniden dene’yi seçin veya raporunuzu rapor sitesinden gönderin.
report-failed-busy = Rapor hizmeti meşgul. Mesajınız hâlâ burada. Daha sonra tekrar deneyin.
report-failed-outdated = Vanta Manager’ın bu sürümü artık rapor gönderemiyor. Mesajınız hâlâ burada: kopyalayıp rapor sitesine yapıştırın. Tanılama verilerini eklediyseniz ZIP’i incele’yi seçin ve ZIP’i de oraya ekleyin.
report-failed-diagnostics = Hazırlanan tanılama verileri gönderilemiyor. Mesajınız hâlâ burada. Tanılama verilerini yeniden hazırlayın veya Tanılama verilerini ekle seçeneğini kapatın.
# Link under a report that wasn't sent.
report-sending = Gönderiliyor…
report-send = Rapor gönder

# $min and $max are numbers: the message lengths the report service accepts.
report-validation-message = { $min }–{ $max } karakter girin.

# $max is a number: the longest contact details the report service accepts.
report-validation-contact = İletişim bilgilerini { $max } karakterle sınırlayın.

report-validation-consent = Bu raporu göndermeyi kabul ettiğinizi onaylayın.

report-failed-title = Rapor gönderilmedi

## Windows version update
home-plan-intro = Bu güncelleştirme iki bölümden oluşur. Dosyalarınız ve uygulamalarınız korunur. Windows'u güncelleştirmek Vanta'ın değişikliklerinden bazılarını geri alırsa Vanta bunları yeniden uygular.
home-plan-windows-title = Windows 11, sürüm { $release }
home-plan-windows-detail = Vanta bunu Windows Update'ten yükler. Tamamlamak için bilgisayarınız yeniden başlar.
home-plan-windows-optional = Önerilir. Vanta bunu Windows Update'ten yükler. Tamamlamak için bilgisayarınız yeniden başlar.
home-plan-atlas-title = Vanta { $version }
home-plan-atlas-detail = Vanta dosyalarını güncelleştirir ve yaptığınız seçimleri korur. Sonunda bilgisayarınız yeniden başlar.
home-end-of-updates-title = Windows 11 { $current } sürümü için güvenlik güncelleştirmeleri { $date } tarihinde sona eriyor
home-end-of-updates-past-title = Windows 11 { $current } sürümü artık güvenlik güncelleştirmesi almıyor
home-end-of-updates-message = Vanta { $version } sürümüne güncelleştirmek bu bilgisayarı Windows 11 { $release } sürümüne de geçirir. Bu sürüm { $until } tarihine kadar güvenlik güncelleştirmeleri alır.
install-windows-edition = Vanta { $version } sürümü Windows 11 Pro, Enterprise ve Education ile çalışır. Bu bilgisayarda { $product } yüklü, bu yüzden Vanta bu bilgisayara kurulamaz.
install-windows-edition-ending = Vanta { $version } sürümü Windows 11 Pro, Enterprise ve Education ile çalışır. Bu bilgisayarda { $product } yüklü, bu yüzden Vanta bu bilgisayara kurulamaz. Windows 11 { $current } sürümü için güvenlik güncelleştirmeleri { $date } tarihinde sona eriyor. Windows Update bu bilgisayarı daha yeni bir sürüme geçirebilir.
install-windows-no-path = Vanta { $version } sürümü için Windows 11 { $releases } sürümü gerekiyor ve Windows Update bu bilgisayarı mevcut Windows'tan bu sürüme geçiremiyor. Vanta { $version } sürümünü kullanmak için dosyalarınızı yedekleyin ve Windows'u bir Vanta ISO'suyla yeniden yükleyin.
home-update-access-title = Vanta güncelleştirmesi için Windows Update ayarları değiştirildi
home-update-access-not-offered = Vanta, bu bilgisayarı Windows 11 { $release } sürümüne geçirmek için Windows Update'i açtı, ancak Windows Update bu sürümü henüz sunmadı. Yeniden denetle'yi veya Ayarları geri yükle'yi seçin.
home-update-access-before = Vanta, bu bilgisayarı Windows 11 { $release } sürümüne geçirmek için Windows Update'i açtı ve işlemi henüz bitirmedi. Güncelleştirmeye devam edin veya Ayarları geri yükle'yi seçin.
home-update-access-after = Bu bilgisayarda Windows 11 { $release } sürümü var. Vanta kurulumunu tamamlayın veya Ayarları geri yükle'yi seçin.
home-update-access-plain = Vanta, güncelleştirmeleri yüklemek için Windows Update'i açtı ve işlemi henüz bitirmedi. Güncelleştirmeye devam edin veya Ayarları geri yükle'yi seçin.
home-update-access-unreadable = Vanta, değiştirdiği Windows Update ayarlarının kaydını okuyamıyor, bu yüzden hiçbir şeyi değiştirmeyecek veya geri yüklemeyecek. Vanta ekibinin yardımcı olabilmesi için Rapor gönder'i seçin.
home-update-access-failed = Vanta ayarları geri yükleyemedi. Yeniden deneyin veya Rapor gönder'i seçin. Ayrıntılar: { $error }
home-update-access-install-active = Önce Vanta kurulumunu tamamlayın. Kurulumun son adımı bu ayarları geri yükler.
home-continue-update = Güncelleştirmeye devam et
home-put-back = Ayarları geri yükle
home-putting-back = Ayarlar geri yükleniyor…
windows-card-title = Windows 11, sürüm { $release }
windows-card-required = Vanta { $version } sürümü için daha yeni bir Windows sürümü gerekiyor. Vanta aşağıda Windows'u güncelleştirirken Windows Update'ten Windows 11 { $release } sürümünü de yükler.
windows-card-question = Bu bilgisayar hangi Windows sürümünü kullansın?
windows-choice-move = Windows 11 { $release } sürümüne güncelleştir
windows-choice-move-detail = Önerilir. { $date } tarihine kadar güvenlik güncelleştirmeleri. Bir yeniden başlatma daha.
windows-choice-keep = Windows 11 { $current } sürümünde kal
windows-choice-keep-detail = Bilgisayarınız bu sürümde kalır. Windows Update onu daha yeni bir sürüme geçirmez, bu yüzden daha sonra geçmek için Vanta Manager'da ayrı bir güncelleştirme gerekir.
windows-card-facts = Neler değişir
windows-fact-keep = Dosyalarınız ve uygulamalarınız korunur. Güncelleştirme Vanta'ın değişikliklerinden bazılarını geri alırsa Vanta, kurulurken bunları yeniden uygular.
windows-fact-restart = Tamamlamak için bilgisayarınız en az bir kez daha yeniden başlar.
transition-offer-expectation = Windows Update bu sürümü genellikle birkaç dakika içinde sunar, ancak bu 2 saate kadar sürebilir; Vanta sizin yerinize bekler ve denetler.
windows-fact-stays = Sonrasında Windows { $release } sürümünde kalır ve kendiliğinden daha yeni bir sürüme geçmez.
windows-fact-removed = { $release } sürümünde Windows PowerShell 2.0 ve WMIC aracı yer almaz.
# Güncelleştirme geçmişi (Update history), Geri dön (Go back) and Sistem > Kurtarma are
# Windows' own Turkish labels.
windows-card-undo = Daha sonra geri almak için güncelleştirmeyi Windows Update > Güncelleştirme geçmişi bölümünden kaldırın. Windows güncelleştirme sırasında kendini yeniden yüklediyse bunun yerine 10 gün içinde Ayarlar > Sistem > Kurtarma bölümünde Geri dön'ü seçin. Vanta { $version } sürümü { $current } sürümünü desteklemez, bu yüzden Vanta { $version } kurulduktan sonra bu güncelleştirmeyi geri almayın.
windows-card-undo-optional = Daha sonra geri almak için güncelleştirmeyi Windows Update > Güncelleştirme geçmişi bölümünden kaldırın. Windows güncelleştirme sırasında kendini yeniden yüklediyse bunun yerine 10 gün içinde Ayarlar > Sistem > Kurtarma bölümünde Geri dön'ü seçin.
windows-terms = Windows 11 { $release } sürümü için Microsoft Yazılım Lisans Koşulları'nı kabul ediyorum
windows-terms-link = Lisans koşullarını oku
windows-card-locked = { $current } sürümünde kalmak için İptal'i, ardından Güncellemeyi durdur'u seçin.
prepare-description-transition = Vanta, kurulumdan önce Windows'un beklediği güncelleştirmeleri, ardından Windows 11 { $release } sürümünü yükler, sonra da Microsoft Store'u ve Store uygulamalarınızı güncelleştirir. Açık Store uygulamaları güncelleştirilirken kapanabilir; bu yüzden önce bu uygulamalardaki çalışmanızı kaydedin. Bilgisayarınız en az bir kez yeniden başlar.
prepare-start-transition = Windows'u { $release } sürümüne güncelleştir
prepare-needs-terms = Windows 11, sürüm { $release } kartında lisans koşullarını kabul ettiğinizde kullanılabilir.
ready-banner-not-offered-message = Şimdi neler yapabileceğinizi görmek için Windows ve Store güncellemeleri kartına bakın.
ready-banner-transition-failed-message = Sonra ne yapmanız gerektiğini görmek için Windows ve Store güncellemeleri kartına bakın.
ready-banner-terms-title = Devam etmek için lisans koşullarını kabul edin
ready-banner-terms-message = Koşullar bu sayfanın aşağısındaki Windows 11, sürüm { $release } kartında. Ardından Windows'u { $release } sürümüne güncelleştir'i seçin.
access-notice-title = Vanta, Windows Update'i geçici olarak açıyor
access-off = Windows Update bu bilgisayarda kapalı. Vanta, Windows'u güncelleştirirken onu yeniden açar.
access-paused = Windows güncelleştirmeleri bu bilgisayarda duraklatılmış. Vanta, Windows'u güncelleştirirken bunları sürdürür.
access-delayed = Aylık güncelleştirmeler bu bilgisayarda ertelenmiş. Vanta, Windows'u güncelleştirirken ertelemeyi kaldırır.
access-back-chosen = Vanta { $version } kurulduğunda bu ayarlar seçtiğiniz şekle döner.
access-back = Vanta { $version } kurulduğunda bu ayarlar eski hâline döner.
access-back-stop = Bundan önce durdurursanız Vanta bunları geri yükler.
prepare-reboot-transition = Windows 11 { $release } sürümü yüklendi. Yüklemeyi tamamlamak için Yeniden başlat ve devam et'i seçin. Oturum açtıktan sonra Vanta yeniden açılır.
prepare-reboot-commit = { $release } sürümünün yüklenmesini tamamlamak için Windows'un bir kez daha yeniden başlatılması gerekiyor. Oturum açtıktan sonra Vanta yeniden açılır.
prepare-restart-commit-failed = Windows, { $release } sürümünü yeniden başlatma sırasında tamamlanacak şekilde hazırlayamadı, bu yüzden bilgisayarınız yeniden başlamadı. Yeniden denemek için Yeniden başlat ve devam et'i seçin.
prepare-reason-feature-update = yeni Windows sürümü
prepare-reason-feature-commit = yeni Windows sürümünün tamamlanması
prepare-resumed-transition = Bilgisayarınız yeniden başladı. Vanta'ın Windows 11 { $release } sürümünün tamamlandığını denetlemesi ve kalan güncelleştirmeleri yüklemesi için Güncellemelere devam et'i seçin.
prepare-waiting-offer = Windows Update'in Windows 11 { $release } sürümünü sunması bekleniyor. Bu genellikle birkaç dakika sürer, ancak 2 saate kadar sürebilir. Bilgisayarınızı kullanmaya devam edebilirsiniz; Vanta'ı açık bırakın.
prepare-resumed-before-move = Bilgisayarınız, güncelleştirmelerin yüklenmesini tamamlamak için yeniden başladı. Vanta'ın kalan güncelleştirmeleri, ardından Windows 11 { $release } sürümünü yükleyebilmesi için Güncellemelere devam et'i seçin.
prepare-not-offered-title = Windows Update'in Windows 11 { $release } sürümünü sunması bekleniyor
prepare-transition-failed-title = Windows, { $release } sürümüne geçemedi
prepare-failed-feature-not-offered = Windows Update'in Windows 11 { $release } sürümünü bir bilgisayara sunması biraz zaman alabilir. Bilgisayarınızda hâlâ { $current } sürümü var.
prepare-offer-rechecking = Vanta her 10 dakikada bir yeniden denetler ve Windows Update bu sürümü sunar sunmaz kendiliğinden devam eder. Yeniden denetle'yi de seçebilirsiniz.
prepare-offer-waited =
    { $minutes ->
        [one] { $minutes } dakikadır bekleniyor.
       *[other] { $minutes } dakikadır bekleniyor.
    }
prepare-offer-next-check =
    { $minutes ->
        [one] Sonraki denetim { $minutes } dakika sonra.
       *[other] Sonraki denetim { $minutes } dakika sonra.
    }
prepare-offer-checking-now = Şimdi denetleniyor.
prepare-offer-check-again = Şimdi denetlemek için Yeniden denetle'yi seçin.
prepare-offer-wait-ended-title = Windows Update, Windows 11 { $release } sürümünü henüz sunmadı
prepare-offer-wait-ended = Windows Update, Windows 11 { $release } sürümünü 2 saat içinde sunmadı, bu yüzden Vanta beklemeyi bıraktı ve Windows Update ayarlarınızı geri yükledi. Daha sonra Yeniden denetle'yi seçin. Bekleyemiyorsanız dosyalarınızı yedekleyin ve Windows'u bir Vanta ISO'suyla yeniden yükleyin.
prepare-offer-wait-put-back-failed = Windows Update, Windows 11 { $release } sürümünü 2 saat içinde sunmadı ve Vanta, Windows Update ayarlarınızı geri yükleyemedi. Yeniden denemek için Ayarları geri yükle'yi seçin. Ayrıntılar: { $error }
prepare-failed-feature-hardware = Bu bilgisayar Windows 11 donanım gereksinimlerini karşılamıyor ({ $missing }), bu yüzden Windows Update onu { $release } sürümüne geçirmez. Bilgisayarınızda hâlâ { $current } sürümü var. Vanta { $version } sürümünü kullanmak için dosyalarınızı yedekleyin ve Windows'u bir Vanta ISO'suyla yeniden yükleyin.
hardware-tpm = TPM 2.0
hardware-uefi = UEFI ürün yazılımı
prepare-failed-feature-hidden = Windows 11 { $release } sürümü bu bilgisayarda Windows Update'te gizlenmiş. Gizlemek için kullandığınız araçla yeniden gösterin, ardından Yeniden dene'yi seçin.
prepare-failed-feature-disk-space = Windows'un bu güncelleştirme için { $drive } sürücüsünde en az { $needed } GB boş alana ihtiyacı var, sürücüde ise { $free } GB boş alan var. Vanta hiçbir şeyi değiştirmedi. Alan boşaltın, ardından Yeniden dene'yi seçin.
prepare-failed-feature-servicing = Windows, bileşen deposunda onaramadığı bir hasar bildiriyor, bu yüzden Vanta hiçbir şeyi değiştirmedi. Windows'u onarın, ardından Yeniden dene'yi seçin.
prepare-failed-feature-managed = Bu bilgisayar güncelleştirmeleri bir kuruluşun güncelleştirme sunucusundan alıyor, bu yüzden Vanta onu { $release } sürümüne geçiremez. Vanta hiçbir şeyi değiştirmedi.
prepare-failed-feature-policy = Bu bilgisayardaki bir şey, Vanta değiştirdikten sonra şunu sürekli eski hâline getiriyor: { $setting }. Bu yüzden Vanta Windows'u güncelleştiremiyor. Bu bilgisayarı bir kuruluş yönetiyorsa kuruluşa danışın. Durdurduğunuzda Vanta değiştirdiklerini geri yükler.
prepare-failed-feature-blocked = Vanta'ın değiştirmediği bir ayar Windows Update'in çalışmasını engelliyor: { $setting }. Windows Update'in çalışabilmesi için bu ayarı değiştirin, ardından Yeniden dene'yi seçin.
prepare-failed-feature-rolled-back = Windows, { $release } sürümünün yüklenmesini yeniden başlatma sırasında tamamlayamadı ve { $current } sürümüne geri döndü. Dosyalarınız ve uygulamalarınız etkilenmedi. Yeniden dene'yi veya Rapor gönder'i seçin.
prepare-failed-feature-components-lost = Windows güncelleştirmesinden sonra Vanta'ın bazı değişiklikleri kayboldu ve Windows'un kendini yeniden yüklediğine dair bir iz yok, bu yüzden Vanta ne olduğunu anlayamıyor. Vanta { $version } kurulmadı. Vanta ekibinin yardımcı olabilmesi için Rapor gönder'i seçin.
prepare-failed-feature-build = Vanta bu bilgisayarı güncelleştirirken Windows sürümü değişti. Ayarları geri yükle'yi seçin, ardından Giriş sayfasından baştan başlayın.
prepare-failed-feature-journal = Vanta, değiştirdiği Windows Update ayarlarının kaydını okuyamıyor, bu yüzden hiçbir şeyi değiştirmeyecek veya geri yüklemeyecek. Vanta ekibinin yardımcı olabilmesi için Rapor gönder'i seçin.
# $setting is the name of a Windows Update policy value, such as TargetReleaseVersionInfo (text).
prepare-failed-feature-pin = Bu bilgisayardaki bir Windows Update ilkesinin ({ $setting }) değeri Vanta'ın kaydedemeyeceği türden, bu yüzden Vanta hiçbir şeyi değiştirmedi. Vanta ekibinin yardımcı olabilmesi için Rapor gönder'i seçin.
prepare-failed-feature-terms = Windows 11 { $release } sürümünün lisans koşullarını kabul edin, ardından Yeniden dene'yi seçin.
prepare-failed-feature-failed = Windows, { $release } sürümünü yükleyemedi. Bilgisayarınızda hâlâ { $current } sürümü var. Yeniden dene'yi seçin. Yine başarısız olursa Rapor gönder'i seçin.
prepare-check-again = Yeniden denetle
prepare-keep-version = { $current } sürümünde kal
stop-update-title = Vanta { $version } sürümüne güncelleştirme durdurulsun mu?
stop-update-title-windows = Windows güncelleştirmesi durdurulsun mu?
stop-update-before = Vanta, değiştirdiği Windows Update ayarlarını geri yükler. Windows'un zaten yüklediği güncelleştirmeler yüklü kalır ve bilgisayarınız Windows 11 { $current } sürümünde kalır.
stop-update-after = Bilgisayarınız Windows 11 { $release } sürümünde kalır. Vanta, değiştirdiği Windows Update ayarlarını geri yükler.
stop-update-access = Vanta, değiştirdiği Windows Update ayarlarını geri yükler. Windows'un zaten yüklediği güncelleştirmeler yüklü kalır.
stop-update-keep = Güncelleştirmeye devam et
# Dialog shown when the window is closed while Windows Update is turned on for an update; its
# buttons are window-close-keep and window-close-put-back.
window-close-update-access-title = Vanta kapatılsın mı?
window-close-update-access-message = Vanta kapanmadan önce değiştirdiği Windows Update ayarlarını geri yükler. Güncelleştirmeye Giriş sayfasından yeniden başlayabilirsiniz.
window-close-put-back = Geri yükle ve kapat
# When putting the settings back before closing failed. The reason comes first, then this
# message; the buttons are window-close-keep and window-close-close.
window-close-put-back-failed-title = Ayarlar geri yüklenmeden kapatılsın mı?
window-close-put-back-failed-message = Vanta'ı şimdi kapatırsanız Windows Update ayarları Vanta'ın değiştirdiği şekilde kalır. Vanta'ı yeniden açtığınızda Giriş sayfası bunları geri yüklemeyi önerir.
installed-update-off-again = Seçtiğiniz gibi Windows Update yeniden kapatıldı. Kapalıyken bilgisayarınız güvenlik güncelleştirmesi almaz.
installed-update-paused-again = Seçtiğiniz gibi Windows güncelleştirmeleri yeniden duraklatıldı. Duraklatılmışken bilgisayarınız güvenlik güncelleştirmesi almaz.
detail-build-transition = Bu bilgisayarda, bu Vanta sürümünün desteklemediği Windows 11 { $current } sürümü var. Vanta aşağıda Windows'u güncelleştirirken Windows'u { $release } sürümüne geçirir.
report-transition-intro = Vanta için Windows güncelleştirmesi tamamlanmadı. Vanta ekibi için ayrıntılar:
mode-rebase = Windows güncelleştirmesinden sonra yeniden kurulum
history-mode-rebase = Windows güncelleştirmesinden sonra yeniden kurulum
ready-rebase-title = Windows güncelleştirme sırasında kendini yeniden yükledi
ready-rebase-message = Windows 11 { $release } sürümü bu bilgisayardaki önceki Windows'un yerini aldı, bu yüzden Vanta'ın bazı değişiklikleri kayboldu. Vanta { $version }, Vanta { $previous } için yaptığınız seçimlerle bunları yeniden uygular.
update-path-update-title = Vanta { $version } sürümüne nasıl güncelleştirmek istersiniz?
update-path-reinstall-title = Vanta { $version } sürümünü nasıl yeniden kurmak istersiniz?
update-path-keep = Seçimlerimi koru
update-path-keep-detail = Vanta her seçimi bu bilgisayardaki şu anki hâliyle korur ve hiçbirini değiştirmez. Bu daha hızlı yoldur.
update-path-choose = Yeniden seç
update-path-choose-detail = Bu bilgisayarın şu anki durumundan başlayarak her seçimi yeniden yapın. Vanta her birini yeni bir kurulumdaki gibi uygular. Uygulamalarınız, dosyalarınız, Başlat menüsü, görev çubuğu ve temanız olduğu gibi kalır; Vanta klasöründe değiştirdiğiniz ve bu seçimlerin kapsamadığı ayarlar da öyle.
update-path-now-title = Bu bilgisayardaki mevcut seçimleriniz
update-path-unknown = Vanta bunu bilgisayarınızdan anlayamıyor, bu yüzden size soracak
option-detected-off = Geçerli sistemde kapalı olarak algılandı. Hiçbir seçim yapılmadı, bu yüzden güvenli varsayılan (açık kalsın) seçili: lütfen kendiniz seçin.
update-path-differs = Vanta'ın son kurulumunuzla ilgili kaydı şu seçimlerde bu bilgisayarla eşleşmiyor: { $choices }. Bu liste bilgisayarın şu anki durumunu gösterir.
keep-choices-title = Seçimleriniz korunuyor
keep-choices-partial = Vanta bu bilgisayarın şu anki durumunu korur. Şunları bilgisayarınızdan anlayamıyor, bu yüzden bunları siz seçin: { $missing }
choose-again-title = Yeniden seçiyorsunuz
choose-again-detail = Her seçim bu bilgisayarın şu anki durumundan başlar. Vanta seçtiklerinizi kurulum sırasında uygular.
option-now = Şu anda bu bilgisayarda
change-defender-enable = Vanta, Microsoft Defender'ı geri getirir. Bilgisayarınız yeniden başladıktan sonra korumasını Windows Güvenliği'nde açın.
change-mitigations-default = Vanta, işlemci korumalarını Windows'un varsayılan ayarlarıyla yeniden açar. Bu değişiklik, bilgisayarınız yeniden başladıktan sonra geçerli olur.
change-mitigations-all-on = Şu anda tüm işlemci korumaları açık. Korumaları tutarsanız hepsi açık kalır.
change-auto-updates-default = Vanta, Windows'un güncelleştirmeleri yeniden otomatik olarak yüklemesine izin verir.
change-hibernation-on = Vanta hazırda bekletmeyi yeniden açar.
change-power-saving-on = Vanta güç tasarrufunu yeniden açar ve önceki güç planınıza, önceki bir plan yoksa Dengeli plana geri döner.
change-core-isolation-on = Vanta, sanallaştırma tabanlı güvenliği (VBS) yeniden açar; ancak bu bilgisayarda bir ilke bunu denetliyorsa açmaz. Bu değişiklik, bilgisayarınız yeniden başladıktan sonra geçerli olur.
change-remove-snipping-tool = Ekran Alıntısı Aracı'nı bu bilgisayardaki herkes için kaldırır. Vanta onu daha sonra geri getiremez, ancak Microsoft Store'dan yeniden yükleyebilirsiniz.
fixed-uninstall-edge = Microsoft Edge zaten kaldırılmış ve Vanta'ı güncelleştirmek onu geri getiremez. Yeniden yüklemek için Vanta klasöründeki Install or Remove Edge dosyasını kullanın.
fixed-installed = { $app } yüklü. Vanta uygulamaları kaldırmaz; bu uygulamayı kaldırmak için Windows Ayarları'ndaki Yüklü uygulamalar sayfasını açın.
browser-also = { $installed } yüklü kalır ve Vanta ayrıca { $browser } tarayıcısını yükler.
summary-update-path = Güncelleştirme yöntemi
step-heading-update-path-a11y = { $heading }. { $question }
security-banner-removed-title = Vanta, Microsoft Defender'ı bu bilgisayardan kaldırdı
security-banner-restore-title = Vanta bu kurulumda Microsoft Defender'ı geri getiriyor
security-banner-restore-message = Defender henüz çalışmıyor, bu yüzden bu adımda kapatılacak bir şey yok. Bilgisayarınız yeniden başladıktan sonra korumasını Windows Güvenliği'nde açın. Devam et'i seçin.
security-banner-missing-title = Microsoft Defender bulunamadı
security-banner-missing-message = Vanta onu kaldırmadı, bu yüzden geri getiremez. Devam edebilirsiniz, ancak başka bir virüsten koruma uygulaması yükleyene veya Windows'u onarana kadar bilgisayarınızda virüsten koruma olmaz.
installed-defender-not-restored-title = Microsoft Defender hâlâ kaldırılmış durumda
installed-defender-not-restored-message = Microsoft Defender'ı tutmayı seçtiniz, ancak önceki bir Vanta güncelleştirmesi onu geri getirmedi, bu yüzden bilgisayarınızda virüsten koruma yok. Geri getirmek için Vanta'ı güncelleştirin veya yeniden kurun ve Yeniden seç seçeneğini belirleyin. Ya da masaüstünüzdeki Vanta klasöründe 7. Security > Defender klasörünü açın, Toggle Defender dosyasını çalıştırın, Enable Windows Defender seçeneğini belirleyin ve bilgisayarınızı yeniden başlatın.
choices-not-applied-title = Bazı seçimler uygulanmadı
choices-not-applied-message = Vanta şu seçimler için bu bilgisayarın şu anki durumunu kaydetti: { $choices }. Nedenini kurulum günlüğünde bulabilirsiniz.
rebase-choices-title = Vanta { $previous } sürümündeki seçimleriniz
rebase-choices-detail = Vanta, Vanta { $previous } için yaptığınız seçimleri kullanır, bu yüzden burada seçilecek bir şey yok. Bunları sonradan değiştirmek için Vanta'ı yeniden kur'u seçin, ardından Yeniden seç seçeneğini belirleyin.
rebase-choices-partial = Vanta, Vanta { $previous } için yaptığınız seçimleri kullanır. Şunları bulamadı, bu yüzden bunları denetleyin: { $missing }
restart-other-title = Bu bilgisayarda başka biri oturum açmış
restart-others-title = Bu bilgisayarda başka kişiler oturum açmış
restart-others-message = Yeniden başlatma onların uygulamalarını kapatır ve kaydedilmemiş çalışmaları kaybolur. Oturum açmış olanlar: { $names }.
# "Yeniden başlatma" alone would read as the noun "restart", so the button says what it cancels.
restart-others-keep = Yeniden başlatmaktan vazgeç
restart-others-restart = Yine de yeniden başlat
prepare-store-self-update = Önce Microsoft Store güncelleştiriliyor. Bu bilgisayardaki sürümü güncel değil.
prepare-store-repair = Microsoft Store onarılıyor. Bu birkaç dakika sürebilir.
prepare-store-updated = Microsoft Store güncel değildi, bu yüzden Vanta onu uygulamalarınızdan önce güncelleştirdi.
prepare-store-bootstrapped = Microsoft Store kendini güncelleştiremedi, bu yüzden Vanta en son Uygulama Yükleyicisi'ni ve Microsoft Store'u Microsoft'tan yükledi.
prepare-store-repaired = Microsoft Store çalışmıyordu, bu yüzden Vanta onu onardı.
prepare-store-skipped-removed = Microsoft Store bu bilgisayarda kapalı, bu yüzden Vanta Store uygulaması güncelleştirmelerini atladı.
prepare-failed-store-repair-failed = Microsoft Store bu bilgisayarda uygulama yükleyemiyor veya güncelleştiremiyor ve Vanta onu onaramadı. Vanta'ın çalışan bir Store'a ihtiyacı var, çünkü Store bozukken Vanta'ı yüklemek Store'u ve uygulamalarını bozuk bırakabilir. Yeniden denemek için Microsoft Store'u onar'ı seçin. Yine çalışmazsa dosyalarınızı yedekleyin ve Windows'u bir Vanta ISO'suyla yeniden yükleyin ya da Rapor gönder'i seçin.
prepare-repair-store = Microsoft Store'u onar

screen-keyboard-title = Klavye dilleri
screen-keyboard-question = Birden fazla klavye dili kullanıyor musunuz?
package-option-keyboard-shortcuts = Evet, klavye kısayollarıyla
package-option-keyboard-selector = Evet, görev çubuğundaki seçiciyle
package-option-keyboard-single = Hayır, tek bir klavye düzeni kullanıyorum
consequence-keyboard-shortcuts = Alt+Shift dili, Ctrl+Shift klavye düzenini değiştirir.
consequence-keyboard-selector = Oyun sırasında yanlışlıkla geçiş yapmamak için Alt+Shift ve Ctrl+Shift kapatılır.
package-choice-keyboard-description = Klavye dilini nasıl değiştireceğinizi seçin.
consequence-keyboard-single = { consequence-keyboard-selector }

# Seçenekler ekranının üstündeki seçim modu çubuğu.
options-mode-title = Seçim modu
options-mode-recommended = Vanta tarafından önerilen
options-mode-manual = Elle seç
options-mode-recommended-detail = Vanta tarafından önerilen profili yalnızca bu ekrandaki seçeneklere uygular (VBS, kimlik avı koruması, Store ve Ekran Alıntısı Aracı korunur; önceki seçimleri değiştirmeden Brave ve Vanta iyileştirmeleri açılır).
options-mode-manual-detail = Tek tek seçmeniz için tüm ek seçenekler işaretsiz başlar veya tek tıkla Vanta tarafından önerilen profili uygular.
options-mode-proceed = Önerilen ile devam et
prepare-ready-title = Her şey hazır — aşağıdan Devam'a tıklayın
prepare-ready-detail = Windows bir sonraki adım için hazır. Şimdi devam edebilirsiniz.
option-recommended-label = { $label } (önerilir)
option-core-isolation-unlock = Valorant veya bunu zorunlu tutan hile korumalı başka oyunlar oynamıyorum
option-why-disable-hibernation = Kazanç: SSD'de birkaç GB yer açar ve temiz başlangıç sağlar. Dikkat: dizüstü bilgisayarlarda hazırda bekletme ve Hızlı Başlatma kapanır.
option-why-disable-power-saving = Kazanç: oyunlarda işlemci frekans düşüşlerini ve gecikmeleri azaltır. Dikkat: daha fazla güç tüketir ve dizüstü pil ömrünü kısaltır.
option-why-disable-core-isolation = Kazanç: bazı bilgisayarlarda CPU yükünü biraz azaltabilir. Dikkat: zararlı sürücülere karşı korumayı düşürür ve katı anti-cheat içeren oyunları (Valorant/Vanguard gibi) engeller.
option-why-disable-phishing-protection = Ne yapar: güvensiz sitelere Windows parolanızı yazarken çıkan uyarıyı kapatır. Kazanç: kayda değer FPS artışı sağlamaz. Dikkat: parola çalınmasına karşı korumayı azaltır.
option-why-disable-gamebar = Ne yapar: Xbox Game Bar katmanını ve arka plan kaydını (Game DVR) kapatır. Kazanç: oyunlarda GPU ve disk yükünü azaltır. Dikkat: Win+G ve Game Bar klipleri çalışmaz.
option-why-remove-store = Ne yapar: App Installer ve winget'i koruyarak Microsoft Store uygulamasını kaldırır. Kazanç: arka planda daha az güncelleme ve işlem. Dikkat: Store uygulamaları veya Game Pass oyunları indirilemez.
option-why-vanta-power = Ne yapar: masaüstü bilgisayarlar için ayarlanmış Vanta güç planını etkinleştirir. Kazanç: oyunlarda güç tasarrufu kısıtlaması olmadan işlemciyi hızlı tutar. Dikkat: yalnızca masaüstünde uygulanır; dizüstünde atlanır.
option-why-vanta-memory = Ne yapar: bellek sıkıştırmayı açık tutar, sayfa birleştirme ve uygulama ön yüklemeyi kapatır. Kazanç: arka plan disk kullanımını azaltır ve kare sürelerini dengeler. Dikkat: büyük uygulamalar ilk açılışta biraz daha yavaş olabilir.
option-why-tools-on-logon = Ne yapar: kurulum sonrası bir sonraki oturum açılışında Vanta Tools'u otomatik açar. Kazanç: programları kurmayı ve ayarları gözden geçirmeyi kolaylaştırır. Dikkat: kalıcı etkisi yoktur.
option-why-remove-snipping-tool = Ne yapar: Windows'un yerleşik Ekran Alıntısı Aracı'nı kaldırır. Kazanç: ShareX veya Lightshot kullanıyorsanız gereksiz bir uygulamayı siler. Dikkat: başka araç kurmadan Win+Shift+S çalışmaz.
option-why-uninstall-edge = Kazanç: Edge'in arka plan güncelleyicilerini ve hizmetlerini kaldırır. Dikkat: başka bir tarayıcının kurulu veya aşağıda seçili olduğundan emin olun.
option-why-install-another-browser = Kazanç: kurulumdan hemen sonra hazır bir tarayıcı sunar; Edge'i kaldırıyorsanız özellikle faydalıdır. Dikkat: internet bağlantısı gerekir.
option-why-install-eclean = Kazanç: kurulum sonrası geçici dosyaları temizlemeye ve başlangıç uygulamalarını yönetmeye yardımcı olur. Dikkat: isteğe bağlıdır; hesap ve internet gerekir.
option-why-browser-brave = Ne yapar: yerleşik reklam ve izleyici engelleyicili Chromium tarayıcısı Brave'i kurar. Kazanç: eklentisiz hızlı ve temiz gezinme. Dikkat: isteğe bağlı kripto özellikleri ayarlardan yok sayılabilir.
option-why-browser-librewolf = Ne yapar: telemetrisiz, gizlilik odaklı Firefox türevi LibreWolf'u kurar. Kazanç: varsayılan olarak güçlü izleme koruması. Dikkat: bazı siteler çerez istisnası isteyebilir.
option-why-browser-firefox = Ne yapar: Chromium'dan bağımsız Mozilla Firefox'u kurar. Kazanç: güçlü gizlilik ve geniş eklenti desteği. Dikkat: yalnızca Chromium için yapılan bazı web uygulamaları farklı çalışabilir.
option-why-browser-chrome = Ne yapar: Google hesap eşitlemeli Google Chrome'u kurar. Kazanç: web siteleriyle en yüksek uyumluluk. Dikkat: gizlilik odaklı tarayıcılara göre daha fazla RAM kullanır ve daha çok veri toplar.
