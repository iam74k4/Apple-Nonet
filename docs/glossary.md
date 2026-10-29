# 英語用語集

このファイルは Nonet の英語版の用語集で、翻訳する人のための訳語の基準です。アプリの文字列カタログ（`Localizable.xcstrings`）、設定画面、利用ガイド、販売サイト（`site/en/`）を英語にするときは、ここにある訳語をそのまま使ってください。macOS に Apple 自身の用語があるもの（システム設定、アクセシビリティ、ショートカット、Open at Login など）はそれに合わせました。公開済みの英語サイトの言い回しとも食い違わないようにしています。大文字・小文字の使い分けも Apple に合わせます。ウインドウ名、メニュー項目、ボタン、ポップアップの選択肢、タブ名は Title Case にします（例: Check for Updates…、Key Release）。設定の項目名、チェックボックス、説明文、メッセージは、文頭だけを大文字にする sentence case にします（例: Open at login）。販売サイトの見出しは今のまま sentence case です。新しい用語が必要になったら、訳す前にこの表へ追加してください。

| Japanese | English | Note |
|---|---|---|
| Nonet | Nonet | Product name. Never translate, never all caps. |
| トリガーキー | trigger key | Lowercase in prose ("hold the trigger key"). The settings label is "Trigger key". "trigger" alone is fine where space is tight. The site already uses this term. Do not use "hotkey" or "activation key". |
| 右⌘ / 右⌥ / 右⇧ / fn | right ⌘ / right ⌥ / right ⇧ / fn | In prose, follow the site ("Hold right ⌥"; capitalized only at the start of a sentence). In pop-up options, use "Right Command (⌘)", "Right Option (⌥)", "Right Shift (⇧)" and "fn". Keep "fn" lowercase as printed on the key. Docs may add "(Globe)" because newer keyboards label the key 🌐. |
| トリガーキーを押す / 押している間 / 離す | press / hold / release | "Press" is the moment the key goes down, "hold" means keeping it down, and "release" means letting go. Site: "Hold right ⌥", "Release ⌥ to run". |
| 修飾キー | modifier key | Apple term. |
| マス | button | Use "button" everywhere users see it: the app, the guide and the site. The site's visible English copy already uses "button" throughout: the title "nine buttons for every app", "Slide to a button", "drag it onto an empty button", "buttons no longer run" in the FAQ, and "profiles, buttons, actions" in the privacy policy. The Japanese site and guide also say 9つのボタン. "cell" and "tile" appear only as HTML/CSS class names in the site's demo and illustrations, and in code such as `CellIconView`. Users never see them, so they can stay as code names. "cell" reads like a spreadsheet cell and "tile" like a passive decoration. "button" tells people they press it and something runs. To avoid confusing it with push buttons in the Settings window, docs refer to on-screen controls by their label ("click Add Profile"), not as "the … button". |
| 9マス / 9つのボタン | the nine buttons; 3×3 grid | Spell out "nine" for the set (site). Use "grid" only for the layout itself ("split into a 3×3 grid"). Always use × (U+00D7), never x. |
| 空きマス | empty button | Site: "an empty button". Do not use "blank" or "unassigned". |
| マスの境界 | edge (between buttons) | Site: "A tick at every edge", "crosses into another button". |
| HUD | HUD | Keep the acronym and write "the HUD". Do not expand it in the UI. The user guide may explain it once: "the HUD, an overlay that shows all nine buttons". Do not use "heads-up display", "overlay" or "palette" as its name. |
| ハイライト / 白く光る | highlight / highlighted | "The button under your finger is highlighted." Do not use "glow" or "light up". |
| 速押し | quick tap | Pressing the trigger key and tapping within the HUD delay runs the button right away without the HUD. The site describes it ("press and tap", "run without looking"). The app and guide use "quick tap" as the noun. Do not use "fast press" or "flick". |
| 実行する | run | Site: "It runs right away", "buttons no longer run". Use "run" for buttons, actions, scripts and shortcuts. Avoid "execute" and "fire". Do not use "trigger" as a verb, because the word belongs to the trigger key. |
| 実行のタイミング | Run on | Settings label. Its options are the next two rows. In prose: "set **Run on** to **Finger Lift**". |
| キーを離したとき | Key Release | The default option of Run on (`onTriggerRelease`). In prose: "when you release the trigger key". |
| 指を離したとき | Finger Lift | Option of Run on (`onFingerLift`). In prose: "when you lift your finger". |
| 指を置く / 置いたまま止める | rest your finger | Site: "Rest your finger and the HUD appears". |
| 指を滑らせる | slide | Site: "Slide to a button". |
| タップ / マスを押す | tap | "tap a button". Do not use "click" or "press" for trackpad buttons. |
| 指を離す | lift your finger | |
| やめる（キャンセル） | cancel | "To cancel, …". The button label is "Cancel". |
| 2本指で左右にスワイプ | swipe left or right with two fingers | Site wording. The noun is "two-finger swipe". |
| ページ | page | "up to three pages (27 buttons)", "the next page of nine". |
| HUD の下の点 | page dots | The dots under the HUD that show the current page. |
| プロファイル | profile | Site: "A profile for each app". |
| アプリのプロファイル | app profile | "the Xcode profile". |
| グローバル | Global | Proper name of the profile that applies to every app, so it is capitalized: "the Global profile", "Global pages". Apple's "All Applications" (Keyboard › App Shortcuts) was considered, but it doesn't work in compound labels. Do not use "Default" or "Universal". |
| プリセット | preset | Use "preset" in the app and guide. The site's marketing may say "ready-made layout". |
| ランチャー | launcher | Common noun, lowercase. Site: "a launcher filled with apps from your Mac, a handy stand-in for Launchpad". Launchpad is an Apple trademark and no longer exists in macOS 26. |
| 前面のアプリ | front app | Site: "the front app", "the app in front". "frontmost app" is Apple's developer term; keep it out of the UI. Do not use "active app", "foreground app" or "current app". |
| 起動中のアプリ | running app | Site: "a running app". |
| インストール済みのアプリ | installed apps | |
| アプリ | app | Apple's user-facing word. Use "Applications" only for the folder name. |
| 起動する / 開く（アプリを） | open | Apple prefers "open" to "launch" in user-facing text. The action is "Open App" and the setting is "Open at login". |
| 前面のときは隠す | Hide if already in front | Checkbox for the Open App action. |
| アクション | action | "seven kinds of actions" (site). |
| アクションの種類 | Action type | Inspector label. |
| キー入力 | Keystrokes | Action type (site). In prose: "send keystrokes". The plural is deliberate because one action can send a key sequence. |
| 続けて押すキー | sequence | Site: "a sequence like ⌘L then ⌘C". Display it as "⌘L → ⌘C". |
| 記録する / 記録欄 | record / shortcut recorder | The field shows "Record Shortcut" and changes to "Type Shortcut" while recording. |
| キー配列 / JIS 配列 | keyboard layout / JIS keyboard | Site: "JIS keyboards", "any keyboard layout". |
| アプリを開く | Open App | Action type. The site uses sentence case ("Open app"), following its own style. |
| URL | URL | Action type. |
| スクリプト | Script | Action type; "zsh script" in prose. |
| 実行の仕方: 裏で実行 / ターミナルで実行 | Run: In Background / In Terminal | Script options. In prose: "run in the background", "run in Terminal". |
| 制限時間 | Timeout | "Timeout: 60 s". |
| 作業フォルダ | working directory | Standard shell term, which script users already know. |
| プロジェクトのフォルダ | project folder | Site: "its project folder". |
| 書類 | document | Apple term: "the document open in the front window". |
| 環境変数 | environment variable | |
| 終了コード | exit code | "Script failed (exit code %d)". |
| エラー出力 | standard error | "the last lines of standard error". |
| ショートカット（ショートカット.app） | the Shortcuts app; a shortcut | Apple calls the app "Shortcuts" and an item in it "a shortcut", lowercase. The action type is "Shortcut". Do not write "Shortcuts.app" in UI text. |
| ショートカット（キーの組み合わせ） | keyboard shortcut | Always write "keyboard shortcut" when the text means a key combination, so it is not confused with Shortcuts items. The site's marketing ("no shortcuts to memorize") is fine as is. |
| 選択中のテキストを渡す | Pass selected text as input | Checkbox for the Shortcut action. |
| メニュー項目 | Menu Item / menu item | Apple term. Title Case as an action type. Use Apple's verb in prose: "choose a menu item". |
| メニューから割り当てる | Pick from Menus | Button and sheet title. Site: "Pick from the menus". The search field placeholder is "Search menus" (site). |
| 割り当てる | assign | "assign it to an empty button". |
| AI | AI | Action type. Use "Apple Intelligence" for the system feature. AI actions run on "the on-device language model" (privacy policy). |
| 指示文 | prompt | Field label "Prompt". |
| 結果の出し方 | Output | Label for the AI action's result options. |
| 選択範囲を置き換える | Replace Selection | Output option. |
| クリップボードにコピー | Copy to Clipboard | Output option. Same wording as the Shortcuts action. |
| 結果を表示 / 画面に表示 | Show Result | Output option. It opens the "result panel", which has Copy and Close buttons. |
| 結果のパネル | result panel | |
| 選択中のテキスト | selected text | Apple term. Error text: "Select some text first." |
| 選択範囲 | selection | |
| クリップボード | clipboard | Lowercase in prose. |
| Mac の中の言語モデル | on-device language model | Privacy policy wording. |
| Apple Intelligence | Apple Intelligence | Apple trademark. Never write "Apple AI". |
| 設定 / 設定… | Settings / Settings… | macOS 13 and later. Never "Preferences". The window title is "Nonet Settings". |
| 一般 | General | Settings pane. |
| サイドバー | sidebar | |
| インスペクタ | inspector | Apple term (Xcode, Pages). |
| 表示名 | Name | Inspector field: the text shown under the icon. |
| アイコン（SF Symbols / アプリのアイコン / 1〜2文字） | Icon: Symbol / App Icon / Text | Icon sources. Mention "SF Symbols" only when naming Apple's library. 1〜2文字 is "1–2 characters". |
| プロファイルを追加 | Add Profile… | Ends with an ellipsis because an app must be chosen next. |
| 複製 / 削除 / 無効化 / 空にする | Duplicate / Delete / Disable / Clear | Context menu commands for profiles and buttons. |
| このマスをテスト実行 | Test This Button | Context menu command. In prose: "test run". |
| 並べ替え / 入れ替え | reorder / swap | "Drag to reorder", "drag to swap buttons". |
| 右クリック | Control-click | Apple docs style: "Control-click (or right-click)". |
| Nonet を有効にする | Enable Nonet | Settings checkbox, and a menu bar menu item with a checkmark. |
| HUD が出るまでの時間 | HUD delay | Settings label. Value "0.3 s", range "0.15–0.8 s". Taps faster than this count as quick taps. |
| HUD の位置 | HUD position | Options: "Center of Screen" / "Near Pointer". |
| 前面のアプリで切り替える | Switch profiles with the front app | Settings checkbox. |
| グローバルのページをつなげる | Add Global pages after app pages | Settings checkbox. |
| 触覚 | Haptic feedback | Apple term. Settings label with options "Off / Light / Medium / Strong". Not "Firm", which Apple uses for trackpad click pressure. Prose can describe the feeling as "a light tick". Avoid "vibration" in the UI. |
| トリガーキーを前面のアプリに渡す | Pass the trigger key to the front app | Settings checkbox. |
| 実行を知らせる | Show a notice when a button runs | Settings checkbox. The notice is the short label at the bottom of the screen. |
| カーソル | pointer | Apple calls the mouse arrow the "pointer", and the site does too ("the pointer stays put"). Use "cursor" only for a text insertion point. |
| カーソルの固定方法（詳細） | Pointer lock method (Advanced) | Options: "Automatic" / "Discard Movement" / "Detach Pointer" / "Off". |
| ログイン時に起動 | Open at login | Apple's wording (Dock menu and Login Items). Sentence case because it is a checkbox. |
| ログイン項目 | Login Items | System Settings › General › Login Items on macOS 14; the pane is "Login Items & Extensions" on macOS 15 and later. |
| プロファイルの書き出し / 読み込み | Export Profiles… / Import Profiles… | "a .nonetprofile file". |
| ライセンス | License | Settings pane and menu item. US spelling, never "licence". |
| 情報 | About | Settings pane. |
| 利用ガイド | User Guide | |
| お問い合わせ | Contact | Site footer. |
| 試用 / 試用期間 | trial / free trial | Site: "14-day free trial", "When the trial ends". Do not use "evaluation" or "demo". |
| 試用期間が終了しました | Your trial has ended | Exact site wording (FAQ). |
| 試用の残り日数 | days left in your trial | "%lld days left in your trial". Use xcstrings plural variants ("1 day left"). |
| ライセンスキー | license key | Site: "Enter a license key". |
| 登録 / 登録者 | Register / Registered to | Entering a valid key registers your copy. The button is "Register" and the status reads `Registered to <name>`. Do not use "Activate", because that suggests online activation and keys are checked offline. |
| 購入する / 購入ページ | Buy Nonet / purchase page | Site button and privacy policy wording. |
| 買い切り | one-time purchase | Site. |
| メニューバー / メニューバーのアイコン | menu bar / menu bar icon | Apple term. |
| プロファイルを編集… | Edit Profiles… | Menu bar menu item. |
| 「Xcode のプロファイル」（メニューの状態） | Xcode profile | Status line in the menu bar menu. |
| 初回の案内 / 初回の案内をもう一度 | welcome guide / Show Welcome Guide | Menu item without an ellipsis, because it only opens a window. |
| アプリを選ぶ / あとで設定する / 試してみる | Choose Apps / Set Up Later / Try It Out | Onboarding steps and buttons. Apple uses "choose" for user decisions and "select" for text or list items. |
| 練習モード | practice mode | "Nothing runs in practice mode." |
| アップデート / アップデートを確認 | update / Check for Updates… | Sparkle's standard menu item. |
| 終了 | Quit Nonet | Apple's `Quit <App>` pattern. |
| 「⌘を離して実行」（HUD の案内） | Release ⌘ to run | Site wording. |
| アクセシビリティ | Accessibility | Name of the System Settings pane, so it is capitalized: "Accessibility permission". |
| オートメーション | Automation | Same rule: "Automation permission". |
| 許可 / 許可する | permission / allow | "Nonet needs Accessibility permission", "allow Nonet". The status reads "Accessibility permission required", and the error is "%@ permission required". |
| システム設定 | System Settings | Never "System Preferences". Path style: "System Settings › Privacy & Security › Accessibility" (› as on the site). |
| システム設定を開く | Open System Settings | Apple's own button wording. |
| プライバシーとセキュリティ | Privacy & Security | |
| Apple Intelligence と Siri | Apple Intelligence & Siri | System Settings pane. |
| セキュアキーボード入力 | Secure Keyboard Entry | Terminal menu item. |
| ターミナル | Terminal | The app's name, capitalized. |
| トラックパッド / マルチタッチ | trackpad / multi-touch | "Magic Trackpad" is an Apple trademark. |
| 感圧タッチ | Force Touch trackpad | |
| Apple シリコン | Apple silicon | Lowercase s (Apple style). |
| ゴミ箱 / アプリケーションフォルダ / ホームフォルダ | Trash / Applications folder / home folder | Finder terms. |
| セッション | (internal only) | Code term for the time from pressing to releasing the trigger key. Do not show it to users. |
| トースト | notice | "toast" is the internal name; users see "notice". |
| 〜できませんでした | Couldn't … | Apple style uses contractions: "Couldn't open %@". |
| 〜が見つかりません | Can't find … | "Can't find the menu item “%@”". |
| 〜してください | imperative, no "please" | "Select some text first." Apple style avoids "please". |
| 〜など%lld個（プリセットの説明） | %lld buttons, including … | "%lld buttons, including Build, Test and Claude Code". Use plural variants. |
| プリセットのボタン名 | the target app's own English wording | Take preset names from the target app's English menus (Xcode "Build", "Test"; Zoom "Mute"). |
| 「」 / … / 〜 / 秒 | “ ” / … (U+2026) / – (en dash) / s | Curly quotes, the single ellipsis character, an en dash for ranges, and a space before units: "0.15–0.8 s", "60 s". Spell out "seconds" in running prose. Menu paths: "Nonet › Settings…". |
