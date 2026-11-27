### Vanta Manager: Japanese (ja), preview translation. Revised 1 October 2026 from the en-GB source (i18n/en-GB/atlas.ftl).
###
### Conventions for this catalog:
### - Polite です・ます form for sentences; noun-stop or verb-stem labels for
###   buttons and headings, as Windows does (再起動, キャンセル, 完了).
### - A half-width space between Japanese and Latin words or numbers, and
###   between katakana compounds (インストール ファイル), as Microsoft does.
### - Full-width 。、 with half-width ( ) and : plus a half-width space, as
###   Microsoft Japanese UI does; half-width "?" in questions.
### - Japanese has only the "other" plural category; exact [1]/[2] are used
###   where the wording changes.
### - "Relaunch" (the Vanta Manager) is 再実行 / 開き直す; "restart" (the PC or
###   Windows) is 再起動. Never swap them.
### - "Vanta package" (the .vantapkg file) is "Vanta パッケージ", shortened to
###   "パッケージ" once it's clear; "package file" is パッケージ ファイル.

## 共通

app-name = Vanta Manager
common-done = 完了
common-cancel = キャンセル
common-back = 戻る
common-next = 続行
common-dismiss = 閉じる
# Link beside a summary row that jumps back to change that choice.
common-change = 変更
common-copy = コピー
# Shown where a list of options is empty.
common-none = なし
# Accessible name of the back arrow on the Install and Settings pages.
common-back-to-home = ホームに戻る
# Accessible name of the gear button in the title bar.
common-settings = 設定
common-close-settings = 設定を閉じる
common-open-windows-security = Windows セキュリティを開く
# Relaunches the Vanta Manager with administrator rights (UAC). Not a PC restart.
common-restart-as-administrator = 管理者として再実行
common-try-again = 再試行
common-show-details = 詳細を表示
common-hide-details = 詳細を非表示
# Accessible name of a Show details or Hide details toggle. $action is common-show-details or
# common-hide-details; $section is the title of the card it opens.
common-details-a11y = { $action }、{ $section }
common-open-log-file = ログ ファイルを開く
# Accessible name of the Copy button beside the install log.
common-copy-install-log = インストール ログをコピー
common-install-log = インストール ログ
# Row labels in summary cards.
common-windows = Windows
common-options = オプション
common-package = インストール ファイル
common-installed-as = インストールの種類
common-installed = インストール済み
common-checking = 確認中
# Joins two items in a list: "Brave、Firefox". The braces keep the literal.
list-separator = { "、" }
# Joins two alternatives: "26100 または 26200".
list-or = { $a } または { $b }
# Joins the last two items of a list: "改ざん防止、クラウド提供の保護" (CLDR ja uses 、 here too).
# $a may itself be several items joined with list-separator.
list-and = { $a }、{ $b }
# Accessible name of a message bar that announces itself: its title, then its message.
infobar-a11y = { $title }。{ $message }

## ウィンドウ

# Dialog shown when the window is closed while an install runs.
window-close-title = インストール中にウィンドウを閉じますか?
window-close-message = インストールはバックグラウンドで続行されます。進行状況と結果を確認するには、Vanta をもう一度開いてください。インストールが終わるまで PC の電源を切らないでください。
# Instead of window-close-message when the installation restarts the PC afterwards: only an
# open Vanta window restarts it, so closing the window cancels that.
window-close-message-restart = インストールはバックグラウンドで続行されますが、Vanta を閉じている間は PC が自動的に再起動しません。進行状況と結果を確認するには、Vanta をもう一度開いてください。インストールが終わるまで PC の電源を切らないでください。
# The safe answer in every dialog shown when the window is closed, including those for ISO
# and USB creation, updates and Windows Update access.
window-close-keep = 開いたままにする
window-close-close = ウィンドウを閉じる
# Dialog shown when the window is closed during the final checks, before the
# installer has started; window-close-keep and window-close-close are its buttons.
window-close-preparing-title = インストールの開始前に閉じますか?
window-close-preparing-message = Vanta は PC を確認中で、まだインストールを開始していません。今閉じると、インストールは開始されません。続行するには、Vanta をもう一度開いてください。
prepare-close-title = 更新はまだ実行中です
# "Stop updating" is prepare-stop, the dialog's other button.
prepare-close-message = 更新の実行中は Vanta を開いたままにしてください。「更新を停止」を選ぶと、現在の手順が終わった時点で更新が停止し、その後 Vanta を閉じられます。
# Dialog shown when the window is closed during the restart countdown after a
# successful install. Its buttons are window-close-keep, restart-now and
# window-close-restart-close.
window-close-restart-title = 再起動せずに Vanta を閉じますか?
# "今すぐ再起動" is restart-now, one of this dialog's three buttons.
window-close-restart-message = Vanta のセットアップを完了するには、PC の再起動が必要です。今 Vanta を閉じると PC は再起動されないため、準備ができたらご自身で再起動してください。「今すぐ再起動」を選ぶ前に作業を保存してください。
window-close-restart-close = 再起動せずに閉じる
# Dialog shown when the window is closed during a setup with Windows Security switches still
# off. $switches names them as Windows Security does, joined like a list. Its buttons are
# window-close-keep, common-open-windows-security and window-close-close.
window-close-protection-title = 保護がオフのまま Vanta を閉じますか?
window-close-protection-message = Windows セキュリティの一部の保護がまだオフになっています: { $switches }。Vanta のインストールを最後まで行わない場合は、閉じる前に保護をオンに戻してください。インストールを続ける場合は、Vanta をもう一度開くとセットアップを再開します。
# The Open button of the file picker for an Vanta package (.vantapkg) file, on Get ready and the
# ISO page. It's a button label, so keep it short.
file-dialog-open-package = Vanta パッケージ (.vantapkg) を開く
# Message Windows shows in its restart notification.
shutdown-comment = Vanta のインストールが完了しました。セットアップを完了するため、Windows を再起動します。
# Message Windows shows in its restart notification when "Get ready" restarts
# to finish installing Windows updates.
prepare-shutdown-comment = 更新プログラムのインストールを完了するため、Vanta が Windows を再起動します。

## システム

# "Windows 11 Pro 25H2 (ビルド 26200.1234)". All three values are text.
system-description = { $product } { $version } (ビルド { $build })

## ホーム ページ

home-not-installed = Vanta へようこそ
# The headline when Vanta Manager can't tell what is installed on this PC.
home-state-unknown = この PC の Vanta
# The headline when Vanta is installed. $version is text.
home-version = Vanta { $version }
# $date is a formatted date.
home-installed-on = インストール日: { $date }
home-status-checking = 更新プログラムを確認しています
# While startup checks whether another window's installation is running.
home-status-recovering = 実行中のインストールを確認しています
home-status-offline = 更新プログラムを確認できませんでした
home-status-not-checked = 更新プログラムはまだ確認していません
home-status-update = Vanta { $version } が利用可能です
home-status-up-to-date = 最新の状態です
home-status-newest = 最新バージョン: Vanta { $version }
# An earlier installation of Vanta { $version } stopped before it finished.
home-status-unfinished = Vanta { $version } のインストールが完了していません
home-check-again = もう一度確認
# Primary button while an install is running or waiting.
home-show-install = 進行状況を表示
home-continue-installing = セットアップを続行
home-update-to = Vanta { $version } に更新
home-reinstall = Vanta を再インストール
home-install = Vanta をインストール
home-finish-install = Vanta { $version } のインストールを完了
home-start-over = 最初からやり直す
home-restart-title = PC の再起動が必要です
home-security-reminder-title = 保護をオンに戻してください
# Instead of home-security-reminder-title when no switch reads off but some couldn't be read
# (with home-security-reminder-unreadable-message).
home-security-reminder-unreadable-title = 保護がオンになっているか確認してください
home-security-reminder-message = Vanta は現在インストールを実行していませんが、Windows セキュリティの一部の保護がまだオフになっています。Windows セキュリティを開き、次の保護を必ずオンにしてください: { $switches }。
home-security-reminder-unreadable-message = Vanta は一部の保護スイッチを読み取れませんでした。Windows セキュリティで、次の保護がオンになっていることを確認してください: { $switches }。
home-elevation-title = インストールには管理者権限が必要です
home-state-error-title = Vanta のインストール情報を読み取れませんでした
home-state-error-message = Vanta のバージョン、選択内容、履歴が正しく表示されない可能性があります。「もう一度確認」を選んで再試行してください。詳細: { $error }
home-whats-new = Vanta { $version } の新機能
home-view-release = GitHub でリリース ノートを表示
home-released = リリース日: { $date }
home-show-less = 折りたたむ
home-show-full-notes = リリース ノートをすべて表示
home-your-install = Vanta のインストール情報
# Vanta is installed, but without the record Vanta Manager keeps (older versions didn't write one).
home-install-unrecorded = この PC には Vanta のインストール方法の記録がないため、選択内容とインストール履歴を表示できません。
home-history = インストール履歴
# One history row. $version is text, $mode one of the history-mode-* messages, $date a formatted date and time.
home-history-entry = Vanta { $version } · { $mode } · { $date }
home-how-it-works = PC を Vanta 用に準備しましょう
home-step-1-detail = Vanta が PC を確認し、保留中の Windows と Microsoft Store の更新プログラムをインストールして、インストール ファイルをダウンロードします。Store アプリが終了したり、PC の再起動が必要になったりすることがあるため、先に作業を保存してください。
# Tester build: the Vanta package is bundled, nothing is downloaded.
home-step-1-detail-bundled = Vanta が PC を確認し、保留中の Windows と Microsoft Store の更新プログラムをインストールして、同梱のインストール ファイルを準備します。Store アプリが終了したり、PC の再起動が必要になったりすることがあるため、先に作業を保存してください。
home-step-2-detail = Microsoft Defender とプロセッサの保護を残すかどうかと、Windows の更新プログラムのインストール方法を選び、必要に応じて追加オプションも選びます。
home-step-3-detail = インストールを妨げないよう、Windows セキュリティの 4 つの保護スイッチをオフにします。手順は Vanta がご案内します。
# Japanese has no plural forms; the same wording serves every count.
home-step-4-detail = インストールには約 { $minutes } 分かかります。その後、PC の再起動が必要です。
# Accessible name of a numbered step.
home-step-a11y = 手順 { $number }: { $title }
# Link buttons: say where they lead, not just the brand.
home-report-problem = 問題を報告

## インストールの種類 (状態ドキュメントから)

mode-fresh = 新規インストール
mode-upgrade = 以前のバージョンからの更新
mode-reapply = 同じバージョンの再インストール
mode-unknown = インストール
# Short forms used inside a history row.
history-mode-fresh = 新規インストール
history-mode-upgrade = 更新
history-mode-reapply = 再インストール
history-mode-unknown = インストール

## ホーム ページの通知

notice-settings-reset-title = Vanta は既定のアプリ設定を使用しています
# $error is a raw error message (text).
notice-settings-unreadable = 保存されたアプリの設定を読み取れませんでした。Windows の設定は変更されていません。詳細: { $error }
# $file is a file name (text).
notice-settings-damaged-kept = アプリの設定ファイルが破損していたため、リセットしました。以前のファイルは { $file } として保存してあります。詳細: { $error }
notice-settings-damaged = アプリの設定ファイルが破損していました。当面は既定の設定を使用します。詳細: { $error }
notice-settings-not-saved-title = アプリの設定を保存できませんでした
# $error is a raw error message (text).
notice-settings-not-saved = Vanta は最新の変更を保存できなかったため、Vanta を閉じると変更が失われる可能性があります。別の Vanta ウィンドウが開いている場合は閉じてから、もう一度変更してください。詳細: { $error }
notice-session-unreadable-title = 前回のインストールの状態を確認できませんでした
# $path is a file path (text).
notice-session-unreadable-message = 以前のインストールがまだ実行中かどうかを、Vanta は確認できませんでした。判断できない場合は、Vanta コミュニティに相談してください。実行中のインストールがないと確信できる場合に限り、{ $path } を削除してから再試行してください。詳細: { $error }

## 管理者への昇格

elevation-declined = 許可が得られませんでした。再試行し、Vanta による変更を許可するかどうか Windows が確認したら「はい」を選んでください。
elevation-declined-continue = 許可が得られませんでした。再試行し、Vanta による変更を許可するかどうか Windows が確認したら「はい」を選んでください。選択した設定は保存されています。
elevation-draft-not-saved = 選択した設定を保存できなかったため、Vanta は再実行されていません。再試行してください。詳細: { $error }
# Shown with the home-start-over button.
elevation-taken-over = 別の Vanta ウィンドウがこのセットアップを使用しているため、Vanta は再実行されていません。そのウィンドウで続行するか、「最初からやり直す」を選んでここでもう一度セットアップしてください。

## インストールの流れ

step-ready = 準備
step-options = 設定の選択
step-security = Windows セキュリティ
step-install = インストール
install-title = Vanta のセットアップ
# Accessible name of the row of steps.
stepper-label = Vanta セットアップの手順
# Accessible name of one step. $status is one of the stepper-status-* messages.
stepper-step-a11y = 手順 { $number }/{ $total }、{ $title }、{ $status }
stepper-status-completed = 完了
stepper-status-current = 現在の手順
stepper-status-upcoming = 今後の手順
stepper-status-attention = 要注意
# Heading above each step's content.
step-heading = 手順 { $number }/{ $total }: { $title }
# Accessible name of the step heading on a screen of Your choices, read when it takes focus.
# $heading is step-heading; $progress is options-progress; $question is the screen's question.
step-heading-choice-a11y = { $heading }。{ $progress }: { $question }
# The same on the optional extras screen; $progress is options-progress-extras.
step-heading-extras-a11y = { $heading }。{ $progress }

## 手順 1: 準備

