// 担当: engine。「画面に置く」のマスを光らせている間の置く枠のプレビューと、離したときの実行
import CoreGraphics
import Foundation
@testable import NonetCore
import Testing

@MainActor
@Suite struct ControllerPlaceWindowTests {
    typealias F = ControllerFixtures

    static let leftCell = Cell(title: "左半分", icon: .symbol(WindowRegion.left.symbol), action: .placeWindow(PlaceWindowAction(region: .left)))

    /// Safari のページの左上のマスを「左半分」にする
    private func harness() throws -> ControllerHarness {
        let h = try ControllerHarness()
        h.start()
        let safariID = try h.profileID(F.safari)
        h.controller.update { $0.setCell(Self.leftCell, at: CellAddress(page: 0, index: 0), profileID: safariID) }
        return h
    }

    @Test("光らせている間だけ置く枠を見せ、外枠に戻すと消す。離すと、そのアプリに向けて置く")
    func previewFollowsTheHighlightAndLiftPlaces() async throws {
        let h = try harness()
        let visible = try #require(h.windowPlacer.visibleFrame)
        h.open()
        #expect(h.hud.placementPreview == nil)
        h.advance(0.05)
        h.touch(on: 0)
        #expect(h.hud.placementPreview == WindowRegion.left.frame(in: visible))
        // ほかのマスへ移すと消え、外枠でも消える
        h.touch(on: 1)
        #expect(h.hud.placementPreview == nil)
        h.touch(on: 0)
        #expect(h.hud.placementPreview != nil)
        h.touch(x: 0.5, y: 0.03)
        #expect(h.hud.placementPreview == nil)

        h.touch(on: 0)
        h.advance(0.2)
        h.lift()
        await h.settle()
        #expect(h.hud.placementPreview == nil)
        #expect(!h.hud.isVisible)
        #expect(h.performer.actions == [Self.leftCell.action])
        #expect(h.performer.calls.first?.frontmostApp == F.safariApp)
    }

    @Test("ウインドウが無ければ枠は出さないが、マスは光る")
    func noWindowNoPreview() throws {
        let h = try harness()
        h.windowPlacer.visibleFrame = nil
        h.open()
        h.advance(0.05)
        h.touch(on: 0)
        #expect(h.hud.current?.highlightedIndex == 0)
        #expect(h.hud.placementPreview == nil)
        h.liftAndClose()
    }

    @Test("閉じるときは必ず枠を消す（キーで閉じたときも）")
    func closingHidesThePreview() throws {
        let h = try harness()
        h.open()
        h.advance(0.05)
        h.touch(on: 0)
        #expect(h.hud.placementPreview != nil)
        h.keyboard.pressKey()
        #expect(h.hud.placementPreview == nil)
        #expect(h.hud.placementPreviews.count == 2)
    }
}
