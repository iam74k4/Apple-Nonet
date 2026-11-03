// 担当: ui-shell
import NonetCore
import Observation
import SwiftUI

/// HUD の寸法。標準の値（HUDLayout）に、設定の「HUD の大きさ」の倍率を掛ける
struct HUDMetrics: Equatable {
    /// 寸法と文字に掛ける倍率（HUDModel.scale）
    var scale: CGFloat

    init(scale: CGFloat) {
        self.scale = scale.isFinite && scale > 0 ? scale : 1
    }

    var width: CGFloat { HUDLayout.width * scale }
    var cellSpacing: CGFloat { HUDLayout.cellSpacing * scale }
    var cellHeight: CGFloat { HUDLayout.cellHeight * scale }
    var cornerRadius: CGFloat { HUDLayout.cornerRadius * scale }
    var cellCornerRadius: CGFloat { HUDLayout.cellCornerRadius * scale }
    var bannerHeight: CGFloat { HUDLayout.bannerHeight * scale }
    var bannerSpacing: CGFloat { HUDLayout.bannerSpacing * scale }
    var frameSide: CGFloat { HUDLayout.frameSide * scale }
    var frameTop: CGFloat { HUDLayout.frameTop * scale }
    var frameBottom: CGFloat { HUDLayout.frameBottom * scale }
    /// 少し長く止めるマスの進み具合の線の太さ
    var holdLineWidth: CGFloat { 2.5 * scale }
    var headerFontSize: CGFloat { 12 * scale }
    var cellTitleFontSize: CGFloat { 12 * scale }
    var detailFontSize: CGFloat { 11 * scale }
    var iconSize: CGFloat { 18 * scale }
    /// 少し長く止めてから実行するマスの印（HoldBadge）の大きさと、マスの角からの距離
    var badgeSize: CGFloat { 8 * scale }
    var badgeInset: CGFloat { 6 * scale }
    var dotSize: CGFloat { 5 * scale }
    var dotSpacing: CGFloat { 6 * scale }
    /// アプリのページとグローバルのページの点の間に、さらに空ける幅
    var pageGroupGap: CGFloat { HUDLayout.pageGroupGap * scale }

    /// 9マスの上と下の、外枠の幅（帯・案内の分を含む）。上は題名とページの点が並び、下は使い始めの案内が入る
    func gridInsets(for model: HUDModel) -> (top: CGFloat, bottom: CGFloat) {
        var top = HUDLayout.frameTop
        if model.banner != nil {
            top += HUDLayout.bannerHeight + HUDLayout.bannerSpacing
        }
        return (top * scale, HUDLayout.frameBottom * scale)
    }

    /// 左右の外枠に出す進み具合の線の、上と下の余白。9マスの高さに合わせる（上と下で外枠の幅が違うので、同じ値にはしない）
    func pagingBarInsets(for model: HUDModel) -> (top: CGFloat, bottom: CGFloat) {
        let insets = gridInsets(for: model)
        return (insets.top + cellCornerRadius, insets.bottom + cellCornerRadius)
    }

    func size(for model: HUDModel) -> CGSize {
        let insets = gridInsets(for: model)
        let grid = 3 * cellHeight + 2 * cellSpacing
        return CGSize(width: HUDLayout.width * scale, height: insets.top + grid + insets.bottom)
    }
}

/// HUD の標準の寸法（倍率 1）。パネルそのものがトラックパッドを表し、9マスの周りの余白が外枠（指を出して離すと何もせずに閉じる場所）になる。
/// 外枠は、ふだんは描かず、指がそこにあるときだけ濃くして見せる
enum HUDLayout {
    static let width: CGFloat = 368
    static let cellHeight: CGFloat = 54
    static let cellSpacing: CGFloat = 6
    /// パネルの角の丸み。Dock のような丸い面にする
    static let cornerRadius: CGFloat = 22
    static let cellCornerRadius: CGFloat = 10
    static let bannerHeight: CGFloat = 24
    static let bannerSpacing: CGFloat = 6
    static let pageGroupGap: CGFloat = 6
    /// 外枠の幅。トラックパッドの割合（左右 11%・奥 17%・手前 15%）の順を保つ（奥が最も広く、題名とページの点が入る）。
    /// 割合どおりにするとマスが細くなりすぎるので、帯は控えめにする
    static let frameSide: CGFloat = 12
    static let frameTop: CGFloat = 28
    static let frameBottom: CGFloat = 12
    /// 外枠を濃くするとき、9マスの下の塗らない部分を、マスより外へ広げる幅（外枠の帯とマスの間に少しすき間を空ける）
    static let gridWell: CGFloat = 3
    /// パネルの影を SwiftUI で描くための余白。ウィンドウの影は中身が変わると遅れて付くので使わない
    static let shadowMargin: CGFloat = 28

