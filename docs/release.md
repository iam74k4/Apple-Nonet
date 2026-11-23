# リリースと販売の手順

Nonet は Mac App Store ではなく直販する（非公開の `MultitouchSupport.framework` を使うため。[architecture.md](architecture.md) §1）。配るものは次の3つ。

| もの | 中身 | 作り方 |
|---|---|---|
| DMG | Developer ID で署名し、公証してステープルした `Nonet.app`（DMG 自体も署名・公証・ステープル済み） | `scripts/release.sh` |
| appcast.xml | Sparkle がアップデートを見つけるためのフィード（EdDSA 署名つき） | `scripts/release.sh` が Sparkle の `generate_appcast` で更新 |
| 販売ページ | `site/`（静的な HTML。ビルド不要） | そのままアップロード |

ライセンスは「14日間の試用 → 買い切り」。キーは Ed25519 で署名した文字列で、アプリはサーバー無しで検証する（[architecture.md](architecture.md) §6「ライセンス」）。返金したキーや公開されてしまったキーは、アプリに入れる一覧で止める（3.5）。

---

## 1. 一度だけの準備

### 1.1 道具

- Apple Developer Program のメンバーシップ（チーム ID `NL9ZXK2SGR`。`project.yml` の `DEVELOPMENT_TEAM`）
- Xcode 27 以降（Swift 6 のツールと、AI のアクションに要る FoundationModels の入った macOS SDK が要る）。`xcode-select -p` で選ばれている Xcode を確かめる。古い Xcode（26 より前）でもビルドは通ってしまい、AI のアクションが「macOS 26 以降が必要です」で失敗するアプリになるので、`scripts/release.sh` は SDK に FoundationModels が無ければビルドの前に止まる
- XcodeGen: `brew install xcodegen`
- 一度 `scripts/build.sh` を動かして、Sparkle のパッケージを取ってくる（`build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/` に `generate_keys` と `generate_appcast` が入る）

### 1.2 Developer ID 証明書

`Developer ID Application` の証明書が要る。作れるのはチームの Account Holder だけ。

1. Xcode › Settings › Accounts でチームを選び、Manage Certificates… › ＋ › **Developer ID Application**
2. 確かめる:

   ```bash
   security find-identity -v -p codesigning | grep "Developer ID Application"
   # 例: 1) ABCD… "Developer ID Application: Takanari Okazaki (NL9ZXK2SGR)"
   ```

3. キーチェーンアクセスで証明書と秘密鍵を `.p12` に書き出し、パスワードマネージャーなど安全な場所に保管する（Mac を替えたときに要る）

`scripts/release.sh` は、このチームの有効な Developer ID Application 証明書が無いと、ビルドを始める前に止まる。

### 1.3 公証の準備（notarytool のキーチェーンのプロファイル）

公証には App Store Connect の API キー（おすすめ）か、Apple ID の App 用パスワードを使う。どちらもキーチェーンに保存し、スクリプトにはプロファイル名だけを渡す。

```bash
# API キー（App Store Connect › ユーザとアクセス › 統合 › App Store Connect API で「Developer」の権限で作る）
xcrun notarytool store-credentials nonet-notary \
  --key ~/secrets/AuthKey_XXXXXXXXXX.p8 --key-id XXXXXXXXXX --issuer xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

# または Apple ID（appleid.apple.com で App 用パスワードを作る。パスワードは聞かれたときに入力し、コマンドに書かない）
xcrun notarytool store-credentials nonet-notary --apple-id you@example.com --team-id NL9ZXK2SGR
```

シェルの設定（`~/.zshrc` など）に `export NONET_NOTARY_PROFILE=nonet-notary` を書いておく。`.p8` はリポジトリの外に置く。

### 1.4 Sparkle の鍵（アップデートの署名）

Sparkle はアップデートを EdDSA（Ed25519）で署名し、アプリに入れた公開鍵で確かめる。

```bash
SPARKLE_BIN=build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin
"$SPARKLE_BIN/generate_keys"            # 秘密鍵をログインキーチェーンに作り、公開鍵を表示する
"$SPARKLE_BIN/generate_keys" -p         # あとで公開鍵だけを見る
"$SPARKLE_BIN/generate_keys" -x ~/sparkle-private-key.txt   # 秘密鍵を書き出す（バックアップ用）
```

- 表示された公開鍵を `Config/Nonet.xcconfig` の `NONET_SPARKLE_PUBLIC_KEY` に入れる。**公開鍵に `//` が含まれていたら**（base64 の鍵の約1%）、xcconfig では `//` から後ろがコメントになって切れるので、`//` を `/$()/` と書く（例: `abc…xy/$()/z…=`。`$()` は空文字に展開される）。そのまま書くと、`scripts/release.sh` が「「//」の所で切れています」と言って止まる。Xcode の Organizer から直接書き出すと、切れた鍵が入って、どの利用者もアップデートを確かめられなくなる
- 書き出した秘密鍵はパスワードマネージャーとオフラインの媒体の2か所に保管し、元のファイルは消す。別の Mac では `generate_keys -f <ファイル>` で取り込む
- **秘密鍵を失うと、配布済みのアプリにアップデートを届けられなくなる**。漏れると偽のアップデートを作られる
- 複数の製品で鍵を分けたいときは `--account nonet` のように名前を付け、`NONET_SPARKLE_KEY_ACCOUNT=nonet` を設定する

`scripts/release.sh` は、キーチェーンの鍵の公開鍵が `NONET_SPARKLE_PUBLIC_KEY` と一致しないと止まる。

### 1.5 ライセンスの鍵

```bash
mkdir -p ~/Nonet-secrets && chmod 700 ~/Nonet-secrets
cd Packages/NonetKit
swift run nonet-license keygen --out ~/Nonet-secrets
```

- 秘密鍵は 600 の権限で保存される。**必ずリポジトリの外**に置く（`.gitignore` は `*.private-key` と `secrets/` を除外しているが、それに頼らない）
- 表示された公開鍵を `NONET_LICENSE_PUBLIC_KEY` に入れる
- 秘密鍵はパスワードマネージャーとオフラインの媒体にバックアップする。失うと、今のアプリが受け付けるキーを新しく発行できなくなる
- 漏れたら誰でもキーを作れる。鍵を作り直して公開鍵を差し替えた版を出すことになるが、アプリが受け付ける公開鍵は1つなので、それまでに発行したキーはすべて使えなくなる（再発行が要る）。そうならないよう厳重に扱う

発行と確認（`Packages/NonetKit` で動かす）:

```bash
swift run nonet-license issue --key ~/Nonet-secrets/<秘密鍵のファイル> --name "山田 太郎" --email taro@example.com
swift run nonet-license verify --public ../../Config/Nonet.xcconfig "<発行したキー>"
```

- `issue` は発行したキーを、今いるフォルダから上にたどって見つけた `Config/Nonet.xcconfig` の `NONET_LICENSE_PUBLIC_KEY`（アプリに入る公開鍵）と、秘密鍵と同じフォルダの `nonet-license.public-key` で検証し、どちらかと合わなければ発行しない。鍵を作り直したのに xcconfig の公開鍵が古いまま、といった間違いで、だれも登録できないキーを配らないためである。xcconfig の公開鍵が `//` の所で切れていても止まる（1.6）
- リポジトリの外で動かすときは、`--public <リポジトリ>/Config/Nonet.xcconfig` でアプリの公開鍵を渡す（`--public` には base64 の公開鍵か、そのファイルか、`.xcconfig` を渡せる）
- `--public` を付けても、リポジトリの中なら xcconfig のアプリの公開鍵とも比べ、違えば発行しない（売上の自動化で毎回 `--public` を付けていて、鍵の組を作り直したのに xcconfig が古いまま、といった間違いで使えないキーを配らないため）。前の鍵の組で作った古い版のアプリ向けに、分かったうえで発行するときだけ `--skip-app-key-check` を付ける
- `verify` とアプリは、キーの前後に付いた「License key:」や「License Key」（改行）のような見出し・引用符・かっこ・メールの引用の「>」・文末の句点を無視して、キーの部分（`eyJ` で始まる）を取り出す。キーの形の部分が2つ以上あれば、中身が Nonet のライセンスとして読めるもの（メールのリンクの JWT などは除く）がちょうど1つのときだけ使う

### 1.6 Config/Nonet.xcconfig

販売用の7つの値を入れてコミットする（公開鍵・URL・問い合わせ先なので、公開されても問題ない）。

```
NONET_APPCAST_URL = https:/$()/nonet.astlog.dev/updates/appcast.xml
NONET_SPARKLE_PUBLIC_KEY = <generate_keys の公開鍵>
NONET_PURCHASE_URL = https:/$()/nonet.astlog.dev/buy.html
NONET_SUPPORT_URL = https:/$()/nonet.astlog.dev/guide.html
NONET_PRIVACY_URL = https:/$()/nonet.astlog.dev/privacy.html
NONET_LICENSE_PUBLIC_KEY = <nonet-license keygen の公開鍵>
NONET_SUPPORT_EMAIL = <問い合わせを受けるメールアドレス>
```

`NONET_SUPPORT_EMAIL` は、設定の「Nonet」のタブと、ライセンスキーを登録できなかったときのエラーの横に出る「お問い合わせ…」の宛先になる（Info.plist の `NonetSupportEmail`）。押すと、件名「Nonet <版> のお問い合わせ」と、アプリの版・macOS の版・Mac の機種・キーボードの種類（JIS / ANSI / ISO）だけを書いた本文で、メールのアプリが開く（ライセンスキーやプロファイルの中身は入れない）。`support@nonet.astlog.dev` のようなアドレスだけを書き、`mailto:` は付けない。空のままだとボタンを出さない。プライバシーポリシー（[privacy.md](privacy.md) の「お問い合わせ」）と販売ページの問い合わせ先も同じアドレスにする。`scripts/release.sh` は、空・メールアドレスの形でない・`example.com` などの仮の値のときに止まり、書き出したアプリの Info.plist の値も確かめる。

`NONET_PURCHASE_URL` は、メニュー・設定の「Nonet」のタブ・試用が終わったときのウインドウの「購入する」が開く購入のページ（`site/buy.html`。2026-11-08 に埋めた）。利用ガイドやプライバシーポリシーと同じサイトのページなら、アプリが英語で動いているときは英語のページ（`site/en/buy.html`。ドルの価格）を開く。販売サービスなどほかの場所のページは、言語にかかわらずそのまま開く。

`NONET_SUPPORT_URL` と `NONET_PRIVACY_URL` は設定の「Nonet」のタブの「利用ガイド」「プライバシー」のリンクになる。日本語のページ（`site/guide.html`・`site/privacy.html`）を指しておく。アプリが英語で動いているときは、最後の要素の前に `en/` を入れた英語のページ（`https://nonet.astlog.dev/en/guide.html`。`site/en/guide.html`）を開く。`#troubleshooting` のような節へのリンクは、日本語と英語で同じ id にしてある。

