// 担当: engine。角の長押しで始めたセッション（SessionActivation.cornerHold）の規則
import Foundation
import NonetCore
import Testing

extension SessionScenario {
    /// 角の長押しでセッションを始める（設定は台本のもの）
    @discardableResult
    mutating func holdCorner(at time: TimeInterval) -> [SessionEffect] {
        var corner = configuration
        corner.activation = .cornerHold
        return send(.triggerDown(at: time, configuration: corner))
    }
}

@Suite struct SessionEngineCornerHoldTests {
    /// 左上の角（マス 0）
    static let corner = (x: 0.05, y: 0.95)

    /// 左上の角に指を置き、長押しで始めた台本（始めたのは 1.4 秒）
    private func started(_ configuration: SessionConfiguration = SessionConfiguration()) -> SessionScenario {
        var s = SessionScenario(configuration)
        s.touch(x: Self.corner.x, y: Self.corner.y, at: 1)
        s.holdCorner(at: 1.4)
        return s
    }

    // MARK: 始まり

    /// 速押しの段階も hudDelay も無く、すぐに HUD を出して指の下のマスを光らせ、触覚で知らせる
    @Test func theHUDAppearsAtOnceWithTheCellUnderTheFinger() {
        var s = SessionScenario()
        s.touch(x: Self.corner.x, y: Self.corner.y, at: 1)
        #expect(s.holdCorner(at: 1.4) == [
            .beginPointerSuppression,
            .showHUD(page: 0, highlightedCell: 0),
            .haptic(.activation),
            .requestTick(at: 1.4 + SessionConfiguration.defaultMaxDuration),
        ])
        #expect(s.engine.isInSession)
        #expect(s.engine.isCornerHoldSession)
        #expect(!s.engine.isTriggerHeld)
        #expect(s.engine.hud == SessionHUDState(page: 0, highlightedCell: 0))
        // hudDelay が過ぎても何も起きない
        #expect(s.tick(at: 1.4 + SessionConfiguration.defaultHUDDelay).visible.isEmpty)
    }

    @Test func theTopRightCornerHighlightsTheTopRightCell() {
        var s = SessionScenario()
        s.touch(x: 0.95, y: 0.95, at: 1)
        #expect(s.holdCorner(at: 1.4).visible == [.beginPointerSuppression, .showHUD(page: 0, highlightedCell: 2), .haptic(.activation)])
    }

    /// 長押しの指がもう離れていたら、何も出さずに終える
    @Test func withoutAFingerTheSessionEndsAtOnce() {
        var s = SessionScenario()
        #expect(s.holdCorner(at: 1) == [.beginPointerSuppression, .endPointerSuppression(dropsLateClicks: false), .sessionEnded(.cancelled)])
        #expect(!s.engine.isInSession)
    }

    // MARK: 選ぶ・実行する

    @Test func theHighlightFollowsTheFinger() {
        var s = started()
        #expect(s.touch(on: 1, at: 1.5) == [.updateHUD(page: 0, highlightedCell: 1), .haptic(.boundary)])
        #expect(s.touch(on: 4, at: 1.6) == [.updateHUD(page: 0, highlightedCell: 4), .haptic(.boundary)])
        #expect(s.engine.hud == SessionHUDState(page: 0, highlightedCell: 4))
    }

    /// 実行のタイミングの設定や hudDelay に関係なく、滑らせてから離すと光っているマスを実行する
    @Test(arguments: [FireMode.onTriggerRelease, .onFingerLift])
    func liftingAfterSlidingRunsTheHighlightedCell(fireMode: FireMode) {
        var s = started(SessionConfiguration(hudDelay: 0.8, fireMode: fireMode))
        s.touch(on: 4, at: 1.6)
        #expect(s.lift(at: 1.8) == [
            .hideHUD,
            .execute(page: 0, cell: 4, wasFastTap: false),
            .endPointerSuppression(dropsLateClicks: true),
            .sessionEnded(.released),
        ])
        #expect(!s.engine.isInSession)
    }

    /// 滑らせて角のマスに戻ってから離しても、滑らせたので実行する
    @Test func slidingAwayAndBackStillCounts() {
        var s = started()
        s.touch(x: 0.2, y: 0.9, at: 1.5)
        s.touch(x: Self.corner.x, y: Self.corner.y, at: 1.6)
        #expect(s.lift(at: 1.7).executions == [.execute(page: 0, cell: 0, wasFastTap: false)])
    }

    @Test func liftingWithoutSlidingCancels() {
        var s = started()
        // 止めているとみなす範囲の揺れ
        s.touch(x: Self.corner.x + 0.01, y: Self.corner.y - 0.01, at: 1.6)
        #expect(s.lift(at: 2) == [.hideHUD, .endPointerSuppression(dropsLateClicks: true), .sessionEnded(.cancelled)])
        #expect(s.log.executions.isEmpty)
    }

    /// 空きマスでは何も起きない（仕様 12）。キャンセルとして終える
    @Test func liftingOnAnEmptyCellRunsNothing() {
        var s = started(SessionConfiguration(occupiedCells: [[0]]))
        s.touch(on: 4, at: 1.6)
        #expect(s.lift(at: 1.8) == [.hideHUD, .endPointerSuppression(dropsLateClicks: true), .sessionEnded(.cancelled)])
    }

    /// 2本以上で触れたまま離したら実行しない（仕様 9）
    @Test func liftingTwoFingersTogetherRunsNothing() {
        var s = started()
        s.touch(on: 4, at: 1.5)
        s.touch(2, on: 5, at: 1.6)
        #expect(s.engine.hud == SessionHUDState(page: 0, highlightedCell: nil))
        let lifted = s.liftAll(at: 1.8)
        #expect(lifted.endReason == .cancelled)
        // ページを変えずに2本以上で離したので、受け付けなかったことを触覚で知らせる
        #expect(lifted.hapticEvents == [.rejected])
        #expect(s.log.executions.isEmpty)
    }

    /// 離すと同時にほかの指を置いた（restarted）ときも、すべての指が離れたとみなして終える
    @Test func aFingerReplacedWithinOneFrameEndsTheSession() {
        var s = started()
        s.touch(on: 4, at: 1.5)
        let effects = s.setFingers([(id: 2, x: 0.5, y: 0.2)], at: 1.6)
        #expect(effects.executions == [.execute(page: 0, cell: 4, wasFastTap: false)])
        #expect(effects.endReason == .released)
        #expect(!s.engine.isInSession)
    }

    // MARK: ページ

    /// 2本指のスワイプでページを変えられる。変えた後は「滑らせていない」に戻るので、そのまま離すとキャンセル
    @Test func aPageSwipeResetsTheSlideSoLiftingRightAfterCancels() {
        var s = started(SessionConfiguration(pageCount: 2))
        s.touch(on: 4, at: 1.5)
        s.touch(2, x: 0.7, y: 0.5, at: 1.6)
        #expect(s.setFingers([(id: 1, x: 0.35, y: 0.5), (id: 2, x: 0.55, y: 0.5)], at: 1.7) == [
            .updateHUD(page: 1, highlightedCell: nil),
            .haptic(.pageChange),
        ])
        #expect(s.liftAll(at: 1.8) == [.hideHUD, .endPointerSuppression(dropsLateClicks: true), .sessionEnded(.cancelled)])
    }

    @Test func afterAPageSwipeOneFingerLeftMustSlideAgainToChoose() {
        var s = started(SessionConfiguration(pageCount: 2))
        s.touch(on: 4, at: 1.5)
        s.touch(2, x: 0.7, y: 0.5, at: 1.6)
        s.setFingers([(id: 1, x: 0.35, y: 0.5), (id: 2, x: 0.55, y: 0.5)], at: 1.7)
        // 1本指に戻ると、残った指のマスがまた光る
        #expect(s.lift(2, at: 1.8) == [.updateHUD(page: 1, highlightedCell: 4)])
        var cancelled = s
        #expect(cancelled.lift(at: 1.9).endReason == .cancelled)
        #expect(cancelled.log.executions.isEmpty)
        // 滑らせ直してから離すと、新しいページのマスを実行する
        s.touch(on: 8, at: 1.9)
        #expect(s.lift(at: 2.0).executions == [.execute(page: 1, cell: 8, wasFastTap: false)])
    }

    /// 1本指に戻ったら、次の2本指のスワイプでまたページを変えられる（1回のセッションで何ページでも）
    @Test func eachTwoFingerSwipeTurnsOnePage() {
        var s = started(SessionConfiguration(pageCount: 3))
        s.touch(2, x: 0.7, y: 0.5, at: 1.5)
        s.setFingers([(id: 1, x: Self.corner.x, y: Self.corner.y), (id: 2, x: 0.4, y: 0.5)], at: 1.6)
        #expect(s.engine.pageIndex == 1)
        s.lift(2, at: 1.7)
        s.touch(3, x: 0.7, y: 0.5, at: 1.8)
        s.setFingers([(id: 1, x: Self.corner.x, y: Self.corner.y), (id: 3, x: 0.4, y: 0.5)], at: 1.9)
        #expect(s.engine.pageIndex == 2)
        #expect(s.log.hapticEvents == [.activation, .pageChange, .pageChange])
    }

    // MARK: 終わり方

    @Test func anotherKeyInterruptsWithoutRunning() {
        var s = started()
        s.touch(on: 4, at: 1.5)
        let effects = s.interrupt(at: 1.6)
        #expect(effects.first == .hideHUD)
        #expect(effects.endReason == .interrupted)
        #expect(!s.engine.isInSession)
        #expect(s.lift(at: 1.7).isEmpty)
        #expect(s.log.executions.isEmpty)
    }

    /// トリガーキーを押したら、角の長押しのセッションを何も実行せずに終え、トリガーキーのセッションを始める
    @Test func pressingTheTriggerStartsAKeySession() {
        var s = started()
        s.touch(on: 4, at: 1.5)
        #expect(s.pressTrigger(at: 1.6) == [
            .hideHUD,
            .endPointerSuppression(dropsLateClicks: false),
            .sessionEnded(.interrupted),
            .beginPointerSuppression,
            .requestTick(at: 1.6 + SessionConfiguration.defaultHUDDelay),
        ])
        #expect(s.engine.isTriggerHeld)
        #expect(!s.engine.isCornerHoldSession)
        // 置いたままの指は、トリガーキーのセッションのふだんの規則で選ぶ（hudDelay で HUD、トリガーを離して実行）
        #expect(s.tick(at: 1.6 + SessionConfiguration.defaultHUDDelay).visible == [.showHUD(page: 0, highlightedCell: 4)])
        #expect(s.releaseTrigger(at: 2.0).executions == [.execute(page: 0, cell: 4, wasFastTap: false)])
    }

    /// トリガーを押していないので、離したイベントは関係ない
    @Test func aTriggerReleaseDoesNothing() {
        var s = started()
        s.touch(on: 4, at: 1.5)
        #expect(s.releaseTrigger(at: 1.6).isEmpty)
        #expect(s.engine.isInSession)
        #expect(s.engine.hud == SessionHUDState(page: 0, highlightedCell: 4))
    }

    @Test func maxDurationStillEndsTheSession() {
        var s = started(SessionConfiguration(maxDuration: 5))
        #expect(s.tick(at: 6.39).visible.isEmpty)
        #expect(s.tick(at: 6.4) == [.hideHUD, .endPointerSuppression(dropsLateClicks: false), .sessionEnded(.timeout)])
        #expect(s.lift(at: 6.5).isEmpty)
        #expect(s.log.executions.isEmpty)
    }

    /// 終わった後は、トリガーキーのセッションに影響しない（次のトリガーはふだんどおり速押しできる）
    @Test func aKeySessionAfterACornerSessionBehavesAsUsual() {
        var s = started()
        s.lift(at: 1.6)
        s.pressTrigger(at: 2)
        s.touch(on: 2, at: 2.05)
        #expect(s.lift(at: 2.1).executions == [.execute(page: 0, cell: 2, wasFastTap: true)])
    }
}
