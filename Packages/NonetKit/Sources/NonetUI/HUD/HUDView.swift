// 担当: ui-shell
import NonetCore
import Observation
import SwiftUI

/// HUD の寸法。標準の値（HUDLayout）に、設定の「大きく表示」の倍率を掛ける
struct HUDMetrics: Equatable {
    /// 寸法と文字に掛ける倍率（HUDModel.scale を、札がマスに収まるところまで下げたもの）
    var scale: CGFloat

    init(scale: CGFloat) {
        self.scale = scale.isFinite && scale > 0 ? scale : 1
    }

    var pillHeight: CGFloat { HUDLayout.pillHeight * scale }
    var highlightedPillHeight: CGFloat { HUDLayout.highlightedPillHeight * scale }
    var pillPadding: CGFloat { 14 * scale }
    var pillSpacing: CGFloat { 8 * scale }
    var pillFontSize: CGFloat { 15 * scale }
    var highlightedFontSize: CGFloat { 17 * scale }
    var iconSize: CGFloat { 18 * scale }
    var highlightedIconSize: CGFloat { 20 * scale }
    var titleHeight: CGFloat { HUDLayout.titleHeight * scale }
    var contextHeight: CGFloat { HUDLayout.contextHeight * scale }
    var bannerHeight: CGFloat { HUDLayout.bannerHeight * scale }
    var cancelHeight: CGFloat { HUDLayout.cancelHeight * scale }
    var cancelOffset: CGFloat { HUDLayout.cancelOffset * scale }
    var rowSpacing: CGFloat { HUDLayout.rowSpacing * scale }
    /// 題名・帯・何に対する操作かの札の幅の上限
    var rowsMaxWidth: CGFloat { HUDLayout.rowsMaxWidth * scale }
    var headerFontSize: CGFloat { 13 * scale }
    var contextFontSize: CGFloat { 12 * scale }
    var bandFontSize: CGFloat { 12 * scale }
    var peekHeight: CGFloat { 28 * scale }
    var peekFontSize: CGFloat { 11 * scale }
    var peekIconSize: CGFloat { 14 * scale }
    var chevronSize: CGFloat { 22 * scale }
    var pagingBarWidth: CGFloat { 4 * scale }
    var gridCornerRadius: CGFloat { HUDLayout.gridCornerRadius * scale }
    /// 少し長く止めるマスの進み具合の線の太さ
    var holdLineWidth: CGFloat { 2.5 * scale }
    /// 少し長く止めてから実行するマスの印（HoldBadge）の大きさ
    var badgeSize: CGFloat { 8 * scale }
    var dotSize: CGFloat { 5 * scale }
    var dotSpacing: CGFloat { 6 * scale }
    /// アプリのページとグローバルのページの点の間に、さらに空ける幅
    var pageGroupGap: CGFloat { HUDLayout.pageGroupGap * scale }
    /// 空きマスの点の大きさ
    var emptyDotSize: CGFloat { 10 * scale }

    /// 奥の帯に積む行（題名・帯・何に対する操作か）の高さの合計
    func rowsHeight(for model: HUDModel) -> CGFloat {
        var height = titleHeight
        if model.banner != nil { height += bannerHeight + rowSpacing }
        if model.context != nil { height += contextHeight + rowSpacing }
        return height
    }
}

/// HUD の標準の寸法（倍率 1）。HUD はポインタのあるディスプレイいっぱいに敷く、トラックパッドの地図:
/// 画面の縁の帯が外枠（GridInsets.cancelFrame: 左右 11%・奥 17%・手前 15%。やめる場所）、その内側が 3×3 のマスで、
/// それぞれのマスの中央にアイコンと名前の札を置く。指の位置は画面のその場所の点で出す（HUDScreenLayout）
enum HUDLayout {
    static let pillHeight: CGFloat = 38
    static let highlightedPillHeight: CGFloat = 44
    static let titleHeight: CGFloat = 30
    static let contextHeight: CGFloat = 26
    static let bannerHeight: CGFloat = 26
    static let cancelHeight: CGFloat = 28
    /// 「離すとやめる」の札の中心の、9マスの下辺からの距離（手前の帯の上のほう。Dock に重ねない）
    static let cancelOffset: CGFloat = 24
    /// 題名・帯・地図の間
    static let rowSpacing: CGFloat = 8
    static let rowsMaxWidth: CGFloat = 560
    /// 9マスの枠の角の丸み
    static let gridCornerRadius: CGFloat = 28
    static let pageGroupGap: CGFloat = 6
    /// 札の上下に残す余白。「大きく表示」の倍率はこれを残してマスに収まるところまで
    static let pillMargin: CGFloat = 8

    /// 「大きく表示」の倍率を、光らせた札がマスに収まるところまで下げる
    static func fittedScale(requested: Double, screenSize: CGSize) -> Double {
        let requested = HUDMetrics(scale: requested).scale
        let layout = HUDScreenLayout(size: screenSize)
        let room = layout.cellHeight - 2 * pillMargin
        guard room > 0, highlightedPillHeight > 0 else { return requested }
        return min(requested, room / highlightedPillHeight)
    }
}

/// 画面いっぱいの地図の枠。画面の大きさから、外枠の帯（GridInsets.cancelFrame）と9マスの枠を決める。
/// 座標は SwiftUI（左上が原点、y は下向き）。トラックパッドの奥（HUDFinger.y = 1）が画面の上
struct HUDScreenLayout: Equatable {
    var size: CGSize
    var insets = GridInsets.cancelFrame

    var bandLeft: CGFloat { size.width * insets.left }
    var bandRight: CGFloat { size.width * insets.right }
    var bandTop: CGFloat { size.height * insets.top }
    var bandBottom: CGFloat { size.height * insets.bottom }

    /// 9マスの範囲（外枠の帯の内側）
    var gridRect: CGRect {
        CGRect(x: bandLeft, y: bandTop, width: max(0, size.width - bandLeft - bandRight), height: max(0, size.height - bandTop - bandBottom))
    }

    var cellWidth: CGFloat { gridRect.width / 3 }
    var cellHeight: CGFloat { gridRect.height / 3 }

