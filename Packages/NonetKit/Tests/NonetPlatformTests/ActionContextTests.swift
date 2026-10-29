import AppKit
import NonetCore
@testable import NonetPlatform
import Testing

@Suite("アクションの文脈")
struct ActionContextTests {
    @Test("スクリプトにはソースの書き方によらず、ScriptEnvironment の変数をすべて用意する")
    func scriptNeeds() {
        // 外部のファイルを呼ぶだけのスクリプトでも、変数を読むのはそのファイルの中
        #expect(ContextNeeds.forScript == [.selectedText, .copyFallback, .documentPath, .browserURL])
        // 選択が空と読めたときは ⌘C を送らない（警告音が鳴るだけ）
        #expect(!ContextNeeds.forScript.contains(.copyWhenEmpty))
    }

    @Test("ショートカットは passSelectedText のときだけ選択テキスト、AI は常に選択テキスト")
    func otherNeeds() {
        #expect(ContextNeeds.forShortcut(ShortcutAction(name: "X")).isEmpty)
        #expect(ContextNeeds.forShortcut(ShortcutAction(name: "X", passSelectedText: true)) == [.selectedText, .copyFallback, .copyWhenEmpty])
        #expect(ContextNeeds.forAI == [.selectedText, .copyFallback, .copyWhenEmpty])
    }

    @Test("⌘C を送るのは、選択を読めないとき。選択が空と読めたときは、選択テキストを処理するアクションだけ")
    func copyDecision() {
        #expect(ContextNeeds.forScript.needsCopy(after: .unreadable))
        #expect(!ContextNeeds.forScript.needsCopy(after: .empty))
        #expect(!ContextNeeds.forScript.needsCopy(after: .text("選択")))
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
        for id in ["com.apple.Safari", "com.google.Chrome", "company.thebrowser.Browser", "com.microsoft.edgemac", "com.brave.Browser"] {
            #expect(ContextNeeds.forScript.asksBrowser(bundleID: id), "\(id)")
        }
        #expect(!ContextNeeds.forScript.asksBrowser(bundleID: "com.apple.dt.Xcode"))
        #expect(!ContextNeeds.forScript.asksBrowser(bundleID: "org.mozilla.firefox"))
        #expect(!ContextNeeds.forAI.asksBrowser(bundleID: "com.apple.Safari"))
    }

    @Test("何も要らなければ何も読まない")
    @MainActor
    func emptyNeedsReadNothing() async {
        let reader = ContextReader(keySender: KeySender())
        let app = RunningAppInfo(app: AppReference(bundleID: "com.example.app", name: "App"), processID: 1)
        let info = await reader.read([], app: app)
        #expect(info == ScriptContextInfo(app: app.app))
        let none = await reader.read([.selectedText, .documentPath], app: nil)
        #expect(none == ScriptContextInfo())
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

        /// prefix で始まる呼び出しを待つ（最大 2 秒）。並べて動いていなければ来ないので、時間切れを記録して先へ進む
        func waitFor(_ prefix: String) async {
            for _ in 0 ..< 200 {
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
        copied: String? = "⌘C で取った文",
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
            copySelection: {
                await log.record("copy")
                if rendezvous { await log.waitFor("browser:") }
                return copied
            }
        ))
    }

    private func app(_ bundleID: String) -> RunningAppInfo {
        RunningAppInfo(app: AppReference(bundleID: bundleID, name: bundleID), processID: 4242)
    }

    @Test("外部のスクリプトを呼ぶだけでも、Safari の URL と、アクセシビリティで読めない選択（⌘C）を渡す")
    func scriptInBrowser() async {
        let log = CallLog()
        let info = await reader(selection: .unreadable, log: log).read(.forScript, app: app("com.apple.Safari"))
        #expect(info.browserURL == Self.url)
        #expect(info.selectedText == "⌘C で取った文")
        #expect(info.app?.bundleID == "com.apple.Safari")
        let calls = await log.calls
        #expect(calls.contains("browser:com.apple.Safari"))
        #expect(calls.contains("copy"))
        #expect(calls.contains("documentPath"))
    }

