// 担当: engine
import Foundation

extension ControllerStatus {
    /// 動かしている間の状態。優先順は 無効 > アクセシビリティ > トラックパッド > セキュア入力 > 動作中
    static func resolve(isEnabled: Bool, isAccessibilityGranted: Bool, isTrackpadAvailable: Bool, isSecureInputActive: Bool) -> ControllerStatus {
        if !isEnabled { return .disabled }
        if !isAccessibilityGranted { return .needsAccessibility }
        if !isTrackpadAvailable { return .noTrackpad }
        if isSecureInputActive { return .secureInputActive }
        return .running
    }
}
