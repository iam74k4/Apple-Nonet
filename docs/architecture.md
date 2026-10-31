# Nonet 設計

製品版 Nonet の設計と、実装の分担・決まり・仕様。機能の背景は [feature-plan.md](feature-plan.md)、実機での検証結果は [spike-results.md](spike-results.md)。

## 1. 前提

- macOS 14 以降、Apple シリコン / Intel。Xcode 27・Swift 6.4 でビルドする
- Mac App Store ではなく直販（Developer ID 署名＋公証）。非公開の `MultitouchSupport.framework` を使うため
- メニューバー常駐アプリ（`LSUIElement`）。Dock には出さない
- 設定はすべて Mac の中（`~/Library/Application Support/Nonet/`）。アカウントもサーバーも無し
- 14日間の無料試用 → 買い切りライセンス（Ed25519 署名のキーをオフラインで検証）
- アップデートは Sparkle 2

## 2. 構成

```
project.yml                 XcodeGen（Nonet.xcodeproj は生成物でコミットしない）
Config/Nonet.xcconfig       販売用の値（購入・サポート・プライバシーの URL、公開鍵、appcast）
App/                        アプリ本体。組み立てだけ（AppDelegate・Sparkle）
Packages/NonetKit/          それ以外すべて（swift build / swift test で動く）
  Sources/
    NonetCore/              純粋なロジック（Foundation と Observation、ライセンスの署名とハッシュの CryptoKit だけ。AppKit 禁止。例外: Licensing/TrialRecordKeychain.swift の Security・LocalAuthentication・IOKit。§6「ライセンス」）。Swift 6 言語モード
      Model/                設定のデータ型・編集・保存・プリセット・キー表記・スクリプト用の環境変数
      Engine/               セッションの状態遷移・NonetController
      Licensing/            ライセンスと試用（無効にしたライセンスの一覧は Resources/RevokedLicenses.txt）
      Services.swift        macOS に触れる部分の protocol（契約）
      HUDModel.swift        HUD・トースト・NonetError（契約）
    CMultitouch/            MultitouchSupport を dlopen する C ラッパー
    NonetPlatform/          Services の macOS 実装（Input/・Actions/）。NonetServices.live()
    NonetUI/                SwiftUI / AppKit の画面（Settings/・HUD/・MenuBar/・Onboarding/・Common/）
    NonetLicenseTool/       nonet-license（鍵の生成・キーの発行・検証・無効にする）
  Tests/
    NonetCoreTests/ NonetPlatformTests/ NonetUITests/
scripts/                    ビルド・リリース・アイコン生成
docs/                       設計・リリース手順・利用ガイド
site/                       販売ページ（静的）
```

依存の向き: `NonetCore` ← `NonetPlatform`、`NonetCore` ← `NonetUI`、App はすべてに依存。`NonetUI` は `NonetPlatform` に依存しない（必要なものは `NonetServices` の protocol 経由で受け取る）。

`NonetController`（Core）が本体で、`NonetServices`（protocol の束）と `HUDPresenting`・`LicenseManager`・`HUDGuidanceStoring` を受け取って動く。テストでは偽物の実装を渡す。
- `NonetServices`: トラックパッド（`TouchSource`）・キーボード（`KeyboardMonitor`）・触覚・アクションの実行・前面アプリ・メニューの読み取り・権限・インストール済みアプリ・ショートカット・AI が使えるか・ログイン項目・時計（`Scheduler`）・JIS 配列か、と `presetEnvironment`（`PresetEnvironmentProviding`: この Mac でできること `PresetCapabilities` と Dock のアプリ。既定は `FixedPresetEnvironment`（どちらもできる・Dock は空）で、`live()` は `SystemPresetEnvironment`。作ったときにシェルを調べ始める。§6「プロファイルとページ」）
- `HUDGuidanceStoring`: HUD を出したセッションの数（使い始めの案内、20回まで）と試用期間の残りの帯を最後に出した時刻。アプリは `UserDefaultsHUDGuidanceStore`（`com.iam74k4.Nonet.guidance.hudSessionCount`・`…guidance.lastTrialReminder`）、テストと Debug の `--config-dir` は `MemoryHUDGuidanceStore`

## 3. 担当

| 担当 | 持ち場（このファイル・フォルダだけを編集する） |
|---|---|
| core-model | `NonetCore/Model/` の Action.swift・Profile.swift・Settings.swift・Configuration.swift・ConfigurationStore.swift と、新しく作るファイル。テスト: `NonetCoreTests/Model*`・`Configuration*`・`Store*` |
| keys-license | `NonetCore/Model/Keys.swift`・`ScriptEnvironment.swift`・`NonetCore/Licensing/`・`NonetLicenseTool/`。テスト: `NonetCoreTests/Key*`・`License*`・`ScriptEnvironment*` |
| presets | `NonetCore/Model/Presets.swift` と `PresetData*.swift`。テスト: `NonetCoreTests/Preset*` |
| engine | `NonetCore/Engine/`。テスト: `NonetCoreTests/Engine*`・`Session*`・`Controller*`・`Fakes*` |
| platform-input | `CMultitouch/`・`NonetPlatform/Input/`。テスト: `NonetPlatformTests/Input*` |
| platform-actions | `NonetPlatform/Actions/`。テスト: `NonetPlatformTests/Action*` |
| ui-settings | `NonetUI/Settings/`。テスト: `NonetUITests/Settings*` |
| ui-shell | `NonetUI/HUD/`・`MenuBar/`・`Onboarding/`・`App/`・`App/Assets.xcassets`・`scripts/make-icon.swift`。テスト: `NonetUITests/Shell*` |
| release | `scripts/`（make-icon 以外）・`docs/release.md`・`docs/user-guide.md`・`docs/user-guide.en.md`・`docs/privacy.md`・`site/`・`.github/` |

- **契約**: 各ファイル冒頭に「契約」とあるものと、担当ファイルの公開 API（型名・プロパティ・メソッドのシグネチャ）は変えない。追加はしてよいが、報告する
- `Package.swift`・`project.yml`・`Services.swift`・`HUDModel.swift`・`LiveServices.swift`・`Common/`・`Localizable.xcstrings`・`Placeholder.swift` は統合担当だけが変える。変えてほしいときは報告する
- ほかの担当の未実装部分（`fatalError("未実装: …")`）を呼ぶコードを書いてよい。統合後に動く。ただし自分のテストはそれに頼らない

## 4. 共通の決まり

- コメントと画面の文言は日本語。英語は後でローカライズする
- 画面に出る文字列は必ずローカライズ可能にする: `String(localized: "…", bundle: .module)`、SwiftUI は `Text("…", bundle: .module)`。`Localizable.xcstrings` は編集しない（統合時に抽出する）。`scripts/test.sh`（CI も）は `scripts/sync-strings.sh --check` を動かすので、カタログに無い文言や英語の訳が無い文言があるとテストが失敗する
- ログは `os.Logger(subsystem: "com.iam74k4.Nonet", category: "<担当>")`。キー入力の中身やテキストはログに残さない
- UI とサービスはメインアクター。重い処理（スクリプト・AI・`shortcuts`）は `async` でメインスレッドを止めない
- 失敗は `NonetError` で返す（`errorDescription` がそのままトーストに出る）
- 本番コードで強制アンラップ・`try!`・`fatalError` を使わない（契約のスタブを置き換えた後）
- テストは Swift Testing（`import Testing`・`@Test`・`#expect`）。`Packages/NonetKit` で `swift build` と `swift test` が通ること
- 文体はまわりのコードに合わせる。コメントは「なぜ」が必要なところだけ

## 5. 操作の仕様（セッション）

トリガーキーを押してから離すまでを「セッション」と呼ぶ。設定でトラックパッドの角に指を置いて少し待つことでも始められる（下の「角の呼び出し」）。`SessionEngine`（純粋なロジック）がこの仕様を持ち、`NonetController` が入出力をつなぐ。

