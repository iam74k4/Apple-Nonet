// 担当: presets
// オフィスのプリセット（Microsoft Office と iWork）。出典は各社の公式のキーボードショートカットの一覧
import Foundation

extension PresetData {
    /// 出典: https://support.microsoft.com/en-us/accessibility/outlook/mac/keyboard-shortcuts-in-outlook-for-mac
    /// 中央: 長いメールを選んで読むことが多いので要約。AI を使えない Mac では、読み終えたメールを片付けるアーカイブ ⌃E を中央に移す。
    /// 少し長く止めてから実行する: 送信 ⌘Return（送ったメールは取り消せない）。⌘N はメールの画面では新規メール（カレンダーでは新規予定）
    static func outlook(_ capabilities: PresetCapabilities) -> AppPreset {
        PresetBuilder.preset(
            KnownApp.outlook,
            category: "メール",
            cells: PresetBuilder.aiCentered([
                PresetBuilder.key("新規メール", "square.and.pencil", .key("n", .command)),
                PresetBuilder.key("返信", "arrowshape.turn.up.left", .key("r", .command)),
                PresetBuilder.key("全員に返信", "arrowshape.turn.up.left.2", .key("r", [.shift, .command])),
                PresetBuilder.key("転送", "arrowshape.turn.up.right", .key("j", .command)),
                PresetBuilder.summarize(),
                PresetBuilder.key("アーカイブ", "archivebox", .key("e", .control)),
                PresetBuilder.key("フォルダへ移動", "folder", .key("m", [.shift, .command])),
                PresetBuilder.key("検索", "magnifyingglass", .key("f", [.option, .command])),
                PresetBuilder.holdBeforeRunning(PresetBuilder.key("送信", "paperplane", .special(.returnKey, .command))),
            ], fallbackIndex: 5, filler: PresetBuilder.key("今日フラグ", "flag", .key("1", .control)), capabilities),
            summary: { count in
                if capabilities.appleIntelligence {
                    "返信、アーカイブ、要約など\(count)個"
                } else {
                    "返信、アーカイブ、転送など\(count)個"
                }
            }
        )
    }

    /// 出典: https://support.microsoft.com/en-us/office/keyboard-shortcuts-in-excel-1798d9d5-842a-42b8-9c99-9b7213f0040f （macOS の節）
    /// 中央: 選択中のテキストが無いので AI ではなく、表を見るときにいちばん使うフィルター ⇧⌘F。
    /// 外したもの: 再計算 F9・新規シート ⇧F11（fn キーの設定で変わる）、行や列の挿入（⌃⇧= は JIS で打てない）
    static var excel: AppPreset {
        PresetBuilder.preset(
            KnownApp.excel,
            category: "オフィス",
            cells: [
                PresetBuilder.key("セルの書式", "textformat", .key("1", .command)),
                PresetBuilder.key("オートSUM", "sum", .key("t", [.shift, .command])),
                PresetBuilder.key("並べ替え", "arrow.up.arrow.down", .key("r", [.shift, .command])),
                PresetBuilder.key("前のシート", "arrow.left.square", .special(.leftArrow, .option)),
                PresetBuilder.key("フィルター", "line.3.horizontal.decrease.circle", .key("f", [.shift, .command])),
                PresetBuilder.key("次のシート", "arrow.right.square", .special(.rightArrow, .option)),
                PresetBuilder.key("置換", "text.magnifyingglass", .key("h", [.shift, .command])),
                PresetBuilder.key("形式を選んで貼付", "doc.on.clipboard", .key("v", [.control, .command])),
                PresetBuilder.key("今日の日付", "calendar", .key(";", .control)),
            ],
            summary: { "フィルター、並べ替え、オートSUMなど\($0)個" }
        )
    }