    /// index（0〜8。左上から右へ、上の段から）のマスの枠
    func cellRect(_ index: Int) -> CGRect {
        let row = CGFloat(min(max(index, 0), 8) / 3)
        let column = CGFloat(min(max(index, 0), 8) % 3)
        return CGRect(x: gridRect.minX + cellWidth * column, y: gridRect.minY + cellHeight * row, width: cellWidth, height: cellHeight)
    }

    func cellCenter(_ index: Int) -> CGPoint {
        let rect = cellRect(index)
        return CGPoint(x: rect.midX, y: rect.midY)
    }

    /// 左右の帯（9マスの段の横。角は含まない。ページを切り替える場所）
    var leftBand: CGRect { CGRect(x: 0, y: gridRect.minY, width: bandLeft, height: gridRect.height) }
    var rightBand: CGRect { CGRect(x: size.width - bandRight, y: gridRect.minY, width: bandRight, height: gridRect.height) }
    var topBand: CGRect { CGRect(x: 0, y: 0, width: size.width, height: bandTop) }
    var bottomBand: CGRect { CGRect(x: 0, y: size.height - bandBottom, width: size.width, height: bandBottom) }

    /// トラックパッドの上の指の位置を、画面の位置にする（ポインタをそこへ動かす）
    func point(for finger: HUDFinger) -> CGPoint {
        let x = min(max(finger.x, 0), 1)
        let y = min(max(finger.y, 0), 1)
        return CGPoint(x: x * size.width, y: (1 - y) * size.height)
    }
}

/// HUD の色。モックの値（#111111・#1E1E1E・#A8A8A8 など）。文字と点は WCAG の比（文字 4.5:1、点 3:1）を満たすよう明るくしてある。
/// システム設定の「コントラストを上げる」では、枠・空きマス・文字をさらに明るくする（HUDColors）
enum HUDPalette {
    static let background = Color(white: backgroundWhite)
    static let cell = Color(white: cellWhite)
    static let emptyCell = Color(white: 0x17 / 255)
    static let secondaryText = Color(white: 0x9A / 255)
    static let highlightedForeground = Color(white: 0x11 / 255)
    static let highlightedDetail = Color(white: 0x55 / 255)
    /// 少し長く止めるマスを、止め終える前に光らせる色（白く塗る前）
    static let holdingCell = Color(white: holdingCellWhite)
    static let holdingCellWhite: Double = 0x33 / 255

    static let backgroundWhite: Double = 0x11 / 255
    static let cellWhite: Double = 0x1E / 255

    static func colors(increasedContrast: Bool) -> HUDColors {
        increasedContrast ? .increased : .standard
    }

    /// 灰色どうしのコントラスト比（WCAG 2。白の量 0〜1 で渡す）
    static func contrastRatio(_ first: Double, _ second: Double) -> Double {
        let lighter = max(luminance(first), luminance(second))
        let darker = min(luminance(first), luminance(second))
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func luminance(_ white: Double) -> Double {
        white <= 0.03928 ? white / 12.92 : pow((white + 0.055) / 1.055, 2.4)
    }
}

/// 「コントラストを上げる」で変わる色。白の量（0〜1）と不透明度で持ち、比をテストで確かめる
struct HUDColors: Equatable {
    /// マスの名前とアイコン
    var cellForegroundWhite: Double
    /// マスの下のキー（⌘B など）
    var detailWhite: Double
    /// 右上の案内・ページの番号・使い始めの案内
    var secondaryTextWhite: Double
    var inactiveDotWhite: Double
    /// パネルの縁
    var borderOpacity: Double
    /// 空きマスの点線
    var emptyCellStrokeOpacity: Double
    /// 外枠（やめる場所）。ふだんは控えめな帯と縁、指が外枠にあるときは帯を明るくして縁を白くする
    var frameFillOpacity: Double
    var frameStrokeOpacity: Double
    var frameActiveFillOpacity: Double
    var frameActiveStrokeOpacity: Double
    /// 指が外枠にあるときのマスの不透明度（離しても実行しないことを見せる）
    var dimmedCellOpacity: Double

    static let standard = HUDColors(
        cellForegroundWhite: 0xA8 / 255,
        detailWhite: 0x9A / 255,
        secondaryTextWhite: 0x9A / 255,
        inactiveDotWhite: 0x77 / 255,
        borderOpacity: 0.08,
        emptyCellStrokeOpacity: 0.07,
        frameFillOpacity: 0.035,
        frameStrokeOpacity: 0.1,
        frameActiveFillOpacity: 0.13,
        frameActiveStrokeOpacity: 0.8,
        dimmedCellOpacity: 0.3
    )

    static let increased = HUDColors(
        cellForegroundWhite: 0xE0 / 255,
        detailWhite: 0xC8 / 255,
        secondaryTextWhite: 0xC8 / 255,
        inactiveDotWhite: 0x9A / 255,
        borderOpacity: 0.4,
        emptyCellStrokeOpacity: 0.45,
        frameFillOpacity: 0.07,
        frameStrokeOpacity: 0.45,
        frameActiveFillOpacity: 0.22,
        frameActiveStrokeOpacity: 1,
        // 「コントラストを上げる」では、外枠にいるときも、マスの文字を標準より読みやすく残す
        // （側面の外枠で止めてページが替わったとき、新しいページの中身を読んで、進むかどうか決められるように）
        dimmedCellOpacity: 0.45
    )

    var cellForeground: Color { Color(white: cellForegroundWhite) }
    var detail: Color { Color(white: detailWhite) }
    var secondaryText: Color { Color(white: secondaryTextWhite) }
    var inactiveDot: Color { Color(white: inactiveDotWhite) }
    var border: Color { Color.white.opacity(borderOpacity) }
    var emptyCellStroke: Color { Color.white.opacity(emptyCellStrokeOpacity) }

    func frameFill(isActive: Bool) -> Color {
        Color.white.opacity(isActive ? frameActiveFillOpacity : frameFillOpacity)
    }

    func frameStroke(isActive: Bool) -> Color {
        Color.white.opacity(isActive ? frameActiveStrokeOpacity : frameStrokeOpacity)
    }
}

/// HUD とトーストの面。macOS 26 以降は Dock と同じ Liquid Glass にし、ライト・ダークはシステムの設定に合わせる。
/// それより前の macOS では、モックどおりの暗い不透明な面（HUDPalette）にする
enum HUDSurface: Equatable, Sendable {
    case glass
    case solid

