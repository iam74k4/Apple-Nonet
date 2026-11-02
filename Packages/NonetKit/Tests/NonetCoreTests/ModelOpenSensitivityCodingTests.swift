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

    /// 控えめは狭い帯・多い動き・短い時間、開きやすいはその逆。標準は今までの定数
    @Test func thresholdsGrowWithSensitivity() {
        typealias T = EdgeSlideRecognizer.Thresholds
        let low = T(.low), standard = T(.standard), high = T(.high)
        #expect(standard == .standard)
        #expect(standard == T(bandHeight: EdgeSlideRecognizer.entryBandHeight, travel: EdgeSlideRecognizer.entryTravel, window: EdgeSlideRecognizer.entryWindow))
        #expect(low.bandHeight < standard.bandHeight && standard.bandHeight < high.bandHeight)
        #expect(low.travel > standard.travel && standard.travel > high.travel)
        #expect(low.window < standard.window && standard.window < high.window)
        // どの段でも、開いた瞬間の指は上の外枠（やめる場所）の中にいる
        for thresholds in [low, standard, high] {
            #expect(GridInsets.cancelFrame.top >= thresholds.bandHeight + thresholds.travel)
        }
    }
}
