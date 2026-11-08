import Foundation
import NonetCore
@testable import NonetPlatform
import Testing

/// 裏のスクリプトの PATH・コマンドが見つからないときの説明・スクリプトとショートカットの出力
@Suite("スクリプトの PATH と出力")
struct ActionCommandOutputTests {
    private func run(_ source: String, in directory: ActionTemporaryDirectory, shellPath: String?, outputLimit: Int = ScriptRunner.outputLimit) async throws -> ProcessOutput {
        ScriptRunner.strippingStartupOutput(try await ProcessRunner.run(ProcessRequest(
            executable: ScriptRunner.shell,
            arguments: ScriptRunner.arguments(source: source, shellPath: shellPath),
            environment: ScriptRunner.environment(base: directory.isolatedEnvironment, context: [:], shellPath: shellPath),
            currentDirectory: directory.url,
            timeout: 20,
            outputLimit: outputLimit
        )))
    }

    // MARK: - PATH

    @Test("シェルの PATH があれば、ログインシェルの設定ファイルの後でもそのままの順で使う")
    func shellPathWinsOverPathHelper() async throws {
        let directory = try ActionTemporaryDirectory()
        // /etc/zprofile の path_helper は /usr/bin などを前に並べ替える。ターミナルと同じ順にしたい
        let shellPath = "/nonet/first/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        let output = try await run(#"print -rn -- "$PATH""#, in: directory, shellPath: shellPath)
        #expect(output.succeeded, "\(output.stderr)")
        #expect(output.stdout == shellPath)
    }

