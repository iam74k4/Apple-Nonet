import Foundation
import NonetCore
@testable import NonetPlatform
import Testing

/// Finder に頼む前の確かめ・Finder への依頼・失敗の読み替え。Finder は動かさず、osascript とキーの送りを偽物にする
@Suite("ファイルの操作")
@MainActor
struct ActionFileTests {
    static let home = "/Users/tester"
    static let finderID = "com.apple.finder"

    /// 呼ばれた依頼を覚えて、決めた出力を返す
    final class FakeOsascript: OsascriptRunning, @unchecked Sendable {
        struct Call: Equatable {
            var language: String
            var source: String
            var arguments: [String]
            var timeout: TimeInterval
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
            record(Call(language: language == .javaScript ? "js" : "as", source: source, arguments: arguments, timeout: timeout))
            if language == .javaScript {
                return ProcessOutput(status: 0, wasSignaled: false, timedOut: false, stdout: selection, stderr: "")
            }
            return failure ?? ProcessOutput(status: 0, wasSignaled: false, timedOut: false, stdout: "", stderr: "")
        }
    }

    final class FakeKeys: KeySending {
        var sent: [[KeyChord]] = []
        func send(_ sequence: KeySequence) async throws { sent.append(sequence.chords) }
    }

    /// 前面のアプリの bundleID を、呼ばれるたびに順に返す（最後のものを返し続ける）
    final class Frontmost {
        var ids: [String?]
        private(set) var asked = 0

        init(_ ids: [String?]) { self.ids = ids }

        func next() -> String? {
            defer { asked += 1 }
            return ids[min(asked, ids.count - 1)]
        }
    }

    private func urls(_ paths: [String]) -> String {
        let list = paths.map { "file://" + ($0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? $0) }
        return String(decoding: (try? JSONEncoder().encode(list)) ?? Data(), as: UTF8.self)
    }

    private func runner(_ osascript: FakeOsascript, keys: FakeKeys? = nil, frontmost: Frontmost? = nil) -> FileActionRunner {
        let keys = keys ?? FakeKeys()
        let frontmost = frontmost ?? Frontmost([Self.finderID])
        return FileActionRunner(keys: keys, osascript: osascript, home: Self.home, frontmostBundleID: { frontmost.next() })
    }

    // MARK: Finder の選択

    @Test("選択の読み取りは、日本語やスペースを含む file:// の URL をパスに直す")
    func parsesTheSelection() {
        let output = urls(["/Users/tester/書類/見積 2026.pdf", "/Users/tester/フォルダ"]) + "\n"
        #expect(FinderSelection.parse(output) == ["/Users/tester/書類/見積 2026.pdf", "/Users/tester/フォルダ"])
        #expect(FinderSelection.parse("[]") == [])
        // 末尾に / の付くフォルダの URL
        #expect(FinderSelection.parse(#"["file:///Users/tester/%E6%9B%B8%E9%A1%9E/"]"#) == ["/Users/tester/書類"])
        // 読めない出力は nil（空の選択とは別）
        #expect(FinderSelection.parse("missing value") == nil)
        #expect(FinderSelection.parse("") == nil)
    }

    @Test("ファイルの URL でないものが1つでもあれば、一部だけを動かさないよう全体を読めなかったことにする")
    func anItemThatIsNotAFileMakesTheWholeSelectionUnreadable() {
        #expect(FinderSelection.parse(#"["https://example.com/a", "file:///tmp/a"]"#) == nil)
        #expect(FinderSelection.parse(#"[null, "file:///tmp/a"]"#) == nil)
        #expect(FinderSelection.parse(#"["file:///tmp/a", ""]"#) == nil)
    }

    @Test("名前に改行を含むファイルも、1つのパスとして読む")
    func newlinesInNamesStayInOnePath() {
        let output = urls(["/Users/tester/a\nb.txt"])
        #expect(FinderSelection.parse(output) == ["/Users/tester/a\nb.txt"])
    }

