// 担当: engine。外枠の帯に指を止めて、左右はページ、上下は層を切り替える（SessionConfiguration.edgePageDwell・layerStart）。1回止めて1つだけ動く
import Foundation
import NonetCore
import Testing

@Suite struct SessionEngineEdgePagingTests {
    static let dwell = SessionConfiguration.defaultEdgePageDwell

    /// 右の外枠に止めると、edgePageDwell で次のページ。止めたままでは続けて進まない（1回止めて1ページ）。
    /// 帯の中で動かして止め直せば次へ進み、最後のページの次は最初のページへ回る
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
        #expect(first.hudStates == [SessionHUDState(page: 1, highlightedCell: nil, isInFrame: true, lastTurn: .right)])
        #expect(first.hapticEvents == [.pageChange])
        // 止めたままでは、もう待たない
        #expect(first.tickRequests.allSatisfy { $0 > 5 })
        #expect(s.tick(at: 3).visible.isEmpty)
        #expect(s.engine.pageIndex == 1)

        // 帯の中で動かして止め直すと、また edgePageDwell から数える
        let moved = s.touch(x: Pad.rightFrame.x, y: Pad.rightFrame.y + 0.05, at: 3.1)
        #expect(moved.hudStates.last?.edgePaging == SessionEdgePaging(edge: .right, since: 3.1, duration: Self.dwell))
        s.tick(at: 3.1 + Self.dwell)
        #expect(s.engine.pageIndex == 2)
        // 最後のページの次は最初のページ
        s.touch(x: Pad.rightFrame.x, y: Pad.rightFrame.y - 0.05, at: 4)
        let wrapped = s.tick(at: 4 + Self.dwell)
        #expect(wrapped.hudStates.last?.page == 0)
        #expect(wrapped.hapticEvents == [.pageChange])

