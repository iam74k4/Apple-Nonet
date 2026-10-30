// docs/architecture.md「操作の仕様」の規則ごとのテスト。既定: hudDelay 0.3秒、onTriggerRelease、1ページ
import Testing
import NonetCore

@Suite struct SessionEngineRuleTests {
    // MARK: 1. 開始

    @Test func pressingTheTriggerStartsASessionAndSuppressesThePointer() {
        var s = SessionScenario()
        #expect(s.pressTrigger(at: 0) == [.beginPointerSuppression, .requestTick(at: 0.3)])
        #expect(s.engine.isInSession)
        #expect(s.engine.isTriggerHeld)
        #expect(s.engine.pageIndex == 0)
        #expect(s.engine.hud == nil)
    }

    @Test func inputsOutsideASessionDoNothing() {
        var s = SessionScenario()
        #expect(s.releaseTrigger(at: 1).isEmpty)
        #expect(s.interrupt(at: 1).isEmpty)
        #expect(s.tick(at: 2).isEmpty)
        #expect(s.touch(on: 4, at: 3).isEmpty)
        #expect(s.touch(on: 5, at: 3.1).isEmpty)
        #expect(s.lift(at: 3.2).isEmpty)
        #expect(!s.engine.isInSession)
        #expect(!s.engine.isTriggerHeld)
        #expect(s.engine.pageIndex == nil)
    }

    // MARK: 2. 指

    @Test func highlightFollowsTheLastPlacedFingerWhenFingersAreSwappedBetweenFrames() {
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        s.touch(1, on: 0, at: 0.1)
        s.tick(at: 0.1 + 0.3)
        // 1フレームの間に指 1 が離れ、指 2 が置かれた: 新しいタッチとして指 2 を使う
        s.setFingers([(id: 2, x: Pad.center(8).x, y: Pad.center(8).y)], at: 0.5)
        #expect(s.engine.hud == SessionHUDState(page: 0, highlightedCell: 8))
        #expect(s.releaseTrigger(at: 1).executions == [.execute(page: 0, cell: 8, wasFastTap: false)])
    }

    // MARK: 3. 速押し

    @Test func fastTapExecutesTheTouchDownCellWithoutHUD() {
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        #expect(s.touch(on: 2, at: 0.1) == [.requestTick(at: 0.1 + 0.3)])
        #expect(s.lift(at: 0.2) == [.execute(page: 0, cell: 2, wasFastTap: true), .requestTick(at: 20)])
        #expect(s.releaseTrigger(at: 0.25) == [.endPointerSuppression(dropsLateClicks: true), .sessionEnded(.released)])
        #expect(!s.log.showsHUD)
    }

    @Test func fastTapUsesTheCellWhereTheFingerLandedEvenIfItSlid() {
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        s.touch(on: 0, at: 0.05)
        s.touch(on: 1, at: 0.1)
        s.touch(on: 2, at: 0.15)
        #expect(s.lift(at: 0.2).executions == [.execute(page: 0, cell: 0, wasFastTap: true)])
        #expect(s.log.hapticEvents.isEmpty)
    }

    @Test func fastTapIsAllowedWhenTheFingerLandsJustBeforeHudDelay() {
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        let down = 0.3 - 1e-6
        s.touch(on: 7, at: down)
        // HUD (a) の期限が来ても、指が置かれていれば出さない
        #expect(s.tick(at: 0.3) == [.requestTick(at: down + 0.3)])
        #expect(s.lift(at: 0.5) == [.execute(page: 0, cell: 7, wasFastTap: true), .requestTick(at: 20)])
        #expect(!s.log.showsHUD)
    }

    @Test func fastTapIsAllowedWhenTheFingerLiftsJustBeforeResting() {
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        s.touch(on: 5, at: 0.1)
        let lift = 0.1 + 0.3 - 1e-6
        #expect(s.lift(at: lift).visible == [.execute(page: 0, cell: 5, wasFastTap: true)])
        #expect(!s.log.showsHUD)
    }

    // MARK: 4. HUD

    @Test func hudAppearsAfterHudDelayWithoutATouch() {
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        #expect(s.tick(at: 0.3) == [.showHUD(page: 0, highlightedCell: nil), .requestTick(at: 20)])
        #expect(s.engine.hud == SessionHUDState(page: 0, highlightedCell: nil))
    }