    static var current: HUDSurface {
        if #available(macOS 26, *) { return .glass }
        return .solid
    }
}

/// 面（HUDSurface）と「コントラストを上げる」に合わせた塗り。
/// ガラスでは文字や線を階層のスタイル（.primary・.secondary など）で描き、下に透ける色に合わせてシステムに読みやすくさせる
/// （「コントラストを上げる」「透明度を下げる」も、ガラスそのものはシステムが合わせる）。
/// 不透明な面では、モックの色（HUDPalette・HUDColors）をそのまま使う
struct HUDTheme {
    var surface: HUDSurface
    var colors: HUDColors = .standard
    /// ガラスのときのライト・ダーク。不透明な面はいつもダーク
    var colorScheme: ColorScheme = .dark

    var isGlass: Bool { surface == .glass }
    var isIncreased: Bool { colors == .increased }

    /// ガラスの上の文字と線の色（ダークでは白、ライトでは黒に近い色）
    private var ink: Color { colorScheme == .dark ? .white : Color(white: 0x1D / 255) }
    /// ink で塗った上に置く文字の色
    private var paper: Color { colorScheme == .dark ? Color(white: 0x11 / 255) : .white }

    var title: AnyShapeStyle { isGlass ? AnyShapeStyle(HierarchicalShapeStyle.primary) : AnyShapeStyle(Color.white) }
    var secondaryText: AnyShapeStyle { isGlass ? AnyShapeStyle(HierarchicalShapeStyle.secondary) : AnyShapeStyle(colors.secondaryText) }

    var cellFill: AnyShapeStyle { isGlass ? AnyShapeStyle(FillShapeStyle().secondary) : AnyShapeStyle(HUDPalette.cell) }
    var cellForeground: AnyShapeStyle { isGlass ? AnyShapeStyle(HierarchicalShapeStyle.primary) : AnyShapeStyle(colors.cellForeground) }
    var detail: AnyShapeStyle { isGlass ? AnyShapeStyle(HierarchicalShapeStyle.secondary) : AnyShapeStyle(colors.detail) }

    var emptyCellFill: AnyShapeStyle { isGlass ? AnyShapeStyle(FillShapeStyle().quaternary) : AnyShapeStyle(HUDPalette.emptyCell) }
    var emptyCellStroke: AnyShapeStyle {
        guard isGlass else { return AnyShapeStyle(colors.emptyCellStroke) }
        return isIncreased ? AnyShapeStyle(HierarchicalShapeStyle.secondary) : AnyShapeStyle(HierarchicalShapeStyle.tertiary)
    }
    /// 空きマスを光らせたときの縁（空きマスは塗らない）
    var emptyCellHighlight: Color { (isGlass ? ink : .white).opacity(0.85) }

    /// 光らせたマス（いま指を離すと実行する）。ダークでは白、ライトでは黒く塗って、文字を抜く
    var highlightedFill: Color { isGlass ? ink : .white }
    var highlightedForeground: Color { isGlass ? paper : HUDPalette.highlightedForeground }
    var highlightedDetail: Color { isGlass ? paper.opacity(0.65) : HUDPalette.highlightedDetail }

    /// 少し長く止めるマスを、止め終える前に光らせる塗りと文字
    var holdingFill: AnyShapeStyle { isGlass ? AnyShapeStyle(FillShapeStyle()) : AnyShapeStyle(HUDPalette.holdingCell) }
    var holdingForeground: Color { isGlass ? ink : .white }
    /// 進み具合の線
    var ring: Color { isGlass ? ink : .white }

    /// 画面に敷く膜。下の画面を少し暗くして、札と帯を浮かせる
    var film: Color {
        guard isGlass else { return Color.black.opacity(0.28) }
        return Color.black.opacity(colorScheme == .dark ? 0.22 : 0.10)
    }

    /// 外枠の帯（画面の縁。やめる場所）。ふだんは薄く、指が外枠にあるときは濃くする
    func bandFill(isActive: Bool) -> Color {
        let opacity: Double = isGlass && colorScheme == .light
            ? (isActive ? 0.32 : 0.11)
            : (isActive ? 0.20 : 0.07)
        return Color.white.opacity(isIncreased ? opacity * 1.5 : opacity)
    }

    /// 9マスの枠とマスの境目の線
    func gridLine(isActive: Bool) -> Color {
        let base = isGlass ? ink : Color.white
        return base.opacity(isIncreased ? 0.5 : isActive ? 0.35 : 0.18)
    }

    /// 外枠（やめる場所）。ふだんは控えめな帯と縁、指が外枠にあるときは帯を濃くして縁をはっきりさせる
    func frameFill(isActive: Bool) -> AnyShapeStyle {
        guard isGlass else { return AnyShapeStyle(colors.frameFill(isActive: isActive)) }
        return isActive ? AnyShapeStyle(FillShapeStyle()) : AnyShapeStyle(FillShapeStyle().quaternary)
    }

    func frameStroke(isActive: Bool) -> Color {
        guard isGlass else { return colors.frameStroke(isActive: isActive) }
        return ink.opacity(isActive ? colors.frameActiveStrokeOpacity : isIncreased ? 0.45 : 0.16)
    }

    /// トラックパッドの地図の面（パネルより少しだけ明るい）
    var mapFill: AnyShapeStyle { isGlass ? AnyShapeStyle(FillShapeStyle().quinary) : AnyShapeStyle(Color(white: 0x19 / 255)) }
    /// 隣のページがのぞくマスの面
    var peekFill: AnyShapeStyle { isGlass ? AnyShapeStyle(FillShapeStyle().tertiary) : AnyShapeStyle(Color(white: 0x2A / 255)) }
    /// 「離すとやめる」の下地と文字（下の暗くしたマスの文字が透けないよう、塗りつぶす）
    var labelFill: Color { isGlass ? paper : HUDPalette.background }
    var labelForeground: Color { isGlass ? ink : .white }

    var activeDot: Color { isGlass ? ink : .white }
    /// 選んでいないページの点。ガラスの上では、第三の階層だと明るい背景で見えなくなるので、第二の階層にする
    var inactiveDot: AnyShapeStyle { isGlass ? AnyShapeStyle(HierarchicalShapeStyle.secondary.opacity(0.7)) : AnyShapeStyle(colors.inactiveDot) }

