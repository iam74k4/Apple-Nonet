// 担当: engine。開けないとき（アクセシビリティの許可なし・パスワードの入力中）の扱いと、思わず開いてしまうときの開きやすさの案内
import Foundation
import Testing
@testable import NonetCore

@MainActor
@Suite struct ControllerUnavailableTests {
    typealias F = ControllerFixtures

    // MARK: アクセシビリティの許可なし

    /// 許可が無い間はイベントタップを作れないので、クリックを預からない（強く押し込んでもふつうのクリックで、何も知らせない）
    @Test func withoutAccessibilityNothingIsHeld() async throws {
        let h = try ControllerHarness()
        h.permissions.isAccessibilityGranted = false
        h.start()
        #expect(h.keyboard.forcePressHold == nil)
        h.open()
        h.advance(0.3)
        h.touch(on: 2)
        h.advance(0.3)
        h.liftAndClose()
        await h.settle()

        #expect(h.hud.shown.isEmpty)
        #expect(h.keyboard.suppressionChanges.isEmpty)
        #expect(h.performer.calls.isEmpty)
        #expect(h.haptics.plays.isEmpty)
        #expect(h.controller.lastExecution == nil)
    }

    /// 許可されたら、そのまま開ける（知らせは出さない）
    @Test func grantingAccessibilityLetsTheNextPressOpen() async throws {
        let h = try ControllerHarness()
        h.permissions.isAccessibilityGranted = false
        h.start()
        h.permissions.isAccessibilityGranted = true
        h.advance(NonetController.pollInterval)
        #expect(h.controller.status == .running)
        #expect(h.keyboard.forcePressHold != nil)
        h.run(2)
        await h.settle()
        #expect(h.performer.actions == [F.closeTab.action])
        #expect(h.hud.toasts.isEmpty)
    }

    // MARK: パスワードの入力中

    @Test func secureInputExplainsWhyNothingOpens() throws {
        let h = try ControllerHarness()
        h.permissions.isSecureInputActive = true
        h.start()
        h.open()
        h.liftAndClose()
        #expect(h.hud.shown.isEmpty)
        #expect(h.haptics.events == [.rejected])
        #expect(h.hud.toasts == [ControllerPresentation.secureInputToast])
        // 開かなかったクリックは前面アプリに返す（パスワード欄をふつうにクリックできる）
        #expect(h.keyboard.forcePressAnswers == [false])

        // パスワード欄から離れたら、すぐに開ける
        h.permissions.isSecureInputActive = false
        h.open()
        #expect(h.hud.shown.count == 1)
        h.liftAndClose()
    }

    /// キーを記録している間（設定）は開かず、何も知らせない
    @Test func recordingKeysSaysNothing() throws {
        let h = try ControllerHarness()
        h.permissions.isSecureInputActive = true
        h.start()
        h.controller.isRecordingKeys = true
        h.open()
        h.liftAndClose()
        #expect(h.hud.toasts.isEmpty)
        #expect(h.haptics.plays.isEmpty)
    }

    // MARK: 開きやすさの案内

    static let map = CGRect(x: 100, y: 100, width: 268, height: 268)
    static let center = CGPoint(x: 234, y: 234)

    /// 開いてすぐ、ポインタを真ん中から出さずに離して閉じる（思わず開いてしまったときの閉じ方）
    private func openAndLiftAtCenter(_ h: ControllerHarness) {
        h.keyboard.pointerLocation = Self.center
        h.open()
        h.liftAndClose()
    }

    private func harness(_ transform: (inout GlobalSettings) -> Void = { _ in }) throws -> ControllerHarness {
        let h = try ControllerHarness(configuration: F.configuration(settings: F.settings(transform)))
        h.start()
        h.hud.mapFrame = Self.map
        return h
    }

    /// 続けて3回、開いてすぐ離して閉じたら、開きやすさを「控えめ」にする案内を1回だけ出す
    @Test func repeatedAccidentalOpensSuggestLowSensitivityOnce() throws {
        let h = try harness()
        openAndLiftAtCenter(h)
        openAndLiftAtCenter(h)
        #expect(h.controller.lastCancellation?.liftedBeforeMoving == true)
        #expect(h.hud.toasts.isEmpty)
        openAndLiftAtCenter(h)
        #expect(h.hud.toasts == [ControllerPresentation.sensitivityHintToast])
        #expect(h.guidance.hasShownSensitivityHint)

        for _ in 0..<AccidentalOpenTracker.threshold {
            openAndLiftAtCenter(h)
        }
        #expect(h.hud.toasts.count == 1)
    }

    /// 間が空いていれば数えない
    @Test func accidentalOpensFarApartAreNotCounted() throws {
        let h = try harness()
        openAndLiftAtCenter(h)
        openAndLiftAtCenter(h)
        h.advance(AccidentalOpenTracker.window)
        openAndLiftAtCenter(h)
        #expect(h.hud.toasts.isEmpty)
    }

    /// もう「控えめ」・もう案内した・練習中なら出さない
    @Test func theHintIsNotShownWhenItDoesNotHelp() throws {
        let low = try harness { $0.openSensitivity = .low }
        for _ in 0..<AccidentalOpenTracker.threshold { openAndLiftAtCenter(low) }
        #expect(low.hud.toasts.isEmpty)

        let shown = try harness()
        shown.guidance.hasShownSensitivityHint = true
        for _ in 0..<AccidentalOpenTracker.threshold { openAndLiftAtCenter(shown) }
        #expect(shown.hud.toasts.isEmpty)

        let practice = try harness()
        practice.controller.isPracticeMode = true
        for _ in 0..<AccidentalOpenTracker.threshold { openAndLiftAtCenter(practice) }
        #expect(practice.hud.toasts.isEmpty)
        #expect(!practice.guidance.hasShownSensitivityHint)
    }

    /// 輪の外まで動かしてから離した（ふつうのやめ方）は数えない
    @Test func deliberateCancelsAreNotCounted() throws {
        let h = try harness()
        for _ in 0..<AccidentalOpenTracker.threshold {
            h.keyboard.pointerLocation = Self.center
            h.open()
            h.advance(0.05)
            h.keyboard.pointerLocation = CGPoint(x: Self.center.x, y: Self.center.y + 150)
            h.touch(x: 0.5, y: 0.5)
            h.liftAndClose()
        }
        #expect(h.controller.lastCancellation?.liftedBeforeMoving == false)
        #expect(h.hud.toasts.isEmpty)
    }

    @Test func theTrackerCountsWithinTheWindow() {
        var tracker = AccidentalOpenTracker()
        let window = AccidentalOpenTracker.window
        // 3回目で出す
        let first = [0, 100, 200].map { tracker.record(at: $0) }
        #expect(first == [false, false, true])
        // 出したら数え直す
        #expect(tracker.times.isEmpty)
        // 古いもの（window より前）は数えない
        let second = [300, 400, 300 + window].map { tracker.record(at: $0) }
        #expect(second == [false, false, false])
        #expect(tracker.times == [400, 300 + window])
        // 時計が戻ったら、それより後の記録は捨てる
        let rewound = tracker.record(at: 10)
        #expect(!rewound)
        #expect(tracker.times == [10])
    }
}
