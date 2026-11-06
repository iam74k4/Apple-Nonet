// 担当: ui-shell
import AppKit
import os

private let relaunchLogger = Logger(subsystem: "com.iam74k4.Nonet", category: "ui-shell")

/// Nonet を開き直す（macOS の「画面収録」の許可は、与えた後に開き直したプロセスから効くため）。
/// 自分が終わってから開くよう、少し待ってから open する小さなシェルを先に走らせ、それから終了する
/// （同じ Nonet が動いている間に起動すると、SingleInstance がそちらに任せて終わってしまう。終わり始めた印は applicationWillTerminate で書く）
@MainActor
enum ShellRelaunch {
    static func relaunch(terminate: () -> Void = { NSApplication.shared.terminate(nil) }) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 0.5; /usr/bin/open -n \"$0\"", Bundle.main.bundlePath]
        do {
            try process.run()
        } catch {
            relaunchLogger.error("開き直せない: \(error.localizedDescription, privacy: .public)")
            return
        }
        terminate()
    }
}
