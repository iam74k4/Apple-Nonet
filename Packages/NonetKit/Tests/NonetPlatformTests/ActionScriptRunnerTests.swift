import Foundation
import NonetCore
@testable import NonetPlatform
import Testing

/// 本物の /bin/zsh で動かす。利用者の設定ファイルは読まない（HOME と ZDOTDIR を一時フォルダにする）
@Suite("スクリプトの実行")
struct ActionScriptRunnerTests {
    private func runScript(
        _ source: String,
        in directory: ActionTemporaryDirectory,
        extra: [String: String] = [:],
        workingDirectory: URL? = nil,
        timeout: TimeInterval = 20,
        outputLimit: Int = ScriptRunner.outputLimit,
        killGracePeriod: TimeInterval = 2
    ) async throws -> ProcessOutput {
        try await ProcessRunner.run(ProcessRequest(
            executable: ScriptRunner.shell,
            arguments: ScriptRunner.arguments(source: source),
            environment: directory.isolatedEnvironment.merging(extra) { _, new in new },
            currentDirectory: workingDirectory ?? directory.url,
            timeout: timeout,
            outputLimit: outputLimit,
            killGracePeriod: killGracePeriod
        ))
    }

    @Test("環境変数を受け取り、日本語・改行・引用符もそのまま届く")
    func passesEnvironment() async throws {
        let directory = try ActionTemporaryDirectory()
        let value = "選択\n\"テキスト\" $(echo injected) `id` 'quote'"
        let output = try await runScript(
            #"printf '%s|%s' "$NONET_APP_NAME" "$NONET_SELECTED_TEXT""#,
            in: directory,
            extra: ["NONET_APP_NAME": "Xcode", "NONET_SELECTED_TEXT": value]
        )
        #expect(output.succeeded)
        #expect(output.stdout == "Xcode|\(value)")
    }

    @Test("作業フォルダで動く")
    func workingDirectory() async throws {
        let directory = try ActionTemporaryDirectory()
        let project = try directory.subdirectory("my project's dir")
        let output = try await runScript("pwd -P", in: directory, workingDirectory: project)
        #expect(output.stdout.trimmingCharacters(in: .newlines) == actionRealPath(project))
    }

    @Test("ログインシェルとして動く")
    func loginShell() async throws {
        let directory = try ActionTemporaryDirectory()
        let output = try await runScript("[[ -o login ]] && echo login", in: directory)
        #expect(output.stdout == "login\n")
    }

    @Test("- で始まるソースもオプションにならない")
    func sourceStartingWithDash() async throws {
        let directory = try ActionTemporaryDirectory()
        let output = try await runScript("--nonet-not-an-option 2>/dev/null; echo ran", in: directory)
        #expect(output.stdout == "ran\n")
        #expect(output.status == 0)
    }

    @Test("終了コードと標準エラーの末尾が失敗の説明になる")
    func exitCodeAndStderr() async throws {
        let directory = try ActionTemporaryDirectory()
        let output = try await runScript("echo out; echo one >&2; echo two >&2; echo three >&2; echo four >&2; exit 3", in: directory)
        #expect(output.status == 3)
        #expect(!output.succeeded)
        #expect(output.stdout == "out\n")
        #expect(output.stderr == "one\ntwo\nthree\nfour\n")
        let failure = try #require(ScriptRunner.failure(for: output))
        guard case .actionFailed(let message) = failure else {
            Issue.record("actionFailed になるはず: \(failure)")
            return
        }
        #expect(message.contains("3"))
        #expect(message.hasSuffix("two\nthree\nfour"))
        #expect(!message.contains("one"))
    }

    @Test("成功なら失敗は無い")
    func successHasNoFailure() async throws {
        let directory = try ActionTemporaryDirectory()
        let output = try await runScript("true", in: directory)
        #expect(ScriptRunner.failure(for: output) == nil)
    }

