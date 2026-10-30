// 担当: ui-shell
// 初回の案内を終えたときに、メニューバーのどこに Nonet がいるかを見せる
import AppKit
import SwiftUI

/// メニューバーのアイコンが見えているかの決め方（AppKit から集めた値で決める。テストする）
enum MenuBarItemVisibility {
    struct Screen: Equatable {
        var frame: CGRect
        /// カメラの切り欠き（ノッチ）がある
        var hasNotch: Bool
        /// ノッチの右のメニューバー（NSScreen.auxiliaryTopRightArea）
        var auxiliaryTopRightArea: CGRect?
    }

    /// itemFrame はアイコンのウィンドウの位置（画面の座標）。どの画面にも入っていなければ見えない。
    /// ノッチのある画面では、ノッチの右のメニューバーに入っていなければノッチの陰に隠れている
    static func isVisible(itemFrame: CGRect, screens: [Screen]) -> Bool {
        let center = CGPoint(x: itemFrame.midX, y: itemFrame.midY)
        guard !itemFrame.isEmpty, let screen = screens.first(where: { $0.frame.contains(center) }) else { return false }
        guard screen.hasNotch, let area = screen.auxiliaryTopRightArea, !area.isEmpty else { return true }
        // 画面の中の座標で返る場合にも合わせる（主画面以外では原点がずれる）
        let global = area.intersects(screen.frame) ? area : area.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
        return global.insetBy(dx: -1, dy: -1).contains(center)
    }
}

/// アイコンの下に短く出す吹き出し。アイコンも数回光らせる。
/// 前面にならず、クリックも受けず、ウィンドウを閉じて Nonet を隠しても（ShellActivation）残る
@MainActor
final class MenuBarCallout {
    static let duration: TimeInterval = 4
    /// アイコンを光らせる回数
    static let pulseCount = 3
    static let pulseInterval: TimeInterval = 0.25

    private var panel: MenuBarCalloutPanel?
    private var hideWork: DispatchWorkItem?
    private var pulseTimer: Timer?
    private var remainingPulseSteps = 0

    func show(text: String, below button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { return }
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let panel = self.panel ?? MenuBarCalloutPanel()
        self.panel = panel
        let hosting = NSHostingView(rootView: MenuBarCalloutView(text: text))
        let size = hosting.fittingSize
        var origin = CGPoint(x: buttonFrame.midX - size.width / 2, y: buttonFrame.minY - 2 - size.height)
        if let visible = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        }
        panel.contentView = hosting
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
        pulse(button)
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.hide() }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.duration, execute: work)
    }

    func hide() {
        hideWork?.cancel()
        hideWork = nil
        pulseTimer?.invalidate()
        pulseTimer = nil
        panel?.orderOut(nil)
    }

    /// 押したときと同じ見た目で、数回光らせる
    private func pulse(_ button: NSStatusBarButton) {
        pulseTimer?.invalidate()
        remainingPulseSteps = Self.pulseCount * 2
        let timer = Timer(timeInterval: Self.pulseInterval, repeats: true) { [weak self, weak button] _ in
            MainActor.assumeIsolated { self?.pulseStep(button) }
        }
        pulseTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        pulseStep(button)
    }

    private func pulseStep(_ button: NSStatusBarButton?) {
        guard let button, remainingPulseSteps > 0 else {
            button?.highlight(false)
            pulseTimer?.invalidate()
            pulseTimer = nil
            return
        }
        remainingPulseSteps -= 1
        button.highlight(remainingPulseSteps % 2 == 1)
    }
}

/// キーにならず、クリックを受けないパネル
private final class MenuBarCalloutPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        // 案内のウィンドウを閉じた後に Nonet を隠しても（前面を前のアプリに返す）、吹き出しは残す
        canHide = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// 上向きの矢印の付いた吹き出し
private struct MenuBarCalloutView: View {
    let text: String

    var body: some View {
        VStack(spacing: -1) {
            MenuBarCalloutArrow()
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay(MenuBarCalloutArrow().stroke(Color.secondary.opacity(0.35), lineWidth: 1))
                .frame(width: 16, height: 8)
                .zIndex(1)
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .fixedSize()
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color(nsColor: .windowBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.35))
                )
        }
        .padding(4)
        .accessibilityHidden(true)
    }
}

/// 下の辺を開いた三角（吹き出しの本体に重ねる）
private struct MenuBarCalloutArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}
