import AppKit
import SwiftUI

/// 前面アプリからフォーカスを奪わずに、最前面へ浮かぶパネル
final class OverlayPanel: NSPanel {
    init(size: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class HUDController {
    private static let hudSize = NSSize(width: 504, height: 315)
    private static let toastSize = NSSize(width: 240, height: 48)

    private let panel = OverlayPanel(size: hudSize)
    private let toastPanel = OverlayPanel(size: toastSize)
    private var toastHide: DispatchWorkItem?

    init(controller: SpikeController) {
        panel.contentView = NSHostingView(rootView: HUDView(controller: controller))
    }

    func show(at position: HUDPosition) {
        let mouse = NSEvent.mouseLocation
        guard let screen = Self.screen(containing: mouse) else { return }
        let size = Self.hudSize
        var origin: NSPoint
        switch position {
        case .center:
            origin = NSPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2)
        case .cursor:
            origin = NSPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height / 2)
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
            origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        }
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    /// 実行したアクションを一瞬だけ表示する
    func toast(_ text: String) {
        guard let screen = Self.screen(containing: NSEvent.mouseLocation) else { return }
        toastPanel.contentView = NSHostingView(rootView: ToastView(text: text))
        toastPanel.setFrameOrigin(NSPoint(
            x: screen.frame.midX - Self.toastSize.width / 2,
            y: screen.visibleFrame.minY + 120
        ))
        toastPanel.orderFrontRegardless()
        toastHide?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.toastPanel.orderOut(nil) }
        toastHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    private static func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
    }
}

private struct HUDView: View {
    let controller: SpikeController

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("検証用（Xcode の例）")
                    .foregroundStyle(.white)
                    .fontWeight(.medium)
                Spacer()
                Text(controller.fireMode == .onRelease ? "\(controller.trigger.symbol)を離して実行" : "マスから指を離して実行")
                    .foregroundStyle(Color(white: 0.6))
            }
            .font(.system(size: 12))
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach(0..<3, id: \.self) { row in
                    GridRow {
                        ForEach(0..<3, id: \.self) { column in
                            cell(row * 3 + column)
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(width: 504, height: 315)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(white: 0.067)))
    }

    private func cell(_ index: Int) -> some View {
        let selected = controller.fingerCount > 0 && controller.currentCell == index
        let item = sampleCells[index]
        return VStack(spacing: 6) {
            Image(systemName: item.symbol)
                .font(.system(size: 20))
            Text(item.label)
                .font(.system(size: 13, weight: .medium))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(selected ? Color(white: 0.067) : Color(white: 0.66))
        .background(RoundedRectangle(cornerRadius: 12).fill(selected ? Color.white : Color(white: 0.118)))
    }
}

private struct ToastView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 240, height: 48)
            .background(Capsule().fill(Color(white: 0.067)))
    }
}