    @Test("シェルの PATH が無ければ今までどおり（ログインシェルの PATH）")
    func withoutShellPath() async throws {
        let directory = try ActionTemporaryDirectory()
        let output = try await run(#"print -rn -- "$PATH""#, in: directory, shellPath: nil)
        #expect(output.succeeded)
        #expect(output.stdout.contains("/usr/bin"))
        #expect(!output.stdout.hasPrefix("/nonet/"))
    }

    @Test("出力の始まりの印と PATH を前に置いても、行番号と引数の形は変わらない")
    func argumentsWithShellPath() async throws {
        let start = "print -rn -- '\(ScriptRunner.outputMarker)'; "
        #expect(ScriptRunner.arguments(source: "echo hi", shellPath: nil) == ["-l", "-c", "--", start + "echo hi"])
        #expect(ScriptRunner.arguments(source: "echo hi", shellPath: "") == ["-l", "-c", "--", start + "echo hi"])
        let arguments = ScriptRunner.arguments(source: "echo hi", shellPath: "/a b/it's:/usr/bin")
        #expect(arguments.prefix(3) == ["-l", "-c", "--"])
        #expect(arguments.last == start + #"export PATH='/a b/it'\''s:/usr/bin'; echo hi"#)

        let directory = try ActionTemporaryDirectory()
        let output = try await run("true\nnonet-no-such-command-xyz", in: directory, shellPath: "/usr/bin:/bin")
        #expect(output.status == ScriptRunner.commandNotFoundStatus)
        #expect(output.stderr.contains("zsh:2:"), "\(output.stderr)")
    }

    @Test("環境変数の PATH もシェルの PATH にする")
    func environmentPath() {
        let merged = ScriptRunner.environment(base: ["PATH": "/usr/bin"], context: [:], shellPath: "/opt/x/bin:/usr/bin")
        #expect(merged["PATH"] == "/opt/x/bin:/usr/bin")
        #expect(ScriptRunner.environment(base: ["PATH": "/usr/bin"], context: [:], shellPath: nil)["PATH"] == "/usr/bin")
    }

    // MARK: - 終了コード 127

    @Test("コマンドが見つからなければ、名前を添えて確かめ方を出す（標準エラーより前）")
    func commandNotFoundHint() async throws {
        let directory = try ActionTemporaryDirectory()
        let output = try await run("echo before >&2; nonet-no-such-command-xyz --flag", in: directory, shellPath: nil)
        #expect(output.status == 127)
        let failure = try #require(ScriptRunner.failure(for: output))
        guard case .actionFailed(let message) = failure else {
            Issue.record("actionFailed になるはず: \(failure)")
            return
        }
        let lines = message.split(separator: "\n").map(String.init)
        let hint = String(
            localized: "コマンドが見つかりません。インストールされているか、ターミナルで command -v \("nonet-no-such-command-xyz") を確かめてください。",
            bundle: .nonetActions
        )
        #expect(lines.first == String(localized: "スクリプトが失敗しました（終了コード \(Int32(127))）", bundle: .nonetActions))
        #expect(lines.dropFirst().first == hint)
        #expect(lines.last?.contains("nonet-no-such-command-xyz") == true)
        // 知らせは4行まで
        #expect(lines.count <= 4)
    }

    @Test("名前が分からなければ、名前なしの確かめ方")
    func commandNotFoundWithoutName() throws {
        let output = ProcessOutput(status: 127, wasSignaled: false, timedOut: false, stdout: "", stderr: "")
        guard case .actionFailed(let message)? = ScriptRunner.failure(for: output) else {
            Issue.record("actionFailed になるはず")
            return
        }
        #expect(message.hasSuffix(String(localized: "コマンドが見つかりません。インストールされているか、ターミナルで確かめてください。", bundle: .nonetActions)))
    }

    @Test("ほかの終了コードには確かめ方を付けない")
    func otherFailuresHaveNoHint() throws {
        let output = ProcessOutput(status: 1, wasSignaled: false, timedOut: false, stdout: "", stderr: "zsh:1: command not found: x\n")
        guard case .actionFailed(let message)? = ScriptRunner.failure(for: output) else {
            Issue.record("actionFailed になるはず")
            return
        }
        #expect(!message.contains(ScriptRunner.commandNotFoundHint(command: "x")))
    }

    @Test("標準エラーからコマンドの名前を読む", arguments: [
        ("zsh:1: command not found: claude\n", "claude"),
        ("zsh: command not found: npx", "npx"),
        ("bash: line 1: pnpm: command not found", "pnpm"),
        ("sh: bun: command not found\n", "bun"),
        ("env: node: No such file or directory\n", "node"),
        ("first\nzsh:3: command not found: older\nzsh:5: command not found: newer\n", "newer"),
        ("permission denied: ./run.sh", nil),
        ("", nil),
    ] as [(String, String?)])
    func missingCommandName(stderr: String, expected: String?) {
        #expect(ScriptRunner.missingCommand(in: stderr) == expected)
    }

    // MARK: - 出力

    static func output(_ stdout: String, truncated: Bool = false) -> ProcessOutput {
        ProcessOutput(status: 0, wasSignaled: false, timedOut: false, stdout: stdout, stderr: "", stdoutTruncated: truncated)
    }

    @Test("最後の改行を1つだけ除く。空なら使わない", arguments: [
        ("value\n", "value"),
        ("value", "value"),
        ("two\n\n", "two\n"),
        ("crlf\r\n", "crlf"),
        ("line1\nline2\n", "line1\nline2"),
        ("  spaced  \n", "  spaced  "),
        ("\n", nil),
        ("", nil),
        // 空白と改行だけなら、空のパネルを出さない
        ("  \n\n", nil),
        // 画像などのバイト列は出さない
        ("PNG\u{0}\u{1}", nil),
        ("bad\u{FFFD}bytes", nil),
    ] as [(String, String?)])
    func trimsOneTrailingNewline(stdout: String, expected: String?) {
        #expect(CommandOutput.text(from: Self.output(stdout)) == expected)
    }

    @Test("リッチテキスト（ショートカットのテキスト）は文字だけにする")
    func richTextBecomesPlainText() {
        let rtf = #"{\rtf1\ansi\deff0 {\fonttbl {\f0 Helvetica;}}\f0 Hello \b world\b0}"#
        #expect(CommandOutput.text(from: Self.output(rtf)) == "Hello world")
    }

    @Test("上限を超えて先頭が切れた出力は、終わりの部分をそうと分かるように出す（成功のまま）")
    func truncatedOutputShowsTheEnd() {
        let note = String(localized: "（出力が長いため、終わりの \(ScriptRunner.outputLimit / 1024) KB だけを表示しています）", bundle: .nonetActions)
        #expect(CommandOutput.text(from: Self.output("tail\n", truncated: true)) == note + "\ntail")
    }

    @Test("ログインシェルの設定ファイル（~/.zprofile・~/.zlogin）が出す文字は、出力に混ぜない")
    func loginShellOutputIsDropped() async throws {
        let directory = try ActionTemporaryDirectory()
        try "print -r -- 'Agent pid 4242'\n".write(to: directory.url.appendingPathComponent(".zprofile"), atomically: true, encoding: .utf8)
        try "print -r -- 'from-zlogin'\n".write(to: directory.url.appendingPathComponent(".zlogin"), atomically: true, encoding: .utf8)
        let output = try await ScriptRunner.runInBackground(
            source: "print -r -- result",
            environment: directory.isolatedEnvironment,
            workingDirectory: directory.url,
            timeout: 20,
            shellPath: "/usr/bin:/bin"
        )
        #expect(CommandOutput.text(from: output) == "result")
        // 何も出さないスクリプトなら、パネルは出ない
        let silent = try await ScriptRunner.runInBackground(source: "true", environment: directory.isolatedEnvironment, workingDirectory: directory.url, timeout: 20)
        #expect(CommandOutput.text(from: silent) == nil)
    }

    @Test("失敗したスクリプトの知らせには、標準エラーが空なら標準出力を添える")
    func failureFallsBackToStandardOutput() async throws {
        let directory = try ActionTemporaryDirectory()
        let error = await #expect(throws: NonetError.self) {
            try await ScriptRunner.runInBackground(source: "print -r -- 'disk is full'; exit 3", environment: directory.isolatedEnvironment, workingDirectory: directory.url, timeout: 20)
        }
        guard case .actionFailed(let message)? = error else { Issue.record("\(String(describing: error))"); return }
        #expect(message.contains("disk is full"))
        #expect(!message.contains(ScriptRunner.outputMarker))
    }

