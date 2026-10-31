// 担当: presets
// ブラウザのプリセット。中央は選択中の文章の要約。AI を使えない Mac ではページ内検索（⌘F）を中央に移す
import Foundation

extension PresetData {
    /// 出典:
    /// - Safari: https://support.apple.com/guide/safari/keyboard-and-other-shortcuts-cpsh003/mac
    ///   （⌘W・⇧⌘T・⌘[・⌘]・⌘L・⌘F「Search the current webpage」）
    /// - ⌘T 新規タブ・⌘R 再読み込み（Safari）・⌘C: https://support.apple.com/en-us/102650
    /// 外したもの: あとで読む ⇧⌘D（リーディングリストに追加するだけで、毎日使う操作ではない）。代わりにページ内検索
    static func safari(_ capabilities: PresetCapabilities) -> AppPreset {
        PresetBuilder.preset(
            KnownApp.safari,
            category: "ブラウザ",
            cells: PresetBuilder.aiCentered([
                PresetBuilder.key("新規タブ", "plus.square.on.square", .key("t", .command)),
                PresetBuilder.key("タブを閉じる", "xmark.square", .key("w", .command)),
                PresetBuilder.key("リロード", "arrow.clockwise", .key("r", .command)),
                PresetBuilder.key("戻る", "chevron.backward", .key("[", .command)),
                PresetBuilder.summarize(),
                PresetBuilder.key("進む", "chevron.forward", .key("]", .command)),
                PresetBuilder.findOnPage(),
                PresetBuilder.key("タブを復元", "arrow.uturn.backward", .key("t", [.shift, .command])),
                // ⌘L でアドレス欄を選び（URL 全体が選択される）、⌘C でコピーする
                PresetBuilder.key("リンクをコピー", "link", .sequence(.key("l", .command), .key("c", .command))),
            ], fallbackIndex: 6, filler: PresetBuilder.key("新規ウインドウ", "macwindow.badge.plus", .key("n", .command)), capabilities),
            summary: { count in
                if capabilities.appleIntelligence {
                    "タブ、戻る・進む、要約など\(count)個"
                } else {
                    "タブ、戻る・進む、ページ内検索など\(count)個"
                }
            }
        )
    }

    /// 出典: https://support.google.com/chrome/answer/157179?hl=en&co=GENIE.Platform%3DDesktop （Mac の欄）
    /// Mac の欄の再読み込みは ⇧⌘R（キャッシュを使わずに再読み込み）だけなので、それを使う。
    /// ⌘F は同じ欄の「Open the Find Bar to search the current page」。
    /// 外したもの: ブックマーク ⌘D（保存するだけで、毎日使う操作ではない）。代わりにページ内検索
    static func chrome(_ capabilities: PresetCapabilities) -> AppPreset {
        PresetBuilder.preset(
            KnownApp.chrome,
            category: "ブラウザ",
            cells: PresetBuilder.aiCentered([
                PresetBuilder.key("新規タブ", "plus.square.on.square", .key("t", .command)),
                PresetBuilder.key("タブを閉じる", "xmark.square", .key("w", .command)),
                PresetBuilder.key("リロード", "arrow.clockwise", .key("r", [.shift, .command])),
                PresetBuilder.key("戻る", "chevron.backward", .key("[", .command)),
                PresetBuilder.summarize(),
                PresetBuilder.key("進む", "chevron.forward", .key("]", .command)),
                PresetBuilder.findOnPage(),
                PresetBuilder.key("タブを復元", "arrow.uturn.backward", .key("t", [.shift, .command])),
                // ⌘L でアドレスバーへ移り（URL が選択される）、⌘C でコピーする
                PresetBuilder.key("リンクをコピー", "link", .sequence(.key("l", .command), .key("c", .command))),
            ], fallbackIndex: 6, filler: PresetBuilder.key("新規ウインドウ", "macwindow.badge.plus", .key("n", .command)), capabilities),
            summary: { count in
                if capabilities.appleIntelligence {
                    "タブ、戻る・進む、要約など\(count)個"
                } else {
                    "タブ、戻る・進む、ページ内検索など\(count)個"
                }
            }
        )
    }

    /// 出典（Arc のヘルプセンターのリリースノート）:
    /// - https://resources.arc.net/hc/en-us/articles/20498463803799-Arc-for-macOS-2021-Release-Notes
    ///   （⇧⌘C で URL をコピー・⇧⌘R で再読み込み・⌥⌘N で Little Arc・⌘N で新規ウインドウ・⌘T でコマンドバー）
    /// - https://resources.arc.net/hc/en-us/articles/20498417809815-Arc-for-macOS-2022-Release-Notes （⌘W）
    /// - https://resources.arc.net/hc/en-us/articles/20498377604887-Arc-for-macOS-2023-Release-Notes （⇧⌘T・⌘F）
    /// ⌘[ / ⌘] は Arc の資料に載っていないので入れない。
    /// Arc は 2026年12月22日に提供が終わる（後継は Dia）:
    /// https://resources.arc.net/hc/en-us/articles/44412972248471-Arc-Sunset-Key-Dates-and-What-to-Expect
    static func arc(_ capabilities: PresetCapabilities) -> AppPreset {
        PresetBuilder.preset(
            KnownApp.arc,
            category: "ブラウザ",
            cells: PresetBuilder.aiCentered([
                PresetBuilder.key("新規タブ", "plus.square.on.square", .key("t", .command)),
                PresetBuilder.key("タブを閉じる", "xmark.square", .key("w", .command)),
                PresetBuilder.key("リロード", "arrow.clockwise", .key("r", [.shift, .command])),
                PresetBuilder.key("Little Arc", "macwindow", .key("n", [.option, .command])),
                PresetBuilder.summarize(),
                PresetBuilder.key("リンクをコピー", "link", .key("c", [.shift, .command])),
                PresetBuilder.key("タブを復元", "arrow.uturn.backward", .key("t", [.shift, .command])),
                PresetBuilder.findOnPage(),
                PresetBuilder.key("新規ウインドウ", "macwindow.badge.plus", .key("n", .command)),
            ], fallbackIndex: 7, filler: PresetBuilder.key("サイドバー", "sidebar.left", .key("s", .command)), capabilities),
            summary: { count in
                if capabilities.appleIntelligence {
                    "Little Arc、リンクをコピー、要約など\(count)個"
                } else {
                    "Little Arc、リンクをコピー、ページ内検索など\(count)個"
                }
            }
        )
    }
}
