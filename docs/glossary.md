# 英語用語集

このファイルは Nonet の英語版の用語集で、翻訳する人のための訳語の基準です。アプリの文字列カタログ（`Localizable.xcstrings`）、設定画面、利用ガイド、販売サイト（`site/en/`）を英語にするときは、ここにある訳語をそのまま使ってください。macOS に Apple 自身の用語があるもの（システム設定、アクセシビリティ、ショートカット、Open at Login など）はそれに合わせました。公開済みの英語サイトの言い回しとも食い違わないようにしています。大文字・小文字の使い分けも Apple に合わせます。ウインドウ名、メニュー項目、ボタン、ポップアップの選択肢、タブ名は Title Case にします（例: Check for Updates…、Center of Screen）。設定の項目名、チェックボックス、説明文、メッセージは、文頭だけを大文字にする sentence case にします（例: Open at login）。販売サイトの見出しは今のまま sentence case です。新しい用語が必要になったら、訳す前にこの表へ追加してください。

| Japanese | English | Note |
|---|---|---|
| Nonet | Nonet | Product name. Never translate, never all caps. |
| 上の縁 | top edge | The top edge of the trackpad, where the nine buttons are opened from. In prose: "the top edge of the trackpad". Do not use "top border" or "top side". |
| 開く動き / 上の縁から開く | slide down from the top edge / Open from the top edge | The only way to open the nine buttons: place one finger on the top edge of the trackpad and slide it straight down. App: "Place a finger on the top edge of the trackpad and slide it down to open the nine buttons.", "Slide a finger down from the top edge of the trackpad to open the HUD". 上の縁から開く is the welcome guide's tip title "Open from the top edge". Internal code calls the gesture the edge slide (`EdgeSlideRecognizer`); users never see that name. Never "swipe down" (a two-finger swipe changes pages), "pull down" or "press". |
| 外枠 | frame | The band around the nine buttons on the trackpad. Lifting your finger there closes the HUD without running anything. App: "Lift in the frame to cancel", "slide out to the frame around the nine buttons". Do not use "border", "edge" (that is the top edge or the line between buttons) or "margin". |
| キーを押す（閉じる） | press a key | Keyboard only. Pressing any key while the nine buttons are open closes them without running anything, and the key still reaches the front app: "Pressing a key also closes them.", "or press any key". |
| 修飾キー | modifier key | Apple term. |
| マス | button | Use "button" everywhere users see it: the app, the guide and the site. The site's visible English copy already uses "button" throughout: the title "nine buttons for every app", "Slide to a button", "drag it onto an empty button", "buttons no longer run" in the FAQ, and "profiles, buttons, actions" in the privacy policy. In Japanese, the app and the guide call the nine cells マス everywhere (menu items, tips, the filter placeholder, Settings); 9つのボタン appears only in the marketing-style welcome line (and on the Japanese site), so マス never competes with real push buttons in Settings. "cell" and "tile" appear only as HTML/CSS class names in the site's demo and illustrations, and in code such as `CellIconView`. Users never see them, so they can stay as code names. "cell" reads like a spreadsheet cell and "tile" like a passive decoration. "button" tells people that choosing it runs something (on the trackpad you lift your finger on it; you never press it). To avoid confusing it with push buttons in the Settings window, docs refer to on-screen controls by their label ("click Add Profile"), not as "the … button". |
| 9マス / 9つのボタン | the nine buttons; 3×3 grid | Spell out "nine" for the set (site). Use "grid" only for the layout itself ("split into a 3×3 grid"). Always use × (U+00D7), never x. |
| 空きマス | empty button | Site: "an empty button". Do not use "blank" or "unassigned". |
| マスの境界 | edge (between buttons) | Site: "A tick at every edge", "crosses into another button". |
| HUD | HUD | Keep the acronym and write "the HUD". Do not expand it in the UI. The user guide may explain it once: "the HUD, an overlay that shows all nine buttons". Do not use "heads-up display", "overlay" or "palette" as its name. |
| ハイライト / 白く光る | highlight / highlighted | "The button under your finger is highlighted." Do not use "glow" or "light up". |
| 実行する | run | Site: "buttons no longer run". Use "run" for buttons, actions, scripts and shortcuts. Avoid "execute", "fire" and "trigger" (as a verb). |
| 指を置く | place a finger | The start of the opening slide: "Place a finger on the top edge of the trackpad". Japanese uses only 置く / 滑らせる / 止める / 離す for the trackpad, never 長押し / 押したまま / 押す; English never uses "press", "press and hold", "touch and hold", "tap" or "click" for it: on a trackpad "press" means click. 押す is fine for keys and on-screen buttons. |
| 指を滑らせる | slide | App: "Slide to choose". Site: "Slide to a button". |
| 指を止める | hold your finger (on a button) | Keeping the finger still on a button before lifting. Used for 少し長く止めてから実行: "hold your finger on this button a little longer before lifting". Not "rest", "wait" or "press and hold". |
| 指を離す | lift your finger | App: "Lift on a button to run", "Lift in the frame to cancel", "Lift to cancel". |
| やめる（キャンセル） | cancel | "To cancel, …". The HUD says "Lift to cancel" while the finger is in the frame. The button label is "Cancel". |
| 左右の外枠で止める | hold your finger in the left or right frame | The main way to change pages: hold the finger in the side frame, beside the rows, for 0.5 s. HUD: "Hold for the next page" / "Hold for the previous page" under "Lift to cancel". Short form: "Hold in the side frame to change pages". |
| 2本指で左右にスワイプ | swipe left or right with two fingers | The other way to change pages. The noun is "two-finger swipe". |
| ページ | page | "up to three pages (27 buttons)", "the next page of nine". |
| HUD のページの点 | page dots | The dots in the HUD's top bar, to the right of the title, that show the current page ("Practice" replaces them during the welcome guide's practice). |
| プロファイル | profile | Site: "A profile for each app". |
| アプリのプロファイル | app profile | "the Xcode profile". |
| グローバル | Global | Proper name of the profile that applies to every app, so it is capitalized: "the Global profile", "Global pages". Apple's "All Applications" (Keyboard › App Shortcuts) was considered, but it doesn't work in compound labels. Do not use "Default" or "Universal". |
| プリセット | preset | Use "preset" in the app and guide. The site's marketing may say "ready-made layout". |
| ランチャー | launcher | Common noun, lowercase. Site: "a launcher filled with apps from your Mac, a handy stand-in for Launchpad". Launchpad is an Apple trademark and no longer exists in macOS 26. |
| 前面のアプリ | front app | Site: "the front app", "the app in front". "frontmost app" is Apple's developer term; keep it out of the UI. Do not use "active app", "foreground app" or "current app". |
| 起動中のアプリ | running app | Site: "a running app". |
| インストール済みのアプリ | installed apps | |
| アプリ | app | Apple's user-facing word. Use "Applications" only for the folder name. |
| 起動する / 開く（アプリを） | open | Apple prefers "open" to "launch" in user-facing text. The action is "Open" (with App chosen under What to open) and the setting is "Open at login". |
| 前面のときは隠す | Hide if already in front | Checkbox of the Open action when it opens an app. |
| アクション | action | "eight kinds of actions" (site). |
| アクションの種類 | Action type | Inspector label. |
| キー入力 | Keystrokes | Action type (site). In prose: "send keystrokes". The plural is deliberate because one action can send a key sequence. |
| 続けて押すキー | sequence | Site: "a sequence like ⌘L then ⌘C". Display it as "⌘L → ⌘C". |
| 記録する / 記録欄 | record / shortcut recorder | The field shows "Record Shortcut" and changes to "Type Shortcut" while recording. |
| キー配列 / JIS 配列 | keyboard layout / JIS keyboard | Site: "JIS keyboards", "any keyboard layout". |
| 開く（アクションの種類） | Open | Action type that opens an app or a URL (the former Open App and URL kinds). The site's chip reads "Open an app or URL". |
| 開くもの / アプリ / URL | What to open / App / URL | Segmented control of the Open action. The アプリ key is shared with the icon picker segment and the Menu Item editor's row label. |
| 画面に置く | Place on Screen | Action type that moves the front app's window to a fixed part of the screen. Title Case as an action type and as the name of the Global profile's first page; in prose "place the window". Not "snap", "tile" or "window management". |
| 場所（画面に置く） | Position | Inspector label of the Place on Screen action. The nine values are Top Left / Top Half / Top Right / Left Half / Maximize / Right Half / Bottom Left / Bottom Half / Bottom Right (Title Case; "half", not "side"). |
| 置く枠 / 離すと、ここに置きます | target area (outline) / Lift to place it here | The light-blue outline shown on screen while a Place on Screen button is highlighted, and its note. |
| %@ のウインドウ / 前面のウインドウ（HUD の帯） | %@ window / The front window | The context band under the HUD title that says what a Place on Screen page acts on: "Safari window". |
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
| 結果の出し方 | Output | Label for the result options of the AI action. Background scripts and shortcuts have no Output option: their text output, if any, goes to the result panel. |
| 選択範囲を置き換える | Replace Selection | Output option. |
| クリップボードにコピー | Copy to Clipboard | Output option of the AI action. Same wording as the Shortcuts app. |
| 画面に表示 | Show Result | Output option. It opens the "result panel", which has Copy and Close buttons. |
| 結果のパネル | result panel | |
| ファイル（アクションの種類） | File | Action type for the files selected in Finder. Singular, like Script and Shortcut. Not "File Management" (that is the preset category ファイル of the Finder preset). |
| ゴミ箱に入れる / 名前を変更 / 複製 | Move to Trash / Rename / Duplicate | The three operations of the File action. "Move to Trash" is Finder's own term. Never "Delete": Nonet never deletes files for good. |
| Finder で選んでいるファイルを | On the files selected in Finder | Label above the File action's operations. |
| 選んだファイル | Selected Files | Name of the Finder preset's second page (Duplicate, Rename and Move to Trash, plus Finder keys). Its button 新規フォルダへ (⌃⌘N, "New Folder with Selection" in Finder) is "Into New Folder" because button names are at most 16 columns wide. |
| Finder で選んでいるファイルに「%@」を実行しますか？ / 実行する | Run “%@” on the files selected in Finder? / Run | Confirmation before the Test Run of a File button (every operation changes files). |
| オートメーション（Finder） | Automation (Finder) | Permission name in the error "Automation (Finder) permission required." The macOS pane is Privacy & Security › Automation. |
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
| アイコン（SF Symbols / アプリのアイコン） | Icon: Symbol / App Icon | Icon sources. Mention "SF Symbols" only when naming Apple's library. |
| プロファイルを追加 | Add Profile… | Ends with an ellipsis because an app must be chosen next. The sheet it opens is titled "Add Profile", without an ellipsis (its own key, `settings.addProfileSheet.title`). |
| 複製 / 削除 | Duplicate / Delete | Context menu commands for buttons (with Test This Button, and Add Action on an empty button). コピー / ペースト ("Copy" / "Paste") are the Edit menu items: ⌘C and ⌘V copy and paste a button, also between profiles. |
| 隣と入れ替え / 上と入れ替え / 下と入れ替え / 左と入れ替え / 右と入れ替え | Swap With / Swap with Button Above / Swap with Button Below / Swap with Button on the Left / Swap with Button on the Right | VoiceOver actions for a button, done with ⌥⌘ and an arrow key (not in the context menu). |
| 複製して別のアプリに使う… / プリセットに戻す… | Duplicate for Another App… / Reset to Preset… | Profile context menu commands. Reset to Preset… appears only for apps that have a preset. |
| 前面にあるとき / このプロファイル / グローバルを使う / このアプリでは Nonet を使わない | When in Front / This Profile / Use Global / Turn Off Nonet in This App | Pop-up menu in the profile header (and in the profile context menu) that sets how an app uses Nonet. The header's tooltip is "When %@ is in front". |
| オフ / グローバル / 使用中（サイドバーの印） | Off / Global / In Use | Badges in the profile list: turned off in this app, uses the Global buttons (its own key, `settings.sidebar.usesGlobalBadge`), and the profile the front app is using now. |
| プロファイルを絞り込む / 名前・マス・キーで絞り込み / 絞り込みをやめる | Filter Profiles / Filter by name, button or keys / Clear Filter | The filter above the profile list (⌘F; always shown with 8 or more app profiles). Results read "Xcode › Build". |
| 名前を変更… / ページの名前 | Rename… / Page Name | Renaming a page. A named page shows in the HUD title as "Xcode · Debug". |
| ページの操作 / ページを追加 / このページを削除… | Page Actions / Add Page / Delete This Page… | The … menu next to the page chips (its help tag and VoiceOver label are "Page Actions"). It acts on the selected page and also has Rename…. The menu item Add Page has its own key (`settings.pageMenu.addPage`), because the + button's help tag ページを追加 is "Add page". |
| 以前の設定に戻す… / 戻す… / この設定に戻す / 控え | Restore an Earlier Version… / Restore… / Restore / saved version | Button under Export & Import, its sheet and its confirmation. In prose, 控え (a saved copy of the settings) is "saved version". Don't call it a "backup" in the UI, so it isn't confused with an exported file. |
| このマスをテスト実行 | Test This Button | Context menu command. In prose: "test run". Nonet doesn't open from the top edge while its own window is the key window (Settings uses the trackpad for dragging buttons), so this is how to try a button from Settings. |
| 少し長く止めてから実行 | Hold before running | Inspector checkbox (`Cell.requiresHold`; the configuration file still calls it `requiresHUD`) and the VoiceOver value of the timer mark at the top right of such a button in the HUD and the Settings grid. Sentence case. The button runs only if the finger stays on it about 0.45 seconds; meanwhile its outline in the HUD fills around. Caption: "Runs only if you hold your finger on this button a little longer before lifting. When the outline in the HUD goes all the way around, lift to run." Do not use "long press", "press and hold" or "confirm". |
| 並べ替え / 入れ替え | reorder / swap | "Drag to reorder", "drag to swap buttons". |
| 右クリック | Control-click | Apple docs style: "Control-click (or right-click)". |
| Nonet を有効にする | Enable Nonet | Settings checkbox, and a menu bar menu item with a checkmark. Caption in Settings: "When off, sliding in from the top edge of the trackpad doesn't open the buttons". |
| 開き方とやめ方 | How to open and cancel | Row under Opening and HUD in Settings › General, with a small figure of the trackpad and an arrow from the top edge. Caption: "Place a finger on the top edge of the trackpad and slide it down to open the nine buttons. Slide to choose, then lift on a button to run it. To close without running anything, slide out to the frame around the buttons and lift, or press any key." |
| 開きやすさ / 控えめ / 標準 / 開きやすい | Open sensitivity / Low / Standard / High | Settings label and its segmented options (`GlobalSettings.openSensitivity`). The caption describes the band, the distance and the time of the chosen level. |
| 大きく表示 | Show larger | Settings toggle that replaces the old HUD size options (`HUDScale.standard` / `.large`, 1 / 1.25×). Caption: "Shows the HUD and the notices at the bottom of the screen at 1.25×". |
| HUD の位置 | HUD position | Retired: the HUD always appears next to the pointer. The old setting value (`hudPosition`) is read and dropped. |
| ためらったときだけ HUD を出す | Show the HUD only when you hesitate | General setting (`hudOnHesitation`): for the first 0.4 seconds after opening only haptics guide; the map appears if the buttons stay open longer. Not "delay" or "hide the HUD". |
| 触覚 | Haptic feedback | Apple term. Settings toggle (on is the medium strength). Caption: "The trackpad gives a light tick when the buttons open, when you cross into another button and when a button runs (Force Touch trackpads only)". Not "Firm", which Apple uses for trackpad click pressure. Prose can describe the feeling as "a light tick"; closing without running anything gives "two light taps". Here "tap" means the haptic, never a finger action. Avoid "vibration" in the UI. |
| ポインタ | pointer | Apple calls the mouse arrow the "pointer" (Japanese ポインタ), and the site does too ("the pointer stays put"). Japanese UI text says ポインタ, never カーソル, for it. Use "cursor" (カーソル) only for a text insertion point. |
| ログイン時に起動 | Open at login | Apple's wording (Dock menu and Login Items). Sentence case because it is a checkbox. |
| ログイン項目 | Login Items | System Settings › General › Login Items on macOS 14; the pane is "Login Items & Extensions" on macOS 15 and later. |
| プロファイルの書き出し / 読み込み | Export or import profiles | Setting label under Export & Import on the Nonet tab, next to the push buttons "Export…" and "Import…". The save and open panels are titled "Export Profiles" and "Import Profiles". The file is "a .nonetprofile file". |
| ライセンス | License | The license section at the top of the Nonet tab of Settings (status, purchase, key registration). US spelling, never "licence". |
| 情報 | About | The About part at the bottom of the Nonet tab of Settings (version, User Guide, Check for Updates…, Contact Support…, Uninstall Nonet…). |
| Nonet（設定のタブ） | Nonet | The third Settings tab (Profiles / General / Nonet). It holds the license section, Export & Import and the About part. The menu items Registered and Enter License Key… open it. |
| 利用ガイド | User Guide | |
| お問い合わせ | Contact | Site footer. |
| お問い合わせ… | Contact Support… | Button in the About part of the Nonet tab of Settings and next to license errors. It opens a pre-filled email (subject "Nonet %@ support"). |
| Nonet をアンインストール… / アンインストール | Uninstall Nonet… / Uninstall | Button in the About part of the Nonet tab of Settings, and its confirmation. The last step is "Open System Settings and Quit". |
| 試用 / 試用期間 | trial / free trial | Site: "14-day free trial", "When the trial ends". Do not use "evaluation" or "demo". |
| 試用期間が終了しました | Your trial has ended | Exact site wording (FAQ). |
| 試用期間が終了しました。メニューバーの Nonet から購入・登録できます。 | Your trial has ended. Buy Nonet or register a license key from its menu bar icon. | HUD banner and notice after the trial ends. |
| 試用の残り日数 | days left in your trial | "%lld days left in your trial". Use xcstrings plural variants ("1 day left"). The same English is used for 試用期間は残り%lld日です (the menu status and the HUD reminder with 3 days or fewer left) and 試用期間：残り%lld日. Japanese writes day counts without spaces (残り14日) and uses the full-width colon. |
| 試用期間中（残り%lld日・%@まで） | %lld days left in your trial (ends %@) | Status line of the license section (Nonet tab), with the end date in the UI language ("November 14"). |
| ライセンスキー | license key | Site: "Enter a license key". The placeholder of the license section's key field is "License key" (its own key, `settings.license.keyPlaceholder`); the row label ライセンスキー is "License Key". |
| 登録 / 登録者 | Register / Registered to | Entering a valid key registers your copy. The button is "Register" and the status reads `Registered to <name>`. Do not use "Activate", because that suggests online activation and keys are checked offline. |
| 購入する / 購入ページ | Buy Nonet / purchase page | Site button and privacy policy wording. Also the button in the license section of the Nonet tab, in the trial-ended window and in the Settings banner. |
| Nonet を購入… / ライセンスキーを入力… | Buy Nonet… / Enter License Key… | Nonet menu items during the trial and after it ends. Enter License Key… is also the button in the trial-ended banner of Settings and in the welcome guide. |
| 購入済みの方 / 別のライセンスキーを登録 | Already Bought Nonet? / Register a Different License Key | Section headers above the license key field in the license section of the Nonet tab. |
| ライセンスキーが見つからないときは | Can't find your license key? | Link under the license key field. It opens the site's FAQ. |
| キーをコピー / 別のキーを登録… | Copy License Key / Register a Different Key… | Buttons in the License Key row once registered. |
| このライセンスキーを登録しますか？ | Register this license key? | Asked when a `nonet://register` link or a .nonetlicense file is opened. Nonet never registers a key without asking. |
| Nonet の試用期間が終了しました / あとで / ライセンスキーを登録… | Your Nonet trial has ended / Not Now / Register License Key… | The small window shown at most once a day after the trial ends, together with Buy Nonet. |
| 買い切り | one-time purchase | Site. |
| メニューバー / メニューバーのアイコン | menu bar / menu bar icon | Apple term. |
| Nonet のメニュー | the Nonet menu | The menu that opens from the menu bar icon. The user guide uses this name: "choose Settings… from the Nonet menu". |
| 早見表 | cheat sheet | Docs-only name (lowercase in prose) for the grid at the top of the Nonet menu: the buttons the front app would show if you opened them now, from the first page. Its title is the profile's, "Buttons for %@" or "Global Buttons" (with " · " and the page name when the page has one); ‹ › are "Previous Page" / "Next Page"; clicking a button opens it in Settings › Profiles. In an app set to Turn Off Nonet in This App, one line replaces the grid: "Nonet is off in %@". The UI itself never shows the words 早見表 or "cheat sheet". |
| %@ のマスを編集… / %@ のマスを作る… / グローバルのマスを編集… | Edit Buttons for %@… / Create Buttons for %@… / Edit Global Buttons… | Nonet menu item for the front app. Japanese prose in the guide writes ◯◯ のマスを編集…; the English guide writes "Edit Buttons for Xcode…". The welcome guide's tip doesn't name an app (the app behind the window may not be the one the user means): "Click the 3×3 icon in the menu bar and choose Edit Buttons for <app>… to change the buttons for the app in front." |
| このアプリでは使わない | Turn Off in This App | Nonet menu item with a checkmark. Sets the front app to Turn Off Nonet in This App: in that app, sliding in from the top edge does nothing and the trackpad works as usual ("Nonet is off in %@. The trackpad works as usual."). |
| 最近の実行 | Recent Runs | Nonet menu submenu. Each item reads "✓ Xcode › Build"; a failure reads "✗ …", then " — " and the first line of the reason. |
| ヘルプ / Nonet ヘルプ | Help / Nonet Help | Help menu of the hidden main menu (⌘?). |
| Nonet はここにいます | Nonet lives here | Bubble under the menu bar icon when the welcome guide closes (with Done, Skip or the close button; not with Open Settings). |
| 「Xcode のプロファイル」（メニューの状態） | Xcode profile | Status line in the menu bar menu. |
| 初回の案内 / 初回の案内をもう一度 | welcome guide / Show Welcome Guide | Menu item without an ellipsis, because it only opens a window. |
| 試してみる | Try It Out | Onboarding step and button (the second and last step, after Accessibility). Apple uses "choose" for user decisions and "select" for text or list items. |
| 試してみましょう / 開いて、マスで離す / 外枠で離して、やめる / いまの課題 / この後の課題 / 済み | Try it out / Open and lift on a button / Cancel in the frame / Current task / Next task / Done | The practice step's heading, its two tasks and their states. The first task: "Place a finger on the top edge of the trackpad and slide it down to open the HUD, which shows all nine buttons. Slide to “%@” and lift your finger there." |
| Nonet を使うには、あと1つ許可が必要です / 今後表示しない | One more step to start using Nonet / Don't show again | The permission step when the welcome guide reopens at launch without Accessibility permission. |
| Mac にログインしたら Nonet を自動で起動する | Open Nonet automatically when you log in | Checkbox at the bottom of the welcome guide's Try It Out step. Checked on first launch; when the guide is shown again, it starts from the current Open at login setting. Applied when the guide closes from that step. Sentence case because it is a checkbox. If the menu bar icon is hidden, the step also says "If you can't see the icon in the menu bar, open Nonet from the Applications folder to open Settings." |
| 練習モード | practice mode | "Nothing runs in practice mode." |
| アップデート / アップデートを確認 | update / Check for Updates… | Sparkle's standard menu item. |
| アップデートがあります… | Update Available… | Replaces Check for Updates… in the Nonet menu when a scheduled check has found an update. Title Case and an ellipsis, because it opens Sparkle's update window. |
| 終了 | Quit Nonet | Apple's `Quit <App>` pattern. |
| Nonet について | About Nonet | App menu item of the hidden main menu. It opens the Nonet tab of Settings. |
| 取り消す / やり直す / カット / コピー / ペースト / ペーストしてスタイルを合わせる / 削除 / すべてを選択 | Undo / Redo / Cut / Copy / Paste / Paste and Match Style / Delete / Select All | Edit menu of the hidden main menu. These are Apple's standard item names. The menu itself is "Edit" (its own key, `menu.edit`, because 編集 is also the symbol group "Editing"). |
| ウインドウ / 閉じる / しまう | Window / Close / Minimize | Window menu of the hidden main menu (⌘W, ⌘M). |
| マスで指を離すと実行 | Lift on a button to run | Former HUD hint, no longer shown or read (the HUD shows no how-to text). The welcome guide's practice says "Done. Lift your finger on a button to run it." |
| 止めると次のページ / 止めると前のページ（HUD） | Hold for the next page / Hold for the previous page | Second line under "✕ Lift to cancel" while the finger is in the left or right frame and there is a page on that side. |
| そのまま止めて待つ / 離すと実行（VoiceOver） | Keep your finger still / Lift to run | VoiceOver text for a Hold before running button while its outline is still going around, and once it's complete (VoiceOver says "Lift to run" then). Not shown in the HUD: the outline and the haptic show the progress. The only text in the HUD's top bar is "Practice". |
| Nonet のウィンドウが前面のときは、9マスは開きません / ほかのアプリの上で試してください | The nine buttons don't open while a Nonet window is in front / Try it over another app | Notice at the bottom of the screen, shown once per launch when the user slides in from the top edge while Settings or the welcome guide is in front. Info style, not an error. |
| うまく開かないときは… / 外枠で離すと、何も実行せずに閉じます。… / マスの境目の線の上で離すと、実行しません。… / 通りかかっただけのマスは実行しません。… / 空きマスでは何も起きません。… / 指を1本にして… / まだ外枠で離していません。… | If it doesn't open… / Lifting in the frame closes the buttons without running anything. … / Lifting right on the line between two buttons runs nothing. … / A button you only slid across doesn't run. … / Nothing happens on an empty button. … / Use one finger… / You haven't lifted in the frame yet. … | Practice hints in the welcome guide: the standing hint under task 1, and one hint per reason a lift ran nothing (`SessionCancellation`). Each ends with what to do next. |
| 離すとやめる（HUD） | Lift to cancel | Always shown with ✕ in the bottom band of the HUD's trackpad map; it stands out while the finger is in the frame (the buttons dim and the frame band brightens), including right after opening, because the finger always counts as being in the frame until it slides a little further. |
| トラックパッドの地図（HUD） | trackpad map | The HUD is a small panel next to the pointer that draws the trackpad: the nine buttons, the frame band in the trackpad's own proportions, ‹ › in the side bands when there is a page on that side, and the bottom band with "Lift to cancel". The real pointer moves over the map to follow the finger (there is no separate finger dot). |
| 練習中（HUD） | Practice | Next to the profile name in the HUD while the welcome guide's practice runs. |
| 「%@」を実行中… | Running “%@”… | Notice while a slow button runs. |
| %@ › %@ / %@ › %@（%lldページ目） | %1$@ › %2$@ / %1$@ › %2$@ (page %3$lld) | Title of a failure notice: profile › button, plus the page when the profile has more than one. |
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
| セッション | (internal only) | Code term for the time from opening the nine buttons until every finger leaves the trackpad. Do not show it to users. |
| トースト / 通知 | notice | "toast" is the internal name; users see "notice". Japanese captions call it 通知 (画面の下に出る通知). |
| 〜できませんでした | Couldn't … | Apple style uses contractions: "Couldn't open %@". |
| 〜が見つかりません | Can't find … | "Can't find the menu item “%@”". |
| 〜してください | imperative, no "please" | "Select some text first." Apple style avoids "please". |
| 。（日本語の文末） | (period) | Japanese only: a one-sentence caption, notice, status line or alert text has no 。 at the end; text with two or more sentences ends every sentence, including the last, with 。. English keeps its own periods. |
| ない（無い） | — | Japanese UI text writes ない in hiragana (プロファイルのないアプリ, 一覧にないアプリを選ぶ…), as Apple does. |
| 次へ進んでください | Click Next to continue. | Footer of the welcome guide's permission step once Accessibility is allowed. The card already says 許可されています, so the footer doesn't repeat it. |
| 〜など%lld個（プリセットの説明） | %lld buttons, including … | "%lld buttons, including Build, Test and Open Quickly". Use plural variants. Name only buttons the preset really has on this Mac (AI and Claude Code buttons are left out when they can't run). |
| プリセットのボタン名 | the target app's own English wording | Take preset names from the target app's English menus (Xcode "Build", "Test"; Zoom "Mute"). |
| 「」 / … / 〜 / 秒 | “ ” / … (U+2026) / – (en dash) / s | Curly quotes, the single ellipsis character, an en dash for ranges ("1–2 characters"), and a space before units: "0.6 s", "60 s". Spell out "seconds" in running prose. Menu paths: "Nonet › Settings…". |
| 打鍵 | keystroke | "Adds Esc as a keystroke". The action type is still "Keystrokes". |
| 表記で入力 / キーの表記 | Type keys as text / Keys as text | Placeholder and VoiceOver label of the field where keys are typed as text. The example is in the caption under the field: "For example, ⌘L → ⌘C. …". Apple style avoids "e.g.". |
| 決定（入力欄の横のボタン） / 使う（アイコンの文字） | Apply / Use | Buttons that confirm a typed value. |
| 送るキー / 開くアプリ / 開く URL / 実行するスクリプト / 実行するショートカット / 押すメニュー項目 | Keys to send / App to open / URL to open / Script to run / Shortcut to run / Menu item to choose | Inspector field labels, sentence case. |
| 未設定 / なし（メニューを順にたどって押します） | Not set / None (Nonet opens the menus to choose it) | Values shown when a button or a menu item has nothing set. |
| 登録済み | Registered | License status title and menu bar line. The detail line is "Registered to %@". |
| この Mac から登録を消す / 登録を消す… / 登録を消す | Remove License from This Mac / Remove… / Remove | Opposite of Register. Never "Deactivate" or "Unregister". Alert title: "Remove the license from this Mac?". Result: "The license was removed from this Mac." |
| 無効になっている / 無効にされている（ライセンスキー） | deactivated | A key we revoked (a refunded license or a key that was made public): "This license key has been deactivated". The user can't undo it, so it's not the same as Remove License from This Mac. |
| 発行日 / ライセンス ID / 買い切りのライセンス | Issued / License ID / One-time purchase | License pane labels. |
| もう一度確かめる | Check Again | Button in the Settings status banner and in the welcome guide (looks for the trackpad, or checks secure input, again). The Accessibility banner has only Open System Settings. |
| 開き方と HUD / 起動 / 書き出しと読み込み / 状態 | Opening and HUD / Startup / Export & Import / Status | Settings section headers, Title Case. 開き方と HUD and 起動 are on the General tab; 書き出しと読み込み and 状態 are on the Nonet tab. |
| 新しいプロファイルだけ追加 / 置き換えて読み込む / 読み込む | Add New Profiles Only / Replace and Import / Import | Buttons in the import confirmation sheet. "Import" is shown when nothing would be replaced. It has its own key (`settings.import.confirmButton`), because the bare 読み込む is "Load" in the Pick from Menus panel. When the sheet lists buttons that run something, these buttons stay disabled until the list is scrolled to the end. |
| ・%@ › %@ / スクリプト（%lld行）: / キー入力: %@ / メニュー項目: %@ › %@ / ショートカット: %@ / AI への指示: / 結果: %@ / 開くファイル: %@ | • %1$@ › %2$@ / Script (%lld lines): / Keystrokes: %@ / Menu item: %1$@ › %2$@ / Shortcut: %@ / Instructions for AI: / Result: %@ / File to open: %@ | The import confirmation's list of buttons that run something (Script, Keystrokes, Menu Item and AI buttons, and URLs that open a file): "Profile › Button", then everything the button does, never cut off: every line of the script, all the keys, the menu item and its keyboard shortcut, the AI prompt and output, or the file. Use plural variants for the line count. |
| 最後までスクロールして中身をすべて確かめると、読み込めます / Return と同じ働きのキー（または ⌃ の付いたキー）を押します。… / 注意が要る命令（%@）を含みます。… | Scroll to the end to check everything before you can import. / Presses a key that works like Return (or a key with ⌃). … / Contains commands that need care (%@). … | Hint and warnings in the import confirmation sheet. "a key that works like Return" covers Return, Enter and keys that type a line break in the current keyboard layout; "commands that need care" are curl, wget, base64, eval, a pipe into a shell, osascript and rm -rf. |
| 元に戻す（9マスの下） / マスを空にしました | Undo / Cleared the button. | The notice and link under the grid after a button is cleared. Other notices: "Replaced the button with the menu item.", "Replaced the button with the pasted one.", "Deleted the “%@” profile." and "Deleted “%@”." (a page). |
| マスを空にする / マスの移動 / マスの入れ替え / メニュー項目の割り当て / マスの変更 / マスの貼り付け / プロファイルの削除 / ページの削除 / プロファイルの複製 / プリセットに戻す / ページの名前の変更 | Clear Button / Move Button / Swap Buttons / Assign Menu Item / Change Button / Paste Button / Delete Profile / Delete Page / Duplicate Profile / Reset to Preset / Rename Page | Undo action names (`UndoManager.setActionName`) for edits in Settings. Title Case. Change Button is one inspector edit step. |
| 既定（サイドバーのバッジ） | Default | Only the badge next to the Global profile. The profile itself is always named "Global". |
| プリセットあり / 追加済み / 設定済み | Preset / Added / Added | Badges in app lists. 設定済み（無効） is "Added, disabled". |
| 記号 / アプリ（アイコンの種類） | Symbol / App | Icon picker segments. The アプリ key is shared with the Open action's What to open segment and the Menu Item editor's row label, so the segment says "App", not "App Icon". The Profiles sidebar header has its own key (`settings.sidebar.appsHeader`) and reads "Apps". |
| 左上 / 上 / 右上 / 左 / 中央 / 右 / 左下 / 下 / 右下 | top left / top / top right / left / center / right / bottom left / bottom / bottom right | Button positions, lowercase. Used inside "Button %lld (%@)" and VoiceOver labels. Before a noun, the four corners use their own keys (`attributivePosition.topLeft` and so on) with U+2011 non-breaking hyphens, so the line doesn't wrap at the hyphen: "the bottom‑left button". The welcome guide's practice feedback uses the plain form: "That was “Build” (top left). “Run” is at the center." |
| 開発 / デザイン / チャット / メール / ブラウザ / 会議 / ドキュメント / ファイル（プリセットの分類） | Development / Design / Chat / Mail / Web Browsing / Video Conferencing / Writing / File Management | Preset categories shown with each app in Add Profile. Title Case. |
| よく使う / 編集 / 画面と操作 / メディアと連絡 / AI と文章 / 開発（記号の分類） | Common / Editing / Windows & Navigation / Media & Communication / AI & Writing / Development | Symbol groups in the icon picker. 編集 here is "Editing", not the Edit menu. |
| マス %lld（%@） | Button %lld (%@) | Inspector heading and VoiceOver label, e.g. "Button 3 (top right)". An empty one is "%@: empty" in Settings and "Empty button, %@" in the HUD. |
| アクションを追加 / マスに入れる / このマスを空にする / 既定のアイコンに戻す | Add Action / Put in Button / Clear This Button / Restore Default Icon | Commands, Title Case. マスに入れる is the Pick from Menus panel's context menu item (it puts the item in the selected Menu Item button, or an empty button). |
| アプリを選ぶ…（1つ選ぶ） / 一覧にないアプリを選ぶ… | Choose App… / Choose Another App… | Singular wherever one app is picked (the Open action's App to open, Add Profile). The bare key アプリを選ぶ is also used for the Pick from Menus app pop-up's placeholder and for the app open panel's title, translated "Choose App". |
| 一覧を読み直す / 読み直す / 読み込む / メニューを読み込む / もう一度読む | Reload List / Reload / Load / Load Menus / Try Again | Shortcut list, Pick from Menus panel and their retry buttons. |
| 「ボタン名」を押す（文中で操作を指す） | click <label> | In UI text, name controls by their label without quotes: "Click Add Profile to…", "click Register", "Click Next to continue". |
| 動作中 / 停止しています / パスワード入力中は使えません | Running / Stopped / Unavailable while entering a password | Menu bar status line. |
| この知らせを消す / アクセシビリティを許可… | Dismiss Notice / Allow Accessibility Access… | Menu bar menu items. |
| Nonet（無効） / Nonet（確認が必要） / Nonet（アップデートがあります） | Nonet (disabled) / Nonet (needs attention) / Nonet (update available) | Menu bar icon tooltip and VoiceOver. |
| あとで許可する | Not Now | Onboarding. No exclamation marks. |
| スクリプトで使える環境変数 / スクリプトに渡す環境変数 | Environment variables for scripts / Environment variables passed to scripts | Help button label and popover heading in the Script editor. |
| ほか%lld個 | And %lld more | End of a list in the import confirmation. Use plural variants. |
| ' （アポストロフィ） | ' | Use the straight apostrophe in contractions ("Can't", "doesn't"), as the existing catalogs do. Quoted names use curly quotes: Delete the “%@” profile? Code examples keep straight quotes. |
| ・（箇条書きの頭） | • | Bullet for list lines in alerts: "• %@". |