1. **開始**: トリガーキーが単独で押された（ほかの修飾キーが押されていない）ら開始する。Nonet が無効・トラックパッドが無い・設定ウィンドウでキー記録中なら開始しない。前面アプリのプロファイルが「このアプリでは Nonet を使わない」（`Profile.mode == .off`。`NonetConfiguration.isTurnedOff(forBundleID:)`）でも開始しない（ポインタも止めず HUD も出さない。そのアプリが前面の間は `KeyboardMonitor.passTriggerToApps` を true にするので、`passTriggerToApps` の設定がオフでもトリガーキーはアプリに届く）。Nonet のウィンドウがキーのときも開始する（実行できるマスは限る。下の「実装で決めた細部（NonetController）」）。開始と同時にポインタの抑止を始め、前面アプリのページの並び（`resolvedPages`）を決め、最初のページを使う
2. **指**: 触れている指のうち最後に置いた指を使う。マスは 3×3 の等分で、境界には余裕（ヒステリシス 0.03）を持たせる
3. **速押し（すぐにタップ）**: HUD が出る前に1本指を置き、その指が `hudDelay`（既定 0.3秒。設定「指を止めてから HUD が出るまでの時間」、0.15〜0.8）止まる前に離れたら、置いた位置のマスを即実行する。HUD は出さない。実行したマスを `showExecutionToast` ならトーストで知らせる
4. **HUD**: 次のどちらかで HUD を出す。(a) トリガーを押してから `placementWindow`（0.6秒。`SessionConfiguration.defaultPlacementWindow`。設定には出さず、`hudDelay` より短くはしない）の間に指が置かれなかった（キーボードからトラックパッドへ手を動かす間に出さないよう、(b) より長い）、(b) 置いた指が `hudDelay` 以上触れたままになった。HUD は指の下のマスをハイライトする
5. **HUD からの実行**: `onTriggerRelease` なら、指を置いたままトリガーを離すとハイライト中のマスを実行。指を離してからトリガーを離すとキャンセル。ただし HUD が出ているときも、`tapMaxDuration`（0.25秒）より短く、置いた位置から `tapMaxTravel`（0.04。トラックパッドを 1 とした距離）より動かずに1本指で離したタップは、置いたマスをその場で実行して HUD を閉じる（`execute` の触覚。速押しではないので `wasFastTap` は false。セッションは続く。トリガーより前から置いていた指は数えない。角の呼び出しのセッションは離せば実行するので関係ない）。それより長く置いた指は、これまでどおり滑らせて選びトリガーを離して実行する。`onFingerLift` なら、1本指を離したときにハイライト中のマスを実行し、HUD は閉じる
6. **続けて実行**: トリガーを押したまま、何度でも速押しできる（HUD でのタップの後も同じ）。一度実行した後は (a) では HUD を出さず、(b) のときだけ出す
7. **触覚**: ハイライトするマスが変わるたびに `boundary`、ページが変わったら `pageChange`、実行したら `execute`、受け付けたが何もしなかったら `rejected`（下の 12・9・8・13 と、Nonet のウィンドウが前面で実行しなかったとき）。強さは設定の `haptics`。種類は強さと打つ回数で見分けられる（`HapticTuning`。actuationID は 弱 / 中 / 強）: `boundary` 3 / 4 / 5 を1打、`execute` 4 / 6 / 6 を1打、`pageChange` 4 / 4 / 5 を 50ms 空けて2打（弱は `rejected` と同じにならないよう 3 ではなく 4）、`rejected` はどの強さでも 3 を 40ms 空けて2打。`activation`（角の呼び出し）は `execute` と同じ
8. **ページ**: 2本指で横にスワイプ（2本の平均の移動が 0.12 以上）すると前後のページへ。端では止まり、`rejected` の触覚で知らせる（1ページしか無いときも）。1回のスワイプ（指が離れるまで）で1ページ。HUD が出ていなければ出す
9. **2本以上の指**: 2本以上触れたタッチは実行しない。ページを変えずに（変えようとせずに）離したら `rejected` の触覚。ただし、トリガーを押す前から置いていて動かしていない指（`restingTolerance` 0.02 より動いていない。手前に置いた親指など）は数えない。その指1本だけが触れていても、ハイライトも (b) の HUD も実行もしない（HUD は指を置いていないときと同じく (a) で出す）。ほかに置いた指は新しいタッチ（速押しの候補で、そのマスを実行できる）になり、2本指のスワイプも数えない指を除いて測る。トリガーキーのセッションでは手のひらは見分けない（角の呼び出しは接触の大きさで見分ける。下の「角の呼び出し」）
10. **中断**: セッション中にほかのキーや修飾キーが押されたら、何も実行せずに終える（そのキーは前面アプリに渡る）。トラックパッドに触れていない間に届いたマウスの押す・移動・ホイールのスクロールも同じ（下の「マウスとホイール」）。20秒を超えたセッションも終える
11. **何もしない**: 指を置かずにトリガーを離したら何もしない。トリガーより前から休めている指（9）だけが触れているときも同じ（その指を離しても何もしない）
12. **空きマス**: 実行しても何も起きない。すぐにタップした（速押し・HUD でのタップ）なら `rejected` の触覚で、押したことは届いたと知らせる（トリガーを離して空きマスを選んだときはキャンセルなので鳴らさない）
13. **ライセンス**: 試用期間が終わっていたら、HUD に「試用期間が終了しました。メニューバーの Nonet から購入・登録できます。」の帯（注意）を出し、実行の代わりに `NonetError.licenseRequired`（同じ文）のトーストと `rejected` の触覚を出す。残りが `HUDGuidance.trialReminderDays`（3日）以下になったら、HUD の帯（知らせ。注意の印は付けない）に「試用期間は残り N 日です」を、1日（暦の日）に1回だけ出す。出したセッションの間は出したまま
14. **練習モード**: `isPracticeMode` の間は実行せず、`lastExecution` に記録だけする（`recentExecutions` には入れない）
15. **使い始めの案内**: HUD を出したセッションが `HUDGuidance.beginnerSessionLimit`（20回）になるまで、9マスの下に1〜2行の案内を出す（`HUDModel.footnote`。「指を滑らせて選ぶ · 先に指を離してから右⌘を離すとやめる」。「指を離したとき」は「やめるときは指を置いたまま左の⇧を押す」、角の呼び出しは「滑らせずに離すとやめる」。ページが複数なら「 · 2本指のスワイプでページを切り替え」）。数えるのはセッションで最初に HUD を出したときに1回（`HUDGuidanceStoring`。アプリでは UserDefaults）。HUD の右上の案内はトリガーキーの名前まで言う（「タップか、右⌘を離して実行」。「指を離したとき」と角の呼び出しは「指を離して実行」）

ポインタの抑止（`KeyboardMonitor.isSuppressingPointer`）はセッション開始から終了まで。セッション中に押したクリックの「離す」も、終了後に捨てる。

マウスとホイール（`TrackpadContact`・`KeyboardMonitor.isTrackpadTouched`）: `NonetController` は指のフレームから、トラックパッドに触れているかをキーボードモニターに知らせる（モニターを始めたときと、変わったとき）。抑止中に、トラックパッドに触れていない間に届いたマウスの押す（どのボタンも）・移動とドラッグ・慣性でないスクロールは、マウスやホイールのものとみなし、手を加えずに前面アプリに渡して `.interrupted` を1回送る（右⌘を押したままのマウスでの⌘クリックやホイールでの拡大を飲み込まない）。指が離れてから 0.5秒（`TrackpadContact.releaseGrace`。`lateClickWindow` と同じ）の間は、そのタッチの「タップでクリック」や最後の移動が遅れて届くので見分けない。慣性のスクロール（momentum phase が 0 でない）はトラックパッドのものとして、これまでどおり捨てる。触れているかを一度も知らされていないモニターは見分けない。押し込んだクリック（感圧）や縦の2本指スクロールを前面アプリに渡すことはしない

終わる直前の 0.5秒（`SessionEngine.lateClickWindow`）のうちに指が離れたか、置いて 0.5秒たたない指がまだ触れているときは、その指の「タップでクリック」が抑止の後に届くことがある。エンジンはこれを `endPointerSuppression(dropsLateClicks: true)` で知らせ、ポインタのタップは終わった後も 0.2秒（`PointerSuppressor.clickGraceInterval`）残って、その間に届いたクリックの「押す」と、対になる「離す」を捨てる（止めていたポインタの下でクリックにならないように）。移動とスクロールは渡す。指に触れていないセッション（トリガーをほかのキーと組み合わせただけ など）の後は捨てない。0.2秒は、メインスレッドで抑止を終えた時刻から数える。
- 捨てた「押す」の「離す」が届かないとき（デバイスが外れたなど）は、押してから 2秒以上（`staleButtonAge`）たち、0.5秒ごとの見直しで2回続けて（`staleButtonSweeps`）物理的に離れて見えたら忘れる
- タップが無効にされていた間に取りこぼしたかもしれない「離す」は、最初の見直しで物理的に離れて見えたら忘れる
- macOS は Nonet が自分でポインタのタップを無効にした（`CGEvent.tapEnable(false)`。開始の直後と、片付けを終えるたび）後にも `tapDisabledByUserInput` を届ける。有効にしておくつもりが無いとき（`isPointerTapEnabled` が false）のそれは取りこぼしとみなさず、ログにも書かない（`PointerTapDisableResponse`）。時間切れ（`tapDisabledByTimeout`）と、有効にしておくはずの間の無効化は、これまでどおり取りこぼしとみなす

実装で決めた細部（SessionEngine）:
- 一度でも2本以上触れたタッチは、ハイライトも境界の触覚も出さない（9 により実行しないため）
- トリガーを離した時点で、置いて `hudDelay` 未満の指が残っていれば、その指が離れるまで（最長 `hudDelay`）セッションを続ける。離れれば速押しとして実行する（空きマスなら `rejected`、2本以上なら 9 と同じく `rejected`）
- トリガーより前から置いていた指は速押しにならない。このため `NonetController` はセッション外のタッチのフレームもすべてエンジンに渡す
- トリガーより前から置いていた指は、1本だけでも休めている指（`restingTolerance` より動いていない指）として数えない: ハイライトせず、(b) の HUD も出さず（指を置いていないときと同じく (a) の `placementWindow` で出す）、トリガーを離しても、`onFingerLift` でその指を離しても実行しない。2本指のスワイプの起点だけは、トリガーを押した時点のその指の位置にする。そこへ新しく指を置いたら、休めている指を除いた新しいタッチにする（速押しの候補。HUD が出ていれば HUD でのタップの候補）。そのタッチの指がすべて離れたら（休めている指が残っていても）タッチが離れたとみなす。休めている指は、`restingTolerance` より動かしたらふつうの指にし（速押しにはしない。ハイライトで追い、動かした時刻から `hudDelay` で (b) の HUD。HUD が出ていればその場でハイライト）、ほかの指でタップしている間のずれでは外さない（そのタッチが離れたら位置を測り直す）。一度実行した後に休めている指だけが残っても、HUD は出さない（6）
- 例外: 角の呼び出しのセッション中にトリガーキーを押したときに触れている指は、そのセッションで選んでいた指なので休めている指にしない（下の「角の呼び出し」）
- HUD でのタップ（5）の長さは指を置いた時刻から、移動は最初に置いた指の置いた位置からの最大の距離で測る。空きマスなら `rejected` を鳴らして HUD は出したまま、ハイライトを消す
- 2本指を左へ動かすと次のページ（Launchpad と同じ向き）
- `onFingerLift` で、指を置いたままトリガーを離したらキャンセル
- `execute` の触覚はエンジンではなく `NonetController` が鳴らす（空きマス・ライセンス切れ・Nonet のウィンドウでは鳴らさず、ライセンス切れと Nonet のウィンドウでは `rejected`。エンジンが中身を知らない空きマスの速押しも `rejected`）。エンジンは `boundary`・`pageChange`・`activation` と、空きマスのすぐにタップ・2本以上で離した・端のページから先へのスワイプの `rejected` を出す
- Nonet 自身が送ったキー（`SyntheticKeyEvent.userData` の印付き）は 10 の「ほかのキー」に数えない。速押しの連続実行（6）でキー入力のアクションを使えるようにするため
- 空きマス（12）: `SessionConfiguration.occupiedCells`（解決したページごとの、中身のあるマス）があれば、エンジンが空きマスを実行しない。空きマスの速押しは「実行せずに離した」とみなすので、6 の (a) の HUD は止まらない（6 で (a) を止めるのは、本当に実行した後だけ）。`onFingerLift` で光っている空きマスから指を離すと、HUD は開いたまま。`onTriggerRelease` で空きマスの上でトリガーを離すと、キャンセルとして終える。`occupiedCells` が無ければ、これまでどおり `NonetController` が空きマスを無視する
- `triggerDown` を受けたら、`NonetController` は同じ呼び出しの中で `isSuppressingPointer = true` にする（直後のポインタイベントを取りこぼさない）。`passTriggerToApps` が false のときはモニターがトリガーキーを常に飲み込むので、Nonet が無効の間はキーボードモニターを止める

