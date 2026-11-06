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

    /// 「背景に合わせて色を変える」は既定でオフ（画面収録の許可と、macOS 15 の確認ダイアログを伴うので、利用者が選ぶ）。
    /// オンにすると保存され、HUD は測るようになる（HUDModel.adaptsInk）。説明は許可とダイアログのことを言う
    @Test func adaptiveInkIsOffByDefaultAndSaved() throws {
        let h = try SettingsHarness()
        #expect(!h.model.settings.adaptiveHUDInk)
        #expect(!GlobalSettings().adaptiveHUDInk)
        #expect(SettingsText.adaptiveInkTitle == L10n.ui("背景に合わせて色を変える"))
        #expect(SettingsText.adaptiveInkDetail == L10n.ui("開くたびに HUD の下の画面の明るさを測り、アイコンを白か黒にします。macOS の「画面収録」の許可が要り、macOS 15 以降では月に一度ほど確認のダイアログが出ます。画像はその場で捨て、保存も送信もしません"))
        #expect(SettingsText.adaptiveInkDetail.contains("macOS 15"))
        h.model.setSetting(\.adaptiveHUDInk, true)
        #expect(h.controller.configuration.settings.adaptiveHUDInk)
        #expect(try h.saved()?.settings.adaptiveHUDInk == true)
    }

    /// 画面収録の許可: 聞くだけ・求める・システム設定を開く。ボタンを押したら・ウィンドウが前面に戻ったら読み直す
    @Test func screenCapturePermissionIsReadAndRequested() throws {
        let h = try SettingsHarness()
        #expect(!h.model.isScreenCaptureGranted)
        h.model.requestScreenCapture()
        #expect(h.permissions.screenCaptureRequestCount == 1)
        h.model.openScreenCaptureSettings()
        #expect(h.permissions.screenCaptureOpenCount == 1)
        h.permissions.isScreenCaptureGranted = true
        h.model.refreshPermissions()
        #expect(h.model.isScreenCaptureGranted)
    }

    /// 起動した後に許可したときは、開き直すまで効かないので、そう言って開き直すボタンを出す。
    /// 起動時から許可があった・起動後でも撮れていたなら要らない。許可があるのに撮れなかったときも開き直しを勧める
    @Test func relaunchIsOfferedWhenThePermissionCannotTakeEffectYet() throws {
        let h = try SettingsHarness()
        var outcome = ScreenCaptureBackdropSampler.Outcome.notTried
        h.model.screenCaptureOutcome = { outcome }
        #expect(!h.model.screenCaptureNeedsRelaunch)
        h.permissions.isScreenCaptureGranted = true
        h.permissions.screenCaptureGrantedAtLaunch = false
        h.model.refreshPermissions()
        #expect(h.model.screenCaptureNeedsRelaunch)
        outcome = .succeeded
        h.model.refreshPermissions()
        #expect(!h.model.screenCaptureNeedsRelaunch)
        h.permissions.screenCaptureGrantedAtLaunch = true
        outcome = .failed
        h.model.refreshPermissions()
        #expect(h.model.screenCaptureNeedsRelaunch)
        outcome = .notTried
        h.model.refreshPermissions()
        #expect(!h.model.screenCaptureNeedsRelaunch)
        #expect(SettingsText.screenCaptureNeedsRelaunch == L10n.ui("「画面収録」の許可は、Nonet を開き直すと効きます。それまでは黒いアイコンに白い縁で表示します。"))
        #expect(SettingsText.relaunchButton == L10n.ui("Nonet を開き直す"))
        var relaunched = 0
        h.model.relaunch = { relaunched += 1 }
        h.model.relaunch()
        #expect(relaunched == 1)
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
        // 説明は、選んだ段の帯の高さ・動き・時間を言う
        #expect(SettingsText.openSensitivityDetail(.low) == L10n.ui("奥の端から 6mm ほどに置いた指を、0.4秒のうちに 7mm ほど下へ。ふだんのポインタ操作で開いてしまうときに"))
        #expect(SettingsText.openSensitivityDetail(.standard) == L10n.ui("奥の端から 9mm ほどに置いた指を、0.6秒のうちに 5mm ほど下へ"))
        #expect(SettingsText.openSensitivityDetail(.high) == L10n.ui("奥の端から 13mm ほどに置いた指を、1秒のうちに 4mm ほど下へ。縁から滑らせても開かないことがあるときに"))
        #expect(Set(OpenSensitivity.allCases.map(SettingsText.openSensitivityDetail)).count == 3)
    }
}
