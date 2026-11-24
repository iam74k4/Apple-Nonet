# AstLog に Nonet を載せる

ポートフォリオ AstLog（https://astlog.dev）の Projects に Nonet を足すための下書き。管理画面の欄の順に、貼る値をそのまま置く。

- 書いた日: 2026-10-31
- 基にしたもの: AstLog は本番と同じ `main` の `cb899fd`。Nonet は branch `claude/nonet-app-features-b5e3dc`
- 発売前の値（「開発中」・テストの本数・リンク）は、[5. 発売時に直すもの](#5-発売時に直すもの) を見て直す

## いまの状態（2026-10-31 に公開）

https://astlog.dev/apps/item/nonet に公開した（並び順 15。AppMixer と SaifuLog の間）。この下の手順と値は、そのときの下書きとして残す。実際に入れたものとの違い:

- **画像**: アイコンは `App/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png`（512×512）。2026-11-06 に輪のアイコンへ差し替えた（`icon_256x256.png`。管理画面にログインせず、この Mac の wrangler から管理画面の保存と同じ手順で: KV `items/nonet-icon-<乱数>.png` に置く → D1 の `icon_url` を更新 → 古い画像を `archive/` に 90 日の控えとして移して公開の鍵を消す → `site:version` を進める）。2026-11-08 に、同じ絵を影なしにしたもの（`swift scripts/make-icon.swift --site-icon` の 256×256 を可逆の WebP にしたもの）へ同じ手順で差し替えた（KV `items/nonet-<16進 32 字>.webp`。いまの AstLog の `putImage` と同じ長さの乱数）。アプリのアイコンの影は板の外の余白を薄い黒で埋めて絵の端で四角く切れるので、明るい地では板のまわりに灰色の四角が見えていた（AppMixer・SaifuLog のアイコンは影なし）。メインとほかの画像は、AppMixer の Mac App Store の画像（2026-10 の版）と同じ作りの 1440×900 の JPEG を4枚（メイン: Xcode の9マス / 外枠とページの切り替え / アプリごとの9マス（Zoom） / ランチャー）。暗い無地のグラデーションの上にメニューバーを描き、左に緑の小見出し・2行の見出し・説明・3行の箇条、右に HUD を置く。HUD は実物のガラスを撮った（Debug ビルドの `--preview-hud --preview-app <bundle ID> --preview-backdrop <背景の画像>` で、背景を画面いっぱいに敷いてから撮る。背景は `scripts/make-backdrop.swift` の共通のもの）
- **デモ動画（AstLog の「ほかの画像」の先頭（並び順 5）。2026-11-07 に輪の HUD で撮り直して差し替えた: 15.7 秒・321KB・H.264・1440×900。差し替えはアイコンと同じく wrangler から、KV `items/nonet-<乱数>.mp4` → D1 `item_shots.url`・`alt` → 旧動画を `archive/` へ → `site:version`。代替テキストに「指の動きは台本どおりに入れたもの」と書いた。メインの画像と「ほかの画像」2〜4 の JPEG も同じ日に輪の HUD で作り直した: `--preview-hud --snapshot` で撮った HUD の窓の PNG（色合わせをオンにし、別プロセスの暗い窓の上で撮ると白いアイコンになる）を、`scripts/compose-store-image.swift` が `docs/astlog-images/*.json` の文言と並べて 1440×900 の JPEG にする（背景はデモ動画と同じ `scripts/make-backdrop.swift` の PNG。`swift scripts/make-backdrop.swift backdrop-store.png 2880 1800` を3つめの引数に渡す）。ランチャーの HUD は、見本の設定でグローバルのページの先頭をランチャーに入れ替え、プロファイルの無いアプリ（TextEdit）を `--preview-app` にして撮る）**: Debug ビルドの `--demo` で撮る。本物の操作のロジック・NonetController・HUD を動かし、何も実行せず（performer を差し替える）、ポインタも抑止しない（HUD に重なるポインタだけは、本物と同じく開いている間 HUD の外へ寄せる）。画面の右下に、指の位置を示すトラックパッドの図が出る。`--demo-script` を付けると、実機の指の代わりに内蔵の台本（`NonetUI/MenuBar/DemoScript.swift`。1つのアプリのまま4回開く: 上のマスを実行・輪のすぐ下で止めてグローバルのページへ移り左のマスを実行・もう一度グローバルへ移り輪の右で止めて次のページの右上のマスを実行・真ん中から輪の下の外へ出てすぐ離してやめる）を入れる。`--demo-script-file <JSON>` なら、内蔵の代わりにファイルの台本を入れる（`[[秒, x, y], [秒], …]`。x は左が 0・y は手前が 0 の 0〜1 で、x・y の無い行は指を離す。収録に使うものは `scripts/demo/xcode.json`・`zoom.json`）。読めない台本・検査に落ちる台本（時刻が戻る・x か y が 0〜1 の外・指を離さずに終わる など）では、背景が無いときと同じく `demo: error: …` を書いて始めずに終える。内蔵の台本と `scripts/demo/` の台本は、`ShellDemoScriptTests` が本物の `EdgeSlideRecognizer`・`SessionEngine` と、ポインタでマスを選ぶ `ControllerPointerSelection` に通して確かめている。付けなければ実機の指をそのまま図に出す。人が操作したものではなく、台本どおりの指の位置を入れたものなので、説明文もそう書く。撮るには画面が点いていてロックされていないこと（スリープ中・ロック中は画面の一覧が空になり、録画できない）。録画の道具 `scripts/record-screen.swift` は ScreenCaptureKit で書く（`screencapture -v` は録画を始められなかった）:

  **デモ動画の決まり（2026-11-09。2026-11-11 に背景を墨の無地に変えた。全アプリで同じ。手順と道具は skill `app-promo-media`（`~/.claude/skills/app-promo-media/`）、要点は `~/.claude/rules/demo-video.md`）**:

  - 実際の画面（壁紙・ほかのアプリのウインドウ・本物のメニューバー）は写さない。画面いっぱいに共通の背景を敷いて、その上で撮る
  - 背景はどの動画も `scripts/make-backdrop.swift` の同じもの（墨の無地 `#222226` と、日付・コントロールセンター・Wi-Fi・電池・アプリのアイコンを並べたメニューバー（帯は `#1A1A1D`）。グラデーションも飾りも持たない）。販売ページ・AstLog の画像（`compose-store-image.swift`）も同じ背景なので、画像と動画で見た目がそろう。色と寸法は変えない
  - 操作は図で見せる。画面の右下に、指の位置を示すトラックパッドの図を出す（`DemoTrackpadView`）
  - 見て機能が分かる台本にする。名前のある操作を選んで実行する場面を、1場面に1つずつ見せ、同じ操作を繰り返さない。画面全体を覆う表示は避ける（「画面に置く」の真ん中の「最大化」は、置く場所の枠が画面いっぱいに出て、何の枠か分からない。「左半分」なら枠だと分かる）
  - `--demo` は背景（`--demo-backdrop`）が無い・画面と縦横比が違うと、始めずに終える

  いまの手順（2026-11-11 に載せた動画の撮り方）。Xcode と Zoom を1回ずつ撮り、つなぐ:

  ```bash
  scripts/build.sh                                  # Debug のアプリ（build/DerivedData）
  swiftc -O scripts/vidtool.swift -o build/vidtool
  # $demo: 見本の設定のフォルダ（「3. 画像」の「つくり方」）。Xcode と Zoom のプロファイルがあり、グローバルは「画面に置く」・ランチャーの順
  scripts/demo/record.sh xcode com.apple.dt.Xcode scripts/demo/xcode.json "$demo"   # → build/demo/xcode-raw.mp4
  scripts/demo/record.sh zoom us.zoom.xos scripts/demo/zoom.json "$demo"            # → build/demo/zoom-raw.mp4
  # 場面ごとの区間をつなぎ（場面の間の待ちは 0.5 秒ほどに詰める）、真ん中を2倍に寄せて 1440×900 に縮める。
  # メニューバーの帯（上の 36px）は背景で塗り直し、右下の図（--keep）は寄せずに元の位置と大きさで描く
  swift scripts/make-backdrop.swift build/backdrop-store.png 2880 1800
  X=build/demo/xcode-raw.mp4; Z=build/demo/zoom-raw.mp4
  build/vidtool concat build/demo/demo.mp4 build/backdrop-store.png 36 --size 1440 900 --zoom 2 --keep 1078,648,330,223 \
    $X 2.3 4.3  $Z 2.1 4.5  $Z 5.6 9.3  $Z 10.4 15.0  $Z 16.1 20.3  $Z 21.5 23.7   # 2026-11-20 の区間（撮るたびにコマを見て決める。英語は $X 2.3 4.2 … $Z 2.0 4.5  $Z 5.5 9.3  $Z 10.4 15.0  $Z 16.0 20.3  $Z 21.5 23.6）
  ```

  - `scripts/demo/record.sh <名前> <bundle ID> <台本の JSON> <見本の設定のフォルダ>` は、1本を次の順で撮る（順を変えると、実際の画面が写る）: 収録の道具（`build/record-screen`・`build/demo-pointer`）と、いまの主の画面の大きさの背景（`build/backdrop.png`）を作る → アプリを `--demo-script-file <台本> --demo-start-file <ファイル>` で起こして背景を敷く → アプリが書いた範囲（`demo: capture-region=`。画面の上端から幅いっぱいの 16:10）の収録を始める → ポインタを範囲の真ん中へ動かす（HUD はポインタの位置に開く。終わったら元の位置へ戻す）→ 開始のファイルを作って台本を流す → `demo: finished` が出たら収録を止める → 開始のファイルを消して、アプリに背景を消させる。途中で止まったときも、収録を止めてからアプリを終える
  - 台本が実行するところだったアクションは、`build/demo/<名前>-demo.log` の `demo: perform …` で分かる（デモは何も実行しない）。見本の設定では、`xcode.json` が ⌘R（上の「実行」）、`zoom.json` が ⇧⌘A（真ん中の「ミュート」）・`placeWindow(… WindowRegion.left)`（グローバルの「左半分」）・`launchApp(… "com.apple.mail" …)`（ランチャーの右上の「メール」）・⌃⇧⌘4（ユーティリティの真ん中の「撮影してコピー」）の順で、最後の場面は何も出ない。zoom.json の場面は、真ん中で「ミュート」→ 輪の上で止めてグローバルへ移り「左半分」→ もう一度上で移って右で止めてランチャーへ送り「メール」→ 輪の外を左回りに下へ出て止めてユーティリティへ移り「撮影してコピー」→ 右上の隅（帯より外。止めても何も切り替わらない）で止めて離し、やめる（2026-11-20。上下の入れ替え（下＝ユーティリティ、上＝グローバル）に合わせ、売りの機能を1場面に1つずつ見せる台本にした）。見本の設定はグローバルを「画面に置く」・「ランチャー」・下のページの「ユーティリティ」にする（止めている間に行き先の名前が出るので、ページに名前を付けておく）。どのマスが何かは設定しだいなので、設定を変えたら撮る前にここを見る
  - `vidtool concat` の区間（秒）は、撮った動画のコマを見て決める。台本は、収録が始まって 1 秒あまり後に動き出す。動きの無い間はコマが無いので、区間の頭は直前のコマで埋まる。同じ動画の区間を何度並べてもよいので、場面ごとに区間を切って、場面の間の待ち（台本では 1 秒あまり）を 0.5 秒ほどに詰める
  - **最初の区間は、HUD が開いたところから始める。** AstLog の作品のページは、動画の 0.1 秒目を表紙（再生の前に出る絵）にする。頭に上の縁から滑らせるところを入れると、表紙が何も無い暗い画面になる。上の縁から開く動きは、2つ目からの場面で見える
  - **真ん中を2倍に寄せる（`--zoom 2`）。** HUD は画面の幅の 14% しかなく、ページの大きさ（幅 1280 の画面で動画が半分になる）では、マスの名前の札（「実行」「メール」）が潰れて読めなかった。寄せても粗くならないよう、`record.sh` は 2880×1800 で撮り、`--size 1440 900` で縮める。メニューバーと右下の図は寄せない（どのアプリの動画でも同じ位置と大きさ）
  - macOS は収録中、メニューバーの右（描いた日付のすぐ左）に紫の印を出し、これが収録に写る。WindowServer が描く印なので、ScreenCaptureKit の `excludingApplications`（コントロールセンター・SystemUIServer）では消えなかった。メニューバーの帯は背景と同じはずなので、`vidtool concat`（1本だけなら `vidtool patch`）がコマごとに背景の PNG で塗り直して消す
  - **英語の動画**（販売ページの英語のページの `site/images/demo-en.mp4`。2026-11-15 に撮った）: 同じ台本を、アプリを英語で動かして撮る。`NONET_DEMO_LANGUAGE=en` を付けると、`record.sh` がアプリを `-AppleLanguages (en)` で動かし、背景の日付を「Sat Nov 7 9:41 AM」で描く（`make-backdrop.swift --clock`。位置・字・色は同じ）。マスの名前は設定に書いてある文字なので、見本の設定の日本語の文字を、カタログの英語の訳（NonetCore を先に、無ければ NonetUI。「iPhoneミラーリング」は「iPhone Mirroring」）に置き換えた写し（`build/demo-config-en`）を渡す。仕上げの背景も `swift scripts/make-backdrop.swift build/en/backdrop-store.png 2880 1800 --clock "Sat Nov 7 9:41 AM"` にする。区間は日本語の収録の区間に、撮った2本のずれ（真ん中と図の明るさを比べて合わせた。2026-11-15 は Xcode +0.20 秒・Zoom +0.06 秒）を足したもの:

    ```bash
    NONET_DEMO_LANGUAGE=en scripts/demo/record.sh xcode-en com.apple.dt.Xcode scripts/demo/xcode.json build/demo-config-en
    NONET_DEMO_LANGUAGE=en scripts/demo/record.sh zoom-en us.zoom.xos scripts/demo/zoom.json build/demo-config-en
    X=build/demo/xcode-en-raw.mp4; Z=build/demo/zoom-en-raw.mp4
    build/vidtool concat build/en/demo-en.mp4 build/en/backdrop-store.png 36 --size 1440 900 --zoom 2 --keep 1078,648,330,223 \
      $X 2.40 4.45  $Z 1.48 4.46  $Z 5.08 9.54  $Z 10.16 15.54  $Z 16.16 19.08
    ```

    表紙（`demo-en-poster.jpg`）は、日本語と同じく 0.1 秒目のコマ。使い方と機能の静止画（`hud-*.webp`）は文字が無いので、日英で共通のまま
  - 内蔵の台本（`--demo-script`）は、同じ流れを1つのアプリ（`--demo-app`。既定は Xcode）で通して見せる。確かめるだけなら、録画せずに流して標準エラーを見る: `swift scripts/make-backdrop.swift build/backdrop.png` のあと `"$(scripts/build.sh)/Contents/MacOS/Nonet" --config-dir "$demo" --demo-script --demo-backdrop build/backdrop.png`（20 秒あまり、主の画面の全体が背景で覆われる。終わると自分で終わる）

  撮ったあとは、メニューバーの左側に画面が写っていないかを、0.5 秒ごとのフレームの明るさで確かめてから中身を見る（背景が消えると、ユーザーの画面が写る。`--demo-start-file` は、録画が止まって開始のファイルを消すまで背景を出したままにする）。AstLog の動画は H.264 の MP4・10MB まで・HEVC は不可。代替テキストには「指の動きは台本どおりに入れたもの」と、2回の収録をつないだことを書く。
- **2026-11-08 の差し替え**: アイコンを暗い丸い台に載せ、下で止めてグローバルのページへ移るようにした版で、メインの画像・ほかの画像 2〜4・デモ動画（13.9 秒・301KB・H.264・1440×900）を作り直し、同じ wrangler の手順で差し替えた（KV `items/nonet-<16進 32 字>.<拡張子>` に置き、metadata は `contentType` と `size` → D1 の `items.image_url`・`image_alt` と `item_shots` の `url`・`alt`・寸法を書き換え → 古い5つを `archive/`（`expirationTtl` 90 日、metadata に `originalKey`・`archivedAt`）へ写してから消す → `site:version` を新しい UUID に）。メインの代替テキストは真ん中を「Claude Code」に、動画とほかの画像 2 の代替テキストは下で止めてグローバルのページへ移る流れに直した。見本の設定は Xcode の1ページ目の真ん中と右（クイックオープンと Claude Code）を入れ替えたもの、ランチャーの画像はさらにグローバルの1・2ページ目を入れ替えたもの。動画は台本を流す前にポインタを録る範囲の真ん中へ動かし（HUD はポインタの位置に開く）、0.5 秒ごとのコマで背景以外が写っていないことを確かめた。zsh では行を単語に分けないので、キーと大きさを並べて回すときは bash で回す
- **共通の背景にそろえる（2026-11-09）**: 所有者が全アプリの背景を無彩色（`#1F1F21` → `#0E0E0F`）に決めた。画像4枚は `make-backdrop.swift` の背景で作り直し、wrangler で差し替えた（メイン `nonet-16b4aeab7423a13f7a094fa2bb251c28.jpg`・並び順 10 `nonet-86ff5fe439e90fec7d704799be0f943d.jpg`・20 `nonet-2cc9d47189abd165f66034a897454198.jpg`・30 `nonet-8d62ab7ff343ebd1a1f466aad00f8955.jpg`。前の4枚は `archive/` に 90 日。文言は公開中の版（ページの画像の箇条は develop の `docs/astlog-images/shot10.json`））。**動画（2026-11-08）はまだ前のまま**: メニューバーが日付やアイコンの無い帯で、地も前の色。所有者の指示で、Nonet の動作確認のセッションが終わってから、その版で撮り直して差し替える（2026-11-09 に develop を入れた版で試しに撮ったものは `build/astlog/demo.mp4`。差し替えには使わない）。撮り直すときの残りの課題: macOS が収録中に出す紫の印が、描いたメニューバーの日付のすぐ左に写る。WindowServer が描く印なので、ScreenCaptureKit の `excludingApplications`（コントロールセンター・SystemUIServer）では消えなかった。コマごとにメニューバーの帯（上の 34pt）を背景の PNG で塗り直すなど、収録の側で消す（→ 2026-11-11 に撮り直し、`scripts/vidtool.swift` で塗り直した。次の項）
- **上下の入れ替えに合わせた撮り直し（2026-11-20。astlog.dev には 2026-11-25 に公開。販売ページは 1.1.0 で公開）**: 下＝ユーティリティ・上＝グローバルに変えた版（1.1.0）に合わせ、売りの機能を1場面に1つずつ見せる台本（Xcode の「実行」→ Zoom の「ミュート」→ 上でグローバルの「左半分」→ 上・右でランチャーの「メール」→ 下でユーティリティの「撮影してコピー」→ 右上の遠い外でやめる）で、日本語（19.1 秒）と英語（19.2 秒）を撮った。販売ページの `site/images/demo.mp4`・`demo-poster.jpg`・`demo-en.mp4`・`demo-en-poster.jpg` と、ページの動画の説明はこのブランチで差し替え済み。配っている 1.0.1 は下でグローバルが開くので、販売ページは **1.1.0 を出すときに一緒に公開する**（所有者の決定。販売ページは `main` から出す）。astlog.dev は、所有者の指示で 1.1.0 を待たずに 2026-11-25 に差し替えた（下の「astlog.dev の差し替え（2026-11-25）」）。AstLog の動画も、Nonet の動画を再生する場面があるので撮り直す（まだ）
- **墨の無地の背景と、機能が分かる台本（2026-11-11）**: 所有者が共通の背景を墨の無地（`#222226`。AstLog の墨）に変え、動画は「見て機能が分かる台本」にすると決めた（前の内蔵の台本は「見せる操作の選び方が悪い」「最大化の枠で全画面が紺になるのが変」）。メインの画像・ほかの画像 2〜4・動画をこの背景で作り直し、wrangler で差し替えた（メイン `nonet-af1017a95ebeb5f183f305b7801c01c2.jpg`・動画 `nonet-36ce6a1fef9bead9deefe38a6e202400.mp4`・外枠の絵 `nonet-75989e4c3f0d8e16b004e41947d8011c.jpg`・Zoom の絵 `nonet-f9cc6387c046c5abdf09dc0815a83390.jpg`・ランチャーの絵 `nonet-b72721a8175144088527855356805cd3.jpg`）。動画（22.3 秒・348KB・H.264・1440×900。区間は Xcode 1.3〜5.0 秒・Zoom 1.6〜20.2 秒）は、Xcode（`scripts/demo/xcode.json`: 上の「実行」で離す）と Zoom（`scripts/demo/zoom.json`: 真ん中の「ミュート」→ 輪の下で止めてグローバルの「左半分」→ もう一度グローバルへ移り、輪の右で止めてランチャーの「メール」→ やめる）の2回の収録をつないだもので、代替テキストにもそう書いた。撮り方は上の「いまの手順」。最初に載せた動画（`nonet-62411c9b548a43b2096567635e931529.mp4`）は、収録と書き出しが色を BT.709 として扱い、地が `#2B2B2B` に明るく表示された（画像は `#222126`）。同じ日の夜に、色を sRGB で書く `record-screen.swift`・`vidtool.swift` と、この「いまの手順」で撮り直して差し替えた（前の動画は `archive/` に 90 日）。撮っている間にマウスが動くと、次の場面の HUD がそこで開き、画面の端では実際の Dock が背景より上に出て写った。撮る間はマウスとトラックパッドに触れない。内蔵の台本（`--demo-script`）も、同じ流れを1つのアプリで見せる形に組み直した（載せた動画には使っていない）。同じ夜のレビューで、ページの上でマスの名前が読めない・22 秒のうち 8 秒が何も無い画面・表紙が暗い無地・「やめる」場面で真ん中の「ミュート」が名前つきで光ってから閉じる（選んだように見える）が見つかり、撮り直して差し替えた（動画 `nonet-e759af75961aefffff06cfcb65c91af9.mp4`・17.8 秒・628KB。前の `nonet-36ce6a1fef9bead9deefe38a6e202400.mp4` は `archive/` に 90 日）: 真ん中を2倍に寄せ、場面の間を詰め、HUD が開いたところから始める。「やめる」場面は、開いてすぐ指を上へ戻して輪の上の外で 1 秒止め（アプリの層の上の帯は、切り替える先も案内も無い）、鍵が薄くなったところで離す（`zoom.json` と内蔵の台本の4つ目）
- **取り組みの内容（Story）**: AppMixer・SaifuLog と同じく空のまま
- **リンク（2026-11-25）**: `Website` / `https://nonet.astlog.dev/` の1本だけを足した（日本語の販売ページ。AstLog の文は日本語なので、英語の `/en/` は足さない）。作品のページと Projects の一覧に出る。押し手（`lead_link`）は 0 のまま。管理画面は使わず、この Mac の wrangler で書いた: 本番 D1 の `item_links` に1行（`item_id` 4・`sort_order` 0）→ `items.updated_at` を進める → AstLog のリポジトリで `npm run site:touch`（`site:version` を進める）。`Download`・`Buy` は発売してから足す（[リンクを追加する](#リンクを追加する任意)）
- **astlog.dev の差し替え（2026-11-25）**: 所有者の指示で、上下の入れ替えの版の動画と外枠の絵を、1.1.0 を待たずに差し替えた。管理画面は使わず、この Mac の wrangler で、skill `app-promo-media` の `astlog-replace.py` を流してから `npm run site:touch`
  - 動画（「ほかの画像」の先頭、id 13）: `nonet-e759af75961aefffff06cfcb65c91af9.mp4` → `nonet-b45d5f6e299907f9be0344e926ebf8f4.mp4`（19.1 秒・825KB・H.264・1440×900。販売ページの `site/images/demo.mp4` と同じもの）。代替テキストは `build/astlog/plan.json`（`.claude/worktrees/demo-v2`）の文。plan の動画の行には寸法（`w`・`h`）が要る。無いと、道具は新しい動画を KV に置いてから止まる（このときは、置かれたキーが D1 から指されていないのを確かめて消した）
  - 外枠の絵（id 10）: 箇条の3行目を「下で止めると、グローバルのページ」（札「下」）から「下でユーティリティ、上でグローバル」（記号 `arrow.up.arrow.down`・札「上下」）に直して作り直した（`docs/astlog-images/shot10.json`）。`nonet-75989e4c3f0d8e16b004e41947d8011c.jpg` → `nonet-5db58210691c270ae4d0cb2fe3dc743c.jpg`。代替テキストも「下で止めるとユーティリティ、上で止めるとグローバルのページ」に直した。HUD は `develop` の Debug ビルドの `--config-dir <見本の設定 build/demo-config の写し> --preview-hud --preview-app com.apple.dt.Xcode --snapshot <フォルダ>` が書く `round2-1-HUDOverlayPanel.png`（指が外枠にある状態）
  - 背景は、`demo-v2` の `build/backdrop-store.png`（2026-11-20 に書き出したもの）を使った。いまの macOS で `make-backdrop.swift` から書き出し直すと、メニューバーの電池（`battery.100percent`）が塗りつぶしの形に、日付が「11月7日(土)」（括弧の前の空きが無い）に変わり、公開中のほかの画像とそろわない。前の絵と比べて、3行目の外の色の差は最大 13/255（JPEG の揺れの範囲）
  - 前の2つは `archive/` に 90 日。差し替えたあと、作品のページに新しい2つが出て、URL が 200（動画の範囲の要求は 206）で返り、中身が手元のファイルと一致し、壊れた絵とコンソールのエラーが無いのを確かめた（`astlog/astlog-proof.mjs`）
  - 残り: AstLog の動画の撮り直し（Projects の一覧と Nonet の作品のページの文も、下の項で変わった）。作品の説明文は、同じ日に強く押し込む開き方で書き直した（次の項）
- **説明文と状態（2026-11-25）**: 所有者の指示で、AstLog の全作品の説明文を「AI っぽさ」の少ない短い文に書き直し、開発中・販売中のような状態は説明文から外して、AstLog に足した状態の欄（Web-AstLog の PR #85。管理画面の「一覧の札」で選び、公開ページには英語の札で出る）に移した。書き方は所有者が決めた: 短い文に分ける・技術の名前はタグに任せる・Nonet は 1.1.0 の既定の開き方（強く押し込んで少し止める）で書く・Nonet の状態は「開発中」
  - Nonet の説明文: 「トラックパッドの上の縁から指を滑らせると、ポインタの周りにアプリごとの9つのアイコンが開く常駐アプリ。非公開の MultitouchSupport で指の位置を読み、直販に向けて開発中。」 → 「Mac のトラックパッドを、アプリごとの9つのボタンにするアプリ。強く押し込んで少し止めると、ポインタの周りに開く。」。状態は「開発中」（札 `In development`）
  - 配っている 1.0.x とページの動画は、上の縁から滑らせて開く版のまま。説明文だけが 1.1.0 の開き方を先に言う（所有者の決定）
  - 書き方: 管理画面は使わず、この Mac の wrangler で、5作品の `summary`・`status`・`updated_at` を1回の書き込みで書いた（`updated_at` は前の値を照合して進めた）→ `npm run site:touch`。https://astlog.dev/projects と5作品のページで、新しい文と札が出て、前の文が無いのを確かめた
  - 戻したいとき: 管理画面の編集画面で説明文を書き戻し、状態を「（なし）」にして保存する

## 0. 前提

- **下書きで保存し、公開は後にする。**（これは 2026-10-31 の下書きのときの前提。Nonet の項目はすでに公開済みで、Website のリンク先 https://nonet.astlog.dev/ は 2026-11-25 に開いているのを確かめて足した。）Website のリンク先は、Cloudflare に販売ページを出してから（`docs/hosting.md`）「公開する」にする
- 販売ページの仮の値（購入のページの `TODO: Paddle の…`・`support@TODO.invalid` など）が残ったまま AstLog に公開すると、リンクの先で TODO が見える。`scripts/check-site.sh --strict` が通ってから公開する
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
| 説明文 | 下のとおり（58 字） | 「何であるか。何をしたか。」の2文を常体で。100 字まで。公開するときは必須 |
| 状態（一覧の札） | `開発中`（札は `In development`） | 開発中・準備中・公開中・販売中・終了から選ぶ。一覧の行と作品のページの札に、年のあとに英語で出る |

説明文（2026-11-25 に書き直した。いまの本番の値）:

```text
Mac のトラックパッドを、アプリごとの9つのボタンにするアプリ。強く押し込んで少し止めると、ポインタの周りに開く。
```

ほかの作品と同じく、短い文で何であるかだけを言い、技術の名前（MultitouchSupport）はタグに、状態（開発中）は状態の欄に任せる。最初に載せたときの説明文は「トラックパッドの上の縁から指を滑らせると、ポインタの周りにアプリごとの9つのアイコンが開く常駐アプリ。非公開の MultitouchSupport で指の位置を読み、直販に向けて開発中。」（[いまの状態](#いまの状態2026-10-31-に公開) の「説明文と状態（2026-11-25）」）。

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
指の位置は MultitouchSupport の生のフレームから読み、最後に置いた指の絶対位置でマスを決めます（ポインタの位置は使いません）。9マスは、トラックパッドを強めのクリックの2段目まで押し込んで少し止めたときだけ開きます。そのクリックは、強く押し込んで止めたかが分かるまで CGEventTap で預かり、開いたら捨て（ポインタの下のボタンを押さない）、そうでなければ写しを送り直してアプリに返します。開いている間のポインタ・クリックの抑止も CGEventTap で行い、キーボード用とポインタ用のタップは開いている間（ポインタ用はクリックを預かっている間とその直後の後片付けの間も）だけ有効にして、ふだんのキーとポインタのイベントをアプリに通さないようにしています。開いている間にキーが押されたら何も実行せずに閉じ、そのキーは前面のアプリに渡します。

開くとすぐにポインタの周りに9つのアイコン（HUD）を出し、指を滑らせてポインタを向けたアイコンで離すと実行、アイコンの輪の外で離すと何もせずに閉じます。滑らせて通りかかっただけのマスを実行しないよう、マスに 0.1 秒留まってから離したときだけ実行します。右か左の外へ出して止めるとページが切り替わります。マスの境界をまたぐたびにトラックパッドを振動させる作りにし、非公開の MTActuator を優先して、使えなければ公開の NSHapticFeedbackManager に切り替えます。

非公開のフレームワークを使うので Mac App Store には出せず、直販にしました。利用者のアカウントも、ライセンスを確かめるサーバーも持たず、ライセンスキーは Ed25519 で署名した文字列をアプリの中だけで確かめます。リリースは scripts/release.sh 1本で、Developer ID の署名と公証、DMG、Sparkle 2 のアップデートの配信情報（appcast）までをつくる形にし、外部のツールを差し替えたテストで手順を確かめています。
```

成果:

```text
まだ販売していません。14日間の試用のあとに買い切りで売る予定で、価格と販売サービスは決めていません。実機での手動テスト（強く押し込んで開く・マスで離して実行・外枠やキーでやめる・ポインタとクリックの抑止・触覚・2本指スワイプなど）は、これから製品版で通します。

自動テストは、Swift Testing のテスト 1,307 件と、リリースのスクリプト・販売ページ・ドキュメントのテスト 120 件です。scripts/test.sh がこれに加えてアプリのビルドと自己診断（--self-check）までを通します。macOS 14 以降を対象にし、アプリの画面と販売ページは日本語と英語で用意しています。
```

- 背景の1段落目は、販売ページの「3つの約束」（買わなくていい・覚えなくていい）から書いた。自分の動機と違うところがあれば直す
- 取り組みの「Claude Code の複数のセッションに分けて」は、`docs/architecture.md` の §3（担当）とコミットの記録から書いた。載せたくなければ、この1文を「担当範囲ごとに分けて実装しました」にする
- 既にある作品（AppMixer・SaifuLog・AstLog）は Story を書いていない。そろえるなら4つとも空のままでもよい（空の欄は出ない）

### リンクを追加する（任意）

| ラベル | URL | いつ |
|---|---|---|
| `Website` | `https://nonet.astlog.dev/` | **2026-11-25 に入れた**（販売ページが開いてから） |
| `Download` | `https://nonet.astlog.dev/download` | **いまは入れない。** 公証済みの DMG を出したら、Website の次に足す（最新の DMG へ飛ぶ固定の URL） |
| `Buy` | `https://nonet.astlog.dev/buy.html` | **いまは入れない。** 購入のページ（`site/buy.html`）に Paddle のトークンと価格の ID を入れて公開し、Paddle の購入画面が開くのを確かめてから、Download の次に足す |
| `Repository` | — | **入れない。** 有料のアプリなので、GitHub のリポジトリ（`iam74k4/Apple-Nonet`）は非公開にした（2026-10-31） |

- ラベルは既にある作品と同じく英語（`App Store`・`Repository`）
- 並びは Website・Download・Buy（販売ページと同じく、試してから買う順）
- URL は `https://` で始める（`isSafeUrl`）。ラベルと URL の片方だけの行は保存できない
- 購入は `Buy` のリンクで販売ページの購入のページへ渡し、AstLog のページで Paddle の購入画面を直に開くことはしない。AstLog の公開ページはスクリプトを動かさない（CSP の `script-src 'none'`）ので AstLog のコードを変えることになり、Paddle に `astlog.dev` のドメインの承認を別に申請し、AstLog のプライバシーポリシーにも Paddle のことを書き足すことになる。買う人が見る購入画面は販売ページの「購入する」と同じなので、リンクで足りる

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
| ほかの画像 1 | 操作の動画（10〜15 秒）。強く押し込んで開く → HUD を見ながら指を滑らせ、マスで離して実行、次にもう一度開いて外枠で離してやめる | 16:10・H.264 の MP4・音なし・10MB 未満 | `Nonet の操作を収録した画面の動画。HUD が出て、指の位置に合わせて光るマスが移り、そのマスが実行される。続けてもう一度 HUD を出し、「離すとやめる」が出たところで何も実行せずに閉じる` |
| ほかの画像 2 | 設定のウィンドウ（プロファイル）。左にグローバルとアプリのプロファイル、中央に Xcode の 3×3、右にインスペクタ | 1440×900 の JPEG（ウィンドウを 16:10 の地に置く） | `設定のウィンドウ。左にグローバルとアプリのプロファイル、中央に Xcode の 3×3 のマス、右に選んだマスのアクションが並ぶ画面` |
| ほかの画像 3 | メニューから割り当て。メニューを検索し、項目を空いたマスへドラッグしているところ | 1440×900 の JPEG | `メニューから割り当て。起動中のアプリのメニューを検索し、項目を空いたマスへドラッグしている画面` |
| ほかの画像 4 | 初回の案内の「Mac にあるアプリから、9マスを用意しました」 | 1440×900 の JPEG | `初回の案内で、Mac に入っているアプリのうち9マスを用意してあるもの（Xcode・Safari など）を選ぶ画面` |
| ほかの画像 5（任意） | 設定の「一般」（開き方とやめ方の図・大きさ・触覚） | 1440×900 の JPEG | `全体の設定。トラックパッドの図で開き方とやめ方を示し、HUD の位置と大きさ・触覚の強さなどを選ぶ画面` |

- ほかの画像の中で、動画を先に置くか静止画を先に置くかは好みでよい（並び順の欄で変えられる）。メインの画像は動画にできない
- 動画は実際のアプリを収録する。販売ページのヒーローも、2026-11-15 から同じデモ動画（`site/images/demo.mp4`）を使う（それまでの絵のアニメーションはやめた）。デモ動画を撮り直したら、販売ページの `site/images/demo.mp4`・`demo-poster.jpg`（HUD が開いたコマ。0.1 秒目）と、使い方・機能の静止画（`site/images/hud-*.webp`。名前の札が出る前のコマを、HUD を中心に切り出したもの）も作り直す。英語のページの動画（`site/images/demo-en.mp4`・`demo-en-poster.jpg`）も、同じ台本で英語の画面を撮り直す（2026-11-15 に撮った。撮り方はブランチ `claude/promo-ink-backdrop` の「英語の動画」）
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
| トラックパッドを強く押し込んで少し止めると、アプリごとの 3×3 のボタンが開く | `README.md` の冒頭、`docs/user-guide.md`「Nonet とは」 |
| メニューバーの常駐アプリ（Dock に出ない） | `docs/architecture.md` §1（`LSUIElement`）、`project.yml` |
| 非公開の MultitouchSupport を dlopen で読み、指の位置を読む | `Packages/NonetKit/Sources/CMultitouch/CMultitouch.c`（`dlopen`）、`docs/spike-results.md` |
| 指の位置を読むだけなら許可が要らない（検証用のアプリで確かめた） | `docs/spike-results.md`「確認できたこと」 |
| 最後に置いた指の絶対位置でマスを決め、ポインタの位置は使わない | `docs/architecture.md` §5 の 4、`docs/user-guide.md`「Nonet とは」 |
| 強めのクリックの2段目まで押し込んで止めたときだけ開き、そのクリックは開いたら捨て、そうでなければアプリに返す | `docs/architecture.md` §5 の 1、`NonetPlatform/Input/ForceClickLogic.swift` |
| CGEventTap で開いている間のポインタ・クリックの抑止とキーでの中断。キーボード用とポインタ用のタップは開いている間（ポインタ用は後片付けの間も）だけ有効 | `Packages/NonetKit/Sources/NonetPlatform/Input/EventTapKeyboardMonitor.swift`（冒頭の説明と `updateKeyboardTap`・`updatePointerTap`） |
| 開いている間にキーが押されたら何も実行せずに閉じ、そのキーは前面アプリに渡す | `docs/architecture.md` §5 の 9、`docs/user-guide.md`「やめる（キャンセル）」 |
| 開くとすぐに HUD。マスに 0.1 秒留まってから離すと実行し、輪の外で離すとやめる | `docs/architecture.md` §5 の 3・4・6、`SessionEngine.swift` の `defaultLiftDwell`、`GridMapper.swift` の `GridInsets.cancelFrame` |
| 境界・ページ・実行で振動。MTActuator を優先し、使えなければ NSHapticFeedbackManager | `docs/architecture.md` §5 の 5 と §7、`NonetPlatform/Input/TrackpadHapticPlayer.swift` |
| Xcode や Zoom など 15 のアプリに9マスを用意 | `NonetCore/Model/Presets.swift` の `PresetLibrary.apps`（15件） |
| グローバルのページは Launchpad の代わりのランチャーから始まる（macOS 26 で Launchpad が無くなった） | `docs/architecture.md` §6「プロファイルとページ」、`Presets.swift` の `makeGlobalProfile` |
| Mac App Store ではなく直販。利用者のアカウントもライセンスのサーバーも無い | `README.md`、`docs/architecture.md` §1 |
| ライセンスキーは Ed25519 の署名で、アプリの中だけで確かめる | `NonetCore/Licensing/License.swift`（`Curve25519.Signing`）、`docs/release.md` の冒頭 |
| 14日間の試用のあと買い切り。¥1,480（税込）・$9.99、販売サービスは Paddle | `site/index.html`（価格）、`docs/release.md` §3 |
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
| 状態（一覧の札） | `開発中` | `販売中`（札 `On sale`）。説明文は変えない |
| 成果の1段落目 | まだ販売していない・価格と販売サービスは未定・実機の手動テストはこれから | 販売を始めた月・価格・販売サービスを書く。手動テストが済んだら、その一文を消す |
| 成果のテストの件数 | 書いた日の件数 | 下のコマンドで数え直す |
| 成果の CI の一文 | 書いていない | コードを push して GitHub Actions が緑になったら、2段落目に「プッシュのたびに GitHub Actions でも同じ一式を動かしています。」を足す |
| 工夫の触覚・ポインタの書き方 | MTActuator を優先し、使えなければ NSHapticFeedbackManager に切り替える作り | 手動テスト（ポインタの固定・触覚）で方式が決まったら、それに合わせる |
| リンク `Download` | 入れない | 公証済みの DMG を出したら `Download` / `https://nonet.astlog.dev/download` を Website の次に足す |
| リンク `Buy` | 入れない | 購入のページに Paddle のトークンと価格の ID を入れて公開し、`scripts/check-site.sh --strict` が通って購入画面が開くのを確かめたら、`Buy` / `https://nonet.astlog.dev/buy.html` を Download の次に足す |
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

載せるのには要らなかった。本番の AstLog（`main` の `cb899fd`）の管理画面だけで、この作品を載せられる。

- 開発中であることは、2026-11-25 から状態の欄で言う（Web-AstLog の PR #85 で足した `items.status`。それまでは説明文に「開発中」と書いていた）
- AstLog から買えるようにするのも、リンク（`Buy`）だけで足りる（[リンクを追加する](#リンクを追加する任意)）
- 動画のスクリーンショット・Story の小さな Markdown・作品の文書の欄は、本番にはあるが手元の `develop` には無い。手元で試すときは `main` に合わせてから
