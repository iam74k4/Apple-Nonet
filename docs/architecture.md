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
Config/Nonet.xcconfig       販売用の値（購入 URL・公開鍵・appcast）
App/                        アプリ本体。組み立てだけ（AppDelegate・Sparkle）
Packages/NonetKit/          それ以外すべて（swift build / swift test で動く）
  Sources/
    NonetCore/              純粋なロジック（Foundation と Observation だけ。AppKit 禁止）。Swift 6 言語モード
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
| release | `scripts/`（make-icon 以外）・`docs/release.md`・`docs/user-guide.md`・`docs/privacy.md`・`site/`・`.github/` |

- **契約**: 各ファイル冒頭に「契約」とあるものと、担当ファイルの公開 API（型名・プロパティ・メソッドのシグネチャ）は変えない。追加はしてよいが、報告する
- `Package.swift`・`project.yml`・`Services.swift`・`HUDModel.swift`・`LiveServices.swift`・`Common/`・`Localizable.xcstrings`・`Placeholder.swift` は統合担当だけが変える。変えてほしいときは報告する
- ほかの担当の未実装部分（`fatalError("未実装: …")`）を呼ぶコードを書いてよい。統合後に動く。ただし自分のテストはそれに頼らない

## 4. 共通の決まり

- コメントと画面の文言は日本語。英語は後でローカライズする
- 画面に出る文字列は必ずローカライズ可能にする: `String(localized: "…", bundle: .module)`、SwiftUI は `Text("…", bundle: .module)`。`Localizable.xcstrings` は編集しない（統合時に抽出する）
- ログは `os.Logger(subsystem: "com.iam74k4.Nonet", category: "<担当>")`。キー入力の中身やテキストはログに残さない
- UI とサービスはメインアクター。重い処理（スクリプト・AI・`shortcuts`）は `async` でメインスレッドを止めない
- 失敗は `NonetError` で返す（`errorDescription` がそのままトーストに出る）
- 本番コードで強制アンラップ・`try!`・`fatalError` を使わない（契約のスタブを置き換えた後）
- テストは Swift Testing（`import Testing`・`@Test`・`#expect`）。`Packages/NonetKit` で `swift build` と `swift test` が通ること
- 文体はまわりのコードに合わせる。コメントは「なぜ」が必要なところだけ

## 5. 操作の仕様（セッション）

トリガーキーを押してから離すまでを「セッション」と呼ぶ。`SessionEngine`（純粋なロジック）がこの仕様を持ち、`NonetController` が入出力をつなぐ。

1. **開始**: トリガーキーが単独で押された（ほかの修飾キーが押されていない）ら開始する。Nonet が無効・トラックパッドが無い・設定ウィンドウでキー記録中なら開始しない。開始と同時にポインタの抑止を始め、前面アプリのページの並び（`resolvedPages`）を決め、最初のページを使う
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

## 6. 機能の仕様

### プロファイルとページ
- グローバルが必ず1つ（先頭）。アプリのプロファイルは bundleID ごとに1つまで。各プロファイル 1〜3 ページ
- `resolvedPages(frontmostBundleID:)`: `autoSwitchProfiles` が true で、そのアプリの有効なプロファイルがあれば、そのページ。`appendGlobalPages` なら後ろにグローバルのページをつなげる。プロファイルが無ければグローバルのページだけ
- グローバルの初期値はランチャー: `PresetLibrary.launcherCandidates` のうちインストール済みのアプリを最大9個（起動アクション、アイコンはアプリ）。macOS 26 で Launchpad が無くなったので、その代わりになる