Debug ビルド（開発用。`scripts/build.sh`・Xcode の実行）は、`NONET_APPCAST_URL` だけ `project.yml` で空にしてある（Debug の設定の上書き）。同じ bundle ID の製品版を入れた Mac で、開発用のビルドが本番の appcast からアップデートを受け取らないようにするためである。空にすると Info.plist の `SUFeedURL` が空になり、アプリは Sparkle を動かさない。メニューの「アップデートを確認」・「アップデートがあります…」とアイコンの印・設定の「Nonet」のタブのアップデートの確認は、配信先が無いときと同じで出ない。Release（`scripts/release.sh`）はこの xcconfig の値のままで、書き出したアプリの `SUFeedURL` を確かめる。

`.html` は省かない（`…/guide` ではなく `…/guide.html`）。S3 ＋ CloudFront のように `.html` を補わないホストでは、省いた URL は 404 になる。`scripts/check-site.sh` は、ホストが `site/index.html` の canonical と同じなら、`.html` を省いた URL を問題として知らせる（1.8）。

**xcconfig では `//` から後ろがコメントになる**。URL は `https:/$()/…` と書く（`$()` は空文字に展開される）。`https://…` と書くと `https:` で切れ、アップデートの確認も購入ページも動かない。公開鍵（base64）にも `//` が入ることがあり（約1%）、そのときも `//` を `/$()/` と書く。`scripts/release.sh` と `nonet-license issue` は、これらの切れ方を見つけて止まる。

### 1.7 配布の場所

販売ページとアップデートは `https://nonet.astlog.dev` から配る（Cloudflare の Worker と R2。astlog.dev と同じアカウント）。何がどこにあるか・最初の準備・上限と費用・戻し方は [hosting.md](hosting.md)。

- appcast.xml の URL は `https://nonet.astlog.dev/updates/appcast.xml`（`NONET_APPCAST_URL`）。一度出したら変えない。変えるときは古い URL からリダイレクトし続ける
- DMG とデルタは appcast と同じ場所（例: `https://nonet.astlog.dev/updates/Nonet-1.0.0.dmg`）。`NONET_DOWNLOAD_URL_PREFIX` は設定しない（Worker は `/updates/` の下しか配らず、`scripts/publish.sh` も別の URL を指す appcast は上げない）
- 無いファイルには 404 を返す（`cloudflare/wrangler.toml` の `not_found_handling = "404-page"`）。無いファイルにも 200 で `index.html` を返す設定（SPA 向けのフォールバック）にすると、スクリプトが公開中の appcast を確かめられずに止まる
- 販売ページの「ダウンロード」は、ダウンロードのページ（`thanks.html`・`en/thanks.html`。インストールの3つの手順つき）を指し、そのページが `https://nonet.astlog.dev/download` を開く。Worker が appcast の最新の DMG へリダイレクトするので、リリースのたびに書き換えなくてよい
- 販売ページとアプリの「購入する」は、購入のページ（`buy.html`・`en/buy.html`）を開き、そのページが Paddle の購入画面を開く（3.6）
- `site/` には利用ガイド（`guide.html`・`en/guide.html`）とプライバシーポリシー（`privacy.html`・`en/privacy.html`）も入っている。アプリの「利用ガイド」「プライバシー」が開くページで、Worker が販売ページと一緒に配る
- 最初の準備（R2・バケット `nonet-updates`・API トークン・DNS・最初のデプロイ・GitHub の environment）は hosting.md の「2. 最初の準備」

### 1.8 販売ページの仮の値を埋める

`site/` の仮の値はすべて埋めた（価格・販売サービスの名前・購入のページは 2026-11-08、問い合わせ先と特商法の電話番号の表記と Paddle の本番のトークン・価格の ID は 2026-11-15）。埋めた値を変えるときも、下の表の場所をそろえる。

| 仮の値 | 場所 | 埋めるもの |
|---|---|---|
| 価格（2026-11-08 に決めて埋めた） | `index.html`・`en/index.html` の価格と head の JSON-LD の `offers`、`tokushoho.html` の販売価格 | ¥1,480（税込）・$9.99（税は別）。変えるときは全部をそろえる（`scripts/tests/site_test.sh` の `test_price_is_the_same_everywhere` が確かめる） |
| 販売サービス（2026-11-15 に埋めた）: `data-paddle-token`（`live_…`）・`data-paddle-price`（`pri_…`） | 購入のページ（`buy.html`・`en/buy.html`。同じ値） | Paddle のクライアント用トークンと価格の ID（3.6）。作り直したら両方のページを直す |
| 問い合わせ先（2026-11-15 に `support@astlog.dev` で埋めた） | 各ページのフッター・よくある質問・利用規約・特商法の表記・プライバシーポリシー・`NONET_SUPPORT_EMAIL` | 変えるときは全部をそろえる（利用ガイドのフッターは `scripts/build-guide.py` で直す）。Cloudflare の Email Routing で Gmail に転送する |

```bash
scripts/check-site.sh --strict   # 上の仮の値が1つでも残っていれば失敗
```

`--strict` でも止めないものが1つある。よくある質問の「確認済みの macOS」（`data-placeholder="tested-macos"`）で、リリースのたびに実物で確かめた版を書く（「2.7 確かめる」）。`scripts/check-site.sh` は、残っていれば知らせる。

見出し（`index.html` の h1）や HUD の静止画（`site/images/hud-xcode.webp`）を変えたら、共有の画像を作り直す（Google Chrome と sips を使う）:

```bash
python3 -I scripts/make-site-images.py   # site/images/og-ja.png・og-en.png（1200×630）と site/apple-touch-icon.png（180×180）
```

`scripts/check-site.sh` は、`Config/Nonet.xcconfig`（`--config <xcconfig>` でほかのファイルも選べる）の `NONET_SUPPORT_URL`・`NONET_PRIVACY_URL`・`NONET_PURCHASE_URL` のホストが `site/index.html` の canonical と同じなら、そのページが `site/` にあるか、英語で動くアプリが開くページ（最後の要素の前に `en/` を入れたもの。購入のページはそのまま開くので見ない）もあるか、`.html` を省いていないかを確かめる。`--strict` では、これらの URL を入れたのに `site/index.html` に canonical が無い（確かめられない）ときも失敗にする。

### 1.9 Sparkle の版を上げる

`project.yml` は Sparkle を `exactVersion: "2.10.1"` で固定している（Package.resolved は Nonet.xcodeproj の中にできてコミットしないので、固定しないと新しい Mac や CI で、試していない版のアップデートの仕組みと `generate_appcast` になる）。`scripts/release.sh` は解決した版を表示する。上げるときは:

1. Sparkle のリリースノートで、変わったところ（設定のキー・appcast の書き方・最低の macOS）を確かめる
2. `project.yml` の `exactVersion` を書き換え、`scripts/build.sh` でパッケージを解決し直す（`generate_appcast` と `generate_keys` も新しい版になる）
3. `scripts/test.sh` を通し、dry run（2.4）の後、一つ前の版から新しい版へ Sparkle でアップデートできることを確かめる
4. `project.yml` をコミットする

---

## 2. リリースごとの手順

### 2.1 版を決める

| 値 | 例 | 決め方 |
|---|---|---|
| バージョン（`MARKETING_VERSION`） | `1.2.0` | 利用者に見せる版。`1.2` か `1.2.3` |
| ビルド番号（`CURRENT_PROJECT_VERSION`） | `42` | Sparkle は**ビルド番号**で新旧を比べる。毎回、公開済みのものより大きい整数にする |

`project.yml` は書き換えない（スクリプトが xcodebuild の設定として渡す）。

### 2.2 リリースノートを書く

`.html`・`.md`・`.txt` のどれかで短く書く（例: `notes/1.2.0.md`）。Sparkle のアップデートの画面に出る。HTML なら `<body>` などを付けない断片にする。

`--notes` に渡したファイルは、リポジトリの中にあってもコミットしていなくてよい（本番の「コミットしていない変更」の確認から、このファイルだけは外す。アプリには入らないため）。残しておくなら、本番の後、タグを付ける前にコミットする。ほかのファイルに変更があれば、これまでどおり本番は止まる。

### 2.3 文言の英語

画面の文言を足したり変えたりしたら、カタログに集めて英語の訳を入れる。`scripts/test.sh`（CI も）は `scripts/sync-strings.sh --check` で、コードの文言がカタログに無いか英語の訳が無いと失敗する（入れ忘れると、英語の利用者に日本語のまま出る）。

```bash
scripts/sync-strings.sh          # 各ターゲットの Localizable.xcstrings に集める
scripts/sync-strings.sh --check  # カタログを書き換えずに、足りない文言を表示する
```

### 2.4 試しに通す（dry run）

```bash
scripts/release.sh --dry-run 1.2.0 42
```

公証とステープルを飛ばし、署名した DMG と appcast の試し版を `build/release/1.2.0/` に作る。公開用のフォルダには触れない。**この DMG は公証していないので配らない**。

### 2.5 本番

```bash
NONET_NOTARY_PROFILE=nonet-notary scripts/release.sh --notes notes/1.2.0.md 1.2.0 42
```

**初めてのリリースだけ** `--first-release` を付ける（dry run でも同じ）。公開中の appcast が無い（`NONET_APPCAST_URL` が 404 か 410 を返す）とき、このオプションが無ければスクリプトは止まる。URL の書き間違いや、`NONET_RELEASES_DIR` の appcast.xml が無い状態で、過去の版の項目が消えた appcast を作って公開中のものを上書きしないためである。

```bash
NONET_NOTARY_PROFILE=nonet-notary scripts/release.sh --first-release --notes notes/1.0.0.md 1.0.0 1
```

始めに、ビルドするコミット（ハッシュ）・ブランチ・コミットしていない変更の有無を表示する（公開する DMG の元になるもの）。本番は**きれいな `main` のコミット**からだけ出せる。`main` 以外のブランチ（detached HEAD を含む）なら `--allow-branch` が、コミットしていない変更があれば `--allow-dirty` が要る。dry run はどちらも警告するだけで止まらない。`.claude/` の中の未追跡のファイルは、コミットしていない変更に数えない（追跡しているファイルの変更は数える）。このコミットを含むリモートのブランチが手元に無ければ、push していない警告を出す（手元の `origin/*` の情報だけを見て、ネットワークは使わない。止めはしない）。タグは公開のあとに付ける（2.8）。

スクリプトがすること:

1. 準備の確認（コマンド・Developer ID 証明書・macOS SDK に FoundationModels があるか・`Config/Nonet.xcconfig` の値・notarytool のプロファイル・ブランチが `main` か・コミットしていない変更。`--notes` のファイルは除く。公開用のフォルダにすでに `Nonet-<バージョン>.dmg` があるか・手元の appcast.xml にすでに同じ版の項目があるか）。足りないものをまとめて表示して止まる（dry run でも、ブランチと変更と notarytool のプロファイル以外は同じ。dry run が通っても、公証の設定ができているとは限らない）
2. XcodeGen でプロジェクトを作り、パッケージを解決する（Sparkle は `project.yml` で固定した版。1.9）
3. キーチェーンの Sparkle の鍵が `NONET_SPARKLE_PUBLIC_KEY` と一致するか、ビルド番号が appcast の最大より大きいかを確かめる。appcast は毎回、公開中のもの（`NONET_APPCAST_URL`）を作業用フォルダ（`build/release/<バージョン>/published-appcast.xml`）に取ってきて、手元の appcast.xml とビルド番号（`sparkle:version`）で比べる
   - 手元に無ければ、公開中のものを使う
   - 公開中のものにあって手元に無いビルドがあれば止まる（別の Mac やバックアップの古い appcast から作って、公開中の項目を消したり、公開済みと同じビルド番号を出したりしないため）
   - 手元の方がビルドが多いだけなら、警告して手元のものを使う（前のリリースの appcast をまだアップロードしていない、または CDN がアップロードの前の appcast をまだ返している。どちらも手元のものが新しい）
   - ビルドが同じで中身が違えば、空白・改行の違いだけなら手元のものを使い、それ以外（公開中のものをサーバーで直したなど）は止まる
   - 取れなければ（403・503・ネットワークのエラーなど）止まる。dry run では警告して、手元のものを使って続ける（何も公開しないので）。404・410 で新しく作る（または手元のものを引き継ぐ）のは `--first-release` のときだけ
   - 手元の appcast か公開中の appcast に、同じ版（`sparkle:shortVersionString`）か同じ DMG の URL（`<DMG の URL の前半>Nonet-<バージョン>.dmg`）の項目がすでにあれば止まる。公開した版の番号は使い回せない（DMG の名前は版で決まるので、出し直すと公開済みの DMG を上書きし、appcast に同じ URL を指す項目が2つでき、後の差分も作れなくなる）
4. `xcodebuild archive`（Release・Developer ID Application・hardened runtime・`--timestamp`）
5. `ExportOptions.plist`（`method` は `developer-id`）で書き出す
6. 署名を確かめる: `codesign --verify --deep --strict`、Developer ID・チーム・タイムスタンプ・hardened runtime、中の Mach-O（Sparkle 本体・XPC サービス・Autoupdate・Updater.app、アプリの `Contents/MacOS`・`XPCServices` など）の Developer ID とタイムスタンプ、そのうち実行ファイルの hardened runtime（dylib は見ない。公証はどの実行ファイルにも hardened runtime を求める）、Info.plist の版と販売用の値。続けて中身を確かめる（どれも公証に出す前に止める）:
   - アプリの実行ファイルに、DEBUG ビルドだけのコード（`#if DEBUG` の中の `DemoSession`・`DebugPreview` などの型の名前と、そこだけが出す文言）が入っていないこと（`strings -a`。印の一覧は release.sh の `DEBUG_ONLY_MARKERS`）。起動引数の名前（`--demo-script` など）は NonetUI の `ShellLaunchOptions` がどのビルドでも読むので印にしない。Release のコードが読んでよい起動引数が `--self-check` だけであることは、静的なテスト（`scripts/tests/launch_options_test.sh`）が確かめる
   - 署名に `com.apple.security.get-task-allow`（Debug ビルドの署名。ほかのプロセスがデバッガーでつなげる）が付いていないこと（`codesign -d --entitlements :-`）
   - 書き出したアプリを `Contents/MacOS/Nonet --self-check` で実際に動かし、JSON の `ok` が `true`（終了コードも 0）と報告すること。終わらなければ `NONET_SELF_CHECK_TIMEOUT` 秒（既定 60）で止める
7. アプリを zip にして `xcrun notarytool submit --wait` で公証し、`stapler staple` してから `spctl -a -vv` で Gatekeeper の評価を確かめる
8. DMG を作る（ボリューム名 `Nonet`、`/Applications` へのリンクつき）→ 署名 → 公証 → ステープル → `spctl` で確認
9. DMG とリリースノートを公開用のフォルダ（`NONET_RELEASES_DIR`、既定 `build/releases`）に入れ（同じ名前の DMG があれば上書きせずに止まる）、`generate_appcast` で appcast.xml を更新する（`NONET_APPCAST_URL` のファイル名にかかわらず、手元の名前は `appcast.xml`）

公証が通らなければ、notarytool のログを表示して止まる。作業用のファイルとログは `build/release/<バージョン>/` に残る。

| 環境変数 | 既定 | 意味 |
|---|---|---|
| `NONET_NOTARY_PROFILE` | なし（本番では必須） | notarytool のキーチェーンのプロファイル名 |
| `NONET_RELEASES_DIR` | `build/releases` | 公開する DMG・デルタ・appcast.xml を貯めるフォルダ |
| `NONET_DOWNLOAD_URL_PREFIX` | appcast.xml と同じ場所 | appcast に書く DMG の URL の前半 |
| `NONET_SPARKLE_KEY_ACCOUNT` | `ed25519` | Sparkle の秘密鍵のキーチェーンのアカウント名 |
| `NONET_NOTARY_TIMEOUT` | `1h` | 公証の結果を待つ上限 |
| `NONET_SELF_CHECK_TIMEOUT` | `60` | 書き出したアプリの `--self-check` を待つ上限（秒） |

オプション: `--dry-run`（公証しない）、`--notes <ファイル>`（リリースノート）、`--first-release`（初めてのリリース。公開中の appcast が無ければ新しく作る）、`--force-local-appcast`（公開中の appcast を取ってこずに、手元の appcast.xml をそのまま使う。手元のものが正しいと分かっているときだけ）、`--allow-dirty`（コミットしていない変更があっても続ける。本番はこれが無いと止まる）、`--allow-branch`（`main` 以外のブランチから出す。本番はこれが無いと止まる）、`--help`。

`NONET_RELEASES_DIR` には過去の DMG と appcast.xml が貯まる。Sparkle は古い版との差分（`*.delta`）をここで作る。appcast にはすべての版の項目を残す（`generate_appcast --maximum-versions 0`。既定の 3 だと古い版の項目を消して DMG を `old_updates/` に移すので、出した版の番号を使い直さない確かめが効かなくなる）。公開中の appcast.xml はスクリプトが毎回取ってきて比べるので `build/` を消しても困らないが、差分を作るには過去の DMG が要るので、バックアップされる場所を指定しておくとよい。

### 2.6 アップロード

`scripts/publish.sh` で上げる（先に一度 `cd cloudflare && npm ci`）。

```bash
scripts/publish.sh --dry-run 1.2.0   # 確かめて、上げるものを表示するだけ
scripts/publish.sh 1.2.0
```

順番が大事（appcast が先に出ると、まだ無い DMG を指してしまう）。スクリプトはこの順でしか上げない。

1. `Nonet-1.2.0.dmg`
2. appcast のその版の項目にあるデルタ（`*.delta`）のうち、まだ同じ中身が上がっていないもの
3. 最後に `appcast.xml`（`old_updates/` は上げない）

上げる前に、DMG と appcast が合っているか（URL・大きさ・最新か）と、公開中の appcast が手元より新しくないかを確かめ、公開中の appcast を `NONET_RELEASES_DIR/appcast-history/` に控える。DMG そのものも確かめる（`codesign --verify`・`xcrun stapler validate`・`spctl -a -t open --context context:primary-signature`）。公証の前の DMG（dry run で作ったもの）や署名の壊れた DMG は上げない。appcast の項目（DMG とデルタ）に `sparkle:edSignature` が無いときも上げない（署名の無い更新を Sparkle は受け付けない）。上げたあとに、公開中の appcast にその版があること、DMG の URL が 200 で大きさが合うこと、`/download` がその DMG へ飛ぶことを確かめる。販売ページはリリースのたびに書き換えなくてよい（確認済みの macOS を書き換えたときは 2.7 のとおりデプロイする）。詳しくは [hosting.md](hosting.md) の「3. リリースごとの手順」。

### 2.7 確かめる

- 公開した URL から DMG をダウンロードし、別のユーザーか別の Mac で開く。Gatekeeper の警告が出ずに起動すること
- 一つ前の版を起動し、メニューの「アップデートを確認」で新しい版が見つかり、入れ替わること
- `curl -I <appcast の URL>` が 200 を返すこと
- **確認済みの macOS**: 試した macOS の版（例: `macOS 14.7・15.6・26.1`）を、販売ページのよくある質問「macOS のアップデートで使えなくなることはありますか？」（`site/index.html`・`site/en/index.html` の `data-placeholder="tested-macos"`）に書き、`data-placeholder` と `class="todo"` と、その段落の `hidden` を外す（埋めるまでは `hidden` で買う人には見せない）。実際に試した版だけを書く。新しい macOS のベータが出たら、ベータのうちに試して直す（ページでそう約束している）。直せないまま使えない状態が続くなら、購入からの日数にかかわらず返金する（利用規約の 6）。書き換えたら main に入れ、GitHub の Actions › site › Run workflow でサイトに出す（publish.sh はページを上げない。[hosting.md](hosting.md) の「3. リリースごとの手順」の「ページだけを変えたとき」）

### 2.8 タグを付ける

```bash
git tag -a v1.2.0 -m "Nonet 1.2.0"
git push origin v1.2.0
```

### 2.9 困ったとき

