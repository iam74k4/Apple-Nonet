# プライバシーポリシー / Privacy Policy

[日本語](#日本語) · [English](#english)

> この文書が原本です。販売ページの `site/privacy.html` と `site/en/privacy.html` は同じ内容なので、変えるときは3つとも直し、最終更新日もそろえてください（`scripts/tests/run.sh docs` が日付のずれを見つけます）。

---

## 日本語

最終更新: 2026年10月30日

Nonet（以下「本アプリ」）は、Takanari Okazaki（以下「私たち」）が提供する macOS 用のアプリです。本アプリは、あなたの情報を集めないように作っています。

### 1. 集めない情報

- 本アプリには、利用状況の分析（アナリティクス）、テレメトリ、クラッシュレポートの送信、広告の仕組みがありません。
- アカウントはありません。本アプリから私たちのサーバーに、あなたの情報を送ることはありません。

### 2. Mac の中だけに保存する情報

- **設定**（プロファイル・マス・アクション・全体の設定）: `~/Library/Application Support/Nonet/` に保存します。
- **試用の開始日とライセンスキー**: 本アプリの環境設定（`~/Library/Preferences/com.iam74k4.Nonet.plist`）に保存します。ライセンスキーには、購入時の名前とメールアドレスが含まれます。

どちらも Mac の外には送りません。本アプリを削除するときにまとめて消せます（手順は[利用ガイド](user-guide.md#アンインストール)）。

### 3. アクセシビリティの許可の使い方

本アプリは macOS の「アクセシビリティ」の許可を、次のことだけに使います。

- トリガーキーが押された・離されたこと、その間にほかのキーが押されたことを知る。入力した文字の内容は、記録も保存も送信もしません。
- トリガーキーを押している間、カーソルの移動・クリック・スクロールを前面のアプリに渡さない。
- あなたが設定したキー入力を前面のアプリに送り、メニュー項目を押す。
- 設定画面で、起動中のアプリのメニューの一覧を読む。
- あなたが設定したアクションが必要とするときだけ、選択中のテキストと、前面のウィンドウで開いている書類の場所を読む。

トラックパッドの指の位置は、macOS のマルチタッチの仕組みから読み、どのマスかを決めるためにメモリの中だけで使います。保存も送信もしません。

### 4. オートメーション（Apple Events）

スクリプトのアクションでブラウザに表示中のページの URL を使うとき、またはスクリプトをターミナルで実行するときに、そのブラウザやターミナルに問い合わせます。macOS が初回に許可を確認します。

### 5. あなたが設定するアクション

スクリプト・ショートカット・URL など、あなたが設定したアクションは、あなたの権限で Mac の中で実行されます。そのアクションがどんな情報を扱い、どこへ送るかは、アクションの中身によります。ほかの人から受け取ったプロファイルを読み込むときは、中のスクリプトを確かめてください。

AI のアクションは、Apple の Foundation Models フレームワークを使い、Mac の中の言語モデルで処理します。本アプリが選択中のテキストを外部に送ることはありません。

### 6. ネットワーク

本アプリがネットワークを使うのは、次のときだけです。

- **アップデートの確認**: オープンソースの Sparkle を使い、更新の情報と新しい版を配布元から HTTPS で定期的に取得します。このとき配布元のサーバーには、通信に伴う一般的な情報（IP アドレス、アプリと macOS の版を含む User-Agent など）が届きます。Sparkle のシステム情報を送る機能は使っていません。
- **購入ページを開く**: 「購入する」を選ぶと、既定のブラウザで購入ページを開きます。購入の手続きは販売サービスのプライバシーポリシーに従います。

ライセンスキーの確認は Mac の中で行い、ネットワークを使いません。

### 7. 購入のときの情報

購入の手続きと支払いは販売サービスが行い、カード番号などの支払いの情報を私たちが受け取ることはありません。私たちは、ライセンスキーの発行とサポートのために、販売サービスから購入者の名前・メールアドレス・注文の情報を受け取ります。これらは、ライセンスキーの発行と再発行、問い合わせへの対応、法令で求められる記録のためだけに使い、第三者に売ったり広告に使ったりしません。

### 8. 販売ページ

販売ページは、Cookie・アクセス解析・外部のフォントやスクリプトを使っていません。ページを置いているホスティング事業者が、一般的なアクセスログ（IP アドレスなど）を記録することがあります。

### 9. このポリシーの変更

内容を変えるときは、このページを更新し、最終更新日を改めます。

### 10. お問い合わせ

Takanari Okazaki（問い合わせ先: TODO: サポートのメールアドレス）

---

## English

Last updated: October 30, 2026

Nonet ("the app") is a macOS app provided by Takanari Okazaki ("we"). The app is designed not to collect your information.

### 1. What we do not collect

- The app contains no analytics, telemetry, crash-report uploads or advertising.
- There is no account. The app never sends your information to our servers.

### 2. What stays on your Mac

- **Settings** (profiles, buttons, actions and preferences) are stored in `~/Library/Application Support/Nonet/`.
- **Trial start date and license key** are stored in the app's preferences (`~/Library/Preferences/com.iam74k4.Nonet.plist`). A license key contains the name and email address used for the purchase.

Neither leaves your Mac. You can remove both when you uninstall the app (see the [user guide](user-guide.md#アンインストール)).

### 3. How the Accessibility permission is used

The app uses the macOS Accessibility permission only to:

- Detect when the trigger key is pressed or released and whether another key is pressed meanwhile. What you type is never recorded, stored or sent.
- Keep pointer movement, clicks and scrolling from reaching the front app while you hold the trigger key.
- Send the keystrokes you configured to the front app and choose menu items.
- Read the menus of running apps in the settings window.
- Read the selected text and the location of the document open in the front window, only when an action you configured needs them.

Finger positions on the trackpad are read through macOS's multi-touch support and used only in memory to decide which button you are on. They are never stored or sent.

### 4. Automation (Apple Events)

When a script action uses the URL of the page shown in your browser, or runs a script in Terminal, the app asks that browser or Terminal. macOS asks for your permission the first time.

### 5. Actions you configure

Actions you configure, such as scripts, shortcuts and URLs, run on your Mac with your privileges. What information they handle and where they send it depends on what they do. Check the scripts in any profile you receive from someone else before importing it.

AI actions use Apple's Foundation Models framework and are processed by the on-device language model. The app never sends your selected text anywhere.

### 6. Network

The app uses the network only:

- **To check for updates**: using the open-source Sparkle framework, it periodically fetches update information and new versions from our distribution server over HTTPS. The server receives the information that comes with any connection, such as your IP address and a User-Agent that includes the app and macOS versions. Sparkle's system profiling is not used.
- **To open the purchase page**: choosing "Buy" opens the purchase page in your default browser. The purchase is governed by the store's privacy policy.

License keys are verified on your Mac without using the network.

### 7. Purchase information

The store handles checkout and payment; we never receive your card details. To issue license keys and provide support, we receive the buyer's name, email address and order details from the store. We use them only to issue and reissue license keys, answer your questions and keep records required by law. We never sell them or use them for advertising.

### 8. Website

The website uses no cookies, analytics, or external fonts or scripts. The hosting provider may keep standard access logs, such as IP addresses.

### 9. Changes

When this policy changes, we update this page and its "Last updated" date.

### 10. Contact

Takanari Okazaki (contact: TODO: support email address)