    @Test("NUL の入ったスクリプトは、始める前に断った理由をそのまま知らせる（「実行できませんでした」にまとめない）")
    func nulInScriptKeepsTheReason() async throws {
        let directory = try ActionTemporaryDirectory()
        let error = await #expect(throws: NonetError.self) {
            try await ScriptRunner.runInBackground(source: "echo a\u{0}b", environment: directory.isolatedEnvironment, workingDirectory: directory.url, timeout: 20)
        }
        guard case .actionFailed(let message)? = error else { Issue.record("\(String(describing: error))"); return }
        #expect(message.contains("NUL"))
    }

    @Test("標準出力が上限を超えたかを返す")
    func reportsTruncation() async throws {
        let directory = try ActionTemporaryDirectory()
        // 上限には、先頭の印（ScriptRunner.outputMarker）も数える
        let small = try await run("printf 'abc'", in: directory, shellPath: nil, outputLimit: 32)
        #expect(!small.stdoutTruncated)
        #expect(small.stdout == "abc")
        let large = try await run("printf '%.0s0123456789' {1..10}", in: directory, shellPath: nil, outputLimit: 32)
        #expect(large.stdoutTruncated)
        #expect(large.stdout.hasSuffix("0123456789"))
    }

    @Test("runInBackground は成功したら出力を返す")
    func runInBackgroundReturnsOutput() async throws {
        let directory = try ActionTemporaryDirectory()
        let output = try await ScriptRunner.runInBackground(
            source: "print -r -- \"$NONET_APP_NAME\"",
            environment: directory.isolatedEnvironment.merging(["NONET_APP_NAME": "Finder"]) { _, new in new },
            workingDirectory: directory.url,
            timeout: 20,
            shellPath: "/usr/bin:/bin"
        )
        #expect(CommandOutput.text(from: output) == "Finder")
    }

    // MARK: - ショートカット

    @Test("出力の種類は頼まない（画像やファイルを返すショートカットを失敗させない）。名前は -- の後")
    func shortcutArguments() {
        #expect(ShortcutRunner.arguments(name: "n", inputPath: nil) == ["run", "--", "n"])
        #expect(ShortcutRunner.arguments(name: "n", inputPath: "/tmp/in.txt") == ["run", "--input-path", "/tmp/in.txt", "--", "n"])
        #expect(ShortcutRunner.arguments(name: "-x", inputPath: nil) == ["run", "--", "-x"])
    }
}

