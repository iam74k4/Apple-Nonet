// 担当: ui-shell
import Foundation
import NonetCore
@testable import NonetUI
import Testing

/// 初回の案内をどう終えたか
enum ShellFirstGuideEnding: String, CaseIterable, Sendable {
    /// ようこそのまま閉じた
    case closedAtWelcome
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

    /// 読み上げと、少し後に行うことを、テストから見られるようにしたもの
    final class Recorder {
        var announcements: [String] = []
        var scheduled: [(delay: TimeInterval, action: @MainActor () -> Void)] = []

        @MainActor
        func runScheduled() {
            let actions = scheduled
            scheduled = []
            for item in actions {
                item.action()
            }
        }
    }

    static func make(
        installed: Set<String> = installed,
        granted: Bool = true,
        isFirstLaunchGuide: Bool = true,
        clock: Clock = Clock(),
        license: LicenseManager? = nil,
        frontmost: RunningAppInfo? = nil,
        recorder: Recorder = Recorder()
    ) -> (OnboardingModel, ShellControllerHarness) {
        let harness = ShellControllerHarness(installed: installed, accessibilityGranted: granted, license: license)
        harness.frontmost.current = frontmost
        harness.controller.start()
        let model = OnboardingModel(
            controller: harness.controller,
            license: harness.license,
            permissions: harness.permissions,
            installedApps: harness.installedApps,
            frontmostApp: harness.frontmost,
            touchSource: harness.touchSource,
            loginItem: harness.loginItem,
            isFirstLaunchGuide: isFirstLaunchGuide,
            now: { clock.now }
        )
        model.announce = { recorder.announcements.append($0) }
        model.scheduleAfter = { delay, action in recorder.scheduled.append((delay, action)) }
        return (model, harness)
    }

    /// 練習の画面まで進める
    static func enterPractice(_ model: OnboardingModel) {
        model.next()
        model.applySelection()
    }

