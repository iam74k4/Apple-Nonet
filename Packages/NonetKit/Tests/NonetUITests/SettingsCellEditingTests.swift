// 担当: ui-settings
import Foundation
import NonetCore
@testable import NonetUI
import Testing

@Suite struct SettingsCellEditingTests {
    @Test func everyKindHasANameASymbolAndADefault() {
        // URL は「開く」の中で切り替えるので、一覧には並べない
        #expect(Set(SettingsActionKinds.ordered + [.openURL]) == Set(ActionKind.allCases))
        #expect(SettingsActionKinds.menuKind(of: .openURL(URLAction(url: ""))) == .launchApp)
        for kind in ActionKind.allCases {
            #expect(!SettingsActionKinds.name(kind).isEmpty)
            #expect(SettingsCellEditing.defaultAction(for: kind).kind == kind)
            // どの種類も、中身を決めるまでは実行できない。ただしファイルは「複製」、画面に置くは「最大化」から始まり、
            // 最近のスクショは決めることが無いので、すぐ使える
            let usableAtOnce: Set<ActionKind> = [.file, .placeWindow, .screenshots, .media]
            #expect(SettingsCellEditing.isIncomplete(SettingsCellEditing.defaultAction(for: kind)) == !usableAtOnce.contains(kind))
            let cell = SettingsCellEditing.newCell(kind: kind)
            #expect(cell.title.isEmpty)
            // ファイルは操作ごと、画面に置くは場所ごとのアイコン
            let expectedSymbol = switch kind {
            case .file: SettingsActionKinds.symbol(FileOperation.duplicate)
            case .placeWindow: WindowRegion.maximize.symbol
            case .media: MediaKey.playPause.symbol
            default: SettingsActionKinds.symbol(kind)
            }
            #expect(cell.icon == .symbol(expectedSymbol))
        }
    }

    /// 「テキストを貼る」は最初の1文字のアイコン（いくつあっても HUD で見分けられる）。空なら種類のアイコン
    @Test func pasteTextIconsUseTheFirstCharacter() {
        #expect(SettingsCellEditing.defaultIcon(for: .pasteText(PasteTextAction(text: "  署名\n岡崎"))) == .text("署"))
        #expect(SettingsCellEditing.defaultIcon(for: .pasteText(PasteTextAction(text: ""))) == .symbol(SettingsActionKinds.symbol(.pasteText)))
    }

    @Test func newCellsGetAutomaticTitlesFromTheirAction() {
        let cell = SettingsCellEditing.newCell(kind: .keystroke)
        let updated = SettingsCellEditing.replacingAction(.keystroke(.key("b", .command)), in: cell)
        #expect(updated.title == "⌘B")
        #expect(updated.icon == .symbol("keyboard"))
        #expect(updated.id == cell.id)
    }

    @Test func userTitlesAndIconsAreKept() {
        let cell = Cell(title: "ビルド", icon: .symbol("hammer"), action: .keystroke(.key("b", .command)))
        let updated = SettingsCellEditing.replacingAction(.keystroke(.key("r", .command)), in: cell)
        #expect(updated.title == "ビルド")
        #expect(updated.icon == .symbol("hammer"))
        #expect(updated.action == .keystroke(.key("r", .command)))
    }

    @Test func choosingAnAppUsesItsNameAndIcon() {
        var cell = SettingsCellEditing.newCell(kind: .launchApp)
        cell = SettingsCellEditing.choosingApp(SettingsFixtures.figma, in: cell)
        #expect(cell.title == "Figma")
        #expect(cell.icon == .app(bundleID: SettingsFixtures.figma.bundleID))
        // 自動で付いた名前とアイコンは、選び直すと付け替わる
        cell = SettingsCellEditing.choosingApp(SettingsFixtures.notes, in: cell)
        #expect(cell.title == "メモ")
        #expect(cell.icon == .app(bundleID: SettingsFixtures.notes.bundleID))
    }

    @Test func choosingAnAppKeepsHideIfFrontmost() {
        let cell = Cell(title: "Safari", icon: .app(bundleID: SettingsFixtures.safari.bundleID),
                        action: .launchApp(LaunchAppAction(app: SettingsFixtures.safari, hideIfFrontmost: true)))
        let updated = SettingsCellEditing.choosingApp(SettingsFixtures.figma, in: cell)
        #expect(updated.action == .launchApp(LaunchAppAction(app: SettingsFixtures.figma, hideIfFrontmost: true)))
    }

