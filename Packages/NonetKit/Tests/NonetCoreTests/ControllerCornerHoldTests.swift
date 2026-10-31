// 担当: engine。トラックパッドの角の長押し（GlobalSettings.touchActivation）から NonetController がセッションを始め、
// HUD・触覚・実行・キーボードまでをつなぐか。既定: 左上の角、前面は Safari（ページは Safari 2枚＋グローバル1枚）、トリガーは右⌥
import Foundation
import Testing
@testable import NonetCore

@MainActor
@Suite struct ControllerCornerHoldTests {
    typealias F = ControllerFixtures

    /// 左上の角の中ほど（マス 0）
    static let topLeft = (x: 0.05, y: 0.95)

    private func harness(
        _ transform: (inout GlobalSettings) -> Void = { _ in },
        trialEnded: Bool = false,
        frontmost: RunningAppInfo? = F.safariApp
    ) throws -> ControllerHarness {
        let settings = F.settings {
            $0.touchActivation = .topLeft
            transform(&$0)
        }
        return try ControllerHarness(configuration: F.configuration(settings: settings), trialEnded: trialEnded, frontmost: frontmost)
    }

    /// 左上の角に指を置いて、長押しの時間だけ待つ（その間フレームは送らない。合図はタイマーで来る）
    private func holdCorner(_ h: ControllerHarness) {
        h.touch(x: Self.topLeft.x, y: Self.topLeft.y)
        h.advance(CornerHoldRecognizer.holdDuration)
    }

    /// cell へ滑らせ、離せば実行される長さ（liftDwell）だけそのマスに留まる
    private func slide(_ h: ControllerHarness, to cell: Int) {
        h.touch(on: cell)
        h.advance(CornerHoldRecognizer.liftDwell)
    }

    private func expectNoSession(_ h: ControllerHarness) {
        #expect(!h.keyboard.isSuppressingPointer)
        #expect(h.keyboard.suppressionChanges.isEmpty)
        #expect(h.hud.shown.isEmpty)
        #expect(h.haptics.plays.isEmpty)
        #expect(!h.keyboard.interruptsWithoutTrigger)
    }

    // MARK: 始まり

    @Test func aLongPressInTheCornerOpensTheHUDAtOnce() throws {
        let h = try harness()
        h.start()
        h.touch(x: Self.topLeft.x, y: Self.topLeft.y)
        h.advance(CornerHoldRecognizer.holdDuration - 0.01)
        expectNoSession(h)

        h.advance(0.01)
        #expect(h.keyboard.isSuppressingPointer)
        #expect(h.keyboard.interruptsWithoutTrigger)
        #expect(h.hud.isVisible)
        let model = try #require(h.hud.current)
        #expect(model.title == "Safari")
        #expect(model.highlightedIndex == 0)
        // 実行のタイミングが「キーを離したとき」でも、指を離して実行する
        #expect(model.hint == ModelFixtures.text("指を離して実行"))
        #expect(model.banner == nil)
        #expect(h.haptics.plays == [.init(event: .activation, strength: .medium)])
        // 抑止を始めてから HUD と触覚
        #expect(h.recorder.events == ["suppress:on", "keys:watch", "hud:show", "haptic:activation"])
    }

    /// 指を止めている間にフレームが届き続けても、始めるのは1回だけ
    @Test func framesAndTheTimerStartOnlyOneSession() throws {
        let h = try harness()
        h.start()
        h.touch(x: Self.topLeft.x, y: Self.topLeft.y)
        h.advance(0.2)
        h.sendFrame()
        h.advance(0.2)
        h.sendFrame()
        h.advance(0.3)
        h.sendFrame()
        #expect(h.hud.shown.count == 1)
        #expect(h.haptics.events == [.activation])
        #expect(h.keyboard.suppressionChanges == [true])
    }

    @Test func theTopRightCornerWorksWhenChosen() throws {
        let h = try harness { $0.touchActivation = .topRight }
        h.start()
        holdCorner(h)
        expectNoSession(h)
        h.lift()
        h.touch(x: 0.95, y: 0.95)
        h.advance(CornerHoldRecognizer.holdDuration)
        #expect(h.hud.current?.highlightedIndex == 2)
    }

