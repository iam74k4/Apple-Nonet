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
    /// システム設定の「透明度を下げる」。トーストを出すたびに読み直す
    private let prefersReducedTransparency: () -> Bool
    /// HUD の下の画面の明るさを測る（アイコンの色を下地に合わせる）。無ければ測らない
    private let backdropSampler: (any HUDBackdropSampling)?

    private let hudStore = HUDStore()
    /// 何回目の HUD か。下の画面を測り終えたとき、その間に閉じた・出し直した HUD の色を変えないため
    private var inkGeneration = 0
    private lazy var hudPanel: HUDOverlayPanel = {
        let panel = HUDOverlayPanel()
        panel.contentView = HUDOverlayPanel.hostingView(HUDRootView(store: hudStore))
        return panel
    }()
    private lazy var hudFader = HUDPanelFader(panel: hudPanel)
    /// 表示中の HUD の見た目の枠（影の余白を含まない）と、その画面
    private var hudFrame: CGRect?
    private var hudScreen: HUDScreenGeometry?
    /// 表示中の HUD の地図の枠（主画面の左上が原点、y が下向き）。デモがポインタを台本の指の位置へ動かすのに読む
    public private(set) var mapFrame: CGRect?

    private let toast = HUDToastPresenter()
    private let result = HUDResultPanelController()
    private let placementPreview = HUDPlacementPreviewController()

    public convenience init() {
        self.init(
            screens: { HUDScreenGeometry.current() },
            mouseLocation: { NSEvent.mouseLocation },
            prefersIncreasedContrast: { NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast },
            prefersReducedMotion: { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion },
            prefersReducedTransparency: { NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency },
            backdropSampler: ScreenCaptureBackdropSampler()
        )
    }

    init(
        screens: @escaping () -> [HUDScreenGeometry],
        mouseLocation: @escaping () -> CGPoint,
        prefersIncreasedContrast: @escaping () -> Bool = { false },
        prefersReducedMotion: @escaping () -> Bool = { false },
        prefersReducedTransparency: @escaping () -> Bool = { false },
        backdropSampler: (any HUDBackdropSampling)? = nil
    ) {
        self.screens = screens
        self.mouseLocation = mouseLocation
        self.prefersIncreasedContrast = prefersIncreasedContrast
        self.prefersReducedMotion = prefersReducedMotion
        self.prefersReducedTransparency = prefersReducedTransparency
        self.backdropSampler = backdropSampler
    }

    /// いまの鍵の色（テスト用）
    var inks: HUDInks { hudStore.inks }
    /// 帯を円の下に出すか（テスト用）
    var pillBelow: Bool { hudStore.pillBelow }

    /// HUD を表示中か（フェードアウト中は含まない）
    var isShowingHUD: Bool { hudFader.isShowing }

    /// 出す（ポインタを中心にした円）。円を囲む正方形の枠（主画面の左上が原点）を返す。表示中にもう一度呼ばれたら、位置を動かさずに中身だけ変える。
    /// アイコンの色は、まず黒に白い縁（どの下地でも読める）で出し、下の画面を測り終えたら鍵ごとに白か濃い色に替える
    @discardableResult
    public func show(_ model: HUDModel) -> CGRect? {
        if hudFader.isShowing, hudFrame != nil {
            return update(model) ?? mapFrame
        }
        let cursor = mouseLocation()
        guard let screen = HUDPlacement.screen(containing: cursor, in: screens()) else {
            logger.error("HUD を出す画面が見つからない")
            return nil
        }
        let model = HUDPlacement.fitted(model, in: screen)
        hudStore.model = model
        hudStore.inks = .fallback
        hudStore.increasedContrast = prefersIncreasedContrast()
        hudStore.reduceMotion = prefersReducedMotion()
        let frame = HUDPlacement.hudFrame(size: HUDLayout.size(for: model), metrics: HUDMetrics(scale: model.scale), cursor: cursor, screen: screen)
        place(frame, screen: screen)
        hudFader.show()
        sampleBackdrop(for: model)
        // フェードアウト中の前の HUD があっても、新しい HUD として最初から読む
        HUDAccessibility.announce(HUDAnnouncement.announcement(from: nil, to: model) ?? "")
        return mapFrame
    }

    /// 設定で「背景に合わせて色を変える」がオンで、画面収録の許可があれば、HUD の下を 1 枚撮って鍵ごとの明るさを測る。
    /// 測り終えるまでの数コマは黒に白い縁のまま（HUDInks.fallback）。その間に閉じた・出し直したら、結果は捨てる
    private func sampleBackdrop(for model: HUDModel) {
        inkGeneration += 1
        guard model.adaptsInk, let sampler = backdropSampler, sampler.isAvailable, let map = mapFrame else { return }
        let generation = inkGeneration
        let metrics = HUDMetrics(scale: model.scale)
        let keys = (0..<Page.cellCount).map(metrics.position(ofCell:))
        sampler.sample(map, keys: keys, radius: metrics.selectionRadius) { [weak self] luminances in
            guard let self, self.inkGeneration == generation, self.hudFader.isShowing else { return }
            self.hudStore.inks = HUDInkDecision.inks(forLuminances: luminances)
        }
    }

    /// 中身を変える。大きさが変わるときは、円（ポインタが選ぶ場所）を動かさずに下へ伸び縮みさせ、新しい枠を返す
    @discardableResult
    public func update(_ model: HUDModel) -> CGRect? {
        guard hudFader.isShowing, let frame = hudFrame, let screen = hudScreen else { return nil }
        let model = HUDPlacement.fitted(model, in: screen)
        let previous = hudStore.model
        guard previous != model else { return nil }
        hudStore.model = model
        let size = HUDLayout.size(for: model)
        var resized: CGRect?
        if size != frame.size {
            resized = HUDPlacement.resized(frame, to: size, in: screen)
            place(resized!, screen: screen)
        }
        if let announcement = HUDAnnouncement.announcement(from: previous, to: model) {
            HUDAccessibility.announce(announcement)
        }
        return resized == nil ? nil : mapFrame
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
        inkGeneration += 1
        hudFrame = nil
        hudScreen = nil
        mapFrame = nil
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
        if let model = hudStore.model, let primary = screens().first?.frame {
            let metrics = HUDMetrics(scale: model.scale)
            mapFrame = HUDPlacement.mapFrame(hudFrame: frame, metrics: metrics, primaryScreen: primary)
            hudStore.pillBelow = HUDPlacement.pillFitsBelow(hudFrame: frame, metrics: metrics, screen: screen)
        }
        let margin = HUDLayout.shadowMargin
        hudPanel.setFrame(frame.insetBy(dx: -margin, dy: -margin), display: true)
    }
}