ready-banner-busy-title = PC を準備しています
ready-banner-busy-message = Vanta が PC を確認し、インストール ファイルを準備しています。
ready-banner-blocked-title = PC の準備がまだできていません
ready-banner-blocked-message = 「PC の確認」で示された項目に対処してから、「もう一度確認」を選んでください。
ready-banner-no-package-title = 続行するには Vanta をダウンロードしてください
ready-banner-no-package-message = 「インストール ファイル」で Vanta をダウンロードするか、Vanta パッケージ (.vantapkg) をお持ちの場合は「パッケージ ファイルを開く」を選んでください。
# The package tried needs a newer Vanta Manager. The title is also the footer's hint then.
ready-banner-manager-title = 続行するには新しい Vanta Manager をダウンロードしてください
# "Download Vanta Manager" is manager-download, the button in Installation files (package-title).
ready-banner-manager-message = 「インストール ファイル」で「Vanta Manager をダウンロード」を選んでから、このバージョンの代わりに新しいバージョンを使ってください。
# Tester build: the bundled Vanta package couldn't be unpacked.
ready-banner-no-package-bundled-title = 続行するには同梱の Vanta パッケージを準備してください
ready-banner-no-package-bundled-message = このアプリに同梱された Vanta パッケージはまだ準備できていません。「インストール ファイル」カードを確認してください。
ready-banner-updates-title = 続行するには Windows と Store アプリを更新してください
ready-banner-updates-message = 「更新を確認してインストール」を選んでください。更新が終わると、Vanta が PC をもう一度確認します。
# While Windows and Store apps update. "Update Windows and Store apps" is prepare-title, the
# card further down the page.
ready-banner-updating-title = Windows と Store アプリを更新しています
ready-banner-updating-message = 時間がかかることがあります。Vanta を開いたままにしてください。進行状況は「Windows と Store アプリの更新」で確認できます。
# After Stop updating. "Check and install updates" is prepare-start, the card's button.
ready-banner-updates-stopped-title = 更新を停止しました
ready-banner-updates-stopped-message = 更新を完了するには、「Windows と Store アプリの更新」で「更新を確認してインストール」を選んでください。
# Vanta reopened after restarting the PC to continue updating. "Continue updates" is
# prepare-continue, the card's button.
ready-banner-updates-resumed-title = PC が再起動しました
ready-banner-updates-resumed-message = 更新を完了するには、「Windows と Store アプリの更新」で「更新を続ける」を選んでください。
# Under prepare-failed-title or prepare-unconfirmed-title. "Try again" is common-try-again,
# the card's button.
ready-banner-updates-failed-message = 「Windows と Store アプリの更新」で対処方法を確認してから、「再試行」を選んでください。
# Under prepare-reboot-title. "Restart and continue" is prepare-restart, the card's button.
ready-banner-reboot-message = 先に作業を保存してから、「Windows と Store アプリの更新」で「再起動して続行」を選んでください。
ready-banner-warnings-title = 確認しておきたい点があります
ready-banner-warnings-message = このまま続行できますが、先に「PC の確認」で示された項目を読んでください。
ready-banner-ok-title = 設定を選択する準備ができました
ready-banner-ok-message = 確認はすべて完了し、インストール ファイルの準備ができました。

# Card title and accessible name of the list of checks.
ready-this-pc = PC の確認
ready-check-again = もう一度確認
ready-checks-passed = { $count } 項目は問題ありません

package-title = インストール ファイル
# $received and $total are formatted numbers of megabytes (text).
package-downloading = Vanta { $version } をダウンロード中 · { $received } / { $total } MB
# Japanese has no plural forms; the same wording serves every count.
package-unpacking-progress = 展開中 · { $done } / { $total } ファイル
package-unpacking = 展開中
package-looking = 最新の Vanta バージョンを確認しています。
# Tester build: the bundled Vanta package is being unpacked, nothing is downloaded.
package-looking-bundled = 同梱の Vanta パッケージを準備しています。
package-none = Vanta をダウンロードして、インストール ファイルを入手してください。Vanta パッケージ (.vantapkg) をすでにお持ちの場合は、代わりにそれを開いてください。
# The GitHub release check failed. "最新バージョンをダウンロード" is package-download-newest,
# the button offered in this state; it checks again.
package-release-failed = Vanta は最新バージョンを確認できませんでした。インターネット接続を確認してから「最新バージョンをダウンロード」を選ぶか、保存済みの Vanta パッケージ (.vantapkg) を開いてください。
# Short status words beside the card title.
package-status-downloading = ダウンロード中
package-status-unpacking = 展開中
package-status-failed = 準備できませんでした
package-status-ready = 準備完了
package-status-checking = 確認中
package-status-preparing = 準備中
package-status-missing = 未ダウンロード
# Accessible name of the progress bar.
package-progress = インストール ファイルの進行状況
package-download-again = もう一度ダウンロード
package-download-version = Vanta { $version } をダウンロード
package-download-newest = 最新バージョンをダウンロード
package-cancel-download = ダウンロードをキャンセル
package-open-file = パッケージ ファイルを開く
# Where the package came from. $file is a file name, $path a folder path (text).
package-from-release = Vanta { $version } を GitHub からダウンロードしました。インストールの準備ができています。
package-from-file = Vanta { $version } を { $file } から読み込みました。インストールの準備ができています。
package-unpacked = Vanta { $version } のインストール準備ができています。
package-none-yet = インストール ファイルが選択されていません
acquire-no-asset = Vanta { $version } にはダウンロードできるパッケージ ファイルがありません。続行するには、保存済みの Vanta パッケージ (.vantapkg) を開いてください。
# Shown for a package older than Vanta 0.6.0, and for a file that isn't an Vanta package, such as an
# .apbx file from an Vanta release before 0.6.
acquire-unsupported = このアプリでインストールできるのは Vanta 0.6.0 以降の Vanta パッケージ (.vantapkg) です。
# A package new enough to include the installer script that this app drives, but without it.
acquire-incomplete = Vanta { $version } には、このアプリでのインストールに必要なファイルが含まれていません。もう一度ダウンロードするか、別の Vanta パッケージ (.vantapkg) を開いてください。
acquire-failed = インストール ファイルを準備できませんでした。もう一度ダウンロードするか、別の Vanta パッケージ (.vantapkg) を開いてください。詳細: { $error }
# The download received nothing for a minute and was stopped.
acquire-stalled = ダウンロードが応答しなくなりました。インターネット接続を確認してからもう一度ダウンロードするか、保存済みの Vanta パッケージ (.vantapkg) を開いてください。
# Tester build: the bundled Vanta package couldn't be unpacked. Try again is the only control offered.
acquire-failed-bundled = 同梱の Vanta パッケージを準備できませんでした。「再試行」を選んでください。詳細: { $error }
# The Vanta package asks for a newer Vanta Manager than this one. $version is the version it asks for,
# such as 0.7.0. "Download Vanta Manager" is manager-download, the button beside the message.
acquire-manager-outdated = この Vanta パッケージには Vanta Manager { $version } 以降が必要です。「Vanta Manager をダウンロード」を選んでから、このバージョンの代わりに新しいバージョンを使ってください。
# The same, for a package that doesn't say which version it needs.
acquire-manager-outdated-any = この Vanta パッケージには新しいバージョンの Vanta Manager が必要です。「Vanta Manager をダウンロード」を選んでから、このバージョンの代わりに新しいバージョンを使ってください。

## 新しい Vanta Manager

# Opens the latest Vanta release on GitHub in the browser, where Vanta Manager is downloaded.
manager-download = Vanta Manager をダウンロード
# A note on Home and in Settings that a newer Vanta Manager has been released. $version is its
# version, such as 0.7.0. The note doesn't stop anything; manager-download is its button.
manager-update-title = Vanta Manager { $version } が利用可能です
manager-update-message = Vanta Manager は自身を更新できません。新しいバージョンをダウンロードして、このバージョンの代わりに使ってください。

## システム チェック

check-administrator = インストールの権限
check-supported-build = Windows の互換性
check-pending-updates = Windows 更新プログラム
check-pending-reboot = 保留中の再起動
check-third-party-antivirus = 他のウイルス対策ソフト
check-internet = インターネット接続
check-power = 電源
check-activation = Windows のライセンス認証
# Accessible name of a check row. $state is one of the check-state-* messages.
check-a11y = { $title }: { $state }
check-state-checking = 確認中
check-state-passed = 問題なし
check-state-warning = 要注意
check-state-failed-blocking = インストール前に対処が必要
check-state-failed = 要注意
check-state-unknown = 確認できませんでした
check-fix-windows-update = Windows Update を開く
check-fix-network = ネットワーク設定を開く
check-fix-power = 電源設定を開く
check-fix-activation = ライセンス認証の設定を開く
check-fix-apps = インストールされているアプリを開く
# Check box the user ticks when the Windows Update scan could not run.
check-ack-updates = Windows Update で、インストール待ちの更新プログラムがないことを確認しました

detail-admin-ok = Vanta には、インストールに必要な変更を行う権限があります。
detail-admin-missing = Vanta を管理者として再実行し、Windows が許可を求めたら「はい」を選んでください。
# $builds is a list of build numbers such as "26100 または 26200"; $build is this PC's (text).
detail-build-unsupported = このバージョンの Vanta には Windows ビルド { $builds } が必要です。この PC のビルドは { $build } です。続行する前に、対応する Windows バージョンをインストールしてください。
detail-build-missing = この Vanta パッケージには、対応する Windows ビルドが記載されていません。LocalTest ビルドではなく、パッケージの完全なビルドを使用してください。
detail-updates-none = インストール待ちの Windows 更新プログラムはありません。
# $titles lists up to two update names (text); $count is the total.
detail-updates-pending =
    { $count ->
        [1] 次の更新プログラムがインストール待ちです: { $titles }。「Windows と Store アプリの更新」で Vanta がインストールします。
        [2] 次の { $count } 件の更新プログラムがインストール待ちです: { $titles }。「Windows と Store アプリの更新」で Vanta がインストールします。
       *[other] { $titles } など、{ $count } 件の更新プログラムがインストール待ちです。「Windows と Store アプリの更新」で Vanta がインストールします。
    }
detail-updates-unknown = Windows 更新プログラムを確認できませんでした。Windows Update を開き、インストール待ちの更新プログラムがなければ下でチェックを入れてください。 ({ $error })
detail-reboot-none = 現在、Windows の再起動は必要ありません。
detail-reboot-pending = 以前の変更を完了するため、Windows の再起動が必要です。「更新を確認してインストール」を選ぶと、まず再起動するよう Vanta が案内します。
# $reasons: the pending-restart markers Windows set, from the prepare-reason-* names.
detail-reboot-pending-reasons = 以前の変更を完了するため、Windows の再起動が必要です ({ $reasons })。「更新を確認してインストール」を選ぶと、まず再起動するよう Vanta が案内します。
# Warning, not a block: $files lists up to three file paths Windows will replace or remove at the next restart.
detail-reboot-file-renames = このまま続行できます。Windows には、次回の再起動時に置き換えまたは削除するファイルがあります ({ $files })。Xbox Gaming Services など一部のアプリは、再起動のたびにこの処理を予約します。
detail-reboot-unknown = Windows に再起動が必要かどうかを確認できませんでした。PC を再起動し、Vanta を開き直してからもう一度確認してください。 ({ $error })
detail-antivirus-none = 他のウイルス対策ソフトは検出されませんでした。
# $products is a list of product names (text).
detail-antivirus-found = Microsoft Defender 以外のウイルス対策アプリは、インストールを妨げることがあります。{ $products } をアンインストールしてから、「もう一度確認」を選んでください。
# Warning, not a block: Security Center still lists the product but its files are gone.
detail-antivirus-stale = Windows セキュリティには { $products } がまだ表示されていますが、そのファイルはすでに削除されているため、インストールされていない状態です。Vanta はこのままインストールできます。
detail-antivirus-unknown = 他のウイルス対策ソフトを確認できませんでした。「もう一度確認」を選んでください。失敗が続く場合は、PC を再起動してからもう一度確認してください。 ({ $error })
detail-internet-ok = インターネットに接続されています。Vanta がソフトウェアをダウンロードしてインストールする間、接続を維持してください。
detail-internet-missing = インターネットに接続してから、もう一度確認してください。
detail-power-mains = PC は電源に接続されています。インストールが終わるまで接続したままにしてください。
detail-power-battery = インストール中に電源が切れないよう、PC を電源に接続してください。
detail-power-unknown = PC が電源に接続されているかどうかを、Vanta は確認できませんでした。ノート PC の場合は電源に接続してから、「もう一度確認」を選んでください。この状態が続く場合は、「レポートを送信」を選んでください。
detail-activation-ok = Windows はライセンス認証されています。Vanta はこれを変更しません。
detail-activation-missing = Windows はライセンス認証されていません。続行できますが、Vanta が代わりにライセンス認証を行うことはありません。
detail-activation-no-licence = Windows からライセンス情報が報告されませんでした。続行できます。Vanta はライセンス認証の状態を変更しません。
detail-activation-unknown = Windows のライセンス認証を確認できませんでした。続行できます。Vanta はライセンス認証の状態を変更しません。 ({ $error })

## 手順 2: 設定の選択

options-progress = 選択 { $number }/{ $total }
options-progress-extras = 選択 { $number }/{ $total }: 追加オプション
options-change-later = Microsoft Defender、プロセッサの保護、更新の設定は、後からデスクトップの Vanta フォルダーで変更できます。
# Short names for each decision (summary rows) and the question each screen asks.
screen-defender-title = Microsoft Defender
screen-defender-question = Microsoft Defender を残しますか?
screen-mitigations-title = プロセッサの保護
screen-mitigations-question = Windows のプロセッサ保護を維持しますか?
screen-updates-title = Windows Update
screen-updates-question = 更新プログラムをどのようにインストールしますか?
screen-browser-title = ブラウザー
screen-power-title = 電源とセキュリティ
screen-apps-title = アプリ
screen-optional-apps-title = 任意のアプリ
screen-choose-one-title = オプションを選択
screen-extras-title = 追加オプション
# Question for a required choice this app has no specific wording for.
screen-generic-question = 「{ $title }」のオプションを選んでください
learn-more-defender = Microsoft Defender の詳細
learn-more-mitigations = プロセッサの保護の詳細
learn-more-updates = Windows Update の詳細
learn-more-browser = ブラウザーの詳細
learn-more-power = 電源とセキュリティの詳細
learn-more-apps = アプリの詳細
learn-more-eclean = eclean と Vanta の連携について
learn-more-generic = セットアップ ガイドを読む
# One line under the chosen answer: what it means for the PC.
consequence-defender-enable = Windows 標準のウイルス対策を残し、ウイルスなどの脅威から PC を保護します。
consequence-defender-disable = SmartScreen も削除します。別のウイルス対策アプリをインストールするまで、PC はウイルス対策による保護を受けられません。また、認識されないアプリやダウンロードしたファイルを開く前に、Windows が警告しなくなります。
consequence-mitigations-default = プロセッサの欠陥や、アプリのバグを悪用する攻撃に対する Windows の既定の保護を維持します。
consequence-mitigations-disable = 制御フロー ガードなど、アプリに対する Exploit Protection もオフにします。これによりセキュリティが低下します。パフォーマンスに差が出るかどうかは、プロセッサによって異なります。
consequence-auto-updates-disable = 定期的に Windows Update を開いて、更新プログラムをインストールしてください。更新の通知は引き続き表示されます。
consequence-auto-updates-default = Windows がセキュリティ修正を含む更新プログラムを自動的にインストールします。

## Vanta パッケージのテキスト
## Labels and descriptions for the Vanta package's options and choices, by
## their ids in the package's vanta.json. The app shows these in place of the
## package's own English text; an option or choice that a newer package adds,
## which has no message here, shows the package's English.

