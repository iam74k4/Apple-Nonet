// 担当: ui-settings
// たくさん作り込む人のための操作: 使わないアプリ・プロファイルの複製とプリセットに戻す・マスのコピーと貼り付け・
// ほかのプロファイルへのコピー・隣との入れ替え・絞り込み・ページの名前・キーボード・インスペクタの取り消し・控えと以前の設定に戻す
import AppKit
import Foundation
import NonetCore
@testable import NonetUI
import Testing

@MainActor
private func harness() throws -> SettingsHarness {
    let h = try SettingsHarness()
    // アプリではイベントごとに区切られる。テストでは run loop が回らないので、操作ごとに区切る
    h.model.undoManager.groupsByEvent = false
    return h
}

@MainActor
private func cell(_ h: SettingsHarness, _ index: Int, page: Int = 0) -> Cell? {
    h.model.selectedProfile.pages[page].cells[index]
}

/// テストごとの名前付きペーストボード（ほかのアプリのコピーを消さない）
@MainActor
private func pasteboard() -> NSPasteboard {
    NSPasteboard(name: NSPasteboard.Name("NonetSettingsTests-\(UUID().uuidString)"))
}

@Suite @MainActor struct SettingsProfileModeTests {
    @Test func theThreeWaysToUseAProfile() throws {
        let h = try harness()
        let xcode = try #require(h.xcodeProfile)
        h.model.setProfileMode(xcode.id, .off)
        #expect(h.xcodeProfile?.mode == .off)
        #expect(try h.saved()?.isTurnedOff(forBundleID: SettingsFixtures.xcode.bundleID) == true)
        h.model.setProfileMode(xcode.id, .global)
        #expect(h.xcodeProfile?.isEnabled == false)
        #expect(try h.saved()?.appProfile(forBundleID: SettingsFixtures.xcode.bundleID) == nil)
    }

    @Test func theHeaderDescribesEachWay() throws {
        let h = try harness()
        var profile = try #require(h.xcodeProfile)
        #expect(SettingsText.profileDescription(profile) == L10n.ui("\(profile.name) が前面にあるときに使う9マス"))
        profile.mode = .global
        #expect(SettingsText.profileDescription(profile) == L10n.ui("\(profile.name) ではグローバルのマスを使います。このプロファイルのマスは残しています。"))
        profile.mode = .off
        #expect(SettingsText.profileDescription(profile) == L10n.ui("\(profile.name) では Nonet を使いません。トラックパッドはいつもどおり働きます。"))
        #expect(SettingsText.name(ProfileMode.off) == L10n.ui("このアプリでは Nonet を使わない"))
        #expect(SettingsProfileRow.badge(.profile) == nil)
        #expect(SettingsProfileRow.badge(.off) == L10n.ui("オフ"))
    }
}

@Suite @MainActor struct SettingsDeletionUndoTests {
    @Test func deletingAProfileLeavesABackupAndANotice() throws {
        let h = try harness()
        let xcode = try #require(h.xcodeProfile)
        h.model.requestDeleteProfile(xcode.id)
        let confirmation = try #require(h.model.confirmation)
        h.model.confirm(confirmation)
        #expect(h.xcodeProfile == nil)
        #expect(h.model.undoNotice?.text == L10n.ui("「\(xcode.name)」のプロファイルを削除しました"))
        let backups = h.store.backups()
        #expect(backups.map(\.reason) == [.beforeDeletingProfile])
        #expect(try h.store.loadBackup(backups[0]).profile(id: xcode.id) != nil)
        // グリッドの下の「元に戻す」でも戻せる
        h.model.undoFromNotice()
        #expect(h.xcodeProfile == xcode)
    }

    /// 消した後に同じアプリのプロファイルを作っていたら、戻さずに知らせる
    @Test func aProfileCannotComeBackOverANewOne() throws {
        let h = try harness()
        let xcode = try #require(h.xcodeProfile)
        h.model.deleteProfile(xcode.id)
        h.controller.update { $0.addAppProfile(for: SettingsFixtures.xcode, preset: nil) }
        h.model.undoManager.undo()
        #expect(h.xcodeProfile?.id != xcode.id)
        #expect(h.model.gridMessage == L10n.ui("「\(xcode.name)」のプロファイルがすでにあるため、元に戻せませんでした"))
    }