実装で決めた細部（NonetController）:
- 状態は 無効 > アクセシビリティなし > トラックパッドなし > セキュア入力中 > 動作中 の順で決める。有効な間は2秒ごとに確かめ直す（パスワード欄に入るとセキュア入力はいつでも始まるため）。トリガーを押したときにも、セキュア入力に出入りしていないかを確かめ直す
- キーボードモニターは、有効・アクセシビリティあり・トラックパッドあり のときだけ動かす（トラックパッドが無いのにトリガーキーを飲み込むと、そのキーが何もしなくなる）
- 指の位置（`TouchSource`）は、有効・アクセシビリティあり のときだけ読む。「アクセシビリティなし」では止め、触れていた指は離れたことにする（空のフレームを渡す）。セキュア入力中と「トラックパッドなし」では止めない（セキュア入力は出入りが多く、終わったらすぐ使えるように。トラックパッドは見つけ直せるように）
- 状態が「動作中」でなくなったら、サービスを止める前にセッションを終える（ポインタの抑止・HUD が残らない）
- セッションの間は、トリガーを押したときの前面アプリとそのページを使い続ける。新しいセッションの文脈は `beginPointerSuppression` の時点で差し替える（取りこぼした triggerUp の後始末が、新しいセッションを消さないように）
- `license.refresh()` はトリガーを押した直後ではなく、メインループの次の回で呼ぶ（イベントタップのコールバックの中でファイルを書かない）。呼ぶのは 60秒（`NonetController.licenseRefreshInterval`）に1回までで、ライセンスがあれば呼ばない。実行してよいかは `canExecuteActions` がいつでも正しく答える
- Nonet のウィンドウがキーのとき（設定・練習の手前までの初回の案内・クリックしてキーにした結果のパネル。`FrontmostAppObserving.isOwnWindowKey`）も、セッションはふだんどおり始まる。ポインタの抑止と HUD は動き、HUD は直前のアプリのプロファイルを出す。ただし前面アプリに働きかけるマス（キー入力・スクリプト・ショートカット・メニュー項目・AI。`ControllerExecutionPolicy.dependsOnFrontmostApp`）は実行せず、「Nonet のウィンドウが前面にあるので実行しませんでした。設定では「このマスをテスト実行」で試せます。」の失敗のトーストを出し、`lastExecution` に失敗として記録する（送ったキーや読む選択範囲が Nonet のウィンドウのものになるため）。アプリを開く・URL は実行する。練習モードはこれまでどおり記録する。Nonet が前面のアプリでも、キーのウィンドウが無ければ（設定を閉じた後・Finder から開いた直後）何も止めない
- トリガーを押したら `TouchSource.revalidate()` を呼ぶ（止まったトラックパッドを開始し直す。下の「トラックパッド」）
- 実行はタップした順に始まる。キー入力・メニュー項目・アプリ・URL・ターミナルのスクリプトは1つずつ（前の実行が終わるまで次は待つ。最長5秒）。裏で動かすスクリプト・ショートカット・AI は、前面アプリの文脈を読み終えるまでの最長1秒だけ次を待たせ、その後は並行して動く。`lastExecution` は最後に終わった実行
- 設定の変更はすぐに反映し、ファイルへの保存は 0.5 秒ごとにまとめる（`ControllerConfigurationSaver`。`stop()` で書き切る。アプリは終了するとき、`stop()` の前に設定のウィンドウの打ちかけの欄と記録中のキーを確定させる（`SettingsWindowController.commitPendingEdits()`））。書けなかったとき（ディスクがいっぱい など）は、その設定を待たせたまま 2秒後に書き直し、続けて失敗するたびに間を倍にして最長 60秒（`firstRetryInterval`・`maxRetryInterval`）。書けたら間を戻す。新しい変更が来たら、書き直しを待たずにふだんどおり 0.5秒後に書く。終了するとき（`stop()`）も書き直す。`start()` で読み込む前の変更は保存しない。設定ファイルを読めなかったときは、そのプロセスの間は保存しない（`notice` で知らせる）。壊れていたときは初期設定で置き換えて保存する
- 「このマスをテスト実行」: アプリのプロファイルならそのアプリを、グローバルなら設定を開く前に使っていたアプリを前面に出してから（0.4 秒＋最長 8×0.2 秒待つ）実行する。前面に出せなかったとき、前面アプリに入力を送るアクション（キー入力・選択範囲を置き換える AI）は実行しない。練習モードでも実行するが、試用期間が終わっていたら実行しない
- 成功のトーストは、HUD を出さずに実行したとき（速押し）と、「実行中」のトーストを出した長く掛かるマスが終わったときだけ（`showExecutionToast`）。結果のパネルを出したときと失敗は別で、失敗はいつもトーストで知らせる。トーストの大きさは設定の「HUD の大きさ」（`GlobalSettings.hudScale`: 標準 / 大きい / 特大 = 1 / 1.25 / 1.5。`ToastModel.scale`・`HUDModel.scale`。画面に収まらなければ ui-shell が収まるところまで小さくする）
- 長く掛かるマス（`ControllerExecutionPolicy.isLongRunning`: 裏で動くスクリプト・ショートカット・AI）が 0.5秒（`NonetController.runningToastDelay`）で終わらなければ、終わるまで「「マス」を実行中…」のトースト（`ToastModel.Style.running`。時間では消えない）を出す。終わったら、結果のパネル（トーストは消す）・失敗のトースト・成功のトースト（`showExecutionToast` なら、HUD から実行しても）に置き換えるか、知らせることが無ければ消す（`HUDPresenting.hideToast`。ほかのトーストに置き換わっていれば消さない）。テスト実行でも同じ（成功のトーストは出さない）
- 失敗のトーストの見出しは、どこのマスか（「プロファイル › マス」。プロファイルのページが複数なら「（2ページ目）」も）。説明は失敗の理由。表示時間は 1.5秒＋見出しと説明の1文字ごとに 0.06秒を 3〜8秒に収めたもの。トリガーキーを押している間は消さず、離してから 1秒で消す（`HUDPresenting.setTriggerHeld`。`NonetController` は `SessionEngine.isTriggerHeld` が変わったときに知らせる。角の呼び出しではトリガーを押していない）
- 実行の記録は `lastExecution` のほかに、新しい順に最大10個（`recentExecutions`・`recentExecutionLimit`）残す。失敗・試用期間の終了・Nonet のウィンドウで実行しなかったもの・テスト実行も含め、練習モードの記録は含めない。`ExecutionRecord.profileID` でマスのプロファイルが分かる

角の呼び出し（トラックパッドだけで呼び出す。選んだ上の角に指を置いて少し待つ。`GlobalSettings.touchActivation`・`CornerHoldRecognizer`・`SessionActivation.cornerHold`）:
- 設定は 使わない（既定）・左上の角に指を置く・右上の角に指を置く。トリガーキーはどれでもいつもどおり使える。設定ファイルには「使わない」以外のときだけ `touchActivation` を書く（無い・知らない値なら使わない。前の版の書式のまま）
- 見分け方（`CornerHoldRecognizer`。`NonetController` がセッションの外も含めてすべてのフレームを渡す）: 選んだ上の角の範囲（横 `zoneWidth` = 0.12・奥行き `zoneHeight` = 0.18。トラックパッドを 1 とした割合で、縁ちょうどは中）で触れ始めた1本指が、ほかの指が触れず、触れた位置から `movementTolerance`（0.02。トラックパッドを 1 とした距離）より動かずに `holdDuration`（0.4秒）触れ続けたら合図する。2本目の指・それより動いた・先に離した・角の外で触れ始めて入ってきた・最初から2本以上で触れた・接触が手のひらの大きさ（`TouchPoint.majorAxis` が `palmMajorAxis` = 25 以上）になった、のどれかなら、そのタッチではもう待たない。手のひらの値は MultitouchSupport の接触の長径（`CMTTouch.majorAxis`。指先でおよそ 8〜15、平らに置いた親指でも 20 ほど）で、それより大きいものだけを外す控えめな値にしている（実機では確かめていない。値が取れない接触は外さない）。合図は1つのタッチで1回だけ。設定が「使わない」の間とセッション中に触れ始めた指は待たない（トリガーキーのセッションの指を、終わった後に角の呼び出しとみなさない）。指を止めている間にフレームが来なくても始められるよう、`NonetController` は合図の時刻にタイマーを置く。トラックパッドを止めたとき（無効にした など）は、触れていた指は離れたことにする
- 始め方: トリガーキーと同じ `NonetController.beginSession` を通る（1 と同じく、無効・アクセシビリティなし・トラックパッドなし・セキュア入力中・キー記録中なら始めない。前面アプリのページを使い、Nonet のウィンドウがキーのときの決まりも同じ）。マウスやトラックパッドのボタンが物理的に押されている（`KeyboardMonitor.isMouseButtonDown`。クリックしたままドラッグを始めるところ など）なら始めず、何も知らせない。試用期間が終わっていたら始めない（角に指を置いただけで、何も実行できない HUD を出さないため）。そのときは、始められる状態（「このアプリでは Nonet を使わない」アプリが前面でないことも含む。1 と同じ確かめ）なら、トリガーキーでマスを押したときと同じく、終わったことと次にすることを失敗のトースト1つ（「試用期間が終了しました」「メニューバーの Nonet から購入・登録できます」）と `rejected` の触覚で知らせる（合図は1つのタッチで1回なので、トーストも1回）
- エンジンには `.triggerDown` の `configuration.activation` を `.cornerHold` にして渡す。開始と同時にポインタの抑止を始め、速押しの段階も `hudDelay` も無く HUD を出して指の下のマスを光らせ、`activation` の触覚を鳴らす。HUD の案内は、実行のタイミングの設定に関係なく「指を離して実行」
- ハイライトは 2 と同じく最後に置いた指を追う（境界の触覚も 7 と同じ）。すべての指が離れたら終える: 測り始めてから指が `movementTolerance` より動いていて、光っているマスに `liftDwell`（0.15秒。そのマスになった時刻と、動いたとみなした時刻の遅いほうから数える）以上留まってから離したなら、光っているマスを実行して released。動いていない・留まらずに離した（置いて止めていた指が、そのままポインタの移動やドラッグで動いて離れた など）なら何もせずに cancelled。2本以上で離した・空きマス（12）も何もせずに cancelled（2本以上で、ページを変えずに離したときは `rejected` の触覚）。測り始めるのは、セッションの始まりと、2本以上から1本指に戻ったとき。HUD でのタップ（5）とトリガーより前から休めている指（9）の決まりは使わない
- 2本指の横のスワイプで 8 のとおりページを変える。2本以上から1本指に戻ったら、残った指でまた選べ（ハイライトが戻る）、次の2本指のスワイプでもう1ページ変えられる。「動いた」も測り直すので、スワイプの直後に離すとキャンセル（選ぶにはもう一度滑らせる）
- ほかのキーや修飾キーを押したら（修飾キーを離しただけでは終えない）10 と同じく何も実行せずに終える。トリガーを押していないので、セッションの間は `KeyboardMonitor.interruptsWithoutTrigger` を true にし、モニターにトリガー無しでも `.interrupted` を1回送ってもらう（そのキーは前面アプリに渡す。Nonet 自身が送ったキーは数えない）。トリガーを押したまま ⌘C などで一度中断した後に、押したまま角の呼び出しで始めたセッションも、次のキーや修飾キーで終える（`TriggerDetector` が押している間の中断とは別に、このセッションのための `.interrupted` をもう1回送る）。トリガーキーを押したら、このセッションを終えてトリガーキーのセッションを始める（置いたままの指はこのセッションで選んでいた指なので、休めている指（9）にせず、4 (b) で HUD）。トリガーを離したイベントは使わない。`maxDuration`（20秒）を超えたら終える
- 角の呼び出しはタップではないが、終えるときの遅れて届くクリックの扱い（`lateClickWindow`・`clickGraceInterval`）はトリガーキーと同じ（指を離して終えるので、ふつうは捨てる）