    func bannerFill(isWarning: Bool) -> AnyShapeStyle {
        guard isGlass else { return AnyShapeStyle(Color(white: isWarning ? 0.2 : 0.15)) }
        return isWarning ? AnyShapeStyle(FillShapeStyle()) : AnyShapeStyle(FillShapeStyle().secondary)
    }

    func bannerStroke(isWarning: Bool) -> Color {
        (isGlass ? ink : .white).opacity(isWarning ? 0.25 : 0.12)
    }
}

/// HUD・トーストの面を敷く。ガラスはシステムが縁の光と影を付けるので、不透明な面だけ自分で縁と影を描く
struct HUDSurfaceBackground<S: InsettableShape>: ViewModifier {
    let surface: HUDSurface
    let shape: S
    var border: Color
    var shadowOpacity: Double
    var shadowRadius: CGFloat
    var shadowY: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if surface == .glass, #available(macOS 26, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(shape.fill(HUDPalette.background).shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, y: shadowY))
                .overlay(shape.strokeBorder(border, lineWidth: 1))
                .environment(\.colorScheme, .dark)
        }
    }
}

/// 外枠の帯。トラックパッドを表す面から、9マスの下（マスより少し広げた角丸の四角）をくり抜いた形。
/// マスの下は塗らないので、外枠の帯だけが見える（マスの間のすき間は外枠ではない）
struct HUDFrameBand: Shape {
    var cornerRadius: CGFloat
    /// くり抜く四角の、外側の縁からの距離
    var insets: EdgeInsets
    var innerCornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: rect, cornerRadius: cornerRadius, style: .continuous)
        let inner = CGRect(
            x: rect.minX + insets.leading,
            y: rect.minY + insets.top,
            width: rect.width - insets.leading - insets.trailing,
            height: rect.height - insets.top - insets.bottom
        )
        if inner.width > 0, inner.height > 0 {
            path.addRoundedRect(in: inner, cornerSize: CGSize(width: innerCornerRadius, height: innerCornerRadius), style: .continuous)
        }
        return path
    }
}

/// 表示中の HUD の中身。update のたびにここだけを書き換え、ウィンドウやホスティングビューは作り直さない
@MainActor
@Observable
final class HUDStore {
    var model: HUDModel?
    /// システム設定の「コントラストを上げる」（出すたびに読み直す）
    var increasedContrast = false
    /// システム設定の「視差効果を減らす」（出すたびに読み直す）。外枠の切り替えをアニメーションにせず、進み具合も満たしていかない
    var reduceMotion = false
    /// システム設定の「透明度を下げる」（出すたびに読み直す）。ガラスの札をやめて不透明な面にする
    var reduceTransparency = false
}

/// パネルに置く根のビュー。画面いっぱいに地図を敷く
struct HUDRootView: View {
    let store: HUDStore

    var body: some View {
        ZStack {
            if let model = store.model {
                HUDView(
                    model: model,
                    colors: HUDPalette.colors(increasedContrast: store.increasedContrast),
                    reduceMotion: store.reduceMotion,
                    reduceTransparency: store.reduceTransparency
                )
            }
        }
    }
}