package-option-defender-enable = Microsoft Defender を残す
package-option-defender-disable = Microsoft Defender を削除する
package-option-mitigations-default = プロセッサの保護を維持する
package-option-mitigations-disable = プロセッサの保護をオフにする
package-option-auto-updates-disable = 更新プログラムを自分でインストールする
package-option-auto-updates-default = 更新プログラムを自動的にインストールする
package-option-disable-hibernation = 休止状態をオフにする

package-option-disable-phishing-protection = Turn off Enhanced Phishing Protection (Windows stops warning when you type your password into a known phishing site)
package-option-disable-gamebar = Turn off Game Bar and game capture
package-option-remove-store = Remove the Microsoft Store (App Installer and winget stay)
package-option-vanta-power = Use the Vanta power plan (desktop PCs only; skipped on laptops)
package-option-vanta-memory = Use the Vanta memory profile (memory compression on, page combining and app pre-launch off)
package-option-tools-on-logon = Open Vanta Tools the next time I sign in
package-option-disable-power-saving = 省電力機能をオフにする
package-option-disable-core-isolation = 仮想化ベースのセキュリティ (VBS) をオフにする
package-option-remove-snipping-tool = Snipping Tool を削除する
package-option-uninstall-edge = Microsoft Edge を削除する
package-option-install-another-browser = ブラウザーをインストールする
package-option-install-eclean = eclean をインストールする
package-option-browser-brave = Brave
package-option-browser-librewolf = LibreWolf
package-option-browser-firefox = Firefox
package-option-browser-chrome = Chrome
package-choice-defender-description = Microsoft Defender は Windows に組み込まれたウイルス対策です。削除するのは、リスクを理解したうえで、別のウイルス対策アプリを使う予定がある場合だけにしてください。どちらを選んでも、Vanta はスマート アプリ コントロール、拡張フィッシング保護、デバイスの検索をオフにします。

package-choice-protections-description = Windows protections that stay on unless you turn them off. Nothing here is turned off by default.
package-choice-vanta-description = Vanta extras. All are off unless you tick them.
package-choice-mitigations-description = これらの保護はセキュリティの軽減策とも呼ばれ、Spectre や Meltdown などのプロセッサの欠陥や、アプリのバグを悪用する攻撃から PC を守ります。Windows の既定のまま維持することをおすすめします。
package-choice-auto-updates-description = Vanta のインストール完了後に Windows が更新プログラムをインストールする方法を選択します（事前にこの PC を準備するステップ 1 とは異なります）。Windows に自動インストールさせるか、手動でインストールするかを選べます。どちらの場合も、Vanta は Windows を現在のバージョンに維持し、Microsoft のサポート終了までセキュリティ修正プログラムのみを受け取ります。また、Microsoft Store アプリの自動更新もオフになるため、Microsoft Store で更新してください。
package-choice-browser-description = インストールするブラウザーを選んでください。Vanta はブラウザーの設定を変更しません。

## 手順 3: Windows セキュリティ

security-banner-reading-title = Windows セキュリティを確認しています
security-banner-reading-message = Vanta が下の 4 つの保護スイッチを確認しています。
security-banner-off-title = 4 つの保護スイッチはすべてオフです
# Shown instead of the switch list when Microsoft Defender isn't on this PC and the user
# chose to remove it.
security-banner-absent-title = この PC に Microsoft Defender はインストールされていません
security-banner-absent-message = この手順でオフにするものはありません。「続行」を選んでください。
security-banner-off-message = 「続行」を選んで、セットアップ内容を確認し、Vanta をインストールしてください。
security-banner-on-title = Windows セキュリティでウイルス対策の保護をオフにしてください
security-banner-on-message = Microsoft Defender は、Vanta による変更をブロックすることがあります。「Windows セキュリティを開く」を選び、下に表示されているスイッチをそれぞれオフにしてください。Microsoft Defender を残す場合は、インストールが完了したらスイッチをオンに戻してください。
# The page name in Windows Security.
security-list-title = ウイルスと脅威の防止の設定
security-switch-off = オフ
security-switch-on = オン
security-switch-unreadable = 読み取れません
security-switch-reading = 確認中
security-all-off = すべてオフ
# Accessible name of a switch row. $state is one of the security-switch-* messages.
security-a11y = { $title }: { $state }
# Parts of the summary "2 個がまだオン、1 個が読み取れません".
security-count-still-on = { $count } 個がまだオン
security-count-unreadable = { $count } 個が読み取れません
security-count-join = { $a }、{ $b }
security-unknown-title = Vanta が読み取れなかったスイッチを確認してください
security-unknown-message = Windows セキュリティで 4 つのスイッチがすべてオフになっていることを確認してから、下でチェックを入れてください。
security-acknowledge = Windows セキュリティで、4 つのスイッチがすべてオフになっていることを確認しました
security-unknown-unelevated-title = 保護の確認には管理者権限が必要です
security-unknown-unelevated-message = Microsoft Defender の設定を確認できるよう、Vanta を管理者として再実行してください。
# The four switches, named as Windows Security names them in Japanese.
protection-tamper = 改ざん防止
protection-tamper-why = Vanta による Defender のセキュリティ設定の変更がブロックされないよう、オフにしてください。
protection-realtime = リアルタイム保護
protection-realtime-why = スキャン中に Defender が Vanta のインストール ファイルをブロックしないよう、オフにしてください。
protection-cloud = クラウド提供の保護
protection-cloud-why = オンラインの脅威チェックが Vanta のインストール ファイルをブロックしないよう、オフにしてください。
protection-samples = サンプルの自動送信
protection-samples-why = オフにすると、Defender が Vanta のファイルを分析のために Microsoft へ自動送信しなくなります。

## 手順 4: インストール

# Accessible name of the progress bar.
install-progress = インストールの進行状況
# The installation's progress shown beside the bar. $percent is a whole number from 0 to 99.
install-percent = { $percent }%
outcome-succeeded-title = Vanta がインストールされました
outcome-lost-title = インストール結果を確認できませんでした
outcome-failed-title = インストールが完了しませんでした
outcome-requirements = この PC はインストール要件を満たしていませんでした。インストールによる変更はありません。「準備」に戻って、もう一度確認を実行してください。
# The -resumed variants follow a retry of an installation an earlier attempt had already started applying.
outcome-requirements-resumed = この PC はインストール要件を満たしていなかったため、今回の試行は停止しました。以前の試行ですでに変更の適用が始まっています。「準備」に戻って、もう一度確認を実行してください。
outcome-not-elevated = Vanta に管理者権限がありませんでした。インストールによる変更はありません。Vanta を管理者として再実行してから、もう一度お試しください。
outcome-not-elevated-resumed = Vanta に管理者権限がなかったため、今回の試行は停止しました。以前の試行ですでに変更の適用が始まっています。Vanta を管理者として再実行してから、もう一度お試しください。
# The installer's live check found Windows or Store updates unfinished. Get ready offers the
# update check again; "更新を確認してインストール" is prepare-start, its button in that state.
outcome-preparation-stale = Windows と Store アプリが最新の状態であることを Vanta が確認できなかったため、Windows を変更する前にインストールを停止しました。「準備」に戻って「更新を確認してインストール」を選んでください。
outcome-preparation-stale-resumed = Windows と Store アプリが最新の状態であることを Vanta が確認できなかったため、今回の試行は停止しました。ただし、以前の試行ですでに変更の適用が始まっています。「準備」に戻って「更新を確認してインストール」を選んでください。
outcome-failed-preflight = 変更を加える前にインストールが停止しました。もう一度試すことができます。再び停止する場合は、「レポートを送信」を選んでください。
outcome-failed-staging = ファイルの準備中、Windows を変更する前にインストールが停止しました。もう一度試すことができます。再び停止する場合は、「レポートを送信」を選んでください。
outcome-failed-applying = 一部の変更はすでに適用されている可能性があります。もう一度試すことができます。ここで中止する場合は、オフにした保護のうちまだ利用できるものを Windows セキュリティでオンに戻してください。
outcome-failed-applying-defender-removed = 一部の変更はすでに適用されている可能性があります。もう一度試すことができます。インストールが再び停止する場合は、「レポートを送信」を選んでください。
outcome-failed-resumed = 今回の試行は途中で停止しましたが、以前の試行ですでに変更の適用が始まっています。もう一度試すことができます。ここで中止する場合は、オフにした保護のうちまだ利用できるものを Windows セキュリティでオンに戻してください。
outcome-failed-resumed-defender-removed = 今回の試行は途中で停止しましたが、以前の試行ですでに変更の適用が始まっています。もう一度試すことができます。インストールが再び停止する場合は、「レポートを送信」を選んでください。
outcome-failed-repeated = 今回の試行は前回と同じエラーで停止しました。一部の変更はすでに適用されている可能性があります。何も変えずにもう一度試しても解決する可能性は低いです。Vanta チームが原因を調べられるように、「レポートを送信」を選んでください。ここで中止する場合は、オフにした保護のうちまだ利用できるものを Windows セキュリティでオンに戻してください。
outcome-failed-repeated-defender-removed = 今回の試行は前回と同じエラーで停止しました。一部の変更はすでに適用されている可能性があります。何も変えずにもう一度試しても解決する可能性は低いです。Vanta チームが原因を調べられるように、「レポートを送信」を選んでください。
outcome-failed-repeated-apps = Windows が依然として { $apps } を削除しなかったため、今回の試行は前回と同じエラーで停止しました。一部の変更はすでに適用されている可能性があります。何も変えずにもう一度試しても解決する可能性は低いです。Vanta チームが原因を調べられるように、「レポートを送信」を選んでください。ここで中止する場合は、オフにした保護のうちまだ利用できるものを Windows セキュリティでオンに戻してください。
outcome-failed-repeated-apps-defender-removed = Windows が依然として { $apps } を削除しなかったため、今回の試行は前回と同じエラーで停止しました。一部の変更はすでに適用されている可能性があります。何も変えずにもう一度試しても解決する可能性は低いです。Vanta チームが原因を調べられるように、「レポートを送信」を選んでください。
outcome-not-started = インストーラーが時間内に起動しませんでした。インストールによる変更はありません。もう一度試すことができます。
outcome-lost = インストーラーは結果を報告せずに停止しました。一部の変更はすでに適用されている可能性があります。もう一度試すことができます。ここで中止する場合は、オフにした保護のうちまだ利用できるものを Windows セキュリティでオンに戻してください。
outcome-lost-defender-removed = インストーラーは結果を報告せずに停止しました。一部の変更はすでに適用されている可能性があります。もう一度試すことができます。再び停止する場合は、「レポートを送信」を選んでください。
restart-now-message = Vanta のセットアップを完了するため、Windows を再起動しています。
# Japanese has no plural forms; the same wording serves every count.
restart-countdown = Vanta のセットアップを完了するため、{ $seconds } 秒後に Windows を再起動します。先に作業を保存するには、「後で再起動」を選んでください。
restart-stopped = 自動再起動をキャンセルしました。作業を保存してから PC を再起動し、Vanta のセットアップを完了してください。
restart-needed = 作業を保存してから PC を再起動し、Vanta のセットアップを完了してください。
restart-dont-now = 後で再起動
restart-now = 今すぐ再起動
restart-start-failed = Vanta は PC を再起動できませんでした。作業を保存してから、スタート メニューから再起動してください。詳細: { $error }
preflight-title = インストールは開始されていません
preflight-invalid-options = 選択した設定を Vanta で使用できませんでした。「設定の選択」に戻って内容を確認し、再試行してください。詳細: { $error }
# $problems is a sentence or two built from preflight-problem and preflight-security.
preflight-changed = 前回の確認の後で PC の状態が変わりました。次の問題を解決してから再試行してください。{ $problems }
preflight-problem = { $title }: { $detail }
# $summary is the Windows Security summary such as "2 個がまだオン".
preflight-security = Windows セキュリティ: { $summary }。
preflight-busy = 別の Vanta ウィンドウがインストールを開始しています。少し待ってから、もう一度「Vanta をインストール」を選んでください。
# Shown with the home-start-over button.
preflight-taken-over = 別の Vanta ウィンドウがこのセットアップを使用しているため、インストールは開始されていません。そのウィンドウで続行するか、「最初からやり直す」を選んでここでもう一度セットアップしてください。
preflight-record-unreadable = 前回のインストールがまだ実行中かどうかを確認できなかったため、Vanta は新しいインストールを開始していません。「準備」に戻って、次に行うことを確認してください。詳細: { $error }
preflight-refused = インストーラーを起動できませんでした。インストールによる変更はありません。再試行するには「Vanta をインストール」を選んでください。問題が続く場合は、「レポートを送信」を選んでください。詳細: { $error }
# Instead of preflight-refused when retrying an installation an earlier attempt had already started applying.
preflight-refused-resumed = インストーラーを起動できなかったため、今回の試行は停止しました。以前の試行ですでに変更の適用が始まっています。再試行するには「Vanta をインストール」を選んでください。問題が続く場合は、「レポートを送信」を選んでください。詳細: { $error }
go-to-ready = 「準備」に戻る
go-to-options = 「設定の選択」に戻る
# Replaces Continue on a choice opened from a Change link on the Install step, while Continue leads straight back there.
go-to-install = 「インストール」に戻る
output-problem-title = インストールの進行状況を読み取れませんでした
output-problem-message = Vanta はログを読み取れませんでした。インストールが停止したとは限りません。PC の電源を切らずに、ログ ファイルを開いてみてください。詳細: { $error }
install-elevate-title = インストールには管理者権限が必要です
install-no-package-title = 先にインストール ファイルを選んでください
install-no-package-message = 「準備」に戻って Vanta をダウンロードするか、保存済みの Vanta パッケージ (.vantapkg) を開いてください。
# Tester build variant of install-no-package-message.
install-no-package-bundled-message = 「準備」に戻って、このアプリに同梱された Vanta パッケージを準備してください。
# Step 4 when step 1 is incomplete for this session (checks or Windows updates), with go-to-ready as the button.
install-not-ready-title = 先に「準備」を完了してください
install-not-ready-message = インストールを始める前に、Vanta が PC の確認と Windows の更新を完了する必要があります。
install-security-title = インストール前にウイルス対策の保護を確認してください
install-security-reading = 4 つの保護スイッチをもう一度確認しています。
install-security-message = { $summary }。インストールする前に、Windows セキュリティを開いて 4 つのスイッチがすべてオフになっていることを確認してください。
summary-try-again = 再試行前の確認
summary-ready = Vanta のセットアップ内容を確認
summary-activation = ライセンス認証
summary-activation-ok = ライセンス認証済み。Vanta はこれを変更しません。
summary-activation-missing = ライセンス認証されていません。続行できますが、Vanta が Windows のライセンス認証を行うことはありません。
summary-activation-unknown = Vanta は Windows のライセンス認証の状態を変更しません。
summary-duration = 推定時間
# Japanese has no plural forms; the same wording serves every count.
summary-duration-value = { $minutes } 分、その後に再起動
summary-restart-checkbox = インストール後に PC を自動的に再起動する
summary-show-command = インストール コマンドを表示
summary-hide-command = インストール コマンドを非表示
summary-copy-command-a11y = インストール コマンドをコピー
summary-command-unavailable = インストール コマンドを準備できませんでした。詳細: { $error }
summary-not-chosen = まだ選択されていません
# Accessible name of a Change link. $title is a screen-*-title message.
summary-change-a11y = { $title } を変更
footer-still-checking = インストールの準備中
footer-fix-items = 続行するには、「PC の確認」の項目に対処してください
footer-need-package = 続行するには、Vanta をダウンロードするか Vanta パッケージを開いてください
# Tester build variant of footer-need-package.
footer-need-package-bundled = 続行するには、同梱の Vanta パッケージを準備してください
footer-reading-security = 保護スイッチを確認中
footer-security-pending = 続行するには、4 つのスイッチをすべてオフにしてください
footer-security-confirm = 続行するには、Vanta が読み取れなかったスイッチを確認してください
footer-install-ready = 先に作業を保存し、アプリを閉じてください
button-install = Vanta をインストール
# Japanese has no plural forms; the same wording serves every count.
log-earlier-lines = これより前の { $count } 行はログ ファイルにあります。
# Appended when the log is copied. $path is a file path (text).
log-full-log-note = (完全なログ: { $path })

