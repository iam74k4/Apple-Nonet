// 担当: presets
// デザイン・ファイル・ドキュメントのプリセット
import Foundation

extension PresetData {
    /// 出典（Figma のヘルプセンター）:
    /// - ⌥⌘G フレーム・⌘D 複製: https://help.figma.com/hc/en-us/articles/360041539473-Frames-in-Figma-Design
    /// - ⌘G グループ・⇧⌘G グループ解除: https://help.figma.com/hc/en-us/articles/360039832054-The-difference-between-frames-and-groups
    /// - ⌥⌘K コンポーネント: https://help.figma.com/hc/en-us/articles/360038663154-Create-components-to-reuse-in-designs
    /// - ⇧A 自動レイアウト: https://help.figma.com/hc/en-us/articles/5731482952599-Toggle-on-auto-layout-in-designs
    /// - ⇧1 全体を表示: https://help.figma.com/hc/en-us/articles/360041065034-Adjust-your-zoom-and-view-options
    /// - ⇧⌘C PNG でコピー: https://help.figma.com/hc/en-us/articles/4409078832791-Copy-and-paste-objects
    /// - ⇧⌘E 書き出し: https://help.figma.com/hc/en-us/articles/360040028114-Export-static-designs-from-Figma
    /// モックから外したもの: UI を隠す ⌘\（日本語配列では ⌘゛に割り当てが変わる。
    /// https://help.figma.com/hc/en-us/articles/5665442977431-Select-keyboard-layout ）
    /// 中央: 選択中のテキストが無いので AI ではなく、レイアウトの組み立てでいちばん使う自動レイアウトを置く。
    /// ⇧A と ⇧1 は Figma の既定どおり ⌘ を付けない（キャンバスを操作しているときだけ効く）
    static var figma: AppPreset {
        PresetBuilder.preset(
            KnownApp.figma,
            category: "デザイン",
            cells: [
                PresetBuilder.key("フレーム", "square.dashed", .key("g", [.option, .command])),
                PresetBuilder.key("グループ", "rectangle.3.group", .key("g", .command)),
                PresetBuilder.key("グループ解除", "square.split.2x2", .key("g", [.shift, .command])),
                PresetBuilder.key("複製", "plus.square.on.square", .key("d", .command)),
                PresetBuilder.key("自動レイアウト", "rectangle.grid.1x2", .key("a", .shift)),
                PresetBuilder.key("コンポーネント化", "diamond", .key("k", [.option, .command])),
                PresetBuilder.key("全体を表示", "arrow.up.left.and.arrow.down.right", .key("1", .shift)),
                PresetBuilder.key("PNGでコピー", "photo.on.rectangle", .key("c", [.shift, .command])),
                PresetBuilder.key("書き出し", "square.and.arrow.up", .key("e", [.shift, .command])),
            ],
            summary: { "フレーム、自動レイアウト、書き出しなど\($0)個" }
        )
    }

    /// 出典: https://support.apple.com/en-us/102650 （Finder とシステムのショートカット）
    /// 中央: 選択中のテキストが無いので AI ではなく、ファイルを開かずに中身を確かめるクイックルックを置く。
    /// 隠しファイルの表示 ⇧⌘. はこのページに載っていないので入れない
    static var finder: AppPreset {
        PresetBuilder.preset(
            KnownApp.finder,
            category: "ファイル",
            cells: [
                PresetBuilder.key("新規ウインドウ", "macwindow.badge.plus", .key("n", .command)),
                PresetBuilder.key("新規フォルダ", "folder.badge.plus", .key("n", [.shift, .command])),
                PresetBuilder.key("情報を見る", "info.circle", .key("i", .command)),
                PresetBuilder.key("ダウンロード", "arrow.down.circle", .key("l", [.option, .command])),
                PresetBuilder.key("クイックルック", "eye", .key("y", .command)),
                PresetBuilder.key("デスクトップ", "menubar.dock.rectangle", .key("d", [.shift, .command])),
                PresetBuilder.key("上の階層へ", "arrow.turn.left.up", .special(.upArrow, .command)),
                PresetBuilder.key("フォルダへ移動", "folder", .key("g", [.shift, .command])),
                PresetBuilder.key("AirDrop", "dot.radiowaves.up.forward", .key("r", [.shift, .command])),
            ],
            summary: { "新規フォルダ、クイックルック、AirDrop など\($0)個" }
        )
    }

    /// 出典: https://www.notion.com/help/keyboard-shortcuts
    /// このページは英語配列が前提と書いてあるので、配列で位置が変わる記号（⌘[ ⌘] など）は使わず、英数字だけにする。
    /// 中央: 自分で書いた文章を選ぶことが多いので校正（選択範囲を置き換える）
    static var notion: AppPreset {
        PresetBuilder.preset(
            KnownApp.notion,
            category: "ドキュメント",
            cells: [
                PresetBuilder.key("新規ページ", "doc.badge.plus", .key("n", .command)),
                PresetBuilder.key("検索", "magnifyingglass", .key("p", .command)),
                PresetBuilder.key("リンクをコピー", "link", .key("l", .command)),
                PresetBuilder.key("コメント", "text.bubble", .key("m", [.shift, .command])),
                PresetBuilder.proofread(),
                PresetBuilder.key("上の階層へ", "arrow.turn.left.up", .key("u", [.shift, .command])),
                PresetBuilder.key("見出し1", "textformat.size.larger", .key("1", [.option, .command])),
                PresetBuilder.key("ToDo", "checklist", .key("4", [.option, .command])),
                PresetBuilder.key("箇条書き", "list.bullet", .key("5", [.option, .command])),
            ],
            summary: { "新規ページ、検索、校正など\($0)個" }
        )
    }

    /// 出典: https://support.apple.com/guide/notes/keyboard-shortcuts-and-gestures-apd46c25187e/mac
    /// 中央: 自分で書いたメモを選ぶことが多いので校正（選択範囲を置き換える）
    static var notes: AppPreset {
        PresetBuilder.preset(
            KnownApp.notes,
            category: "ドキュメント",
            cells: [
                PresetBuilder.key("新規メモ", "square.and.pencil", .key("n", .command)),
                PresetBuilder.key("チェックリスト", "checklist", .key("l", [.shift, .command])),
                PresetBuilder.key("表", "tablecells", .key("t", [.option, .command])),
                PresetBuilder.key("タイトル", "textformat.size.larger", .key("t", [.shift, .command])),
                PresetBuilder.proofread(),
                PresetBuilder.key("見出し", "textformat", .key("h", [.shift, .command])),
                PresetBuilder.key("箇条書き", "list.bullet", .key("7", [.shift, .command])),
                PresetBuilder.key("本文", "text.alignleft", .key("b", [.shift, .command])),
                PresetBuilder.key("検索", "magnifyingglass", .key("f", [.option, .command])),
            ],
            summary: { "チェックリスト、表、校正など\($0)個" }
        )
    }
}