    /// 前面アプリのページを使う（トリガーキーと同じ）
    @Test func theSessionUsesThePagesOfTheFrontmostApp() async throws {
        let h = try harness(frontmost: F.notesApp)
        h.start()
        holdCorner(h)
        #expect(h.hud.current?.title == ModelFixtures.globalName)
        slide(h, to: 8)
        h.lift()
        await h.settle()
        #expect(h.performer.actions == [F.docs.action])
        #expect(h.performer.calls.first?.frontmostApp == F.notesApp)
    }

    // MARK: 選ぶ・実行する

    @Test func slidingAndLiftingRunsTheHighlightedCell() async throws {
        let h = try harness()
        h.start()
        holdCorner(h)
        slide(h, to: 2)
        #expect(h.hud.current?.highlightedIndex == 2)
        h.lift()
        await h.settle()

        #expect(h.performer.actions == [F.closeTab.action])
        #expect(h.performer.calls.first?.frontmostApp == F.safariApp)
        #expect(h.haptics.events == [.activation, .boundary, .execute])
        #expect(!h.hud.isVisible)
        #expect(!h.keyboard.isSuppressingPointer)
        #expect(!h.keyboard.interruptsWithoutTrigger)
        // 長押しはタップではないが、終える直前に指が離れたので、遅れて届くクリックは捨てる
        #expect(h.keyboard.lateClickGraces == [true])
        // HUD から実行したので、成功のトーストは出さない
        #expect(h.hud.toasts.isEmpty)
        let record = try #require(h.controller.lastExecution)
        #expect(record.cellTitle == F.closeTab.title)
        #expect(record.address == CellAddress(page: 0, index: 2))
        #expect(!record.wasFastTap)
    }

    @Test func liftingWithoutSlidingRunsNothing() async throws {
        let h = try harness()
        h.start()
        holdCorner(h)
        h.lift()
        await h.settle()

        #expect(h.performer.calls.isEmpty)
        #expect(h.haptics.events == [.activation])
        #expect(!h.hud.isVisible)
        #expect(!h.keyboard.isSuppressingPointer)
        #expect(!h.keyboard.interruptsWithoutTrigger)
        #expect(h.controller.lastExecution == nil)
    }

    /// Nonet のウィンドウがキーなら、トリガーキーと同じく前面アプリに働きかけるマスは実行しない
    @Test func theOwnWindowRuleStillApplies() async throws {
        let h = try harness()
        h.start()
        h.frontmost.isOwnWindowKey = true
        holdCorner(h)
        slide(h, to: 2)
        h.lift()
        await h.settle()

        #expect(h.performer.calls.isEmpty)
        #expect(h.hud.toasts.map(\.style) == [.failure])
        #expect(h.controller.lastExecution?.succeeded == false)
    }

    @Test func hapticsOffPlaysNothingButStillStarts() throws {
        let h = try harness { $0.haptics = .off }
        h.start()
        holdCorner(h)
        #expect(h.hud.isVisible)
        #expect(h.haptics.plays.isEmpty)
    }

    // MARK: 始めないとき（トリガーキーと同じ条件）

    @Test func nothingHappensWhileTheSettingIsOff() throws {
        let h = try harness { $0.touchActivation = .off }
        h.start()
        holdCorner(h)
        h.advance(1)
        expectNoSession(h)
    }

    @Test func nothingHappensWhileNonetIsDisabled() throws {
        let h = try harness { $0.isEnabled = false }
        h.start()
        holdCorner(h)
        expectNoSession(h)
    }

    /// 試用期間が終わっていたら始めない（何も実行できない HUD は出さない）。トリガーキーでマスを押したときと同じく、
    /// 終わったことと次にすることをトースト1つと触覚で知らせる
    @Test func anExpiredTrialOnlyTellsItHasEnded() throws {
        let h = try harness(trialEnded: true)
        h.start()
        holdCorner(h)
        #expect(!h.keyboard.isSuppressingPointer)
        #expect(h.keyboard.suppressionChanges.isEmpty)
        #expect(h.hud.shown.isEmpty)
        #expect(!h.keyboard.interruptsWithoutTrigger)
        #expect(h.haptics.events == [.rejected])
        #expect(h.hud.toasts == [ControllerPresentation.trialEndedToast])
        // 同じタッチのまま待っても、もう一度は知らせない
        h.advance(1)
        #expect(h.hud.toasts.count == 1)
        #expect(h.hud.shown.isEmpty)
    }

