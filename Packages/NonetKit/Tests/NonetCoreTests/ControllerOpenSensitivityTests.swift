// 担当: engine。設定の「開きやすさ」（GlobalSettings.openSensitivity）が、開く動きの見分け方に効く
import Foundation
import NonetCore
import Testing

@Suite @MainActor struct ControllerOpenSensitivityTests {
    private func harness(_ sensitivity: OpenSensitivity) throws -> ControllerHarness {
        let h = try ControllerHarness(configuration: ControllerFixtures.configuration(settings: ControllerFixtures.settings { $0.openSensitivity = sensitivity }))
        h.start()
        return h
    }

    /// 控えめ: 標準で開く動き（0.06 下へ）では開かず、0.07 下へ動かすと開く
    @Test func lowNeedsMoreTravel() throws {
        let h = try harness(.low)
        h.touch(x: 0.5, y: 0.98)
        h.advance(0.05)
        h.touch(x: 0.5, y: 0.92)
        h.advance(EdgeSlideRecognizer.entryConfirmDelay)
        #expect(!h.hud.isVisible)
        h.touch(x: 0.5, y: 0.90)
        h.advance(EdgeSlideRecognizer.entryConfirmDelay)
        #expect(h.hud.isVisible)
    }

    /// 開きやすい: 標準の帯の外（0.89）で触れ始めても、0.04 下へ動かせば開く
    @Test func highOpensFromFurtherDown() throws {
        let h = try harness(.high)
        h.touch(x: 0.5, y: 0.89)
        h.advance(0.05)
        h.touch(x: 0.5, y: 0.85)
        h.advance(EdgeSlideRecognizer.entryConfirmDelay)
        #expect(h.hud.isVisible)
    }

    /// 標準では、0.89 は帯の外なので開かない
    @Test func standardDoesNotOpenBelowItsBand() throws {
        let h = try harness(.standard)
        h.touch(x: 0.5, y: 0.89)
        h.advance(0.05)
        h.touch(x: 0.5, y: 0.85)
        h.advance(EdgeSlideRecognizer.entryConfirmDelay)
        #expect(!h.hud.isVisible)
    }

    /// 設定を変えたら、起動し直さなくても次のタッチから効く
    @Test func changingTheSettingTakesEffectOnTheNextTouch() throws {
        let h = try harness(.standard)
        h.controller.update { $0.settings.openSensitivity = .high }
        h.touch(x: 0.5, y: 0.89)
        h.advance(0.05)
        h.touch(x: 0.5, y: 0.85)
        h.advance(EdgeSlideRecognizer.entryConfirmDelay)
        #expect(h.hud.isVisible)
    }
}
