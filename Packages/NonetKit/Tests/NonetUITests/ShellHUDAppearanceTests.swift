// 担当: ui-shell。HUD の大きさ（設定の「HUD の大きさ」）・読みやすさ（コントラスト）・ページの点・使い始めの案内
import AppKit
import CoreGraphics
import NonetCore
import SwiftUI
@testable import NonetUI
import Testing

@Suite("HUD の大きさと見た目")
@MainActor
struct ShellHUDAppearanceTests {
    static func model(pageCount: Int = 1, banner: String? = nil, scale: Double = 1) -> HUDModel {
        HUDModel(
            title: "Xcode",
            pageIndex: 0,
            pageCount: pageCount,
            cells: Array(repeating: nil, count: 9),
            highlightedIndex: nil,
            banner: banner,
            scale: scale
        )
    }

    @Test("大きさの倍率は、寸法をそのまま大きくする")
    func scaledSize() {
        let side = RadialLayout.outerRadius * 2
        #expect(HUDLayout.size(for: Self.model(scale: 1)) == CGSize(width: side, height: side))
        #expect(HUDLayout.size(for: Self.model(scale: 1.25)) == CGSize(width: side * 1.25, height: side * 1.25))
        #expect(HUDLayout.size(for: Self.model(scale: 1.5)) == CGSize(width: side * 1.5, height: side * 1.5))
        // 壊れた倍率は 1
        #expect(HUDLayout.size(for: Self.model(scale: .nan)) == CGSize(width: side, height: side))
        // 帯は枠の外（下か上）。影の余白に収まる
        #expect(HUDMetrics(scale: 1).pillFrame(below: true) == CGRect(x: 0, y: side + HUDLayout.pillGap, width: side, height: HUDLayout.pillHeight))
        #expect(HUDMetrics(scale: 1).pillFrame(below: false) == CGRect(x: 0, y: -(HUDLayout.pillGap + HUDLayout.pillHeight), width: side, height: HUDLayout.pillHeight))
        #expect(HUDLayout.pillGap + HUDLayout.pillHeight + 9 <= HUDLayout.shadowMargin)
        #expect(HUDMetrics(scale: 1.5).iconSize == 30)
        #expect(HUDMetrics(scale: 1.5).selectionRadius == 33)
        #expect(HUDMetrics(scale: 1.5).keyRadius == 162)
    }