## インストール中の画面

installing-checking-title = 最終確認
installing-checking-line = 変更を加える前に、Vanta が PC を確認しています。少し時間がかかる場合があります。
installing-title = Vanta をインストールしています
installing-phase-preflight = PC を確認し、インストール ファイルを準備しています。
installing-phase-staging = インストール ファイルを準備しています。PC の電源を切らないでください。
installing-phase-applying = 選択した設定に従って Windows を設定しています。PC の電源を切らず、電源に接続したままにしてください。
installing-phase-done = インストールを完了しています。PC の電源を切らないでください。
installing-installed-title = Vanta がインストールされました
# $time is a formatted clock time.
installing-started-just-now = { $time } に開始 (経過 1 分未満)
# Japanese has no plural forms; the same wording serves every count.
installing-started-minutes = { $time } に開始 (経過 { $minutes } 分)
installing-restart-auto = インストールが完了すると、PC は自動的に再起動します。それまでに、他のアプリで作業中の内容を保存してください。

## 再起動後の「Vanta がインストールされました」ウィンドウ

installed-title-version = Vanta { $version } がインストールされました
installed-title = Vanta がインストールされました
installed-ready = セットアップが完了しました。Vanta を適用した PC をお使いいただけます。
installed-security-message = Microsoft Defender を残しましたが、その保護の一部がまだオフになっています。Windows セキュリティを開き、次の保護を必ずオンにしてください: { $switches }。
installed-defender-removed-title = Microsoft Defender は削除されました
installed-defender-removed-message = 別のウイルス対策アプリをインストールするまで、PC はウイルス対策による保護を受けられません。SmartScreen も削除されたため、認識されないアプリやダウンロードしたファイルを開く前に、Windows が警告することはありません。
# Home and the "Vanta is installed" window, after an installation that kept Microsoft Defender,
# when it is missing and no Vanta package removed it. Its title is security-banner-missing-title;
# "Report a problem" is home-report-problem, its button.
installed-defender-missing-message = Microsoft Defender を残すことを選びましたが、Defender が見つかりません。Vanta が削除したものではありません。他のウイルス対策アプリを使っていない場合は、ウイルス対策アプリをインストールして PC を保護してください。Defender をご自身で削除していない場合は、「問題を報告」を選んでください。

## 設定

settings-title = 設定
settings-theme = アプリのテーマ
settings-theme-system = Windows に合わせる
settings-theme-light = ライト
settings-theme-dark = ダーク
settings-theme-contrast-note = Vanta は Windows のコントラスト テーマの配色を使用しています。
settings-theme-mica-note = 半透明の背景を表示するには、Windows と同じライトまたはダークのテーマを選んでください。
settings-language = 言語
settings-language-system = Windows に合わせる
settings-language-system-selected = { settings-language-system } ({ $language })
# Under "Windows に合わせる": which language that gives. $language is a language's own name.
settings-language-system-detail = 「Windows に合わせる」の場合: { $language }
# A short tag under each language that is translated but not yet reviewed by a native speaker.
settings-language-preview-tag = プレビュー
# Under the language list, once, explaining the Preview tag.
settings-language-preview-note = プレビュー翻訳は、まだネイティブ スピーカーによるレビューを受けていません。
preview-notice = { $language }はプレビュー翻訳のため、誤りが含まれている可能性があります。
preview-notice-switch = 英語に切り替える
preview-notice-language = 言語を変更
# $tag is a language tag (text).
settings-language-unavailable = { $tag } はこのバージョンの Vanta では利用できません。現在は英語で表示しています。選択した言語は保存されています。
# $languages is the Windows display-language list (text).
settings-language-windows-unmatched = Vanta は Windows の表示言語 ({ $languages }) にまだ対応していません。現在は英語で表示しています。
settings-language-windows-unavailable = Windows の表示言語を確認できませんでした。現在は英語で表示しています。詳細: { $error }
# $locale is the regional format's own name, for example "日本語 (日本)".
settings-language-formats = 数値、日付、時刻は Windows の地域設定の形式 ({ $locale }) に従います。
# Instead of settings-language-formats when the regional format writes dates or times
# right to left. $locale is the format's English name, for example "Arabic (Saudi Arabia)".
settings-language-formats-numbers-only = 数値は Windows の地域設定の形式 ({ $locale }) に従います。Vanta はまだ右から左に書くテキストを表示できないため、日付と時刻には標準の形式を使用します。
settings-language-contribute = GitHub で Vanta の翻訳に協力する
settings-usage-analytics = 表示した画面、ISO の作成、インストール結果を Vanta と共有する
settings-restart-label = インストール後に PC を自動的に再起動する
settings-restart-locked = この設定はインストールが終わってから変更できます。
settings-restart-description = オンにすると、インストールの完了後 10 秒以内に PC が再起動し、開いているアプリはすべて閉じられます。インストールする前に作業を保存してください。
settings-help = ヘルプとフィードバック
settings-about = バージョン情報
settings-about-app = Vanta Manager
settings-about-version = バージョン
settings-about-licence = ライセンス
settings-about-licence-value = Vanta © コントリビューター、GPL-3.0
settings-about-gpl-link = GPL-3.0 ライセンスを読む
settings-about-based-on = ベース
settings-about-based-on-value = AtlasOS 0.6.0 (GPL-3.0) ベース
settings-about-atlas-link = GitHub の AtlasOS
settings-about-fonts = フォント
settings-about-fonts-value = Geist および Geist Mono (OFL-1.1、Vercel)
settings-about-fonts-link = Geist OFL-1.1 ライセンス
settings-about-source = ソースコード
# $version is the Vanta release version (text).
settings-about-source-value = 完全な対応ソースコードは各リリースに Vanta-{ $version }-source.zip および Vanta-{ $version }-third-party-sources.zip として同梱されています。
settings-about-source-link = GitHub リポジトリ
settings-about-releases-link = GitHub リリース
settings-about-network = ネットワーク
settings-about-network-value = Vanta は winget のマニフェストおよびリリース取得のためだけに api.github.com へ問い合わせを行い、個人データは送信しません。
# Link that opens the third-party licence notices.
settings-view-licences = THIRD-PARTY-NOTICES.txt を開く
# Under the links when Windows could not open the notices.
settings-licences-failed = THIRD-PARTY-NOTICES.txt を開けませんでした。再試行するか、ライセンス フォルダーで確認してください。
settings-open-data-folder = アプリのフォルダーを開く

## Optional choices: explanations shown before selection.

consequence-disable-hibernation = 休止状態でセッションを保存するために使うディスク領域を解放します。休止状態と高速スタートアップは使えなくなります。
consequence-disable-power-saving = 省電力機能をオフにします。消費電力や発熱が増え、バッテリー駆動時間が短くなる場合があります。
consequence-disable-core-isolation = メモリ整合性を含む、Windows の追加のセキュリティ層をオフにします。保護が弱まり、この機能を必要とするアプリやゲームに影響する場合があります。
consequence-remove-snipping-tool = スクリーンショットや画面録画に使う Windows のアプリを削除します。
consequence-uninstall-edge = Microsoft Edge ブラウザーを削除します。別のブラウザーがあることを確認するか、下で選んでください。
# Instead of consequence-uninstall-edge when Vanta is installed on this PC, which has the
# user's Edge data. "choose one below" refers to the browser choice under it.
consequence-uninstall-edge-data = Microsoft Edge と、この PC の Edge のお気に入り、履歴、保存したパスワードを削除します。Microsoft アカウントに同期されていないデータは失われます。別のブラウザーがあることを確認するか、下で選んでください。
# Under Remove Microsoft Edge in the Install step's summary, with a caution glyph.
caution-uninstall-edge = この PC の Edge のお気に入り、履歴、保存したパスワードを削除します。
consequence-install-another-browser = 下でブラウザーを選ぶと、Vanta がインストールします。
consequence-install-toolbox = Vanta Toolbox を追加すると、Vanta の設定を管理しやすくなります。Toolbox はベータ版のため、一部の機能は未完成の場合があります。
consequence-install-eclean = セットアップ後の PC を整える、Vanta 開発チームのメンテナンス ツールです。不要なファイルやスタートアップ アプリを確認できます。アカウントとインターネット接続が必要です。

# Introduction on the home page before Vanta is installed.
home-intro = Vanta は Windows を調整して、バックグラウンドの動作や気を散らす要素を減らします。Windows を新規インストールしたら、ご自身のアプリやファイルを追加する前に Vanta をインストールしてください。

