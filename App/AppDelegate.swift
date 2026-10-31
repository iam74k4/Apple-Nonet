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
    /// 購入ページ・利用ガイド・プライバシーポリシー。利用ガイドとプライバシーポリシーは、画面が英語なら英語のページ（サイトの en/ の下）
    private let links = AppLinks(purchase: AppInfo.purchaseURL, support: AppInfo.supportURL, privacy: AppInfo.privacyURL)
        .localized(language: Bundle.main.preferredLocalizations.first)
    #if DEBUG
    private var preview: DebugPreview?
    #endif

    init(options: ShellLaunchOptions) {
        self.options = options
        super.init()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // 画面には出ないが、設定や案内のウィンドウで ⌘C・⌘V・⌘Z・⌘W などを使えるようにする
        // ⌘? の「Nonet ヘルプ」は利用ガイドを開く
        let guide = links.support
        NSApplication.shared.mainMenu = ShellMainMenu.make(
            onAbout: { [weak self] in self?.showSettings(tab: .about) },
            onOpenSettings: { [weak self] in self?.showSettings(tab: .general) },
            onHelp: guide.map { url in { _ = NSWorkspace.shared.open(url) } }
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // ディスクイメージなどから開かれたら、アプリケーションフォルダに移して開き直す
        if ShellMoveToApplications.offerIfNeeded() {
            NSApplication.shared.terminate(nil)
            return
        }
        // 起動できたなら、ほかの Nonet はもう動いていない。前のプロセスが残した終わりかけの印を消す
        ShellQuitMarker.removeAll()
        let services = NonetServices.live()
        let hud = HUDWindowController()
        let license = makeLicenseManager()
        let controller = NonetController(
            services: services,
            store: ConfigurationStore(directory: configurationDirectory),
            hud: hud,
            license: license,
            guidance: makeGuidanceStore()
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
        // 許可の手順と「システム設定を開く」（macOS の確認とシステム設定を同時に出さない）は案内の最初の画面にあるので、そこを開く
        menuBar.onRequestAccessibility = { [weak self] in
            self?.showOnboarding(purpose: .permission(remindsAtLaunch: false))
        }
        menuBar.onEditButtons = { [weak self] app in self?.settingsWindow?.showButtons(for: app) }
        menuBar.onShowRun = { [weak self] record in self?.settingsWindow?.showRun(record) }
        menuBar.onShowCell = { [weak self] profileID, address in self?.settingsWindow?.showCell(profileID: profileID, address: address) }
        let frontmost = services.frontmostApp
        menuBar.frontmostApp = { frontmost.current?.app }
        menuBar.links = links
        updater.onUpdateAvailableChange = { [weak menuBar] available in menuBar?.isUpdateAvailable = available }
        self.menuBar = menuBar
        settingsWindow = SettingsWindowController(
            controller: controller,
            license: license,
            services: services,
            links: links,
            onCheckForUpdates: checkForUpdates
        )

        setUpLicenseSupport(license: license)
        observeLicenseRefreshTriggers()
        controller.start()
        // 初回起動なら案内を開く。許可しないまま終えていたら、起動のたびに許可の画面で開き直す（「今後表示しない」まで）
        switch OnboardingLaunchGuide.decide(
            isFirstLaunch: controller.isFirstLaunch,
            isEnabled: controller.configuration.settings.isEnabled,
            isAccessibilityGranted: services.permissions.isAccessibilityGranted,
            isReminderHidden: reminderPreference.isHidden
        ) {
        case .firstRun:
            showOnboarding()
        case .permissionReminder:
            showOnboarding(purpose: .permission(remindsAtLaunch: true))
        case .none:
            break
        }
        #if DEBUG
        applyDebugOptions()
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 終わりきる前にもう一度開かれたら、そちらはこれが終わるのを待ってから起動する（印が無ければ、すぐにこちらへ任せる）
        ShellQuitMarker.mark(processID: ProcessInfo.processInfo.processIdentifier)
        for (center, observer) in licenseRefreshObservers {
            center.removeObserver(observer)
        }
        licenseRefreshObservers = []
        // 設定画面の打ちかけ（少し止まってから確定する欄）と記録中のキーを先に確定させ、stop() で一緒に書く
        settingsWindow?.commitPendingEdits()
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

    /// 「今後表示しない」の置き場所。設定の置き場所を分けたとき（DEBUG）は UserDefaults に書かない
    private lazy var reminderPreference: OnboardingReminderPreference = {
        #if DEBUG
        if options.configDirectory != nil {
            return OnboardingReminderPreference(defaults: nil)
        }
        #endif
        return OnboardingReminderPreference(defaults: .standard)
    }()

    /// 使い始めの HUD の案内の回数と、試用期間の知らせの日付。設定の置き場所を分けたときは本物（UserDefaults）に書かない
    private func makeGuidanceStore() -> any HUDGuidanceStoring {
        #if DEBUG
        if options.configDirectory != nil || options.simulateExpiredTrial {
            return MemoryHUDGuidanceStore()
        }
        #endif
        return UserDefaultsHUDGuidanceStore()
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
        // 試用の記録はキーチェーンにも置く（Developer ID で署名したビルドでだけ働く。docs/privacy.md）。
        // 記録をすべて消されても、2つ目の項目（marker）と以前に使った跡（Backups・Caches のフォルダ）で、試用をやり直させない
        return LicenseManager(verifier: verifier, storage: UserDefaultsLicenseStorage(
            keychain: SystemTrialRecordKeychain(),
            marker: SystemTrialRecordKeychain.machineMarker(),
            evidence: FileTrialUsageEvidence.standard()
        ))
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

    private func showOnboarding(purpose: OnboardingPurpose = .guide) {
        if let onboardingWindow {
            onboardingWindow.show()
            return
        }
        guard let controller, let services else { return }
        let window = OnboardingWindowController(controller: controller, services: services, license: license) { [weak self] in
            self?.onboardingWindow = nil
        }
        window.purpose = purpose
        window.reminderPreference = reminderPreference
        window.onOpenSettings = { [weak self] tab in self?.showSettings(tab: tab) }
        window.isStatusItemVisible = { [weak self] in self?.menuBar?.isStatusItemVisible ?? true }
        // 「完了」で閉じたら、メニューバーのどこに Nonet がいるかを見せる
        window.onComplete = { [weak self] in self?.menuBar?.pointAtStatusItem() }
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
            if let step = options.onboardingStep {
                // メニューバーのアイコンが並び終えてから進める（完了の画面は、アイコンが見えているかを確かめる）
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    MainActor.assumeIsolated { self?.onboardingWindow?.previewStep(step) }
                }
            }
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
