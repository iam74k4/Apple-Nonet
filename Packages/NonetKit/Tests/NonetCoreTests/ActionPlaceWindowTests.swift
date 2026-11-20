// 担当: core-model。「画面に置く」のアクション（Codable・場所の枠・初回の設定）
import CoreGraphics
import Foundation
@testable import NonetCore
import Testing

@Suite("画面に置く")
struct ActionPlaceWindowTests {
    @Test("すべての場所が往復し、type と region で書く", arguments: WindowRegion.allCases)
    func everyRegionRoundTrips(_ region: WindowRegion) throws {
        let action = Action.placeWindow(PlaceWindowAction(region: region))
        #expect(try ModelFixtures.roundTrip(action) == action)
        let object = try ModelFixtures.jsonObject(action)
        #expect(object["type"] as? String == "placeWindow")
        #expect(object["region"] as? String == region.rawValue)
        #expect(action.kind == .placeWindow)
        #expect(action.summary == region.title)
    }

    /// 知らない場所は、別の場所として読まない（マスごと読めない）
    @Test func anUnknownRegionIsUnreadable() {
        #expect(throws: (any Error).self) {
            try ModelFixtures.decode(Action.self, #"{"type": "placeWindow", "region": "somewhere"}"#)
        }
    }

    /// 場所の並びは HUD のマスと同じ（左上から右へ、上の段から）
    @Test func regionsFollowTheGridOrder() {
        #expect(WindowRegion.allCases == [.topLeft, .top, .topRight, .left, .maximize, .right, .bottomLeft, .bottom, .bottomRight])
        #expect(Set(WindowRegion.allCases.map(\.symbol)).count == WindowRegion.allCases.count)
    }

    /// 画面の使える範囲を 3×3 の決まりで分ける（AppKit の座標: y は上向き）
    @Test func framesSplitTheVisibleArea() {
        let visible = CGRect(x: 0, y: 70, width: 1440, height: 800)
        #expect(WindowRegion.maximize.frame(in: visible) == visible)
        #expect(WindowRegion.left.frame(in: visible) == CGRect(x: 0, y: 70, width: 720, height: 800))
        #expect(WindowRegion.right.frame(in: visible) == CGRect(x: 720, y: 70, width: 720, height: 800))
        #expect(WindowRegion.top.frame(in: visible) == CGRect(x: 0, y: 470, width: 1440, height: 400))
        #expect(WindowRegion.bottom.frame(in: visible) == CGRect(x: 0, y: 70, width: 1440, height: 400))
        #expect(WindowRegion.topLeft.frame(in: visible) == CGRect(x: 0, y: 470, width: 720, height: 400))
        #expect(WindowRegion.topRight.frame(in: visible) == CGRect(x: 720, y: 470, width: 720, height: 400))
        #expect(WindowRegion.bottomLeft.frame(in: visible) == CGRect(x: 0, y: 70, width: 720, height: 400))
        #expect(WindowRegion.bottomRight.frame(in: visible) == CGRect(x: 720, y: 70, width: 720, height: 400))
        // どの枠も使える範囲の中
        for region in WindowRegion.allCases {
            #expect(visible.contains(region.frame(in: visible)))
        }
    }

    /// 実行の決まり: 前面のアプリに向けて行い、キーは送らず、すぐ終わる
    @Test func executionPolicy() {
        let action = Action.placeWindow(PlaceWindowAction(region: .left))
        #expect(ControllerExecutionPolicy.dependsOnFrontmostApp(action))
        #expect(!ControllerExecutionPolicy.sendsInputToFrontmostApp(action))
        #expect(!ControllerExecutionPolicy.isLongRunning(action))
    }

    /// 初回の設定: グローバルの最初のページは「画面に置く」の9マス、次がランチャー、最後が下のページの「ユーティリティ」（ページ数の上限に収める）
    @Test func theFirstGlobalPageIsWindowPlacement() throws {
        let launcher = PresetLibrary.launcherCandidates.map(\.bundleID)
        let configuration = NonetConfiguration.initial(appPresets: [], installedBundleIDs: Set(launcher))
        let pages = configuration.globalProfile.pages
        #expect(pages.count == Profile.maxPages)
        #expect(pages[0].name == PresetBuilder.text("画面に置く"))
        #expect(pages[0].cells.map { $0?.action } == WindowRegion.allCases.map { .placeWindow(PlaceWindowAction(region: $0)) })
        #expect(pages[0].cells.compactMap { $0 }.map(\.title) == WindowRegion.allCases.map(\.title))
        // ランチャーは1ページ（9個）まで
        #expect(pages[1].cells.compactMap { $0 }.count == Page.cellCount)
        #expect(pages[1].cells.compactMap { $0 }.allSatisfy { $0.action.kind == .launchApp })
        #expect(pages[2].name == PresetBuilder.text("ユーティリティ"))
        #expect(pages[2].cells.map { $0?.action } == PresetLibrary.makeUtilityPage().cells.map { $0?.action })
        #expect(pages.map(\.isBelow) == [false, false, true])

        // ランチャーの候補が無ければ、「画面に置く」と「ユーティリティ」だけ
        let bare = NonetConfiguration.initial(appPresets: [], installedBundleIDs: [])
        #expect(bare.globalProfile.pages.map(\.name) == [PresetBuilder.text("画面に置く"), PresetBuilder.text("ユーティリティ")])
    }
}
