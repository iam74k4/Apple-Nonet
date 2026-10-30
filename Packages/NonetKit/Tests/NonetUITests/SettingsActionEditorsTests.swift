// 担当: ui-settings（アクションの編集欄）
// スクリプト（裏で実行）とショートカットの「結果の出し方」
import AppKit
import NonetCore
@testable import NonetUI
import SwiftUI
import Testing

@Suite @MainActor struct SettingsActionEditorsTests {
    @Test func outputChoicesStartWithIgnoreThenTheAIChoices() {
        #expect(SettingsCommandOutput.choices == [nil, .replaceSelection, .copyToClipboard, .showResult])
    }

    @Test func outputNamesMatchTheAIEditor() {
        #expect(SettingsCommandOutput.name(nil) == L10n.ui("出力を使わない"))
        // AI と同じ言葉
        for output in AIOutput.allCases {
            #expect(SettingsCommandOutput.name(output) == SettingsText.name(output))
        }
        #expect(SettingsCommandOutput.name(.showResult) == L10n.ui("画面に表示"))
    }

    @Test func choosingAnOutputIsSaved() throws {
        let h = try SettingsHarness()
        h.model.createCell(kind: .script, at: 1)
        let script = try #require(h.model.selectedCell?.id)
        h.model.updateAction(ofCell: script, as: ScriptAction.self) { $0.output = .copyToClipboard }
        h.model.pendingEdits.flushAll()
        guard case .script(let saved)? = try h.saved()?.globalProfile.pages[0].cells[1]?.action else {
            Issue.record("スクリプトのマスが無い")
            return
        }
        #expect(saved.output == .copyToClipboard)

        let other = try SettingsHarness()
        other.model.createCell(kind: .shortcut, at: 1)
        let shortcut = try #require(other.model.selectedCell?.id)
        other.model.updateAction(ofCell: shortcut, as: ShortcutAction.self) { $0.output = .replaceSelection }
        other.model.pendingEdits.flushAll()
        guard case .shortcut(let savedShortcut)? = try other.saved()?.globalProfile.pages[0].cells[1]?.action else {
            Issue.record("ショートカットのマスが無い")
            return
        }
        #expect(savedShortcut.output == .replaceSelection)
    }

    // MARK: - 画面

    @Test func outputChoicesAppearOnlyForBackgroundScripts() {
        // ターミナルで実行するときは、出力はターミナルのウインドウに出る
        #expect(SettingsScriptEditor.showsOutput(ScriptAction(source: "date", runMode: .background)))
        #expect(!SettingsScriptEditor.showsOutput(ScriptAction(source: "claude", runMode: .terminal, output: .showResult)))
    }
}
