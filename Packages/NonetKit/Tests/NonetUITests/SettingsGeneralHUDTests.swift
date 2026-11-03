// 担当: ui-settings。一般の「開き方と HUD」と「フィードバック」: HUD の大きさ・開き方の説明・説明の文
import AppKit
import NonetCore
@testable import NonetUI
import SwiftUI
import Testing

@Suite struct SettingsGeneralHUDTextTests {
    /// docs/user-guide.md の「設定（一般）」と同じ名前
    @Test func namesMatchTheUserGuide() {
        #expect(SettingsText.hudLargeTitle == L10n.ui("大きく表示"))
        #expect(SettingsText.hudLargeDetail == L10n.ui("HUD と画面の下の通知を 1.25 倍にします"))
        #expect(SettingsText.hapticsDetail == L10n.ui("開いたとき・マスの境界をまたいだとき・実行したときに、トラックパッドが軽く振動します（感圧タッチのトラックパッドだけ）"))
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

    /// 一般のタブは、開きやすさと HUD の位置の2つの選択と、スイッチだけ。ポップアップやスライダーは無い
    @Test func theGeneralTabHasOnlyTwoSegmentedChoices() async throws {
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
        #expect(segments.contains(OpenSensitivity.allCases.map(SettingsText.name)))
        // HUD の位置の選択肢は無い（HUD は画面いっぱいの地図）。「ためらったときだけ出す」はスイッチ
        #expect(segments.count == 1)
        #expect(!walk(hosting).contains { $0 is NSPopUpButton })
        #expect(!walk(hosting).contains { $0 is NSSlider })
    }
}

@Suite(.serialized) @MainActor struct SettingsGeneralOpenSensitivityTests {
    @Test func theSensitivityIsSavedImmediately() throws {
        let h = try SettingsHarness()
        #expect(h.model.settings.openSensitivity == .standard)
        h.model.setSetting(\.openSensitivity, .low)
        #expect(h.controller.configuration.settings.openSensitivity == .low)
        #expect(try h.saved()?.settings.openSensitivity == .low)
    }

    @Test func namesAndDetailsMatchTheUserGuide() {
        #expect(SettingsText.openSensitivityTitle == L10n.ui("開きやすさ"))
        #expect(OpenSensitivity.allCases.map(SettingsText.name) == [L10n.ui("控えめ"), L10n.ui("標準"), L10n.ui("開きやすい")])
        // 説明は、選んだ段の帯の高さ・動き・時間を言う
        #expect(SettingsText.openSensitivityDetail(.low) == L10n.ui("奥の端から 6mm ほどに置いた指を、0.4秒のうちに 7mm ほど下へ。ふだんのポインタ操作で開いてしまうときに"))
        #expect(SettingsText.openSensitivityDetail(.standard) == L10n.ui("奥の端から 9mm ほどに置いた指を、0.6秒のうちに 5mm ほど下へ"))
        #expect(SettingsText.openSensitivityDetail(.high) == L10n.ui("奥の端から 13mm ほどに置いた指を、1秒のうちに 4mm ほど下へ。縁から滑らせても開かないことがあるときに"))
        #expect(Set(OpenSensitivity.allCases.map(SettingsText.openSensitivityDetail)).count == 3)
    }
}
