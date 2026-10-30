// 担当: ui-shell。NonetController をテストで動かすための偽のサービス（キーもアプリも本物には触れない）
import Foundation
import NonetCore
@testable import NonetUI

@MainActor
final class ShellFakeTouchSource: TouchSource {
    var isAvailable = true
    var onFrame: ((TouchFrame) -> Void)?
    func start() throws {}
    func stop() {}
}

@MainActor
final class ShellFakeKeyboard: KeyboardMonitor {
    var trigger: TriggerKey = .rightCommand
    var passTriggerToApps = true
    var cursorLock: CursorLockMethod = .automatic
    var isSuppressingPointer = false
    var onEvent: ((KeyboardEvent) -> Void)?
    private(set) var isRunning = false
    func start() throws { isRunning = true }
    func stop() { isRunning = false }
}

@MainActor
final class ShellFakeHaptics: HapticPlayer {
    func play(_ event: HapticEvent, strength: HapticStrength) {}
}

@MainActor
final class ShellFakePerformer: ActionPerforming {
    private(set) var performed: [Action] = []
    func perform(_ action: Action, context: ActionContext) async throws {
        performed.append(action)
    }
}

@MainActor
final class ShellFakeFrontmost: FrontmostAppObserving {
    var current: RunningAppInfo?
    var onChange: ((RunningAppInfo?) -> Void)?
    func start() {}
    func stop() {}
}

@MainActor
final class ShellFakeMenus: MenuReading {
    func runningApps() -> [RunningAppInfo] { [] }
    func menuItems(for app: RunningAppInfo) async throws -> [MenuItemNode] { [] }
}

@MainActor
final class ShellFakePermissions: PermissionsProviding {
    var isAccessibilityGranted: Bool
    var isSecureInputActive = false
    private(set) var requestCount = 0
    private(set) var openSettingsCount = 0

    init(granted: Bool) {
        isAccessibilityGranted = granted
    }

    func requestAccessibility() { requestCount += 1 }
    func openAccessibilitySettings() { openSettingsCount += 1 }
}

@MainActor
final class ShellFakeInstalledApps: InstalledAppsProviding {
    var bundleIDs: Set<String>

    init(_ bundleIDs: Set<String>) {
        self.bundleIDs = bundleIDs
    }

    func installedApps() -> [AppReference] {
        bundleIDs.sorted().map { AppReference(bundleID: $0, name: $0) }
    }

    func isInstalled(bundleID: String) -> Bool {
        bundleIDs.contains(bundleID)
    }
}

@MainActor
final class ShellFakeShortcuts: ShortcutsProviding {
    func shortcutNames() async -> [String] { [] }
}

@MainActor
final class ShellFakeAI: AIAvailabilityProviding {
    var unavailableReason: String?
}

@MainActor
final class ShellFakeLoginItem: LoginItemControlling {
    var isEnabled = false
    /// 投げるエラー（システム設定での許可待ちなど）
    var failure: (any Error)?
    private(set) var setCount = 0

    func setEnabled(_ enabled: Bool) throws {
        setCount += 1
        if let failure { throw failure }
        isEnabled = enabled
    }
}

@MainActor
final class ShellFakeTask: ScheduledTask {
    let deadline: TimeInterval
    let action: @MainActor () -> Void
    private(set) var isCancelled = false

    init(deadline: TimeInterval, action: @escaping @MainActor () -> Void) {
        self.deadline = deadline
        self.action = action
    }

    func cancel() { isCancelled = true }
}

/// 時間は advance(by:) で進めたときだけ進む（セッションのタイマーは動かさない）
@MainActor
final class ShellFakeScheduler: Scheduler {
    var now: TimeInterval = 1000
    private var tasks: [ShellFakeTask] = []

    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> any ScheduledTask {
        let task = ShellFakeTask(deadline: now + delay, action: action)
        tasks.append(task)
        return task
    }

