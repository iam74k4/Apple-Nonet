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
    NonetCore/              純粋なロジック（Foundation と Observation だけ。AppKit 禁止。例外: Licensing/TrialRecordKeychain.swift の Security・LocalAuthentication。§6「ライセンス」）。Swift 6 言語モード
      Model/                設定のデータ型・編集・保存・プリセット・キー表記・スクリプト用の環境変数
      Engine/               セッションの状態遷移・NonetController
      Licensing/            ライセンスと試用
      Services.swift        macOS に触れる部分の protocol（契約）
      HUDModel.swift        HUD・トースト・NonetError（契約）
    CMultitouch/            MultitouchSupport を dlopen する C ラッパー
    NonetPlatform/          Services の macOS 実装（Input/・Actions/）。NonetServices.live()
    NonetUI/                SwiftUI / AppKit の画面（Settings/・HUD/・MenuBar/・Onboarding/・Common/）
    NonetLicenseTool/       nonet-license（鍵の生成・キーの発行・検証）
  Tests/
    NonetCoreTests/ NonetPlatformTests/ NonetUITests/
scripts/                    ビルド・リリース・アイコン生成
docs/                       設計・リリース手順・利用ガイド
site/                       販売ページ（静的）
```

依存の向き: `NonetCore` ← `NonetPlatform`、`NonetCore` ← `NonetUI`、App はすべてに依存。`NonetUI` は `NonetPlatform` に依存しない（必要なものは `NonetServices` の protocol 経由で受け取る）。

`NonetController`（Core）が本体で、`NonetServices`（protocol の束）と `HUDPresenting` を受け取って動く。テストでは偽物の実装を渡す。

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

トリガーキーを押してから離すまでを「セッション」と呼ぶ。設定でトラックパッドの角の長押しからも始められる（下の「角の長押し」）。`SessionEngine`（純粋なロジック）がこの仕様を持ち、`NonetController` が入出力をつなぐ。

1. **開始**: トリガーキーが単独で押された（ほかの修飾キーが押されていない）ら開始する。Nonet が無効・トラックパッドが無い・設定ウィンドウでキー記録中なら開始しない。Nonet のウィンドウがキーのときも開始する（実行できるマスは限る。下の「実装で決めた細部（NonetController）」）。開始と同時にポインタの抑止を始め、前面アプリのページの並び（`resolvedPages`）を決め、最初のページを使う
2. **指**: 触れている指のうち最後に置いた指を使う。マスは 3×3 の等分で、境界には余裕（ヒステリシス 0.03）を持たせる
3. **速押し**: トリガーを押してから `hudDelay`（既定 0.3秒）以内に1本指を置き、その指が `hudDelay` 止まる前に離れたら、置いた位置のマスを即実行する。HUD は出さない。実行したマスを `showExecutionToast` ならトーストで知らせる
4. **HUD**: 次のどちらかで HUD を出す。(a) トリガーを押してから `hudDelay` の間に指が置かれなかった、(b) 置いた指が `hudDelay` 以上触れたままになった。HUD は指の下のマスをハイライトする
5. **HUD からの実行**: `onTriggerRelease` なら、指を置いたままトリガーを離すとハイライト中のマスを実行。指を離してからトリガーを離すとキャンセル。`onFingerLift` なら、1本指を離したときにハイライト中のマスを実行し、HUD は閉じる
6. **続けて実行**: トリガーを押したまま、何度でも速押しできる。一度実行した後は (a) では HUD を出さず、(b) のときだけ出す
7. **触覚**: ハイライトするマスが変わるたびに `boundary`、ページが変わったら `pageChange`、実行したら `execute`。強さは設定の `haptics`
8. **ページ**: 2本指で横にスワイプ（2本の平均の移動が 0.12 以上）すると前後のページへ。端では止まる。1回のスワイプ（指が離れるまで）で1ページ。HUD が出ていなければ出す
9. **2本以上の指**: 2本以上触れたタッチは実行しない
10. **中断**: セッション中にほかのキーや修飾キーが押されたら、何も実行せずに終える（そのキーは前面アプリに渡る）。20秒を超えたセッションも終える
11. **何もしない**: 指を置かずにトリガーを離したら何もしない
12. **空きマス**: 実行しても何も起きない（触覚も鳴らさない）
13. **ライセンス**: 試用期間が終わっていたら、HUD に「試用期間が終了しました」の帯を出し、実行の代わりに `NonetError.licenseRequired` のトーストを出す
14. **練習モード**: `isPracticeMode` の間は実行せず、`lastExecution` に記録だけする

ポインタの抑止（`KeyboardMonitor.isSuppressingPointer`）はセッション開始から終了まで。セッション中に押したクリックの「離す」も、終了後に捨てる。

終わる直前の 0.5秒（`SessionEngine.lateClickWindow`）のうちに指が離れたか、置いて 0.5秒たたない指がまだ触れているときは、その指の「タップでクリック」が抑止の後に届くことがある。エンジンはこれを `endPointerSuppression(dropsLateClicks: true)` で知らせ、ポインタのタップは終わった後も 0.2秒（`PointerSuppressor.clickGraceInterval`）残って、その間に届いたクリックの「押す」と、対になる「離す」を捨てる（止めていたカーソルの下でクリックにならないように）。移動とスクロールは渡す。指に触れていないセッション（トリガーをほかのキーと組み合わせただけ など）の後は捨てない。0.2秒は、メインスレッドで抑止を終えた時刻から数える。
- 捨てた「押す」の「離す」が届かないとき（デバイスが外れたなど）は、押してから 2秒以上（`staleButtonAge`）たち、0.5秒ごとの見直しで2回続けて（`staleButtonSweeps`）物理的に離れて見えたら忘れる
- タップが無効にされていた間に取りこぼしたかもしれない「離す」は、最初の見直しで物理的に離れて見えたら忘れる

実装で決めた細部（SessionEngine）:
- 一度でも2本以上触れたタッチは、ハイライトも境界の触覚も出さない（9 により実行しないため）
- トリガーを離した時点で、置いて `hudDelay` 未満の指が残っていれば、その指が離れるまで（最長 `hudDelay`）セッションを続ける。離れれば速押しとして実行する
- トリガーより前から置いていた指は速押しにならない。このため `NonetController` はセッション外のタッチのフレームもすべてエンジンに渡す
- 2本指を左へ動かすと次のページ（Launchpad と同じ向き）
- `onFingerLift` で、指を置いたままトリガーを離したらキャンセル
- `execute` の触覚はエンジンではなく `NonetController` が鳴らす（空きマス・ライセンス切れでは鳴らさない）
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
- Nonet のウィンドウがキーのとき（設定・練習の手前までの初回の案内・クリックしてキーにした結果のパネル。`FrontmostAppObserving.isOwnWindowKey`）も、セッションはふだんどおり始まる。ポインタの抑止と HUD は動き、HUD は直前のアプリのプロファイルを出す。ただし前面アプリに働きかけるマス（キー入力・スクリプト・ショートカット・メニュー項目・AI。`ControllerExecutionPolicy.dependsOnFrontmostApp`）は実行せず、「Nonet のウィンドウが前面にあるので実行しませんでした。設定では「このマスをテスト実行」で試せます」の失敗のトーストを出し、`lastExecution` に失敗として記録する（送ったキーや読む選択範囲が Nonet のウィンドウのものになるため）。アプリを開く・URL は実行する。練習モードはこれまでどおり記録する。Nonet が前面のアプリでも、キーのウィンドウが無ければ（設定を閉じた後・Finder から開いた直後）何も止めない
- トリガーを押したら `TouchSource.revalidate()` を呼ぶ（止まったトラックパッドを開始し直す。下の「トラックパッド」）
- 実行はタップした順に始まる。キー入力・メニュー項目・アプリ・URL・ターミナルのスクリプトは1つずつ（前の実行が終わるまで次は待つ。最長5秒）。裏で動かすスクリプト・ショートカット・AI は、前面アプリの文脈を読み終えるまでの最長1秒だけ次を待たせ、その後は並行して動く。`lastExecution` は最後に終わった実行
- 設定の変更はすぐに反映し、ファイルへの保存は 0.5 秒ごとにまとめる（`stop()` で書き切る）。`start()` で読み込む前の変更は保存しない。設定ファイルを読めなかったときは、そのプロセスの間は保存しない（`notice` で知らせる）。壊れていたときは初期設定で置き換えて保存する
- 「このマスをテスト実行」: アプリのプロファイルならそのアプリを、グローバルなら設定を開く前に使っていたアプリを前面に出してから（0.4 秒＋最長 8×0.2 秒待つ）実行する。前面に出せなかったとき、前面アプリに入力を送るアクション（キー入力・選択範囲を置き換える AI）は実行しない。練習モードでも実行するが、試用期間が終わっていたら実行しない
- トーストは速押しのときだけ（`showExecutionToast`）。結果のパネルを出したときと失敗は別で、失敗はいつもトーストで知らせる

角の長押し（トラックパッドだけで呼び出す。`GlobalSettings.touchActivation`・`CornerHoldRecognizer`・`SessionActivation.cornerHold`）:
- 設定は 使わない（既定）・左上の角で長押し・右上の角で長押し。トリガーキーはどれでもいつもどおり使える。設定ファイルには「使わない」以外のときだけ `touchActivation` を書く（無い・知らない値なら使わない。前の版の書式のまま）
- 見分け方（`CornerHoldRecognizer`。`NonetController` がセッションの外も含めてすべてのフレームを渡す）: 選んだ上の角の範囲（横 `zoneWidth` = 0.12・奥行き `zoneHeight` = 0.18。トラックパッドを 1 とした割合で、縁ちょうどは中）で触れ始めた1本指が、ほかの指が触れず、触れた位置から `movementTolerance`（0.02。トラックパッドを 1 とした距離）より動かずに `holdDuration`（0.4秒）触れ続けたら合図する。2本目の指・それより動いた・先に離した・角の外で触れ始めて入ってきた・最初から2本以上で触れた、のどれかなら、そのタッチではもう待たない。合図は1つのタッチで1回だけ。設定が「使わない」の間とセッション中に触れ始めた指は待たない（トリガーキーのセッションの指を、終わった後に長押しとみなさない）。指を止めている間にフレームが来なくても始められるよう、`NonetController` は合図の時刻にタイマーを置く。トラックパッドを止めたとき（無効にした など）は、触れていた指は離れたことにする
- 始め方: トリガーキーと同じ `NonetController.beginSession` を通る（1 と同じく、無効・アクセシビリティなし・トラックパッドなし・セキュア入力中・キー記録中なら始めない。前面アプリのページを使い、Nonet のウィンドウがキーのときの決まりも同じ）。ただし試用期間が終わっていたら始めない（角に指を置いただけで、何も実行できない HUD を出さないため。トリガーキーなら 13 の帯で知らせる）
- エンジンには `.triggerDown` の `configuration.activation` を `.cornerHold` にして渡す。開始と同時にポインタの抑止を始め、速押しの段階も `hudDelay` も無く HUD を出して指の下のマスを光らせ、`activation` の触覚を鳴らす。HUD の案内は、実行のタイミングの設定に関係なく「指を離して実行」
- ハイライトは 2 と同じく最後に置いた指を追う（境界の触覚も 7 と同じ）。すべての指が離れたら終える: 測り始めてから指が `movementTolerance` より動いていれば、光っているマスを実行して released。動いていなければ何もせずに cancelled。2本以上で離した・空きマス（12）も何もせずに cancelled。測り始めるのは、セッションの始まりと、2本以上から1本指に戻ったとき
- 2本指の横のスワイプで 8 のとおりページを変える。2本以上から1本指に戻ったら、残った指でまた選べ（ハイライトが戻る）、次の2本指のスワイプでもう1ページ変えられる。「動いた」も測り直すので、スワイプの直後に離すとキャンセル（選ぶにはもう一度滑らせる）
- ほかのキーや修飾キーを押したら（修飾キーを離しただけでは終えない）10 と同じく何も実行せずに終える。トリガーを押していないので、セッションの間は `KeyboardMonitor.interruptsWithoutTrigger` を true にし、モニターにトリガー無しでも `.interrupted` を1回送ってもらう（そのキーは前面アプリに渡す。Nonet 自身が送ったキーは数えない）。トリガーキーを押したら、このセッションを終えてトリガーキーのセッションを始める（置いたままの指は 4 (b) で HUD）。トリガーを離したイベントは使わない。`maxDuration`（20秒）を超えたら終える
- 長押しはタップではないが、終えるときの遅れて届くクリックの扱い（`lateClickWindow`・`clickGraceInterval`）はトリガーキーと同じ（指を離して終えるので、ふつうは捨てる）

実装で決めた細部（トラックパッド。`MultitouchTouchSource`）:
- 次のときにデバイスを開始し直す: IOKit の抜き差しの通知（`AppleMultitouchDevice` の match・terminate）、スリープからの復帰、ユーザーのセッションが前面に戻ったとき（ファストユーザスイッチ）、画面のスリープからの復帰、ディスプレイの構成の変化。指が触れている間は、離れるまで待つ
- 使えるはずのデバイスの一部を開始できなければ、1・3・10・30秒後、その後は60秒ごとに開始し直す（`MultitouchRecovery.retryDelays`）
- 抜き差しの通知を取りこぼしても気づくよう、デバイスの一覧を10秒ごとに見直し（`MultitouchRecovery.listCheckInterval`）、開始しようとしたものと違えば開始し直す
- トリガーを押したとき（`TouchSource.revalidate()`）、開始し直してから10秒（`silentRestartInterval`）たってもフレームが1つも届いていなければ開始し直す（止まったのか、触れていないだけかは分からないので、この間隔に1回まで）

## 6. 機能の仕様

### プロファイルとページ
- グローバルが必ず1つ（先頭）。アプリのプロファイルは bundleID ごとに1つまで。各プロファイル 1〜3 ページ
- `resolvedPages(frontmostBundleID:)`: `autoSwitchProfiles` が true で、そのアプリの有効なプロファイルがあれば、そのページ。`appendGlobalPages` なら後ろにグローバルのページをつなげる。プロファイルが無ければグローバルのページだけ
- グローバルの初期値はランチャー: `PresetLibrary.launcherCandidates` のうちインストール済みのアプリを候補の順に最大3ページ（27個）（起動アクション、アイコンはアプリ）。macOS 26 で Launchpad が無くなったので、その代わりになる。Arc は 2026-12-22 に動かなくなるため、候補には Dia を入れている（Arc のアプリ用プリセットは残す）

### アクション
| 種類 | 動き |
|---|---|
| キー入力 | 前面アプリに送る。`.character` は現在のキー配列で仮想キーコードを探す（JIS でも ⌘[ などが正しく届く）。修飾キーはイベントのフラグに明示し、押しっぱなしのトリガーキーが混ざらないようにする。連続キーは 40ms 間隔 |
| アプリ起動 | 起動中なら前面へ、無ければ起動。`hideIfFrontmost` なら前面のとき隠す |
| URL | 既定のアプリで開く。スキームが無ければ https を付ける |
| スクリプト | `/bin/zsh -l -c`。`ScriptEnvironment` の環境変数を渡し、作業フォルダはプロジェクトのフォルダ（無ければホーム）。background は制限時間で打ち切り、失敗したら標準エラーの末尾をトーストに出す。terminal はターミナルの新しいウィンドウで実行（一時的な .command ファイルを `NSWorkspace` でターミナルに開かせる。Apple Events は使わない）。.command ファイルは利用者ごとの一時フォルダ（`confstr(_CS_DARWIN_USER_TEMP_DIR)` の `Nonet/Terminal/`、本人だけが入れる）に本人だけが読み書き・実行できるファイルとして書き、実行が始まると自分を消す。開かれずに残ったものは5分後と、次の起動時に消す |
| ショートカット | `/usr/bin/shortcuts run <名前>`。`passSelectedText` なら選択中のテキストを入力に渡す |
| メニュー項目 | 対象アプリが前面で `keyEquivalent` があればキーを送る。無ければアクセシビリティ API でメニューをパスどおりにたどって押す。状態で名前が変わる項目（「再生」⇄「一時停止」、「ツールバーを表示」⇄「ツールバーを非表示」、Enter/Exit Full Screen など）は対になる名前でも探し、最後の項目はそれでも無ければ、同じメニューで同じショートカットを持つ項目が1つだけのときそれを押す（1回押した後も動き続けるように） |
| AI | macOS 26 以降で Apple Intelligence が使えるときだけ。選択中のテキストと指示文を端末内の言語モデル（FoundationModels）に渡し、出力先に従う。使えなければ `NonetError.unavailable`。「結果を表示」は `ActionPerforming.performReturningOutput` が文字列を返し、`NonetController` が `HUDPresenting.showResult` で結果のパネルに出す（コピーと閉じるがある）。「選択範囲を置き換える」は、アクセシビリティが「選択なし」と答えて ⌘C で取ったとき（貼ると置き換えでなくカーソルの位置への挿入になる）と、クリップボードの中身を保てないとき（下）は、貼り付けずに結果のパネルに出す |

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
- サイドバー: グローバル・アプリのプロファイル（アイコン付き、並べ替え・削除・無効化）・「プロファイルを追加」（インストール済みアプリから選ぶ。プリセットがあれば中身を入れる）
- 中央: ページの切り替え（最大3）と 3×3 のグリッド。クリックで選択、ドラッグで入れ替え、Delete で空に、右クリックで複製・削除・テスト実行
- マスの編集（空にする・Delete・複製・作る・ドラッグでの入れ替えと移動・メニュー項目の割り当て。中身のあるマスを置き換えるときも）は、設定ウィンドウの `UndoManager`（`SettingsModel.undoManager`）に積み、⌘Z（メインメニューの「取り消す」）で戻せる。操作の名前は「マスを空にする」「マスの移動」「マスの入れ替え」「メニュー項目の割り当て」。マスを空にしたときと、中身のあるマスをメニュー項目で置き換えたときは、グリッドの下に「マスを空にしました」（または「マスの中身をメニュー項目で置き換えました」）と「元に戻す」も出す。その後に変わったマスは、消したり上書きしたりせず「マスがその後に変わったため、元に戻せませんでした」と知らせる。ページやプロファイルの削除と、プロファイルを置き換える読み込みは、そのプロファイルの undo の履歴だけを捨てる
- 右: インスペクタ。表示名・アイコン（SF Symbols の候補・アプリ・文字）・アクションの種類と中身。キー入力は記録欄（押したキーをそのまま記録）と、macOS が先に使うキー（⇧⌘4・⌘Space など、記録できない）を書く「表記で入力」の欄。アプリは一覧から選ぶ。ショートカットは名前の一覧から選ぶ
- メニューから割り当て: 起動中アプリのメニューを読み（`MenuReading.menuItems(for:)` は async で、読むのはメインスレッドの外）、検索して、空きマスへドラッグ（またはダブルクリック）
- 「このマスをテスト実行」
- 全体の設定: 有効化・トリガーキー（JIS で右⌥を選ぶと警告）・トラックパッドだけで呼び出す（角の長押し。§5）・実行タイミング・HUD の待ち時間・HUD の位置・触覚・グローバルのページをつなげる・トリガーキーを前面アプリに渡す・実行を知らせる・カーソルの固定方法（「詳細」の見出しの下）・ログイン時に起動・プロファイルの書き出し / 読み込み（`ConfigurationStore.importDocument(from:)` → `NonetConfiguration.importProfiles(_:)`。結果の件数 `ImportResult` を知らせる）
- 読み込みの確認（`SettingsImportPlan`）: 今の設定が置き換わるとき、または読み込むプロファイルに、スクリプト・Return を押すか4打より長いキー入力・Mac の中のファイルを開く URL のマスがあるときは、何も置き換わらなくても読み込む前に確かめる。そのマスは「・プロファイル › マス」と中身（スクリプトは最初の3行と行数、押すキー、開くファイルの場所）で並べる。スクリプト全体は読み込んだ後にインスペクタで読める。メニュー項目のショートカットは1打だけ残し、それより長いものは読み込むときに捨てる（その項目はメニューを押して選ぶ）
- 文言は docs/user-guide.md の項目名と合わせる
- ライセンス: 状態（試用の残り日数 / 登録者）・キーの入力・購入ページ
- 情報: バージョン・アップデートの確認・利用ガイド・プライバシー（URL は `AppLinks`。Info.plist の `NonetSupportURL`・`NonetPrivacyURL`。未設定ならリンクを出さない）。アプリが英語で動いているときは、URL の最後の要素の前に `en/` を入れたページ（`…/guide.html` → `…/en/guide.html`）を開く。`scripts/check-site.sh` は、その英語のページも site/ にあるかを確かめる

### 初回起動（ui-shell）
1. ようこそ＋アクセシビリティの許可（許可されたら自動で次へ）。許可は1秒ごとに確かめ、許可されたら、システム設定の後ろに隠れた案内のウインドウを自分で前に出す（Nonet は Dock にも ⌘Tab にも出ないので、利用者は探せない）。許可しないまま「あとで許可する」で進むと、上の段階の印は済んだ印ではなく「!」になる
2. アプリを選ぶ: インストール済みでプリセットのあるアプリを並べ、選ぶ（モックのボード「初回起動」）。「あとで設定する」もある
3. 試してみる: 練習モードで、トリガー＋タップを案内どおりにやってもらう（「右⌘を押しながら右上をタップ」→ 成功表示）。試せないときは理由と、その場で直せるならそのボタンを出す（`OnboardingPracticeBlocker`）: 無効なら「Nonet を有効にする」、アクセシビリティが無ければ「システム設定を開く」、試用期間が終わっていれば「ライセンスキーを入力…」（設定の「ライセンス」を開く。キーを登録すると知らせは消える）。トラックパッドが無い・パスワードの入力中は理由だけ
4. 完了

### メニューバー（ui-shell）
- 3×3 のアイコン（中央が塗り）。無効・権限なし・試用終了で見た目を変える
- メニュー: 状態（例: 「Xcode のプロファイル」「アクセシビリティの許可が必要です」）・有効にする・設定…・プロファイルを編集…・初回の案内をもう一度・ライセンス（試用の残り日数）・アップデートを確認・終了
- アップデートの知らせ: Nonet は前面にならないので、Sparkle の定期の確認で見つかったアップデートは、Sparkle の画面（ほかのアプリの後ろに隠れる）ではなくメニューバーで控えめに知らせる（`SPUStandardUserDriverDelegate` の gentle reminders。起動の直後のように Sparkle がそのまま前に出せるときは Sparkle に任せる）。メニューの「アップデートを確認」が「アップデートがあります…」に変わり、アイコンには「確認が必要」と同じ右上の点が付き、ツールチップと VoiceOver は「Nonet（アップデートがあります）」になる。点は、ほかに確認が必要なことが無く、Nonet が無効でないときだけ（問題や無効の見た目を優先する）。選ぶと Nonet を前面にしてから Sparkle の画面を出す。点と項目は、Sparkle の画面を見せたときか、アップデートのセッションが終わったときに消える

### ウインドウとメインメニュー（ui-shell）
- 画面には出ないメインメニュー（`ShellMainMenu`。App が起動時に `NSApp.mainMenu` に入れる）を持つ。Nonet は `.accessory` なのでメニューは見えないが、設定や初回の案内のウインドウがキーの間、標準のキーがこれを通って文字の欄やウインドウに届く（無いとライセンスキーの欄に ⌘V で貼れない）。アプリのメニュー: 「Nonet について」（設定の「情報」）・「設定…」⌘,・「終了」⌘Q。編集: 取り消す・やり直す・カット・コピー・ペースト・ペーストしてスタイルを合わせる・削除・すべてを選択。ウインドウ: 閉じる ⌘W・しまう ⌘M。設定のウインドウは ⌘W のために閉じられるウインドウにしておく
- ⌘Q は、Nonet のウインドウが前面のときは Nonet を終了する。ほかのアプリが前面のまま結果のパネルをクリックしてキーにしたときの ⌘Q は、パネルだけを閉じる（メニューバーは前面のアプリのものなので、Nonet を終わらせない）
- Nonet の最後のウインドウ（設定・初回の案内）を閉じたら、その前に使っていたアプリを前面に戻す（Nonet が前面のままキーのウインドウが無いと、キー入力のマスのキーが Nonet に送られ、どこにも届かない）

### HUD（ui-shell）
- モックどおり: 黒い角丸のパネルに 3×3、ハイライトは白地に黒。上にプロファイル名と案内（「⌘を離して実行」）、ページが複数なら点で位置を示す
- 前面アプリからフォーカスを奪わない非アクティブなパネル。全 Space・フルスクリーンの上にも出す。表示先はカーソルのあるディスプレイ
- トーストは画面下部に 0.8 秒（失敗は少し長く）
- 結果のパネル（`showResult`）: AI の結果など。文を選択でき、「コピー」「閉じる」と Esc で閉じる。前面アプリのフォーカスは奪わない

### ライセンス（keys-license）
- 試用は初回起動から14日。残り日数は日付の切り上げ
- キーは `base64url(JSON).base64url(署名)`。JSON は `LicenseInfo`。公開鍵は Info.plist の `NonetLicensePublicKey`
- `nonet-license keygen` で鍵を作り、秘密鍵はリポジトリの外に置く。`issue` は発行したキーを `Config/Nonet.xcconfig` の `NONET_LICENSE_PUBLIC_KEY`（アプリに入る公開鍵。`//` で切れていれば止まる）と秘密鍵の隣の公開鍵（または `--public`）で検証してから出す。`--public` がアプリの公開鍵と違えば、`--skip-app-key-check` が無い限り出さない
- 貼り付けたキーは、空白・改行を除いた全体が `eyJ` で始まるキーの形ならそれを使う。そうでなければ前後の文（「License key:」「License Key」（改行）・引用符・メールの「>」・句点など）を除いて、キーの形（`eyJ…` と 86 文字の署名）の部分を探し、中身が `LicenseInfo` として読めるものがちょうど1種類あるとき（読めるものが無ければ、キーの形のものがちょうど1種類あるとき）だけそれを使う（`LicenseCoding.licenseKey(in:)`）。保存するのはキーの部分だけ
- 試用は使った時間を数える（時計を戻しても増えない）。`canExecuteActions` はいつでも正しいが、表示用の `entitlement` は `refresh()` でしか変わらない。`NonetController` はトリガーを押した後（60秒に1回まで。ライセンスがあれば呼ばない。§5）、ui-shell はメニューを開いたとき・スリープ解除・日付の変化・時計の変更で `refresh()` を呼ぶ。ライセンスが登録されているときの `refresh()` は、試用の記録を書かない
- 試用の記録（開始日・最後に数えた時刻・使った時間）は `UserDefaultsLicenseStorage` が UserDefaults と `Application Support/Nonet/` の隠しファイルに置き、アプリ本体（`UserDefaultsLicenseStorage(keychain: SystemTrialRecordKeychain())`）では `SystemTrialRecordKeychain`（ログインキーチェーンの汎用パスワード `com.iam74k4.Nonet.license.trial`。Developer ID で署名した製品版でだけ動く）にも置く。キーチェーンは起動ごとに1回読み、ほかの2か所の両方に (時刻, 使った時間) の組が無ければその組で、あれば使った時間だけを下限として数える。書くのは起動したとき・使った時間が1時間増えたとき・時計が変わったとき（`didSaveTrialProgress`・`needsKeychainWrite`）。`--self-check` と Debug の `--config-dir` はキーチェーンを使わない
- NonetCore は Foundation と Observation だけ（§2）だが、`Licensing/TrialRecordKeychain.swift` だけは例外として Security と LocalAuthentication を使う（キーチェーンの読み書きと、署名の身元の確認。`TrialRecordKeychain` の protocol で差し替えられ、テストでは本物のキーチェーンに触れない）。ライセンスのロジックと同じ場所に置き、App が1行で使えるようにするため
- 置き場所の記録が食い違ったら `TrialRecord.reconciled` でまとめる: 開始日は最も早いもの、(最後に数えた時刻, 使った時間) は置き場所ごとの組として、次に数えたときに最も多くなる組 (U, V + U)（U = 使った時間の最大、V = 時刻 − 使った時間 の最小）にする。古い記録（バックアップから戻したフォルダ・書けないファイル）で同じ時間を二重に数えず、1か所だけ書き換えても延びず、時計を戻しても減らない
- 動いている間に、保存先の使った時間が自分の数えた量より多くなっていたら（ほかの Nonet が数えた）、自分の数え方（自分の使った時間 ＋ 前に数えてからの経過）と保存先の数え方（保存先の使った時間 ＋ 保存先の最後に数えた時刻からの経過）の多い方を取る。使った時間を最も多く残し、同じ経過を二重には数えない（保存先の量に自分の経過を足さない）

