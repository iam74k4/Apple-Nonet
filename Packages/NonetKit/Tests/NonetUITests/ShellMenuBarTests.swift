// 担当: ui-shell
import AppKit
import CoreGraphics
import Foundation
import NonetCore
import Observation
@testable import NonetUI
import Testing

/// テストの引数に使う状態（引数はメインアクターの外で作られる）
enum ShellMenuState {
    static func make(
        _ status: ControllerStatus = .running,
        enabled: Bool = true,
        profile: String? = nil,
        global: Bool = false,
        notice: String? = nil,
        entitlement: Entitlement = .trial(daysLeft: 12),
        updates: Bool = false,
        updateAvailable: Bool = false,
        editTarget: MenuBarEditTarget = .global,
        purchase: Bool = false,
        guide: Bool = false
    ) -> MenuBarState {
        MenuBarState(
            status: status,
            isEnabled: enabled,
            activeProfileName: profile,
            isGlobalProfileActive: global,
            notice: notice,
            entitlement: entitlement,
            canCheckForUpdates: updates,
            isUpdateAvailable: updateAvailable,
            editTarget: editTarget,
            canPurchase: purchase,
            hasGuide: guide
        )
    }

    static let licensed = Entitlement.licensed(LicenseInfo(licenseID: "1", licensee: "A", email: nil, issuedAt: Date(timeIntervalSince1970: 0)))
}

@Suite("メニューバー")
@MainActor
struct ShellMenuBarTests {
    @Test("状態の文", arguments: [
        (ShellMenuState.make(profile: "Xcode"), L10n.ui("\("Xcode") のプロファイル")),
        (ShellMenuState.make(profile: "グローバル", global: true), L10n.ui("グローバルのプロファイル")),
        (ShellMenuState.make(), L10n.ui("動作中")),
        (ShellMenuState.make(profile: ""), L10n.ui("動作中")),
        (ShellMenuState.make(.disabled, enabled: false), L10n.ui("Nonet は無効です")),
        (ShellMenuState.make(.needsAccessibility, enabled: false), L10n.ui("Nonet は無効です")),
        (ShellMenuState.make(.needsAccessibility), L10n.ui("アクセシビリティの許可が必要です")),
        (ShellMenuState.make(.noTrackpad), L10n.ui("トラックパッドが見つかりません")),
        (ShellMenuState.make(.secureInputActive), L10n.ui("パスワード入力中は使えません")),
        (ShellMenuState.make(.stopped), L10n.ui("停止しています")),
        // 試用期間が終わった・終わりが近いことは、プロファイルの名前の代わりに状態の行で知らせる
        (ShellMenuState.make(profile: "Xcode", entitlement: .expired), L10n.ui("試用期間が終了しました")),
        (ShellMenuState.make(profile: "Xcode", entitlement: .trial(daysLeft: 4)), L10n.ui("\("Xcode") のプロファイル")),
        // 動けない理由の方を先に言う
        (ShellMenuState.make(.needsAccessibility, entitlement: .expired), L10n.ui("アクセシビリティの許可が必要です")),
        (ShellMenuState.make(.disabled, enabled: false, entitlement: .trial(daysLeft: 1)), L10n.ui("Nonet は無効です")),
    ])
    func statusText(state: MenuBarState, expected: String) {
        #expect(MenuBarModel.statusText(for: state) == expected)
    }

    @Test("「このアプリでは使わない」アプリが前面なら、状態の行はプロファイルの名前ではなく、使わないこと")
    func statusTextInATurnedOffApp() {
        var state = ShellMenuState.make(profile: "グローバル", global: true)
        state.isTurnedOffInFrontApp = true
        #expect(MenuBarModel.statusText(for: state) == L10n.ui("このアプリでは使いません"))
    }

