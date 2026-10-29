// 担当: ui-shell
import Foundation
import NonetCore
@testable import NonetUI
import Testing

/// 初回の案内をどう終えたか
enum ShellFirstGuideEnding: String, CaseIterable, Sendable {
    /// ようこそのまま閉じた
    case closedAtWelcome
    /// 「あとで設定する」で飛ばしてから閉じた
    case skipped
    /// 選んだアプリを反映してから閉じた
    case applied
}

@Suite("初回起動")
@MainActor
struct ShellOnboardingTests {
    nonisolated static let installed: Set<String> = [
        ShellFixtures.xcode, ShellFixtures.safari, ShellFixtures.finder, "com.figma.Desktop", "com.apple.Terminal",
    ]

    /// 時計を差し替えたモデル
    final class Clock {
        var now = ShellControllerHarness.now
    }

    static func make(
        installed: Set<String> = installed,
        granted: Bool = true,
        isFirstLaunchGuide: Bool = true,
        clock: Clock = Clock()
    ) -> (OnboardingModel, ShellControllerHarness) {
        let harness = ShellControllerHarness(installed: installed, accessibilityGranted: granted)
        harness.controller.start()
        let model = OnboardingModel(
            controller: harness.controller,
            permissions: harness.permissions,
            installedApps: harness.installedApps,
            isFirstLaunchGuide: isFirstLaunchGuide,
            now: { clock.now }
        )
        return (model, harness)
    }

    // MARK: - アクセシビリティ

    @Test("許可されたら自動で「アプリを選ぶ」へ進み、コントローラーに知らせる")
    func autoAdvanceOnPermission() {
        let (model, harness) = Self.make(granted: false)
        #expect(model.step == .welcome)
        #expect(!model.isAccessibilityGranted)
        #expect(harness.controller.status == .needsAccessibility)

        model.pollPermission()
        #expect(model.step == .welcome)

        harness.permissions.isAccessibilityGranted = true
        model.pollPermission()
        #expect(model.isAccessibilityGranted)
        #expect(model.step == .apps)
        #expect(harness.controller.status == .running)
    }

    @Test("最初の画面以外で許可されても、画面は動かさない")
    func permissionLaterDoesNotJump() {
        let (model, harness) = Self.make(granted: false)
        model.next()
        model.skipSelection()
        #expect(model.step == .practice)
        #expect(model.practiceBlocker == .needsAccessibility)
        #expect(model.practiceBlocker?.message == "アクセシビリティが許可されていないため、まだ試せません")
        harness.permissions.isAccessibilityGranted = true
        model.pollPermission()
        #expect(model.step == .practice)
        #expect(model.practiceBlocker == nil)
    }

    @Test("最初から許可されていれば待たずに次へ進める（自動では進まない）")
    func alreadyGranted() {
        let (model, _) = Self.make(granted: true)
        #expect(model.isAccessibilityGranted)
        model.pollPermission()
        #expect(model.step == .welcome)
        model.next()
        #expect(model.step == .apps)
    }

    @Test("許可を取り消されたら表示を戻す")
    func permissionRevoked() {
        let (model, harness) = Self.make(granted: true)
        harness.permissions.isAccessibilityGranted = false
        model.pollPermission()
        #expect(!model.isAccessibilityGranted)
        #expect(harness.controller.status == .needsAccessibility)
    }

    @Test("「システム設定を開く」は許可のダイアログと設定アプリの両方")
    func requestAccessibility() {
        let (model, harness) = Self.make(granted: false)
        model.requestAccessibility()
        #expect(harness.permissions.requestCount == 1)
        #expect(harness.permissions.openSettingsCount == 1)
    }

    @Test("許可せずに先へ進める")
    func continueWithoutPermission() {
        let (model, _) = Self.make(granted: false)
        model.next()
        #expect(model.step == .apps)
    }

    // MARK: - アプリを選ぶ

