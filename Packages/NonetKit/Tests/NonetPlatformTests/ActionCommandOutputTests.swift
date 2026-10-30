import Foundation
import NonetCore
@testable import NonetPlatform
import Testing

/// 裏のスクリプトの PATH・コマンドが見つからないときの説明・スクリプトとショートカットの出力
@Suite("スクリプトの PATH と出力")
struct ActionCommandOutputTests {
    private func run(_ source: String, in directory: ActionTemporaryDirectory, shellPath: String?, outputLimit: Int = ScriptRunner.outputLimit) async throws -> ProcessOutput {
        try await ProcessRunner.run(ProcessRequest(
            executable: ScriptRunner.shell,
            arguments: ScriptRunner.arguments(source: source, shellPath: shellPath),
            environment: ScriptRunner.environment(base: directory.isolatedEnvironment, context: [:], shellPath: shellPath),
            currentDirectory: directory.url,
            timeout: 20,
            outputLimit: outputLimit
        ))
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

    @Test("PATH を前に置いても、行番号と引数の形は変わらない")
    func argumentsWithShellPath() async throws {
        #expect(ScriptRunner.arguments(source: "echo hi", shellPath: nil) == ["-l", "-c", "--", "echo hi"])
        #expect(ScriptRunner.arguments(source: "echo hi", shellPath: "") == ["-l", "-c", "--", "echo hi"])
        let arguments = ScriptRunner.arguments(source: "echo hi", shellPath: "/a b/it's:/usr/bin")
        #expect(arguments.prefix(3) == ["-l", "-c", "--"])
        #expect(arguments.last == #"export PATH='/a b/it'\''s:/usr/bin'; echo hi"#)

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
            localized: "コマンドが見つかりません。インストールされているか、ターミナルで command -v \("nonet-no-such-command-xyz") を確かめてください",
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
        #expect(message.hasSuffix(String(localized: "コマンドが見つかりません。インストールされているか、ターミナルで確かめてください", bundle: .nonetActions)))
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
    ] as [(String, String?)])
    func trimsOneTrailingNewline(stdout: String, expected: String?) throws {
        #expect(try CommandOutput.text(from: Self.output(stdout)) == expected)
    }

    @Test("上限を超えて先頭が切れた出力は使わない")
    func truncatedOutputIsRefused() throws {
        let error = #expect(throws: NonetError.self) {
            try CommandOutput.text(from: Self.output("tail", truncated: true))
        }
        let expected = String(localized: "出力が大きすぎるため、使えませんでした（\(ScriptRunner.outputLimit / 1024) KB まで）", bundle: .nonetActions)
        #expect(error == .actionFailed(expected))
    }

    @Test("標準出力が上限を超えたかを返す")
    func reportsTruncation() async throws {
        let directory = try ActionTemporaryDirectory()
        let small = try await run("printf 'abc'", in: directory, shellPath: nil, outputLimit: 16)
        #expect(!small.stdoutTruncated)
        #expect(small.stdout == "abc")
        let large = try await run("printf '%.0s0123456789' {1..10}", in: directory, shellPath: nil, outputLimit: 16)
        #expect(large.stdoutTruncated)
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
        #expect(try CommandOutput.text(from: output) == "Finder")
    }

    // MARK: - ショートカット

    @Test("出力を使うときだけ、テキストで出力するよう頼む")
    func shortcutArguments() {
        #expect(ShortcutRunner.arguments(name: "n", inputPath: nil) == ["run", "--", "n"])
        #expect(ShortcutRunner.arguments(name: "n", inputPath: "/tmp/in.txt", wantsTextOutput: true)
            == ["run", "--input-path", "/tmp/in.txt", "--output-type", "public.utf8-plain-text", "--", "n"])
        #expect(ShortcutRunner.arguments(name: "-x", inputPath: nil, wantsTextOutput: true)
            == ["run", "--output-type", "public.utf8-plain-text", "--", "-x"])
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
}