    /// 開いて目標のマスで離した記録（1つ目の課題）
    static func runRecord(_ model: OnboardingModel, date: Date) throws -> ExecutionRecord {
        let target = try #require(model.practicePage).runTarget
        return ShellFixtures.record(index: target.index, date: date, title: target.title)
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
        model.applySelection()
        #expect(model.step == .practice)
        #expect(model.practiceBlocker == .needsAccessibility)
        #expect(model.practiceBlocker?.message == L10n.ui("アクセシビリティが許可されていないため、まだ試せません"))
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

    @Test("許可されたときだけ true を返す（ウィンドウを前に出す合図）")
    func pollPermissionReportsGrant() {
        let (model, harness) = Self.make(granted: false)
        #expect(!model.pollPermission())
        harness.permissions.isAccessibilityGranted = true
        #expect(model.pollPermission())
        #expect(!model.pollPermission())
        harness.permissions.isAccessibilityGranted = false
        #expect(!model.pollPermission())
    }

    @Test("許可されたら、システム設定の後ろに隠れた案内のウィンドウを前に出す（どの画面でも）")
    func raisesWindowWhenGranted() {
        let harness = ShellControllerHarness(installed: Self.installed, accessibilityGranted: false)
        harness.controller.start()
        let window = OnboardingWindowController(controller: harness.controller, services: harness.services, history: OnboardingGuideHistory()) {}
        var raised = 0
        window.raiseWindow = { raised += 1 }
        window.checkPermission()
        #expect(raised == 0)
        harness.permissions.isAccessibilityGranted = true
        window.checkPermission()
        #expect(raised == 1)
        #expect(window.model.step == .apps)
        window.checkPermission()
        #expect(raised == 1)

        // 練習の画面で「システム設定を開く」から許可したときも
        harness.permissions.isAccessibilityGranted = false
        window.checkPermission()
        window.model.applySelection()
        harness.permissions.isAccessibilityGranted = true
        window.checkPermission()
        #expect(raised == 2)
        #expect(window.model.step == .practice)
        window.windowDidClose()
    }

    @Test("「システム設定を開く」: 1回目は macOS の確認だけ（確認に移ればシステム設定は開かない）。2回目からはシステム設定だけ")
    func requestAccessibility() {
        let recorder = Recorder()
        let (model, harness) = Self.make(granted: false, recorder: recorder)
        model.requestAccessibility()
        #expect(harness.permissions.requestCount == 1)
        #expect(harness.permissions.openSettingsCount == 0)
        // macOS の確認が前に出て、案内のウィンドウはキーでなくなった
        model.setWindowKey(false)
        #expect(recorder.scheduled.map(\.delay) == [OnboardingModel.promptFallbackDelay])
        recorder.runScheduled()
        #expect(harness.permissions.openSettingsCount == 0)

        model.setWindowKey(true)
        model.requestAccessibility()
        #expect(harness.permissions.requestCount == 1)
        #expect(harness.permissions.openSettingsCount == 1)
        #expect(recorder.scheduled.isEmpty)
    }

    @Test("前に確認を出したことがあって macOS が確認を出さなければ（ウィンドウがキーのまま）、少し後にシステム設定だけを開く")
    func requestAccessibilityFallsBackToSettings() {
        let recorder = Recorder()
        let (model, harness) = Self.make(granted: false, recorder: recorder)
        model.requestAccessibility()
        #expect(harness.permissions.openSettingsCount == 0)
        recorder.runScheduled()
        #expect(harness.permissions.requestCount == 1)
        #expect(harness.permissions.openSettingsCount == 1)

        // その間に許可されていれば開かない
        let (granted, grantedHarness) = Self.make(granted: false, recorder: recorder)
        granted.requestAccessibility()
        grantedHarness.permissions.isAccessibilityGranted = true
        recorder.runScheduled()
        #expect(grantedHarness.permissions.openSettingsCount == 0)
    }

    @Test("許可されたら VoiceOver に知らせる（最初の画面では次へ進むことも）")
    func announcesPermission() {
        let recorder = Recorder()
        let (model, harness) = Self.make(granted: false, recorder: recorder)
        harness.permissions.isAccessibilityGranted = true
        model.pollPermission()
        #expect(recorder.announcements == [L10n.ui("アクセシビリティが許可されました。次へ進みます。")])

        harness.permissions.isAccessibilityGranted = false
        model.pollPermission()
        harness.permissions.isAccessibilityGranted = true
        model.pollPermission()
        #expect(model.step == .apps)
        #expect(recorder.announcements.last == L10n.ui("アクセシビリティが許可されました"))
    }

    @Test("トラックパッドが無ければ最初の画面で知らせ、「もう一度確かめる」で探し直す。許可を待つ間も探し直す")
    func welcomeTrackpadCheck() {
        let harness = ShellControllerHarness(installed: Self.installed, accessibilityGranted: false)
        harness.touchSource.isAvailable = false
        harness.controller.start()
        let model = OnboardingModel(
            controller: harness.controller,
            permissions: harness.permissions,
            installedApps: harness.installedApps,
            touchSource: harness.touchSource,
            isFirstLaunchGuide: true
        )
        #expect(model.isTrackpadMissing)
        #expect(OnboardingModel.noTrackpadMessage
            == L10n.ui("トラックパッドが見つかりません。Magic Trackpad の電源を入れてつなぐと、自動で見つけます（10秒ほど）。"))
        model.recheckTrackpad()
        #expect(model.isTrackpadMissing)
        harness.touchSource.isAvailable = true
        model.recheckTrackpad()
        #expect(!model.isTrackpadMissing)

        harness.touchSource.isAvailable = false
        model.recheckTrackpad()
        harness.touchSource.isAvailable = true
        model.pollPermission()
        #expect(!model.isTrackpadMissing)

        // touchSource を渡さなければ確かめない
        let unchecked = OnboardingModel(
            controller: harness.controller,
            permissions: harness.permissions,
            installedApps: harness.installedApps,
            isFirstLaunchGuide: false
        )
        #expect(!unchecked.isTrackpadMissing)
    }

