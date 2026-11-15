// 担当: presets（スクリプトとショートカットの書式。前の版の「結果の出し方」は読み飛ばす）
import Foundation
import Testing
@testable import NonetCore

@Suite struct ActionOutputCodingTests {
    @Test func theFormatHasNoOutputKey() throws {
        let cases: [(Action, String)] = [
            (.script(ScriptAction(source: "make")),
             #"{"type":"script","source":"make","runMode":"background","timeout":60}"#),
            (.shortcut(ShortcutAction(name: "集中")),
             #"{"type":"shortcut","name":"集中","passSelectedText":false}"#),
        ]
        for (action, json) in cases {
            #expect(try ModelFixtures.jsonObject(action) == ModelFixtures.jsonObject(json), "\(json)")
            #expect(try ModelFixtures.decode(Action.self, json) == action, "\(json)")
        }
    }

    /// 前の版の「結果の出し方」（output）が書いてあっても読み飛ばし、書き直すと残らない
    @Test func anOldOutputKeyIsIgnored() throws {
        let script = try ModelFixtures.decode(Action.self, #"{"type": "script", "source": "ls", "runMode": "background", "timeout": 30, "output": "copyToClipboard"}"#)
        #expect(script == .script(ScriptAction(source: "ls", timeout: 30)))
        #expect(try ModelFixtures.jsonObject(script)["output"] == nil)
        let shortcut = try ModelFixtures.decode(Action.self, #"{"type": "shortcut", "name": "n", "passSelectedText": true, "output": "replaceSelection"}"#)
        #expect(shortcut == .shortcut(ShortcutAction(name: "n", passSelectedText: true)))
        #expect(try ModelFixtures.jsonObject(shortcut)["output"] == nil)
    }
}
