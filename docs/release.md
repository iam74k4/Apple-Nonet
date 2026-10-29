# リリースと販売の手順

Nonet は Mac App Store ではなく直販する（非公開の `MultitouchSupport.framework` を使うため。[architecture.md](architecture.md) §1）。配るものは次の3つ。

| もの | 中身 | 作り方 |
|---|---|---|
| DMG | Developer ID で署名し、公証してステープルした `Nonet.app`（DMG 自体も署名・公証・ステープル済み） | `scripts/release.sh` |
| appcast.xml | Sparkle がアップデートを見つけるためのフィード（EdDSA 署名つき） | `scripts/release.sh` が Sparkle の `generate_appcast` で更新 |
| 販売ページ | `site/`（静的な HTML。ビルド不要） | そのままアップロード |

ライセンスは「14日間の試用 → 買い切り」。キーは Ed25519 で署名した文字列で、アプリはサーバー無しで検証する（[architecture.md](architecture.md) §6「ライセンス」）。

---

## 1. 一度だけの準備

### 1.1 道具

- Apple Developer Program のメンバーシップ（チーム ID `NL9ZXK2SGR`。`project.yml` の `DEVELOPMENT_TEAM`）
- Xcode 27 以降（Swift 6 のツールが要る）
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

- 表示された公開鍵を `Config/Nonet.xcconfig` の `NONET_SPARKLE_PUBLIC_KEY` に入れる
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

発行と確認:

```bash
swift run nonet-license issue --key ~/Nonet-secrets/<秘密鍵のファイル> --name "山田 太郎" --email taro@example.com
swift run nonet-license verify --public "<公開鍵>" "<発行したキー>"
```

### 1.6 Config/Nonet.xcconfig

販売用の4つの値を入れてコミットする（公開鍵と URL なので、公開されても問題ない）。

```
NONET_APPCAST_URL = https:/$()/nonet.example.com/updates/appcast.xml
NONET_SPARKLE_PUBLIC_KEY = <generate_keys の公開鍵>
NONET_PURCHASE_URL = https:/$()/nonet.example.com/buy
NONET_LICENSE_PUBLIC_KEY = <nonet-license keygen の公開鍵>
```

**xcconfig では `//` から後ろがコメントになる**。URL は `https:/$()/…` と書く（`$()` は空文字に展開される）。`https://…` と書くと `https:` で切れ、アップデートの確認も購入ページも動かない。`scripts/release.sh` はこの間違いを見つけて止まる。

### 1.7 配布の場所

HTTPS で静的なファイルを置ける場所なら何でもよい（Cloudflare Pages / R2、GitHub Pages ＋ Releases、Netlify、S3 ＋ CloudFront など）。決めること:

- appcast.xml の URL（`NONET_APPCAST_URL`。一度出したら変えない。変えるときは古い URL からリダイレクトする）。ファイル名は `appcast.xml` でなくてもよい（手元ではいつも `appcast.xml` として作るので、その URL の名前でアップロードする）
- 無いファイルには 404 を返す設定にする。無いファイルにも 200 で `index.html` を返す設定（SPA 向けのフォールバックなど）だと、スクリプトが公開中の appcast を確かめられずに止まる
- DMG を置く URL。既定では appcast.xml と同じ場所（例: `https://nonet.example.com/updates/Nonet-1.0.0.dmg`）。別にするなら `NONET_DOWNLOAD_URL_PREFIX` を設定する
- 販売ページ（`site/`）の置き場所。「ダウンロード」ボタンは最新の DMG を指すので、毎回書き換えるか、最新を指す固定の URL（例: `/download` から最新の DMG へリダイレクト）を用意する

### 1.8 販売ページの仮の値を埋める

`site/` には価格・ダウンロード・購入・問い合わせ先などの仮の値（`TODO` と `TODO.invalid`）がある。埋めたら確かめる:

```bash
scripts/check-site.sh --strict   # TODO が1つでも残っていれば失敗
```

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

### 2.3 試しに通す（dry run）

```bash
scripts/release.sh --dry-run 1.2.0 42
```

