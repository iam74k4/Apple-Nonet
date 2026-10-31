# 配布の場所（nonet.astlog.dev と Cloudflare）

販売ページと Sparkle のアップデート（appcast・DMG・デルタ）は `https://nonet.astlog.dev` から配る。中身は Cloudflare の Worker 1つ（`cloudflare/`）と、R2 のバケット1つ（`nonet-updates`）。アカウントはポートフォリオの astlog.dev と同じで、書き方（`wrangler.toml`・GitHub Actions・トークンの置き方）もそろえてある。

リリースの作り方（署名・公証・appcast）は [release.md](release.md)。ここには、作ったものをどこに、どう出すかを書く。

---

## 1. 何がどこにあるか

| URL | 中身 | 置き場所 | 出し方 |
|---|---|---|---|
| `/`・`/en/` | 販売ページ（日本語・英語） | `site/index.html`・`site/en/index.html` | GitHub Actions の site（手で実行） |
| `/privacy.html`・`/guide.html`・`/terms.html`（`/en/` の下も）・`/tokushoho.html`（日本語だけ） | プライバシーポリシー・使い方・利用規約・特定商取引法に基づく表記 | `site/` | 同上 |
| `/thanks.html`・`/en/thanks.html` | ダウンロードのページ。販売ページの「ダウンロード」「無料で試す」がここを指し、ここが `/download` を開く（Mac でだけ。JavaScript が無ければ `noscript` の meta refresh）。`noindex` | `site/` | 同上 |
| `/robots.txt`・`/sitemap.xml` | 検索エンジン向け。`/download` と `/updates/` はクロールさせない。ページを足したら sitemap.xml にも足す（`scripts/check-site.sh` が確かめる） | `site/` | 同上 |
| `/images/og-ja.png`・`/images/og-en.png`・`/apple-touch-icon.png` | 共有の画像（1200×630）とホーム画面のアイコン（180×180） | `site/`（`python3 -I scripts/make-site-images.py` で作る） | 同上 |
| 無いページ | `site/404.html`（`/en/` の下は `site/en/404.html`）を 404 で | `site/` | 同上 |
| `/updates/appcast.xml` | Sparkle のフィード | R2 の `nonet-updates/appcast.xml` | `scripts/publish.sh` |
| `/updates/Nonet-<版>.dmg` | 配る DMG | R2 | `scripts/publish.sh` |
| `/updates/Nonet<新>-<旧>.delta` | 差分（Sparkle の generate_appcast が作る） | R2 | `scripts/publish.sh` |
| `/download` | 最新の DMG へのリダイレクト | Worker が R2 の appcast を読んで決める | 何もしなくてよい |

アプリ・ページ・docs が指す URL。一度出したら変えない:

- appcast: `https://nonet.astlog.dev/updates/appcast.xml`（`Config/Nonet.xcconfig` の `NONET_APPCAST_URL`）
- プライバシーポリシー: `https://nonet.astlog.dev/privacy.html`（`NONET_PRIVACY_URL`）
- 使い方: `https://nonet.astlog.dev/guide.html`（`NONET_SUPPORT_URL`）
- ダウンロード: `https://nonet.astlog.dev/download`（ページのボタンは `thanks.html` を指し、そこからこの URL を開く）

`.html` を付けない URL（`/privacy`・`/guide`）は 404 になる。リンクには必ず `.html` を付ける。

| ファイル | 役目 |
|---|---|
| `cloudflare/wrangler.toml` | Worker の設定（名前 `nonet`・アカウント・custom domain・静的アセット・R2 のバインディング） |
| `cloudflare/src/` | Worker。`/`・`/en`・`/en/`・`/updates/*`・`/download` だけを受け持つ |
| `cloudflare/test/` | Worker のテスト（`node --test test/*.test.js`） |
| `cloudflare/scripts/smoke.sh` | 手元で本物の Worker（`wrangler dev --local`）を立て、すべての URL を curl で確かめる。Cloudflare には何も送らない |
| `cloudflare/scripts/appcast-info.js` | `scripts/publish.sh` が、appcast を Worker の `/download` と同じ読み方で読むための道具 |
| `cloudflare/package.json`・`package-lock.json` | wrangler を 4.133.0 に固定する |
| `site/_headers` | ページに付けるヘッダ（CSP など） |
| `site/.assetsignore` | アップロードしないファイル（Finder の `.DS_Store`） |
| `scripts/publish.sh` | リリースを1つ R2 に上げる |
| `.github/workflows/site.yml` | 確認（push・プルリクエスト）と、手で実行する本番のデプロイ |