    @Test("インストール済みでプリセットのあるアプリだけを、プリセットの順に並べて全部選ぶ")
    func choices() {
        let (model, _) = Self.make()
        let expected = PresetLibrary.apps.map(\.app.bundleID).filter { Self.installed.contains($0) }
        #expect(model.choices.map(\.id) == expected)
        #expect(model.choices.contains { $0.id == ShellFixtures.xcode })
        #expect(model.choices.allSatisfy { $0.isSelected && !$0.isConfigured })
        #expect(model.selectedCount == expected.count)
        #expect(model.choices.allSatisfy { !$0.summary.isEmpty && !$0.category.isEmpty })
    }

    @Test("選択を切り替える。すべて外す・すべて選ぶ")
    func toggleSelection() {
        let (model, _) = Self.make()
        model.toggle(ShellFixtures.safari)
        #expect(model.choices.first { $0.id == ShellFixtures.safari }?.isSelected == false)
        #expect(model.selectedCount == model.choices.count - 1)
        model.toggle("not.installed")
        #expect(model.selectedCount == model.choices.count - 1)
        model.setAllSelected(false)
        #expect(model.selectedCount == 0)
        model.setAllSelected(true)
        #expect(model.selectedCount == model.choices.count)
    }

    @Test("「次へ」は選んだアプリだけのプロファイルとランチャーで作り直し、全体の設定はそのまま残す")
    func applyKeepsSettings() {
        let (model, harness) = Self.make()
        // 案内を開いた後に全体の設定だけを変えても（メニューで無効にしたなど）、作り直してよい
        harness.controller.update { configuration in
            configuration.settings.trigger = .rightShift
            configuration.settings.hudDelay = 0.55
            configuration.settings.hudPosition = .nearCursor
            configuration.settings.haptics = .strong
            configuration.settings.fireMode = .onFingerLift
        }
        let settingsBefore = harness.controller.configuration.settings
        model.next()
        #expect(model.replacesProfiles)
        model.setAllSelected(false)
        model.toggle(ShellFixtures.xcode)
        model.toggle(ShellFixtures.safari)
        model.applySelection()

        let configuration = harness.controller.configuration
        #expect(configuration.settings == settingsBefore)
        #expect(configuration.profiles.compactMap(\.app?.bundleID).sorted() == [ShellFixtures.safari, ShellFixtures.xcode].sorted())
        #expect(configuration.profiles.first?.isGlobal == true)
        // グローバルはインストール済みのランチャー候補（Finder・Safari・Xcode など）
        let launcherApps = configuration.globalProfile.pages.flatMap(\.cells).compactMap { cell -> String? in
            guard case .launchApp(let launch)? = cell?.action else { return nil }
            return launch.app.bundleID
        }
        #expect(!launcherApps.isEmpty)
        #expect(launcherApps.allSatisfy { Self.installed.contains($0) })
        #expect(model.step == .practice)
    }

    @Test("何も選ばずに「次へ」ならアプリのプロファイルは無し（グローバルだけ）")
    func applyNothingSelected() {
        let (model, harness) = Self.make()
        model.next()
        model.setAllSelected(false)
        model.applySelection()
        #expect(harness.controller.configuration.profiles.count == 1)
        #expect(harness.controller.configuration.profiles[0].isGlobal)
    }

    @Test("「あとで設定する」は設定を変えずに試してみるへ")
    func skipSelection() {
        let (model, harness) = Self.make()
        let before = harness.controller.configuration
        model.next()
        model.setAllSelected(false)
        model.skipSelection()
        #expect(model.step == .practice)
        #expect(harness.controller.configuration == before)
    }

    @Test("「アプリを選ぶ」以外の画面では反映しない")
    func applyOnlyOnAppsStep() {
        let (model, harness) = Self.make()
        let before = harness.controller.configuration
        model.applySelection()
        model.skipSelection()
        #expect(model.step == .welcome)
        #expect(harness.controller.configuration == before)
    }

