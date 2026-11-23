// 担当: engine（設定に足した開きやすさ。GlobalSettings.openSensitivity）の保存と読み込み
import Foundation
@testable import NonetCore
import Testing

@Suite("モデルの Codable: 開きやすさ")
struct ModelOpenSensitivityCodingTests {
    @Test func theDefaultIsStandard() {
        #expect(GlobalSettings().openSensitivity == .standard)
        #expect(OpenSensitivity.allCases == [.low, .standard, .high])
    }

    @Test("すべての値が往復する", arguments: OpenSensitivity.allCases)
    func everyValueRoundTrips(_ sensitivity: OpenSensitivity) throws {
        let settings = GlobalSettings(haptics: .light, hudScale: .large, openSensitivity: sensitivity)
        #expect(try ModelFixtures.roundTrip(settings) == settings)
    }

    /// 標準（既定）なら書かない。この設定より前の版と同じ書式のまま
    @Test func standardIsNotWrittenAndOtherValuesAre() throws {
        #expect(try ModelFixtures.jsonObject(GlobalSettings())["openSensitivity"] == nil)
        #expect(try ModelFixtures.jsonObject(GlobalSettings(openSensitivity: .low))["openSensitivity"] as? String == "low")
        #expect(try ModelFixtures.jsonObject(GlobalSettings(openSensitivity: .high))["openSensitivity"] as? String == "high")
    }

    @Test func anOldFileOrAnUnknownValueReadsAsStandard() throws {
        let old = #"{"isEnabled": true, "haptics": "light", "hudScale": "large"}"#
        #expect(try ModelFixtures.decode(GlobalSettings.self, old).openSensitivity == .standard)
        let unknown = try ModelFixtures.decode(GlobalSettings.self, #"{"openSensitivity": "huge", "haptics": "strong"}"#)
        #expect(unknown.openSensitivity == .standard)
        #expect(unknown.haptics == .strong)
    }

    /// 控えめほど、強く押し込んでから長く止めないと開かない
    @Test func holdTimesShrinkWithSensitivity() {
        #expect(ForcePress.hold(for: .low) > ForcePress.hold(for: .standard))
        #expect(ForcePress.hold(for: .standard) > ForcePress.hold(for: .high))
        #expect(ForcePress.hold(for: .high) > 0)
    }
}