### 1.1 応答の決まり

ページ（静的なアセット）は Worker を通らずに配られる。Worker が動くのは `wrangler.toml` の `run_worker_first` に書いたパスだけ。ブラウザで開いたとき（`Sec-Fetch-Mode: navigate` の付いた要求）も同じで、`/download` と DMG の URL は Worker が返す。

| URL | 状態 | Cache-Control | ほか |
|---|---|---|---|
| `/`・`/en/` | 200（Worker が `index.html` を引く） | `public, max-age=0, must-revalidate` | ETag。`If-None-Match` が合えば 304。ヘッダは `site/_headers`（CSP・`nosniff` など） |
| `/privacy.html` などのページ・`style.css`・`script.js`・`favicon.svg`・`robots.txt`・`sitemap.xml`・画像 | 200（`.html` のまま。リダイレクトしない） | 同上 | 同上 |
| `/en` | 301 → `/en/` | `public, max-age=86400` | |
| 無いパス（`/privacy`・`/_headers`・`/.DS_Store` も） | 404 と、いちばん近い `404.html` | `public, max-age=0, must-revalidate` | |
| `/updates/appcast.xml` | 200。`If-None-Match`・`If-Modified-Since` が合えば 304 | `no-cache`（使う前に毎回確かめる） | `application/xml; charset=utf-8`、ETag・Last-Modified、CSP `sandbox`、`nosniff` |
| `/updates/Nonet-<版>.dmg`・`/updates/*.delta` | 200。`Range` は 206、範囲の外は 416。`If-Range` が今の中身と違えば全体を 200 | `no-cache` | `application/x-apple-diskimage`・`application/octet-stream`、`Accept-Ranges: bytes`、Content-Length |
| `/updates`・`/updates/`・ほかの名前 | 404（R2 に問い合わせない。一覧も出さない） | `no-store` | |
| `/updates/*`・`/download` への POST など | 405 | `no-store` | `Allow: GET, HEAD` |
| `/download` | 302 → `https://nonet.astlog.dev/updates/Nonet-<最新>.dmg` | `no-store` | 最新は appcast の既定のチャンネルで `sparkle:version` が最大の項目。まだ何も出していなければ 404 ページ。appcast が読めない・その DMG が R2 に無いときは 503（`Retry-After: 300`。理由は Workers Logs） |

`no-cache` にしているのは、同じ名前のまま中身が変わりうるため（失敗したリリースを同じ版で作り直すなど）。ETag で確かめるので、変わっていなければ 304 で済む。

---

## 2. 最初の準備（一度だけ。持ち主がやる）

Cloudflare と GitHub のアカウントでする作業で、スクリプトはしない。上から順に進める。

### 2.1 R2 を有効にする

1. Cloudflare のダッシュボード（astlog.dev と同じアカウント）› Storage & databases › R2 › Overview
2. 案内に沿って R2 の購読（checkout）を済ませる

公式の手順は「checkout を済ませる」とだけ書いていて、支払い方法が要るかは書いていない。支払い方法の登録を求められたという報告が多いので、求められたら登録する。無料枠（「6. 上限と費用」）に収まれば請求は 0 円。astlog.dev の Worker はまだ R2 を使っていない（Web-AstLog の README に「R2 が未有効」とある）ので、このアカウントで初めて有効にすることになる。

### 2.2 バケットを作る

```bash
cd cloudflare
npm ci                                   # 固定した wrangler（4.133.0）を入れる
npx wrangler login                       # ブラウザで Cloudflare にログイン（astlog.dev と同じアカウント）
npx wrangler whoami                      # アカウント ID が 360a84624267a606e9d58788216eb46d か確かめる
npx wrangler r2 bucket create nonet-updates
```