公証とステープルを飛ばし、署名した DMG と appcast の試し版を `build/release/1.2.0/` に作る。公開用のフォルダには触れない。**この DMG は公証していないので配らない**。

### 2.4 本番

```bash
NONET_NOTARY_PROFILE=nonet-notary scripts/release.sh --notes notes/1.2.0.md 1.2.0 42
```

**初めてのリリースだけ** `--first-release` を付ける（dry run でも同じ）。公開中の appcast が無い（`NONET_APPCAST_URL` が 404 か 410 を返す）とき、このオプションが無ければスクリプトは止まる。URL の書き間違いや、`NONET_RELEASES_DIR` の appcast.xml が無い状態で、過去の版の項目が消えた appcast を作って公開中のものを上書きしないためである。

```bash
NONET_NOTARY_PROFILE=nonet-notary scripts/release.sh --first-release --notes notes/1.0.0.md 1.0.0 1
```

スクリプトがすること:

1. 準備の確認（コマンド・Developer ID 証明書・`Config/Nonet.xcconfig` の値・notarytool のプロファイル・コミットしていない変更。`--notes` のファイルは除く）。足りないものをまとめて表示して止まる
2. XcodeGen でプロジェクトを作り、パッケージを解決する
3. キーチェーンの Sparkle の鍵が `NONET_SPARKLE_PUBLIC_KEY` と一致するか、ビルド番号が appcast の最大より大きいかを確かめる。手元に appcast.xml が無ければ、公開中のもの（`NONET_APPCAST_URL`）を取ってくる。取れなければ（403・503・ネットワークのエラーなど）止まる。404・410 で新しく作るのは `--first-release` のときだけ
4. `xcodebuild archive`（Release・Developer ID Application・hardened runtime・`--timestamp`）
5. `ExportOptions.plist`（`method` は `developer-id`）で書き出す
6. 署名を確かめる: `codesign --verify --deep --strict`、Developer ID・チーム・タイムスタンプ・hardened runtime、中の実行ファイル（Sparkle の XPC サービスなど）、Info.plist の版と販売用の値
7. アプリを zip にして `xcrun notarytool submit --wait` で公証し、`stapler staple` してから `spctl -a -vv` で Gatekeeper の評価を確かめる
8. DMG を作る（ボリューム名 `Nonet`、`/Applications` へのリンクつき）→ 署名 → 公証 → ステープル → `spctl` で確認
9. DMG とリリースノートを公開用のフォルダ（`NONET_RELEASES_DIR`、既定 `build/releases`）に入れ、`generate_appcast` で appcast.xml を更新する（`NONET_APPCAST_URL` のファイル名にかかわらず、手元の名前は `appcast.xml`）

公証が通らなければ、notarytool のログを表示して止まる。作業用のファイルとログは `build/release/<バージョン>/` に残る。

| 環境変数 | 既定 | 意味 |
|---|---|---|
| `NONET_NOTARY_PROFILE` | なし（本番では必須） | notarytool のキーチェーンのプロファイル名 |
| `NONET_RELEASES_DIR` | `build/releases` | 公開する DMG・デルタ・appcast.xml を貯めるフォルダ |
| `NONET_DOWNLOAD_URL_PREFIX` | appcast.xml と同じ場所 | appcast に書く DMG の URL の前半 |
| `NONET_SPARKLE_KEY_ACCOUNT` | `ed25519` | Sparkle の秘密鍵のキーチェーンのアカウント名 |
| `NONET_NOTARY_TIMEOUT` | `1h` | 公証の結果を待つ上限 |

オプション: `--dry-run`（公証しない）、`--notes <ファイル>`（リリースノート）、`--first-release`（初めてのリリース。公開中の appcast が無ければ新しく作る）、`--allow-dirty`（コミットしていない変更があっても続ける）、`--help`。

`NONET_RELEASES_DIR` には過去の DMG と appcast.xml が貯まる。Sparkle は古い版との差分（`*.delta`）をここで作り、古い項目は `old_updates/` に移す。`build/` は消しても困らないよう、公開中の appcast.xml はスクリプトが取ってくるが、差分を作るには過去の DMG が要るので、バックアップされる場所を指定しておくとよい。

