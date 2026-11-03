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
    /// 表示中の HUD の画面
    private var hudScreen: HUDScreenGeometry?

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
        // 表示中にもう一度呼ばれたら、中身だけ変える
        if hudFader.isShowing, hudScreen != nil {
            update(model)
            return
        }
        let cursor = mouseLocation()
        guard let screen = HUDPlacement.screen(containing: cursor, in: screens()) else {
            logger.error("HUD を出す画面が見つからない")
            return
        }
        hudStore.model = model
        hudStore.finger = nil
        hudStore.increasedContrast = prefersIncreasedContrast()
        hudStore.reduceMotion = prefersReducedMotion()
        hudStore.reduceTransparency = prefersReducedTransparency()
        hudScreen = screen
        hudPanel.setFrame(HUDPlacement.hudFrame(on: screen), display: true)
        hudFader.show()
        // フェードアウト中の前の HUD があっても、新しい HUD として最初から読む
        HUDAccessibility.announce(HUDAnnouncement.announcement(from: nil, to: model) ?? "")
    }

    public func update(_ model: HUDModel) {
        guard hudFader.isShowing, hudScreen != nil else { return }
        let previous = hudStore.model
        guard previous != model else { return }
        hudStore.model = model
        if let announcement = HUDAnnouncement.announcement(from: previous, to: model) {
            HUDAccessibility.announce(announcement)
        }
    }

    public func updateFinger(_ finger: HUDFinger?) {
        guard hudFader.isShowing else { return }
        hudStore.finger = finger
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
        hudScreen = nil
        hudFader.hide { [weak self] in
            self?.hudStore.model = nil
            self?.hudStore.finger = nil
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
        self.result.show(result, centeredAt: HUDPlacement.resultAnchor(on: screen), on: screen)
    }
}
