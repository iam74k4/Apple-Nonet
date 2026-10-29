import CoreGraphics
import NonetCore
import Testing
@testable import NonetPlatform

@Suite struct InputPointerSuppressorTests {
    typealias Kind = PointerEventKind

    private func event(_ type: UInt32, button: Int64 = 0) -> PointerEventInfo {
        PointerEventInfo(type: type, buttonNumber: button)
    }

    private func scroll(phase: Int64, momentum: Int64) -> PointerEventInfo {
        PointerEventInfo(type: Kind.scrollWheel, scrollPhase: phase, momentumPhase: momentum)
    }

    @Test func suppressedTypesMatchTheSpec() {
        let expected: Set<UInt32> = [1, 2, 3, 4, 5, 6, 7, 18, 19, 20, 22, 25, 26, 27, 29, 30, 31, 32, 33, 34, 37]
        #expect(Kind.all == expected)
        for type in UInt32(0)...40 {
            #expect(Kind.isPointer(type) == expected.contains(type), "type \(type)")
        }
        // キーボードは対象外
        #expect(!Kind.isPointer(CGEventType.keyDown.rawValue))
        #expect(!Kind.isPointer(CGEventType.keyUp.rawValue))
        #expect(!Kind.isPointer(CGEventType.flagsChanged.rawValue))
    }

    @Test func buttonsAndMovesAreClassified() {
        #expect(Kind.downButton(1, buttonNumber: 9) == 0)
        #expect(Kind.downButton(3, buttonNumber: 9) == 1)
        #expect(Kind.downButton(25, buttonNumber: 4) == 4)
        #expect(Kind.upButton(2, buttonNumber: 9) == 0)
        #expect(Kind.upButton(4, buttonNumber: 9) == 1)
        #expect(Kind.upButton(26, buttonNumber: 4) == 4)
        #expect(Kind.dragButton(6, buttonNumber: 9) == 0)
        #expect(Kind.dragButton(7, buttonNumber: 9) == 1)
        #expect(Kind.dragButton(27, buttonNumber: 2) == 2)
        #expect(Kind.downButton(5, buttonNumber: 0) == nil)
        #expect([5, 6, 7, 27].allSatisfy(Kind.isMove))
        #expect(![1, 2, 22, 29].contains(where: Kind.isMove))
        #expect(Kind.needsButtonNumber(25) && Kind.needsButtonNumber(26) && Kind.needsButtonNumber(27))
        #expect(!Kind.needsButtonNumber(1))
    }

    @Test func passesEverythingWhenNotSuppressing() {
        var suppressor = PointerSuppressor()
        for type in Kind.all.sorted() {
            #expect(suppressor.decide(event(type), suppressing: false, dropsMoves: true) == .pass, "type \(type)")
        }
        #expect(suppressor.droppedButtons.isEmpty)
    }

    @Test func dropsPointerEventsWhileSuppressing() {
        var suppressor = PointerSuppressor()
        let dropped: [UInt32] = [5, 6, 7, 18, 19, 20, 22, 27, 29, 30, 31, 32, 33, 34, 37]
        for type in dropped {
            #expect(suppressor.decide(event(type), suppressing: true, dropsMoves: true) == .drop, "type \(type)")
        }
    }

    @Test func dropsTheUpOfADroppedDownEvenAfterSuppressionEnds() {
        var suppressor = PointerSuppressor()
        #expect(suppressor.decide(event(Kind.leftMouseDown), suppressing: true, dropsMoves: true) == .drop)
        #expect(suppressor.droppedButtons == [0])
        #expect(suppressor.decide(event(Kind.leftMouseUp), suppressing: false, dropsMoves: false) == .drop)
        #expect(suppressor.droppedButtons.isEmpty)
        // 次のクリックは普通に通る
        #expect(suppressor.decide(event(Kind.leftMouseDown), suppressing: false, dropsMoves: false) == .pass)
        #expect(suppressor.decide(event(Kind.leftMouseUp), suppressing: false, dropsMoves: false) == .pass)
    }

    @Test func passesTheUpOfADownThatWasPassedEvenWhileSuppressing() {
        var suppressor = PointerSuppressor()
        #expect(suppressor.decide(event(Kind.rightMouseDown), suppressing: false, dropsMoves: true) == .pass)
        #expect(suppressor.decide(event(Kind.rightMouseUp), suppressing: true, dropsMoves: true) == .pass)
    }

    @Test func tracksOtherButtonsByNumber() {
        var suppressor = PointerSuppressor()
        #expect(suppressor.decide(event(Kind.otherMouseDown, button: 3), suppressing: false, dropsMoves: true) == .pass)
        #expect(suppressor.decide(event(Kind.otherMouseDown, button: 2), suppressing: true, dropsMoves: true) == .drop)
        #expect(suppressor.decide(event(Kind.otherMouseUp, button: 3), suppressing: true, dropsMoves: true) == .pass)
        #expect(suppressor.decide(event(Kind.otherMouseUp, button: 2), suppressing: false, dropsMoves: true) == .drop)
        #expect(suppressor.droppedButtons.isEmpty)
    }

    @Test func aFreshDownClearsAStaleDroppedButton() {
        var suppressor = PointerSuppressor()
        _ = suppressor.decide(event(Kind.leftMouseDown), suppressing: true, dropsMoves: true)
        // 離すイベントを取りこぼした（タップが無効になっていた）まま、普通にクリックする
        #expect(suppressor.decide(event(Kind.leftMouseDown), suppressing: false, dropsMoves: true) == .pass)
        #expect(suppressor.decide(event(Kind.leftMouseUp), suppressing: false, dropsMoves: true) == .pass)
    }

