// 担当: ui-shell
import AppKit
import QuartzCore
import SwiftUI

/// 前面アプリからフォーカスを奪わずに最前面へ浮かぶ、マウスを素通しするパネル（HUD とトースト）
final class HUDOverlayPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        // フルスクリーンのアプリやほかのアプリの浮いたパネルの上にも出す
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        isOpaque = false
        backgroundColor = .clear
        // 影は SwiftUI で描く。ウィンドウの影は中身が変わると遅れて付き直してちらつく
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// 大きさを SwiftUI に決めさせない（update のたびにウィンドウの大きさが動かないように）
    static func hostingView<Content: View>(_ rootView: Content) -> NSHostingView<Content> {
        let view = NSHostingView(rootView: rootView)
        view.sizingOptions = []
        return view
    }
}

/// パネルをすぐに出し、隠すときだけ短くフェードアウトする。
/// フェードの途中で出し直したらフェードを捨てる（animator を使わず、自分のタイマーで確実に止める）
@MainActor
final class HUDPanelFader {
    static let fadeOutDuration: TimeInterval = 0.12

    let panel: NSPanel
    /// show の後、hide されるまで true（フェード中は false）
    private(set) var isShowing = false
    private var fadeTimer: Timer?

    init(panel: NSPanel) {
        self.panel = panel
    }

    /// 不透明のまま前に出す。最初のフレームを遅らせない
    func show() {
        cancelFade()
        isShowing = true
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    /// onHidden は隠し終えたとき（フェードの途中で show したら呼ばない）
    func hide(onHidden: @escaping @MainActor () -> Void = {}) {
        guard isShowing else { return }
        isShowing = false
        cancelFade()
        guard panel.isVisible else {
            onHidden()
            return
        }
        let start = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, self.fadeTimer === timer else {
                    timer.invalidate()
                    return
                }
                let progress = min(1, (CACurrentMediaTime() - start) / Self.fadeOutDuration)
                self.panel.alphaValue = 1 - progress
                if progress >= 1 {
                    self.cancelFade()
                    self.panel.orderOut(nil)
                    onHidden()
                }
            }
        }
        fadeTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    /// フェードせずにすぐ隠す
    func hideImmediately() {
        isShowing = false
        cancelFade()
        panel.orderOut(nil)
    }

    private func cancelFade() {
        fadeTimer?.invalidate()
        fadeTimer = nil
    }
}