    @Test("ようこその説明は、上の縁から指を滑らせることを言う")
    func welcomeSubtitleSaysHowToOpen() {
        #expect(ShellText.welcomeSubtitle == L10n.ui("トラックパッドの上の縁から指を滑らせると、トラックパッドがアプリごとに変わる9つのボタンになります"))
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
            configuration.settings.hudScale = .large
            configuration.settings.hudPosition = .nearCursor
            configuration.settings.haptics = .strong
            configuration.settings.cursorLock = .dropEvents
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

    @Test("選び直さずに「次へ」を押すと、おすすめ（並んだアプリすべて）のまま使う（飛ばすボタンは無い）")
    func nextKeepsSuggestions() {
        let (model, harness) = Self.make()
        let suggested = Set(harness.controller.configuration.profiles.compactMap(\.app?.bundleID))
        model.next()
        #expect(model.choices.allSatisfy { $0.isSelected })
        model.applySelection()
        #expect(model.step == .practice)
        #expect(Set(harness.controller.configuration.profiles.compactMap(\.app?.bundleID)) == suggested)
        #expect(Set(model.choices.map(\.id)) == suggested)
    }

    @Test("「アプリを選ぶ」以外の画面では反映しない")
    func applyOnlyOnAppsStep() {
        let (model, harness) = Self.make()
        let before = harness.controller.configuration
        model.applySelection()
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
            configuration.settings.haptics = .off
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
        #expect(configuration.settings.haptics == .off)
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
        harness.flushSaves()
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

    @Test("初回の案内を開いたまま設定で共通マスを作っても、プロファイルを作り直すときに捨てない")
    func sharedCellsSurviveReplacingProfiles() throws {
        let (model, harness) = Self.make()
        model.next()
        #expect(model.replacesProfiles)
        var configuration = harness.controller.configuration
        let cell = Cell(title: "共通", icon: .symbol("star"), action: .keystroke(.key("b", .command)))
        configuration.setSharedCell(cell, at: 8)
        harness.controller.replaceConfiguration(configuration)
        // プロファイルは変えていないので、まだ作り直す
        #expect(model.replacesProfiles)
        model.applySelection()
        #expect(harness.controller.configuration.sharedCells[8]?.title == "共通")
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
            license: harness.license,
            guidance: MemoryHUDGuidanceStore()
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
        Self.enterPractice(model)
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
    func practiceFollowsWindowVisibility() throws {
        let clock = Clock()
        let (model, harness) = Self.make(clock: clock)
        Self.enterPractice(model)
        #expect(harness.controller.isPracticeMode)

        model.setWindowVisible(false)
        #expect(!harness.controller.isPracticeMode)
        // 隠れている間の実行は本物なので練習に数えない
        model.handleExecution(try Self.runRecord(model, date: clock.now.addingTimeInterval(1)))
        #expect(model.practice == .run)

        clock.now = clock.now.addingTimeInterval(10)
        model.setWindowVisible(true)
        #expect(harness.controller.isPracticeMode)
        // 見えるようになる前の記録も数えない
        model.handleExecution(try Self.runRecord(model, date: clock.now.addingTimeInterval(-2)))
        #expect(model.practice == .run)
        model.handleExecution(try Self.runRecord(model, date: clock.now.addingTimeInterval(1)))
        #expect(model.practice == .cancel)
    }

    @Test("隠れたまま練習の画面に入っても練習モードにしない。ほかの画面では見え方で練習モードを変えない")
    func hiddenWindowEntersPractice() {
        let (model, harness) = Self.make()
        model.setWindowVisible(false)
        #expect(!harness.controller.isPracticeMode)
        Self.enterPractice(model)
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
    func practiceRequiresKeyWindow() throws {
        let clock = Clock()
        let (model, harness) = Self.make(clock: clock)
        Self.enterPractice(model)
        #expect(harness.controller.isPracticeMode)

        // Safari に切り替えた。ウィンドウの一部はまだ見えている
        model.setWindowKey(false)
        #expect(model.isWindowVisible)
        #expect(!model.isWindowAttended)
        #expect(!harness.controller.isPracticeMode)
        // その間に目標のマスを実行したのは本物なので、練習の成功にしない
        model.handleExecution(try Self.runRecord(model, date: clock.now.addingTimeInterval(1)))
        #expect(model.practice == .run)

        clock.now = clock.now.addingTimeInterval(10)
        model.setWindowKey(true)
        #expect(harness.controller.isPracticeMode)
        // 戻る前の記録は数えない
        model.handleExecution(try Self.runRecord(model, date: clock.now.addingTimeInterval(-2)))
        #expect(model.practice == .run)
        model.handleExecution(try Self.runRecord(model, date: clock.now.addingTimeInterval(1)))
        #expect(model.practice == .cancel)
    }

    @Test("キーでないまま練習の画面に入っても練習モードにしない。見えていてキーのときだけ練習モード")
    func practiceNeedsVisibleAndKey() {
        let (model, harness) = Self.make()
        model.setWindowKey(false)
        Self.enterPractice(model)
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

    @Test("練習の目標は、HUD に出る前面のアプリのプロファイルの本物のボタン（中央から）")
    func practiceTargetsComeFromTheFrontApp() throws {
        let (model, harness) = Self.make(frontmost: ShellFixtures.running(ShellFixtures.xcode, name: "Xcode"))
        Self.enterPractice(model)
        let xcode = try #require(harness.controller.configuration.appProfile(forBundleID: ShellFixtures.xcode))
        let page = try #require(model.practicePage)
        #expect(page.profileName == xcode.name)
        #expect(page.titles == xcode.pages[0].cells.map { $0?.title })
        #expect(page.runTarget.title == xcode.pages[0].cells[page.runTarget.index]?.title)

        // 前面のアプリが変われば、そのアプリのページで案内する（プロファイルが無ければグローバル）
        harness.frontmost.current = ShellFixtures.running("com.example.none", name: "None")
        #expect(model.practicePage?.profileName == harness.controller.configuration.globalProfile.name)
        // 前面のアプリが分からなければグローバル
        let (global, globalHarness) = Self.make()
        #expect(global.practicePage?.profileName == globalHarness.controller.configuration.globalProfile.name)
    }

    @Test("目標のマスの選び方: 中身のあるマスから。中央、下の段（左下・右下・下）、左右、上の段の順", arguments: [
        ([0, 2, 6], 6),
        ([0, 4], 4),
        ([8], 8),
        ([1, 3, 7], 7),
        ([2, 5], 5),
    ])
    func practiceTargetChoice(occupied: [Int], run: Int) throws {
        let cells: [Cell?] = (0..<Page.cellCount).map { index in
            occupied.contains(index) ? Cell(title: "マス\(index)", icon: .symbol("star"), action: .openURL(URLAction(url: "example.com"))) : nil
        }
        let page = try #require(OnboardingPracticePage(ResolvedPage(profileID: UUID(), profileName: "P", pageIndex: 0, cells: cells)))
        #expect(page.runTarget == OnboardingPracticeTarget(index: run, title: "マス\(run)"))
        #expect(page.titles.compactMap { $0 }.count == occupied.count)
    }

    /// 少し長く止めてから実行するマス（Cell.requiresHold）は、最初の練習には選ばない（そればかりなら使う）
    @Test func practiceSkipsHoldCells() throws {
        let cells: [Cell?] = (0..<Page.cellCount).map { index in
            guard [0, 4, 6].contains(index) else { return nil }
            return Cell(title: "マス\(index)", icon: .symbol("star"), action: .openURL(URLAction(url: "example.com")), requiresHold: index == 4)
        }
        let page = try #require(OnboardingPracticePage(ResolvedPage(profileID: UUID(), profileName: "P", pageIndex: 0, cells: cells)))
        #expect(page.runTarget.index == 6)
        let onlyHold: [Cell?] = [Cell(title: "A", icon: .symbol("star"), action: .openURL(URLAction(url: "a")), requiresHold: true)]
        let fallback = try #require(OnboardingPracticePage(ResolvedPage(profileID: UUID(), profileName: "P", pageIndex: 0, cells: onlyHold)))
        #expect(fallback.runTarget.index == 0)
    }

    @Test("中身のあるマスが無いページでは練習できない（空きマスは押しても何も記録されない）。「設定を開く」でプロファイルを開く")
    func practiceWithoutButtons() throws {
        #expect(OnboardingPracticePage(nil) == nil)
        #expect(OnboardingPracticePage(ResolvedPage(profileID: UUID(), profileName: "P", pageIndex: 0, cells: Array(repeating: nil, count: 9))) == nil)

        let (model, harness) = Self.make()
        var opened: [SettingsTab] = []
        model.onOpenSettings = { opened.append($0) }
        Self.enterPractice(model)
        let global = harness.controller.configuration.globalProfile.id
        harness.controller.update { configuration in
            for index in 0..<Page.cellCount {
                configuration.setCell(nil, at: CellAddress(page: 0, index: index), profileID: global)
            }
        }
        let blocker = try #require(model.practiceBlocker)
        #expect(blocker == .noButtons)
        #expect(blocker.message == L10n.ui("いま使うページのマスはすべて空いています。設定でマスにアクションを入れると試せます。"))
        #expect(blocker.remedy == .openProfiles)
        #expect(blocker.remedy?.title == L10n.ui("設定を開く"))
        model.resolve(.openProfiles)
        #expect(opened == [.profiles])
    }

    @Test("練習の手順は、上の縁から開いて目標のボタンの名前で離すこと、外枠で離してやめること")
    func practiceInstructionText() throws {
        let (model, _) = Self.make()
        Self.enterPractice(model)
        let page = try #require(model.practicePage)
        let title = page.runTarget.title
        #expect(ShellText.practiceRunInstruction(page.runTarget)
            == L10n.ui("トラックパッドの上の縁に指を置き、そのまま下へ滑らせると HUD（9マスの一覧）が開きます。指を「\(title)」まで滑らせて、そこで離してください。"))
        #expect(ShellText.practiceCancelInstruction
            == L10n.ui("もう一度上の縁から HUD を開き、今度は指を外枠（9マスの外側）まで滑らせてから離してください。何も実行せずに閉じます。"))
        #expect(ShellText.practiceRanInsteadOfCancelling("X")
            == L10n.ui("「\("X")」で離しました。やめるときは、指を外枠まで滑らせてから離してください。"))
        // トラックパッドには「押す」「長押し」と言わない
        for text in [ShellText.practiceRunInstruction(page.runTarget), ShellText.practiceCancelInstruction, ShellText.doneOpenTip, ShellText.doneCancelTip] {
            #expect(!text.contains("長押し"))
        }
    }

    @Test("違うマスの知らせは、押したマスの位置と名前、目標の位置を言う。位置の呼び方（英語は bottom-left）")
    func wrongCellMessage() {
        let bottomLeft = String(localized: "左下", bundle: .nonetUI)
        let topRight = String(localized: "右上", bundle: .nonetUI)
        let target = OnboardingPracticeTarget(index: 2, title: "Safari")
        #expect(ShellText.practiceWrongCell(index: 6, title: "Finder", target: target)
            == L10n.ui("いまのは\(bottomLeft)の「\("Finder")」です。「\("Safari")」は\(topRight)にあります。"))
        #expect(HUDAnnouncement.attributivePositionName(6) == String(localized: "attributivePosition.bottomLeft", defaultValue: "左下", bundle: .nonetUI))
        #expect(HUDAnnouncement.attributivePositionName(0) == String(localized: "attributivePosition.topLeft", defaultValue: "左上", bundle: .nonetUI))
        #expect(HUDAnnouncement.attributivePositionName(2) == String(localized: "attributivePosition.topRight", defaultValue: "右上", bundle: .nonetUI))
        #expect(HUDAnnouncement.attributivePositionName(8) == String(localized: "attributivePosition.bottomRight", defaultValue: "右下", bundle: .nonetUI))
        // 角でなければ読み上げと同じ
        for index in [1, 3, 4, 5, 7] {
            #expect(HUDAnnouncement.attributivePositionName(index) == HUDAnnouncement.positionName(index))
        }
    }

    @Test("練習は2つ: 開いて目標のマスで離す（違うマスは知らせる）→ 外枠で離してやめる（マスを実行したら知らせる）。VoiceOver にも知らせる")
    func practiceTwoTasks() throws {
        let clock = Clock()
        let recorder = Recorder()
        let (model, _) = Self.make(clock: clock, frontmost: ShellFixtures.running(ShellFixtures.xcode, name: "Xcode"), recorder: recorder)
        Self.enterPractice(model)
        let page = try #require(model.practicePage)
        let started = clock.now
        #expect(model.practice == .run)

        // 練習を始める前の記録は数えない
        model.handleExecution(try Self.runRecord(model, date: started.addingTimeInterval(-1)))
        #expect(model.practice == .run)
        #expect(model.practiceFeedback == nil)

        // 1つ目: 違うマス
        let wrong = (0..<Page.cellCount).first { $0 != page.runTarget.index && page.titles[$0] != nil } ?? 0
        model.handleExecution(ShellFixtures.record(index: wrong, date: started.addingTimeInterval(1), title: "違う"))
        #expect(model.practice == .run)
        #expect(model.practiceFeedback == .wrongCell(index: wrong, title: "違う"))
        #expect(recorder.announcements.last == ShellText.practiceWrongCell(index: wrong, title: "違う", target: page.runTarget))
        // まだ1つ目の間は、外枠でやめても進まない
        model.handleCancellation(ShellFixtures.cancellation(date: started.addingTimeInterval(1.5)))
        #expect(model.practice == .run)
        // 何も起きないと壊れて見えるので、実行されなかった理由と、どうすればよいかを知らせる
        #expect(model.practiceFeedback == .notRun(.liftedInFrame, whileCancelling: false))
        #expect(recorder.announcements.last == ShellText.practiceNotRun(.liftedInFrame, target: page.runTarget, whileCancelling: false))

        // 目標のマス（別のページの同じ位置でもよい）
        model.handleExecution(ShellFixtures.record(index: page.runTarget.index, page: 1, date: started.addingTimeInterval(2)))
        #expect(model.practice == .cancel)
        #expect(model.practiceFeedback == nil)
        #expect(recorder.announcements.last == L10n.ui("できました。マスで指を離すと実行します。"))

        // 2つ目: マスで離して実行したら、外枠まで滑らせるよう知らせる
        model.handleExecution(ShellFixtures.record(index: wrong, date: started.addingTimeInterval(3), title: "違う"))
        #expect(model.practice == .cancel)
        #expect(model.practiceFeedback == .ranInsteadOfCancelling(title: "違う"))
        #expect(recorder.announcements.last == ShellText.practiceRanInsteadOfCancelling("違う"))
        // 止める時間が足りずに閉じたのは、やめる操作とは数えない
        model.handleCancellation(ShellFixtures.cancellation(.liftedTooSoon, date: started.addingTimeInterval(4)))
        #expect(model.practice == .cancel)
        #expect(model.practiceFeedback == .notRun(.liftedTooSoon, whileCancelling: true))
        #expect(recorder.announcements.last == ShellText.practiceNotRun(.liftedTooSoon, target: page.runTarget, whileCancelling: true))
        // 外枠で離した
        model.handleCancellation(ShellFixtures.cancellation(date: started.addingTimeInterval(5)))
        #expect(model.practice == .succeeded)
        #expect(model.practiceFeedback == nil)
        #expect(recorder.announcements.last == L10n.ui("できました。迷ったら外枠で離せば、何も実行しません。"))

        // 成功の後に実行しても成功のまま
        model.handleExecution(ShellFixtures.record(index: 7, date: started.addingTimeInterval(6)))
        #expect(model.practice == .succeeded)
        #expect(model.practiceFeedback == nil)
    }

    @Test("練習を始める前・練習の画面の外でやめた記録は数えない。nil は無視する")
    func cancellationsOutsidePractice() throws {
        let clock = Clock()
        let (model, _) = Self.make(clock: clock)
        model.handleCancellation(ShellFixtures.cancellation(date: clock.now.addingTimeInterval(5)))
        Self.enterPractice(model)
        model.handleExecution(try Self.runRecord(model, date: clock.now.addingTimeInterval(1)))
        #expect(model.practice == .cancel)
        model.handleCancellation(ShellFixtures.cancellation(date: clock.now.addingTimeInterval(-1)))
        model.handleCancellation(nil)
        #expect(model.practice == .cancel)
    }

    @Test("試用期間が終わっていれば、ライセンスの知らせと「ライセンスキーを入力…」を出す。登録したら知らせを消す")
    func practiceBlockedForLicense() throws {
        let pair = LicenseSigner.generateKeyPair()
        let signer = try LicenseSigner(privateKeyBase64: pair.privateKeyBase64)
        let key = try signer.sign(LicenseInfo(licenseID: "NONET-SHELL-1", licensee: "Test", email: nil, issuedAt: Date(timeIntervalSince1970: 1_800_000_000)))
        let now = ShellControllerHarness.now
        // 30日前に試用を始めた（期限切れ）。9マスは開かない
        let license = LicenseManager(
            verifier: try LicenseVerifier(publicKeyBase64: pair.publicKeyBase64),
            storage: ShellFakeLicenseStorage(trialStartDate: now.addingTimeInterval(-30 * 24 * 60 * 60)),
            now: { now }
        )
        #expect(license.entitlement == .expired)
        let clock = Clock()
        let (model, _) = Self.make(clock: clock, license: license)
        var opened: [SettingsTab] = []
        model.onOpenSettings = { opened.append($0) }
        Self.enterPractice(model)
        let blocker = try #require(model.practiceBlocker)
        #expect(blocker == .licenseRequired)
        #expect(blocker.message == L10n.ui("試用期間が終了しているため、試せません。ライセンスキーを登録すると試せます。"))
        #expect(blocker.remedy?.title == L10n.ui("ライセンスキーを入力…"))
        model.resolve(.openLicense)
        #expect(opened == [.license])

        // 設定でライセンスキーを登録して戻ってきたら、知らせは出さない
        try license.activate(licenseKey: key)
        #expect(model.practiceBlocker == nil)
        model.handleExecution(try Self.runRecord(model, date: clock.now.addingTimeInterval(2)))
        #expect(model.practice == .cancel)
    }

    @Test("ほかの理由で失敗した記録も成功にしない")
    func failedRecordIsNotSuccess() throws {
        let clock = Clock()
        let (model, _) = Self.make(clock: clock)
        Self.enterPractice(model)
        var record = try Self.runRecord(model, date: clock.now.addingTimeInterval(1))
        record.succeeded = false
        record.message = "失敗"
        model.handleExecution(record)
        #expect(model.practice == .run)
        #expect(model.practiceFeedback == nil)
        #expect(model.practiceBlocker == nil)
    }

    @Test("上の段の印: 許可しないまま進んだら「アクセシビリティ」に済みの印を付けない")
    func stepMarks() {
        func marks(_ current: OnboardingStep, granted: Bool) -> [OnboardingStepMark] {
            [OnboardingStep.welcome, .apps, .practice].map { OnboardingStepMark.mark(for: $0, current: current, isAccessibilityGranted: granted) }
        }
        #expect(marks(.welcome, granted: false) == [.current, .upcoming, .upcoming])
        #expect(marks(.apps, granted: true) == [.done, .current, .upcoming])
        #expect(marks(.apps, granted: false) == [.skipped, .current, .upcoming])
        #expect(marks(.practice, granted: false) == [.skipped, .done, .current])
        #expect(marks(.done, granted: true) == [.done, .done, .done])
    }

    @Test("練習の画面を開いたときにすでにあった記録は、時刻が後でも数えない")
    func practiceIgnoresBaseline() async throws {
        let clock = Clock()
        let (model, harness) = Self.make(clock: clock)
        Self.enterPractice(model)
        let target = try #require(model.practicePage).runTarget
        model.back()
        // テスト実行の記録を lastExecution に残しておく（HUD の目標のマス）
        let global = harness.controller.configuration.globalProfile
        let cell = try #require(global.pages[0].cells[target.index])
        clock.now = Date().addingTimeInterval(-60)
        _ = await harness.controller.testRun(cell, profileID: global.id)
        // テスト実行を lastExecution に残さないコントローラーなら、この確かめ方はできない
        guard let existing = harness.controller.lastExecution else { return }

        model.applySelection()
        model.handleExecution(existing)
        #expect(model.practice == .run)
    }

    @Test("練習の画面の外では記録を数えない。nil は無視する")
    func executionOutsidePractice() throws {
        let clock = Clock()
        let (model, _) = Self.make(clock: clock)
        model.handleExecution(ShellFixtures.record(index: 2, date: clock.now.addingTimeInterval(5)))
        Self.enterPractice(model)
        #expect(model.practice == .run)
        model.handleExecution(nil)
        #expect(model.practice == .run)
    }

    @Test("練習の画面に入り直したら、やり直し")
    func practiceRestart() throws {
        let clock = Clock()
        let (model, _) = Self.make(clock: clock)
        Self.enterPractice(model)
        model.handleExecution(try Self.runRecord(model, date: clock.now.addingTimeInterval(1)))
        model.handleCancellation(ShellFixtures.cancellation(date: clock.now.addingTimeInterval(2)))
        #expect(model.practice == .succeeded)
        model.back()
        clock.now = clock.now.addingTimeInterval(10)
        model.applySelection()
        #expect(model.practice == .run)
        #expect(model.practiceFeedback == nil)
        // 入り直す前の記録は数えない
        model.handleExecution(try Self.runRecord(model, date: clock.now.addingTimeInterval(-5)))
        #expect(model.practice == .run)
    }

    @Test("練習できない理由: 無効にしている")
    func practiceBlockers() {
        let (model, harness) = Self.make()
        #expect(model.practiceBlocker == nil)
        harness.controller.update { $0.settings.isEnabled = false }
        #expect(model.practiceBlocker == .disabled)
        #expect(model.practiceBlocker?.message == L10n.ui("Nonet が無効になっています。有効にすると試せます。"))
        #expect(!harness.controller.configuration.settings.isEnabled)
        model.enableNonet()
        #expect(harness.controller.configuration.settings.isEnabled)
        #expect(model.practiceBlocker == nil)
    }

    @Test("トラックパッドが無ければ、見つけ方の知らせと「もう一度確かめる」。つないで確かめ直したら練習できる")
    func practiceNoTrackpad() throws {
        let (model, harness) = Self.make()
        Self.enterPractice(model)
        harness.touchSource.isAvailable = false
        harness.controller.refreshPermissions()
        let blocker = try #require(model.practiceBlocker)
        #expect(blocker == .noTrackpad)
        #expect(blocker.message == L10n.ui("トラックパッドが見つかりません。Magic Trackpad の電源を入れてつなぐと、自動で見つけます（10秒ほど）。"))
        #expect(blocker.remedy == .recheck)
        #expect(blocker.remedy?.title == L10n.ui("もう一度確かめる"))
        harness.touchSource.isAvailable = true
        model.resolve(.recheck)
        #expect(model.practiceBlocker == nil)
    }

    @Test("無効で許可も無いときは「無効」の知らせと「有効にする」。有効にしたら許可の知らせと「システム設定を開く」")
    func practiceBlockerTextAndActionAgree() throws {
        let (model, harness) = Self.make(granted: false)
        Self.enterPractice(model)
        harness.controller.update { $0.settings.isEnabled = false }
        #expect(!model.isAccessibilityGranted)
        let disabled = try #require(model.practiceBlocker)
        #expect(disabled == .disabled)
        #expect(disabled.message == L10n.ui("Nonet が無効になっています。有効にすると試せます。"))
        #expect(disabled.remedy == .enableNonet)
        #expect(disabled.remedy?.title == L10n.ui("Nonet を有効にする"))

        model.resolve(.enableNonet)
        #expect(harness.controller.configuration.settings.isEnabled)
        #expect(harness.permissions.requestCount == 0)
        let needsAccessibility = model.practiceBlocker
        #expect(needsAccessibility == .needsAccessibility)
        #expect(needsAccessibility?.remedy == .openAccessibilitySettings)
        #expect(needsAccessibility?.remedy?.title == L10n.ui("システム設定を開く"))

        // 1回目は macOS の確認だけ。2回目はシステム設定だけ
        model.resolve(.openAccessibilitySettings)
        #expect(harness.permissions.requestCount == 1)
        #expect(harness.permissions.openSettingsCount == 0)
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
        (.noTrackpad, .recheck),
        (.secureInput, nil),
        (.noButtons, .openProfiles),
        (.licenseRequired, .openLicense),
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

@Suite("練習の案内の言い方")
struct ShellPracticeTextTests {
    @Test("少し長く止めるマスを練習に使うときは、止め方も案内する")
    func aHoldTargetExplainsHowToHold() {
        let plain = OnboardingPracticeTarget(index: 4, title: "Safari")
        let hold = OnboardingPracticeTarget(index: 4, title: "送信", requiresHold: true)
        #expect(!ShellText.practiceRunInstruction(plain).contains(ShellText.practiceRunInstruction(hold).suffix(10)))
        #expect(ShellText.practiceRunInstruction(hold).hasPrefix(String(ShellText.practiceRunInstruction(hold).prefix(20))))
        #expect(ShellText.practiceRunInstruction(hold).count > ShellText.practiceRunInstruction(plain).count)
    }

    @Test("実行されなかった理由ごとに、違う手がかりを出す")
    func eachReasonHasItsOwnHint() {
        let target = OnboardingPracticeTarget(index: 4, title: "Safari")
        let reasons: [SessionCancellation] = [.liftedInFrame, .liftedOnBoundary, .liftedTooSoon, .liftedOnEmptyCell, .liftedWithSeveralFingers]
        let texts = reasons.map { ShellText.practiceNotRun($0, target: target, whileCancelling: false) }
        #expect(Set(texts).count == reasons.count)
        // やめる課題の途中は、外枠で離す以外は、どれも同じ案内
        let cancelling = Set(reasons.map { ShellText.practiceNotRun($0, target: target, whileCancelling: true) })
        #expect(cancelling.count == 1)
        // トラックパッドには「押す」「長押し」と言わない
        for text in texts + Array(cancelling) + [ShellText.practiceOpenHint] {
            #expect(!text.contains("押す") && !text.contains("長押し"))
        }
    }
}
