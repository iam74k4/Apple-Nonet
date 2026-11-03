// 担当: engine。「ためらったときだけ出す」: 開いてから hesitationDelay は HUD を出さず（触覚だけ）、それより長く開いたままなら出す
import CoreGraphics
import Foundation
@testable import NonetCore
import Testing

@MainActor
@Suite struct ControllerHesitationTests {
    typealias F = ControllerFixtures

    private func harness() throws -> ControllerHarness {
        let h = try ControllerHarness()
        h.start()
        h.controller.update { $0.settings.hudOnHesitation = true }
        return h
    }

    @Test("開いてから 0.4 秒は出さず、迷っていれば最新の中身で出す。出た後はふだんどおり更新する")
    func showsAfterTheDelayWithTheLatestState() throws {
        let h = try harness()
        h.open()
        #expect(h.hud.shown.isEmpty && !h.hud.isVisible)
        h.advance(0.05)
        h.touch(on: 4)
        #expect(h.hud.shown.isEmpty)
        h.advance(NonetController.hesitationDelay)
        #expect(h.hud.shown.count == 1)
        #expect(h.hud.current?.highlightedIndex == 4)
        h.touch(on: 5)
        #expect(h.hud.current?.highlightedIndex == 5)
        h.liftAndClose()
        #expect(!h.hud.isVisible)
    }

    @Test("0.4 秒より早く離せば画面は変わらない（HUD を出さずに実行する）。次に開いたときに前の待ちを引きずらない")
    func liftingEarlyNeverShows() async throws {
        let h = try harness()
        h.open()
        h.advance(0.05)
        h.touch(on: 4)
        h.advance(0.2)
        h.lift()
        await h.settle()
        #expect(h.performer.actions.count == 1)
        h.advance(1)
        #expect(h.hud.shown.isEmpty)
        #expect(!h.hud.isVisible)
    }

    @Test("「画面に置く」の置く枠は待たずに出す")
    func placementPreviewDoesNotWait() throws {
        let h = try harness()
        let safariID = try h.profileID(F.safari)
        let cell = Cell(title: "左半分", icon: .symbol(WindowRegion.left.symbol), action: .placeWindow(PlaceWindowAction(region: .left)))
        h.controller.update { $0.setCell(cell, at: CellAddress(page: 0, index: 0), profileID: safariID) }
        h.open()
        h.advance(0.05)
        h.touch(on: 0)
        #expect(h.hud.shown.isEmpty)
        #expect(h.hud.placementPreview != nil)
        h.keyboard.pressKey()
        #expect(h.hud.placementPreview == nil)
        h.advance(1)
        #expect(h.hud.shown.isEmpty)
    }
}