- バケットは公開しない。R2 の設定で Public access（`r2.dev` の URL）も custom domain も付けない（作ったときは非公開）。外からは Worker の `/updates/*` だけで読む
- 名前は `wrangler.toml` の `bucket_name` と `scripts/publish.sh` が `nonet-updates` を前提にしている

### 2.3 API トークン

GitHub Actions がデプロイに使うトークンを1つ作る。ダッシュボード › My Profile › API Tokens › Create Token › Create Custom Token で、次の3つだけを付ける。

| 種類 | 権限 | 範囲 |
|---|---|---|
| Account | Workers Scripts: Edit | astlog.dev のアカウントだけ |
| Zone | Workers Routes: Edit | Specific zone: `astlog.dev` |
| Zone | Zone: Read | Specific zone: `astlog.dev` |

- Workers Scripts: Edit で、Worker（コード・静的アセット・設定）を出せる。R2 のバインディングを付けて出すのに R2 の権限は要らない（公式の Workers の権限の説明）
- Workers Routes: Edit は、custom domain（`nonet.astlog.dev`）を Worker に割り当てるのに要る。wrangler はデプロイのたびに割り当てを送るので、最初だけでなくずっと要る
- Zone: Read は、wrangler が `nonet.astlog.dev` からゾーン（astlog.dev）を探すのに使う
- Account Settings: Read と User Details: Read は要らない（`account_id` は `wrangler.toml` に書いてある）
- このトークンでは Worker を新しく作れない（新しい Worker を作るには Workers の Admin が要る）。だから最初のデプロイは手元から出す（2.5）
- R2 には触れない。DMG と appcast は手元から `scripts/publish.sh` で上げる

手元の `scripts/publish.sh` は、`wrangler login` のログインで動く。トークンで動かしたいときは、Account › Workers R2 Storage: Edit だけのトークンを別に作る。これはアカウントのすべてのバケットに書ける。バケットごとに絞れる「Object Read & Write」は S3 互換の API 用で、wrangler が使う Cloudflare の API には効かない。トークンはコマンドの行に書かない（シェルの履歴に残る）:

```bash
read -rs CLOUDFLARE_API_TOKEN && export CLOUDFLARE_API_TOKEN   # 貼り付けて Enter（画面に出ない）
scripts/publish.sh 1.2.0
```

### 2.4 DNS（nonet.astlog.dev）

astlog.dev の DNS は Cloudflare にある。`nonet.astlog.dev` のレコードと証明書は、最初のデプロイで Cloudflare が作る（Workers の Custom Domain）。**自分でレコードを作らない**。

先に、いま何も無いことを確かめる:

```bash
dig +short nonet.astlog.dev A
dig +short nonet.astlog.dev AAAA
dig +short nonet.astlog.dev CNAME
```

何も出なければよい（2026-10-30 には何も無かった）。ダッシュボード › astlog.dev › DNS › Records で `nonet` を検索しても見られる。

もうレコードがあったら:

1. 何に使っているかを確かめる（ほかのサービス・前に試した Pages など）
2. 要らなければ、DNS › Records で消してからデプロイする。CNAME があると Custom Domain は作れない（公式）
3. 消さずに手元から `wrangler deploy` すると、wrangler が「You already have DNS records that conflict for these Custom Domains … Update them to point to this script instead?」と聞く。消してよいものだけ `y` にする。別の Worker が `nonet.astlog.dev` を使っていても、同じように聞く
4. GitHub Actions の中（端末ではない）の wrangler は、**聞かずに上書きする**（wrangler 4.133.0 のコードで確かめた）。だから最初のデプロイは手元から出し、そのあとも DNS に `nonet` のレコードを足さない

astlog.dev は `Strict-Transport-Security: max-age=31536000; includeSubDomains` を返している。astlog.dev を開いたことのあるブラウザは、`nonet.astlog.dev` を HTTPS でしか開かず、証明書のエラーも先へ進めない。証明書ができるまで開けなくても、少し待ってから開き直す。

### 2.5 最初のデプロイ（手元から）

```bash
scripts/check-site.sh --strict          # 仮の値（TODO・.invalid）が残っていないか
cd cloudflare
npm ci
node --test test/*.test.js              # Worker のテスト
scripts/smoke.sh                        # 手元で本物の Worker を立て、すべての URL を確かめる
npx wrangler deploy --dry-run           # 束ねられるか
npx wrangler deploy                     # 2.2 の wrangler login のまま
```

