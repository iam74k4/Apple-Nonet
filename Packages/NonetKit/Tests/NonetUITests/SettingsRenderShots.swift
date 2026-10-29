// 担当: ui-settings
// 見た目の確認用に、画面を PNG に描き出す。NONET_RENDER_SHOTS=<フォルダ> のときだけ動く
//   NONET_RENDER_SHOTS=/tmp/nonet-ui-settings-shots swift test --filter SettingsRenderShots
import AppKit
import NonetCore
@testable import NonetUI
import SwiftUI
import Testing

private let shotsDirectory = ProcessInfo.processInfo.environment["NONET_RENDER_SHOTS"]

@Suite(.enabled(if: shotsDirectory != nil), .serialized)
@MainActor
struct SettingsRenderShots {
    private let appearances: [(String, NSAppearance.Name)] = [("light", .aqua), ("dark", .darkAqua)]

    private var directory: URL {
        URL(fileURLWithPath: shotsDirectory ?? NSTemporaryDirectory(), isDirectory: true)
    }

    /// 長い名前や空きマスを含む、見本の設定
    private static func sampleConfiguration() -> NonetConfiguration {
        var configuration = SettingsFixtures.configuration()
        let longApp = AppReference(bundleID: "com.example.long", name: "とても長い名前のアプリケーション プロフェッショナル版")
        let longID = configuration.addAppProfile(for: longApp, preset: nil)
        configuration.setCell(Cell(
            title: "選択範囲をフレームで囲んで自動レイアウトを追加する",
            icon: .symbol("rectangle.3.group"),
            action: .keystroke(.sequence(.key("g", [.option, .command]), .key("a", .shift), .key("k", [.option, .command])))
        ), at: CellAddress(page: 0, index: 0), profileID: longID)
        configuration.setCell(Cell(title: "", icon: .symbol("link"), action: .openURL(URLAction(url: "exa mple"))),
                              at: CellAddress(page: 0, index: 4), profileID: longID)
        configuration.setCell(Cell(title: "要約", icon: .text("要"), action: .ai(AIAction(prompt: "3行で要約して", output: .showResult))),
                              at: CellAddress(page: 0, index: 8), profileID: longID)
        configuration.addAppProfile(for: SettingsFixtures.figma, preset: PresetLibrary.preset(forBundleID: SettingsFixtures.figma.bundleID))
        return configuration.validated()
    }

    private func harness() throws -> SettingsHarness {
        _ = NSApplication.shared
        let h = try SettingsHarness(
            configuration: Self.sampleConfiguration(),
            isJISKeyboard: true,
            links: AppLinks(
                purchase: URL(string: "https://example.com/buy"),
                support: URL(string: "https://example.com/guide"),
                privacy: URL(string: "https://example.com/privacy")
            )
        )
        h.menus.apps = [SettingsMenuSamples.figma, SettingsMenuSamples.notes]
        h.menus.items = SettingsMenuSamples.figmaMenus
        h.shortcuts.names = ["マイクを切り替える", "ページを要約", "翻訳"]
        h.ai.unavailableReason = "Apple Intelligence がオフになっています。システム設定 › Apple Intelligence と Siri でオンにしてください"
        return h
    }

    private func profile(named name: String, in h: SettingsHarness) throws -> Profile {
        try #require(h.controller.configuration.profiles.first { $0.name.hasPrefix(name) })
    }

