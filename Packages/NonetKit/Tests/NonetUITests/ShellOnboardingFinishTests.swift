// 担当: ui-shell
// 初回の案内の後半: 完了の画面（こつ・試用期間・ログイン時に起動）・起動したときの許可の案内
import Foundation
import NonetCore
@testable import NonetUI
import Testing

@Suite("初回起動（完了・許可の案内）")
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

    // MARK: - 完了

    @Test("完了の画面のこつ: 上の縁から開く・外枠でやめる・マスを変えるメニューの項目")
    func doneTips() throws {
        let (_, harness) = Base.make(frontmost: ShellFixtures.running(ShellFixtures.xcode, name: "Xcode"))
        // 案内のウインドウの裏にあるアプリ（ここでは Xcode）の名前は出さない
        let xcodeName = try #require(harness.controller.configuration.appProfile(forBundleID: ShellFixtures.xcode)).name
        #expect(ShellText.doneEditTip
            == L10n.ui("メニューバーの 3×3 のアイコン ›「（アプリ名）のマスを編集…」で、前面のアプリのマスを変えられます"))
        #expect(!ShellText.doneEditTip.contains(xcodeName))
        #expect(ShellText.doneOpenTip
            == L10n.ui("トラックパッドの上の縁から指を下へ滑らせると、HUD（9マスの一覧）が開きます。指を滑らせて選び、マスで離すと実行します。"))
        #expect(ShellText.doneCancelTip
            == L10n.ui("9マスの外側の外枠まで指を滑らせて離すと、何も実行せずに閉じます。キーを押しても閉じます。"))
    }

    @Test("完了の画面の試用期間の一行: 試用中だけ、残りの日数を文言の言語の規則で数える")
    func trialNote() throws {
        let (model, _) = Base.make()
        #expect(model.trialDaysLeft == 14)
        let language = Locale(identifier: Bundle.nonetUI.preferredLocalizations.first ?? "ja")
        for days in [1, 14] {
            #expect(ShellText.trialNote(daysLeft: days)
                == String(localized: "試用期間はあと\(days)日です。購入はメニューバーからいつでもできます。", bundle: .nonetUI, locale: language))
        }
        let now = ShellControllerHarness.now
        let expired = LicenseManager(
            verifier: nil,
            storage: ShellFakeLicenseStorage(trialStartDate: now.addingTimeInterval(-30 * 24 * 60 * 60)),
            now: { now }
        )
        let (ended, _) = Base.make(license: expired)
        #expect(ended.trialDaysLeft == nil)
    }

    @Test("完了の画面に入ったときに、メニューバーのアイコンが見えているかを確かめる")
    func statusItemVisibility() {
        let (model, _) = Base.make()
        var visible = false
        model.statusItemVisibility = { visible }
        #expect(model.isStatusItemVisible)
        Base.enterPractice(model)
        model.next()
        #expect(model.step == .done)
        #expect(!model.isStatusItemVisible)
        model.back()
        visible = true
        model.next()
        #expect(model.isStatusItemVisible)
    }

    @Test("「ログイン時に起動」は最初から選ばれていて、「完了」で反映する。完了の画面の外では何もしない")
    func finishEnablesLoginItem() {
        let (model, harness) = Base.make()
        #expect(model.opensAtLogin)
        #expect(model.finish())
        #expect(!harness.loginItem.isEnabled)
        Base.enterPractice(model)
        model.next()
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

    @Test("システム設定での許可が要るときは設定の一般と同じ知らせを出して開いたまま。同じ選択で押し直せば閉じる")
    func finishNeedsApproval() {
        let recorder = Base.Recorder()
        let (model, harness) = Base.make(recorder: recorder)
        Base.enterPractice(model)
        model.next()
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
        failing.next()
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

    @Test("ウィンドウの「完了」はログイン時に起動を反映してから閉じ、メニューバーのアイコンの場所を見せる。途中で閉じたときは見せない")
    func windowCompletion() {
        let harness = ShellControllerHarness(installed: Base.installed)
        harness.controller.start()
        var finished = 0
        let window = OnboardingWindowController(controller: harness.controller, services: harness.services, history: OnboardingGuideHistory()) {
            finished += 1
        }
        window.handBackActivation = {}
        var completed = 0
        var opened: [SettingsTab] = []
        window.onComplete = { completed += 1 }
        window.onOpenSettings = { opened.append($0) }
        Base.enterPractice(window.model)
        window.model.next()
        harness.loginItem.failure = NonetError.permissionDenied("ログイン項目")
        // 知らせを出したので、まだ閉じない
        window.complete()
        #expect(completed == 0)
        window.complete()
        #expect(completed == 1)
        window.windowDidClose()
        #expect(finished == 1)

        // 「設定を開く」もログイン時に起動を反映する
        let other = OnboardingWindowController(controller: harness.controller, services: harness.services, history: OnboardingGuideHistory()) {}
        other.handBackActivation = {}
        other.onOpenSettings = { opened.append($0) }
        Base.enterPractice(other.model)
        other.model.next()
        harness.loginItem.failure = nil
        other.openSettings()
        #expect(harness.loginItem.isEnabled)
        #expect(opened == [.profiles])
        other.windowDidClose()
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
        let window = OnboardingWindowController(controller: harness.controller, services: harness.services, history: OnboardingGuideHistory()) {}
        #expect(window.purpose == .guide)
        let preference = OnboardingReminderPreference(defaults: nil)
        window.purpose = .permission(remindsAtLaunch: true)
        window.reminderPreference = preference
        #expect(window.model.purpose == .permission(remindsAtLaunch: true))
        #expect(!window.model.hidesReminder)
        window.model.setHidesReminder(true)
        #expect(preference.isHidden)
        // 覚えている値で始める
        let next = OnboardingWindowController(controller: harness.controller, services: harness.services, history: OnboardingGuideHistory()) {}
        next.reminderPreference = preference
        #expect(next.model.hidesReminder)
    }

    #if DEBUG
    @Test("見た目の確認用に、指定の画面まで進める（知らない名前は無視する）")
    func previewStep() {
        let harness = ShellControllerHarness(installed: Base.installed)
        harness.controller.start()
        let window = OnboardingWindowController(controller: harness.controller, services: harness.services, history: OnboardingGuideHistory()) {}
        window.previewStep("unknown")
        #expect(window.model.step == .welcome)
        window.previewStep("practice")
        #expect(window.model.step == .practice)
        window.previewStep("done")
        #expect(window.model.step == .done)
        window.windowDidClose()
    }
    #endif
}
