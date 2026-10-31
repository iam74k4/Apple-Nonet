// 担当: ui-settings。一般の「開き方と HUD」と「フィードバック」: HUD の大きさ・開き方の説明・説明の文
import AppKit
import NonetCore
@testable import NonetUI
import SwiftUI
import Testing

@Suite struct SettingsGeneralHUDTextTests {
    /// docs/user-guide.md の「設定（一般）」と同じ選択肢の名前
    @Test func hudScaleNamesMatchTheUserGuide() {
        #expect(HUDScale.allCases.map(SettingsText.name) == [L10n.ui("標準"), L10n.ui("大きい"), L10n.ui("特大")])
        #expect(SettingsText.hudScaleTitle == L10n.ui("HUD の大きさ"))
        #expect(SettingsText.hudScaleDetail == L10n.ui("画面の下に出る通知も同じ大きさになります"))
    }

    @Test func notificationDetailsCoverTheNewFeedback() {
        #expect(SettingsText.hapticsDetail == L10n.ui("開いたとき・マスの境界をまたいだとき・ページが変わったとき・実行したときに振動します。何も実行せずに閉じたときは軽く2回振動します。"))
        #expect(SettingsText.executionToastDetail == L10n.ui("時間の掛かるマスが終わったときに、画面の下に通知を出します"))
    }
}

@Suite(.serialized) @MainActor struct SettingsGeneralHUDTests {
    @Test func theHUDSizeIsSavedImmediately() throws {
        let h = try SettingsHarness()
        #expect(h.model.settings.hudScale == .standard)
        h.model.setSetting(\.hudScale, .extraLarge)
        #expect(h.controller.configuration.settings.hudScale == .extraLarge)
        #expect(try h.saved()?.settings.hudScale == .extraLarge)
    }

    /// 一般のタブの「開き方と HUD」に、HUD の大きさの3つの選択肢が並び、トリガーキーや角の選択肢は無い
    @Test func theGeneralTabShowsTheHUDSizeChoices() async throws {
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
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(80))
        hosting.layoutSubtreeIfNeeded()

        func walk(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(walk) }
        let segments = walk(hosting).compactMap { $0 as? NSSegmentedControl }.map { control in
            (0..<control.segmentCount).map { control.label(forSegment: $0) ?? "" }
        }
        #expect(segments.contains(HUDScale.allCases.map(SettingsText.name)))
        // ポップアップは「ポインタの固定方法」だけ（トリガーキー・角・実行のタイミングは無い）
        let popups = walk(hosting).compactMap { $0 as? NSPopUpButton }
        #expect(popups.count <= 1)
        #expect(!walk(hosting).contains { $0 is NSSlider })
    }
}