    @Test func renderAll() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (suffix, appearance) in appearances {
            let h = try harness()
            let model = h.model

            // プロファイル: Xcode の中央（Claude Code のスクリプト）
            model.selectProfile(try profile(named: "Xcode", in: h).id)
            model.selectCell(4)
            try await render(SettingsRootView(model: model), size: CGSize(width: 1120, height: 720), appearance, "profiles-script-\(suffix)")

            // 最小の大きさ・キー入力のマス
            model.selectCell(0)
            try await render(SettingsRootView(model: model), size: CGSize(width: 860, height: 560), appearance, "profiles-min-keystroke-\(suffix)")

            // 記録中
            let cellID = try #require(model.selectedCell?.id)
            model.beginRecording(cellID: cellID)
            model.handleKeyDown(keyCode: 0x25, characters: "l", flags: .command)
            model.handleFlagsChanged([.command, .shift])
            try await render(SettingsInspectorView(model: model), size: CGSize(width: 310, height: 520), appearance, "inspector-recording-\(suffix)")
            model.cancelRecording()

            // 長い名前のプロファイル・空きマス・URL の誤り
            model.selectProfile(try profile(named: "とても長い", in: h).id)
            model.selectCell(4)
            try await render(SettingsRootView(model: model), size: CGSize(width: 1120, height: 720), appearance, "profiles-long-url-\(suffix)")
            model.selectCell(1)
            try await render(SettingsInspectorView(model: model), size: CGSize(width: 310, height: 520), appearance, "inspector-empty-\(suffix)")
            model.selectCell(8)
            try await render(SettingsInspectorView(model: model), size: CGSize(width: 310, height: 620), appearance, "inspector-ai-\(suffix)")

            // グローバル・アプリ起動・無効のプロファイル（Safari）
            model.selectProfile(nil)
            model.selectCell(0)
            try await render(SettingsInspectorView(model: model), size: CGSize(width: 310, height: 560), appearance, "inspector-launch-\(suffix)")
            model.selectProfile(try profile(named: "Safari", in: h).id)
            try await render(SettingsRootView(model: model), size: CGSize(width: 1120, height: 720), appearance, "profiles-disabled-\(suffix)")

            // ショートカット・メニュー項目
            model.selectProfile(nil)
            model.createCell(kind: .shortcut, at: 1)
            let shortcutID = try #require(model.selectedCell?.id)
            model.replaceAction(ofCell: shortcutID, with: .shortcut(ShortcutAction(name: "無いショートカット", passSelectedText: true)))
            model.shortcutList.loadIfNeeded()
            await model.shortcutList.waitUntilLoaded()
            try await render(SettingsInspectorView(model: model), size: CGSize(width: 310, height: 560), appearance, "inspector-shortcut-\(suffix)")

            // メニューから割り当て
            model.showMenus(true)
            model.menuBrowser.select(SettingsMenuSamples.figma)
            await model.menuBrowser.waitUntilLoaded()
            let node = try #require(model.menuBrowser.sections.dropFirst().first?.entries.dropFirst().first?.node)
            model.assignMenuItem(node, to: CellAddress(page: 0, index: 3))
            try await render(SettingsRootView(model: model), size: CGSize(width: 1120, height: 720), appearance, "profiles-menus-\(suffix)")
            model.showMenus(false)
            try await render(SettingsInspectorView(model: model), size: CGSize(width: 310, height: 520), appearance, "inspector-menuitem-\(suffix)")
            model.menuBrowser.query = "存在しない"
            model.showMenus(true)
            try await render(SettingsMenuPanel(model: model, browser: model.menuBrowser), size: CGSize(width: 310, height: 520), appearance, "menus-noresult-\(suffix)")
            h.menus.error = .permissionDenied("アクセシビリティ")
            model.menuBrowser.reload()
            await model.menuBrowser.waitUntilLoaded()
            try await render(SettingsMenuPanel(model: model, browser: model.menuBrowser), size: CGSize(width: 310, height: 520), appearance, "menus-permission-\(suffix)")
            model.showMenus(false)

            // 一般（JIS で右⌥・ログイン項目の失敗）
            model.tab = .general
            model.setSetting(\.trigger, .rightOption)
            h.loginItem.failure = SettingsFakeLoginError()
            model.setLoginItemEnabled(true)
            try await render(SettingsRootView(model: model), size: CGSize(width: 860, height: 1300), appearance, "general-\(suffix)")

            // ライセンス（試用・エラー）
            model.tab = .license
            model.licenseKeyInput = "eyJsaWNlbnNlSUQiOiJ.broken"
            model.activateLicense()
            try await render(SettingsRootView(model: model), size: CGSize(width: 860, height: 640), appearance, "license-trial-\(suffix)")

            // 情報
            model.tab = .about
            try await render(SettingsRootView(model: model), size: CGSize(width: 860, height: 640), appearance, "about-\(suffix)")

            // 状態の帯（権限なし）と書き出しの結果
            h.permissions.isAccessibilityGranted = false
            h.controller.refreshPermissions()
            model.fileMessage = SettingsMessage(text: "2個のプロファイルを追加しました。\nスクリプトを含むマスがあります。実行する前に中身を確かめてください。", isError: false)
            model.tab = .profiles
            try await render(SettingsRootView(model: model), size: CGSize(width: 1120, height: 760), appearance, "banners-\(suffix)")

            // シートと吹き出しの中身
            model.loadInstalledAppsIfNeeded()
            try await render(SettingsAddProfileSheet(model: model), size: CGSize(width: 460, height: 520), appearance, "sheet-add-profile-\(suffix)")
            try await render(
                SettingsIconPicker(icon: .symbol("hammer"), suggestedAppBundleID: "com.apple.dt.Xcode", defaultIcon: .symbol("keyboard")) { _ in },
                size: CGSize(width: 340, height: 360), appearance, "popover-icons-\(suffix)"
            )
            try await render(SettingsScriptHelp().padding(16).frame(width: 380), size: CGSize(width: 380, height: 480), appearance, "popover-script-help-\(suffix)")
            try await render(
                SettingsAppPickerPopover(model: model, current: "com.apple.Safari") { _ in },
                size: CGSize(width: 320, height: 380), appearance, "popover-apps-\(suffix)"
            )
        }
    }

    @Test func renderLicensedAndExpired() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let pair = LicenseSigner.generateKeyPair()
        let signer = try LicenseSigner(privateKeyBase64: pair.privateKeyBase64)
        let key = try signer.sign(LicenseInfo(licenseID: "NONET-2026-000123", licensee: "山田 太郎", email: "taro.yamada@example.com", issuedAt: Date(timeIntervalSince1970: 1_790_000_000)))
        for (suffix, appearance) in appearances {
            _ = NSApplication.shared
            let h = try SettingsHarness(verifier: try LicenseVerifier(publicKeyBase64: pair.publicKeyBase64), links: AppLinks(purchase: URL(string: "https://example.com/buy")))
            h.model.tab = .license
            h.model.licenseKeyInput = key
            h.model.activateLicense()
            try await render(SettingsRootView(model: h.model), size: CGSize(width: 860, height: 640), appearance, "license-licensed-\(suffix)")

            let storage = SettingsFakeLicenseStorage()
            storage.trialStartDate = Date(timeIntervalSinceReferenceDate: 700_000_000)
            let expired = LicenseManager(verifier: nil, storage: storage, now: { Date(timeIntervalSinceReferenceDate: 800_000_000) })
            let model = SettingsModel(controller: h.controller, license: expired, services: h.services, links: AppLinks(purchase: URL(string: "https://example.com/buy")), onCheckForUpdates: {})
            model.tab = .license
            try await render(SettingsRootView(model: model), size: CGSize(width: 860, height: 560), appearance, "license-expired-\(suffix)")
            model.tab = .about
            try await render(SettingsRootView(model: model), size: CGSize(width: 860, height: 560), appearance, "about-update-\(suffix)")
            try await render(SettingsAboutView(model: model, showsNotices: true), size: CGSize(width: 860, height: 900), appearance, "about-notices-\(suffix)")
        }
    }

    /// ツールバーを含むウィンドウ全体（画面には出さない）
    @Test func renderWindowChrome() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (suffix, appearance) in appearances {
            let h = try harness()
            let controller = SettingsWindowController(controller: h.controller, license: h.license, services: h.services, links: AppLinks(), onCheckForUpdates: nil)
            controller.autosavesFrame = false
            let window = controller.loadWindow()
            window.appearance = NSAppearance(named: appearance)
            controller.select(.profiles)
            controller.model.selectProfile(try profile(named: "Xcode", in: h).id)
            controller.model.selectCell(4)
            try await settle()
            guard let frameView = window.contentView?.superview else { return }
            frameView.layoutSubtreeIfNeeded()
            try write(frameView, name: "window-\(suffix)")
            window.close()
        }
    }

    // MARK: - 描き出し

    private func settle() async throws {
        for _ in 0..<4 {
            try await Task.sleep(for: .milliseconds(80))
        }
    }

    private func render<V: View>(_ view: V, size: CGSize, _ appearance: NSAppearance.Name, _ name: String) async throws {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height).background(Color(nsColor: .windowBackgroundColor)))
        hosting.frame = NSRect(origin: .zero, size: size)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        try await settle()
        hosting.layoutSubtreeIfNeeded()
        try write(hosting, name: name)
        window.contentView = nil
        window.close()
    }

    private func write(_ view: NSView, name: String) throws {
        guard let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            Issue.record("\(name) を描けない")
            return
        }
        view.cacheDisplay(in: view.bounds, to: representation)
        let data = try #require(representation.representation(using: .png, properties: [:]))
        try data.write(to: directory.appending(path: "\(name).png"))
    }
}
