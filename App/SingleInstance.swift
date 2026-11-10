import AppKit
import NonetUI

/// 同じ Nonet（同じ bundle ID）がもう動いていたら、そちらに設定を開かせてこのプロセスは終わる。
/// 動いている方がディスクイメージなどから開いたままのもので、こちらがアプリケーションフォルダのものなら、そちらを終わらせて代わりに動く。
/// こちらがディスクイメージなどから開いたもので、アプリケーションフォルダで動いている方より新しければ、そちらを終わらせて起動し、
/// アプリケーションフォルダの Nonet を置き換えるかを尋ねる（AppDelegate の ShellMoveToApplications.offerIfNeeded）。
/// 新しくなければ、そのことを伝えてから終わる。決め方は NonetUI の ShellInstanceGuard（テストあり）
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
            location: ShellInstallLocation.of(bundleURL: Bundle.main.bundleURL),
            bundleVersion: Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        )
        var locations: [pid_t: ShellInstallLocation] = [:]
        var versions: [pid_t: String?] = [:]
        var askedToQuit: Set<pid_t> = []
        let start = Date()
        while true {
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).map { app in
                let processID = app.processIdentifier
                let location = locations[processID] ?? app.bundleURL.map(ShellInstallLocation.of(bundleURL:)) ?? .installed
                locations[processID] = location
                let version = versions[processID] ?? app.bundleURL.flatMap(bundleVersion(at:))
                versions[processID] = version
                return ShellRunningInstance(
                    processID: processID,
                    bundleURL: app.bundleURL,
                    isTerminated: app.isTerminated || !isAlive(processID),
                    isFinishedLaunching: app.isFinishedLaunching,
                    // 終わり始めたもの（applicationWillTerminate で印を書く）だけを待つ。動いているものには、待たずに設定を開かせる
                    isQuitting: processID != current.processIdentifier
                        && ShellQuitMarker.isQuitting(processID: processID, launchDate: app.launchDate),
                    launchDate: app.launchDate,
                    location: location,
                    bundleVersion: version
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
                // ディスクイメージなどから開いたままのもの（またはこちらより古いアプリケーションフォルダのもの）を終わらせ、
                // こちらが代わりに動く。古い方を終わらせたときは、起動した後で置き換えるかを尋ねる
                if askedToQuit.insert(other.processID).inserted {
                    NSRunningApplication(processIdentifier: other.processID)?.terminate()
                }
                waitBriefly()
            case .handOff(let other):
                // 起動の途中のもの（同時に開かれた）は、こちらが終わるのを待って起動するので、頼まずに終わる
                // （こちらが起動を終えたように見えると、相手もこちらへ任せて、両方とも終わってしまう）
                guard other.isFinishedLaunching else { exit(0) }
                forwardOpenRequestsAndExit(to: other, explainsFirst: false)
            case .explainAndHandOff(let other):
                // ディスクイメージなどから開いたこちらは、動いている方より新しくない。黙って終わらずに伝えてから任せる
                forwardOpenRequestsAndExit(to: other, explainsFirst: true)
            }
        }
    }

    /// bundleURL のアプリのビルド番号（CFBundleVersion）。Bundle はキャッシュされるので、Info.plist を直接読む
    private static func bundleVersion(at bundleURL: URL) -> String? {
        let plist = bundleURL.appendingPathComponent("Contents/Info.plist", isDirectory: false)
        return NSDictionary(contentsOf: plist)?["CFBundleVersion"] as? String
    }

    /// 一覧の isTerminated・isFinishedLaunching はメインのランループで更新される
    private static func waitBriefly() {
        RunLoop.current.run(until: Date().addingTimeInterval(ShellInstanceGuard.pollInterval))
    }

    /// プロセスがまだあるか（一覧から消えるのは少し遅れる）
    private static func isAlive(_ processID: pid_t) -> Bool {
        kill(processID, 0) == 0 || errno == EPERM
    }

    /// 動いている方に任せて終わる。購入のメールの nonet://register のリンクや .nonetlicense のファイルで開かれていたら、
    /// それを動いている方で開く（開かれたことは NSApplication を動かしてから届くので、少しだけ受け取ってから終わる）。
    /// 何も届かなければ、動いている方に設定を開かせる
    private static func forwardOpenRequestsAndExit(to other: ShellRunningInstance, explainsFirst: Bool) -> Never {
        let forwarder = HandOffForwarder(target: other, explainsFirst: explainsFirst)
        let app = NSApplication.shared
        // Dock に出さない（本体と同じ。.prohibited だと、新しくないことを伝える画面を出せない）
        app.setActivationPolicy(.accessory)
        app.delegate = forwarder
        app.run()
        exit(0)
    }

    /// 動いている方を開き直すと、そちらの applicationShouldHandleReopen が設定を開く
    static func showSettings(of other: ShellRunningInstance) {
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

/// 任せて終わる前に、このプロセスで開かれたリンクとファイルを受け取り、動いている Nonet で開く
@MainActor
private final class HandOffForwarder: NSObject, NSApplicationDelegate {
    /// 起動してから、開かれたものが届くのを待つ時間
    static let collectionDelay: TimeInterval = 0.5

    private let target: ShellRunningInstance
    private let explainsFirst: Bool
    private var items: [URL] = []

    init(target: ShellRunningInstance, explainsFirst: Bool) {
        self.target = target
        self.explainsFirst = explainsFirst
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if explainsFirst {
            // 尋ねている間に届いたものも、application(_:open:) で受け取る
            ShellMoveToApplications.explainAlreadyRunning(runningAt: target.bundleURL)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.collectionDelay) { [self] in
            MainActor.assumeIsolated { finish() }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        items += urls
    }

    private func finish() {
        if !items.isEmpty, let url = target.bundleURL {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            let done = DoneFlag()
            NSWorkspace.shared.open(items, withApplicationAt: url, configuration: configuration) { _, _ in
                done.set()
            }
            // 頼んだことが届く前に終わらないよう、少しだけ待つ
            let deadline = Date().addingTimeInterval(5)
            while !done.isSet, Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            }
        } else {
            SingleInstance.showSettings(of: target)
        }
        exit(0)
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
