// 担当: engine。外枠の帯に指を止めて、左右はページ、上下は層を切り替える（SessionConfiguration.edgePageDwell・edgePageRepeat・layerStart）
import Foundation
import NonetCore
import Testing

@Suite struct SessionEngineEdgePagingTests {
    static let dwell = SessionConfiguration.defaultEdgePageDwell
    static let repeatDwell = SessionConfiguration.defaultEdgePageRepeat

    /// 右の外枠に止めると、edgePageDwell で次のページ。止めたままなら edgePageRepeat ごとに進み、最後のページの次は最初のページへ回る
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
            SessionHUDState(page: 1, highlightedCell: nil, isInFrame: true, edgePaging: SessionEdgePaging(edge: .right, since: 0.7, duration: Self.repeatDwell), lastTurn: .right),
        ])
        #expect(first.hapticEvents == [.pageChange])

        // 最後のページへ。層の中で輪になるので、そこからも待ち続け、次は最初のページへ回る
        let second = 0.7 + Self.repeatDwell
        let toLast = s.tick(at: second)
        #expect(toLast.hudStates == [
            SessionHUDState(page: 2, highlightedCell: nil, isInFrame: true, edgePaging: SessionEdgePaging(edge: .right, since: second, duration: Self.repeatDwell), lastTurn: .right),
        ])
        #expect(toLast.hapticEvents == [.pageChange])
        let third = second + Self.repeatDwell
        let wrapped = s.tick(at: third)
        #expect(wrapped.hudStates == [
            SessionHUDState(page: 0, highlightedCell: nil, isInFrame: true, edgePaging: SessionEdgePaging(edge: .right, since: third, duration: Self.repeatDwell), lastTurn: .right),
        ])
        #expect(wrapped.hapticEvents == [.pageChange])
        #expect(s.engine.pageIndex == 0)

        // 外枠で離すのは、ページを変えた後でも、やめる操作
        let lifted = s.lift(at: third + 0.1)
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

    /// 層が1つなら、上下の外枠と角ではページも層も変わらず、触覚も鳴らない（開いた直後の指は上の外枠にいる）。
    /// 上下では案内だけを出す（restingUpOrDownWithOneLayerShowsTheHint）
    @Test(arguments: [Pad.topFrame, Pad.bottomFrame, (x: 0.97, y: 0.94), (x: 0.03, y: 0.04)])
    func theTopAndBottomFramesAndCornersDoNotTurnPages(point: (x: Double, y: Double)) {
        var s = SessionScenario(pageCount: 3)
        s.slideIn(at: 0)
        s.touch(x: point.x, y: point.y, at: 0.2)
        #expect(s.engine.hud?.edgePaging == nil)
        #expect(s.tick(at: 3).hapticEvents.isEmpty)
        #expect(s.engine.pageIndex == 0)
    }

    /// 層が1つ（前面のアプリのページが無い）なら、上下の帯に edgePageDwell 止めると、切り替える先が無いことを HUD が案内する
    /// （触覚は鳴らさない）。帯を出る・2本目の指を置くと消える
    @Test func restingUpOrDownWithOneLayerShowsTheHint() {
        var s = SessionScenario(pageCount: 3)
        s.slideIn(at: 0)
        s.touch(on: 4, at: 0.1)
        let below = s.touch(x: Pad.bottomFrame.x, y: Pad.bottomFrame.y, at: 0.2)
        #expect(below.hudStates == [SessionHUDState(page: 0, highlightedCell: nil, isInFrame: true)])
        #expect(below.tickRequests == [0.2 + Self.dwell])
        #expect(s.tick(at: 0.2 + Self.dwell - 0.01).visible.isEmpty)
        let hinted = s.tick(at: 0.2 + Self.dwell)
        #expect(hinted.hudStates == [SessionHUDState(page: 0, highlightedCell: nil, isInFrame: true, layerHint: .down)])
        #expect(hinted.hapticEvents.isEmpty)
        // 案内した後は待たない
        #expect(s.tick(at: 3).visible.isEmpty)
        #expect(s.engine.pageIndex == 0)

        // 帯を出たら消える。上の帯でも同じ
        let back = s.touch(on: 4, at: 3.1)
        #expect(back.hudStates.last?.layerHint == nil)
        s.touch(x: Pad.topFrame.x, y: Pad.topFrame.y, at: 3.2)
        s.tick(at: 3.2 + Self.dwell)
        #expect(s.engine.hud?.layerHint == .up)
        s.touch(2, x: 0.5, y: 0.5, at: 4)
        #expect(s.engine.hud?.layerHint == nil)
    }

    /// 層が2つなら、上下に止めても案内しない（アプリの層の上・グローバルの層の下）。開いた直後の指（上の外枠にいることにしているだけ）でも案内しない
    @Test func theHintIsOnlyForOneLayerAndNotRightAfterOpening() {
        var layered = Self.layered()
        layered.slideIn(at: 0)
        layered.touch(on: 4, at: 0.1)
        layered.touch(x: Pad.topFrame.x, y: Pad.topFrame.y, at: 0.2)
        #expect(layered.tick(at: 3).visible.isEmpty)
        #expect(layered.engine.hud?.layerHint == nil)

        var justOpened = SessionScenario(pageCount: 3)
        justOpened.slideIn(at: 0)
        #expect(justOpened.tick(at: 3).visible.isEmpty)
        #expect(justOpened.engine.hud?.layerHint == nil)
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

    /// 下の帯に止めるとグローバルの層の最初のページへ（強めの1打）。上の帯に止めると、下へ移る前にいたアプリのページへ戻る
    @Test func restingDownSwitchesToTheGlobalLayerAndUpReturns() {
        var s = Self.layered()
        s.slideIn(at: 0)
        s.touch(x: Pad.rightFrame.x, y: Pad.rightFrame.y, at: 0.2)
        s.tick(at: 0.2 + Self.dwell)
        #expect(s.engine.pageIndex == 1)

        let down = s.touch(x: Pad.bottomFrame.x, y: Pad.bottomFrame.y, at: 1)
        #expect(down.hudStates.last?.edgePaging?.edge == .down)
        let switched = s.tick(at: 1 + Self.dwell)
        #expect(switched.hudStates == [SessionHUDState(page: 2, highlightedCell: nil, isInFrame: true, lastTurn: .down)])
        #expect(switched.hapticEvents == [.layerChange])
        // 下にはもう層が無いので待たない
        #expect(s.tick(at: 4).visible.isEmpty)

        // グローバルの層の中で右へ
        s.touch(x: Pad.rightFrame.x, y: Pad.rightFrame.y, at: 4.1)
        s.tick(at: 4.1 + Self.dwell)
        #expect(s.engine.pageIndex == 3)

        let up = s.touch(x: Pad.topFrame.x, y: Pad.topFrame.y, at: 5)
        #expect(up.hudStates.last?.edgePaging?.edge == .up)
        let back = s.tick(at: 5 + Self.dwell)
        #expect(back.hudStates == [SessionHUDState(page: 1, highlightedCell: nil, isInFrame: true, lastTurn: .up)])
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
        s.tick(at: 0.2 + Self.dwell + Self.repeatDwell)
        #expect(s.engine.pageIndex == 0)
        #expect(s.engine.hud?.lastTurn == .right)

        s.touch(x: Pad.bottomFrame.x, y: Pad.bottomFrame.y, at: 2)
        s.tick(at: 2 + Self.dwell)
        #expect(s.engine.pageIndex == 2)
        s.touch(x: Pad.leftFrame.x, y: Pad.leftFrame.y, at: 3)
        #expect(s.engine.hud?.edgePaging?.edge == .left)
        s.tick(at: 3 + Self.dwell)
        #expect(s.engine.pageIndex == 3)
        #expect(s.engine.hud?.lastTurn == .left)
    }

    /// ページが1つの層では、左右に止めても何も変わらず、待たない。横のスワイプは受け付けなかった触覚
    @Test func aLayerWithOnePageDoesNotTurnLeftOrRight() {
        // アプリの層に 1 ページ（0）、グローバルの層に 2 ページ（1・2）
        var s = SessionScenario(SessionConfiguration(pageCount: 3, layerStart: 1))
        s.slideIn(at: 0)
        s.touch(x: Pad.rightFrame.x, y: Pad.rightFrame.y, at: 0.2)
        #expect(s.engine.hud?.edgePaging == nil)
        s.touch(x: Pad.leftFrame.x, y: Pad.leftFrame.y, at: 0.3)
        #expect(s.engine.hud?.edgePaging == nil)
        #expect(s.tick(at: 3).visible.isEmpty)
        #expect(s.engine.pageIndex == 0)
        s.setFingers([(1, 0.5, 0.5), (2, 0.7, 0.5)], at: 3.1)
        let swipe = s.setFingers([(1, 0.35, 0.5), (2, 0.55, 0.5)], at: 3.2)
        #expect(swipe.hapticEvents == [.rejected])
        #expect(s.engine.pageIndex == 0)
    }

    /// アプリの層では、上の帯に止めても何も起きない（開いた直後の指がいる上の外枠で、層が変わらない）
    @Test func restingUpInTheAppLayerDoesNothing() {
        var s = Self.layered()
        s.slideIn(at: 0)
        s.touch(x: Pad.topFrame.x, y: Pad.topFrame.y, at: 0.2)
        #expect(s.engine.hud?.edgePaging == nil)
        #expect(s.tick(at: 3).visible.isEmpty)
        #expect(s.engine.pageIndex == 0)
    }

    /// 2本指の横のスワイプも、その層の中でページを送り、端からは反対の端へ回る
    @Test func aTwoFingerSwipeWrapsInsideTheLayer() {
        var s = Self.layered()
        s.slideIn(at: 0)
        s.touch(x: Pad.rightFrame.x, y: Pad.rightFrame.y, at: 0.2)
        s.tick(at: 0.2 + Self.dwell)
        #expect(s.engine.pageIndex == 1)
        s.setFingers([(1, 0.5, 0.5), (2, 0.7, 0.5)], at: 1)
        // 指を左へ（次のページ）。アプリの層の最後のページなので、アプリの層の最初のページへ（グローバルへは進まない）
        let swipe = s.setFingers([(1, 0.35, 0.5), (2, 0.55, 0.5)], at: 1.1)
        #expect(swipe.hudStates == [SessionHUDState(page: 0, highlightedCell: nil, lastTurn: .right)])
        #expect(swipe.hapticEvents == [.pageChange])
    }

    /// 2本指の縦のスワイプで層を切り替える。指を奥へ動かすとグローバルの層へ、手前へ動かすとアプリの層へ戻る（強めの1打）
    @Test func aVerticalTwoFingerSwipeSwitchesLayers() {
        var s = Self.layered()
        s.slideIn(at: 0)
        s.touch(on: 4, at: 0.1)
        s.setFingers([(1, 0.5, 0.4), (2, 0.6, 0.4)], at: 0.2)
        let down = s.setFingers([(1, 0.5, 0.6), (2, 0.6, 0.6)], at: 0.3)
        #expect(down.hudStates == [SessionHUDState(page: 2, highlightedCell: nil, lastTurn: .down)])
        #expect(down.hapticEvents == [.layerChange])
        // 1回のスワイプで1回だけ
        #expect(s.setFingers([(1, 0.5, 0.8), (2, 0.6, 0.8)], at: 0.4).visible.isEmpty)
        s.setFingers([(1, 0.5, 0.5)], at: 0.5)
        s.setFingers([(1, 0.5, 0.6), (2, 0.6, 0.6)], at: 0.6)
        let up = s.setFingers([(1, 0.5, 0.4), (2, 0.6, 0.4)], at: 0.7)
        #expect(up.hudStates == [SessionHUDState(page: 0, highlightedCell: nil, lastTurn: .up)])
        #expect(up.hapticEvents == [.layerChange])
    }

    /// 層が1つなら、縦のスワイプでは何も変わらない（受け付けなかった触覚）。縦より横が大きければページ
    @Test func aVerticalSwipeWithOneLayerIsRejected() {
        var s = SessionScenario(pageCount: 3)
        s.slideIn(at: 0)
        s.setFingers([(1, 0.5, 0.4), (2, 0.6, 0.4)], at: 0.2)
        let swipe = s.setFingers([(1, 0.5, 0.6), (2, 0.6, 0.6)], at: 0.3)
        #expect(swipe.hapticEvents == [.rejected])
        #expect(s.engine.pageIndex == 0)
        s.setFingers([(1, 0.5, 0.5)], at: 0.4)
        s.setFingers([(1, 0.5, 0.5), (2, 0.7, 0.5)], at: 0.5)
        let diagonal = s.setFingers([(1, 0.3, 0.55), (2, 0.5, 0.55)], at: 0.6)
        #expect(diagonal.hapticEvents == [.pageChange])
        #expect(s.engine.pageIndex == 1)
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
        let broken = SessionConfiguration(edgePageDwell: .nan, edgePageRepeat: -1).sanitized
        #expect(broken.edgePageDwell == Self.dwell)
        #expect(broken.edgePageRepeat == Self.repeatDwell)
    }
}
