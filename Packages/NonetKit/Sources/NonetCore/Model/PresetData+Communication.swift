// 担当: presets
// 会議・チャット・メールのプリセット
import Foundation

extension PresetData {
    /// 出典: https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0067050 （macOS の欄）
    /// 中央: 選択中のテキストが無いので AI ではなく、会議中にいちばん使うミュートを置く。
    /// モックから外したもの: 退出 ⌘W（macOS の欄では「現在のウインドウを閉じる」で、退出の割り当ては無い）
    /// 録画 ⇧⌘R は「コンピューターへの録画の開始 / 停止」
    static var zoom: AppPreset {
        PresetBuilder.preset(
            KnownApp.zoom,
            category: "会議",
            cells: [
                PresetBuilder.key("ビデオ", "video", .key("v", [.shift, .command])),
                PresetBuilder.key("画面共有", "display", .key("s", [.shift, .command])),
                PresetBuilder.key("挙手", "hand.raised", .key("y", .option)),
                PresetBuilder.key("チャット", "bubble.left.and.bubble.right", .key("h", [.shift, .command])),
                PresetBuilder.key("ミュート", "mic.slash", .key("a", [.shift, .command])),
                PresetBuilder.key("参加者", "person.2", .key("u", .command)),
                PresetBuilder.key("表示切替", "square.grid.2x2", .key("w", [.shift, .command])),
                PresetBuilder.key("全画面", "arrow.up.left.and.arrow.down.right", .key("f", [.shift, .command])),
                PresetBuilder.key("録画", "record.circle", .key("r", [.shift, .command])),
            ],
            summary: { "ミュート、ビデオ、画面共有など\($0)個" }
        )
    }

    /// 出典: https://slack.com/help/articles/201374536-Slack-keyboard-shortcuts （Mac の欄）
    /// 会話の切り替え ⌘K は Mac の欄に載っていないので使わない。
    /// 中央: 読んでいるメッセージを選んで訳すことが多いので翻訳
    static var slack: AppPreset {
        PresetBuilder.preset(
            KnownApp.slack,
            category: "チャット",
            cells: [
                PresetBuilder.key("新規メッセージ", "square.and.pencil", .key("n", .command)),
                PresetBuilder.key("検索", "magnifyingglass", .key("g", .command)),
                PresetBuilder.key("全未読", "tray.full", .key("a", [.shift, .command])),
                PresetBuilder.key("スレッド", "bubble.left.and.bubble.right", .key("t", [.shift, .command])),
                PresetBuilder.translate(),
                PresetBuilder.key("アクティビティ", "bell", .key("m", [.shift, .command])),
                PresetBuilder.key("DM", "bubble.left", .key("k", [.shift, .command])),
                PresetBuilder.key("ステータス", "face.smiling", .key("y", [.shift, .command])),
                // ハドルミーティングの開始・参加・退出を切り替える
                PresetBuilder.key("ハドル", "headphones", .key("h", [.shift, .command])),
            ],
            summary: { "スレッド、翻訳、ハドルなど\($0)個" }
        )
    }

    /// 出典: https://support.microsoft.com/en-us/office/keyboard-shortcuts-for-microsoft-teams-2e8e2a70-e8d8-4a19-949b-4c36dd5292d2
    /// （新しい Teams の Mac の欄）。⌘1〜⌘9 はアプリバーの並び順で変わるので使わない。
    /// 通話の終了 ⇧⌘H は押し間違えると会議から抜けてしまうので入れない。
    /// 中央: 長いチャットを選んで読むことが多いので要約
    static var teams: AppPreset {
        PresetBuilder.preset(
            KnownApp.teams,
            category: "チャット",
            cells: [
                PresetBuilder.key("新規チャット", "square.and.pencil", .key("n", .command)),
                PresetBuilder.key("検索", "magnifyingglass", .key("e", .command)),
                PresetBuilder.key("チャットへ移動", "arrow.right.circle", .key("g", .command)),
                PresetBuilder.key("未読", "tray.full", .key("u", [.option, .command])),
                PresetBuilder.summarize(),
                PresetBuilder.key("メンション", "at", .key("m", [.option, .command])),
                PresetBuilder.key("ミュート", "mic.slash", .key("m", [.shift, .command])),
                PresetBuilder.key("ビデオ", "video", .key("o", [.shift, .command])),
                // 共有するコンテンツのトレイを開く
                PresetBuilder.key("画面共有", "display", .key("e", [.shift, .command])),
            ],
            summary: { "ミュート、検索、要約など\($0)個" }
        )
    }

    /// 出典: https://support.apple.com/guide/mail/keyboard-shortcuts-mlhlb94f262b/mac
    /// 中央: 受け取ったメールを選んで読むことが多いので要約（受信したメールは書き換えられないので結果は表示）
    static var mail: AppPreset {
        PresetBuilder.preset(
            KnownApp.mail,
            category: "メール",
            cells: [
                PresetBuilder.key("新規メール", "square.and.pencil", .key("n", .command)),
                PresetBuilder.key("返信", "arrowshape.turn.up.left", .key("r", .command)),
                PresetBuilder.key("全員に返信", "arrowshape.turn.up.left.2", .key("r", [.shift, .command])),
                PresetBuilder.key("転送", "arrowshape.turn.up.right", .key("f", [.shift, .command])),
                PresetBuilder.summarize(),
                PresetBuilder.key("アーカイブ", "archivebox", .key("a", [.control, .command])),
                PresetBuilder.key("受信", "tray.and.arrow.down", .key("n", [.shift, .command])),
                PresetBuilder.key("既読/未読", "envelope.badge", .key("u", [.shift, .command])),
                PresetBuilder.key("送信", "paperplane", .key("d", [.shift, .command])),
            ],
            summary: { "返信、アーカイブ、要約など\($0)個" }
        )
    }
}