@Suite("ターミナルで ~/.zshrc を読む")
struct ActionTerminalZshrcTests {
    @Test("自分を消した直後に ~/.zshrc（ZDOTDIR があればそこ）を読み、その後に export と cd")
    func contentsSourceZshrc() {
        let text = TerminalCommandFile.contents(source: "claude", variables: ["PROJECT_DIR": "/p"], workingDirectory: "/p")
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let remove = lines.firstIndex(of: "rm -f -- \"$0\"") ?? -1
        #expect(lines.indices.contains(remove + 1))
        #expect(lines[remove + 1] == #"[[ -r "${ZDOTDIR:-$HOME}/.zshrc" ]] && source "${ZDOTDIR:-$HOME}/.zshrc""#)
        let export = lines.firstIndex { $0.hasPrefix("export PROJECT_DIR") } ?? -1
        #expect(remove + 1 < export)
    }

    @Test("実際に動かすと、~/.zshrc の関数と PATH が使え、~/.zshrc の cd より作業フォルダが勝つ")
    func runsWithZshrc() async throws {
        let directory = try ActionTemporaryDirectory()
        let project = try directory.subdirectory("project")
        try """
            nonet_from_zshrc() { print -r -- "from zshrc"; }
            path=(/nonet/zshrc/bin $path)
            cd /
            """.write(to: directory.url.appendingPathComponent(".zshrc"), atomically: true, encoding: .utf8)
        let contents = TerminalCommandFile.contents(
            source: #"nonet_from_zshrc; print -r -- "${path[1]}"; pwd -P"#,
            variables: [:],
            workingDirectory: project.path
        )
        let file = try TerminalCommandFile.write(contents, in: try directory.subdirectory("commands"))
        let output = try await ProcessRunner.run(ProcessRequest(
            executable: file,
            arguments: [],
            environment: directory.isolatedEnvironment,
            currentDirectory: directory.url,
            timeout: 20
        ))
        #expect(output.succeeded, "\(output.stderr)")
        #expect(output.stdout == "from zshrc\n/nonet/zshrc/bin\n\(actionRealPath(project))\n")
    }

    @Test(".zshrc が無くても動く")
    func runsWithoutZshrc() async throws {
        let directory = try ActionTemporaryDirectory()
        let contents = TerminalCommandFile.contents(source: "echo ran", variables: [:], workingDirectory: directory.url.path)
        let file = try TerminalCommandFile.write(contents, in: try directory.subdirectory("commands"))
        let output = try await ProcessRunner.run(ProcessRequest(
            executable: file,
            arguments: [],
            environment: directory.isolatedEnvironment,
            currentDirectory: directory.url,
            timeout: 20
        ))
        #expect(output.succeeded, "\(output.stderr)")
        #expect(output.stdout == "ran\n")
    }
}

@Suite("Dock のアプリ")
struct ActionDockAppsTests {
    static let tiles: [[String: Any]] = [
        ["tile-type": "file-tile", "tile-data": [
            "bundle-identifier": "com.apple.dt.Xcode",
            "file-label": "Xcode",
            "file-data": ["_CFURLString": "file:///Applications/Xcode.app/", "_CFURLStringType": 15],
        ]],
        ["tile-type": "spacer-tile", "tile-data": [String: Any]()],
        ["tile-type": "file-tile", "tile-data": [
            "bundle-identifier": "com.apple.mail",
            "file-label": "メール",
            "file-data": ["_CFURLString": "/System/Applications/Mail.app", "_CFURLStringType": 0],
        ]],
        ["tile-type": "file-tile", "tile-data": ["bundle-identifier": "  ", "file-label": "空"]],
        ["tile-type": "file-tile", "tile-data": ["bundle-identifier": "org.example.web", "file-data": ["_CFURLString": "https://example.com"]]],
    ]

