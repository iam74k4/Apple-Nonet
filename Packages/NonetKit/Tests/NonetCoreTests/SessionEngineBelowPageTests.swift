// 担当: engine。下のページ（SessionConfiguration.belowStart）: 真ん中の層から下の帯に止めて移り、上の帯で元のページへ戻る
import Foundation
import NonetCore
import Testing

@Suite struct SessionEngineBelowPageTests {
    static let dwell = SessionConfiguration.defaultEdgePageDwell

    /// 前面のアプリのページが無い: グローバルの層に 2 ページ（0・1）、下のページ（2）
    static func globalOnly() -> SessionScenario {
        SessionScenario(SessionConfiguration(pageCount: 3, belowStart: 2))
    }

    /// アプリの層に 2 ページ（0・1）、グローバルの層に 2 ページ（2・3）、下のページ（4）
    static func layered() -> SessionScenario {
        SessionScenario(SessionConfiguration(pageCount: 5, layerStart: 2, belowStart: 4))
    }

    /// 前面のアプリのページが無くても、下の帯に止めると下のページへ（強めの1打）。下のページの下には何も無く、知らせもしない。
    /// 上の帯に止めると、下へ移る前にいたページへ戻る
    @Test func restingDownOpensTheBelowPageAndUpReturns() {
        var s = Self.globalOnly()
        s.slideIn(at: 0)
        s.touch(x: Pad.rightFrame.x, y: Pad.rightFrame.y, at: 0.2)
        s.tick(at: 0.2 + Self.dwell)
        #expect(s.engine.pageIndex == 1)

        let down = s.touch(x: Pad.bottomFrame.x, y: Pad.bottomFrame.y, at: 1)
        #expect(down.hudStates.last?.edgePaging?.edge == .down)
        let opened = s.tick(at: 1 + Self.dwell)
        #expect(opened.hudStates == [SessionHUDState(page: 2, highlightedCell: nil, isInFrame: true, lastTurn: .down)])
        #expect(opened.hapticEvents == [.layerChange])
        // 下にはもう何も無い。下へ移った後なので、知らせもしない
        #expect(s.tick(at: 4).visible.isEmpty)
        #expect(s.engine.hud?.edgeHint == nil)

        let up = s.touch(x: Pad.topFrame.x, y: Pad.topFrame.y, at: 5)
        #expect(up.hudStates.last?.edgePaging?.edge == .up)
        let back = s.tick(at: 5 + Self.dwell)
        #expect(back.hudStates == [SessionHUDState(page: 1, highlightedCell: nil, isInFrame: true, lastTurn: .up)])
        #expect(back.hapticEvents == [.layerChange])
    }

    /// 下のページは1ページの層: 左右に止めても送らず、送るページが無いことを触覚で知らせる。真ん中の層の左右にも入らない
    @Test func theBelowPageIsALayerOfItsOwn() {
        var s = Self.globalOnly()
        s.slideIn(at: 0)
        // グローバルの層の2ページの中で回り、下のページへは進まない
        s.touch(x: Pad.leftFrame.x, y: Pad.leftFrame.y, at: 0.2)
        s.tick(at: 0.2 + Self.dwell)
        #expect(s.engine.pageIndex == 1)

        s.touch(x: Pad.bottomFrame.x, y: Pad.bottomFrame.y, at: 1)
        s.tick(at: 1 + Self.dwell)
        #expect(s.engine.pageIndex == 2)
        s.touch(x: Pad.rightFrame.x, y: Pad.rightFrame.y, at: 2)
        #expect(s.engine.hud?.edgePaging == nil)
        let hinted = s.tick(at: 2 + Self.dwell)
        #expect(hinted.hudStates.last?.edgeHint == .right)
        #expect(hinted.hapticEvents == [.rejected])
        #expect(s.engine.pageIndex == 2)
    }

    /// 前面のアプリのページが無いときの上の帯は、知らせるだけ（グローバルの層が無い）
    @Test func restingUpWithoutAnAppLayerOnlyBuzzes() {
        var s = Self.globalOnly()
        s.slideIn(at: 0)
        s.touch(on: 4, at: 0.1)
        s.touch(x: Pad.topFrame.x, y: Pad.topFrame.y, at: 0.2)
        #expect(s.engine.hud?.edgePaging == nil)
        let hinted = s.tick(at: 0.2 + Self.dwell)
        #expect(hinted.hudStates == [SessionHUDState(page: 0, highlightedCell: nil, isInFrame: true, edgeHint: .up)])
        #expect(hinted.hapticEvents == [.rejected])
        #expect(s.engine.pageIndex == 0)
    }

