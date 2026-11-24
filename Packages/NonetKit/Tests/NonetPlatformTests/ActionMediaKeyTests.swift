import Foundation
import NonetCore
import Testing
@testable import NonetPlatform

/// 再生・音量・明るさのキーの、システムのイベントの値（IOKit の NX_KEYTYPE_*）。実際には送らない
@Suite struct ActionMediaKeyTests {
    @Test func keyCodesMatchIOKit() {
        #expect(MediaKeyCode.code(for: .volumeUp) == 0)
        #expect(MediaKeyCode.code(for: .volumeDown) == 1)
        #expect(MediaKeyCode.code(for: .brightnessUp) == 2)
        #expect(MediaKeyCode.code(for: .brightnessDown) == 3)
        #expect(MediaKeyCode.code(for: .mute) == 7)
        #expect(MediaKeyCode.code(for: .playPause) == 16)
        #expect(MediaKeyCode.code(for: .next) == 17)
        #expect(MediaKeyCode.code(for: .previous) == 18)
        #expect(Set(MediaKey.allCases.map(MediaKeyCode.code)).count == MediaKey.allCases.count)
    }

    @Test func data1CarriesTheKeyAndTheDirection() {
        #expect(MediaKeyCode.data1(for: .playPause, down: true) == 0x10_0A00)
        #expect(MediaKeyCode.data1(for: .playPause, down: false) == 0x10_0B00)
        #expect(MediaKeyCode.data1(for: .volumeUp, down: true) == 0x0A00)
    }
}
