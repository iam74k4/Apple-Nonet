import AppKit
import NonetUI

/// 同じ Nonet（同じ bundle ID）がもう動いていたら、そちらに設定を開かせてこのプロセスは終わる。
/// 動いている方がディスクイメージなどから開いたままのもので、こちらがアプリケーションフォルダのものなら、そちらを終わらせて代わりに動く。
/// 決め方は NonetUI の ShellInstanceGuard（テストあり）
@MainActor
enum SingleInstance {
    /// 起動を続けてよければ戻る。任せたときは戻らない
    static func handOffIfAlreadyRunning(allowsMultiple: Bool) {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let current = NSRunningApplication.current
        // 自分はまだ起動の途中（NSApplication を動かす前）
        let own = ShellRunningInstance(
            processID: current.processIdentifier,
            bundleURL: Bundle.main.bundleURL,
            isFinishedLaunching: false,
            launchDate: current.launchDate,
            location: ShellInstallLocation.of(bundleURL: Bundle.main.bundleURL)
        )
        var locations: [pid_t: ShellInstallLocation] = [:]
        var askedToQuit: Set<pid_t> = []
        let start = Date()
        while true {
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).map { app in
                let processID = app.processIdentifier
                let location = locations[processID] ?? app.bundleURL.map(ShellInstallLocation.of(bundleURL:)) ?? .installed
                locations[processID] = location
                return ShellRunningInstance(
                    processID: processID,
                    bundleURL: app.bundleURL,
                    isTerminated: app.isTerminated || !isAlive(processID),
                    isFinishedLaunching: app.isFinishedLaunching,
                    launchDate: app.launchDate,
                    location: location
                )
            }
            switch ShellInstanceGuard.decide(
                running: running,
                own: own,
                waited: Date().timeIntervalSince(start),
                allowsMultiple: allowsMultiple
            ) {
            case .launch:
                return
            case .wait:
                waitBriefly()
            case .replace(let other):
                // ディスクイメージなどから開いたままのものを終わらせ、アプリケーションフォルダのこちらが代わりに動く
                if askedToQuit.insert(other.processID).inserted {
                    NSRunningApplication(processIdentifier: other.processID)?.terminate()
                }
                waitBriefly()
            case .handOff(let other):
                // 起動の途中のもの（同時に開かれた）は、こちらが終わるのを待って起動するので、頼まずに終わる
                if other.isFinishedLaunching {
                    showSettings(of: other)
                }
                exit(0)
            }
        }
    }

    /// 一覧の isTerminated・isFinishedLaunching はメインのランループで更新される
    private static func waitBriefly() {
        RunLoop.current.run(until: Date().addingTimeInterval(ShellInstanceGuard.pollInterval))
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
