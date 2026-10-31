// 担当: ui-settings
// 共通マス: サイドバーの「共通マス」の行での編集と元に戻す、ほかのプロファイルでの見え方（その場では編集しない）、
// 「共通マスにする」「共通マスをやめる」、書き出しと読み込みの確認、絞り込み
import AppKit
import Foundation
import NonetCore
@testable import NonetUI
import Testing

@Suite @MainActor struct SettingsSharedCellsTests {
    static let mute = SettingsFixtures.key("ミュート", .key("m", [.command, .shift]))

    /// グローバル: [Safari, 空, ターミナル]、Xcode（プリセット）、Safari（空・無効）。共通マスを 4 に置く
    private func harness(shared: Bool = true) throws -> SettingsHarness {
        let h = try SettingsHarness()
        h.model.undoManager.groupsByEvent = false
        if shared {
            h.controller.update { $0.setSharedCell(Self.mute, at: 4) }
        }
        return h
    }

    private func sharedTitle(_ h: SettingsHarness, _ position: Int) -> String? {
        h.controller.configuration.sharedCells[position]?.title
    }

    // MARK: - 共通マスの行

    @Test func theSharedRowIsAOnePageGridEditedLikeAProfile() throws {
        let h = try harness(shared: false)
        let profiles = h.controller.configuration.profiles
        h.model.selectProfile(SharedCells.profileID)
        #expect(h.model.isSharedCellsSelected)
        #expect(h.model.selectedProfile.id == SharedCells.profileID)
        #expect(h.model.selectedProfile.pages.count == 1)
        #expect(!h.model.canAddPage)
        #expect(SettingsText.profileName(h.model.selectedProfile) == L10n.ui("共通マス"))
        #expect(SettingsText.profileDescription(h.model.selectedProfile) == SettingsText.sharedCellsDescription)
        // 共通マスの行では、どの位置も共通マスの「代わり」ではない
        #expect(h.model.sharedCell(at: 4) == nil)

        h.model.createCell(kind: .keystroke, at: 4)
        let created = try #require(h.controller.configuration.sharedCells[4])
        #expect(h.model.selectedCell == created)
        // プロファイルには触れない
        #expect(h.controller.configuration.profiles == profiles)
        #expect(try h.saved()?.sharedCells[4] == created)

        h.model.undoManager.undo()
        #expect(h.controller.configuration.sharedCells.isEmpty)
        h.model.undoManager.redo()
        #expect(h.controller.configuration.sharedCells[4] == created)
    }

    @Test func inspectorEditsOfASharedCellCanBeUndone() throws {
        let h = try harness()
        h.model.selectProfile(SharedCells.profileID)
        h.model.selectCell(4)
        let shared = try #require(h.model.selectedCell)
        h.model.updateCell(id: shared.id) { $0.title = "マイクを切る" }
        #expect(sharedTitle(h, 4) == "マイクを切る")
        #expect(try h.saved()?.sharedCells[4]?.title == "マイクを切る")
        h.model.selectCell(0)
        #expect(h.model.undoManager.undoActionName == SettingsModel.inspectorEditActionName)
        h.model.undoManager.undo()
        #expect(sharedTitle(h, 4) == "ミュート")
        #expect(h.model.isSharedCellsSelected)
        #expect(h.model.selectedIndex == 4)
    }

    @Test func swappingAndClearingInTheSharedRowChangeOnlySharedCells() throws {
        let h = try harness()
        let profiles = h.controller.configuration.profiles
        h.model.selectProfile(SharedCells.profileID)
        h.model.swapCell(at: 4, .up)
        #expect(h.controller.configuration.sharedCells.occupiedPositions == [1])
        h.model.clearCell(at: 1)
        #expect(h.controller.configuration.sharedCells.isEmpty)
        #expect(h.controller.configuration.profiles == profiles)
        h.model.undoManager.undo()
        h.model.undoManager.undo()
        #expect(sharedTitle(h, 4) == "ミュート")
    }

    // MARK: - ほかのプロファイルでの見え方

    @Test func otherProfilesShowTheSharedCellAndKeepTheirOwnCell() throws {
        let h = try harness()
        let xcode = try #require(h.xcodeProfile)
        let own = try #require(xcode.pages[0].cells[4])
        h.model.selectProfile(xcode.id)
        h.model.selectCell(4)
        #expect(h.model.sharedCell(at: 4)?.title == "ミュート")
        #expect(h.model.isCoveredByShared(CellAddress(page: 1, index: 4)))
        // その場では編集しない（インスペクタは説明と「共通マスを編集」を出す）
        #expect(h.model.selectedCell == nil)
        #expect(!h.model.focusNameField())
        #expect(h.model.displayedProfile.pages[0].cells[4]?.title == "ミュート")
        // Xcode のマスは設定に残っている
        #expect(h.xcodeProfile?.pages[0].cells[4] == own)
    }

