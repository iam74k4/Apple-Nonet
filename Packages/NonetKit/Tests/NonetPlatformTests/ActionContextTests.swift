import AppKit
import NonetCore
@testable import NonetPlatform
import Testing

@Suite("アクションの文脈")
struct ActionContextTests {
    @Test("スクリプト: 副作用の無いものは常に、⌘C とブラウザは変数が書かれているときだけ")
    func scriptNeeds() {
        let plain = ContextNeeds.forScript(source: "open -a Simulator")
        #expect(plain == [.selectedText, .documentPath])

        let selected = ContextNeeds.forScript(source: #"echo "$NONET_SELECTED_TEXT" | pbcopy"#)
        #expect(selected.contains([.selectedText, .copyFallback, .documentPath]))
        #expect(!selected.contains(.browserURL))

        let browser = ContextNeeds.forScript(source: "~/bin/summarize.sh \"$NONET_BROWSER_URL\"")
        #expect(browser.contains(.browserURL))
        #expect(!browser.contains(.copyFallback))
    }

    @Test("ショートカットは passSelectedText のときだけ選択テキスト、AI は常に選択テキスト")
    func otherNeeds() {
        #expect(ContextNeeds.forShortcut(ShortcutAction(name: "X")).isEmpty)
        #expect(ContextNeeds.forShortcut(ShortcutAction(name: "X", passSelectedText: true)) == [.selectedText, .copyFallback])
        #expect(ContextNeeds.forAI == [.selectedText, .copyFallback])
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
