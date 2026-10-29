// 担当: ui-shell
import AppKit
import NonetCore
import Observation
import SwiftUI

/// トーストの寸法と表示時間
enum HUDToastLayout {
    static let maxWidth: CGFloat = 520
    static let minWidth: CGFloat = 120
    static let shadowMargin: CGFloat = 16

    /// 成功と案内は一瞬、失敗は読めるだけの時間
    static func duration(for style: ToastModel.Style) -> TimeInterval {
        switch style {
        case .info, .success: 0.8
        case .failure: 2.5
        }
    }

    /// アイコンが無いときに出す記号。案内は出さない
    static func fallbackSymbol(for style: ToastModel.Style) -> String? {
        switch style {
        case .info: nil
        case .success: "checkmark.circle.fill"
        case .failure: "exclamationmark.triangle.fill"
        }
    }
}

@MainActor
@Observable
final class HUDToastStore {
    var toast: ToastModel?
}

struct HUDToastRootView: View {
    let store: HUDToastStore

    var body: some View {
        ZStack {
            if let toast = store.toast {
                HUDToastView(toast: toast)
            }
        }
        .padding(HUDToastLayout.shadowMargin)
    }
}

/// 画面の下に一瞬出す黒い小さな帯。アイコン＋名前（＋説明）
struct HUDToastView: View {
    let toast: ToastModel

    var body: some View {
        HStack(spacing: 10) {
            // 失敗はマスのアイコンより「失敗した」ことを見せる
            if let icon = toast.icon, toast.style != .failure {
                CellIconView(icon, size: 16)
            } else if let symbol = HUDToastLayout.fallbackSymbol(for: toast.style) {
                Image(systemName: symbol)
                    .font(.system(size: 16))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let detail = toast.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(HUDPalette.secondaryText)
                        .lineLimit(toast.style == .failure ? 4 : 1)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .foregroundStyle(Color(white: 0.85))
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .frame(minWidth: HUDToastLayout.minWidth)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(HUDPalette.background)
                .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(toast.style == .failure ? 0.3 : 0.1), lineWidth: 1)
        )
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .combine)
    }
}

/// トーストのパネル。新しいトーストは今のものを置き換え、置き換えたものの「隠す」は取り消す
@MainActor
final class HUDToastPresenter {
    private let store = HUDToastStore()
    private lazy var panel: HUDOverlayPanel = {
        let panel = HUDOverlayPanel()
        panel.contentView = HUDOverlayPanel.hostingView(HUDToastRootView(store: store))
        return panel
    }()
    private lazy var fader = HUDPanelFader(panel: panel)
    private lazy var measurer = NSHostingController(rootView: HUDToastView(toast: ToastModel(title: "")))
    private var hideTimer: Timer?

    func show(_ toast: ToastModel, on screen: HUDScreenGeometry) {
        store.toast = toast
        let size = measure(toast)
        let margin = HUDToastLayout.shadowMargin
        let frame = HUDPlacement.toastFrame(size: size, screen: screen).insetBy(dx: -margin, dy: -margin)
        panel.setFrame(frame, display: true)
        fader.show()
        HUDAccessibility.announce(HUDAccessibility.toastAnnouncement(title: toast.title, detail: toast.detail))

        hideTimer?.invalidate()
        let timer = Timer(timeInterval: HUDToastLayout.duration(for: toast.style), repeats: false) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, self.hideTimer === timer else { return }
                self.hide()
            }
        }
        hideTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func hide() {
        hideTimer?.invalidate()
        hideTimer = nil
        fader.hide { [weak self] in
            self?.store.toast = nil
        }
    }

    /// 文が長ければ最大の幅で折り返した大きさ
    private func measure(_ toast: ToastModel) -> CGSize {
        measurer.rootView = HUDToastView(toast: toast)
        let fitting = measurer.sizeThatFits(in: CGSize(width: HUDToastLayout.maxWidth, height: 400))
        return CGSize(width: min(ceil(fitting.width), HUDToastLayout.maxWidth), height: ceil(fitting.height))
    }
}