    @Test func deletingAPageWithButtonsLeavesABackupAndCanBeUndone() throws {
        let h = try harness()
        h.model.addPage()
        let profileID = h.model.selectedProfile.id
        // 空のページは控えを残さない
        h.model.removePage(1, profileID: profileID)
        #expect(h.store.backups().isEmpty)
        #expect(h.model.undoNotice?.text == L10n.ui("「\(SettingsText.pageTitle(index: 1, name: nil))」を削除しました"))

        h.model.selectPage(0)
        h.model.addPage()
        h.model.createCell(kind: .ai, at: 0)
        h.model.renamePage(1, to: "要約")
        let page = h.model.selectedProfile.pages[1]
        h.model.removePage(1, profileID: profileID)
        #expect(h.store.backups().map(\.reason) == [.beforeDeletingPage])
        #expect(h.model.undoNotice?.text == L10n.ui("「\(SettingsText.pageTitle(index: 1, name: "要約"))」を削除しました"))
        h.model.undoFromNotice()
        #expect(h.model.selectedProfile.pages[1] == page)
        #expect(h.model.pageIndex == 1)
    }

    /// 消したページを戻す前に3ページにしていたら、戻さずに知らせる
    @Test func aPageCannotComeBackWhenThereAreThree() throws {
        let h = try harness()
        h.model.addPage()
        h.model.removePage(1, profileID: h.model.selectedProfile.id)
        h.controller.update { configuration in
            let id = configuration.globalProfile.id
            configuration.addPage(profileID: id)
            configuration.addPage(profileID: id)
        }
        h.model.undoManager.undo()
        #expect(h.model.selectedProfile.pages.count == Profile.maxPages)
        #expect(h.model.gridMessage == L10n.ui("ページが \(Profile.maxPages) 枚あるため、消したページを元に戻せませんでした"))
    }

    @Test func theDialogsNoLongerSayItCannotBeUndone() {
        #expect(!L10n.ui("このプロファイルのマスもすべて削除します。⌘Z で元に戻せます。").isEmpty)
        #expect(L10n.ui("このプロファイルのマスもすべて削除します。⌘Z で元に戻せます。") != L10n.ui("このプロファイルの9マスはすべて消えます。元に戻せません。"))
    }
}

@Suite @MainActor struct SettingsInspectorUndoTests {
    @Test func editsOfOneCellBecomeOneUndo() throws {
        let h = try harness()
        let safari = try #require(cell(h, 0))
        h.model.changeKind(ofCell: safari.id, to: .openURL)
        h.model.updateAction(ofCell: safari.id, as: URLAction.self) { $0.url = "https://example.com" }
        h.model.updateCell(id: safari.id) { $0.icon = .symbol("link") }
        #expect(h.model.undoManager.undoActionName == L10n.ui("マスの変更"))
        h.model.undoManager.undo()
        #expect(cell(h, 0) == safari)
        #expect(!h.model.undoManager.canUndo)
        h.model.undoManager.redo()
        #expect(cell(h, 0)?.action == .openURL(URLAction(url: "https://example.com")))
    }

    @Test func choosingAnotherCellStartsANewUndo() throws {
        let h = try harness()
        let safari = try #require(cell(h, 0))
        h.model.updateCell(id: safari.id) { $0.title = "A" }
        h.model.selectCell(2)
        h.model.selectCell(0)
        h.model.updateCell(id: safari.id) { $0.title = "B" }
        h.model.undoManager.undo()
        #expect(cell(h, 0)?.title == "A")
        h.model.undoManager.undo()
        #expect(cell(h, 0) == safari)
    }

    /// 元に戻した後の変更は、新しいまとまりになる
    @Test func editsAfterUndoAreSeparate() throws {
        let h = try harness()
        let safari = try #require(cell(h, 0))
        h.model.updateCell(id: safari.id) { $0.title = "A" }
        h.model.undoManager.undo()
        h.model.updateCell(id: safari.id) { $0.title = "B" }
        h.model.undoManager.undo()
        #expect(cell(h, 0) == safari)
    }

