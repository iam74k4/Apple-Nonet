import AppKit
import NonetCore
@testable import NonetPlatform
import Testing

@Suite("アクションの文脈")
struct ActionContextTests {
    private static let selectionScript = #"printf '%s' "$NONET_SELECTED_TEXT" | pbcopy"#
    private static let urlScript = #"open "$NONET_BROWSER_URL""#

    @Test("スクリプトは、ソースに書かれた変数の文脈だけを読む。書類の場所はいつも読む")
    func scriptNeeds() {
        // 使わないスクリプトでは ⌘C も送らず、ブラウザにも聞かない
        #expect(ContextNeeds.forScript(source: "open -b com.apple.dt.Devices") == [.documentPath])
        #expect(ContextNeeds.forScript(source: #"cd "${PROJECT_DIR:-$HOME}" && claude"#) == [.documentPath])
        #expect(ContextNeeds.forScript(source: Self.selectionScript) == [.documentPath, .selectedText, .copyFallback])
        #expect(ContextNeeds.forScript(source: Self.urlScript) == [.documentPath, .browserURL])
        // 外部のファイルに渡すときは、コメントに名前を書けばよい
        #expect(ContextNeeds.forScript(source: "# NONET_SELECTED_TEXT NONET_BROWSER_URL\n~/bin/tool.sh")
            == [.documentPath, .selectedText, .copyFallback, .browserURL])
        // 選択が空と読めたときは ⌘C を送らない（警告音が鳴るだけ）
        #expect(!ContextNeeds.forScript(source: Self.selectionScript).contains(.copyWhenEmpty))
    }

    @Test("ソースから探す名前は、ScriptEnvironment が渡す変数の名前と同じ")
    func scriptVariableNames() {
        let variables = ScriptEnvironment.variables(
            for: ScriptContextInfo(browserURL: "https://example.com", selectedText: "選択"),
            projectDirectory: nil
        )
        #expect(variables[ScriptVariableName.selectedText] == "選択")
        #expect(variables[ScriptVariableName.browserURL] == "https://example.com")
    }

    @Test("ショートカットは passSelectedText のときだけ選択テキスト、AI は常に選択テキスト")
    func otherNeeds() {
        #expect(ContextNeeds.forShortcut(ShortcutAction(name: "X")).isEmpty)
        #expect(ContextNeeds.forShortcut(ShortcutAction(name: "X", passSelectedText: true)) == [.selectedText, .copyFallback, .copyWhenEmpty])
        #expect(ContextNeeds.forAI == [.selectedText, .copyFallback, .copyWhenEmpty])
    }

    @Test("⌘C を送るのは、選択を読めないとき。選択が空と読めたときは、選択テキストを処理するアクションだけ")
    func copyDecision() {
        let script = ContextNeeds.forScript(source: Self.selectionScript)
        #expect(script.needsCopy(after: .unreadable))
        #expect(!script.needsCopy(after: .empty))
        #expect(!script.needsCopy(after: .text("選択")))
        #expect(!ContextNeeds.forScript(source: "say hello").needsCopy(after: .unreadable))
        #expect(ContextNeeds.forAI.needsCopy(after: .unreadable))
        #expect(ContextNeeds.forAI.needsCopy(after: .empty))
        #expect(!ContextNeeds.forAI.needsCopy(after: .text("選択")))
        #expect(!ContextNeeds([.selectedText, .documentPath]).needsCopy(after: .unreadable))
        #expect(!ContextNeeds([.selectedText, .documentPath]).needsCopy(after: .empty))
    }

    @Test("アクセシビリティの結果: 文字があれば選択、空文字は選択なし、それ以外は読めない")
    func axSelection() {
        #expect(AXSelection(error: .success, value: "選択した文" as CFString) == .text("選択した文"))
        #expect(AXSelection(error: .success, value: " " as CFString) == .text(" "))
        #expect(AXSelection(error: .success, value: "" as CFString) == .empty)
        #expect(AXSelection(error: .success, value: nil) == .unreadable)
        #expect(AXSelection(error: .success, value: 42 as CFNumber) == .unreadable)
        #expect(AXSelection(error: .noValue, value: nil) == .unreadable)
        #expect(AXSelection(error: .attributeUnsupported, value: nil) == .unreadable)
        #expect(AXSelection(error: .cannotComplete, value: "古い値" as CFString) == .unreadable)
    }

    @Test("ブラウザに聞くのは、対応しているブラウザが前面のときだけ")
    func browserGate() {
        let script = ContextNeeds.forScript(source: Self.urlScript)
        for id in ["com.apple.Safari", "com.google.Chrome", "company.thebrowser.Browser", "com.microsoft.edgemac", "com.brave.Browser"] {
            #expect(script.asksBrowser(bundleID: id), "\(id)")
        }
        #expect(!script.asksBrowser(bundleID: "com.apple.dt.Xcode"))
        #expect(!script.asksBrowser(bundleID: "org.mozilla.firefox"))
        #expect(!ContextNeeds.forAI.asksBrowser(bundleID: "com.apple.Safari"))
        // URL を使わないスクリプトでは、Chrome が前面でもオートメーションの確認を出さない
        #expect(!ContextNeeds.forScript(source: "open -b com.apple.dt.Devices").asksBrowser(bundleID: "com.google.Chrome"))
    }

    @Test("何も要らなければ何も読まない")
    @MainActor
    func emptyNeedsReadNothing() async {
        let reader = ContextReader(keySender: KeySender())
        let app = RunningAppInfo(app: AppReference(bundleID: "com.example.app", name: "App"), processID: 1)
        let reading = await reader.read([], app: app)
        #expect(reading == ContextReading(info: ScriptContextInfo(app: app.app)))
        let none = await reader.read([.selectedText, .documentPath], app: nil)
        #expect(none == ContextReading(info: ScriptContextInfo()))
    }

    @Test("書類の場所", arguments: [
        ("file:///Users/me/Projects/App/App.xcodeproj/", "/Users/me/Projects/App/App.xcodeproj"),
        ("file:///Users/me/My%20Notes/%E3%83%A1%E3%83%A2.txt", "/Users/me/My Notes/メモ.txt"),
        ("/Users/me/plain.txt", "/Users/me/plain.txt"),
        ("/Users/me/folder/", "/Users/me/folder"),
        ("file:///", "/"),
    ])
    func documentPaths(value: String, expected: String) {
        #expect(DocumentPathParser.path(fromAXDocument: value) == expected)
    }

    @Test("ファイル以外の書類は nil", arguments: ["https://example.com/doc", "", "relative/path.txt"])
    func nonFileDocuments(value: String) {
        #expect(DocumentPathParser.path(fromAXDocument: value) == nil)
    }

    @Test("ブラウザごとの AppleScript")
    func browserScripts() {
        #expect(BrowserURLReader.script(forBundleID: "com.apple.Safari") == #"tell application id "com.apple.Safari" to return URL of front document"#)
        for id in ["com.google.Chrome", "company.thebrowser.Browser", "com.microsoft.edgemac", "com.brave.Browser"] {
            #expect(BrowserURLReader.script(forBundleID: id) == "tell application id \"\(id)\" to return URL of active tab of front window")
        }
        #expect(BrowserURLReader.script(forBundleID: "org.mozilla.firefox") == nil)
        #expect(BrowserURLReader.script(forBundleID: "com.apple.Safari\" to do shell script \"x") == nil)
    }

    @Test("何も選択していないと行を丸ごとコピーするエディタでは、改行で終わる1行は選択なしとみなす")
    func lineCopyingEditors() {
        let line = "let total = items.reduce(0, +)\n"
        for id in ["com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "md.obsidian", "com.jetbrains.intellij", "com.sublimetext.4"] {
            #expect(ContextReader.selectedText(fromCopy: line, bundleID: id) == nil, "\(id)")
        }
        // 複数行や、改行で終わらない部分は選択したもの
        #expect(ContextReader.selectedText(fromCopy: "a\nb\n", bundleID: "com.microsoft.VSCode") == "a\nb\n")
        #expect(ContextReader.selectedText(fromCopy: "items.reduce", bundleID: "com.microsoft.VSCode") == "items.reduce")
        // ほかのアプリでは、そのまま選択テキスト
        #expect(ContextReader.selectedText(fromCopy: line, bundleID: "com.tinyspeck.slackmacgap") == line)
    }

    @Test("Windows の改行（CRLF）の書類でも、改行で終わる1行は選択なしとみなす")
    func lineCopyingEditorsWithCRLF() {
        let line = "let total = items.reduce(0, +)\r\n"
        for id in ["com.microsoft.VSCode", "com.jetbrains.intellij", "com.sublimetext.4"] {
            #expect(ContextReader.selectedText(fromCopy: line, bundleID: id) == nil, "\(id)")
        }
        #expect(ContextReader.selectedText(fromCopy: "\r\n", bundleID: "com.microsoft.VSCode") == nil)
        // 複数行は選択したもの
        #expect(ContextReader.selectedText(fromCopy: "a\r\nb\r\n", bundleID: "com.microsoft.VSCode") == "a\r\nb\r\n")
    }

    @Test("選択テキストが無いときの説明: ⌘C を送れなかった理由と、エディタの行のコピーを無視したことを分けて伝える")
    func noSelectionMessages() {
        let info = ScriptContextInfo(app: nil)
        let plain = SelectionMessage.noSelection(ContextReading(info: info))
        #expect(plain == String(localized: "テキストを選択してから実行してください", bundle: .nonetActions))
        let denied = SelectionMessage.noSelection(ContextReading(info: info, copyUnavailable: .denied))
        let tooLarge = SelectionMessage.noSelection(ContextReading(info: info, copyUnavailable: .tooLarge))
        let lineCopy = SelectionMessage.noSelection(ContextReading(info: info, ignoredLineCopy: true))
        #expect(Set([plain, denied, tooLarge, lineCopy]).count == 4)
        // クリップボードを保てない理由のうち、許可が無いとき以外は同じ説明（選択したテキストを自分でコピーすれば読める）
        for failure in [PasteboardSnapshot.Failure.tooSlow, .unrestorable, .unreadable] {
            #expect(SelectionMessage.noSelection(ContextReading(info: info, copyUnavailable: failure)) == tooLarge)
        }
    }

    @Test("選択を置き換えるのは、アクセシビリティで読めたか、読めずに ⌘C で取れたときだけ")
    func replacePlan() {
        #expect(ReplacePlan.canPaste(over: .accessibility))
        #expect(ReplacePlan.canPaste(over: .copyAfterUnreadable))
        // 「選択なし」と答えていたなら、貼り付けはカーソルの位置への挿入になる
        #expect(!ReplacePlan.canPaste(over: .copyAfterEmpty))
    }

    @Test("osascript の出力")
    func browserOutput() {
        #expect(BrowserURLReader.parse("https://example.com/\n") == "https://example.com/")
        #expect(BrowserURLReader.parse("missing value\n") == nil)
        #expect(BrowserURLReader.parse("  \n") == nil)
    }

    @Test("対応していないブラウザには聞かない")
    func unsupportedBrowser() async {
        #expect(await BrowserURLReader.read(bundleID: "com.apple.finder") == nil)
    }
}

