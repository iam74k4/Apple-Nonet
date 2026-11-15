// 担当: presets
// 会議・チャット・メールのプリセット
import Foundation

extension PresetData {
    /// 出典: https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0067050 （macOS の欄）
    /// 中央: 選択中のテキストが無いので AI ではなく、会議中にいちばん使うミュートを置く。
    /// モックから外したもの: 退出 ⌘W（macOS の欄では「現在のウインドウを閉じる」で、退出の割り当ては無い）
    /// 録画 ⇧⌘R は「コンピューターへの録画の開始 / 停止」
    /// 少し長く止めてから実行する（PresetBuilder.holdBeforeRunning）: ビデオ・画面共有・挙手・録画。押し間違えると参加者みんなに見える
    /// （録画は参加者に知らされる）。ミュートは咳や物音ですぐに切り替えたいので付けない
    static var zoom: AppPreset {
        PresetBuilder.preset(
            KnownApp.zoom,
            category: "会議",
            cells: [
                PresetBuilder.holdBeforeRunning(PresetBuilder.key("ビデオ", "video", .key("v", [.shift, .command]))),
                PresetBuilder.holdBeforeRunning(PresetBuilder.key("画面共有", "display", .key("s", [.shift, .command]))),
                PresetBuilder.holdBeforeRunning(PresetBuilder.key("挙手", "hand.raised", .key("y", .option))),
                PresetBuilder.key("チャット", "bubble.left.and.bubble.right", .key("h", [.shift, .command])),
                PresetBuilder.key("ミュート", "mic.slash", .key("a", [.shift, .command])),
                PresetBuilder.key("参加者", "person.2", .key("u", .command)),
                PresetBuilder.key("表示切替", "square.grid.2x2", .key("w", [.shift, .command])),
                PresetBuilder.key("全画面", "arrow.up.left.and.arrow.down.right", .key("f", [.shift, .command])),
                PresetBuilder.holdBeforeRunning(PresetBuilder.key("録画", "record.circle", .key("r", [.shift, .command]))),
            ],
            summary: { "ミュート、ビデオ、画面共有など\($0)個" }
        )
    }

    /// 出典: https://slack.com/help/articles/201374536-Slack-keyboard-shortcuts （Mac の欄）
    /// - 会話へ移動 ⌘K はこの一覧の Mac の欄には無いが、Slack のヘルプ「Navigate Slack with your keyboard」の
    ///   「Open a conversation」に「Press ⌘ K (Mac) or Ctrl K (Windows/Linux)」とある:
    ///   https://slack.com/help/articles/115003340723-Navigate-Slack-with-your-keyboard
    /// ハドル ⇧⌘H は「開始・参加・退出・終了」を1つのキーで切り替えるので入れない（Teams の ⇧⌘H と同じ理由）。
    /// 押し間違えると通話から抜けたり、マイクをオンにしてチャンネルにハドルを始めたりしてしまう。canvas では検索と置換にもなる。
    /// 外したもの: ステータス ⇧⌘Y（毎日は使わない）。代わりに、いちばん使う会話へ移動 ⌘K
    /// 中央: 読んでいるメッセージを選んで訳すことが多いので翻訳。AI を使えない Mac では会話へ移動を中央に移す
    static func slack(_ capabilities: PresetCapabilities) -> AppPreset {
        PresetBuilder.preset(
            KnownApp.slack,
            category: "チャット",
            cells: PresetBuilder.aiCentered([
                PresetBuilder.key("新規メッセージ", "square.and.pencil", .key("n", .command)),
                PresetBuilder.key("検索", "magnifyingglass", .key("g", .command)),
                PresetBuilder.key("全未読", "tray.full", .key("a", [.shift, .command])),
                PresetBuilder.key("スレッド", "bubble.left.and.bubble.right", .key("t", [.shift, .command])),
                PresetBuilder.translate(),
                PresetBuilder.key("アクティビティ", "bell", .key("m", [.shift, .command])),
                PresetBuilder.key("DM", "bubble.left", .key("k", [.shift, .command])),
                // 名前を入れてチャンネルか DM を開く。押し間違えても入力欄が開くだけ
                PresetBuilder.key("会話へ移動", "arrow.right.circle", .key("k", .command)),
                // 次の未読のチャンネルか DM へ移る。押し間違えても移動するだけ
                PresetBuilder.key("次の未読", "arrow.down.circle", .special(.downArrow, [.option, .shift])),
            ], fallbackIndex: 7, filler: PresetBuilder.key("前の未読", "arrow.up.circle", .special(.upArrow, [.option, .shift])), capabilities),
            summary: { count in
                if capabilities.appleIntelligence {
                    "スレッド、翻訳、未読など\(count)個"
                } else {
                    "スレッド、未読、会話へ移動など\(count)個"
                }
            }
        )
    }

