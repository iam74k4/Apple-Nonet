import Foundation
import NonetCore
@testable import NonetPlatform
import Testing

/// Finder に頼む前の確かめ・Finder への依頼・失敗の読み替え。Finder は動かさず、osascript を偽物にする
@Suite("ファイルの操作")
@MainActor
struct ActionFileTests {
    static let finder = RunningAppInfo(app: AppReference(bundleID: "com.apple.finder", name: "Finder"), processID: 100)
    static let safari = RunningAppInfo(app: AppReference(bundleID: "com.apple.Safari", name: "Safari"), processID: 200)
    static let home = "/Users/tester"

    /// 呼ばれた依頼を覚えて、決めた出力を返す
    final class FakeOsascript: OsascriptRunning, @unchecked Sendable {
        struct Call: Equatable {
            var language: String
            var source: String
            var arguments: [String]
        }

        private let lock = NSLock()
        private var recorded: [Call] = []
        var selection: String
        var failure: ProcessOutput?

        init(selection: String = "[]", failure: ProcessOutput? = nil) {
            self.selection = selection
            self.failure = failure
        }

        var calls: [Call] {
            lock.lock()
            defer { lock.unlock() }
            return recorded
        }

        private func record(_ call: Call) {
            lock.lock()
            recorded.append(call)
            lock.unlock()
        }

        func run(_ language: OsascriptLanguage, source: String, arguments: [String], timeout: TimeInterval) async throws -> ProcessOutput {
            record(Call(language: language == .javaScript ? "js" : "as", source: source, arguments: arguments))
            if language == .javaScript {
                return ProcessOutput(status: 0, wasSignaled: false, timedOut: false, stdout: selection, stderr: "")
            }
            return failure ?? ProcessOutput(status: 0, wasSignaled: false, timedOut: false, stdout: "", stderr: "")
        }
    }

    struct FakePrompt: RenamePrompting {
        var answer: String?
        func requestName(currentName: String) async -> String? { answer }
    }

    private func urls(_ paths: [String]) -> String {
        let list = paths.map { "file://" + ($0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? $0) }
        return String(decoding: (try? JSONEncoder().encode(list)) ?? Data(), as: UTF8.self)
    }

    private func runner(_ osascript: FakeOsascript, answer: String? = nil, directories: Set<String> = ["/Users/tester/Documents"]) -> FileActionRunner {
        FileActionRunner(osascript: osascript, prompt: FakePrompt(answer: answer), home: Self.home, directoryExists: { directories.contains($0) })
    }

    private func message(of error: any Error) -> String? {
        (error as? NonetError)?.errorDescription
    }

    // MARK: Finder の選択

    @Test("選択の読み取りは、日本語やスペースを含む file:// の URL をパスに直す")
    func parsesTheSelection() {
        let output = urls(["/Users/tester/書類/見積 2026.pdf", "/Users/tester/フォルダ"]) + "\n"
        #expect(FinderSelection.parse(output) == ["/Users/tester/書類/見積 2026.pdf", "/Users/tester/フォルダ"])
        #expect(FinderSelection.parse("[]") == [])
        // ファイルの URL でないものと、値の無いものは捨てる
        #expect(FinderSelection.parse(#"["https://example.com/a", null, "file:///tmp/a"]"#) == ["/tmp/a"])
        // 読めない出力は nil（空の選択とは別）
        #expect(FinderSelection.parse("missing value") == nil)
        #expect(FinderSelection.parse("") == nil)
    }

    @Test("名前に改行を含むファイルも、1つのパスとして読む")
    func newlinesInNamesStayInOnePath() {
        let output = urls(["/Users/tester/a\nb.txt"])
        #expect(FinderSelection.parse(output) == ["/Users/tester/a\nb.txt"])
    }

    // MARK: 前面のアプリ

