// 担当: ui-shell
import AppKit
@testable import NonetUI
import Testing

/// ⌘V などを受けたかを数える文字の欄
private final class ShellPasteSpyTextView: NSTextView {
    private(set) var pasteCount = 0
    private(set) var selectAllCount = 0

    override func paste(_ sender: Any?) {
        pasteCount += 1
    }

    override func selectAll(_ sender: Any?) {
        selectAllCount += 1
        super.selectAll(sender)
    }
}

@Suite("メインメニュー", .serialized)
@MainActor
struct ShellMainMenuTests {
    struct Expected: CustomStringConvertible {
        var title: String
        var action: String?
        var key: String
        var modifiers: NSEvent.ModifierFlags

        var description: String { title }
    }

    static func make(onAbout: @escaping () -> Void = {}, onOpenSettings: @escaping () -> Void = {}) -> NSMenu {
        ShellMainMenu.make(onAbout: onAbout, onOpenSettings: onOpenSettings)
    }

    static func items(_ menu: NSMenu?) -> [Expected] {
        (menu?.items ?? []).filter { !$0.isSeparatorItem }.map { item in
            Expected(
                title: item.title,
                action: item.action.map(NSStringFromSelector),
                key: item.keyEquivalent,
                modifiers: item.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask)
            )
        }
    }

    static func expect(_ actual: [Expected], _ expected: [Expected]) {
        #expect(actual.map(\.title) == expected.map(\.title))
        #expect(actual.map(\.action) == expected.map(\.action))
        #expect(actual.map(\.key) == expected.map(\.key))
        #expect(actual.map(\.modifiers.rawValue) == expected.map(\.modifiers.rawValue))
    }

    @Test("アプリ・編集・ウインドウの3つ")
    func topLevel() {
        let menu = Self.make()
        #expect(menu.items.count == 3)
        #expect(menu.items.allSatisfy { $0.submenu != nil })
        #expect(menu.items[1].submenu?.title == String(localized: "menu.edit", defaultValue: "編集", bundle: .nonetUI))
        #expect(menu.items[2].submenu?.title == L10n.ui("ウインドウ"))
    }

    @Test("アプリのメニュー: Nonet について・設定…（⌘,）・終了（⌘Q）")
    func appMenu() throws {
        _ = NSApplication.shared
        var about = 0
        var settings = 0
        let menu = Self.make(onAbout: { about += 1 }, onOpenSettings: { settings += 1 })
        let appMenu = try #require(menu.items.first?.submenu)
        let items = Self.items(appMenu)
        #expect(items.map(\.title) == [L10n.ui("Nonet について"), L10n.ui("設定…"), L10n.ui("終了")])
        #expect(items.map(\.key) == ["", ",", "q"])
        #expect(items.allSatisfy { $0.modifiers == .command })
        #expect(items[2].action == "terminate:")

        // 「Nonet について」と「設定…」は渡した動作を呼ぶ
        for item in appMenu.items.filter({ !$0.isSeparatorItem }).prefix(2) {
            appMenu.performActionForItem(at: appMenu.index(of: item))
        }
        #expect(about == 1)
        #expect(settings == 1)
    }

    @Test("編集のメニューは標準の動作を宛先なしで送る")
    func editMenu() throws {
        let edit = try #require(Self.make().items[1].submenu)
        Self.expect(Self.items(edit), [
            Expected(title: L10n.ui("取り消す"), action: "undo:", key: "z", modifiers: .command),
            Expected(title: L10n.ui("やり直す"), action: "redo:", key: "z", modifiers: [.command, .shift]),
            Expected(title: L10n.ui("カット"), action: "cut:", key: "x", modifiers: .command),
            Expected(title: L10n.ui("コピー"), action: "copy:", key: "c", modifiers: .command),
            Expected(title: L10n.ui("ペースト"), action: "paste:", key: "v", modifiers: .command),
            Expected(title: L10n.ui("ペーストしてスタイルを合わせる"), action: "pasteAsPlainText:", key: "v", modifiers: [.command, .option, .shift]),
            Expected(title: L10n.ui("削除"), action: "delete:", key: "", modifiers: []),
            Expected(title: L10n.ui("すべてを選択"), action: "selectAll:", key: "a", modifiers: .command),
        ])
        #expect(edit.items.allSatisfy { $0.target == nil })
    }

    @Test("ウインドウのメニュー: 閉じる（⌘W）・しまう（⌘M）")
    func windowMenu() throws {
        let window = try #require(Self.make().items[2].submenu)
        Self.expect(Self.items(window), [
            Expected(title: L10n.ui("閉じる"), action: "performClose:", key: "w", modifiers: .command),
            Expected(title: L10n.ui("しまう"), action: "performMiniaturize:", key: "m", modifiers: .command),
        ])
        #expect(window.items.allSatisfy { $0.target == nil })
    }

    @Test("メニューを入れると ⌘V・⌘A・⌘Z をメニューが受け、文字の欄の paste: などに渡す。無ければ誰も受けない")
    func keyEquivalentsReachTextView() throws {
        let app = NSApplication.shared
        let saved = app.mainMenu
        defer { app.mainMenu = saved }

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let textView = ShellPasteSpyTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        textView.string = "license"
        window.contentView?.addSubview(textView)
        #expect(window.makeFirstResponder(textView))

        // メニューが無ければ ⌘V はウインドウにも受けられず、文字の欄の keyDown に落ちて捨てられる（これまでの Nonet）
        app.mainMenu = nil
        #expect(app.mainMenu?.performKeyEquivalent(with: Self.commandKey("v", keyCode: 9, window: window)) != true)
        #expect(!window.performKeyEquivalent(with: Self.commandKey("v", keyCode: 9, window: window)))

        // メニューを入れると、メニューが ⌘V・⌘A・⌘Z を受ける（文字の欄の keyDown には落ちない）
        app.mainMenu = Self.make()
        let mainMenu = try #require(app.mainMenu)
        for (key, code) in [("v", UInt16(9)), ("a", 0), ("z", 6)] {
            #expect(mainMenu.performKeyEquivalent(with: Self.commandKey(key, keyCode: code, window: window)))
        }
        let items = ["v", "a", "z"].compactMap { Self.item(in: mainMenu, key: $0, modifiers: .command) }
        #expect(items.map { $0.action.map(NSStringFromSelector) } == ["paste:", "selectAll:", "undo:"])
        #expect(items.allSatisfy { $0.target == nil })

        // 宛先が nil なので、キーのウインドウで選ばれている文字の欄が受ける。
        // テストのプロセスはキーのウインドウを持てないので、AppKit が選ぶはずの宛先へ直接送る
        for item in items.prefix(2) {
            #expect(app.sendAction(try #require(item.action), to: textView, from: item))
        }
        #expect(textView.pasteCount == 1)
        #expect(textView.selectAllCount == 1)
    }

    static func item(in menu: NSMenu, key: String, modifiers: NSEvent.ModifierFlags) -> NSMenuItem? {
        for item in menu.items {
            if item.keyEquivalent == key, item.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask) == modifiers {
                return item
            }
            if let submenu = item.submenu, let found = Self.item(in: submenu, key: key, modifiers: modifiers) {
                return found
            }
        }
        return nil
    }

    static func commandKey(_ characters: String, keyCode: UInt16, window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )!
    }
}