## ISO creation
iso-home-title = Windows インストール メディア
iso-home-description = Vanta を含む Windows のインストール ファイル (ISO) を作成して、この PC や別の PC での Windows の再インストールに使用できます。
iso-open = Vanta ISO を作成
iso-title = Vanta ISO を作成
iso-recommended = おすすめ
iso-admin-description = Windows ISO を読み取って新しい ISO を作成するには、Vanta に管理者権限が必要です。「管理者として再実行」を選び、Windows で確認が表示されたら「はい」を選んでください。
iso-source = Windows ISO
iso-download-recommended = Microsoft からダウンロード（推奨）
iso-source-question = Windows はどこから入手しますか？
iso-use-local = ISO ファイルを選ぶ
iso-package-latest-label = 最新版
iso-package-latest = 最新の Vanta パッケージ
iso-package-unavailable = このバージョンの Manager に対応する Vanta パッケージを選んでください。
iso-save-name = 保存名：{ $name }
iso-source-download = Microsoft から Windows 11 をダウンロード
iso-download-arch = アーキテクチャ
iso-download-languages = 言語を読み込み中…
iso-download-list-error = Windows の言語を読み込めませんでした。もう一度試すか、Microsoft のサイトから ISO をダウンロードしてください。
iso-download-file-error = ISO を保存できませんでした。接続と空き容量を確認し、新しいファイル名でもう一度お試しください。
iso-download-website = Microsoft のダウンロードページを開く
iso-download-progress = Windows をダウンロード中 · { $total } 中 { $received }
iso-download-starting = Windows のダウンロードを準備中…
iso-output = 新しい ISO の保存先
iso-no-file = ファイル未選択
# Accessible name of the Browse or Save as button beside a file field: $action is
# that button's text and $field the field's label.
iso-pick-a11y = { $action }: { $field }
iso-inspect = ファイルを確認
iso-mode-title = Vanta をどのようにセットアップしますか?
iso-mode-interactive = サインイン後に Vanta の選択内容を決定
iso-mode-interactive-description = サインインすると Vanta が開き、更新、設定の選択、Vanta のインストールを順にご案内します。
iso-mode-before = Vanta の選択内容を今すぐ決定
iso-mode-before-description = Vanta は選択内容を ISO に保存します。サインインすると Vanta が開いて更新の手順を案内し、その後、この選択内容で Vanta をインストールできます。
iso-package-unsupported-title = 新しいバージョンの Vanta パッケージを選んでください
# "サインイン後に Vanta の選択内容を決定" is iso-mode-interactive.
iso-package-unsupported = この Vanta パッケージでは、Vanta の選択内容を ISO に保存できません。新しいバージョンのパッケージを選ぶか、「サインイン後に Vanta の選択内容を決定」を選んでください。
# Shown when Check files refuses the Vanta package; $minimum as for iso-package.
iso-failed-package-unsupported = この Vanta パッケージは ISO の作成に使用できません。Vanta { $minimum } 以降のパッケージを選んでください。
# Tester build: the bundled package cannot be swapped, so the only way on is the after-sign-in
# mode. Also the Your choices footer hint for any package that can't save choices.
iso-package-unsupported-bundled-title = この ISO には Vanta の選択内容を保存できません
# "サインイン後に Vanta の選択内容を決定" is iso-mode-interactive.
iso-package-unsupported-bundled = このアプリに同梱された Vanta パッケージは、ISO でのセットアップに対応していません。代わりに「サインイン後に Vanta の選択内容を決定」を選んでください。
iso-atlas-options = Vanta の選択内容
iso-review = ISO の内容を確認
iso-review-description = ISO を作成しても、この PC には何もインストールされず、元の ISO も変更されません。作成後は、Vanta で新しい ISO を USB ドライブに書き込み、その USB から Windows を再インストールできます。
iso-review-files = ファイル
iso-step-windows = Windows のセットアップ
iso-step-review = 確認
iso-review-package = Vanta パッケージ
iso-review-output = 新しい ISO
iso-review-editions = エディション
iso-edition = Windows エディション
iso-edition-auto = Windows セットアップ時に選択
iso-accept-terms = Windows のマイクロソフト ソフトウェア ライセンス条項に同意します
iso-architecture-x64 = x64
iso-architecture-arm64 = Arm64
# A file size; $size is a formatted number (text). Megabytes below a gigabyte.
size-megabytes = { $size } MB
size-gigabytes = { $size } GB
iso-review-account = アカウント名
iso-review-target = インストール先
iso-review-drivers = ドライバー
iso-create = ISO を作成
iso-progress-title = ISO を作成しています
iso-stage-inspect = Windows ISO を確認中
iso-stage-copy = Windows ファイルをコピー中
iso-stage-add-atlas = Vanta を追加中
iso-stage-master = ISO ファイルを書き込み中
iso-stage-verify = 新しい ISO を確認中
iso-stage-cleanup = 最終処理中
# Accessible name of one stage while the ISO is created. No "Step": the screen reader adds
# "4 of 6". $status is stepper-status-completed or one of the three below.
iso-stage-a11y = { $title }、{ $status }
iso-stage-status-current = 進行中
# The stage where creating the ISO stopped with an error.
iso-stage-status-failed = 失敗
iso-stage-status-not-started = 未開始
iso-progress-description = Vanta を開いたままにしてください。大きなイメージの処理には時間がかかる場合があります。
iso-cancel = 作成をキャンセル
iso-cancelling = 安全にキャンセルできる時点を待っています
iso-cancelled = ISO の作成をキャンセルしました
iso-cancelled-description = 元の ISO は変更されていません。一時ファイルが残っている場合は、「ログ フォルダーを開く」を選ぶと場所を確認できます。
iso-complete = ISO が完成しました
iso-complete-description = その後、「インストール USB を作成」を選び、Windows を再インストールする前にファイルをバックアップしてください。
iso-open-folder = フォルダーに表示
iso-failed = ISO の作成を完了できませんでした
iso-failed-description = ファイルが選択した場所にあり、保存先のドライブが接続されていることを確認してから、「ISO を作成」を選んでください。失敗が続く場合は、「レポートを送信」を選んでください。
# Title while the Check files step fails; the messages below say why.
iso-check-failed = ファイルを確認できませんでした
iso-check-failed-description = ISO と Vanta パッケージが選択した場所にあり、ダウンロードが完了していることを確認してから、「ファイルを確認」を選んでください。失敗が続く場合は、「レポートを送信」を選んでください。
# Title when Windows refused the administrator relaunch (UAC declined); elevation-declined is the message.
iso-elevation-title = ISO の作成には管理者権限が必要です
# Typed reasons reported by the image worker.
iso-failed-output-exists = 同じ名前のファイルがすでに存在します。「名前を付けて保存」を選んで、新しいファイル名を入力してください。
iso-failed-destination = その場所には新しい ISO を保存できません。「名前を付けて保存」を選び、「ダウンロード」など、この PC 上のフォルダーを選んでください。ネットワーク上の場所や、多くの USB ドライブのように FAT32 または exFAT でフォーマットされたドライブは使用できません。
iso-failed-space = 保存先ドライブの空き領域が不足しています。空き領域を確保するか、新しい ISO を別のドライブに保存してください。
# Home and LTSC are the editions ISO creation drops; the others are examples it keeps.
iso-failed-edition = この ISO には対応する Windows エディションが含まれていません。Windows Home と LTSC には対応していません。Pro、Education、Enterprise など、別のエディションを含む ISO を使用してください。
iso-failed-customised = この ISO には autounattend.xml などのカスタム セットアップ ファイルがすでに含まれています。Microsoft が提供する未変更の Windows ISO を選んでください。
iso-failed-windows-unsupported = この Windows イメージには、Vanta パッケージが対応していません。このパッケージが対応するバージョンの、未変更の 64 ビット版 Windows 11 ISO を使用してください。
iso-failed-network-architecture = この PC のネットワーク ドライバーは、この ISO のアーキテクチャと一致しません。前の画面に戻って「この PC のネットワーク ドライバーを含める」をオフにするか、この PC 用の ISO を選んでください。
iso-failed-unstaged = Vanta は作業フォルダーを準備できなかったため、何も変更されていません。もう一度お試しください。問題が続く場合は、「診断情報をエクスポート」を選んでバグ報告に添付してください。
iso-failed-package-changed = ファイルの確認後に Vanta パッケージが変更されました。「ファイル」の横にある「変更」を選んでから、「ファイルを確認」を選んでください。
iso-diagnostics = ログ フォルダーを開く
iso-close-title = ISO の作成はまだ実行中です
iso-close-message = 作成またはキャンセルが完了するまで、このウィンドウを開いたままにしてください。キャンセルは、現在の処理を安全に停止できる時点まで待機します。
# On the ISO and USB pages while Vanta updates Windows, or puts back Windows Update settings,
# from another page. Their controls are unavailable until it finishes.
iso-locked = Vanta は Windows Update の処理中です。完了すると、ここで続行できます。
prepare-title = Windows と Store アプリの更新
prepare-description = インストール前に、Vanta は Windows、Microsoft Store、Store アプリを更新します。メモ帳、ペイント、ターミナルなど、開いている Store アプリは更新中に終了することがあるため、先に作業内容を保存してください。PC の再起動が必要になることもあります。
prepare-complete = インストールする Windows と Store の更新プログラムは、もう見つかりませんでした。
prepare-reboot-title = 続行するには PC を再起動してください
prepare-reboot = 更新プログラムのインストールを完了するには、PC の再起動が必要です。Vanta はここまでの選択内容を保存し、サインイン後に再び開きます。
# $reasons: the pending-restart markers Windows set, from the prepare-reason-* names.
prepare-reboot-reasons = 更新プログラムのインストールを完了するには、PC の再起動が必要です ({ $reasons })。Vanta はここまでの選択内容を保存し、サインイン後に再び開きます。
# Under the restart message: the button restarts Windows without a countdown.
prepare-reboot-save-work = 先に作業を保存し、アプリを閉じてください。「再起動して続行」を選ぶと、PC はすぐに再起動します。
# Shown instead of another restart when Windows asks for one again right after restarting.
prepare-restart-persists = PC は再起動しましたが、Windows はまだ再起動が必要だと報告しています ({ $reasons })。もう一度再起動しても解決しない可能性が高いため、「Windows Update を開く」を選んで待機中の処理を完了してから、「再試行」を選んでください。何も待機していない場合は、「レポートを送信」を選んでください。
# Names of the markers Windows sets when it wants a restart. They complete
# "Windows の再起動が必要です (…)"; keep them short, noun-stop, in the half-width parentheses.
prepare-reason-servicing = Windows サービシング
prepare-reason-windows-update = Windows Update
prepare-reason-file-renames = 置き換え待ちのファイル
prepare-reason-update-agent = Windows Update サービス
prepare-reason-unknown = 理由の報告なし
prepare-failed = 「再試行」を選んでください。再び失敗する場合は、Windows Update または Microsoft Store で残りの更新を完了するか、「レポートを送信」を選んでください。
prepare-failed-title = 一部の更新を完了できませんでした
# The update run ended without writing any result, for example after Vanta was closed
# while it ran. "再試行" is common-try-again, the button beside it.
prepare-ended-unconfirmed = 更新が結果を報告する前に停止したため、Windows と Store アプリが最新の状態であることを Vanta は確認できません。「再試行」を選んで、更新を確認してください。
prepare-unconfirmed-title = 更新の結果を確認できませんでした
# "更新を確認してインストール" is prepare-start, its button in this state.
prepare-cancelled = 更新を停止しました。一部の更新プログラムはすでにインストールされている可能性があります。続行する前に、「更新を確認してインストール」を選んで更新を完了してください。
prepare-windows-search = Windows の更新を確認しています…
prepare-windows-download = Windows の更新プログラムをダウンロードしています…
prepare-windows-install = Windows の更新プログラムをインストールしています…
prepare-windows-repair = 先に Windows を修復しています。更新プログラムのインストールを妨げる可能性のある破損があると Windows が報告しています。30 分以上かかることがあります。
prepare-store-search = Microsoft Store を確認しています…
prepare-store-install = Microsoft Store とアプリを更新しています…
prepare-stop-description = 現在の手順が完了すると、Vanta は更新を停止します。それまで Vanta を開いたままにしてください。
prepare-stop = 更新を停止
prepare-restart = 再起動して続行
prepare-start = 更新を確認してインストール
# Under the preparation button while it is unavailable. $check is the check-supported-build title.
prepare-blocked-source = このインストールは続行できないため、利用できません。ページ上部のメッセージを確認してください。
prepare-needs-build-check = 「PC の確認」で「{ $check }」に問題がなければ利用できます。
# Under the preparation button, and under the Administrator check, while the installation files are still downloading or unpacking.
prepare-wait-for-package = インストール ファイルの準備ができると利用できます。
iso-username = ローカル アカウント名
iso-account-description = Windows のセットアップでこの名前のローカル アカウントが作成されるため、Microsoft アカウントは必要ありません。初めてサインインするときに、Windows からパスワードの設定を求められます。
iso-username-placeholder = お名前
iso-account-empty = 続行するには、ローカル アカウント名を入力してください
iso-account-invalid = 20 文字以内で入力してください。先頭と末尾には空白を使えません。また、次の記号は使えません: " / \ [ ] : ; | = , + * ? < > @
iso-account-trailing-dot = 名前の末尾にピリオド (.) は使用できません。
iso-account-reserved = この名前は Windows の組み込みアカウントで使用されています。別の名前を入力してください。
iso-terms-in-setup = Windows セットアップでライセンス条項への同意を求められます。
iso-privacy-defaults = この ISO では、Windows のセットアップのMicrosoft アカウント、プライバシーの画面が省略され、任意のデータ共有と個人向けのおすすめがオフになります。
prepare-drivers = ドライバーのインストール方法
prepare-drivers-auto = Windows Update から取得する
prepare-drivers-auto-detail = Windows がハードウェアに適したドライバーを探します。通常はこちらをおすすめします。
prepare-drivers-manual = 自分でインストールする
prepare-drivers-manual-detail = Windows Update はドライバーをインストールしなくなるため、PC やデバイスのメーカーから入手する必要があります。インストール済みのドライバーは保持されます。
prepare-drivers-description = ドライバーは、グラフィックス、サウンド、Wi-Fi などのハードウェアを Windows で使えるようにするものです。更新後にこの設定を変更した場合は、Vanta がもう一度更新を確認する必要があります。
prepare-network-needed = 更新には、従量制課金接続ではないインターネット接続が必要です。Wi-Fi またはイーサネットに接続してから、「再試行」を選んでください。Wi-Fi ネットワークが表示されない場合は、先にネットワーク ドライバーをインストールしてください。
# Connected, but Windows found no internet access (a captive portal, or DNS or firewall filtering).
prepare-network-limited = Windows の報告によると、このネットワークはインターネットに接続できません。ネットワークからサインインを求められた場合はサインインするか、ルーターのほか、DNS やファイアウォールによるフィルタリングも確認してから、再試行してください。
# "従量制課金接続" is the switch's name in Windows network settings.
prepare-network-metered = この接続は従量制課金接続に設定されているか、データ使用量の上限が設定されています。従量制課金接続ではないネットワークに接続するか、ネットワーク設定で「従量制課金接続」をオフにしてから、再試行してください。
prepare-network-settings = ネットワーク設定を開く
iso-target-title = どの PC に Windows を再インストールしますか?
iso-target-this = この PC
# Under This PC (iso-target-this), before it's chosen.
iso-target-this-description = Vanta は、この PC の Wi-Fi とイーサネットのドライバーを ISO に追加できます。これにより、Windows を再インストールした直後からインターネットに接続できます。
iso-target-other = 別の PC
iso-copy-network = この PC のネットワーク ドライバーを含める
iso-network-detail = Windows のインストール時に、この PC の Wi-Fi とイーサネットのドライバーを再利用します。再インストール後は Wi-Fi に接続し直してください。
iso-network-source = ネットワーク ドライバーの取得元
iso-network-installed = インストール済みのドライバーを使う
iso-network-updated = 先に Windows Update で確認する
iso-network-updated-detail = Windows Update が提供する適合ドライバーをダウンロードし、インストール済みのドライバーも予備として保持します。従量制課金ではない接続が必要です。
iso-stage-network-drivers = ネットワーク ドライバーを準備中
iso-network-failed = ネットワーク ドライバーを準備できませんでした。診断情報を確認するか、前の画面に戻ってネットワーク ドライバーの設定を変更してください。
# Under iso-complete when Include this PC's network drivers was chosen but the adapters use
# drivers that come with Windows, so none were added.
iso-network-inbox = この PC のネットワーク アダプターは Windows 付属のドライバーを使用しているため、ISO に含める必要はありません。
iso-mode-desktop = デスクトップを開く前にセットアップを完了
iso-mode-desktop-description = Vanta は選択内容を ISO に保存します。サインイン後、Windows デスクトップが開く前に、Vanta が更新とインストールを完了します。
desktop-setup-description = PC のセットアップを完了しましょう。Vanta の選択内容は保存されています。必要に応じて Windows に戻れます。
desktop-setup-exit = Windows で続ける