    @Test func hudAppearsWhenAFingerRestsForHudDelay() {
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        s.touch(on: 4, at: 0.1)
        #expect(s.tick(at: 0.1 + 0.3) == [.showHUD(page: 0, highlightedCell: 4), .requestTick(at: 20)])
    }

    @Test func restingFingerShowsTheHUDEvenIfTheTickIsLate() {
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        s.touch(on: 4, at: 0.1)
        // tick が来ないまま次のフレームが来ても、期限の分を先に処理する
        #expect(s.touch(on: 4, at: 0.45) == [.showHUD(page: 0, highlightedCell: 4), .requestTick(at: 20)])
    }

    @Test func fingerPlacedAfterTheHUDHighlightsWithoutHaptics() {
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        s.tick(at: 0.3)
        #expect(s.touch(on: 6, at: 0.5) == [.updateHUD(page: 0, highlightedCell: 6)])
    }

    // MARK: 5. HUD からの実行

    @Test func onTriggerReleaseExecutesTheHighlightedCellWhenReleasedWithAFingerDown() {
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        s.touch(on: 4, at: 0.1)
        s.tick(at: 0.4)
        s.touch(on: 5, at: 0.6)
        #expect(s.releaseTrigger(at: 1) == [
            .hideHUD,
            .execute(page: 0, cell: 5, wasFastTap: false),
            .endPointerSuppression(dropsLateClicks: false),
            .sessionEnded(.released),
        ])
        #expect(!s.engine.isInSession)
    }

    @Test func onTriggerReleaseCancelsWhenTheFingerWasLiftedFirst() {
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        s.touch(on: 4, at: 0.1)
        s.tick(at: 0.4)
        #expect(s.lift(at: 0.5) == [.updateHUD(page: 0, highlightedCell: nil)])
        #expect(s.releaseTrigger(at: 0.6) == [.hideHUD, .endPointerSuppression(dropsLateClicks: true), .sessionEnded(.cancelled)])
        #expect(s.log.executions.isEmpty)
    }

    @Test func onTriggerReleaseCancelsWhenTheHUDNeverHadAFinger() {
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        s.tick(at: 0.3)
        #expect(s.releaseTrigger(at: 2) == [.hideHUD, .endPointerSuppression(dropsLateClicks: false), .sessionEnded(.cancelled)])
    }

    @Test func onTriggerReleaseDoesNotExecuteWhenLiftingInTheHUD() {
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        s.tick(at: 0.3)
        s.touch(on: 1, at: 0.4)
        // HUD が出ているときの短いタッチは速押しではない
        #expect(s.lift(at: 0.45) == [.updateHUD(page: 0, highlightedCell: nil)])
        #expect(s.log.executions.isEmpty)
    }

    @Test func onFingerLiftExecutesTheHighlightedCellAndClosesTheHUD() {
        var s = SessionScenario(fireMode: .onFingerLift)
        s.pressTrigger(at: 0)
        s.touch(on: 4, at: 0.1)
        s.tick(at: 0.4)
        s.touch(on: 7, at: 0.5)
        #expect(s.lift(at: 0.6) == [.hideHUD, .execute(page: 0, cell: 7, wasFastTap: false)])
        #expect(s.engine.hud == nil)
        #expect(s.releaseTrigger(at: 0.7) == [.endPointerSuppression(dropsLateClicks: true), .sessionEnded(.released)])
    }

    @Test func onFingerLiftCancelsWhenTheTriggerIsReleasedWithAFingerDown() {
        var s = SessionScenario(fireMode: .onFingerLift)
        s.pressTrigger(at: 0)
        s.touch(on: 4, at: 0.1)
        s.tick(at: 0.4)
        #expect(s.releaseTrigger(at: 1) == [.hideHUD, .endPointerSuppression(dropsLateClicks: false), .sessionEnded(.cancelled)])
        #expect(s.lift(at: 1.1).isEmpty)
        #expect(s.log.executions.isEmpty)
    }

    @Test func onFingerLiftAllowsSelectingAgainAfterExecuting() {
        var s = SessionScenario(fireMode: .onFingerLift)
        s.pressTrigger(at: 0)
        s.touch(on: 4, at: 0.1)
        s.tick(at: 0.4)
        s.lift(at: 0.5)
        // HUD を閉じた後は速押しができる
        s.touch(on: 2, at: 0.6)
        #expect(s.lift(at: 0.7).visible == [.execute(page: 0, cell: 2, wasFastTap: true)])
        // 指を休めれば HUD がまた出る
        s.touch(on: 3, at: 1.0)
        #expect(s.tick(at: 1.0 + 0.3).visible == [.showHUD(page: 0, highlightedCell: 3)])
        #expect(s.lift(at: 1.5).visible == [.hideHUD, .execute(page: 0, cell: 3, wasFastTap: false)])
        #expect(s.log.executions.count == 3)
    }

    // MARK: 6. 続けて実行

    @Test func repeatedFastTapsInOneSessionEachExecute() {
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        s.touch(on: 0, at: 0.05)
        s.lift(at: 0.1)
        s.touch(on: 8, at: 0.6)
        s.lift(at: 0.7)
        s.touch(on: 4, at: 1.5)
        s.lift(at: 1.6)
        s.tick(at: 5)
        #expect(s.log.executions == [
            .execute(page: 0, cell: 0, wasFastTap: true),
            .execute(page: 0, cell: 8, wasFastTap: true),
            .execute(page: 0, cell: 4, wasFastTap: true),
        ])
        #expect(!s.log.showsHUD)
    }

    @Test func afterAnExecutionTheHUDAppearsOnlyForARestingFinger() {
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        s.touch(on: 0, at: 0.05)
        s.lift(at: 0.1)
        // (a) の期限が来ても出さない
        #expect(s.tick(at: 0.3) == [.requestTick(at: 20)])
        #expect(s.tick(at: 3) == [.requestTick(at: 20)])
        // (b) 指を休めると出す
        s.touch(on: 3, at: 4)
        #expect(s.tick(at: 4 + 0.3).visible == [.showHUD(page: 0, highlightedCell: 3)])
        #expect(s.releaseTrigger(at: 5).executions == [.execute(page: 0, cell: 3, wasFastTap: false)])
    }

    // MARK: 7. 触覚

    @Test func boundaryHapticPlaysEachTimeTheHighlightChanges() {
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        s.touch(on: 4, at: 0.1)
        s.tick(at: 0.4)
        #expect(s.touch(on: 5, at: 0.5) == [.updateHUD(page: 0, highlightedCell: 5), .haptic(.boundary)])
        #expect(s.touch(on: 5, at: 0.55).isEmpty)
        #expect(s.touch(on: 2, at: 0.6) == [.updateHUD(page: 0, highlightedCell: 2), .haptic(.boundary)])
        #expect(s.touch(on: 0, at: 0.7) == [.updateHUD(page: 0, highlightedCell: 0), .haptic(.boundary)])
    }

    @Test func noBoundaryHapticBeforeTheHUDAppears() {
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        s.touch(on: 3, at: 0.05)
        s.touch(on: 4, at: 0.1)
        s.touch(on: 5, at: 0.15)
        #expect(s.log.hapticEvents.isEmpty)
    }

    @Test func engineNeverPlaysTheExecuteHapticItself() {
        // 空きマスでは鳴らさない（仕様 12）ので、execute の触覚は controller が決める
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        s.touch(on: 0, at: 0.05)
        s.lift(at: 0.1)
        s.touch(on: 1, at: 0.5)
        s.tick(at: 0.8)
        s.releaseTrigger(at: 1)
        #expect(s.log.executions.count == 2)
        #expect(!s.log.hapticEvents.contains(.execute))
    }

    // MARK: 8. ページ

    @Test func twoFingerSwipeLeftGoesToTheNextPageAndShowsTheHUD() {
        var s = SessionScenario(pageCount: 3)
        s.pressTrigger(at: 0)
        s.setFingers([(1, 0.4, 0.5), (2, 0.6, 0.5)], at: 0.05)
        #expect(s.setFingers([(1, 0.3, 0.5), (2, 0.5, 0.5)], at: 0.1).visible.isEmpty)
        #expect(s.setFingers([(1, 0.25, 0.5), (2, 0.45, 0.5)], at: 0.15) == [
            .showHUD(page: 1, highlightedCell: nil),
            .haptic(.pageChange),
            .requestTick(at: 20),
        ])
        #expect(s.engine.pageIndex == 1)
    }

    @Test func twoFingerSwipeRightGoesToThePreviousPage() {
        var s = SessionScenario(pageCount: 3)
        s.pressTrigger(at: 0)
        s.setFingers([(1, 0.2, 0.5), (2, 0.4, 0.5)], at: 0.05)
        s.setFingers([(1, 0.05, 0.5), (2, 0.25, 0.5)], at: 0.1)
        s.liftAll(at: 0.2)
        #expect(s.engine.pageIndex == 1)
        s.setFingers([(1, 0.2, 0.5), (2, 0.4, 0.5)], at: 0.3)
        #expect(s.setFingers([(1, 0.35, 0.5), (2, 0.55, 0.5)], at: 0.35) == [
            .updateHUD(page: 0, highlightedCell: nil),
            .haptic(.pageChange),
        ])
    }

    @Test func oneSwipeTurnsOnlyOnePageUntilTheFingersLift() {
        var s = SessionScenario(pageCount: 3)
        s.pressTrigger(at: 0)
        s.setFingers([(1, 0.6, 0.5), (2, 0.8, 0.5)], at: 0.05)
        s.setFingers([(1, 0.45, 0.5), (2, 0.65, 0.5)], at: 0.1)
        #expect(s.setFingers([(1, 0.1, 0.5), (2, 0.3, 0.5)], at: 0.15).visible.isEmpty)
        // 戻る向きに動かしても、同じスワイプの間は変わらない
        #expect(s.setFingers([(1, 0.6, 0.5), (2, 0.8, 0.5)], at: 0.2).visible.isEmpty)
        #expect(s.engine.pageIndex == 1)
        s.liftAll(at: 0.25)
        s.setFingers([(1, 0.6, 0.5), (2, 0.8, 0.5)], at: 0.3)
        s.setFingers([(1, 0.45, 0.5), (2, 0.65, 0.5)], at: 0.35)
        #expect(s.engine.pageIndex == 2)
    }

    @Test func swipeStopsAtTheLastPageWithoutHaptics() {
        var s = SessionScenario(pageCount: 2)
        s.pressTrigger(at: 0)
        s.tick(at: 0.3)
        s.setFingers([(1, 0.6, 0.5), (2, 0.8, 0.5)], at: 0.4)
        s.setFingers([(1, 0.45, 0.5), (2, 0.65, 0.5)], at: 0.45)
        s.liftAll(at: 0.5)
        #expect(s.engine.pageIndex == 1)
        s.setFingers([(1, 0.6, 0.5), (2, 0.8, 0.5)], at: 0.6)
        #expect(s.setFingers([(1, 0.45, 0.5), (2, 0.65, 0.5)], at: 0.65).isEmpty)
        #expect(s.engine.pageIndex == 1)
        #expect(s.log.hapticEvents == [.pageChange])
    }

    @Test func swipeAtTheFirstPageStillShowsTheHUD() {
        var s = SessionScenario(pageCount: 3)
        s.pressTrigger(at: 0)
        s.setFingers([(1, 0.2, 0.5), (2, 0.4, 0.5)], at: 0.05)
        #expect(s.setFingers([(1, 0.4, 0.5), (2, 0.6, 0.5)], at: 0.1).visible == [.showHUD(page: 0, highlightedCell: nil)])
        #expect(s.log.hapticEvents.isEmpty)
    }

    @Test func singlePageSwipeOnlyShowsTheHUD() {
        var s = SessionScenario(pageCount: 1)
        s.pressTrigger(at: 0)
        s.setFingers([(1, 0.6, 0.5), (2, 0.8, 0.5)], at: 0.05)
        #expect(s.setFingers([(1, 0.4, 0.5), (2, 0.6, 0.5)], at: 0.1).visible == [.showHUD(page: 0, highlightedCell: nil)])
        #expect(s.engine.pageIndex == 0)
    }

    @Test func swipeBelowTheThresholdDoesNothing() {
        var s = SessionScenario(pageCount: 3)
        s.pressTrigger(at: 0)
        s.setFingers([(1, 0.4, 0.5), (2, 0.6, 0.5)], at: 0.05)
        #expect(s.setFingers([(1, 0.31, 0.5), (2, 0.51, 0.5)], at: 0.1).visible.isEmpty)
        #expect(s.liftAll(at: 0.15).visible.isEmpty)
        #expect(s.engine.pageIndex == 0)
        #expect(s.log.executions.isEmpty)
    }

    @Test func verticalTwoFingerMovementDoesNotTurnPages() {
        var s = SessionScenario(pageCount: 3)
        s.pressTrigger(at: 0)
        s.setFingers([(1, 0.4, 0.2), (2, 0.6, 0.2)], at: 0.05)
        s.setFingers([(1, 0.4, 0.8), (2, 0.6, 0.8)], at: 0.1)
        #expect(s.engine.pageIndex == 0)
        #expect(!s.log.showsHUD)
    }

    @Test func threeFingersDoNotSwipe() {
        var s = SessionScenario(pageCount: 3)
        s.pressTrigger(at: 0)
        s.setFingers([(1, 0.4, 0.5), (2, 0.6, 0.5), (3, 0.5, 0.2)], at: 0.05)
        s.setFingers([(1, 0.1, 0.5), (2, 0.3, 0.5), (3, 0.2, 0.2)], at: 0.1)
        #expect(s.engine.pageIndex == 0)
    }

    @Test func swipeThenLiftDoesNotExecute() {
        var s = SessionScenario(fireMode: .onFingerLift, pageCount: 2)
        s.pressTrigger(at: 0)
        s.setFingers([(1, 0.6, 0.5), (2, 0.8, 0.5)], at: 0.05)
        s.setFingers([(1, 0.45, 0.5), (2, 0.65, 0.5)], at: 0.1)
        // 1本ずつ離しても、2本触れたタッチなので実行しない
        s.lift(2, at: 0.2)
        #expect(s.lift(1, at: 0.3).visible.isEmpty)
        #expect(s.engine.hud == SessionHUDState(page: 1, highlightedCell: nil))
        #expect(s.log.executions.isEmpty)
    }

    @Test func cellChosenAfterASwipeRunsOnTheNewPage() {
        var s = SessionScenario(pageCount: 3)
        s.pressTrigger(at: 0)
        s.setFingers([(1, 0.6, 0.5), (2, 0.8, 0.5)], at: 0.05)
        s.setFingers([(1, 0.45, 0.5), (2, 0.65, 0.5)], at: 0.1)
        s.liftAll(at: 0.2)
        s.touch(on: 3, at: 0.3)
        #expect(s.engine.hud == SessionHUDState(page: 1, highlightedCell: 3))
        #expect(s.releaseTrigger(at: 0.8).executions == [.execute(page: 1, cell: 3, wasFastTap: false)])
    }

    @Test func fastTapAfterAPageChangeRunsOnThatPage() {
        var s = SessionScenario(fireMode: .onFingerLift, pageCount: 3)
        s.pressTrigger(at: 0)
        s.setFingers([(1, 0.6, 0.5), (2, 0.8, 0.5)], at: 0.05)
        s.setFingers([(1, 0.45, 0.5), (2, 0.65, 0.5)], at: 0.1)
        s.liftAll(at: 0.2)
        s.touch(on: 4, at: 0.3)
        s.lift(at: 0.4)
        s.touch(on: 8, at: 0.5)
        s.lift(at: 0.6)
        #expect(s.log.executions == [
            .execute(page: 1, cell: 4, wasFastTap: false),
            .execute(page: 1, cell: 8, wasFastTap: true),
        ])
    }

    @Test func swipeIsMeasuredFromWhereTheSecondFingerLanded() {
        var s = SessionScenario(pageCount: 2)
        s.pressTrigger(at: 0)
        s.touch(1, x: 0.5, y: 0.5, at: 0.05)
        // 2本目を置いた時点の平均が起点
        s.touch(2, x: 0.7, y: 0.5, at: 0.1)
        s.setFingers([(1, 0.45, 0.5), (2, 0.65, 0.5)], at: 0.15)
        #expect(s.engine.pageIndex == 0)
        s.setFingers([(1, 0.4, 0.5), (2, 0.6, 0.5)], at: 0.2)
        #expect(s.engine.pageIndex == 0)
        s.setFingers([(1, 0.35, 0.5), (2, 0.55, 0.5)], at: 0.25)
        #expect(s.engine.pageIndex == 1)
    }

    // MARK: 9. 2本以上の指

    @Test func secondFingerArrivingMidTapCancelsTheTap() {
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        s.touch(1, on: 0, at: 0.05)
        s.touch(2, on: 2, at: 0.08)
        s.lift(1, at: 0.1)
        #expect(s.lift(2, at: 0.12).executions.isEmpty)
        #expect(s.log.executions.isEmpty)
    }

    @Test func twoFingersLandingTogetherNeverExecute() {
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        s.setFingers([(1, 0.1, 0.9), (2, 0.9, 0.9)], at: 0.05)
        s.liftAll(at: 0.1)
        #expect(s.log.executions.isEmpty)
    }

    @Test func aTwoFingerTouchDoesNotCountAsAnExecutionForTheHUD() {
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        s.setFingers([(1, 0.1, 0.9), (2, 0.9, 0.9)], at: 0.05)
        s.liftAll(at: 0.1)
        #expect(s.tick(at: 0.3).visible == [.showHUD(page: 0, highlightedCell: nil)])
    }

    @Test func twoFingerTouchSpanningHudDelayShowsTheHUDWhenItEnds() {
        // 待ち時間中に置いた指が実行せずに離れたら、その時点で迷っているとみなす
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        s.setFingers([(1, 0.1, 0.9), (2, 0.9, 0.9)], at: 0.1)
        #expect(s.tick(at: 0.3) == [.requestTick(at: 0.1 + 0.3)])
        #expect(s.liftAll(at: 0.35) == [.showHUD(page: 0, highlightedCell: nil), .requestTick(at: 20)])
    }

    @Test func secondFingerInTheHUDClearsTheHighlightAndBlocksExecution() {
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        s.touch(1, on: 4, at: 0.1)
        s.tick(at: 0.4)
        #expect(s.touch(2, on: 8, at: 0.5) == [.updateHUD(page: 0, highlightedCell: nil)])
        // 2本目を離しても、このタッチでは実行しない
        #expect(s.lift(2, at: 0.6).isEmpty)
        #expect(s.touch(1, on: 5, at: 0.7).isEmpty)
        #expect(s.releaseTrigger(at: 1) == [.hideHUD, .endPointerSuppression(dropsLateClicks: false), .sessionEnded(.cancelled)])
    }

    @Test func multiFingerTouchInOnFingerLiftModeDoesNotExecute() {
        var s = SessionScenario(fireMode: .onFingerLift)
        s.pressTrigger(at: 0)
        s.touch(1, on: 4, at: 0.1)
        s.tick(at: 0.4)
        s.touch(2, on: 8, at: 0.5)
        s.lift(2, at: 0.6)
        #expect(s.lift(1, at: 0.7).isEmpty)
        #expect(s.engine.hud == SessionHUDState(page: 0, highlightedCell: nil))
        // 新しい1本指のタッチなら実行できる
        s.touch(on: 2, at: 0.8)
        #expect(s.lift(at: 0.9) == [.hideHUD, .execute(page: 0, cell: 2, wasFastTap: false)])
    }

    // MARK: 10. 中断

    @Test func interruptionEndsWithoutExecuting() {
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        s.touch(on: 4, at: 0.1)
        s.tick(at: 0.4)
        #expect(s.interrupt(at: 0.5) == [.hideHUD, .endPointerSuppression(dropsLateClicks: true), .sessionEnded(.interrupted)])
        #expect(s.releaseTrigger(at: 0.6).isEmpty)
        #expect(s.log.executions.isEmpty)
    }

    @Test func interruptionDuringAFastTapDropsTheTap() {
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        s.touch(on: 2, at: 0.05)
        #expect(s.interrupt(at: 0.1) == [.endPointerSuppression(dropsLateClicks: true), .sessionEnded(.interrupted)])
        #expect(s.lift(at: 0.15).isEmpty)
        #expect(s.log.executions.isEmpty)
    }

    @Test func interruptionKeepsEarlierExecutions() {
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        s.touch(on: 2, at: 0.05)
        s.lift(at: 0.1)
        s.interrupt(at: 0.2)
        #expect(s.log.executions == [.execute(page: 0, cell: 2, wasFastTap: true)])
        #expect(s.log.endReason == .interrupted)
    }

    @Test func sessionTimesOutAfterTwentySeconds() {
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        s.touch(on: 4, at: 0.1)
        s.tick(at: 0.4)
        #expect(s.tick(at: 19.9) == [.requestTick(at: 20)])
        #expect(s.tick(at: 20) == [.hideHUD, .endPointerSuppression(dropsLateClicks: false), .sessionEnded(.timeout)])
        // 指を置いたままでも実行しない
        #expect(s.releaseTrigger(at: 21).isEmpty)
        #expect(s.log.executions.isEmpty)
    }

    @Test func timeoutBeforeAnyTickDoesNotFlashTheHUD() {
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        #expect(s.tick(at: 25) == [.endPointerSuppression(dropsLateClicks: false), .sessionEnded(.timeout)])
    }

    @Test func timeoutUsesTheConfiguredMaximum() {
        var s = SessionScenario(SessionConfiguration(maxDuration: 5))
        s.pressTrigger(at: 10)
        s.tick(at: 10.3)
        #expect(s.tick(at: 15).endReason == .timeout)
    }

    // MARK: 11. 何もしない

    @Test func releasingWithoutATouchDoesNothing() {
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        #expect(s.releaseTrigger(at: 0.1) == [.endPointerSuppression(dropsLateClicks: false), .sessionEnded(.released)])
        #expect(s.log.visible == [.beginPointerSuppression, .endPointerSuppression(dropsLateClicks: false), .sessionEnded(.released)])
    }

    // MARK: 12. 空きマス

    /// 1ページ目は 0・2、2ページ目は 4 だけに中身がある
    private func withEmptyCells(fireMode: FireMode = .onTriggerRelease) -> SessionScenario {
        SessionScenario(SessionConfiguration(fireMode: fireMode, pageCount: 2, occupiedCells: [[0, 2], [4]]))
    }

    @Test func fastTapOnAnEmptyCellDoesNotExecuteAndTheHUDStillAppears() {
        var s = withEmptyCells()
        s.pressTrigger(at: 0)
        s.touch(on: 1, at: 0.05)
        // 実行せずに離したのと同じ。迷っていれば (a) の HUD を出す（仕様 6 の「一度実行した後」にしない）
        #expect(s.lift(at: 0.1) == [.requestTick(at: 0.3)])
        #expect(s.tick(at: 0.3).visible == [.showHUD(page: 0, highlightedCell: nil)])
        #expect(s.log.executions.isEmpty)
    }

    @Test func anEmptyTapAfterTheHudDelayShowsTheHUDRightAway() {
        var s = withEmptyCells()
        s.pressTrigger(at: 0)
        s.touch(on: 5, at: 0.25)
        #expect(!s.tick(at: 0.3).showsHUD)
        #expect(s.lift(at: 0.4).visible == [.showHUD(page: 0, highlightedCell: nil)])
        #expect(s.log.executions.isEmpty)
    }

    @Test func anEmptyTapDoesNotUndoAnEarlierExecution() {
        var s = withEmptyCells()
        s.pressTrigger(at: 0)
        s.touch(on: 2, at: 0.05)
        s.lift(at: 0.1)
        s.touch(on: 1, at: 0.5)
        s.lift(at: 0.6)
        #expect(!s.tick(at: 3).showsHUD)
        #expect(s.log.executions == [.execute(page: 0, cell: 2, wasFastTap: true)])
    }

    @Test func anEmptyTapFinishedAfterTheTriggerIsReleasedDoesNotExecute() {
        var s = withEmptyCells()
        s.pressTrigger(at: 0)
        s.touch(on: 1, at: 0.05)
        #expect(s.releaseTrigger(at: 0.08).visible.isEmpty)
        #expect(s.lift(at: 0.1) == [.endPointerSuppression(dropsLateClicks: true), .sessionEnded(.released)])
        #expect(s.log.executions.isEmpty)
    }

    @Test func onFingerLiftKeepsTheHUDWhenLiftedOnAnEmptyCell() {
        var s = withEmptyCells(fireMode: .onFingerLift)
        s.pressTrigger(at: 0)
        s.touch(on: 1, at: 0.05)
        #expect(s.tick(at: 0.35).visible == [.showHUD(page: 0, highlightedCell: 1)])
        // 何も起きないので、HUD は出したまま選び直せる
        #expect(s.lift(at: 0.5).visible == [.updateHUD(page: 0, highlightedCell: nil)])
        #expect(s.engine.hud == SessionHUDState(page: 0, highlightedCell: nil))
        s.touch(on: 2, at: 0.6)
        #expect(s.lift(at: 0.7).visible == [.hideHUD, .execute(page: 0, cell: 2, wasFastTap: false)])
    }

    @Test func onTriggerReleaseOnAnEmptyCellCancels() {
        var s = withEmptyCells()
        s.pressTrigger(at: 0)
        s.touch(on: 1, at: 0.05)
        s.tick(at: 0.35)
        #expect(s.releaseTrigger(at: 0.5) == [.hideHUD, .endPointerSuppression(dropsLateClicks: true), .sessionEnded(.cancelled)])
        #expect(s.log.executions.isEmpty)
    }

    @Test func emptyCellsAreLookedUpOnTheCurrentPage() {
        // 2ページ目では 2 は空き（1ページ目にはある）、4 は中身がある（1ページ目には無い）
        var s = withEmptyCells(fireMode: .onFingerLift)
        s.pressTrigger(at: 0)
        s.setFingers([(1, 0.6, 0.5), (2, 0.8, 0.5)], at: 0.05)
        s.setFingers([(1, 0.45, 0.5), (2, 0.65, 0.5)], at: 0.1)
        s.liftAll(at: 0.2)
        #expect(s.engine.pageIndex == 1)
        s.touch(on: 2, at: 0.3)
        #expect(s.lift(at: 0.4).executions.isEmpty)
        s.touch(on: 4, at: 0.5)
        #expect(s.lift(at: 0.6).executions == [.execute(page: 1, cell: 4, wasFastTap: false)])
    }

    @Test func pagesWithoutAnEntryCountAsFull() {
        // 中身が分からないページのマスは、controller に判断を任せる
        var s = SessionScenario(SessionConfiguration(pageCount: 2, occupiedCells: [[0]]))
        s.pressTrigger(at: 0)
        s.touch(on: 1, at: 0.05)
        #expect(s.lift(at: 0.1).executions.isEmpty)
        s.setFingers([(1, 0.6, 0.5), (2, 0.8, 0.5)], at: 0.5)
        s.setFingers([(1, 0.45, 0.5), (2, 0.65, 0.5)], at: 0.55)
        s.liftAll(at: 0.6)
        s.touch(on: 1, at: 0.7)
        #expect(s.releaseTrigger(at: 1.1).executions == [.execute(page: 1, cell: 1, wasFastTap: false)])
    }

    // MARK: トリガーより前から置いていた指

    @Test func fingerRestingBeforeTheTriggerIsNotATap() {
        var s = SessionScenario()
        s.touch(on: 4, at: 1)
        #expect(s.pressTrigger(at: 2) == [.beginPointerSuppression, .requestTick(at: 2 + 0.3)])
        #expect(s.lift(at: 2.1).isEmpty)
        #expect(s.log.executions.isEmpty)
        // 指が置かれなかったので (a) で HUD を出す
        #expect(s.tick(at: 2 + 0.3).visible == [.showHUD(page: 0, highlightedCell: nil)])
    }

    @Test func fingerRestingBeforeTheTriggerIsHighlightedAndCanBeSelected() {
        var s = SessionScenario()
        s.touch(on: 4, at: 1)
        s.pressTrigger(at: 2)
        #expect(s.tick(at: 2 + 0.3).visible == [.showHUD(page: 0, highlightedCell: 4)])
        #expect(s.touch(on: 5, at: 2.5) == [.updateHUD(page: 0, highlightedCell: 5), .haptic(.boundary)])
        #expect(s.releaseTrigger(at: 3).executions == [.execute(page: 0, cell: 5, wasFastTap: false)])
    }

    @Test func twoFingersRestingBeforeTheTriggerNeverExecute() {
        var s = SessionScenario()
        s.touch(1, on: 4, at: 1)
        s.touch(2, on: 5, at: 1.1)
        s.lift(2, at: 1.2)
        s.pressTrigger(at: 2)
        #expect(s.tick(at: 2 + 0.3).visible == [.showHUD(page: 0, highlightedCell: nil)])
        #expect(s.releaseTrigger(at: 3).executions.isEmpty)
    }

    @Test func swipeWithFingersRestingBeforeTheTriggerIsMeasuredFromThePress() {
        var s = SessionScenario(pageCount: 2)
        // トリガーを押す前の動き（スクロールなど）はページ送りに数えない
        s.setFingers([(1, 0.7, 0.5), (2, 0.9, 0.5)], at: 1)
        s.setFingers([(1, 0.5, 0.5), (2, 0.7, 0.5)], at: 1.1)
        s.pressTrigger(at: 2)
        #expect(s.setFingers([(1, 0.45, 0.5), (2, 0.65, 0.5)], at: 2.05).visible.isEmpty)
        #expect(s.setFingers([(1, 0.35, 0.5), (2, 0.55, 0.5)], at: 2.1).visible == [
            .showHUD(page: 1, highlightedCell: nil),
            .haptic(.pageChange),
        ])
    }

    @Test func newTouchAfterTheRestingFingerLiftsCanBeAFastTap() {
        var s = SessionScenario()
        s.touch(on: 4, at: 1)
        s.pressTrigger(at: 2)
        s.lift(at: 2.05)
        s.touch(on: 0, at: 2.1)
        #expect(s.lift(at: 2.2).executions == [.execute(page: 0, cell: 0, wasFastTap: true)])
    }
}