    /// model.scale の倍率を掛けた大きさ
    static func size(for model: HUDModel) -> CGSize {
        HUDMetrics(scale: model.scale).size(for: model)
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

    /// 外枠（やめる場所）。ふだんは控えめな帯と縁、指が外枠にあるときは帯を濃くして縁をはっきりさせる
    func frameFill(isActive: Bool) -> AnyShapeStyle {
        guard isGlass else { return AnyShapeStyle(colors.frameFill(isActive: isActive)) }
        return isActive ? AnyShapeStyle(FillShapeStyle()) : AnyShapeStyle(FillShapeStyle().quaternary)
    }

    func frameStroke(isActive: Bool) -> Color {
        guard isGlass else { return colors.frameStroke(isActive: isActive) }
        return ink.opacity(isActive ? colors.frameActiveStrokeOpacity : isIncreased ? 0.45 : 0.16)
    }

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
}

/// パネルに置く根のビュー。影の余白の中に HUD を描く
struct HUDRootView: View {
    let store: HUDStore

    var body: some View {
        ZStack {
            if let model = store.model {
                HUDView(model: model, colors: HUDPalette.colors(increasedContrast: store.increasedContrast), reduceMotion: store.reduceMotion)
            }
        }
        .padding(HUDLayout.shadowMargin)
    }
}

struct HUDView: View {
    let model: HUDModel
    var colors: HUDColors = .standard
    var reduceMotion = false
    /// 少し長く止めるマスの進み具合を、この値（0〜1）で止めて描く（見た目の確認用）。nil なら止め始めてから duration で満たす
    var fixedHoldProgress: Double?
    var surface: HUDSurface = .current

    @Environment(\.colorScheme) private var colorScheme

    private var metrics: HUDMetrics { HUDMetrics(scale: model.scale) }
    private var theme: HUDTheme { HUDTheme(surface: surface, colors: colors, colorScheme: colorScheme) }

    var body: some View {
        let metrics = metrics
        let theme = theme
        let size = metrics.size(for: model)
        let insets = metrics.gridInsets(for: model)
        let inFrame = model.isFingerInFrame
        let shape = RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
        ZStack(alignment: .top) {
            if inFrame {
                // 指が外枠にあるときだけ、外枠（パネルの縁と9マスの間）を濃くして縁をはっきりさせる
                frameBand(size: size, insets: insets)
            }
            VStack(spacing: 0) {
                topBar
                    .frame(height: HUDLayout.frameTop * metrics.scale)
                if let banner = model.banner {
                    HUDBannerView(text: banner, style: model.bannerStyle, metrics: metrics, theme: theme)
                        .padding(.horizontal, metrics.frameSide)
                        .padding(.bottom, metrics.bannerSpacing)
                }
                grid
                    .padding(.horizontal, metrics.frameSide)
                    .opacity(inFrame ? colors.dimmedCellOpacity : 1)
                Spacer(minLength: 0)
            }
            if inFrame, let paging = model.edgePaging, !reduceMotion {
                // 指を止めている側の外枠に、ページを切り替えるまでの進み具合。
                // 「視差効果を減らす」では出さない（伸びない線は、最初から「済んだ」ように見える。文は「離すとやめる」の下に出る）
                let bar = metrics.pagingBarInsets(for: model)
                HUDEdgePagingBar(paging: paging, color: theme.ring, animates: !reduceMotion)
                    // 止め始めるたび（反対側に移った・ページを切り替えた）に作り直して、最初から伸ばす
                    .id(HUDEdgePagingBar.restartID(for: paging))
                    .frame(width: max(metrics.frameSide - 6 * metrics.scale, 3 * metrics.scale))
                    .padding(.top, bar.top)
                    .padding(.bottom, bar.bottom)
                    .padding(.horizontal, 3 * metrics.scale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: paging.edge == .left ? .leading : .trailing)
            }
            if inFrame {
                HUDCancelLabel(metrics: metrics, theme: theme, edge: model.edgePaging?.edge)
                    .position(x: size.width / 2, y: insets.top + (3 * metrics.cellHeight + 2 * metrics.cellSpacing) / 2)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: inFrame)
        .modifier(HUDSurfaceBackground(
            surface: surface,
            shape: shape,
            border: colors.border,
            shadowOpacity: 0.35,
            shadowRadius: 18,
            shadowY: 8
        ))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(model.title))
    }

