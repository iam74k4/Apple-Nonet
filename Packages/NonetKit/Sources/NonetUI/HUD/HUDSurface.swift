// 担当: ui-shell
// HUD とトーストの面と色（トーストが使う。HUD そのものは皿も輪も無く、アイコンだけ: HUDView・HUDInk）
import NonetCore
import SwiftUI

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