    @Test("案内をもう一度見るときは、設定済みのアプリを残して足りないものだけ足す")
    func rerunAddsOnly() {
        let (model, harness) = Self.make(isFirstLaunchGuide: false)
        // 初回の設定（インストール済みのプリセットすべて）から Safari を消し、Xcode を編集しておく
        let safariID = harness.controller.configuration.appProfile(forBundleID: ShellFixtures.safari)?.id
        let xcodeID = harness.controller.configuration.appProfile(forBundleID: ShellFixtures.xcode)?.id
        harness.controller.update { configuration in
            if let safariID { configuration.removeProfile(id: safariID) }
            if let xcodeID { configuration.setCell(nil, at: CellAddress(page: 0, index: 0), profileID: xcodeID) }
            configuration.settings.trigger = .function
        }
        let rerun = OnboardingModel(
            controller: harness.controller,
            permissions: harness.permissions,
            installedApps: harness.installedApps,
            isFirstLaunchGuide: false
        )
        _ = model
        let xcode = rerun.choices.first { $0.id == ShellFixtures.xcode }
        let safari = rerun.choices.first { $0.id == ShellFixtures.safari }
        #expect(xcode?.isConfigured == true)
        #expect(safari?.isConfigured == false)
        // 設定済みのものは外せない
        rerun.toggle(ShellFixtures.xcode)
        #expect(rerun.choices.first { $0.id == ShellFixtures.xcode }?.isSelected == true)

        let editedXcode = harness.controller.configuration.appProfile(forBundleID: ShellFixtures.xcode)
        rerun.next()
        rerun.applySelection()
        let configuration = harness.controller.configuration
        #expect(configuration.appProfile(forBundleID: ShellFixtures.safari) != nil)
        #expect(configuration.appProfile(forBundleID: ShellFixtures.xcode) == editedXcode)
        #expect(configuration.settings.trigger == .function)
    }

    @Test("もう一度見るとき、無効にしたプロファイルのアプリも設定済み。足す数に数えず、有効にも戻さない")
    func rerunKeepsDisabledProfile() throws {
        let (model, harness) = Self.make(isFirstLaunchGuide: false)
        let xcodeID = try #require(harness.controller.configuration.appProfile(forBundleID: ShellFixtures.xcode)?.id)
        let safariID = try #require(harness.controller.configuration.appProfile(forBundleID: ShellFixtures.safari)?.id)
        harness.controller.update { configuration in
            configuration.updateProfile(id: xcodeID) { $0.isEnabled = false }
            configuration.removeProfile(id: safariID)
        }
        model.next()
        let xcode = try #require(model.choices.first { $0.id == ShellFixtures.xcode })
        #expect(xcode.isConfigured)
        #expect(xcode.isProfileDisabled)
        #expect(model.choices.filter(\.isProfileDisabled).map(\.id) == [ShellFixtures.xcode])
        // 足すのは消した Safari だけ
        #expect(model.additionCount == 1)
        model.toggle(ShellFixtures.xcode)
        #expect(model.choices.first { $0.id == ShellFixtures.xcode }?.isSelected == true)

        model.applySelection()
        let configuration = harness.controller.configuration
        #expect(configuration.profile(id: xcodeID)?.isEnabled == false)
        #expect(configuration.profiles.filter { $0.app?.bundleID == ShellFixtures.xcode }.count == 1)
        #expect(configuration.appProfile(forBundleID: ShellFixtures.safari) != nil)
    }

    @Test("あるプロファイルの探し方は addAppProfile と同じ（大文字小文字・前後の空白を区別しない、無効も含む）")
    func profileLookupMatchesConfiguration() throws {
        let (_, harness) = Self.make()
        let xcodeID = try #require(harness.controller.configuration.appProfile(forBundleID: ShellFixtures.xcode)?.id)
        harness.controller.update { $0.updateProfile(id: xcodeID) { $0.isEnabled = false } }
        let profiles = harness.controller.configuration.profiles
        #expect(OnboardingModel.profile(forBundleID: " COM.apple.dt.xcode\n", in: profiles)?.id == xcodeID)
        #expect(OnboardingModel.profile(forBundleID: "", in: profiles) == nil)
        #expect(OnboardingModel.profile(forBundleID: "com.example.none", in: profiles) == nil)
        var configuration = harness.controller.configuration
        #expect(configuration.addAppProfile(for: AppReference(bundleID: " COM.apple.dt.xcode\n", name: "Xcode"), preset: nil) == xcodeID)
    }

