// 担当: ui-settings。ページの「ボタンの数」（4・6・8・9・12）
import CoreGraphics
import Foundation
import NonetCore
@testable import NonetUI
import Testing

@Suite @MainActor struct SettingsPageLayoutTests {
    private func harness() throws -> SettingsHarness {
        let h = try SettingsHarness()
        h.model.undoManager.groupsByEvent = false
        return h
    }

    @Test func changingTheCountKeepsTheButtonsAndCanBeUndone() throws {
        let h = try harness()
        let before = h.model.currentPage
        let titles = before.cells.compactMap { $0?.title }
        h.model.setPageLayout(.twelve)
        #expect(h.model.currentPage.layout == .twelve)
        #expect(h.model.currentPage.cells.count == 12)
        #expect(Set(h.model.currentPage.cells.compactMap { $0?.title }) == Set(titles))
        #expect(try h.saved()?.globalProfile.pages[0].layout == .twelve)
        #expect(h.model.undoManager.canUndo)
        h.model.undoManager.undo()
        #expect(h.model.currentPage == before)
    }

    private func fillCurrentPage(_ h: SettingsHarness) {
        for index in h.model.currentPage.cells.indices where h.model.currentPage.cells[index] == nil {
            let profileID = h.model.selectedProfile.id
            let page = h.model.pageIndex
            h.model.controller.update {
                $0.setCell(Cell(title: "x\(index)", icon: .text("x"), action: .keystroke(.key("x"))), at: CellAddress(page: page, index: index), profileID: profileID)
            }
        }
    }

    /// 入りきらない数にすると、入りきらない分をすぐ後ろの新しいページへ移す（ボタンを消さない）。元に戻せる
    @Test func theButtonsThatDoNotFitMoveToANewPage() throws {
        let h = try harness()
        fillCurrentPage(h)
        let before = h.model.selectedProfile.pages
        try #require(before.count < Profile.maxPages)
        let titles = Set(h.model.currentPage.cells.compactMap { $0?.title })
        #expect(h.model.canSetPageLayout(.six))
        #expect(h.model.pageLayoutMovesOverflow(.six))
        #expect(!h.model.pageLayoutMovesOverflow(.twelve))
        h.model.setPageLayout(.six)
        let pages = h.model.selectedProfile.pages
        #expect(pages.count == before.count + 1)
        #expect(pages[h.model.pageIndex].layout == .six)
        #expect(pages[h.model.pageIndex].filledCount == 6)
        #expect(pages[h.model.pageIndex + 1].filledCount == 3)
        let moved = Set(pages[h.model.pageIndex].cells.compactMap { $0?.title } + pages[h.model.pageIndex + 1].cells.compactMap { $0?.title })
        #expect(moved == titles)
        #expect(h.model.gridMessage == SettingsText.pageLayoutMovedOverflow(count: 3, toPage: h.model.pageIndex + 1))
        h.model.undoManager.undo()
        #expect(h.model.selectedProfile.pages == before)
    }

    /// ページが上限なら、入りきらない数は選べない
    @Test func aCountThatCannotHoldTheButtonsIsRefusedWhenThePagesAreFull() throws {
        let h = try harness()
        while h.model.selectedProfile.pages.count < Profile.maxPages {
            let profileID = h.model.selectedProfile.id
            h.model.controller.update { _ = $0.addPage(profileID: profileID) }
        }
        fillCurrentPage(h)
        #expect(!h.model.canSetPageLayout(.eight))
        h.model.setPageLayout(.eight)
        #expect(h.model.currentPage.layout == .nine)
        #expect(h.model.gridMessage != nil)
        #expect(h.model.canSetPageLayout(.twelve))
    }

    /// 選んでいたマスは、詰め直した後も同じものを選ぶ
    @Test func theSelectionFollowsTheButton() throws {
        let h = try harness()
        let index = try #require(h.model.currentPage.cells.indices.last { h.model.currentPage.cells[$0] != nil })
        let id = h.model.currentPage.cells[index]?.id
        h.model.selectCell(index)
        h.model.setPageLayout(.twelve)
        #expect(h.model.selectedCell?.id == id)
    }

