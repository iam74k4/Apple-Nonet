// 担当: core-model。Action.summary と Profile.name
// keystroke の summary は KeySequence.displayString（keys-license）に任せるので、ここでは試さない
import Foundation
@testable import NonetCore
import Testing

@Suite("アクションの説明とプロファイルの名前")
struct ModelSummaryTests {
    @Test("種類ごとの短い説明")
    func summaries() {
        let cases: [(Action, String)] = [
            (.launchApp(LaunchAppAction(app: ModelFixtures.xcode)), "Xcode"),
            (.launchApp(LaunchAppAction(app: AppReference(bundleID: "com.example.NoName", name: "  "))), "com.example.NoName"),
            (.openURL(URLAction(url: "https://developer.apple.com/documentation")), "developer.apple.com"),
            (.script(ScriptAction(source: "make", runMode: .background)), ModelFixtures.text("スクリプト")),
            (.script(ScriptAction(source: "claude", runMode: .terminal)), ModelFixtures.text("ターミナル")),
            (.shortcut(ShortcutAction(name: "マイクのミュート")), "マイクのミュート"),
            (.shortcut(ShortcutAction(name: " ")), ModelFixtures.text("ショートカット")),
            (.menuItem(MenuItemAction(path: ["オブジェクト", "自動レイアウトを追加"])), "自動レイアウトを追加"),
            (.menuItem(MenuItemAction(path: ["編集", ""])), "編集"),
            (.menuItem(MenuItemAction(path: [])), ModelFixtures.text("メニュー項目")),
            (.ai(AIAction(prompt: "要約して")), "AI"),
            (.file(FileAction(operation: .trash)), ModelFixtures.text("ゴミ箱に入れる")),
            (.file(FileAction(operation: .rename)), ModelFixtures.text("名前を変更")),
            (.file(FileAction(operation: .duplicate)), ModelFixtures.text("複製")),
        ]
        for (action, expected) in cases {
            #expect(action.summary == expected)
        }
    }

    @Test("URL はホスト名。www. は省き、スキームが無くても読む", arguments: [
        ("https://www.apple.com/jp/", "apple.com"),
        ("http://example.com:8080/path?q=1", "example.com"),
        ("github.com/iam74k4", "github.com"),
        ("  https://a.example  ", "a.example"),
        ("www.youtube.com", "youtube.com"),
        ("mailto:someone@example.com", "mailto:someone@example.com"),
        ("x-apple.systempreferences:com.apple.preference.security", "x-apple.systempreferences:com.apple.preference.security"),
    ])
    func urlHosts(_ url: String, _ expected: String) {
        #expect(Action.openURL(URLAction(url: url)).summary == expected)
    }

    @Test("空の URL は「URL」")
    func emptyURL() {
        #expect(Action.openURL(URLAction(url: "   ")).summary == "URL")
    }

    @Test("グローバルのプロファイルは「グローバル」、アプリはアプリ名")
    func profileNames() {
        #expect(Profile(kind: .global).name == ModelFixtures.globalName)
        #expect(Profile(kind: .app(ModelFixtures.figma)).name == "Figma")
        #expect(Profile(kind: .app(AppReference(bundleID: "com.example.x", name: ""))).name == "com.example.x")
    }

    @Test("アクションの種類")
    func kinds() {
        #expect(ModelFixtures.nonKeystrokeActions.map(\.kind) == [.launchApp, .openURL, .script, .shortcut, .menuItem, .ai, .file])
        #expect(Action.keystroke(.key("a")).kind == .keystroke)
    }
}
