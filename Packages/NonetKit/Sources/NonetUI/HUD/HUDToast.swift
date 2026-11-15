// 担当: ui-shell
import AppKit
import NonetCore
import Observation
import SwiftUI

/// トーストの寸法と表示時間
enum HUDToastLayout {
    /// 倍率 1 の最大の幅
    static let maxWidth: CGFloat = 520
    static let minWidth: CGFloat = 120
    static let shadowMargin: CGFloat = 16
    /// 成功と、説明の無い案内を出しておく秒数
    static let briefDuration: TimeInterval = 0.8
    /// 失敗（と説明のある案内）の表示時間: 基本の秒数に、1文字ごとの秒数を足し、最短と最長で止める（3行のエラー出力も読めるように）
    static let failureBaseDuration: TimeInterval = 1.5
    static let failureDurationPerCharacter: TimeInterval = 0.06
    static let failureDurationRange: ClosedRange<TimeInterval> = 3...8
    /// 案内の説明の行数の上限（失敗は4行）
    static let infoDetailLineLimit = 2

    /// 成功と説明の無い案内は一瞬、失敗と説明のある案内は読めるだけの時間（見出しと説明の文字数で決める）。実行中は時間では消さない（nil）
    static func duration(for toast: ToastModel) -> TimeInterval? {
        switch toast.style {
        case .success:
            return briefDuration
        case .info:
            guard let detail = toast.detail, !detail.isEmpty else { return briefDuration }
            return readingDuration(for: toast)
        case .failure:
            return readingDuration(for: toast)
        case .running:
            return nil
        }
    }

    /// 見出しと説明を読めるだけの時間
    private static func readingDuration(for toast: ToastModel) -> TimeInterval {
        let characters = toast.title.count + (toast.detail?.count ?? 0)
        let duration = failureBaseDuration + failureDurationPerCharacter * Double(characters)
        return min(max(duration, failureDurationRange.lowerBound), failureDurationRange.upperBound)
    }

    /// 説明の行数の上限。失敗はエラー出力の数行、案内は2行、ほかは1行
    static func detailLineLimit(for style: ToastModel.Style) -> Int {
        switch style {
        case .failure: 4
        case .info: infoDetailLineLimit
        case .success, .running: 1
        }
    }

    /// アイコンが無いときに出す記号。案内と実行中は出さない（実行中はくるくる回る印を出す）
    static func fallbackSymbol(for style: ToastModel.Style) -> String? {
        switch style {
        case .info, .running: nil
        case .success: "checkmark.circle.fill"
        case .failure: "exclamationmark.triangle.fill"
        }
    }

    /// 倍率を掛けた最大の幅。画面より広くしない
    static func maxWidth(scale: CGFloat, screenWidth: CGFloat) -> CGFloat {
        let available = screenWidth - 2 * HUDPlacement.edgeMargin - 2 * shadowMargin
        return max(minWidth, min(maxWidth * scale, available))
    }
}

/// トーストを消す時刻の決め方
struct HUDToastSchedule: Equatable {
    private(set) var style: ToastModel.Style?
    /// 消す時刻。nil なら時間では消さない
    private(set) var hideAt: TimeInterval?

    /// 出した。消す時刻を返す（nil なら時間では消さない）
    mutating func show(_ toast: ToastModel, at now: TimeInterval) -> TimeInterval? {
        style = toast.style
        hideAt = HUDToastLayout.duration(for: toast).map { now + $0 }
        return hideAt
    }

    /// 消す時刻が来た（タイマー）。いま消すなら true
    func deadlineReached(at now: TimeInterval) -> Bool {
        guard let hideAt else { return false }
        return now >= hideAt
    }

    mutating func hidden() {
        style = nil
        hideAt = nil
    }
}

@MainActor
@Observable
final class HUDToastStore {
    var toast: ToastModel?
    /// システム設定の「コントラストを上げる」（出すたびに読み直す）
    var increasedContrast = false
}

struct HUDToastRootView: View {
    let store: HUDToastStore

    var body: some View {
        ZStack {
            if let toast = store.toast {
                HUDToastView(toast: toast, colors: HUDPalette.colors(increasedContrast: store.increasedContrast))
            }
        }
        .padding(HUDToastLayout.shadowMargin)
    }
}

