# プライバシーポリシー / Privacy Policy

[日本語](#日本語) · [English](#english)

> この文書が原本です。販売ページの `site/privacy.html` と `site/en/privacy.html` は同じ内容なので、変えるときは3つとも直し、最終更新日もそろえてください（`scripts/tests/run.sh docs` が日付のずれを見つけます）。

---

## 日本語

最終更新: 2026年10月31日

Nonet（以下「本アプリ」）は、Takanari Okazaki（以下「私たち」）が提供する macOS 用のアプリです。本アプリは、あなたの情報を集めないように作っています。

### 1. 集めない情報

- 本アプリには、利用状況の分析（アナリティクス）、テレメトリ、クラッシュレポートの送信、広告の仕組みがありません。
- アカウントはありません。本アプリから私たちのサーバーに、あなたの情報を送ることはありません。

### 2. Mac の中だけに保存する情報

- **設定**（プロファイル・マス・アクション・全体の設定）: `~/Library/Application Support/Nonet/configuration.json` に保存します。保存するたびに1つ前の版を同じフォルダの `configuration.backup.json` に残します。読めなかったファイルや別の版のファイルは、上書きせずに名前を変えて同じフォルダに残します。
- **試用の記録**（開始日・最後に確かめた時刻・試用を始めてから経った時間）: 本アプリの環境設定（`~/Library/Preferences/com.iam74k4.Nonet.plist`）と `~/Library/Application Support/Nonet/` に保存し、製品版ではログインキーチェーンにも項目（`com.iam74k4.Nonet.license.trial`）として保存します。試用期間を正しく数えるためだけに使います。キーチェーンの項目は iCloud キーチェーンと同期しません。
- **ライセンスキー**: 本アプリの環境設定に保存します。ライセンスキーには、購入時の名前とメールアドレスが含まれます。
- **そのほかの環境設定**: 設定ウインドウの位置と大きさ、アップデートの確認の設定と最後に確認した日時（Sparkle）を、本アプリの環境設定に保存します。
- **一時ファイル**: スクリプトをターミナルで実行するとき、スクリプトとそれに渡す情報（選択中のテキストなど）を書いた一時ファイル（`nonet-….command`）を、Mac の一時フォルダ（`$TMPDIR/Nonet/Terminal/`）に作ります。ショートカットに選択中のテキストを渡すときは、そのテキストを書いた一時ファイル（`input-….txt`）を `$TMPDIR/Nonet/Shortcuts/` に作ります。どちらも本人だけが読める権限で作ります。ターミナルのファイルは実行が始まると消し、開かれずに残ったものは5分後か、次に本アプリを起動したときに消します。ショートカットのファイルは、ショートカットが終わると消します。

どれも Mac の外には送りません。本アプリを削除するときにまとめて消せます（手順は[利用ガイド](user-guide.md#アンインストール)。キーチェーンの項目は、キーチェーンアクセスで消せます）。

### 3. アクセシビリティの許可の使い方

本アプリは macOS の「アクセシビリティ」の許可を、次のことだけに使います。

- トリガーキーが押された・離されたこと、その間にほかのキーが押されたことを知る。入力した文字の内容は、記録も保存も送信もしません。
- トリガーキーを押している間、カーソルの移動・クリック・スクロールを前面のアプリに渡さない。
- あなたが設定したキー入力を前面のアプリに送り、メニュー項目を押す。
- 設定画面で、起動中のアプリのメニューの一覧を読む。
- あなたが設定したアクションを実行する直前に、そのアクションに渡すものを読む。スクリプトでは、前面のウィンドウで開いている書類の場所をいつも読み、選択中のテキストは、スクリプトに変数 `NONET_SELECTED_TEXT` が書かれているときだけ読む。ショートカットでは「選択中のテキストを渡す」がオンのときだけ、AI では毎回、選択中のテキストを読む。選択中のテキストを直接読めないアプリでは、⌘C でクリップボードを使って読み、クリップボードを元に戻す。読んだ内容はそのアクションに渡すだけで、保存も送信もしません。

クリップボードを一時的に使うときは、パスワード管理アプリがパスワードとしてコピーしたもの（`org.nspasteboard.ConcealedType` の印があるもの）を読みも戻しもしません。macOS（15.4 以降）がクリップボードを読む前に確かめる設定のときは、その答えに従い、拒否されていればクリップボードを読みません。

トラックパッドの指の位置は、macOS のマルチタッチの仕組みから読み、どのマスかを決めるためにメモリの中だけで使います。保存も送信もしません。

### 4. オートメーション（Apple Events）

スクリプトに変数 `NONET_BROWSER_URL` が書かれていて、前面のアプリが対応しているブラウザ（Safari・Google Chrome・Arc・Microsoft Edge・Brave）のときだけ、実行する直前にそのブラウザに、表示中のページの URL を問い合わせます。macOS が初回に、そのブラウザを操作する許可を確認します。読んだ URL はそのスクリプトに渡すだけで、保存も送信もしません。スクリプトをターミナルで実行するときは、一時ファイルをターミナルで開くだけで、Apple Events は使いません。

### 5. あなたが設定するアクション

スクリプト・ショートカット・URL など、あなたが設定したアクションは、あなたの権限で Mac の中で実行されます。そのアクションがどんな情報を扱い、どこへ送るかは、アクションの中身によります。

プロファイルを読み込むとき、スクリプトを実行するマス・Return を押すか長いキー入力のマス・Mac の中のファイルを開くマスがあれば、本アプリは読み込む前に、そのマスと中身（スクリプトの最初の数行・押すキー・開くファイルの場所）を並べて確かめます。ほかの人から受け取ったプロファイルは、中身を確かめ、信頼できるものだけを読み込んでください。

AI のアクションは、Apple の Foundation Models フレームワークを使い、Mac の中の言語モデルで処理します。本アプリが選択中のテキストを外部に送ることはありません。結果で選択範囲を置き換えるときは、結果をクリップボードに一時的に置いて ⌘V で貼り付け、元のクリップボードに戻します（クリップボードの履歴を残すアプリに残らないよう、`org.nspasteboard.TransientType` の印を付けます）。

### 6. ネットワーク

本アプリがネットワークを使うのは、次のときだけです。

- **アップデートの確認**: オープンソースの Sparkle を使い、更新の情報と新しい版を配布元から HTTPS で定期的に取得します。このとき配布元のサーバーには、通信に伴う一般的な情報（IP アドレス、アプリと macOS の版を含む User-Agent など）が届きます。Sparkle のシステム情報を送る機能は使っていません。
- **購入ページを開く**: 「購入する」を選ぶと、既定のブラウザで購入ページを開きます。購入の手続きは販売サービスのプライバシーポリシーに従います。

ライセンスキーの確認は Mac の中で行い、ネットワークを使いません。

### 7. 購入のときの情報

購入の手続きと支払いは販売サービスが行い、カード番号などの支払いの情報を私たちが受け取ることはありません。私たちは、ライセンスキーの発行とサポートのために、販売サービスから購入者の名前・メールアドレス・注文の情報を受け取ります。これらは、ライセンスキーの発行と再発行、問い合わせへの対応、法令で求められる記録のためだけに使い、第三者に売ったり広告に使ったりしません。

購入の記録は、法令で求められる期間保存し、その後消します。ご自身の情報の開示・訂正・削除を求めるときは、お問い合わせ先までご連絡ください。販売サービスが持つ情報は、販売サービス（TODO: 販売サービス名）のプライバシーポリシー（TODO: その URL）に従って扱われます。

### 8. 販売ページ

販売ページは、Cookie・アクセス解析・外部のフォントやスクリプトを使っていません。ページを置いているホスティング事業者が、一般的なアクセスログ（IP アドレスなど）を記録することがあります。

ページの言語の案内（「This page is also available in English」など）を閉じると、閉じたことだけをブラウザの localStorage に記録し、次からは出しません。この記録はお使いのブラウザの中にだけあり、送信しません。

### 9. このポリシーの変更

内容を変えるときは、このページを更新し、最終更新日を改めます。

### 10. お問い合わせ

Takanari Okazaki（問い合わせ先: TODO: サポートのメールアドレス）

---

## English

Last updated: October 31, 2026

Nonet ("the app") is a macOS app provided by Takanari Okazaki ("we"). The app is designed not to collect your information.

### 1. What we do not collect

- The app contains no analytics, telemetry, crash-report uploads or advertising.
- There is no account. The app never sends your information to our servers.

### 2. What stays on your Mac

- **Settings** (profiles, buttons, actions and preferences) are stored in `~/Library/Application Support/Nonet/configuration.json`. Each save keeps the previous version as `configuration.backup.json` in the same folder. Files that cannot be read, or that come from another version, are kept in the same folder under a new name instead of being overwritten.
- **Trial records** (the start date, the last check time and how much time has passed since the trial started) are stored in the app's preferences (`~/Library/Preferences/com.iam74k4.Nonet.plist`) and in `~/Library/Application Support/Nonet/`. The release version also stores them as an item in your login keychain (`com.iam74k4.Nonet.license.trial`). They are used only to count the trial period correctly. The keychain item is not synced with iCloud Keychain.
- **License key** is stored in the app's preferences. A license key contains the name and email address used for the purchase.
- **Other preferences**: the position and size of the settings window, and the update-check settings and last check time (Sparkle), are stored in the app's preferences.
- **Temporary files**: when a script runs in Terminal, the app writes the script and the information passed to it (such as the selected text) to a temporary file (`nonet-….command`) in your Mac's temporary folder (`$TMPDIR/Nonet/Terminal/`). When a shortcut is set to receive the selected text, the app writes that text to a temporary file (`input-….txt`) in `$TMPDIR/Nonet/Shortcuts/`. Only you can read these files. The Terminal file is deleted when the script starts; if it is never opened, the app deletes it after 5 minutes or the next time the app opens. The shortcut file is deleted when the shortcut finishes.

None of this leaves your Mac. You can remove all of it when you uninstall the app (see the [user guide](user-guide.en.md#uninstalling); remove the keychain item with Keychain Access).

### 3. How the Accessibility permission is used

The app uses the macOS Accessibility permission only to:

- Detect when the trigger key is pressed or released and whether another key is pressed meanwhile. What you type is never recorded, stored or sent.
- Keep pointer movement, clicks and scrolling from reaching the front app while you hold the trigger key.
- Send the keystrokes you configured to the front app and choose menu items.
- Read the menus of running apps in the settings window.
- Just before an action you configured runs, read the information passed to it. For a script, the app always reads the location of the document open in the front window, and reads the selected text only when the script contains the variable `NONET_SELECTED_TEXT`. For a shortcut, it reads the selected text only when “Pass selected text as input” is on; for an AI action, it always reads the selected text. In apps whose selection cannot be read directly, the app copies it with ⌘C through the clipboard and then restores the clipboard. What it reads is passed only to that action and is never stored or sent.

When the app uses the clipboard this way, it never reads or puts back a password copied by a password manager (content marked `org.nspasteboard.ConcealedType`). If macOS (15.4 or later) is set to ask before apps read the clipboard, the app follows your answer, and if reading is denied, it does not read the clipboard.

Finger positions on the trackpad are read through macOS's multi-touch support and used only in memory to decide which button you are on. They are never stored or sent.

### 4. Automation (Apple Events)

Only when a script contains the variable `NONET_BROWSER_URL` and the front app is a supported browser (Safari, Google Chrome, Arc, Microsoft Edge or Brave) does the app ask that browser for the URL of the page it shows, just before the script runs. macOS asks for your permission to control that browser the first time. The URL is passed only to that script and is never stored or sent. Running a script in Terminal does not use Apple Events; the app only opens a temporary file in Terminal.

### 5. Actions you configure

Actions you configure, such as scripts, shortcuts and URLs, run on your Mac with your privileges. What information they handle and where they send it depends on what they do.

When you import profiles, the app first lists any buttons that run a script, type keys that press Return or are long, or open a file on your Mac, together with what they do (the first lines of the script, the keys or the location of the file), and asks you to confirm. Check profiles you receive from someone else, and import them only if you trust them.

AI actions use Apple's Foundation Models framework and are processed by the on-device language model. The app never sends your selected text anywhere. To replace the selected text with the result, the app puts the result on the clipboard for a moment, pastes it with ⌘V and then restores the clipboard. It marks the result `org.nspasteboard.TransientType` so that clipboard history apps do not keep it.

### 6. Network

The app uses the network only:

- **To check for updates**: using the open-source Sparkle framework, it periodically fetches update information and new versions from our distribution server over HTTPS. The server receives the information that comes with any connection, such as your IP address and a User-Agent that includes the app and macOS versions. Sparkle's system profiling is not used.
- **To open the purchase page**: choosing "Buy" opens the purchase page in your default browser. The purchase is governed by the store's privacy policy.

License keys are verified on your Mac without using the network.

### 7. Purchase information

The store handles checkout and payment; we never receive your card details. To issue license keys and provide support, we receive the buyer's name, email address and order details from the store. We use them only to issue and reissue license keys, answer your questions and keep records required by law. We never sell them or use them for advertising.

Purchase records are kept for the period the law requires and then deleted. To see, correct or delete your information, contact us. Information held by the store is handled under the privacy policy of the store (TODO: store name and the URL of its privacy policy).

### 8. Website

The website uses no cookies, analytics, or external fonts or scripts. The hosting provider may keep standard access logs, such as IP addresses.

If you close the language suggestion (such as “日本語のページもあります”), the site remembers only that you closed it, in your browser's localStorage, so it doesn't show again. This stays in your browser and is never sent anywhere.

### 9. Changes

When this policy changes, we update this page and its "Last updated" date.

### 10. Contact

Takanari Okazaki (contact: TODO: support email address)