### 起動オプション（App/main.swift・`ShellLaunchOptions`）
- `--self-check`（すべてのビルド）: 画面もイベントタップも作らずに、プリセット・ランチャーの候補・設定の保存と読み直し・MultitouchSupport の読み込みを確かめ、JSON を出して終わる（失敗なら終了コード 1）。試用の記録は UserDefaults と Application Support の写し（`.install`・`.install-seen`・`.install-used`）の両方から読むだけで（`ShellSelfCheck.LicenseSnapshot`）、アプリと同じく試用に厳しい方を使うので、アプリと同じライセンスの状態を出す。試用を始めたり、数えたり、記録をそろえたり書いたりはしない（キーチェーンも使わない）。`scripts/test.sh` が最後に動かす
- Debug ビルドだけ: `--config-dir <dir>`（設定をそのフォルダに置き、ライセンスはメモリだけに置く。下の「同時に1つだけ」も調べないので、インストールした Nonet と並べて動かせる）・`--show-settings [tab]`・`--show-onboarding`・`--preview-hud`・`--preview-toast`・`--preview-result`・`--simulate-expired-trial`・`--snapshot <dir>`（開いたウインドウを画像に書き出して終わる）。画面の確認用

### 起動の順と、同時に1つだけ（App/main.swift・App/SingleInstance.swift・`ShellInstanceGuard`）
同じ Nonet が2つ動くと、どちらもトリガーキーとトラックパッドを見て1回のタップでマスが2回実行され、試用の時間も2倍に数えられる。
- `main.swift` は `--self-check` を見た後、NSApplication を動かす前に `SingleInstance` で同じ bundle ID の Nonet を調べる
- どのプロセスから見ても同じ順で、残す1つを決める: 本来の場所のもの（ディスクイメージや App Translocation でないもの）→ 起動し終えたもの → 先に開かれたもの → プロセス番号の小さいもの
- 残すのがほかのものなら、終わりかけ（Sparkle のアップデートの後の再起動など）かもしれないので最長3秒（`shutdownGrace`）待ち、それでも動いていれば任せて終わる。相手が起動し終えていれば開き直し、相手の `applicationShouldHandleReopen` が設定を開く
- 残すのが自分（アプリケーションフォルダなど）で、ディスクイメージなどから開いた Nonet が動いていれば、それに終わってもらってから代わりに動く。10秒（`takeOverTimeout`）たっても終わらなければ、こちらが譲る
- 同時に2つ開かれても、残るのはちょうど1つ