/// 画面いっぱいの地図。膜の上に、外枠の帯・9マスの枠と境目・それぞれのマスの札・題名（奥の帯）・「離すとやめる」（手前の帯）。
/// 指の位置は点を描かず、実際のポインタを動かして示す（HUDWindowController.updateFinger）
struct HUDView: View {
    let model: HUDModel
    var colors: HUDColors = .standard
    var reduceMotion = false
    var reduceTransparency = false
    /// 少し長く止めるマスの進み具合を、この値（0〜1）で止めて描く（見た目の確認用）。nil なら止め始めてから duration で満たす
    var fixedHoldProgress: Double?
    var surface: HUDSurface = .current

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let layout = HUDScreenLayout(size: size)
            let metrics = HUDMetrics(scale: HUDLayout.fittedScale(requested: model.scale, screenSize: size))
            let theme = HUDTheme(surface: reduceTransparency ? .solid : surface, colors: colors, colorScheme: colorScheme)
            let inFrame = model.isFingerInFrame
            // 2本以上の指・滑らせ直すまで: 光っているマスが無く、離しても何も起きない
            let idle = model.highlightedIndex == nil && !inFrame
            ZStack(alignment: .topLeading) {
                Rectangle().fill(theme.film)
                HUDFrameBand(
                    cornerRadius: 0,
                    insets: EdgeInsets(top: layout.bandTop, leading: layout.bandLeft, bottom: layout.bandBottom, trailing: layout.bandRight),
                    innerCornerRadius: metrics.gridCornerRadius
                )
                .fill(theme.bandFill(isActive: inFrame), style: FillStyle(eoFill: true))
                HUDGridLines(layout: layout, cornerRadius: metrics.gridCornerRadius)
                    .stroke(theme.gridLine(isActive: inFrame), lineWidth: 1)
                sideBand(.left, layout: layout, metrics: metrics, theme: theme)
                sideBand(.right, layout: layout, metrics: metrics, theme: theme)
                ForEach(0..<Page.cellCount, id: \.self) { index in
                    HUDCellPill(
                        cell: cell(at: index),
                        isHighlighted: model.highlightedIndex == index,
                        isOnBoundary: model.highlightedIndex == index && model.isHighlightOnBoundary,
                        index: index,
                        metrics: metrics,
                        theme: theme,
                        hold: model.hold?.cellIndex == index && model.highlightedIndex == index ? model.hold : nil,
                        reduceMotion: reduceMotion,
                        fixedHoldProgress: fixedHoldProgress,
                        maxWidth: layout.cellWidth - 2 * HUDLayout.pillMargin
                    )
                    .opacity(inFrame || idle ? colors.dimmedCellOpacity : 1)
                    .position(layout.cellCenter(index))
                }
                topRows(layout: layout, metrics: metrics, theme: theme)
                HUDCancelPill(model: model, isActive: inFrame, metrics: metrics, theme: theme)
                    .position(x: size.width / 2, y: layout.gridRect.maxY + metrics.cancelOffset)
            }
            .frame(width: size.width, height: size.height)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: inFrame)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(model.title))
    }

    /// 奥の帯の中央に積む行: 題名（右にページの点か「練習中」）・帯（試用期間）・何に対する操作か
    private func topRows(layout: HUDScreenLayout, metrics: HUDMetrics, theme: HUDTheme) -> some View {
        let height = metrics.rowsHeight(for: model)
        let width = min(layout.gridRect.width, metrics.rowsMaxWidth)
        return VStack(spacing: metrics.rowSpacing) {
            HUDTitlePill(model: model, metrics: metrics, theme: theme)
            if let banner = model.banner {
                HUDBannerView(text: banner, style: model.bannerStyle, metrics: metrics, theme: theme)
            }
            if let context = model.context {
                HUDContextPill(text: context, metrics: metrics, theme: theme)
            }
        }
        .frame(width: width, height: height)
        .position(x: layout.size.width / 2, y: max(layout.bandTop / 2, height / 2 + metrics.rowSpacing))
    }

    /// 左右の帯。そちらにページがあれば印（‹ ›）。指を止めている間は進み具合の線と、隣のページの端の列
    @ViewBuilder
    private func sideBand(_ edge: PageEdge, layout: HUDScreenLayout, metrics: HUDMetrics, theme: HUDTheme) -> some View {
        let band = edge == .left ? layout.leftBand : layout.rightBand
        let hasPage = edge == .left ? model.pageIndex > 0 : model.pageIndex < model.pageCount - 1
        let paging = model.edgePaging?.edge == edge ? model.edgePaging : nil
        ZStack(alignment: .topLeading) {
            if let paging, !reduceMotion {
                // 「視差効果を減らす」では出さない（伸びない線は、最初から「済んだ」ように見える。文は「離すとやめる」の横に出る）
                let inset = 6 * metrics.scale
                HUDEdgePagingBar(paging: paging, color: theme.ring, animates: !reduceMotion)
                    .id(HUDEdgePagingBar.restartID(for: paging))
                    .frame(width: metrics.pagingBarWidth, height: band.height - 2 * metrics.gridCornerRadius)
                    .position(x: edge == .left ? band.width - inset : inset, y: band.height / 2)
            }
            if paging != nil, let peek = model.edgePeek {
                ForEach(0..<3, id: \.self) { row in
                    HUDPeekPill(cell: row < peek.count ? peek[row] : nil, metrics: metrics, theme: theme, maxWidth: band.width - 2 * HUDLayout.pillMargin)
                        .position(x: band.width / 2, y: layout.cellCenter(row * 3).y - band.minY)
                }
                .transition(.opacity)
            } else if hasPage {
                Image(systemName: edge == .left ? "chevron.left" : "chevron.right")
                    .font(.system(size: metrics.chevronSize, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
                    .opacity(0.7)
                    .position(x: band.width / 2, y: band.height / 2)
            }
        }
        .frame(width: band.width, height: band.height)
        .position(x: band.midX, y: band.midY)
        .accessibilityHidden(true)
    }

    private func cell(at index: Int) -> HUDCell? {
        model.cells.indices.contains(index) ? model.cells[index] : nil
    }
}

/// 9マスの枠（角丸）と、マスの境目の線
struct HUDGridLines: Shape {
    var layout: HUDScreenLayout
    var cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let grid = layout.gridRect
        var path = Path(roundedRect: grid, cornerRadius: min(cornerRadius, grid.width / 2, grid.height / 2), style: .continuous)
        for k in 1...2 {
            let x = grid.minX + layout.cellWidth * CGFloat(k)
            path.move(to: CGPoint(x: x, y: grid.minY))
            path.addLine(to: CGPoint(x: x, y: grid.maxY))
            let y = grid.minY + layout.cellHeight * CGFloat(k)
            path.move(to: CGPoint(x: grid.minX, y: y))
            path.addLine(to: CGPoint(x: grid.maxX, y: y))
        }
        return path
    }
}

/// 札の面。ガラス（macOS 26）か、不透明な暗い面。fill を渡すとその色で塗る（光らせた札）
private struct HUDPillBackground: ViewModifier {
    let theme: HUDTheme
    var fill: AnyShapeStyle?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let fill {
            content.background(Capsule().fill(fill))
        } else {
            content.modifier(HUDSurfaceBackground(
                surface: theme.surface,
                shape: Capsule(),
                border: theme.colors.border,
                shadowOpacity: 0.3,
                shadowRadius: 8,
                shadowY: 3
            ))
        }
    }
}

/// 題名の札。左に題名、右にページの点（練習中は「練習中」）
private struct HUDTitlePill: View {
    let model: HUDModel
    let metrics: HUDMetrics
    let theme: HUDTheme

    var body: some View {
        HStack(spacing: 10 * metrics.scale) {
            Text(model.title)
                .foregroundStyle(theme.title)
                .fontWeight(.semibold)
                .lineLimit(1)
                .truncationMode(.tail)
            if let note = HUDAnnouncement.topNote(for: model) {
                Text(note)
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
                    .layoutPriority(1)
            } else if model.pageCount > 1 {
                HUDPageIndicator(
                    pageIndex: model.pageIndex,
                    pageCount: model.pageCount,
                    globalPagesStart: model.globalPagesStart,
                    metrics: metrics,
                    theme: theme
                )
            }
        }
        .font(.system(size: metrics.headerFontSize))
        .padding(.horizontal, metrics.pillPadding)
        .frame(height: metrics.titleHeight)
        .modifier(HUDPillBackground(theme: theme))
        .accessibilityElement(children: .combine)
    }
}

/// 何に対する操作かの札（「Safari のウインドウ」など）
private struct HUDContextPill: View {
    let text: String
    let metrics: HUDMetrics
    let theme: HUDTheme

    var body: some View {
        Text(text)
            .font(.system(size: metrics.contextFontSize))
            .foregroundStyle(theme.secondaryText)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 12 * metrics.scale)
            .frame(height: metrics.contextHeight)
            .modifier(HUDPillBackground(theme: theme))
            .accessibilityLabel(Text(text))
    }
}

/// 手前の帯の「✕ 離すとやめる」。指が外枠にあるときは塗ってはっきり出し、ページを切り替えられるならその案内も添える
private struct HUDCancelPill: View {
    let model: HUDModel
    let isActive: Bool
    let metrics: HUDMetrics
    let theme: HUDTheme