/// 画面の下に一瞬出す小さな帯（HUD と同じ面）。アイコン＋名前（＋説明）
struct HUDToastView: View {
    let toast: ToastModel
    var colors: HUDColors = .standard
    /// 最大の幅（測るときと同じ値で折り返す）
    var maxWidth: CGFloat?
    var surface: HUDSurface = .current

    private var scale: CGFloat { HUDMetrics(scale: toast.scale).scale }
    private var theme: HUDTheme { HUDTheme(surface: surface, colors: colors) }

    var body: some View {
        let scale = scale
        HStack(spacing: 10 * scale) {
            // 失敗はマスのアイコンより「失敗した」ことを見せる。実行中は回る印
            if toast.style == .running {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(scale)
                    .frame(width: 16 * scale, height: 16 * scale)
            } else if let icon = toast.icon, toast.style != .failure {
                CellIconView(icon, size: 16 * scale)
            } else if let symbol = HUDToastLayout.fallbackSymbol(for: toast.style) {
                Image(systemName: symbol)
                    .font(.system(size: 16 * scale))
            }
            VStack(alignment: .leading, spacing: 2 * scale) {
                Text(toast.title)
                    .font(.system(size: 14 * scale, weight: .semibold))
                    .foregroundStyle(theme.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let detail = toast.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 12 * scale))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(HUDToastLayout.detailLineLimit(for: toast.style))
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .foregroundStyle(surface == .glass ? theme.foreground : AnyShapeStyle(Color(white: 0.85)))
        .padding(.horizontal, 18 * scale)
        .padding(.vertical, 11 * scale)
        .frame(minWidth: HUDToastLayout.minWidth * scale)
        .frame(maxWidth: maxWidth)
        .modifier(HUDSurfaceBackground(
            surface: surface,
            shape: RoundedRectangle(cornerRadius: 22 * scale, style: .continuous),
            border: Color.white.opacity(toast.style == .failure ? 0.3 : max(0.1, colors.borderOpacity)),
            shadowOpacity: 0.3,
            shadowRadius: 10,
            shadowY: 4
        ))
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
    private var schedule = HUDToastSchedule()
    private let now: () -> TimeInterval

    init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.now = now
    }

    func show(_ toast: ToastModel, on screen: HUDScreenGeometry, increasedContrast: Bool) {
        store.toast = toast
        store.increasedContrast = increasedContrast
        let size = measure(toast, screen: screen)
        let margin = HUDToastLayout.shadowMargin
        let frame = HUDPlacement.toastFrame(size: size, screen: screen).insetBy(dx: -margin, dy: -margin)
        panel.setFrame(frame, display: true)
        fader.show()
        HUDAccessibility.announce(HUDAccessibility.toastAnnouncement(title: toast.title, detail: toast.detail))
        startTimer(until: schedule.show(toast, at: now()))
    }

    func hide() {
        hideTimer?.invalidate()
        hideTimer = nil
        schedule.hidden()
        fader.hide { [weak self] in
            self?.store.toast = nil
        }
    }

    private func startTimer(until hideAt: TimeInterval?) {
        hideTimer?.invalidate()
        hideTimer = nil
        guard let hideAt else { return }
        let timer = Timer(timeInterval: max(0, hideAt - now()), repeats: false) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, self.hideTimer === timer else { return }
                self.hideTimer = nil
                if self.schedule.deadlineReached(at: self.now()) {
                    self.hide()
                }
            }
        }
        hideTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    /// 文が長ければ最大の幅で折り返した大きさ
    private func measure(_ toast: ToastModel, screen: HUDScreenGeometry) -> CGSize {
        let limit = HUDToastLayout.maxWidth(scale: HUDMetrics(scale: toast.scale).scale, screenWidth: screen.visibleFrame.width)
        measurer.rootView = HUDToastView(toast: toast, maxWidth: limit)
        let fitting = measurer.sizeThatFits(in: CGSize(width: limit, height: 400 * HUDMetrics(scale: toast.scale).scale))
        return CGSize(width: min(ceil(fitting.width), limit), height: ceil(fitting.height))
    }
}
