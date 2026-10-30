// 担当: ui-shell（統合担当が書いた組み立て。必要に応じて手を入れてよい）
import AppKit
import NonetCore
import NonetPlatform
import NonetUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let options: ShellLaunchOptions
    private var services: NonetServices?
    private var controller: NonetController?
    private var license: LicenseManager?
    private var hud: HUDWindowController?
    private var menuBar: MenuBarController?
    private var settingsWindow: SettingsWindowController?
    private var onboardingWindow: OnboardingWindowController?
    private var licenseRefreshObservers: [(NotificationCenter, NSObjectProtocol)] = []
    /// 試用期間が終わったときの小さなウィンドウ
    private var trialEndedWindow: TrialEndedWindowController?
    /// 起動の途中に届いた nonet://register と .nonetlicense（設定のウィンドウができてから開く）
    private var pendingLicenseLinks: [URL] = []
    private let updater = UpdaterController()
    #if DEBUG
    private var preview: DebugPreview?
    #endif

    init(options: ShellLaunchOptions) {
        self.options = options
        super.init()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // 画面には出ないが、設定や案内のウィンドウで ⌘C・⌘V・⌘Z・⌘W などを使えるようにする
        NSApplication.shared.mainMenu = ShellMainMenu.make(
            onAbout: { [weak self] in self?.showSettings(tab: .about) },
            onOpenSettings: { [weak self] in self?.showSettings(tab: .general) }
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // ディスクイメージなどから開かれたら、アプリケーションフォルダに移して開き直す
        if ShellMoveToApplications.offerIfNeeded() {
            NSApplication.shared.terminate(nil)
            return
        }
        let services = NonetServices.live()
        let hud = HUDWindowController()
        let license = makeLicenseManager()
        let controller = NonetController(
            services: services,
            store: ConfigurationStore(directory: configurationDirectory),
            hud: hud,
            license: license
        )
        self.services = services
        self.hud = hud
        self.license = license
        self.controller = controller

        let checkForUpdates: (() -> Void)? = updater.isAvailable ? { [weak self] in self?.updater.checkForUpdates() } : nil
        let menuBar = MenuBarController(
            controller: controller,
            license: license,
            onOpenSettings: { [weak self] tab in self?.showSettings(tab: tab) },
            onOpenOnboarding: { [weak self] in self?.showOnboarding() },
            onCheckForUpdates: checkForUpdates
        )
        menuBar.onRequestAccessibility = { [weak self] in
            guard let permissions = self?.services?.permissions else { return }
            permissions.requestAccessibility()
            permissions.openAccessibilitySettings()
        }
        updater.onUpdateAvailableChange = { [weak menuBar] available in menuBar?.isUpdateAvailable = available }
        self.menuBar = menuBar
        settingsWindow = SettingsWindowController(
            controller: controller,
            license: license,
            services: services,
            // 利用ガイドとプライバシーポリシーは、画面が英語なら英語のページ（サイトの en/ の下）を開く
            links: AppLinks(purchase: AppInfo.purchaseURL, support: AppInfo.supportURL, privacy: AppInfo.privacyURL)
                .localized(language: Bundle.main.preferredLocalizations.first),
            onCheckForUpdates: checkForUpdates
        )

        setUpLicenseSupport(license: license)
        observeLicenseRefreshTriggers()
        controller.start()
        if controller.isFirstLaunch {
            showOnboarding()
        }
        #if DEBUG
        applyDebugOptions()
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        for (center, observer) in licenseRefreshObservers {
            center.removeObserver(observer)
        }
        licenseRefreshObservers = []
        controller?.stop()
    }

    /// 購入のメールの nonet://register?key=… と、.nonetlicense のファイル。設定のライセンスのタブで、登録してよいか尋ねる
    func application(_ application: NSApplication, open urls: [URL]) {
        pendingLicenseLinks += urls
        openPendingLicenseLinks()
    }

    /// アプリをもう一度開いたら設定を開く
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings(tab: .profiles)
        return false
    }

    private var configurationDirectory: URL {
        #if DEBUG
        if let directory = options.configDirectory {
            return directory
        }
        #endif
        return ConfigurationStore.defaultDirectory
    }

    private func makeLicenseManager() -> LicenseManager {
        let verifier = AppInfo.licensePublicKey.flatMap { try? LicenseVerifier(publicKeyBase64: $0) }
        #if DEBUG
        if options.simulateExpiredTrial {
            return DebugPreview.expiredTrialLicense(verifier: verifier)
        }
        // 設定の置き場所を分けたときは、試用の記録も本物（UserDefaults）に書かない
        if options.configDirectory != nil {
            return DebugPreview.temporaryLicense(verifier: verifier)
        }
        #endif
        // 試用の記録はキーチェーンにも置く（Developer ID で署名したビルドでだけ働く。docs/privacy.md）
        return LicenseManager(verifier: verifier, storage: UserDefaultsLicenseStorage(keychain: SystemTrialRecordKeychain()))
    }

    /// お問い合わせの宛先、試用期間が終わったときのウィンドウ、起動の途中に届いたライセンスのリンク
    private func setUpLicenseSupport(license: LicenseManager) {
        settingsWindow?.supportEmail = AppInfo.supportEmail
        var defaults: UserDefaults? = .standard
        #if DEBUG
        // 設定の置き場所を分けたとき・期限切れを試すときは、ウィンドウを出した日を本物（UserDefaults）に書かない
        if options.configDirectory != nil || options.simulateExpiredTrial {
            defaults = nil
        }
        #endif
        let window = TrialEndedWindowController(license: license, purchaseURL: AppInfo.purchaseURL, defaults: defaults) { [weak self] in
            self?.settingsWindow?.showLicenseKeyEntry()
        }
        trialEndedWindow = window
        window.start()
        openPendingLicenseLinks()
    }

    private func openPendingLicenseLinks() {
        guard let settingsWindow else { return }
        let urls = pendingLicenseLinks
        pendingLicenseLinks = []
        for url in urls {
            settingsWindow.openLicenseLink(url)
        }
    }

    /// 試用の残り日数の表示は refresh() でしか変わらないので、日付や時計が変わりうるときに呼ぶ
    private func observeLicenseRefreshTriggers() {
        let refresh: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.license?.refresh() }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        let center = NotificationCenter.default
        licenseRefreshObservers = [
            (workspace, workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: refresh)),
            (center, center.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main, using: refresh)),
            (center, center.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main, using: refresh)),
        ]
    }

    private func showSettings(tab: SettingsTab) {
        settingsWindow?.show(tab: tab)
    }

    private func showOnboarding() {
        if let onboardingWindow {
            onboardingWindow.show()
            return
        }
        guard let controller, let services else { return }
        let window = OnboardingWindowController(controller: controller, services: services, license: license) { [weak self] in
            self?.onboardingWindow = nil
        }
        window.onOpenSettings = { [weak self] tab in self?.showSettings(tab: tab) }
        onboardingWindow = window
        window.show()
    }

    #if DEBUG
    /// 見た目の確認用の起動引数（一覧は App/DebugPreview.swift）
    private func applyDebugOptions() {
        guard let controller, let hud, let license, let services else { return }
        if let tab = options.settingsTab {
            showSettings(tab: tab)
        }
        if options.showOnboarding {
            showOnboarding()
        }
        let preview = DebugPreview(controller: controller, hud: hud, license: license, services: services)
        if options.previewHUD {
            preview.showHUD()
        }
        if options.previewToast {
            preview.startToasts()
        }
        if options.previewResult {
            preview.showResult()
        }
        if let directory = options.snapshotDirectory {
            preview.snapshotWindowsAndQuit(to: directory)
        }
        self.preview = preview
    }
    #endif
}