- `--strict` が通らないうちは出さない。仮の値が残ったまま出すと、そのページがそのまま公開される（GitHub Actions のデプロイも同じところで止まる）
- DNS のことを聞かれたら 2.4 のとおりに答える
- 終わったら「4. 確かめる」の curl を通す。`/download` と `/updates/appcast.xml` は、最初のリリースを上げるまで 404

### 2.6 GitHub の設定

どれも、Actions の site を初めて実行するより前に済ませる（environment が無いまま実行すると、GitHub は保護の無い `production` を自動で作る）。

1. Settings › Environments › New environment で `production` を作る（作成済み）
2. Deployment protection rules の **Required reviewers** は、このリポジトリ（非公開）の今のプランでは使えない。代わりに、deploy は手動の実行（workflow_dispatch）でしか始まらないので、Run workflow を押す人がその場で承認したことになる（Actions を実行できるのは書き込み権限のある人だけ）。公開リポジトリにするか、Required reviewers を使えるプランにしたら、自分を付ける
3. **Deployment branches and tags** を「Selected branches and tags」にし、`main` だけを足す（設定済み）。site.yml の「main から実行しているか」は、実行したブランチの YAML に書いてあるのでそのブランチで消せる。守りはこちら
4. 2.3 のトークンを、この environment の **Environment secrets** に `CLOUDFLARE_API_TOKEN` として置く。Repository secrets には置かない（environment を外した workflow をどのブランチにでも書けば、ブランチの制限を通らずに読める）
5. （任意）Settings › Branches で `main` を保護し、CI と site の check を必須にする

site.yml の中でも、トークンは wrangler を呼ぶ step の env にだけ渡し（`npm ci` や action からは読めない。deploy の `npm ci` は `--ignore-scripts`）、`permissions: contents: read`、action は commit の SHA で固定してある（Web-AstLog と同じ SHA。上げるときは `git ls-remote --tags https://github.com/actions/<名前>` で引き直し、行末のタグ名も直す）。続けて2回実行しても、デプロイは並んで走らない（後のほうが待つ）。

`npm ci --ignore-scripts` で足りることは確かめてある。deploy に要るのは wrangler の JavaScript と、プラットフォームごとの optionalDependencies（esbuild・workerd の実体）で、install スクリプト（esbuild・workerd の `node install.js`）は要らない。`--ignore-scripts` で入れたものだけで `wrangler deploy --dry-run` と `wrangler dev --local` が動いた。

### 2.7 アプリとページの値

- `Config/Nonet.xcconfig`（xcconfig では `//` から後ろがコメントになるので `https:/$()/` と書く）:

  ```
  NONET_APPCAST_URL = https:/$()/nonet.astlog.dev/updates/appcast.xml
  NONET_SUPPORT_URL = https:/$()/nonet.astlog.dev/guide.html
  NONET_PRIVACY_URL = https:/$()/nonet.astlog.dev/privacy.html
  ```

- `site/` の「ダウンロード」のボタンは `thanks.html` を指し、そのページが `/download` を開く（リリースのたびに書き換えなくてよい）

`scripts/publish.sh` は、`NONET_APPCAST_URL` がこの URL でなければ止まる（アプリが別の場所を見ているなら、ここに上げても届かない）。

---

## 3. リリースごとの手順

1. [release.md](release.md) の「2. リリースごとの手順」で、DMG と appcast を作る（`scripts/release.sh`）
2. 試す: `scripts/publish.sh --dry-run 1.2.0`（確かめて、上げるものとコマンドを表示するだけ）
3. 公開する: `scripts/publish.sh 1.2.0`
4. release.md の「確かめる」（別の Mac で DMG を開く・一つ前の版から Sparkle で更新する）と「タグを付ける」

`scripts/publish.sh <バージョン>` がすること:

1. 準備を確かめる: `cloudflare/node_modules/.bin/wrangler`（無ければ `cd cloudflare && npm ci`）、`node`・`curl`・`codesign`・`xcrun`・`spctl`、`NONET_RELEASES_DIR` の `Nonet-<バージョン>.dmg` と `appcast.xml`、`Config/Nonet.xcconfig` の `NONET_APPCAST_URL`
2. 手元の appcast.xml を Worker と同じ読み方で読み、その版の項目の URL が `https://nonet.astlog.dev/updates/Nonet-<バージョン>.dmg`、`length` が DMG の大きさと同じで、既定のチャンネルで最新か（`/download` の行き先になるか）を確かめる。項目のデルタが手元にあり、大きさが合うかも見る。DMG の署名・公証のステープル・Gatekeeper の評価（`codesign --verify`・`xcrun stapler validate`・`spctl -a -t open --context context:primary-signature`）と、項目（DMG とデルタ）の `sparkle:edSignature` も確かめる（通らなければ、ネットワークに触れる前に止まる。dry run でも同じ）
3. 公開中の appcast を写しを使わずに取り、手元より新しくないか（別の Mac から出していないか）を確かめる。R2 の DMG・デルタの ETag（中身の MD5）を手元と比べ、もう公開した版のファイルを別の中身で差し替えようとしていれば止まる
4. 公開中の appcast を `NONET_RELEASES_DIR/appcast-history/<日時>-before-<バージョン>.xml` に控える（「5. 戻す」で使う）
5. `wrangler r2 object put nonet-updates/<名前> --file … --content-type … --remote` で、DMG → その版のデルタ（同じ中身がもう R2 にあるものは飛ばす）→ appcast.xml の順に上げる。途中で失敗したらそこで止まる。appcast.xml より前で止まれば、公開中の版は変わらない
6. 利用者と同じ URL で確かめる: 公開中の appcast にその版があるか、DMG の URL が 200 で Content-Length が合うか、`/download` がその DMG へ 302 で飛ぶか

| 環境変数 | 既定 | 意味 |
|---|---|---|
| `NONET_RELEASES_DIR` | `build/releases` | release.sh が DMG・デルタ・appcast.xml を置いたフォルダ（release.sh と同じ） |
| `CLOUDFLARE_API_TOKEN` | なし（`wrangler login` のログインを使う） | 2.3 の R2 のトークンで動かすとき |

オプション: `--dry-run`（何も上げない）、`--help`。

| 止まったところ | すること |
|---|---|
| 「固定した wrangler … がありません」 | `cd cloudflare && npm ci` |
| 「… のアップロードに失敗しました」 | 表示された wrangler のエラーを見る。認証（`npx wrangler login`・トークン）とバケット `nonet-updates` を確かめ、同じコマンドでやり直す（上がったデルタは飛ばされる） |
| 「公開中の appcast にはビルド … まであり、手元より新しい」 | 別の Mac から出した。公開中の appcast を `NONET_RELEASES_DIR/appcast.xml` に置き、`scripts/release.sh` からやり直す |
| 「ビルド … はもう公開されていて、R2 の … は中身が違います」 | 公開した版を作り直した。新しいビルド番号で `scripts/release.sh` からやり直す |
| 「… に届きません」「公開中の appcast を確かめられません」 | ネットワーク・Worker を出したか（2.5）・バケットがあるか |
| 「上げ終わりましたが、公開された中身が合いません」 | 「4. 確かめる」の curl で見る。直らなければ「5. 戻す」 |

ページだけを変えたとき: main に入れてから、GitHub › Actions › site › Run workflow（Branch: `main`）。check が通ると、続けて `wrangler deploy` が走る（Required reviewers は使えないので、承認の待ちは無い。Run workflow を押すことが承認になる）。ページを出しても R2（DMG・appcast）は変わらず、`publish.sh` もページを変えない。

---

## 4. 確かめる

```bash
B=https://nonet.astlog.dev
curl -sI "$B/"                                  # 200、content-security-policy
curl -sI "$B/privacy.html"                      # 200（.html のまま。リダイレクトしない）
curl -sI "$B/en"                                # 301、location: /en/
curl -sI "$B/no-such-page"                      # 404
curl -s -H 'Cache-Control: no-cache' "$B/updates/appcast.xml" | grep -E '<sparkle:(version|shortVersionString)>'
curl -sI "$B/updates/Nonet-1.2.0.dmg"           # 200、content-length が DMG の大きさ、cache-control: no-cache
curl -sI -H 'Range: bytes=0-99' "$B/updates/Nonet-1.2.0.dmg"   # 206、content-range: bytes 0-99/…
curl -sI "$B/download"                          # 302、location: …/updates/Nonet-<最新>.dmg、cache-control: no-store
curl -sI -H 'Sec-Fetch-Mode: navigate' "$B/download"           # ブラウザで押したときと同じ要求でも 302
curl -sI "$B/updates/Nonet-9.9.9.dmg"           # 404（無いファイルに 200 を返さない）
```