    /// 文字の欄を打っている間の変更は、打ち終わってから1つにして積む（欄の打ち込みの取り消しより下に入れない）
    @Test func typingIsRecordedWhenTheFieldIsLeft() throws {
        let h = try harness()
        let safari = try #require(cell(h, 0))
        h.model.isEditingText = { true }
        h.model.updateCell(id: safari.id) { $0.title = "ブラ" }
        h.model.updateCell(id: safari.id) { $0.title = "ブラウザ" }
        #expect(!h.model.undoManager.canUndo)
        // ほかの欄に移っただけなら、まだ積まない
        h.model.textEditingDidEnd()
        #expect(!h.model.undoManager.canUndo)
        h.model.isEditingText = { false }
        h.model.textEditingDidEnd()
        #expect(h.model.undoManager.undoActionName == L10n.ui("マスの変更"))
        h.model.undoManager.undo()
        #expect(cell(h, 0) == safari)
    }

    /// 打ち終わる前に別のマスを選んでも、打った分は取り消しに残る
    @Test func choosingAnotherCellRecordsPendingTyping() throws {
        let h = try harness()
        let safari = try #require(cell(h, 0))
        h.model.isEditingText = { true }
        h.model.updateCell(id: safari.id) { $0.title = "ブラウザ" }
        h.model.isEditingText = { false }
        h.model.selectCell(4)
        h.model.undoManager.undo()
        #expect(cell(h, 0) == safari)
    }

    /// 欄の打ち込みの取り消しは欄だけのものにして、離れたら捨てる（マスを元に戻した後に合わない取り消しが残らない）
    @Test func multiLineFieldsKeepTheirOwnTypingUndo() {
        let view = SettingsCodeTextView(text: "", accessibilityLabel: "スクリプト", edit: { _ in }, endEditing: {}, focusChanged: { _ in })
        let coordinator = view.makeCoordinator()
        let textView = NSTextView()
        #expect(coordinator.undoManager(for: textView) === coordinator.typingUndoManager)
        coordinator.typingUndoManager.registerUndo(withTarget: textView) { _ in }
        #expect(coordinator.typingUndoManager.canUndo)
        coordinator.textDidEndEditing(Notification(name: NSText.didEndEditingNotification, object: textView))
        #expect(!coordinator.typingUndoManager.canUndo)
    }
}

@Suite @MainActor struct SettingsProfileCopyTests {
    @Test func duplicatingAProfileForAnotherApp() throws {
        let h = try harness()
        let xcode = try #require(h.xcodeProfile)
        h.model.beginDuplicatingProfile(xcode.id)
        #expect(h.model.isAddingProfile)
        #expect(h.model.duplicatingProfileID == xcode.id)
        h.model.addProfile(for: SettingsFixtures.figma)
        #expect(!h.model.isAddingProfile)
        #expect(h.model.duplicatingProfileID == nil)
        let copy = h.model.selectedProfile
        #expect(copy.app == SettingsFixtures.figma)
        #expect(copy.pages.map { $0.cells.map { $0?.title } } == xcode.pages.map { $0.cells.map { $0?.title } })
        #expect(h.model.undoManager.undoActionName == L10n.ui("プロファイルの複製"))
        h.model.undoManager.undo()
        #expect(!h.model.appProfiles.contains { $0.app == SettingsFixtures.figma })
        // シートを閉じたら複製の元は忘れ、普通の追加に戻る
        h.model.beginDuplicatingProfile(xcode.id)
        h.model.isAddingProfile = false
        #expect(h.model.duplicatingProfileID == nil)
    }

    @Test func resettingToThePreset() throws {
        let h = try harness()
        let xcode = try #require(h.xcodeProfile)
        h.model.selectProfile(xcode.id)
        h.model.clearCell(at: 0)
        h.model.renamePage(0, to: "ビルド")
        let edited = try #require(h.xcodeProfile)
        h.model.requestResetProfile(xcode.id)
        #expect(h.model.confirmation == .resetProfile(id: xcode.id, name: xcode.name))
        h.model.confirm(.resetProfile(id: xcode.id, name: xcode.name))
        let preset = try #require(PresetLibrary.preset(forBundleID: SettingsFixtures.xcode.bundleID))
        #expect(h.xcodeProfile?.pages.map { $0.cells.map { $0?.title } } == preset.pages.map { $0.cells.map { $0?.title } })
        #expect(h.xcodeProfile?.pages.first?.name == nil)
        #expect(h.store.backups().map(\.reason) == [.beforeResettingProfile])
        #expect(h.model.undoManager.undoActionName == L10n.ui("プリセットに戻す"))
        h.model.undoManager.undo()
        #expect(h.xcodeProfile == edited)
        h.model.undoManager.redo()
        #expect(h.xcodeProfile?.pages.first?.name == nil)
    }

