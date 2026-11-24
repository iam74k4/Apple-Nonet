// 担当: core-model。「テキストを貼る」（PasteTextAction）
import Foundation
import Testing
@testable import NonetCore

@Suite struct ModelPasteTextTests {
    @Test func roundTripsAndSummarizesTheFirstLine() throws {
        let action = Action.pasteText(PasteTextAction(text: "いつもお世話になっております。\n岡崎です。"))
        let data = try JSONEncoder().encode(action)
        #expect(try JSONDecoder().decode(Action.self, from: data) == action)
        #expect(action.kind == .pasteText)
        #expect(action.summary == "いつもお世話になっております。")
        #expect(Action.pasteText(PasteTextAction(text: "あいうえおかきくけこさしすせそたち")).summary == "あいうえおかきくけこさしすせそ…")
        #expect(Action.pasteText(PasteTextAction(text: "短い")).summary == "短い")
        #expect(Action.pasteText(PasteTextAction(text: "  \n")).summary == ModelFixtures.text("テキストを貼る"))
    }

    @Test func dateAndTimeAreFilledInWhenPasting() throws {
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let now = Date(timeIntervalSince1970: 1_795_444_000) // 2026-11-23 14:26 UTC（東京は 23:26）
        let paste = PasteTextAction(text: "{date} {time} 報告")
        #expect(paste.expanded(now: now, timeZone: tokyo) == "2026-11-23 23:26 報告")
        // 置き換えるものが無ければそのまま
        #expect(PasteTextAction(text: "{name}").expanded(now: now, timeZone: tokyo) == "{name}")
    }

    /// 貼るのは前面のアプリへの入力（テスト実行では、そのアプリが前面のときだけ）
    @Test func pastingGoesToTheFrontApp() {
        let action = Action.pasteText(PasteTextAction(text: "x"))
        #expect(ControllerExecutionPolicy.sendsInputToFrontmostApp(action))
        #expect(ControllerExecutionPolicy.dependsOnFrontmostApp(action))
        #expect(!ControllerExecutionPolicy.isLongRunning(action))
    }
}
