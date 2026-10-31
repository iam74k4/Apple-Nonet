import CoreGraphics
import Foundation
import NonetCore
import Testing
@testable import NonetPlatform

/// 時刻が関わらないテスト用（抑止の後にクリックを捨てる間も、捨てたボタンを忘れるまでの時間も使わない）
private extension PointerSuppressor {
    mutating func decide(_ event: PointerEventInfo, suppressing: Bool, dropsMoves: Bool) -> Decision {
        decide(event, suppressing: suppressing, dropsMoves: dropsMoves, now: 0)
    }

    mutating func sweep(isPhysicallyPressed: (Int64) -> Bool) {
        sweep(isPhysicallyPressed: isPhysicallyPressed, now: 0)
    }

    func needsEvents(suppressing: Bool) -> Bool {
        needsEvents(suppressing: suppressing, now: 0)
    }
}

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

    // MARK: タップを残す間と片付け

    @Test func needsEventsWhileSuppressingOrWaitingForUpsAndScrollTails() {
        var suppressor = PointerSuppressor()
        #expect(!suppressor.needsEvents(suppressing: false))
        #expect(suppressor.needsEvents(suppressing: true))
        _ = suppressor.decide(event(Kind.otherMouseDown, button: 4), suppressing: true, dropsMoves: true)
        #expect(suppressor.isTracking)
        #expect(suppressor.needsEvents(suppressing: false))
        _ = suppressor.decide(event(Kind.otherMouseUp, button: 4), suppressing: false, dropsMoves: false)
        #expect(!suppressor.needsEvents(suppressing: false))
        _ = suppressor.decide(scroll(phase: 2, momentum: 0), suppressing: true, dropsMoves: true)
        #expect(suppressor.needsEvents(suppressing: false))
        _ = suppressor.decide(scroll(phase: 0, momentum: 3), suppressing: false, dropsMoves: false)
        #expect(!suppressor.needsEvents(suppressing: false))
        // 渡した押下は待たない
        _ = suppressor.decide(event(Kind.leftMouseDown), suppressing: false, dropsMoves: false)
        #expect(!suppressor.needsEvents(suppressing: false))
    }

    @Test func sweepKeepsARecentlyDroppedButtonEvenIfItLooksReleased() {
        var suppressor = PointerSuppressor()
        _ = suppressor.decide(event(Kind.leftMouseDown), suppressing: true, dropsMoves: true)
        suppressor.sweep(isPhysicallyPressed: { _ in false })
        suppressor.sweep(isPhysicallyPressed: { _ in false })
        #expect(suppressor.droppedButtons == [0])
    }

    @Test func sweepForgetsADroppedButtonWhoseUpNeverCame() {
        // セッション中に右クリックを捨て、離すが届く前にマウスが外れた
        var suppressor = PointerSuppressor()
        #expect(suppressor.decide(event(Kind.rightMouseDown), suppressing: true, dropsMoves: true, now: 10) == .drop)
        // 物理的に離れて見えても、押した直後は忘れない（捨てた押下が物理的な状態に反映されるかは分からない）
        suppressor.sweep(isPhysicallyPressed: { _ in false }, now: 10.5)
        suppressor.sweep(isPhysicallyPressed: { _ in false }, now: 11)
        suppressor.sweep(isPhysicallyPressed: { _ in false }, now: 11.5)
        #expect(suppressor.droppedButtons == [1])
        #expect(suppressor.needsEvents(suppressing: false, now: 11.5))
        suppressor.sweep(isPhysicallyPressed: { _ in false }, now: 10 + PointerSuppressor.staleButtonAge)
        #expect(suppressor.droppedButtons.isEmpty)
        #expect(!suppressor.needsEvents(suppressing: false, now: 12))
        // 次の右クリックは普通に通る
        #expect(suppressor.decide(event(Kind.rightMouseDown), suppressing: false, dropsMoves: true, now: 13) == .pass)
        #expect(suppressor.decide(event(Kind.rightMouseUp), suppressing: false, dropsMoves: true, now: 13.1) == .pass)
    }

    @Test func sweepNeedsTheButtonToLookReleasedTwiceInARow() {
        var suppressor = PointerSuppressor()
        _ = suppressor.decide(event(Kind.otherMouseDown, button: 3), suppressing: true, dropsMoves: true, now: 0)
        suppressor.sweep(isPhysicallyPressed: { _ in false }, now: 5)
        #expect(suppressor.droppedButtons == [3])
        // 押したままに見えたら数え直す
        suppressor.sweep(isPhysicallyPressed: { _ in true }, now: 5.5)
        suppressor.sweep(isPhysicallyPressed: { _ in false }, now: 6)
        #expect(suppressor.droppedButtons == [3])
        suppressor.sweep(isPhysicallyPressed: { _ in false }, now: 6.5)
        #expect(suppressor.droppedButtons.isEmpty)
    }

    @Test func sweepKeepsAButtonThatIsStillHeld() {
        var suppressor = PointerSuppressor()
        _ = suppressor.decide(event(Kind.leftMouseDown), suppressing: true, dropsMoves: true, now: 0)
        for time in stride(from: 0.5, through: 10, by: 0.5) {
            suppressor.sweep(isPhysicallyPressed: { _ in true }, now: time)
        }
        #expect(suppressor.droppedButtons == [0])
        #expect(suppressor.decide(event(Kind.leftMouseUp), suppressing: false, dropsMoves: true, now: 10.2) == .drop)
    }

    @Test func sweepForgetsReleasedButtonsAfterEventsWereMissed() {
        var suppressor = PointerSuppressor()
        _ = suppressor.decide(event(Kind.leftMouseDown), suppressing: true, dropsMoves: true)
        _ = suppressor.decide(event(Kind.otherMouseDown, button: 3), suppressing: true, dropsMoves: true)
        suppressor.eventsMayHaveBeenMissed()
        #expect(suppressor.buttonsWithPossiblyMissedUp == [0, 3])
        // 無効にされた後で押したボタンの離すは取りこぼしていない
        _ = suppressor.decide(event(Kind.rightMouseDown), suppressing: true, dropsMoves: true)
        suppressor.sweep(isPhysicallyPressed: { $0 == 3 })
        #expect(suppressor.droppedButtons == [1, 3])
        #expect(suppressor.buttonsWithPossiblyMissedUp.isEmpty)
        // まだ押していたボタンの離すは、あとで届けばいつもどおり捨てる
        suppressor.sweep(isPhysicallyPressed: { _ in false })
        #expect(suppressor.droppedButtons == [1, 3])
        #expect(suppressor.decide(event(Kind.otherMouseUp, button: 3), suppressing: false, dropsMoves: false) == .drop)
    }

    @Test func anUpOrDownClearsThePossiblyMissedMark() {
        var suppressor = PointerSuppressor()
        _ = suppressor.decide(event(Kind.leftMouseDown), suppressing: true, dropsMoves: true)
        suppressor.eventsMayHaveBeenMissed()
        #expect(suppressor.decide(event(Kind.leftMouseUp), suppressing: true, dropsMoves: true) == .drop)
        #expect(suppressor.buttonsWithPossiblyMissedUp.isEmpty)
        _ = suppressor.decide(event(Kind.leftMouseDown), suppressing: true, dropsMoves: true)
        suppressor.sweep(isPhysicallyPressed: { _ in false })
        #expect(suppressor.droppedButtons == [0])
    }

    @Test func sweepEndsAScrollTailOnlyAfterAQuietInterval() {
        var suppressor = PointerSuppressor()
        _ = suppressor.decide(scroll(phase: 2, momentum: 0), suppressing: true, dropsMoves: true)
        // 抑止中に届いたスクロールがあるので、最初の片付けでは終えない
        suppressor.sweep(isPhysicallyPressed: { _ in false })
        #expect(suppressor.isDroppingScrollTail)
        // 慣性が続いている間は終えない
        #expect(suppressor.decide(scroll(phase: 0, momentum: 2), suppressing: false, dropsMoves: false) == .drop)
        suppressor.sweep(isPhysicallyPressed: { _ in false })
        #expect(suppressor.isDroppingScrollTail)
        // 1回分の間、1つも届かなかった
        suppressor.sweep(isPhysicallyPressed: { _ in false })
        #expect(!suppressor.isDroppingScrollTail)
        #expect(!suppressor.isTracking)
        #expect(suppressor.decide(scroll(phase: 2, momentum: 0), suppressing: false, dropsMoves: false) == .pass)
    }

    // MARK: 抑止の直後のクリック

    @Test func aClickRightAfterSuppressionEndsIsDroppedWithItsUp() {
        // 指を離したタップで「タップでクリック」が作ったクリックが、抑止を終えた後に届いた
        var suppressor = PointerSuppressor()
        suppressor.suppressionBegan()
        suppressor.suppressionEnded(at: 10, dropsLateClicks: true)
        #expect(suppressor.decide(event(Kind.leftMouseDown), suppressing: false, dropsMoves: false, now: 10.05) == .drop)
        #expect(suppressor.droppedButtons == [0])
        #expect(suppressor.decide(event(Kind.leftMouseDragged), suppressing: false, dropsMoves: false, now: 10.08) == .passAsMove)
        // 離すは間を過ぎてから届いても捨てる
        #expect(suppressor.decide(event(Kind.leftMouseUp), suppressing: false, dropsMoves: false, now: 10.5) == .drop)
        #expect(suppressor.droppedButtons.isEmpty)
    }

    @Test func theGraceDropsEveryButtonButNothingElse() {
        var suppressor = PointerSuppressor()
        suppressor.suppressionEnded(at: 10, dropsLateClicks: true)
        #expect(suppressor.decide(event(Kind.rightMouseDown), suppressing: false, dropsMoves: true, now: 10.01) == .drop)
        #expect(suppressor.decide(event(Kind.otherMouseDown, button: 4), suppressing: false, dropsMoves: true, now: 10.02) == .drop)
        #expect(suppressor.droppedButtons == [1, 4])
        // 移動・スクロール・ジェスチャーは渡す（カーソルの固定は抑止とともに終わる）
        #expect(suppressor.decide(event(Kind.mouseMoved), suppressing: false, dropsMoves: true, now: 10.03) == .pass)
        #expect(suppressor.decide(scroll(phase: 1, momentum: 0), suppressing: false, dropsMoves: true, now: 10.04) == .pass)
        for type in Kind.gestures {
            #expect(suppressor.decide(event(type), suppressing: false, dropsMoves: true, now: 10.05) == .pass)
        }
        // 抑止の前から押していたボタンの離すは渡す
        #expect(suppressor.decide(event(Kind.leftMouseUp), suppressing: false, dropsMoves: true, now: 10.06) == .pass)
    }

    @Test func clicksPassOnceTheGraceIsOver() {
        var suppressor = PointerSuppressor()
        suppressor.suppressionEnded(at: 10, dropsLateClicks: true)
        let end = 10 + PointerSuppressor.clickGraceInterval
        #expect(suppressor.isInClickGrace(at: end - 0.001))
        #expect(!suppressor.isInClickGrace(at: end))
        #expect(suppressor.decide(event(Kind.leftMouseDown), suppressing: false, dropsMoves: false, now: end) == .pass)
        #expect(suppressor.decide(event(Kind.leftMouseUp), suppressing: false, dropsMoves: false, now: end + 0.05) == .pass)
    }

    @Test func thePointerEventsAreNeededDuringTheGraceOnly() {
        var suppressor = PointerSuppressor()
        #expect(PointerSuppressor.clickGraceInterval > 0.1 && PointerSuppressor.clickGraceInterval < 0.5)
        suppressor.suppressionEnded(at: 10, dropsLateClicks: true)
        #expect(suppressor.needsEvents(suppressing: false, now: 10))
        #expect(suppressor.needsEvents(suppressing: false, now: 10 + PointerSuppressor.clickGraceInterval - 0.001))
        #expect(!suppressor.needsEvents(suppressing: false, now: 10 + PointerSuppressor.clickGraceInterval))
        #expect(!suppressor.isTracking)
    }

    @Test func aNewSuppressionEndsTheGrace() {
        var suppressor = PointerSuppressor()
        suppressor.suppressionEnded(at: 10, dropsLateClicks: true)
        suppressor.suppressionBegan()
        #expect(!suppressor.isInClickGrace(at: 10.05))
        #expect(suppressor.clickGraceDeadline == nil)
        // その抑止が終われば、また間を置く
        suppressor.suppressionEnded(at: 11, dropsLateClicks: true)
        #expect(suppressor.isInClickGrace(at: 11.05))
    }

    @Test func aSessionWithoutARecentLiftKeepsNoGrace() {
        // 指に触れていないセッション（右⌘＋C など）の直後のクリックは、すぐに渡す
        var suppressor = PointerSuppressor()
        suppressor.suppressionBegan()
        suppressor.suppressionEnded(at: 10, dropsLateClicks: false)
        #expect(suppressor.clickGraceDeadline == nil)
        #expect(!suppressor.isInClickGrace(at: 10))
        #expect(!suppressor.needsEvents(suppressing: false, now: 10))
        #expect(suppressor.decide(event(Kind.leftMouseDown), suppressing: false, dropsMoves: false, now: 10.01) == .pass)
        #expect(suppressor.decide(event(Kind.leftMouseUp), suppressing: false, dropsMoves: false, now: 10.05) == .pass)
        #expect(suppressor.droppedButtons.isEmpty)
    }

    @Test func aLaterEndWithoutAGraceReplacesTheGrace() {
        var suppressor = PointerSuppressor()
        suppressor.suppressionEnded(at: 10, dropsLateClicks: true)
        suppressor.suppressionBegan()
        suppressor.suppressionEnded(at: 10.05, dropsLateClicks: false)
        #expect(!suppressor.isInClickGrace(at: 10.1))
        #expect(suppressor.decide(event(Kind.leftMouseDown), suppressing: false, dropsMoves: false, now: 10.1) == .pass)
    }

    @Test func cursorLockPlans() {
        #expect(CursorLockPlan(.automatic) == CursorLockPlan(dropsMoves: true, warpsBack: true, decouples: false, restoresTouchStart: true))
        #expect(CursorLockPlan(.dropEvents) == CursorLockPlan(dropsMoves: true, warpsBack: false, decouples: false, restoresTouchStart: true))
        #expect(CursorLockPlan(.decouple) == CursorLockPlan(dropsMoves: true, warpsBack: false, decouples: true, restoresTouchStart: true))
        #expect(CursorLockPlan(.none) == CursorLockPlan(dropsMoves: false, warpsBack: false, decouples: false, restoresTouchStart: false))
    }

    @Test func warpOnlyWhenTheCursorReallyMoved() {
        let anchor = CGPoint(x: 100, y: 200)
        #expect(!CursorLockPlan.needsWarp(from: anchor, to: anchor))
        #expect(!CursorLockPlan.needsWarp(from: anchor, to: CGPoint(x: 100.4, y: 199.6)))
        #expect(CursorLockPlan.needsWarp(from: anchor, to: CGPoint(x: 101, y: 200)))
        #expect(CursorLockPlan.needsWarp(from: anchor, to: CGPoint(x: 100, y: 190)))
    }
}
