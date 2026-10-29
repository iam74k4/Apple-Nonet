// 担当: ui-shell
import NonetCore

/// メニューバーと初回起動で使う文言
enum ShellText {
    /// 「右⌘」など。利用ガイドの呼び方に合わせる
    static func triggerName(_ trigger: TriggerKey) -> String {
        switch trigger {
        case .rightCommand: String(localized: "右⌘", bundle: .module)
        case .rightOption: String(localized: "右⌥", bundle: .module)
        case .rightShift: String(localized: "右⇧", bundle: .module)
        case .function: String(localized: "fn", bundle: .module)
        }
    }

    /// 練習の案内（例: 「右⌘を押しながら、トラックパッドの右上をタップ」）
    static func practiceInstruction(_ trigger: TriggerKey) -> String {
        String(localized: "\(triggerName(trigger))を押しながら、トラックパッドの右上をタップ", bundle: .module)
    }
}
