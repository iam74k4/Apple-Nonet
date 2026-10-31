// 担当: engine。SessionEngine の操作の仕様（docs/architecture.md §5）を、台本のように確かめる
import Foundation
import NonetCore
import Testing

@Suite struct SessionEngineOpenTests {
    /// 開くと、ポインタの抑止を始め、HUD をすぐに出し（指は上の外枠なので「離すとやめる」）、軽い触覚で知らせる
    @Test func openingSuppressesThePointerShowsTheHUDAndBuzzes() {
        var s = SessionScenario()
        let effects = s.slideIn(at: 10)
        #expect(effects.visible == [
            .beginPointerSuppression,
            .showHUD(SessionHUDState(page: 0, highlightedCell: nil, isInFrame: true)),
            .haptic(.activation),
        ])
        // 時間切れのための tick だけを頼む
        #expect(effects.tickRequests == [10.05 + SessionConfiguration.defaultMaxDuration])
        #expect(s.engine.isInSession)
        #expect(s.engine.hud == SessionHUDState(page: 0, highlightedCell: nil, isInFrame: true))
    }

    /// 開く前のフレームでは何も出さない（エンジンは指を覚えておくだけ）
    @Test func framesOutsideASessionDoNothing() {
        var s = SessionScenario()
        #expect(s.touch(x: 0.5, y: 0.98, at: 0).isEmpty)
        #expect(s.touch(on: 4, at: 0.1).isEmpty)
        #expect(s.lift(at: 0.2).isEmpty)
        #expect(!s.engine.isInSession)
    }

    /// 指がもう離れていたら開かない（何も出さない）
    @Test func openingWithoutAFingerDoesNothing() {
        var s = SessionScenario()
        #expect(s.open(at: 1).isEmpty)
        #expect(!s.engine.isInSession)
    }

    /// 開いている間にもう一度開いたら、前のセッションを何も実行せずに終えてから開く
    @Test func openingAgainInterruptsTheCurrentSession() {
        var s = SessionScenario()
        s.slideIn(at: 0)
        let effects = s.open(at: 1)
        #expect(effects.visible.prefix(3) == [.hideHUD, .endPointerSuppression(dropsLateClicks: false), .sessionEnded(.interrupted)])
        #expect(effects.visible.dropFirst(3).first == .beginPointerSuppression)
        #expect(effects.executions.isEmpty)
    }
}

@Suite struct SessionEngineSelectionTests {
    /// 外枠から9マスに入ると、そのマスが光る。マスとマス・マスと外枠の境目をまたぐたびに境界の触覚
    @Test func theHighlightFollowsTheFingerAndEveryEdgeTicks() {
        var s = SessionScenario()
        s.slideIn(at: 0)
        let intoGrid = s.touch(on: 1, at: 0.1)
        #expect(intoGrid.hudStates == [SessionHUDState(page: 0, highlightedCell: 1)])
        #expect(intoGrid.hapticEvents == [.boundary])
        let nextCell = s.touch(on: 4, at: 0.2)
        #expect(nextCell.hudStates == [SessionHUDState(page: 0, highlightedCell: 4)])
        #expect(nextCell.hapticEvents == [.boundary])
        // 同じマスの中で動いても何も出さない
        #expect(s.touch(x: 0.52, y: 0.47, at: 0.3).visible.isEmpty)
        let out = s.touch(x: Pad.rightFrame.x, y: Pad.rightFrame.y, at: 0.4)
        #expect(out.hudStates == [SessionHUDState(page: 0, highlightedCell: nil, isInFrame: true)])
        #expect(out.hapticEvents == [.boundary])
    }

    /// マスの境界のヒステリシス（0.03）で、境界の上で震える指でもハイライトがちらつかない
    @Test func theCellBoundaryHasHysteresis() {
        var s = SessionScenario()
        s.slideIn(at: 0)
        s.touch(on: 3, at: 0.1)
        let line = GridInsets.cancelFrame.left + (1 - GridInsets.cancelFrame.left - GridInsets.cancelFrame.right) / 3
        #expect(s.touch(x: line + 0.01, y: 0.5, at: 0.2).visible.isEmpty)
        #expect(s.touch(x: line - 0.005, y: 0.5, at: 0.25).visible.isEmpty)
        #expect(s.touch(x: line + 0.05, y: 0.5, at: 0.3).hudStates == [SessionHUDState(page: 0, highlightedCell: 4)])
    }
}