    @Test("画面に収まらない大きさは、収まるところまで小さくする")
    func fittingOnScreen() {
        let main = ShellHUDPlacementTests.main
        #expect(HUDPlacement.fittedScale(for: Self.model(scale: 1.5), in: main) == 1.5)
        let small = HUDScreenGeometry(frame: CGRect(x: 0, y: 0, width: 800, height: 400), visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 370))
        let fitted = HUDPlacement.fittedScale(for: Self.model(pageCount: 3, banner: "帯", scale: 1.5), in: small)
        #expect(fitted < 1.5)
        var model = Self.model(pageCount: 3, banner: "帯", scale: 1.5)
        model = HUDPlacement.fitted(model, in: small)
        let size = HUDLayout.size(for: model)
        let margin = HUDPlacement.edgeMargin + HUDLayout.shadowMargin
        #expect(size.height <= small.visibleFrame.height - 2 * margin + 1e-9)
        #expect(size.width <= small.visibleFrame.width - 2 * margin + 1e-9)
        // 大きな画面では、選んだ大きさのまま
        #expect(HUDPlacement.fittedScale(for: Self.model(scale: 1), in: main) == 1)
        #expect(HUDPlacement.fittedScale(for: Self.model(pageCount: 3, scale: 1.25), in: main) == 1.25)
    }

    @Test("トーストを出していなくても、消すのは何もしない")
    func toastCallsWithoutAToast() {
        let hud = HUDWindowController(screens: { [] }, mouseLocation: { .zero }, prefersIncreasedContrast: { true })
        hud.hideToast()
        #expect(!hud.isShowingHUD)
    }

    @Test("トーストの文字のコントラスト: 4.5:1 以上。「コントラストを上げる」ではさらに上げる")
    func contrast() {
        for colors in [HUDColors.standard, .increased] {
            #expect(HUDLuminance.contrastRatio(white: colors.foregroundWhite, white: HUDPalette.backgroundWhite) >= 4.5)
            #expect(HUDLuminance.contrastRatio(white: colors.secondaryTextWhite, white: HUDPalette.backgroundWhite) >= 4.5)
        }
        let standard = HUDColors.standard
        let increased = HUDColors.increased
        #expect(increased.foregroundWhite > standard.foregroundWhite)
        #expect(increased.secondaryTextWhite > standard.secondaryTextWhite)
        #expect(increased.borderOpacity >= 0.4)
        #expect(HUDPalette.colors(increasedContrast: true) == increased)
        #expect(HUDPalette.colors(increasedContrast: false) == standard)
        // 白と黒は 21:1（下地の測定と同じ式）
        #expect(abs(HUDLuminance.contrastRatio(white: 1, white: 0) - 21) < 1e-9)
    }

    @Test("macOS 26 以降は Dock と同じガラスの面、それより前は暗い不透明な面")
    func surface() {
        if #available(macOS 26, *) {
            #expect(HUDSurface.current == .glass)
        } else {
            #expect(HUDSurface.current == .solid)
        }
    }

    @Test("トーストの面: 不透明な面はモックの色、ガラスでは階層のスタイル")
    func themes() {
        let solid = HUDTheme(surface: .solid, colors: .standard)
        #expect(!solid.isGlass)
        #expect(HUDTheme(surface: .glass).isGlass)
        #expect(HUDColors.standard.secondaryText == Color(white: HUDColors.standard.secondaryTextWhite))
    }

    @Test("外枠にいるときは鍵のアイコンを薄くする。「コントラストを上げる」では薄くしすぎない")
    func dimming() {
        #expect(HUDKeyPalette.dimmedIconOpacity < HUDKeyPalette.dimmedIconOpacityIncreased)
        #expect(HUDKeyPalette.dimmedIconOpacityIncreased <= 0.6)
    }

    @Test("アプリのページとグローバルのページの点の間を空ける")
    func pageDotGap() {
        let metrics = HUDMetrics(scale: 1)
        #expect(HUDPageDots.leadingSpace(before: 0, globalPagesStart: 2, metrics: metrics) == 0)
        #expect(HUDPageDots.leadingSpace(before: 1, globalPagesStart: 2, metrics: metrics) == metrics.dotSpacing)
        #expect(HUDPageDots.leadingSpace(before: 2, globalPagesStart: 2, metrics: metrics) == metrics.dotSpacing + metrics.pageGroupGap)
        #expect(HUDPageDots.leadingSpace(before: 2, globalPagesStart: nil, metrics: metrics) == metrics.dotSpacing)
        #expect(HUDPageDots.leadingSpace(before: 2, globalPagesStart: 2, metrics: HUDMetrics(scale: 1.5)) == (6 + 6) * 1.5)
    }

    @Test("トーストの最大の幅は倍率に合わせ、画面より広くしない")
    func toastWidth() {
        #expect(HUDToastLayout.maxWidth(scale: 1, screenWidth: 1440) == HUDToastLayout.maxWidth)
        #expect(HUDToastLayout.maxWidth(scale: 1.5, screenWidth: 1440) == HUDToastLayout.maxWidth * 1.5)
        let narrow = HUDToastLayout.maxWidth(scale: 1.5, screenWidth: 600)
        #expect(narrow == 600 - 2 * HUDPlacement.edgeMargin - 2 * HUDToastLayout.shadowMargin)
    }

    @Test("大きいトーストは、測った大きさも大きい")
    func toastMeasuresLarger() {
        let measurer = NSHostingController(rootView: HUDToastView(toast: ToastModel(title: "")))
        func width(_ scale: Double) -> CGFloat {
            measurer.rootView = HUDToastView(toast: ToastModel(title: "ビルド", detail: "⌘B", style: .success, scale: scale))
            return measurer.sizeThatFits(in: CGSize(width: 2000, height: 1000)).width
        }
        #expect(width(1.5) > width(1) * 1.3)
    }
}
