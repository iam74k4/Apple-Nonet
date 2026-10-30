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
| メニューから割り当てる | Pick from Menus | Button and sheet title. Site: "Pick from the menus". The search field placeholder is "Search menus" (site). The Menu Item editor's button メニューから選ぶ… is also "Pick from Menus", without an ellipsis, because it opens the same panel. |
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
| プロファイルを追加 | Add Profile… | Ends with an ellipsis because an app must be chosen next. The sheet it opens is titled "Add Profile", without an ellipsis (its own key, `settings.addProfileSheet.title`). |
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
| カーソルの固定方法 | Pointer lock method | Setting label under the Advanced (詳細) section header, so the label itself has no "(Advanced)". Options: "Automatic" / "Discard Movement" / "Detach Pointer" / "Off". |
| ログイン時に起動 | Open at login | Apple's wording (Dock menu and Login Items). Sentence case because it is a checkbox. |
| ログイン項目 | Login Items | System Settings › General › Login Items on macOS 14; the pane is "Login Items & Extensions" on macOS 15 and later. |
| プロファイルの書き出し / 読み込み | Export or import profiles | Setting label in General, next to the push buttons "Export…" and "Import…". The save and open panels are titled "Export Profiles" and "Import Profiles". The file is "a .nonetprofile file". |
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
| Nonet のメニュー | the Nonet menu | The menu that opens from the menu bar icon. The user guide uses this name: "choose Settings… from the Nonet menu". |
| プロファイルを編集… | Edit Profiles… | Menu bar menu item. |
| 「Xcode のプロファイル」（メニューの状態） | Xcode profile | Status line in the menu bar menu. |
| 初回の案内 / 初回の案内をもう一度 | welcome guide / Show Welcome Guide | Menu item without an ellipsis, because it only opens a window. |
| アプリを選ぶ / あとで設定する / 試してみる | Choose Apps / Set Up Later / Try It Out | Onboarding steps and buttons. Apple uses "choose" for user decisions and "select" for text or list items. |
| 練習モード | practice mode | "Nothing runs in practice mode." |
| アップデート / アップデートを確認 | update / Check for Updates… | Sparkle's standard menu item. |
| アップデートがあります… | Update Available… | Replaces Check for Updates… in the Nonet menu when a scheduled check has found an update. Title Case and an ellipsis, because it opens Sparkle's update window. |
| 終了 | Quit Nonet | Apple's `Quit <App>` pattern. |
| Nonet について | About Nonet | App menu item of the hidden main menu. It opens the About tab of Settings. |
| 取り消す / やり直す / カット / コピー / ペースト / ペーストしてスタイルを合わせる / 削除 / すべてを選択 | Undo / Redo / Cut / Copy / Paste / Paste and Match Style / Delete / Select All | Edit menu of the hidden main menu. These are Apple's standard item names. The menu itself is "Edit" (its own key, `menu.edit`, because 編集 is also the symbol group "Editing"). |
| ウインドウ / 閉じる / しまう | Window / Close / Minimize | Window menu of the hidden main menu (⌘W, ⌘M). |
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
| 打鍵 | keystroke | "Adds Esc as a keystroke". The action type is still "Keystrokes". |
| 表記で入力 / キーの表記 | Type keys as text / Keys as text | Placeholder and VoiceOver label of the field where keys are typed as text. The example is in the caption under the field: "For example, ⌘L → ⌘C. …". Apple style avoids "e.g.". |
| 決定（入力欄の横のボタン） / 使う（アイコンの文字） | Apply / Use | Buttons that confirm a typed value. |
| 送るキー / 開くアプリ / 開く URL / 実行するスクリプト / 実行するショートカット / 押すメニュー項目 | Keys to send / App to open / URL to open / Script to run / Shortcut to run / Menu item to choose | Inspector field labels, sentence case. |
| 未設定 / なし（メニューを順にたどって押します） | Not set / None (Nonet opens the menus to choose it) | Values shown when a button or a menu item has nothing set. |
| 登録済み | Registered | License status title and menu bar line. The detail line is "Registered to %@". |
| 登録を解除 / 登録を解除… / この Mac での登録を外す | Unregister / Unregister… / Unregister this Mac | Opposite of Register. Never "Deactivate". Alert title: "Unregister this Mac?". Result: "Your license was removed from this Mac." |
| 発行日 / ライセンス ID / 買い切りのライセンス | Issued / License ID / One-time purchase | License pane labels. |
| 元に戻せません | You can't undo this action. | Apple's wording in confirmation alerts. |
| 許可を求める / もう一度確かめる | Request Permission / Check Again | Buttons in the Settings status banner. |
| トリガーと HUD / 知らせ / 詳細 / 起動 / 書き出しと読み込み / 状態 | Trigger & HUD / Feedback / Advanced / Startup / Export & Import / Status | Settings section headers, Title Case. |
| 新しいプロファイルだけ追加 / 置き換えて読み込む / 読み込む | Add New Profiles Only / Replace and Import / Import | Buttons in the import confirmation alert. "Import" is shown when nothing would be replaced. It has its own key (`settings.import.confirmButton`), because the bare 読み込む is "Load" in the Pick from Menus panel. |
| ・%@ › %@ / スクリプト（%lld行）: / キー入力: %@ / 開くファイル: %@ / …ほか%lld行 | • %1$@ › %2$@ / Script (%lld lines): / Keystrokes: %@ / File to open: %@ / …and %lld more lines | The import confirmation's list of buttons that run something: "• Profile › Button", then the first lines of the script, the keys or the file. Use plural variants for the line counts. |
| 元に戻す（9マスの下） / マスを空にしました | Undo / Cleared the button. | The notice and link under the grid after a button is cleared. After a filled button is replaced with a menu item, the notice is "Replaced the button with the menu item.". |
| マスを空にする / マスの移動 / マスの入れ替え / メニュー項目の割り当て | Clear Button / Move Button / Swap Buttons / Assign Menu Item | Undo action names (`UndoManager.setActionName`) for button edits in Settings. Title Case. |
| 既定（サイドバーのバッジ） | Default | Only the badge next to the Global profile. The profile itself is always named "Global". |
| プリセットあり / 追加済み / 設定済み | Preset / Added / Added | Badges in app lists. 設定済み（無効） is "Added, disabled". |
| 記号 / アプリ / 文字（アイコンの種類） | Symbol / App / Text | Icon picker segments. The アプリ key is shared with the Menu Item editor's row label, so the segment says "App", not "App Icon". The Profiles sidebar header has its own key (`settings.sidebar.appsHeader`) and reads "Apps". |
| 左上 / 上 / 右上 / 左 / 中央 / 右 / 左下 / 下 / 右下 | top left / top / top right / left / center / right / bottom left / bottom / bottom right | Button positions, lowercase. Used inside "Button %lld (%@)" and VoiceOver labels. Before a noun, the four corners use their own keys (`attributivePosition.topLeft` and so on) with U+2011 non-breaking hyphens, so the line doesn't wrap at the hyphen: "That was the bottom‑left button. Try the top‑right corner." |
| 開発 / デザイン / チャット / メール / ブラウザ / 会議 / ドキュメント / ファイル（プリセットの分類） | Development / Design / Chat / Mail / Web Browsing / Video Conferencing / Writing / File Management | Preset categories shown with each app in Choose Apps. Title Case. |
| よく使う / 編集 / 画面と操作 / メディアと連絡 / AI と文章 / 開発（記号の分類） | Common / Editing / Windows & Navigation / Media & Communication / AI & Writing / Development | Symbol groups in the icon picker. 編集 here is "Editing", not the Edit menu. |
| マス %lld（%@） | Button %lld (%@) | Inspector heading and VoiceOver label, e.g. "Button 3 (top right)". An empty one is "%@: empty" in Settings and "Empty button, %@" in the HUD. |
| アクションを追加 / 空いているマスに入れる / このマスを空にする / 既定のアイコンに戻す | Add Action / Add to Empty Button / Clear This Button / Restore Default Icon | Commands, Title Case. |
| アプリを選ぶ…（1つ選ぶ） / 一覧に無いアプリを選ぶ… | Choose App… / Choose Another App… | Singular wherever one app is picked. The bare key アプリを選ぶ is the onboarding step "Choose Apps", but code also uses it for the Pick from Menus app pop-up's placeholder and for the app open panel's title. Those should get their own key, translated "Choose App". |
| 一覧を読み直す / 読み直す / 読み込む / メニューを読み込む / もう一度読む | Reload List / Reload / Load / Load Menus / Try Again | Shortcut list, Pick from Menus panel and their retry buttons. |
| 「ボタン名」を押す（文中で操作を指す） | click <label> | In UI text, name controls by their label without quotes: "Click Add Profile to…", "click Register", "Click Next to continue". |
| 動作中 / 停止しています / パスワード入力中は使えません | Running / Stopped / Unavailable while entering a password | Menu bar status line. |
| この知らせを消す / アクセシビリティを許可… | Dismiss Notice / Allow Accessibility Access… | Menu bar menu items. |
| Nonet（無効） / Nonet（確認が必要） / Nonet（アップデートがあります） | Nonet (disabled) / Nonet (needs attention) / Nonet (update available) | Menu bar icon tooltip and VoiceOver. |
| あとで許可する / 準備ができました / できました！ | Not Now / You're all set / Well done | Onboarding. No exclamation marks. |
| 練習中 · %@ / 指を離して実行 | Practice · %@ / Lift your finger to run | HUD hints. Finger Lift uses the second hint; Key Release uses "Release ⌘ to run". |
| スクリプトで使える環境変数 / スクリプトに渡す環境変数 | Environment variables for scripts / Environment variables passed to scripts | Help button label and popover heading in the Script editor. |
| ほか%lld個 | And %lld more | End of a list in the import confirmation. Use plural variants. |
| ' （アポストロフィ） | ' | Use the straight apostrophe in contractions ("Can't", "doesn't"), as the existing catalogs do. Quoted names use curly quotes: Delete the “%@” profile? Code examples keep straight quotes. |
| ・（箇条書きの頭） | • | Bullet for list lines in alerts: "• %@". |
