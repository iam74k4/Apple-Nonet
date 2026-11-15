import Foundation
import NonetCore
import Testing
@testable import NonetPlatform

/// 実機の MultitouchSupport を読む（権限は要らない）。トラックパッドが無い・読み込めない Mac でも通る。
/// 指の位置が正しいかは確かめられないので、作る・止めるを繰り返しても落ちないことだけを見る
@MainActor
@Suite(.serialized) struct InputMultitouchSmokeTests {
    @Test func listsDevicesWithoutCrashing() {
        let devices = MultitouchLibrary.devices()
        #expect(Set(devices.map(\.id)).count == devices.count)
        #expect(MultitouchDeviceInfo.usable(devices).count <= devices.count)
    }

    @Test func startsAndStopsRepeatedly() async throws {
        let source = MultitouchTouchSource()
        let available = source.isAvailable
        for _ in 0..<3 {
            do {
                try source.start()
            } catch let error as NonetError {
                // MultitouchSupport を読めない Mac
                #expect(!available)
                #expect(error == .unavailable(InputText.multitouchUnavailable))
                return
            }
            #expect(source.isRunning)
            try source.start()
            #expect(source.isAvailable == available)
            try await Task.sleep(for: .milliseconds(50))
            source.stop()
            #expect(!source.isRunning)
            source.stop()
        }
        #expect(source.isAvailable == available)
    }
}