    var body: some View {
        HStack(spacing: 5 * metrics.scale) {
            Image(systemName: "xmark")
                .font(.system(size: 9 * metrics.scale, weight: .bold))
                .accessibilityHidden(true)
            Text(HUDAnnouncement.cancelLabel)
                .lineLimit(1)
            if isActive, let edge = model.edgePaging?.edge {
                Text(verbatim: "·")
                    .opacity(0.6)
                HStack(spacing: 2 * metrics.scale) {
                    if edge == .left {
                        Image(systemName: "chevron.left").accessibilityHidden(true)
                    }
                    Text(HUDAnnouncement.edgePagingLabel(edge))
                        .lineLimit(1)
                    if edge == .right {
                        Image(systemName: "chevron.right").accessibilityHidden(true)
                    }
                }
            }
        }
        .font(.system(size: metrics.bandFontSize, weight: isActive ? .semibold : .regular))
        .foregroundStyle(isActive ? AnyShapeStyle(theme.highlightedForeground) : theme.secondaryText)
        .padding(.horizontal, 12 * metrics.scale)
        .frame(height: metrics.cancelHeight)
        .modifier(HUDPillBackground(theme: theme, fill: isActive ? AnyShapeStyle(theme.highlightedFill) : nil))
        .accessibilityElement(children: .combine)
    }
}

/// 隣のページの端のマス（左右の帯の中にのぞかせる）。小さな札にアイコンと名前
private struct HUDPeekPill: View {
    let cell: HUDCell?
    let metrics: HUDMetrics
    let theme: HUDTheme
    let maxWidth: CGFloat

