// 担当: ui-settings
// ページの並びの図（SettingsPageMap）: 上の段・左右の段・下の段に、どのページを置くか
import Foundation
import NonetCore
@testable import NonetUI
import Testing

@Suite @MainActor struct SettingsPageMapTests {
    /// 初回の設定と同じグローバル（画面に置く・ランチャー・下のページのユーティリティ）と、2ページの Xcode
    private static func configuration() -> NonetConfiguration {
        var global = Profile(kind: .global, pages: [
            PresetLibrary.makeWindowPlacementPage(),
            Page(cells: [SettingsFixtures.launch(SettingsFixtures.safari)]),
            PresetLibrary.makeUtilityPage(),
        ])
        global.pages[1].name = nil
        var configuration = NonetConfiguration(profiles: [global])
        let xcodeID = configuration.addAppProfile(for: SettingsFixtures.xcode, preset: PresetLibrary.preset(forBundleID: SettingsFixtures.xcode.bundleID))
        configuration.addPage(profileID: xcodeID)
        return configuration.validated()
    }

    /// グローバル: 上の段は下のページ、左右の段はそれ以外のページ、下の段は無し
    @Test func theGlobalProfilePutsItsPageAboveOnTop() {
        let configuration = Self.configuration()
        let map = SettingsPageMap(profile: configuration.globalProfile, global: configuration.globalProfile)
        #expect(map.isGlobal)
        #expect(map.ownBelowPage == 2)
        #expect(map.centerPages == [0, 1])
        #expect(map.globalBelowPage == nil)
        #expect(map.globalLayerPages.isEmpty)
    }

    /// アプリ: 左右の段はそのアプリのページ、上の段はグローバルの下のページ、下の段はグローバルのほかのページ
    @Test func anAppProfileShowsTheGlobalPagesAboveAndBelow() throws {
        let configuration = Self.configuration()
        let xcode = try #require(configuration.appProfile(forBundleID: SettingsFixtures.xcode.bundleID))
        let map = SettingsPageMap(profile: xcode, global: configuration.globalProfile)
        #expect(!map.isGlobal)
        #expect(map.centerPages == [0, 1])
        #expect(map.ownBelowPage == nil)
        #expect(map.globalBelowPage == SettingsPageMap.GlobalPage(index: 2, title: L10n.core("ユーティリティ")))
        #expect(map.globalLayerPages == [
            SettingsPageMap.GlobalPage(index: 0, title: L10n.core("画面に置く")),
            SettingsPageMap.GlobalPage(index: 1, title: SettingsText.pageTitle(index: 1, name: nil)),
        ])
    }

    /// 下のページしか無いグローバルは、HUD と同じく、そのページを左右の段に置く。下のページが無ければ上の段は空
    @Test func aLoneOrMissingPageAbove() {
        var lone = Profile(kind: .global, pages: [PresetLibrary.makeUtilityPage()])
        let loneMap = SettingsPageMap(profile: lone, global: lone)
        #expect(loneMap.ownBelowPage == nil)
        #expect(loneMap.centerPages == [0])
        // アプリの図でも、下のページだけのグローバルはふつうのページ（下の段）
        let app = Profile(kind: .app(SettingsFixtures.xcode), pages: [.empty])
        #expect(SettingsPageMap(profile: app, global: lone).globalBelowPage == nil)
        #expect(SettingsPageMap(profile: app, global: lone).globalLayerPages.map(\.index) == [0])
        lone.pages[0].isBelow = false
        let appMap = SettingsPageMap(profile: app, global: lone)
        #expect(appMap.globalBelowPage == nil)
        #expect(appMap.globalLayerPages.map(\.index) == [0])
    }

    /// HUD でアプリのページを使わないとき（「グローバルを使う」「使わない」・マスが1つも無い）は、上下の段を出さない。
    /// マスが無いときは、マスを置けば使うことを一言で言う
    @Test func rowsFollowHowTheAppUsesItsPages() throws {
        let configuration = Self.configuration()
        var xcode = try #require(configuration.appProfile(forBundleID: SettingsFixtures.xcode.bundleID))
        #expect(SettingsPageMap(profile: xcode, global: configuration.globalProfile).showsRows)
        xcode.mode = .global
        #expect(!SettingsPageMap(profile: xcode, global: configuration.globalProfile).showsRows)
        xcode.mode = .off
        #expect(!SettingsPageMap(profile: xcode, global: configuration.globalProfile).showsRows)
        let empty = Profile(kind: .app(SettingsFixtures.notes), pages: [.empty])
        let emptyMap = SettingsPageMap(profile: empty, global: configuration.globalProfile)
        #expect(!emptyMap.showsRows)
        #expect(emptyMap.emptyAppName == SettingsFixtures.notes.name)
        #expect(SettingsPageMap(profile: configuration.globalProfile, global: configuration.globalProfile).showsRows)
    }

    /// 図の上下の段のグローバルのページを押すと、グローバルのプロファイルでそのページを開く
    @Test func openingAGlobalPageFromAnAppProfile() throws {
        let h = try SettingsHarness(configuration: Self.configuration())
        let xcode = try #require(h.xcodeProfile)
        h.model.selectProfile(xcode.id)
        let above = try #require(h.model.pageMap.globalBelowPage)
        h.model.showGlobalPage(above.index)
        #expect(h.model.selectedProfile.isGlobal)
        #expect(h.model.pageIndex == 2)
        #expect(h.model.selectedProfile.pages[h.model.pageIndex].isBelow)
    }
}