    /// 出典: https://support.microsoft.com/en-us/office/keyboard-shortcuts-in-word-95ef89dd-7142-4b50-afb2-f762f663ceb2 （macOS の節）
    /// 中央: 自分で書いた文章を選ぶことが多いので校正（選択範囲を置き換える）。AI を使えない Mac では置換 ⌃H を中央に移す
    static func word(_ capabilities: PresetCapabilities) -> AppPreset {
        PresetBuilder.preset(
            KnownApp.word,
            category: "ドキュメント",
            cells: PresetBuilder.aiCentered([
                PresetBuilder.key("見出し1", "textformat.size.larger", .key("1", [.option, .command])),
                PresetBuilder.key("見出し2", "textformat.size", .key("2", [.option, .command])),
                PresetBuilder.key("標準", "text.alignleft", .key("n", [.shift, .command])),
                PresetBuilder.key("コメント", "text.bubble", .key("a", [.option, .command])),
                PresetBuilder.proofread(),
                PresetBuilder.key("変更履歴", "pencil.line", .key("e", [.shift, .command])),
                PresetBuilder.key("箇条書き", "list.bullet", .key("l", [.shift, .command])),
                PresetBuilder.key("置換", "text.magnifyingglass", .key("h", .control)),
                PresetBuilder.key("改ページ", "doc.badge.plus", .special(.returnKey, .command)),
            ], fallbackIndex: 7, filler: PresetBuilder.key("スペルチェック", "textformat.abc", .key("l", [.option, .command])), capabilities),
            summary: { count in
                if capabilities.appleIntelligence {
                    "見出し、コメント、校正など\(count)個"
                } else {
                    "見出し、コメント、変更履歴など\(count)個"
                }
            }
        )
    }

    /// 出典: https://support.microsoft.com/en-us/office/use-keyboard-shortcuts-to-create-powerpoint-presentations-ebb3d20e-dcd4-444f-a38e-bb5c5ed180f4
    /// と https://support.microsoft.com/en-us/topic/use-keyboard-shortcuts-to-deliver-powerpoint-presentations-1524ffce-bd2a-45f4-9a7f-f18b992b93a0 （macOS の節）
    /// 中央: 選択中のテキストが無いので AI ではなく、確かめながら作るときにいちばん使う「現在から再生」⌘Return
    static var powerPoint: AppPreset {
        PresetBuilder.preset(
            KnownApp.powerPoint,
            category: "オフィス",
            cells: [
                PresetBuilder.key("新しいスライド", "rectangle.badge.plus", .key("n", [.shift, .command])),
                PresetBuilder.key("スライドを複製", "plus.square.on.square", .key("d", [.shift, .command])),
                PresetBuilder.key("スライド一覧", "square.grid.3x3", .key("2", .command)),
                PresetBuilder.key("先頭から再生", "play.rectangle", .special(.returnKey, [.shift, .command])),
                PresetBuilder.key("現在から再生", "play.fill", .special(.returnKey, .command)),
                PresetBuilder.key("発表者ツール", "person.crop.rectangle", .special(.returnKey, .option)),
                PresetBuilder.key("グループ化", "rectangle.3.group", .key("g", [.option, .command])),
                PresetBuilder.key("最前面へ", "square.3.layers.3d.top.filled", .key("f", [.shift, .command])),
                PresetBuilder.key("全体を表示", "arrow.up.left.and.arrow.down.right", .key("o", [.option, .command])),
            ],
            summary: { "再生、新しいスライド、発表者ツールなど\($0)個" }
        )
    }

    /// 出典: https://support.apple.com/guide/keynote/keyboard-shortcuts-tanfde4a3e6d/mac
    /// 中央: 選択中のテキストが無いので AI ではなく、確かめながら作るときにいちばん使う再生 ⌥⌘P。
    /// 外したもの: 先頭から再生（キーが無く、⌥ を押しながら再生ボタンを押す）。右下はスライドの絵を撮る「範囲を撮影」
    static var keynote: AppPreset {
        PresetBuilder.preset(
            KnownApp.keynote,
            category: "オフィス",
            cells: [
                PresetBuilder.key("新規スライド", "rectangle.badge.plus", .key("n", [.shift, .command])),
                PresetBuilder.key("スキップ", "eye.slash", .key("h", [.shift, .command])),
                PresetBuilder.key("スライドへ移動", "arrow.right.square", .key("g", [.control, .command])),
                PresetBuilder.key("グループ化", "rectangle.3.group", .key("g", [.option, .command])),
                PresetBuilder.key("再生", "play.fill", .key("p", [.option, .command])),
                PresetBuilder.key("発表者ノート", "note.text", .key("p", [.shift, .command])),
                PresetBuilder.key("最前面へ", "square.3.layers.3d.top.filled", .key("f", [.shift, .command])),
                PresetBuilder.key("最背面へ", "square.3.layers.3d.bottom.filled", .key("b", [.shift, .command])),
                PresetBuilder.captureArea(),
            ],
            summary: { "再生、新規スライド、発表者ノートなど\($0)個" }
        )
    }