    /// 無効などで始められないときは、試用期間が終わっていても何も知らせない
    @Test func anExpiredTrialIsNotToldWhileNonetIsDisabled() throws {
        let h = try harness({ $0.isEnabled = false }, trialEnded: true)
        h.start()
        holdCorner(h)
        expectNoSession(h)
        #expect(h.hud.toasts.isEmpty)
    }

    @Test func nothingHappensWithoutAccessibility() throws {
        let h = try harness()
        h.permissions.isAccessibilityGranted = false
        h.start()
        holdCorner(h)
        expectNoSession(h)
        #expect(h.controller.status == .needsAccessibility)
    }

    @Test func nothingHappensWhileSecureInputIsActive() throws {
        let h = try harness()
        h.start()
        h.permissions.isSecureInputActive = true
        holdCorner(h)
        expectNoSession(h)
        #expect(h.controller.status == .secureInputActive)
    }

    @Test func nothingHappensWhileRecordingKeys() throws {
        let h = try harness()
        h.start()
        h.controller.isRecordingKeys = true
        holdCorner(h)
        expectNoSession(h)
    }

    /// ボタンを押し込んだまま（クリックしたままドラッグを始めるところ など）なら始めない。
    /// 合図は1つのタッチで1回なので、そのタッチの間にボタンを離しても始めない
    @Test func nothingHappensWhileAMouseButtonIsDown() throws {
        let h = try harness(trialEnded: true)
        h.start()
        h.keyboard.isMouseButtonDown = true
        holdCorner(h)
        expectNoSession(h)
        // 試用期間の終了も知らせない
        #expect(h.hud.toasts.isEmpty)
        h.keyboard.isMouseButtonDown = false
        h.advance(1)
        expectNoSession(h)
    }

    /// 手のひらの大きさの接触は長押しとみなさない。指の大きさなら始める
    @Test func aPalmSizedContactDoesNotStartASession() throws {
        let h = try harness()
        h.start()
        h.majorAxes[1] = CornerHoldRecognizer.palmMajorAxis + 5
        holdCorner(h)
        expectNoSession(h)

        h.lift()
        h.majorAxes[1] = 12
        holdCorner(h)
        #expect(h.hud.isVisible)
    }

    /// 置いて止めていた接触が、少し（3mm ほど）ずれてすぐに離れても実行しない（滑らせた後、マスに liftDwell 留まっていない）
    @Test func aStillContactThatDriftsAndLiftsAtOnceRunsNothing() async throws {
        let h = try harness()
        h.start()
        h.touch(x: Self.topLeft.x, y: Self.topLeft.y)
        h.advance(CornerHoldRecognizer.holdDuration + 0.1)
        #expect(h.hud.isVisible)
        h.touch(x: Self.topLeft.x + 0.025, y: Self.topLeft.y)
        h.advance(0.1)
        h.lift()
        await h.settle()

        #expect(h.performer.calls.isEmpty)
        #expect(h.controller.lastExecution == nil)
        #expect(!h.hud.isVisible)
        #expect(!h.keyboard.isSuppressingPointer)
    }

    /// トリガーキーのセッション中に置いた指は、セッションが終わった後も長押しとみなさない
    @Test func aFingerPlacedDuringAKeySessionDoesNotStartOneAfterwards() throws {
        let h = try harness()
        h.start()
        h.pressTrigger()
        h.touch(x: Self.topLeft.x, y: Self.topLeft.y)
        h.advance(0.5)
        h.releaseTrigger()
        let shown = h.hud.shown.count
        h.advance(1)
        #expect(!h.keyboard.isSuppressingPointer)
        #expect(h.hud.shown.count == shown)
        #expect(!h.haptics.events.contains(.activation))
    }

    /// 待っている間にトラックパッドを止めたら（無効にした など）、その指は離れたことにする。すぐに有効に戻しても始めない
    @Test func stoppingTheTrackpadWhileWaitingForgetsTheFinger() throws {
        let h = try harness()
        h.start()
        h.touch(x: Self.topLeft.x, y: Self.topLeft.y)
        h.advance(0.2)
        h.controller.update { $0.settings.isEnabled = false }
        h.controller.update { $0.settings.isEnabled = true }
        h.advance(0.3)
        expectNoSession(h)
    }

