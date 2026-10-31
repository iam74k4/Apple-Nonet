// 担当: ui-settings。一般の「トリガーと HUD」と「知らせ」: HUD の大きさ・指を止めてから HUD が出るまでの時間・説明の文
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

    /// 指を置かないときの待ち時間とは別の、指を止めてからの時間だと分かる名前と説明
    @Test func theHudDelaySaysItCountsFromTheRestingFinger() {
        #expect(SettingsText.hudDelayTitle == L10n.ui("指を止めてから HUD が出るまでの時間"))
        #expect(SettingsText.hudDelayDetail == L10n.ui("指を置いたままこの時間止めると HUD が出ます。これより短いタップはその場で実行します。"))
    }

    /// 「キーを離したとき」でも、すぐにタップすれば HUD が出ていても実行する
    @Test func fireModeDetailsSayTappingWorksWithTheHUD() {
        #expect(SettingsText.detail(FireMode.onTriggerRelease) == L10n.ui("HUD（9マスの一覧）で選んだマスを、トリガーキーを離したときに実行します。すぐにタップすれば、HUD が出ていてもその場で実行します。"))
        #expect(SettingsText.detail(FireMode.onFingerLift) == L10n.ui("HUD（9マスの一覧）で選んだマスを、指を離したときに実行します。やめるときは指を置いたまま左の⇧を押します。"))
    }

    @Test func notificationDetailsCoverTheNewFeedback() {
        #expect(SettingsText.hapticsDetail == L10n.ui("マスの境界をまたいだとき・ページが変わったとき・実行したときに振動します。何も実行しなかったときは軽く2回振動します。"))
        #expect(SettingsText.executionToastDetail == L10n.ui("HUD を出さずに実行したときと、時間の掛かるマスが終わったときに、画面の下に通知を出します"))
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

    /// 一般のタブの「トリガーと HUD」に、HUD の大きさの3つの選択肢が並ぶ
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
    }
}