    @Test("runInBackground は失敗で NonetError.actionFailed、成功なら何も投げない")
    func runInBackground() async throws {
        let directory = try ActionTemporaryDirectory()
        try await ScriptRunner.runInBackground(
            source: "test \"$NONET_APP_NAME\" = Finder",
            environment: directory.isolatedEnvironment.merging(["NONET_APP_NAME": "Finder"]) { _, new in new },
            workingDirectory: directory.url,
            timeout: 20
        )
        await #expect(throws: NonetError.self) {
            try await ScriptRunner.runInBackground(
                source: "echo broken >&2; exit 1",
                environment: directory.isolatedEnvironment,
                workingDirectory: directory.url,
                timeout: 20
            )
        }
        let empty = await #expect(throws: NonetError.self) {
            try await ScriptRunner.runInBackground(source: " \n ", environment: [:], workingDirectory: directory.url, timeout: 1)
        }
        if case .actionFailed = empty {} else { Issue.record("空のスクリプトは actionFailed になるはず: \(String(describing: empty))") }
    }

    @Test("制限時間を過ぎたら止め、子プロセスも止める")
    func timeoutKillsProcessGroup() async throws {
        let directory = try ActionTemporaryDirectory()
        let pidFile = directory.url.appendingPathComponent("child.pid")
        var output: ProcessOutput?
        let elapsed = try await actionElapsedSeconds {
            output = try await runScript("sleep 30 & echo $! > child.pid; wait", in: directory, timeout: 0.5)
        }
        #expect(output?.timedOut == true)
        #expect(output.flatMap(ScriptRunner.failure(for:)) == .timedOut)
        #expect(elapsed < 5)
        let childPID = try #require(Int32(String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        try await Task.sleep(for: .milliseconds(300))
        #expect(kill(childPID, 0) != 0, "孫プロセスが残っている")
    }

    @Test("SIGTERM を無視するスクリプトは SIGKILL で止める")
    func killsAfterGracePeriod() async throws {
        let directory = try ActionTemporaryDirectory()
        var output: ProcessOutput?
        let elapsed = try await actionElapsedSeconds {
            output = try await runScript("trap '' TERM; sleep 30", in: directory, timeout: 0.3, killGracePeriod: 0.5)
        }
        #expect(output?.timedOut == true)
        #expect(output?.wasSignaled == true)
        #expect(elapsed < 5)
    }

    @Test("シェルが SIGTERM で終わっても、SIGTERM を無視する子孫は猶予の後にグループごと止める")
    func killsDescendantsIgnoringSIGTERM() async throws {
        let directory = try ActionTemporaryDirectory()
        let pidFile = directory.url.appendingPathComponent("child.pid")
        let output = try await runScript(
            "(trap '' TERM; exec sleep 30) & echo $! > child.pid; wait",
            in: directory,
            timeout: 0.5,
            killGracePeriod: 0.5
        )
        #expect(output.timedOut)
        let childPID = try #require(Int32(String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        var stopped = false
        for _ in 0 ..< 150 where !stopped {
            try await Task.sleep(for: .milliseconds(20))
            stopped = kill(childPID, 0) != 0
        }
        if !stopped { kill(childPID, SIGKILL) }
        #expect(stopped, "SIGTERM を無視した孫プロセスが残っている")
    }

    @Test("裏に残ったプロセスが出力を握っていても、本体が終われば戻る")
    func doesNotWaitForBackgroundChildren() async throws {
        let directory = try ActionTemporaryDirectory()
        var output: ProcessOutput?
        let elapsed = try await actionElapsedSeconds {
            output = try await runScript("sleep 3 & echo done", in: directory)
        }
        #expect(output?.succeeded == true)
        #expect(output?.stdout == "done\n")
        #expect(elapsed < 2.5)
    }

    @Test("出力は上限まで、末尾を残す")
    func boundedOutput() async throws {
        let directory = try ActionTemporaryDirectory()
        let output = try await runScript("seq 1 200000; seq 1 50000 >&2", in: directory, outputLimit: 1024)
        #expect(output.succeeded)
        #expect(output.stdout.utf8.count <= 1024)
        #expect(output.stdout.hasSuffix("199999\n200000\n"))
        #expect(output.stderr.utf8.count <= 1024)
        #expect(output.stderr.hasSuffix("50000\n"))
    }

    @Test("取り消すとすぐに止まる")
    func cancellation() async throws {
        let directory = try ActionTemporaryDirectory()
        let task = Task {
            try await runScript("sleep 30", in: directory, timeout: 60)
        }
        try await Task.sleep(for: .milliseconds(300))
        let elapsed = await actionElapsedSeconds {
            task.cancel()
            let result = await task.result
            #expect(throws: CancellationError.self) { try result.get() }
        }
        #expect(elapsed < 5)
    }

    @Test("起動できない実行ファイルは投げる")
    func launchFailure() async {
        await #expect(throws: (any Error).self) {
            try await ProcessRunner.run(ProcessRequest(
                executable: URL(fileURLWithPath: "/nonexistent/nonet-test"),
                arguments: [],
                environment: [:],
                currentDirectory: nil,
                timeout: 5
            ))
        }
    }

    @Test("標準入力は空（読もうとしても待たない）")
    func stdinIsEmpty() async throws {
        let directory = try ActionTemporaryDirectory()
        let output = try await runScript("cat; echo end", in: directory, timeout: 10)
        #expect(output.stdout == "end\n")
        #expect(!output.timedOut)
    }
}

