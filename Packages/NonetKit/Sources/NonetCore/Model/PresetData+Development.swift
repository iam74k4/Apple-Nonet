// 担当: presets
// 開発アプリのプリセット。中央は Claude Code（ターミナルで対話モード）
import Foundation

extension PresetData {
    /// 出典:
    /// - ⌘B ビルド・⌘R 実行・⌘. 停止・⌥⌘C コミット: https://developer.apple.com/library/archive/documentation/IDEs/Conceptual/xcode_help-command_shortcuts/MenuCommands/MenuCommands014.html
    /// - ⌘U テスト: https://developer.apple.com/library/archive/documentation/DeveloperTools/Conceptual/testing_with_xcode/chapters/05-running_tests.html
    /// - Integrate > Commit のメニュー: https://developer.apple.com/documentation/xcode/tracking-code-changes-in-a-source-control-repository
    /// - Xcode 27.1 の既定の割り当て（IDEKit.framework の IDEKit.xcplugindata）でも、上の5つと ⇧⌘K（Clean Build Folder）を確認した
    /// - Device Hub: Xcode 27 で Simulator.app が Device Hub（com.apple.dt.Devices）に置き換わった
    ///   https://mjtsai.com/blog/2026/06/25/xcode-27s-device-hub/
    /// モックから外したもの: Slack の起動（入っていないと失敗する）、ミュート（ユーザーが作るショートカットが前提）、
    /// スクショ ⇧⌘4（システム全体のショートカットで、前面アプリに送っても撮れるとは限らない）
    static var xcode: AppPreset {
        PresetBuilder.preset(
            KnownApp.xcode,
            category: "開発",
            cells: [
                PresetBuilder.key("ビルド", "hammer", .key("b", .command)),
                PresetBuilder.key("実行", "play.fill", .key("r", .command)),
                PresetBuilder.key("テスト", "checkmark.diamond", .key("u", .command)),
                // Xcode 27 は Device Hub、それより前は Simulator.app。どちらの Xcode でも開けるよう順に試す
                PresetBuilder.script("シミュレータ", "iphone", ScriptAction(
                    source: "open -b com.apple.dt.Devices 2>/dev/null || open -b com.apple.iphonesimulator",
                    timeout: 15
                )),
                PresetBuilder.claudeCode(),
                PresetBuilder.launch("ターミナル", "apple.terminal", KnownApp.terminal),
                PresetBuilder.key("停止", "stop.fill", .key(".", .command)),
                PresetBuilder.key("クリーン", "eraser", .key("k", [.shift, .command])),
                PresetBuilder.key("コミット", "arrow.triangle.branch", .key("c", [.option, .command])),
            ],
            summary: { "ビルド、テスト、Claude Code など\($0)個" }
        )
    }

    /// 出典: https://code.visualstudio.com/docs/reference/default-keybindings
    /// 外したもの: ターミナルの切り替え ⌃`（JIS では ` が修飾キーなしで打てない）、エディタの分割 ⌘\（同じく \）
    static var vsCode: AppPreset {
        PresetBuilder.preset(
            KnownApp.vsCode,
            category: "開発",
            cells: [
                PresetBuilder.key("コマンド", "command", .key("p", [.shift, .command])),
                PresetBuilder.key("ファイルを開く", "doc.text.magnifyingglass", .key("p", .command)),
                PresetBuilder.key("全体を検索", "magnifyingglass", .key("f", [.shift, .command])),
                PresetBuilder.key("サイドバー", "sidebar.left", .key("b", .command)),
                PresetBuilder.claudeCode(),
                PresetBuilder.key("ソース管理", "arrow.triangle.branch", .key("g", [.control, .shift])),
                PresetBuilder.key("整形", "text.alignleft", .key("f", [.shift, .option])),
                PresetBuilder.key("コメント", "text.bubble", .key("/", .command)),
                PresetBuilder.key("定義へ移動", "arrow.right.circle", .special(.f12)),
            ],
            summary: { "コマンド、検索、Claude Code など\($0)個" }
        )
    }

    /// 出典:
    /// - Cursor 独自: https://cursor.com/docs/reference/keyboard-shortcuts
    ///   （⇧⌘P コマンド・⌘I サイドパネル・⌘E エージェントのレイアウト・⇧⌘L 選択範囲をチャットへ・⌘/ モデルの切り替え）
    /// - 同じページに「VS Code のキー割り当てが土台」とあるので、⌘P・⇧⌘F・⌃⇧G は VS Code の既定に従う:
    ///   https://code.visualstudio.com/docs/reference/default-keybindings
    /// ⌘/ は Cursor ではコメントではなくモデルの切り替えになっている
    static var cursor: AppPreset {
        PresetBuilder.preset(
            KnownApp.cursor,
            category: "開発",
            cells: [
                PresetBuilder.key("コマンド", "command", .key("p", [.shift, .command])),
                PresetBuilder.key("ファイルを開く", "doc.text.magnifyingglass", .key("p", .command)),
                PresetBuilder.key("全体を検索", "magnifyingglass", .key("f", [.shift, .command])),
                PresetBuilder.key("AIチャット", "bubble.left.and.text.bubble.right", .key("i", .command)),
                PresetBuilder.claudeCode(),
                PresetBuilder.key("エージェント表示", "rectangle.split.3x1", .key("e", .command)),
                PresetBuilder.key("チャットに追加", "text.badge.plus", .key("l", [.shift, .command])),
                PresetBuilder.key("モデル切替", "cpu", .key("/", .command)),
                PresetBuilder.key("ソース管理", "arrow.triangle.branch", .key("g", [.control, .shift])),
            ],
            summary: { "AIチャット、エージェント、Claude Code など\($0)個" }
        )
    }

    /// 出典: https://support.apple.com/guide/terminal/keyboard-shortcuts-trmlshtcts/mac
    /// タブの移動は ⇧⌘[ / ⇧⌘] ではなく、キー配列に関係しない ⌃Tab / ⌃⇧Tab（同じページに載っている）を使う
    static var terminal: AppPreset {
        PresetBuilder.preset(
            KnownApp.terminal,
            category: "開発",
            cells: [
                PresetBuilder.key("新規ウインドウ", "macwindow.badge.plus", .key("n", .command)),
                PresetBuilder.key("新規タブ", "plus.square.on.square", .key("t", .command)),
                PresetBuilder.key("タブを閉じる", "xmark.square", .key("w", .command)),
                PresetBuilder.key("前のタブ", "chevron.backward", .special(.tab, [.control, .shift])),
                PresetBuilder.claudeCode(),
                PresetBuilder.key("次のタブ", "chevron.forward", .special(.tab, .control)),
                // ⌘. は実行中のコマンドに ⌃C を送る
                PresetBuilder.key("中断", "stop.circle", .key(".", .command)),
                PresetBuilder.key("クリア", "eraser", .key("k", .command)),
                PresetBuilder.key("分割", "rectangle.split.1x2", .key("d", .command)),
            ],
            summary: { "タブ、クリア、Claude Code など\($0)個" }
        )
    }
}
