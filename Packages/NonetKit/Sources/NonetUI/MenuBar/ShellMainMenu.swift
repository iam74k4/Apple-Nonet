// 担当: ui-shell
import AppKit

/// アプリのメインメニュー。Nonet はメニューバーに常駐する（.accessory）ので画面の上には出ないが、
/// 設定や初回の案内のウィンドウがキーの間、⌘C・⌘V・⌘Z・⌘A・⌘W などのキーはこのメニューを通って文字の欄やウィンドウに届く。
/// メニューが無いと、ライセンスキーの欄に ⌘V で貼り付けられない
@MainActor
public enum ShellMainMenu {
    /// 起動時に App が NSApp.mainMenu に入れる。onAbout は「Nonet について」、onOpenSettings は「設定…」、
    /// onHelp は「Nonet ヘルプ」（⌘?。利用ガイドを開く。nil ならヘルプのメニューを出さない）、
    /// onQuit は「終了」（⌘Q。ShellQuitConfirmation で確かめてから終える。nil ならすぐ終える）
    public static func make(
        onAbout: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onHelp: (() -> Void)? = nil,
        onQuit: (() -> Void)? = nil
    ) -> NSMenu {
        let main = NSMenu(title: "Nonet")
        main.addItem(submenuItem(appMenu(onAbout: onAbout, onOpenSettings: onOpenSettings, onQuit: onQuit)))
        main.addItem(submenuItem(editMenu()))
        main.addItem(submenuItem(windowMenu()))
        if let onHelp {
            main.addItem(submenuItem(helpMenu(onHelp: onHelp)))
        }
        return main
    }

    private static func appMenu(onAbout: @escaping () -> Void, onOpenSettings: @escaping () -> Void, onQuit: (() -> Void)?) -> NSMenu {
        let menu = NSMenu(title: "Nonet")
        menu.addItem(closureItem(String(localized: "Nonet について", bundle: .module), onAbout))
        menu.addItem(.separator())
        menu.addItem(closureItem(String(localized: "設定…", bundle: .module), keyEquivalent: ",", onOpenSettings))
        menu.addItem(.separator())
        // ⌘Q はウインドウを閉じるつもりで押されやすい。終えるとトラックパッドから開かなくなるので、確かめてから終える
        if let onQuit {
            menu.addItem(closureItem(String(localized: "終了", bundle: .module), keyEquivalent: "q", onQuit))
        } else {
            menu.addItem(item(String(localized: "終了", bundle: .module), #selector(NSApplication.terminate(_:)), "q"))
        }
        return menu
    }

    /// 宛先を決めない（nil）ので、キーになっている文字の欄が受ける
    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "menu.edit", defaultValue: "編集", bundle: .module))
        menu.addItem(item(String(localized: "取り消す", bundle: .module), Selector(("undo:")), "z"))
        menu.addItem(item(String(localized: "やり直す", bundle: .module), Selector(("redo:")), "z", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "カット", bundle: .module), #selector(NSText.cut(_:)), "x"))
        menu.addItem(item(String(localized: "コピー", bundle: .module), #selector(NSText.copy(_:)), "c"))
        menu.addItem(item(String(localized: "ペースト", bundle: .module), #selector(NSText.paste(_:)), "v"))
        menu.addItem(item(
            String(localized: "ペーストしてスタイルを合わせる", bundle: .module),
            #selector(NSTextView.pasteAsPlainText(_:)),
            "v",
            [.command, .option, .shift]
        ))
        menu.addItem(item(String(localized: "削除", bundle: .module), #selector(NSText.delete(_:)), "", []))
        menu.addItem(item(String(localized: "すべてを選択", bundle: .module), #selector(NSText.selectAll(_:)), "a"))
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "ウインドウ", bundle: .module))
        menu.addItem(item(String(localized: "閉じる", bundle: .module), #selector(NSWindow.performClose(_:)), "w"))
        menu.addItem(item(String(localized: "しまう", bundle: .module), #selector(NSWindow.performMiniaturize(_:)), "m"))
        return menu
    }

    /// 設定や案内のウィンドウがキーの間、⌘? で利用ガイドを開く
    private static func helpMenu(onHelp: @escaping () -> Void) -> NSMenu {
        let menu = NSMenu(title: String(localized: "ヘルプ", bundle: .module))
        menu.addItem(closureItem(String(localized: "Nonet ヘルプ", bundle: .module), keyEquivalent: "?", onHelp))
        return menu
    }

    private static func submenuItem(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private static func item(
        _ title: String,
        _ action: Selector,
        _ keyEquivalent: String,
        _ modifiers: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    private static func closureItem(_ title: String, keyEquivalent: String = "", _ action: @escaping () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(ShellMainMenuTarget.runAction(_:)), keyEquivalent: keyEquivalent)
        // メニュー項目は target を保持しないので、ずっと残る1つに受けさせる
        item.target = ShellMainMenuTarget.shared
        item.representedObject = ShellMainMenuAction(action)
        return item
    }
}

/// メニュー項目の動作（representedObject に入れる）
private final class ShellMainMenuAction {
    let run: @MainActor () -> Void

    init(_ run: @escaping @MainActor () -> Void) {
        self.run = run
    }
}

private final class ShellMainMenuTarget: NSObject {
    static let shared = ShellMainMenuTarget()

    /// perform(_:) だと #selector が NSObject の performSelector: を指してしまう
    @objc func runAction(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? ShellMainMenuAction else { return }
        MainActor.assumeIsolated { action.run() }
    }
}
