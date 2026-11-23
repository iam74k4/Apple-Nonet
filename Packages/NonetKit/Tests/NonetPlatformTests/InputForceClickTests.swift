import CoreGraphics
import Foundation
import NonetCore
import Testing
@testable import NonetPlatform

@Suite struct InputForceClickTests {
    private let point = CGPoint(x: 100, y: 200)
    private let hold: TimeInterval = 0.25

    private func held() -> ForceClickHolder {
        var holder = ForceClickHolder()
        #expect(holder.leftDown(at: point, now: 1, canHold: true) == .drop)
        return holder
    }

    @Test func passesClicksItCannotHold() {
        var holder = ForceClickHolder()
        #expect(holder.leftDown(at: point, now: 1, canHold: false) == .pass)
        #expect(!holder.isActive)
        #expect(holder.leftUp() == .pass)
        #expect(holder.leftDragged(to: CGPoint(x: 300, y: 300)) == .pass)
        #expect(holder.pressure(stage: 2, now: 1.1) == .pass)
        #expect(holder.nextDeadline(hold: hold) == nil)
    }

    @Test func anOrdinaryClickIsGivenBackWhenReleased() {
        var holder = held()
        #expect(holder.heldLocation == point)
        #expect(holder.pressure(stage: 1, now: 1.05) == .drop)
        #expect(holder.leftUp() == .giveBackWithCurrent)
        #expect(!holder.isActive)
    }

    @Test func smallMovesWhilePressingStayHeldAndLargerOnesStartADrag() {
        var holder = held()
        #expect(holder.leftDragged(to: CGPoint(x: point.x + 3, y: point.y + 3)) == .drop)
        #expect(holder.isActive)
        #expect(holder.leftDragged(to: CGPoint(x: point.x + ForceClickHolder.slop + 1, y: point.y)) == .giveBackWithCurrent)
        #expect(!holder.isActive)
        // 返した後の動きと離すは、そのまま渡す
        #expect(holder.leftDragged(to: CGPoint(x: 400, y: 200)) == .pass)
        #expect(holder.leftUp() == .pass)
    }

    @Test func aLightLongPressIsGivenBackAfterTheLimit() {
        var holder = held()
        let deadline = 1 + ForceClickHolder.lightPressLimit
        #expect(holder.nextDeadline(hold: hold) == deadline)
        #expect(holder.tick(now: deadline - 0.01, hold: hold) == .none)
        #expect(holder.tick(now: deadline, hold: hold) == .giveBack)
        #expect(!holder.isActive)
    }

    @Test func pressingHardAndHoldingAsksToOpen() {
        var holder = held()
        #expect(holder.pressure(stage: 2, now: 1.2) == .drop)
        // 2段目からの時間で数える（押した時刻からの lightPressLimit では返さない）
        #expect(holder.nextDeadline(hold: hold) == 1.2 + hold)
        #expect(holder.tick(now: 1 + ForceClickHolder.lightPressLimit - 0.2, hold: hold) == .none)
        // 押し込みの強さが揺れて 1 段目に戻っても、押している間は数え続ける
        #expect(holder.pressure(stage: 1, now: 1.3) == .drop)
        #expect(holder.nextDeadline(hold: hold) == 1.2 + hold)
        #expect(holder.tick(now: 1.2 + hold, hold: hold) == .requestOpen)
        #expect(holder.isActive)
        #expect(holder.nextDeadline(hold: hold) == nil)
    }

    @Test func releasingBeforeTheHoldEndsIsAnOrdinaryClick() {
        var holder = held()
        _ = holder.pressure(stage: 2, now: 1.1)
        #expect(holder.leftUp() == .giveBackWithCurrent)
        #expect(holder.tick(now: 2, hold: hold) == .none)
    }

    @Test func openingDropsTheClickAndTurnsItsDragsIntoMoves() {
        var holder = held()
        _ = holder.pressure(stage: 2, now: 1.1)
        #expect(holder.tick(now: 1.1 + hold, hold: hold) == .requestOpen)
        #expect(holder.leftDragged(to: CGPoint(x: 500, y: 500)) == .drop)
        #expect(holder.finish(opened: true) == .none)
        #expect(holder.phase == .consumed)
        #expect(holder.leftDragged(to: CGPoint(x: 520, y: 500)) == .passAsMove)
        #expect(holder.pressure(stage: 2, now: 2) == .drop)
        #expect(holder.leftUp() == .drop)
        #expect(!holder.isActive)
    }

    @Test func openingAfterTheButtonWasReleasedForgetsTheClick() {
        var holder = held()
        _ = holder.pressure(stage: 2, now: 1.1)
        _ = holder.tick(now: 2, hold: hold)
        #expect(holder.leftUp() == .drop)
        #expect(holder.finish(opened: true) == .none)
        #expect(!holder.isActive)
    }

    @Test func notOpeningGivesTheClickBack() {
        var holder = held()
        _ = holder.pressure(stage: 2, now: 1.1)
        _ = holder.tick(now: 2, hold: hold)
        #expect(holder.finish(opened: false) == .giveBack(withUp: false))
        #expect(!holder.isActive)

        var released = held()
        _ = released.pressure(stage: 2, now: 1.1)
        _ = released.tick(now: 2, hold: hold)
        _ = released.leftUp()
        #expect(released.finish(opened: false) == .giveBack(withUp: true))
        // 答えは1回だけ
        #expect(released.finish(opened: false) == .none)
    }

    @Test func returningEverythingGivesBackWhatIsHeld() {
        var holding = held()
        #expect(holding.returnAll(isPressed: true) == .giveBack(withUp: false))
        var releasedMeanwhile = held()
        #expect(releasedMeanwhile.returnAll(isPressed: false) == .giveBack(withUp: true))
        var consumed = held()
        _ = consumed.pressure(stage: 2, now: 1.1)
        _ = consumed.tick(now: 2, hold: hold)
        _ = consumed.finish(opened: true)
        #expect(consumed.returnAll(isPressed: true) == .none)
        #expect(!consumed.isActive)
        var idle = ForceClickHolder()
        #expect(idle.returnAll(isPressed: false) == .none)
    }

    @Test func aMissedReleaseOfAnOpenedClickIsForgotten() {
        var holder = held()
        _ = holder.pressure(stage: 2, now: 1.1)
        _ = holder.tick(now: 2, hold: hold)
        _ = holder.finish(opened: true)
        holder.forgetConsumedIfReleased(isPressed: true)
        #expect(holder.phase == .consumed)
        holder.forgetConsumedIfReleased(isPressed: false)
        #expect(!holder.isActive)
    }

    @Test func aNewPressEndsAnyClickWhoseReleaseWasMissed() {
        var holder = held()
        _ = holder.pressure(stage: 2, now: 1.1)
        _ = holder.tick(now: 2, hold: hold)
        _ = holder.finish(opened: true)
        #expect(holder.leftDown(at: point, now: 3, canHold: false) == .pass)
        #expect(!holder.isActive)
    }

    @Test func holdTimesFollowTheOpenSensitivity() {
        // 控えめほど長く止める
        #expect(ForcePress.hold(for: .high) < ForcePress.hold(for: .standard))
        #expect(ForcePress.hold(for: .standard) < ForcePress.hold(for: .low))
    }
}
