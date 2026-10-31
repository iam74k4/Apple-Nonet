// 担当: core-model（スクリーンショットと画面収録のアクションの書式と決まり）
import Foundation
import Testing
@testable import NonetCore

@Suite struct ActionScreenCaptureCodingTests {
    @Test(arguments: ScreenCaptureMode.allCases)
    func everyModeRoundTrips(mode: ScreenCaptureMode) throws {
        let action = Action.screenCapture(ScreenCaptureAction(mode: mode, toClipboard: mode.supportsClipboard))
        #expect(try ModelFixtures.roundTrip(action) == action)
        #expect(action.kind == .screenCapture)
        #expect(!action.summary.isEmpty)
    }

    @Test func theClipboardIsWrittenOnlyWhenUsed() throws {
        let cases: [(Action, String)] = [
            (.screenCapture(ScreenCaptureAction(mode: .area)), #"{"type":"screenCapture","mode":"area"}"#),
            (.screenCapture(ScreenCaptureAction(mode: .window, toClipboard: true)), #"{"type":"screenCapture","mode":"window","toClipboard":true}"#),
            // クリップボードに入れられないモードに残っていた値は、書き出さない
            (.screenCapture(ScreenCaptureAction(mode: .toolbar, toClipboard: true)), #"{"type":"screenCapture","mode":"toolbar"}"#),
        ]
        for (action, json) in cases {
            #expect(try ModelFixtures.jsonObject(action) == ModelFixtures.jsonObject(json), "\(json)")
        }
        #expect(try ModelFixtures.decode(Action.self, #"{"type":"screenCapture","mode":"area"}"#) == .screenCapture(ScreenCaptureAction(mode: .area)))
    }

    @Test(arguments: [#"{"type":"screenCapture","mode":"area","toClipboard":3}"#, #"{"type":"screenCapture","mode":"area","toClipboard":null}"#])
    func aBrokenClipboardFlagReadsAsOff(json: String) throws {
        #expect(try ModelFixtures.decode(Action.self, json) == .screenCapture(ScreenCaptureAction(mode: .area)))
    }

    /// 知らないモードを別のモードとして読まない。読めなければ、そのマスは空きになる
    @Test(arguments: [#"{"type":"screenCapture","mode":"video"}"#, #"{"type":"screenCapture"}"#, #"{"type":"screenCapture","mode":null}"#])
    func anUnknownModeIsNotReadAsAnother(json: String) {
        #expect(throws: DecodingError.self) { try ModelFixtures.decode(Action.self, json) }
    }

    @Test func onlyStillAndWindowCapturesCanGoToTheClipboard() {
        #expect(ScreenCaptureMode.allCases.filter(\.supportsClipboard) == [.area, .window, .fullScreen])
    }

    @Test func titlesAreDistinctAndShort() {
        let titles = ScreenCaptureMode.allCases.map(\.title)
        #expect(Set(titles).count == titles.count)
        for title in titles {
            #expect(PresetTestSupport.displayWidth(title) <= PresetTestSupport.maxTitleWidth, "\(title)")
        }
    }

    @Test func captureKeysWorkInAnyFrontApp() {
        for mode in ScreenCaptureMode.allCases {
            let action = Action.screenCapture(ScreenCaptureAction(mode: mode))
            #expect(!ControllerExecutionPolicy.dependsOnFrontmostApp(action))
            #expect(!ControllerExecutionPolicy.sendsInputToFrontmostApp(action))
            #expect(!ControllerExecutionPolicy.isLongRunning(action))
        }
    }
}