@Suite struct SessionEngineLiftTests {
    /// 光っているマスに liftDwell（0.15 秒）以上留まって離すと、HUD を閉じてそのマスを実行する
    @Test func liftingOnACellAfterTheDwellRunsIt() {
        var s = SessionScenario()
        s.slideIn(at: 0)
        s.touch(on: 8, at: 0.1)
        let effects = s.lift(at: 0.1 + SessionConfiguration.defaultLiftDwell + 0.001)
        #expect(effects.visible == [
            .hideHUD,
            .execute(page: 0, cell: 8),
            .endPointerSuppression(dropsLateClicks: true),
            .sessionEnded(.released),
        ])
        // execute の触覚は controller が鳴らす
        #expect(effects.hapticEvents.isEmpty)
        #expect(!s.engine.isInSession)
    }

    /// 留まる時間が足りないうちに離した（滑らせながら離した）ら、実行せずに rejected の触覚
    @Test func liftingBeforeTheDwellCancels() {
        var s = SessionScenario()
        s.slideIn(at: 0)
        s.touch(on: 8, at: 0.1)
        let effects = s.lift(at: 0.1 + SessionConfiguration.defaultLiftDwell - 0.01)
        #expect(effects.executions.isEmpty)
        #expect(effects.hapticEvents == [.rejected])
        #expect(effects.endReason == .cancelled(.liftedTooSoon))
    }

    /// 留まる時間はそのマスになった時刻から数える（前のマスにいた時間は数えない）
    @Test func theDwellRestartsOnEveryNewCell() {
        var s = SessionScenario()
        s.slideIn(at: 0)
        s.touch(on: 7, at: 0.1)
        s.touch(on: 8, at: 1.0)
        #expect(s.lift(at: 1.0 + SessionConfiguration.defaultLiftDwell - 0.01).endReason == .cancelled(.liftedTooSoon))
    }

    /// 外枠で離すのが、やめる操作。何も実行せず、rejected の触覚
    @Test(arguments: 0..<4)
    func liftingInTheFrameCancels(side: Int) {
        let point = [Pad.topFrame, Pad.bottomFrame, Pad.leftFrame, Pad.rightFrame][side]
        var s = SessionScenario()
        s.slideIn(at: 0)
        s.touch(on: 4, at: 0.1)
        s.touch(x: point.x, y: point.y, at: 0.3)
        let effects = s.lift(at: 2)
        #expect(effects.executions.isEmpty)
        #expect(effects.visible == [
            .haptic(.rejected),
            .hideHUD,
            .endPointerSuppression(dropsLateClicks: true),
            .sessionEnded(.cancelled(.liftedInFrame)),
        ])
    }

    /// 開いたまま（上の外枠で）すぐに離しても、やめる
    @Test func liftingRightAfterOpeningCancels() {
        var s = SessionScenario()
        s.slideIn(at: 0)
        #expect(s.lift(at: 0.1).endReason == .cancelled(.liftedInFrame))
    }

    /// マスの境界の帯の上で離したら、どちらのマスを狙ったか分からないので実行しない
    @Test func liftingOnTheBoundaryBandCancels() {
        var s = SessionScenario()
        s.slideIn(at: 0)
        s.touch(on: 3, at: 0.1)
        let line = GridInsets.cancelFrame.left + (1 - GridInsets.cancelFrame.left - GridInsets.cancelFrame.right) / 3
        // ヒステリシスで、まだマス 3 が光っている
        #expect(s.touch(x: line - 0.01, y: 0.5, at: 0.2).visible.isEmpty)
        let effects = s.lift(at: 1)
        #expect(effects.executions.isEmpty)
        #expect(effects.hapticEvents == [.rejected])
        #expect(effects.endReason == .cancelled(.liftedOnBoundary))
    }

    /// 空きマスで離しても何も実行しない
    @Test func liftingOnAnEmptyCellCancels() {
        var s = SessionScenario(SessionConfiguration(occupiedCells: [[0, 8]]))
        s.slideIn(at: 0)
        s.touch(on: 4, at: 0.1)
        let effects = s.lift(at: 1)
        #expect(effects.executions.isEmpty)
        #expect(effects.hapticEvents == [.rejected])
        #expect(effects.endReason == .cancelled(.liftedOnEmptyCell))
        // 中身が分からないマスは controller に任せる
        var unknown = SessionScenario(SessionConfiguration(pageCount: 2, occupiedCells: [[0]]))
        unknown.slideIn(at: 0)
        unknown.setFingers([(1, 0.6, 0.5), (2, 0.8, 0.5)], at: 0.1)
        unknown.setFingers([(1, 0.4, 0.5), (2, 0.6, 0.5)], at: 0.15)
        unknown.lift(2, at: 0.2)
        unknown.touch(on: 4, at: 0.3)
        #expect(unknown.lift(at: 1).executions == [.execute(page: 1, cell: 4)])
    }
}

