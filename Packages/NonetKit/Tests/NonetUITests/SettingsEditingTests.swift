// 担当: ui-settings
// 打ちかけの確定（遅れて届く確定が、その間の変更を戻さないこと）と、スクリプトの欄が打った文字をそのまま残すこと
import AppKit
import NonetCore
@testable import NonetUI
import SwiftUI
import Testing

@Suite @MainActor struct SettingsDraftBufferTests {
    @Test func theDebouncedCommitCallsTheLatestClosure() async throws {
        var calls: [String] = []
        let buffer = SettingsDraftBuffer(value: "", delay: .milliseconds(20)) { calls.append("old:\($0)") }
        buffer.edit("echo hi")
        #expect(buffer.hasPendingEdit)
        // 待っている間に描き直され、書き込み先が替わった
        buffer.commit = { calls.append("new:\($0)") }
        await buffer.waitForPendingCommit()
        #expect(calls == ["new:echo hi"])
        #expect(!buffer.hasPendingEdit)
    }

    @Test func typingStopsTheEarlierTimer() async throws {
        var calls: [String] = []
        let buffer = SettingsDraftBuffer(value: "", delay: .milliseconds(30)) { calls.append($0) }
        buffer.edit("a")
        buffer.edit("ab")
        #expect(calls.isEmpty)
        await buffer.waitForPendingCommit()
        // 止めた最初の確定は、後から届かない
        try await Task.sleep(for: .milliseconds(100))
        #expect(calls == ["ab"])
    }

    @Test func outsideChangesReplaceTheFieldOnlyWhenNothingIsTyped() {
        var calls: [String] = []
        let buffer = SettingsDraftBuffer(value: "a", delay: .seconds(60)) { calls.append($0) }
        buffer.valueChanged("b")
        #expect(buffer.draft == "b")
        buffer.edit("bc")
        buffer.valueChanged("x")
        // 打ちかけは残す
        #expect(buffer.draft == "bc")
        buffer.flush()
        #expect(calls == ["bc"])
        // 確定した後は、ほかで整えた値（前後の空白を除いたものなど）に合わせる
        buffer.valueChanged("bc ")
        #expect(buffer.draft == "bc ")
    }

    @Test func flushingWithoutChangesDoesNotWrite() {
        var calls: [String] = []
        let buffer = SettingsDraftBuffer(value: "a", delay: .seconds(60)) { calls.append($0) }
        buffer.flush()
        buffer.edit("a")
        buffer.flush()
        // 打ってから元に戻した
        buffer.edit("ab")
        buffer.edit("a")
        buffer.flush()
        #expect(calls.isEmpty)
    }

    @Test func pendingEditsAreFlushedTogether() {
        let registry = SettingsPendingEdits()
        var calls: [String] = []
        let first = SettingsDraftBuffer(value: "", delay: .seconds(60)) { calls.append("1:\($0)") }
        let second = SettingsDraftBuffer(value: "", delay: .seconds(60)) { calls.append("2:\($0)") }
        first.registry = registry
        second.registry = registry
        first.edit("x")
        second.edit("y")
        #expect(registry.count == 2)
        second.flush()
        #expect(registry.count == 1)
        registry.flushAll()
        #expect(registry.count == 0)
        #expect(calls == ["2:y", "1:x"])
    }
}

/// 本物のインスペクタを画面に出さずに組み立て、欄に打ち込んで確かめる
@Suite(.serialized) @MainActor struct SettingsEditorHostingTests {
    @MainActor
    private final class Host {
        let window: NSWindow
        let view: NSView

        init<V: View>(_ root: V, size: CGSize = CGSize(width: 320, height: 760)) {
            _ = NSApplication.shared
            window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let hosting = NSHostingView(rootView: root.frame(width: size.width, height: size.height))
            hosting.frame = NSRect(origin: .zero, size: size)
            window.contentView = hosting
            view = hosting
        }

        func settle(_ milliseconds: Int = 60) async throws {
            view.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(milliseconds))
            view.layoutSubtreeIfNeeded()
        }

        func descendants<T: NSView>(_ type: T.Type) -> [T] {
            func walk(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(walk) }
            return walk(view).compactMap { $0 as? T }
        }

        /// 1文字ずつ打つ（スマート引用符などの置き換えは、1文字ずつ打ったときに起きる）
        func type(_ text: String, into textView: NSTextView) {
            window.makeFirstResponder(textView)
            for character in text {
                textView.insertText(String(character), replacementRange: textView.selectedRange())
            }
        }

