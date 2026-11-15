// 担当: ui-shell
// 「画面に置く」のプレビュー。HUD でそのマスを光らせている間、置く枠を薄い青で画面に見せる（離すと、ここに置きます）
import AppKit
import NonetCore
import SwiftUI

@MainActor
final class HUDPlacementPreviewController {
    private lazy var panel: HUDOverlayPanel = {
        let panel = HUDOverlayPanel()
        // HUD より下に出す（枠の上に HUD が重なっても、HUD が読める）
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 1)
        panel.contentView = HUDOverlayPanel.hostingView(HUDPlacementPreviewView())
        return panel
    }()
    private(set) var frame: CGRect?

    /// frame は AppKit のグローバル座標。もう同じ枠を出していれば何もしない
    func show(_ frame: CGRect, animated: Bool) {
        guard self.frame != frame else { return }
        let wasShowing = self.frame != nil
        self.frame = frame
        panel.setFrame(frame, display: true)
        if !wasShowing {
            panel.alphaValue = animated ? 0 : 1
            panel.orderFrontRegardless()
            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.12
                    panel.animator().alphaValue = 1
                }
            }
        }
    }

    func hide() {
        guard frame != nil else { return }
        frame = nil
        panel.orderOut(nil)
        panel.alphaValue = 1
    }
}

/// 置く枠: 薄い青の面と線、左上に「離すと、ここに置きます」
struct HUDPlacementPreviewView: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.accentColor.opacity(0.14))
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.8), lineWidth: 2)
            // 文字は選んだ色の上で読める色（強調色が黄色やグラファイトでも白に決めない）
            Text("離すと、ここに置きます", bundle: .module)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(nsColor: .alternateSelectedControlTextColor))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.accentColor))
                .padding(16)
        }
        .padding(4)
        .accessibilityHidden(true)
    }
}