# Windows installation USB
usb-title = インストール USB を作成
usb-existing = 既存の ISO から USB を作成
usb-description = ISO を USB ドライブに書き込んで、その USB から Windows を再インストールできるようにします。Vanta も同時にインストールするには、Vanta で作成した ISO を使用してください。
# Button that opens the file picker for an ISO, and the Open button of that picker, on the USB
# and ISO pages.
usb-choose-iso = ISO を選択
usb-drive = USB ドライブ
# $min and $max are formatted numbers (text), in gigabytes and terabytes.
usb-empty = USB ドライブが見つかりません。{ $min } GB 以上の USB ドライブを接続してから、「一覧を更新」を選んでください。{ $max } TB を超えるドライブ、読み取り専用のドライブ、実行中の Windows があるドライブは表示されません。
usb-refresh = 一覧を更新
# Shown when the drive list could not be read.
usb-scan-failed = ドライブが接続されていることを確認してから、「一覧を更新」を選んでください。詳細を確認するには、「ログ フォルダーを開く」を選んでください。
usb-scan-failed-title = USB ドライブの一覧を取得できませんでした
# Parts of a drive's detail line, joined by usb-detail-separator; empty parts are left out.
# $size is a formatted number of gigabytes (text); $volumes and $serial are text.
usb-drive-size = { $size } GB
usb-drive-serial = シリアル番号: { $serial }
usb-detail-separator = { " · " }
usb-review = USB を確認
usb-erase-title = この USB ドライブを消去しますか?
usb-erase-description = { $drive } ({ $size } GB) の内容は、すべてのファイルとパーティションを含め、完全に消去されます。残しておきたいものは、先に別のドライブにコピーしてください。ISO ファイルは保持されます。
usb-layout = Vanta はドライブの最大 32 GB を使用し、残りの領域は使用しません。この USB ドライブは、Windows 11 に必要な UEFI モードで起動する PC で使用できます。
usb-ack = この USB ドライブの内容がすべて消去されることを理解しました
usb-write = 消去して USB を作成
usb-stage-prepare = インストール ファイルを準備しています…
usb-stage-format = USB をフォーマットしています…
usb-stage-copy = インストール ファイルをコピーしています…
usb-stage-verify = USB を検証しています…
usb-working = Vanta を開いたまま、USB ドライブを接続しておいてください。キャンセルすると、作成途中の USB ドライブは Windows のインストールに使用できません。
# Titles of the error bar, the success bar and the close prompt while a USB is being written.
usb-failed-title = USB の作成を完了できませんでした
usb-complete-title = USB の準備ができました
usb-close-title = USB の作成はまだ実行中です
# After erasing may have begun.
usb-failed = ドライブはすでに消去されている可能性があるため、まだ Windows のインストールには使用できません。ドライブが接続されていることを確認してから、「USB を確認」を選んで再試行してください。接続し直した場合は、先に「一覧を更新」を選んでドライブを選択し直してください。
# Before anything on the drive was changed: in general, then for the reasons the writer reports.
usb-failed-unchanged = USB ドライブは変更されていません。「ログ フォルダーを開く」を選んで原因を確認してから、「USB を確認」を選んで再試行してください。
usb-failed-iso = この ISO はインストール USB の作成に使用できません。Vanta で作成した ISO か、Vanta が対応するバージョンの Microsoft 提供の Windows 11 ISO を選んでください。USB ドライブは変更されていません。
usb-failed-location = ISO または Vanta Manager が、この USB ドライブ、ネットワーク上の場所、またはリンクされたフォルダーにあります。そのファイルをこの PC のローカル フォルダーに移動してから、再試行してください。USB ドライブは変更されていません。
usb-failed-space = Windows ドライブの空き領域が不足しているため、インストール ファイルを準備できません。空き領域を確保してから、再試行してください。USB ドライブは変更されていません。
usb-failed-fit = インストール ファイルがこの USB ドライブに収まりません。容量の大きいドライブを使用して、再試行してください。USB ドライブは変更されていません。
usb-failed-drive-changed = 一覧を読み取った後に、USB ドライブが取り外されたか、接続し直されたか、別のドライブに交換されました。「一覧を更新」を選んでドライブを選択し直してから、「USB を確認」を選んでください。USB ドライブは変更されていません。
usb-cancelled = ドライブに不完全なインストール ファイルが残っている可能性があります。Windows のインストール前に作成し直してください。
usb-cancelled-title = USB の作成をキャンセルしました
usb-cancelled-unchanged = USB ドライブは変更されていません。
usb-complete = Vanta がすべてのファイルを確認しました。「USB を取り出す」を選んでから、再インストールする PC のファイルをバックアップしてください。その PC にドライブを接続し、ブート メニューを使って USB ドライブから起動してください (多くの場合、PC の起動時に F12、F11、Esc のいずれかのキーで表示できます)。
usb-eject = USB を取り出す
usb-ejected = USB ドライブを取り外せるようになりました。再インストールする PC のファイルをバックアップしてください。その後、ブート メニューを使って、その PC を USB ドライブから起動してください (多くの場合、起動時に F12、F11、Esc のいずれかのキーで表示できます)。
usb-eject-failed = USB を使用しているファイルやウィンドウを閉じてから、もう一度お試しください。
usb-eject-failed-title = USB を取り出せませんでした
ready-fresh-title = Vanta は新規インストールした Windows 向けです
ready-fresh-description = この PC の Windows をすでに使用している場合は、続行する前にファイルをバックアップして Windows を再インストールしてください。対応するバージョンを再インストールできるよう、先に「PC の確認」で「Windows の互換性」に問題がないことを確認してください。
# Home, LTSC and Server are the editions the check refuses; the others are examples of
# editions it accepts. Keep edition names as Windows shows them.
detail-edition-unsupported = Windows 11 の Home、LTSC、Server エディションには対応していません。Pro、Education、Enterprise など、別のエディションを使用してください。Windows がエディションを識別できなかった場合は、続行する前に問題を解決してください。
install-source-title = インストールできません
install-source-unsupported = Vanta { $source } から { $target } へ直接更新することはできません。このバージョンを使用するには、ファイルをバックアップしてから Windows を再インストールしてください。
# Before a package is chosen, so the version on offer isn't known yet.
install-source-unsupported-any = Vanta { $source } から直接更新することはできません。新しいバージョンを使用するには、ファイルをバックアップしてから Windows を再インストールしてください。
# "パッケージ ファイルを開く" is package-open-file. $folder is a folder path (text).
install-source-resume = Vanta { $target } のインストールが完了していません。このインストールを完了できるのは Vanta { $target } のパッケージだけです。「パッケージ ファイルを開く」を選び、その Vanta パッケージ (.vantapkg) を選択してください。Vanta がダウンロードした場合は、{ $folder } にあります。
# Tester build: only the bundled Vanta package can be installed.
install-source-resume-bundled = Vanta { $target } のインストールが完了していません。このテスト ビルドは同梱の Vanta パッケージしかインストールできないため、Vanta Manager のリリース ビルドで Vanta { $target } のパッケージを使用して、このインストールを完了してください。
install-source-unknown = この PC に何がインストールされているかを Vanta が確認できなかったため、今はインストールを行いません。Vanta チームが対応できるよう、「レポートを送信」を選んでください。
# $problem is one of the install-source-* messages; $error is a raw error message (text).
install-source-details = { $problem }詳細: { $error }
iso-edition-selection = 対応するエディションのみが含まれます。Windows のセットアップでは、Windows ライセンスをお持ちのエディションを選択してください。
detail-windows-preview = Insider ビルドには対応していません。Windows 11 の一般公開版を使用してください。
detail-windows-release-unknown = この Windows ビルドが一般公開版かどうかを確認できませんでした。インターネットに接続して、もう一度確認してください。
# $build is this PC's Windows build and update number, such as 26300.9807 (text).
detail-windows-release-unlisted = ビルド { $build } は Microsoft の Windows 11 一般公開版の一覧に含まれていないため、Vanta はまだこのビルドにインストールできません。Release Preview ビルドやその他のプレビュー ビルドには対応していません。Microsoft がこのビルドを一覧に追加したら、「もう一度確認」を選んでください。
iso-release-unknown = この ISO が、Vanta パッケージが対応する Windows 11 の一般公開版であることを Vanta は確認できませんでした。インターネットに接続してから、もう一度「ファイルを確認」を選んでください。それでも失敗する場合は、Microsoft から ISO をダウンロードし直してください。
iso-release-unlisted = この ISO の Windows 11 ビルドは、Microsoft の一般公開版の一覧に含まれていません。Release Preview ビルドやその他のプレビュー ビルドには対応していません。Microsoft から ISO をダウンロードするか、Microsoft がこのビルドを一覧に追加してから、もう一度「ファイルを確認」を選んでください。
prepare-previous-worker = 以前に開始した更新がまだ実行中です。Vanta は完了するまで待機します。完了後に、もう一度更新を確認できます。

ready-used-windows-title = この PC の Windows はすでに使用されているようです
ready-used-windows-description = この PC の Windows は、インストールから 1 週間以上経過しているか、すでに複数のアプリが入っています。この状態での Vanta のインストールはサポート対象外で、行わないことを強くおすすめします。既存のアプリや設定が正しく動作しなくなる可能性があります。また、Vanta は OneDrive を削除するため、OneDrive 内のファイルは同期されなくなり、デスクトップ、ドキュメント、ピクチャのフォルダーが空に見える場合があります。先にファイルをバックアップして Windows を再インストールするか、リスクを受け入れる場合にのみ続行してください。
ready-used-windows-dismiss = このまま続行

prepare-resumed = PC が再起動し、Vanta はここまでの選択内容を復元しました。Vanta をインストールする前に、「更新を続ける」を選んで更新を完了してください。
prepare-continue = 更新を続ける
prepare-saving-restart = 選択内容を保存し、Windows の再起動後に Vanta を開くよう設定しています…
prepare-restart-save-failed = 選択内容を保存できませんでした。再起動する前にもう一度お試しください。
prepare-restart-registration-failed = 選択内容は保存されましたが、再起動後に Vanta が自動で開くよう設定できませんでした。もう一度試すか、ご自身で PC を再起動し、サインイン後に Vanta を開いてください。
prepare-restart-source-linked = 選択内容は保存されましたが、Vanta Manager がリンクされたフォルダーにある間は、再起動後に Vanta が自動で開くよう設定できません。Vanta を閉じ、Vanta Manager をこの PC のローカル フォルダーに移動してください。その後、そこから開くか、ご自身で PC を再起動し、サインイン後にそこから開いてください。
prepare-restart-failed = Vanta は PC を再起動できませんでした。もう一度試すか、スタート メニューから再起動してください。選択内容は保存されており、サインイン後に Vanta が再び開きます。
diagnostics-export = 診断情報をエクスポート
diagnostics-exporting = 診断情報を収集中…
diagnostics-privacy = Vanta チームに非公開でレポートを送信するか、助けを求めるときに共有できる診断情報の ZIP をエクスポートできます。Vanta は、ZIP からユーザー名、PC 名、メール アドレスを削除します。
# Title of the result bar after an export; its button is iso-open-folder.
diagnostics-saved = 診断情報の ZIP を作成しました
diagnostics-failed-title = 診断情報をエクスポートできませんでした
# $error is the raw error (text).
diagnostics-failed = PC のディスクに空き領域があることを確認してから、再試行してください。詳細: { $error }

## Tester builds (embedded-package feature)

# One line of chrome under the title bar on a release-candidate build.
rc-banner = Vanta { $release } テスト ビルド。このアプリは同梱の Vanta パッケージのみをインストールします。
home-status-bundled = テスト ビルド { $release }
home-status-ready = インストール可能
package-bundled = このアプリに同梱された Vanta { $version } のインストール準備ができています。
rc-about-release = テスト ビルド
rc-about-commit = ソース コミット
rc-about-package = 同梱の Vanta パッケージ (SHA-256)
iso-package-bundled = このアプリに同梱された Vanta パッケージ
prepare-percent = この段階の { $percent }% が完了
prepare-count = 完了した更新: { $completed } / { $total }
prepare-bytes = 約 { $total } MB 中 { $downloaded } MB をダウンロード済み
prepare-elapsed = 経過時間: { $minutes } 分 { $seconds } 秒
prepare-progress-waiting = 更新サービスを待っています。この手順では進捗率を取得できません。
prepare-progress-unchanged = { $minutes } 分間、進捗がありません。大きな更新には時間がかかることがあるため、Vanta を開いたままにしてください。詳細を確認するには、「ログ フォルダーを開く」を選んでください。
prepare-report-delayed = { $seconds } 秒間、Windows から進捗が報告されていません。更新はまだ実行中の可能性があるため、Vanta を開いたままにしてください。

prepare-affected-app = 対象のアプリ
prepare-app-in-use = { $app } を閉じてから、再試行してください。開いている間は、Windows がこのアプリを更新できません。ウィンドウが見つからない場合は、タスク マネージャーで終了してください。それでも失敗する場合は、PC を再起動し、{ $app } を開く前に再試行してください。
prepare-install-busy = 別のインストールまたは必要な再起動により、更新がブロックされています。他のインストールが終わるのを待ち、Windows から再起動を求められた場合は PC を再起動してから、再試行してください。
prepare-failed-component-store = Windows のコンポーネント ストアに更新プログラムのインストールを妨げる破損があると Windows が報告しており、Vanta では修復できませんでした。PC を再起動してから、「再試行」を選んでください。それでも更新に失敗する場合は、ファイルをバックアップしてから、Vanta ISO で Windows を再インストールしてください。
prepare-failed-component-store-unrepairable = Windows のコンポーネント ストアに修復できない破損があると Windows が報告しているため、更新プログラムをインストールできません。ファイルをバックアップしてから、Vanta ISO で Windows を再インストールしてください。
# Causes the update worker names. The worker's own English message is shown below as a detail.
prepare-failed-session-owner = Vanta は、Windows にサインインしているアカウントとは別のアカウントで実行されています。管理者アカウントで Windows にサインインし、そのアカウントから Vanta を開いてから、再試行してください。
prepare-failed-store-missing = お使いのアカウントでは Microsoft Store がセットアップされていません。Microsoft Store を一度開くか、見つからない場合は再インストールしてから、再試行してください。
prepare-failed-store-battery = バッテリーを節約するため、Microsoft Store が更新を一時停止しました。PC を電源に接続してから、再試行してください。
prepare-failed-store-network = PC が従量制課金接続ではないネットワークに接続されるまで、Microsoft Store は更新を一時停止しています。従量制課金接続ではない Wi-Fi またはイーサネットに接続してから、再試行してください。
prepare-failed-store-timeout = Store アプリの更新が完了していません。Microsoft Store で残りのダウンロードを完了してから、再試行してください。
prepare-failed-store-passes = Microsoft Store から新しい更新プログラムが提供され続けました。Microsoft Store で残りの更新を完了してから、再試行してください。
prepare-failed-manual-updates = 一部の Windows 更新プログラムは Windows Update で完了する必要があります。Windows Update を開いて完了してから、再試行してください。
prepare-failed-windows-passes = Windows Update から新しい更新プログラムが提供され続けました。Windows Update で残りの更新を完了してから、再試行してください。
prepare-failed-source-linked = Vanta Manager がリンクされたフォルダーにあります。Vanta を閉じ、Vanta Manager をこの PC のローカル フォルダーに移動してから、そこから開いてください。
prepare-error-code = エラー コード: { $code }
prepare-open-store = Microsoft Store を開く

check-user-account = ユーザー アカウント
detail-user-account-ok = UAC が有効で、アカウントのインストール準備が整っています。
detail-user-account-not-ready = ユーザー アカウント制御 (UAC) を有効にし、PC を再起動してから、もう一度お試しください。組み込みの Administrator アカウントを使用している場合は、別の管理者アカウントでサインインしてください。
detail-user-account-work-or-school = 職場または学校アカウント (Microsoft Entra ID) からは Vanta をインストールできません。ローカル アカウントまたは Microsoft アカウントでサインインしてから、再試行してください。
detail-user-account-unknown = Vanta はユーザー アカウントを確認できませんでした。PC を再起動し、Vanta を開き直してからもう一度確認してください。この状態が続く場合は、「レポートを送信」を選んでください。Windows の報告: { $error }

footer-prepare-required = 続行するには、Windows と Store アプリの更新を完了してください
footer-prepare-stopping = 現在の手順の完了後に更新を停止します…
resume-choices-title = 前回のインストールを再開
resume-choices-detail = 前回のインストールを完了するため、Vanta は前回の選択内容を復元しました。インストールが完了するまで、「設定の選択」でこれらを変更することはできません。