### 2.5 アップロード

順番が大事（appcast が先に出ると、まだ無い DMG を指してしまう）。

1. `Nonet-1.2.0.dmg` と、新しくできた `*.delta` を DMG の置き場所へ
2. そのあと `appcast.xml` を `NONET_APPCAST_URL` へ（`old_updates/` は上げない）。URL のファイル名が `appcast.xml` でなければ、その名前で上げる（スクリプトが最後に表示する）
3. 販売ページの「ダウンロード」が新しい DMG を指すようにする

### 2.6 確かめる

- 公開した URL から DMG をダウンロードし、別のユーザーか別の Mac で開く。Gatekeeper の警告が出ずに起動すること
- 一つ前の版を起動し、メニューの「アップデートを確認」で新しい版が見つかり、入れ替わること
- `curl -I <appcast の URL>` が 200 を返すこと

### 2.7 タグを付ける

```bash
git tag -a v1.2.0 -m "Nonet 1.2.0"
git push origin v1.2.0
```

### 2.8 困ったとき

| 症状 | 確かめること |
|---|---|
| 公証が `Invalid` | スクリプトが出すログを見る。よくあるのは、署名の無い実行ファイル・タイムスタンプが無い・hardened runtime が無い。`xcrun notarytool log <ID> --keychain-profile "$NONET_NOTARY_PROFILE"` でもう一度見られる |
| `spctl` が `rejected` | 公証とステープルが済んでいるか（`xcrun stapler validate`）。dry run では rejected が正常 |
| 「ビルド番号は…より大きく」 | 公開済みより大きい番号にする。公開していない試しの項目なら appcast.xml から消す |
| 「公開中の appcast が見つかりません（HTTP 404）」 | 初めてのリリースなら `--first-release` を付ける。公開済みなら `NONET_APPCAST_URL` が公開中の URL と同じか確かめる。分からなければ、公開中の appcast をダウンロードして `NONET_RELEASES_DIR/appcast.xml` に置く |
| 「公開中の appcast を取得できませんでした（HTTP 403 など）」 | ホスティングのアクセス制限（ボット対策・権限）や一時的な障害。`curl -I <appcast の URL>` で確かめる。直せなければ、公開中の appcast を `NONET_RELEASES_DIR/appcast.xml` に置いてからやり直す |
| 「中身が appcast（RSS）ではありません」 | 無いファイルにも 200 でページを返す設定になっていないか（1.7） |
| 「コミットしていない変更があります」 | `git status` で確かめる。`--notes` のファイルは数えない |
| Sparkle の鍵が一致しない | 別の Mac や別のアカウント名で鍵を作っていないか。バックアップから `generate_keys -f` で取り込む |
| アップデートが見つからない | appcast の `sparkle:version` が今の版より大きいか、appcast と DMG の URL に HTTPS で届くか、`SUPublicEDKey` が鍵と一致しているか |

---

## 3. 販売とライセンスの届け方

アプリはキーをオフラインで確かめるので、販売の仕組みは「支払いを受けて、`nonet-license issue` と同じ形のキーを購入者に届ける」だけでよい。どれを使うかは**オーナーが決める**。

| 方法 | 向いているとき | 注意 |
|---|---|---|
| Lemon Squeezy | 海外にも売る。消費税・VAT を販売代行（Merchant of Record）として扱ってほしい | 独自のライセンスキー機能はあるが、形が違うのでアプリは検証できない。自前のキーを届けるには Webhook が要る |
| Paddle | 同上。手数料と審査の条件を比べて選ぶ | Webhook（`transaction.completed`）でキーを発行する |
| Gumroad | まず手軽に始めたい | 販売の通知（Ping）を Webhook として受けられる |
| 手動（メール） | 発売直後で数が少ない | 販売の通知を見て `nonet-license issue` で発行し、メールで送る。数が増えたら自動化する |

税の扱いと手数料は各社の最新の規約で確かめる。

