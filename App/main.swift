import AppKit
import NonetUI

let launchOptions = ShellLaunchOptions.parse(CommandLine.arguments)

// 画面を出さずに確かめて終わる（初回の案内も設定も開かない）
if launchOptions.selfCheck {
    let status = MainActor.assumeIsolated { SelfCheck.run() }
    exit(status)
}

MainActor.assumeIsolated {
    // 同じ Nonet が2つ動くと、1回のタップでマスが2回実行される。もう動いていたらそちらに任せて終わる。
    // ただし、ディスクイメージなどから開いたこちらの方が新しければ、動いている方を終わらせてから起動し、
    // アプリケーションフォルダへ移す（置き換える）かを AppDelegate で尋ねる。新しくなければ、伝えてから終わる。
    // DEBUG ビルドで設定の置き場所を分けたとき（見た目の確認）は、配布版と並べて動かしてよい
    #if DEBUG
    let allowsMultiple = launchOptions.configDirectory != nil
    #else
    let allowsMultiple = false
    #endif
    SingleInstance.handOffIfAlreadyRunning(allowsMultiple: allowsMultiple)

    let app = NSApplication.shared
    let delegate = AppDelegate(options: launchOptions)
    app.delegate = delegate
    // メニューバーに常駐する（Dock には出さない）
    app.setActivationPolicy(.accessory)
    app.run()
}
