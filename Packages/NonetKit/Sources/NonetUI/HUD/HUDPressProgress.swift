// 担当: ui-shell
// 強く押し込んでから9マスが開くまでの短い間、ポインタの周りに満ちていく輪を出す（途中で離すとふつうのクリックになることを見せる）。
// クリックを通す小さなパネルで、フォーカスも奪わない
import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class HUDPressProgressStore {
    var progress: Double = 0
}

@MainActor
final class HUDPressProgressController {
    static let size: CGFloat = 46
    private let store = HUDPressProgressStore()
    private var panel: NSPanel?
    /// パネルの段。ふだんはメニューバーと同じ段。デモ（収録の背景を screenSaver − 1 に敷く）は背景より上にする（HUDWindowController.pressProgressLevel）
    var level: NSWindow.Level = .statusBar {
        didSet { panel?.level = level }
    }
    /// システム設定の「視差効果を減らす」では、満ちていく動きを付けずに輪だけ出す
    var prefersReducedMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    var isVisible: Bool { panel?.isVisible == true }

    /// point（AppKit のグローバル座標）を中心に、duration で満ちる輪を出す
    func show(at point: CGPoint, duration: TimeInterval) {
        let panel = self.panel ?? makePanel()
        let size = Self.size
        panel.setFrame(CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size), display: false)
        store.progress = 0
        panel.orderFrontRegardless()
        if prefersReducedMotion() {
            store.progress = 1
        } else {
            withAnimation(.linear(duration: max(duration, 0.01))) {
                store.progress = 1
            }
        }
    }

    func hide() {
        panel?.orderOut(nil)
        store.progress = 0
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.size, height: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = level
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: HUDPressProgressView(store: store))
        self.panel = panel
        return panel
    }
}

struct HUDPressProgressView: View {
    let store: HUDPressProgressStore

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.black.opacity(0.25), lineWidth: 5)
            Circle()
                .trim(from: 0, to: store.progress)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: .black.opacity(0.35), radius: 2)
        }
        .padding(6)
        .accessibilityHidden(true)
    }
}