    /// 出典: https://support.apple.com/guide/pages/keyboard-shortcuts-tanc0ffef022/mac
    /// 中央: 自分で書いた文章を選ぶことが多いので校正（選択範囲を置き換える）。AI を使えない Mac では単語数 ⇧⌘W を中央に移す。
    /// 段落スタイルは既定のキーが無い（自分で割り当てる）ので入れない
    static func pages(_ capabilities: PresetCapabilities) -> AppPreset {
        PresetBuilder.preset(
            KnownApp.pages,
            category: "ドキュメント",
            cells: PresetBuilder.aiCentered([
                PresetBuilder.key("単語数", "number", .key("w", [.shift, .command])),
                PresetBuilder.key("コメント", "text.bubble", .key("k", [.shift, .command])),
                PresetBuilder.key("ハイライト", "highlighter", .key("h", [.shift, .command])),
                PresetBuilder.key("変更を承認", "checkmark.circle", .key("a", [.option, .command])),
                PresetBuilder.proofread(),
                PresetBuilder.key("変更を却下", "xmark.circle", .key("r", [.option, .command])),
                PresetBuilder.key("不可視文字", "paragraphsign", .key("i", [.shift, .command])),
                PresetBuilder.key("ページへ移動", "arrow.right.square", .key("g", [.control, .command])),
                PresetBuilder.key("改ページ", "doc.badge.plus", .special(.returnKey, .command)),
            ], fallbackIndex: 0, filler: PresetBuilder.key("ブックマーク", "bookmark", .key("b", [.option, .command])), capabilities),
            summary: { count in
                if capabilities.appleIntelligence {
                    "コメント、変更の承認、校正など\(count)個"
                } else {
                    "コメント、変更の承認、単語数など\(count)個"
                }
            }
        )
    }

    /// 出典: https://support.apple.com/guide/numbers/keyboard-shortcuts-tana45192591/mac
    /// 中央: 選択中のテキストが無いので AI ではなく、表を見るときにいちばん使うフィルタ ⌥⌘F。
    /// 外したもの: 数式エディタ（= のキーは JIS で打てない）
    static var numbers: AppPreset {
        PresetBuilder.preset(
            KnownApp.numbers,
            category: "オフィス",
            cells: [
                PresetBuilder.key("行を上に追加", "arrow.up.to.line", .special(.upArrow, .option)),
                PresetBuilder.key("行を下に追加", "arrow.down.to.line", .special(.downArrow, .option)),
                PresetBuilder.key("列を右に追加", "arrow.right.to.line", .special(.rightArrow, .option)),
                PresetBuilder.key("並べ替え", "arrow.up.arrow.down", .key("r", [.shift, .command])),
                PresetBuilder.key("フィルタ", "line.3.horizontal.decrease.circle", .key("f", [.option, .command])),
                PresetBuilder.key("セルを結合", "rectangle.split.2x1", .key("m", [.control, .command])),
                PresetBuilder.key("新規シート", "plus.rectangle.on.rectangle", .key("n", [.shift, .command])),
                PresetBuilder.key("前のシート", "arrow.left.square", .key("[", [.shift, .command])),
                PresetBuilder.key("次のシート", "arrow.right.square", .key("]", [.shift, .command])),
            ],
            summary: { "行の追加、フィルタ、並べ替えなど\($0)個" }
        )
    }
}