    @Test func stoppingTheControllerWhileWaitingForgetsTheFinger() throws {
        let h = try harness()
        h.start()
        h.touch(x: Self.topLeft.x, y: Self.topLeft.y)
        h.advance(0.2)
        h.controller.stop()
        h.start()
        h.advance(0.3)
        expectNoSession(h)
    }

    // MARK: 終わり方

    /// ほかのキーを押したら何も実行せずに終える。置いたままの指で、また始まることもない
    @Test func anyKeyInterruptsAndTheSameTouchDoesNotStartAgain() async throws {
        let h = try harness()
        h.start()
        holdCorner(h)
        h.touch(on: 2)
        h.interrupt()
        #expect(!h.hud.isVisible)
        #expect(!h.keyboard.isSuppressingPointer)
        #expect(!h.keyboard.interruptsWithoutTrigger)
        h.advance(1)
        h.sendFrame()
        h.lift()
        await h.settle()
        #expect(h.performer.calls.isEmpty)
        #expect(h.hud.shown.count == 1)
        #expect(h.haptics.events == [.activation, .boundary])
    }

    /// トリガーキーを押したら、トリガーキーのセッションに替わる（置いたままの指はふだんの規則で選ぶ）
    @Test func pressingTheTriggerSwitchesToAKeySession() async throws {
        let h = try harness()
        h.start()
        holdCorner(h)
        h.touch(on: 2)
        h.pressTrigger()
        #expect(!h.hud.isVisible)
        #expect(h.keyboard.isSuppressingPointer)
        #expect(!h.keyboard.interruptsWithoutTrigger)
        h.advance(0.3)
        #expect(h.hud.isVisible)
        #expect(h.hud.current?.hint == ControllerPresentation.hint(fireMode: .onTriggerRelease, trigger: .rightOption, isPracticeMode: false))
        h.releaseTrigger()
        await h.settle()
        #expect(h.performer.actions == [F.closeTab.action])
        h.lift()
        #expect(!h.keyboard.isSuppressingPointer)
    }

    @Test func maxDurationEndsTheSession() async throws {
        let h = try harness()
        h.start()
        holdCorner(h)
        h.touch(on: 2)
        h.advance(SessionConfiguration.defaultMaxDuration)
        #expect(!h.hud.isVisible)
        #expect(!h.keyboard.isSuppressingPointer)
        #expect(!h.keyboard.interruptsWithoutTrigger)
        h.lift()
        await h.settle()
        #expect(h.performer.calls.isEmpty)
    }

    @Test func stoppingEndsTheSession() throws {
        let h = try harness()
        h.start()
        holdCorner(h)
        h.controller.stop()
        #expect(!h.hud.isVisible)
        #expect(!h.keyboard.isSuppressingPointer)
        #expect(!h.keyboard.interruptsWithoutTrigger)
    }

    // MARK: 設定

    /// 設定はすぐに効き、保存される
    @Test func theSettingTakesEffectAtOnceAndIsSaved() throws {
        let h = try harness { $0.touchActivation = .off }
        h.start()
        h.controller.update { $0.settings.touchActivation = .topLeft }
        holdCorner(h)
        #expect(h.hud.isVisible)
        h.advance(ControllerConfigurationSaver.defaultInterval)
        #expect(try h.savedConfiguration()?.settings.touchActivation == .topLeft)
    }

    /// この設定より前の版の設定ファイル（touchActivation が無い）は「使わない」として読む
    @Test func anOldConfigurationWithoutTheSettingReadsAsOff() throws {
        let h = try ControllerHarness(configuration: nil)
        var json = try #require(try JSONSerialization.jsonObject(with: try JSONEncoder().encode(F.configuration(settings: F.settings { $0.touchActivation = .topRight }))) as? [String: Any])
        var settings = try #require(json["settings"] as? [String: Any])
        #expect(settings["touchActivation"] as? String == "topRight")
        settings["touchActivation"] = nil
        json["settings"] = settings
        try JSONSerialization.data(withJSONObject: json).write(to: h.store.fileURL)
        h.start()
        #expect(h.controller.configuration.settings.touchActivation == .off)
        #expect(!h.controller.isFirstLaunch)
        holdCorner(h)
        expectNoSession(h)
    }
}
