// 担当: ui-shell
import AppKit
import NonetCore
@testable import NonetUI
import Testing

/// 設定や案内のウィンドウを閉じた後、Nonet を前面のまま残さない（キー入力のマスが Nonet に打たないように）
@Suite("前面を返す")
@MainActor
struct ShellActivationTests {
    typealias State = ShellActivation.WindowState

    static let visibleWindow = State(isVisible: true, canBecomeKey: true)
    static let closedWindow = State(isVisible: false, canBecomeKey: true)
    /// HUD・トーストのパネルとメニューバーのアイコン
    static let visiblePanel = State(isVisible: true, canBecomeKey: false)

    @Test("Nonet が前面で、ほかに見えているウィンドウが無ければ返す")
    func handsBackWhenNoWindowIsLeft() {
        #expect(ShellActivation.shouldHandBack(isActive: true, windows: []))
        #expect(ShellActivation.shouldHandBack(isActive: true, windows: [Self.closedWindow]))
        // HUD のパネルやメニューバーのアイコンは、キーにならないので数えない
        #expect(ShellActivation.shouldHandBack(isActive: true, windows: [Self.closedWindow, Self.visiblePanel]))
    }

    @Test("ほかの Nonet のウィンドウ（設定・案内・AI の結果）が見えていれば返さない")
    func keepsActivationWhileAnotherWindowIsOpen() {
        #expect(!ShellActivation.shouldHandBack(isActive: true, windows: [Self.closedWindow, Self.visibleWindow]))
        #expect(!ShellActivation.shouldHandBack(isActive: true, windows: [Self.visiblePanel, Self.visibleWindow]))
    }

    @Test("Nonet が前面でなければ何もしない（ほかのアプリを使っている）")
    func doesNothingWhenNotActive() {
        #expect(!ShellActivation.shouldHandBack(isActive: false, windows: []))
        #expect(!ShellActivation.shouldHandBack(isActive: false, windows: [Self.visibleWindow]))
    }

    @Test("ウィンドウの見え方: HUD のパネルはキーにならない。AI の結果のパネルと、出していないウィンドウはキーになれる")
    func windowStates() {
        _ = NSApplication.shared
        let hud = HUDOverlayPanel()
        #expect(ShellActivation.state(of: hud) == State(isVisible: false, canBecomeKey: false))
        let result = HUDResultPanel()
        defer { result.close() }
        #expect(ShellActivation.state(of: result).canBecomeKey)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled, .closable], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        #expect(ShellActivation.state(of: window) == Self.closedWindow)
    }

    @Test("テストのプロセスは前面にならないので、閉じた後に確かめても何もしない")
    func checkingInTestsDoesNothing() {
        #expect(!NSApplication.shared.isActive)
        ShellActivation.handBackIfNoWindowIsOpen()
        #expect(!NSApplication.shared.isHidden)
    }

    @Test("案内のウィンドウを閉じたら、前面を返すか確かめる")
    func closingTheGuideHandsBackActivation() {
        let harness = ShellControllerHarness(installed: [], accessibilityGranted: true)
        harness.controller.start()
        let window = OnboardingWindowController(controller: harness.controller, services: harness.services, history: OnboardingGuideHistory()) {}
        var handBacks = 0
        window.handBackActivation = { handBacks += 1 }
        window.windowDidClose()
        #expect(handBacks == 1)
    }
}
