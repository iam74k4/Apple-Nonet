// 担当: ui-settings
// 設定画面のテストで使う偽物のサービスと、NonetController を組み立てる道具
import AppKit
import Foundation
import NonetCore
@testable import NonetUI

@MainActor
final class SettingsFakeTouchSource: TouchSource {
    var isAvailable = true
    var onFrame: ((TouchFrame) -> Void)?
    func start() throws {}
    func stop() {}
}

@MainActor
final class SettingsFakeKeyboard: KeyboardMonitor {
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
final class SettingsFakeHaptics: HapticPlayer {
    func play(_ event: HapticEvent, strength: HapticStrength) {}
}

@MainActor
final class SettingsFakePerformer: ActionPerforming {
    private(set) var performed: [Action] = []
    var error: NonetError?

    func perform(_ action: Action, context: ActionContext) async throws {
        performed.append(action)
        if let error { throw error }
    }
}

@MainActor
final class SettingsFakeFrontmost: FrontmostAppObserving {
    var current: RunningAppInfo?
    var onChange: ((RunningAppInfo?) -> Void)?
    func start() {}
    func stop() {}
}

@MainActor
final class SettingsFakeMenus: MenuReading {
    var apps: [RunningAppInfo] = []
    var items: [MenuItemNode] = []
    /// アプリごとの中身（無ければ items）
    var itemsByProcess: [Int32: [MenuItemNode]] = [:]
    /// アプリごとの読み込みにかかる時間
    var delayByProcess: [Int32: Duration] = [:]
    var error: NonetError?
    private(set) var requested: [RunningAppInfo] = []

    func runningApps() -> [RunningAppInfo] { apps }

    func menuItems(for app: RunningAppInfo) async throws -> [MenuItemNode] {
        requested.append(app)
        if let delay = delayByProcess[app.processID] {
            try? await Task.sleep(for: delay)
        }
        if let error { throw error }
        return itemsByProcess[app.processID] ?? items
    }
}

@MainActor
final class SettingsFakePermissions: PermissionsProviding {
    var isAccessibilityGranted = true
    var isSecureInputActive = false
    private(set) var requestCount = 0
    private(set) var openCount = 0
    func requestAccessibility() { requestCount += 1 }
    func openAccessibilitySettings() { openCount += 1 }
}

@MainActor
final class SettingsFakeInstalledApps: InstalledAppsProviding {
    var apps: [AppReference] = []
    private(set) var listCount = 0

    func installedApps() -> [AppReference] {
        listCount += 1
        return apps
    }

    func isInstalled(bundleID: String) -> Bool {
        apps.contains { $0.bundleID.caseInsensitiveCompare(bundleID) == .orderedSame }
    }
}

@MainActor
final class SettingsFakeShortcuts: ShortcutsProviding {
    var names: [String] = []
    private(set) var loadCount = 0
    func shortcutNames() async -> [String] {
        loadCount += 1
        return names
    }
}

@MainActor
final class SettingsFakeAI: AIAvailabilityProviding {
    var unavailableReason: String?
}

struct SettingsFakeLoginError: LocalizedError {
    var errorDescription: String? { "承認されていません" }
}

@MainActor
final class SettingsFakeLoginItem: LoginItemControlling {
    var isEnabled = false
    var failure: (any Error)?
    func setEnabled(_ enabled: Bool) throws {
        if let failure { throw failure }
        isEnabled = enabled
    }
}

@MainActor
final class SettingsFakeTask: ScheduledTask {
    func cancel() {}
}

@MainActor
final class SettingsFakeScheduler: Scheduler {
    var now: TimeInterval = 0
    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> any ScheduledTask {
        SettingsFakeTask()
    }
}

@MainActor
final class SettingsFakeHUD: HUDPresenting {
    func show(_ model: HUDModel, position: HUDPosition) {}
    func update(_ model: HUDModel) {}
    func hide() {}
    func showToast(_ toast: ToastModel) {}
    func showResult(_ result: ResultModel) {}
}

final class SettingsFakeLicenseStorage: LicenseStorage {
    var trialStartDate: Date?
    var licenseKey: String?
    var trialLastSeenDate: Date?
    var trialUsedTime: TimeInterval?
}

@MainActor
final class SettingsFakeFiles: SettingsFileChoosing {
    var exportURL: URL?
    var importURL: URL?
    var applicationURL: URL?
    private(set) var suggestedNames: [String] = []

    func chooseExportDestination(suggestedName: String) async -> URL? {
        suggestedNames.append(suggestedName)
        return exportURL
    }