| 症状 | 確かめること |
|---|---|
| 公証が `Invalid` | スクリプトが出すログを見る。よくあるのは、署名の無い実行ファイル・タイムスタンプが無い・hardened runtime が無い。`xcrun notarytool log <ID> --keychain-profile "$NONET_NOTARY_PROFILE"` でもう一度見られる |
| `spctl` が `rejected` | 公証とステープルが済んでいるか（`xcrun stapler validate`）。dry run では rejected が正常 |
| 「ビルド番号 … は、appcast に載っている最大の … より大きくしてください」 | 公開済みより大きい番号にする。公開していない試しの項目なら appcast.xml から消す |
| 「…には、すでに版 … の項目があります」・「すでに同じ DMG の URL（…）の項目があります」 | 公開した版を出し直そうとしている（版を上げ忘れて、ビルド番号だけ上げたなど）。**版（バージョン）を上げて**出す（例: `1.2.0` を直すなら `1.2.1` とビルド番号 43）。公開した DMG と appcast の項目はそのまま残す（利用者の手元の版との差分に要る）。その版をまだどこにも公開しておらず、作り直したいときだけ: 公開中の appcast にその版が無いことを `curl -s <appcast の URL>` で確かめてから、手元の appcast.xml からその版の `<item>` を消し、`NONET_RELEASES_DIR` の `Nonet-<バージョン>.dmg`・同じ名前のリリースノート・その版の `*.delta` を消してやり直す |
| 「…/Nonet-<バージョン>.dmg がすでにあります」 | 公開済みの DMG は上書きしない。版を上げて出す。前の本番が DMG を入れた後（appcast の更新）で失敗し、appcast にその版の項目が無く、どこにも上げていないなら、その DMG を消してやり直す |
| 同じ版を2回出してしまった（appcast に同じ URL を指す項目が2つ。`publish.sh` が「… を指す項目が 2 個」で止まる） | 古いスクリプトで出したときだけ起こる。上げずに直す: `NONET_RELEASES_DIR/appcast-history/` かサーバーの公開中の appcast.xml を手元の appcast.xml に戻し（公開中のものをそのまま使う）、上書きされた `Nonet-<バージョン>.dmg` は公開中のもの（`curl -o <DMG の URL>`）で戻す。新しく作った方の `*.delta` も消す。そのあと版を上げて出し直す |
| 「… で hardened runtime が有効になっていません」 | 公証に出す前に止めている（公証はどの実行ファイルにも hardened runtime を求める）。Sparkle の版上げや書き出しの設定で、中の実行ファイルの runtime が落ちていないか（`codesign -dvv <ファイル>` の `flags=` に `runtime`） |
| 「公開中の appcast が見つかりません（HTTP 404）」 | 初めてのリリースなら `--first-release` を付ける。公開済みなら `NONET_APPCAST_URL` が公開中の URL と同じか確かめる。分からなければ、公開中の appcast をダウンロードして `NONET_RELEASES_DIR/appcast.xml` に置き、`--force-local-appcast` を付ける |
| 「公開中の appcast を取得できませんでした（HTTP 403 など）」 | ホスティングのアクセス制限（ボット対策・権限）や一時的な障害。`curl -I <appcast の URL>` で確かめる。直せなければ、公開中の appcast を `NONET_RELEASES_DIR/appcast.xml` に置き、`--force-local-appcast` を付けてやり直す |
| 「手元の appcast に、公開中のビルド … がありません」 | 手元のものが古い（別の Mac・バックアップ）。手元の appcast.xml を消してやり直す（公開中のものを取ってくる）。手元が正しいと分かっているときだけ `--force-local-appcast` |
| 「同じビルドの項目の中身が違います」 | 公開中の appcast をサーバーで直したなら、手元の appcast.xml を消してやり直す。どちらが正しいかは、作業用フォルダの `published-appcast.xml` と `diff` で比べる |
| 「どちらにもあるビルドの項目の中身が違います」 | 手元の方がビルドが多く（まだ上げていない版がある）、そのうえ公開中の appcast をサーバーで直した。手元の appcast.xml を消して公開中のものを取ってきてから、手元にしか無かったビルドの項目を入れ直す（その版の DMG があれば、次の release.sh の generate_appcast が入れる）。どちらが正しいかは `published-appcast.xml` と `diff` で比べる |
| 「公開中のものに無いビルド … があります」（警告） | 前のリリースの appcast.xml をまだアップロードしていないなら、今回の appcast と一緒に、そのビルドの DMG もアップロードする。アップロードしたばかりなら CDN のキャッシュが古いだけ |
| 「App/ が試用の記録をキーチェーンに置いていません」 | プライバシーポリシーは製品版がキーチェーンの項目を作ると書いている。`App/AppDelegate.swift` で `UserDefaultsLicenseStorage(keychain: SystemTrialRecordKeychain(), marker: SystemTrialRecordKeychain.machineMarker(), evidence: FileTrialUsageEvidence.standard())` を使う（3.3）。キーチェーンを使わないことにしたなら、プライバシーポリシー（3つとも）からキーチェーンの項目を消す |
| 「--public の公開鍵が、アプリに入れる公開鍵（…）と違うため、発行しません」 | xcconfig の `NONET_LICENSE_PUBLIC_KEY` と `--public` の鍵が keygen で作った同じ組か確かめる。前の鍵の組の古い版のアプリ向けに発行するときだけ `--skip-app-key-check` |
| 「macOS SDK … に FoundationModels がありません」 | `xcode-select -p` が古い Xcode を指している。`sudo xcode-select -s /Applications/Xcode.app` で Xcode 27 以降（1.1）を選ぶ |
| 「… が「//」の所で切れています」 | 公開鍵の `//` を `/$()/` と書く（1.4・1.6） |
| 「中身が appcast（RSS）ではありません」 | 無いファイルにも 200 でページを返す設定になっていないか（1.7） |
| 「コミットしていない変更があります」 | `git status` で確かめる。`--notes` のファイルと、`.claude/` の中の未追跡のファイルは数えない。コミットしてから出す。変更ごと出すと決めているときだけ `--allow-dirty` |
| 「ブランチが main ではありません」 | `main` に切り替えて（またはマージして）出す。別のブランチから出すと決めているときだけ `--allow-branch`。タグ（2.8）は出したコミットに付けるので、そのコミットが `main` にあるようにする。dry run は警告するだけ |
| 「…に DEBUG ビルドだけのコード（…）が入っています」 | Release でないビルドを書き出していないか、`#if DEBUG` の外にデモやプレビューのコードが出ていないか。印は release.sh の `DEBUG_ONLY_MARKERS`。Swift の型の名前を変えたら、印も直す（`scripts/tests/release_test.sh` が、印が `#if DEBUG` の中にだけあることを確かめる） |
| 「…が com.apple.security.get-task-allow の付いた署名です」 | Debug の署名（Apple Development）のまま書き出していないか。`App/Nonet.entitlements` に `get-task-allow` を書かない |
| 「…--self-check が ok になりませんでした」 | 表示された `failures` を見る（`version`・`presets`・`launcherCandidates`・`configurationRoundTrip`・`multitouch`）。作業用フォルダ（`build/release/<バージョン>/`）の `self-check.json` と `self-check.err` に出力が残る。同じ確認は `scripts/test.sh` の最後（Debug のビルド）でも動く |
| 「DMG に問題があります」（`publish.sh`） | `codesign --verify`・`xcrun stapler validate`・`spctl -a -t open --context context:primary-signature -v` のどれが通らないかが出る。公証の前の DMG（dry run）を上げようとしていないか。`NONET_RELEASES_DIR` の DMG が、`release.sh` を `--dry-run` なしで通したものか |
| 「手元の appcast.xml の項目に Sparkle の署名がありません」（`publish.sh`） | `generate_appcast` が秘密鍵で署名できていない。キーチェーンの Sparkle の鍵（1.4）を確かめて、`release.sh` をやり直す |
| Sparkle の鍵が一致しない | 別の Mac や別のアカウント名で鍵を作っていないか。バックアップから `generate_keys -f` で取り込む |
| アップデートが見つからない | appcast の `sparkle:version` が今の版より大きいか、appcast と DMG の URL に HTTPS で届くか、`SUPublicEDKey` が鍵と一致しているか |

---

## 3. 販売とライセンスの届け方

アプリはキーをオフラインで確かめるので、販売の仕組みは「支払いを受けて、`nonet-license issue` と同じ形のキーを購入者に届ける」だけでよい。販売サービスは **Paddle（Paddle Billing。販売代理店 = Merchant of Record）** に決めた（2026-11-08）。キーは Paddle のライセンスキーの機能ではなく自前で発行し、nonet.astlog.dev の Worker が Paddle の通知を受けて自動で届ける（3.2。2026-11-15 に決めた）。キーはこれまでどおり Mac の中だけで確かめ、オンラインの認証（アクティベーション）はしない。Worker を設定するまでと、自動で届かなかったときは手動で届ける（3.1）。

ライセンス ID は **Paddle の取引の ID（`txn_…`）** にする。自動でも手動でも同じ ID になり、返金のときはその ID で無効にする（3.5）ので、発行の台帳は持たない。

Paddle にした理由（2026-11-08 に各社の公式ページで比べた。手数料と規約は申し込む前にもう一度確かめる）:

| | Paddle | Lemon Squeezy | Stripe Managed Payments |
|---|---|---|---|
| 手数料 | 5% + 50¢（海外の買い手も同じ） | 5% + 50¢、米国の外の取引は +1.5%、入金ごとに 1% | 3.5% + Stripe の決済手数料（日本 3.6%、通貨の換算 +2%） |
| 日本の購入者 | 円で決済、購入画面は日本語。日本の消費税 10% を集めて納めると明記 | 決済はすべて USD。日本の消費税の記載は無い | 日本の事業者が日本の購入者に売った分の税は対象外（自分で扱う） |
| これから | 通常どおり | Stripe Managed Payments への移行を公式に予告（2026） | 審査制 |

Stripe をそのまま使う（売主が自分）と手数料は最も安いが、各国の消費税・VAT・売上税の登録と申告を自分で背負うので選ばない。

Paddle で決まっていること（公式のヘルプと開発者向けの資料による）:

| 項目 | 内容 |
|---|---|
| 手数料 | 1回の決済ごとに 5% + 50¢。$10 未満の商品は個別に相談 |
| 入金 | 月1回（15日まで）、最低 $100（残りは繰り越し）。電信送金か Payoneer。残高の通貨は USD・EUR・GBP・AUD・CAD で、別の通貨で受け取ると最大 1.5% の換算、通貨をまたぐ送金は $15 |
| 審査（ドメイン） | 販売ページに、商品の説明・価格・利用規約・返金の方針・プライバシーポリシー（ナビゲーションから開ける）と HTTPS が要る。規約には個人の開発者の名前（法的な名前が望ましい）。多くは自動で承認、手動の審査は 5〜7 営業日。購入画面を開くドメインごとに申請する（nonet.astlog.dev） |
| 購入画面 | 承認したドメインのページで Paddle.js のオーバーレイを開く（3.6）。購入画面だけのリンク（hosted checkout）は別の承認が要る |
| 返金 | 売り手がダッシュボードか API で行う。確認済みのアカウントで $400 以下なら自動で承認、それ以外は Paddle の承認待ち |
| 売主 | 日本の購入者には Paddle.com Market Limited（30 Old Bailey, London, United Kingdom, EC4M 7AU）。Paddle Buyer Terms の「Rest of world」 |
| 消費税 | 日本の消費税 10% を事業者向け・個人向けとも Paddle が集めて納める。Paddle から受け取るお金の、自分の側の扱いは税理士に確かめる |

### 3.1 手動で届ける（Worker を設定するまで・自動で届かなかったとき）

```bash
cd Packages/NonetKit
swift run nonet-license issue --key ~/Nonet-secrets/<秘密鍵のファイル> --name "購入者の名前" --email buyer@example.com --id txn_…
```