/// 文脈を読む手段を偽物にして、何をどの順で読むかを確かめる（キーは送らず、アプリにも聞かない）
@Suite("文脈の集め方")
@MainActor
struct ActionContextGatheringTests {
    private actor CallLog {
        private(set) var calls: [String] = []

        func record(_ call: String) {
            calls.append(call)
        }

        /// prefix で始まる呼び出しを待つ（最大 10 秒）。並べて動いていなければ来ないので、時間切れを記録して先へ進む。
        /// 回数ではなく時刻で区切る（遅い Mac（CI）では 10 ミリ秒の眠りが延び、相手が始まる前に回数を使いきることがある）
        func waitFor(_ prefix: String) async {
            let deadline = ContinuousClock.now + .seconds(10)
            while ContinuousClock.now < deadline {
                if calls.contains(where: { $0.hasPrefix(prefix) }) { return }
                try? await Task.sleep(for: .milliseconds(10))
            }
            calls.append("timeout:\(prefix)")
        }
    }

    private nonisolated static let url = "https://example.com/article"

    /// rendezvous なら、ブラウザへの問い合わせと ⌘C がお互いの始まりを待つ（並べて動いていなければ時間切れになる）
    private func reader(
        selection: AXSelection,
        documentPath: String? = nil,
        copied: ClipboardCopy.Outcome = .copied("⌘C で取った文"),
        log: CallLog,
        rendezvous: Bool = false
    ) -> ContextReader {
        ContextReader(sources: ContextReader.Sources(
            selection: { _ in
                await log.record("selection")
                return selection
            },
            documentPath: { _ in
                await log.record("documentPath")
                return documentPath
            },
            browserURL: { bundleID in
                await log.record("browser:\(bundleID)")
                if rendezvous { await log.waitFor("copy") }
                return Self.url
            },
            copySelection: { pid in
                await log.record("copy:\(pid)")
                if rendezvous { await log.waitFor("browser:") }
                return copied
            }
        ))
    }

