// 担当: engine。開き方（GlobalSettings.openGesture）: 強く押し込む・上の縁から滑らせる・両方
import Foundation
import Testing
@testable import NonetCore

@MainActor
@Suite struct ControllerOpenGestureTests {
    typealias F = ControllerFixtures

    private func harness(_ gesture: OpenGesture) throws -> ControllerHarness {
        let h = try ControllerHarness(configuration: F.configuration(settings: F.settings { $0.openGesture = gesture }))
        h.start()
        return h
    }

    /// 既定は強く押し込む。上の縁から滑らせても開かない（ふつうのポインタ操作のまま）
    @Test func theDefaultIsTheFirmPressOnly() throws {
        let h = try harness(.forcePress)
        #expect(GlobalSettings().openGesture == .forcePress)
        h.slideOpen()
        #expect(h.hud.shown.isEmpty)
        h.lift()
        h.open()
        #expect(h.hud.shown.count == 1)
    }

    /// 上の縁から滑らせるだけにしたら、クリックを預からない（強く押し込んでもふつうのクリック）
    @Test func edgeSlideOnlyHoldsNoClicks() async throws {
        let h = try harness(.edgeSlide)
        #expect(h.keyboard.forcePressHold == nil)
        #expect(!h.forcePress())
        h.slideOpen()
        #expect(h.hud.shown.count == 1)
        h.choose(2)
        await h.settle()
        #expect(h.performer.actions == [F.closeTab.action])
    }

    @Test func bothOpenTheButtons() throws {
        let h = try harness(.both)
        #expect(h.keyboard.forcePressHold == ForcePress.hold(for: .standard))
        h.slideOpen()
        #expect(h.hud.shown.count == 1)
        h.liftAndClose()
        h.open()
        #expect(h.hud.shown.count == 2)
    }

    /// 上の縁からの滑り込みは、クリックしたままのドラッグでは開かない
    @Test func aPressedButtonKeepsTheSlideClosed() throws {
        let h = try harness(.edgeSlide)
        h.keyboard.isMouseButtonDown = true
        h.slideOpen()
        #expect(h.hud.shown.isEmpty)
    }

    /// 許可が無いときに上の縁から滑らせたら、開けない理由を知らせる（滑り込みは指のフレームで見分けるので届く）
    @Test func withoutAccessibilityTheSlideExplainsWhy() throws {
        let h = try ControllerHarness(configuration: F.configuration(settings: F.settings { $0.openGesture = .edgeSlide }))
        h.permissions.isAccessibilityGranted = false
        h.start()
        h.slideOpen()
        #expect(h.hud.shown.isEmpty)
        #expect(h.haptics.events == [.rejected])
        #expect(h.hud.toasts == [ControllerPresentation.accessibilityNeededToast(isMenuBarIconVisible: true)])
    }

    /// 設定を変えたら、起動し直さなくても効く
    @Test func changingTheGestureTakesEffectAtOnce() throws {
        let h = try harness(.forcePress)
        h.controller.update { $0.settings.openGesture = .edgeSlide }
        #expect(h.keyboard.forcePressHold == nil)
        h.slideOpen()
        #expect(h.hud.shown.count == 1)
    }

    @Test func theGestureIsStoredOnlyWhenItIsNotTheDefault() throws {
        let standard = try JSONEncoder().encode(GlobalSettings())
        #expect(!String(decoding: standard, as: UTF8.self).contains("openGesture"))
        let both = try JSONEncoder().encode(GlobalSettings(openGesture: .both))
        #expect(try JSONDecoder().decode(GlobalSettings.self, from: both).openGesture == .both)
        let unknown = #"{"openGesture": "wave"}"#
        #expect(try JSONDecoder().decode(GlobalSettings.self, from: Data(unknown.utf8)).openGesture == .forcePress)
    }
}
