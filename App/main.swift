import AppKit
import NonetUI

let launchOptions = ShellLaunchOptions.parse(CommandLine.arguments)

// 画面を出さずに確かめて終わる（初回の案内も設定も開かない）
if launchOptions.selfCheck {
    let status = MainActor.assumeIsolated { SelfCheck.run() }
    exit(status)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate(options: launchOptions)
    app.delegate = delegate
    // メニューバーに常駐する（Dock には出さない）
    app.setActivationPolicy(.accessory)
    app.run()
}