    @Test("Finder が前面でないときは、選択を読まずに知らせる")
    func requiresFinderInFront() async {
        let osascript = FakeOsascript(selection: urls(["/Users/tester/a.txt"]))
        for frontmost in [Self.safari, nil] {
            await #expect(throws: NonetError.self) {
                try await runner(osascript).run(FileAction(operation: .trash), frontmost: frontmost)
            }
        }
        #expect(osascript.calls.isEmpty)
    }

    // MARK: 選択の確かめ

    @Test("何も選んでいないときは、何も動かさない")
    func emptySelectionDoesNothing() async {
        let osascript = FakeOsascript(selection: "[]")
        await #expect(throws: NonetError.self) {
            try await runner(osascript).run(FileAction(operation: .trash), frontmost: Self.finder)
        }
        #expect(osascript.calls.map(\.language) == ["js"])
    }

    @Test("読めない出力のときは、何も動かさない")
    func unreadableSelectionDoesNothing() async {
        let osascript = FakeOsascript(selection: "oops")
        await #expect(throws: NonetError.self) {
            try await runner(osascript).run(FileAction(operation: .trash), frontmost: Self.finder)
        }
        #expect(osascript.calls.map(\.language) == ["js"])
    }

    @Test("多すぎる選択は動かさない。開くのは20個まで")
    func tooManyFiles() async throws {
        let many = (0...FinderSelection.limit).map { "/Users/tester/f\($0).txt" }
        let osascript = FakeOsascript(selection: urls(many))
        await #expect(throws: NonetError.self) {
            try await runner(osascript).run(FileAction(operation: .trash), frontmost: Self.finder)
        }
        let some = FakeOsascript(selection: urls((0...FinderSelection.openLimit).map { "/Users/tester/f\($0).txt" }))
        await #expect(throws: NonetError.self) {
            try await runner(some).run(FileAction(operation: .open), frontmost: Self.finder)
        }
        #expect(some.calls.map(\.language) == ["js"])
        // 20個ちょうどなら開く
        let exact = FakeOsascript(selection: urls((1...FinderSelection.openLimit).map { "/Users/tester/f\($0).txt" }))
        try await runner(exact).run(FileAction(operation: .open), frontmost: Self.finder)
        #expect(exact.calls.last?.arguments.count == FinderSelection.openLimit)
    }

    @Test("ゴミ箱の中のファイルや、ホーム・ディスクの一番上は、ゴミ箱に入れない")
    func refusesProtectedAndTrashedItems() async {
        let protectedPaths = [
            "/Users/tester/.Trash/old.txt", "/Volumes/Backup/.Trashes/501/x", "/Users/tester", "/Applications", "/Volumes/Backup", "/",
        ]
        for path in protectedPaths {
            let osascript = FakeOsascript(selection: urls([path]))
            await #expect(throws: NonetError.self) {
                try await runner(osascript).run(FileAction(operation: .trash), frontmost: Self.finder)
            }
            #expect(osascript.calls.map(\.language) == ["js"], "\(path)")
        }
    }

    @Test("ゴミ箱の中のファイルは、ゴミ箱の外へ移せる")
    func trashedItemsCanBeMovedOut() async throws {
        let osascript = FakeOsascript(selection: urls(["/Users/tester/.Trash/old.txt"]))
        try await runner(osascript).run(FileAction(operation: .move, destination: "/Users/tester/Documents"), frontmost: Self.finder)
        #expect(osascript.calls.last?.arguments == ["/Users/tester/Documents", "/Users/tester/.Trash/old.txt"])
    }

    // MARK: 各操作

    @Test("ゴミ箱に入れる: 選んだファイルのパスを、そのまま引数で渡す")
    func trashesTheSelection() async throws {
        let paths = ["/Users/tester/a \"1\".txt", "/Users/tester/-b.txt", "/Users/tester/書類"]
        let osascript = FakeOsascript(selection: urls(paths))
        try await runner(osascript).run(FileAction(operation: .trash), frontmost: Self.finder)
        let call = try #require(osascript.calls.last)
        #expect(osascript.calls.map(\.language) == ["js", "as"])
        #expect(call.source == FileScripts.trash)
        #expect(call.source.contains("delete targets"))
        #expect(call.arguments == paths)
    }

    @Test("開く・複製は、それぞれの依頼を選んだファイルに出す")
    func opensAndDuplicates() async throws {
        let osascript = FakeOsascript(selection: urls(["/Users/tester/a.txt"]))
        try await runner(osascript).run(FileAction(operation: .open), frontmost: Self.finder)
        try await runner(osascript).run(FileAction(operation: .duplicate), frontmost: Self.finder)
        let scripts = osascript.calls.filter { $0.language == "as" }
        #expect(scripts.map(\.source) == [FileScripts.open, FileScripts.duplicate])
        #expect(scripts.allSatisfy { $0.arguments == ["/Users/tester/a.txt"] })
    }

    @Test("移動: 先頭の引数が移動先（前後の空白と末尾の / は除く）。フォルダが無ければ選択も読まない")
    func movesToTheDestination() async throws {
        let osascript = FakeOsascript(selection: urls(["/Users/tester/a.txt", "/Users/tester/b.txt"]))
        let spaced = FileAction(operation: .move, destination: "  /Users/tester/Documents/  ")
        try await runner(osascript).run(spaced, frontmost: Self.finder)
        let call = try #require(osascript.calls.last)
        #expect(call.source == FileScripts.move)
        #expect(call.arguments == ["/Users/tester/Documents", "/Users/tester/a.txt", "/Users/tester/b.txt"])

        let missing = FakeOsascript(selection: urls(["/Users/tester/a.txt"]))
        for destination in ["", "   ", "/Users/tester/Nowhere", "relative/path"] {
            await #expect(throws: NonetError.self) {
                try await runner(missing).run(FileAction(operation: .move, destination: destination), frontmost: Self.finder)
            }
        }
        #expect(missing.calls.isEmpty)
    }

    @Test("名前を変える: ダイアログで入力した名前を、前後の空白を除いて渡す")
    func renames() async throws {
        let osascript = FakeOsascript(selection: urls(["/Users/tester/a.txt"]))
        try await runner(osascript, answer: "  b \"2\".txt \n").run(FileAction(operation: .rename), frontmost: Self.finder)
        let call = try #require(osascript.calls.last)
        #expect(call.source == FileScripts.rename)
        #expect(call.arguments == ["/Users/tester/a.txt", "b \"2\".txt"])
    }

    @Test("名前を変える: やめたとき・同じ名前・使えない名前・複数選択では変えない")
    func renameDoesNothingWhenNotNeeded() async throws {
        let one = FakeOsascript(selection: urls(["/Users/tester/a.txt"]))
        try await runner(one, answer: nil).run(FileAction(operation: .rename), frontmost: Self.finder)
        try await runner(one, answer: "a.txt").run(FileAction(operation: .rename), frontmost: Self.finder)
        #expect(one.calls.allSatisfy { $0.language == "js" })

        for name in ["", "  ", ".", "..", "x/y", "x:y", "a\nb", String(repeating: "あ", count: 100)] {
            await #expect(throws: NonetError.self) {
                try await runner(one, answer: name).run(FileAction(operation: .rename), frontmost: Self.finder)
            }
        }
        #expect(one.calls.allSatisfy { $0.language == "js" })

        let two = FakeOsascript(selection: urls(["/Users/tester/a.txt", "/Users/tester/b.txt"]))
        await #expect(throws: NonetError.self) {
            try await runner(two, answer: "c.txt").run(FileAction(operation: .rename), frontmost: Self.finder)
        }
        #expect(two.calls.map(\.language) == ["js"])
    }

    // MARK: Finder からの失敗

    private func failed(_ stderr: String, status: Int32 = 1, timedOut: Bool = false) -> ProcessOutput {
        ProcessOutput(status: status, wasSignaled: false, timedOut: timedOut, stdout: "", stderr: stderr)
    }

    @Test("オートメーションの許可が無いときは、許可が要ることを知らせる")
    func reportsMissingAutomationPermission() async {
        let osascript = FakeOsascript(
            selection: urls(["/Users/tester/a.txt"]),
            failure: failed("execution error: Finder へ Apple イベントを送信する権限がありません。 (-1743)")
        )
        await #expect(throws: NonetError.permissionDenied(ActionText.finderAutomation)) {
            try await runner(osascript).run(FileAction(operation: .trash), frontmost: Self.finder)
        }
    }

    @Test("失敗の番号を、分かる言葉にする")
    func mapsErrorNumbers() {
        func error(_ stderr: String) -> NonetError? { FinderScriptFailure.error(for: failed(stderr)) }
        #expect(error("12:20: execution error: エラー (-1743)") == .permissionDenied(ActionText.finderAutomation))
        #expect(error("execution error: Finder は起動していません。 (-600)") != nil)
        for number in [-48, -15267, -1728, -1700] {
            let reason = error("129:134: execution error: 失敗 (\(number))")
            #expect(reason != nil)
            #expect(reason != .permissionDenied(ActionText.finderAutomation))
        }
        // 知らない番号でも、標準エラーの末尾を添えて知らせる
        #expect(error("execution error: こわれた (-99999)")?.errorDescription?.contains("こわれた") == true)
        #expect(error("") != nil)
        #expect(FinderScriptFailure.error(for: failed("", status: 0, timedOut: true)) == .timedOut)
        #expect(FinderScriptFailure.error(for: ProcessOutput(status: 0, wasSignaled: false, timedOut: false, stdout: "", stderr: "")) == nil)
    }

    @Test("エラーの番号は、最後の行の終わりの括弧から読む")
    func readsTheErrorNumber() {
        #expect(FinderScriptFailure.errorNumber(in: "a (1)\nexecution error: x (-1743)\n\n") == -1743)
        #expect(FinderScriptFailure.errorNumber(in: "execution error: x") == nil)
        #expect(FinderScriptFailure.errorNumber(in: "") == nil)
        #expect(FinderScriptFailure.errorNumber(in: "x (abc)") == nil)
    }

    // MARK: 依頼の書き方

    @Test("依頼の文には、ファイルのパスも名前も埋め込まない（引数で渡す）")
    func scriptsTakeEverythingFromArguments() {
        for script in [FileScripts.open, FileScripts.trash, FileScripts.duplicate, FileScripts.move, FileScripts.rename] {
            #expect(script.contains("on run argv"))
            #expect(!script.contains("/Users"))
            // 完全な削除（empty trash・rm・delete のあとの permanently）は使わない
            #expect(!script.contains("empty"))
            #expect(!script.contains("rm "))
        }
        #expect(FileScripts.trash.contains("delete targets"))
        #expect(!FileScripts.move.contains("replacing"))
    }

    @Test("移動先は存在するフォルダだけ。~ はホームに直す")
    func destinations() throws {
        let directory = try ActionTemporaryDirectory()
        let folder = try directory.subdirectory("dest")
        let file = directory.url.appendingPathComponent("file.txt")
        try Data().write(to: file)
        #expect(FilePlan.destination(folder.path) == folder.path)
        #expect(FilePlan.destination("  \(folder.path)  ") == folder.path)
        #expect(FilePlan.destination(file.path) == nil)
        #expect(FilePlan.destination("") == nil)
        #expect(FilePlan.destination("dest") == nil)
        let home = FilePlan.destination("~")
        #expect(home == (NSHomeDirectory() as NSString).expandingTildeInPath)
    }

    @Test("名前の確かめ: 前後の空白を除き、255バイトまで")
    func nameValidation() throws {
        #expect(try FilePlan.validatedName("  報告書 final.docx ").get() == "報告書 final.docx")
        #expect(try FilePlan.validatedName(String(repeating: "a", count: 255)).get().utf8.count == 255)
        #expect(throws: NonetError.self) { try FilePlan.validatedName(String(repeating: "a", count: 256)).get() }
        #expect(throws: NonetError.self) { try FilePlan.validatedName(String(repeating: "あ", count: 86)).get() }
    }
}
