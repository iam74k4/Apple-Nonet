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

    /// 練習の2つの課題を済ませた案内
    static func practiced(
        frontmost: RunningAppInfo? = nil,
        recorder: Base.Recorder = Base.Recorder(),
        clock: Base.Clock = Base.Clock()
    ) throws -> (OnboardingModel, ShellControllerHarness) {
        let (model, harness) = Base.make(clock: clock, frontmost: frontmost, recorder: recorder)
        Base.enterPractice(model)
        model.handleExecution(try Base.runRecord(model, date: clock.now.addingTimeInterval(1)))
        model.handleCancellation(ShellFixtures.cancellation(date: clock.now.addingTimeInterval(2)))
        #expect(model.practice == .succeeded)
        return (model, harness)
    }

    // MARK: - 閉じ方

    @Test("ウィンドウの「完了」「スキップ」は閉じてメニューバーのアイコンの場所を見せる。閉じるボタンで閉じたときは見せない")
    func windowCompletion() throws {
        let harness = ShellControllerHarness(installed: Base.installed)
        harness.controller.start()
        var finished = 0
        let window = OnboardingWindowController(controller: harness.controller, services: harness.services) {
            finished += 1
        }
        window.handBackActivation = {}
        var completed = 0
        var opened: [SettingsTab] = []
        window.onComplete = { completed += 1 }
        window.onOpenSettings = { opened.append($0) }
        Base.enterPractice(window.model)
        window.complete()
        #expect(completed == 1)
        window.windowDidClose()
        #expect(finished == 1)
        #expect(!harness.controller.isPracticeMode)
        // 案内はプロファイルを作り直さない（起動時のプリセットのまま）
        #expect(harness.controller.configuration.appProfile(forBundleID: ShellFixtures.xcode) != nil)

        // 「設定を開く」は閉じて設定の「プロファイル」を開く
        let other = OnboardingWindowController(controller: harness.controller, services: harness.services) {}
        other.handBackActivation = {}
        other.onOpenSettings = { opened.append($0) }
        Base.enterPractice(other.model)
        other.openSettings()
        #expect(opened == [.profiles])
        other.windowDidClose()
        #expect(completed == 1)
        // 案内は「ログイン時に起動」に触れない（設定の「一般」で変える）
        #expect(!harness.loginItem.isEnabled)
        #expect(harness.loginItem.setCount == 0)
    }

    @Test("練習の2つの課題を済ませてから閉じられる")
    func practicedThenClosed() throws {
        let (model, harness) = try Self.practiced()
        #expect(model.step == .practice)
        model.next()
        #expect(model.step == .practice)
        model.close()
        #expect(!harness.controller.isPracticeMode)
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
