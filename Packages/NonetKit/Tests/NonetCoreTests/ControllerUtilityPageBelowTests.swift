// 担当: engine・core-model。下のページを足す前の開発中の版で作った設定の「ユーティリティ」を、1回だけ下のページにする
import Foundation
@testable import NonetCore
import Testing

@Suite @MainActor struct ControllerUtilityPageBelowTests {
    /// 前の版の形: グローバルが「画面に置く」・ふつうのページの「ユーティリティ」
    static func earlierConfiguration() -> NonetConfiguration {
        var utilities = PresetLibrary.makeUtilityPage()
        utilities.isBelow = false
        let global = Profile(kind: .global, pages: [PresetLibrary.makeWindowPlacementPage(), utilities])
        return NonetConfiguration(profiles: [global]).validated()
    }

    /// 型どおりのユーティリティだけを下のページにする。中身を変えたページ・下のページがもうある・ページが1つだけなら触らない
    @Test func onlyAnUntouchedUtilityPageBecomesThePageAbove() {
        var configuration = Self.earlierConfiguration()
        let marked = configuration.markUtilityPageBelow()
        #expect(marked)
        #expect(configuration.globalProfile.pages.map(\.isBelow) == [false, true])
        let again = configuration.markUtilityPageBelow()
        #expect(!again)

        var edited = Self.earlierConfiguration()
        edited.setCell(nil, at: CellAddress(page: 1, index: 0), profileID: edited.globalProfile.id)
        let editedMarked = edited.markUtilityPageBelow()
        #expect(!editedMarked)

        var lone = Self.earlierConfiguration()
        lone.removePage(at: 0, profileID: lone.globalProfile.id)
        let loneMarked = lone.markUtilityPageBelow()
        #expect(!loneMarked)
    }

    /// 起動したときに1回だけ手直しして保存する。済ませた後に利用者が外しても、次の起動で付け直さない
    @Test func theControllerMarksItOnceAtStart() throws {
        let h = try ControllerHarness(configuration: Self.earlierConfiguration())
        h.start()
        #expect(h.controller.configuration.globalProfile.pages.map(\.isBelow) == [false, true])
        #expect(h.guidance.hasMarkedUtilityPageBelow)
        h.controller.update { _ = $0.setBelowPage(false, at: 1, profileID: $0.globalProfile.id) }
        h.controller.stop()
        h.start()
        #expect(h.controller.configuration.globalProfile.pages.allSatisfy { !$0.isBelow })
    }

    /// 壊れた設定ファイルを初期の設定で置き換えたときも、手直しは済んだことにする（後で外した下のページを付け直さない）
    @Test func aReplacedCorruptFileNeedsNoMarking() throws {
        let h = try ControllerHarness(configuration: nil)
        try Data("{ broken".utf8).write(to: h.directory.appending(path: "configuration.json"))
        h.start()
        #expect(h.controller.configuration.globalProfile.pages.last?.isBelow == true)
        #expect(h.guidance.hasMarkedUtilityPageBelow)
    }

    /// 初回の設定では、はじめから下のページなので、手直しは済んだことにする
    @Test func aFreshSetupNeedsNoMarking() throws {
        let h = try ControllerHarness(configuration: nil)
        h.start()
        #expect(h.guidance.hasMarkedUtilityPageBelow)
    }
}
