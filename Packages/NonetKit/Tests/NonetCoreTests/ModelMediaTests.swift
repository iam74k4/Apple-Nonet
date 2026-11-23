// 担当: core-model。再生・音量・明るさのボタン（MediaAction）と「メディア」のページ
import Foundation
import Testing
@testable import NonetCore

@Suite struct ModelMediaTests {
    @Test(arguments: MediaKey.allCases)
    func eachKeyRoundTrips(_ key: MediaKey) throws {
        let action = Action.media(MediaAction(key: key))
        let data = try JSONEncoder().encode(action)
        #expect(String(decoding: data, as: UTF8.self) == #"{"key":"\#(key.rawValue)","type":"media"}"# || String(decoding: data, as: UTF8.self) == #"{"type":"media","key":"\#(key.rawValue)"}"#)
        #expect(try JSONDecoder().decode(Action.self, from: data) == action)
        #expect(action.kind == .media)
        #expect(action.summary == key.title)
        #expect(!key.title.isEmpty)
    }

    /// 知らないキーは別のキーとして読まず、マスごと読めない（空きマスになる）
    @Test func anUnknownKeyIsNotRead() {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(Action.self, from: Data(#"{"type":"media","key":"eject"}"#.utf8))
        }
    }

    /// 音量と明るさは2段、再生は1回
    @Test func volumeAndBrightnessMoveTwoSteps() {
        #expect(MediaKey.volumeUp.steps == 2)
        #expect(MediaKey.brightnessDown.steps == 2)
        #expect(MediaKey.playPause.steps == 1)
        #expect(MediaKey.mute.steps == 1)
    }

    /// 真ん中が再生／一時停止、左右が前と次、上下が音量。どのアプリが前面でも同じ
    @Test func theMediaPageIsLaidOutLikeAPlayer() {
        let keys = PresetLibrary.makeMediaPage().cells.map { cell -> MediaKey? in
            if case .media(let media)? = cell?.action { media.key } else { nil }
        }
        #expect(keys == [nil, .volumeUp, .brightnessUp, .previous, .playPause, .next, .mute, .volumeDown, .brightnessDown])
        #expect(!ControllerExecutionPolicy.dependsOnFrontmostApp(.media(MediaAction(key: .mute))))
        #expect(!ControllerExecutionPolicy.isLongRunning(.media(MediaAction(key: .mute))))
    }
}
