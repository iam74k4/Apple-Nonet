// 担当: ui-settings
// 設定画面で使い回す部品（色・見出し・注意書き・帯）
import AppKit
import NonetCore
import SwiftUI

/// モックに合わせた白黒の色。ダークモードでも同じ明暗の関係にする。
/// アクセシビリティの「コントラストを上げる」では、枠をはっきりさせた色にする（ハイコントラストの外観）
enum SettingsPalette {
    /// 明るさ（0 が黒、1 が白）。ライト・ダークと、それぞれのハイコントラスト
    struct Shades: Equatable {
        var light: CGFloat
        var dark: CGFloat
        var lightHighContrast: CGFloat
        var darkHighContrast: CGFloat
    }

    static let gridBackgroundShades = Shades(light: 0.957, dark: 0.165, lightHighContrast: 0.93, darkHighContrast: 0.1)
    static let cellBackgroundShades = Shades(light: 1.0, dark: 0.235, lightHighContrast: 1.0, darkHighContrast: 0.2)
    /// ライトの枠は白いマスとの差が 3:1 ほどになる濃さ（0.878 ではほとんど見えなかった）
    static let cellBorderShades = Shades(light: 0.55, dark: 0.33, lightHighContrast: 0.2, darkHighContrast: 0.82)
    static let emptyBorderShades = Shades(light: 0.72, dark: 0.45, lightHighContrast: 0.3, darkHighContrast: 0.75)
    static let panelBorderShades = Shades(light: 0.898, dark: 0.26, lightHighContrast: 0.4, darkHighContrast: 0.7)

    static let gridBackground = dynamic(gridBackgroundShades)
    static let cellBackground = dynamic(cellBackgroundShades)
    static let cellBorder = dynamic(cellBorderShades)
    static let emptyBorder = dynamic(emptyBorderShades)
    static let panelBorder = dynamic(panelBorderShades)

    /// 外観に合う明るさ。ハイコントラストの外観か、「コントラストを上げる」がオンならハイコントラストの色
    static func white(
        _ shades: Shades,
        for appearance: NSAppearance,
        increaseContrast: Bool = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    ) -> CGFloat {
        let match = appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua])
        let isDark = match == .darkAqua || match == .accessibilityHighContrastDarkAqua
        let isHighContrast = increaseContrast || match == .accessibilityHighContrastAqua || match == .accessibilityHighContrastDarkAqua
        switch (isDark, isHighContrast) {
        case (false, false): return shades.light
        case (true, false): return shades.dark
        case (false, true): return shades.lightHighContrast
        case (true, true): return shades.darkHighContrast
        }
    }

    private static func dynamic(_ shades: Shades) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            NSColor(white: white(shades, for: appearance), alpha: 1)
        })
    }
}

/// 角の丸みと、小さな記号だけのボタンの大きさ。丸みはこの4つだけを使う（欄・チップは small、ボタンの面は medium、
/// マス・カードは large、グリッドの台のようにマスを囲むものは container）
enum SettingsMetrics {
    static let smallRadius: CGFloat = 6
    static let mediumRadius: CGFloat = 8
    static let largeRadius: CGFloat = 12
    static let containerRadius: CGFloat = 16
    /// 記号だけの枠なしのボタン（×・?）の押せる範囲。記号は小さくても、ここまでは押せる
    static let iconButtonSize: CGFloat = 22
}

extension View {
    /// 記号だけの枠なしのボタンの押せる範囲を SettingsMetrics.iconButtonSize 四方に広げる
    func settingsIconButtonFrame() -> some View {
        frame(width: SettingsMetrics.iconButtonSize, height: SettingsMetrics.iconButtonSize)
            .contentShape(Rectangle())
    }
}

/// インスペクタの見出し付きの欄
struct SettingsField<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 小さな注意書き
struct SettingsNote: View {
    let text: String
    var symbol: String?
    var isWarning = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let symbol {
                Image(systemName: symbol)
                    .foregroundStyle(isWarning ? Color.orange : Color.secondary)
                    .accessibilityHidden(true)
            }
            Text(text)
                .foregroundStyle(isWarning ? Color.primary : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 11))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 画面上部の帯（知らせ・権限など）
struct SettingsBanner<Buttons: View>: View {
    let symbol: String
    let title: String
    let message: String?
    var isWarning = true
    var onClose: (() -> Void)?
    @ViewBuilder var buttons: Buttons

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .foregroundStyle(isWarning ? Color.orange : Color.secondary)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                if let message, !message.isEmpty {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            buttons
                .controlSize(.small)
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .settingsIconButtonFrame()
                }
                .buttonStyle(.borderless)
                .help(String(localized: "閉じる", bundle: .module))
                .accessibilityLabel(String(localized: "閉じる", bundle: .module))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
    }
}

/// ヘルプの「?」ボタン。押すと吹き出しで説明を出す
struct SettingsHelpButton<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content
    @State private var isShown = false

    var body: some View {
        Button {
            isShown.toggle()
        } label: {
            Image(systemName: "questionmark.circle")
                .settingsIconButtonFrame()
        }
        .buttonStyle(.borderless)
        .help(label)
        .accessibilityLabel(label)
        .popover(isPresented: $isShown, arrowEdge: .trailing) {
            content
                .padding(16)
                .frame(width: 380)
        }
    }
}