@Suite("スクリプトの準備")
struct ActionScriptSetupTests {
    @Test("引数は -l -c -- ソース")
    func arguments() {
        #expect(ScriptRunner.arguments(source: "echo hi") == ["-l", "-c", "--", "echo hi"])
    }

    @Test("環境変数: 文脈を重ね、古い NONET_* を消し、LC_CTYPE を補う")
    func environment() {
        let base = ["PATH": "/usr/bin", "NONET_SELECTED_TEXT": "stale", "PROJECT_DIR": "/old", "HOME": "/Users/me"]
        let merged = ScriptRunner.environment(base: base, context: ["NONET_APP_NAME": "Xcode", "PROJECT_DIR": "/new"])
        #expect(merged["PATH"] == "/usr/bin")
        #expect(merged["HOME"] == "/Users/me")
        #expect(merged["NONET_SELECTED_TEXT"] == nil)
        #expect(merged["NONET_APP_NAME"] == "Xcode")
        #expect(merged["PROJECT_DIR"] == "/new")
        #expect(merged["LC_CTYPE"] == "UTF-8")

        let withLang = ScriptRunner.environment(base: ["LANG": "ja_JP.UTF-8"], context: [:])
        #expect(withLang["LC_CTYPE"] == nil)
        #expect(ScriptRunner.environment(base: ["PROJECT_DIR": "/old"], context: [:])["PROJECT_DIR"] == nil)
    }

