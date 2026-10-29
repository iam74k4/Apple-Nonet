// 担当: platform-actions
import AppKit
import NonetCore

/// スクリプトアクション（/bin/zsh -l -c）
enum ScriptRunner {
    static let shell = URL(fileURLWithPath: "/bin/zsh")
    static let defaultTimeout: TimeInterval = 60
    static let maximumTimeout: TimeInterval = 24 * 60 * 60
    static let outputLimit = 64 * 1024

    /// ソースは引数の1つとして渡す。"--" で、"-" で始まるソースもオプションと間違えさせない
    static func arguments(source: String) -> [String] {
        ["-l", "-c", "--", source]
    }

    static func effectiveTimeout(_ timeout: Double) -> TimeInterval {
        guard timeout.isFinite, timeout > 0 else { return defaultTimeout }
        return min(timeout, maximumTimeout)
    }

    /// Nonet の環境変数に文脈の変数を重ねる。前に残った NONET_* は消す。
    /// Finder から起動したアプリには LANG が無く、pbcopy などが UTF-8 を化けさせるので LC_CTYPE を補う
    static func environment(base: [String: String], context: [String: String]) -> [String: String] {
        var environment = base.filter { key, _ in !key.hasPrefix("NONET_") && key != "PROJECT_DIR" }
        environment.merge(context) { _, new in new }
        if environment["LANG"] == nil, environment["LC_ALL"] == nil, environment["LC_CTYPE"] == nil {
            environment["LC_CTYPE"] = "UTF-8"
        }
        return environment
    }

    /// プロジェクトのフォルダがあればそこ、無ければホーム
    static func workingDirectory(projectDirectory: String?, home: URL, isDirectory: (String) -> Bool) -> URL {
        if let projectDirectory, !projectDirectory.isEmpty, isDirectory(projectDirectory) {
            return URL(fileURLWithPath: projectDirectory, isDirectory: true)
        }
        return home
    }

    static func isDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    static func validate(source: String) throws {
        if source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw NonetError.actionFailed(String(localized: "スクリプトが空です", bundle: .nonetActions))
        }
    }

    /// 裏で実行し、終わるまで待つ。失敗したら標準エラーの末尾を添えた NonetError
    static func runInBackground(
        source: String,
        environment: [String: String],
        workingDirectory: URL,
        timeout: TimeInterval
    ) async throws {
        try validate(source: source)
        let output: ProcessOutput
        do {
            output = try await ProcessRunner.run(ProcessRequest(
                executable: shell,
                arguments: arguments(source: source),
                environment: environment,
                currentDirectory: workingDirectory,
                timeout: timeout,
                outputLimit: outputLimit
            ))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            ActionLog.logger.error("スクリプトを起動できませんでした: \(error.localizedDescription)")
            throw NonetError.actionFailed(String(localized: "スクリプトを実行できませんでした", bundle: .nonetActions))
        }
        if let failure = failure(for: output) { throw failure }
    }

    static func failure(for output: ProcessOutput) -> NonetError? {
        if output.timedOut { return .timedOut }
        if output.wasSignaled {
            let headline = String(localized: "スクリプトが中断されました（シグナル \(output.status)）", bundle: .nonetActions)
            return .actionFailed(ActionText.message(headline, detail: output.stderr))
        }
        if output.status != 0 {
            let headline = String(localized: "スクリプトが失敗しました（終了コード \(output.status)）", bundle: .nonetActions)
            return .actionFailed(ActionText.message(headline, detail: output.stderr))
        }
        return nil
    }
}

/// ターミナルで実行するための一時的な .command ファイル
enum TerminalCommandFile {
    static let terminalBundleID = "com.apple.Terminal"
    static let filePrefix = "nonet-"
    static let fileExtension = "command"
    /// 開かれずに残ったファイルを消すまでの時間
    static let staleAge: TimeInterval = 60 * 60

    static var directory: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("Nonet", isDirectory: true)
            .appendingPathComponent("Terminal", isDirectory: true)
    }

    /// シェルの単一引用符で囲む。中の ' は '\'' にする。NUL は環境変数にもシェルにも入らないので消す
    static func shellQuoted(_ text: String) -> String {
        let cleaned = text.replacingOccurrences(of: "\0", with: "")
        return "'" + cleaned.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func isValidVariableName(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first, first == "_" || (first.isASCII && first.properties.isAlphabetic) else {
            return false
        }
        return name.unicodeScalars.allSatisfy { $0 == "_" || ($0.isASCII && ($0.properties.isAlphabetic || ("0" ... "9").contains($0))) }
    }

    /// 実行が始まったら自分を消し、変数を export し、作業フォルダへ移ってからスクリプトを実行する
    static func contents(source: String, variables: [String: String], workingDirectory: String) -> String {
        var lines = [
            "#!/bin/zsh -l",
            "# Nonet がターミナルで実行するために作った一時ファイル（実行が始まると消える）",
            "rm -f -- \"$0\"",
        ]
        for name in variables.keys.sorted() where isValidVariableName(name) {
            lines.append("export \(name)=\(shellQuoted(variables[name] ?? ""))")
        }
        lines.append("cd -- \(shellQuoted(workingDirectory)) || exit 1")
        lines.append(source)
        return lines.joined(separator: "\n") + "\n"
    }

    /// 本人だけが読み書き・実行できるファイルとして書く
    static func write(_ contents: String, in directory: URL) throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = directory.appendingPathComponent("\(filePrefix)\(UUID().uuidString).\(fileExtension)", isDirectory: false)
        guard fileManager.createFile(atPath: url.path, contents: Data(contents.utf8), attributes: [.posixPermissions: 0o700]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return url
    }

    /// 開かれなかったなどで残った古いファイルを消す
    static func removeStaleFiles(in directory: URL, olderThan age: TimeInterval, now: Date = Date()) {
        let fileManager = FileManager.default
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        for url in urls where url.lastPathComponent.hasPrefix(filePrefix) && url.pathExtension == fileExtension {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, now.timeIntervalSince(modified) > age {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    /// ターミナルの新しいウィンドウで実行する
    @MainActor
    static func open(source: String, variables: [String: String], workingDirectory: String) async throws {
        try ScriptRunner.validate(source: source)
        let directory = directory
        removeStaleFiles(in: directory, olderThan: staleAge)
        let file: URL
        do {
            file = try write(contents(source: source, variables: variables, workingDirectory: workingDirectory), in: directory)
        } catch {
            ActionLog.logger.error("一時ファイルを書けませんでした: \(error.localizedDescription)")
            throw NonetError.actionFailed(String(localized: "ターミナル用のファイルを作れませんでした", bundle: .nonetActions))
        }
        let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: terminalBundleID)
            ?? URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app", isDirectory: true)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            _ = try await NSWorkspace.shared.open([file], withApplicationAt: terminal, configuration: configuration)
        } catch {
            try? FileManager.default.removeItem(at: file)
            ActionLog.logger.error("ターミナルを開けませんでした: \(error.localizedDescription)")
            throw NonetError.actionFailed(String(localized: "ターミナルを開けませんでした", bundle: .nonetActions))
        }
    }
}