## Voluntary reports
report-title = レポートを送信
report-received = レポートを受信しました
report-reference = このレポートについて Vanta チームに問い合わせる場合に備えて、この参照番号を控えておいてください。連絡先を入力した場合はチームから返信することがありますが、返信は保証されません。
# Accessible name of the Copy button beside the report reference.
report-copy-reference = 参照番号をコピー
report-another = 別のレポートを送信
# Label of the choice between the two kinds of report.
report-kind = 何を送信しますか?
report-kind-issue = 問題
report-kind-suggestion = 提案
# $min and $max are numbers: the message lengths the report service accepts.
report-intro = 何が起きたか、または何を変えてほしいかを記入してください ({ $min }～{ $max } 文字)。メッセージにパスワードを含めないでください。
report-message = メッセージ
report-message-placeholder = 次の操作をしようとしました…
report-contact = 連絡先 (任意)
report-contact-placeholder = メール アドレスまたは Discord ユーザー名
report-attach = 診断情報を添付
report-attach-description = 原因の特定に役立つログとシステムの詳細情報です。Vanta は、ユーザー名、PC 名、メール アドレス、既知のパスワードやキーを削除します。エラーの詳細、ハードウェアのモデル、アプリ名は残ります。送信前に ZIP の内容を確認できます。
report-prepare = 診断情報を準備
report-review = ZIP を確認
report-prepare-failed-title = 診断情報を準備できませんでした
# $error is a raw error message (text).
report-prepare-failed = 診断情報をもう一度準備するか、「診断情報を添付」をオフにして、診断情報なしでレポートを送信してください。詳細: { $error }
report-privacy = Vanta Manager does not send reports: nothing leaves this PC. Your message and diagnostics stay here.
report-consent = このレポートと添付した診断情報を Vanta チームに送信することに同意します
report-failed = メッセージは保持されています。インターネット接続を確認してから「再試行」を選ぶか、レポート サイトからレポートを送信してください。
report-failed-busy = レポート サービスが混み合っています。メッセージは保持されています。しばらくしてから再試行してください。
report-failed-outdated = このバージョンの Vanta Manager ではレポートを送信できなくなりました。メッセージは保持されているので、レポート サイトにコピーしてください。診断情報を添付していた場合は、「ZIP を確認」を選び、その ZIP もレポート サイトで添付してください。
report-failed-diagnostics = 準備した診断情報を送信できません。メッセージは保持されています。診断情報をもう一度準備するか、「診断情報を添付」をオフにしてください。
# Link under a report that wasn't sent.
report-sending = 送信中…
report-send = レポートを送信

# $min and $max are numbers: the message lengths the report service accepts.
report-validation-message = { $min }～{ $max } 文字で入力してください。

# $max is a number: the longest contact details the report service accepts.
report-validation-contact = 連絡先は { $max } 文字以内で入力してください。

report-validation-consent = このレポートの送信に同意してください。

report-failed-title = レポートを送信できませんでした

## Windows version update
home-plan-intro = この更新は 2 段階で行われます。ファイルとアプリはそのまま残ります。Windows の更新によって Vanta の変更が元に戻された場合は、Vanta が適用し直します。
home-plan-windows-title = Windows 11 バージョン { $release }
home-plan-windows-detail = Vanta が Windows Update からインストールします。インストールを完了するため、PC が再起動します。
home-plan-windows-optional = 推奨。Vanta が Windows Update からインストールします。インストールを完了するため、PC が再起動します。
home-plan-atlas-title = Vanta { $version }
home-plan-atlas-detail = Vanta がファイルを更新し、選択内容はそのまま引き継ぎます。最後に PC が再起動します。
home-end-of-updates-title = Windows 11 バージョン { $current } のセキュリティ更新プログラムの提供は { $date } に終了します
home-end-of-updates-past-title = Windows 11 バージョン { $current } のセキュリティ更新プログラムの提供は終了しました
home-end-of-updates-message = Vanta { $version } に更新すると、この PC は Windows 11 バージョン { $release } にも移行します。このバージョンには { $until } までセキュリティ更新プログラムが提供されます。
install-windows-edition = Vanta { $version } は Windows 11 Pro、Enterprise、Education に対応しています。この PC の Windows は { $product } のため、Vanta をインストールできません。
install-windows-edition-ending = Vanta { $version } は Windows 11 Pro、Enterprise、Education に対応しています。この PC の Windows は { $product } のため、Vanta をインストールできません。Windows 11 バージョン { $current } のセキュリティ更新プログラムの提供は { $date } に終了します。Windows Update で、この PC を新しいバージョンに移行できます。
install-windows-no-path = Vanta { $version } には Windows 11 バージョン { $releases } が必要ですが、この PC の Windows から Windows Update でそのバージョンに移行することはできません。Vanta { $version } を使用するには、ファイルをバックアップしてから、Vanta ISO で Windows を再インストールしてください。
home-update-access-title = Vanta の更新のため、Windows Update の設定が変更されています
home-update-access-not-offered = Vanta はこの PC を Windows 11 バージョン { $release } に移行するために Windows Update をオンにしましたが、Windows Update ではまだ提供されていません。「もう一度確認」または「設定を元に戻す」を選んでください。
home-update-access-before = Vanta はこの PC を Windows 11 バージョン { $release } に移行するために Windows Update をオンにしましたが、まだ完了していません。更新を続行するか、「設定を元に戻す」を選んでください。
home-update-access-after = この PC には Windows 11 バージョン { $release } がインストールされています。Vanta のインストールを完了するか、「設定を元に戻す」を選んでください。
home-update-access-plain = Vanta は更新プログラムをインストールするために Windows Update をオンにしましたが、まだ完了していません。更新を続行するか、「設定を元に戻す」を選んでください。
home-update-access-unreadable = Vanta は、変更した Windows Update の設定の記録を読み取れないため、何も変更せず、元にも戻しません。Vanta チームが対応できるよう、「レポートを送信」を選んでください。
home-update-access-failed = Vanta は設定を元に戻せませんでした。もう一度試すか、「レポートを送信」を選んでください。詳細: { $error }
home-update-access-install-active = 先に Vanta のインストールを完了してください。インストールの最後に、これらの設定は元に戻されます。
home-continue-update = 更新を続行
home-put-back = 設定を元に戻す
home-putting-back = 設定を元に戻しています…
windows-card-title = Windows 11 バージョン { $release }
windows-card-required = Vanta { $version } には、より新しいバージョンの Windows が必要です。下で Windows を更新するときに、Vanta は Windows Update から Windows 11 バージョン { $release } もインストールします。
windows-card-question = この PC でどのバージョンの Windows を使用しますか?
windows-choice-move = Windows 11 バージョン { $release } に更新
windows-choice-move-detail = 推奨。{ $date } までセキュリティ更新プログラムが提供されます。再起動が 1 回増えます。
windows-choice-keep = Windows 11 バージョン { $current } を維持
windows-choice-keep-detail = PC はこのバージョンのままです。Windows Update によって新しいバージョンに移行されることはないため、後で移行するには Vanta Manager でもう一度更新する必要があります。
windows-card-facts = 変更内容
windows-fact-keep = ファイルとアプリはそのまま残ります。更新によって Vanta の変更が元に戻された場合は、インストール時に Vanta が適用し直します。
windows-fact-restart = 完了するまでに、PC はさらに 1 回以上再起動します。
transition-offer-expectation = Windows Update でこのバージョンが提供されるまで、通常は数分ですが、最大 2 時間かかることがあります。Vanta が自動で確認しながら待機します。
windows-fact-stays = その後、Windows はバージョン { $release } のままになり、自動的に新しいバージョンに移行することはありません。
windows-fact-removed = バージョン { $release } には、Windows PowerShell 2.0 と WMIC ツールが含まれていません。
# "設定" > "Windows Update" > "更新の履歴" and "設定" > "システム" > "回復" > "戻す" are the
# labels Japanese Windows 11 shows.
windows-card-undo = 後で元に戻すには、「設定」の「Windows Update」>「更新の履歴」から更新プログラムをアンインストールしてください。更新時に Windows が再インストールされた場合は、代わりに 10 日以内に「設定」の「システム」>「回復」で「戻す」を選んでください。Vanta { $version } はバージョン { $current } に対応していないため、Vanta { $version } をインストールした後は元に戻さないでください。
windows-card-undo-optional = 後で元に戻すには、「設定」の「Windows Update」>「更新の履歴」から更新プログラムをアンインストールしてください。更新時に Windows が再インストールされた場合は、代わりに 10 日以内に「設定」の「システム」>「回復」で「戻す」を選んでください。
windows-terms = Windows 11 バージョン { $release } のマイクロソフト ソフトウェア ライセンス条項に同意します
windows-terms-link = ライセンス条項を読む
windows-card-locked = バージョン { $current } のままにするには、「キャンセル」を選んでから「更新を停止」を選んでください。
prepare-description-transition = インストール前に、Vanta は保留中の Windows 更新プログラムをインストールし、次に Windows 11 バージョン { $release } をインストールしてから、Microsoft Store と Store アプリを更新します。開いている Store アプリは更新中に終了することがあるため、先にそのアプリでの作業を保存してください。PC は少なくとも 1 回再起動します。
prepare-start-transition = Windows をバージョン { $release } に更新
prepare-needs-terms = 「Windows 11 バージョン { $release }」でライセンス条項に同意すると利用できます。
ready-banner-not-offered-message = 現在できることは、「Windows と Store アプリの更新」で確認してください。
ready-banner-transition-failed-message = 次に行うことは、「Windows と Store アプリの更新」で確認してください。
ready-banner-terms-title = 続行するにはライセンス条項に同意してください
ready-banner-terms-message = ライセンス条項は、このページの下にある「Windows 11 バージョン { $release }」にあります。同意したら、「Windows をバージョン { $release } に更新」を選んでください。
access-notice-title = Vanta は一時的に Windows Update をオンにします
access-off = この PC では Windows Update がオフになっています。Windows の更新中は、Vanta がオンに戻します。
access-paused = この PC では Windows の更新が一時停止されています。Windows の更新中は、Vanta が一時停止を解除します。
access-delayed = この PC では毎月の更新プログラムが延期されています。Windows の更新中は、Vanta が延期を解除します。
access-back-chosen = Vanta { $version } のインストールが完了すると、これらの設定は選択したとおりに戻ります。
access-back = Vanta { $version } のインストールが完了すると、これらの設定は元の状態に戻ります。
access-back-stop = それより前に停止した場合も、Vanta が元に戻します。
prepare-reboot-transition = Windows 11 バージョン { $release } がインストールされました。インストールを完了するには、「再起動して続行」を選んでください。サインイン後に Vanta が再び開きます。
prepare-reboot-commit = バージョン { $release } のインストールを完了するには、Windows をもう一度再起動する必要があります。サインイン後に Vanta が再び開きます。
prepare-restart-commit-failed = Windows は再起動時にバージョン { $release } のインストールを完了する準備ができなかったため、PC は再起動されませんでした。もう一度試すには、「再起動して続行」を選んでください。
prepare-reason-feature-update = 新しい Windows バージョン
prepare-reason-feature-commit = 新しい Windows バージョンの完了処理
prepare-resumed-transition = PC が再起動しました。「更新を続ける」を選ぶと、Windows 11 バージョン { $release } のインストールが完了したことを Vanta が確認し、残りの更新プログラムをインストールします。
prepare-waiting-offer = Windows Update で Windows 11 バージョン { $release } が提供されるのを待っています。通常は数分で提供されますが、最大 2 時間かかることがあります。PC は引き続き使用できますが、Vanta は開いたままにしてください。
prepare-resumed-before-move = 更新プログラムのインストールを完了するため、PC が再起動しました。「更新を続ける」を選ぶと、Vanta が残りの更新プログラムをインストールし、その後 Windows 11 バージョン { $release } をインストールします。
prepare-not-offered-title = Windows Update で Windows 11 バージョン { $release } が提供されるのを待っています
prepare-transition-failed-title = Windows をバージョン { $release } に移行できませんでした
prepare-failed-feature-not-offered = Windows Update で Windows 11 バージョン { $release } が PC に提供されるまで、時間がかかることがあります。PC は現在もバージョン { $current } です。
prepare-offer-rechecking = Vanta は 10 分ごとに再確認し、Windows Update で提供され次第、自動で続行します。「もう一度確認」を選ぶこともできます。
prepare-offer-waited = { $minutes } 分間待機しています。
prepare-offer-next-check = 次の確認は { $minutes } 分後です。
prepare-offer-checking-now = 確認しています。
prepare-offer-check-again = 今すぐ確認するには、「もう一度確認」を選んでください。
prepare-offer-wait-ended-title = Windows Update で Windows 11 バージョン { $release } がまだ提供されていません
prepare-offer-wait-ended = Windows Update で 2 時間以内に Windows 11 バージョン { $release } が提供されなかったため、Vanta は待機を終了し、Windows Update の設定を元に戻しました。後で「もう一度確認」を選んでください。待てない場合は、ファイルをバックアップしてから、Vanta ISO で Windows を再インストールしてください。
# $error is the raw error.
prepare-offer-wait-put-back-failed = Windows Update で 2 時間以内に Windows 11 バージョン { $release } が提供されず、Vanta は Windows Update の設定を元に戻せませんでした。もう一度試すには、「設定を元に戻す」を選んでください。詳細: { $error }
prepare-failed-feature-hardware = この PC は Windows 11 のハードウェア要件 ({ $missing }) を満たしていないため、Windows Update でバージョン { $release } に移行することはできません。PC は現在もバージョン { $current } です。Vanta { $version } を使用するには、ファイルをバックアップしてから、Vanta ISO で Windows を再インストールしてください。
hardware-tpm = TPM 2.0
hardware-uefi = UEFI ファームウェア
prepare-failed-feature-hidden = この PC では、Windows Update で Windows 11 バージョン { $release } が非表示になっています。非表示にしたときのツールで再表示してから、「再試行」を選んでください。
prepare-failed-feature-disk-space = この更新には、ドライブ { $drive } に { $needed } GB 以上の空き領域が必要ですが、現在の空き領域は { $free } GB です。Vanta は何も変更していません。空き領域を確保してから、「再試行」を選んでください。
prepare-failed-feature-servicing = Windows のコンポーネント ストアに修復できない破損があると Windows が報告しているため、Vanta は何も変更していません。Windows を修復してから、「再試行」を選んでください。
prepare-failed-feature-managed = この PC は組織の更新サーバーから更新プログラムを受け取っているため、Vanta はバージョン { $release } に移行できません。Vanta は何も変更していません。
prepare-failed-feature-policy = Vanta が { $setting } を変更しても、この PC 上の何かが繰り返し変更前の状態に戻すため、Vanta は Windows を更新できません。この PC が組織によって管理されている場合は、管理者に問い合わせてください。停止すると、Vanta は変更した内容を元に戻します。
prepare-failed-feature-blocked = Vanta が変更していない設定によって、Windows Update を実行できません: { $setting }。Windows Update を実行できるようにこの設定を変更してから、「再試行」を選んでください。
prepare-failed-feature-rolled-back = Windows は再起動中にバージョン { $release } のインストールを完了できず、バージョン { $current } に戻りました。ファイルとアプリに影響はありません。「再試行」または「レポートを送信」を選んでください。
prepare-failed-feature-components-lost = Windows の更新後に Vanta の変更の一部が失われていますが、Windows が再インストールされた形跡はないため、Vanta は何が起きたのかを判断できません。Vanta { $version } はインストールされていません。Vanta チームが対応できるよう、「レポートを送信」を選んでください。
prepare-failed-feature-build = Vanta による更新中に、この PC の Windows のバージョンが変わりました。「設定を元に戻す」を選んでから、ホームからやり直してください。
prepare-failed-feature-journal = Vanta は、変更した Windows Update の設定の記録を読み取れないため、何も変更せず、元にも戻しません。Vanta チームが対応できるよう、「レポートを送信」を選んでください。
# $setting is the name of a Windows Update policy value, such as TargetReleaseVersionInfo.
prepare-failed-feature-pin = この PC の Windows Update ポリシー { $setting } に Vanta が記録できない値が設定されているため、Vanta は何も変更していません。Vanta チームが対応できるよう、「レポートを送信」を選んでください。
prepare-failed-feature-terms = Windows 11 バージョン { $release } のライセンス条項に同意してから、「再試行」を選んでください。
prepare-failed-feature-failed = Windows はバージョン { $release } をインストールできませんでした。PC は現在もバージョン { $current } です。「再試行」を選んでください。再び失敗する場合は、「レポートを送信」を選んでください。
prepare-check-again = もう一度確認
prepare-keep-version = バージョン { $current } を維持
stop-update-title = Vanta { $version } への更新を停止しますか?
stop-update-title-windows = Windows の更新を停止しますか?
stop-update-before = Vanta は変更した Windows Update の設定を元に戻します。Windows がすでにインストールした更新プログラムはそのまま残り、PC は Windows 11 バージョン { $current } のままです。
stop-update-after = PC は Windows 11 バージョン { $release } のままです。Vanta は変更した Windows Update の設定を元に戻します。
stop-update-access = Vanta は変更した Windows Update の設定を元に戻します。Windows がすでにインストールした更新プログラムはそのまま残ります。
stop-update-keep = 更新を継続
# Dialog shown when the window is closed while Windows Update is turned on for an update; its
# buttons are window-close-keep and window-close-put-back.
window-close-update-access-title = Vanta を閉じますか?
window-close-update-access-message = Vanta は閉じる前に、変更した Windows Update の設定を元に戻します。更新はホームからもう一度開始できます。
window-close-put-back = 元に戻して閉じる
# When putting the settings back before closing failed. The reason comes first, then this
# message; the buttons are window-close-keep and window-close-close.
window-close-put-back-failed-title = 設定を元に戻さずに閉じますか?
window-close-put-back-failed-message = 今 Vanta を閉じると、Windows Update の設定は Vanta が変更したままになります。次に Vanta を開くと、ホームから設定を元に戻せます。
installed-update-off-again = 選択したとおり、Windows Update は再びオフになりました。オフの間、PC はセキュリティ更新プログラムを受け取りません。
installed-update-paused-again = 選択したとおり、Windows の更新は再び一時停止されました。一時停止中、PC はセキュリティ更新プログラムを受け取りません。
detail-build-transition = この PC の Windows は Windows 11 バージョン { $current } で、このバージョンの Vanta は対応していません。下で Windows を更新するときに、Vanta が Windows をバージョン { $release } に移行します。
report-transition-intro = Vanta のための Windows の更新が完了しませんでした。Vanta チーム向けの詳細:
mode-rebase = Windows の更新後の再インストール
history-mode-rebase = Windows 更新後の再インストール
ready-rebase-title = 更新時に Windows が再インストールされました
ready-rebase-message = Windows 11 バージョン { $release } がこの PC の以前の Windows を置き換えたため、Vanta の変更の一部が失われています。Vanta { $version } は、Vanta { $previous } での選択内容に従って、それらを適用し直します。
update-path-update-title = Vanta { $version } にどのように更新しますか?
update-path-reinstall-title = Vanta { $version } をどのように再インストールしますか?
update-path-keep = 選択内容を維持する
update-path-keep-detail = Vanta は、すべての選択をこの PC の現在の設定のまま維持し、どれも変更しません。こちらのほうが早く完了します。
update-path-choose = 選択をやり直す
update-path-choose-detail = この PC の現在の設定を出発点に、すべての選択をもう一度行います。Vanta は新規インストールと同じように各選択を適用します。アプリ、ファイル、スタート メニュー、タスク バー、テーマはそのまま残ります。Vanta フォルダーで変更した設定のうち、これらの選択に含まれないものもそのまま残ります。
update-path-now-title = この PC の現在の選択内容
update-path-unknown = PC から判断できないため、Vanta がお尋ねします
option-detected-off = 現在のシステムでは無効になっていることを検出しました。選択は記録されていないため、安全な既定値（有効のまま）が選ばれています。ご自身で選んでください。
update-path-differs = { $choices } について、前回のインストールに関する Vanta の記録がこの PC と一致しません。この一覧には、PC の現在の設定が表示されています。
keep-choices-title = 選択内容の維持
keep-choices-partial = Vanta はこの PC の現在の設定を維持します。次の項目は PC から判断できないため、選んでください: { $missing }
choose-again-title = 選択のやり直し
choose-again-detail = 各選択では、最初にこの PC の現在の設定が選択されています。選んだ内容は、インストール中に Vanta が適用します。
option-now = この PC の現在の設定
change-defender-enable = Vanta は Microsoft Defender を復元します。再起動後に、Windows セキュリティで Defender の保護をオンにしてください。
change-mitigations-default = Vanta はプロセッサの保護を Windows の既定どおりにオンに戻します。再起動後に有効になります。
change-mitigations-all-on = 現在、プロセッサの保護はすべてオンになっています。保護を維持すると、すべてオンのままになります。
change-auto-updates-default = Vanta は、Windows が更新プログラムを再び自動的にインストールするようにします。
change-hibernation-on = Vanta は休止状態をオンに戻します。
change-power-saving-on = Vanta は省電力機能をオンに戻し、以前の電源プランに戻します。以前の電源プランがない場合は「バランス」にします。
change-core-isolation-on = Vanta は仮想化ベースのセキュリティ (VBS) をオンに戻します。ただし、この PC のポリシーで管理されている場合は変更しません。再起動後に有効になります。
change-remove-snipping-tool = この PC のすべてのユーザーから Snipping Tool を削除します。Vanta では後から元に戻せませんが、Microsoft Store から再インストールできます。
fixed-uninstall-edge = Microsoft Edge はすでに削除されており、Vanta を更新しても元に戻りません。再インストールするには、Vanta フォルダーにある「Install or Remove Edge」を使用してください。
fixed-installed = { $app } はインストール済みです。Vanta はアプリをアンインストールしません。削除するには、Windows の「設定」で「インストールされているアプリ」を開いてください。
browser-also = { $installed } はそのまま残り、Vanta が { $browser } もインストールします。
summary-update-path = Vanta の更新方法
step-heading-update-path-a11y = { $heading }。{ $question }
security-banner-removed-title = この PC の Microsoft Defender は Vanta によって削除されています
security-banner-restore-title = このインストールで Vanta が Microsoft Defender を復元します
security-banner-restore-message = Defender はまだ実行されていないため、この手順でオフにするものはありません。再起動後に、Windows セキュリティで Defender の保護をオンにしてください。「続行」を選んでください。
security-banner-missing-title = Microsoft Defender が見つかりません
security-banner-missing-message = Vanta が削除したものではないため、Vanta では復元できません。続行できますが、別のウイルス対策アプリをインストールするか Windows を修復するまで、PC はウイルス対策による保護を受けられません。
installed-defender-not-restored-title = Microsoft Defender は削除されたままです
installed-defender-not-restored-message = Microsoft Defender を残すことを選びましたが、以前の Vanta の更新で復元されなかったため、PC はウイルス対策による保護を受けていません。復元するには、Vanta を更新または再インストールして「選択をやり直す」を選択してください。または、デスクトップの Vanta フォルダーで「7. Security」>「Defender」を開き、「Toggle Defender」を実行して「Enable Windows Defender」を選んでから、PC を再起動してください。
choices-not-applied-title = 一部の選択が反映されませんでした
choices-not-applied-message = { $choices } について、Vanta はこの PC の現在の設定を記録しました。理由はインストール ログで確認できます。
rebase-choices-title = Vanta { $previous } からの選択内容
rebase-choices-detail = Vanta は Vanta { $previous } での選択内容を使用するため、ここで選ぶものはありません。後で変更するには、「Vanta を再インストール」を選んでから、「選択をやり直す」を選択してください。
rebase-choices-partial = Vanta は Vanta { $previous } での選択内容を使用します。次の項目は見つからなかったため、確認してください: { $missing }
restart-other-title = この PC に別のユーザーがサインインしています
restart-others-title = この PC に他のユーザーが複数サインインしています
restart-others-message = 再起動すると、サインインしているユーザーのアプリが閉じられ、保存されていない作業は失われます。サインイン中: { $names }。
restart-others-keep = 再起動しない
restart-others-restart = このまま再起動
prepare-store-self-update = 先に Microsoft Store を更新しています。この PC の Microsoft Store は最新ではありません。
prepare-store-repair = Microsoft Store を修復しています。数分かかることがあります。
prepare-store-updated = Microsoft Store が最新ではなかったため、Vanta はアプリより先に Microsoft Store を更新しました。
prepare-store-bootstrapped = Microsoft Store が自身を更新できなかったため、Vanta は Microsoft から最新のアプリ インストーラーと Microsoft Store をインストールしました。
prepare-store-repaired = Microsoft Store が動作していなかったため、Vanta が修復しました。
prepare-store-skipped-removed = この PC では Microsoft Store がオフになっているため、Vanta は Store アプリの更新をスキップしました。
prepare-failed-store-repair-failed = Microsoft Store がこの PC でアプリのインストールや更新を行えず、Vanta は修復できませんでした。Store が壊れた状態で Vanta をインストールすると、Store とそのアプリが壊れたままになる可能性があるため、Vanta には Store が正常に動作している必要があります。もう一度試すには、「Microsoft Store を修復」を選んでください。それでも動作しない場合は、ファイルをバックアップしてから Vanta ISO で Windows を再インストールするか、「レポートを送信」を選んでください。
prepare-repair-store = Microsoft Store を修復