手元だけで確かめるなら `cloudflare/scripts/smoke.sh`（Cloudflare に何も送らない。`wrangler dev --local` と使い捨ての R2 で、上と同じことを確かめる）。

`/download` が 503 のときは、ダッシュボード › Workers & Pages › nonet › Logs に理由が出ている（appcast が読めない・最新の項目の DMG が R2 に無い、など）。

---

## 5. 戻す

### 5.1 ページと Worker

```bash
cd cloudflare
npx wrangler deployments list                     # 最近のデプロイと版の ID
npx wrangler rollback <版の ID> -m "理由"           # 版の ID を省くと、一覧から選べる
```

- 静的なアセット（`site/`）は Worker の版ごとに持つので、ページも一緒に戻る
- R2 の中身（appcast・DMG）は戻らない（公式: 結びつけたリソースはロールバックで変わらない）
- 戻せるのは最近の 100 版まで
- 落ち着いたら main も直して（revert など）、Actions で出し直す。直さないと、次のデプロイで元に戻る

### 5.2 出したアップデートを引っ込める

`scripts/publish.sh` は、上げる前の公開中の appcast を `NONET_RELEASES_DIR/appcast-history/` に控えている。それを上げ直す:

```bash
cd cloudflare
npx wrangler r2 object put nonet-updates/appcast.xml --remote \
  --file ../build/releases/appcast-history/<日時>-before-1.2.0.xml \
  --content-type "application/xml; charset=utf-8"
curl -s -H 'Cache-Control: no-cache' https://nonet.astlog.dev/updates/appcast.xml | grep '<sparkle:version>'
curl -sI https://nonet.astlog.dev/download        # 前の版の DMG を指す
```

- `--remote` を忘れない。wrangler 4 の `r2 object` は、付けないと手元の Miniflare に書くだけで「Upload complete.」と出る
- Sparkle は古い版へは戻さない。もう入れた人を直すには、直した版を**引っ込めた版より大きいビルド番号**で出す
- 手元の `NONET_RELEASES_DIR` も戻す。引っ込めた版の DMG とデルタをフォルダの直下から出し（例: `withdrawn/` の中へ）、控えの appcast を `appcast.xml` として置く。DMG を直下に残すと、次の `release.sh` の generate_appcast がまた項目に入れる
- `release.sh` は手元の appcast の最大より大きいビルド番号しか受け付けないが、引っ込めた版の番号はもう appcast に無い。次のビルド番号は、引っ込めた版より大きくすることを自分で守る
- 引っ込めた版の DMG は R2 に残しておいてよい（appcast から外れれば、Sparkle も `/download` も指さない）

---

## 6. 上限と費用

Workers は無料プラン、R2 は無料枠の範囲で動かす想定。数字は 2026-10-31 に公式の資料で確かめたもの。

| もの | 無料の範囲 | 超えたら | このサイトでは |
|---|---|---|---|
| Workers のリクエスト | 1日 100,000（UTC の 0 時に戻る） | Worker を通るパスが 429 になる（静的なアセットは出続ける） | Worker を通るのは `/`・`/en`・`/en/`・`/updates/*`・`/download` だけ。Sparkle の確認は1台につき1日1回ほど |
| Workers の CPU 時間 | 1回 10ms（R2 などを待つ時間は数えない） | その要求がエラー | `/download` は 1 MB より大きい appcast を読まない（503） |
| 静的なアセット | 要求は無料で回数の上限なし。1つの版に 20,000 ファイル、1ファイル 25 MiB まで | | ページだけ。DMG は R2 なので関係ない |
| Workers Logs | 1日 200,000 件、3日残る | | `head_sampling_rate = 1` で全部を残す |
| R2 の保存 | 10 GB-月 | $0.015 / GB-月 | DMG が数十 MB なら、数百回のリリースまで |
| R2 の Class A（PutObject など） | 月 100 万回 | $4.50 / 100 万回 | `publish.sh` の1回で数回 |
| R2 の Class B（GetObject・HeadObject） | 月 1,000 万回 | $0.36 / 100 万回 | appcast・DMG の1回の取得で2回（head と get。304 なら1回）。`/download` で2回 |
| R2 からの転送（egress） | 無料 | | |
| `wrangler r2 object put` | 1ファイル 300 MiB まで | 上げられない | `publish.sh` が先に確かめる |

