// 担当: presets
// サイトごとのボタンのプリセット（「サイトを追加」で、そのサイトを選んだときに入れる）。
// どれもそのサイトの標準のキー（設定を変えなくても効くもの）だけを送る
//
// 出典:
// - YouTube のキーボード ショートカット: https://support.google.com/youtube/answer/7631406
import Foundation

public enum SitePresets {
    /// 「サイトを追加」で候補に出すサイト（プリセットのあるもの）
    public static let suggestedHosts = ["youtube.com"]

    /// そのサイトのプリセットのページ。無ければ nil（空のページで作る）
    public static func pages(forHost host: String) -> [Page]? {
        switch SiteReference.normalizedHost(host) {
        case "youtube.com": [youtube]
        default: nil
        }
    }

    /// 真ん中が再生／一時停止、左右が10秒戻る・進む、上下が全画面と字幕。斜めは速さ・消音・シアター
    static var youtube: Page {
        Page(
            cells: [
                PresetBuilder.key("遅く", "tortoise", .key(",", [.shift])),
                PresetBuilder.key("全画面", "arrow.up.left.and.arrow.down.right", .key("f", [])),
                PresetBuilder.key("速く", "hare", .key(".", [.shift])),
                PresetBuilder.key("10秒戻る", "gobackward.10", .key("j", [])),
                PresetBuilder.key("再生／一時停止", "playpause.fill", .key("k", [])),
                PresetBuilder.key("10秒進む", "goforward.10", .key("l", [])),
                PresetBuilder.key("消音", "speaker.slash", .key("m", [])),
                PresetBuilder.key("字幕", "captions.bubble", .key("c", [])),
                PresetBuilder.key("シアター", "rectangle.expand.vertical", .key("t", [])),
            ],
            name: PresetBuilder.text("YouTube")
        )
    }
}