    private func hasAction(_ profile: Profile?, _ matches: (Action) -> Bool) -> Bool {
        profile?.pages.contains { $0.cells.contains { $0.map { matches($0.action) } ?? false } } ?? false
    }

    /// 「プリセットに戻す」も、この Mac で動かないアクション（AI・Claude Code）は入れない（初回の設定やプロファイルの追加と同じ）
    @Test func resettingToThePresetUsesThisMacsCapabilities() throws {
        let h = try harness()
        let environment = try #require(h.services.presetEnvironment as? FixedPresetEnvironment)
        environment.capabilities = .none
        let xcode = try #require(h.xcodeProfile)
        h.model.resetProfileToPreset(xcode.id)
        let expected = try #require(PresetLibrary.preset(forBundleID: SettingsFixtures.xcode.bundleID, capabilities: .none))
        #expect(h.xcodeProfile?.pages.map { $0.cells.map { $0?.action } } == expected.pages.map { $0.cells.map { $0?.action } })
        #expect(!hasAction(h.xcodeProfile) { if case .ai = $0 { true } else { false } })
        // Safari: AI の使えない Mac（macOS 14/15）では AI のマスを入れない
        let safari = try #require(h.safariProfile)
        h.model.resetProfileToPreset(safari.id)
        #expect(!hasAction(h.safariProfile) { if case .ai = $0 { true } else { false } })
    }

    /// 確かめるシートを出している間に claude を調べ終えたら、Claude Code のマスも入れる
    @Test func resettingToThePresetWaitsForClaudeCodeToBeChecked() async throws {
        let environment = SettingsFakePresetEnvironment(capabilities: .none, resolved: .all)
        let h = try SettingsHarness(presetEnvironment: environment)
        h.model.undoManager.groupsByEvent = false
        let xcode = try #require(h.xcodeProfile)
        h.model.requestResetProfile(xcode.id)
        await h.model.presetCapabilitiesTask?.value
        h.model.confirm(.resetProfile(id: xcode.id, name: xcode.name))
        let expected = try #require(PresetLibrary.preset(forBundleID: SettingsFixtures.xcode.bundleID, capabilities: .all))
        #expect(h.xcodeProfile?.pages.map { $0.cells.map { $0?.action } } == expected.pages.map { $0.cells.map { $0?.action } })
        // 戻した後は忘れ、次に戻すときに調べ直す
        #expect(h.model.resolvedPresetCapabilities == nil)
        #expect(h.model.preset(forProfile: xcode.id)?.pages.map { $0.cells.map { $0?.action } }
            == PresetLibrary.preset(forBundleID: SettingsFixtures.xcode.bundleID, capabilities: .none)?.pages.map { $0.cells.map { $0?.action } })
    }

    /// プリセットの無いアプリとグローバルには出さない
    @Test func resetIsOfferedOnlyWithAPreset() throws {
        let h = try harness()
        var plainID: UUID?
        h.controller.update { plainID = $0.addAppProfile(for: AppReference(bundleID: "com.example.plain", name: "Plain"), preset: nil) }
        let plain = try #require(plainID)
        #expect(h.model.preset(forProfile: plain) == nil)
        h.model.requestResetProfile(plain)
        h.model.requestResetProfile(h.controller.configuration.globalProfile.id)
        #expect(h.model.confirmation == nil)
    }

    @Test func copyAndPasteACell() throws {
        let h = try harness()
        let board = pasteboard()
        let safari = try #require(cell(h, 0))
        #expect(!h.model.canPasteCell(from: board))
        #expect(h.model.copyCell(at: 0, to: board))
        #expect(!h.model.copyCell(at: 1, to: board))
        #expect(h.model.canPasteCell(from: board))
        // 文字としては書かない
        #expect(board.string(forType: .string) == nil)

        h.model.selectCell(1)
        h.model.pasteCell(at: 1, from: board)
        let pasted = try #require(cell(h, 1))
        #expect(pasted.id != safari.id)
        #expect(pasted.title == safari.title)
        #expect(pasted.action == safari.action)
        #expect(h.model.undoNotice == nil)
        #expect(h.model.undoManager.undoActionName == L10n.ui("マスの貼り付け"))

        // 中身のあるマスに貼ると置き換え、グリッドの下から戻せる
        let terminal = try #require(cell(h, 2))
        h.model.selectCell(2)
        h.model.pasteCell(at: 2, from: board)
        #expect(cell(h, 2)?.title == safari.title)
        #expect(h.model.undoNotice?.text == L10n.ui("マスを貼り付けたもので置き換えました"))
        h.model.undoFromNotice()
        #expect(cell(h, 2) == terminal)

        // ほかのプロファイルにも貼れる
        let xcode = try #require(h.xcodeProfile)
        h.model.selectProfile(xcode.id)
        h.model.pasteCell(at: 0, from: board)
        #expect(cell(h, 0)?.title == safari.title)
    }

    @Test func copyingAButtonToAnotherProfile() throws {
        let h = try harness()
        let safari = try #require(cell(h, 0))
        let target = try #require(h.safariProfile)
        #expect(h.model.copyTargets.map(\.id) == h.controller.configuration.profiles.dropFirst().map(\.id))
        h.model.copyCell(at: 0, toProfile: target.id)
        let copied = try #require(h.safariProfile?.pages[0].cells[0])
        #expect(copied.title == safari.title)
        #expect(copied.id != safari.id)
        #expect(h.model.undoNotice?.text == L10n.ui("「\(target.name)」の\(SettingsText.pageTitle(index: 0, name: nil))にコピーしました"))
        h.model.undoFromNotice()
        #expect(h.safariProfile?.pages[0].cells[0] == nil)
        // 元に戻すと、戻した先（Safari）を見せる
        #expect(h.model.selectedProfile.id == target.id)
        h.model.selectProfile(nil)

        // 空きが無ければ知らせる
        let xcode = try #require(h.xcodeProfile)
        #expect(xcode.pages.allSatisfy { $0.cells.allSatisfy { $0 != nil } })
        h.model.copyCell(at: 0, toProfile: xcode.id)
        #expect(h.model.gridMessage == L10n.ui("「\(xcode.name)」に空いているマスがありません。マスを空けるか、ページを追加してください。"))
    }
}