    var body: some View {
        Group {
            if let cell {
                HStack(spacing: 5 * metrics.scale) {
                    CellIconView(cell.icon, size: metrics.peekIconSize)
                    Text(cell.title)
                        .font(.system(size: metrics.peekFontSize, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .foregroundStyle(theme.cellForeground)
                .padding(.horizontal, 9 * metrics.scale)
                .frame(height: metrics.peekHeight)
                .frame(maxWidth: maxWidth)
                .fixedSize(horizontal: true, vertical: false)
                .modifier(HUDPillBackground(theme: theme, fill: theme.peekFill))
            } else {
                Circle()
                    .fill(theme.emptyCellFill)
                    .frame(width: metrics.emptyDotSize, height: metrics.emptyDotSize)
            }
        }
        .opacity(0.8)
    }
}

/// マスの札。アイコンと名前（押すキーは出さない。読み上げには入る）。空きマスは薄い点だけで、光らせたときは「空きマス」の枠だけの札
struct HUDCellPill: View {
    let cell: HUDCell?
    let isHighlighted: Bool
    /// 指が境目の線の上にあり、いま離しても実行しない。塗らずに、空きマスと同じ枠だけで示す
    var isOnBoundary = false
    let index: Int
    var metrics = HUDMetrics(scale: 1)
    var theme = HUDTheme(surface: .solid)
    /// 光っている、少し長く止めるマスの進み具合。止め終えるまでは塗らず、縁に沿って線を伸ばす
    var hold: HUDHold?
    var reduceMotion = false
    var fixedHoldProgress: Double?
    var maxWidth: CGFloat = .infinity

    /// 塗る（いま指を離すと実行する）。少し長く止めるマスは止め終えてから。境目の線の上では塗らない
    private var isFilled: Bool {
        isHighlighted && !isOnBoundary && (hold?.isReady ?? true)
    }

    /// 少し長く止めるマスを止めている途中
    private var isHolding: Bool {
        isHighlighted && hold?.isReady == false
    }

    var body: some View {
        let height = isHighlighted ? metrics.highlightedPillHeight : metrics.pillHeight
        Group {
            if let cell {
                HStack(spacing: metrics.pillSpacing) {
                    CellIconView(cell.icon, size: isHighlighted ? metrics.highlightedIconSize : metrics.iconSize)
                    Text(cell.title)
                        .font(.system(size: isHighlighted ? metrics.highlightedFontSize : metrics.pillFontSize, weight: isHighlighted ? .bold : .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .truncationMode(.tail)
                    if cell.requiresHold {
                        HoldBadge(size: metrics.badgeSize, style: isFilled ? AnyShapeStyle(theme.highlightedDetail) : isHolding ? AnyShapeStyle(theme.holdingForeground) : theme.detail)
                    }
                }
                .padding(.horizontal, metrics.pillPadding)
                .frame(height: height)
                .frame(maxWidth: maxWidth)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(isFilled ? AnyShapeStyle(theme.highlightedForeground) : isHolding ? AnyShapeStyle(theme.holdingForeground) : theme.cellForeground)
                .modifier(HUDPillBackground(theme: theme, fill: isFilled ? AnyShapeStyle(theme.highlightedFill) : isHolding ? theme.holdingFill : nil))
                .overlay {
                    if isHighlighted, isOnBoundary, !isHolding {
                        // 離しても実行しない。空きマスを指したときと同じ枠で示す（塗り＝離すと実行、と食い違わない）
                        Capsule().strokeBorder(theme.emptyCellHighlight, lineWidth: 1.5)
                    }
                }
                .overlay {
                    if isHolding, let hold {
                        HUDHoldRing(
                            hold: hold,
                            cornerRadius: height / 2,
                            lineWidth: metrics.holdLineWidth,
                            color: theme.ring,
                            animates: !reduceMotion,
                            fixedProgress: fixedHoldProgress
                        )
                    }
                }
            } else if isHighlighted {
                // 空きマスは実行しても何も起きないので、塗らずに枠だけで示す
                Text(HUDAnnouncement.emptyCellLabel)
                    .font(.system(size: metrics.pillFontSize, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
                    .padding(.horizontal, metrics.pillPadding)
                    .frame(height: metrics.pillHeight)
                    .overlay(Capsule().strokeBorder(theme.emptyCellHighlight, lineWidth: 1.5))
            } else {
                // 空きマスは、薄い点だけ
                Circle()
                    .fill(theme.emptyCellFill)
                    .frame(width: metrics.emptyDotSize, height: metrics.emptyDotSize)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(HUDAnnouncement.cellDescription(cell, index: index)))
        .accessibilityValue(Text(HUDAnnouncement.cellValue(cell)))
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
    }
}

/// 少し長く止めるマスの進み具合。マスの縁に沿って白い線を伸ばし、一周したら（HUDHold.isReady）マスが白くなる。
/// 「視差効果を減らす」では線を伸ばさず、縁を点線で囲むだけにする（止め終えたら白くなるのは同じ）
struct HUDHoldRing: View {
    let hold: HUDHold
    let cornerRadius: CGFloat
    let lineWidth: CGFloat
    var color = Color.white
    let animates: Bool
    let fixedProgress: Double?
    @State private var progress: CGFloat = 0

    var body: some View {
        let ring = HUDHoldRingShape(cornerRadius: cornerRadius, inset: lineWidth / 2)
        ZStack {
            if let fixedProgress {
                ring.stroke(color.opacity(0.2), lineWidth: lineWidth)
                ring.trim(from: 0, to: CGFloat(min(max(fixedProgress, 0), 1)))
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            } else if animates {
                ring.stroke(color.opacity(0.2), lineWidth: lineWidth)
                ring.trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            } else {
                ring.stroke(color.opacity(0.7), style: StrokeStyle(lineWidth: lineWidth * 0.6, dash: [lineWidth * 1.5, lineWidth * 1.5]))
            }
        }
        .onAppear { start() }
        .onChange(of: hold.since) { start() }
        .accessibilityHidden(true)
    }

    /// 止め始めた（このマスになった・滑らせ直した）ところから、duration で一周させる
    private func start() {
        guard animates, fixedProgress == nil else { return }
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) { progress = 0 }
        withAnimation(.linear(duration: max(hold.duration, 0))) { progress = 1 }
    }
}

/// マスの縁をなぞる線。上の辺の中ほどから時計回りに一周する（進み具合が時計の針と同じ向きに伸びる）
struct HUDHoldRingShape: Shape {
    var cornerRadius: CGFloat
    /// 線の太さの半分だけ内側を通る（マスの外にはみ出さない）
    var inset: CGFloat

    func path(in rect: CGRect) -> Path {
        let box = rect.insetBy(dx: inset, dy: inset)
        let radius = max(0, min(cornerRadius - inset, box.width / 2, box.height / 2))
        var path = Path()
        path.move(to: CGPoint(x: box.midX, y: box.minY))
        path.addLine(to: CGPoint(x: box.maxX - radius, y: box.minY))
        path.addArc(center: CGPoint(x: box.maxX - radius, y: box.minY + radius), radius: radius, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: box.maxX, y: box.maxY - radius))
        path.addArc(center: CGPoint(x: box.maxX - radius, y: box.maxY - radius), radius: radius, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: box.minX + radius, y: box.maxY))
        path.addArc(center: CGPoint(x: box.minX + radius, y: box.maxY - radius), radius: radius, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: box.minX, y: box.minY + radius))
        path.addArc(center: CGPoint(x: box.minX + radius, y: box.minY + radius), radius: radius, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        return path
    }
}

/// 左右の外枠に指を止めている間、ページを切り替えるまでの進み具合。外枠の帯の中で、縦長の線を中ほどから上下へ伸ばす。
/// 「視差効果を減らす」では出さない（HUDView.pad）。animates が false のときの線は、見た目の確認用の静止画
struct HUDEdgePagingBar: View {
    let paging: HUDEdgePaging
    var color = Color.white
    let animates: Bool
    /// この線を作った（止め始めた）時刻。呼び出し側が止め始めるたびに id を変えて作り直すので、そのたびに最初から数える
    @State private var startedAt = Date()

    var body: some View {
        TimelineView(.animation(paused: !animates)) { context in
            ZStack {
                Capsule().fill(color.opacity(0.2))
                if animates {
                    Capsule().fill(color)
                        .scaleEffect(x: 1, y: Self.progress(elapsed: context.date.timeIntervalSince(startedAt), duration: paging.duration), anchor: .center)
                } else {
                    Capsule().fill(color.opacity(0.6))
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// 止め始めてから elapsed 秒たったときの進み具合（0〜1）。duration が0以下なら、最初から満ちている
    static func progress(elapsed: TimeInterval, duration: TimeInterval) -> CGFloat {
        guard duration.isFinite, elapsed.isFinite else { return 0 }
        guard duration > 0 else { return 1 }
        return CGFloat(min(max(elapsed / duration, 0), 1))
    }

    /// 線を作り直す目印。反対側に移ったときと、ページを切り替えて数え直すとき（since が変わる）に変わる。
    /// 状態を0に戻してからアニメーションで1にする書き方だと、同じ更新の中で0への書き込みが消え、満ちたまま残る
    static func restartID(for paging: HUDEdgePaging) -> String {
        "\(paging.edge)-\(paging.since)"
    }
}

private struct HUDBannerView: View {
    let text: String
    let style: HUDBannerStyle
    let metrics: HUDMetrics
    let theme: HUDTheme

    var body: some View {
        HStack(spacing: 6 * metrics.scale) {
            Image(systemName: style == .warning ? "exclamationmark.triangle.fill" : "clock")
            Text(text)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .font(.system(size: metrics.headerFontSize, weight: .medium))
        .foregroundStyle(theme.title)
        .frame(maxWidth: .infinity)
        .frame(height: metrics.bannerHeight)
        .background(RoundedRectangle(cornerRadius: 8 * metrics.scale, style: .continuous).fill(theme.bannerFill(isWarning: style == .warning)))
        .overlay(
            RoundedRectangle(cornerRadius: 8 * metrics.scale, style: .continuous)
                .strokeBorder(theme.bannerStroke(isWarning: style == .warning), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

/// ページの点。アプリのページの後ろにグローバルのページをつなげたときは、その境目を少し離す
private struct HUDPageIndicator: View {
    let pageIndex: Int
    let pageCount: Int
    let globalPagesStart: Int?
    let metrics: HUDMetrics
    let theme: HUDTheme

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<pageCount, id: \.self) { page in
                Circle()
                    .fill(page == pageIndex ? AnyShapeStyle(theme.activeDot) : theme.inactiveDot)
                    .frame(width: metrics.dotSize, height: metrics.dotSize)
                    .padding(.leading, HUDPageDots.leadingSpace(before: page, globalPagesStart: globalPagesStart, metrics: metrics))
            }
        }
        // 見るのは点だけ（「1 / 3」を並べると同じことを2回言う）。何ページ目かは VoiceOver の値で読む
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("ページ", bundle: .module))
        .accessibilityValue(Text(HUDAnnouncement.pageDescription(pageIndex: pageIndex, pageCount: pageCount)))
    }
}

/// ページの点の並べ方
enum HUDPageDots {
    /// page 番目の点の前に空ける幅。グローバルの最初のページの前は pageGroupGap だけ広い
    static func leadingSpace(before page: Int, globalPagesStart: Int?, metrics: HUDMetrics) -> CGFloat {
        guard page > 0 else { return 0 }
        return page == globalPagesStart ? metrics.dotSpacing + metrics.pageGroupGap : metrics.dotSpacing
    }
}

/// VoiceOver に読ませる文
enum HUDAnnouncement {
    /// マスの位置の呼び方（左上から右へ、上の行から）
    static func positionName(_ index: Int) -> String {
        switch index {
        case 0: String(localized: "左上", bundle: .module)
        case 1: String(localized: "上", bundle: .module)
        case 2: String(localized: "右上", bundle: .module)
        case 3: String(localized: "左", bundle: .module)
        case 4: String(localized: "中央", bundle: .module)
        case 5: String(localized: "右", bundle: .module)
        case 6: String(localized: "左下", bundle: .module)
        case 7: String(localized: "下", bundle: .module)
        case 8: String(localized: "右下", bundle: .module)
        default: ""
        }
    }

    /// 名詞の前に置くときの位置の呼び方（英語では「top-right corner」のようにハイフンでつなぐ）。
    /// 角の4つだけ別の訳が要る。ほかは positionName と同じ
    static func attributivePositionName(_ index: Int) -> String {
        switch index {
        case 0: String(localized: "attributivePosition.topLeft", defaultValue: "左上", bundle: .module)
        case 2: String(localized: "attributivePosition.topRight", defaultValue: "右上", bundle: .module)
        case 6: String(localized: "attributivePosition.bottomLeft", defaultValue: "左下", bundle: .module)
        case 8: String(localized: "attributivePosition.bottomRight", defaultValue: "右下", bundle: .module)
        default: positionName(index)
        }
    }

    static func pageDescription(pageIndex: Int, pageCount: Int) -> String {
        String(localized: "\(pageCount) ページ中 \(pageIndex + 1) ページ目", bundle: .module)
    }

    static func cellDescription(_ cell: HUDCell?, index: Int) -> String {
        let position = positionName(index)
        guard let cell else {
            return String(localized: "空きマス、\(position)", bundle: .module)
        }
        if let detail = cell.detail, !detail.isEmpty {
            return String(localized: "\(cell.title)、\(detail)、\(position)", bundle: .module)
        }
        return String(localized: "\(cell.title)、\(position)", bundle: .module)
    }

    /// マスの VoiceOver の値。少し長く止めてから実行するマスなら、それを言う
    static func cellValue(_ cell: HUDCell?) -> String {
        HoldMark.accessibilityValue(requiresHold: cell?.requiresHold == true)
    }

    /// 光らせた空きマスの札の文
    static var emptyCellLabel: String {
        String(localized: "空きマス", bundle: .module)
    }

    /// 指が外枠にあるときの「離すとやめる」（手前の帯の札と読み上げ）
    static var cancelLabel: String {
        String(localized: "離すとやめる", bundle: .module)
    }

    /// 左右の外枠に指を止めているときに「離すとやめる」に添える文
    static func edgePagingLabel(_ edge: PageEdge) -> String {
        switch edge {
        case .left: String(localized: "止めると前のページ", bundle: .module)
        case .right: String(localized: "止めると次のページ", bundle: .module)
        }
    }

    /// 指が外枠にあるときに読む文。左右の外枠でそちらにページがあれば、止めるとページが変わることも言う
    static func frameLabel(in model: HUDModel) -> String {
        guard let edge = model.edgePaging?.edge else { return cancelLabel }
        return [cancelLabel, edgePagingLabel(edge)].joined(separator: String(localized: "、", bundle: .module))
    }

    /// HUD の左上の題名の右に出す一言。練習中だけ「練習中」。無ければ nil（ページの点を出す）。
    /// 少し長く止めるマスの進み具合は、マスの縁の輪が見せる（文は VoiceOver にだけ読む）
    static func topNote(for model: HUDModel) -> String? {
        model.isPractice ? String(localized: "練習中", bundle: .module) : nil
    }

    /// 少し長く止めるマスを止めている途中（VoiceOver）
    static var holdWaiting: String {
        String(localized: "そのまま止めて待つ", bundle: .module)
    }

    /// 少し長く止めるマスを止め終えたとき（VoiceOver）
    static var holdReady: String {
        String(localized: "離すと実行", bundle: .module)
    }

    /// ハイライト中のマス。指が外枠にある・離れていれば nil。少し長く止めてから実行するマスなら、そう言い添える
    static func highlighted(in model: HUDModel) -> String? {
        guard let index = model.highlightedIndex, (0..<Page.cellCount).contains(index) else { return nil }
        let cell = model.cells.indices.contains(index) ? model.cells[index] : nil
        let description = cellDescription(cell, index: index)
        guard cell?.requiresHold == true else { return description }
        return String(localized: "\(description)、\(HoldMark.accessibilityValue)", bundle: .module)
    }

    /// 前の表示から読み上げる内容が変わったときだけ文を返す（同じ文を何度も読ませない）。
    /// 外枠に入ったら「離すとやめる」、少し長く止めるマスを止め終えたら「離すと実行」
    static func announcement(from previous: HUDModel?, to model: HUDModel) -> String? {
        let isNewPage = previous == nil || previous?.pageIndex != model.pageIndex || previous?.title != model.title
        let current = model.isFingerInFrame ? frameLabel(in: model) : highlighted(in: model)
        if !isNewPage, let hold = model.hold, hold.isReady, previous?.hold?.isReady != true, previous?.highlightedIndex == model.highlightedIndex {
            return holdReady
        }
        if isNewPage {
            let page = model.pageCount > 1
                ? String(localized: "\(model.title)、\(pageDescription(pageIndex: model.pageIndex, pageCount: model.pageCount))", bundle: .module)
                : model.title
            return [page, current].compactMap { $0 }.joined(separator: String(localized: "、", bundle: .module))
        }
        let before = previous.flatMap { $0.isFingerInFrame ? frameLabel(in: $0) : highlighted(in: $0) }
        guard before != current else { return nil }
        return current
    }
}