    // MARK: - 作り直すのは初回の案内だけ

    @Test("案内の記録: 作り直してよいのは、初回起動で最初に開いた案内だけ")
    func guideHistory() {
        let firstLaunch = OnboardingGuideHistory()
        #expect(!firstLaunch.hasBegunGuide)
        #expect(firstLaunch.beginGuide(isFirstLaunch: true))
        #expect(firstLaunch.hasBegunGuide)
        #expect(!firstLaunch.beginGuide(isFirstLaunch: true))
        #expect(!firstLaunch.beginGuide(isFirstLaunch: true))

        let relaunched = OnboardingGuideHistory()
        #expect(!relaunched.beginGuide(isFirstLaunch: false))
        #expect(relaunched.hasBegunGuide)
    }

    @Test("初回の案内を閉じた後に同じプロセスで開き直した案内は、作り直さない（その間に作ったプロファイルと編集が残る）",
          arguments: ShellFirstGuideEnding.allCases)
    func reopenedGuideKeepsEdits(ending: ShellFirstGuideEnding) throws {
        let harness = ShellControllerHarness(installed: Self.installed)
        harness.controller.start()
        #expect(harness.controller.isFirstLaunch)
        let history = OnboardingGuideHistory()
        var finished = 0
        let first = OnboardingWindowController(controller: harness.controller, services: harness.services, history: history) {
            finished += 1
        }
        #expect(first.model.replacesProfiles)
        switch ending {
        case .closedAtWelcome:
            break
        case .skipped:
            first.model.next()
            first.model.skipSelection()
        case .applied:
            first.model.next()
            first.model.applySelection()
        }
        first.windowDidClose()
        #expect(finished == 1)
        #expect(!harness.controller.isPracticeMode)

        // 設定で、自分のアプリのプロファイルを作り、Xcode とグローバルを編集し、Safari を消す
        let customID = try Self.editProfilesInSettings(harness)
        let edited = harness.controller.configuration
        // isFirstLaunch はこのプロセスの間 true のまま
        #expect(harness.controller.isFirstLaunch)

        let second = OnboardingWindowController(controller: harness.controller, services: harness.services, history: history) {}
        #expect(!second.model.isFirstLaunchGuide)
        #expect(!second.model.replacesProfiles)
        second.model.next()
        #expect(second.model.choices.first { $0.id == ShellFixtures.xcode }?.isConfigured == true)
        #expect(second.model.additionCount == 1)
        second.model.applySelection()
        second.windowDidClose()

        let configuration = harness.controller.configuration
        try Self.expectEditsSurvived(configuration, edited: edited, customID: customID)
        // 消した Safari だけが足される
        #expect(configuration.appProfile(forBundleID: ShellFixtures.safari) != nil)
        #expect(configuration.profiles.count == edited.profiles.count + 1)
        // 保存された設定にも残っている
        let saved = try #require(try ConfigurationStore(directory: harness.directory).load())
        try Self.expectEditsSurvived(saved, edited: edited, customID: customID)
    }

    @Test("初回の案内で作り直した後に設定で編集したら、戻って「次へ」を押し直しても作り直さない")
    func reapplyAfterEditKeepsEdits() throws {
        let (model, harness) = Self.make()
        model.next()
        model.applySelection()
        #expect(model.step == .practice)

        let customID = try Self.editProfilesInSettings(harness)
        let edited = harness.controller.configuration
        model.back()
        #expect(model.step == .apps)
        #expect(!model.replacesProfiles)
        #expect(model.choices.first { $0.id == ShellFixtures.xcode }?.isConfigured == true)
        model.next()
        #expect(model.step == .practice)
        try Self.expectEditsSurvived(harness.controller.configuration, edited: edited, customID: customID)
    }

