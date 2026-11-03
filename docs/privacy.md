# プライバシーポリシー / Privacy Policy

[日本語](#日本語) · [English](#english)

> この文書が原本です。販売ページの `site/privacy.html` と `site/en/privacy.html` は同じ内容なので、変えるときは3つとも直し、最終更新日もそろえてください（`scripts/tests/run.sh docs` が日付のずれを見つけます）。

---

## 日本語

最終更新: 2026年11月3日

Nonet（以下「本アプリ」）は、Takanari Okazaki（以下「私たち」）が提供する macOS 用のアプリです。本アプリは、あなたの情報を集めないように作っています。

### 1. 集めない情報

- 本アプリには、利用状況の分析（アナリティクス）、テレメトリ、クラッシュレポートの送信、広告の仕組みがありません。
- アカウントはありません。本アプリから私たちのサーバーに、あなたの情報を送ることはありません。

### 2. Mac の中だけに保存する情報

- **設定**（プロファイル・マス・アクション・全体の設定）: `~/Library/Application Support/Nonet/configuration.json` に保存します。保存するたびに1つ前の版を同じフォルダの `configuration.backup.json` に残します。設定ファイルを読めなかったときは、上書きせずに `configuration.corrupt-<日時>.json` に名前を変えて、同じフォルダに残します。読めても、保存すると失う内容（本アプリが知らない種類のマスや設定など）があるときは、元のファイルの写しを `configuration.lossy-<日時>.json` として、別の版の本アプリで書かれたファイルは、その写しを `configuration.v<番号>.json`（番号はファイルの形式の版）として、同じフォルダに残します。これらは設定と同じ内容（スクリプトなども含みます）で、本アプリは消さないので、`~/Library/Application Support/Nonet/` のフォルダを消すまで残ります。設定を変えている間（1時間に1回まで）と、プロファイルやページの削除・読み込みなどの前には、その時点の設定の控えを `~/Library/Application Support/Nonet/Backups/` に新しいものから10個まで残します（「以前の設定に戻す…」で使います）。
- **試用の記録**（開始日・最後に確かめた時刻・試用を始めてから経った時間）: 本アプリの環境設定（`~/Library/Preferences/com.iam74k4.Nonet.plist`）と `~/Library/Application Support/Nonet/` に保存します。製品版ではログインキーチェーンにも項目（`com.iam74k4.Nonet.license.trial`）として保存し、同じ記録を、この Mac の識別子（IOPlatformUUID）とアプリの ID から作ったハッシュ（64桁の16進数）を名前にした2つ目の項目にも写します（識別子そのものは保存も送信もしません）。試用の記録がどこにもないときは、`~/Library/Application Support/Nonet/Backups/` と `~/Library/Caches/com.iam74k4.Nonet/` のフォルダの作成日を、試用を始めた日の代わりに使います（作成日を読むだけです）。どれも試用期間を正しく数えるためだけに使います。キーチェーンの項目は iCloud キーチェーンと同期しません。
- **ライセンスキー**: 本アプリの環境設定に保存します。ライセンスキーには、購入時の名前とメールアドレスが含まれます。
- **そのほかの環境設定**: 設定ウインドウの位置と大きさ、アップデートの確認の設定と最後に確認した日時（Sparkle）、HUD の使い始めの案内を出した回数（20回まで）、試用期間の残りや終了を知らせた日付、起動したときに許可の案内を出さない設定（「今後表示しない」）を、本アプリの環境設定に保存します。
- **一時ファイル**: スクリプトをターミナルで実行するとき、スクリプトとそれに渡す情報（選択中のテキストなど）を書いた一時ファイル（`nonet-….command`）を、Mac の一時フォルダ（`$TMPDIR/Nonet/Terminal/`）に作ります。ショートカットに選択中のテキストを渡すときは、そのテキストを書いた一時ファイル（`input-….txt`）を `$TMPDIR/Nonet/Shortcuts/` に作ります。どちらも本人だけが読める権限で作ります。ターミナルのファイルは実行が始まると消し、開かれずに残ったものは5分後か、次に本アプリを起動したときに消します。ショートカットのファイルは、ショートカットが終わると消します。本アプリが終了するときは、続けて開かれた本アプリが待つかどうかを決めるための、中身のない印のファイル（`Nonet-quitting-<番号>`）を Mac の一時フォルダに作ります。

本アプリは、最初の設定を作るときに Dock に置いてあるアプリの一覧を読み、ランチャーの並びに使います。また、起動したときに、スクリプトをターミナルと同じ条件で動かすため、あなたのログインシェル（`~/.zshrc` を含む）を1回動かして、`PATH` と `claude` コマンドの有無を調べます。どちらもメモリの中で使うか、設定に入れるだけです。

どれも Mac の外には送りません。本アプリを削除するときにまとめて消せます（手順は[利用ガイド](user-guide.md#アンインストール)。キーチェーンの2つの項目（`com.iam74k4.Nonet.license.trial` と、名前が64桁の16進数のもの）は、キーチェーンアクセスで消せます）。設定の「Nonet」のタブの「Nonet をアンインストール…」は、本アプリと設定のフォルダとキャッシュをゴミ箱に入れますが、ライセンスキーと試用の記録（環境設定とキーチェーン）は残します。入れ直したときに、登録し直さずに使えるようにするためです。

アプリの「お問い合わせ…」で作るメールには、アプリと macOS の版・Mac の機種・キーボードの種類だけが入り、送るかどうかはあなたが決めます。ライセンスキーや設定の中身は入りません。

### 3. アクセシビリティの許可の使い方

本アプリは macOS の「アクセシビリティ」の許可を、次のことだけに使います。

- 9マスを開いている間、ポインタの移動・クリック・スクロール・ジェスチャーを前面のアプリに渡さず、ポインタをトラックパッドの上の指の位置に合わせて動かす（閉じると元の位置に戻す）。そのためのポインタのイベントタップは、9マスを開いている間と、閉じた直後の短い後片付けの間（遅れて届くクリックと、開いている間に渡さなかったクリックの「離す」やスクロールの続きを捨てる間）だけ有効にし、それ以外のときはポインタのイベントが本アプリを通りません。開いている間に、トラックパッドに指を触れずにマウスやホイールを使ったときは、そのイベントを手を加えずに前面のアプリに渡し、9マスを閉じます。
- 9マスを開いている間だけ、キーが押されたことを知り、押されたら何も実行せずに9マスを閉じる。キーボードのイベントタップは9マスを開いている間だけ有効にし、それ以外のときはキーボードのイベントが本アプリを通りません。押されたキーは手を加えずに前面のアプリに渡します。入力した文字の内容は、記録も保存も送信もしません。
- あなたが設定したキー入力を前面のアプリに送り、メニュー項目を押す。メニュー項目のショートカットを送る前には、アプリのメニューにあるその項目のショートカットを読み、同じかを確かめる。
- 「画面に置く」のアクションで、前面のアプリのウインドウの位置と大きさを読んで変える。9マスでそのマスを光らせている間は、置く枠を画面に出すために位置と大きさを読む。読んだ値はその場で使うだけで、保存も送信もしません。
- 設定画面で、起動中のアプリのメニューの一覧を読む。
- あなたが設定したアクションを実行する直前に、そのアクションに渡すものを読む。スクリプトでは、前面のウィンドウで開いている書類の場所をいつも読み、選択中のテキストは、スクリプトに変数 `NONET_SELECTED_TEXT` が書かれているときだけ読む。ショートカットでは「選択中のテキストを渡す」がオンのときだけ、AI では毎回、選択中のテキストを読む。選択中のテキストを直接読めないアプリでは、⌘C でクリップボードを使って読み、クリップボードを元に戻す。読んだ内容はそのアクションに渡すだけで、保存も送信もしません。

クリップボードを一時的に使うときは、パスワード管理アプリがパスワードとしてコピーしたもの（`org.nspasteboard.ConcealedType` の印があるもの）を読みも戻しもしません。macOS（15.4 以降）がクリップボードを読む前に確かめる設定のときは、その答えに従い、拒否されていればクリップボードを読みません。

トラックパッドの指の位置は、macOS のマルチタッチの仕組みから読み（この読み取りには許可は要りません）、9マスを開く動き（上の縁から指を滑らせる）を見分けることと、どのマスかを決めることのためにメモリの中だけで使います。保存も送信もしません。

### 4. オートメーション（Apple Events）

次の2つのときだけ、他のアプリに Apple Events を送ります。macOS が初回に、そのアプリを操作する許可を確認します。

- スクリプトに変数 `NONET_BROWSER_URL` が書かれていて、前面のアプリが対応しているブラウザ（Safari・Google Chrome・Arc・Microsoft Edge・Brave）のとき、実行する直前にそのブラウザに、表示中のページの URL を問い合わせます。読んだ URL はそのスクリプトに渡すだけで、保存も送信もしません。
- 「ファイル」のアクションを実行するとき、前面のアプリが Finder であれば、Finder に、選んでいるファイルの場所を問い合わせ、あなたが設定した操作（開く・ゴミ箱に入れる・複製・移動）を Finder に頼みます（名前の変更は、Return キーを送って Finder の名前の変更を始めます）。読むのはファイルの場所（名前とフォルダ）だけで、ファイルの中身は読みません。場所は操作に使うだけで、保存も送信もしません。ゴミ箱に入れるときも、完全には削除しません。

スクリプトをターミナルで実行するときは、一時ファイルをターミナルで開くだけで、Apple Events は使いません。

### 5. あなたが設定するアクション

スクリプト・ショートカット・URL など、あなたが設定したアクションは、あなたの権限で Mac の中で実行されます。そのアクションがどんな情報を扱い、どこへ送るかは、アクションの中身によります。

プロファイルを読み込むとき、スクリプト・キー入力・メニュー項目・AI のマスや、Finder で選んだファイルをゴミ箱に入れる・名前を変える・複製するマス、Mac の中のファイルを開くマスがあれば、本アプリは読み込む前に、そのマスと中身のすべて（スクリプトのすべての行・押すキー・メニュー項目とショートカット・AI への指示と結果の出し方・ファイルの操作・開くファイルの場所）を並べて確かめます。Return と同じ働きのキーや ⌃ の付いたキーを押すマスと、注意が要る命令（curl・`| sh`・rm -rf など）を含む行は目立たせ、中身を最後までスクロールするまで読み込めません。ほかの人から受け取ったプロファイルは、中身を確かめ、信頼できるものだけを読み込んでください。

AI のアクションは、Apple の Foundation Models フレームワークを使い、Mac の中の言語モデルで処理します。本アプリが選択中のテキストを外部に送ることはありません。結果で選択範囲を置き換えるときは、結果をクリップボードに一時的に置いて ⌘V で貼り付け、元のクリップボードに戻します（クリップボードの履歴を残すアプリに残らないよう、`org.nspasteboard.TransientType` の印を付けます）。

### 6. ネットワーク

本アプリがネットワークを使うのは、次のときだけです。

- **アップデートの確認**: オープンソースの Sparkle を使い、更新の情報と新しい版を配布元から HTTPS で定期的に取得します。このとき配布元のサーバーには、通信に伴う一般的な情報（IP アドレス、アプリと macOS の版を含む User-Agent など）が届きます。Sparkle のシステム情報を送る機能は使っていません。
- **購入ページを開く**: 「購入する」を選ぶと、既定のブラウザで購入ページを開きます。購入の手続きは販売サービスのプライバシーポリシーに従います。

利用ガイドやプライバシーポリシーなど、販売ページのページを選んだときは、既定のブラウザで開きます（「8. 販売ページ」）。

ライセンスキーの確認は Mac の中で行い、ネットワークを使いません。返金したライセンスや公開されてしまったキーは、アプリに入れた無効にしたライセンスの一覧（ライセンス ID の SHA-256。新しい版で更新します）と照らして受け付けませんが、このときも通信はしません。購入のメールのリンク（`nonet://register`）や `.nonetlicense` のファイルを開いたときも、キーを本アプリに渡すだけで、ネットワークは使いません。

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

Last updated: November 3, 2026

Nonet ("the app") is a macOS app provided by Takanari Okazaki ("we"). The app is designed not to collect your information.

### 1. What we do not collect

- The app contains no analytics, telemetry, crash-report uploads or advertising.
- There is no account. The app never sends your information to our servers.

### 2. What stays on your Mac

- **Settings** (profiles, buttons, actions and preferences) are stored in `~/Library/Application Support/Nonet/configuration.json`. Each save keeps the previous version as `configuration.backup.json` in the same folder. If a settings file cannot be read, the app keeps it in the same folder, renamed `configuration.corrupt-<date-time>.json`, instead of overwriting it. If it can be read but saving would lose something in it (such as a kind of button or a setting this version does not know), the app keeps a copy of the original file as `configuration.lossy-<date-time>.json`; for a file written by another version of the app, it keeps a copy as `configuration.v<number>.json` (the number is the version of the file format), in the same folder. These files hold the same information as your settings (including any scripts), and the app never deletes them, so they stay until you delete the `~/Library/Application Support/Nonet/` folder. While you change your settings (at most once an hour) and before you delete a profile or a page, import profiles and similar changes, the app also saves a copy of your settings in `~/Library/Application Support/Nonet/Backups/` and keeps the newest 10 (used by “Restore an Earlier Version…”).
- **Trial records** (the start date, the last check time and how much time has passed since the trial started) are stored in the app's preferences (`~/Library/Preferences/com.iam74k4.Nonet.plist`) and in `~/Library/Application Support/Nonet/`. The release version also stores them as an item in your login keychain (`com.iam74k4.Nonet.license.trial`), and copies the same record to a second item named with a hash (64 hexadecimal digits) made from this Mac's identifier (IOPlatformUUID) and the app's ID. The identifier itself is never stored or sent. If no trial record is left anywhere, the app uses the creation dates of the folders `~/Library/Application Support/Nonet/Backups/` and `~/Library/Caches/com.iam74k4.Nonet/` in place of the trial start date (it only reads these dates). All of this is used only to count the trial period correctly. The keychain items are not synced with iCloud Keychain.
- **License key** is stored in the app's preferences. A license key contains the name and email address used for the purchase.
- **Other preferences**: the position and size of the settings window, the update-check settings and last check time (Sparkle), how many times the HUD's beginner tips were shown (up to 20), the dates the app last reminded you about the trial, and whether you chose not to see the permission reminder at launch (“Don't show again”) are stored in the app's preferences.
- **Temporary files**: when a script runs in Terminal, the app writes the script and the information passed to it (such as the selected text) to a temporary file (`nonet-….command`) in your Mac's temporary folder (`$TMPDIR/Nonet/Terminal/`). When a shortcut is set to receive the selected text, the app writes that text to a temporary file (`input-….txt`) in `$TMPDIR/Nonet/Shortcuts/`. Only you can read these files. The Terminal file is deleted when the script starts; if it is never opened, the app deletes it after 5 minutes or the next time the app opens. The shortcut file is deleted when the shortcut finishes. When the app quits, it creates an empty marker file (`Nonet-quitting-<number>`) in your Mac's temporary folder, so that a copy of the app opened right afterwards knows to wait.

When it creates your first settings, the app reads the list of apps in your Dock and uses it to order the launcher. Each time it opens, the app runs your login shell once (including `~/.zshrc`) to find your `PATH` and whether the `claude` command exists, so that scripts run as they do in Terminal. Both are used only in memory or in your settings.

None of this leaves your Mac. You can remove all of it when you uninstall the app (see the [user guide](user-guide.en.md#uninstalling); remove the two keychain items, `com.iam74k4.Nonet.license.trial` and the one named with 64 hexadecimal digits, with Keychain Access). “Uninstall Nonet…” on the Nonet tab of Settings moves the app, its settings folder and its caches to the Trash, but keeps your license key and trial records (in the preferences and the keychain), so the app works again without registering if you reinstall it.

When you use “Contact Support…” in the app, the email it creates contains only the versions of the app and macOS, your Mac model and your keyboard type. You decide whether to send it. It never includes your license key or your settings.

### 3. How the Accessibility permission is used

The app uses the macOS Accessibility permission only to:

- Keep pointer movement, clicks, scrolling and gestures from reaching the front app, and move the pointer to follow your finger on the trackpad (it returns to where it was when the buttons close), while the nine buttons are open. The pointer event tap for this is enabled only while the nine buttons are open and for a short clean-up right after they close (to drop a late click, and the release of a click or the rest of a scroll that it held back while they were open); at all other times, pointer events never pass through the app. If you use a mouse or scroll wheel while the buttons are open and no finger is on the trackpad, the app passes that event to the front app unchanged and closes the buttons.
- Notice that a key was pressed while the nine buttons are open, so that it can close them without running anything. The keyboard event tap is enabled only while the nine buttons are open; at all other times, keyboard events never pass through the app. The key still reaches the front app unchanged. What you type is never recorded, stored or sent.
- Send the keystrokes you configured to the front app and choose menu items. Before sending a menu item's keyboard shortcut, the app reads that item's shortcut in the app's menus to check that they match.
- Read and change the position and size of the front app's window when a Place on Screen action runs. While that button is highlighted among the nine buttons, the app reads the position and size to outline the target area on screen. What it reads is used only at that moment and is never stored or sent.
- Read the menus of running apps in the settings window.
- Just before an action you configured runs, read the information passed to it. For a script, the app always reads the location of the document open in the front window, and reads the selected text only when the script contains the variable `NONET_SELECTED_TEXT`. For a shortcut, it reads the selected text only when “Pass selected text as input” is on; for an AI action, it always reads the selected text. In apps whose selection cannot be read directly, the app copies it with ⌘C through the clipboard and then restores the clipboard. What it reads is passed only to that action and is never stored or sent.

When the app uses the clipboard this way, it never reads or puts back a password copied by a password manager (content marked `org.nspasteboard.ConcealedType`). If macOS (15.4 or later) is set to ask before apps read the clipboard, the app follows your answer, and if reading is denied, it does not read the clipboard.

Finger positions on the trackpad are read through macOS's multi-touch support (reading them needs no permission) and used only in memory to recognize the slide that opens the nine buttons (a finger sliding down from the top edge) and to decide which button you are on. They are never stored or sent.

### 4. Automation (Apple Events)

The app sends Apple Events to other apps in only two cases. macOS asks for your permission to control that app the first time.

- When a script contains the variable `NONET_BROWSER_URL` and the front app is a supported browser (Safari, Google Chrome, Arc, Microsoft Edge or Brave), the app asks that browser for the URL of the page it shows, just before the script runs. The URL is passed only to that script and is never stored or sent.
- When a File action runs and the front app is Finder, the app asks Finder for the location of the files you have selected, and asks Finder to do what you configured (open, move to the Trash, duplicate or move; for rename, it sends the Return key to start Finder's rename). It reads only the location (name and folder) of each file, never what is inside it. The locations are used only for that operation and are never stored or sent. Moving to the Trash never deletes files for good.

Running a script in Terminal does not use Apple Events; the app only opens a temporary file in Terminal.

### 5. Actions you configure

Actions you configure, such as scripts, shortcuts and URLs, run on your Mac with your privileges. What information they handle and where they send it depends on what they do.

When you import profiles, the app first lists any Script, Keystrokes, Menu Item and AI buttons, any File buttons that move to the Trash, rename or duplicate the files selected in Finder, and any buttons that open a file on your Mac, together with everything they do (every line of the script, the keys, the menu item and its keyboard shortcut, the AI prompt and output, the file operation, or the location of the file), and asks you to confirm. Buttons that press a key that works like Return (or a key with ⌃) and lines with commands that need care (such as curl, `| sh` and rm -rf) are highlighted, and you can't import until you scroll to the end. Check profiles you receive from someone else, and import them only if you trust them.

AI actions use Apple's Foundation Models framework and are processed by the on-device language model. The app never sends your selected text anywhere. To replace the selected text with the result, the app puts the result on the clipboard for a moment, pastes it with ⌘V and then restores the clipboard. It marks the result `org.nspasteboard.TransientType` so that clipboard history apps do not keep it.

### 6. Network

The app uses the network only:

- **To check for updates**: using the open-source Sparkle framework, it periodically fetches update information and new versions from our distribution server over HTTPS. The server receives the information that comes with any connection, such as your IP address and a User-Agent that includes the app and macOS versions. Sparkle's system profiling is not used.
- **To open the purchase page**: choosing "Buy Nonet" opens the purchase page in your default browser. The purchase is governed by the store's privacy policy.

When you choose a page of the website, such as the user guide or this privacy policy, it opens in your default browser (see “8. Website”).

License keys are verified on your Mac without using the network. Refunded licenses and keys that were made public are checked against a list of deactivated licenses (SHA-256 hashes of license IDs) built into the app and updated with new versions, so this check doesn't use the network either. Opening the link in your purchase email (`nonet://register`) or a `.nonetlicense` file only passes the key to the app and doesn't use the network.

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
