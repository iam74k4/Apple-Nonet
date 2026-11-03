// 担当: ui-shell
// 初回の案内の後半: 閉じ方・起動したときの許可の案内
import Foundation
import NonetCore
@testable import NonetUI
import Testing

@Suite("初回起動（閉じ方・許可の案内）")
@MainActor
struct ShellOnboardingFinishTests {
    typealias Base = ShellOnboardingTests

    // MARK: - 閉じ方

    @Test("どう閉じても（閉じるボタンでも）アイコンの場所を見せる。「設定を開く」は設定の「プロファイル」を開き、見せない")
    func windowCompletion() throws {
        let harness = ShellControllerHarness(installed: Base.installed)
        harness.controller.start()
        var finished = 0
        var completed = 0
        var opened: [SettingsTab] = []
        func makeWindow() -> OnboardingWindowController {
            let window = OnboardingWindowController(controller: harness.controller, services: harness.services) { finished += 1 }
            window.handBackActivation = {}
            window.onComplete = { completed += 1 }
            window.onOpenSettings = { opened.append($0) }
            return window
        }

        // 「完了」「スキップ」（テストではウィンドウが無いので、閉じたことは windowDidClose で知らせる）
        let done = makeWindow()
        Base.enterPractice(done.model)
        done.complete()
        done.windowDidClose()
        #expect(completed == 1)
        #expect(finished == 1)
        #expect(!harness.controller.isPracticeMode)
        // 案内はプロファイルを作り直さない（起動時のプリセットのまま）
        #expect(harness.controller.configuration.appProfile(forBundleID: ShellFixtures.xcode) != nil)

        // 閉じるボタン（最初の画面のままでも）
        let closed = makeWindow()
        closed.windowDidClose()
        #expect(completed == 2)
        #expect(finished == 2)

        // 「設定を開く」
        let settings = makeWindow()
        Base.enterPractice(settings.model)
        settings.openSettings()
        settings.windowDidClose()
        #expect(opened == [.profiles])
        #expect(completed == 2)
        #expect(finished == 3)
    }

    @Test("練習の画面に入ったときに、メニューバーのアイコンが見えているかを確かめる")
    func statusItemVisibility() {
        let (model, _) = Base.make()
        var visible = false
        model.statusItemVisibility = { visible }
        #expect(model.isStatusItemVisible)
        Base.enterPractice(model)
        #expect(!model.isStatusItemVisible)
        model.back()
        visible = true
        model.next()
        #expect(model.isStatusItemVisible)
    }

    @Test("初回起動では「ログイン時に起動」を選んでおき、練習の画面を閉じるときに反映する。最初の画面では何もしない")
    func finishEnablesLoginItem() {
        let (model, harness) = Base.make()
        #expect(harness.controller.isFirstLaunch)
        #expect(model.opensAtLogin)
        #expect(model.finish())
        #expect(!harness.loginItem.isEnabled)
        Base.enterPractice(model)
        #expect(model.finish())
        #expect(harness.loginItem.isEnabled)
        #expect(model.loginItemMessage == nil)
        // 同じなら変えない
        #expect(model.finish())
        #expect(harness.loginItem.setCount == 1)

        // 外したら止める
        model.opensAtLogin = false
        #expect(model.finish())
        #expect(!harness.loginItem.isEnabled)
    }

    @Test("閉じるボタンで閉じても、練習の画面で選んでいた「ログイン時に起動」を反映する")
    func closingTheWindowAppliesTheLoginItem() {
        let harness = ShellControllerHarness(installed: Base.installed)
        harness.controller.start()
        let window = OnboardingWindowController(controller: harness.controller, services: harness.services) {}
        window.handBackActivation = {}
        Base.enterPractice(window.model)
        window.windowDidClose()
        #expect(harness.loginItem.isEnabled)
    }

    @Test("もう一度見るときは、いまの「ログイン時に起動」から始める（設定の「一般」で外したものを戻さない）")
    func rerunStartsFromTheCurrentLoginItem() throws {
        let harness = ShellControllerHarness(installed: Base.installed)
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
        let model = OnboardingModel(controller: relaunched, permissions: harness.permissions, loginItem: harness.loginItem)
        #expect(!model.opensAtLogin)
        model.next()
        #expect(model.finish())
        #expect(harness.loginItem.setCount == 0)
    }

