// 担当: ui-shell
// 少し長く止めてから実行するマス（Cell.requiresHold）の印。HUD と設定のグリッドで同じ記号と読み上げを使う
import SwiftUI

enum HoldMark {
    /// マスの右上に付ける記号（SF Symbols）。止めて待つことを表す
    static let symbol = "timer"

    /// VoiceOver でマスの値として読む（設定のチェックボックスと同じ文言）
    static var accessibilityValue: String {
        String(localized: "少し長く止めてから実行", bundle: .module)
    }

    /// 印の無いマスは値を読まない
    static func accessibilityValue(requiresHold: Bool) -> String {
        requiresHold ? accessibilityValue : ""
    }
}

/// マスの右上の小さな印。マスの読み上げは accessibilityValue で言うので、印そのものは読ませない
struct HoldBadge: View {
    var size: CGFloat
    var color: Color

    var body: some View {
        Image(systemName: HoldMark.symbol)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }
}
