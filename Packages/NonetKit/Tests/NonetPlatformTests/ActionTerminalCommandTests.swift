import Foundation
@testable import NonetPlatform
import Testing

/// ターミナルは開かず、作った .command ファイルを /bin/zsh で直接動かして確かめる
@Suite("ターミナル用の .command ファイル")
struct ActionTerminalCommandTests {
    @Test("単一引用符で囲み、中の ' は '\\'' にする")
    func shellQuoting() {
        #expect(TerminalCommandFile.shellQuoted("abc") == "'abc'")
        #expect(TerminalCommandFile.shellQuoted("") == "''")
        #expect(TerminalCommandFile.shellQuoted("it's") == #"'it'\''s'"#)
        #expect(TerminalCommandFile.shellQuoted("a\0b") == "'ab'")
        #expect(TerminalCommandFile.shellQuoted("$(id) `id` \"x\"") == "'$(id) `id` \"x\"'")
    }

    @Test("変数名として使えるもの", arguments: [
        ("NONET_APP_NAME", true), ("PROJECT_DIR", true), ("_x1", true), ("a", true),
        ("", false), ("1ABC", false), ("BAD-NAME", false), ("A B", false), ("A=B", false), ("日本", false), ("X;rm", false),
    ])
    func variableNames(name: String, valid: Bool) {
        #expect(TerminalCommandFile.isValidVariableName(name) == valid)
    }

    @Test("中身: 自分を消し、変数を export し、作業フォルダへ移ってからスクリプト")
    func contentsLayout() {
        let text = TerminalCommandFile.contents(
            source: "claude",
            variables: ["PROJECT_DIR": "/p", "NONET_APP_NAME": "Xcode", "BAD-NAME": "x"],
            workingDirectory: "/p"
        )
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        #expect(lines.first == "#!/bin/zsh -l")
        #expect(lines.contains("rm -f -- \"$0\""))
        #expect(lines.contains("export NONET_APP_NAME='Xcode'"))
        #expect(lines.contains("export PROJECT_DIR='/p'"))
        #expect(!text.contains("BAD-NAME"))
        let exportIndex = lines.firstIndex { $0.hasPrefix("export NONET_APP_NAME") } ?? 0
        let cdIndex = lines.firstIndex { $0.hasPrefix("cd -- ") } ?? 0
        let sourceIndex = lines.firstIndex(of: "claude") ?? 0
        #expect(exportIndex < cdIndex)
        #expect(cdIndex < sourceIndex)
        #expect(text.hasSuffix("claude\n"))
    }

    @Test("実際に動かすと、変数の値はそのまま届き、作業フォルダへ移り、ファイルは消える")
    func runsSafely() async throws {
        let directory = try ActionTemporaryDirectory()
        let project = try directory.subdirectory("it's a \"project\" $(whoami)")
        let marker = directory.url.appendingPathComponent("injected")
        let tricky = "'; touch \(marker.path); echo '\n$(touch \(marker.path))`touch \(marker.path)`\"\\ 日本語"
        let variables = [
            "NONET_SELECTED_TEXT": tricky,
            "NONET_APP_NAME": "App's \"Name\"",
            "PROJECT_DIR": project.path,
        ]
        let source = #"printf '%s\n--\n%s\n--\n' "$NONET_SELECTED_TEXT" "$NONET_APP_NAME"; pwd -P"#
        let contents = TerminalCommandFile.contents(source: source, variables: variables, workingDirectory: project.path)
        let commandDirectory = try directory.subdirectory("commands")
        let file = try TerminalCommandFile.write(contents, in: commandDirectory)

        let output = try await ProcessRunner.run(ProcessRequest(
            executable: file,
            arguments: [],
            environment: directory.isolatedEnvironment,
            currentDirectory: directory.url,
            timeout: 20
        ))
        #expect(output.succeeded, "\(output.stderr)")
        #expect(output.stdout == "\(tricky)\n--\nApp's \"Name\"\n--\n\(actionRealPath(project))\n")
        #expect(!FileManager.default.fileExists(atPath: marker.path), "値がシェルに解釈された")
        #expect(!FileManager.default.fileExists(atPath: file.path), "実行後にファイルが消えていない")
    }

    @Test("作業フォルダが無ければスクリプトを実行しない")
    func missingWorkingDirectory() async throws {
        let directory = try ActionTemporaryDirectory()
        let contents = TerminalCommandFile.contents(
            source: "echo ran",
            variables: [:],
            workingDirectory: directory.url.appendingPathComponent("missing").path
        )
        let file = try TerminalCommandFile.write(contents, in: directory.url)
        let output = try await ProcessRunner.run(ProcessRequest(
            executable: file,
            arguments: [],
            environment: directory.isolatedEnvironment,
            currentDirectory: directory.url,
            timeout: 20
        ))
        #expect(output.status == 1)
        #expect(!output.stdout.contains("ran"))
    }

    @Test("書いたファイルは本人だけが読み書き・実行できる")
    func permissions() throws {
        let directory = try ActionTemporaryDirectory()
        let commandDirectory = directory.url.appendingPathComponent("Nonet/Terminal", isDirectory: true)
        let file = try TerminalCommandFile.write("#!/bin/zsh\n", in: commandDirectory)
        #expect(file.lastPathComponent.hasPrefix("nonet-"))
        #expect(file.pathExtension == "command")
        let fileMode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        let directoryMode = try FileManager.default.attributesOfItem(atPath: commandDirectory.path)[.posixPermissions] as? Int
        #expect(fileMode == 0o700)
        #expect(directoryMode == 0o700)
    }

    @Test("古い .command だけを消す")
    func removesStaleFiles() throws {
        let directory = try ActionTemporaryDirectory()
        let now = Date()
        func make(_ name: String, age: TimeInterval) throws -> URL {
            let url = directory.url.appendingPathComponent(name)
            try Data("x".utf8).write(to: url)
            try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: url.path)
            return url
        }
        let old = try make("nonet-old.command", age: 7200)
        let fresh = try make("nonet-fresh.command", age: 60)
        let other = try make("other.command", age: 7200)
        let otherExtension = try make("nonet-old.txt", age: 7200)
        TerminalCommandFile.removeStaleFiles(in: directory.url, olderThan: 3600, now: now)
        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(FileManager.default.fileExists(atPath: fresh.path))
        #expect(FileManager.default.fileExists(atPath: other.path))
        #expect(FileManager.default.fileExists(atPath: otherExtension.path))
        // フォルダが無くても落ちない
        TerminalCommandFile.removeStaleFiles(in: directory.url.appendingPathComponent("missing"), olderThan: 1)
    }
}
