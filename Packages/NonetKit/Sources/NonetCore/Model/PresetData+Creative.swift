// 担当: presets
// 絵・映像・ノートのプリセット。出典は各社の公式のキーボードショートカットの一覧
import Foundation

extension PresetData {
    /// 出典: https://helpx.adobe.com/content/dam/help/en/photoshop/using/default-keyboard-shortcuts/photoshop-keyboard-shortcuts.pdf （macOS の列）
    /// 中央: 選択中のテキストが無いので AI ではなく、レイヤーを動かすときにいちばん使う自由変形 ⌘T。
    /// ツールの切り替え（V・B・M など）は修飾キーなしの単キーで、入力欄にフォーカスがあると文字が入るので入れない。
    /// 右下はカンバスの絵を撮る「範囲を撮影」
    static var photoshop: AppPreset {
        PresetBuilder.preset(
            KnownApp.photoshop,
            category: "デザイン",
            cells: [
                PresetBuilder.key("新規レイヤー", "square.stack.3d.up", .key("n", [.shift, .command])),
                PresetBuilder.key("コピーで新規", "plus.square.on.square", .key("j", .command)),
                PresetBuilder.key("グループ化", "folder", .key("g", .command)),
                PresetBuilder.key("選択解除", "cursorarrow.slash", .key("d", .command)),
                PresetBuilder.key("自由変形", "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left", .key("t", .command)),
                PresetBuilder.key("トーンカーブ", "point.topleft.down.to.point.bottomright.curvepath", .key("m", .command)),
                PresetBuilder.key("レイヤーを結合", "square.stack.3d.down.right", .key("e", .command)),
                PresetBuilder.key("表示レイヤー結合", "square.stack.3d.down.forward", .key("e", [.shift, .command])),
                PresetBuilder.captureArea(),
            ],
            summary: { "新規レイヤー、自由変形、結合など\($0)個" }
        )
    }

    /// 出典: https://support.apple.com/guide/final-cut-pro/keyboard-shortcuts-ver90ba5929/mac
    /// 中央: 選択中のテキストが無いので AI ではなく、編集でいちばん使うブレード ⌘B。
    /// 接続 Q・挿入 W・上書き D・追加 E・マーカー M などは修飾キーなしの単キーで、入力欄にフォーカスがあると文字が入るので入れない。
    /// 少し長く止めてから実行する: 共有 ⌘E（書き出しが始まり、時間が掛かる）
    static var finalCut: AppPreset {
        PresetBuilder.preset(
            KnownApp.finalCut,
            category: "映像",
            cells: [
                PresetBuilder.key("読み込み", "square.and.arrow.down", .key("i", .command)),
                PresetBuilder.key("新規プロジェクト", "film", .key("n", .command)),
                PresetBuilder.key("全体を表示", "arrow.up.left.and.arrow.down.right", .key("z", [.shift, .command])),
                PresetBuilder.key("ソロ", "headphones", .key("s", .option)),
                PresetBuilder.key("ブレード", "scissors", .key("b", .command)),
                PresetBuilder.key("すべてブレード", "scissors.badge.ellipsis", .key("b", [.shift, .command])),
                PresetBuilder.key("トランジション", "arrow.left.arrow.right", .key("t", .command)),
                PresetBuilder.holdBeforeRunning(PresetBuilder.key("共有", "square.and.arrow.up", .key("e", .command))),
                PresetBuilder.captureArea(),
            ],
            summary: { "ブレード、トランジション、共有など\($0)個" }
        )
    }

    /// 出典: https://obsidian.md/help/hotkeys ・ https://obsidian.md/help/editing-shortcuts ・各プラグインの説明（クイックスイッチャー・コマンドパレット・検索）
    /// 中央: 自分で書いたノートを選ぶことが多いので校正（選択範囲を置き換える）。AI を使えない Mac ではクイック切替 ⌘O を中央に移す。
    /// デイリーノート・バックリンク・グラフは既定のキーが無い（Hotkeys で割り当てる）ので入れない
    static func obsidian(_ capabilities: PresetCapabilities) -> AppPreset {
        PresetBuilder.preset(
            KnownApp.obsidian,
            category: "ドキュメント",
            cells: PresetBuilder.aiCentered([
                PresetBuilder.key("クイック切替", "arrow.right.circle", .key("o", .command)),
                PresetBuilder.key("コマンド", "command", .key("p", .command)),
                PresetBuilder.key("全体を検索", "magnifyingglass", .key("f", [.shift, .command])),
                PresetBuilder.key("新規ノート", "square.and.pencil", .key("n", .command)),
                PresetBuilder.proofread(),
                PresetBuilder.key("閲覧モード", "eye", .key("e", .command)),
                PresetBuilder.key("検索と置換", "text.magnifyingglass", .key("f", [.option, .command])),
                PresetBuilder.key("プロパティ", "list.bullet.rectangle", .key(";", .command)),
                PresetBuilder.key("書式なし貼付", "doc.on.clipboard", .key("v", [.shift, .command])),
            ], fallbackIndex: 0, filler: PresetBuilder.key("新規タブ", "plus.square.on.square", .key("t", .command)), capabilities),
            summary: { count in
                if capabilities.appleIntelligence {
                    "クイック切替、検索、校正など\(count)個"
                } else {
                    "クイック切替、検索、閲覧モードなど\(count)個"
                }
            }
        )
    }
}