実装で決めた細部（トラックパッド。`MultitouchTouchSource`）:
- 次のときにデバイスを開始し直す: IOKit の抜き差しの通知（`AppleMultitouchDevice` の match・terminate）、スリープからの復帰、ユーザーのセッションが前面に戻ったとき（ファストユーザスイッチ）、画面のスリープからの復帰、ディスプレイの構成の変化。指が触れている間は、離れるまで待つ
- 使えるはずのデバイスの一部を開始できなければ、1・3・10・30秒後、その後は60秒ごとに開始し直す（`MultitouchRecovery.retryDelays`）
- 抜き差しの通知を取りこぼしても気づくよう、デバイスの一覧を10秒ごとに見直し（`MultitouchRecovery.listCheckInterval`）、開始しようとしたものと違えば開始し直す
- トリガーを押したとき（`TouchSource.revalidate()`）、開始し直してから10秒（`silentRestartInterval`）たってもフレームが1つも届いていなければ開始し直す（止まったのか、触れていないだけかは分からないので、この間隔に1回まで）

## 6. 機能の仕様

### プロファイルとページ
- グローバルが必ず1つ（先頭）。アプリのプロファイルは bundleID ごとに1つまで。各プロファイル 1〜3 ページ
- アプリのプロファイルの使い方は `Profile.mode`: `profile`（このプロファイル）・`global`（グローバルを使う。ボタンは残す）・`off`（このアプリでは Nonet を使わない。§5 の 1）。`isEnabled` は `mode == .profile` の計算プロパティ（false を入れると `global`）。`setAppMode(_:for:preset:)` はプロファイルが無ければ（preset があればその中身で）作ってから変える
- `resolvedPages(frontmostBundleID:)`: `autoSwitchProfiles` が true で、そのアプリのプロファイルが `profile` なら、そのページ。`appendGlobalPages` なら後ろにグローバルのページをつなげる。プロファイルが無い・`global` ならグローバルのページだけ。`ResolvedPage.title` は HUD の題名で、ページに名前（`Page.name`）があれば「Xcode · デバッグ」、無ければプロファイルの名前
- グローバルの初期値はランチャー（`PresetLibrary.makeGlobalProfile(installedBundleIDs:dockApps:)`）: Dock の persistent-apps（`com.apple.dock` の CFPreferences を読むだけ。インストールされていないものと Nonet は飛ばす）を Dock の順に先に、残りを `PresetLibrary.launcherCandidates` のうちインストール済みのアプリを候補の順に、最大3ページ（27個）（起動アクション、アイコンはアプリ）。Dock にもある候補は候補の短い名前（「VS Code」など）を使い、ChatGPT は1つだけ。Dock を読めなければ候補だけ。macOS 26 で Launchpad が無くなったので、その代わりになる。Arc は 2026-12-22 に動かなくなるため、候補には Dia を入れている（Arc のアプリ用プリセットは残す）
- プリセットはこの Mac でできること（`PresetCapabilities`: Apple Intelligence・`claude` コマンド）に合わせて組み立てる（`PresetLibrary.apps(for:)`・`preset(forBundleID:capabilities:)`。引数の無い呼び出しは「どちらも使える」）。AI が使えなければ AI のマスを入れず、外側のマスを1つ中央に移す（Safari・Chrome・Arc はページ内検索 ⌘F、Mail はアーカイブ、Teams はミュート、Slack は会話へ移動 ⌘K、Notion は検索、メモはチェックリスト。移した元のマスは空ける）。Claude Code のマスはどの場合も中央に置かない（Xcode はクイックオープン ⇧⌘O、VS Code・Cursor はコマンド ⇧⌘P、ターミナルは新規タブ ⌘T を中央に置き、Claude Code はその外側。`claude` が無ければ空ける）。Apple Intelligence のモデルをダウンロード中なら使えるものとして扱う。分類の説明（「〜など%lld個」）は入っているマスだけを数える
- 初回の設定（`NonetConfiguration.initial(…, dockApps:)`）と、初回の案内の「アプリを選ぶ」・「プロファイルを追加」は、`NonetServices.presetEnvironment` の `capabilities` と `dockApps()` を使う。`claude` はシェルを調べ終えるまで見つからない扱いなので、初回の案内は「アプリを選ぶ」で調べ終えるのを待ってからプリセットを作り直す

### 設定ファイル（`ConfigurationStore`）
- `~/Library/Application Support/Nonet/configuration.json`（`NonetConfiguration`: `version`・`settings`・`profiles`）。書き込みはアトミックで、中身が変わるときだけ書き、直前の版を `configuration.backup.json` に残す。読めない今のファイルは上書きしない
- 書式は前の版の Nonet でも読めるようにする。無い項目・知らない値は既定値で読み（`decodeLossy`）、新しい項目は既定値と違うときだけ書く:
  - `settings.touchActivation`（`off` | `topLeft` | `topRight`）は `off` 以外のときだけ、`settings.hudScale`（`standard` | `large` | `extraLarge`）は `standard` 以外のときだけ書く
  - `Profile.mode`（`profile` | `global` | `off`）: `isEnabled` はいつも書き（`profile` のときだけ true）、`"mode": "off"` は `off` のときだけ足す（前の版は使わないアプリを「グローバルを使う」として読む）。知らない `mode` は `isEnabled` で読む
  - `Page.name` は付けたときだけ書く（改行は空白にし、空なら無し）
  - `ScriptAction.output`・`ShortcutAction.output`（`replaceSelection` | `copyToClipboard` | `showResult`）は使うときだけ。無い・空・知らない値は「出力を使わない」
- 控え（`ConfigurationBackup`）: `Backups/configuration-<UTC の yyyyMMdd'T'HHmmss'Z'>-<理由>.json`（中身は configuration.json と同じ書式）を新しいものから10個（`maxBackups`）残す。理由は `auto`（`save()` で、いちばん新しい控えから1時間（`automaticBackupInterval`）たっていれば、変える前の設定）・`delete-profile`・`delete-page`（マスのあるページだけ）・`import`・`reset-profile`・`restore`（以前の設定に戻す前）。設定の「以前の設定に戻す…」が並べて読む。同じ秒の控えは、理由が違っても続けて番号を付け（`-2`・`-3`…。番号の無いものは 1。`parseBackupName`）、日時 → 番号 → 名前の順で新しいものから並べる（同じ中身の控えを作らない確かめと、10個への間引きが、本当にいちばん新しいものと比べるように）