    func chooseImportSource() async -> URL? { importURL }
    func chooseApplication() async -> URL? { applicationURL }
}

enum SettingsFixtures {
    static let xcode = AppReference(bundleID: "com.apple.dt.Xcode", name: "Xcode")
    static let safari = AppReference(bundleID: "com.apple.Safari", name: "Safari")
    static let figma = AppReference(bundleID: "com.figma.Desktop", name: "Figma")
    static let notes = AppReference(bundleID: "com.apple.Notes", name: "メモ")
    static let terminal = AppReference(bundleID: "com.apple.Terminal", name: "ターミナル")

    static func launch(_ app: AppReference) -> Cell {
        Cell(title: app.name, icon: .app(bundleID: app.bundleID), action: .launchApp(LaunchAppAction(app: app)))
    }

    static func key(_ title: String, _ keys: KeySequence) -> Cell {
        Cell(title: title, icon: .symbol("keyboard"), action: .keystroke(keys))
    }

    /// グローバル（2マス）・Xcode（プリセット）・Safari（空・無効）
    static func configuration() -> NonetConfiguration {
        let global = Profile(kind: .global, pages: [Page(cells: [launch(safari), nil, launch(terminal)])])
        var configuration = NonetConfiguration(profiles: [global])
        configuration.addAppProfile(for: xcode, preset: PresetLibrary.preset(forBundleID: xcode.bundleID))
        let safariID = configuration.addAppProfile(for: safari, preset: nil)
        configuration.updateProfile(id: safariID) { $0.isEnabled = false }
        return configuration.validated()
    }
}

/// 偽物のサービスと一時フォルダの ConfigurationStore で組み立てた NonetController と SettingsModel
@MainActor
final class SettingsHarness {
    let directory: URL
    let store: ConfigurationStore
    let touch = SettingsFakeTouchSource()
    let keyboard = SettingsFakeKeyboard()
    let performer = SettingsFakePerformer()
    let frontmost = SettingsFakeFrontmost()
    let menus = SettingsFakeMenus()
    let permissions = SettingsFakePermissions()
    let installed = SettingsFakeInstalledApps()
    let shortcuts = SettingsFakeShortcuts()
    let ai = SettingsFakeAI()
    let loginItem = SettingsFakeLoginItem()
    let licenseStorage = SettingsFakeLicenseStorage()
    let files = SettingsFakeFiles()
    let services: NonetServices
    let license: LicenseManager
    let controller: NonetController
    let model: SettingsModel
    private(set) var openedURLs: [URL] = []

    init(
        configuration: NonetConfiguration? = SettingsFixtures.configuration(),
        isJISKeyboard: Bool = false,
        verifier: LicenseVerifier? = nil,
        links: AppLinks = AppLinks()
    ) throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "NonetSettingsTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = ConfigurationStore(directory: directory)
        installed.apps = [SettingsFixtures.figma, SettingsFixtures.notes, SettingsFixtures.safari, SettingsFixtures.xcode]
        services = NonetServices(
            touchSource: touch,
            keyboard: keyboard,
            haptics: SettingsFakeHaptics(),
            performer: performer,
            frontmostApp: frontmost,
            menus: menus,
            permissions: permissions,
            installedApps: installed,
            shortcuts: shortcuts,
            ai: ai,
            loginItem: loginItem,
            scheduler: SettingsFakeScheduler(),
            isJISKeyboard: isJISKeyboard
        )
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        license = LicenseManager(verifier: verifier, storage: licenseStorage, now: { start })
        controller = NonetController(services: services, store: store, hud: SettingsFakeHUD(), license: license)
        controller.start()
        if let configuration {
            controller.replaceConfiguration(configuration)
        }
        model = SettingsModel(controller: controller, license: license, services: services, links: links, onCheckForUpdates: nil)
        model.files = files
        model.openURL = { [weak self] url in self?.openedURLs.append(url) }
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    var xcodeProfile: Profile? {
        controller.configuration.profiles.first { $0.app?.bundleID == SettingsFixtures.xcode.bundleID }
    }

    var safariProfile: Profile? {
        controller.configuration.profiles.first { $0.app?.bundleID == SettingsFixtures.safari.bundleID }
    }

    /// 保存されたファイルから読み直した設定
    func saved() throws -> NonetConfiguration? {
        try store.load()
    }

    func temporaryFile(_ name: String) -> URL {
        directory.appending(path: name, directoryHint: .notDirectory)
    }
}
