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
    /// 最後に HUD を出した位置の設定。結果のパネルもそれに合わせる
    private var lastPosition: HUDPosition = .screenCenter

    private let toast = HUDToastPresenter()
    private let result = HUDResultPanelController()

    public convenience init() {
        self.init(screens: { HUDScreenGeometry.current() }, mouseLocation: { NSEvent.mouseLocation })
    }

    init(screens: @escaping () -> [HUDScreenGeometry], mouseLocation: @escaping () -> CGPoint) {
        self.screens = screens
        self.mouseLocation = mouseLocation
    }

    /// HUD を表示中か（フェードアウト中は含まない）
    var isShowingHUD: Bool { hudFader.isShowing }

    public func show(_ model: HUDModel, position: HUDPosition) {
        lastPosition = position
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
        hudStore.model = model
        let frame = HUDPlacement.hudFrame(size: HUDLayout.size(for: model), position: position, cursor: cursor, screen: screen)
        place(frame, screen: screen)
        hudFader.show()
        // フェードアウト中の前の HUD があっても、新しい HUD として最初から読む
        HUDAccessibility.announce(HUDAnnouncement.announcement(from: nil, to: model) ?? "")
    }

    public func update(_ model: HUDModel) {
        guard hudFader.isShowing, let frame = hudFrame, let screen = hudScreen else { return }
        let previous = hudStore.model
        guard previous != model else { return }
        hudStore.model = model
        let size = HUDLayout.size(for: model)
        if size != frame.size {
            // 帯やページの点が増減したら、中心をそろえて大きさを変える
            place(HUDPlacement.frame(size: size, centeredAt: CGPoint(x: frame.midX, y: frame.midY), in: screen), screen: screen)
        }
        if let announcement = HUDAnnouncement.announcement(from: previous, to: model) {
            HUDAccessibility.announce(announcement)
        }
    }

    public func hide() {
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
        self.toast.show(toast, on: screen)
    }

    public func showResult(_ result: ResultModel) {
        let cursor = mouseLocation()
        guard let screen = HUDPlacement.screen(containing: cursor, in: screens()) else {
            logger.error("結果のパネルを出す画面が見つからない")
            return
        }
        // HUD を出していた場所（中央かカーソルの近く）に出す
        let anchor = HUDPlacement.hudFrame(size: .zero, position: lastPosition, cursor: cursor, screen: screen)
        self.result.show(result, centeredAt: CGPoint(x: anchor.midX, y: anchor.midY), on: screen)
    }

    private func place(_ frame: CGRect, screen: HUDScreenGeometry) {
        hudFrame = frame
        hudScreen = screen
        let margin = HUDLayout.shadowMargin
        hudPanel.setFrame(frame.insetBy(dx: -margin, dy: -margin), display: true)
    }
}
