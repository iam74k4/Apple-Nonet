// 担当: platform-actions
import Foundation
import os

extension Bundle {
    /// Actions の文言を引く場所
    static var nonetActions: Bundle {
        .module
    }
}

enum ActionLog {
    static let logger = Logger(subsystem: "com.iam74k4.Nonet", category: "platform-actions")
}

enum ActionText {
    /// NonetError.permissionDenied に渡す権限の名前
    static var accessibility: String {
        String(localized: "アクセシビリティ", bundle: .nonetActions)
    }

    /// エラーに添える標準エラーの末尾。空行を除き、長い行は切り詰める
    static func lastLines(of text: String, count: Int = 3, maxLineLength: Int = 200) -> [String] {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.suffix(count).map { line in
            line.count > maxLineLength ? String(line.prefix(maxLineLength)) + "…" : line
        }
    }

    /// 見出しと詳細（標準エラーの末尾など）を改行でつなぐ
    static func message(_ headline: String, detail: String) -> String {
        let lines = lastLines(of: detail)
        return lines.isEmpty ? headline : ([headline] + lines).joined(separator: "\n")
    }
}