- `--id` には Paddle の取引の ID（Paddle › Transactions の `txn_…`。Paddle からの販売のメールにもある）を渡す。Worker が届けるキーと同じライセンス ID になり、返金のときはこの ID で無効にする（3.5）
- `--name` は Paddle の顧客（Customers）の名前。名前が無ければ（Paddle の購入画面は名前を聞かないことが多い）メールアドレスを入れる（Worker と同じ）
- 手で発行したキーは、Worker が同じ取引から作るキーと署名の部分が違う（`nonet-license` の CryptoKit は署名に毎回乱数を混ぜる）。どちらも有効で、ライセンス ID も同じ
- Worker を設定してあれば、発行する代わりに `curl -s 'https://nonet.astlog.dev/api/license?transaction_id=txn_…'` で、自動で届けたものと同じキーを取り出せる（3.2）

送る文面の例（`<キー>` は発行したキー。キーは base64url と `.` だけなので、URL にそのまま入れられる）:

> Nonet をご購入いただきありがとうございます。
>
> Nonet を入れた Mac で、次のリンクを開くと登録できます。
>
> Nonet に登録する: nonet://register?key=<キー>
>
> リンクを開けないときは、メニューバーの Nonet のアイコンから「ライセンスキーを入力…」を選び、次のライセンスキーを貼り付けて「登録」を押してください。
>
> ライセンスキー: <キー>
>
> ライセンス ID: <ライセンス ID>（問い合わせのときにお知らせください。登録には使えません）
>
> 1つのライセンスで、あなたが使うすべての Mac に使えます。キーはこの Mac の中だけで確認され、ネットワークには送られません。

- リンクやファイルを開くと、Nonet は設定の「Nonet」のタブにキーを入れ、登録者を見せて「このライセンスキーを登録しますか？」と尋ねる（黙っては登録しない）。HTML のメールなら「Nonet に登録する」をリンクの文字にしてよい
- キーを書いたテキストファイルを `<名前>.nonetlicense` として添えてもよい（UTF-8、64 KiB まで。「License key:」などの前後の文があってもキーだけを読む）。開くとリンクと同じように尋ねる
- ライセンス ID を貼り付けられたときは、アプリが「これはライセンス ID です」と知らせる。キーと ID は別の行に書く

support@astlog.dev は受け取るだけ（Cloudflare Email Routing）なので、手動のメールは開発者のメールから送り、返信先を support@astlog.dev にする。発行の記録は要らない（取引の ID・名前・メールアドレスは Paddle に残り、キーはそこから作り直せる）。

### 3.2 自動で届ける（Worker）

nonet.astlog.dev の Worker（`cloudflare/src/licensing.js`）が、Paddle の通知を受けてキーを作り、購入者にメールで送る。購入のページにも、購入が済んだその場でキーを出す。キーは何も保存しない。

**仕組み**

| URL | 呼ぶもの | すること |
|---|---|---|
| `POST /api/paddle/webhook` | Paddle（通知） | `transaction.completed` で、キーを作って購入者にメールで送る。承認された返金・チャージバックで、開発者に知らせる |
| `GET /api/license?transaction_id=txn_…` | 購入のページ（`site/buy.js`） | 済んだ取引なら、そのキーを JSON（`license_key`・`license_id`）で返す |

1. 購入が済むと、Paddle が `transaction.completed` の通知を送る
2. Worker が `Paddle-Signature: ts=<UNIX 時刻>;h1=<16進>` を確かめる。`ts + ":" + 受け取ったままの本文` を通知先の秘密（`pdl_ntfset_…`）で HMAC-SHA256 したものと、かかる時間が中身によらない比べ方（`crypto.subtle.verify`）で比べる。時刻のずれは前後5秒まで（Paddle の既定と同じ）。秘密を入れ替えている間に `h1` が2つ来ても、どちらかが合えば通す。合わなければ 401 で何もしない
3. Nonet の価格（`PADDLE_PRICE_ID`）を含む取引だけを受け持つ。ほかの商品・ほかの種類の通知には 200 を返して何もしない（2xx でないと Paddle が送り直し続ける）
4. Paddle の API で取引を読み直し（`GET /transactions/{id}?include=customer`。顧客が含まれていなければ `GET /customers/{id}`）、状態が `completed` で Nonet の価格があることを確かめる。通知には購入者の名前とメールアドレスが入らないので、顧客はここで読む
5. `LicenseInfo` を作る: `licenseID` は取引の ID、`licensee` は顧客の名前（`null` か空ならメールアドレス。制御文字は空白にする）、`email` は顧客のメールアドレス、`edition` は `standard`、`issuedAt` は取引の `billed_at`（無ければ `created_at`）を秒まで。JSON は `nonet-license` と1バイトも違わない（`scripts/tests/license_test.sh` が、Worker のキーを `nonet-license verify` で確かめ、`issue` のキーと JSON の部分を比べる）
6. 秘密鍵で Ed25519 の署名をし（WebCrypto。`nonet-license` の 32 バイトの秘密鍵を PKCS#8 にして読む）、アプリの公開鍵（`LICENSE_PUBLIC_KEY`）で確かめてから、購入者にメールで送る（Resend。差出人 `Nonet <support@astlog.dev>`、返信先 `support@astlog.dev`。文面は 3.1 と同じで、日本語のあとに英語。HTML のメールでは「Nonet に登録する」がリンク）
7. 送れたら 200。Paddle の API やメールが失敗したら 502 などを返すので、Paddle が時間をおいて送り直す（Resend の DNS を直すのが遅れても、送り直しで届く）

- **同じ取引からは、何度作っても同じキーになる**（WebCrypto の Ed25519 の署名は RFC 8032 のとおり決まった値。中身は取引と顧客だけで決まる）。だから保存しなくてよく、ページと通知で同じキーになる。顧客のメールアドレスや名前を Paddle で変えると、その後に作るキーは中身が変わる（ライセンス ID は同じで、どちらも有効）
- **メールが二重に届くことがある**: 同じ取引のメールは Resend の `Idempotency-Key`（`nonet-license/<取引の ID>`）で 24 時間のうちは1通にまとめる。それでも、200 が Paddle に届かずに 24 時間より後に送り直されたときや、Paddle の画面から送り直したときは、同じキーのメールがもう1通届く（受け入れる）
- **購入のページ**: Paddle.js の `checkout.completed` で、`buy.js` が取引の ID で `/api/license` に聞き、キー・「キーをコピー」・「Nonet に登録する」（`nonet://register?key=…`）を出す。Worker は API で取引を確かめ、`completed` で Nonet の価格なら返す。支払いの直後でまだ `completed` でなければ 409 を返し、`buy.js` は 1・2・3・5・8 秒あとに聞き直す。聞けない（設定していない・失敗した）ときは「遅くとも24時間以内にメールで届く」という案内のまま。CSP はこの2つのページだけ `connect-src 'self'` を足した（`site/_headers`）
- **取引の ID を知っている人は、その購入者のキーを取り出せる**。取引の ID は推測できない（`txn_` と 26 文字）が、知っているのは購入者・Paddle・開発者だけにしておく（取引の画面のスクリーンショットを共有しない）。Workers Logs には、要求の URL（取引の ID を含む）が3日残る（[hosting.md](hosting.md)「6. 上限と費用」）。返金した取引でも、キーは返し続ける（アプリは無効にした一覧で止める。3.5）
- **返金・チャージバック**: `adjustment.created`・`adjustment.updated` で、承認された（`approved`）`refund` か `chargeback` が Nonet の取引のものなら、support@astlog.dev に「`nonet-license revoke txn_…`」の知らせを送る。無効にするのは手で行う（3.5）。一部だけの返金（`partial`）も知らせるので、キーを使い続けてもらうかを決める
- **キーをなくした人に送り直す**: `curl -s 'https://nonet.astlog.dev/api/license?transaction_id=txn_…'` で同じキーを取り出して送るか、Paddle › Developer tools › Notifications の通知のログから、その取引の `transaction.completed` を送り直す
- **設定が1つでも欠けていれば**、`/api/*` は 503 を返すだけで何もしない（ページとアップデートの配布は変わらない。購入のページはメールで届くという案内のまま）。足りない名前は Workers Logs（ダッシュボードの Workers & Pages › nonet › Logs）に出る。秘密の値はログに出さない
- Workers の無料プランの CPU（1回 10ms）: 署名と HMAC は 1ms ほど。API とメールを待つ時間は数えない

**設定**

| 名前 | 置き場所 | 中身 |
|---|---|---|
| `PADDLE_API_KEY` | 秘密（`wrangler secret put`） | Paddle の API キー。`pdl_live_apikey_…` なら本番、`pdl_sdbx_apikey_…` なら sandbox の API を使う。権限は `transaction.read` と `customer.read` だけ |
| `PADDLE_NOTIFICATION_SECRET` | 秘密 | 通知先の秘密（`pdl_ntfset_…`） |
| `LICENSE_PRIVATE_KEY` | 秘密 | `nonet-license keygen` の秘密鍵（`nonet-license.private-key` の中身。base64 の1行） |
| `RESEND_API_KEY` | 秘密 | Resend の API キー（送信だけ・astlog.dev だけ） |
| `LICENSE_PUBLIC_KEY` | `cloudflare/wrangler.toml` の `[vars]` | アプリの公開鍵。`NONET_LICENSE_PUBLIC_KEY`（1.6）と同じ値にする（`cloudflare/test/licensing.test.js` が確かめる）。鍵を作り直したら、ここも直す |
| `PADDLE_PRICE_ID` | `wrangler.toml` の `[vars]` | Nonet の価格の ID。`buy.html` の `data-paddle-price` と同じ（同上） |

**持ち主がすること**（sandbox で通してから本番に入れる）