    @Test("初回の案内で作り直した後、何も編集していなければ戻って選び直せる")
    func reselectWithoutEdits() {
        let (model, harness) = Self.make()
        model.next()
        model.applySelection()
        model.back()
        #expect(model.replacesProfiles)
        #expect(model.choices.allSatisfy { !$0.isConfigured })
        model.toggle(ShellFixtures.safari)
        model.applySelection()
        let configuration = harness.controller.configuration
        #expect(configuration.appProfile(forBundleID: ShellFixtures.safari) == nil)
        #expect(configuration.appProfile(forBundleID: ShellFixtures.xcode) != nil)
    }

    @Test("初回の案内を開いたまま設定でプロファイルを編集したら、「次へ」は足すだけ")
    func editWhileFirstGuideOpen() throws {
        let (model, harness) = Self.make()
        model.next()
        #expect(model.replacesProfiles)
        #expect(model.choices.allSatisfy { !$0.isConfigured })
        model.setAllSelected(false)

        let customID = try Self.editProfilesInSettings(harness)
        let edited = harness.controller.configuration
        #expect(!model.replacesProfiles)
        // 選び直せるのは、プロファイルの無い（消した）Safari だけ。外したままなので足さない
        #expect(model.choices.filter { !$0.isConfigured }.map(\.id) == [ShellFixtures.safari])
        #expect(model.additionCount == 0)
        model.applySelection()
        #expect(harness.controller.configuration == edited)
        try Self.expectEditsSurvived(harness.controller.configuration, edited: edited, customID: customID)
    }

    @Test("保存した設定があって起動したときは、最初に開いた案内でも作り直さない")
    func notFirstLaunchNeverReplaces() {
        let harness = ShellControllerHarness(installed: Self.installed)
        harness.controller.start()
        let relaunched = NonetController(
            services: harness.services,
            store: ConfigurationStore(directory: harness.directory),
            hud: ShellFakeHUD(),
            license: harness.license
        )
        relaunched.start()
        #expect(!relaunched.isFirstLaunch)
        let window = OnboardingWindowController(controller: relaunched, services: harness.services, history: OnboardingGuideHistory()) {}
        #expect(!window.model.replacesProfiles)
        window.windowDidClose()
    }

    /// 設定画面での編集の代わり。自分のアプリのプロファイルを作り、Xcode とグローバルのマスを変え、Safari を消す
    static func editProfilesInSettings(_ harness: ShellControllerHarness) throws -> UUID {
        let configuration = harness.controller.configuration
        let xcodeID = try #require(configuration.appProfile(forBundleID: ShellFixtures.xcode)?.id)
        let safariID = try #require(configuration.appProfile(forBundleID: ShellFixtures.safari)?.id)
        var customID: UUID?
        harness.controller.update { configuration in
            let id = configuration.addAppProfile(for: AppReference(bundleID: "com.example.Custom", name: "Custom"), preset: nil)
            customID = id
            let custom = Cell(title: "自分のマス", icon: .symbol("star"), action: .openURL(URLAction(url: "https://example.com")))
            configuration.setCell(custom, at: CellAddress(page: 0, index: 4), profileID: id)
            configuration.setCell(nil, at: CellAddress(page: 0, index: 0), profileID: xcodeID)
            let launcher = Cell(title: "ランチャーのマス", icon: .symbol("bolt"), action: .openURL(URLAction(url: "https://example.org")))
            configuration.setCell(launcher, at: CellAddress(page: 0, index: 8), profileID: configuration.globalProfile.id)
            configuration.removeProfile(id: safariID)
        }
        return try #require(customID)
    }

    static func expectEditsSurvived(_ configuration: NonetConfiguration, edited: NonetConfiguration, customID: UUID) throws {
        let custom = try #require(configuration.appProfile(forBundleID: "com.example.Custom"))
        #expect(custom.id == customID)
        #expect(custom == edited.profile(id: customID))
        #expect(custom.pages[0].cells[4]?.title == "自分のマス")
        let xcode = configuration.appProfile(forBundleID: ShellFixtures.xcode)
        #expect(xcode != nil)
        #expect(xcode == edited.appProfile(forBundleID: ShellFixtures.xcode))
        #expect(xcode?.pages[0].cells[0] == nil)
        #expect(configuration.globalProfile == edited.globalProfile)
        #expect(configuration.globalProfile.pages[0].cells[8]?.title == "ランチャーのマス")
    }

