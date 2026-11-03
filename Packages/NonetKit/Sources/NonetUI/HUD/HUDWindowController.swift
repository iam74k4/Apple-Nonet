// 担当: ui-shell（クラス名・init・HUDPresenting への準拠は契約）
import AppKit
import NonetCore
import os
import SwiftUI

private let logger = Logger(subsystem: "com.iam74k4.Nonet", category: "ui-shell")

/// HUD・トースト・結果のパネル。前面アプリからフォーカスを奪わない、最前面のパネルに出す。
/// update はハイライトが変わるたびに呼ばれるので、パネルとホスティングビューは使い回し、中身のモデルだけを書き換える
@MainActor
public final class HUDWindowController: HUDPresenting {
    private let screens: () -> [HUDScreenGeometry]
    private let mouseLocation: () -> CGPoint
    /// システム設定の「コントラストを上げる」。HUD とトーストを出すたびに読み直す
    private let prefersIncreasedContrast: () -> Bool
    /// システム設定の「視差効果を減らす」。HUD を出すたびに読み直す
    private let prefersReducedMotion: () -> Bool
    /// システム設定の「透明度を下げる」。HUD を出すたびに読み直す
    private let prefersReducedTransparency: () -> Bool

    private let hudStore = HUDStore()
    private lazy var hudPanel: HUDOverlayPanel = {
        let panel = HUDOverlayPanel()
        panel.contentView = HUDOverlayPanel.hostingView(HUDRootView(store: hudStore))
        return panel
    }()
    private lazy var hudFader = HUDPanelFader(panel: hudPanel)
    /// 表示中の HUD の見た目の枠（影の余白を含まない）と、その画面
    private var hudFrame: CGRect?
    private var hudScreen: HUDScreenGeometry?
    /// 9マスを開いている間、ポインタを地図の上の指の位置へ動かす（座標は主画面の左上が原点）。App が KeyboardMonitor.movePointer につなぐ
    public var onMovePointer: ((CGPoint) -> Void)?

    private let toast = HUDToastPresenter()
    private let result = HUDResultPanelController()
    private let placementPreview = HUDPlacementPreviewController()

    public convenience init() {
        self.init(
            screens: { HUDScreenGeometry.current() },
            mouseLocation: { NSEvent.mouseLocation },
            prefersIncreasedContrast: { NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast },
            prefersReducedMotion: { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion },
            prefersReducedTransparency: { NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency }
        )
    }

    init(
        screens: @escaping () -> [HUDScreenGeometry],
        mouseLocation: @escaping () -> CGPoint,
        prefersIncreasedContrast: @escaping () -> Bool = { false },
        prefersReducedMotion: @escaping () -> Bool = { false },
        prefersReducedTransparency: @escaping () -> Bool = { false }
    ) {
        self.screens = screens
        self.mouseLocation = mouseLocation
        self.prefersIncreasedContrast = prefersIncreasedContrast
        self.prefersReducedMotion = prefersReducedMotion
        self.prefersReducedTransparency = prefersReducedTransparency
    }

    /// HUD を表示中か（フェードアウト中は含まない）
    var isShowingHUD: Bool { hudFader.isShowing }

    public func show(_ model: HUDModel) {
        // 表示中にもう一度呼ばれたら、位置を動かさずに中身だけ変える
        if hudFader.isShowing, hudFrame != nil {
            update(model)
            return
        }
        let cursor = mouseLocation()
        guard let screen = HUDPlacement.screen(containing: cursor, in: screens()) else {
            logger.error("HUD を出す画面が見つからない")
            return
        }
        let model = HUDPlacement.fitted(model, in: screen)
        hudStore.model = model
        hudStore.increasedContrast = prefersIncreasedContrast()
        hudStore.reduceMotion = prefersReducedMotion()
        hudStore.reduceTransparency = prefersReducedTransparency()
        place(HUDPlacement.hudFrame(size: HUDLayout.size(for: model), cursor: cursor, screen: screen), screen: screen)
        hudFader.show()
        // フェードアウト中の前の HUD があっても、新しい HUD として最初から読む
        HUDAccessibility.announce(HUDAnnouncement.announcement(from: nil, to: model) ?? "")
    }

    public func update(_ model: HUDModel) {
        guard hudFader.isShowing, let frame = hudFrame, let screen = hudScreen else { return }
        let model = HUDPlacement.fitted(model, in: screen)
        let previous = hudStore.model
        guard previous != model else { return }
        hudStore.model = model
        let size = HUDLayout.size(for: model)
        if size != frame.size {
            // 帯やページの点が増減したら、中心をそろえて大きさを変える
            let resized = HUDPlacement.frame(size: size, centeredAt: CGPoint(x: frame.midX, y: frame.midY), in: screen)
            place(resized, screen: screen)
        }
        if let announcement = HUDAnnouncement.announcement(from: previous, to: model) {
            HUDAccessibility.announce(announcement)
        }
    }

    /// 指の位置を地図の上に写し、実際のポインタをそこへ動かす（地図に点は描かない。2本以上の指では動かさない）
    public func updateFinger(_ finger: HUDFinger?) {
        guard hudFader.isShowing, let frame = hudFrame, let model = hudStore.model, let finger, let onMovePointer,
              let primary = screens().first?.frame else { return }
        onMovePointer(HUDPlacement.pointerLocation(for: finger, model: model, hudFrame: frame, primaryScreen: primary))
    }

    public func showPlacementPreview(_ frame: CGRect) {
        placementPreview.show(frame, animated: !prefersReducedMotion())
    }

    public func hidePlacementPreview() {
        placementPreview.hide()
    }

    public func hide() {
        placementPreview.hide()
        guard hudFader.isShowing else { return }
        hudFrame = nil
        hudScreen = nil
        hudFader.hide { [weak self] in
            self?.hudStore.model = nil
        }
    }

    public func showToast(_ toast: ToastModel) {
        guard let screen = HUDPlacement.screen(containing: mouseLocation(), in: screens()) else {
            logger.error("トーストを出す画面が見つからない")
            return
        }
        self.toast.show(toast, on: screen, increasedContrast: prefersIncreasedContrast())
    }

    public func hideToast() {
        toast.hide()
    }

    public func showResult(_ result: ResultModel) {
        let cursor = mouseLocation()
        guard let screen = HUDPlacement.screen(containing: cursor, in: screens()) else {
            logger.error("結果のパネルを出す画面が見つからない")
            return
        }
        // HUD を出していた場所（ポインタの近く）に出す
        let anchor = hudFrame.map { CGPoint(x: $0.midX, y: $0.midY) } ?? cursor
        self.result.show(result, centeredAt: anchor, on: screen)
    }

    private func place(_ frame: CGRect, screen: HUDScreenGeometry) {
        hudFrame = frame
        hudScreen = screen
        let margin = HUDLayout.shadowMargin
        hudPanel.setFrame(frame.insetBy(dx: -margin, dy: -margin), display: true)
    }
}