    /// 出典: https://support.microsoft.com/en-us/office/keyboard-shortcuts-for-microsoft-teams-2e8e2a70-e8d8-4a19-949b-4c36dd5292d2
    /// （新しい Teams の Mac の欄）。⌘1〜⌘9 はアプリバーの並び順で変わるので使わない。
    /// 通話の終了 ⇧⌘H は押し間違えると会議から抜けてしまうので入れない。
    /// 少し長く止めてから実行する（PresetBuilder.holdBeforeRunning）: ビデオと画面共有（Zoom と同じ。押し間違えると参加者に見える）。
    /// ミュートは咳や物音ですぐに切り替えたいので付けない
    /// 中央: 長いチャットを選んで読むことが多いので要約。AI を使えない Mac では、会議中にいちばん使うミュートを中央に移す
    static func teams(_ capabilities: PresetCapabilities) -> AppPreset {
        PresetBuilder.preset(
            KnownApp.teams,
            category: "チャット",
            cells: PresetBuilder.aiCentered([
                PresetBuilder.key("新規チャット", "square.and.pencil", .key("n", .command)),
                PresetBuilder.key("検索", "magnifyingglass", .key("e", .command)),
                PresetBuilder.key("チャットへ移動", "arrow.right.circle", .key("g", .command)),
                PresetBuilder.key("未読", "tray.full", .key("u", [.option, .command])),
                PresetBuilder.summarize(),
                PresetBuilder.key("メンション", "at", .key("m", [.option, .command])),
                PresetBuilder.key("ミュート", "mic.slash", .key("m", [.shift, .command])),
                PresetBuilder.holdBeforeRunning(PresetBuilder.key("ビデオ", "video", .key("o", [.shift, .command]))),
                // 共有するコンテンツのトレイを開く（Zoom の画面共有と同じ印にそろえる）
                PresetBuilder.holdBeforeRunning(PresetBuilder.key("画面共有", "display", .key("e", [.shift, .command]))),
            // 挙手は Zoom と同じく、押し間違えると参加者に見えるので少し長く止めてから実行する
            ], fallbackIndex: 6, filler: PresetBuilder.holdBeforeRunning(PresetBuilder.key("挙手", "hand.raised", .key("k", [.shift, .command]))), capabilities),
            summary: { count in
                if capabilities.appleIntelligence {
                    "ミュート、検索、要約など\(count)個"
                } else {
                    // Zoom と同じ説明（どちらにもミュート・ビデオ・画面共有がある）
                    "ミュート、ビデオ、画面共有など\(count)個"
                }
            }
        )
    }

    /// 出典: https://support.apple.com/guide/mail/keyboard-shortcuts-mlhlb94f262b/mac
    /// 中央: 受け取ったメールを選んで読むことが多いので要約（受信したメールは書き換えられないので結果は表示）。
    /// AI を使えない Mac では、読み終えたメールを片付けるアーカイブを中央に移す
    /// 少し長く止めてから実行する（PresetBuilder.holdBeforeRunning）: 送信（送ったメールは取り消せない）。返信・転送は書く画面が開くだけなので付けない
    static func mail(_ capabilities: PresetCapabilities) -> AppPreset {
        PresetBuilder.preset(
            KnownApp.mail,
            category: "メール",
            cells: PresetBuilder.aiCentered([
                PresetBuilder.key("新規メール", "square.and.pencil", .key("n", .command)),
                PresetBuilder.key("返信", "arrowshape.turn.up.left", .key("r", .command)),
                PresetBuilder.key("全員に返信", "arrowshape.turn.up.left.2", .key("r", [.shift, .command])),
                PresetBuilder.key("転送", "arrowshape.turn.up.right", .key("f", [.shift, .command])),
                PresetBuilder.summarize(),
                PresetBuilder.key("アーカイブ", "archivebox", .key("a", [.control, .command])),
                PresetBuilder.key("受信", "tray.and.arrow.down", .key("n", [.shift, .command])),
                PresetBuilder.key("既読/未読", "envelope.badge", .key("u", [.shift, .command])),
                PresetBuilder.holdBeforeRunning(PresetBuilder.key("送信", "paperplane", .key("d", [.shift, .command]))),
            ], fallbackIndex: 5, filler: PresetBuilder.key("フラグ", "flag", .key("l", [.shift, .command])), capabilities),
            summary: { count in
                if capabilities.appleIntelligence {
                    "返信、アーカイブ、要約など\(count)個"
                } else {
                    "返信、アーカイブ、転送など\(count)個"
                }
            }
        )
    }
}