    /// 下のページから上で戻った指を帯に残していても、真ん中の層の上では知らせない（止めたまま2回目の反応をしない）
    @Test func noHintAfterComingBackWhileStillResting() {
        var s = Self.globalOnly()
        s.slideIn(at: 0)
        s.touch(on: 4, at: 0.1)
        s.touch(x: Pad.bottomFrame.x, y: Pad.bottomFrame.y, at: 0.2)
        s.tick(at: 0.2 + Self.dwell)
        s.touch(x: Pad.topFrame.x, y: Pad.topFrame.y, at: 1)
        s.tick(at: 1 + Self.dwell)
        #expect(s.engine.pageIndex == 0)
        #expect(s.tick(at: 4).visible.isEmpty)
        #expect(s.engine.hud?.edgeHint == nil)
        // 帯の中で動かして止め直せば知らせる
        s.touch(x: Pad.topFrame.x + 0.05, y: Pad.topFrame.y, at: 4.1)
        #expect(s.tick(at: 4.1 + Self.dwell).hapticEvents == [.rejected])
        #expect(s.engine.hud?.edgeHint == .up)
    }

    /// 上下は3段を1段ずつ: アプリの層から下で下のページ、上でアプリの層の元のページ、止め直してもう一度上でグローバルの層、
    /// 下でアプリの層の元のページ（グローバルの層からは、下のページへ飛ばない）。止めたままでは1段だけで、待たない
    @Test func upAndDownMoveOneRowAtATime() {
        var s = Self.layered()
        s.slideIn(at: 0)
        s.touch(x: Pad.rightFrame.x, y: Pad.rightFrame.y, at: 0.2)
        s.tick(at: 0.2 + Self.dwell)
        #expect(s.engine.pageIndex == 1)

        s.touch(x: Pad.bottomFrame.x, y: Pad.bottomFrame.y, at: 1)
        s.tick(at: 1 + Self.dwell)
        #expect(s.engine.pageIndex == 4)

        s.touch(x: Pad.topFrame.x, y: Pad.topFrame.y, at: 2)
        s.tick(at: 2 + Self.dwell)
        #expect(s.engine.pageIndex == 1)
        // 止めたままでは、もう1段上のグローバルの層へは進まない（待たない）
        #expect(s.engine.hud?.edgePaging == nil)
        #expect(s.tick(at: 4).visible.isEmpty)
        #expect(s.engine.pageIndex == 1)
        // 帯の中で動かして止め直すと進む
        s.touch(x: Pad.topFrame.x + 0.05, y: Pad.topFrame.y, at: 4.1)
        s.tick(at: 4.1 + Self.dwell)
        #expect(s.engine.pageIndex == 2)
        #expect(s.engine.hud?.lastTurn == .up)

        s.touch(x: Pad.bottomFrame.x, y: Pad.bottomFrame.y, at: 5)
        s.tick(at: 5 + Self.dwell)
        #expect(s.engine.pageIndex == 1)
        #expect(s.engine.hud?.lastTurn == .down)
    }

    /// 2本指で縦に動かしても、上下には移らない（ページを動かすのは、輪の外で止めることだけ）
    @Test func aVerticalTwoFingerSwipeDoesNothing() {
        var s = Self.globalOnly()
        s.slideIn(at: 0)
        s.touch(on: 4, at: 0.1)
        s.setFingers([(1, 0.5, 0.6), (2, 0.6, 0.6)], at: 0.2)
        let swipe = s.setFingers([(1, 0.5, 0.2), (2, 0.6, 0.2)], at: 0.3)
        #expect(swipe.visible.isEmpty)
        #expect(s.engine.pageIndex == 0)
    }

    /// 下のページは、その前に1ページ以上あるときだけ。グローバルの層の境目は、下のページより前のときだけ
    @Test func theBelowStartIsSanitized() {
        #expect(SessionConfiguration(pageCount: 3, belowStart: 2).sanitized.belowStart == 2)
        #expect(SessionConfiguration(pageCount: 3, belowStart: 3).sanitized.belowStart == nil)
        #expect(SessionConfiguration(pageCount: 3, belowStart: 0).sanitized.belowStart == nil)
        let noGlobalLayer = SessionConfiguration(pageCount: 3, layerStart: 2, belowStart: 2).sanitized
        #expect(noGlobalLayer.belowStart == 2)
        #expect(noGlobalLayer.layerStart == nil)
        #expect(SessionConfiguration(pageCount: 5, layerStart: 2, belowStart: 4).sanitized.layerStart == 2)
    }
}
