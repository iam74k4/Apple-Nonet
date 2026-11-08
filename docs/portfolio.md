# AstLog に Nonet を載せる

ポートフォリオ AstLog（https://astlog.dev）の Projects に Nonet を足すための下書き。管理画面の欄の順に、貼る値をそのまま置く。

- 書いた日: 2026-10-31
- 基にしたもの: AstLog は本番と同じ `main` の `cb899fd`。Nonet は branch `claude/nonet-app-features-b5e3dc`
- 発売前の値（「開発中」・テストの本数・リンク）は、[5. 発売時に直すもの](#5-発売時に直すもの) を見て直す

## いまの状態（2026-10-31 に公開）

https://astlog.dev/apps/item/nonet に公開した（並び順 15。AppMixer と SaifuLog の間）。この下の手順と値は、そのときの下書きとして残す。実際に入れたものとの違い:

- **画像**: アイコンは `App/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png`（512×512）。2026-11-06 に輪のアイコンへ差し替えた（`icon_256x256.png`。管理画面にログインせず、この Mac の wrangler から管理画面の保存と同じ手順で: KV `items/nonet-icon-<乱数>.png` に置く → D1 の `icon_url` を更新 → 古い画像を `archive/` に 90 日の控えとして移して公開の鍵を消す → `site:version` を進める）。2026-11-08 に、同じ絵を影なしにしたもの（`swift scripts/make-icon.swift --site-icon` の 256×256 を可逆の WebP にしたもの）へ同じ手順で差し替えた（KV `items/nonet-<16進 32 字>.webp`。いまの AstLog の `putImage` と同じ長さの乱数）。アプリのアイコンの影は板の外の余白を薄い黒で埋めて絵の端で四角く切れるので、明るい地では板のまわりに灰色の四角が見えていた（AppMixer・SaifuLog のアイコンは影なし）。メインとほかの画像は、AppMixer の Mac App Store の画像（2026-10 の版）と同じ作りの 1440×900 の JPEG を4枚（メイン: Xcode の9マス / 外枠とページの切り替え / アプリごとの9マス（Zoom） / ランチャー）。暗い無地のグラデーションの上にメニューバーを描き、左に緑の小見出し・2行の見出し・説明・3行の箇条、右に HUD を置く。HUD は実物のガラスを撮った（Debug ビルドの `--preview-hud --preview-app <bundle ID> --preview-backdrop <背景の画像>` で、背景を画面いっぱいに敷いてから撮る）
- **デモ動画（AstLog の「ほかの画像」の先頭（並び順 5）。2026-11-07 に輪の HUD で撮り直して差し替えた: 15.7 秒・321KB・H.264・1440×900。差し替えはアイコンと同じく wrangler から、KV `items/nonet-<乱数>.mp4` → D1 `item_shots.url`・`alt` → 旧動画を `archive/` へ → `site:version`。代替テキストに「指の動きは台本どおりに入れたもの」と書いた。メインの画像と「ほかの画像」2〜4 の JPEG も同じ日に輪の HUD で作り直した: `--preview-hud --snapshot` で撮った HUD の窓の PNG（色合わせをオンにし、別プロセスの暗い窓の上で撮ると白いアイコンになる）を、`scripts/compose-store-image.swift` が `docs/astlog-images/*.json` の文言と並べて 1440×900 の JPEG にする。ランチャーの HUD は、見本の設定でグローバルのページの先頭をランチャーに入れ替え、プロファイルの無いアプリ（TextEdit）を `--preview-app` にして撮る）**: Debug ビルドの `--demo` で撮る。本物の操作のロジック・NonetController・HUD を動かし、何も実行せず（performer を差し替える）、ポインタも抑止しない（HUD に重なるポインタだけは、本物と同じく開いている間 HUD の外へ寄せる）。画面の右下に、指の位置を示すトラックパッドの図が出る。`--demo-script` を付けると、実機の指の代わりに台本（`NonetUI/MenuBar/DemoScript.swift`。3回開く: 中央のマスを実行・輪のすぐ下で止めてグローバルのページへ移って実行・手前の外枠ですぐ離してやめる）を入れる。台本は `ShellDemoScriptTests` が本物の `EdgeSlideRecognizer`・`SessionEngine` に通して確かめている。付けなければ実機の指をそのまま図に出す。人が操作したものではなく、台本どおりの指の位置を入れたものなので、説明文もそう書く。撮るには画面が点いていてロックされていないこと（スリープ中・ロック中は画面の一覧が空になり、録画できない）。録画の道具 `scripts/record-screen.swift` は ScreenCaptureKit で書く（`screencapture -v` は録画を始められなかった）:

  ```bash
  swiftc -O -parse-as-library scripts/record-screen.swift -o build/record-screen
  app=build/DerivedData/Build/Products/Debug/Nonet.app/Contents/MacOS/Nonet
  # backdrop.png: 暗いグラデーションとメニューバーを描いた、画面と同じ縦横比の画像。$demo: 見本の設定（Xcode のプロファイルの中央が Claude Code）
  "$app" --config-dir "$demo" --demo-script --demo-start-file go --demo-app com.apple.dt.Xcode --demo-backdrop backdrop.png 2> demo.log &
  # 背景が出てから録画を始め、録画が始まってから台本を動かす。台本が終わったら録画を止め、go を消してアプリを終えさせる
  build/record-screen demo.mp4 30 0 0 1710 1069 1440 900 3000000 > rec.log &   # 範囲は demo.log の capture-region
  touch go; # …demo.log に "demo: finished" が出るまで待つ
  kill -INT %2; wait %2; rm go
  ```

  zsh では `${=REGION}` のように分けて渡す（変数を引用せずに書いても単語に分かれない）。録画を `go` の前に始めると先頭に背景だけの数秒が入るので、最後の引数（最初に捨てる秒）でその分を捨てる。背景の画像は 3420×2224 px（画面と同じ）の暗いグラデーションに上端の帯を描いた PNG を CoreGraphics で作ればよい。

  撮ったあとは、メニューバーの左側に画面が写っていないかを、0.5 秒ごとのフレームの明るさで確かめてから中身を見る（背景が消えると、ユーザーの画面が写る。`--demo-start-file` は、録画が止まって go を消すまで背景を出したままにする）。AstLog の動画は H.264 の MP4・10MB まで・HEVC は不可。
- **取り組みの内容（Story）**: AppMixer・SaifuLog と同じく空のまま
- **リンク**: 入れていない。販売ページ（nonet.astlog.dev）を開いたら `Website` を足す

## 0. 前提

- **下書きで保存し、公開は後にする。** Website のリンク先 https://nonet.astlog.dev/ は、まだ開いていない。Cloudflare に販売ページを出してから（`docs/hosting.md`）「公開する」にする
- 販売ページの仮の値（`¥TODO`・`https://TODO.invalid/…`・`support@TODO.invalid`）が残ったまま AstLog に公開すると、リンクの先で TODO が見える。`scripts/check-site.sh --strict` が通ってから公開する
- AstLog の Worker が持つのは `astlog.dev` の custom domain だけ（AstLog の `wrangler.toml` の `routes`）。同じ Cloudflare アカウントで `nonet.astlog.dev` を別の Worker（`cloudflare/`）に当てても、AstLog とはぶつからない
- 手元の AstLog（`/Users/iam74k4/Git/Web-AstLog`）は `develop` で、本番より古い。この文書の欄・上限・画像の決まりは本番の `main`（`cb899fd`）に合わせた（作品の文書の欄・動画・保存後に編集画面へ戻る、は `main` にしか無い）

## 1. 追加のしかた

1. https://astlog.dev/admin に GitHub か Google でログインする
2. 左のメニューの「作品」→ タブ「個人開発」→「＋ 作品を追加」（`/admin/items/new?type=app`）
3. 下の [2. 欄ごとの値](#2-欄ごとの値) を上から順に埋める。畳んである欄は見出し（「画像を追加する」など）を押して開く
4. 画像はファイルを選ぶ（URL は受け付けない）。入力エラーで戻されたときは、ファイルの欄だけ空に戻るので選び直す
5. 「公開する」は外したまま（下書き）で、「保存前にプレビュー」で見てから「保存」。保存すると、その作品の編集画面に戻る
6. ほかの画像の足す欄は1回に4つ。5つ以上足すときは、保存してから開き直すと空いた欄が出る。1回の保存で送れるのは合計 24MB まで（動画1本と画像3枚なら 13MB なので、1回で足せる）
7. 公開の条件（[0. 前提](#0-前提)）がそろったら「公開する」を入れて保存し、https://astlog.dev/apps/item/nonet を開いて確かめる

## 2. 欄ごとの値

### 基本情報

| 欄 | 値 | 決まり |
|---|---|---|
| タイトル | `Nonet` | 32 字まで（一覧の題・作品のページの見出し・共有カードの題）。下書きでも必須 |
| 説明文 | 下のとおり（86 字） | 「何であるか。何をしたか。」の2文を常体で。100 字まで。公開するときは必須 |

説明文:

```text
トラックパッドの上の縁から指を滑らせると、ポインタの周りにアプリごとの9つのアイコンが開く常駐アプリ。非公開の MultitouchSupport で指の位置を読み、直販に向けて開発中。
```

既にある作品の説明文と同じ形にしてある（AppMixer は「〜で…を制御する常駐アプリ。Mac App Store で配布している。」、SaifuLog は「…家計簿アプリ。…形で開発中。」）。

### 画像を追加する（任意）

| 欄 | 値 |
|---|---|
| 画像 | HUD の画面（[3. 画像](#3-画像) の「メインの画像」） |
| 画像の代替テキスト | `Nonet の HUD。Xcode の画面の上に9マス（ビルド・実行・テストなど）が出て、真ん中の「Claude Code」が白く光っている画面` |
| アイコン | `swift scripts/make-icon.swift --site-icon <出力先>.png` で書き出した 256×256 の PNG（影なし。[3. 画像](#3-画像) の「アイコン」） |
| ほかの画像（スクリーンショット） | [3. 画像](#3-画像) の「ほかの画像」1〜4（5 は任意）。代替テキストも同じ表にある |

代替テキストは、実際に撮った画面に合わせて直す（写っていないものを書かない）。画像を公開するときは1枚ずつ必須。

### 取り組みの内容を書く（任意）

Story の4つの欄。どれも「です・ます」で、空行で段落を分ける。作品のページの Screenshots の下に、小節「Story」として BACKGROUND / APPROACH / HIGHLIGHTS / RESULTS の見出しで出る（一覧には出ない）。長さに上限は無い。「前の本文（見出しなし）」の欄は、新しい作品では出ない。

背景:

```text
よく使う操作をボタン1つで呼び出したくても、ボタンの並んだ専用の機器を足せば机の上の物が増え、キーボードショートカットは覚えきれません。MacBook にもともとあるトラックパッドを、上の縁から指を滑らせたときだけボタンとして使えれば、どちらも要らなくなると考えてつくっています。

使うボタンはアプリごとに違うので、前面のアプリに合わせて9マスが切り替わるようにしました。Xcode や Zoom など 15 のアプリには最初から9マスを用意しています。どのアプリでも使うグローバルのページは、macOS 26 で無くなった Launchpad の代わりに、Mac に入っているアプリを並べたランチャーから始まります。
```

取り組み:

```text
企画・設計から実装、テスト、販売ページ、リリースの手順までを個人で進めています。最初に検証用のアプリをつくり、非公開の MultitouchSupport を読み込めることと、指の位置を読むだけならアクセシビリティなどの許可が要らないことを確かめてから、製品版に入りました。

製品版は、設計書で9つの担当範囲と、そのあいだの契約（protocol とメソッドの形）を先に決め、Claude Code の複数のセッションに分けて並行で実装しました。操作のロジックは AppKit に触れないモジュールに置き、テスト用の偽の実装を渡して確かめられる形にしています。
```

工夫:

```text
指の位置は MultitouchSupport の生のフレームから読み、最後に置いた指の絶対位置でマスを決めます（ポインタの位置は使いません）。9マスは、トラックパッドの上の縁で触れ始めた1本指がすぐに下へ滑ったときだけ開き、ゆっくりした動き・2本以上の指・手のひらでは開かないようにして、ふだんの操作と見分けています。開いている間のポインタ・クリックの抑止は CGEventTap で行い、キーボード用とポインタ用のタップは開いている間（ポインタ用はその直後の後片付けの間も）だけ有効にして、ふだんのキーとポインタのイベントをアプリに通さないようにしています。開いている間にキーが押されたら何も実行せずに閉じ、そのキーは前面のアプリに渡します。

開くとすぐにポインタの周りに9つのアイコン（HUD）を出し、指を滑らせてポインタを向けたアイコンで離すと実行、アイコンの輪の外で離すと何もせずに閉じます。滑らせて通りかかっただけのマスを実行しないよう、マスに 0.1 秒留まってから離したときだけ実行します。右か左の外へ出して止めるとページが切り替わります。マスの境界をまたぐたびにトラックパッドを振動させる作りにし、非公開の MTActuator を優先して、使えなければ公開の NSHapticFeedbackManager に切り替えます。

非公開のフレームワークを使うので Mac App Store には出せず、直販にしました。利用者のアカウントも、ライセンスを確かめるサーバーも持たず、ライセンスキーは Ed25519 で署名した文字列をアプリの中だけで確かめます。リリースは scripts/release.sh 1本で、Developer ID の署名と公証、DMG、Sparkle 2 のアップデートの配信情報（appcast）までをつくる形にし、外部のツールを差し替えたテストで手順を確かめています。
```

成果:

```text
まだ販売していません。14日間の試用のあとに買い切りで売る予定で、価格と販売サービスは決めていません。実機での手動テスト（上の縁から開く・マスで離して実行・外枠やキーでやめる・ポインタとクリックの抑止・触覚・2本指スワイプなど）は、これから製品版で通します。

自動テストは、Swift Testing のテスト 1,307 件と、リリースのスクリプト・販売ページ・ドキュメントのテスト 120 件です。scripts/test.sh がこれに加えてアプリのビルドと自己診断（--self-check）までを通します。macOS 14 以降を対象にし、アプリの画面と販売ページは日本語と英語で用意しています。
```

- 背景の1段落目は、販売ページの「3つの約束」（買わなくていい・覚えなくていい）から書いた。自分の動機と違うところがあれば直す
- 取り組みの「Claude Code の複数のセッションに分けて」は、`docs/architecture.md` の §3（担当）とコミットの記録から書いた。載せたくなければ、この1文を「担当範囲ごとに分けて実装しました」にする
- 既にある作品（AppMixer・SaifuLog・AstLog）は Story を書いていない。そろえるなら4つとも空のままでもよい（空の欄は出ない）

### リンクを追加する（任意）

| ラベル | URL | いつ |
|---|---|---|
| `Website` | `https://nonet.astlog.dev/` | いま入れる（公開は販売ページが開いてから） |
| `Download` | `https://nonet.astlog.dev/download` | **いまは入れない。** 公証済みの DMG を出したら、Website の次に足す（最新の DMG へ飛ぶ固定の URL） |
| `Repository` | — | **入れない。** 有料のアプリなので、GitHub のリポジトリ（`iam74k4/Apple-Nonet`）は非公開にした（2026-10-31） |

- ラベルは既にある作品と同じく英語（`App Store`・`Repository`）
- URL は `https://` で始める（`isSafeUrl`）。ラベルと URL の片方だけの行は保存できない

### 成果の数字を追加する（任意）

空のまま。売り上げ・ダウンロード数・利用者の数はまだ無い。テストの本数は Story の成果に書いた（実績値の欄は「1,200 DL 公開から3か月」のような使われ方の数のための欄）。

### 分類と担当を設定する（任意）

| 欄 | 値 |
|---|---|
| 担当メンバー | 岡崎 昂功 |
| プラットフォーム | macOS |
| 年 | `2026` |
| タグ | `Swift, SwiftUI, MultitouchSupport` |

- タグは既にある作品と同じく3つ（AppMixer は Swift・SwiftUI・Core Audio）。中心の技術を3つ目に置いた。足すなら `Sparkle` か `CGEventTap`
- 年は、ほかの開発中の作品（SaifuLog）と同じく `2026`。2027 年に入っても続けているなら `2026 — 現在` にする

### プライバシーポリシーとサポートを書く（任意）

**2つとも空のまま。** ここに書くと `https://astlog.dev/apps/item/nonet/privacy` と `…/support` にページができ、作品のページにリンクが並ぶ。Nonet のプライバシーポリシーと使い方は販売ページ（`https://nonet.astlog.dev/privacy.html`・`/guide.html`、英語は `/en/…`）が正で、アプリの「情報」タブのリンクもそちらに向ける（`Config/Nonet.xcconfig` の `NONET_PRIVACY_URL`・`NONET_SUPPORT_URL`）。2か所に置くと中身がずれる。

### 詳細設定（任意）

| 欄 | 値 |
|---|---|
| URL の末尾 | `nonet`（空でもタイトルから `nonet` ができる）。作品のページは `https://astlog.dev/apps/item/nonet` |
| 並び順 | AppMixer と SaifuLog の間の数。作品一覧の右の数字で2つの並び順を見て、その間にする（10 と 20 なら `15`） |

- 公開ページの並びは、年の新しい順 → 並び順（小さいほど先）→ 作った順。いまの本番は AppMixer・SaifuLog・AstLog の順（どれも 2026）で、出した製品（AppMixer）の次に置く想定
- `nonet` は本番で 404（2026-10-30。ほかの作品が下書きで使っていても 404 なので、保存で「この slug は既に使われています」と出たら別の名前にする）

### 公開する

外したまま（下書き）で保存する。公開するのは [0. 前提](#0-前提) の2つ（nonet.astlog.dev が開く・販売ページの TODO が無い）がそろってから。

## 3. 画像

### AstLog が受け付けるもの

| 欄 | 受け付けるもの | 上限 | どこに出るか |
|---|---|---|---|
| 画像（メイン） | PNG・JPEG・WebP・AVIF・GIF（動画は不可）。種類はファイルの中身で決まる。SVG・HEIC は不可 | 1MB（GIF は 3MB） | 作品のページ・Screenshots の先頭・共有カード（`og:image`）。横長で 300×157 以上なら大きいカード。AVIF は共有カードに使われない |
| 画像の代替テキスト | 文 | 公開するときは必須 | 読み上げ・`og:image:alt` |
| アイコン | 画像と同じ。正方形 | 1MB（GIF は 3MB） | 一覧の題の左（40px）と作品のページの見出しの左（64px）。代替テキストは無い |
| ほかの画像 | 画像と同じ ＋ H.264 の動画（MP4・MOV。HEVC は不可） | 1枚 1MB（GIF 3MB）・動画 10MB・8枚まで・1回の保存で合計 24MB | 作品のページの Screenshots（先頭を大きく、続きを2列。16:10 の枠に切らずに収める）。動画は押して再生し、共有カードには使わない |

全体の容量は 300MB（AstLog の概要に使っている量が出る）。既にある作品は、アイコンが 256×256 の WebP、スクリーンショットが 1440×900（16:10）の JPEG。

### 載せるもの

| 枠 | 中身 | 形 | 代替テキスト |
|---|---|---|---|
| アイコン | `swift scripts/make-icon.swift --site-icon <出力先>.png` で書き出した 256×256 の PNG。アプリのアイコン（`App/Assets.xcassets/AppIcon.appiconset/icon_256x256.png`）は**そのまま上げない**——影が板の外の余白を薄い黒で埋めていて、明るい地では板のまわりに灰色の四角が見える。ほかの作品にそろえて WebP にするなら可逆で書き出す | 正方形・256×256・板の外は透明 | なし |
| メインの画像 | HUD の画面。Xcode を前面にして HUD を出し、真ん中の「Claude Code」が光っている。上にプロファイル名「Xcode」と「マスで指を離すと実行」（Xcode のプリセットの並びは ビルド・実行・テスト／シミュレータ・Claude Code・クイックオープン。見本の設定でプリセットの真ん中のクイックオープンと右の Claude Code を入れ替えたもの／停止・クリーン・コミット） | 1440×900（16:10）の JPEG・1MB 未満 | `Nonet の HUD。Xcode の画面の上に9マス（ビルド・実行・テストなど）が出て、真ん中の「Claude Code」が白く光っている画面` |
| ほかの画像 1 | 操作の動画（10〜15 秒）。上の縁から指を滑らせて開く → HUD を見ながら指を滑らせ、マスで離して実行、次にもう一度開いて外枠で離してやめる | 16:10・H.264 の MP4・音なし・10MB 未満 | `Nonet の操作を収録した画面の動画。HUD が出て、指の位置に合わせて光るマスが移り、そのマスが実行される。続けてもう一度 HUD を出し、「離すとやめる」が出たところで何も実行せずに閉じる` |
| ほかの画像 2 | 設定のウィンドウ（プロファイル）。左にグローバルとアプリのプロファイル、中央に Xcode の 3×3、右にインスペクタ | 1440×900 の JPEG（ウィンドウを 16:10 の地に置く） | `設定のウィンドウ。左にグローバルとアプリのプロファイル、中央に Xcode の 3×3 のマス、右に選んだマスのアクションが並ぶ画面` |
| ほかの画像 3 | メニューから割り当て。メニューを検索し、項目を空いたマスへドラッグしているところ | 1440×900 の JPEG | `メニューから割り当て。起動中のアプリのメニューを検索し、項目を空いたマスへドラッグしている画面` |
| ほかの画像 4 | 初回の案内の「Mac にあるアプリから、9マスを用意しました」 | 1440×900 の JPEG | `初回の案内で、Mac に入っているアプリのうち9マスを用意してあるもの（Xcode・Safari など）を選ぶ画面` |
| ほかの画像 5（任意） | 設定の「一般」（開き方とやめ方の図・大きさ・触覚） | 1440×900 の JPEG | `全体の設定。トラックパッドの図で開き方とやめ方を示し、HUD の位置と大きさ・触覚の強さなどを選ぶ画面` |

- ほかの画像の中で、動画を先に置くか静止画を先に置くかは好みでよい（並び順の欄で変えられる）。メインの画像は動画にできない
- 動画は実際のアプリを収録する。販売ページのデモ（`site/index.html` の `.demo`）は絵のアニメーションなので、使うなら代替テキストを「販売ページの操作のデモ（アニメーション）。…」にする。実機の手動テストが済むまでは、静止画だけでもよい
- 英語の画面にしない（AstLog の文は日本語）

### つくり方

自分の設定を変えず、動いている Nonet と並べて動かせるよう、Debug ビルドの `--config-dir` で見本用のフォルダを使う（`--config-dir` が無いと、ほかの Nonet が動いているときはそちらに任せて終わる）。

- 見本の設定と初回の案内（ほかの画像 4）:

  ```bash
  app="$(scripts/build.sh)"; demo=~/Desktop/nonet-demo
  "$app/Contents/MacOS/Nonet" --config-dir "$demo" --show-onboarding
  ```

  「次へ」で「Mac にあるアプリから、9マスを用意しました」の画面まで進め、⌘⇧4 → Space → ウィンドウをクリックで撮る。Xcode が選ばれているのを確かめて「次へ：試してみる」→「スキップ」→「完了」まで進め、メニューバーから終了する
- 設定のウィンドウ（ほかの画像 2）: `"$app/Contents/MacOS/Nonet" --config-dir "$demo" --show-settings profiles` で開き、サイドバーで Xcode を、グリッドでマスを1つ選んでから ⌘⇧4 → Space で撮る（`--snapshot` はグローバルのプロファイルを選んだ状態しか書き出さない）
- 一般（ほかの画像 5）: `"$app/Contents/MacOS/Nonet" --config-dir "$demo" --show-settings general --snapshot ~/Desktop/nonet-shots`（ウィンドウを PNG に書き出して終わる。画面収録の許可は要らない）
- HUD（メインの画像）: 9マスを開いている間はキーを押すと HUD が閉じ、⌘⇧4 で撮れないので、Debug ビルドの `--preview-hud` を使う。`sleep 3; "$app/Contents/MacOS/Nonet" --config-dir "$demo" --preview-hud` を打ち、3秒のうちに Xcode を前面にして、HUD が出たら画面ごと撮る。Xcode のプロファイルがある見本の設定でないと、グローバルのランチャーが出る。Xcode には見せてよいプロジェクトを開いておき、パスやアカウント名が写っていないかを確かめる
- メニューから割り当て（ほかの画像 3）: 設定のウィンドウで「メニューから割り当て」を開き、項目をドラッグしている途中を ⌘⇧4 で撮る
- 縮小と JPEG: 画面ごとの PNG は先に 16:10 に切る（幅 W なら高さ W×0.625。2560×1664 なら `sips -c 1600 2560 full.png --out crop.png`、2940×1912 なら `sips -c 1838 2940 full.png --out crop.png`）。そのあと `sips -z 900 1440 -s format jpeg -s formatOptions 85 crop.png --out main.jpg`。1MB（1,000,000 バイト）を超えたら品質を下げる。ウィンドウだけの画像は、16:10 の地（1440×900）に置いてから JPEG にする
- 動画: ⌘⇧5 で 16:10 の範囲を収録し、H.264 で書き出す（QuickTime Player の書き出しでは HEVC を外す。AstLog は HEVC を受け付けない）。ffmpeg なら `ffmpeg -i in.mov -vf scale=1440:-2 -c:v libx264 -pix_fmt yuv420p -crf 23 -an -movflags +faststart out.mp4`。10MB を超えたら短くするか `-crf` を上げる

## 4. 書いたことの出どころ

| 書いたこと | 出どころ |
|---|---|
| トラックパッドの上の縁から指を滑らせると、アプリごとの 3×3 のボタンが開く | `README.md` の冒頭、`docs/user-guide.md`「Nonet とは」 |
| メニューバーの常駐アプリ（Dock に出ない） | `docs/architecture.md` §1（`LSUIElement`）、`project.yml` |
| 非公開の MultitouchSupport を dlopen で読み、指の位置を読む | `Packages/NonetKit/Sources/CMultitouch/CMultitouch.c`（`dlopen`）、`docs/spike-results.md` |
| 指の位置を読むだけなら許可が要らない（検証用のアプリで確かめた） | `docs/spike-results.md`「確認できたこと」 |
| 最後に置いた指の絶対位置でマスを決め、ポインタの位置は使わない | `docs/architecture.md` §5 の 4、`docs/user-guide.md`「Nonet とは」 |
| 上の縁で触れ始めた1本指がすぐに下へ滑ったときだけ開き、ゆっくりした動き・2本以上の指・手のひらでは開かない | `docs/architecture.md` §5 の 1、`NonetCore/Engine/EdgeSlideRecognizer.swift` |
| CGEventTap で開いている間のポインタ・クリックの抑止とキーでの中断。キーボード用とポインタ用のタップは開いている間（ポインタ用は後片付けの間も）だけ有効 | `Packages/NonetKit/Sources/NonetPlatform/Input/EventTapKeyboardMonitor.swift`（冒頭の説明と `updateKeyboardTap`・`updatePointerTap`） |
| 開いている間にキーが押されたら何も実行せずに閉じ、そのキーは前面アプリに渡す | `docs/architecture.md` §5 の 9、`docs/user-guide.md`「やめる（キャンセル）」 |
| 開くとすぐに HUD。マスに 0.1 秒留まってから離すと実行し、輪の外で離すとやめる | `docs/architecture.md` §5 の 3・4・6、`SessionEngine.swift` の `defaultLiftDwell`、`GridMapper.swift` の `GridInsets.cancelFrame` |
| 境界・ページ・実行で振動。MTActuator を優先し、使えなければ NSHapticFeedbackManager | `docs/architecture.md` §5 の 5 と §7、`NonetPlatform/Input/TrackpadHapticPlayer.swift` |
| Xcode や Zoom など 15 のアプリに9マスを用意 | `NonetCore/Model/Presets.swift` の `PresetLibrary.apps`（15件） |
| グローバルのページは Launchpad の代わりのランチャーから始まる（macOS 26 で Launchpad が無くなった） | `docs/architecture.md` §6「プロファイルとページ」、`Presets.swift` の `makeGlobalProfile` |
| Mac App Store ではなく直販。利用者のアカウントもライセンスのサーバーも無い | `README.md`、`docs/architecture.md` §1 |
| ライセンスキーは Ed25519 の署名で、アプリの中だけで確かめる | `NonetCore/Licensing/License.swift`（`Curve25519.Signing`）、`docs/release.md` の冒頭 |
| 14日間の試用のあと買い切り。価格・販売サービスは未定 | `README.md`、`site/index.html`（`¥TODO`・`TODO: 販売サービス名`） |
| scripts/release.sh が Developer ID の署名・公証・DMG・Sparkle 2 の appcast までをつくる形。外部のツールを差し替えたテストで確かめている | `docs/release.md` §2.4、`scripts/release.sh`、`scripts/tests/release_test.sh` と `scripts/tests/fakes/` |
| 実機での手動テストはまだ | `docs/release.md` §4「公開前のチェックリスト」の「アプリ」、`docs/architecture.md` §7 |
| 9つの担当範囲と契約を先に決め、Claude Code の複数のセッションで並行に実装 | `docs/architecture.md` §3、コミットの `Co-Authored-By: Claude` と `Merge ui-shell` などの統合のコミット |
| 操作のロジックは AppKit に触れないモジュールにあり、偽の実装を渡してテストする | `docs/architecture.md` §2（`NonetCore` は Foundation と Observation だけ、テストでは偽の実装を渡す） |
| Swift Testing のテストの件数 | `cd Packages/NonetKit && swift test` の最後の3行（`Test run with … tests` の合計。引数つきのテストは引数ごとに数える） |
| スクリプト・販売ページ・ドキュメントのテストの件数 | `scripts/tests/run.sh` の最後の行（「… 件すべて通りました」） |
| scripts/test.sh がアプリのビルドと自己診断まで通す | `scripts/test.sh` |
| macOS 14 以降 | `README.md`、`docs/user-guide.md`「動作環境」 |
| アプリの画面と販売ページは日本語と英語 | `NonetCore`・`NonetPlatform`・`NonetUI` の `Localizable.xcstrings`（すべてに英語。`scripts/sync-strings.sh --check` が確かめる）、`site/en/` |

## 5. 発売時に直すもの

| どこ | いま | 発売したら |
|---|---|---|
| 説明文の2文目 | `直販に向けて開発中。` | `販売ページで直販している。`（全体で 89 字） |
| 成果の1段落目 | まだ販売していない・価格と販売サービスは未定・実機の手動テストはこれから | 販売を始めた月・価格・販売サービスを書く。手動テストが済んだら、その一文を消す |
| 成果のテストの件数 | 書いた日の件数 | 下のコマンドで数え直す |
| 成果の CI の一文 | 書いていない | コードを push して GitHub Actions が緑になったら、2段落目に「プッシュのたびに GitHub Actions でも同じ一式を動かしています。」を足す |
| 工夫の触覚・ポインタの書き方 | MTActuator を優先し、使えなければ NSHapticFeedbackManager に切り替える作り | 手動テスト（ポインタの固定・触覚）で方式が決まったら、それに合わせる |
| リンク `Download` | 入れない | 公証済みの DMG を出したら `Download` / `https://nonet.astlog.dev/download` を Website の次に足す |
| リンク `Repository` | 入れない | リポジトリは非公開なので入れない |
| 公開する | 外す（下書き） | nonet.astlog.dev が開き、`scripts/check-site.sh --strict` が通ったら入れる |
| 画像 | — | 画面が変わったら撮り直し、代替テキストも合わせる。動画を販売ページのデモで代えていたら、実際のアプリの収録に替える |
| 実績値 | 空 | 本当の数（ダウンロード数など）が出たら。添えは「1,200 DL 公開から3か月」のように値と単位のあとに続けて読める形 |
| 年 | `2026` | 2027 年に入っても続けているなら `2026 — 現在` |

テストの件数の数え直し（リポジトリの一番上で）:

```bash
(cd Packages/NonetKit && swift test 2>&1 | grep 'Test run with')   # 3行の件数を足す
scripts/tests/run.sh | tail -1                                       # 「… 件すべて通りました」
```

発売したときの成果の1段落目の例（括弧の中を埋める）:

```text
（年月）に販売を始めました。14日間の試用のあと、（価格）の買い切りで、支払いは（販売サービス）が扱います。
```

## 6. AstLog 側の変更

要らない。本番の AstLog（`main` の `cb899fd`）の管理画面だけで、この作品を載せられる。

- 開発中であることは説明文と Story の成果で言う（AstLog に状態の欄は無く、SaifuLog も同じ書き方）
- 動画のスクリーンショット・Story の小さな Markdown・作品の文書の欄は、本番にはあるが手元の `develop` には無い。手元で試すときは `main` に合わせてから
