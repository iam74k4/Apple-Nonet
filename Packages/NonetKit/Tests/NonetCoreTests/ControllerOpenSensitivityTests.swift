// 担当: engine。設定の「開きやすさ」（GlobalSettings.openSensitivity）が、強く押し込んでから止める時間に効く
import Foundation
import NonetCore
import Testing

@Suite @MainActor struct ControllerOpenSensitivityTests {
    private func harness(_ sensitivity: OpenSensitivity) throws -> ControllerHarness {
        let h = try ControllerHarness(configuration: ControllerFixtures.configuration(settings: ControllerFixtures.settings { $0.openSensitivity = sensitivity }))
        h.start()
        return h
    }

    /// 開きやすさごとの止める時間を、キーボードモニターに入れる
    @Test(arguments: OpenSensitivity.allCases)
    func theHoldTimeFollowsTheSetting(_ sensitivity: OpenSensitivity) throws {
        let h = try harness(sensitivity)
        #expect(h.keyboard.forcePressHold == ForcePress.hold(for: sensitivity))
    }

    /// 設定を変えたら、起動し直さなくても次の押し込みから効く
    @Test func changingTheSettingTakesEffectOnTheNextPress() throws {
        let h = try harness(.standard)
        h.controller.update { $0.settings.openSensitivity = .high }
        #expect(h.keyboard.forcePressHold == ForcePress.hold(for: .high))
        h.open()
        #expect(h.hud.isVisible)
    }

    /// 無効にしたら預からない。有効に戻したら預かる
    @Test func disablingDisarms() throws {
        let h = try harness(.standard)
        h.controller.update { $0.settings.isEnabled = false }
        #expect(h.keyboard.forcePressHold == nil)
        h.controller.update { $0.settings.isEnabled = true }
        #expect(h.keyboard.forcePressHold == ForcePress.hold(for: .standard))
    }
}
