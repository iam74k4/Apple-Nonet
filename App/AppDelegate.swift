// 担当: ui-shell（統合担当が書いた組み立て。必要に応じて手を入れてよい）
import AppKit
import NonetCore
import NonetPlatform
import NonetUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var services: NonetServices?
    private var controller: NonetController?
    private var license: LicenseManager?
    private var hud: HUDWindowController?
    private var menuBar: MenuBarController?
    private var settingsWindow: SettingsWindowController?
    private var onboardingWindow: OnboardingWindowController?
    private let updater = UpdaterController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let services = NonetServices.live()
        let hud = HUDWindowController()
        let verifier = AppInfo.licensePublicKey.flatMap { try? LicenseVerifier(publicKeyBase64: $0) }
        let license = LicenseManager(verifier: verifier, storage: UserDefaultsLicenseStorage())
        let controller = NonetController(
            services: services,
            store: ConfigurationStore(directory: ConfigurationStore.defaultDirectory),
            hud: hud,
            license: license
        )
        self.services = services
        self.hud = hud
        self.license = license
        self.controller = controller

        let checkForUpdates: (() -> Void)? = updater.isAvailable ? { [weak self] in self?.updater.checkForUpdates() } : nil
        menuBar = MenuBarController(
            controller: controller,
            license: license,
            onOpenSettings: { [weak self] tab in self?.showSettings(tab: tab) },
            onOpenOnboarding: { [weak self] in self?.showOnboarding() },
            onCheckForUpdates: checkForUpdates
        )
        settingsWindow = SettingsWindowController(
            controller: controller,
            license: license,
            services: services,
            links: AppLinks(purchase: AppInfo.purchaseURL, support: AppInfo.supportURL, privacy: AppInfo.privacyURL),
            onCheckForUpdates: checkForUpdates
        )

        controller.start()
        if controller.isFirstLaunch {
            showOnboarding()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.stop()
    }

    /// Dock やアプリの再オープンで設定を開く
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings(tab: .profiles)
        return false
    }

    private func showSettings(tab: SettingsTab) {
        settingsWindow?.show(tab: tab)
    }

    private func showOnboarding() {
        guard let controller, let services else { return }
        let window = OnboardingWindowController(controller: controller, services: services) { [weak self] in
            self?.onboardingWindow = nil
        }
        onboardingWindow = window
        window.show()
    }
}
