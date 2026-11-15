// 担当: platform-actions
import Foundation
import NonetCore

/// /usr/bin/shortcuts（ショートカット.app のコマンド）。
/// 出力は、--output-path を付けずに実行すると標準出力（パイプ）に書かれる。
/// Apple の「コマンドラインからショートカットを実行する」に「the | character」でほかのコマンドに渡せるとある:
/// https://support.apple.com/guide/shortcuts-mac/run-shortcuts-from-the-command-line-apd455c82f02/mac
/// --output-type（出力の種類）は付けない。画像やファイルを返すショートカットで、テキストにできずに失敗しうるので。
/// テキストでない出力は CommandOutput.text が除く（リッチテキストは文字にする）
enum ShortcutRunner {
    static let executable = URL(fileURLWithPath: "/usr/bin/shortcuts")
    /// 対話のあるショートカットもあるので長め
    static let timeout: TimeInterval = 300

    /// 名前は "--" の後に置き、"-" で始まる名前もオプションと間違えさせない
    static func arguments(name: String, inputPath: String?) -> [String] {
        var arguments = ["run"]
        if let inputPath { arguments += ["--input-path", inputPath] }
        return arguments + ["--", name]
    }

    /// 利用者ごとの一時フォルダ（TMPDIR を /tmp などに変えていても、OS に聞いた本人だけの場所。ターミナルの一時ファイルと同じ）
    static var inputDirectory: URL {
        TerminalCommandFile.perUserTemporaryDirectory
            .appendingPathComponent("Nonet", isDirectory: true)
            .appendingPathComponent("Shortcuts", isDirectory: true)
    }

    /// input があれば一時ファイルに書いて入力として渡す（終わったら消す）。成功したら出力を返す
    @discardableResult
    static func run(name: String, input: String?) async throws -> ProcessOutput {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NonetError.actionFailed(String(localized: "ショートカットの名前が空です", bundle: .nonetActions))
        }
        var inputFile: URL?
        defer { if let inputFile { try? FileManager.default.removeItem(at: inputFile) } }
        if let input {
            do {
                inputFile = try writeInput(input)
            } catch {
                ActionLog.logger.error("ショートカットの入力を書けませんでした: \(error.localizedDescription)")
                throw NonetError.actionFailed(String(localized: "ショートカットに渡すテキストを用意できませんでした", bundle: .nonetActions))
            }
        }
        let output: ProcessOutput
        do {
            output = try await ProcessRunner.run(ProcessRequest(
                executable: executable,
                arguments: arguments(name: name, inputPath: inputFile?.path),
                environment: nil,
                currentDirectory: nil,
                timeout: timeout,
                outputLimit: ScriptRunner.outputLimit
            ))
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as NonetError {
            // 始める前に断った理由（名前に NUL が入っているなど）は、そのまま知らせる
            throw error
        } catch {
            ActionLog.logger.error("shortcuts を起動できませんでした: \(error.localizedDescription)")
            throw NonetError.actionFailed(String(localized: "ショートカットを実行できませんでした", bundle: .nonetActions))
        }
        if let failure = failure(for: output, name: name) { throw failure }
        return output
    }

    static func failure(for output: ProcessOutput, name: String) -> NonetError? {
        if output.timedOut { return .timedOut }
        guard !output.succeeded else { return nil }
        let headline = String(localized: "ショートカット「\(name)」が失敗しました", bundle: .nonetActions)
        return .actionFailed(ActionText.message(headline, detail: output.stderr.isEmpty ? output.stdout : output.stderr))
    }

    /// 選択中のテキストを、本人だけが読み書きできるファイルとして書く。フォルダが前からあっても本人だけのものにし、
    /// ファイルは新しく作る（既にあるファイルやリンクには書かない。ほかの利用者に入れ替えられたり読まれたりしない）
    private static func writeInput(_ text: String) throws -> URL {
        let fileManager = FileManager.default
        let directory = inputDirectory
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let url = directory.appendingPathComponent("input-\(UUID().uuidString).txt", isDirectory: false)
        let descriptor = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: Data(text.utf8))
            try handle.close()
        } catch {
            try? fileManager.removeItem(at: url)
            throw error
        }
        return url
    }
}

enum ShortcutListParser {
    /// `shortcuts list` の出力（1行に1つ）。空行と重複を除き、名前順
    static func names(from output: String) -> [String] {
        var seen = Set<String>()
        return output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}

/// `shortcuts list` でショートカットの名前を得る
@MainActor
public final class ShortcutsCLI: ShortcutsProviding {
    static let listTimeout: TimeInterval = 15

    public init() {}

    public func shortcutNames() async -> [String] {
        do {
            let output = try await ProcessRunner.run(ProcessRequest(
                executable: ShortcutRunner.executable,
                arguments: ["list"],
                environment: nil,
                currentDirectory: nil,
                timeout: Self.listTimeout,
                outputLimit: 1 << 20
            ))
            guard output.succeeded else {
                ActionLog.logger.error("shortcuts list が失敗しました（終了コード \(output.status)、時間切れ \(output.timedOut)）")
                return []
            }
            return ShortcutListParser.names(from: output.stdout)
        } catch {
            ActionLog.logger.error("shortcuts list を実行できませんでした: \(error.localizedDescription)")
            return []
        }
    }
}
