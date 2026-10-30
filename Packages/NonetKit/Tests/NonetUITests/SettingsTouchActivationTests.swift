// 担当: ui-settings。一般の「トラックパッドだけで呼び出す」
import AppKit
import NonetCore
@testable import NonetUI
import SwiftUI
import Testing

@Suite struct SettingsTouchActivationTextTests {
    /// docs/user-guide.md の「設定（一般）」と同じ選択肢の名前
    @Test func choiceNamesMatchTheUserGuide() {
        #expect(TouchActivation.allCases.map(SettingsText.name) == [
            L10n.ui("使わない"),
            L10n.ui("左上の角で長押し"),
            L10n.ui("右上の角で長押し"),
        ])
    }
}

@Suite(.serialized) @MainActor struct SettingsTouchActivationTests {
    @Test func theChoiceIsSavedImmediately() throws {
        let h = try SettingsHarness()
        #expect(h.model.settings.touchActivation == .off)
        h.model.setSetting(\.touchActivation, .topRight)
        #expect(h.controller.configuration.settings.touchActivation == .topRight)
        #expect(try h.saved()?.settings.touchActivation == .topRight)
    }

    /// 一般のタブで、トリガーキーのすぐ下に出て、いまの設定を表示する
    @Test func theGeneralTabShowsThePickerRightUnderTheTriggerKey() async throws {
        _ = NSApplication.shared
        let h = try SettingsHarness()
        let size = CGSize(width: 640, height: 1400)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: SettingsGeneralView(model: h.model).frame(width: size.width, height: size.height))
        hosting.frame = NSRect(origin: .zero, size: size)
        window.contentView = hosting
        defer {
            window.contentView = nil
            window.close()
        }
        func settle() async throws {
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(80))
            hosting.layoutSubtreeIfNeeded()
        }
        /// ポップアップの、選んでいる項目の名前（画面の上から順）。SwiftUI は項目を開くときに作るので、名前だけを見る
        func popUpTitles() -> [String] {
            func walk(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(walk) }
            return walk(hosting).compactMap { $0 as? NSPopUpButton }.map(\.title)
        }

        try await settle()
        let trigger = SettingsText.name(h.model.settings.trigger)
        let titles = popUpTitles()
        let triggerIndex = try #require(titles.firstIndex(of: trigger))
        #expect(titles.dropFirst(triggerIndex + 1).first == SettingsText.name(TouchActivation.off))

        h.model.setSetting(\.touchActivation, .topRight)
        try await settle()
        #expect(popUpTitles().dropFirst(triggerIndex + 1).first == SettingsText.name(TouchActivation.topRight))
    }
}
