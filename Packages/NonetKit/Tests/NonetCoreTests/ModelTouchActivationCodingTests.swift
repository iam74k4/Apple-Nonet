// 担当: core-model。トラックパッドだけで呼び出す設定（GlobalSettings.touchActivation）の保存と読み込み
import Foundation
@testable import NonetCore
import Testing

@Suite("モデルの Codable: トラックパッドだけで呼び出す")
struct ModelTouchActivationCodingTests {
    @Test func theDefaultIsOffAndTheChoicesAreInOrder() {
        #expect(GlobalSettings().touchActivation == .off)
        #expect(TouchActivation.allCases == [.off, .topLeft, .topRight])
    }

    @Test("すべての値が往復する", arguments: TouchActivation.allCases)
    func everyValueRoundTrips(_ activation: TouchActivation) throws {
        let settings = GlobalSettings(fireMode: .onFingerLift, touchActivation: activation)
        #expect(try ModelFixtures.roundTrip(settings) == settings)
    }

    /// 使わない（既定）なら書かない。この設定より前の版と同じ書式のまま
    @Test func offIsNotWrittenAndOtherValuesAre() throws {
        #expect(try ModelFixtures.jsonObject(GlobalSettings())["touchActivation"] == nil)
        #expect(try ModelFixtures.jsonObject(GlobalSettings(touchActivation: .topLeft))["touchActivation"] as? String == "topLeft")
        #expect(try ModelFixtures.jsonObject(GlobalSettings(touchActivation: .topRight))["touchActivation"] as? String == "topRight")
    }

    @Test func anOldFileWithoutTheKeyReadsAsOff() throws {
        let old = #"{"isEnabled": true, "trigger": "rightCommand", "haptics": "light", "cursorLock": "dropEvents"}"#
        let settings = try ModelFixtures.decode(GlobalSettings.self, old)
        #expect(settings.touchActivation == .off)
        #expect(settings.haptics == .light)
    }

    @Test func anUnknownValueReadsAsOffAndKeepsTheOtherSettings() throws {
        let settings = try ModelFixtures.decode(GlobalSettings.self, #"{"touchActivation": "bottomLeft", "haptics": "strong"}"#)
        #expect(settings == GlobalSettings(haptics: .strong))
        let wrongType = try ModelFixtures.decode(GlobalSettings.self, #"{"touchActivation": 2}"#)
        #expect(wrongType.touchActivation == .off)
    }

    @Test func aWholeConfigurationKeepsTheSetting() throws {
        let configuration = ModelFixtures.configuration(settings: GlobalSettings(touchActivation: .topRight))
        #expect(try ModelFixtures.roundTrip(configuration).settings.touchActivation == .topRight)
    }
}