    private func app(_ bundleID: String) -> RunningAppInfo {
        RunningAppInfo(app: AppReference(bundleID: bundleID, name: bundleID), processID: 4242)
    }

    private nonisolated static let contextScript = #"printf '%s %s' "$NONET_BROWSER_URL" "$NONET_SELECTED_TEXT""#

    @Test("変数を使うスクリプトには、Safari の URL と、アクセシビリティで読めない選択（⌘C）を渡す")
    func scriptInBrowser() async {
        let log = CallLog()
        let reading = await reader(selection: .unreadable, log: log).read(.forScript(source: Self.contextScript), app: app("com.apple.Safari"))
        let info = reading.info
        #expect(reading.selectionSource == .copyAfterUnreadable)
        #expect(info.browserURL == Self.url)
        #expect(info.selectedText == "⌘C で取った文")
        #expect(info.app?.bundleID == "com.apple.Safari")
        let calls = await log.calls
        #expect(calls.contains("browser:com.apple.Safari"))
        #expect(calls.contains("copy:4242"))
        #expect(calls.contains("documentPath"))
    }

    @Test("変数を使わないスクリプトは、⌘C を送らず、ブラウザにも聞かない（書類の場所だけ読む）")
    func scriptWithoutContextVariables() async {
        let log = CallLog()
        let reading = await reader(selection: .unreadable, documentPath: "/tmp/doc.txt", log: log)
            .read(.forScript(source: "open -b com.apple.dt.Devices"), app: app("com.google.Chrome"))
        #expect(reading.info == ScriptContextInfo(
            app: AppReference(bundleID: "com.google.Chrome", name: "com.google.Chrome"),
            documentPath: "/tmp/doc.txt"
        ))
        #expect(await log.calls == ["documentPath"])
    }

    @Test("ブラウザでないアプリには osascript で聞かない")
    func scriptOutsideBrowser() async {
        let log = CallLog()
        let reading = await reader(selection: .text("選択"), documentPath: "/tmp/App/App.xcodeproj", log: log)
            .read(.forScript(source: Self.contextScript), app: app("com.apple.dt.Xcode"))
        #expect(reading.selectionSource == .accessibility)
        #expect(reading.info == ScriptContextInfo(
            app: AppReference(bundleID: "com.apple.dt.Xcode", name: "com.apple.dt.Xcode"),
            documentPath: "/tmp/App/App.xcodeproj",
            selectedText: "選択"
        ))
        let calls = await log.calls
        #expect(!calls.contains { $0.hasPrefix("browser") })
        #expect(!calls.contains { $0.hasPrefix("copy") })
    }

    @Test("スクリプト: 選択が空と読めたら ⌘C は送らない。AI は送る")
    func emptySelection() async {
        let scriptLog = CallLog()
        let script = await reader(selection: .empty, log: scriptLog).read(.forScript(source: Self.contextScript), app: app("com.apple.dt.Xcode"))
        #expect(script.info.selectedText == nil)
        #expect(await !scriptLog.calls.contains { $0.hasPrefix("copy") })

        let aiLog = CallLog()
        let ai = await reader(selection: .empty, log: aiLog).read(.forAI, app: app("com.apple.dt.Xcode"))
        #expect(ai.info.selectedText == "⌘C で取った文")
        // 置き換えてよいかは分からない
        #expect(ai.selectionSource == .copyAfterEmpty)
        #expect(await aiLog.calls.contains("copy:4242"))
    }

    @Test("⌘C でも取れなければ選択テキストは無し")
    func copyFindsNothing() async {
        let log = CallLog()
        let reading = await reader(selection: .unreadable, copied: .nothing, log: log)
            .read(.forShortcut(ShortcutAction(name: "X", passSelectedText: true)), app: app("com.tinyspeck.slackmacgap"))
        let info = reading.info
        #expect(reading.selectionSource == nil)
        #expect(reading.copyUnavailable == nil)
        #expect(info.selectedText == nil)
        #expect(info.browserURL == nil)
        #expect(info.documentPath == nil)
        #expect(await log.calls == ["selection", "copy:4242"])
    }

    @Test("クリップボードの中身を保てずに ⌘C を送らなかったことが分かる")
    func copySkipped() async {
        let reading = await reader(selection: .unreadable, copied: .clipboardUnavailable(.tooLarge), log: CallLog())
            .read(.forAI, app: app("com.tinyspeck.slackmacgap"))
        #expect(reading.info.selectedText == nil)
        #expect(reading.copyUnavailable == .tooLarge)
    }

    @Test("VS Code で何も選択せずに ⌘C で取れた1行は、選択テキストにしない")
    func lineCopyIsNotASelection() async {
        let line = "let total = items.reduce(0, +)\n"
        let vscode = await reader(selection: .unreadable, copied: .copied(line), log: CallLog()).read(.forAI, app: app("com.microsoft.VSCode"))
        #expect(vscode.info.selectedText == nil)
        #expect(vscode.selectionSource == nil)
        #expect(vscode.ignoredLineCopy)
        let slack = await reader(selection: .unreadable, copied: .copied(line), log: CallLog()).read(.forAI, app: app("com.tinyspeck.slackmacgap"))
        #expect(slack.info.selectedText == line)
        #expect(!slack.ignoredLineCopy)
    }

    @Test("ブラウザへの問い合わせは、選択テキストを読むのと並べて行う")
    func browserRunsConcurrently() async {
        let log = CallLog()
        let info = await reader(selection: .unreadable, log: log, rendezvous: true)
            .read(.forScript(source: Self.contextScript), app: app("com.google.Chrome")).info
        #expect(info.browserURL == Self.url)
        #expect(info.selectedText == "⌘C で取った文")
        let calls = await log.calls
        #expect(calls.contains("browser:com.google.Chrome"))
        #expect(calls.contains("copy:4242"))
        // どちらを先にしても、順に読んでいれば先のほうが相手を待ちきれない
        #expect(!calls.contains { $0.hasPrefix("timeout") }, "\(calls)")
    }
}

@Suite("AI アクション")
struct ActionAITests {
    @Test("指示文の後に区切りと選択テキストを付ける")
    func prompt() {
        #expect(OnDeviceAI.prompt(instruction: "  要約して\n", text: "本文\n2行目") == "要約して\n\n---\n本文\n2行目")
    }

    @Test("使えない環境では理由つきの unavailable、使えるなら何も投げない")
    func availability() {
        do {
            try OnDeviceAI.checkAvailability()
        } catch let error as NonetError {
            guard case .unavailable(let reason) = error else {
                Issue.record("unavailable になるはず: \(error)")
                return
            }
            #expect(!reason.isEmpty)
        } catch {
            Issue.record("NonetError になるはず: \(error)")
        }
    }
}