    @Test("試用期間の残りが3日以下なら、状態の行で残りの日数を言う（文言の言語の規則で数える）")
    func trialEndingText() {
        for days in 1...MenuBarModel.trialWarningDays {
            let state = ShellMenuState.make(profile: "Xcode", entitlement: .trial(daysLeft: days))
            #expect(MenuBarModel.status(for: state) == .trialEnding(daysLeft: days))
            #expect(MenuBarModel.statusText(for: state)
                == String(localized: "試用期間は残り\(days)日です", bundle: .nonetUI, locale: Self.textLanguage))
        }
        #expect(MenuBarModel.trialWarningDays == 3)
    }

    @Test("アイコン: 普段・無効・確認が必要", arguments: [
        (ShellMenuState.make(), MenuBarIconState.normal),
        (ShellMenuState.make(entitlement: .licensed(LicenseInfo(licenseID: "1", licensee: "A", email: nil, issuedAt: Date(timeIntervalSince1970: 0)))), .normal),
        (ShellMenuState.make(.disabled, enabled: false), .disabled),
        (ShellMenuState.make(.running, enabled: false), .disabled),
        (ShellMenuState.make(.stopped), .disabled),
        (ShellMenuState.make(.needsAccessibility), .attention),
        (ShellMenuState.make(.noTrackpad), .attention),
        (ShellMenuState.make(.secureInputActive), .attention),
        (ShellMenuState.make(entitlement: .expired), .attention),
        (ShellMenuState.make(notice: "設定ファイルを保存できません"), .attention),
        // 試用期間の終わりが近い（3日以下）
        (ShellMenuState.make(entitlement: .trial(daysLeft: 3)), .attention),
        (ShellMenuState.make(entitlement: .trial(daysLeft: 1)), .attention),
        (ShellMenuState.make(entitlement: .trial(daysLeft: 4)), .normal),
        // 自分で無効にしているなら、試用切れや知らせより「無効」を見せる
        (ShellMenuState.make(.disabled, enabled: false, notice: "壊れていました", entitlement: .expired), .disabled),
        (ShellMenuState.make(.disabled, enabled: false, entitlement: .trial(daysLeft: 2)), .disabled),
    ])
    func iconState(state: MenuBarState, expected: MenuBarIconState) {
        #expect(MenuBarModel.iconState(for: state) == expected)
        // アップデートが無ければ、メニューバーのアイコンも同じ
        #expect(MenuBarModel.buttonIconState(for: state) == expected)
    }

    @Test("見つかったアップデートは、普段どおりのときだけアイコンの印で知らせる（問題・無効の見た目を優先）", arguments: [
        (ShellMenuState.make(updates: true, updateAvailable: true), MenuBarIconState.updateAvailable),
        (ShellMenuState.make(.needsAccessibility, updates: true, updateAvailable: true), .attention),
        (ShellMenuState.make(entitlement: .expired, updates: true, updateAvailable: true), .attention),
        (ShellMenuState.make(.disabled, enabled: false, updates: true, updateAvailable: true), .disabled),
        // アップデートを確認できないなら出さない
        (ShellMenuState.make(updates: false, updateAvailable: true), .normal),
        (ShellMenuState.make(updates: true, updateAvailable: false), .normal),
    ])
    func updateBadge(state: MenuBarState, expected: MenuBarIconState) {
        #expect(MenuBarModel.buttonIconState(for: state) == expected)
        // メニューの状態の行はアップデートで変えない
        #expect(MenuBarModel.iconState(for: state) != .updateAvailable)
    }

    @Test("アイコンの説明: アップデートがあることも伝える")
    func accessibilityDescriptions() {
        #expect(MenuBarModel.accessibilityDescription(for: ShellMenuState.make()) == L10n.ui("Nonet"))
        #expect(MenuBarModel.accessibilityDescription(for: ShellMenuState.make(updates: true, updateAvailable: true))
            == L10n.ui("Nonet（アップデートがあります）"))
        #expect(MenuBarModel.accessibilityDescription(for: ShellMenuState.make(.noTrackpad, updates: true, updateAvailable: true))
            == L10n.ui("Nonet（確認が必要）"))
    }

    @Test("Sparkle からアップデートを受けたら、メニューを開かなくてもアイコンに印が付き、見せたら消える")
    func updateRedrawsIcon() throws {
        let harness = ShellControllerHarness()
        harness.controller.start()
        let menuBar = MenuBarController(
            controller: harness.controller,
            license: harness.license,
            onOpenSettings: { _ in },
            onOpenOnboarding: {},
            onCheckForUpdates: {}
        )
        defer { NSStatusBar.system.removeStatusItem(menuBar.statusItem) }
        let button = try #require(menuBar.statusItem.button)
        #expect(button.image === MenuBarIconRenderer.image(for: .normal))
        #expect(button.toolTip == L10n.ui("Nonet"))

        menuBar.isUpdateAvailable = true
        #expect(button.image === MenuBarIconRenderer.image(for: .updateAvailable))
        #expect(button.toolTip == L10n.ui("Nonet（アップデートがあります）"))
        #expect(button.accessibilityLabel() == L10n.ui("Nonet（アップデートがあります）"))

        menuBar.isUpdateAvailable = false
        #expect(button.image === MenuBarIconRenderer.image(for: .normal))
        #expect(button.toolTip == L10n.ui("Nonet"))
    }

    @Test("ライセンスの行")
    func licenseText() {
        #expect(MenuBarModel.licenseText(for: .trial(daysLeft: 3)) == L10n.ui("試用期間：残り\(3)日"))
        #expect(MenuBarModel.licenseText(for: .expired) == L10n.ui("試用期間が終了しました"))
        let info = LicenseInfo(licenseID: "1", licensee: "山田", email: nil, issuedAt: Date(timeIntervalSince1970: 0))
        #expect(MenuBarModel.licenseText(for: .licensed(info)) == L10n.ui("登録済み"))
    }

    /// 文言の言語（地域は付けない）。複数形の期待値はこの規則で選ぶ
    static var textLanguage: Locale {
        Locale(identifier: Bundle.nonetUI.preferredLocalizations.first ?? "ja")
    }

    @Test("試用の残り日数は、地域の設定ではなく文言の言語の規則で数を数える（日本の地域でアプリが英語でも「1 day」）")
    func licenseTextPlural() {
        for days in [1, 2] {
            #expect(MenuBarModel.licenseText(for: .trial(daysLeft: days))
                == String(localized: "試用期間：残り\(days)日", bundle: .nonetUI, locale: Self.textLanguage))
        }
    }

    @Test("文言のロケール: 言語は文言のもの、地域は今の設定")
    func textLocale() {
        let locale = Locale.localization("en", region: Locale.Region("JP"))
        #expect(locale.language.languageCode == .english)
        #expect(locale.region == Locale.Region("JP"))
        #expect(Locale.localization("ja", region: nil).language.languageCode == .japanese)
        #expect(Locale.localization(nil, region: nil) == Locale.current)
        #expect(Locale.nonetUI.language.languageCode?.identifier == Bundle.nonetUI.preferredLocalizations.first)
    }

    @Test("メニューの並び（普段・試用中）。購入ページ・利用ガイド・アップデートの確認が無ければ出さない")
    func entries() {
        let xcode = AppReference(bundleID: ShellFixtures.xcode, name: "Xcode")
        let entries = MenuBarModel.entries(for: ShellMenuState.make(profile: "Xcode", editTarget: .app(xcode, name: "Xcode")))
        #expect(entries == [
            .status(L10n.ui("\("Xcode") のプロファイル"), .normal),
            .separator,
            .toggleEnabled(isOn: true),
            .separator,
            .openSettings,
            .editButtons(.app(xcode, name: "Xcode")),
            .turnOffInApp(xcode, isOn: false),
            .showOnboarding,
            .separator,
            .trialInfo(L10n.ui("試用期間：残り\(12)日")),
            .enterLicenseKey,
            .separator,
            .quit,
        ])
    }

    @Test("購入ページがあれば「Nonet を購入…」、利用ガイドがあれば「利用ガイド」を出す")
    func purchaseAndGuideEntries() {
        let entries = MenuBarModel.entries(for: ShellMenuState.make(purchase: true, guide: true))
        #expect(Array(entries[4...]) == [
            .openSettings,
            .editButtons(.global),
            .showOnboarding,
            .userGuide,
            .separator,
            .trialInfo(L10n.ui("試用期間：残り\(12)日")),
            .purchase,
            .enterLicenseKey,
            .separator,
            .quit,
        ])
    }

    @Test("登録済みなら購入とライセンスキーの入力は出さず、「登録済み」から設定の「ライセンス」を開く")
    func licensedEntries() {
        let entries = MenuBarModel.entries(for: ShellMenuState.make(entitlement: ShellMenuState.licensed, purchase: true))
        #expect(entries.contains(.license(L10n.ui("登録済み"))))
        #expect(!entries.contains(.purchase))
        #expect(!entries.contains(.enterLicenseKey))
        #expect(!entries.contains { if case .trialInfo = $0 { true } else { false } })
    }

    @Test("試用期間が終わった・終わりが近いときは状態の行で知らせ、同じことを下の行で繰り返さない。購入とライセンスキーの入力は出す")
    func trialEndedEntries() {
        let ended = MenuBarModel.entries(for: ShellMenuState.make(profile: "Xcode", entitlement: .expired, purchase: true))
        #expect(ended.first == .status(L10n.ui("試用期間が終了しました"), .attention))
        #expect(!ended.contains { if case .trialInfo = $0 { true } else { false } })
        #expect(ended.contains(.purchase))
        #expect(ended.contains(.enterLicenseKey))

        let ending = MenuBarModel.entries(for: ShellMenuState.make(entitlement: .trial(daysLeft: 2)))
        #expect(!ending.contains { if case .trialInfo = $0 { true } else { false } })
        #expect(ending.contains(.enterLicenseKey))

        // 状態の行がほかの理由を言っているときは、試用期間の行も出す
        let blocked = MenuBarModel.entries(for: ShellMenuState.make(.noTrackpad, entitlement: .expired))
        #expect(blocked.contains(.trialInfo(L10n.ui("試用期間が終了しました"))))
    }

    @Test("アップデートの確認はライセンスキーの入力の次")
    func updatesEntry() throws {
        let entries = MenuBarModel.entries(for: ShellMenuState.make(updates: true))
        let license = try #require(entries.firstIndex(of: .enterLicenseKey))
        #expect(entries[license + 1] == .checkForUpdates)
    }

    @Test("定期の確認で見つかったアップデートは「アップデートがあります…」で知らせる")
    func updateAvailableEntry() throws {
        let entries = MenuBarModel.entries(for: ShellMenuState.make(updates: true, updateAvailable: true))
        let license = try #require(entries.firstIndex(of: .enterLicenseKey))
        #expect(entries[license + 1] == .updateAvailable)
        #expect(!entries.contains(.checkForUpdates))
        #expect(MenuBarEntry.updateAvailable.title == L10n.ui("アップデートがあります…"))
        // アップデートを確認できないなら出さない
        #expect(!MenuBarModel.entries(for: ShellMenuState.make(updates: false, updateAvailable: true)).contains(.updateAvailable))
    }

    @Test("許可が無ければ「アクセシビリティを許可…」を出す。無効のときは出さない")
    func accessibilityEntry() {
        #expect(MenuBarModel.entries(for: ShellMenuState.make(.needsAccessibility)).contains(.requestAccessibility))
        #expect(!MenuBarModel.entries(for: ShellMenuState.make(.needsAccessibility, enabled: false)).contains(.requestAccessibility))
        #expect(!MenuBarModel.entries(for: ShellMenuState.make()).contains(.requestAccessibility))
    }

    @Test("知らせがあれば状態の下に出し、消す項目を付ける")
    func noticeEntries() {
        let entries = MenuBarModel.entries(for: ShellMenuState.make(.running, notice: "設定ファイルが壊れていたので退避しました"))
        #expect(Array(entries.prefix(3)) == [
            .status(L10n.ui("動作中"), .attention),
            .notice("設定ファイルが壊れていたので退避しました"),
            .dismissNotice,
        ])
        #expect(!MenuBarModel.entries(for: ShellMenuState.make(notice: "")).contains(.dismissNotice))
    }

    @Test("無効のときはチェックを外す")
    func toggleOff() {
        #expect(MenuBarModel.entries(for: ShellMenuState.make(.disabled, enabled: false)).contains(.toggleEnabled(isOn: false)))
    }

    @Test("項目の文言は利用ガイドと同じ")
    func titles() {
        #expect(MenuBarEntry.toggleEnabled(isOn: true).title == L10n.ui("Nonet を有効にする"))
        #expect(MenuBarEntry.openSettings.title == L10n.ui("設定…"))
        #expect(MenuBarEntry.editButtons(.app(AppReference(bundleID: ShellFixtures.xcode, name: "Xcode"), name: "Xcode")).title
            == L10n.ui("\("Xcode") のマスを編集…"))
        #expect(MenuBarEntry.editButtons(.newApp(AppReference(bundleID: "com.apple.iWork.Pages", name: "Pages"))).title
            == L10n.ui("\("Pages") のマスを作る…"))
        // 名前が分からなければ bundle ID
        #expect(MenuBarEntry.editButtons(.newApp(AppReference(bundleID: "com.example.app", name: " "))).title
            == L10n.ui("\("com.example.app") のマスを作る…"))
        #expect(MenuBarEntry.editButtons(.global).title == L10n.ui("グローバルのマスを編集…"))
        #expect(MenuBarEntry.showOnboarding.title == L10n.ui("初回の案内をもう一度"))
        #expect(MenuBarEntry.userGuide.title == L10n.ui("利用ガイド"))
        #expect(MenuBarEntry.purchase.title == L10n.ui("Nonet を購入…"))
        #expect(MenuBarEntry.enterLicenseKey.title == L10n.ui("ライセンスキーを入力…"))
        #expect(MenuBarEntry.checkForUpdates.title == L10n.ui("アップデートを確認"))
        #expect(MenuBarEntry.quit.title == L10n.ui("終了"))
    }

    @Test("「◯◯のボタンを編集…」は前面のアプリで決める: プロファイルがあれば編集（無効でも）、無ければ作る、分からなければグローバル")
    func editTarget() throws {
        var configuration = NonetConfiguration(profiles: [Profile(kind: .global, pages: [.empty])])
        let xcode = AppReference(bundleID: ShellFixtures.xcode, name: "Xcode")
        let xcodeID = configuration.addAppProfile(for: xcode, preset: nil)
        let pages = AppReference(bundleID: "com.apple.iWork.Pages", name: "Pages")
        #expect(MenuBarEditTarget.resolve(frontApp: xcode, configuration: configuration) == .app(xcode, name: "Xcode"))
        #expect(MenuBarEditTarget.resolve(frontApp: AppReference(bundleID: " COM.apple.dt.xcode", name: "Xcode"), configuration: configuration)
            == .app(AppReference(bundleID: " COM.apple.dt.xcode", name: "Xcode"), name: "Xcode"))
        #expect(MenuBarEditTarget.resolve(frontApp: pages, configuration: configuration) == .newApp(pages))
        #expect(MenuBarEditTarget.resolve(frontApp: nil, configuration: configuration) == .global)
        #expect(MenuBarEditTarget.resolve(frontApp: AppReference(bundleID: "", name: "?"), configuration: configuration) == .global)
        configuration.updateProfile(id: xcodeID) { $0.isEnabled = false }
        #expect(MenuBarEditTarget.resolve(frontApp: xcode, configuration: configuration) == .app(xcode, name: "Xcode"))
        #expect(MenuBarEditTarget.global.app == nil)
        #expect(MenuBarEditTarget.newApp(pages).app == pages)
    }

    @Test("メニューの項目を押すと動く（宛先の selector が NSObject の performSelector: にならない）")
    func menuItemsRun() throws {
        let app = NSApplication.shared
        let harness = ShellControllerHarness()
        harness.controller.start()
        var opened: [SettingsTab] = []
        var onboarding = 0
        var updates = 0
        var edited: [AppReference?] = []
        var urls: [URL] = []
        let menuBar = MenuBarController(
            controller: harness.controller,
            license: harness.license,
            onOpenSettings: { opened.append($0) },
            onOpenOnboarding: { onboarding += 1 },
            onCheckForUpdates: { updates += 1 }
        )
        defer { NSStatusBar.system.removeStatusItem(menuBar.statusItem) }
        let pages = AppReference(bundleID: "com.apple.iWork.Pages", name: "Pages")
        let purchase = try #require(URL(string: "https://example.com/buy"))
        let guide = try #require(URL(string: "https://example.com/guide.html"))
        menuBar.frontmostApp = { pages }
        menuBar.onEditButtons = { edited.append($0) }
        menuBar.links = AppLinks(purchase: purchase, support: guide)
        menuBar.openURL = { urls.append($0) }
        menuBar.isUpdateAvailable = true
        let menu = menuBar.menu
        menu.delegate?.menuNeedsUpdate?(menu)
        func press(_ title: String) throws {
            let item = try #require(menu.items.first { $0.title == title })
            #expect(item.action.map(NSStringFromSelector) != "performSelector:")
            #expect(app.sendAction(try #require(item.action), to: item.target, from: item))
        }
        try press(L10n.ui("設定…"))
        try press(L10n.ui("\("Pages") のマスを作る…"))
        try press(L10n.ui("初回の案内をもう一度"))
        try press(L10n.ui("利用ガイド"))
        try press(L10n.ui("Nonet を購入…"))
        try press(L10n.ui("ライセンスキーを入力…"))
        try press(L10n.ui("アップデートがあります…"))
        #expect(opened == [.general, .license])
        #expect(edited == [pages])
        #expect(urls == [guide, purchase])
        #expect(onboarding == 1)
        #expect(updates == 1)
        // 試用期間の行は知らせだけ（押せない）
        #expect(menu.items.first { $0.title == L10n.ui("試用期間：残り\(14)日") }?.isEnabled == false)
        try press(L10n.ui("Nonet を有効にする"))
        #expect(!harness.controller.configuration.settings.isEnabled)

        // 開くものを受け取らなければ、設定の「プロファイル」を開く
        menuBar.onEditButtons = nil
        menuBar.frontmostApp = nil
        menu.delegate?.menuNeedsUpdate?(menu)
        try press(L10n.ui("グローバルのマスを編集…"))
        #expect(opened == [.general, .license, .profiles])
    }

    /// メニューの「このアプリでは使わない」を押す。押す前に menuNeedsUpdate でメニューを作り直す
    private func pressTurnOff(_ menuBar: MenuBarController) throws {
        let menu = menuBar.menu
        menu.delegate?.menuNeedsUpdate?(menu)
        let item = try #require(menu.items.first { $0.title == L10n.ui("このアプリでは使わない") })
        #expect(NSApplication.shared.sendAction(try #require(item.action), to: item.target, from: item))
    }

    private func makeMenuBar(_ harness: ShellControllerHarness, frontmost app: AppReference) -> MenuBarController {
        let menuBar = MenuBarController(
            controller: harness.controller,
            license: harness.license,
            onOpenSettings: { _ in },
            onOpenOnboarding: {},
            onCheckForUpdates: {}
        )
        menuBar.frontmostApp = { app }
        return menuBar
    }

    @Test("「このアプリでは使わない」を2回選ぶと元に戻る。プロファイルの無かったアプリは、空のプロファイルで止めて、戻すと消す")
    func turningOffTwiceRestoresAnAppWithoutAProfile() throws {
        let harness = ShellControllerHarness()
        harness.controller.start()
        let notes = AppReference(bundleID: "com.apple.Notes", name: "メモ")
        #expect(PresetLibrary.preset(forBundleID: notes.bundleID) != nil)
        harness.controller.update { configuration in
            configuration.profiles.removeAll { $0.app?.bundleID == notes.bundleID }
        }
        let before = harness.controller.configuration
        let menuBar = makeMenuBar(harness, frontmost: notes)
        defer { NSStatusBar.system.removeStatusItem(menuBar.statusItem) }

        try pressTurnOff(menuBar)
        #expect(harness.controller.configuration.isTurnedOff(forBundleID: notes.bundleID))
        // プリセットのボタンは足さない（オフの間に設定画面で「このプロファイル」にしても、グローバルのボタンが増えたように見えない）
        let created = harness.controller.configuration.profiles.first { $0.app?.bundleID == notes.bundleID }
        #expect(created?.pages.allSatisfy { $0.cells.allSatisfy { $0 == nil } } == true)

        try pressTurnOff(menuBar)
        #expect(!harness.controller.configuration.isTurnedOff(forBundleID: notes.bundleID))
        #expect(harness.controller.configuration == before)
    }

    @Test("「このアプリでは使わない」を2回選ぶと、オフにする前の使い方（グローバルを使う）に戻る")
    func turningOffTwiceRestoresThePreviousMode() throws {
        let harness = ShellControllerHarness()
        harness.controller.start()
        let pages = AppReference(bundleID: ShellFixtures.xcode, name: "Xcode")
        #expect(PresetLibrary.preset(forBundleID: pages.bundleID) != nil)
        var id: UUID?
        harness.controller.update { configuration in
            id = configuration.addAppProfile(for: pages, preset: PresetLibrary.preset(forBundleID: pages.bundleID))
            configuration.setAppMode(.global, for: pages)
        }
        let profileID = try #require(id)
        let before = harness.controller.configuration
        let menuBar = makeMenuBar(harness, frontmost: pages)
        defer { NSStatusBar.system.removeStatusItem(menuBar.statusItem) }

        try pressTurnOff(menuBar)
        #expect(harness.controller.configuration.profile(id: profileID)?.mode == .off)
        try pressTurnOff(menuBar)
        #expect(harness.controller.configuration.profile(id: profileID)?.mode == .global)
        #expect(harness.controller.configuration == before)
    }

    @Test("設定画面でオフにしたアプリは、ボタンのあるプロファイルならそれを、無ければグローバルを使うように戻す")
    func turningBackOnWithoutMemory() throws {
        let harness = ShellControllerHarness()
        harness.controller.start()
        let pages = AppReference(bundleID: ShellFixtures.xcode, name: "Xcode")
        harness.controller.update { configuration in
            configuration.setAppMode(.off, for: pages, preset: PresetLibrary.preset(forBundleID: pages.bundleID))
        }
        let menuBar = makeMenuBar(harness, frontmost: pages)
        defer { NSStatusBar.system.removeStatusItem(menuBar.statusItem) }
        try pressTurnOff(menuBar)
        #expect(harness.controller.configuration.appMode(forBundleID: pages.bundleID) == .profile)
    }

    @Test("NonetController と LicenseManager から状態を集める")
    func stateFromController() throws {
        let harness = ShellControllerHarness(installed: [ShellFixtures.xcode], accessibilityGranted: false)
        harness.controller.start()
        let state = MenuBarState(controller: harness.controller, license: harness.license, canCheckForUpdates: true)
        #expect(state.status == .needsAccessibility)
        #expect(state.isEnabled)
        #expect(state.entitlement == .trial(daysLeft: 14))
        #expect(state.canCheckForUpdates)
        #expect(state.editTarget == .global)
        #expect(!state.canPurchase)
        #expect(!state.hasGuide)
        #expect(MenuBarModel.iconState(for: state) == .attention)

        let xcode = AppReference(bundleID: ShellFixtures.xcode, name: "Xcode")
        let linked = MenuBarState(
            controller: harness.controller,
            license: harness.license,
            canCheckForUpdates: false,
            frontApp: xcode,
            links: AppLinks(purchase: URL(string: "https://example.com/buy"), support: URL(string: "https://example.com/guide"))
        )
        let xcodeName = try #require(harness.controller.configuration.appProfile(forBundleID: ShellFixtures.xcode)).name
        #expect(linked.editTarget == .app(xcode, name: xcodeName))
        #expect(linked.canPurchase)
        #expect(linked.hasGuide)

        harness.controller.update { $0.settings.isEnabled = false }
        let disabled = MenuBarState(controller: harness.controller, license: harness.license, canCheckForUpdates: false)
        #expect(!disabled.isEnabled)
        #expect(MenuBarModel.iconState(for: disabled) == .disabled)
    }

    @Test("見張り: 最初の値をすぐに知らせ、変わったら知らせる。cancel で止まる")
    func observer() async {
        let harness = ShellControllerHarness(accessibilityGranted: true)
        var seen: [Bool] = []
        let observer = ShellObserver({ harness.controller.configuration.settings.isEnabled }, onChange: { seen.append($0) })
        #expect(seen == [true])
        harness.controller.update { $0.settings.isEnabled = false }
        await Self.drainMainQueue()
        #expect(seen == [true, false])
        // 同じ値なら知らせない
        harness.controller.update { $0.settings.haptics = .strong }
        await Self.drainMainQueue()
        #expect(seen == [true, false])
        observer.cancel()
        harness.controller.update { $0.settings.isEnabled = true }
        await Self.drainMainQueue()
        #expect(seen == [true, false])
    }

    @Test("アイコンの形: 輪の8つの点と真ん中の点が重ならず、キャンバスに収まり、中央にそろう")
    func iconGeometry() {
        let canvas = CGRect(origin: .zero, size: MenuBarIconGeometry.canvas)
        let dots = MenuBarIconGeometry.ringDotRects() + [MenuBarIconGeometry.centerDotRect]
        #expect(dots.count == 9)
        for (index, dot) in dots.enumerated() {
            #expect(canvas.contains(dot))
            for other in dots[(index + 1)...] {
                #expect(!dot.intersects(other))
            }
        }
        // 上から時計回り（y は下向き）: 0 が上、1 が右上、2 が右、4 が下、6 が左。どれも輪の上
        let center = MenuBarIconGeometry.center
        let points = MenuBarIconGeometry.ringPoints()
        #expect(points.count == 8)
        #expect(abs(points[0].x - center.x) < 0.001 && points[0].y < center.y)
        #expect(points[1].x > center.x && points[1].y < center.y)
        #expect(points[2].x > center.x && abs(points[2].y - center.y) < 0.001)
        #expect(abs(points[4].x - center.x) < 0.001 && points[4].y > center.y)
        #expect(points[6].x < center.x && abs(points[6].y - center.y) < 0.001)
        for point in points {
            #expect(abs(Self.distance(from: point, to: center) - MenuBarIconGeometry.ringRadius) < 0.001)
        }
        // 中央にそろう
        let bounds = MenuBarIconGeometry.markBounds
        #expect(abs(bounds.midX - canvas.midX) < 0.001)
        #expect(abs(bounds.midY - canvas.midY) < 0.001)
        #expect(abs(MenuBarIconGeometry.centerDotRect.midX - canvas.midX) < 0.001)
        #expect(abs(MenuBarIconGeometry.centerDotRect.midY - canvas.midY) < 0.001)
    }

    @Test("アイコンの形: 真ん中の塗りと印。確かめてほしいことは「!」、アップデートは点（見分けられるように）")
    func iconVariants() {
        #expect(MenuBarIconGeometry.fillsCenter(for: .normal))
        #expect(MenuBarIconGeometry.fillsCenter(for: .attention))
        #expect(MenuBarIconGeometry.fillsCenter(for: .updateAvailable))
        #expect(!MenuBarIconGeometry.fillsCenter(for: .disabled))
        #expect(MenuBarIconGeometry.badge(for: .attention) == .exclamation)
        #expect(MenuBarIconGeometry.badge(for: .updateAvailable) == .dot)
        #expect(MenuBarIconGeometry.badge(for: .normal) == nil)
        #expect(MenuBarIconGeometry.badge(for: .disabled) == nil)
        #expect(MenuBarIconGeometry.showsBadge(for: .attention))
        #expect(MenuBarIconGeometry.showsBadge(for: .updateAvailable))
        #expect(!MenuBarIconGeometry.showsBadge(for: .normal))
        #expect(!MenuBarIconGeometry.showsBadge(for: .disabled))
        #expect(MenuBarIconRenderer.image(for: .attention) !== MenuBarIconRenderer.image(for: .updateAvailable))

        // 「!」は右上の点を切り抜いた輪の中に収まり、キャンバスからはみ出さない
        let canvas = CGRect(origin: .zero, size: MenuBarIconGeometry.canvas)
        let badgeCenter = MenuBarIconGeometry.badgeCenter
        let cutout = MenuBarIconGeometry.badgeCutoutRadius
        let mark = MenuBarIconGeometry.exclamationBar.union(MenuBarIconGeometry.exclamationDot)
        #expect(canvas.contains(mark))
        for corner in [CGPoint(x: mark.minX, y: mark.minY), CGPoint(x: mark.maxX, y: mark.minY), CGPoint(x: mark.minX, y: mark.maxY), CGPoint(x: mark.maxX, y: mark.maxY)] {
            #expect(Self.distance(from: corner, to: badgeCenter) <= cutout)
        }
        // 縦棒と点は離れている（「!」に見える）
        #expect(MenuBarIconGeometry.exclamationBar.maxY < MenuBarIconGeometry.exclamationDot.minY)

        // 印は右上の点の代わりに置く: その点は切り抜きの中にすっぽり入り、ほかの点と真ん中の点には触れず、キャンバスからはみ出さない
        let radius = MenuBarIconGeometry.badgeRadius
        #expect(canvas.contains(MenuBarIconGeometry.rect(center: badgeCenter, radius: radius)))
        #expect(cutout > radius)
        let points = MenuBarIconGeometry.ringPoints()
        let replaced = points[MenuBarIconGeometry.badgeSlot]
        #expect(replaced.x > MenuBarIconGeometry.center.x && replaced.y < MenuBarIconGeometry.center.y)
        #expect(Self.distance(from: replaced, to: badgeCenter) + MenuBarIconGeometry.dotRadius <= cutout + 0.001)
        for (slot, point) in points.enumerated() where slot != MenuBarIconGeometry.badgeSlot {
            #expect(Self.distance(from: point, to: badgeCenter) - MenuBarIconGeometry.dotRadius >= cutout - 0.001)
        }
        #expect(Self.distance(from: MenuBarIconGeometry.center, to: badgeCenter) - MenuBarIconGeometry.centerDotRadius >= cutout)
    }

    @Test("アイコンの画像はテンプレートで、状態ごとに使い回す")
    func iconImages() {
        for state in MenuBarIconState.allCases {
            let image = MenuBarIconRenderer.image(for: state)
            #expect(image.isTemplate)
            #expect(image.size == MenuBarIconGeometry.canvas)
            #expect(MenuBarIconRenderer.image(for: state) === image)
        }
    }

    @Test("ようこその説明は、上の縁から指を滑らせることを言う")
    func welcomeText() {
        #expect(ShellText.welcomeSubtitle == L10n.ui("トラックパッドの上の縁から指を滑らせると、トラックパッドがアプリごとに変わる9つのボタンになります"))
    }

    @Test("メニューバーのアイコンが見えているか: 画面の中で、ノッチのある画面ではノッチの右のメニューバーにあるとき")
    func statusItemVisibility() {
        typealias Screen = MenuBarItemVisibility.Screen
        let plain = Screen(frame: CGRect(x: 0, y: 0, width: 1440, height: 900), hasNotch: false, auxiliaryTopRightArea: nil)
        let item = CGRect(x: 1200, y: 876, width: 24, height: 24)
        #expect(MenuBarItemVisibility.isVisible(itemFrame: item, screens: [plain]))
        #expect(!MenuBarItemVisibility.isVisible(itemFrame: CGRect(x: -100, y: 876, width: 24, height: 24), screens: [plain]))
        #expect(!MenuBarItemVisibility.isVisible(itemFrame: .zero, screens: [plain]))
        #expect(!MenuBarItemVisibility.isVisible(itemFrame: item, screens: []))

        // ノッチの右（x 840〜1512）にあれば見える。ノッチの陰（x 670〜840）なら見えない
        let notched = Screen(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            hasNotch: true,
            auxiliaryTopRightArea: CGRect(x: 840, y: 950, width: 672, height: 32)
        )
        #expect(MenuBarItemVisibility.isVisible(itemFrame: CGRect(x: 1000, y: 954, width: 24, height: 24), screens: [notched]))
        #expect(!MenuBarItemVisibility.isVisible(itemFrame: CGRect(x: 740, y: 954, width: 24, height: 24), screens: [notched]))
        // 主画面でない画面で、画面の中の座標で返っても合わせる
        let second = Screen(
            frame: CGRect(x: 1512, y: 0, width: 1512, height: 982),
            hasNotch: true,
            auxiliaryTopRightArea: CGRect(x: 840, y: 950, width: 672, height: 32)
        )
        #expect(MenuBarItemVisibility.isVisible(itemFrame: CGRect(x: 2600, y: 954, width: 24, height: 24), screens: [notched, second]))
        #expect(!MenuBarItemVisibility.isVisible(itemFrame: CGRect(x: 2250, y: 954, width: 24, height: 24), screens: [notched, second]))
    }

    @Test("見えていなければ、メニューバーのアイコンの場所を見せない（テストではアイコンが画面に出ない）")
    func pointAtHiddenStatusItem() {
        let harness = ShellControllerHarness()
        harness.controller.start()
        let menuBar = MenuBarController(controller: harness.controller, license: harness.license, onOpenSettings: { _ in }, onOpenOnboarding: {}, onCheckForUpdates: nil)
        defer { NSStatusBar.system.removeStatusItem(menuBar.statusItem) }
        menuBar.statusItem.isVisible = false
        #expect(!menuBar.isStatusItemVisible)
        menuBar.pointAtStatusItem()
        #expect(menuBar.statusItem.button?.isHighlighted != true)
    }

    static func distance(from point: CGPoint, to other: CGPoint) -> CGFloat {
        ((point.x - other.x) * (point.x - other.x) + (point.y - other.y) * (point.y - other.y)).squareRoot()
    }

    static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }

    /// ShellObserver はメインキューで読み直すので、積まれた仕事を流す
    static func drainMainQueue() async {
        for _ in 0..<3 {
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
    }
}