        // 外枠で離すのは、ページを変えた後でも、やめる操作
        let lifted = s.lift(at: 4 + Self.dwell + 0.1)
        #expect(lifted.executions.isEmpty)
        #expect(lifted.endReason == .cancelled(.liftedInFrame))
    }

    /// 左の外枠に止めると前のページ。最初のページからは最後のページへ回る
    @Test func restingOnTheLeftFrameTurnsBack() {
        var s = SessionScenario(pageCount: 3)
        s.slideIn(at: 0)
        let onEdge = s.touch(x: Pad.leftFrame.x, y: Pad.leftFrame.y, at: 0.2)
        #expect(onEdge.hudStates == [
            SessionHUDState(page: 0, highlightedCell: nil, isInFrame: true, edgePaging: SessionEdgePaging(edge: .left, since: 0.2, duration: Self.dwell)),
        ])
        let wrapped = s.tick(at: 0.2 + Self.dwell)
        #expect(wrapped.hudStates.last?.page == 2)
        #expect(wrapped.hudStates.last?.lastTurn == .left)
        #expect(wrapped.hapticEvents == [.pageChange])

        // 反対の側へ移ったら、最初から数え直す。最後のページの右は最初のページ
        let back = s.touch(x: Pad.rightFrame.x, y: Pad.rightFrame.y, at: 1)
        #expect(back.hudStates == [
            SessionHUDState(page: 2, highlightedCell: nil, isInFrame: true, edgePaging: SessionEdgePaging(edge: .right, since: 1, duration: Self.dwell), lastTurn: .left),
        ])
        let turned = s.tick(at: 1 + Self.dwell)
        #expect(turned.hudStates.last?.page == 0)
        #expect(turned.hudStates.last?.lastTurn == .right)
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

    /// 四隅では、ページも層も変わらず、触覚も鳴らない（どの側でもない。迷ったときの逃げ場）
    @Test(arguments: [(x: 0.97, y: 0.94), (x: 0.03, y: 0.04)])
    func theTopAndBottomFramesAndCornersDoNotTurnPages(point: (x: Double, y: Double)) {
        var s = SessionScenario(pageCount: 3)
        s.slideIn(at: 0)
        s.touch(x: point.x, y: point.y, at: 0.2)
        #expect(s.engine.hud?.edgePaging == nil)
        #expect(s.tick(at: 3).hapticEvents.isEmpty)
        #expect(s.engine.pageIndex == 0)
    }

    /// 層が1つ（前面のアプリのページが無い）で下のページも無いなら、上下の帯に edgePageDwell 止めると、切り替える先が無いことを
    /// 受け付けなかった触覚で1回知らせる（文字は出さない）。帯を出る・2本目の指を置くと、知らせた印は消える
    @Test func restingUpOrDownWithOneLayerShowsTheHint() {
        var s = SessionScenario(pageCount: 3)
        s.slideIn(at: 0)
        s.touch(on: 4, at: 0.1)
        let below = s.touch(x: Pad.bottomFrame.x, y: Pad.bottomFrame.y, at: 0.2)
        #expect(below.hudStates == [SessionHUDState(page: 0, highlightedCell: nil, isInFrame: true)])
        #expect(below.tickRequests == [0.2 + Self.dwell])
        #expect(s.tick(at: 0.2 + Self.dwell - 0.01).visible.isEmpty)
        let hinted = s.tick(at: 0.2 + Self.dwell)
        #expect(hinted.hudStates == [SessionHUDState(page: 0, highlightedCell: nil, isInFrame: true, edgeHint: .down)])
        #expect(hinted.hapticEvents == [.rejected])
        // 知らせた後は待たない（触覚も1回だけ）
        #expect(s.tick(at: 3).visible.isEmpty)
        #expect(s.engine.pageIndex == 0)

        // 帯を出たら消える。上の帯でも同じ
        let back = s.touch(on: 4, at: 3.1)
        #expect(back.hudStates.last?.edgeHint == nil)
        s.touch(x: Pad.topFrame.x, y: Pad.topFrame.y, at: 3.2)
        s.tick(at: 3.2 + Self.dwell)
        #expect(s.engine.hud?.edgeHint == .up)
        s.touch(2, x: 0.5, y: 0.5, at: 4)
        #expect(s.engine.hud?.edgeHint == nil)
    }

    /// 知らせるのも、帯の中で edgeRestTravel より動かしている間は止めたと数えない（ページを切り替えるのと同じ）。知らせた印は、帯の中で動かしても消さない
    @Test func movingInsideTheBandRestartsTheHintTimer() {
        var s = SessionScenario(pageCount: 3)
        s.slideIn(at: 0)
        s.touch(on: 4, at: 0.1)
        s.touch(x: Pad.bottomFrame.x, y: Pad.bottomFrame.y, at: 0.2)
        let moved = s.touch(x: Pad.bottomFrame.x + 0.05, y: Pad.bottomFrame.y, at: 0.5)
        #expect(moved.tickRequests == [0.5 + Self.dwell])
        #expect(s.tick(at: 0.2 + Self.dwell).visible.isEmpty)
        let hinted = s.tick(at: 0.5 + Self.dwell)
        #expect(hinted.hudStates.last?.edgeHint == .down)
        let movedAgain = s.touch(x: Pad.bottomFrame.x - 0.05, y: Pad.bottomFrame.y, at: 1.5)
        #expect(movedAgain.visible.isEmpty)
        #expect(s.engine.hud?.edgeHint == .down)
    }

    /// 開いた直後の指が上の帯にいる間は知らせず、動き出した（openTravel より滑らせた）時刻から数える
    @Test func theHintCountsFromWhenTheOpeningFingerMoves() {
        var s = SessionScenario(pageCount: 3)
        s.slideIn(at: 0)
        #expect(s.tick(at: 1).visible.isEmpty)
        s.touch(x: Pad.slid.x, y: Pad.slid.y + 0.025, at: 1)
        #expect(s.tick(at: 1 + Self.dwell - 0.01).visible.isEmpty)
        let hinted = s.tick(at: 1 + Self.dwell)
        #expect(hinted.hudStates.last?.edgeHint == .up)
        #expect(hinted.hapticEvents == [.rejected])
    }

    /// 層が2つでも、下のページが無ければアプリの層の下で知らせる。上へ移った後のグローバルの層の上は知らせない。
    /// 開いた直後の指（上の外枠にいることにしているだけ）でも知らせない
    @Test func theHintIsOnlyInTheMiddleRowAndNotRightAfterOpening() {
        var layered = Self.layered()
        layered.slideIn(at: 0)
        layered.touch(on: 4, at: 0.1)
        layered.touch(x: Pad.bottomFrame.x, y: Pad.bottomFrame.y, at: 0.2)
        #expect(layered.tick(at: 0.2 + Self.dwell).hapticEvents == [.rejected])
        #expect(layered.engine.hud?.edgeHint == .down)
        layered.touch(x: Pad.topFrame.x, y: Pad.topFrame.y, at: 1)
        layered.tick(at: 1 + Self.dwell)
        #expect(layered.engine.pageIndex == 2)
        layered.touch(x: Pad.topFrame.x + 0.05, y: Pad.topFrame.y, at: 2)
        #expect(layered.tick(at: 4).visible.isEmpty)
        #expect(layered.engine.hud?.edgeHint == nil)

        var justOpened = SessionScenario(pageCount: 3)
        justOpened.slideIn(at: 0)
        #expect(justOpened.tick(at: 3).visible.isEmpty)
        #expect(justOpened.engine.hud?.edgeHint == nil)
    }

    /// 横の帯の近くで開いても、開いた直後の指（上の外枠にいることにしている）は、動かさなければページを変えない
    @Test func anOpeningFingerBesideTheSideBandDoesNotTurnThePage() {
        var s = SessionScenario(pageCount: 3)
        s.touch(x: 0.05, y: 0.86, at: 0)
        s.touch(x: 0.05, y: 0.80, at: 0.05)
        s.open(at: 0.05)
        #expect(GridMapper(insets: .cancelFrame).pagingEdge(x: 0.05, y: 0.80) == .left)
        #expect(s.engine.hud?.edgePaging == nil)
        #expect(s.tick(at: 2).hapticEvents.isEmpty)
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

    /// 切り替える場所は、9マスの行の横の左右の外枠（ページ）と、列の上下の外枠（層）。四隅はどの側でもない
    @Test func thePagingEdgesAreBesideTheRowsAndColumns() {
        let grid = GridMapper(insets: .cancelFrame)
        #expect(grid.pagingEdge(x: Pad.leftFrame.x, y: Pad.leftFrame.y) == .left)
        #expect(grid.pagingEdge(x: Pad.rightFrame.x, y: Pad.rightFrame.y) == .right)
        #expect(grid.pagingEdge(x: 0.5, y: 0.5) == nil)
        #expect(grid.pagingEdge(x: Pad.topFrame.x, y: Pad.topFrame.y) == .up)
        #expect(grid.pagingEdge(x: Pad.bottomFrame.x, y: Pad.bottomFrame.y) == .down)
        #expect(grid.pagingEdge(x: 0.97, y: 0.94) == nil)
        #expect(grid.pagingEdge(x: 0.03, y: 0.04) == nil)
        // ポインタで選ぶときの、どの側でもない外枠の位置（奥の左の角）
        let neutral = ControllerPointerSelection.gridPosition(for: .frame, pagingEdge: nil)
        #expect(grid.pagingEdge(x: neutral.x, y: neutral.y) == nil)
    }

    static func layered() -> SessionScenario {
        // アプリの層に 2 ページ（0・1）、グローバルの層に 2 ページ（2・3）
        SessionScenario(SessionConfiguration(pageCount: 4, layerStart: 2))
    }

    /// 上の帯に止めるとグローバルの層の最初のページへ（強めの1打）。下の帯に止めると、上へ移る前にいたアプリのページへ戻る
    @Test func restingUpSwitchesToTheGlobalLayerAndDownReturns() {
        var s = Self.layered()
        s.slideIn(at: 0)
        s.touch(x: Pad.rightFrame.x, y: Pad.rightFrame.y, at: 0.2)
        s.tick(at: 0.2 + Self.dwell)
        #expect(s.engine.pageIndex == 1)

        let up = s.touch(x: Pad.topFrame.x, y: Pad.topFrame.y, at: 1)
        #expect(up.hudStates.last?.edgePaging?.edge == .up)
        let switched = s.tick(at: 1 + Self.dwell)
        #expect(switched.hudStates == [SessionHUDState(page: 2, highlightedCell: nil, isInFrame: true, lastTurn: .up)])
        #expect(switched.hapticEvents == [.layerChange])
        // 上にはもう層が無いので待たない
        #expect(s.tick(at: 4).visible.isEmpty)

        // グローバルの層の中で右へ
        s.touch(x: Pad.rightFrame.x, y: Pad.rightFrame.y, at: 4.1)
        s.tick(at: 4.1 + Self.dwell)
        #expect(s.engine.pageIndex == 3)

        let down = s.touch(x: Pad.bottomFrame.x, y: Pad.bottomFrame.y, at: 5)
        #expect(down.hudStates.last?.edgePaging?.edge == .down)
        let back = s.tick(at: 5 + Self.dwell)
        #expect(back.hudStates == [SessionHUDState(page: 1, highlightedCell: nil, isInFrame: true, lastTurn: .down)])
        #expect(back.hapticEvents == [.layerChange])
    }

    /// 左右はその層の中で輪になる。アプリの層の最後のページの右はアプリの層の最初のページ（グローバルへは進まない）、
    /// グローバルの層の最初のページの左はグローバルの層の最後のページ（アプリへは戻らない）
    @Test func leftAndRightWrapInsideTheLayer() {
        var s = Self.layered()
        s.slideIn(at: 0)
        s.touch(x: Pad.rightFrame.x, y: Pad.rightFrame.y, at: 0.2)
        s.tick(at: 0.2 + Self.dwell)
        #expect(s.engine.pageIndex == 1)
        #expect(s.engine.hud?.edgePaging == nil)
        s.touch(x: Pad.rightFrame.x, y: Pad.rightFrame.y + 0.05, at: 1.7)
        s.tick(at: 1.7 + Self.dwell)
        #expect(s.engine.pageIndex == 0)
        #expect(s.engine.hud?.lastTurn == .right)

        s.touch(x: Pad.topFrame.x, y: Pad.topFrame.y, at: 2.5)
        s.tick(at: 2.5 + Self.dwell)
        #expect(s.engine.pageIndex == 2)
        s.touch(x: Pad.leftFrame.x, y: Pad.leftFrame.y, at: 3)
        #expect(s.engine.hud?.edgePaging?.edge == .left)
        s.tick(at: 3 + Self.dwell)
        #expect(s.engine.pageIndex == 3)
        #expect(s.engine.hud?.lastTurn == .left)
    }

    /// ページが1つの層では、左右に止めても何も変わらない。edgePageDwell 止めると、送るページが無いことを受け付けなかった触覚で知らせる
    @Test func aLayerWithOnePageDoesNotTurnLeftOrRight() {
        // アプリの層に 1 ページ（0）、グローバルの層に 2 ページ（1・2）
        var s = SessionScenario(SessionConfiguration(pageCount: 3, layerStart: 1))
        s.slideIn(at: 0)
        s.touch(x: Pad.rightFrame.x, y: Pad.rightFrame.y, at: 0.2)
        #expect(s.engine.hud?.edgePaging == nil)
        s.touch(x: Pad.leftFrame.x, y: Pad.leftFrame.y, at: 0.3)
        #expect(s.engine.hud?.edgePaging == nil)
        let hinted = s.tick(at: 0.3 + Self.dwell)
        #expect(hinted.hudStates == [SessionHUDState(page: 0, highlightedCell: nil, isInFrame: true, edgeHint: .left)])
        #expect(hinted.hapticEvents == [.rejected])
        #expect(s.tick(at: 3).visible.isEmpty)
        #expect(s.engine.pageIndex == 0)
    }

    /// 開いた直後の指がいる上の外枠では、動かさなければ何も起きない（グローバルの層へも移らず、知らせもしない）
    @Test func restingUpInTheAppLayerDoesNothing() {
        var s = Self.layered()
        s.slideIn(at: 0)
        s.touch(x: Pad.topFrame.x, y: Pad.topFrame.y, at: 0.2)
        #expect(s.engine.hud?.edgePaging == nil)
        #expect(s.tick(at: 3).visible.isEmpty)
        #expect(s.engine.pageIndex == 0)
    }

    /// 層の境目は、どちらの層にも1ページ以上あるときだけ
    @Test func theLayerStartIsSanitized() {
        #expect(SessionConfiguration(pageCount: 3, layerStart: 2).sanitized.layerStart == 2)
        #expect(SessionConfiguration(pageCount: 3, layerStart: 3).sanitized.layerStart == nil)
        #expect(SessionConfiguration(pageCount: 3, layerStart: 0).sanitized.layerStart == nil)
        #expect(SessionConfiguration(pageCount: 3).sanitized.layerStart == nil)
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
        let broken = SessionConfiguration(edgePageDwell: .nan).sanitized
        #expect(broken.edgePageDwell == Self.dwell)
    }
}
