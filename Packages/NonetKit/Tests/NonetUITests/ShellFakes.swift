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
    func setEnabled(_ enabled: Bool) throws { isEnabled = enabled }
}

@MainActor
final class ShellFakeTask: ScheduledTask {
    private(set) var isCancelled = false
    func cancel() { isCancelled = true }
}

/// 時間は進まない（セッションのタイマーは動かさない）
@MainActor
final class ShellFakeScheduler: Scheduler {
    var now: TimeInterval = 1000
    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> any ScheduledTask {
        ShellFakeTask()
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
    let installedApps: ShellFakeInstalledApps
    let license: LicenseManager
    let directory: URL

    init(installed: Set<String> = [], accessibilityGranted: Bool = true, isJIS: Bool = true) {
        permissions = ShellFakePermissions(granted: accessibilityGranted)
        installedApps = ShellFakeInstalledApps(installed)
        services = NonetServices(
            touchSource: ShellFakeTouchSource(),
            keyboard: ShellFakeKeyboard(),
            haptics: ShellFakeHaptics(),
            performer: ShellFakePerformer(),
            frontmostApp: ShellFakeFrontmost(),
            menus: ShellFakeMenus(),
            permissions: permissions,
            installedApps: installedApps,
            shortcuts: ShellFakeShortcuts(),
            ai: ShellFakeAI(),
            loginItem: ShellFakeLoginItem(),
            scheduler: ShellFakeScheduler(),
            isJISKeyboard: isJIS
        )
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("nonet-shell-tests-\(UUID().uuidString)", isDirectory: true)
        let now = Self.now
        license = LicenseManager(verifier: nil, storage: ShellFakeLicenseStorage(), now: { now })
        controller = NonetController(
            services: services,
            store: ConfigurationStore(directory: directory),
            hud: ShellFakeHUD(),
            license: license
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }
}

enum ShellFixtures {
    static func record(index: Int, page: Int = 0, date: Date, title: String = "マス") -> ExecutionRecord {
        ExecutionRecord(
            cellTitle: title,
            profileName: "Xcode",
            address: CellAddress(page: page, index: index),
            succeeded: true,
            message: nil,
            wasFastTap: true,
            date: date
        )
    }

    static let xcode = "com.apple.dt.Xcode"
    static let safari = "com.apple.Safari"
    static let finder = "com.apple.finder"
}
