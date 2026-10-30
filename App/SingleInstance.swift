import AppKit
import NonetUI

/// 同じ Nonet（同じ bundle ID）がもう動いていたら、そちらに設定を開かせてこのプロセスは終わる。
/// 決め方は NonetUI の ShellInstanceGuard（テストあり）
@MainActor
enum SingleInstance {
    /// 起動を続けてよければ戻る。任せたときは戻らない
    static func handOffIfAlreadyRunning(allowsMultiple: Bool) {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let ownProcessID = ProcessInfo.processInfo.processIdentifier
        let start = Date()
        while true {
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).map { app in
                ShellRunningInstance(
                    processID: app.processIdentifier,
                    bundleURL: app.bundleURL,
                    isTerminated: app.isTerminated || !isAlive(app.processIdentifier)
                )
            }
            switch ShellInstanceGuard.decide(
                running: running,
                ownProcessID: ownProcessID,
                waited: Date().timeIntervalSince(start),
                allowsMultiple: allowsMultiple
            ) {
            case .launch:
                return
            case .wait:
                // 一覧の isTerminated はメインのランループで更新される
                RunLoop.current.run(until: Date().addingTimeInterval(ShellInstanceGuard.pollInterval))
            case .handOff(let other):
                showSettings(of: other)
                exit(0)
            }
        }
    }

    /// プロセスがまだあるか（一覧から消えるのは少し遅れる）
    private static func isAlive(_ processID: pid_t) -> Bool {
        kill(processID, 0) == 0 || errno == EPERM
    }

    /// 動いている方を開き直すと、そちらの applicationShouldHandleReopen が設定を開く
    private static func showSettings(of other: ShellRunningInstance) {
        guard let url = other.bundleURL else {
            NSRunningApplication(processIdentifier: other.processID)?.activate()
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let done = DoneFlag()
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            done.set()
        }
        // 頼んだことが届く前に終わらないよう、少しだけ待つ
        let deadline = Date().addingTimeInterval(5)
        while !done.isSet, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
    }
}

/// 別のスレッドから立てる印
private final class DoneFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.withLock { value }
    }

    func set() {
        lock.withLock { value = true }
    }
}