    /// 上の外枠。左に題名、右にページの点（少し長く止めるマスを止めている間は、その案内。練習中は「練習中」）
    private var topBar: some View {
        HStack(spacing: 10 * metrics.scale) {
            Text(model.title)
                .foregroundStyle(theme.title)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
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
        .padding(.horizontal, metrics.frameSide + 2 * metrics.scale)
    }

    /// 外枠（パネルの縁と9マスの間）を濃くした帯と、その縁
    private func frameBand(size: CGSize, insets: (top: CGFloat, bottom: CGFloat)) -> some View {
        let well = HUDLayout.gridWell * metrics.scale
        let band = HUDFrameBand(
            cornerRadius: metrics.cornerRadius,
            insets: EdgeInsets(
                top: insets.top - well,
                leading: metrics.frameSide - well,
                bottom: insets.bottom - well,
                trailing: metrics.frameSide - well
            ),
            innerCornerRadius: metrics.cellCornerRadius + well
        )
        return ZStack {
            band.fill(theme.frameFill(isActive: true), style: FillStyle(eoFill: true))
            RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                .strokeBorder(theme.frameStroke(isActive: true), lineWidth: 1.5 * metrics.scale)
        }
        .frame(width: size.width, height: size.height)
    }

    private var grid: some View {
        Grid(horizontalSpacing: metrics.cellSpacing, verticalSpacing: metrics.cellSpacing) {
            ForEach(0..<3, id: \.self) { row in
                GridRow {
                    ForEach(0..<3, id: \.self) { column in
                        let index = row * 3 + column
                        HUDCellView(
                            cell: cell(at: index),
                            isHighlighted: model.highlightedIndex == index,
                            isOnBoundary: model.highlightedIndex == index && model.isHighlightOnBoundary,
                            index: index,
                            metrics: metrics,
                            theme: theme,
                            hold: model.hold?.cellIndex == index && model.highlightedIndex == index ? model.hold : nil,
                            reduceMotion: reduceMotion,
                            fixedHoldProgress: fixedHoldProgress
                        )
                    }
                }
            }
        }
    }

    private func cell(at index: Int) -> HUDCell? {
        model.cells.indices.contains(index) ? model.cells[index] : nil
    }
}

struct HUDCellView: View {
    let cell: HUDCell?
    let isHighlighted: Bool
    /// 指が境目の線の上にあり、いま離しても実行しない。塗らずに、空きマスと同じ枠だけで示す
    var isOnBoundary = false
    let index: Int
    var metrics = HUDMetrics(scale: 1)
    var theme = HUDTheme(surface: .solid)
    /// 光っている、少し長く止めるマスの進み具合。止め終えるまでは白く塗らず、縁に沿って線を伸ばす
    var hold: HUDHold?
    var reduceMotion = false
    var fixedHoldProgress: Double?

    /// 白く塗る（いま指を離すと実行する）。少し長く止めるマスは止め終えてから。境目の線の上では塗らない
    private var isFilled: Bool {
        isHighlighted && !isOnBoundary && (hold?.isReady ?? true)
    }