screen-keyboard-title = キーボードの言語
screen-keyboard-question = 複数のキーボード言語を使いますか?
package-option-keyboard-shortcuts = はい、キーボード ショートカットで切り替える
package-option-keyboard-selector = はい、タスク バーの選択メニューで切り替える
package-option-keyboard-single = いいえ、1 つのキーボード レイアウトだけを使う
consequence-keyboard-shortcuts = Alt+Shift で言語を、Ctrl+Shift でキーボード レイアウトを切り替えます。
consequence-keyboard-selector = ゲーム中に誤って切り替わらないよう、Alt+Shift と Ctrl+Shift をオフにします。
package-choice-keyboard-description = キーボード言語の切り替え方法を選んでください。
consequence-keyboard-single = { consequence-keyboard-selector }

# 選択画面の上部に表示される選択モードバー。
options-mode-title = 選択モード
options-mode-recommended = Vanta のおすすめ
options-mode-manual = 手動で選択
options-mode-recommended-detail = この画面のオプションにのみ Vanta の推奨プロファイルを適用します（VBS、フィッシング対策、Store、Snipping Tool を維持し、前の選択を変えずに Brave と Vanta 最適化を有効化）。
options-mode-manual-detail = 追加オプションはすべて未選択から個別に選べます。またはワンクリックで Vanta のおすすめを適用できます。
options-mode-proceed = おすすめ設定で進む
prepare-ready-title = 準備完了 — 下の「続行」をクリックしてください
prepare-ready-detail = Windows は次のステップに進む準備が整いました。今すぐ続行できます。
option-recommended-label = { $label } (推奨)
option-core-isolation-unlock = Valorant やこれを必須とするアンチチート搭載ゲームはプレイしません
option-why-disable-hibernation = 利点: SSD の容量を数 GB 空け、毎回クリーンに起動できます。注意: ノート PC では休止状態と高速スタートアップが使えなくなります。
option-why-disable-power-saving = 利点: ゲーム中のクロック低下や遅延を防ぎます。注意: 消費電力が増え、ノート PC のバッテリー持続時間が短くなります。
option-why-disable-core-isolation = 利点: 一部の PC で CPU 負荷をわずかに下げることがあります。注意: 悪意あるドライバーからの保護が弱まり、Valorant（Vanguard）などの厳格なアンチチート搭載ゲームが起動できなくなります。
option-why-disable-phishing-protection = 内容: 危険なサイトへパスワードを入力する際の Windows 警告を無効にします。利点: FPS への実質的な効果はありません。注意: パスワード盗難に対する保護が下がります。
option-why-disable-gamebar = 内容: Xbox Game Bar とバックグラウンド録画（Game DVR）を無効にします。利点: ゲーム中の GPU・ディスク負荷を軽減します。注意: Win+G や Game Bar のクリップ録画が使えなくなります。
option-why-remove-store = 内容: App Installer と winget を残して Microsoft Store アプリを削除します。利点: バックグラウンド更新を減らせます。注意: Store アプリや Game Pass ゲームの入手ができなくなります。
option-why-vanta-power = 内容: デスクトップ向けに調整された Vanta 電源プランを有効にします。利点: 省電力による制限を避け、ゲーム時の応答性を保ちます。注意: デスクトップ専用（ノート PC ではスキップ）。
option-why-vanta-memory = 内容: メモリ圧縮を有効に保ち、ページ結合とアプリの事前起動を無効にします。利点: バックグラウンドのディスク負荷を抑えフレームタイムを安定させます。注意: 重いアプリの初回起動がやや遅くなる場合があります。
option-why-tools-on-logon = 内容: セットアップ後の次回サインイン時に Vanta Tools を自動で開きます。利点: すぐにアプリ導入や設定確認ができます。注意: 恒久的な影響はありません。
option-why-remove-snipping-tool = 内容: Windows 標準の Snipping Tool を削除します。利点: ShareX や Lightshot を使う場合に不要な標準アプリを減らせます。注意: 別のツールを入れないと Win+Shift+S が使えません。
option-why-uninstall-edge = 利点: Edge のバックグラウンド更新や常駐サービスを削除します。注意: 別のブラウザーが入っているか、下で選択してください。
option-why-install-another-browser = 利点: セットアップ直後から使えるブラウザーを用意します（Edge 削除時に便利）。注意: インターネット接続が必要です。
option-why-install-eclean = 利点: 一時ファイルの整理やスタートアップ管理に役立ちます。注意: 任意機能でアカウントとネット接続が必要です。
option-why-browser-brave = 内容: 広告・トラッカーブロック内蔵の Chromium 系ブラウザー Brave を導入します。利点: 拡張機能なしで高速・快適に閲覧できます。注意: 任意の暗号資産機能は設定で無視できます。
option-why-browser-librewolf = 内容: テレメトリを排した高プライバシー Firefox 派生 LibreWolf を導入します。利点: 強力な追跡防止。注意: 一部サイトで Cookie 例外が必要な場合があります。
option-why-browser-firefox = 内容: Chromium に依存しない独立ブラウザー Mozilla Firefox を導入します。利点: 高いプライバシー性と豊富な拡張機能。注意: 一部の Chromium 向けサイトで挙動が異なる場合があります。
option-why-browser-chrome = 内容: Google アカウント同期対応の Google Chrome を導入します。利点: 最も高い Web 互換性。注意: プライバシー重視ブラウザーよりメモリ消費とデータ収集が多めです。
