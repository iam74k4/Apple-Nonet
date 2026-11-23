// 担当: core-model。ページのボタンの数（4・6・8・9・12）: 書式・数を変えたときの詰め直し・円の並び
import Foundation
import Testing
@testable import NonetCore

@Suite struct ModelPageLayoutTests {
    private func cell(_ title: String) -> Cell {
        Cell(title: title, icon: .text(String(title.prefix(1))), action: .keystroke(.key("a")))
    }

    @Test func aPageHasAsManyCellsAsItsLayout() {
        for layout in PageLayout.allCases {
            #expect(Page(layout: layout).cells.count == layout.slotCount)
        }
        #expect(Page().layout == .nine)
        #expect(Page(cells: Array(repeating: cell("a"), count: 20), layout: .twelve).cells.count == 12)
        #expect(PageLayout.allCases.map(\.gridShape.cellCount) == PageLayout.allCases.map(\.slotCount))
    }

    /// 9 のページは前と同じ書式（buttons を書かない）。ほかは buttons を書き、読めない数は近い数
    @Test func theLayoutRoundTripsAndNineIsNotWritten() throws {
        let nine = Page(cells: [cell("a")])
        let nineJSON = String(decoding: try JSONEncoder().encode(nine), as: UTF8.self)
        #expect(!nineJSON.contains("buttons"))
        let twelve = Page(cells: [cell("a"), nil, cell("c")], name: "多い", layout: .twelve)
        let data = try JSONEncoder().encode(twelve)
        #expect(String(decoding: data, as: UTF8.self).contains(#""buttons":12"#))
        #expect(try JSONDecoder().decode(Page.self, from: data) == twelve)
        let odd = try JSONDecoder().decode(Page.self, from: Data(#"{"cells":[],"buttons":7}"#.utf8))
        #expect(odd.layout == .eight)
        #expect(odd.cells.count == 8)
        let broken = try JSONDecoder().decode(Page.self, from: Data(#"{"cells":[],"buttons":"many"}"#.utf8))
        #expect(broken.layout == .nine)
        #expect(PageLayout(nearest: 5) == .six)
        #expect(PageLayout(nearest: 100) == .twelve)
        #expect(PageLayout(nearest: 0) == .four)
    }

    /// 円の並び: 9 は 3×3 の向き（上が 1）と真ん中 4、ほかは 0 から上から時計回りで、真ん中は無い
    @Test func theRingOrder() {
        #expect(PageLayout.nine.ringCells == [1, 2, 5, 8, 7, 6, 3, 0])
        #expect(PageLayout.nine.centerCell == 4)
        #expect(PageLayout.twelve.ringCells == Array(0..<12))
        #expect(PageLayout.twelve.centerCell == nil)
        #expect(PageLayout.nine.clockwiseCells == [1, 2, 5, 8, 7, 6, 3, 0, 4])
    }

    /// 数を変えても、上から時計回りの順を保つ。減らすときは後ろの空きマスから減らす
    @Test func resizingKeepsTheClockwiseOrder() {
        // 9: 上（1）に a、右（5）に b、左上（0）に c、真ん中（4）に d
        var cells: [Cell?] = Array(repeating: nil, count: 9)
        cells[1] = cell("a")
        cells[5] = cell("b")
        cells[0] = cell("c")
        cells[4] = cell("d")
        let nine = Page(cells: cells, name: "p")
        let twelve = nine.resized(to: .twelve)
        #expect(twelve.layout == .twelve)
        #expect(twelve.name == "p")
        // 時計回りに 1, 2, 5, 8, 7, 6, 3, 0, 4 → 0〜8
        #expect(twelve.cells.map { $0?.title } == ["a", nil, "b", nil, nil, nil, nil, "c", "d", nil, nil, nil])
        // 戻すと元どおり
        #expect(twelve.resized(to: .nine) == nine)
        // 4 には中身が4つなので入る。空きマスを詰める
        #expect(nine.canResize(to: .four))
        #expect(nine.resized(to: .four).cells.map { $0?.title } == ["a", "b", "c", "d"])
        // 中身が多すぎる数にはできない
        let full = Page(cells: (0..<9).map { cell("\($0)") })
        #expect(!full.canResize(to: .eight))
        #expect(full.canResize(to: .twelve))
        #expect(nine.resized(to: .nine) == nine)
    }

    @Test func theConfigurationChangesTheLayoutOnlyWhenEverythingFits() throws {
        let profile = Profile(kind: .global, pages: [Page(cells: (0..<9).map { cell("\($0)") })])
        var configuration = NonetConfiguration(profiles: [profile]).validated()
        let id = configuration.globalProfile.id
        let tooFew = configuration.setPageLayout(.six, at: 0, profileID: id)
        #expect(!tooFew)
        #expect(configuration.globalProfile.pages[0].layout == .nine)
        let twelve = configuration.setPageLayout(.twelve, at: 0, profileID: id)
        #expect(twelve)
        #expect(configuration.globalProfile.pages[0].layout == .twelve)
        // HUD に渡すページにもボタンの数が付く
        #expect(configuration.resolvedPages(frontmostBundleID: nil).first?.layout == .twelve)
        // 保存して読み直しても同じ
        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(NonetConfiguration.self, from: data)
        #expect(decoded.globalProfile.pages[0].layout == .twelve)
        // 12 にしたときに、9 の上から時計回りの順（1, 2, 5, 8, 7, 6, 3, 0, 4）で詰め直してある
        #expect(decoded.globalProfile.pages[0].cells.compactMap { $0?.title } == PageLayout.nine.clockwiseCells.map { "\($0)" })
    }

    /// 円の上の鍵の向きと、ポインタの向きで選ぶマス
    @Test func theRadialMapperFollowsTheLayout() {
        let mapper = RadialMapper()
        for layout in PageLayout.allCases {
            for cell in layout.ringCells {
                let position = RadialLayout.position(ofCell: cell, layout: layout)!
                #expect(mapper.zone(dx: position.x, dy: position.y, layout: layout) == .cell(cell), "\(layout) \(cell)")
            }
        }
        // 12: 3時の方向（右）は 3、6時の方向（下）は 6
        #expect(mapper.zone(dx: 100, dy: 0, layout: .twelve) == .cell(3))
        #expect(mapper.zone(dx: 0, dy: 100, layout: .twelve) == .cell(6))
        // 4: 真ん中は外枠（離すとやめる）で、止めてもページは変わらない
        #expect(mapper.zone(dx: 5, dy: 5, layout: .four) == .frame)
        #expect(mapper.isInCenter(dx: 5, dy: 5, layout: .four))
        #expect(mapper.pagingEdge(dx: 30, dy: 0) == nil)
        #expect(mapper.zone(dx: 5, dy: 5, layout: .nine) == .cell(4))
        // 外は外枠
        #expect(mapper.zone(dx: 0, dy: 160, layout: .six) == .frame)
    }

    /// ポインタから合成した指の位置を、エンジンがそのページの升目で同じマスに戻す
    @Test func synthesizedPositionsMapBackToTheSameCell() {
        for layout in PageLayout.allCases {
            let grid = GridMapper(insets: .cancelFrame, shape: layout.gridShape)
            for index in 0..<layout.slotCount {
                let center = ControllerPointerSelection.cellCenter(index, shape: layout.gridShape)
                #expect(grid.zone(x: center.x, y: center.y) == .cell(index), "\(layout) \(index)")
                #expect(!grid.isInBoundaryBand(x: center.x, y: center.y))
            }
        }
    }
}