    /// 少し長く止めるマスを止めている途中
    private var isHolding: Bool {
        isHighlighted && hold?.isReady == false
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: metrics.cellCornerRadius, style: .continuous)
        ZStack {
            if let cell {
                shape.fill(isFilled ? AnyShapeStyle(theme.highlightedFill) : isHolding ? theme.holdingFill : theme.cellFill)
                // 押すキー（⌘B など）は出さない。マスは、アイコンと名前だけ（読み上げには、キーも入る）
                VStack(spacing: 3 * metrics.scale) {
                    CellIconView(cell.icon, size: metrics.iconSize)
                    Text(cell.title)
                        .font(.system(size: metrics.cellTitleFontSize, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .truncationMode(.tail)
                }
                .padding(.horizontal, 6 * metrics.scale)
                .foregroundStyle(isFilled ? AnyShapeStyle(theme.highlightedForeground) : isHolding ? AnyShapeStyle(theme.holdingForeground) : theme.cellForeground)
                if isHighlighted, isOnBoundary, !isHolding {
                    // 離しても実行しない。空きマスを指したときと同じ枠で示す（白い塗り＝離すと実行、と食い違わない）
                    shape.strokeBorder(theme.emptyCellHighlight, lineWidth: 1.5)
                }
                if isHolding, let hold {
                    HUDHoldRing(
                        hold: hold,
                        cornerRadius: metrics.cellCornerRadius,
                        lineWidth: metrics.holdLineWidth,
                        color: theme.ring,
                        animates: !reduceMotion,
                        fixedProgress: fixedHoldProgress
                    )
                }
            } else if isHighlighted {
                // 空きマスは実行しても何も起きないので、塗らずに枠だけで示す
                shape.fill(theme.emptyCellFill)
                shape.strokeBorder(theme.emptyCellHighlight, lineWidth: 1.5)
            } else {
                // 空きマスは、薄い面だけ。「コントラストを上げる」のときだけ、縁を付けて見分けやすくする
                shape.fill(theme.emptyCellFill)
                if theme.isIncreased {
                    shape.strokeBorder(theme.emptyCellStroke, lineWidth: 1)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: metrics.cellHeight)
        .overlay(alignment: .topTrailing) {
            if cell?.requiresHold == true {
                HoldBadge(size: metrics.badgeSize, style: isFilled ? AnyShapeStyle(theme.highlightedDetail) : isHolding ? AnyShapeStyle(theme.holdingForeground) : theme.detail)
                    .padding(metrics.badgeInset)
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

/// 指が外枠にあるときに、薄くしたマスの上に出す「離すとやめる」。
/// 左右の外枠でそちらにページがあれば、その下に「止めると次のページ」（左なら前のページ）を添える
struct HUDCancelLabel: View {
    var metrics = HUDMetrics(scale: 1)
    var theme = HUDTheme(surface: .solid)
    /// 指を止めている左右の外枠（そちらにページがあるときだけ）
    var edge: PageEdge?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10 * metrics.scale, style: .continuous)
        VStack(spacing: 4 * metrics.scale) {
            HStack(spacing: 7 * metrics.scale) {
                Image(systemName: "xmark")
                    .font(.system(size: 11 * metrics.scale, weight: .bold))
                    .accessibilityHidden(true)
                Text(HUDAnnouncement.cancelLabel)
                    .font(.system(size: 14 * metrics.scale, weight: .semibold))
                    .lineLimit(1)
            }
            if let edge {
                HStack(spacing: 4 * metrics.scale) {
                    if edge == .left {
                        Image(systemName: "chevron.left").accessibilityHidden(true)
                    }
                    Text(HUDAnnouncement.edgePagingLabel(edge))
                        .lineLimit(1)
                    if edge == .right {
                        Image(systemName: "chevron.right").accessibilityHidden(true)
                    }
                }
                .font(.system(size: 11 * metrics.scale, weight: .medium))
                .opacity(0.75)
            }
        }
        .foregroundStyle(theme.labelForeground)
        .padding(.horizontal, 16 * metrics.scale)
        .padding(.vertical, 9 * metrics.scale)
        // 下の薄くしたマスの文字が透けないよう、塗りつぶす
        .background(shape.fill(theme.labelFill))
        .overlay(shape.strokeBorder(theme.frameStroke(isActive: true), lineWidth: 1))
        .accessibilityElement(children: .combine)
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

    /// 指が外枠にあるときの「離すとやめる」（HUD の中央と読み上げ）
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