    /// 円に並べるページの矢印キー: その向きのいちばん近いマス
    @Test func arrowKeysMoveAroundTheRing() {
        // 4: 上 0・右 1・下 2・左 3
        #expect(SettingsGrid.neighbor(of: 0, .right, layout: .four) == 1)
        #expect(SettingsGrid.neighbor(of: 0, .down, layout: .four) == 2)
        #expect(SettingsGrid.neighbor(of: 1, .left, layout: .four) == 3)
        #expect(SettingsGrid.neighbor(of: 0, .up, layout: .four) == 0)
        // 12: 3時（3）の上は 2、下は 4
        #expect(SettingsGrid.neighbor(of: 3, .up, layout: .twelve) == 2)
        #expect(SettingsGrid.neighbor(of: 3, .down, layout: .twelve) == 4)
        // 9 は 3×3 のまま
        #expect(SettingsGrid.neighbor(of: 4, .left) == 3)
    }

    @Test func positionsAreNamedByDirection() {
        #expect(SettingsGrid.positionName(1, layout: .four) == L10n.ui("右"))
        #expect(SettingsGrid.positionName(0, layout: .eight) == L10n.ui("上"))
        #expect(SettingsGrid.positionName(1, layout: .twelve) == L10n.ui("\(1)時の方向"))
        #expect(SettingsGrid.positionName(0, layout: .nine) == L10n.ui("左上"))
    }

    /// 初回の案内の練習: 9 以外のページでも、下の鍵から選んでもらい、位置はそのページの呼び方で言う
    @Test func thePracticeFollowsTheLayout() throws {
        #expect(OnboardingPracticePage.runPreference(for: .four).first == 2)
        #expect(OnboardingPracticePage.runPreference(for: .twelve).first == 6)
        #expect(OnboardingPracticePage.runPreference(for: .nine) == OnboardingPracticePage.runPreference)
        let cells = (0..<4).map { Cell(title: "b\($0)", icon: .text("b"), action: .keystroke(.key("b"))) }
        let page = ResolvedPage(profileID: UUID(), profileName: "グローバル", pageIndex: 0, cells: cells, layout: .four)
        let practice = try #require(OnboardingPracticePage(page))
        #expect(practice.titles.count == 4)
        #expect(practice.runTarget.index == 2)
        #expect(practice.runTarget.positionName == L10n.ui("下"))
    }

    /// 少ないページは鍵を大きく、12 は隣と重ならないよう小さく描く
    @Test func keysAreSizedByTheButtonCount() {
        let base = HUDMetrics(scale: 1)
        #expect(base.forKeys(of: .four).selectionRadius > base.selectionRadius)
        #expect(base.forKeys(of: .nine).selectionRadius == base.selectionRadius)
        let twelve = base.forKeys(of: .twelve)
        // 隣の鍵の中心の間（円の弦）より、白い円の直径が小さい
        let gap = 2 * RadialLayout.keyRadius * sin(.pi / 12)
        #expect(Double(twelve.selectionRadius * 2) < gap)
        // 位置は変えない
        #expect(twelve.position(ofCell: 3, layout: .twelve) == base.position(ofCell: 3, layout: .twelve))
    }

    /// 円に並べたマスは枠に収まり、隣と重ならない
    @Test func theRingFitsTheGrid() {
        let size = CGSize(width: 616, height: 361)
        for layout in PageLayout.allCases where layout != .nine {
            let cell = SettingsRingLayout.cellSize(for: layout, in: size)
            let frames = (0..<layout.slotCount).map { index in
                let center = SettingsRingLayout.center(of: index, layout: layout, in: size, cell: cell)
                return CGRect(x: center.x - cell.width / 2, y: center.y - cell.height / 2, width: cell.width, height: cell.height)
            }
            for (index, frame) in frames.enumerated() {
                #expect(CGRect(origin: .zero, size: size).insetBy(dx: -0.5, dy: -0.5).contains(frame), "\(layout) \(index)")
                for other in frames[(index + 1)...] {
                    #expect(!frame.intersects(other), "\(layout) \(index)")
                }
            }
        }
    }
}
