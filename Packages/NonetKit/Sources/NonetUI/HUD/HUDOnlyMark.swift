// 担当: ui-shell
// HUD で選んだときだけ実行するマス（Cell.requiresHUD）の印。HUD と設定のグリッドで同じ記号と読み上げを使う
import SwiftUI

enum HUDOnlyMark {
    /// マスの右上に付ける記号（SF Symbols）
    static let symbol = "lock.fill"

    /// VoiceOver でマスの値として読む
    static var accessibilityValue: String {
        String(localized: "HUD で選んだときだけ実行", bundle: .module)
    }

    /// 印の無いマスは値を読まない
    static func accessibilityValue(requiresHUD: Bool) -> String {
        requiresHUD ? accessibilityValue : ""
    }
}

/// マスの右上の小さな印。マスの読み上げは accessibilityValue で言うので、印そのものは読ませない
struct HUDOnlyBadge: View {
    var size: CGFloat
    var color: Color

    var body: some View {
        Image(systemName: HUDOnlyMark.symbol)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }
}