@Suite @MainActor struct SettingsKeyboardTests {
    @Test func swappingWithANeighbor() throws {
        let h = try harness()
        let safari = try #require(cell(h, 0))
        #expect(!h.model.canSwapCell(at: 0, .up))
        #expect(!h.model.canSwapCell(at: 0, .left))
        #expect(h.model.canSwapCell(at: 0, .right))
        #expect(h.model.canSwapCell(at: 4, .up))
        h.model.swapCell(at: 0, .left)
        #expect(cell(h, 0) == safari)
        h.model.swapCell(at: 0, .down)
        #expect(cell(h, 3) == safari)
        #expect(cell(h, 0) == nil)
        #expect(h.model.selectedIndex == 3)
        #expect(h.model.undoManager.undoActionName == L10n.ui("マスの移動"))
        #expect(SettingsText.swapName(.up) == L10n.ui("上と入れ替え"))
    }

    @Test func optionCommandArrowIsTheSwapShortcut() {
        #expect(SettingsGridView.isOptionCommand([.option, .command]))
        #expect(SettingsGridView.isOptionCommand([.option, .command, .numericPad]))
        #expect(!SettingsGridView.isOptionCommand([.command]))
        #expect(!SettingsGridView.isOptionCommand([.option, .command, .shift]))
        #expect(SettingsGridView.direction(.leftArrow) == .left)
        #expect(SettingsGridView.direction("d") == nil)
    }

    @Test func returnMovesToTheNameField() throws {
        let h = try harness()
        h.model.showMenus(true)
        #expect(h.model.focusNameField())
        #expect(h.model.nameFieldFocusRequest == 1)
        #expect(h.model.rightPanel == .inspector)
        // 空きマスには表示名の欄が無い
        h.model.selectCell(1)
        #expect(!h.model.focusNameField())
        #expect(h.model.nameFieldFocusRequest == 1)
    }

    @Test func commandNumberPicksAPage() throws {
        let h = try harness()
        h.model.addPage()
        h.model.selectPageByShortcut(1)
        #expect(h.model.pageIndex == 0)
        h.model.selectPageByShortcut(2)
        #expect(h.model.pageIndex == 1)
        h.model.selectPageByShortcut(3)
        #expect(h.model.pageIndex == 1)
    }
}