    @Test("アプリのタイルを Dock の順に読む。仕切りと bundleID の無いものは飛ばす")
    func parsesTiles() {
        let tiles = DockApps.tiles(from: Self.tiles)
        #expect(tiles == [
            DockTile(bundleID: "com.apple.dt.Xcode", url: URL(string: "file:///Applications/Xcode.app/"), label: "Xcode"),
            DockTile(bundleID: "com.apple.mail", url: URL(fileURLWithPath: "/System/Applications/Mail.app", isDirectory: true), label: "メール"),
            DockTile(bundleID: "org.example.web", url: nil, label: nil),
        ])
        #expect(DockApps.tiles(from: nil).isEmpty)
        #expect(DockApps.tiles(from: "not an array").isEmpty)
    }

    @Test("インストール済みだけを、Finder の名前（無ければ Dock の名前）で。自分自身と2つ目は除く")
    func installedAppsOnly() {
        let tiles = [
            DockTile(bundleID: "com.iam74k4.Nonet", url: URL(fileURLWithPath: "/Applications/Nonet.app"), label: "Nonet"),
            DockTile(bundleID: "com.apple.dt.Xcode", url: URL(fileURLWithPath: "/Applications/Xcode.app"), label: "Xcode-old"),
            DockTile(bundleID: "com.example.removed", url: URL(fileURLWithPath: "/Applications/Removed.app"), label: "Removed"),
            DockTile(bundleID: "COM.APPLE.DT.XCODE", url: URL(fileURLWithPath: "/Applications/Xcode.app"), label: "Xcode"),
            DockTile(bundleID: "com.example.labelled", url: URL(fileURLWithPath: "/Applications/Labelled.app"), label: "ラベル"),
            DockTile(bundleID: "com.example.bare", url: URL(fileURLWithPath: "/Applications/Bare.app"), label: nil),
        ]
        let apps = DockApps.apps(
            from: tiles,
            excluding: "com.iam74k4.nonet",
            locate: { $0.bundleID == "com.example.removed" ? nil : $0.url },
            name: { $0.lastPathComponent == "Xcode.app" ? "Xcode" : nil }
        )
        #expect(apps == [
            AppReference(bundleID: "com.apple.dt.Xcode", name: "Xcode"),
            AppReference(bundleID: "com.example.labelled", name: "ラベル"),
            AppReference(bundleID: "com.example.bare", name: "com.example.bare"),
        ])
    }

    @Test("この Mac の Dock を読める（確認は出ない。中身は Mac ごとに違うので形だけ）")
    func readsThisMac() {
        for tile in DockApps.readTiles() {
            #expect(!tile.bundleID.isEmpty)
        }
    }

    /// NUL（U+0000）の入った引数や環境変数は、Process に渡すとアプリが落ちる（Objective-C の例外）。始める前にエラーにする
    @Test func argumentsWithNULAreRefusedBeforeLaunch() async throws {
        let echo = URL(fileURLWithPath: "/bin/echo")
        await #expect(throws: NonetError.self) {
            _ = try await ProcessRunner.run(ProcessRequest(executable: echo, arguments: ["a\u{0}b"], environment: nil, currentDirectory: nil, timeout: 5))
        }
        await #expect(throws: NonetError.self) {
            _ = try await ProcessRunner.run(ProcessRequest(executable: echo, arguments: ["ok"], environment: ["X": "a\u{0}b"], currentDirectory: nil, timeout: 5))
        }
        let output = try await ProcessRunner.run(ProcessRequest(executable: echo, arguments: ["ok"], environment: nil, currentDirectory: nil, timeout: 5))
        #expect(output.stdout == "ok\n")
    }
}