    @Test("作業フォルダ: プロジェクトのフォルダがあればそこ、無ければホーム")
    func workingDirectory() {
        let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)
        #expect(ScriptRunner.workingDirectory(projectDirectory: nil, home: home) { _ in true } == home)
        #expect(ScriptRunner.workingDirectory(projectDirectory: "", home: home) { _ in true } == home)
        #expect(ScriptRunner.workingDirectory(projectDirectory: "/missing", home: home) { _ in false } == home)
        #expect(ScriptRunner.workingDirectory(projectDirectory: "/Users/me/app", home: home) { _ in true }.path == "/Users/me/app")
    }

    /// 調べたパスを記録する偽のファイルシステム
    private final class StatLog {
        var paths: [String] = []
        let existing: Set<String>

        init(existing: Set<String> = []) {
            self.existing = existing
        }

        func fileExists(_ path: String) -> Bool {
            paths.append(path)
            return existing.contains(path)
        }
    }

    @Test("ネットワークの場所の書類では .git などを探さず、書類のフォルダをプロジェクトにする")
    func networkVolumeSkipsSearch() {
        let log = StatLog()
        let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)
        let location = ScriptLocation.resolve(
            documentPath: "/Volumes/NAS/share/docs/report.docx",
            home: home,
            fileExists: log.fileExists,
            isLocalVolume: { _ in false },
            isDirectory: { _ in true }
        )
        #expect(log.paths.isEmpty, "\(log.paths)")
        #expect(location.projectDirectory == "/Volumes/NAS/share/docs")
        #expect(location.workingDirectory.path == "/Volumes/NAS/share/docs")
    }

    @Test("ホームの外では、書類から上へ決まった数のフォルダまでしか調べず、/ や /Volumes は調べない")
    func boundedSearchOutsideHome() {
        let log = StatLog()
        let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)
        let deep = "/Volumes/Dev/" + (1 ... 12).map { "d\($0)" }.joined(separator: "/") + "/file.txt"
        let location = ScriptLocation.resolve(
            documentPath: deep,
            home: home,
            maxLevels: 4,
            fileExists: log.fileExists,
            isLocalVolume: { _ in true },
            isDirectory: { _ in true }
        )
        let directories = Set(log.paths.map { ($0 as NSString).deletingLastPathComponent })
        #expect(directories.count == 4, "\(directories.sorted())")
        #expect(!log.paths.contains { $0.hasPrefix("/Volumes/.") || $0.hasPrefix("//") || $0 == "/.git" })
        #expect(location.projectDirectory == "/Volumes/Dev/" + (1 ... 12).map { "d\($0)" }.joined(separator: "/"))

        let shallow = StatLog()
        _ = ScriptLocation.resolve(
            documentPath: "/Volumes/Dev/file.txt",
            home: home,
            fileExists: shallow.fileExists,
            isLocalVolume: { _ in true },
            isDirectory: { _ in true }
        )
        // /Volumes/Dev（外付けのディスクの一番上）までは調べ、/Volumes と / は調べない
        #expect(Set(shallow.paths) == ["/Volumes/Dev/file.txt/.git", "/Volumes/Dev/file.txt/Package.swift", "/Volumes/Dev/.git", "/Volumes/Dev/Package.swift"])
    }

    @Test("範囲の中で .git が見つかればそこがプロジェクト。ホームより上は調べない")
    func findsMarkerWithinRange() {
        let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)
        let found = ScriptLocation.resolve(
            documentPath: "/Users/me/src/app/Sources/main.swift",
            home: home,
            fileExists: StatLog(existing: ["/Users/me/src/app/.git"]).fileExists,
            isLocalVolume: { _ in true },
            isDirectory: { _ in true }
        )
        #expect(found.projectDirectory == "/Users/me/src/app")
        #expect(found.workingDirectory.path == "/Users/me/src/app")

        let log = StatLog()
        _ = ScriptLocation.resolve(
            documentPath: "/Users/me/notes.txt",
            home: home,
            fileExists: log.fileExists,
            isLocalVolume: { _ in true },
            isDirectory: { _ in true }
        )
        #expect(!log.paths.contains("/Users/me/.git"))
        #expect(!log.paths.contains("/Users/.git"))
    }

    @Test("ホームの中では深さの上限なしに上へたどる（Maven・Gradle・Android のソースや深いモノレポでもルートを見つける）", arguments: [
        "/Users/me/dev/proj/src/main/java/com/acme/app/web/Controller.java",
        "/Users/me/dev/proj/apps/web/src/app/settings/profile/a/b/c/d/e/page.tsx",
    ])
    func deepProjectInsideHome(path: String) {
        let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)
        let log = StatLog(existing: ["/Users/me/dev/proj/.git"])
        let location = ScriptLocation.resolve(
            documentPath: path,
            home: home,
            maxLevels: 4,
            fileExists: log.fileExists,
            isLocalVolume: { _ in true },
            isDirectory: { _ in true }
        )
        #expect(location.projectDirectory == "/Users/me/dev/proj")
        #expect(!log.paths.contains("/Users/me/.git"))
    }

    @Test("ホームの外でも、標準の上限なら外付けのディスクの深いソースからルートを見つける")
    func deepProjectOnExternalDisk() {
        let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)
        let location = ScriptLocation.resolve(
            documentPath: "/Volumes/SSD/dev/proj/src/main/java/com/acme/app/web/Controller.java",
            home: home,
            fileExists: StatLog(existing: ["/Volumes/SSD/dev/proj/.git"]).fileExists,
            isLocalVolume: { _ in true },
            isDirectory: { _ in true }
        )
        #expect(location.projectDirectory == "/Volumes/SSD/dev/proj")
    }

    @Test("ホームの中かどうか（ディスクは見ない）")
    func insideHome() {
        let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)
        #expect(ScriptLocation.isInside("/Users/me/a/b.txt", home: home))
        #expect(ScriptLocation.isInside("/Users/me", home: home))
        #expect(ScriptLocation.isInside("/Users/me/./x/../y.txt", home: home))
        #expect(!ScriptLocation.isInside("/Users/meow/a.txt", home: home))
        #expect(!ScriptLocation.isInside("/Users/me/../other/a.txt", home: home))
        #expect(!ScriptLocation.isInside("/Volumes/Dev/a.txt", home: home))
    }

    @Test("書類が無ければプロジェクトは無く、作業フォルダはホーム")
    func noDocument() async {
        let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)
        #expect(await ScriptLocation.find(documentPath: nil, home: home) == ScriptLocation(projectDirectory: nil, workingDirectory: home))
        #expect(await ScriptLocation.find(documentPath: "", home: home) == ScriptLocation(projectDirectory: nil, workingDirectory: home))
    }

    @Test("本物のフォルダで: .git のあるフォルダがプロジェクトで作業フォルダ")
    func findsRealProject() async throws {
        let directory = try ActionTemporaryDirectory()
        let project = try directory.subdirectory("app")
        try FileManager.default.createDirectory(at: project.appendingPathComponent(".git"), withIntermediateDirectories: true)
        let sources = try directory.subdirectory("app/Sources")
        let file = sources.appendingPathComponent("main.swift")
        try Data("x".utf8).write(to: file)
        #expect(ScriptLocation.isLocalVolume(file.path))
        let home = URL(fileURLWithPath: "/nonexistent-home", isDirectory: true)
        let location = await ScriptLocation.find(documentPath: file.path, home: home, timeout: 5)
        #expect(location.projectDirectory == project.path)
        #expect(location.workingDirectory.path == project.path)
    }

    @Test("フォルダかどうか")
    func isDirectory() throws {
        let directory = try ActionTemporaryDirectory()
        let file = directory.url.appendingPathComponent("file.txt")
        try Data("x".utf8).write(to: file)
        #expect(ScriptRunner.isDirectory(directory.url.path))
        #expect(!ScriptRunner.isDirectory(file.path))
        #expect(!ScriptRunner.isDirectory(directory.url.appendingPathComponent("missing").path))
    }

    @Test("制限時間: おかしな値は既定の 60 秒、長すぎる値は 1 日まで")
    func timeouts() {
        #expect(ScriptRunner.effectiveTimeout(5) == 5)
        #expect(ScriptRunner.effectiveTimeout(0) == 60)
        #expect(ScriptRunner.effectiveTimeout(-1) == 60)
        #expect(ScriptRunner.effectiveTimeout(.nan) == 60)
        #expect(ScriptRunner.effectiveTimeout(.infinity) == 60)
        #expect(ScriptRunner.effectiveTimeout(1e9) == 86400)
    }

    @Test("標準エラーの末尾の行")
    func lastLines() {
        #expect(ActionText.lastLines(of: "a\n\nb\n  c  \nd\n") == ["b", "c", "d"])
        #expect(ActionText.lastLines(of: "") == [])
        #expect(ActionText.lastLines(of: "x\r\ny", count: 5) == ["x", "y"])
        let long = String(repeating: "あ", count: 300)
        #expect(ActionText.lastLines(of: long, maxLineLength: 10) == [String(repeating: "あ", count: 10) + "…"])
        #expect(ActionText.message("見出し", detail: "") == "見出し")
        #expect(ActionText.message("見出し", detail: "e1\ne2") == "見出し\ne1\ne2")
    }
}

