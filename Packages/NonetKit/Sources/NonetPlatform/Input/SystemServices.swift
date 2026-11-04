// 担当: platform-input
// クラス名・public init・protocol への準拠は契約（NonetServices.live() が使う）
import AppKit
import ApplicationServices
import Carbon
import NonetCore

@MainActor
public final class SystemPermissions: PermissionsProviding {
    /// 設定アプリのアクセシビリティの欄。上から順に試す
    static let accessibilitySettingsURLs = [
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
    ]

    public init() {}

    public var isAccessibilityGranted: Bool { AXIsProcessTrusted() }

    public func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    public func openAccessibilitySettings() {
        for string in Self.accessibilitySettingsURLs {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
        inputLogger.error("アクセシビリティの設定を開けないので、システム設定を開く")
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }

    public var isSecureInputActive: Bool { IsSecureEventInputEnabled() }

    /// 設定アプリの画面収録の欄
    static let screenCaptureSettingsURLs = [
        "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
        "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture",
    ]

    /// 聞くだけで、ダイアログは出さない
    public var isScreenCaptureGranted: Bool { CGPreflightScreenCaptureAccess() }

    /// まだ聞いていなければシステムのダイアログを出す。断られた後は何も出ないので、設定画面は openScreenCaptureSettings も並べる
    public func requestScreenCapture() {
        _ = CGRequestScreenCaptureAccess()
    }

    public func openScreenCaptureSettings() {
        for string in Self.screenCaptureSettingsURLs {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
        inputLogger.error("画面収録の設定を開けないので、システム設定を開く")
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }
}

/// 前面アプリを見張る。Nonet 自身が前面になったとき（設定画面を開いたときなど）は無視して、直前のアプリのままにする
@MainActor
public final class WorkspaceFrontmostAppObserver: FrontmostAppObserving {
    public var onChange: ((RunningAppInfo?) -> Void)?
    public private(set) var current: RunningAppInfo?

    private let own = FrontmostAppFilter.Own(bundleID: Bundle.main.bundleIdentifier, processID: ProcessInfo.processInfo.processIdentifier)
    private var observations: [NotificationObservation] = []

    public init() {
        if case .update(let info) = decide(NSWorkspace.shared.frontmostApplication) {
            current = info
        }
    }

    public func start() {
        guard observations.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        observations = [
            NotificationObservation(center: center, name: NSWorkspace.didActivateApplicationNotification) { [weak self] notification in
                self?.activated(Self.application(in: notification))
            },
            NotificationObservation(center: center, name: NSWorkspace.didTerminateApplicationNotification) { [weak self] notification in
                self?.terminated(Self.application(in: notification))
            },
        ]
        activated(NSWorkspace.shared.frontmostApplication)
    }

    public func stop() {
        observations = []
    }

    /// 設定ウィンドウ・初回の案内・結果のパネル（クリックしてキーにしたとき）など、Nonet のウィンドウがキーで、
    /// 送ったキーがそこに届く。Nonet が前面のアプリでも、ウィンドウを閉じた後や Finder から開いた直後のように
    /// キーのウィンドウが無ければ false（キーはどのウィンドウにも届かない）
    public var isOwnWindowKey: Bool {
        let window = NSApplication.shared.keyWindow
        return FrontmostAppFilter.receivesKeys(keyWindowIsKey: window?.isKeyWindow, isVisible: window?.isVisible)
    }

    private func activated(_ app: NSRunningApplication?) {
        guard case .update(let info) = decide(app) else { return }
        set(info)
    }

    /// 前面のアプリが終了して Nonet が前面になったときに、終了したアプリのプロファイルを使い続けないように
    private func terminated(_ app: NSRunningApplication?) {
        guard let app, app.processIdentifier == current?.processID else { return }
        set(nil)
    }

    private func set(_ info: RunningAppInfo?) {
        guard info != current else { return }
        current = info
        onChange?(info)
    }

    private func decide(_ app: NSRunningApplication?) -> FrontmostAppFilter.Decision {
        guard let app else { return .update(nil) }
        return FrontmostAppFilter.decide(bundleID: app.bundleIdentifier, name: app.localizedName, processID: app.processIdentifier, own: own)
    }

    private static func application(in notification: Notification) -> NSRunningApplication? {
        notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
    }
}

/// 前面になったアプリをどう扱うか
enum FrontmostAppFilter {
    struct Own: Equatable {
        var bundleID: String?
        var processID: Int32
    }

    /// Nonet 自身（同じ bundleID の別のプロセスも含む）
    static func isOwn(bundleID: String?, processID: Int32, own: Own) -> Bool {
        if processID == own.processID { return true }
        if let bundleID, let ownBundleID = own.bundleID, bundleID == ownBundleID { return true }
        return false
    }

    /// NSApplication.keyWindow の様子から、送ったキーが Nonet のウィンドウに届くか。キーのウィンドウが無い（nil）・
    /// 閉じた・隠れたウィンドウには届かない。Nonet が前面のアプリかどうかでは決めない（ウィンドウを閉じた後も前面に残るため）
    static func receivesKeys(keyWindowIsKey: Bool?, isVisible: Bool?) -> Bool {
        keyWindowIsKey == true && isVisible == true
    }

    enum Decision: Equatable {
        /// Nonet 自身。今の値を変えない
        case ignore
        /// bundleID の無いアプリは nil（グローバルのプロファイルを使う）
        case update(RunningAppInfo?)
    }

    static func decide(bundleID: String?, name: String?, processID: Int32, own: Own) -> Decision {
        if isOwn(bundleID: bundleID, processID: processID, own: own) { return .ignore }
        guard let bundleID, !bundleID.isEmpty else { return .update(nil) }
        let displayName = name.flatMap { $0.isEmpty ? nil : $0 } ?? bundleID
        return .update(RunningAppInfo(app: AppReference(bundleID: bundleID, name: displayName), processID: processID))
    }
}

/// メインキューで動くタイマー。now は起動からの単調増加の秒
@MainActor
public final class MainRunLoopScheduler: Scheduler {
    /// これより先の予定は丸める（DispatchTime のあふれを避ける）
    static let maximumDelay: TimeInterval = 365 * 24 * 60 * 60

    public init() {}

    public var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    @discardableResult
    public func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> any ScheduledTask {
        let task = MainQueueTask(action: action)
        // メインキューはメニューを開いている間（イベントトラッキング中）も動く
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.clampedDelay(delay)) {
            MainActor.assumeIsolated { task.fire() }
        }
        return task
    }

    /// 負の値と NaN は 0
    static func clampedDelay(_ delay: TimeInterval) -> TimeInterval {
        guard !delay.isNaN else { return 0 }
        return min(max(delay, 0), maximumDelay)
    }
}

@MainActor
final class MainQueueTask: ScheduledTask {
    private var action: (@MainActor () -> Void)?

    init(action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    var isPending: Bool { action != nil }

    func cancel() {
        action = nil
    }

    func fire() {
        guard let action else { return }
        // 先に外しておく（action の中で cancel されても、2回呼ばれることもない）
        self.action = nil
        action()
    }
}
