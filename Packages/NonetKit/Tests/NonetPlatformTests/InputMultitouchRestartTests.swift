import Foundation
import NonetCore
import Testing
@testable import NonetPlatform

@Suite struct InputMultitouchRestartTests {
    typealias Planner = MultitouchRestartPlanner

    private func frame(_ time: TimeInterval, touching: Bool) -> TouchFrame {
        TouchFrame(timestamp: time, points: touching ? [TouchPoint(id: 1, x: 0.5, y: 0.5)] : [])
    }

    /// device の上に指を置いたまま、time まではフレームが届いている
    private func touchingPlanner(on device: UInt64, at time: TimeInterval) -> Planner {
        var planner = Planner(staleInterval: 0.5)
        planner.delivered(frame(time - 0.3, touching: true), from: device)
        planner.delivered(frame(time, touching: true), from: device)
        return planner
    }

    @Test(arguments: [Planner.Reason.start, .hotPlug, .wake])
    func restartsRightAwayWhenNoFingerIsDown(reason: Planner.Reason) {
        var planner = Planner()
        planner.delivered(frame(1, touching: true), from: 7)
        planner.delivered(frame(1.1, touching: false), from: 7)
        planner.request(reason)
        #expect(planner.decide(connectedDevices: [7], now: 1.2) == .restart(liftFirst: false))
        #expect(planner.pendingReason == nil)
    }

    @Test func hotPlugWhileTouchingAConnectedDeviceWaitsForTheLift() {
        // 内蔵トラックパッドに指を置いている間に、Magic Mouse がつながり直した
        var planner = touchingPlanner(on: 7, at: 10)
        planner.request(.hotPlug)
        #expect(planner.decide(connectedDevices: [7, 9], now: 10.1) == .waitForLift)
        #expect(planner.pendingReason == .hotPlug)
        // 指を置いている間は待ち続ける
        planner.delivered(frame(11, touching: true), from: 7)
        #expect(planner.decide(connectedDevices: [7, 9], now: 11.05) == .waitForLift)
        // 離れたら、作ったフレームを渡さずに開始し直す
        planner.delivered(frame(11.5, touching: false), from: 7)
        #expect(planner.decide(connectedDevices: [7, 9], now: 12) == .restart(liftFirst: false))
        #expect(planner.pendingReason == nil)
    }

    @Test func hotPlugThatRemovedTheTouchedDeviceLiftsTheFinger() {
        var planner = touchingPlanner(on: 7, at: 10)
        planner.request(.hotPlug)
        #expect(planner.decide(connectedDevices: [9], now: 10.1) == .restart(liftFirst: true))
        #expect(planner.decide(connectedDevices: [], now: 10.1) == .restart(liftFirst: true))
    }

    @Test func hotPlugWhileTheTouchedDeviceHasGoneQuietLiftsTheFinger() {
        // 同じ ID でつながり直した（前のデバイスのフレームはもう来ない）
        var planner = touchingPlanner(on: 7, at: 10)
        planner.request(.hotPlug)
        #expect(planner.decide(connectedDevices: [7], now: 10.4) == .waitForLift)
        #expect(planner.decide(connectedDevices: [7], now: 10.6) == .restart(liftFirst: true))
    }

    @Test func touchingWithoutAKnownDeviceDoesNotWait() {
        var planner = Planner()
        planner.delivered(frame(10, touching: true), from: nil)
        planner.request(.hotPlug)
        #expect(planner.decide(connectedDevices: [7], now: 10.1) == .restart(liftFirst: true))
    }

    @Test func wakeRestartsEvenWhileTouching() {
        var planner = touchingPlanner(on: 7, at: 10)
        planner.request(.wake)
        #expect(planner.decide(connectedDevices: [7], now: 10.1) == .restart(liftFirst: true))
    }

    @Test func aPendingWakeIsNotDowngradedByALaterHotPlug() {
        var planner = touchingPlanner(on: 7, at: 10)
        #expect(planner.request(.wake) == .wake)
        #expect(planner.request(.hotPlug) == .wake)
        #expect(planner.decide(connectedDevices: [7], now: 10.1) == .restart(liftFirst: true))
    }

    @Test func aWakeUpgradesAWaitingHotPlug() {
        var planner = touchingPlanner(on: 7, at: 10)
        planner.request(.hotPlug)
        #expect(planner.decide(connectedDevices: [7], now: 10.1) == .waitForLift)
        #expect(planner.request(.wake) == .wake)
        #expect(planner.decide(connectedDevices: [7], now: 10.2) == .restart(liftFirst: true))
    }

    @Test func theSyntheticLiftEndsTheTouchButKeepsTheDevice() {
        var planner = touchingPlanner(on: 7, at: 10)
        planner.delivered(frame(10.1, touching: false), from: nil)
        #expect(!planner.isTouching)
        #expect(planner.activeDevice == 7)
    }

    @Test func resetForgetsEverythingButTheStaleInterval() {
        var planner = touchingPlanner(on: 7, at: 10)
        planner.request(.hotPlug)
        planner.reset()
        #expect(planner.pendingReason == nil)
        #expect(!planner.isTouching)
        #expect(planner.activeDevice == nil)
        #expect(planner.staleInterval == 0.5)
    }

    @Test func onlyHotPlugWaits() {
        #expect(!Planner.Reason.hotPlug.isUnconditional)
        #expect(Planner.Reason.wake.isUnconditional)
        #expect(Planner.Reason.start.isUnconditional)
    }
}
