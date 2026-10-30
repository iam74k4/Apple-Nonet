// 担当: platform-actions
import Foundation
import NonetCore

/// /usr/bin/shortcuts（ショートカット.app のコマンド）。
/// 出力は、--output-path を付けずに実行すると標準出力（パイプ）に書かれる。
/// Apple の「コマンドラインからショートカットを実行する」に「the | character」でほかのコマンドに渡せるとあり、
/// --output-type で出力の種類（UTI）を決められる: https://support.apple.com/guide/shortcuts-mac/run-shortcuts-from-the-command-line-apd455c82f02/mac
enum ShortcutRunner {
    static let executable = URL(fileURLWithPath: "/usr/bin/shortcuts")
    /// 対話のあるショートカットもあるので長め
    static let timeout: TimeInterval = 300
    /// 出力を使うときに頼む種類。リッチテキストや画像のままでは文字として読めないので、UTF-8 のテキストにしてもらう
    static let textOutputType = "public.utf8-plain-text"

    /// 名前は "--" の後に置き、"-" で始まる名前もオプションと間違えさせない
    static func arguments(name: String, inputPath: String?, wantsTextOutput: Bool = false) -> [String] {
        var arguments = ["run"]
        if let inputPath { arguments += ["--input-path", inputPath] }
        if wantsTextOutput { arguments += ["--output-type", textOutputType] }
        return arguments + ["--", name]
    }

    static var inputDirectory: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("Nonet", isDirectory: true)
            .appendingPathComponent("Shortcuts", isDirectory: true)
    }

    /// input があれば一時ファイルに書いて入力として渡す（終わったら消す）。成功したら出力を返す
    @discardableResult
    static func run(name: String, input: String?, wantsTextOutput: Bool = false) async throws -> ProcessOutput {
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
                arguments: arguments(name: name, inputPath: inputFile?.path, wantsTextOutput: wantsTextOutput),
                environment: nil,
                currentDirectory: nil,
                timeout: timeout,
                outputLimit: ScriptRunner.outputLimit
            ))
        } catch is CancellationError {
            throw CancellationError()
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

    private static func writeInput(_ text: String) throws -> URL {
        let fileManager = FileManager.default
        let directory = inputDirectory
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = directory.appendingPathComponent("input-\(UUID().uuidString).txt", isDirectory: false)
        guard fileManager.createFile(atPath: url.path, contents: Data(text.utf8), attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
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