    @Test func dragsOfADroppedButtonBecomeMovesAfterSuppression() {
        var suppressor = PointerSuppressor()
        _ = suppressor.decide(event(Kind.leftMouseDown), suppressing: true, dropsMoves: true)
        #expect(suppressor.decide(event(Kind.leftMouseDragged), suppressing: true, dropsMoves: true) == .drop)
        #expect(suppressor.decide(event(Kind.leftMouseDragged), suppressing: false, dropsMoves: false) == .passAsMove)
        #expect(suppressor.decide(event(Kind.rightMouseDragged), suppressing: false, dropsMoves: false) == .pass)
        #expect(suppressor.decide(event(Kind.leftMouseUp), suppressing: false, dropsMoves: false) == .drop)
        #expect(suppressor.decide(event(Kind.leftMouseDragged), suppressing: false, dropsMoves: false) == .pass)
    }

    @Test func withoutCursorLockMovesPassButClicksAreStillDropped() {
        var suppressor = PointerSuppressor()
        #expect(suppressor.decide(event(Kind.mouseMoved), suppressing: true, dropsMoves: false) == .pass)
        // セッションの前から押していたボタンのドラッグは、そのまま渡す
        _ = suppressor.decide(event(Kind.leftMouseDown), suppressing: false, dropsMoves: false)
        #expect(suppressor.decide(event(Kind.leftMouseDragged), suppressing: true, dropsMoves: false) == .pass)
        #expect(suppressor.decide(event(Kind.leftMouseUp), suppressing: true, dropsMoves: false) == .pass)
        #expect(suppressor.decide(event(Kind.rightMouseDown), suppressing: true, dropsMoves: false) == .drop)
        #expect(suppressor.decide(event(Kind.rightMouseDragged), suppressing: true, dropsMoves: false) == .passAsMove)
        #expect(suppressor.decide(event(Kind.scrollWheel), suppressing: true, dropsMoves: false) == .drop)
        #expect(suppressor.decide(event(31), suppressing: true, dropsMoves: false) == .drop)
    }

    @Test func dropsTheScrollMomentumThatStartedDuringSuppression() {
        var suppressor = PointerSuppressor()
        #expect(suppressor.decide(scroll(phase: 1, momentum: 0), suppressing: true, dropsMoves: true) == .drop)
        #expect(suppressor.decide(scroll(phase: 2, momentum: 0), suppressing: true, dropsMoves: true) == .drop)
        // トリガーを離した後もジェスチャーと慣性は続く
        #expect(suppressor.decide(scroll(phase: 2, momentum: 0), suppressing: false, dropsMoves: false) == .drop)
        #expect(suppressor.decide(scroll(phase: 4, momentum: 0), suppressing: false, dropsMoves: false) == .drop)
        #expect(suppressor.decide(scroll(phase: 0, momentum: 1), suppressing: false, dropsMoves: false) == .drop)
        #expect(suppressor.decide(scroll(phase: 0, momentum: 2), suppressing: false, dropsMoves: false) == .drop)
        #expect(suppressor.decide(scroll(phase: 0, momentum: 3), suppressing: false, dropsMoves: false) == .drop)
        #expect(!suppressor.isDroppingScrollTail)
        #expect(suppressor.decide(scroll(phase: 2, momentum: 0), suppressing: false, dropsMoves: false) == .pass)
    }

    @Test(arguments: [(Int64(1), Int64(0)), (Int64(128), Int64(0)), (Int64(0), Int64(0))])
    func aNewScrollEndsTheDroppedTail(phase: Int64, momentum: Int64) {
        var suppressor = PointerSuppressor()
        _ = suppressor.decide(scroll(phase: 2, momentum: 0), suppressing: true, dropsMoves: true)
        #expect(suppressor.decide(scroll(phase: phase, momentum: momentum), suppressing: false, dropsMoves: false) == .pass)
        #expect(!suppressor.isDroppingScrollTail)
    }

    @Test func scrollWithoutTailPasses() {
        var suppressor = PointerSuppressor()
        #expect(suppressor.decide(scroll(phase: 0, momentum: 2), suppressing: false, dropsMoves: false) == .pass)
    }

    @Test func gesturesPassOutsideSuppression() {
        var suppressor = PointerSuppressor()
        for type in Kind.gestures {
            #expect(suppressor.decide(event(type), suppressing: true, dropsMoves: false) == .drop)
            #expect(suppressor.decide(event(type), suppressing: false, dropsMoves: true) == .pass)
        }
    }

    @Test func cursorLockPlans() {
        #expect(CursorLockPlan(.automatic) == CursorLockPlan(dropsMoves: true, warpsBack: true, decouples: false))
        #expect(CursorLockPlan(.dropEvents) == CursorLockPlan(dropsMoves: true, warpsBack: false, decouples: false))
        #expect(CursorLockPlan(.decouple) == CursorLockPlan(dropsMoves: true, warpsBack: false, decouples: true))
        #expect(CursorLockPlan(.none) == CursorLockPlan(dropsMoves: false, warpsBack: false, decouples: false))
    }

    @Test func warpOnlyWhenTheCursorReallyMoved() {
        let anchor = CGPoint(x: 100, y: 200)
        #expect(!CursorLockPlan.needsWarp(from: anchor, to: anchor))
        #expect(!CursorLockPlan.needsWarp(from: anchor, to: CGPoint(x: 100.4, y: 199.6)))
        #expect(CursorLockPlan.needsWarp(from: anchor, to: CGPoint(x: 101, y: 200)))
        #expect(CursorLockPlan.needsWarp(from: anchor, to: CGPoint(x: 100, y: 190)))
    }
}