### アクション
| 種類 | 動き |
|---|---|
| キー入力 | 前面アプリに送る。`.character` は現在のキー配列で仮想キーコードを探す（JIS でも ⌘[ などが正しく届く）。修飾キーはイベントのフラグに明示し、押しっぱなしのトリガーキーが混ざらないようにする。連続キーは 40ms 間隔 |
| アプリ起動 | 起動中なら前面へ、無ければ起動。`hideIfFrontmost` なら前面のとき隠す |
| URL | 既定のアプリで開く。スキームが無ければ https を付ける |
| スクリプト | `/bin/zsh -l -c`。`ScriptEnvironment` の環境変数を渡し、作業フォルダはプロジェクトのフォルダ（無ければホーム）。background は制限時間で打ち切り、失敗したら標準エラーの末尾をトーストに出す。terminal はターミナルの新しいウィンドウで実行（一時的な .command ファイルを開く） |
| ショートカット | `/usr/bin/shortcuts run <名前>`。`passSelectedText` なら選択中のテキストを入力に渡す |
| メニュー項目 | 対象アプリが前面で `keyEquivalent` があればキーを送る。無ければアクセシビリティ API でメニューをパスどおりにたどって押す |
| AI | macOS 26 以降で Apple Intelligence が使えるときだけ。選択中のテキストと指示文を端末内の言語モデル（FoundationModels）に渡し、出力先に従う。使えなければ `NonetError.unavailable` |

選択中のテキストはアクセシビリティ API（`kAXSelectedTextAttribute`）で取り、取れなければ ⌘C でクリップボード経由（クリップボードは元に戻す）。書類の場所は前面ウィンドウの `kAXDocumentAttribute`、ブラウザの URL は Safari / Chrome / Arc / Edge / Brave に AppleScript で聞く。

### 権限
- アクセシビリティ: イベントタップ（トリガーの検出・ポインタの抑止）、キー送出、メニュー操作、選択テキストの取得に必要
- 指の位置の取得には権限が要らない（検証済み）
- オートメーション: ブラウザの URL 取得とターミナル実行のときに、macOS が初回に確認する
- 許可されていなければ `status = .needsAccessibility`。2秒ごとに確かめ、許可されたら自動で動き出す

### 設定画面（ui-settings）
- サイドバー: グローバル・アプリのプロファイル（アイコン付き、並べ替え・削除・無効化）・「プロファイルを追加」（インストール済みアプリから選ぶ。プリセットがあれば中身を入れる）
- 中央: ページの切り替え（最大3）と 3×3 のグリッド。クリックで選択、ドラッグで入れ替え、Delete で空に、右クリックで複製・削除・テスト実行
- 右: インスペクタ。表示名・アイコン（SF Symbols の候補・アプリ・文字）・アクションの種類と中身。キー入力は記録欄（押したキーをそのまま記録）。アプリは一覧から選ぶ。ショートカットは名前の一覧から選ぶ
- メニューから割り当て: 起動中アプリのメニューを読み、検索して、空きマスへドラッグ（またはダブルクリック）
- 「このマスをテスト実行」
- 全体の設定: 有効化・トリガーキー（JIS で右⌥を選ぶと警告）・実行タイミング・HUD の待ち時間・HUD の位置・触覚・グローバルのページをつなげる・トリガーキーを前面アプリに渡す・実行を知らせる・カーソルの固定方法（詳細）・ログイン時に起動・プロファイルの書き出し / 読み込み
- ライセンス: 状態（試用の残り日数 / 登録者）・キーの入力・購入ページ
- 情報: バージョン・アップデートの確認・利用ガイド・プライバシー

### 初回起動（ui-shell）
1. ようこそ＋アクセシビリティの許可（許可されたら自動で次へ）
2. アプリを選ぶ: インストール済みでプリセットのあるアプリを並べ、選ぶ（モックのボード「初回起動」）。「あとで設定する」もある
3. 試してみる: 練習モードで、トリガー＋タップを案内どおりにやってもらう（「右⌘を押しながら右上をタップ」→ 成功表示）
4. 完了

### メニューバー（ui-shell）
- 3×3 のアイコン（中央が塗り）。無効・権限なし・試用終了で見た目を変える
- メニュー: 状態（例: 「Xcode のプロファイル」「アクセシビリティの許可が必要です」）・有効にする・設定…・プロファイルを編集…・初回の案内をもう一度・ライセンス（試用の残り日数）・アップデートを確認・終了

### HUD（ui-shell）
- モックどおり: 黒い角丸のパネルに 3×3、ハイライトは白地に黒。上にプロファイル名と案内（「⌘を離して実行」）、ページが複数なら点で位置を示す
- 前面アプリからフォーカスを奪わない非アクティブなパネル。全 Space・フルスクリーンの上にも出す。表示先はカーソルのあるディスプレイ
- トーストは画面下部に 0.8 秒

### ライセンス（keys-license）
- 試用は初回起動から14日。残り日数は日付の切り上げ
- キーは `base64url(JSON).base64url(署名)`。JSON は `LicenseInfo`。公開鍵は Info.plist の `NonetLicensePublicKey`
- `nonet-license keygen` で鍵を作り、秘密鍵はリポジトリの外に置く

## 7. 実機で確かめられていないこと

フェーズ0の検証アプリでは手動テストが終わっていない。次の点は設定で切り替えられるようにし、既定値は安全側にする。
- カーソルの固定: 移動イベントを捨てて止まるか → `CursorLockMethod` で方式を選べる。既定の automatic は捨てたうえでずれたら戻す
- 触覚: 別アプリが前面のとき `NSHapticFeedbackManager` が効くか → MTActuator を優先し、失敗したら公開 API
- 2本指スワイプが前面アプリ（Safari の戻るなど）に届かないか → セッション中はジェスチャー系のイベントも捨てる