@Suite("末尾を残すバッファ")
struct ActionTailBufferTests {
    @Test("上限以内ならそのまま")
    func underLimit() {
        var buffer = TailBuffer(limit: 10)
        buffer.append(Data("abc".utf8))
        buffer.append(Data())
        buffer.append(Data("def".utf8))
        #expect(buffer.text == "abcdef")
        #expect(!buffer.isTruncated)
    }

    @Test("上限を超えたら末尾を残す")
    func keepsTail() {
        var buffer = TailBuffer(limit: 4)
        for chunk in ["12345", "678", "9"] { buffer.append(Data(chunk.utf8)) }
        #expect(buffer.text == "6789")
        #expect(buffer.isTruncated)
        #expect(buffer.data.count == 4)
    }

    @Test("切った場所が文字の途中なら、そのかけらを捨てる")
    func dropsPartialCharacter() {
        var buffer = TailBuffer(limit: 7)
        buffer.append(Data("あいう".utf8)) // 9 バイト
        #expect(buffer.text == "いう")
    }

    @Test("上限 0 は何も残さない")
    func zeroLimit() {
        var buffer = TailBuffer(limit: 0)
        buffer.append(Data("abc".utf8))
        #expect(buffer.text.isEmpty)
        #expect(buffer.isTruncated)
    }
}