@Suite @MainActor struct SettingsFilterTests {
    @Test func theFilterAppearsWithManyProfilesOrCommandF() throws {
        let h = try harness()
        #expect(!h.model.showsProfileFilter)
        h.model.focusFilter()
        #expect(h.model.showsProfileFilter)
        #expect(h.model.filterFocusRequest == 1)
        h.model.clearFilter()
        #expect(!h.model.showsProfileFilter)

        h.controller.update { configuration in
            for index in 0..<SettingsModel.filterThreshold {
                configuration.addAppProfile(for: AppReference(bundleID: "com.example.app\(index)", name: "App \(index)"), preset: nil)
            }
        }
        #expect(h.model.showsProfileFilter)
    }

    @Test func searchingNamesAndKeysAcrossProfiles() throws {
        let h = try harness()
        let xcode = try #require(h.xcodeProfile)
        let build = try #require(xcode.pages[0].cells[0])
        h.controller.update { $0.renamePage(at: 0, profileID: xcode.id, to: "ビルド") }

        h.model.profileQuery = "safa"
        var results = h.model.searchResults
        #expect(results.profiles.map(\.id) == [h.safariProfile?.id])
        // グローバルの Safari を開くボタンも見つかる
        #expect(results.cells.map(\.profileID) == [h.controller.configuration.globalProfile.id])

        h.model.profileQuery = "⌘B"
        results = h.model.searchResults
        let match = try #require(results.cells.first)
        #expect(results.cells.count == 1)
        #expect(match.title == build.title)
        #expect(match.path == "Xcode › ビルド › \(build.title)")
        #expect(match.detailIsKeys)
        h.model.reveal(match)
        #expect(h.model.selectedProfile.id == xcode.id)
        #expect(h.model.selectedCell == build)

        // 打った表記でも探せる
        #expect(SettingsProfileSearch.keyQuery("⌘b") == KeySequence.key("b", .command).displayString)
        #expect(SettingsProfileSearch.keyQuery("b") == nil)
        h.model.profileQuery = "存在しないボタン"
        #expect(h.model.searchResults.isEmpty)
        h.model.profileQuery = "  "
        #expect(h.model.searchResults == SettingsSearchResults())
    }

    /// アプリ起動のマスのグリッドの説明は種類の名前だけになったが、開くアプリの名前でも見つかる
    @Test func searchingFindsLaunchAppCellsByAppName() throws {
        var configuration = NonetConfiguration(profiles: []).validated()
        let global = configuration.globalProfile.id
        var cell = SettingsFixtures.launch(SettingsFixtures.safari)
        cell.title = "ウェブ"
        configuration.setCell(cell, at: CellAddress(page: 0, index: 0), profileID: global)
        let results = SettingsProfileSearch.results(for: "safari", in: configuration)
        #expect(results.cells.map { $0.title } == ["ウェブ"])
        #expect(results.cells.first?.detail == L10n.ui("アプリ起動"))
    }
}

@Suite @MainActor struct SettingsPageNameTests {
    @Test func renamingAPageCanBeUndone() throws {
        let h = try harness()
        h.model.addPage()
        h.model.beginRenamingPage(0)
        #expect(h.model.pageIndex == 0)
        #expect(h.model.renamingPage == 0)
        h.model.renamePage(0, to: "  デバッグ ")
        #expect(h.model.renamingPage == nil)
        #expect(h.model.selectedProfile.pages[0].name == "デバッグ")
        #expect(try h.saved()?.globalProfile.pages[0].name == "デバッグ")
        #expect(h.model.undoManager.undoActionName == L10n.ui("ページの名前の変更"))
        h.model.undoManager.undo()
        #expect(h.model.selectedProfile.pages[0].name == nil)
        // 同じ名前なら何も積まない（いちばん上はページの追加のまま）
        h.model.renamePage(0, to: "")
        #expect(h.model.undoManager.undoActionName == L10n.ui("ページを追加"))
    }

    @Test func pageTitlesUseTheName() {
        #expect(SettingsText.pageTitle(index: 1, name: nil) == L10n.ui("ページ \(2)"))
        #expect(SettingsText.pageTitle(index: 1, name: " Git ") == "Git")
        #expect(SettingsText.pageAccessibilityLabel(index: 1, name: "Git") == L10n.ui("ページ \(2)、\("Git")"))
    }
}