    @Test func sharedPositionsCannotBeEditedInPlace() throws {
        let h = try harness()
        let xcode = try #require(h.xcodeProfile)
        h.model.selectProfile(xcode.id)
        let before = h.controller.configuration

        h.model.clearCell(at: 4)
        h.model.duplicateCell(at: 4)
        h.model.swapCell(at: 4, .up)
        h.model.swapCell(at: 1, .down)
        #expect(!h.model.canSwapCell(at: 4, .left))
        #expect(!h.model.canSwapCell(at: 3, .right))
        let drag = SettingsDragPayload.cell(profileID: xcode.id, address: CellAddress(page: 0, index: 4))
        #expect(!h.model.handleDrop(drag, onto: 0))
        let onto = SettingsDragPayload.cell(profileID: xcode.id, address: CellAddress(page: 0, index: 0))
        #expect(!h.model.handleDrop(onto, onto: 4))
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("nonet-shared-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        h.model.selectCell(0)
        #expect(h.model.copyCell(at: 0, to: pasteboard))
        h.model.pasteCell(at: 4, from: pasteboard)
        h.model.assignMenuItem(MenuItemNode(title: "保存", path: ["ファイル", "保存"]), to: CellAddress(page: 0, index: 4))

        #expect(h.controller.configuration == before)
        #expect(!h.model.undoManager.canUndo)
    }

    @Test func emptyCellSearchesSkipSharedPositions() throws {
        let h = try harness()
        // Safari のプロファイルは空。左上だけ置き、共通マスを右上（2）にも置く
        let safari = try #require(h.safariProfile)
        h.controller.update {
            $0.setSharedCell(SettingsFixtures.key("ロック", .key("q", [.command, .control])), at: 1)
            $0.setCell(SettingsFixtures.launch(SettingsFixtures.notes), at: CellAddress(page: 0, index: 0), profileID: safari.id)
        }
        h.model.selectProfile(safari.id)
        // 共通マスの位置（空いていても）には作らない
        h.model.createCell(kind: .openURL, at: 1)
        #expect(h.safariProfile?.pages[0].cells[1] == nil)
        // 複製は共通マスの位置を飛ばす
        h.model.duplicateCell(at: 0)
        #expect(h.safariProfile?.pages[0].cells[1] == nil)
        #expect(h.safariProfile?.pages[0].cells[2]?.title == SettingsFixtures.notes.name)
        // ほかのプロファイルへのコピーも、共通マスの位置を空きにしない
        h.model.selectProfile(h.controller.configuration.globalProfile.id)
        h.model.copyCell(at: 0, toProfile: safari.id)
        #expect(h.safariProfile?.pages[0].cells[1] == nil)
        #expect(h.safariProfile?.pages[0].cells[3]?.title == SettingsFixtures.safari.name)
    }

    @Test func editSharedCellJumpsToTheSharedRow() throws {
        let h = try harness()
        let xcode = try #require(h.xcodeProfile)
        h.model.showProfile(id: xcode.id, at: CellAddress(page: 0, index: 4))
        h.model.selectTab(.general)
        h.model.editSharedCell(at: 4)
        #expect(h.model.tab == .profiles)
        #expect(h.model.isSharedCellsSelected)
        #expect(h.model.selectedIndex == 4)
        #expect(h.model.selectedCell?.title == "ミュート")
    }

    // MARK: - 共通マスにする・やめる

    @Test func makeSharedCopiesTheCellAndKeepsTheProfileCell() throws {
        let h = try harness(shared: false)
        let xcode = try #require(h.xcodeProfile)
        let own = try #require(xcode.pages[0].cells[0])
        h.model.selectProfile(xcode.id)
        #expect(h.model.canMakeShared(at: 0))
        h.model.requestMakeShared(at: 0)
        #expect(h.model.confirmation == nil)
        let shared = try #require(h.controller.configuration.sharedCells[0])
        #expect(shared.title == own.title)
        #expect(shared.action == own.action)
        #expect(shared.id != own.id)
        #expect(h.xcodeProfile?.pages[0].cells[0] == own)
        // グローバル（Safari を開くマス）でも、同じ位置にこのマスが出る
        #expect(h.controller.configuration.resolvedPages(frontmostBundleID: nil)[0].cells[0] == shared)
        #expect(h.model.undoNotice?.actionName == SettingsModel.makeSharedActionName)
        #expect(!h.model.canMakeShared(at: 0))

        h.model.undoManager.undo()
        #expect(h.controller.configuration.sharedCells.isEmpty)
        #expect(h.xcodeProfile?.pages[0].cells[0] == own)
        h.model.undoManager.redo()
        #expect(h.controller.configuration.sharedCells[0]?.title == own.title)
    }

    @Test func makingSharedWhereASharedCellExistsAsksFirst() throws {
        let h = try harness()
        let xcode = try #require(h.xcodeProfile)
        let own = try #require(xcode.pages[0].cells[4])
        h.model.selectProfile(xcode.id)
        h.model.requestMakeShared(at: 4)
        let confirmation = try #require(h.model.confirmation)
        #expect(confirmation == .replaceSharedCell(profileID: xcode.id, address: CellAddress(page: 0, index: 4)))
        #expect(sharedTitle(h, 4) == "ミュート")
        h.model.confirm(confirmation)
        #expect(sharedTitle(h, 4) == own.title)
        h.model.undoManager.undo()
        #expect(sharedTitle(h, 4) == "ミュート")
    }

    @Test func makeSharedIsNotOfferedInTheSharedRowOrOnEmptyCells() throws {
        let h = try harness()
        h.model.selectProfile(SharedCells.profileID)
        #expect(!h.model.canMakeShared(at: 4))
        h.model.requestMakeShared(at: 4)
        #expect(h.model.confirmation == nil)
        h.model.selectProfile(h.controller.configuration.globalProfile.id)
        #expect(!h.model.canMakeShared(at: 1))
        #expect(h.model.canMakeShared(at: 0))
    }

    @Test func stopSharingBringsBackEachProfileCell() throws {
        let h = try harness()
        let xcode = try #require(h.xcodeProfile)
        let own = try #require(xcode.pages[0].cells[4])
        h.model.selectProfile(xcode.id)
        h.model.selectCell(4)
        h.model.stopSharing(at: 4)
        #expect(h.controller.configuration.sharedCells.isEmpty)
        #expect(h.model.sharedCell(at: 4) == nil)
        #expect(h.model.selectedCell == own)
        #expect(h.model.undoNotice?.actionName == SettingsModel.stopSharingActionName)

        h.model.undoFromNotice()
        #expect(sharedTitle(h, 4) == "ミュート")
        #expect(try h.saved()?.sharedCells[4]?.title == "ミュート")
    }

    // MARK: - 書き出しと読み込み

    @Test func theFullExportIncludesSharedCellsAndAProfileExportDoesNot() async throws {
        let h = try harness()
        let all = h.temporaryFile("all.nonetprofile")
        h.files.exportURL = all
        await h.model.exportAllProfiles(suggestedName: "Nonet")
        #expect(try ConfigurationStore.importDocument(from: Data(contentsOf: all)).sharedCells[4]?.title == "ミュート")

        let xcode = try #require(h.xcodeProfile)
        let one = h.temporaryFile("one.nonetprofile")
        h.files.exportURL = one
        await h.model.exportProfiles([xcode], suggestedName: "Xcode")
        #expect(try ConfigurationStore.importDocument(from: Data(contentsOf: one)).sharedCells.isEmpty)
    }

    @Test func importingSharedCellsIsReviewedAndReplacesThem() throws {
        let h = try harness()
        let colleague = try harness(shared: false)
        let script = Cell(title: "片付け", icon: .symbol("trash"), action: .script(ScriptAction(source: "rm -rf ~/tmp/cache")))
        colleague.controller.update { $0.setSharedCell(script, at: 2) }
        let url = h.temporaryFile("colleague.nonetprofile")
        h.model.exportProfiles(colleague.controller.configuration.profiles, sharedCells: colleague.controller.configuration.sharedCells, to: url)
        h.model.fileMessage = nil

        h.model.importProfiles(from: url)
        guard case .importProfiles(let plan)? = h.model.confirmation else {
            Issue.record("確かめずに読み込んだ")
            return
        }
        #expect(plan.result.replacedSharedCells)
        #expect(plan.replacesExisting)
        let reviewed = try #require(plan.reviewedCells.first { $0.cell.title == "片付け" })
        #expect(reviewed.profileName == L10n.ui("共通マス"))
        #expect(SettingsText.importReplacementLines(plan).contains(L10n.ui("・\(L10n.ui("共通マス"))")))
        #expect(SettingsText.importConfirmation(plan).contains("rm -rf ~/tmp/cache"))
        // 中身を最後まで見るまでは読み込まない
        h.model.confirm(.importProfiles(plan))
        #expect(sharedTitle(h, 4) == "ミュート")

        h.model.markImportReviewRead()
        h.model.confirm(.importProfiles(plan))
        #expect(h.controller.configuration.sharedCells.occupiedPositions == [2])
        #expect(sharedTitle(h, 2) == "片付け")
        let text = try #require(h.model.fileMessage?.text)
        #expect(text.contains(L10n.ui("共通マスを置き換えました。")))
        #expect(text.contains(L10n.ui("スクリプトを含むマスがあります。実行する前に中身を確かめてください。")))
    }

    @Test func importingOnlyNewProfilesLeavesSharedCellsAlone() throws {
        let h = try harness()
        let colleague = try harness(shared: false)
        colleague.model.addProfile(for: SettingsFixtures.figma)
        colleague.controller.update { $0.setSharedCell(SettingsFixtures.launch(SettingsFixtures.notes), at: 0) }
        let url = h.temporaryFile("colleague.nonetprofile")
        h.model.exportProfiles(colleague.controller.configuration.profiles, sharedCells: colleague.controller.configuration.sharedCells, to: url)
        h.model.importProfiles(from: url)
        guard case .importProfiles(let plan)? = h.model.confirmation else {
            Issue.record("確かめずに読み込んだ")
            return
        }
        #expect(plan.newProfilesOnly(in: h.controller.configuration).sharedCells.isEmpty)
        h.model.markImportReviewRead()
        h.model.importNewProfilesOnly(plan)
        #expect(h.controller.configuration.sharedCells.occupiedPositions == [4])
        #expect(h.model.appProfiles.contains { $0.app?.bundleID == SettingsFixtures.figma.bundleID })
    }

    /// 共通マスを置き換える読み込みの後は、共通マスの取り消しは場所が合わないので忘れる
    @Test func aReplacingImportForgetsSharedCellUndo() throws {
        let h = try harness()
        h.model.selectProfile(SharedCells.profileID)
        h.model.createCell(kind: .openURL, at: 0)
        #expect(h.model.undoManager.canUndo)
        let colleague = try harness(shared: false)
        colleague.controller.update { $0.setSharedCell(SettingsFixtures.launch(SettingsFixtures.notes), at: 8) }
        var document = ConfigurationStore.ImportedProfiles(profiles: [], sharedCells: colleague.controller.configuration.sharedCells)
        document.profiles = [Profile(kind: .app(SettingsFixtures.figma))]
        let plan = SettingsImportPlan(document: document, configuration: h.controller.configuration, fileName: "x")
        h.model.confirm(.importProfiles(plan))
        #expect(h.controller.configuration.sharedCells.occupiedPositions == [8])
        #expect(!h.model.undoManager.canUndo)
    }

    // MARK: - 絞り込み

    @Test func theFilterFindsSharedCellsAndSkipsHiddenProfileCells() throws {
        let h = try harness()
        let xcode = try #require(h.xcodeProfile)
        let hidden = try #require(xcode.pages[0].cells[4])
        let results = SettingsProfileSearch.results(for: "ミュート", in: h.controller.configuration)
        let match = try #require(results.cells.first)
        #expect(match.profileID == SharedCells.profileID)
        #expect(match.path == "\(L10n.ui("共通マス")) › ミュート")
        // 共通マスに隠れている Xcode のマスは出さない
        let hiddenResults = SettingsProfileSearch.results(for: SettingsGrid.displayTitle(for: hidden), in: h.controller.configuration)
        #expect(!hiddenResults.cells.contains { $0.profileID == xcode.id && $0.address.index == 4 })

        h.model.reveal(match)
        #expect(h.model.isSharedCellsSelected)
        #expect(h.model.selectedIndex == 4)
    }

    // MARK: - 見た目の文言

    /// HUD と設定のグリッドの VoiceOver は、共通マスであることを同じ言葉で言う
    @Test func theHUDAndTheGridSayTheCellIsShared() {
        let shared = HUDCell(title: "ミュート", icon: .symbol("mic.slash"), isShared: true)
        let plain = HUDCell(title: "ビルド", icon: .symbol("hammer"))
        #expect(HUDAnnouncement.sharedValue(shared) == SettingsText.sharedCellAccessibilityValue)
        #expect(SettingsText.sharedCellAccessibilityValue.isEmpty == false)
        #expect(HUDAnnouncement.sharedValue(plain) == nil)
        #expect(HUDAnnouncement.sharedValue(nil) == nil)
    }
}
