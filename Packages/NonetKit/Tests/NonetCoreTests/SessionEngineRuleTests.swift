// docs/architecture.md「操作の仕様」の規則ごとのテスト。既定: hudDelay 0.3秒、placementWindow 0.6秒、onTriggerRelease、1ページ
import Testing
import NonetCore

@Suite struct SessionEngineRuleTests {
    // MARK: 1. 開始

    @Test func pressingTheTriggerStartsASessionAndSuppressesThePointer() {
        var s = SessionScenario()
        // 指を置かなければ placementWindow で HUD を出す
        #expect(s.pressTrigger(at: 0) == [.beginPointerSuppression, .requestTick(at: 0.6)])
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

    /// 4 (a): 指を置かないときは hudDelay ではなく placementWindow で出す（キーボードからトラックパッドへ手を動かす間に出さない）
    @Test func hudAppearsAfterThePlacementWindowWithoutATouch() {
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        #expect(s.tick(at: 0.3) == [.requestTick(at: 0.6)])
        #expect(s.engine.hud == nil)
        #expect(s.tick(at: 0.6) == [.showHUD(page: 0, highlightedCell: nil), .requestTick(at: 20)])
        #expect(s.engine.hud == SessionHUDState(page: 0, highlightedCell: nil))
    }

    /// 手を動かして hudDelay より後に置いた指も、placementWindow より前ならすぐにタップとして実行できる
    @Test func aFingerLandingAfterHudDelayButInsideThePlacementWindowCanStillTap() {
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        s.touch(on: 2, at: 0.45)
        #expect(s.lift(at: 0.55).visible == [.execute(page: 0, cell: 2, wasFastTap: true)])
        #expect(!s.log.showsHUD)
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
        s.tick(at: 0.6)
        #expect(s.touch(on: 6, at: 0.7) == [.updateHUD(page: 0, highlightedCell: 6)])
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
        s.tick(at: 0.6)
        #expect(s.releaseTrigger(at: 2) == [.hideHUD, .endPointerSuppression(dropsLateClicks: false), .sessionEnded(.cancelled)])
    }

    /// HUD が出ていても、短いタップは置いたマスをその場で実行して HUD を閉じる。速押しではない（HUD で見て選んだ）
    @Test func onTriggerReleaseRunsAShortTapInTheHUD() {
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        s.tick(at: 0.6)
        s.touch(on: 1, at: 0.7)
        #expect(s.lift(at: 0.75) == [.hideHUD, .execute(page: 0, cell: 1, wasFastTap: false)])
        #expect(s.engine.hud == nil)
        #expect(s.engine.isInSession)
        // セッションは続き、続けてすぐにタップできる。(a) の HUD はもう出ない（仕様 6）
        s.touch(on: 5, at: 0.9)
        #expect(s.lift(at: 0.95).visible == [.execute(page: 0, cell: 5, wasFastTap: true)])
        #expect(!s.tick(at: 5).showsHUD)
        #expect(s.releaseTrigger(at: 6).endReason == .released)
    }

    /// tapMaxDuration 以上置いた指は、これまでどおり HUD で選ぶ指（先に離すとやめる）
    @Test func onTriggerReleaseDoesNotRunARestingFingerLiftedInTheHUD() {
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        s.tick(at: 0.6)
        s.touch(on: 1, at: 0.7)
        #expect(s.lift(at: 0.7 + SessionConfiguration.tapMaxDuration) == [.updateHUD(page: 0, highlightedCell: nil)])
        #expect(s.releaseTrigger(at: 1.2).endReason == .cancelled)
        #expect(s.log.executions.isEmpty)
    }

    /// tapMaxTravel より動いた指は、滑らせて選んでいる指
    @Test func onTriggerReleaseDoesNotRunAShortSlideInTheHUD() {
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        s.tick(at: 0.6)
        s.touch(x: 0.5, y: 0.5, at: 0.7)
        s.touch(x: 0.5 + SessionConfiguration.tapMaxTravel, y: 0.5, at: 0.75)
        #expect(s.lift(at: 0.8) == [.updateHUD(page: 0, highlightedCell: nil)])
        #expect(s.log.executions.isEmpty)
        // 少しだけなら、置いたマスのタップ
        s.touch(x: 0.5, y: 0.5, at: 1.0)
        s.touch(x: 0.5 + SessionConfiguration.tapMaxTravel / 2, y: 0.5, at: 1.05)
        #expect(s.lift(at: 1.1) == [.hideHUD, .execute(page: 0, cell: 4, wasFastTap: false)])
    }

    /// トリガーより前から置いていた指を離しても、HUD でのタップにしない（休めている指なので、ハイライトもしない）
    @Test func aFingerRestingBeforeTheTriggerIsNotATapInTheHUD() {
        var s = SessionScenario(SessionConfiguration(hudDelay: 0.15, placementWindow: 0.15))
        s.touch(on: 4, at: 1.95)
        s.pressTrigger(at: 2)
        #expect(s.tick(at: 2.15).visible == [.showHUD(page: 0, highlightedCell: nil)])
        #expect(s.lift(at: 2.17).visible.isEmpty)
        #expect(s.log.executions.isEmpty)
    }

    /// 「指を離したとき」は、短くても長くても、離せば光っているマスを実行する（これまでどおり）
    @Test func onFingerLiftRunsAShortTapInTheHUDAsBefore() {
        var s = SessionScenario(fireMode: .onFingerLift)
        s.pressTrigger(at: 0)
        s.tick(at: 0.6)
        s.touch(on: 7, at: 0.7)
        #expect(s.lift(at: 0.75) == [.hideHUD, .execute(page: 0, cell: 7, wasFastTap: false)])
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

    /// 最後のページから先へは行かず、受け付けなかったことを触覚で知らせる（ページの触覚と区別できる）
    @Test func swipeStopsAtTheLastPageWithARejectedHaptic() {
        var s = SessionScenario(pageCount: 2)
        s.pressTrigger(at: 0)
        s.tick(at: 0.6)
        s.setFingers([(1, 0.6, 0.5), (2, 0.8, 0.5)], at: 0.7)
        s.setFingers([(1, 0.45, 0.5), (2, 0.65, 0.5)], at: 0.75)
        s.liftAll(at: 0.8)
        #expect(s.engine.pageIndex == 1)
        s.setFingers([(1, 0.6, 0.5), (2, 0.8, 0.5)], at: 0.9)
        #expect(s.setFingers([(1, 0.45, 0.5), (2, 0.65, 0.5)], at: 0.95) == [.haptic(.rejected)])
        // 端で止まったスワイプを離しても、もう一度は鳴らさない
        #expect(s.liftAll(at: 1.0).isEmpty)
        #expect(s.engine.pageIndex == 1)
        #expect(s.log.hapticEvents == [.pageChange, .rejected])
    }

    @Test func swipeAtTheFirstPageStillShowsTheHUD() {
        var s = SessionScenario(pageCount: 3)
        s.pressTrigger(at: 0)
        s.setFingers([(1, 0.2, 0.5), (2, 0.4, 0.5)], at: 0.05)
        #expect(s.setFingers([(1, 0.4, 0.5), (2, 0.6, 0.5)], at: 0.1).visible == [.showHUD(page: 0, highlightedCell: nil), .haptic(.rejected)])
        #expect(s.log.hapticEvents == [.rejected])
    }

    @Test func singlePageSwipeOnlyShowsTheHUD() {
        var s = SessionScenario(pageCount: 1)
        s.pressTrigger(at: 0)
        s.setFingers([(1, 0.6, 0.5), (2, 0.8, 0.5)], at: 0.05)
        #expect(s.setFingers([(1, 0.4, 0.5), (2, 0.6, 0.5)], at: 0.1).visible == [.showHUD(page: 0, highlightedCell: nil), .haptic(.rejected)])
        #expect(s.engine.pageIndex == 0)
    }

    /// ページを変えずに2本指を離した: 実行せず、受け付けなかったことを触覚で知らせる
    @Test func swipeBelowTheThresholdOnlyTellsItWasNotRecognised() {
        var s = SessionScenario(pageCount: 3)
        s.pressTrigger(at: 0)
        s.setFingers([(1, 0.4, 0.5), (2, 0.6, 0.5)], at: 0.05)
        #expect(s.setFingers([(1, 0.31, 0.5), (2, 0.51, 0.5)], at: 0.1).visible.isEmpty)
        #expect(s.liftAll(at: 0.15).visible == [.haptic(.rejected)])
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
        #expect(s.liftAll(at: 0.1).visible == [.haptic(.rejected)])
        #expect(s.tick(at: 0.6).visible == [.showHUD(page: 0, highlightedCell: nil)])
    }

    @Test func twoFingerTouchSpanningThePlacementWindowShowsTheHUDWhenItEnds() {
        // 待ち時間中に置いた指が実行せずに離れたら、その時点で迷っているとみなす
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        s.setFingers([(1, 0.1, 0.9), (2, 0.9, 0.9)], at: 0.35)
        #expect(s.tick(at: 0.6) == [.requestTick(at: 0.35 + 0.3)])
        #expect(s.liftAll(at: 0.62) == [.haptic(.rejected), .showHUD(page: 0, highlightedCell: nil), .requestTick(at: 20)])
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
        // 2本触れたタッチは実行せず、受け付けなかったことを触覚で知らせる
        #expect(s.lift(1, at: 0.7) == [.haptic(.rejected)])
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
        // 実行せずに離したのと同じ。迷っていれば (a) の HUD を出す（仕様 6 の「一度実行した後」にしない）。
        // 押したことは届いているので、受け付けなかったことを触覚で知らせる
        #expect(s.lift(at: 0.1) == [.haptic(.rejected), .requestTick(at: 0.6)])
        #expect(s.tick(at: 0.6).visible == [.showHUD(page: 0, highlightedCell: nil)])
        #expect(s.log.executions.isEmpty)
    }

    @Test func anEmptyTapAfterThePlacementWindowShowsTheHUDRightAway() {
        var s = withEmptyCells()
        s.pressTrigger(at: 0)
        s.touch(on: 5, at: 0.55)
        #expect(!s.tick(at: 0.6).showsHUD)
        #expect(s.lift(at: 0.7).visible == [.haptic(.rejected), .showHUD(page: 0, highlightedCell: nil)])
        #expect(s.log.executions.isEmpty)
    }

    /// HUD でのタップも、空きマスなら実行せずに触覚で知らせ、HUD は出したまま
    @Test func aTapOnAnEmptyCellInTheHUDOnlyBuzzes() {
        var s = withEmptyCells()
        s.pressTrigger(at: 0)
        s.tick(at: 0.6)
        s.touch(on: 1, at: 0.7)
        #expect(s.lift(at: 0.75) == [.haptic(.rejected), .updateHUD(page: 0, highlightedCell: nil)])
        #expect(s.engine.hud == SessionHUDState(page: 0, highlightedCell: nil))
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
        #expect(s.lift(at: 0.1) == [.haptic(.rejected), .endPointerSuppression(dropsLateClicks: true), .sessionEnded(.released)])
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
        // 休めている指は置いた指に数えないので、HUD は (a) の時刻に出す
        #expect(s.pressTrigger(at: 2) == [.beginPointerSuppression, .requestTick(at: 2 + 0.6)])
        // 速押しにはしない
        #expect(s.lift(at: 2.1).isEmpty)
        #expect(s.log.executions.isEmpty)
        #expect(s.tick(at: 2 + 0.6).visible == [.showHUD(page: 0, highlightedCell: nil)])
    }

    /// トリガーより前から休めている指は、1本だけでも数えない（仕様 9・11）。(b) の HUD もハイライトも無く、
    /// HUD を出さずにトリガーを離しても、HUD を出してから離しても、何も実行しない
    @Test(arguments: [2.4, 3])
    func aFingerRestingBeforeTheTriggerIsNotSelectedWhenTheTriggerIsReleased(releaseAt: Double) {
        var s = SessionScenario()
        s.touch(on: 8, at: 1)
        s.pressTrigger(at: 2)
        #expect(s.tick(at: 2 + 0.3).visible.isEmpty)
        if releaseAt > 2.6 {
            #expect(s.tick(at: 2 + 0.6).visible == [.showHUD(page: 0, highlightedCell: nil)])
        }
        let released = s.releaseTrigger(at: releaseAt)
        #expect(released.executions.isEmpty)
        #expect(released.endReason == (releaseAt > 2.6 ? SessionEndReason.cancelled : .released))
        #expect(s.log.hapticEvents.isEmpty)
    }

    /// 「指を離したとき」でも、休めていた指を離すだけでは実行しない（HUD が出ていても）
    @Test func liftingAFingerRestingBeforeTheTriggerRunsNothingOnFingerLift() {
        var early = SessionScenario(fireMode: .onFingerLift)
        early.touch(on: 8, at: 1)
        early.pressTrigger(at: 2)
        #expect(early.lift(at: 2.4).visible.isEmpty)

        var late = SessionScenario(fireMode: .onFingerLift)
        late.touch(on: 8, at: 1)
        late.pressTrigger(at: 2)
        #expect(late.tick(at: 2.6).visible == [.showHUD(page: 0, highlightedCell: nil)])
        #expect(late.lift(at: 2.8).visible.isEmpty)
        #expect(early.log.executions.isEmpty && late.log.executions.isEmpty)
    }

    /// 休めていた指を restingTolerance より動かしたら、ふつうの指としてハイライトで追い、動かした時刻から hudDelay で (b) の HUD
    @Test func fingerRestingBeforeTheTriggerIsFollowedOnceItSlides() {
        var s = SessionScenario()
        s.touch(on: 4, at: 1)
        s.pressTrigger(at: 2)
        // 止めているとみなす範囲のずれでは数えない
        s.touch(x: Pad.center(4).x + SessionConfiguration.restingTolerance / 2, y: Pad.center(4).y, at: 2.2)
        #expect(s.tick(at: 2.3).visible.isEmpty)
        s.touch(on: 5, at: 2.4)
        // (a) の 2.6 ではなく、動かしてから hudDelay
        #expect(s.tick(at: 2.6).visible.isEmpty)
        #expect(s.tick(at: 2.4 + 0.3).visible == [.showHUD(page: 0, highlightedCell: 5)])
        #expect(s.releaseTrigger(at: 3).executions == [.execute(page: 0, cell: 5, wasFastTap: false)])
    }

    /// HUD が (a) で出た後に休めていた指を滑らせたら、その場でハイライトする（置いただけではないので、境界の触覚は鳴らさない）
    @Test func fingerRestingBeforeTheTriggerIsHighlightedWhenItSlidesInTheHUD() {
        var s = SessionScenario()
        s.touch(on: 4, at: 1)
        s.pressTrigger(at: 2)
        #expect(s.tick(at: 2.6).visible == [.showHUD(page: 0, highlightedCell: nil)])
        #expect(s.touch(on: 5, at: 2.7) == [.updateHUD(page: 0, highlightedCell: 5)])
        #expect(s.releaseTrigger(at: 3).executions == [.execute(page: 0, cell: 5, wasFastTap: false)])
    }

    @Test func twoFingersRestingBeforeTheTriggerNeverExecute() {
        var s = SessionScenario()
        s.touch(1, on: 4, at: 1)
        s.touch(2, on: 5, at: 1.1)
        s.lift(2, at: 1.2)
        s.pressTrigger(at: 2)
        #expect(s.tick(at: 2 + 0.3).visible.isEmpty)
        #expect(s.tick(at: 2 + 0.6).visible == [.showHUD(page: 0, highlightedCell: nil)])
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

    // MARK: トリガーより前から休めている指（親指を手前に置いたまま、など）

    /// 休めている指のほかに置いた指は、新しいすぐにタップ（2本の指のタッチにしない）
    @Test func aTapBesideARestingFingerRuns() {
        var s = SessionScenario()
        s.touch(1, x: 0.5, y: 0.05, at: 1)
        s.pressTrigger(at: 2)
        s.touch(2, on: 2, at: 2.1)
        #expect(s.lift(2, at: 2.2).visible == [.execute(page: 0, cell: 2, wasFastTap: true)])
        // 続けてもう一度。親指を置いたままでも HUD は出ない（一度実行した後は (a) を出さない。親指は休めている指）
        s.touch(3, on: 6, at: 2.4)
        #expect(s.lift(3, at: 2.5).visible == [.execute(page: 0, cell: 6, wasFastTap: true)])
        #expect(!s.tick(at: 5).showsHUD)
        #expect(!s.log.hapticEvents.contains(.rejected))
    }

    /// 休めている指は2本目に数えないので、休めている指のほかの2本でページを変えられる
    @Test func aRestingFingerDoesNotBlockATwoFingerSwipe() {
        var s = SessionScenario(pageCount: 2)
        s.touch(1, x: 0.5, y: 0.05, at: 1)
        s.pressTrigger(at: 2)
        s.touch(2, x: 0.6, y: 0.5, at: 2.05)
        s.touch(3, x: 0.8, y: 0.5, at: 2.06)
        s.setFingers([(1, 0.5, 0.05), (2, 0.45, 0.5), (3, 0.65, 0.5)], at: 2.1)
        #expect(s.engine.pageIndex == 1)
        #expect(s.log.hapticEvents == [.pageChange])
    }

    /// 休めている指を滑らせたら、ふつうの指としてハイライトで追う（速押しにはしない）
    @Test func aRestingFingerThatSlidesIsFollowed() {
        var s = SessionScenario()
        s.touch(1, on: 4, at: 1)
        s.pressTrigger(at: 2)
        s.touch(2, on: 0, at: 2.05)
        s.lift(2, at: 2.1)
        #expect(s.log.executions == [.execute(page: 0, cell: 0, wasFastTap: true)])
        // 残った指はもう HUD を出さないが、滑らせれば（restingTolerance より動けば）追う
        s.touch(1, x: Pad.center(4).x + SessionConfiguration.restingTolerance / 2, y: Pad.center(4).y, at: 2.3)
        #expect(!s.tick(at: 3).showsHUD)
        s.touch(1, on: 5, at: 3.1)
        #expect(s.tick(at: 3.1 + 0.3).visible == [.showHUD(page: 0, highlightedCell: 5)])
        #expect(s.releaseTrigger(at: 4).executions == [.execute(page: 0, cell: 5, wasFastTap: false)])
    }

    /// 休めている指のほかに置いた指は、HUD が出ていれば境界の触覚を鳴らさずにハイライトし、短ければ HUD でのタップ
    @Test func aTapBesideARestingFingerInTheHUDRunsWithoutABoundaryBuzz() {
        var s = SessionScenario()
        s.touch(1, on: 7, at: 1)
        s.pressTrigger(at: 2)
        // 休めている指はハイライトしない
        #expect(s.tick(at: 2.6).visible == [.showHUD(page: 0, highlightedCell: nil)])
        #expect(s.touch(2, on: 2, at: 2.7) == [.updateHUD(page: 0, highlightedCell: 2)])
        #expect(s.lift(2, at: 2.8) == [.hideHUD, .execute(page: 0, cell: 2, wasFastTap: false)])
        #expect(s.log.hapticEvents.isEmpty)
    }

    /// ほかの指でタップしている間の休めている指の小さなずれは、2本目に数えない
    @Test func aRestingFingerThatDriftsDuringATapIsStillIgnored() {
        var s = SessionScenario()
        s.touch(1, x: 0.5, y: 0.05, at: 1)
        s.pressTrigger(at: 2)
        s.touch(2, on: 2, at: 2.1)
        s.setFingers([(1, 0.53, 0.05), (2, Pad.center(2).x, Pad.center(2).y)], at: 2.15)
        #expect(s.lift(2, at: 2.2).visible == [.execute(page: 0, cell: 2, wasFastTap: true)])
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