先に来るのは Workers の1日 100,000 回のほう（R2 の Class B の無料枠は、1日あたりにするとそれより多い）。足りなくなったら Workers の有料プラン（1日の上限が無くなる）を考える。

出典:

- Workers の上限: https://developers.cloudflare.com/workers/platform/limits/
- 静的なアセットの料金と上限: https://developers.cloudflare.com/workers/static-assets/billing-and-limitations/
- Workers Logs: https://developers.cloudflare.com/workers/observability/logs/workers-logs/
- R2 の料金: https://developers.cloudflare.com/r2/pricing/
- R2 を有効にする: https://developers.cloudflare.com/r2/get-started/
- R2 の公開（`r2.dev`）: https://developers.cloudflare.com/r2/buckets/public-buckets/
- R2 のトークン: https://developers.cloudflare.com/r2/api/tokens/
- Workers の権限: https://developers.cloudflare.com/workers/authorization/workers/
- API トークンの権限の一覧: https://developers.cloudflare.com/fundamentals/api/reference/permissions/
- Custom Domain: https://developers.cloudflare.com/workers/configuration/routing/custom-domains/
- ロールバック: https://developers.cloudflare.com/workers/configuration/versions-and-deployments/rollbacks/

---

## 7. してはいけないこと

- **`not_found_handling = "single-page-application"` にしない**（SPA のフォールバック）。無い appcast や DMG にも `index.html` が 200 で返り、`release.sh` が公開中の appcast を確かめられず、Sparkle は読めないフィードを受け取る（release.md 1.7）
- `html_handling` を既定（`auto-trailing-slash`）に戻さない。`/privacy.html` が `/privacy` へ 307 で飛び、アプリと docs の URL がどれもリダイレクトになる
- **R2 のバケットを公開しない**（Public access の `r2.dev` の URL・バケットへの custom domain）。同じファイルが2つの URL から取れ、Worker のヘッダ（`no-cache`・CSP）も効かない。`r2.dev` は回数を絞られた開発用（公式）
- **appcast の URL を変えない**。出したアプリは `SUFeedURL` の URL だけを見に来る。どうしても変えるなら、古い URL から新しい appcast へのリダイレクトをずっと残す（Sparkle はリダイレクトをたどる）
- appcast を DMG より先に上げない。手で上げるときも DMG → デルタ → appcast の順（`scripts/publish.sh` はこの順でしか上げない）
- 公開した版の DMG・デルタを、別の中身で上書きしない。appcast の EdDSA の署名と合わなくなり、Sparkle がアップデートを断る。作り直したら新しいビルド番号で出す
- `/updates/*` と `/download` を長く写させない（Cache Rules の Cache Everything・`immutable` など）。`/download` は最新を指し続ける必要があり、DMG は同じ名前で作り直すことがある
- `workers_dev` と `preview_urls` を有効にしない（`*.workers.dev` から同じ中身が出る）
- `CLOUDFLARE_API_TOKEN` を Repository secrets・job の env・ファイルに置かない
- 最初のデプロイを GitHub Actions から出さない（DNS のレコードを聞かずに上書きする。2.4）
- `old_updates/`・`appcast-history/` を上げない（`publish.sh` はその版のファイルと appcast だけを上げる）

wrangler を上げるときは、`cloudflare/package.json` と `package-lock.json` を一緒に更新し、`wrangler.toml` の `compatibility_date` をその wrangler の workerd が対応する日付にそろえてから、`node --test`・`scripts/smoke.sh`・`wrangler deploy --dry-run` を通す。
