// 担当: presets
// ブラウザのプリセット。中央は選択中の文章の要約
import Foundation

extension PresetData {
    /// 出典:
    /// - Safari: https://support.apple.com/guide/safari/keyboard-and-other-shortcuts-cpsh003/mac
    ///   （⌘W・⇧⌘T・⌘[・⌘]・⇧⌘D・⌘L）
    /// - ⌘T 新規タブ・⌘R 再読み込み（Safari）・⌘C: https://support.apple.com/en-us/102650
    static var safari: AppPreset {
        PresetBuilder.preset(
            KnownApp.safari,
            category: "ブラウザ",
            cells: [
                PresetBuilder.key("新規タブ", "plus.square.on.square", .key("t", .command)),
                PresetBuilder.key("タブを閉じる", "xmark.square", .key("w", .command)),
                PresetBuilder.key("リロード", "arrow.clockwise", .key("r", .command)),
                PresetBuilder.key("戻る", "chevron.backward", .key("[", .command)),
                PresetBuilder.summarize(),
                PresetBuilder.key("進む", "chevron.forward", .key("]", .command)),
                PresetBuilder.key("あとで読む", "eyeglasses", .key("d", [.shift, .command])),
                PresetBuilder.key("タブを復元", "arrow.uturn.backward", .key("t", [.shift, .command])),
                // ⌘L でアドレス欄を選び（URL 全体が選択される）、⌘C でコピーする
                PresetBuilder.key("リンクをコピー", "link", .sequence(.key("l", .command), .key("c", .command))),
            ],
            summary: { "タブ、戻る・進む、要約など\($0)個" }
        )
    }

    /// 出典: https://support.google.com/chrome/answer/157179?hl=en&co=GENIE.Platform%3DDesktop （Mac の欄）
    /// Mac の欄の再読み込みは ⇧⌘R（キャッシュを使わずに再読み込み）だけなので、それを使う
    static var chrome: AppPreset {
        PresetBuilder.preset(
            KnownApp.chrome,
            category: "ブラウザ",
            cells: [
                PresetBuilder.key("新規タブ", "plus.square.on.square", .key("t", .command)),
                PresetBuilder.key("タブを閉じる", "xmark.square", .key("w", .command)),
                PresetBuilder.key("リロード", "arrow.clockwise", .key("r", [.shift, .command])),
                PresetBuilder.key("戻る", "chevron.backward", .key("[", .command)),
                PresetBuilder.summarize(),
                PresetBuilder.key("進む", "chevron.forward", .key("]", .command)),
                PresetBuilder.key("ブックマーク", "bookmark", .key("d", .command)),
                PresetBuilder.key("タブを復元", "arrow.uturn.backward", .key("t", [.shift, .command])),
                // ⌘L でアドレスバーへ移り（URL が選択される）、⌘C でコピーする
                PresetBuilder.key("リンクをコピー", "link", .sequence(.key("l", .command), .key("c", .command))),
            ],
            summary: { "タブ、戻る・進む、要約など\($0)個" }
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
    static var arc: AppPreset {
        PresetBuilder.preset(
            KnownApp.arc,
            category: "ブラウザ",
            cells: [
                PresetBuilder.key("新規タブ", "plus.square.on.square", .key("t", .command)),
                PresetBuilder.key("タブを閉じる", "xmark.square", .key("w", .command)),
                PresetBuilder.key("リロード", "arrow.clockwise", .key("r", [.shift, .command])),
                PresetBuilder.key("Little Arc", "macwindow", .key("n", [.option, .command])),
                PresetBuilder.summarize(),
                PresetBuilder.key("リンクをコピー", "link", .key("c", [.shift, .command])),
                PresetBuilder.key("タブを復元", "arrow.uturn.backward", .key("t", [.shift, .command])),
                PresetBuilder.key("ページ内検索", "text.magnifyingglass", .key("f", .command)),
                PresetBuilder.key("新規ウインドウ", "macwindow.badge.plus", .key("n", .command)),
            ],
            summary: { "Little Arc、リンクをコピー、要約など\($0)個" }
        )
    }
}