    @Test("プリセットのあるアプリが無ければ、選ぶものは空")
    func noPresetApps() {
        let (model, harness) = Self.make(installed: ["com.example.unknown"])
        #expect(model.choices.isEmpty)
        model.next()
        model.applySelection()
        #expect(harness.controller.configuration.profiles.count == 1)
        #expect(model.step == .practice)
    }

    // MARK: - 練習

    @Test("練習の画面の間だけ練習モード。どの離れ方でも必ず戻す")
    func practiceModeLifecycle() {
        let (model, harness) = Self.make()
        #expect(!harness.controller.isPracticeMode)
        model.next()
        model.skipSelection()
        #expect(model.step == .practice)
        #expect(harness.controller.isPracticeMode)

        model.back()
        #expect(model.step == .apps)
        #expect(!harness.controller.isPracticeMode)

        model.applySelection()
        #expect(harness.controller.isPracticeMode)
        model.next()
        #expect(model.step == .done)
        #expect(!harness.controller.isPracticeMode)

        model.back()
        #expect(model.step == .practice)
        #expect(harness.controller.isPracticeMode)
        model.close()
        #expect(!harness.controller.isPracticeMode)
    }

    @Test("ウィンドウが隠れている間は練習モードにせず、その間の実行は数えない")
    func practiceFollowsWindowVisibility() {
        let clock = Clock()
        let (model, harness) = Self.make(clock: clock)
        model.next()
        model.skipSelection()
        #expect(harness.controller.isPracticeMode)

        model.setWindowVisible(false)
        #expect(!harness.controller.isPracticeMode)
        // 隠れている間の実行は本物なので練習に数えない
        model.handleExecution(ShellFixtures.record(index: 2, date: clock.now.addingTimeInterval(1)))
        #expect(model.practice == .waiting)

        clock.now = clock.now.addingTimeInterval(10)
        model.setWindowVisible(true)
        #expect(harness.controller.isPracticeMode)
        // 見えるようになる前の記録も数えない
        model.handleExecution(ShellFixtures.record(index: 2, date: clock.now.addingTimeInterval(-2)))
        #expect(model.practice == .waiting)
        model.handleExecution(ShellFixtures.record(index: 2, date: clock.now.addingTimeInterval(1)))
        #expect(model.practice == .succeeded)
    }

    @Test("隠れたまま練習の画面に入っても練習モードにしない。ほかの画面では見え方で練習モードを変えない")
    func hiddenWindowEntersPractice() {
        let (model, harness) = Self.make()
        model.setWindowVisible(false)
        #expect(!harness.controller.isPracticeMode)
        model.next()
        model.skipSelection()
        #expect(model.step == .practice)
        #expect(!harness.controller.isPracticeMode)
        model.setWindowVisible(true)
        #expect(harness.controller.isPracticeMode)
        model.next()
        model.setWindowVisible(false)
        model.setWindowVisible(true)
        #expect(!harness.controller.isPracticeMode)
    }

    @Test("見えていても、ほかのアプリを使っている（キーでない）間は練習モードにせず、その間の実行は数えない")
    func practiceRequiresKeyWindow() {
        let clock = Clock()
        let (model, harness) = Self.make(clock: clock)
        model.next()
        model.skipSelection()
        #expect(harness.controller.isPracticeMode)

        // Safari に切り替えた。ウィンドウの一部はまだ見えている
        model.setWindowKey(false)
        #expect(model.isWindowVisible)
        #expect(!model.isWindowAttended)
        #expect(!harness.controller.isPracticeMode)
        // その間に右上を押したのは本物の実行なので、練習の成功にしない
        model.handleExecution(ShellFixtures.record(index: 2, date: clock.now.addingTimeInterval(1)))
        #expect(model.practice == .waiting)

        clock.now = clock.now.addingTimeInterval(10)
        model.setWindowKey(true)
        #expect(harness.controller.isPracticeMode)
        // 戻る前の記録は数えない
        model.handleExecution(ShellFixtures.record(index: 2, date: clock.now.addingTimeInterval(-2)))
        #expect(model.practice == .waiting)
        model.handleExecution(ShellFixtures.record(index: 2, date: clock.now.addingTimeInterval(1)))
        #expect(model.practice == .succeeded)
    }