1. **メールの送り元（Resend）**: https://resend.com でアカウントを作る。Domains で `astlog.dev` を足し（地域は Tokyo でよい）、表示された DNS のレコード（DKIM の TXT と、送信用のサブドメインの MX・SPF の TXT）を Cloudflare の astlog.dev の DNS に足して、Verified になるのを待つ。受信の Cloudflare Email Routing の MX・SPF は astlog.dev そのものにあり、Resend のものはサブドメインに置くのでぶつからない。API Keys で、権限を Sending access、ドメインを astlog.dev だけにしたキーを作る。無料のプランの1日・1か月の通数の上限を確かめておく
2. **sandbox で試す**（手元の Worker で。本番の Worker には何も置かない）
   1. sandbox の Paddle（3.6 の 1）の Developer tools › Authentication で、API キーを作る（権限は Transactions の Read と Customers の Read だけ）
   2. 手元の Worker に外から届く URL を作る（例: `brew install cloudflared` のあと `cloudflared tunnel --url http://localhost:8787`。表示される `https://….trycloudflare.com`）
   3. sandbox の Paddle の Developer tools › Notifications で通知先を足す。URL は `<2 の URL>/api/paddle/webhook`、イベントは `transaction.completed`・`adjustment.created`・`adjustment.updated` の3つ。表示される秘密（`pdl_ntfset_…`）を控える
   4. `cloudflare/.dev.vars`（`.gitignore` が無視する。コミットしない）に sandbox の値を書く。`PADDLE_PRICE_ID` は sandbox の価格で、`wrangler.toml` の値を上書きする:
      ```
      PADDLE_API_KEY=pdl_sdbx_apikey_…
      PADDLE_NOTIFICATION_SECRET=pdl_ntfset_…
      LICENSE_PRIVATE_KEY=<~/Nonet-secrets/nonet-license.private-key の中身>
      RESEND_API_KEY=re_…
      PADDLE_PRICE_ID=pri_…
      ```
   5. `buy.html` の `data-paddle-token`・`data-paddle-price` を一時的に sandbox の値にし（3.6 の 1 と同じ。コミットしない）、`cd cloudflare && npx wrangler dev --local` で立てる（http://localhost:8787）
   6. http://localhost:8787/buy.html でテスト用のカードで買う。ページにキーが出ること、購入のときのメールアドレスにキーのメールが届くこと、そのキーを Nonet に登録できることを確かめる。sandbox の Paddle でその取引を返金し、support@astlog.dev に知らせが届くことも見る
   7. 終わったら `buy.html` を戻し、`.dev.vars` を消し、sandbox の通知先を消す（止める）
3. **本番に入れる**
   1. 本番の Paddle の Developer tools › Authentication で、API キー（`pdl_live_apikey_…`。Transactions の Read と Customers の Read だけ）を作る
   2. Developer tools › Notifications で通知先を足す。URL は `https://nonet.astlog.dev/api/paddle/webhook`、イベントは 2 の 3 と同じ3つ。秘密を控える
   3. 秘密を Worker に置く（値は聞かれたときに貼り付ける。コマンドの引数やリポジトリのファイルに書かない。`secret put` はその場で新しい版として効き、後のデプロイでも消えない）:
      ```bash
      cd cloudflare
      npx wrangler secret put PADDLE_API_KEY
      npx wrangler secret put PADDLE_NOTIFICATION_SECRET
      npx wrangler secret put RESEND_API_KEY
      npx wrangler secret put LICENSE_PRIVATE_KEY < ~/Nonet-secrets/nonet-license.private-key
      ```
   4. この変更を入れた Worker を出す（[hosting.md](hosting.md) の 2.5 か GitHub Actions）。`wrangler.toml` の `[vars]` の2つは、テストがアプリと購入のページの値と比べている
   5. 確かめる: `curl -s 'https://nonet.astlog.dev/api/license?transaction_id=txn_01aaaaaaaaaaaaaaaaaaaaaaaa'` が `{"error":"not_found"}` なら設定は揃っている（`{"error":"unavailable"}` なら足りないものがあり、Workers Logs に名前が出る）。本番で一度自分で買い、ページとメールにキーが出て登録できること、返金して知らせが届き、`nonet-license revoke` できることを見る（3.6 の 7）
4. Paddle からの販売のメールは受け取ったままにしておく。届いていないという問い合わせには、上の「送り直す」か 3.1 で応える

**気をつけること**

- **秘密鍵が Cloudflare に置かれる**（2026-11-15 に受け入れた）。秘密の値はダッシュボードでも読めないが、Worker のコードからは読めるので、Cloudflare のアカウントか、Worker を出せる API トークン（`CLOUDFLARE_API_TOKEN`。[hosting.md](hosting.md) 2.3）を取られると、好きなキーを作られうる。アカウントの2段階認証とトークンの置き場所を守る。漏れたら 1.5 のとおり鍵を作り直す（それまでのキーはすべて再発行になる）
- Paddle の API キーは読むだけ（`transaction.read`・`customer.read`）。漏れても、取引と顧客を読まれるだけで、返金や変更はできない。通知の秘密が漏れると偽の通知を送れるが、Worker は API で取引を読み直すので、本物の取引の購入者にしかキーは届かない
- 購入者の名前とメールアドレスは、Paddle から Worker を通って Resend に渡る（[privacy.md](privacy.md) の「7. 購入のときの情報」）。Worker は保存しない
- `/api/license` は、形の合う取引の ID が来るたびに Paddle の API を1回呼ぶ（回数の制限は付けていない）。でたらめな ID を大量に送られると、Workers の1日の回数（[hosting.md](hosting.md)「6. 上限と費用」）や Paddle の API の回数の上限を使われうる。気になったら、Cloudflare の WAF の Rate limiting rules（無料のプランでも1つ作れる）で `/api/license` を IP ごとに絞る

### 3.3 試用の記録（方針）

試用は「初めて起動してから使った時間が14日」で終わる。どれだけ使ったかの記録は、Mac の中の4か所に置く。

| 置き場所 | 中身 | 消えるとき |
|---|---|---|
| 環境設定（`~/Library/Preferences/com.iam74k4.Nonet.plist`） | 開始日・最後に数えた時刻・使った時間 | 環境設定を消したとき、アンインストールツール |
| `~/Library/Application Support/Nonet/` の隠しファイル | 同じ | フォルダを消したとき、アンインストールツール |
| ログインキーチェーンの項目（サービス `com.iam74k4.Nonet.license.trial`） | 同じ（起動したとき、使った時間が1時間増えるごと、時計が変わったときに書く） | キーチェーンアクセスで消したとき |
| ログインキーチェーンの2つ目の項目（サービスの名前は IOPlatformUUID と bundle ID から作った SHA-256 の16進64桁。ラベルは付けない） | 同じ（1つ目と同じときに書く） | キーチェーンアクセスで消したとき |

- 食い違ったら、どの記録で数えても試用が最も短くなるように1つにまとめる（バックアップから戻した古いフォルダで同じ日を二重に数えたり、1か所だけ書き換えて延ばしたりできない）。決まりは `TrialRecord.reconciled`（`NonetCore/Licensing/LicenseManager.swift`）のコメント
- 2つ目の項目は、名前から Nonet のものとは分からない（`SystemTrialRecordKeychain.machineMarker`）。1つ目の項目だけをキーチェーンアクセスで消しても、こちらが残っていれば試用は続きから数える。2つの項目の記録が食い違えば、上の決まりで1つにまとめる。Mac の識別子（IOPlatformUUID）を読めなければ使わない。識別子そのものは保存しない
- キーチェーンは起動ごとに1回読む。ほかの2か所の両方から記録が消えていれば（アンインストールツールで環境設定と Application Support をまとめて消した）、キーチェーンの記録で数える。入れ直しても、時計を戻しても、試用はやり直しにならない
- ほかの2か所に記録があるときは、キーチェーンの「使った時間」だけを下限として使う（環境設定に「使った時間 0」と書き込んでも減らない）。最後に数えた時刻は使わない（キーチェーンは毎回は書かないので、時計がずれていた起動の記録が残っていることがあり、それで数えるとずれた分を余計に数えるため）
- 起動したままの日が続いても、キーチェーンは使った時間が1時間増えるごとに書き直す（ほかの2か所を消して入れ直し、時計を戻して起動しても、減るのは最後の1時間ほどだけ）
- 4か所のどこにも試用の記録が無いときだけ、以前に使った跡から開始日を決める（`UserDefaultsLicenseStorage.earlierUseStart`）。記録が1か所にでも残っていれば、跡は見ない
  - 2つ目の項目はあるのに読めない（壊れている・書き換えられた）: 前に使ったことは確かだが、いつかは分からないので、期限切れにする（今から14日前を開始日にする）
  - `~/Library/Application Support/Nonet/Backups/` か `~/Library/Caches/com.iam74k4.Nonet/` のフォルダがある: いちばん古い作成日を開始日にする（`FileTrialUsageEvidence`。14日を過ぎていれば期限切れ）。試用はフォルダができるより前に始まっているので、実際より長くは数えない。初めての起動でフォルダが先にできても、作成日はほぼ今なので試用は減らない。2025年より前の作成日は正しく読めていないものとして使わず、時計より後の作成日は今として数える
