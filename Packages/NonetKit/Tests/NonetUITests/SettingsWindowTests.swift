// 担当: ui-settings
// ウィンドウの組み立て（画面には出さない）
import AppKit
import NonetCore
@testable import NonetUI
import Testing

@Suite @MainActor struct SettingsWindowTests {
    private func makeController(_ h: SettingsHarness) -> SettingsWindowController {
        let controller = SettingsWindowController(
            controller: h.controller,
            license: h.license,
            services: h.services,
            links: AppLinks(),
            onCheckForUpdates: nil
        )
        controller.autosavesFrame = false
        return controller
    }

    @Test func buildsOneReusableWindowWithTabs() throws {
        _ = NSApplication.shared
        let h = try SettingsHarness()
        let controller = makeController(h)
        let window = controller.loadWindow()
        #expect(controller.loadWindow() === window)
        #expect(!window.isReleasedWhenClosed)
        #expect(window.styleMask.contains([.titled, .closable, .miniaturizable, .resizable]))
        #expect(window.contentMinSize.width >= 860)
        #expect(window.contentMinSize.height >= 560)
        #expect(!window.isVisible)
        let toolbar = try #require(window.toolbar)
        #expect(toolbar.items.map(\.label) == [L10n.ui("プロファイル"), L10n.ui("一般"), L10n.ui("ライセンス"), L10n.ui("情報")])
        #expect(window.delegate != nil)
        #expect(controller.model.files != nil)
    }

    /// 前に開いていた操作スペース（フルスクリーンのアプリの外）へ移らず、今の操作スペースに出す
    @Test func theWindowOpensOnTheCurrentSpace() throws {
        _ = NSApplication.shared
        let h = try SettingsHarness()
        let window = makeController(h).loadWindow()
        #expect(window.collectionBehavior.contains(.moveToActiveSpace))
        #expect(window.collectionBehavior.contains(.fullScreenAuxiliary))
    }

    /// 編集 › 取り消す（⌘Z）はウィンドウの undoManager に届く。マスの変更を元に戻せるよう、設定の undoManager を返す
    @Test func undoGoesThroughTheSettingsUndoManager() throws {
        _ = NSApplication.shared
        let h = try SettingsHarness()
        let controller = makeController(h)
        let window = controller.loadWindow()
        #expect(window.undoManager === controller.model.undoManager)
        // 中身（SwiftUI）の欄も、応答の連なりで同じものに届く
        #expect(window.contentView?.undoManager === controller.model.undoManager)
    }

    /// 編集メニューの「取り消す」（宛先なしの undo:）は、ウィンドウからマスの変更の取り消しに届く
    @Test func theWindowsUndoActionUndoesCellChanges() throws {
        _ = NSApplication.shared
        let h = try SettingsHarness()
        let controller = makeController(h)
        let window = controller.loadWindow()
        controller.model.undoManager.groupsByEvent = false
        let safari = try #require(controller.model.selectedCell)
        controller.model.clearCell(at: 0)
        #expect(window.tryToPerform(Selector(("undo:")), with: nil))
        #expect(controller.model.selectedCell == safari)
        #expect(window.tryToPerform(Selector(("redo:")), with: nil))
        #expect(controller.model.selectedCell == nil)
    }

    /// ほかのタブで元に戻すとプロファイルのタブに移る。ウィンドウの題名とツールバーの選択も合わせる
    @Test func undoingFromAnotherTabSelectsTheProfilesTab() throws {
        _ = NSApplication.shared
        let h = try SettingsHarness()
        let controller = makeController(h)
        let window = controller.loadWindow()
        controller.model.undoManager.groupsByEvent = false
        controller.model.clearCell(at: 0)
        controller.select(.general)
        #expect(window.title == L10n.ui("一般"))
        controller.model.undoManager.undo()
        #expect(controller.model.tab == .profiles)
        #expect(window.title == L10n.ui("プロファイル"))
        #expect(window.toolbar?.selectedItemIdentifier == SettingsWindowCoordinator.identifier(for: .profiles))
    }

    @Test func selectingATabUpdatesTitleAndToolbar() throws {
        _ = NSApplication.shared
        let h = try SettingsHarness()
        let controller = makeController(h)
        let window = controller.loadWindow()
        controller.select(.license)
        #expect(controller.model.tab == .license)
        #expect(window.title == L10n.ui("ライセンス"))
        #expect(window.toolbar?.selectedItemIdentifier == SettingsWindowCoordinator.identifier(for: .license))
        controller.select(.general)
        #expect(window.title == L10n.ui("一般"))
    }

    @Test func closingTheWindowStopsKeyRecording() throws {
        _ = NSApplication.shared
        let h = try SettingsHarness()
        let controller = makeController(h)
        let window = controller.loadWindow()
        controller.model.createCell(kind: .keystroke, at: 1)
        let id = try #require(controller.model.selectedCell?.id)
        controller.model.beginRecording(cellID: id)
        #expect(h.controller.isRecordingKeys)
        window.delegate?.windowWillClose?(Notification(name: NSWindow.willCloseNotification, object: window))
        #expect(!h.controller.isRecordingKeys)
    }
}
