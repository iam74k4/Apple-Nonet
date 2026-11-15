// 担当: engine。少し長く止めてから実行するマス（Cell.requiresHold）と境界の帯を、NonetController を通して確かめる。
// 既定: 前面は Safari（ControllerHarness）
import Foundation
import Testing
@testable import NonetCore

@MainActor
@Suite struct ControllerHoldTests {
    typealias F = ControllerFixtures

    /// Safari の1ページ目の「タブを閉じる」（マス 2）を、少し長く止めてから実行するマスにした設定
    static func configuration() -> NonetConfiguration {
        var configuration = F.configuration()
        let safari = configuration.appProfile(forBundleID: F.safari.bundleID)
        if let id = safari?.id {
            var closeTab = F.closeTab
            closeTab.requiresHold = true
            configuration.setCell(closeTab, at: CellAddress(page: 0, index: 2), profileID: id)
        }
        return configuration
    }

    @Test func theSessionPassesTheHoldCellsOfEveryPage() throws {
        let session = ControllerSession(configuration: Self.configuration(), frontmostApp: F.safariApp)
        #expect(session.engineConfiguration.holdCells == [[2], [], []])
        // HUD のマスにも印を付ける
        let model = session.hudModel(SessionHUDState(page: 0, highlightedCell: nil), isPracticeMode: false, isTrialEnded: false)
        #expect(model.cells.map { $0?.requiresHold } == [false, nil, true, nil, false, nil, nil, nil, false])
    }

    /// 少し長く止めるマスで止めている間は進み具合を見せ、止め終えたら「離すと実行」の状態になる
    @Test func theHUDShowsTheHoldProgress() throws {
        let h = try ControllerHarness(configuration: Self.configuration())
        h.start()
        h.open()
        h.advance(0.05)
        h.touch(on: 2)
        let started = h.scheduler.now
        #expect(h.hud.current?.hold == HUDHold(cellIndex: 2, since: started, duration: SessionConfiguration.defaultHoldDwell, isReady: false))
        h.advance(SessionConfiguration.defaultHoldDwell - 0.01)
        #expect(h.hud.current?.hold?.isReady == false)
        h.advance(0.01)
        #expect(h.hud.current?.hold == HUDHold(cellIndex: 2, since: started, duration: SessionConfiguration.defaultHoldDwell, isReady: true))
        // ほかのマスへ移ると、進み具合は消える
        h.touch(on: 0)
        #expect(h.hud.current?.hold == nil)
        #expect(h.hud.current?.highlightedIndex == 0)
    }

    /// ふつうの時間（0.15 秒）だけ止めて離しても、少し長く止めるマスは実行しない
    @Test func theOrdinaryDwellIsNotEnough() async throws {
        let h = try ControllerHarness(configuration: Self.configuration())
        h.start()
        h.run(2, dwell: 0.3)
        await h.settle()
        #expect(h.performer.calls.isEmpty)
        #expect(h.haptics.events.last == .rejected)
        #expect(h.controller.lastCancellation?.reason == .liftedTooSoon)
        // 止め終えてから離せば実行する
        h.run(2, dwell: SessionConfiguration.defaultHoldDwell + 0.05)
        await h.settle()
        #expect(h.performer.actions == [F.closeTab.action])
    }

    /// 境界の線の上で離しても、どちらのマスも実行しない
    @Test func liftingOnALineRunsNothing() async throws {
        let h = try ControllerHarness()
        h.start()
        h.open()
        h.advance(0.05)
        h.touch(on: 4)
        h.advance(0.3)
        // マス 4 と 5 の間の線の上（ヒステリシスで、まだマス 4 が光っている）
        let frame = GridInsets.cancelFrame
        let line = frame.left + (1 - frame.left - frame.right) * 2 / 3
        h.touch(x: line - 0.005, y: Pad.center(4).y)
        #expect(h.hud.current?.highlightedIndex == 4)
        h.advance(0.3)
        h.lift()
        await h.settle()
        #expect(h.performer.calls.isEmpty)
        #expect(h.haptics.events.last == .rejected)
        #expect(h.controller.lastCancellation?.reason == .liftedOnBoundary)
    }
}
