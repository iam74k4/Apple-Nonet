// 担当: engine。左右の外枠に指を止めてページを切り替える（SessionConfiguration.edgePageDwell・edgePageRepeat）
import Foundation
import NonetCore
import Testing

@Suite struct SessionEngineEdgePagingTests {
    static let dwell = SessionConfiguration.defaultEdgePageDwell
    static let repeatDwell = SessionConfiguration.defaultEdgePageRepeat

    /// 右の外枠に止めると、edgePageDwell で次のページ。止めたままなら edgePageRepeat ごとに進み、最後のページで止まる
    @Test func restingOnTheRightFrameTurnsToTheNextPages() {
        var s = SessionScenario(pageCount: 3)
        s.slideIn(at: 0)
        let onEdge = s.touch(x: Pad.rightFrame.x, y: Pad.rightFrame.y, at: 0.2)
        #expect(onEdge.hudStates == [
            SessionHUDState(page: 0, highlightedCell: nil, isInFrame: true, edgePaging: SessionEdgePaging(edge: .right, since: 0.2, duration: Self.dwell)),
        ])
        #expect(onEdge.tickRequests == [0.2 + Self.dwell])
        #expect(s.tick(at: 0.2 + Self.dwell - 0.01).visible.isEmpty)

        let first = s.tick(at: 0.2 + Self.dwell)
        #expect(first.hudStates == [
            SessionHUDState(page: 1, highlightedCell: nil, isInFrame: true, edgePaging: SessionEdgePaging(edge: .right, since: 0.7, duration: Self.repeatDwell)),
        ])
        #expect(first.hapticEvents == [.pageChange])

        // 最後のページに来たら、それ以上は待たない（進み具合も出さない）
        let second = s.tick(at: 0.7 + Self.repeatDwell)
        #expect(second.hudStates == [SessionHUDState(page: 2, highlightedCell: nil, isInFrame: true)])
        #expect(second.hapticEvents == [.pageChange])
        #expect(s.tick(at: 5).visible.isEmpty)
        #expect(s.engine.pageIndex == 2)

        // 外枠で離すのは、ページを変えた後でも、やめる操作
        let lifted = s.lift(at: 5.1)
        #expect(lifted.executions.isEmpty)
        #expect(lifted.endReason == .cancelled(.liftedInFrame))
    }

    /// 左の外枠に止めると前のページ。最初のページでは何も待たない
    @Test func restingOnTheLeftFrameTurnsBack() {
        var s = SessionScenario(pageCount: 2)
        s.slideIn(at: 0)
        #expect(s.touch(x: Pad.leftFrame.x, y: Pad.leftFrame.y, at: 0.2).visible.isEmpty)
        #expect(s.tick(at: 2).visible.isEmpty)
        #expect(s.engine.pageIndex == 0)

        s.touch(x: Pad.rightFrame.x, y: Pad.rightFrame.y, at: 2.1)
        s.tick(at: 2.1 + Self.dwell)
        #expect(s.engine.pageIndex == 1)
        // 反対の側へ移ったら、最初から数え直す
        let back = s.touch(x: Pad.leftFrame.x, y: Pad.leftFrame.y, at: 3)
        #expect(back.hudStates == [
            SessionHUDState(page: 1, highlightedCell: nil, isInFrame: true, edgePaging: SessionEdgePaging(edge: .left, since: 3, duration: Self.dwell)),
        ])
        let turned = s.tick(at: 3 + Self.dwell)
        #expect(turned.hudStates == [SessionHUDState(page: 0, highlightedCell: nil, isInFrame: true)])
        #expect(turned.hapticEvents == [.pageChange])
    }

    /// 止め終える前にマスへ戻ったら、ページは変えない
    @Test func leavingBeforeTheDwellKeepsThePage() {
        var s = SessionScenario(pageCount: 3)
        s.slideIn(at: 0)
        s.touch(x: Pad.rightFrame.x, y: Pad.rightFrame.y, at: 0.2)
        let back = s.touch(on: 5, at: 0.5)
        #expect(back.hudStates == [SessionHUDState(page: 0, highlightedCell: 5)])
        #expect(s.tick(at: 0.2 + Self.dwell).visible.isEmpty)
        #expect(s.engine.pageIndex == 0)
    }

    /// ページを変えた後にマスへ滑らせて離すと、新しいページのマスを実行する
    @Test func aCellOnTheNewPageRunsAfterTurning() {
        var s = SessionScenario(pageCount: 2)
        s.slideIn(at: 0)
        s.touch(x: Pad.rightFrame.x, y: Pad.rightFrame.y, at: 0.2)
        s.tick(at: 0.2 + Self.dwell)
        s.touch(on: 5, at: 0.8)
        #expect(s.lift(at: 1).executions == [.execute(page: 1, cell: 5)])
    }

    /// 上下の外枠と角では、ページを変えない（開いた直後の指は上の外枠にいる）
    @Test(arguments: [Pad.topFrame, Pad.bottomFrame, (x: 0.97, y: 0.94), (x: 0.03, y: 0.04)])
    func theTopAndBottomFramesAndCornersDoNotTurnPages(point: (x: Double, y: Double)) {
        var s = SessionScenario(pageCount: 3)
        s.slideIn(at: 0)
        s.touch(x: point.x, y: point.y, at: 0.2)
        #expect(s.engine.hud?.edgePaging == nil)
        #expect(s.tick(at: 3).visible.isEmpty)
        #expect(s.engine.pageIndex == 0)
    }

    /// 2本目の指を置いたら、端での切り替えは待たない
    @Test func aSecondFingerStopsWaitingAtTheEdge() {
        var s = SessionScenario(pageCount: 3)
        s.slideIn(at: 0)
        s.touch(x: Pad.rightFrame.x, y: Pad.rightFrame.y, at: 0.2)
        s.touch(2, x: 0.5, y: 0.5, at: 0.3)
        #expect(s.engine.hud?.edgePaging == nil)
        #expect(s.tick(at: 1).hapticEvents.isEmpty)
        #expect(s.engine.pageIndex == 0)
    }

    /// 左右の外枠のうち、ページを切り替える場所は9マスの行の横だけ
    @Test func thePagingEdgesAreBesideTheRows() {
        let grid = GridMapper(insets: .cancelFrame)
        #expect(grid.pagingEdge(x: Pad.leftFrame.x, y: Pad.leftFrame.y) == .left)
        #expect(grid.pagingEdge(x: Pad.rightFrame.x, y: Pad.rightFrame.y) == .right)
        #expect(grid.pagingEdge(x: 0.5, y: 0.5) == nil)
        #expect(grid.pagingEdge(x: Pad.topFrame.x, y: Pad.topFrame.y) == nil)
        #expect(grid.pagingEdge(x: 0.97, y: 0.94) == nil)
        #expect(grid.pagingEdge(x: 0.03, y: 0.04) == nil)
    }

    /// 行き過ぎた指を、外枠の中で動かしながらゆっくり戻している間は、止めているとは数えない（ページは変わらない）
    @Test func movingInsideTheSideFrameDoesNotTurnThePage() {
        var s = SessionScenario(pageCount: 3)
        s.slideIn(at: 0)
        s.touch(x: 0.97, y: 0.5, at: 0.2)
        var t = 0.2
        var turned = false
        while t < 1.0 {
            t += 0.02
            // 外枠の中（0.97 → 0.90）を、0.02 ごとに 0.002 ずつ（0.1/秒）戻す
            let x = 0.97 - (t - 0.2) * 0.09
            let effects = s.touch(x: x, y: 0.5, at: t) + s.tick(at: t)
            if effects.hapticEvents.contains(.pageChange) { turned = true }
        }
        #expect(!turned)
        #expect(s.engine.pageIndex == 0)
    }

    /// 外枠の中で動かした後も、そこで止め直せば edgePageDwell でページが変わる（動かした時刻から数える）
    @Test func restingAgainAfterMovingTurnsThePage() {
        var s = SessionScenario(pageCount: 3)
        s.slideIn(at: 0)
        s.touch(x: 0.96, y: 0.5, at: 0.2)
        // 0.4 秒に外枠の中で 0.05 動かし、そこで止める
        s.touch(x: 0.91, y: 0.5, at: 0.4)
        #expect(s.tick(at: 0.4 + Self.dwell - 0.01).visible.isEmpty)
        let turned = s.tick(at: 0.4 + Self.dwell)
        #expect(turned.hapticEvents == [.pageChange])
        #expect(s.engine.pageIndex == 1)
    }

    @Test func theDwellsAreSanitized() {
        let broken = SessionConfiguration(edgePageDwell: .nan, edgePageRepeat: -1).sanitized
        #expect(broken.edgePageDwell == Self.dwell)
        #expect(broken.edgePageRepeat == Self.repeatDwell)
    }
}
