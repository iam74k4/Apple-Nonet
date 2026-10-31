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
    static func model(pageCount: Int = 1, banner: String? = nil, footnote: String? = nil, scale: Double = 1) -> HUDModel {
        HUDModel(
            title: "Xcode",
            pageIndex: 0,
            pageCount: pageCount,
            cells: Array(repeating: nil, count: 9),
            highlightedIndex: nil,
            hint: "",
            banner: banner,
            footnote: footnote,
            scale: scale
        )
    }

    @Test("大きさの倍率は、寸法をそのまま大きくする")
    func scaledSize() {
        #expect(HUDLayout.size(for: Self.model(scale: 1)) == CGSize(width: 504, height: 349))
        #expect(HUDLayout.size(for: Self.model(scale: 1.25)) == CGSize(width: 630, height: 436.25))
        #expect(HUDLayout.size(for: Self.model(scale: 1.5)) == CGSize(width: 756, height: 523.5))
        // 壊れた倍率は 1
        #expect(HUDLayout.size(for: Self.model(scale: .nan)) == CGSize(width: 504, height: 349))
        #expect(HUDMetrics(scale: 1.5).headerFontSize == 18)
        #expect(HUDMetrics(scale: 1.5).cellTitleFontSize == 19.5)
    }

    @Test("使い始めの案内の分だけ高くなる")
    func footnoteHeight() {
        let plain = HUDLayout.size(for: Self.model())
        let withFootnote = HUDLayout.size(for: Self.model(footnote: "指を滑らせて選ぶ"))
        #expect(withFootnote.height == plain.height + HUDLayout.footnoteHeight + HUDLayout.spacing)
        #expect(HUDLayout.size(for: Self.model(footnote: "案内", scale: 1.5)).height == withFootnote.height * 1.5)
    }

    @Test("画面に収まらない大きさは、収まるところまで小さくする")
    func fittingOnScreen() {
        let main = ShellHUDPlacementTests.main
        #expect(HUDPlacement.fittedScale(for: Self.model(scale: 1.5), in: main) == 1.5)
        let small = HUDScreenGeometry(frame: CGRect(x: 0, y: 0, width: 800, height: 500), visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 470))
        let fitted = HUDPlacement.fittedScale(for: Self.model(pageCount: 3, banner: "帯", footnote: "案内", scale: 1.5), in: small)
        #expect(fitted < 1.5)
        var model = Self.model(pageCount: 3, banner: "帯", footnote: "案内", scale: 1.5)
        model = HUDPlacement.fitted(model, in: small)
        let size = HUDLayout.size(for: model)
        let margin = HUDPlacement.edgeMargin + HUDLayout.shadowMargin
        #expect(size.height <= small.visibleFrame.height - 2 * margin + 1e-9)
        #expect(size.width <= small.visibleFrame.width - 2 * margin + 1e-9)
        // 大きな画面では、選んだ大きさのまま
        #expect(HUDPlacement.fittedScale(for: Self.model(scale: 1), in: main) == 1)
        #expect(HUDPlacement.fittedScale(for: Self.model(pageCount: 3, footnote: "案内", scale: 1.25), in: main) == 1.25)
    }

    @Test("トーストを出していなくても、消すのは何もしない")
    func toastCallsWithoutAToast() {
        let hud = HUDWindowController(screens: { [] }, mouseLocation: { .zero }, prefersIncreasedContrast: { true })
        hud.hideToast()
        #expect(!hud.isShowingHUD)
    }

    @Test("文字と点のコントラスト: 文字は 4.5:1、点は 3:1 以上。「コントラストを上げる」ではさらに上げる")
    func contrast() {
        for colors in [HUDColors.standard, .increased] {
            #expect(HUDPalette.contrastRatio(colors.detailWhite, HUDPalette.cellWhite) >= 4.5)
            #expect(HUDPalette.contrastRatio(colors.cellForegroundWhite, HUDPalette.cellWhite) >= 4.5)
            #expect(HUDPalette.contrastRatio(colors.secondaryTextWhite, HUDPalette.backgroundWhite) >= 4.5)
            #expect(HUDPalette.contrastRatio(colors.inactiveDotWhite, HUDPalette.backgroundWhite) >= 3)
        }
        let standard = HUDColors.standard
        let increased = HUDColors.increased
        #expect(increased.cellForegroundWhite > standard.cellForegroundWhite)
        #expect(increased.detailWhite > standard.detailWhite)
        #expect(increased.inactiveDotWhite > standard.inactiveDotWhite)
        #expect(increased.borderOpacity >= 0.4)
        #expect(increased.emptyCellStrokeOpacity >= 0.45)
        #expect(HUDPalette.colors(increasedContrast: true) == increased)
        #expect(HUDPalette.colors(increasedContrast: false) == standard)
        // 白と黒は 21:1
        #expect(abs(HUDPalette.contrastRatio(1, 0) - 21) < 1e-9)
    }

    @Test("macOS 26 以降は Dock と同じガラスの面、それより前は暗い不透明な面")
    func surface() {
        if #available(macOS 26, *) {
            #expect(HUDSurface.current == .glass)
        } else {
            #expect(HUDSurface.current == .solid)
        }
    }

    @Test("不透明な面はモックの色のまま。ガラスでは光らせたマスをライトでは黒く、ダークでは白く塗って文字を抜く")
    func themes() {
        let solid = HUDTheme(surface: .solid, colors: .standard, colorScheme: .light)
        #expect(solid.highlightedFill == .white)
        #expect(solid.highlightedForeground == HUDPalette.highlightedForeground)
        #expect(solid.frameStroke(isActive: true) == HUDColors.standard.frameStroke(isActive: true))
        #expect(solid.labelFill == HUDPalette.background)

        let dark = HUDTheme(surface: .glass, colors: .standard, colorScheme: .dark)
        #expect(dark.highlightedFill == .white)
        #expect(dark.labelForeground == .white)
        let light = HUDTheme(surface: .glass, colors: .standard, colorScheme: .light)
        #expect(light.highlightedFill != .white)
        #expect(light.highlightedForeground == .white)
        #expect(light.labelFill == .white)
        // 外枠に指があるときの縁は、ふだんよりはっきりさせる。「コントラストを上げる」ではふだんの縁も濃くする
        let increased = HUDTheme(surface: .glass, colors: .increased, colorScheme: .light)
        #expect(light.frameStroke(isActive: true) != light.frameStroke(isActive: false))
        #expect(increased.frameStroke(isActive: false) != light.frameStroke(isActive: false))
    }

    @Test("外枠の帯は、9マスの下をくり抜いた形")
    func frameBand() {
        let band = HUDFrameBand(cornerRadius: 18, insets: EdgeInsets(top: 14, leading: 9, bottom: 12, trailing: 9), innerCornerRadius: 16)
        // 偶奇の規則で塗る（SwiftUI の Path.contains(_:eoFill:) は、くり抜いた形で結果が逆になるので CGPath で確かめる）
        let path = band.path(in: CGRect(x: 0, y: 0, width: 400, height: 300)).cgPath
        // 帯の中
        #expect(path.contains(CGPoint(x: 4, y: 150), using: .evenOdd))
        #expect(path.contains(CGPoint(x: 200, y: 6), using: .evenOdd))
        #expect(path.contains(CGPoint(x: 200, y: 294), using: .evenOdd))
        // 9マスの下は塗らない
        #expect(!path.contains(CGPoint(x: 200, y: 150), using: .evenOdd))
        #expect(!path.contains(CGPoint(x: 20, y: 30), using: .evenOdd))
    }

    @Test("アプリのページとグローバルのページの点の間を空ける")
    func pageDotGap() {
        let metrics = HUDMetrics(scale: 1)
        #expect(HUDPageDots.leadingSpace(before: 0, globalPagesStart: 2, metrics: metrics) == 0)
        #expect(HUDPageDots.leadingSpace(before: 1, globalPagesStart: 2, metrics: metrics) == metrics.dotSpacing)
        #expect(HUDPageDots.leadingSpace(before: 2, globalPagesStart: 2, metrics: metrics) == metrics.dotSpacing + metrics.pageGroupGap)
        #expect(HUDPageDots.leadingSpace(before: 2, globalPagesStart: nil, metrics: metrics) == metrics.dotSpacing)
        #expect(HUDPageDots.leadingSpace(before: 2, globalPagesStart: 2, metrics: HUDMetrics(scale: 1.5)) == (8 + 8) * 1.5)
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