    /// 時計を進め、期限が来たものを期限の順に動かす
    func advance(by interval: TimeInterval) {
        let end = now + interval
        while let next = tasks.filter({ !$0.isCancelled && $0.deadline <= end }).min(by: { $0.deadline < $1.deadline }) {
            tasks.removeAll { $0 === next }
            now = max(now, next.deadline)
            next.action()
        }
        tasks.removeAll(where: \.isCancelled)
        now = end
    }
}

@MainActor
final class ShellFakeHUD: HUDPresenting {
    private(set) var shown: [HUDModel] = []
    private(set) var toasts: [ToastModel] = []
    func show(_ model: HUDModel, position: HUDPosition) { shown.append(model) }
    func update(_ model: HUDModel) {}
    func hide() {}
    func showToast(_ toast: ToastModel) { toasts.append(toast) }
    func showResult(_ result: ResultModel) {}
}

final class ShellFakeLicenseStorage: LicenseStorage {
    var trialStartDate: Date?
    var licenseKey: String?
    var trialLastSeenDate: Date?
    var trialUsedTime: TimeInterval?

    init(trialStartDate: Date? = nil) {
        self.trialStartDate = trialStartDate
    }
}

/// 偽のサービスで作った NonetController。設定は一時フォルダに保存する
@MainActor
final class ShellControllerHarness {
    nonisolated static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    let controller: NonetController
    let services: NonetServices
    let permissions: ShellFakePermissions
    let touchSource = ShellFakeTouchSource()
    let frontmost = ShellFakeFrontmost()
    let loginItem = ShellFakeLoginItem()
    let installedApps: ShellFakeInstalledApps
    let license: LicenseManager
    let scheduler = ShellFakeScheduler()
    let directory: URL

    /// license を渡さなければ、試用の初日（残り14日）
    init(installed: Set<String> = [], accessibilityGranted: Bool = true, isJIS: Bool = true, license: LicenseManager? = nil) {
        permissions = ShellFakePermissions(granted: accessibilityGranted)
        installedApps = ShellFakeInstalledApps(installed)
        services = NonetServices(
            touchSource: touchSource,
            keyboard: ShellFakeKeyboard(),
            haptics: ShellFakeHaptics(),
            performer: ShellFakePerformer(),
            frontmostApp: frontmost,
            menus: ShellFakeMenus(),
            permissions: permissions,
            installedApps: installedApps,
            shortcuts: ShellFakeShortcuts(),
            ai: ShellFakeAI(),
            loginItem: loginItem,
            scheduler: scheduler,
            isJISKeyboard: isJIS
        )
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("nonet-shell-tests-\(UUID().uuidString)", isDirectory: true)
        let now = Self.now
        self.license = license ?? LicenseManager(verifier: nil, storage: ShellFakeLicenseStorage(), now: { now })
        controller = NonetController(
            services: services,
            store: ConfigurationStore(directory: directory),
            hud: ShellFakeHUD(),
            license: self.license
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    /// コントローラーがまとめて書く保存を、保存の間隔（0.5 秒）だけ時計を進めて書かせる
    func flushSaves() {
        scheduler.advance(by: 0.5)
    }
}

enum ShellFixtures {
    /// fastTap が false なら、HUD を出してから実行した（HUD のマスをタップしたときも）
    static func record(index: Int, page: Int = 0, date: Date, title: String = "マス", fastTap: Bool = true, profile: String = "Xcode") -> ExecutionRecord {
        ExecutionRecord(
            cellTitle: title,
            profileName: profile,
            address: CellAddress(page: page, index: index),
            succeeded: true,
            message: nil,
            wasFastTap: fastTap,
            date: date
        )
    }

    static func running(_ bundleID: String, name: String) -> RunningAppInfo {
        RunningAppInfo(app: AppReference(bundleID: bundleID, name: name), processID: 4242)
    }

    static let xcode = "com.apple.dt.Xcode"
    static let safari = "com.apple.Safari"
    static let finder = "com.apple.finder"
}
