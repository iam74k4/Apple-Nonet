// 担当: platform-actions
import Foundation
import NonetCore
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

/// 止まるかもしれない呼び出し（クリップボードの中身を渡すのが遅いアプリ・眠ったネットワークの場所）をメインスレッドの外で行う。
/// メインスレッドではイベントタップも動いているので、そこで待つと Mac 全体のキー入力が止まる
enum BlockingCall {
    /// 制限時間を過ぎたら呼び出しの終わりを待たずに fallback を返す（呼び出しは裏で終わるまで続く）。
    /// queue を渡すと、そのキューで呼ぶ（直列のキューなら、前の呼び出しが終わってから）
    static func run<T>(
        timeout: TimeInterval,
        fallback: T,
        queue: DispatchQueue = .global(qos: .userInitiated),
        _ body: @escaping @Sendable () -> T
    ) async -> T {
        await withCheckedContinuation { continuation in
            let gate = ResumeOnce(continuation)
            queue.async {
                gate.resume(with: body())
            }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + max(0, timeout)) {
                gate.resume(with: fallback)
            }
        }
    }

    /// 先に来たほうだけで再開する
    private final class ResumeOnce<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<T, Never>?

        init(_ continuation: CheckedContinuation<T, Never>) {
            self.continuation = continuation
        }

        func resume(with value: T) {
            lock.lock()
            let continuation = self.continuation
            self.continuation = nil
            lock.unlock()
            continuation?.resume(returning: value)
        }
    }
}

/// キー入力のマスを送る直前に、前面のアプリが、9マスを開いたとき（テスト実行では前面に出したとき）のアプリのままか確かめる。
/// 前のマスのアプリの起動を待つ間などに前面が変わっていたら、別のアプリに ⌘W などを送らない
enum KeyTarget {
    /// expected が無い・いまの前面が分からないときは確かめない
    static func check(expected: RunningAppInfo?, frontmostPID: pid_t?) throws {
        guard let expected, let frontmostPID, frontmostPID != expected.processID else { return }
        ActionLog.logger.notice("前面のアプリが変わったので、キーを送らない")
        throw NonetError.actionFailed(String(localized: "前面のアプリが変わったため、キーを送りませんでした", bundle: .nonetActions))
    }
}

enum ActionText {
    /// NonetError.permissionDenied に渡す権限の名前
    static var accessibility: String {
        String(localized: "アクセシビリティ", bundle: .nonetActions)
    }

    /// Finder を操作する許可（システム設定の「プライバシーとセキュリティ」の「オートメーション」）
    static var finderAutomation: String {
        String(localized: "オートメーション（Finder）", bundle: .nonetActions)
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
    static func message(_ headline: String, detail: String, lineCount: Int = 3) -> String {
        let lines = lastLines(of: detail, count: lineCount)
        return lines.isEmpty ? headline : ([headline] + lines).joined(separator: "\n")
    }
}