        func type(_ text: String, intoFieldWithPlaceholder placeholder: String) throws {
            let field = try #require(descendants(NSTextField.self).first {
                $0.placeholderString == placeholder || $0.placeholderAttributedString?.string == placeholder
            })
            window.makeFirstResponder(field)
            let editor = try #require(field.currentEditor())
            editor.insertText(text)
        }

        func close() {
            window.contentView = nil
            window.close()
        }
    }

    private func inspector(_ h: SettingsHarness) -> some View {
        SettingsInspectorView(model: h.model)
            .environment(\.settingsPendingEdits, h.model.pendingEdits)
    }

    private static let script = "cd \"$PROJECT_DIR\" && git log --oneline -3 -- 'a b' # \"x\" ... (c)"

    @Test func theScriptEditorKeepsWhatWasTyped() async throws {
        var committed: [String] = []
        let registry = SettingsPendingEdits()
        let host = Host(
            SettingsCommitTextEditor(value: "", code: true, minHeight: 120, accessibilityLabel: "スクリプト") { committed.append($0) }
                .environment(\.settingsPendingEdits, registry),
            size: CGSize(width: 300, height: 140)
        )
        defer { host.close() }
        try await host.settle()
        let textView = try #require(host.descendants(NSTextView.self).first)
        #expect(!textView.isAutomaticQuoteSubstitutionEnabled)
        #expect(!textView.isAutomaticDashSubstitutionEnabled)
        #expect(!textView.isAutomaticTextReplacementEnabled)
        #expect(!textView.isAutomaticSpellingCorrectionEnabled)
        #expect(!textView.isContinuousSpellCheckingEnabled)
        #expect(!textView.smartInsertDeleteEnabled)
        #expect(!textView.isRichText)
        #expect(textView.accessibilityLabel() == "スクリプト")

        host.type(Self.script, into: textView)
        // 置き換えは少し遅れて行われるので待つ
        try await host.settle(400)
        #expect(textView.string == Self.script)
        registry.flushAll()
        #expect(committed == [Self.script])
    }

    /// 比べるための確認: 同じ欄で置き換えを有効に戻すと、同じ打ち方で “ と — になる（上のテストが空振りしていない）。
    /// CI（GitHub Actions の Mac）ではテキストの自動置き換えそのものが働かないので、手元でだけ確かめる
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil, "CI の Mac ではテキストの自動置き換えが働かない"))
    func theSameEditorWithSubstitutionsOnWouldReplaceQuotes() async throws {
        let host = Host(
            SettingsCommitTextEditor(value: "", code: true, minHeight: 120, accessibilityLabel: "スクリプト") { _ in },
            size: CGSize(width: 300, height: 140)
        )
        defer { host.close() }
        try await host.settle()
        let textView = try #require(host.descendants(NSTextView.self).first)
        textView.isAutomaticQuoteSubstitutionEnabled = true
        textView.isAutomaticDashSubstitutionEnabled = true
        host.type("echo \"hi\" --x ", into: textView)
        #expect(host.window.firstResponder === textView)
        try await host.settle(400)
        #expect(textView.string == "echo “hi” —x ")
    }

    @Test func typingThenChangingTheRunModeKeepsBoth() async throws {
        let h = try SettingsHarness()
        h.model.createCell(kind: .script, at: 1)
        let id = try #require(h.model.selectedCell?.id)
        let host = Host(inspector(h))
        defer { host.close() }
        try await host.settle()
        let textView = try #require(host.descendants(SettingsCodeNSTextView.self).first)
        host.type("echo hi", into: textView)
        // 確定を待たずに「ターミナルで実行」と制限時間を変えた（ピッカーとステッパーと同じ呼び方）
        h.model.updateAction(ofCell: id, as: ScriptAction.self) { $0.runMode = .terminal }
        try await host.settle(900)
        // 混んでいて確定がまだなら、ここで届ける（届くのはどちらにしても切り替えの後）
        h.model.pendingEdits.flushAll()
        #expect(h.model.cell(id: id)?.action == .script(ScriptAction(source: "echo hi", runMode: .terminal)))
        #expect(try h.saved()?.globalProfile.pages[0].cells[1]?.action == .script(ScriptAction(source: "echo hi", runMode: .terminal)))
    }

    @Test func typingThenTogglingPassSelectedTextKeepsBoth() async throws {
        let h = try SettingsHarness()
        h.model.createCell(kind: .shortcut, at: 1)
        let id = try #require(h.model.selectedCell?.id)
        let host = Host(inspector(h))
        defer { host.close() }
        try await host.settle()
        try host.type("翻訳", intoFieldWithPlaceholder: L10n.ui("ショートカットの名前"))
        h.model.updateAction(ofCell: id, as: ShortcutAction.self) { $0.passSelectedText = true }
        try await host.settle(700)
        h.model.pendingEdits.flushAll()
        #expect(h.model.cell(id: id)?.action == .shortcut(ShortcutAction(name: "翻訳", passSelectedText: true)))
    }

    @Test func typingThenChangingTheKindKeepsTheNewKind() async throws {
        let h = try SettingsHarness()
        h.model.createCell(kind: .openURL, at: 1)
        let id = try #require(h.model.selectedCell?.id)
        let host = Host(inspector(h))
        defer { host.close() }
        try await host.settle()
        try host.type("example.com", intoFieldWithPlaceholder: "https://example.com")
        h.model.changeKind(ofCell: id, to: .keystroke)
        // 欄が消えたときの確定や、待っていた確定が届いても種類は戻らない
        try await host.settle(700)
        #expect(h.model.cell(id: id)?.action == .keystroke(KeySequence([])))
        #expect(try h.saved()?.globalProfile.pages[0].cells[1]?.action.kind == .keystroke)
        // 打ちかけは切り替える前に確定したので、URL に戻すと残っている
        h.model.changeKind(ofCell: id, to: .openURL)
        #expect(h.model.cell(id: id)?.action == .openURL(URLAction(url: "example.com")))
    }

    /// 打ちかけのまま、そのマスへメニュー項目を落とした。消える URL 欄の確定がメニュー項目を URL に戻さない
    @Test func typingThenDroppingAMenuItemOnTheCellKeepsTheMenuItem() async throws {
        let h = try SettingsHarness()
        h.model.createCell(kind: .openURL, at: 1)
        let id = try #require(h.model.selectedCell?.id)
        let host = Host(inspector(h))
        defer { host.close() }
        try await host.settle()
        try host.type("example.com", intoFieldWithPlaceholder: "https://example.com")
        let node = MenuItemNode(title: "コピー", path: ["編集", "コピー"], keyEquivalent: .key("c", .command))
        h.model.assignMenuItem(node, to: CellAddress(page: 0, index: 1))
        try await host.settle(700)
        h.model.pendingEdits.flushAll()
        #expect(h.model.cell(id: id)?.action == .menuItem(MenuItemAction(path: ["編集", "コピー"], keyEquivalent: .key("c", .command))))
        #expect(try h.saved()?.globalProfile.pages[0].cells[1]?.action.kind == .menuItem)
    }

    @Test func typingAPromptThenChangingTheOutputKeepsBoth() async throws {
        let h = try SettingsHarness()
        h.model.createCell(kind: .ai, at: 1)
        let id = try #require(h.model.selectedCell?.id)
        let host = Host(inspector(h))
        defer { host.close() }
        try await host.settle()
        let textView = try #require(host.descendants(NSTextView.self).first { $0.isEditable && !$0.isFieldEditor })
        host.type("3行で要約して", into: textView)
        h.model.updateAction(ofCell: id, as: AIAction.self) { $0.output = .copyToClipboard }
        try await host.settle(900)
        h.model.pendingEdits.flushAll()
        #expect(h.model.cell(id: id)?.action == .ai(AIAction(prompt: "3行で要約して", output: .copyToClipboard)))
    }

    @Test func pageBarFitsTheNarrowestCenterColumn() throws {
        let h = try SettingsHarness()
        h.model.addPage()
        h.model.addPage()
        #expect(h.model.selectedProfile.pages.count == 3)
        // 最小の窓（860pt）での中央の列: 860 − サイドバー 210 − インスペクタ 310 − 区切り − 左右の余白 48
        let hosting = NSHostingController(rootView: SettingsPageBar(model: h.model))
        let narrow = hosting.sizeThatFits(in: CGSize(width: 290, height: 400))
        let wide = hosting.sizeThatFits(in: CGSize(width: 600, height: 400))
        #expect(narrow.width <= 290)
        // 折り返して2行にならない
        #expect(narrow.height <= wide.height + 1)
        // 3段（下のページ・左右に送るページ・下）の、どの段も1行
        #expect(wide.height < 32 * 3, "\(wide.height)")
    }
}
