// 担当: presets
// グローバルの「ユーティリティ」のページ。どのアプリの前でも同じ、macOS のショートカットと短いスクリプト。
//
// 選び方:
// - トラックパッドの操作で既に出せるもの（Mission Control・アプリの一覧・デスクトップの切り替え・デスクトップの表示）は入れない
// - 許可を増やさない。キーは今のアクセシビリティの許可で送り、スクリプトは許可の要らないコマンドだけにする。
//   例外は「最近のスクショ」: 初めて使うときだけ、macOS がスクリーンショットの保存先（既定はデスクトップ）を読む許可を求める。
//   撮ったスクリーンショットをすぐ添付する、撮影のマスと組で使うものなので、撮影の並びの近くに置く
// - 入れないもの: ダークモードの切り替え（System Events のオートメーションの許可が要る）、集中モード（標準のキーが無く、
//   利用者が作るショートカットが前提）、ゴミ箱を空にする（元に戻せない）、音量・明るさの上げ下げ（今のキーの送り方では
//   メディアキーを送れない）、強制終了 ⌥⌘Esc（アプリが送ったキーでは macOS が「アプリケーションの強制終了」を開かない。
//   2026-11-18 に macOS 26 で、KeySender と同じ送り方でも修飾キーを1つずつ押す送り方でも開かなかった。
//   Apple メニューの項目を押す作りは、メニューの名前が言語で変わるうえ、止まったアプリの前では効かないので取らない）
// - 撮影・収録・ロックのキーは macOS 全体のショートカット。システム設定で変えた・オフにした Mac では効かない
//   （利用ガイドの「ユーティリティ」に書いてある）
//
// 出典:
// - ⇧⌘3・⇧⌘4・⇧⌘5: https://support.apple.com/en-us/102646 と https://support.apple.com/en-us/102650
// - ⌃⇧⌘4（選んだ範囲をクリップボードへ）: システム設定 › キーボード › キーボードショートカット › スクリーンショット の既定
//   （com.apple.symbolichotkeys の 31。前の版の画面の撮影のアクションが読んでいたものと同じ）
// - 収録を止める ⌃⌘Esc: https://support.apple.com/en-us/102618
// - 画面をロック ⌃⌘Q・絵文字と記号 ⌃⌘Space: https://support.apple.com/en-us/102650
import Foundation

extension PresetData {
    /// 上の段は撮影と収録。中央は、撮ってそのままチャットや書類に貼れる「撮影してコピー」（指を置きやすく、
    /// 迷った指が止まっても困らない: 範囲を選ぶ画面が出るだけで、Esc でやめられる）。
    /// 中の段の左は文字を入れる前に開く絵文字と記号、右は撮ったスクリーンショットを添付する「最近のスクショ」（Spotlight は ⌘Space で
    /// 誰でも開けるので、ここには置かない）。下の段は、どのアプリにも無いが時々要るもの。
    /// 画面をロックは、押し間違えるとパスワードを打ち直すことになるので少し長く止めてから実行する
    static var utilityPage: Page {
        Page(
            cells: [
                PresetBuilder.captureArea(),
                PresetBuilder.key("撮影と収録", "camera.viewfinder", .key("5", [.shift, .command])),
                PresetBuilder.key("収録を止める", "stop.circle", .special(.escape, [.control, .command])),
                PresetBuilder.key("絵文字と記号", "face.smiling", .special(.space, [.control, .command])),
                PresetBuilder.key("撮影してコピー", "rectangle.dashed.and.paperclip", .key("4", [.control, .shift, .command])),
                Cell(title: PresetBuilder.text("最近のスクショ"), icon: .symbol("photo.on.rectangle"), action: .screenshots(ScreenshotTrayAction())),
                PresetBuilder.script("消音の切り替え", "speaker.slash", ScriptAction(source: muteToggleScript)),
                PresetBuilder.script("画面を消す", "moon.zzz", ScriptAction(source: "pmset displaysleepnow")),
                PresetBuilder.holdBeforeRunning(PresetBuilder.key("画面をロック", "lock.display", .key("q", [.control, .command]))),
            ],
            name: PresetBuilder.text("ユーティリティ")
        )
    }

    /// 出力の音を消す・戻す。AppleScript の標準の命令（set volume）なので、オートメーションの許可は要らない。
    /// 何も出力しないので、結果のパネルは出ない。消音できない出力先（一部の HDMI など）では失敗のトーストになる
    static let muteToggleScript = "osascript -e 'set volume output muted not (output muted of (get volume settings))'"
}