### アクション
| 種類 | 動き |
|---|---|
| キー入力 | 前面アプリに送る。`.character` は現在のキー配列で仮想キーコードを探す（JIS でも ⌘[ などが正しく届く）。修飾キーはイベントのフラグに明示し、押しっぱなしのトリガーキーが混ざらないようにする。連続キーは 40ms 間隔 |
| アプリ起動 | 起動中なら前面へ、無ければ起動。`hideIfFrontmost` なら前面のとき隠す |
| URL | 既定のアプリで開く。スキームが無ければ https を付ける |
| スクリプト | `/bin/zsh -l -c`。`ScriptEnvironment` の環境変数を渡し、作業フォルダはプロジェクトのフォルダ（無ければホーム）。background は制限時間で打ち切り、失敗したら標準エラーの末尾をトーストに出す。終了コード 127 なら、見出しの次に「コマンドが見つかりません。インストールされているか、ターミナルで command -v <名前> を確かめてください。」（名前は zsh・bash/sh・env の形の標準エラーから読む）を置き、その後に標準エラーを2行（失敗のトーストは4行までしか出ないため）。PATH: 起動ごとに1回、メインスレッドの外で `/bin/zsh -l -i -c`（`UserShellProbe`。3秒まで）を動かし、印で挟んで書かせた PATH と `command -v claude` の結果を読む（~/.zshrc が何かを表示しても読み違えない）。background のスクリプトには、調べた PATH を環境変数で渡し、さらにスクリプトの1行目の先頭で入れ直す（macOS のログインシェルの設定 path_helper が並びを変え、nvm・~/.local/bin などを後ろに回すため。行番号は変わらない）。調べられなければ今までどおり。`output`（`ScriptAction.output`、省略可。無い・空・知らない値は「出力を使わない」で、前の版と同じ書式のまま）があれば、標準出力から最後の改行を1つ除いたものを AI と同じ出力先（置き換え・コピー・結果のパネル）に渡す。空なら何もしない。64 KB（`ScriptRunner.outputLimit`）を超えたら切らずにエラーにする（一部だけを貼らない）。terminal はターミナルの新しいウィンドウで実行（一時的な .command ファイルを `NSWorkspace` でターミナルに開かせる。Apple Events は使わない）。.command ファイルは利用者ごとの一時フォルダ（`confstr(_CS_DARWIN_USER_TEMP_DIR)` の `Nonet/Terminal/`、本人だけが入れる）に本人だけが読み書き・実行できるファイルとして書き、実行が始まると自分を消し、`${ZDOTDIR:-$HOME}/.zshrc` を読み込んでから変数を export して作業フォルダへ移る。開かれずに残ったものは5分後と、次の起動時に消す。terminal は `output` を使わない |
| ショートカット | `/usr/bin/shortcuts run <名前>`。`passSelectedText` なら選択中のテキストを入力に渡す。`output`（`ShortcutAction.output`。扱いはスクリプトと同じ）があれば `--output-type public.utf8-plain-text` を付け、標準出力をテキストとして読む（`--output-path -` は文書に無いので使わない） |
| メニュー項目 | 対象アプリが前面で、`keyEquivalent` が、アプリのメニューから読んだその項目のショートカット（`MenuItemPresser.shortcut(path:pid:)`・`MenuShortcutLookup`。メインスレッドの外で読む。項目が無い・使えない・ショートカットが無ければ nil）と同じときだけキーを送る（`MenuActionPlan.decide`。読み込んだファイルのマスが、項目とは別のキーを送れないように）。違う・読めない・キーを送れないときは、アクセシビリティ API でメニューをパスどおりにたどって押す。状態で名前が変わる項目（「再生」⇄「一時停止」、「ツールバーを表示」⇄「ツールバーを非表示」、Enter/Exit Full Screen など）は対になる名前でも探し、最後の項目はそれでも無ければ、同じメニューで同じショートカットを持つ項目が1つだけのときそれを押す（1回押した後も動き続けるように） |
| AI | macOS 26 以降で Apple Intelligence が使えるときだけ。選択中のテキストと指示文を端末内の言語モデル（FoundationModels）に渡し、出力先に従う。使えなければ `NonetError.unavailable`。「画面に表示」（`showResult`）は `ActionPerforming.performReturningOutput` が文字列を返し、`NonetController` が `HUDPresenting.showResult` で結果のパネルに出す（コピーと閉じるがある）。「選択範囲を置き換える」は、アクセシビリティが「選択なし」と答えて ⌘C で取ったとき（貼ると置き換えでなくカーソルの位置への挿入になる）と、クリップボードの中身を保てないとき（下）は、貼り付けずに結果のパネルに出す |

選択中のテキストはアクセシビリティ API（`kAXSelectedTextAttribute`）で取り、取れなければ ⌘C でクリップボード経由（クリップボードは元に戻す）。何も選択していないと ⌘C で行を丸ごとコピーするエディタ（VS Code 系・Cursor・Windsurf・Obsidian・JetBrains の IDE・Android Studio・Sublime Text）で、改行（LF か CRLF）で終わる1行だけが取れたときは、選択なしとみなす。書類の場所は前面ウィンドウの `kAXDocumentAttribute`、ブラウザの URL は Safari / Chrome / Arc / Edge / Brave に AppleScript で聞く。

スクリプトには、変数ごとに要るものだけを読んで渡す。`NONET_SELECTED_TEXT`（⌘C を送ることがある）と `NONET_BROWSER_URL`（初回はオートメーションの確認が出る）は、スクリプトのソースにその名前が書かれているときだけ読む（コメントでもよい。別のファイルのスクリプトを呼ぶだけなら、名前をコメントに書いてもらう）。ほかのスクリプトは ⌘C を送らず、ブラウザにも聞かない。`NONET_APP_BUNDLE_ID`・`NONET_APP_NAME`・`NONET_DOCUMENT_PATH`・`NONET_PROJECT_DIR`・`PROJECT_DIR` は副作用が無いので、値があればいつも渡す。

プロジェクトのフォルダ（`ScriptLocation`）: `.xcodeproj` などの書類はその親、ほかは上へたどって `.git` か `Package.swift` のあるフォルダ。ホームの中ではホームで止まり、深さの制限は無い（Maven・Gradle・Android や深いモノレポ）。ホームの外（`/Volumes/SSD` など）では、書類のフォルダを含めて上へ32個（`maxSearchLevels`）までで、`/` や `/Volumes` のような浅いフォルダは調べない。ネットワークの場所の書類では探さず、書類のフォルダをそのまま使う。調べるのはメインスレッドの外で、0.3秒（`ScriptLocation.timeout`）で終わらなければ（眠った NAS など）プロジェクトのフォルダは無しで、作業フォルダはホーム。

クリップボード（`NonetPlatform/Actions/Pasteboard.swift`）:
- 中身はメインスレッドの外で、Carbon の Pasteboard Manager を使って1本の直列のキューで1つずつ読む（`PasteboardReader`・`CarbonPasteboard`）。`NSPasteboard(name:)` はいつも同じ共有のオブジェクトを返してスレッドセーフではないので、`NSPasteboard` はメインスレッドでだけ使う。前の読み取りが時間切れの後も続いていれば、新しく読み始めない
- Nonet がクリップボードを一時的に使う操作（⌘C で読む・⌘V で貼る）は1つずつ行う（`ClipboardSession`）。まだ戻していない貼り付けの写しは、次の操作が写す前に戻す
- 写せないとき（64 MB より大きい・ファイルの約束・読む許可が無い・元のアプリが時間内に渡さない）はクリップボードに触らない。⌘C は送らず、「選択範囲を置き換える」は結果のパネルに出す。制限時間は1秒、読む前に macOS が確かめることがある（macOS 15.4 以降。`PasteboardAccess.asks`）ときは利用者が答えるまで最長20秒。「常に拒否」なら読みも戻しもしない
- 画像は項目ごとに1つの形だけを写し、Finder のファイルの項目ではアイコンを写さない（どちらも求められてから作るので遅く大きい）
- パスワード管理アプリの印（`org.nspasteboard.ConcealedType`）があれば、読みも戻しもしない。貼り付ける結果には、履歴のアプリに残さない印（`org.nspasteboard.TransientType`）を付ける
- ⌘C の後に何も書かれなければ、遅れて書くアプリのために0.5秒だけ見張り、最初に書かれたものを、⌘C を送ったアプリがまだ前面のときだけ元に戻す。ほかの操作や書き込みが始まったらやめる（利用者が自分でしたコピーは戻さない）

### 権限
- アクセシビリティ: イベントタップ（トリガーの検出・ポインタの抑止）、キー送出、メニュー操作、選択テキストの取得に必要
- 指の位置の取得には権限が要らない（検証済み）
- オートメーション: スクリプトが `NONET_BROWSER_URL` を使い、対応ブラウザが前面にあるときだけ、macOS が初回に確認する。ターミナルでの実行と書類の場所には使わない（Info.plist の `NSAppleEventsUsageDescription` も、ブラウザに表示中のページの URL を聞くことだけを書く）
- クリップボード: macOS 15.4 以降でクリップボードを読む前に確かめる設定なら、Nonet が読むとき（⌘C で選択を読む・貼り付ける前に元の中身を写す）に macOS が確かめる。拒否されていれば読まない（上の「クリップボード」）
- 許可されていなければ `status = .needsAccessibility`。2秒ごとに確かめ、許可されたら自動で動き出す

### 設定画面（ui-settings）
- サイドバー: グローバル（「既定」）・アプリのプロファイル（アイコン付き、並べ替え・削除。`mode` が `global` なら「グローバル」、`off` なら「オフ」の印。前面のアプリでいま使われているプロファイル（`SettingsModel.inUseProfileID`）には「使用中」の印。どちらも VoiceOver の値にも入れる）・「プロファイルを追加」（インストール済みアプリから選ぶ。プリセットがあれば `presetEnvironment` に合わせた中身を入れる）。右クリック: 「前面にあるとき」（`mode` の3択）・「複製して別のアプリに使う…」（「プロファイルを追加」のシートを使い、もうプロファイルのあるアプリは出さない。元のアプリのメニューを押すマスは新しいアプリのメニューを押すようにする）・「プリセットに戻す…」（プリセットがあるときだけ。確かめてから。中身はこの Mac でできることに合わせる: 確かめている間に `presetEnvironment.resolvedCapabilities()` で調べ、調べ終えていなければ `presetEnvironment.capabilities`。戻した後は次に調べ直す）・「このプロファイルを書き出す…」・「削除…」
- 絞り込み（`SettingsProfileSearch`）: アプリのプロファイルが8個（`SettingsModel.filterThreshold`）以上か、⌘F で欄を出す。Esc か ×（「絞り込みをやめる」）で閉じる。プロファイルの名前と、すべてのプロファイルのマスの名前・説明に合うものを出し、⌘B のような修飾キー付きの文字は送るキーにも合わせる。結果は「Xcode › ビルド ⌘B」のように並べ、選ぶとそのマスを開く
- 見出し: プロファイルの名前と「前面にあるとき」のポップアップ（このプロファイル / グローバルを使う / このアプリでは Nonet を使わない。狭いときは見出しを省き、名前を優先する）
- 中央: ページの切り替え（最大3。⌘1〜⌘3）と 3×3 のグリッド。ページのボタンをダブルクリックするか右クリックの「名前を変更…」で `Page.name` を付ける（空なら「ページ N」に戻る）。クリックで選択、ドラッグで入れ替え、Delete で空に。グリッドにいるとき: Return で表示名の欄へ、⌘D 複製、⌘⌫ 空にする、⌥⌘＋矢印キーで隣と入れ替え（空きマスとなら移動）、⌘C・⌘V でコピーと貼り付け（`com.iam74k4.nonet.cell` の独自の型だけを書き、文字としては書かない）。右クリック: 複製・コピー・ペースト・隣と入れ替え・ほかのプロファイルにコピー（そのプロファイルの最初の空きマスへ。無ければ知らせる）・削除・テスト実行（空きマスではアクションを追加・ペースト・隣と入れ替え）。右クリックの項目にはキーの印を付けない（文字の欄を打っている間のキーを取らないため）。キーはメインメニューと重ならない
- 元に戻す: 設定ウィンドウの `UndoManager`（`SettingsModel.undoManager`）に積み、⌘Z（メインメニューの「取り消す」）で戻せる。積むのは、マスの編集（空にする・Delete・複製・作る・ドラッグでの入れ替えと移動・メニュー項目の割り当て・貼り付け・ほかのプロファイルへのコピー。中身のあるマスを置き換えるときも）、ページの追加（戻すと足したページを消す。その後にマスを置いていれば消さずに知らせる。やり直すと同じ場所に足す）、インスペクタでの変更（選んだマスごとに1つ。別のマスを選ぶ・ほかの種類の編集・元に戻すで区切る。文字の欄にいる間の変更は、編集を終えたときに1つにまとめる。スクリプトと指示文の欄の打ち込みは、その欄だけの `UndoManager` に積み、欄を離れたら捨てる）、ページの名前の変更、プリセットに戻す、複製して別のアプリに使う、プロファイルとページの削除。操作の名前は「マスを空にする」「マスの移動」「マスの入れ替え」「メニュー項目の割り当て」「マスの変更」「マスの貼り付け」「ページを追加」「プロファイルの削除」「ページの削除」「プロファイルの複製」「プリセットに戻す」「ページの名前の変更」など。マスを空にしたとき・中身のあるマスをメニュー項目や貼り付けで置き換えたとき・ほかのプロファイルにコピーしたとき・プロファイルやページを削除したときは、グリッドの下に知らせ（「マスを空にしました」など）と「元に戻す」も出す。その後に変わったマスは、消したり上書きしたりせず「マスがその後に変わったため、元に戻せませんでした」と知らせる。消したプロファイルと同じアプリのプロファイルをその後に作っていた・ページがもう3枚あるときも、戻さずに知らせる（消したページを3枚で戻せなかったときは、マスの場所がずれるので、取り消しが終わってからそのプロファイルのマスの undo の履歴を捨てる）。プロファイルを置き換える読み込みは、そのプロファイルの undo の履歴だけを捨て、以前の設定に戻したときはすべて捨てる
- 以前の設定に戻す（`SettingsBackupsView`）: 「書き出しと読み込み」の「以前の設定に戻す…」で控え（上の「設定ファイル」の Backups）を新しい順に並べ、「戻す…」→「この設定に戻す」で `NonetController.replaceConfiguration` する。戻す前の設定も控え（`restore`）に残す
- 右: インスペクタ。表示名・アイコン（SF Symbols の候補・アプリ・文字）・アクションの種類と中身。キー入力は記録欄（押したキーをそのまま記録）と、macOS が先に使うキー（⇧⌘4・⌘Space など、記録できない）を書く「表記で入力」の欄。アプリは一覧から選ぶ。ショートカットは名前の一覧から選ぶ
- メニューから割り当て: 起動中アプリのメニューを読み（`MenuReading.menuItems(for:)` は async で、読むのはメインスレッドの外）、検索して、空きマスへドラッグ（またはダブルクリック）
- 「このマスをテスト実行」
- 全体の設定: 有効化・トリガーキー（JIS で右⌥を選ぶと警告）・トラックパッドだけで呼び出す（角の呼び出し。§5）・実行のタイミング・指を止めてから HUD が出るまでの時間（`hudDelay`）・HUD の位置・HUD の大きさ（`hudScale`）・前面のアプリで切り替える・グローバルのページをつなげる・触覚・実行したことを表示・トリガーキーを前面アプリに渡す・ポインタの固定方法（「詳細」の見出しの下）・ログイン時に起動・プロファイルの書き出し / 読み込み（`ConfigurationStore.importDocument(from:)` → `NonetConfiguration.importProfiles(_:)`。結果の件数 `ImportResult` を知らせる）・以前の設定に戻す…
- 読み込みの確認（`SettingsImportPlan`・シートは `SettingsImportReviewSheet`）: 今の設定が置き換わるとき、または読み込むプロファイルに、スクリプト・キー入力（短くても）・メニュー項目・AI・Mac の中のファイルを開く URL のマスがあるときは、何も置き換わらなくても読み込む前に確かめる。そのマスは数に上限なく、「プロファイル › マス」と中身のすべて（スクリプトはすべての行、キー入力は押すキーのすべて、メニュー項目はパスとショートカット、AI は指示と結果の出し方、URL は開くファイル）で、スクロールできる読むだけの欄に、等幅・折り返しで切らずに並べる。ファイルから来た文の見えない文字（制御文字・文字の向きを変える書式文字など）は「⟨U+202E⟩」のように見える形にする（`visibleLine`）。Return と同じ働きのキーを押すマス（今のキー配列で打つ文字（`SettingsKeyCharacters`・UCKeyTranslate）が CR・LF・ETX になるもの、キーコード 36・52・76、⌃ の付いたキーすべて。`pressesSubmitKey`）と、注意が要る命令（curl・wget・base64・eval・`| sh` などのシェルへのパイプ・osascript・rm -rf。`suspiciousTerms`）を含む行は橙色で目立たせる。中身を見せるマスがあれば、欄を最後までスクロールするまで「読み込む」「置き換えて読み込む」「新しいプロファイルだけ追加」を押せない（`SettingsModel.canConfirmImport`。確認を出すたびに戻す）。メニュー項目のショートカットは1打だけ残し、それより長いものは読み込むときに捨てる（その項目はメニューを押して選ぶ。1打でも、実行するときにアプリのメニューの項目のショートカットと違えば送らない。§6「アクション」）
- 文言は docs/user-guide.md の項目名と合わせる
- 色: ハイコントラストの見た目か「コントラストを上げる」（`accessibilityDisplayShouldIncreaseContrast`）では、マスの縁を濃く太くする
- ライセンス（`SettingsLicenseView`）: 「状態」（試用の残り日数と終わる日 `LicenseManager.trialEndDate` / 登録者・発行日・ライセンス ID / 終了）→ 登録していなければ「買い切りのライセンス」の行（「購入する」。`NONET_PURCHASE_URL` が空なら出さない）→「購入済みの方」のキーの欄（登録済みなら「ライセンスキー」の行に「キーをコピー」（`registeredLicenseKey` を `org.nspasteboard.ConcealedType` の印付きで書く）と「別のキーを登録…」、その下に「この Mac から登録を消す」）。キーを貼るまでは「購入する」を、貼ったら「登録」を既定のボタンにする（青いボタンを2つ並べない）。登録できなかったときの文はどれも次にすることで終え（`SettingsText.licenseError`。ライセンス ID や UUID を貼ったとき・公開鍵の無いビルドにはそれぞれの文）、横に「お問い合わせ…」。「ライセンスキーが見つからないときは」はサイトの `#faq-license-key`（英語なら `en/`）を開く
- 購入のメールのリンク `nonet://register?key=…` と `.nonetlicense` のファイル（`project.yml` で登録。`SettingsLicenseLink`）: 開くとライセンスのタブにキーを入れて「このライセンスキーを登録しますか？」と尋ねる（黙って登録しない）。キーは 8 KiB・URL は 24 KiB・ファイルは 64 KiB まで、ふつうのファイルだけを読み、制御文字は除く。起動の途中に届いたものは設定のウィンドウができるまで持っておく
- 試用期間の終了: 設定のどのタブでも上に帯（「購入する」「ライセンスキーを入力…」。ライセンスのタブでは出さない）。`TrialEndedWindowController` は起動したときと試用期間が終わったときに、1日（暦の日）に1回まで、前面を奪わない小さなウィンドウ（「購入する」「ライセンスキーを登録…」「あとで」）を出し、ほかで登録したら閉じる。出した日は UserDefaults の `com.iam74k4.Nonet.license.trialEndedPromptShown`（Debug の `--config-dir`・`--simulate-expired-trial` ではメモリだけ）
- 状態の帯: アクセシビリティの許可が無いときは「システム設定を開く」だけ（最初に押したときは macOS の許可の確認だけを出し、2回目からはシステム設定だけを開く）
- 情報: バージョン・アップデートの確認・利用ガイド・プライバシー（URL は `AppLinks`。Info.plist の `NonetSupportURL`・`NonetPrivacyURL`。未設定ならリンクを出さない）・お問い合わせ…・Nonet をアンインストール…。アプリが英語で動いているときは、URL の最後の要素の前に `en/` を入れたページ（`…/guide.html` → `…/en/guide.html`）を開く。`scripts/check-site.sh` は、その英語のページも site/ にあるかを確かめる

### 初回起動（ui-shell）
1. ようこそ＋アクセシビリティの許可（許可されたら自動で次へ）。副題は実際のトリガーキーを言う（「右⌘キーを押している間だけ…」）。手順を3行（「システム設定を開く」を押す・一覧の Nonet をオンにする（パスワードか Touch ID）・この画面に自動で戻る）で示す。「システム設定を開く」は、最初に押したときは macOS の確認だけを出し、1.5秒のうちに確認が前に出なければ（macOS は二度は尋ねないことが多い）そのときシステム設定を開く。2回目からはシステム設定だけを開く（同時に両方は出さない）。許可は1秒ごとに確かめ、許可されたら、システム設定の後ろに隠れた案内のウインドウを自分で前に出す（Nonet は Dock にも ⌘Tab にも出ないので、利用者は探せない）。トラックパッドが無ければ、許可より前にこの画面で知らせ「もう一度確かめる」を出す。許可しないまま「あとで許可する」で進むと、上の段階の印は済んだ印ではなく「!」になる
2. アプリを選ぶ: インストール済みでプリセットのあるアプリを並べ、選ぶ（モックのボード「初回起動」）。最初はすべて選んである（「次へ：試してみる」が「おすすめのまま使う」を兼ねるので、飛ばすボタンは置かない）。プリセットは `presetEnvironment` でできることに合わせる（§6「プロファイルとページ」）
3. 試してみる: 練習モードで2つの課題（`OnboardingPracticeState`: `hud` → `quickTap`）。どちらも HUD に実際に出るページ（前面のアプリのプロファイル）の実在のボタンを名前で示し、トラックパッドの図に9マスの名前を並べる。(1)「HUD（9マスの一覧）から選ぶ」: 成功した実行のうち `wasFastTap == false`（HUD でのタップも数える）。文は実行のタイミングに合わせる。(2)「すぐにタップ」: 名前を示した角のマス（右上から）を `wasFastTap == true` で。違うマスなら押したマスと目標の場所を言い、HUD の前に実行した・2つ目で HUD を使った、にはそれぞれの文。マスの位置だけを見る（どのページでもよい）。試せないときは理由と、その場で直せるならそのボタンを出す（`OnboardingPracticeBlocker`）: 無効なら「Nonet を有効にする」、アクセシビリティが無ければ「システム設定を開く」、トラックパッドが無ければ「もう一度確かめる」、いま使うページにボタンが無ければ「設定を開く」、試用期間が終わっていれば「ライセンスキーを入力…」（設定の「ライセンス」を開く。キーを登録すると知らせは消える）。パスワードの入力中は理由だけ。2つとも済むと「キーを使わない方法もあります」のカード: 左上の角 / 右上の角を選んで「試してみる」で `touchActivation` をオンにし、HUD からの実行（`wasFastTap == false`）で済んだとみなす（どの始め方かは記録に無い）。「オフに戻す」で戻す。成功・違うマス・許可・ログイン項目の問題は VoiceOver でも読み上げ、各段階の見出しは見出しとして、出たときに VoiceOver の焦点を移す
4. 完了（「準備ができました」）: こつ4つ（迷ったら指を止める・2本指でスワイプ・マスを変える（アプリの名前は出さず「メニューバーの 3×3 のアイコン ›「（アプリ名）のマスを編集…」で、前面のアプリのマスを変えられます」。案内の後ろのアプリが、その人の思うアプリとは限らないため）・角に指を置いて待つ）と試用期間の残り。「Mac にログインしたら Nonet を自動で起動する」（最初から選択。`LoginItemControlling` で「完了」と「設定を開く」のときに反映し、承認が要る・失敗したときはウィンドウを閉じずに知らせ、もう一度押すと閉じる）。「完了」で閉じると、メニューバーのアイコンを3回光らせ、その下に「Nonet はここにいます」の吹き出しを4秒（`MenuBarCallout`。Nonet が前面を返した後も残す）。アイコンが見えない（ノッチの裏を含む）ときは、アプリケーションフォルダから開く案内を代わりに出す

- 起動したときの許可の案内（`OnboardingLaunchGuide`）: 初回の起動なら案内を最初から。そうでなく、Nonet が有効でアクセシビリティが無く、「今後表示しない」（UserDefaults の `NonetHidesPermissionReminder`）を選んでいなければ、許可の画面だけを「Nonet を使うには、あと1つ許可が必要です」の題で開く。メニューの「アクセシビリティを許可…」も同じ画面を開く（「今後表示しない」は出さない）
- ウインドウは 760×600。Debug ビルドの `--onboarding-step <welcome|apps|practice|done>` で、その段階を開く（見た目の確認用）

### メニューバー（ui-shell）
- 3×3 のアイコン（中央が塗り）。無効なら薄く（塗りなし）。確かめてほしいこと（権限なし・トラックパッドなし・パスワード入力中・試用終了や残り `MenuBarModel.trialWarningDays`（3日）以下・知らせ）は右上を「!」に、アップデートは右上を点にする（`MenuBarIcon.badge`。「新しいものがある」と「手を貸してほしい」を見分けられるように）。意味はツールチップ・VoiceOver と状態の行で伝える
- メニュー（`MenuBarModel.entries`）: 状態の行（例: 「Xcode のプロファイル」「アクセシビリティの許可が必要です」「試用期間が終了しました」「試用期間は残り3日です」。無効 > 停止 > 許可 > トラックパッド > パスワード入力中 > 試用期間 の順）・アクセシビリティを許可…（許可が無いとき。初回の案内の許可の画面を開く）・知らせとこの知らせを消す・Nonet を有効にする・設定…・「◯◯ のマスを編集…」（`MenuBarEditTarget`: 前面のアプリにプロファイルがあれば「Xcode のマスを編集…」、無ければ「Pages のマスを作る…」（選ぶとプリセットがあればその中身で作って開く）、前面のアプリが分からないか `autoSwitchProfiles` が false なら「グローバルのマスを編集…」。`SettingsWindowController.showButtons(for:)` は 60秒以内にそのプロファイルで実行したマスも選ぶ）・このアプリでは使わない（前面のアプリが分かるときだけ。チェックが付く。オンで `setAppMode(.off, for:)`（プロファイルが無ければ空のページで作る。グローバルのマスを使っていたアプリにプリセットのマスを足さないため）。`MenuBarController` はオフにする前の使い方をプロファイルごとに覚え（起動している間だけ）、もう一度選ぶとそれに戻す（`profile` か `global`。オフにするときに作ったプロファイルは、空のままなら消し、マスを置いていれば `profile`）。覚えていないとき（起動し直した・設定でオフにした）は、マスのあるプロファイルなら `profile`、無ければ `global`）・最近の実行（`NonetController.recentExecutions` があるとき。「✓ Xcode › ビルド」、失敗は「✗ …」と「 — 」の後に理由の1行目。選ぶと `SettingsWindowController.showRun(_:)` でそのプロファイル・ページ・マスを開く。プロファイルは `ExecutionRecord.profileID`、無ければ名前で探す）・初回の案内をもう一度・利用ガイド（`NonetSupportURL` があるとき）・ライセンス（登録済みなら「登録済み」で、選ぶとライセンスのタブ。試用中と終了後は押せない行で残り日数か終了を出し（状態の行が同じことを言っていれば出さない）、その下に「Nonet を購入…」（購入ページがあるとき）と「ライセンスキーを入力…」）・アップデートを確認・終了
- アップデートの知らせ: Nonet は前面にならないので、Sparkle の定期の確認で見つかったアップデートは、Sparkle の画面（ほかのアプリの後ろに隠れる）ではなくメニューバーで控えめに知らせる（`SPUStandardUserDriverDelegate` の gentle reminders。起動の直後のように Sparkle がそのまま前に出せるときは Sparkle に任せる）。メニューの「アップデートを確認」が「アップデートがあります…」に変わり、アイコンの右上が点になり（「確認が必要」の「!」とは別の形）、ツールチップと VoiceOver は「Nonet（アップデートがあります）」になる。点は、ほかに確認が必要なことが無く、Nonet が無効でないときだけ（問題や無効の見た目を優先する）。選ぶと Nonet を前面にしてから Sparkle の画面を出す。点と項目は、Sparkle の画面を見せたときか、アップデートのセッションが終わったときに消える

### ウインドウとメインメニュー（ui-shell）
- 画面には出ないメインメニュー（`ShellMainMenu`。App が起動時に `NSApp.mainMenu` に入れる）を持つ。Nonet は `.accessory` なのでメニューは見えないが、設定や初回の案内のウインドウがキーの間、標準のキーがこれを通って文字の欄やウインドウに届く（無いとライセンスキーの欄に ⌘V で貼れない）。アプリのメニュー: 「Nonet について」（設定の「情報」）・「設定…」⌘,・「終了」⌘Q。編集: 取り消す・やり直す・カット・コピー・ペースト・ペーストしてスタイルを合わせる・削除・すべてを選択。ウインドウ: 閉じる ⌘W・しまう ⌘M。ヘルプ: 「Nonet ヘルプ」⌘?（利用ガイドを開く。英語で動いていれば英語のページ）。設定のウインドウは ⌘W のために閉じられるウインドウにしておく
- ⌘Q は、Nonet のウインドウが前面のときは Nonet を終了する。ほかのアプリが前面のまま結果のパネルをクリックしてキーにしたときの ⌘Q は、パネルだけを閉じる（メニューバーは前面のアプリのものなので、Nonet を終わらせない）
- Nonet の最後のウインドウ（設定・初回の案内）を閉じたら、その前に使っていたアプリを前面に戻す（Nonet が前面のままキーのウインドウが無いと、キー入力のマスのキーが Nonet に送られ、どこにも届かない）

### HUD（ui-shell）
- モックどおり: 黒い角丸のパネルに 3×3、ハイライトは白地に黒。上に題名（`ResolvedPage.title`: プロファイル名、ページに名前があれば「Xcode · デバッグ」）と案内（「タップか、右⌘を離して実行」。§5 の 15）。ページが複数なら点で位置を示し、アプリのページとつなげたグローバルのページの間は 8pt 空ける（`HUDModel.globalPagesStart`）。使い始めの20回は9マスの下に案内（`HUDModel.footnote`）。帯は注意（試用期間の終了）と知らせ（残り日数）（`HUDModel.bannerStyle`）
- 文字は 4.5:1・点は 3:1 以上（説明と二次の文字 #9A9A9A、選んでいない点 #777）。「コントラストを上げる」では縁・空きマスの破線・文字を明るくする（HUD やトーストを出すたびに読む）
- 「HUD の大きさ」（`hudScale`: 1 / 1.25 / 1.5 倍。`HUDModel.scale`・`ToastModel.scale`）で HUD とトーストを大きくし、画面に収まらなければ収まるところまで縮める
- 前面アプリからフォーカスを奪わない非アクティブなパネル。全 Space・フルスクリーンの上にも出す。表示先はポインタのあるディスプレイ
- トーストは画面下部に 0.8 秒。失敗は 1.5秒＋見出しと説明の1文字ごとに 0.06秒（3〜8秒）で、トリガーキーを押している間は消さず、離して 1秒で消す（`HUDPresenting.setTriggerHeld`）。実行中のトースト（`ToastModel.Style.running`。くるくる回る印）は時間では消えず、`HUDPresenting.hideToast` か次のトーストで消える
- 結果のパネル（`showResult`）: AI の結果など。文を選択でき、「コピー」「閉じる」と Esc で閉じる。前面アプリのフォーカスは奪わない

### ライセンス（keys-license）
- 試用は初回起動から14日。残り日数は日付の切り上げ。`LicenseManager.trialEndDate`（試用中だけ）は最後に数えた時刻＋（14日 − 使った時間）で、時計を変えない限り毎回同じ日時になる（ライセンスのタブの「11月14日まで」）
- `LicenseManager.registeredLicenseKey`（登録済みのときだけ）は保存したキー。設定の「キーをコピー」が、同じ人のほかの Mac に登録するために使う。ライセンスは1人に1つで、その人が使うすべての Mac で使える（台数の登録や解除は無い）
- キーは `base64url(JSON).base64url(署名)`。JSON は `LicenseInfo`。公開鍵は Info.plist の `NonetLicensePublicKey`
- `nonet-license keygen` で鍵を作り、秘密鍵はリポジトリの外に置く。`issue` は発行したキーを `Config/Nonet.xcconfig` の `NONET_LICENSE_PUBLIC_KEY`（アプリに入る公開鍵。`//` で切れていれば止まる）と秘密鍵の隣の公開鍵（または `--public`）で検証してから出す。`--public` がアプリの公開鍵と違えば、`--skip-app-key-check` が無い限り出さない
- 貼り付けたキーは、空白・改行を除いた全体が `eyJ` で始まるキーの形ならそれを使う。そうでなければ前後の文（「License key:」「License Key」（改行）・引用符・メールの「>」・句点など）を除いて、キーの形（`eyJ…` と 86 文字の署名）の部分を探し、中身が `LicenseInfo` として読めるものがちょうど1種類あるとき（読めるものが無ければ、キーの形のものがちょうど1種類あるとき）だけそれを使う（`LicenseCoding.licenseKey(in:)`）。保存するのはキーの部分だけ
- 試用は使った時間を数える（時計を戻しても増えない）。`canExecuteActions` はいつでも正しいが、表示用の `entitlement` は `refresh()` でしか変わらない。`NonetController` はトリガーを押した後（60秒に1回まで。ライセンスがあれば呼ばない。§5）、ui-shell はメニューを開いたとき・スリープ解除・日付の変化・時計の変更で `refresh()` を呼ぶ。ライセンスが登録されているときの `refresh()` は、試用の記録を書かない
- 試用の記録（開始日・最後に数えた時刻・使った時間）は `UserDefaultsLicenseStorage` が UserDefaults と `Application Support/Nonet/` の隠しファイルに置き、アプリ本体（`UserDefaultsLicenseStorage(keychain: SystemTrialRecordKeychain(), marker: SystemTrialRecordKeychain.machineMarker(), evidence: FileTrialUsageEvidence.standard())`）では `SystemTrialRecordKeychain`（ログインキーチェーンの汎用パスワード `com.iam74k4.Nonet.license.trial`。Developer ID で署名した製品版でだけ動く）にも置く。キーチェーンは起動ごとに1回読み、ほかの2か所の両方に (時刻, 使った時間) の組が無ければその組で、あれば使った時間だけを下限として数える。書くのは起動したとき・使った時間が1時間増えたとき・時計が変わったとき（`didSaveTrialProgress`・`needsKeychainWrite`）。`--self-check` と Debug の `--config-dir` はキーチェーンを使わない
- 2つ目のキーチェーンの項目（`marker`。`SystemTrialRecordKeychain.machineMarker()`）: サービスの名前は SHA-256(IOPlatformUUID の大文字 + 改行 + bundle ID の小文字) の16進64桁、アカウントはその先頭16文字、ラベルは付けない（名前から Nonet のものとは分からない）。1つ目と同じ記録を同じときに書き（`didSaveTrialProgress`）、起動ごとに1回、1つ目と一緒に読んで `TrialRecord.reconciled` でまとめる。1つ目だけを消しても試用は続く。Mac の識別子は IOKit（`IOPlatformExpertDevice` の `kIOPlatformUUIDKey`）で読み、読めなければ使わない。識別子そのものは保存しない。動くのは1つ目と同じく Developer ID で署名した製品版だけ
- 以前に使った跡（`evidence`。`TrialUsageEvidence`・`FileTrialUsageEvidence`）: 4か所のどこにも開始日が無いときだけ、`UserDefaultsLicenseStorage.earlierUseStart` で開始日を決める。2つ目の項目があるのに記録として読めなければ（壊れている・書き換えられた）、いつ使ったかは分からないので、ちょうど期限切れになる日（今 − 14日）。そうでなければ `Application Support/Nonet/Backups/` と `~/Library/Caches/<bundle ID>/` のフォルダの作成日のうちいちばん古いもの（フォルダは中身を書き換えても作成日が変わらず、試用はそれより前に始まっているので、実際より長くは数えない。初めての起動でフォルダが先にできても、作成日はほぼ今なので試用は減らない）。`earliestPlausibleUse`（2025-01-01）より前の日付は使わず、今より後の日付は今にする。フォルダの日付は署名に関係なく見る。`--self-check` と Debug の `--config-dir` は、2つ目の項目もフォルダも使わない
- 無効にしたライセンス（`LicenseRevocationList`。`LicenseRevocation.swift`）: 返金したキーや公開されてしまったキーのライセンス ID の SHA-256（16進の小文字）を、`NonetCore/Resources/RevokedLicenses.txt`（1行に1つ。`#` から後ろはコメント）としてアプリに入れる（`LicenseRevocationList.bundled`。読めなければ空にしてログに残す）。`LicenseManager` は保存したキー（`storedLicense()`）と登録しようとしたキー（`verify(licenseKey:)`）の両方を、署名を確かめた後に照らし、一覧にあれば `LicenseError.revoked`。保存したキーなら登録していないものとして扱い（試用の記録で数え直す）、キーは消さずに `revokedLicense` に中身を入れ、設定のライセンスのタブが理由を出す。一覧に足すのは `nonet-license revoke`（[release.md](release.md) 3.5）。通信はしない。`nonet-license verify` は一覧を見ない
- NonetCore は Foundation と Observation と CryptoKit だけ（§2。CryptoKit は、`License.swift` の署名の確かめと `LicenseRevocation.swift`・`TrialRecordKeychain.swift` の SHA-256 に使う）だが、`Licensing/TrialRecordKeychain.swift` だけは例外として Security・LocalAuthentication・IOKit を使う（キーチェーンの読み書きと署名の身元の確認、2つ目の項目の名前に使う Mac の識別子の読み取り。`TrialRecordKeychain` の protocol で差し替えられ、テストでは本物のキーチェーンに触れない）。ライセンスのロジックと同じ場所に置き、App が1行で使えるようにするため
- 置き場所の記録が食い違ったら `TrialRecord.reconciled` でまとめる: 開始日は最も早いもの、(最後に数えた時刻, 使った時間) は置き場所ごとの組として、次に数えたときに最も多くなる組 (U, V + U)（U = 使った時間の最大、V = 時刻 − 使った時間 の最小）にする。古い記録（バックアップから戻したフォルダ・書けないファイル）で同じ時間を二重に数えず、1か所だけ書き換えても延びず、時計を戻しても減らない
- 動いている間に、保存先の使った時間が自分の数えた量より多くなっていたら（ほかの Nonet が数えた）、自分の数え方（自分の使った時間 ＋ 前に数えてからの経過）と保存先の数え方（保存先の使った時間 ＋ 保存先の最後に数えた時刻からの経過）の多い方を取る。使った時間を最も多く残し、同じ経過を二重には数えない（保存先の量に自分の経過を足さない）

### 起動オプション（App/main.swift・`ShellLaunchOptions`）
- `--self-check`（すべてのビルド）: 画面もイベントタップも作らずに、プリセット・ランチャーの候補・設定の保存と読み直し・MultitouchSupport の読み込みを確かめ、JSON を出して終わる（失敗なら終了コード 1）。試用の記録は UserDefaults と Application Support の写し（`.install`・`.install-seen`・`.install-used`）の両方から読むだけで（`ShellSelfCheck.LicenseSnapshot`）、アプリと同じく試用に厳しい方を使うので、アプリと同じライセンスの状態を出す。ただしキーチェーン（2つの項目）と以前に使った跡（フォルダの作成日）は使わないので、UserDefaults と Application Support の記録がどちらも消えているときは、アプリが期限切れとしても「残り14日」と出ることがある。試用を始めたり、数えたり、記録をそろえたり書いたりはしない。`scripts/test.sh` が最後に動かす
- Debug ビルドだけ: `--config-dir <dir>`（設定をそのフォルダに置き、ライセンスはメモリだけに置く。HUD の案内の回数・試用期間の知らせの日付（`MemoryHUDGuidanceStore`）・「今後表示しない」・試用期間の終了のウインドウを出した日も UserDefaults に書かない。下の「同時に1つだけ」も調べないので、インストールした Nonet と並べて動かせる）・`--show-settings [tab]`・`--show-onboarding`・`--onboarding-step <welcome|apps|practice|done>`・`--preview-hud`・`--preview-toast`・`--preview-result`・`--simulate-expired-trial`・`--snapshot <dir>`（開いたウインドウを画像に書き出して終わる）。画面の確認用

### 起動の順と、同時に1つだけ（App/main.swift・App/SingleInstance.swift・`ShellInstanceGuard`）
同じ Nonet が2つ動くと、どちらもトリガーキーとトラックパッドを見て1回のタップでマスが2回実行され、試用の時間も2倍に数えられる。
- `main.swift` は `--self-check` を見た後、NSApplication を動かす前に `SingleInstance` で同じ bundle ID の Nonet を調べる
- 終わり始めた Nonet は `applicationWillTerminate` で一時フォルダに印のファイル（`ShellQuitMarker`。`Nonet-quitting-<プロセス番号>`）を書き、起動したときに消す。印のあるもの（終了した直後に開き直した・Sparkle のアップデートの後の再起動など）は残す候補にせず、終わるのを最長10秒（`takeOverTimeout`）待ってから起動する（2つが同時にトリガーキーを見ないように）
- どのプロセスから見ても同じ決め方で、残りの中から残す1つを決める（`ShellInstanceGuard.keeper`）。まず場所ごとに（本来の場所 = ディスクイメージや App Translocation でないもの・一時的な場所）1つずつ候補を、起動し終えたもの → 先に開かれたもの → プロセス番号の小さいもの の順で選ぶ。次に、本来の場所の候補を残す。ただし一時的な場所の候補の方がビルド番号（`CFBundleVersion`。`App/SingleInstance.swift` が各プロセスの `Contents/Info.plist` から読む）が数として大きければ、そちらを残す（分からなければ新しいとはみなさない）。2段に分けるのは、2つずつ比べる順に「場所が違えばビルド番号」を混ぜると、3つ以上のときに順が輪になり、プロセスごとに答えが変わることがあるため
- 残すのがほかのもので、それが起動し終えていれば、待たずに任せて終わる（もう一度開くとすぐに設定が開くように。相手の `applicationShouldHandleReopen` が設定のプロファイルのタブを開く）。一時的な場所から開いた自分が本来の場所のものに任せるとき（ディスクイメージの方が新しくない）は、黙って終わらずに「Nonet はすでに動いています」（`ShellMoveToApplications.explainAlreadyRunning`。両方の版を言い、入れ替えるには動いている方を終了してから開き直すと伝える）を出してから任せる（`ShellInstanceDecision.explainAndHandOff`）。相手も起動の途中（同時に開かれた）なら最長3秒（`shutdownGrace`）待ってから任せる
- 残すのが自分で、起動し終えたほかの Nonet が動いていれば（自分がアプリケーションフォルダなどのものなら、ディスクイメージなどから開いたもの。自分が新しいディスクイメージのものなら、古いアプリケーションフォルダのもの）、それに終わってもらってから代わりに動く（`replace`）。10秒（`takeOverTimeout`）たっても終わらなければ、こちらが譲る。新しいディスクイメージの方が動いたときは、起動した後で `AppDelegate` がアプリケーションフォルダの Nonet を置き換えるかを尋ねる（下の「アプリケーションフォルダへ移す」）
- 同時に2つ開かれても、残るのはちょうど1つ

### アプリケーションフォルダへ移す（`ShellMoveToApplications`）
- App Translocation か読み取り専用のディスクイメージから開かれたら（Sparkle がアップデートを入れない場合と同じ）、`AppDelegate` が「Nonet をアプリケーションフォルダに移しますか？」と尋ねる。移す先は `/Applications`、そこに書き込めなければ（管理者でない）`~/Applications`。どちらにも書き込めなければ、尋ねずに Finder でドラッグする方法を伝える
- 移す先にすでに Nonet があれば、置き換えてよいか確かめてから、古い方をゴミ箱に入れる。最後の入れ替えに失敗したら、ゴミ箱から元の場所に戻す
- 同じフォルダの隠した一時的な名前に写し、写しから `com.apple.quarantine` を外し（Finder で移したときと同じ。外さないと、移した先でまた App Translocation で開かれる）、入れ替える。写すのに失敗したら、写しかけのものも残さない
- 入れ替えたら、このプロセスが終わるのを待ってから移した先を開くよう頼み、自分は終わる

## 7. 実機で確かめられていないこと

フェーズ0の検証アプリでは手動テストが終わっていない。次の点は設定で切り替えられるようにし、既定値は安全側にする。
- ポインタの固定: 移動イベントを捨てて止まるか → `CursorLockMethod` で方式を選べる。既定の automatic は捨てたうえでずれたら戻す
- 触覚: 別アプリが前面のとき `NSHapticFeedbackManager` が効くか → MTActuator を優先し、失敗したら公開 API
- 2本指スワイプが前面アプリ（Safari の戻るなど）に届かないか → セッション中はジェスチャー系のイベントも捨てる
- 「タップでクリック」のクリック（mouseDown）と、MultitouchSupport の指が離れたフレームのどちらが先に届くか（手動テスト T5 で、CGEvent / NSEvent のタイムスタンプを指のフレームと並べてログに出す）。0.2秒の猶予（`clickGraceInterval`）と 0.5秒の `lateClickWindow` で足りるか。本物の HID のイベントで CGEvent のタイムスタンプの単位が何か。タップが捨てた「押す」が `hidSystemState` のボタンの状態に表れるか（表れないと、捨てたボタンを忘れる見直しが早すぎたり遅すぎたりする）

- 角の呼び出し（§5）: 角の範囲（0.12 × 0.18）・0.4秒・動きの許容 0.02 で、ふだんの操作で誤って出ず、狙えばすぐに出るか。指を置いて待っている間、macOS が指をクリックやドラッグとして扱わないか。離す前に留まる 0.15秒（`liftDwell`）が、選んだつもりの実行を落とさず、ポインタを動かすつもりで離したときを実行しないか
- 手のひらの見分け（§5「角の呼び出し」）: `CornerHoldRecognizer.palmMajorAxis` = 25 は、MultitouchSupport の `majorAxis`（指先でおよそ 8〜15、平らに置いた親指で 20 ほど、という見込み）から決めた値で、実機では確かめていない。単位が見込みと違っても、手のひらを見分けなくなる方向にしか外れない（今より悪くはならない）。実機で指先・親指・手のひらの値をログに出して確かめる
- HUD でのタップ（0.25秒・0.04）・休めている指（0.02）・マウスの見分け（指を離して 0.5秒）が実機で妥当か。離して 0.5秒より後に「タップでクリック」が届かないか。2打の触覚（50ms・40ms）が1打と区別できるか
- シェルを調べる `zsh -l -i`（§6「アクション」）: ~/.zshrc が ~/Documents などに触れると、macOS が Nonet の名前で許可を求めることがある。ショートカットの出力（`--output-type public.utf8-plain-text`）は、実物のショートカットでは通して試していない

手動で確かめること（トラックパッドの開始し直し。§5「トラックパッド」）: スリープと復帰、外部ディスプレイをつないだまま蓋を閉じて開く、Magic Trackpad を外してつなぎ直す、ファストユーザスイッチ。どれも起動し直さずにトラックパッドが使え続けるか、ログの「トラックパッド（…）: N 台を開始」と開始し直しの記録を見る
