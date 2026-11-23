// 担当: engine
// 9マスを開く動き（トラックパッドのどこでも、強く押し込んで少し止める）の時間（docs/architecture.md §5「開く」）。
// 押し込みを見分けるのは KeyboardMonitor（イベントタップ。強めのクリックの2段目を見る）で、ここは止める時間だけを決める
import Foundation

public enum ForcePress {
    /// 強く押し込んでから、開くまで止めておく秒数（開きやすさ GlobalSettings.openSensitivity ごと）。
    /// 標準は、狙って押し込めば待たされると感じない短さで、強めのクリックを「調べる」のつもりで一瞬押しただけでは開かない長さ。
    /// 控えめは、強く押す癖がある人向けにはっきり止めたときだけ。開きやすいは、押し込んだらほぼすぐ
    public static func hold(for sensitivity: OpenSensitivity) -> TimeInterval {
        switch sensitivity {
        case .low: 0.5
        case .standard: 0.25
        case .high: 0.1
        }
    }
}