### 3.1 手動で届ける

```bash
cd Packages/NonetKit
swift run nonet-license issue --key ~/Nonet-secrets/<秘密鍵のファイル> --name "購入者の名前" --email buyer@example.com
```

送る文面の例:

> Nonet をご購入いただきありがとうございます。ライセンスキーは次のとおりです。
>
> （キー）
>
> メニューバーの Nonet のアイコンから「ライセンス」を開き、キーを貼り付けて登録してください。キーはこの Mac の中だけで確認され、ネットワークには送られません。

発行したキー・名前・メールアドレス・注文番号は、再発行に備えて記録しておく（[privacy.md](privacy.md) の「購入のときの情報」の範囲で）。

### 3.2 自動で届ける（決めること）

販売サービスの Webhook を受ける小さなサーバーレスの関数（Cloudflare Workers・Vercel Functions・AWS Lambda など）が要る。関数がすること:

1. Webhook の署名を確かめる（偽の通知でキーを出さない）
2. 注文から名前とメールアドレスを取り、`LicenseInfo` を作る
3. 秘密鍵で署名し、`base64url(JSON).base64url(署名)` の形のキーを作る。JSON の項目名と日付の書き方は `nonet-license` と完全に同じにする（`nonet-license verify` で検証できることをテストで確かめる）
4. 購入者にメールで送り、記録を残す

決めることは、どのサービスを使うか、秘密鍵をクラウドの秘密の変数に置くことを受け入れるか（置けば漏れる経路が増える）、メールをどこから送るか。決まるまでは手動で届ける。

### 3.3 販売ページに要るもの

- 価格・購入ページ・ダウンロードの URL（`site/` の TODO）
- プライバシーポリシー（`site/privacy.html`。原本は [privacy.md](privacy.md)）
- 返金の方針と利用規約（販売サービスのものを使うか、自分で書くか）
- 日本で自分が販売事業者になるなら「特定商取引法に基づく表記」のページ。Merchant of Record を使う場合も、表示が要るかを確かめる
- 問い合わせ先のメールアドレス

---

## 4. 公開前のチェックリスト

**鍵とアカウント**
- [ ] Developer ID Application 証明書（`.p12`）・Sparkle の秘密鍵・ライセンスの秘密鍵を、それぞれ2か所にバックアップした
- [ ] どの秘密鍵もリポジトリに入っていない（`git log -p | grep -i private` などで確かめる）
- [ ] `Config/Nonet.xcconfig` の4つの値を入れ、コミットした

**アプリ**
- [ ] 実機での手動テスト（[spike-results.md](spike-results.md) の T1〜T9）を製品版で通した。カーソルの固定・触覚・2本指スワイプは [architecture.md](architecture.md) §7 の未確認の点
- [ ] JIS と US のキーボード、内蔵トラックパッドと Magic Trackpad で試した
- [ ] 新しいユーザーで、初回起動 → アクセシビリティの許可 → プリセット → 練習まで通した
- [ ] 試用の終了（HUD の帯・実行の代わりのトースト）と、キーの登録で元に戻ることを確かめた
- [ ] `scripts/test.sh` が通る（CI も緑）

**配布**
- [ ] `scripts/release.sh --dry-run --first-release` が通り、本番（`--first-release` 付き）も通った
- [ ] 無いファイルの URL に 404 が返る（`curl -I <無いファイルの URL>`）
- [ ] 公開した URL から落とした DMG が、macOS 14 と macOS 26 の両方で警告なく開く
- [ ] 一つ前の版から Sparkle でアップデートできた（2回目のリリースから）
- [ ] appcast.xml と DMG に HTTPS で届く

**販売**
- [ ] 販売サービスの商品・価格・税の設定をした
- [ ] テスト購入 → キーが届く → アプリで登録できる、を通した
- [ ] `scripts/check-site.sh --strict` が通る（価格・URL・問い合わせ先が埋まっている）
- [ ] プライバシーポリシー・返金の方針・（必要なら）特定商取引法に基づく表記を公開した
- [ ] 問い合わせのメールを受け取れる