    @Test("キーでないまま練習の画面に入っても練習モードにしない。見えていてキーのときだけ練習モード")
    func practiceNeedsVisibleAndKey() {
        let (model, harness) = Self.make()
        model.setWindowKey(false)
        model.next()
        model.skipSelection()
        #expect(model.step == .practice)
        #expect(!harness.controller.isPracticeMode)

        model.setWindowVisible(false)
        model.setWindowKey(true)
        #expect(!harness.controller.isPracticeMode)
        model.setWindowVisible(true)
        #expect(harness.controller.isPracticeMode)
        model.setWindowKey(true)
        #expect(harness.controller.isPracticeMode)

        // ほかの画面では、キーかどうかで練習モードを変えない
        model.next()
        model.setWindowKey(false)
        model.setWindowKey(true)
        #expect(!harness.controller.isPracticeMode)
    }

    @Test("ウィンドウを閉じたら、練習の画面でなくても練習モードを戻す")
    func closeResetsPractice() {
        let (model, harness) = Self.make()
        harness.controller.isPracticeMode = true
        model.close()
        #expect(!harness.controller.isPracticeMode)
    }

    @Test("練習の案内は設定のトリガーキーで出す")
    func practiceInstructionUsesTrigger() {
        let (model, harness) = Self.make()
        harness.controller.update { $0.settings.trigger = .rightOption }
        #expect(model.trigger == .rightOption)
        #expect(ShellText.practiceInstruction(model.trigger) == "右⌥を押しながら、トラックパッドの右上をタップ")
    }

    @Test("右上（どのページでも）を押したら成功。練習を始めた後の記録だけを数える")
    func practiceSuccess() {
        let clock = Clock()
        let (model, _) = Self.make(clock: clock)
        model.next()
        model.skipSelection()
        let started = clock.now

        // 練習を始める前の記録は数えない
        model.handleExecution(ShellFixtures.record(index: 2, date: started.addingTimeInterval(-1)))
        #expect(model.practice == .waiting)

        model.handleExecution(ShellFixtures.record(index: 0, date: started.addingTimeInterval(1)))
        #expect(model.practice == .wrongCell(0))

        model.handleExecution(ShellFixtures.record(index: 2, page: 1, date: started.addingTimeInterval(2)))
        #expect(model.practice == .succeeded)

        // 成功の後に違うマスを押しても成功のまま
        model.handleExecution(ShellFixtures.record(index: 7, date: started.addingTimeInterval(3)))
        #expect(model.practice == .succeeded)
    }

    @Test("練習の画面を開いたときにすでにあった記録は、時刻が後でも数えない")
    func practiceIgnoresBaseline() async {
        let clock = Clock()
        let (model, harness) = Self.make(clock: clock)
        // テスト実行の記録を lastExecution に残しておく（右上のマス）
        let cell = Cell(title: "右上", icon: .symbol("star"), action: .openURL(URLAction(url: "example.com")))
        let global = harness.controller.configuration.globalProfile.id
        harness.controller.update { $0.setCell(cell, at: CellAddress(page: 0, index: 2), profileID: global) }
        clock.now = Date().addingTimeInterval(-60)
        _ = await harness.controller.testRun(cell, profileID: global)
        // テスト実行を lastExecution に残さないコントローラーなら、この確かめ方はできない
        guard let existing = harness.controller.lastExecution else { return }

        model.next()
        model.skipSelection()
        model.handleExecution(existing)
        #expect(model.practice == .waiting)
    }

