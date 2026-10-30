// 担当: presets（スクリプトとショートカットの結果の出し方の書式）
import Foundation
import Testing
@testable import NonetCore

/// スクリプト（裏で実行）とショートカットの output。使わない設定は、項目を足す前と同じ書式
@Suite struct ActionOutputCodingTests {
    @Test func outputIsWrittenOnlyWhenUsed() throws {
        let cases: [(Action, String)] = [
            (.script(ScriptAction(source: "uuidgen", output: .copyToClipboard)),
             #"{"type":"script","source":"uuidgen","runMode":"background","timeout":60,"output":"copyToClipboard"}"#),
            (.script(ScriptAction(source: "make")),
             #"{"type":"script","source":"make","runMode":"background","timeout":60}"#),
            (.shortcut(ShortcutAction(name: "整形", passSelectedText: true, output: .replaceSelection)),
             #"{"type":"shortcut","name":"整形","passSelectedText":true,"output":"replaceSelection"}"#),
            (.shortcut(ShortcutAction(name: "集中")),
             #"{"type":"shortcut","name":"集中","passSelectedText":false}"#),
        ]
        for (action, json) in cases {
            #expect(try ModelFixtures.jsonObject(action) == ModelFixtures.jsonObject(json), "\(json)")
            #expect(try ModelFixtures.decode(Action.self, json) == action, "\(json)")
        }
    }

    @Test func oldConfigurationsIgnoreTheOutput() throws {
        // 項目を足す前の設定は「出力を使わない」
        let script = try ModelFixtures.decode(Action.self, #"{"type": "script", "source": "ls", "runMode": "background", "timeout": 30}"#)
        #expect(script == .script(ScriptAction(source: "ls", timeout: 30, output: nil)))
        let shortcut = try ModelFixtures.decode(Action.self, #"{"type": "shortcut", "name": "n", "passSelectedText": true}"#)
        #expect(shortcut == .shortcut(ShortcutAction(name: "n", passSelectedText: true, output: nil)))
    }

    @Test func unknownOrNullOutputIsIgnored() throws {
        // 知らない値で、勝手に貼り付けやコピーを始めない
        for value in [#""speak""#, "null", "3", #"{"a": 1}"#] {
            let script = try ModelFixtures.decode(Action.self, #"{"type": "script", "source": "ls", "output": \#(value)}"#)
            #expect(script == .script(ScriptAction(source: "ls")), "\(value)")
            let shortcut = try ModelFixtures.decode(Action.self, #"{"type": "shortcut", "name": "n", "output": \#(value)}"#)
            #expect(shortcut == .shortcut(ShortcutAction(name: "n")), "\(value)")
        }
    }

    @Test(arguments: AIOutput.allCases)
    func everyOutputRoundTrips(output: AIOutput) throws {
        let script = Action.script(ScriptAction(source: "date", runMode: .background, timeout: 5, output: output))
        #expect(try ModelFixtures.roundTrip(script) == script)
        let shortcut = Action.shortcut(ShortcutAction(name: "s", output: output))
        #expect(try ModelFixtures.roundTrip(shortcut) == shortcut)
    }

    @Test func validatedKeepsTheOutput() {
        let action = Action.script(ScriptAction(source: "x", timeout: .infinity, output: .showResult))
        guard case .script(let script) = action.validated() else {
            Issue.record("スクリプトのまま")
            return
        }
        #expect(script.output == .showResult)
        #expect(script.timeout == ScriptAction.defaultTimeout)
    }
}
