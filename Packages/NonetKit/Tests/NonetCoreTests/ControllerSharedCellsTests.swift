// 担当: engine（core-model が足した確かめ）。共通マスは、トリガーで決めるページ（resolvedPages）を通して、
// すぐにタップ・空きマスの判定（occupiedCells）・HUD のどれでも、その位置のマスの代わりに使う。既定: 前面は Safari、トリガーは右⌥
import Foundation
import Testing
@testable import NonetCore

@MainActor
@Suite struct ControllerSharedCellsTests {
    typealias F = ControllerFixtures

    static let mute = Cell(title: "ミュート", icon: .symbol("mic.slash"), action: .keystroke(.key("m", [.command, .shift])))
    static let lock = Cell(title: "ロック", icon: .symbol("lock"), action: .keystroke(.key("q", [.command, .control])))

    /// Safari: [新しいタブ, 空, タブを閉じる, 空, 要約, 空, 空, 空, リーダー]。共通マスを 0（Safari では新しいタブ）と 1（Safari では空き）に置く
    private func configuration(_ transform: (inout NonetConfiguration) -> Void = { _ in }) -> NonetConfiguration {
        var configuration = F.configuration()
        configuration.setSharedCell(Self.mute, at: 0)
        configuration.setSharedCell(Self.lock, at: 1)
        transform(&configuration)
        return configuration.validated()
    }

    @Test func aSharedPositionRunsTheSharedCellInsteadOfTheAppCell() async throws {
        let h = try ControllerHarness(configuration: configuration())
        h.start()
        h.run(0)
        await h.settle()
        #expect(h.performer.actions == [Self.mute.action])
        #expect(h.controller.lastExecution?.cellTitle == "ミュート")
        // どこで実行したかは、使っていたプロファイル（Safari）の位置で残す（最近の実行から設定のそのマスを開く）
        #expect(h.controller.lastExecution?.profileID == (try h.profileID(F.safari)))
        #expect(h.controller.lastExecution?.address == CellAddress(page: 0, index: 0))
    }

    /// Safari ではその位置が空きでも、共通マスがあれば空きマスとして扱わない（rejected にしない）
    @Test func aSharedPositionIsNotEmptyEvenWhereTheAppHasNoCell() async throws {
        let h = try ControllerHarness(configuration: configuration())
        h.start()
        h.run(1)
        await h.settle()
        #expect(h.performer.actions == [Self.lock.action])
        #expect(!h.haptics.events.contains(.rejected))
    }

    @Test func theHUDShowsTheSharedCellsWithTheirMark() throws {
        let h = try ControllerHarness(configuration: configuration())
        h.start()
        h.open()
        h.advance(1)
        let cells = try #require(h.hud.current?.cells)
        #expect(cells[0]?.title == "ミュート")
        #expect(cells[0]?.isShared == true)
        #expect(cells[1]?.title == "ロック")
        #expect(cells[1]?.isShared == true)
        #expect(cells[2]?.title == F.closeTab.title)
        #expect(cells[2]?.isShared == false)
        h.closeIfOpen()
    }

    /// プロファイルの無いアプリではグローバルのページで、同じ位置に出る
    @Test func anAppWithoutAProfileGetsTheSharedCellsOnTheGlobalPage() async throws {
        let h = try ControllerHarness(configuration: configuration(), frontmost: F.notesApp)
        h.start()
        h.run(0)
        await h.settle()
        #expect(h.performer.actions == [Self.mute.action])
        #expect(h.controller.lastExecution?.profileID == h.controller.configuration.globalProfile.id)
    }

    @Test func anAppWhereNonetIsOffStaysOffWithSharedCells() async throws {
        let h = try ControllerHarness(configuration: configuration { $0.setAppMode(.off, for: F.safari) })
        h.start()
        h.run(1)
        h.open()
        h.advance(1)
        h.closeIfOpen()
        await h.settle()
        #expect(h.performer.calls.isEmpty)
        #expect(h.hud.shown.isEmpty)
        #expect(!h.keyboard.isSuppressingPointer)
    }

    /// 共通マスをやめると、Safari のそのマスがまた使われる（Safari のマスは消えていない）
    @Test func removingTheSharedCellBringsBackTheAppCell() async throws {
        let h = try ControllerHarness(configuration: configuration())
        h.start()
        h.controller.update { $0.setSharedCell(nil, at: 0) }
        h.run(0)
        await h.settle()
        #expect(h.performer.actions == [F.newTab.action])
    }
}