    @Test func changingKindUsesTheRememberedAction() {
        let script = Action.script(ScriptAction(source: "say hi", runMode: .terminal, timeout: 30))
        let cell = Cell(title: "", icon: .symbol("terminal"), action: script)
        let asKeys = SettingsCellEditing.changingKind(of: cell, to: .keystroke)
        #expect(asKeys.action == .keystroke(KeySequence([])))
        #expect(asKeys.icon == .symbol("keyboard"))
        let back = SettingsCellEditing.changingKind(of: asKeys, to: .script, remembered: script)
        #expect(back.action == script)
        // 種類の違う記憶は使わない
        let url = SettingsCellEditing.changingKind(of: asKeys, to: .openURL, remembered: script)
        #expect(url.action == .openURL(URLAction(url: "")))
        // 同じ種類なら何もしない
        #expect(SettingsCellEditing.changingKind(of: cell, to: .script) == cell)
    }

    @Test func changingKindKeepsAUserTitle() {
        let cell = Cell(title: "Claude Code", icon: .symbol("sparkles"), action: .script(ScriptAction(source: "claude")))
        let changed = SettingsCellEditing.changingKind(of: cell, to: .ai)
        #expect(changed.title == "Claude Code")
        #expect(changed.icon == .symbol("sparkles"))
    }

    @Test func assigningAMenuItemSetsPathKeyAndTitle() {
        let item = MenuItemNode(title: "自動レイアウトを追加", path: ["オブジェクト", "自動レイアウトを追加"], keyEquivalent: .key("a", .shift))
        let created = SettingsCellEditing.assigningMenuItem(item, app: SettingsFixtures.figma, to: nil)
        #expect(created.title == "自動レイアウトを追加")
        #expect(created.icon == .symbol("filemenu.and.selection"))
        #expect(created.action == .menuItem(MenuItemAction(app: SettingsFixtures.figma, path: item.path, keyEquivalent: .key("a", .shift))))

        let existing = Cell(title: "マイ項目", icon: .symbol("star"), action: .keystroke(.key("x", .command)))
        let replaced = SettingsCellEditing.assigningMenuItem(item, app: nil, to: existing)
        #expect(replaced.id == existing.id)
        #expect(replaced.title == "自動レイアウトを追加")
        #expect(replaced.icon == .symbol("star"))
    }

    @Test func incompleteActions() {
        #expect(SettingsCellEditing.isIncomplete(.openURL(URLAction(url: "  "))))
        #expect(!SettingsCellEditing.isIncomplete(.openURL(URLAction(url: "example.com"))))
        #expect(SettingsCellEditing.isIncomplete(.launchApp(LaunchAppAction(app: AppReference(bundleID: " ", name: "x")))))
        #expect(!SettingsCellEditing.isIncomplete(.menuItem(MenuItemAction(path: ["編集", "コピー"]))))
        #expect(SettingsCellEditing.automaticTitle(for: .ai(AIAction(prompt: ""))) == L10n.ui("AI"))
        #expect(SettingsCellEditing.automaticTitle(for: .openURL(URLAction(url: "https://www.example.com/a"))) == "example.com")
    }

    @Test(arguments: [(-5.0, 1.0), (0.4, 1.0), (59.6, 60.0), (90, 90), (99_999, 3600), (Double.nan, 60), (Double.infinity, 60)])
    func timeoutIsClamped(input: Double, expected: Double) {
        #expect(SettingsCellEditing.clampedTimeout(input) == expected)
    }
}

@Suite struct SettingsURLCheckTests {
    @Test(arguments: [
        ("", SettingsURLCheck.empty),
        ("   ", .empty),
        ("https://example.com/path?q=1", .valid),
        ("obsidian://open?vault=Notes", .valid),
        ("mailto:someone@example.com", .valid),
        ("example.com", .addsScheme("https")),
        ("example.com:8080/a", .addsScheme("https")),
        ("localhost:3000", .addsScheme("http")),
        ("[::1]:3000", .addsScheme("http")),
        ("//example.com", .addsScheme("https")),
        ("/Users/me/Documents", .file),
        ("~/Desktop", .file),
        ("https://", .invalid),
        ("https:///path", .invalid),
        ("exa mple.com", .invalid),
        ("http://exa mple.com", .invalid),
    ])
    func classifies(input: String, expected: SettingsURLCheck) {
        #expect(SettingsURLCheck(input) == expected)
    }

    @Test func messages() {
        #expect(SettingsURLCheck("https://example.com").message == nil)
        #expect(SettingsURLCheck("example.com").message == L10n.ui("開くときに \("https"):// を補います"))
        #expect(SettingsURLCheck("exa mple").isProblem)
        #expect(SettingsURLCheck("~/a").message != nil)
    }
}
