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
        #expect(SettingsText.hapticsDetail == L10n.ui("開いたとき・隣のアイコンに移ったとき・実行したときに、トラックパッドが軽く振動します（感圧タッチのトラックパッドだけ）"))
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
        // HUD の位置の選択肢は無い（HUD はポインタのすぐ下に出す）
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
        // 説明は、選んだ段の止める時間を言う（ForcePress.hold と同じ）
        #expect(SettingsText.openSensitivityDetail(.low) == L10n.ui("強く押し込んでから 0.5秒ほど止めると開きます。強めにクリックする癖があって、思わず開いてしまうときに"))
        #expect(SettingsText.openSensitivityDetail(.standard) == L10n.ui("強く押し込んでから 0.25秒ほど止めると開きます"))
        #expect(SettingsText.openSensitivityDetail(.high) == L10n.ui("強く押し込んでから 0.1秒ほどで開きます。止めて待つのがもどかしいときに"))
        #expect(Set(OpenSensitivity.allCases.map { SettingsText.openSensitivityDetail($0) }).count == 3)
    }
}

/// 「ターミナルで実行」のアプリ（GlobalSettings.terminalApp）。iTerm2 が入っているときだけ選べる
@Suite(.serialized) @MainActor struct SettingsGeneralTerminalAppTests {
    static let iTerm2 = AppReference(bundleID: TerminalApp.iTerm2.bundleID, name: "iTerm")

    @Test func iTerm2IsAChoiceOnlyWhenInstalledOrChosen() {
        #expect(SettingsText.terminalChoices(current: .terminal) { _ in false } == [.terminal])
        #expect(SettingsText.terminalChoices(current: .terminal) { $0 == TerminalApp.iTerm2.bundleID } == [.terminal, .iTerm2])
        // 選んだ後に消しても、選んだまま見せる
        #expect(SettingsText.terminalChoices(current: .iTerm2) { _ in false } == [.terminal, .iTerm2])
        #expect(TerminalApp.allCases.map(SettingsText.name) == [L10n.ui("ターミナル"), "iTerm2"])
    }

    @Test func theChoiceIsSavedImmediately() throws {
        let h = try SettingsHarness()
        h.model.setSetting(\.terminalApp, .iTerm2)
        #expect(h.controller.configuration.settings.terminalApp == .iTerm2)
        #expect(try h.saved()?.settings.terminalApp == .iTerm2)
    }

    /// iTerm2 が入っていれば、一般のタブに「ターミナル」「iTerm2」の選択が出る
    @Test func theRowAppearsWhenITerm2IsInstalled() async throws {
        _ = NSApplication.shared
        let h = try SettingsHarness()
        h.installed.apps.append(Self.iTerm2)
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
        #expect(segments.contains(TerminalApp.allCases.map(SettingsText.name)))
        #expect(!walk(hosting).contains { $0 is NSPopUpButton })
    }
}

/// macOS の「強めのクリックと触覚フィードバック」がオフだと、強く押し込んでも開かないので、一般のタブで知らせる
@Suite struct SettingsForceClickTests {
    private func defaults(_ value: Bool?) throws -> UserDefaults {
        let name = "SettingsForceClickTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        if let value { defaults.set(value, forKey: TrackpadForceClick.key) }
        return defaults
    }

    @Test func onlyAnExplicitOffCounts() throws {
        #expect(!TrackpadForceClick.isOff(defaults: try defaults(nil)))
        #expect(!TrackpadForceClick.isOff(defaults: try defaults(true)))
        #expect(TrackpadForceClick.isOff(defaults: try defaults(false)))
    }

    @Test func theNoticeSaysWhereToTurnItOn() {
        #expect(SettingsText.forceClickOffTitle == L10n.ui("macOS の「強めのクリック」がオフです"))
        #expect(TrackpadForceClick.settingsURL.scheme == "x-apple.systempreferences")
    }
}
