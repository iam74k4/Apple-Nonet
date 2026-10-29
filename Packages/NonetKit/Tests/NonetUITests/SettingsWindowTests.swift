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