### アプリケーションフォルダへ移す（`ShellMoveToApplications`）
- App Translocation か読み取り専用のディスクイメージから開かれたら（Sparkle がアップデートを入れない場合と同じ）、`AppDelegate` が「Nonet をアプリケーションフォルダに移しますか？」と尋ねる。移す先は `/Applications`、そこに書き込めなければ（管理者でない）`~/Applications`。どちらにも書き込めなければ、尋ねずに Finder でドラッグする方法を伝える
- 移す先にすでに Nonet があれば、置き換えてよいか確かめてから、古い方をゴミ箱に入れる。最後の入れ替えに失敗したら、ゴミ箱から元の場所に戻す
- 同じフォルダの隠した一時的な名前に写し、写しから `com.apple.quarantine` を外し（Finder で移したときと同じ。外さないと、移した先でまた App Translocation で開かれる）、入れ替える。写すのに失敗したら、写しかけのものも残さない
- 入れ替えたら、このプロセスが終わるのを待ってから移した先を開くよう頼み、自分は終わる

## 7. 実機で確かめられていないこと

フェーズ0の検証アプリでは手動テストが終わっていない。次の点は設定で切り替えられるようにし、既定値は安全側にする。
- カーソルの固定: 移動イベントを捨てて止まるか → `CursorLockMethod` で方式を選べる。既定の automatic は捨てたうえでずれたら戻す
- 触覚: 別アプリが前面のとき `NSHapticFeedbackManager` が効くか → MTActuator を優先し、失敗したら公開 API
- 2本指スワイプが前面アプリ（Safari の戻るなど）に届かないか → セッション中はジェスチャー系のイベントも捨てる
- 「タップでクリック」のクリック（mouseDown）と、MultitouchSupport の指が離れたフレームのどちらが先に届くか（手動テスト T5 で、CGEvent / NSEvent のタイムスタンプを指のフレームと並べてログに出す）。0.2秒の猶予（`clickGraceInterval`）と 0.5秒の `lateClickWindow` で足りるか。本物の HID のイベントで CGEvent のタイムスタンプの単位が何か。タップが捨てた「押す」が `hidSystemState` のボタンの状態に表れるか（表れないと、捨てたボタンを忘れる見直しが早すぎたり遅すぎたりする）

- 角の長押し（§5）: 角の範囲（0.12 × 0.18）・0.4秒・動きの許容 0.02 で、ふだんの操作で誤って出ず、狙えばすぐに出るか。長押しの間、macOS が指をクリックやドラッグとして扱わないか

手動で確かめること（トラックパッドの開始し直し。§5「トラックパッド」）: スリープと復帰、外部ディスプレイをつないだまま蓋を閉じて開く、Magic Trackpad を外してつなぎ直す、ファストユーザスイッチ。どれも起動し直さずにトラックパッドが使え続けるか、ログの「トラックパッド（…）: N 台を開始」と開始し直しの記録を見る
