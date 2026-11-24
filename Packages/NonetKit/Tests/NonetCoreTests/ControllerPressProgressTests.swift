// 担当: engine。強く押し込んでから開くまでの輪（途中で離すとふつうのクリックになることを見せる）
import Foundation
import Testing
@testable import NonetCore

@MainActor
@Suite struct ControllerPressProgressTests {
    typealias F = ControllerFixtures

    @Test func theRingFillsUntilTheButtonsOpen() throws {
        let h = try ControllerHarness()
        h.start()
        h.touch(x: 0.5, y: 0.5)
        h.keyboard.send(.forcePressStarted(hold: 0.25))
        #expect(h.hud.pressProgress == [0.25])
        h.forcePress()
        #expect(h.hud.pressProgress == [0.25, nil])
        #expect(h.hud.shown.count == 1)
    }

    @Test func releasingEarlyHidesTheRing() throws {
        let h = try ControllerHarness()
        h.start()
        h.keyboard.send(.forcePressStarted(hold: 0.5))
        h.keyboard.send(.forcePressCancelled)
        #expect(h.hud.pressProgress == [0.5, nil])
        #expect(h.hud.shown.isEmpty)
    }

    /// すぐ開く段（開きやすい）では、出た瞬間に消えるだけなので出さない
    @Test func aVeryShortHoldShowsNoRing() throws {
        let h = try ControllerHarness()
        h.start()
        h.keyboard.send(.forcePressStarted(hold: ForcePress.hold(for: .high)))
        #expect(h.hud.pressProgress.isEmpty)
    }
}
