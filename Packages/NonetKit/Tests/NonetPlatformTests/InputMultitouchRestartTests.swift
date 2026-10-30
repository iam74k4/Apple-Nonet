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

    @Test func onlyStartWakeAndUserSwitchingRestartWhileTouching() {
        #expect(Planner.Reason.start.isUnconditional)
        #expect(Planner.Reason.wake.isUnconditional)
        #expect(Planner.Reason.sessionActive.isUnconditional)
        // 触れているデバイスとは関係ないことが多いので、指が離れるまで待つ
        for reason in [Planner.Reason.hotPlug, .display, .retry, .deviceListChanged, .silent] {
            #expect(!reason.isUnconditional, "\(reason)")
        }
    }

    @Test(arguments: [Planner.Reason.display, .retry, .deviceListChanged, .silent])
    func newReasonsWaitForTheLiftLikeHotPlug(reason: Planner.Reason) {
        var planner = touchingPlanner(on: 7, at: 10)
        planner.request(reason)
        #expect(planner.decide(connectedDevices: [7], now: 10.1) == .waitForLift)
        // 待っている間に復帰したら、待たずに開始し直す
        #expect(planner.request(.sessionActive) == .sessionActive)
        #expect(planner.decide(connectedDevices: [7], now: 10.2) == .restart(liftFirst: true))
    }
}

@Suite struct InputMultitouchRecoveryTests {
    typealias Recovery = MultitouchRecovery

    @Test func startingEveryUsableDeviceNeedsNoRetry() {
        var recovery = Recovery()
        #expect(recovery.restarted(attempted: [7, 9], started: [9, 7], at: 10) == nil)
        #expect(recovery.failures == 0)
        #expect(!recovery.needsRestart(listed: [7, 9]))
    }

    @Test func retriesWithGrowingDelaysWhileADeviceFailsToStart() {
        // スリープから戻った直後で、内蔵トラックパッドがまだ開始できない
        var recovery = Recovery()
        var delays: [TimeInterval?] = []
        for attempt in 0..<7 {
            delays.append(recovery.restarted(attempted: [7], started: [], at: TimeInterval(attempt)))
        }
        #expect(delays == [1, 3, 10, 30, 60, 60, 60])
        #expect(Recovery.retryDelays.last == 60)
        // 開始できたら、もう試さない
        #expect(recovery.restarted(attempted: [7], started: [7], at: 100) == nil)
        #expect(recovery.failures == 0)
        #expect(recovery.restarted(attempted: [7], started: [], at: 200) == 1)
    }

    @Test func aPartialStartIsRetriedToo() {
        var recovery = Recovery()
        #expect(recovery.restarted(attempted: [7, 9], started: [7], at: 0) == 1)
        #expect(recovery.restarted(attempted: [7, 9], started: [7], at: 1) == 3)
    }

    @Test func aDifferentSetOfDevicesStartsTheBackoffOver() {
        var recovery = Recovery()
        #expect(recovery.restarted(attempted: [7], started: [], at: 0) == 1)
        #expect(recovery.restarted(attempted: [7], started: [], at: 1) == 3)
        // Magic Trackpad がつながった
        #expect(recovery.restarted(attempted: [7, 9], started: [9], at: 4) == 1)
    }

    @Test func aDeviceListThatDiffersFromTheLastAttemptNeedsARestart() {
        var recovery = Recovery()
        // 起動したときはトラックパッドが無かった。抜き差しの通知を受け取れなくても、一覧の見直しで気づく
        #expect(recovery.restarted(attempted: [], started: [], at: 0) == nil)
        #expect(!recovery.needsRestart(listed: []))
        #expect(recovery.needsRestart(listed: [9]))
        _ = recovery.restarted(attempted: [9], started: [9], at: 10)
        #expect(!recovery.needsRestart(listed: [9]))
        // 抜かれた・別のものに替わった
        #expect(recovery.needsRestart(listed: []))
        #expect(recovery.needsRestart(listed: [9, 11]))
        // 並びは問わない
        _ = recovery.restarted(attempted: [9, 11], started: [9, 11], at: 20)
        #expect(!recovery.needsRestart(listed: [11, 9]))
    }

    @Test func theTriggerRestartsDevicesThatHaveSentNoFrameForAWhile() {
        var recovery = Recovery()
        _ = recovery.restarted(attempted: [7], started: [7], at: 100)
        // 開始し直した直後は、まだ触れていないだけかもしれない
        #expect(!recovery.needsRestartOnTrigger(now: 100 + Recovery.silentRestartInterval - 0.1))
        #expect(recovery.needsRestartOnTrigger(now: 100 + Recovery.silentRestartInterval))
        // 開始し直したら、また間を置く
        _ = recovery.restarted(attempted: [7], started: [7], at: 111)
        #expect(!recovery.needsRestartOnTrigger(now: 112))
        #expect(recovery.needsRestartOnTrigger(now: 111 + Recovery.silentRestartInterval))
    }

    @Test func framesKeepTheTriggerFromRestarting() {
        var recovery = Recovery()
        _ = recovery.restarted(attempted: [7], started: [7], at: 100)
        recovery.frameArrived()
        #expect(recovery.hasReceivedFrames)
        #expect(!recovery.needsRestartOnTrigger(now: 1000))
        // 開始し直すと数え直す
        _ = recovery.restarted(attempted: [7], started: [7], at: 1000)
        #expect(!recovery.hasReceivedFrames)
        #expect(recovery.needsRestartOnTrigger(now: 1000 + Recovery.silentRestartInterval))
    }

    @Test func theTriggerNeverRestartsWithoutDevices() {
        var recovery = Recovery()
        #expect(!recovery.needsRestartOnTrigger(now: 1000))
        _ = recovery.restarted(attempted: [], started: [], at: 0)
        #expect(!recovery.needsRestartOnTrigger(now: 1000))
    }

    @Test func intervalsStayCheap() {
        // どれも数秒より短くしない（一覧を作るのも開始し直すのもメインスレッドで動く）
        #expect(Recovery.listCheckInterval >= 5)
        #expect(Recovery.silentRestartInterval >= 5)
        #expect(Recovery.retryDelays.allSatisfy { $0 >= 1 })
        #expect(Recovery.retryDelays == Recovery.retryDelays.sorted())
    }

    @Test func resetForgetsEverything() {
        var recovery = Recovery()
        _ = recovery.restarted(attempted: [7], started: [], at: 0)
        recovery.frameArrived()
        recovery.reset()
        #expect(recovery.attempted.isEmpty)
        #expect(recovery.failures == 0)
        #expect(!recovery.hasReceivedFrames)
        #expect(!recovery.needsRestartOnTrigger(now: 1000))
    }
}
