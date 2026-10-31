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
        // 入れ替えた後に（取り消しに積まれないところで）名前を変えても、元に戻すと変えた名前のまま元の場所へ戻る
        var renamed = safari
        renamed.title = "ブラウザ"
        let profileID = h.model.selectedProfile.id
        h.controller.update { $0.setCell(renamed, at: CellAddress(page: 0, index: 2), profileID: profileID) }
        h.model.undoManager.undo()
        #expect(cell(h, 0)?.id == safari.id)
        #expect(cell(h, 0)?.title == "ブラウザ")
        #expect(cell(h, 2) == terminal)
        h.model.undoManager.redo()
        #expect(cell(h, 2)?.id == safari.id)
        #expect(cell(h, 0) == terminal)
    }

    /// 入れ替えた後にインスペクタで変えたものは、それだけ先に戻る（その次に入れ替えが戻る）
    @Test func inspectorEditsAfterASwapAreUndoneFirst() throws {
        let h = try harness()
        let safari = try #require(cell(h, 0))
        let terminal = try #require(cell(h, 2))
        h.model.swapCells(CellAddress(page: 0, index: 0), CellAddress(page: 0, index: 2))
        h.model.updateCell(id: safari.id) { $0.title = "ブラウザ" }
        #expect(h.model.undoManager.undoActionName == L10n.ui("ボタンの変更"))
        h.model.undoManager.undo()
        #expect(cell(h, 2) == safari)
        #expect(cell(h, 0) == terminal)
        #expect(h.model.undoManager.undoActionName == L10n.ui("マスの入れ替え"))
        h.model.undoManager.undo()
        #expect(cell(h, 0) == safari)
        #expect(cell(h, 2) == terminal)
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

    /// ページやプロファイルを消しても元に戻せる。取り消しは積んだ順に戻るので、それより前の変更も、戻した後なら戻せる
    @Test func removingAPageOrProfileCanBeUndoneAndKeepsEarlierChanges() throws {
        let h = try harness()
        let safari = try #require(cell(h, 0))
        h.model.addPage()
        h.model.createCell(kind: .ai, at: 3)
        let ai = try #require(cell(h, 3, page: 1))
        h.model.selectPage(0)
        h.model.clearCell(at: 0)
        h.model.removePage(1, profileID: h.model.selectedProfile.id)
        #expect(h.model.selectedProfile.pages.count == 1)
        #expect(h.model.undoManager.undoActionName == L10n.ui("ページの削除"))
        h.model.undoManager.undo()
        #expect(h.model.selectedProfile.pages.count == 2)
        #expect(cell(h, 3, page: 1) == ai)
        h.model.undoManager.undo()
        #expect(cell(h, 0) == safari)
        h.model.undoManager.undo()
        #expect(cell(h, 3, page: 1) == nil)

        let xcode = try #require(h.xcodeProfile)
        h.model.selectProfile(xcode.id)
        let original = try #require(cell(h, 0))
        h.model.clearCell(at: 0)
        h.model.deleteProfile(xcode.id)
        #expect(h.xcodeProfile == nil)
        #expect(h.model.undoManager.undoActionName == L10n.ui("プロファイルの削除"))
        h.model.undoManager.undo()
        #expect(h.xcodeProfile?.id == xcode.id)
        #expect(h.model.appProfiles.first?.id == xcode.id)
        #expect(h.model.selectedProfile.id == xcode.id)
        h.model.undoManager.undo()
        #expect(cell(h, 0) == original)
        // やり直すと、また消える
        h.model.undoManager.redo()
        h.model.undoManager.redo()
        #expect(h.xcodeProfile == nil)
        #expect(try h.saved()?.profiles.contains { $0.id == xcode.id } == false)
    }

    /// 3ページのうち2ページ目を消し（3ページ目は空けたマスがある）、続く操作を待つ。消えたページの次のページで空けたマスを返す
    private func removeTheMiddlePageAfterClearingACell(_ h: SettingsHarness) throws -> Cell {
        let globalID = h.model.selectedProfile.id
        h.model.addPage()
        h.model.addPage()
        #expect(h.model.selectedProfile.pages.count == 3)
        // 2ページ目にマスを置く（消すページ。中身があるので控えも残る）
        h.model.selectPage(1)
        h.model.createCell(kind: .openURL, at: 0)
        // 3ページ目のマスを作ってから空にする
        h.model.selectPage(2)
        h.model.createCell(kind: .openURL, at: 4)
        let cleared = try #require(h.model.selectedProfile.pages[2].cells[4])
        h.model.clearCell(at: 4)
        // 2ページ目を消す → 3ページ目が2ページ目になる
        h.model.removePage(1, profileID: globalID)
        #expect(h.model.selectedProfile.pages.count == 2)
        return cleared
    }

    /// ページの追加も元に戻せる。消したページを戻す前に足したページを消すので、上限で戻せなくなることも、
    /// その下のマスの取り消しが番号のずれた別のページに入ることもない
    @Test func addingAPageIsUndoneBeforeARemovedPageIsRestored() throws {
        let h = try harness()
        let cleared = try removeTheMiddlePageAfterClearingACell(h)
        h.model.addPage()
        #expect(h.model.selectedProfile.pages.count == 3)
        #expect(h.model.undoManager.undoActionName == L10n.ui("ページを追加"))
        h.model.undoManager.undo()   // 足したページを消す
        #expect(h.model.selectedProfile.pages.count == 2)
        h.model.undoManager.undo()   // 消したページを戻す
        #expect(h.model.selectedProfile.pages.count == 3)
        #expect(h.model.gridMessage == nil)
        #expect(h.model.selectedProfile.pages[1].cells[0] != nil)
        h.model.undoManager.undo()   // マスを空にしたことを戻す（元のページに）
        #expect(h.model.selectedProfile.pages[2].cells[4]?.id == cleared.id)
        // やり直すと、また空にしてページを消し、ページを足す
        h.model.undoManager.redo()
        h.model.undoManager.redo()
        h.model.undoManager.redo()
        let pages = h.model.selectedProfile.pages
        #expect(pages.count == 3)
        #expect(pages[1].cells[4] == nil)
        #expect(pages[2].cells.allSatisfy { $0 == nil })
        #expect(h.model.undoManager.undoActionName == L10n.ui("ページを追加"))
    }

    /// 足したページにマスがあれば（取り消しに積まれない変更で）、ページは消さずに知らせる
    @Test func anAddedPageWithCellsIsNotRemoved() throws {
        let h = try harness()
        let profileID = h.model.selectedProfile.id
        h.model.addPage()
        h.controller.update { $0.setCell(SettingsFixtures.launch(SettingsFixtures.figma), at: CellAddress(page: 1, index: 2), profileID: profileID) }
        let before = h.controller.configuration
        h.model.undoManager.undo()
        #expect(h.controller.configuration == before)
        #expect(h.model.gridMessage == L10n.ui("マスがその後に変わったため、元に戻せませんでした"))
    }

    /// 取り消しに積まれない変更でページが上限になり、消したページを戻せなければ、
    /// その下に積んだマスの取り消しは忘れる（番号のずれた別のページにマスを入れない）
    @Test func aPageThatCannotBeRestoredDropsTheCellUndoBelowIt() throws {
        let h = try harness()
        let profileID = h.model.selectedProfile.id
        let cleared = try removeTheMiddlePageAfterClearingACell(h)
        // 設定画面の外で（取り消しに積まれずに）ページが足された
        h.controller.update { _ = $0.addPage(profileID: profileID) }
        #expect(h.model.selectedProfile.pages.count == 3)
        h.model.undoManager.undo()   // 上限で戻せない
        #expect(h.model.selectedProfile.pages.count == 3)
        #expect(h.model.gridMessage != nil)
        #expect(!h.model.undoManager.canUndo)
        h.model.undoManager.undo()
        #expect(!h.model.selectedProfile.pages.contains { $0.cells.contains { $0?.id == cleared.id } })
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

    /// インスペクタで書き足したもの（スクリプトと名前）は1つの取り消しで戻り、その次にマスを作ったことが戻る
    @Test func inspectorEditsAreUndoneAsOneStep() throws {
        let h = try harness()
        h.model.createCell(kind: .script, at: 1)
        let created = try #require(cell(h, 1))
        let source = (1...20).map { "echo \($0)" }.joined(separator: "\n")
        h.model.updateAction(ofCell: created.id, as: ScriptAction.self) { $0.source = source }
        h.model.updateCell(id: created.id) { $0.title = "ビルド" }
        #expect(h.model.undoManager.undoActionName == L10n.ui("ボタンの変更"))
        h.model.selectCell(4)
        h.model.undoManager.undo()
        #expect(cell(h, 1) == created)
        #expect(h.model.selectedIndex == 1)
        h.model.undoManager.undo()
        #expect(cell(h, 1) == nil)
        #expect(!h.model.undoManager.canUndo)
    }

    /// 作ったマスに（文字の欄を打っている間で、まだ取り消しに積んでいない）書き足しがあれば、元に戻してもそれごと消さない。戻せない理由を知らせる
    @Test func undoingKeepsWhatWasWrittenInTheInspectorSince() throws {
        let h = try harness()
        h.model.createCell(kind: .script, at: 1)
        let id = try #require(cell(h, 1)?.id)
        let source = (1...20).map { "echo \($0)" }.joined(separator: "\n")
        h.model.isEditingText = { true }
        h.model.updateAction(ofCell: id, as: ScriptAction.self) { $0.source = source }
        h.model.updateCell(id: id) { $0.title = "ビルド" }
        let written = try #require(cell(h, 1))
        h.model.undoManager.undo()
        #expect(cell(h, 1) == written)
        #expect(try h.saved()?.globalProfile.pages[0].cells[1] == written)
        #expect(h.model.selectedIndex == 1)
        #expect(h.model.gridMessage == L10n.ui("マスがその後に変わったため、元に戻せませんでした"))
        // 次の変更の後でも、書き足したものは残っている
        h.model.isEditingText = { false }
        h.model.clearCell(at: 0)
        #expect(cell(h, 1) == written)
    }

    /// 置き換えたメニュー項目の名前を変えた後なら、前の中身に戻さない（変えた名前を失わない）
    @Test func undoingAReplacedCellKeepsLaterEdits() async throws {
        let h = try harness()
        h.menus.apps = [SettingsMenuSamples.figma]
        h.menus.items = SettingsMenuSamples.figmaMenus
        h.model.showMenus(true)
        h.model.menuBrowser.select(SettingsMenuSamples.figma)
        await h.model.menuBrowser.waitUntilLoaded()
        let node = MenuItemNode(title: "自動レイアウトを追加", path: ["オブジェクト", "自動レイアウトを追加"], keyEquivalent: .key("a", .shift))
        #expect(h.model.handleDrop(.menuItem(id: node.id), onto: 0))
        let assigned = try #require(cell(h, 0))
        h.model.updateCell(id: assigned.id) { $0.title = "レイアウト" }
        // 名前の変更が先に戻り、その次に置き換える前の中身に戻る
        h.model.undoManager.undo()
        #expect(cell(h, 0) == assigned)
        h.model.undoManager.undo()
        #expect(cell(h, 0)?.action.kind == .launchApp)
    }

    /// ほかのタブで元に戻すと、プロファイルのタブに移って変わったマスを見せる
    @Test func undoingFromAnotherTabShowsTheProfiles() throws {
        let h = try harness()
        let safari = try #require(cell(h, 0))
        h.model.clearCell(at: 0)
        h.model.selectTab(.general)
        h.model.undoManager.undo()
        #expect(h.model.tab == .profiles)
        #expect(h.model.selectedIndex == 0)
        #expect(cell(h, 0) == safari)
    }

    /// ページを消しても、ほかのプロファイルの変更は戻せる
    @Test func removingAPageKeepsChangesInOtherProfiles() throws {
        let h = try harness()
        let xcode = try #require(h.xcodeProfile)
        h.model.selectProfile(xcode.id)
        let original = try #require(cell(h, 0))
        h.model.clearCell(at: 0)
        h.model.selectProfile(nil)
        h.model.addPage()
        // 空のページは確かめずに消える
        h.model.requestRemovePage(1)
        #expect(h.model.confirmation == nil)
        #expect(h.model.selectedProfile.pages.count == 1)
        // 消したページが先に戻り、次に足したページが消える
        h.model.undoManager.undo()
        #expect(h.model.selectedProfile.pages.count == 2)
        h.model.undoManager.undo()
        #expect(h.model.selectedProfile.pages.count == 1)
        h.model.undoManager.undo()
        #expect(h.model.selectedProfile.id == xcode.id)
        #expect(cell(h, 0) == original)
    }

    /// 新しいプロファイルを加えるだけの読み込みでは忘れない。置き換えた読み込みでは、そのプロファイルの分だけ忘れる
    @Test func importingForgetsOnlyTheReplacedProfiles() throws {
        let h = try harness()
        let global = try #require(cell(h, 0))
        h.model.clearCell(at: 0)
        let xcode = try #require(h.xcodeProfile)
        h.model.selectProfile(xcode.id)
        h.model.clearCell(at: 0)

        let figma = Profile(kind: .app(SettingsFixtures.figma), pages: [.empty])
        let addOnly = h.temporaryFile("figma.nonetprofile")
        h.model.exportProfiles([figma], to: addOnly)
        h.model.importProfiles(from: addOnly)
        #expect(h.model.confirmation == nil)
        #expect(h.model.undoManager.canUndo)

        // Xcode を置き換える（中身は空なので、確かめるのは置き換えだけ）
        let replacement = Profile(kind: .app(SettingsFixtures.xcode), pages: [.empty])
        let replacing = h.temporaryFile("xcode.nonetprofile")
        h.model.exportProfiles([replacement], to: replacing)
        h.model.importProfiles(from: replacing)
        let confirmation = try #require(h.model.confirmation)
        h.model.confirm(confirmation)
        #expect(h.xcodeProfile?.pages == [.empty])
        // Xcode の変更は忘れ、グローバルの変更は戻せる
        #expect(h.model.undoManager.undoActionName == L10n.ui("マスを空にする"))
        h.model.undoManager.undo()
        #expect(h.model.selectedProfile.isGlobal)
        #expect(cell(h, 0) == global)
        #expect(h.xcodeProfile?.pages == [.empty])
        #expect(!h.model.undoManager.canUndo)
    }

    /// 空にしたマスは、グリッドの下の「元に戻す」でも戻せる（編集メニューが無くても）
    @Test func aClearedCellCanBeRestoredFromTheNotice() throws {
        let h = try harness()
        let safari = try #require(cell(h, 0))
        h.model.clearCell(at: 0)
        #expect(h.model.undoNotice == SettingsUndoNotice(text: L10n.ui("マスを空にしました"), actionName: L10n.ui("マスを空にする")))
        h.model.undoFromNotice()
        #expect(cell(h, 0) == safari)
        #expect(h.model.undoNotice == nil)
        // やり直しは編集メニューから
        #expect(h.model.undoManager.canRedo)
    }

    @Test func theNoticeIsShownOnlyForChangesThatLoseSomething() async throws {
        let h = try harness()
        h.model.createCell(kind: .ai, at: 1)
        #expect(h.model.undoNotice == nil)
        h.model.duplicateCell(at: 0)
        #expect(h.model.undoNotice == nil)
        h.model.swapCells(CellAddress(page: 0, index: 0), CellAddress(page: 0, index: 8))
        #expect(h.model.undoNotice == nil)

        h.menus.apps = [SettingsMenuSamples.figma]
        h.menus.items = SettingsMenuSamples.figmaMenus
        h.model.showMenus(true)
        h.model.menuBrowser.select(SettingsMenuSamples.figma)
        await h.model.menuBrowser.waitUntilLoaded()
        let node = MenuItemNode(title: "自動レイアウトを追加", path: ["オブジェクト", "自動レイアウトを追加"], keyEquivalent: .key("a", .shift))
        // 空きマスに入れるだけなら出さない。中身のあるマスを置き換えたら出す
        #expect(h.model.handleDrop(.menuItem(id: node.id), onto: 5))
        #expect(h.model.undoNotice == nil)
        #expect(h.model.handleDrop(.menuItem(id: node.id), onto: 2))
        #expect(h.model.undoNotice?.text == L10n.ui("マスの中身をメニュー項目で置き換えました"))
        // ほかのマスを選ぶと閉じる
        h.model.selectCell(4)
        #expect(h.model.undoNotice == nil)
    }

    /// 知らせを出した後に別の取り消し（文字の入力など）が積まれていれば、知らせからは戻さない
    @Test func theNoticeDoesNotUndoSomethingElse() throws {
        let h = try harness()
        h.model.clearCell(at: 0)
        let other = SettingsUndoTarget()
        var typingUndone = false
        h.model.undoManager.beginUndoGrouping()
        h.model.undoManager.registerUndo(withTarget: other) { _ in typingUndone = true }
        h.model.undoManager.setActionName("Typing")
        h.model.undoManager.endUndoGrouping()
        h.model.undoFromNotice()
        #expect(!typingUndone)
        #expect(cell(h, 0) == nil)
        #expect(h.model.undoNotice == nil)
    }

    @Test func nothingIsRecordedWhenNothingChanges() throws {
        let h = try harness()
        h.model.clearCell(at: 1)
        h.model.createCell(kind: .ai, at: 0)
        #expect(!h.model.undoManager.canUndo)
    }
}
