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

    /// 練習で違うマスを押したとき（例: 「いまのは「左下」のマスです。右上をタップしてみてください」）
    static func wrongCellMessage(_ index: Int) -> String {
        String(localized: "いまのは「\(HUDAnnouncement.attributivePositionName(index))」のマスです。右上をタップしてみてください", bundle: .module)
    }

    /// 案内をもう一度見るときに足すアプリの数。数で文が変わる（1 app profile / 2 app profiles）
    static func additionNote(_ count: Int) -> String {
        String(localized: "\(count)個のアプリのプロファイルを追加します", bundle: .module, locale: .nonetUI)
    }
}