    @Test("練習の画面の外では記録を数えない。nil は無視する")
    func executionOutsidePractice() {
        let clock = Clock()
        let (model, _) = Self.make(clock: clock)
        model.handleExecution(ShellFixtures.record(index: 2, date: clock.now.addingTimeInterval(5)))
        model.next()
        model.skipSelection()
        #expect(model.practice == .waiting)
        model.handleExecution(nil)
        #expect(model.practice == .waiting)
    }

    @Test("練習の画面に入り直したら、やり直し")
    func practiceRestart() {
        let clock = Clock()
        let (model, _) = Self.make(clock: clock)
        model.next()
        model.skipSelection()
        model.handleExecution(ShellFixtures.record(index: 2, date: clock.now.addingTimeInterval(1)))
        #expect(model.practice == .succeeded)
        model.back()
        clock.now = clock.now.addingTimeInterval(10)
        model.skipSelection()
        #expect(model.practice == .waiting)
        // 入り直す前の記録は数えない
        model.handleExecution(ShellFixtures.record(index: 2, date: clock.now.addingTimeInterval(-5)))
        #expect(model.practice == .waiting)
    }

    @Test("練習できない理由: 無効にしている")
    func practiceBlockers() {
        let (model, harness) = Self.make()
        #expect(model.practiceBlocker == nil)
        harness.controller.update { $0.settings.isEnabled = false }
        #expect(model.practiceBlocker == .disabled)
        #expect(model.practiceBlocker?.message == "Nonet が無効になっています。有効にすると試せます")
        #expect(!harness.controller.configuration.settings.isEnabled)
        model.enableNonet()
        #expect(harness.controller.configuration.settings.isEnabled)
        #expect(model.practiceBlocker == nil)
    }

    @Test("無効で許可も無いときは「無効」の知らせと「有効にする」。有効にしたら許可の知らせと「システム設定を開く」")
    func practiceBlockerTextAndActionAgree() throws {
        let (model, harness) = Self.make(granted: false)
        model.next()
        model.skipSelection()
        harness.controller.update { $0.settings.isEnabled = false }
        #expect(!model.isAccessibilityGranted)
        let disabled = try #require(model.practiceBlocker)
        #expect(disabled == .disabled)
        #expect(disabled.message == "Nonet が無効になっています。有効にすると試せます")
        #expect(disabled.remedy == .enableNonet)
        #expect(disabled.remedy?.title == "有効にする")

        model.resolve(.enableNonet)
        #expect(harness.controller.configuration.settings.isEnabled)
        #expect(harness.permissions.requestCount == 0)
        let needsAccessibility = model.practiceBlocker
        #expect(needsAccessibility == .needsAccessibility)
        #expect(needsAccessibility?.remedy == .openAccessibilitySettings)
        #expect(needsAccessibility?.remedy?.title == "システム設定を開く")

        model.resolve(.openAccessibilitySettings)
        #expect(harness.permissions.requestCount == 1)
        #expect(harness.permissions.openSettingsCount == 1)
        harness.permissions.isAccessibilityGranted = true
        model.pollPermission()
        #expect(model.practiceBlocker == nil)
    }

    @Test("練習できない理由ごとの知らせと、その場で直す方法", arguments: [
        (OnboardingPracticeBlocker.disabled, OnboardingPracticeRemedy?.some(.enableNonet)),
        (.needsAccessibility, .openAccessibilitySettings),
        (.noTrackpad, nil),
        (.secureInput, nil),
    ])
    func practiceBlockerRemedies(blocker: OnboardingPracticeBlocker, remedy: OnboardingPracticeRemedy?) {
        #expect(!blocker.message.isEmpty)
        #expect(blocker.remedy == remedy)
    }

    // MARK: - 進む・戻る

    @Test("ステップの順と戻る")
    func stepOrder() {
        let (model, _) = Self.make()
        #expect(OnboardingStep.allCases == [.welcome, .apps, .practice, .done])
        model.back()
        #expect(model.step == .welcome)
        model.next()
        #expect(model.step == .apps)
        model.back()
        #expect(model.step == .welcome)
        model.next()
        model.next()
        #expect(model.step == .practice)
        model.next()
        #expect(model.step == .done)
        model.next()
        #expect(model.step == .done)
    }
}
