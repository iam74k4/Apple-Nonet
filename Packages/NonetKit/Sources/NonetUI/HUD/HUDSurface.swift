// 担当: ui-shell
// トーストの面と色（HUD そのものは皿も輪も無く、アイコンだけ: HUDView・HUDInk）
import NonetCore
import SwiftUI

/// トーストの色。モックの値（#111111 の面に #A8A8A8 の文字など）。文字は WCAG の比 4.5:1 を満たすよう明るくしてある。
/// システム設定の「コントラストを上げる」では、文字と縁をさらに明るくする（HUDColors）
enum HUDPalette {
    static let background = Color(white: backgroundWhite)
    static let backgroundWhite: Double = 0x11 / 255

    static func colors(increasedContrast: Bool) -> HUDColors {
        increasedContrast ? .increased : .standard
    }
}

/// 「コントラストを上げる」で変わる色。白の量（0〜1）と不透明度で持ち、比をテストで確かめる
struct HUDColors: Equatable {
    /// 名前（ガラスの面では階層のスタイルで描くので、不透明な面だけ）
    var foregroundWhite: Double
    /// 説明
    var secondaryTextWhite: Double
    /// パネルの縁
    var borderOpacity: Double

    static let standard = HUDColors(foregroundWhite: 0xA8 / 255, secondaryTextWhite: 0x9A / 255, borderOpacity: 0.08)
    static let increased = HUDColors(foregroundWhite: 0xE0 / 255, secondaryTextWhite: 0xC8 / 255, borderOpacity: 0.4)

    var secondaryText: Color { Color(white: secondaryTextWhite) }
}

/// トーストの面。macOS 26 以降は Dock と同じ Liquid Glass にし、ライト・ダークはシステムの設定に合わせる。
/// それより前の macOS では、モックどおりの暗い不透明な面（HUDPalette）にする
enum HUDSurface: Equatable, Sendable {
    case glass
    case solid

    static var current: HUDSurface {
        if #available(macOS 26, *) { return .glass }
        return .solid
    }
}

/// 面（HUDSurface）と「コントラストを上げる」に合わせた文字の塗り。
/// ガラスでは階層のスタイル（.primary・.secondary）で描き、下に透ける色に合わせてシステムに読みやすくさせる
/// （「コントラストを上げる」「透明度を下げる」も、ガラスそのものはシステムが合わせる）。不透明な面では HUDColors の色をそのまま使う
struct HUDTheme {
    var surface: HUDSurface
    var colors: HUDColors = .standard

    var isGlass: Bool { surface == .glass }

    var title: AnyShapeStyle { isGlass ? AnyShapeStyle(HierarchicalShapeStyle.primary) : AnyShapeStyle(Color.white) }
    var secondaryText: AnyShapeStyle { isGlass ? AnyShapeStyle(HierarchicalShapeStyle.secondary) : AnyShapeStyle(colors.secondaryText) }
    var foreground: AnyShapeStyle { isGlass ? AnyShapeStyle(HierarchicalShapeStyle.primary) : AnyShapeStyle(Color(white: colors.foregroundWhite)) }
}

/// トーストの面を敷く。ガラスはシステムが縁の光と影を付けるので、不透明な面だけ自分で縁と影を描く
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