    @Test("ブラウザでないアプリには osascript で聞かない")
    func scriptOutsideBrowser() async {
        let log = CallLog()
        let info = await reader(selection: .text("選択"), documentPath: "/tmp/App/App.xcodeproj", log: log)
            .read(.forScript, app: app("com.apple.dt.Xcode"))
        #expect(info == ScriptContextInfo(
            app: AppReference(bundleID: "com.apple.dt.Xcode", name: "com.apple.dt.Xcode"),
            documentPath: "/tmp/App/App.xcodeproj",
            selectedText: "選択"
        ))
        let calls = await log.calls
        #expect(!calls.contains { $0.hasPrefix("browser") })
        #expect(!calls.contains("copy"))
    }

    @Test("スクリプト: 選択が空と読めたら ⌘C は送らない。AI は送る")
    func emptySelection() async {
        let scriptLog = CallLog()
        let script = await reader(selection: .empty, log: scriptLog).read(.forScript, app: app("com.apple.dt.Xcode"))
        #expect(script.selectedText == nil)
        #expect(await !scriptLog.calls.contains("copy"))

        let aiLog = CallLog()
        let ai = await reader(selection: .empty, log: aiLog).read(.forAI, app: app("com.apple.dt.Xcode"))
        #expect(ai.selectedText == "⌘C で取った文")
        #expect(await aiLog.calls.contains("copy"))
    }

    @Test("⌘C でも取れなければ選択テキストは無し")
    func copyFindsNothing() async {
        let log = CallLog()
        let info = await reader(selection: .unreadable, copied: nil, log: log).read(.forShortcut(ShortcutAction(name: "X", passSelectedText: true)), app: app("com.tinyspeck.slackmacgap"))
        #expect(info.selectedText == nil)
        #expect(info.browserURL == nil)
        #expect(info.documentPath == nil)
        #expect(await log.calls == ["selection", "copy"])
    }

    @Test("ブラウザへの問い合わせは、選択テキストを読むのと並べて行う")
    func browserRunsConcurrently() async {
        let log = CallLog()
        let info = await reader(selection: .unreadable, log: log, rendezvous: true)
            .read(.forScript, app: app("com.google.Chrome"))
        #expect(info.browserURL == Self.url)
        #expect(info.selectedText == "⌘C で取った文")
        let calls = await log.calls
        #expect(calls.contains("browser:com.google.Chrome"))
        #expect(calls.contains("copy"))
        // どちらを先にしても、順に読んでいれば先のほうが相手を待ちきれない
        #expect(!calls.contains { $0.hasPrefix("timeout") }, "\(calls)")
    }
}

/// 利用者のクリップボードには触らず、名前付きの別のクリップボードで確かめる
@Suite("クリップボードの写しと書き込み")
@MainActor
struct ActionPasteboardTests {
    private func withPrivatePasteboard(_ body: (NSPasteboard) throws -> Void) rethrows {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.iam74k4.Nonet.tests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        try body(pasteboard)
    }

    @Test("書いて戻すと、複数の項目と型が元どおり")
    func snapshotRestores() throws {
        try withPrivatePasteboard { pasteboard in
            let custom = NSPasteboard.PasteboardType("com.iam74k4.nonet.test")
            let first = NSPasteboardItem()
            first.setString("元のテキスト", forType: .string)
            first.setData(Data([1, 2, 3]), forType: custom)
            let second = NSPasteboardItem()
            second.setString("2つめ", forType: .string)
            pasteboard.clearContents()
            pasteboard.writeObjects([first, second])

            let snapshot = PasteboardSnapshot(pasteboard)
            #expect(!snapshot.isEmpty)
            let count = PasteboardWriter.write("AI の結果", to: pasteboard, transient: true)
            #expect(count == pasteboard.changeCount)
            #expect(pasteboard.string(forType: .string) == "AI の結果")
            #expect(pasteboard.types?.contains(PasteboardWriter.transientType) == true)

            snapshot.restore(to: pasteboard)
            let items = try #require(pasteboard.pasteboardItems)
            #expect(items.count == 2)
            #expect(items[0].string(forType: .string) == "元のテキスト")
            #expect(items[0].data(forType: custom) == Data([1, 2, 3]))
            #expect(items[1].string(forType: .string) == "2つめ")
        }
    }

    @Test("空のクリップボードは空に戻す")
    func restoresEmpty() {
        withPrivatePasteboard { pasteboard in
            pasteboard.clearContents()
            let snapshot = PasteboardSnapshot(pasteboard)
            #expect(snapshot.isEmpty)
            PasteboardWriter.write("一時的", to: pasteboard)
            #expect(pasteboard.types?.contains(PasteboardWriter.transientType) == false)
            snapshot.restore(to: pasteboard)
            #expect(pasteboard.string(forType: .string) == nil)
        }
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
