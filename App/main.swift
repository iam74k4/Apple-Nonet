import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // メニューバーに常駐する（Dock には出さない）
    app.setActivationPolicy(.accessory)
    app.run()
}