    @Test("システム設定での許可が要るときは設定の一般と同じ知らせを出して開いたまま。同じ選択で押し直せば閉じる")
    func finishNeedsApproval() {
        let recorder = Base.Recorder()
        let (model, harness) = Base.make(recorder: recorder)
        Base.enterPractice(model)
        harness.loginItem.failure = NonetError.permissionDenied("ログイン項目")
        #expect(!model.finish())
        let approval = L10n.ui("システム設定の「ログイン項目」で Nonet を許可すると、ログイン時に起動するようになります")
        #expect(model.loginItemMessage == approval)
        #expect(recorder.announcements.last == approval)
        #expect(model.finish())
        #expect(harness.loginItem.setCount == 1)

        // ほかの理由で変えられなかったとき
        let (failing, failingHarness) = Base.make()
        Base.enterPractice(failing)
        failingHarness.loginItem.failure = NonetError.actionFailed("だめ")
        #expect(!failing.finish())
        let reason = NonetError.actionFailed("だめ").localizedDescription
        #expect(failing.loginItemMessage == L10n.ui("ログイン時に起動するように設定できませんでした（\(reason)）"))
        // 選び直したら、もう一度試す
        failingHarness.loginItem.failure = nil
        failing.opensAtLogin = false
        #expect(failing.finish())
        failing.opensAtLogin = true
        #expect(failing.finish())
        #expect(failingHarness.loginItem.isEnabled)
    }

    // MARK: - 起動したときの許可の案内

    @Test("起動したときの案内: 初回起動なら初回の案内。有効で許可が無ければ許可の案内（「今後表示しない」を選んでいなければ）", arguments: [
        (true, true, false, false, OnboardingLaunchGuide.firstRun),
        (true, true, true, true, .firstRun),
        (false, true, false, false, .permissionReminder),
        (false, true, false, true, .none),
        (false, true, true, false, .none),
        (false, false, false, false, .none),
    ])
    func launchGuide(isFirstLaunch: Bool, isEnabled: Bool, isGranted: Bool, isHidden: Bool, expected: OnboardingLaunchGuide) {
        #expect(OnboardingLaunchGuide.decide(
            isFirstLaunch: isFirstLaunch,
            isEnabled: isEnabled,
            isAccessibilityGranted: isGranted,
            isReminderHidden: isHidden
        ) == expected)
    }

    @Test("「今後表示しない」は UserDefaults に覚える（渡さなければこのプロセスの間だけ）")
    func reminderPreference() throws {
        let suite = "nonet-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let stored = OnboardingReminderPreference(defaults: defaults)
        #expect(!stored.isHidden)
        stored.isHidden = true
        #expect(OnboardingReminderPreference(defaults: defaults).isHidden)

        let memory = OnboardingReminderPreference(defaults: nil)
        memory.isHidden = true
        #expect(memory.isHidden)
        #expect(!OnboardingReminderPreference(defaults: nil).isHidden)
    }

    @Test("許可の案内として開いたら、見出しを変えて「今後表示しない」を覚える場所につなぐ")
    func permissionPurpose() {
        let harness = ShellControllerHarness(installed: Base.installed, accessibilityGranted: false)
        harness.controller.start()
        let window = OnboardingWindowController(controller: harness.controller, services: harness.services) {}
        #expect(window.purpose == .guide)
        let preference = OnboardingReminderPreference(defaults: nil)
        window.purpose = .permission(remindsAtLaunch: true)
        window.reminderPreference = preference
        #expect(window.model.purpose == .permission(remindsAtLaunch: true))
        #expect(!window.model.hidesReminder)
        window.model.setHidesReminder(true)
        #expect(preference.isHidden)
        // 覚えている値で始める
        let next = OnboardingWindowController(controller: harness.controller, services: harness.services) {}
        next.reminderPreference = preference
        #expect(next.model.hidesReminder)
    }

    #if DEBUG
    @Test("見た目の確認用に、指定の画面まで進める（知らない名前は無視する）")
    func previewStep() {
        let harness = ShellControllerHarness(installed: Base.installed)
        harness.controller.start()
        let window = OnboardingWindowController(controller: harness.controller, services: harness.services) {}
        window.previewStep("unknown")
        #expect(window.model.step == .welcome)
        window.previewStep("practice")
        #expect(window.model.step == .practice)
        window.previewStep("done")
        #expect(window.model.step == .practice)
        window.windowDidClose()
    }
    #endif
}
