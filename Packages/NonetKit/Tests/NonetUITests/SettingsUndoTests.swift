// 担当: ui-settings
// マスの変更（空にする・入れ替える・作る・複製・メニュー項目の割り当て）を元に戻す・やり直す
import AppKit
import Foundation
import NonetCore
@testable import NonetUI
import Testing

@Suite @MainActor struct SettingsUndoTests {
    /// アプリではイベントごと（run loop の1回りごと）に区切られる。テストでは run loop が回らないので、操作ごとに区切る
    private func harness() throws -> SettingsHarness {
        let h = try SettingsHarness()
        h.model.undoManager.groupsByEvent = false
        return h
    }

    private func cell(_ h: SettingsHarness, _ index: Int, page: Int = 0) -> Cell? {
        h.model.selectedProfile.pages[page].cells[index]
    }

    @Test func clearingACellCanBeUndoneAndRedone() throws {
        let h = try harness()
        let safari = try #require(cell(h, 0))
        h.model.clearCell(at: 0)
        #expect(cell(h, 0) == nil)
        #expect(h.model.undoManager.canUndo)
        #expect(h.model.undoManager.undoActionName == L10n.ui("マスを空にする"))

        h.model.selectCell(5)
        h.model.undoManager.undo()
        #expect(cell(h, 0) == safari)
        // 戻したマスを選ぶ
        #expect(h.model.selectedIndex == 0)
        #expect(try h.saved()?.globalProfile.pages[0].cells[0] == safari)

        #expect(h.model.undoManager.canRedo)
        h.model.undoManager.redo()
        #expect(cell(h, 0) == nil)
        #expect(try h.saved()?.globalProfile.pages[0].cells[0] == nil)
    }

    @Test func eachChangeIsUndoneSeparately() throws {
        let h = try harness()
        let safari = try #require(cell(h, 0))
        h.model.clearCell(at: 0)
        h.model.createCell(kind: .openURL, at: 1)
        #expect(h.model.undoManager.undoActionName == L10n.ui("アクションを追加"))
        h.model.undoManager.undo()
        #expect(cell(h, 1) == nil)
        #expect(cell(h, 0) == nil)
        h.model.undoManager.undo()
        #expect(cell(h, 0) == safari)
        #expect(!h.model.undoManager.canUndo)
    }

    @Test func undoingASwapKeepsLaterEdits() throws {
        let h = try harness()
        let safari = try #require(cell(h, 0))
        let terminal = try #require(cell(h, 2))
        let payload = SettingsDragPayload.cell(profileID: h.model.selectedProfile.id, address: CellAddress(page: 0, index: 0))
        #expect(h.model.handleDrop(payload, onto: 2))
        #expect(h.model.undoManager.undoActionName == L10n.ui("マスの入れ替え"))
        // 入れ替えた後に名前を変えても、元に戻すと変えた名前のまま元の場所へ戻る
        h.model.updateCell(id: safari.id) { $0.title = "ブラウザ" }
        h.model.undoManager.undo()
        #expect(cell(h, 0)?.id == safari.id)
        #expect(cell(h, 0)?.title == "ブラウザ")
        #expect(cell(h, 2) == terminal)
        h.model.undoManager.redo()
        #expect(cell(h, 2)?.id == safari.id)
        #expect(cell(h, 0) == terminal)
    }

    @Test func movingToAnEmptyCellIsUndoneAsAMove() throws {
        let h = try harness()
        let safari = try #require(cell(h, 0))
        h.model.swapCells(CellAddress(page: 0, index: 0), CellAddress(page: 0, index: 8))
        #expect(h.model.undoManager.undoActionName == L10n.ui("マスの移動"))
        h.model.undoManager.undo()
        #expect(cell(h, 0) == safari)
        #expect(cell(h, 8) == nil)
    }

    @Test func duplicatingCanBeUndone() throws {
        let h = try harness()
        h.model.duplicateCell(at: 0)
        #expect(cell(h, 1) != nil)
        #expect(h.model.undoManager.undoActionName == L10n.ui("複製"))
        h.model.undoManager.undo()
        #expect(cell(h, 1) == nil)
    }

    /// メニュー項目を中身のあるマスに落とすと置き換わる。元に戻せば前の中身が戻る
    @Test func aMenuItemDroppedOnAFilledCellCanBeUndone() async throws {
        let h = try harness()
        h.menus.apps = [SettingsMenuSamples.figma]
        h.menus.items = SettingsMenuSamples.figmaMenus
        h.model.showMenus(true)
        h.model.menuBrowser.select(SettingsMenuSamples.figma)
        await h.model.menuBrowser.waitUntilLoaded()
        let safari = try #require(cell(h, 0))
        let node = MenuItemNode(title: "自動レイアウトを追加", path: ["オブジェクト", "自動レイアウトを追加"], keyEquivalent: .key("a", .shift))
        #expect(h.model.handleDrop(.menuItem(id: node.id), onto: 0))
        #expect(cell(h, 0)?.action.kind == .menuItem)
        #expect(h.model.undoManager.undoActionName == L10n.ui("メニュー項目の割り当て"))
        h.model.undoManager.undo()
        #expect(cell(h, 0) == safari)
        #expect(try h.saved()?.globalProfile.pages[0].cells[0] == safari)
    }

    @Test func undoingShowsTheProfileThatChanged() throws {
        let h = try harness()
        let xcode = try #require(h.xcodeProfile)
        h.model.selectProfile(xcode.id)
        h.model.selectCell(4)
        let original = try #require(h.model.selectedCell)
        h.model.clearCell(at: 4)
        h.model.selectProfile(nil)
        h.model.undoManager.undo()
        #expect(h.model.selectedProfile.id == xcode.id)
        #expect(h.model.selectedIndex == 4)
        #expect(h.model.selectedCell == original)
    }

    /// ページやプロファイルを消すと場所がずれるので、それより前の変更は元に戻せなくする
    @Test func removingAPageOrProfileForgetsEarlierChanges() throws {
        let h = try harness()
        h.model.addPage()
        h.model.createCell(kind: .ai, at: 3)
        h.model.selectPage(0)
        h.model.clearCell(at: 0)
        #expect(h.model.undoManager.canUndo)
        h.model.removePage(1, profileID: h.model.selectedProfile.id)
        #expect(!h.model.undoManager.canUndo)

        let xcode = try #require(h.xcodeProfile)
        h.model.selectProfile(xcode.id)
        h.model.clearCell(at: 0)
        #expect(h.model.undoManager.canUndo)
        h.model.deleteProfile(xcode.id)
        #expect(!h.model.undoManager.canUndo)
    }

    /// 間にほかの変更（元に戻せない変更）があって、覚えた中身と合わなければ何もしない
    @Test func aStaleUndoChangesNothing() throws {
        let h = try harness()
        h.model.createCell(kind: .ai, at: 1)
        let profileID = h.model.selectedProfile.id
        // 設定画面の外で同じ場所が変わった
        h.controller.update { $0.setCell(SettingsFixtures.launch(SettingsFixtures.figma), at: CellAddress(page: 0, index: 1), profileID: profileID) }
        let before = h.controller.configuration
        h.model.undoManager.undo()
        #expect(h.controller.configuration == before)
    }

    @Test func nothingIsRecordedWhenNothingChanges() throws {
        let h = try harness()
        h.model.clearCell(at: 1)
        h.model.createCell(kind: .ai, at: 0)
        #expect(!h.model.undoManager.canUndo)
    }
}