@Suite @MainActor struct SettingsBackupTests {
    @Test func importingLeavesABackup() throws {
        let h = try harness()
        let figma = Profile(kind: .app(SettingsFixtures.figma), pages: [.empty])
        let file = h.temporaryFile("figma.nonetprofile")
        h.model.exportProfiles([figma], to: file)
        h.model.importProfiles(from: file)
        #expect(h.store.backups().map(\.reason) == [.beforeImport])
    }

    @Test func restoringAnEarlierVersion() throws {
        let h = try harness()
        let xcode = try #require(h.xcodeProfile)
        h.model.deleteProfile(xcode.id)
        h.model.clearCell(at: 0)
        h.model.showBackups()
        #expect(h.model.isShowingBackups)
        let entry = try #require(h.model.backupEntries.first)
        #expect(entry.backup.reason == .beforeDeletingProfile)
        #expect(entry.appProfileCount == 2)
        #expect(SettingsText.backupSummary(entry) == L10n.uiCounted("アプリのプロファイル \(2)個"))

        h.model.restoreBackup(entry.backup)
        #expect(!h.model.isShowingBackups)
        #expect(h.xcodeProfile == xcode)
        #expect(h.controller.configuration.globalProfile.pages[0].cells[0] != nil)
        #expect(!h.model.undoManager.canUndo)
        #expect(h.model.selectedProfile.isGlobal)
        #expect(h.model.fileMessage?.isError == false)
        // 戻す前の設定も控えに残る
        #expect(h.store.backups().first?.reason == .beforeRestoring)
        #expect(try h.store.loadBackup(h.store.backups()[0]).profile(id: xcode.id) == nil)
    }

    @Test func anUnreadableBackupIsShownButNotRestored() throws {
        let h = try harness()
        let backup = try #require(h.store.makeBackup(of: h.controller.configuration, reason: .beforeImport))
        try Data("{".utf8).write(to: backup.url)
        h.model.showBackups()
        #expect(h.model.backupEntries.first?.appProfileCount == nil)
        let before = h.controller.configuration
        h.model.restoreBackup(backup)
        #expect(h.controller.configuration == before)
        #expect(h.model.fileMessage?.isError == true)
    }

    @Test func withoutAStoreThereIsNothingToRestore() throws {
        let h = try harness()
        h.model.backupStore = nil
        // 決めていなければ、読み込んだ設定の場所を使う
        #expect(h.model.backupStore?.directory == ConfigurationStore.lastLoadedDirectory)
    }
}

@Suite @MainActor struct SettingsContrastTests {
    @Test func theGridHonoursIncreaseContrast() throws {
        let shades = SettingsPalette.cellBorderShades
        let light = try #require(NSAppearance(named: .aqua))
        let dark = try #require(NSAppearance(named: .darkAqua))
        let lightHigh = try #require(NSAppearance(named: .accessibilityHighContrastAqua))
        let darkHigh = try #require(NSAppearance(named: .accessibilityHighContrastDarkAqua))
        #expect(SettingsPalette.white(shades, for: light, increaseContrast: false) == 0.55)
        #expect(SettingsPalette.white(shades, for: dark, increaseContrast: false) == shades.dark)
        // 「コントラストを上げる」がオン（外観の名前がハイコントラストでなくても）
        #expect(SettingsPalette.white(shades, for: light, increaseContrast: true) == shades.lightHighContrast)
        #expect(SettingsPalette.white(shades, for: dark, increaseContrast: true) == shades.darkHighContrast)
        // ハイコントラストの外観なら、設定を読まなくても濃くする
        #expect(SettingsPalette.white(shades, for: lightHigh, increaseContrast: false) != shades.dark)
        #expect(SettingsPalette.white(shades, for: darkHigh, increaseContrast: true) == shades.darkHighContrast)
        // ハイコントラストでは、枠と背景の差がふつうより大きい
        for appearance in [light, dark] {
            let background = SettingsPalette.cellBackgroundShades
            let normalGap = abs(SettingsPalette.white(shades, for: appearance, increaseContrast: false) - SettingsPalette.white(background, for: appearance, increaseContrast: false))
            let highGap = abs(SettingsPalette.white(shades, for: appearance, increaseContrast: true) - SettingsPalette.white(background, for: appearance, increaseContrast: true))
            #expect(highGap > normalGap)
        }
    }
}