@Suite struct SessionEngineHoldTests {
    /// 少し長く止めるマス: 止め終えるまで（holdDwell 0.45 秒）は、離しても実行しない
    @Test func aHoldCellNeedsTheLongerDwell() {
        var s = SessionScenario(SessionConfiguration(holdCells: [[8]]))
        s.slideIn(at: 0)
        let onCell = s.touch(on: 8, at: 0.1)
        #expect(onCell.hudStates == [SessionHUDState(page: 0, highlightedCell: 8, hold: SessionHold(cell: 8, since: 0.1, duration: 0.45, isReady: false))])
        // 止め終える時刻に tick を頼む
        #expect(onCell.tickRequests == [0.1 + SessionConfiguration.defaultHoldDwell])
        let early = s.lift(at: 0.5)
        #expect(early.executions.isEmpty)
        #expect(early.hapticEvents == [.rejected])
        #expect(early.endReason == .cancelled(.liftedTooSoon))
    }

    /// 止め終えたら HUD と触覚（holdReady）で知らせ（離すと実行する）、その後に離すと実行する
    @Test func aHoldCellRunsAfterTheHUDShowsItIsReady() {
        var s = SessionScenario(SessionConfiguration(holdCells: [[8]]))
        s.slideIn(at: 0)
        s.touch(on: 8, at: 0.1)
        #expect(s.tick(at: 0.54).visible.isEmpty)
        let ready = s.tick(at: 0.55)
        #expect(ready.hudStates == [SessionHUDState(page: 0, highlightedCell: 8, hold: SessionHold(cell: 8, since: 0.1, duration: 0.45, isReady: true))])
        #expect(ready.hapticEvents == [.holdReady])
        #expect(s.lift(at: 0.65).executions == [.execute(page: 0, cell: 8)])
    }

    /// tick が遅れても、届いたフレームの時刻で止め終えたとみなす
    @Test func aLateTickDoesNotLoseTheHold() {
        var s = SessionScenario(SessionConfiguration(holdCells: [[8]]))
        s.slideIn(at: 0)
        s.touch(on: 8, at: 0.1)
        let effects = s.lift(at: 0.75)
        #expect(effects.hudStates.last?.hold?.isReady == true)
        #expect(effects.executions == [.execute(page: 0, cell: 8)])
    }

    /// 少し長く止めるマスから出たら、進み具合は最初から（ふつうのマスは 0.15 秒で実行できる）
    @Test func leavingAHoldCellResetsItsProgress() {
        var s = SessionScenario(SessionConfiguration(holdCells: [[8]]))
        s.slideIn(at: 0)
        s.touch(on: 8, at: 0.1)
        let away = s.touch(on: 7, at: 0.4)
        #expect(away.hudStates == [SessionHUDState(page: 0, highlightedCell: 7)])
        s.touch(on: 8, at: 0.5)
        #expect(s.lift(at: 0.9).endReason == .cancelled(.liftedTooSoon))
        // ふつうのマス
        var plain = SessionScenario(SessionConfiguration(holdCells: [[8]]))
        plain.slideIn(at: 0)
        plain.touch(on: 7, at: 0.1)
        #expect(plain.lift(at: 0.3).executions == [.execute(page: 0, cell: 7)])
    }
}

@Suite struct SessionEnginePageTests {
    /// 2本指で横にスワイプするとページが変わる。2本の間はハイライトしない。左へ動かすと次のページ
    @Test func aTwoFingerSwipeTurnsThePage() {
        var s = SessionScenario(pageCount: 3)
        s.slideIn(at: 0)
        s.touch(on: 4, at: 0.1)
        let second = s.setFingers([(1, 0.5, 0.5), (2, 0.7, 0.5)], at: 0.2)
        #expect(second.hudStates == [SessionHUDState(page: 0, highlightedCell: nil)])
        let swipe = s.setFingers([(1, 0.35, 0.5), (2, 0.55, 0.5)], at: 0.3)
        #expect(swipe.hudStates == [SessionHUDState(page: 1, highlightedCell: nil)])
        #expect(swipe.hapticEvents == [.pageChange])
        // 1回のスワイプで1ページ
        #expect(s.setFingers([(1, 0.1, 0.5), (2, 0.3, 0.5)], at: 0.4).visible.isEmpty)
        #expect(s.engine.pageIndex == 1)
    }