- キーチェーンを使うのは、Developer ID で署名した製品版だけ（開発用の署名やアドホックのビルド、`--self-check` と Debug の `--config-dir` では使わない。署名の身元が違うと、キーチェーンが許可を聞いてくるため）。iCloud キーチェーンとは同期しない。フォルダの作成日は署名に関係なく見るが、`--self-check` と Debug の `--config-dir` では見ない。このため、記録がすべて消えているときは、自己診断が「残り14日」と出しても、アプリは期限切れとすることがある
- 動いている間に、ほかの置き場所の使った時間の方が多くなっていたら（ほかの Nonet が数えた）、使った時間が最も多く残る数え方を取り、同じ経過を二重には数えない（[architecture.md](architecture.md) §6「ライセンス」）
- ライセンスが登録されている間は、試用の記録を書き換えない（残っている記録はそのまま）
- それでも、キーチェーンアクセスで2つの項目も消し、Backups と Caches のフォルダも消す・macOS の別のユーザーで使う・Mac を初期化する、といった方法で試用はやり直せる。サーバー無しの試用では防ぎきれないので、手間をかける人は止めない、という割り切り
- 利用者がアンインストールで消すものは、利用ガイド（[user-guide.md](user-guide.md#アンインストール)・[user-guide.en.md](user-guide.en.md#uninstalling)）とプライバシーポリシー（[privacy.md](privacy.md)）に書く。利用ガイドの原本はこの2つの Markdown で、販売ページの `site/guide.html`・`site/en/guide.html` は `python3 -I scripts/build-guide.py` で作る（手で直さない。作り直し忘れは `scripts/tests/site_test.sh` が見つける）

### 3.4 販売ページに要るもの

決めたこと（ページに事実として書いてある。変えるときは `index.html`・`en/index.html` の価格とよくある質問、`terms.html`・`en/terms.html`、`tokushoho.html` をそろえて直す）:

- 返金: 購入から30日以内なら、理由を問わず全額。macOS のアップデートで動かなくなり直せないときは、購入からの日数にかかわらず返金
- ライセンス: 1人に1つ。その人が使うすべての Mac で使える（キーは Mac の中で確かめるので、台数の登録や解除は無い）
- アップデート: 1.x はすべて無料
- 販売: Paddle（販売代理店 = Merchant of Record）。売主は Paddle なので、`tokushoho.html` は「販売事業者は Paddle.com Market Limited」と書き、所在地と同社の購入者向け規約（Paddle Buyer Terms）へのリンク、開発者の問い合わせ先を載せる。Paddle には日本の特定商取引法に基づく表記のページが無く、規約にも電話番号が無いので、電話番号は「請求があった場合は、遅滞なく電子メールで開示します」と書いた（2026-11-15 に決めた）
- 利用規約（`terms.html`・`en/terms.html`）: 1人に1つのライセンス・返金・保証の否認と責任の範囲（軽過失は支払った金額まで）・準拠法は日本法

1.8 の仮の値は、2026-11-15 にすべて埋めた（購入のページの Paddle のクライアント用トークンと価格の ID も。3.6）。

### 3.5 ライセンスを無効にする（返金・キーの流出）

返金したライセンスと、公開されてしまったキーは、アプリに入れる一覧（`Packages/NonetKit/Sources/NonetCore/Resources/RevokedLicenses.txt`。`LicenseRevocationList`）で受け付けないようにする。キーはオフラインで確かめるので、サーバーで止めることはできない。

```bash
cd Packages/NonetKit
swift run nonet-license revoke <ライセンス ID（取引の ID の txn_…）かライセンスキー>
```

- 返金では、ライセンス ID は返金した取引の ID（Paddle › Transactions の `txn_…`）。Worker が届けたキーも 3.1 で手で発行したキーも同じ ID なので、1行で両方に効く。承認された返金・チャージバックは、Worker が support@astlog.dev に取引の ID を添えて知らせる（3.2）
- 一覧に `<ライセンス ID の SHA-256>  # <日付（この Mac の日付）>` の行が足される。取引の ID（`txn_` と小文字の英数字 26 文字。発行し直した `-r2` などの付いたものも）と UUID の形の ID には注意を出さない。取引の ID は大文字小文字を区別する（Paddle の ID は小文字なので、そのまま貼る）。前に手で発行した UUID の形の ID は区別しない（小文字で書いても効く）。どちらでもない形を書くと注意が出る（`issue --id` で決めた ID なら、そのままでよい）。ID そのものは書かない（一覧はリポジトリとアプリに入るため）。すでにあれば何もしない。キーを渡したときは、署名は確かめずに中のライセンス ID を使い、キーの中身を表示する。リポジトリの外で動かすときは `--list <一覧のファイル>` で一覧を指定する
- 一覧をコミットして、次のリリース（2.5）に入れる。アプリが受け付けなくなるのはその版からで、それまでの版では使えるまま
- 新しい版では、そのキーは登録できない（「このライセンスキーは無効になっています（返金したライセンスや、公開されてしまったキーは使えません）。心当たりがないときは、お問い合わせください。」）。登録していた Mac では、登録していないものとして扱い、残っている試用の記録で数え直す（試用期間が終わっていれば期限切れ）。ライセンスのタブには「登録してあったライセンスキー（ライセンス ID: …）は無効になっているため、使えません。…」と理由が出る。キーは消さない
- 間違えて足したときは、その行を消してコミットし、次の版を出せば元に戻る
- 返金の記録は Paddle に残り、ライセンス ID が取引の ID なので、別の台帳は要らない（一覧の行の日付が無効にした日）
- 公開されてしまったキーを無効にして、本人に新しいキーを渡すときは、同じ ID では新しいキーも止まるので、`--id txn_…-r2` のように後ろに番号を付けて 3.1 で発行する。購入のページと `/api/license` は、その取引の元のキー（無効にしたもの）を返し続ける
- `nonet-license verify` は一覧を見ない（署名と製品だけを確かめる）

---

### 3.6 Paddle の準備と購入のボタン

サイトとアプリの側はできている（2026-11-08）:

- 販売ページの「購入する」とアプリの「購入する」（`NONET_PURCHASE_URL`）は、購入のページ `buy.html`（英語は `en/buy.html`）を開く。ページは Paddle.js を読み、`site/buy.js` がすぐに購入画面（オーバーレイ）を開く。購入画面の言語はブラウザの言語
- 閉じたら「購入画面を開く」で開き直せる。開けなかったとき・Paddle.js を読めなかったとき（拡張機能で止められたなど）・購入が済んだときは、そう知らせる。購入が済んだら、Worker からキーを受け取ってページに出す（3.2）。受け取れなければ「領収書は Paddle から届き、ライセンスキーは遅くとも24時間以内にメールで届く」。開けなかったときの文は、購入を一時的に受け付けられないことがあること・14日間の試用はそのまま使えること・問い合わせ先を書く
- トークンと価格の ID は、2つのページの `data-paddle-token`・`data-paddle-price`（同じ値。`scripts/tests/buy_script_harness.js` が確かめる）。`test_` で始まるトークンなら sandbox で開く。仮の値のままなら購入画面を開かずに「準備中」と出す（`scripts/check-site.sh --strict` は止まる）
- `?_ptxn=…` を付けて開かれたら、その取引の購入画面は Paddle.js が開く（Paddle の Default payment link をこのページにするため）
- 外のスクリプト（Paddle.js）を読むのはこの2つのページだけ。`site/_headers` でこの2つの CSP だけを Paddle の分（と、キーを受け取る同じサイトへの `connect-src 'self'`）だけ広げる（中身と理由は `_headers` のコメント）。Paddle.js が本番で足す Paddle Retain（解約を減らすための追跡。買い切りには要らない）は CSP で止める。プライバシーポリシーの「8. 販売ページ」に、購入のページだけが Paddle のスクリプトを読むことを書いた

持ち主がすること（アカウントの作成・本人確認・入金先の登録は、本人にしかできない）:

1. **sandbox で試す**: https://sandbox-vendors.paddle.com/signup でテスト用のアカウントを作り、下の 3 と同じ商品と価格、Developer tools › Authentication のクライアント用トークン（`test_…`）を作る。Checkout › Checkout settings の Default payment link には `https://nonet.astlog.dev/buy.html` を入れる。トークンと価格の ID を `buy.html` に一時的に入れて（コミットしない。残したまま公開しようとしても、`check-site.sh --strict` が `test_` のトークンで止める）、`cd site && python3 -m http.server 8000` で http://localhost:8000/buy.html を開き、Paddle のテスト用のカードで買えることと、国を日本にしたときの合計がちょうど ¥1,480（税込み。上乗せされない）で、米国では $9.99 に税が足されることを確かめる
   - 2026-11-15 に sandbox で済ませた。税の扱いを「Automatic based on location」にした価格で、合計は日本 ¥1,480（消費税 ¥135 込み。上乗せなし）・米国 $9.99 ＋ 州の売上税（ニューヨーク $10.88、オレゴン $9.99）・ドイツと英国 $9.99（VAT 込み）。テスト用のカードで買えて、`buy.js` の購入後の案内が出て、領収書（[TEST]）が届いた（sandbox の領収書は買い手ではなく販売者のアカウントのメールに届く）
2. **本番のアカウント**: https://vendors.paddle.com/signup でアカウントを作り、本人と事業の確認を済ませ、入金先（銀行か Payoneer）を登録する。$10 未満の商品なので、手数料（5% + 50¢）の相談もこのときにする
3. **商品と価格**: Catalog › Products で商品「Nonet」（税のカテゴリは Standard digital goods）を作り、価格を1つ足す: 1回払い・USD 9.99、国ごとの価格で日本（JP）を JPY 1,480。税の扱い（Sales tax）は「Automatic based on location」（日本・EU・英国は税込み、米国は税抜き。1 の sandbox で確かめた）
4. **トークン**: Developer tools › Authentication でクライアント用トークン（`live_…`）を作る。トークンと価格の ID（`pri_…`）を `buy.html`・`en/buy.html` に入れる（クライアント用のトークンはページに載せるためのもので、公開してよい。API キー（`pdl_…`）は載せない）
5. **公開**: 問い合わせ先のメールアドレスと特商法の電話番号の表記も埋め（1.8）、`scripts/check-site.sh --strict` を通して nonet.astlog.dev を公開する（[hosting.md](hosting.md)）
6. **ドメインの承認**: Paddle の設定の Website approval で `nonet.astlog.dev` を申請する（販売ページに価格・利用規約・返金の方針・プライバシーポリシーがあることを見られる）。承認されるまで、本番の購入画面は開かない。Default payment link に `https://nonet.astlog.dev/buy.html` を入れる
   - 2026-11-15 に承認された（Checkout approved・Apple Pay approved）。それでも、本人確認（Paddle から届くメールのリンクで、Sumsub に身分証・住所の証明・動画の自撮りを出す）が済むまでは、購入画面は「Something went wrong」になる（コンソールに `transaction_checkout_not_enabled`）。購入のページは「購入画面を開けませんでした」と出す
7. **確かめる**: 承認されたら、本番の購入のページを開き、購入画面が日本語・円で出ること、ブラウザのコンソールに Paddle Retain（`public.profitwell.com`）のほかの CSP の違反が無いことを見る。自分で一度買い、返金まで通しておく
8. **キーを自動で届ける**設定をする（3.2。済むまでは 3.1 の手動）。Paddle › Notifications で、販売のメールを受け取るようにしておく

## 4. 公開前のチェックリスト

**鍵とアカウント**
- [ ] Developer ID Application 証明書（`.p12`）・Sparkle の秘密鍵・ライセンスの秘密鍵を、それぞれ2か所にバックアップした
- [ ] どの秘密鍵もリポジトリに入っていない（`.gitignore` が `*.p12`・`*.p8`・`*.pem`・`*.cer`・`*.private-key`・`.env*`・`.dev.vars`・`secrets/` を無視している。`git grep -I -l -E 'BEGIN (RSA |EC )?PRIVATE KEY'` が何も出さない。履歴は `git log -p | grep -i private` などで確かめる。`scripts/tests/run.sh docs` も確かめる）
- [ ] `Config/Nonet.xcconfig` の7つの値を入れ、コミットした（公開鍵の `//` は `/$()/`）
- [ ] `Packages/NonetKit` で `nonet-license issue` を動かし、アプリの公開鍵（xcconfig）との照合が通った（「注意」が出ない）
- [ ] プライバシーポリシーに書いた試用の記録のキーチェーンの2つの項目を、アプリが本当に作る（`App/AppDelegate.swift` が `SystemTrialRecordKeychain()` と `SystemTrialRecordKeychain.machineMarker()` を渡している。`scripts/release.sh` は1つ目を確かめる）

**アプリ**
- [ ] 実機での手動テストを製品版で通した（操作の仕様は [architecture.md](architecture.md) §5。ポインタの固定・触覚・右か左の外での切り替え・2本指スワイプ・「タップでクリック」の抑止・強く押し込んで開く動きとクリックの預かり・トラックパッドの開始し直しは §7 の未確認の点）:
  - 開く: トラックパッドのどこかに1本指を置き、2回目のカチッまで強く押し込んで 0.25秒止めると、ポインタの周りに9つのアイコン（全体の皿も輪も文字も無く、1つずつ暗い丸い台に白で載る）がすぐに出て軽い触覚が1回鳴る。ポインタは真ん中にあり、明るいウインドウ・暗いウインドウ・写真の壁紙のどの上でも、アイコンが同じように読める（macOS 26 以降は台の下の文字や模様がぼけて見え、それより前の macOS では台が少し濃く、下はぼけない。システム設定の「透明度を下げる」をオンにすると、台は不透明で下が透けない）。ポインタを輪の外へ出すと、台は残ったままアイコンだけが薄くなる。開いている間もポインタはふだんどおり動き、閉じてもそのまま。開いたときに、押し込んだ場所のボタンやリンクが押されない。ふつうのクリック・ダブルクリック・⌘クリック・ドラッグでの範囲の選択とファイルの移動・押したままで出るメニュー（Safari の戻るボタン・Dock）が、Nonet を入れる前と同じように効く（ふつうのクリックはアプリに届くのが離したときになる）。マウスのクリック・「タップでクリック」・2本指のクリックは預からない。Nonet の設定のウインドウが前面のとき（最初の1回だけ理由のトーストが出る）は開かず、クリックはそのまま効く。システム設定の「強めのクリックと触覚フィードバック」をオフにすると開かず、設定の「一般」に知らせが出る。強めにクリックする癖で誤って開く回数を、1日使って数える（ログの `liftedInFrame` の数）
  - 実行: 指を滑らせるとポインタが動き、向けた先のアイコンの下に白い円が出て、別のアイコンに移るたびに軽い触覚が鳴る。真ん中のアイコンは、一度外へ出してから戻すと選べる。マスで少し止めてから離すと実行し、滑らせて通りかかっただけで離したときは実行しない
  - やめる: アイコンの輪の外（真ん中から 134pt）へ出すとアイコンが全部薄くなり、そこで離すと何も実行せずに閉じる（軽い触覚2回）。開いてすぐに離したときも同じ。キーを押しても閉じ、そのキーは前面のアプリに届く。空きマス（小さな点）で離したときも実行しない（キーで閉じたときは触覚が鳴らない）
  - ページ: 開いたまま、ポインタを輪のすぐ外の右か左（真横から上下 45° まで）へ出して 0.5 秒止めるとそちらのページに変わり（触覚2回）、止めたままなら 0.9 秒ごとにもう1ページ進み、一回りしたら止め始めたページの手前で止まる（止めたままでは回り続けない）。止めている間は、その側の縁に白い矢印の円が出て線が一周し、真ん中の下にページの点（いまの層のページだけ）が出る。切り替わると輪が進んだ向きへ押し出され、次の輪が入る（「視差効果を減らす」では入れ替わるだけ）。最後のページから右へは、その層（アプリかグローバル）の最初のページへ回る（グローバルへは進まない）。ページが1つの層では左右に何も起きず、0.5 秒止めると真ん中の下に「左右に送るページはありません」が出る。プロファイルの無いアプリ（LINE など）で上か下に 0.5 秒止めると、真ん中の下に「このアプリのページはまだありません」が出て、触覚は鳴らず、帯を出ると消える。輪から遠く（真ん中から 210pt より外）で止めても何も変わらない。
  - 層: プロファイルのあるアプリで、輪のすぐ下で 0.5 秒止めるとグローバルのページ（画面に置く）へ移り（強めの触覚1回・台が紺になる・真ん中の下に「グローバル」が 1 秒出る・輪が上へ押し出される）、輪のすぐ上で止めると、下へ移る前のアプリのページへ戻る。アプリのページで上、グローバルのページで下に止めても何も起きない。プロファイルの無いアプリでは上下とも何も起きない。同じ側の外で動かしている間は変わらない。輪の外で離すと、ページが変わった後でも、何も実行せずに閉じる。2本指で左右にスワイプしてもページが変わり（端では止まって軽い触覚2回）、Safari の「戻る」などが前面のアプリに届かない。1本指に戻してから滑らせ直して離すと、そのマスを実行する
  - 少し長く止めるマス: 「少し長く止めてから実行」をオンにしたマスは、アイコンの周りの線が一周するまで止めてから離したときだけ実行し、それより早く離すと実行しない
  - 画面に置く: グローバルの1ページ目「画面に置く」（プロファイルのあるアプリでは輪のすぐ下で止めて移る）で、マスを光らせると画面に青い枠と「離すと、ここに置きます」が出る。離すと前面のウインドウがそこに置かれ（左半分・最大化・右下など）、輪の外へ出すと枠が消える。ウインドウのあるディスプレイで置かれ、フルスクリーンのウインドウでは「このウインドウは動かせませんでした」のトーストが出る
  - ユーティリティ: グローバルの2ページ目「ユーティリティ」で、範囲を撮影（範囲を選ぶ十字が出る）・撮影と収録（ツールバーが出る）・撮影してコピー（撮ったものを貼れる）・収録を止める（⇧⌘5 から始めた収録が止まる）・絵文字と記号（文字の欄で一覧が出る）・Spotlight（検索欄が出る）・消音の切り替え（音が消え、もう一度で戻る）・画面を消す（ディスプレイが消え、Mac はスリープしない）・画面をロック（少し長く止めたときだけロックする）が効く。設定の「＋」の「ユーティリティ」「画面に置く」で同じページが足せ、⌘Z で消える
  - 閉じた直後に「タップでクリック」のクリックが、止めていたポインタの下で起きない
  - 設定の「開き方と HUD」: 「Nonet を有効にする」をオフにすると強く押し込んでも開かず、ふつうのクリックになる。「大きく表示」が HUD とトーストに効く。「触覚」をオフにすると振動しない。メニューの「このアプリでは使わない」を入れたアプリでは開かない
  - トラックパッドの開始し直し（スリープ・蓋の開け閉め・Magic Trackpad のつなぎ直し・ファストユーザスイッチ）の後も、起動し直さずに開ける
- [ ] ファイルのアクションを実機で通した（Finder で一時フォルダのファイルを選んで、Finder のプリセットの2ページ目から実行する）: 初めて使うとき macOS が「Nonet が Finder を操作しようとしています」と確かめ、許可すると動く。複製（「◯◯のコピー」ができる）・名前を変更（Finder の名前の変更が始まり、拡張子の前が選ばれていて、入力して Return で変わる）・ゴミ箱に入れる（少し長く止めて離したときだけ。ゴミ箱から「元に戻す」で戻せる）。Safari など別のアプリが前面のときは、Finder で選んだままでも動かず、トーストが出る。許可を外す（システム設定 › プライバシーとセキュリティ › オートメーション）と、「オートメーション（Finder）の許可が必要です」と出る
- [ ] ショートカットのアクションを実物のショートカットで通した（architecture.md §7）: テキストを返すもの・画像を返すもの・何も返さないものを1つずつ実行し、テキストは結果のパネルに出て、画像と何も返さないものは何も出ず、どれも失敗のトーストが出ない
- [ ] Photoshop のプリセットの bundle ID（`com.adobe.Photoshop`。Adobe の文書にも Homebrew にも無く、投稿で確かめただけ）を、インストール済みの Photoshop で `osascript -e 'id of app "Adobe Photoshop 2026"'` を動かして確かめた。違えば `KnownApp.photoshop` を直す
- [ ] JIS と US のキーボード（記録したショートカットがどちらでも同じように届く）、内蔵トラックパッドと Magic Trackpad で試した
- [ ] 新しいユーザーで、初回起動 → アクセシビリティの許可 → 練習 → 「完了」（メニューバーのアイコンが光り「Nonet はここにいます」が出る）まで通した。練習の画面の「Mac にログインしたら Nonet を自動で起動する」は最初から入っていて、閉じた後にシステム設定のログイン項目に Nonet が入っている（許可を求められたら、案内に知らせが出る）。最初の設定に、プリセットのあるインストール済みのアプリのプロファイルとグローバルのランチャーが入っている（`claude` のある Mac では、数秒のうちに Claude Code のマスが入る）
- [ ] 試用の終了（強く押し込んでも開かず、「試用期間が終了しました」のトーストと軽い触覚2回で知らせる・試用期間の終了のウインドウ・設定の帯）と、キーの登録で元に戻ることを確かめた
- [ ] 購入のメールの `nonet://register?key=…` のリンクと `.nonetlicense` のファイルで、登録してよいかを尋ねられ、登録できた
- [ ] `scripts/sync-strings.sh` で文言を集め、英語の訳を入れた（`scripts/test.sh` の `--check` が通る）
- [ ] Developer ID で署名したビルド（dry run の `build/release/<版>/export/Nonet.app`）で、環境設定と `~/Library/Application Support/Nonet/` を消して起動し直しても試用が続き、キーチェーンの許可を聞かれない。キーチェーンアクセスで `com.iam74k4.Nonet.license.trial` も消しても、2つ目の項目で試用が続く
- [ ] `scripts/test.sh` が通る（CI も緑）

**配布**
- [ ] `scripts/release.sh --dry-run --first-release` が通り、本番（`--first-release` 付き）も通った
- [ ] 無いファイルの URL に 404 が返る（`curl -I <無いファイルの URL>`）
- [ ] 公開した URL から落とした DMG が、macOS 14 と macOS 26 の両方で警告なく開く
- [ ] 一つ前の版から Sparkle でアップデートできた（2回目のリリースから）
- [ ] appcast.xml と DMG に HTTPS で届く

**販売**
- [ ] 販売サービスの商品・価格・税の設定をした（Paddle。日本の合計がちょうど ¥1,480 になることを sandbox で確かめた。3.6）
- [ ] Paddle のドメインの承認（`nonet.astlog.dev`）と Default payment link（`https://nonet.astlog.dev/buy.html`）が済み、本番の購入のページで購入画面が開く
- [ ] キーを自動で届ける Worker の秘密4つ（`PADDLE_API_KEY`・`PADDLE_NOTIFICATION_SECRET`・`LICENSE_PRIVATE_KEY`・`RESEND_API_KEY`）を置き、Paddle の通知先と Resend のドメインを設定した。sandbox で通した（3.2）
- [ ] テスト購入 → 購入のページにキーが出る・メールでキーが届く → アプリで登録できる → 返金で support@astlog.dev に知らせが届く、を通した
- [ ] 返金やキーの流出で無効にしたライセンスがあれば、`RevokedLicenses.txt` の変更をコミットした（3.5。この版に入る）
- [ ] `scripts/check-site.sh --strict` が通る（価格・URL・問い合わせ先が埋まっている）
- [ ] 利用ガイド（`site/guide.html`・`site/en/guide.html`）を公開し、`NONET_SUPPORT_URL` が `…/guide.html` を指している
- [ ] プライバシーポリシー・利用規約（返金の方針）・特定商取引法に基づく表記を公開した（どのページのフッターからも開ける。`scripts/check-site.sh` が確かめる）
- [ ] よくある質問の「確認済みの macOS」に、実際に試した版を書いた（2.7）
- [ ] 問い合わせのメールを受け取れる