    @Test("選択を読む制限時間は、初めての許可の確認に答える間も待てる長さ")
    func theReadWaitsForThePermissionPrompt() async throws {
        let osascript = FakeOsascript(selection: urls(["/Users/tester/a.txt"]))
        try await runner(osascript).run(FileAction(operation: .trash))
        #expect(osascript.calls.first?.timeout == FinderSelection.readTimeout)
        #expect(FinderSelection.readTimeout >= 30)
    }

    // MARK: 前面のアプリ

    @Test("Finder が前面でないときは、選択を読まずに知らせる")
    func requiresFinderInFront() async {
        let osascript = FakeOsascript(selection: urls(["/Users/tester/a.txt"]))
        for front in ["com.apple.Safari", nil] as [String?] {
            await #expect(throws: NonetError.self) {
                try await runner(osascript, frontmost: Frontmost([front])).run(FileAction(operation: .trash))
            }
        }
        #expect(osascript.calls.isEmpty)
    }

    @Test("実行する直前の前面アプリで確かめる。選択を読んでいる間に別のアプリが前面になったら、何も動かさない")
    func checksTheFrontAppAgainAfterReadingTheSelection() async {
        let osascript = FakeOsascript(selection: urls(["/Users/tester/a.txt"]))
        let frontmost = Frontmost([Self.finderID, "com.apple.Preview"])
        await #expect(throws: NonetError.self) {
            try await runner(osascript, frontmost: frontmost).run(FileAction(operation: .trash))
        }
        #expect(osascript.calls.map(\.language) == ["js"])
        #expect(frontmost.asked == 2)
    }

    // MARK: 選択の確かめ

    @Test("何も選んでいない・読めない出力のときは、何も動かさない")
    func emptyOrUnreadableSelectionDoesNothing() async {
        for selection in ["[]", "oops", #"["https://example.com/a"]"#] {
            let osascript = FakeOsascript(selection: selection)
            await #expect(throws: NonetError.self) {
                try await runner(osascript).run(FileAction(operation: .trash))
            }
            #expect(osascript.calls.map(\.language) == ["js"], Comment(rawValue: selection))
        }
    }

    @Test("多すぎる選択は動かさない")
    func tooManyFiles() async throws {
        let many = (0...FinderSelection.limit).map { "/Users/tester/f\($0).txt" }
        let osascript = FakeOsascript(selection: urls(many))
        await #expect(throws: NonetError.self) {
            try await runner(osascript).run(FileAction(operation: .trash))
        }
        #expect(osascript.calls.map(\.language) == ["js"])
        // 上限ちょうどなら動かす
        let exact = FakeOsascript(selection: urls((1...FinderSelection.limit).map { "/Users/tester/f\($0).txt" }))
        try await runner(exact).run(FileAction(operation: .duplicate))
        #expect(exact.calls.last?.arguments.count == FinderSelection.limit)
    }

    @Test("ゴミ箱の中のファイルは、ゴミ箱に入れない")
    func refusesFilesAlreadyInTheTrash() async {
        for path in ["/Users/tester/.Trash/old.txt", "/Volumes/Backup/.Trashes/501/x"] {
            let osascript = FakeOsascript(selection: urls([path]))
            await #expect(throws: NonetError.self) {
                try await runner(osascript).run(FileAction(operation: .trash))
            }
            #expect(osascript.calls.map(\.language) == ["js"], Comment(rawValue: path))
        }
    }

    @Test("ホーム・ホームの標準のフォルダ・ディスクの一番上・システムのフォルダ・ほかの利用者のホーム・クラウドの置き場は動かさない",
          arguments: [
              "/Users/tester", "/Users/tester/Desktop", "/Users/tester/Documents", "/Users/tester/Downloads", "/Users/tester/Library",
              "/Users/tester/Library/CloudStorage/Dropbox", "/Users/other", "/Applications", "/Volumes/Backup", "/System", "/",
          ])
    func refusesProtectedPlacesForEveryOperation(path: String) async {
        for operation in FileOperation.allCases {
            let osascript = FakeOsascript(selection: urls([path]))
            await #expect(throws: NonetError.self) {
                try await runner(osascript).run(FileAction(operation: operation))
            }
            #expect(osascript.calls.map(\.language) == ["js"], Comment(rawValue: "\(operation) \(path)"))
        }
    }

    @Test("標準のフォルダの中のファイルや、ほかのディスクの中のフォルダは動かせる")
    func protectedPlacesAreOnlyTheFoldersThemselves() {
        for path in ["/Users/tester/Desktop/a.txt", "/Users/tester/Documents/案件/資料", "/Volumes/Backup/photos", "/Users/tester/Library/CloudStorage/Dropbox/a.txt", "/Users/other/a.txt"] {
            #expect(!FilePlan.isProtected(path, home: Self.home), Comment(rawValue: path))
        }
    }

    // MARK: 各操作

    @Test("ゴミ箱に入れる: 選んだファイルのパスを、そのまま引数で渡す")
    func trashesTheSelection() async throws {
        let paths = ["/Users/tester/a \"1\".txt", "/Users/tester/-b.txt", "/Users/tester/書類/資料"]
        let osascript = FakeOsascript(selection: urls(paths))
        try await runner(osascript).run(FileAction(operation: .trash))
        let call = try #require(osascript.calls.last)
        #expect(osascript.calls.map(\.language) == ["js", "as"])
        #expect(call.source == FileScripts.trash)
        #expect(call.arguments == paths)
        #expect(call.timeout == FileActionRunner.actionTimeout)
    }

    @Test("複製: 選んだファイルに依頼を出し、長く待つ")
    func duplicates() async throws {
        let osascript = FakeOsascript(selection: urls(["/Users/tester/a.txt"]))
        try await runner(osascript).run(FileAction(operation: .duplicate))
        let call = try #require(osascript.calls.last)
        #expect(call.source == FileScripts.duplicate)
        #expect(call.arguments == ["/Users/tester/a.txt"])
        #expect(call.timeout == FileActionRunner.copyTimeout)
    }

    @Test("名前を変える: 選んだものが1つだけのとき、Finder の名前の変更（Return）を始める。osascript では何も頼まない")
    func renameStartsFindersOwnRename() async throws {
        let osascript = FakeOsascript(selection: urls(["/Users/tester/a.txt"]))
        let keys = FakeKeys()
        try await runner(osascript, keys: keys).run(FileAction(operation: .rename))
        #expect(keys.sent == [[KeyChord(.special(.returnKey))]])
        #expect(osascript.calls.map(\.language) == ["js"])
    }

    @Test("名前を変える: 複数選んでいる・何も選んでいない・Finder が前面でないときは、Return を送らない")
    func renameDoesNotSendReturnUnlessOneFileIsSelected() async {
        for selection in [urls(["/Users/tester/a.txt", "/Users/tester/b.txt"]), "[]"] {
            let keys = FakeKeys()
            await #expect(throws: NonetError.self) {
                try await runner(FakeOsascript(selection: selection), keys: keys).run(FileAction(operation: .rename))
            }
            #expect(keys.sent.isEmpty)
        }
        let keys = FakeKeys()
        await #expect(throws: NonetError.self) {
            try await runner(FakeOsascript(selection: urls(["/Users/tester/a.txt"])), keys: keys, frontmost: Frontmost(["com.apple.Safari"])).run(FileAction(operation: .rename))
        }
        #expect(keys.sent.isEmpty)
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
            try await runner(osascript).run(FileAction(operation: .trash))
        }
    }

    @Test("失敗の番号ごとに、決まった言葉にする")
    func mapsErrorNumbers() {
        func message(_ stderr: String) -> String? { FinderScriptFailure.error(for: failed(stderr))?.errorDescription }
        func text(_ key: String.LocalizationValue) -> String { String(localized: key, bundle: .nonetActions) }
        #expect(FinderScriptFailure.error(for: failed("12:20: execution error: エラー (-1743)")) == .permissionDenied(ActionText.finderAutomation))
        #expect(message("execution error: Finder は起動していません。 (-600)") == text("Finder が起動していません"))
        #expect(message("execution error: x (-609)") == text("Finder が起動していません"))
        for number in [-48, -15267] {
            #expect(message("129:134: execution error: 失敗 (\(number))") == text("同じ名前のファイルがあります"), Comment(rawValue: "\(number)"))
        }
        for number in [-1728, -1700, -43] {
            #expect(message("execution error: 失敗 (\(number))") == text("ファイルが見つかりません。選び直してください"), Comment(rawValue: "\(number)"))
        }
        #expect(message("execution error: link (\(FileScripts.ErrorNumber.link))") == text("シンボリックリンクは、ここでは動かせません（リンク先を動かしてしまうため）"))
        #expect(message("execution error: no trash (\(FileScripts.ErrorNumber.noTrash))") == text("ゴミ箱の無い場所（ネットワーク上のファイルなど）は、ここでは削除しません"))
        // 知らない番号でも、標準エラーの末尾を添えて知らせる
        #expect(message("execution error: こわれた (-99999)")?.contains("こわれた") == true)
        #expect(message("") == text("ファイルの操作に失敗しました"))
        #expect(FinderScriptFailure.error(for: ProcessOutput(status: 0, wasSignaled: false, timedOut: false, stdout: "", stderr: "")) == nil)
    }

    @Test("時間切れのときは、Finder の作業が続いていることがあると伝える")
    func timeoutMessageSaysFinderMayStillBeWorking() {
        let message = FinderScriptFailure.error(for: failed("", status: 0, timedOut: true))?.errorDescription
        #expect(message == String(localized: "Finder が時間内に終わりませんでした。Finder の作業は続いていることがあるので、確かめてください", bundle: .nonetActions))
    }

    @Test("エラーの番号は、最後の行の終わりの括弧から読む")
    func readsTheErrorNumber() {
        #expect(FinderScriptFailure.errorNumber(in: "a (1)\nexecution error: x (-1743)\n\n") == -1743)
        #expect(FinderScriptFailure.errorNumber(in: "execution error: x") == nil)
        #expect(FinderScriptFailure.errorNumber(in: "") == nil)
        #expect(FinderScriptFailure.errorNumber(in: "x (abc)") == nil)
    }

    // MARK: 依頼の書き方

    @Test("依頼の文には、ファイルのパスを埋め込まない（引数で渡す）。完全な削除や上書きの語は使わず、シンボリックリンクは動かさない")
    func scriptsTakeEverythingFromArgumentsAndRefuseLinks() {
        for script in [FileScripts.trash, FileScripts.duplicate] {
            #expect(script.contains("on run argv"))
            #expect(script.contains("aliasList(argv)"))
            #expect(!script.contains("/Users"))
            #expect(!script.contains("empty"))
            #expect(!script.contains("rm "))
            #expect(!script.contains("replacing"))
        }
        #expect(FileScripts.trash.contains("delete targets"))
        #expect(FileScripts.trash.contains("local volume"))
    }

    @Test("どの依頼の文も、AppleScript として組み立てられる（osacompile）")
    func scriptsCompile() async throws {
        let directory = try ActionTemporaryDirectory()
        for (name, script) in [("trash", FileScripts.trash), ("duplicate", FileScripts.duplicate)] {
            let output = try await ProcessRunner.run(ProcessRequest(
                executable: URL(fileURLWithPath: "/usr/bin/osacompile"),
                arguments: ["-e", script, "-o", directory.url.appendingPathComponent("\(name).scpt").path],
                environment: nil,
                currentDirectory: nil,
                timeout: 30
            ))
            #expect(output.succeeded, Comment(rawValue: "\(name): \(output.stderr)"))
        }
    }

    @Test("本物の osascript に、\"-\" で始まる引数や引用符・日本語を、そのまま引数として渡せる（Finder は使わない）")
    func realOsascriptPassesArgumentsUntouched() async throws {
        let source = """
        on run argv
            set out to ""
            repeat with a in argv
                set out to out & (contents of a) & "|"
            end repeat
            return out
        end run
        """
        let output = try await Osascript().run(.appleScript, source: source, arguments: ["-b.txt", "a \"1\".txt", "書類", "--"], timeout: 20)
        #expect(output.succeeded, Comment(rawValue: output.stderr))
        #expect(output.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "-b.txt|a \"1\".txt|書類|--|")
        let js = try await Osascript().run(.javaScript, source: "JSON.stringify([1, 'あ'])", arguments: [], timeout: 20)
        #expect(js.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == #"[1,"あ"]"#)
    }
}