    @Test func swipingRightGoesBackAndTheEndsBuzz() {
        var s = SessionScenario(pageCount: 2)
        s.slideIn(at: 0)
        s.setFingers([(1, 0.4, 0.5), (2, 0.6, 0.5)], at: 0.1)
        let back = s.setFingers([(1, 0.6, 0.5), (2, 0.8, 0.5)], at: 0.2)
        #expect(back.hapticEvents == [.rejected])
        #expect(s.engine.pageIndex == 0)
    }

    /// 2本指の後に1本指に戻ったら、残った指でまた選べる。選ぶには滑らせ直す（2本の指は同時に離れにくい）
    @Test func aTwoFingerPhaseResetsTheSelection() {
        var s = SessionScenario(pageCount: 2)
        s.slideIn(at: 0)
        s.touch(on: 4, at: 0.1)
        s.setFingers([(1, 0.5, 0.5), (2, 0.7, 0.5)], at: 0.2)
        s.setFingers([(1, 0.25, 0.5), (2, 0.45, 0.5)], at: 0.3)
        let back = s.lift(2, at: 0.4)
        // ハイライトが戻るが、境界の触覚は鳴らさない
        #expect(back.hudStates == [SessionHUDState(page: 1, highlightedCell: 3)])
        #expect(back.hapticEvents.isEmpty)
        // 滑らせずに離すとやめる（止めていても）
        var still = s
        #expect(still.lift(at: 1.5).endReason == .cancelled(.liftedWithoutSliding))
        // 滑らせて選び、止めてから離すと実行する
        s.touch(on: 4, at: 0.5)
        #expect(s.lift(at: 0.7).executions == [.execute(page: 1, cell: 4)])
    }

    /// 2本以上の指が触れたまま離したら実行しない（ページを変えた後でも、何も実行せずに閉じたことを知らせる）
    @Test func liftingSeveralFingersAtOnceCancels() {
        var s = SessionScenario(pageCount: 2)
        s.slideIn(at: 0)
        s.setFingers([(1, 0.5, 0.5), (2, 0.7, 0.5)], at: 0.1)
        s.setFingers([(1, 0.35, 0.5), (2, 0.55, 0.5)], at: 0.2)
        let effects = s.liftAll(at: 0.3)
        #expect(effects.executions.isEmpty)
        #expect(effects.hapticEvents == [.rejected])
        #expect(effects.endReason == .cancelled(.liftedWithSeveralFingers))
    }
}

@Suite struct SessionEngineEndTests {
    /// キーが押されたら（マウスを使ったら）何も実行せずに閉じる。触覚も鳴らさない
    @Test func aKeyCancelsWithoutRunning() {
        var s = SessionScenario()
        s.slideIn(at: 0)
        s.touch(on: 4, at: 0.1)
        let effects = s.interrupt(at: 1)
        #expect(effects.visible == [.hideHUD, .endPointerSuppression(dropsLateClicks: false), .sessionEnded(.interrupted)])
        // 閉じた後に指を離しても何もしない
        #expect(s.lift(at: 1.1).isEmpty)
        #expect(s.interrupt(at: 2).isEmpty)
    }

    /// 開いてすぐ（触れてから 0.5 秒のうち）に閉じたら、その指の「タップでクリック」を捨ててもらう
    @Test func closingSoonAfterTheTouchDropsLateClicks() {
        var s = SessionScenario()
        s.slideIn(at: 0)
        #expect(s.interrupt(at: 0.3).contains(.endPointerSuppression(dropsLateClicks: true)))
    }

    /// maxDuration（20 秒）を超えたら閉じる（指が離れたフレームを取りこぼしたときの安全装置）
    @Test func aSessionTimesOut() {
        var s = SessionScenario()
        s.slideIn(at: 0)
        s.touch(on: 4, at: 0.1)
        #expect(s.tick(at: 20.04).visible.isEmpty)
        let effects = s.tick(at: 20.06)
        #expect(effects.endReason == .timeout)
        #expect(effects.executions.isEmpty)
        #expect(!s.engine.isInSession)
    }

    /// 時刻が戻った入力は、それまでの最新の時刻に起きたものとして扱う
    @Test func timeNeverGoesBackwards() {
        var s = SessionScenario()
        s.slideIn(at: 10)
        s.touch(on: 4, at: 10.1)
        // 遅れて届いた古い時刻のフレームで離しても、留まった時間は最新の時刻から数える
        #expect(s.lift(at: 9).endReason == .cancelled(.liftedTooSoon))
    }
}
