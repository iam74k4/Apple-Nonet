// 担当: core-model。下のページ（Page.isBelow）の保存と読み込み・決まり（validated）・前面アプリで使うページの並び（resolvedPages）と、
// HUD に渡す層（ControllerPresentation）
import Foundation
@testable import NonetCore
import Testing

@Suite("下のページ")
struct ModelBelowPageTests {
    /// グローバルが global-0・global-2・下のページの global-1（validated が下のページを最後へ移す）＋Xcode（2ページ）
    static func configuration() -> NonetConfiguration {
        var global = ModelFixtures.globalProfile(pageCount: 3)
        global.pages[1].isBelow = true
        return NonetConfiguration(settings: GlobalSettings(), profiles: [global, ModelFixtures.profile(ModelFixtures.xcode, pageCount: 2)])
            .validated()
    }

    static func names(_ pages: [Page]) -> [String?] {
        pages.map { $0.cells[0]?.title }
    }

    // MARK: 保存と読み込み

    /// 付いているときだけ "below": true を書く（前の版と同じ書式のまま）。無い・読めなければふつうのページ。
    /// 開発中の版（上に置いていたころ）の "above" も読む
    @Test func onlyTheBelowPageWritesTheKey() throws {
        let plain = try ModelFixtures.jsonObject(ModelFixtures.page(["a"]))
        #expect(plain["below"] == nil)
        var below = ModelFixtures.page(["a"])
        below.isBelow = true
        let written = try ModelFixtures.jsonObject(below)
        #expect(written["below"] as? Bool == true)
        #expect(written["above"] == nil)
        #expect(try ModelFixtures.roundTrip(below) == below)
        #expect(try !ModelFixtures.decode(Page.self, #"{"cells": []}"#).isBelow)
        #expect(try !ModelFixtures.decode(Page.self, #"{"cells": [], "below": "yes"}"#).isBelow)
        #expect(try ModelFixtures.decode(Page.self, #"{"cells": [], "above": true}"#).isBelow)
    }

    // MARK: 決まり

    /// 下のページはグローバルの1つだけ（前にあるものを残す）で、いつも最後。アプリのページの印は外す
    @Test func onlyOneGlobalPageStaysAboveAndComesLast() throws {
        var global = ModelFixtures.globalProfile(pageCount: 3)
        global.pages[1].isBelow = true
        global.pages[2].isBelow = true
        var app = ModelFixtures.profile(ModelFixtures.xcode, pageCount: 2)
        app.pages[0].isBelow = true
        let validated = NonetConfiguration(settings: GlobalSettings(), profiles: [global, app]).validated()
        #expect(Self.names(validated.globalProfile.pages) == ["global-0", "global-2", "global-1"])
        #expect(validated.globalProfile.pages.map(\.isBelow) == [false, false, true])
        #expect(try #require(validated.appProfile(forBundleID: ModelFixtures.xcode.bundleID)).pages.allSatisfy { !$0.isBelow })
    }

    /// setBelowPage は印を付け替えて、下のページにしたページを最後へ移す（今の番号を返す）。外すと最後のまま。
    /// アプリのプロファイル・範囲外・ページが1つだけのグローバルでは何もしない
    @Test func settingTheBelowPageMovesItLast() throws {
        var configuration = Self.configuration()
        let globalID = configuration.globalProfile.id
        let moved = configuration.setBelowPage(true, at: 0, profileID: globalID)
        #expect(moved == 2)
        #expect(Self.names(configuration.globalProfile.pages) == ["global-2", "global-1", "global-0"])
        #expect(configuration.globalProfile.pages.map(\.isBelow) == [false, false, true])
        let cleared = configuration.setBelowPage(false, at: 2, profileID: globalID)
        #expect(cleared == 2)
        #expect(configuration.globalProfile.pages.allSatisfy { !$0.isBelow })
        let outOfRange = configuration.setBelowPage(true, at: 3, profileID: globalID)
        #expect(outOfRange == nil)
        let xcode = try #require(configuration.appProfile(forBundleID: ModelFixtures.xcode.bundleID))
        let onApp = configuration.setBelowPage(true, at: 0, profileID: xcode.id)
        #expect(onApp == nil)

        var single = NonetConfiguration(settings: GlobalSettings(), profiles: [ModelFixtures.globalProfile(pageCount: 1)])
        let lone = single.setBelowPage(true, at: 0, profileID: single.globalProfile.id)
        #expect(lone == nil)
        #expect(!single.globalProfile.pages[0].isBelow)
    }

    /// ページを足すと、下のページの手前に入る。下のページがもうあれば、足した下のページはふつうのページになる
    @Test func addedPagesGoBeforeTheBelowPage() {
        var configuration = Self.configuration()
        let globalID = configuration.globalProfile.id
        configuration.removePage(at: 1, profileID: globalID)
        var above = ModelFixtures.page(["new"])
        above.isBelow = true
        let added = configuration.addPage(above, profileID: globalID)
        #expect(added == 1)
        #expect(Self.names(configuration.globalProfile.pages) == ["global-0", "new", "global-1"])
        #expect(configuration.globalProfile.pages.map(\.isBelow) == [false, false, true])
    }

    /// 消したページを戻す（元に戻す）と、下のページの印も戻る。ふつうのページは下のページの後ろには入らない（入れた番号を返す）
    @Test func reinsertingAPageKeepsTheOrder() {
        var configuration = Self.configuration()
        let globalID = configuration.globalProfile.id
        let removedAbove = configuration.globalProfile.pages[2]
        configuration.removePage(at: 2, profileID: globalID)
        #expect(configuration.globalProfile.pages.allSatisfy { !$0.isBelow })
        let restored = configuration.insertPage(removedAbove, at: 2, profileID: globalID)
        #expect(restored == 2)
        #expect(configuration.globalProfile.pages.map(\.isBelow) == [false, false, true])

        let removed = configuration.globalProfile.pages[0]
        configuration.removePage(at: 0, profileID: globalID)
        let clamped = configuration.insertPage(removed, at: 5, profileID: globalID)
        #expect(clamped == 1)
        #expect(Self.names(configuration.globalProfile.pages) == ["global-2", "global-0", "global-1"])
    }

    // MARK: 並び

    /// 下のページは最後。アプリのページがあってもなくても、どのアプリの前でも同じ
    @Test func theBelowPageComesLast() {
        let configuration = Self.configuration()
        let globalOnly = configuration.resolvedPages(frontmostBundleID: "com.apple.Notes")
        #expect(globalOnly.map(\.pageIndex) == [0, 1, 2])
        #expect(globalOnly.map(\.isBelow) == [false, false, true])
        let withApp = configuration.resolvedPages(frontmostBundleID: ModelFixtures.xcode.bundleID)
        #expect(withApp.map(\.isBelow) == [false, false, false, false, true])
        #expect(withApp.last?.profileID == configuration.globalProfile.id)
    }

    /// グローバルが下のページだけ（ほかのページを消した）なら、印は残したまま、ふつうのページとして並べる。
    /// アプリのページがあれば、そのページがグローバルの層になる
    @Test func aLoneBelowPageIsAnOrdinaryPage() {
        var configuration = Self.configuration()
        let globalID = configuration.globalProfile.id
        configuration.removePage(at: 0, profileID: globalID)
        configuration.removePage(at: 0, profileID: globalID)
        #expect(configuration.globalProfile.pages.map(\.isBelow) == [true])
        let globalOnly = configuration.resolvedPages(frontmostBundleID: nil)
        #expect(globalOnly.map(\.isBelow) == [false])
        let withApp = configuration.resolvedPages(frontmostBundleID: ModelFixtures.xcode.bundleID)
        #expect(withApp.map(\.isBelow) == [false, false, false])
        #expect(ControllerPresentation.belowPageStart(withApp) == nil)
        #expect(ControllerPresentation.globalPagesStart(withApp) == 2)
    }

    // MARK: HUD に渡す層

    /// 下のページは1ページの層（above）。グローバルの層は下のページの手前まで。セッションの設定にも同じ位置を渡す
    @Test func theBelowPageIsItsOwnLayer() {
        let configuration = Self.configuration()
        let withApp = configuration.resolvedPages(frontmostBundleID: ModelFixtures.xcode.bundleID)
        #expect(ControllerPresentation.globalPagesStart(withApp) == 2)
        #expect(ControllerPresentation.belowPageStart(withApp) == 4)
        #expect(ControllerPresentation.layers(of: withApp, at: 3).layer == .global)
        #expect(ControllerPresentation.layers(of: withApp, at: 3).range == 2..<4)
        #expect(ControllerPresentation.layers(of: withApp, at: 4).layer == .below)
        #expect(ControllerPresentation.layers(of: withApp, at: 4).range == 4..<5)

        let globalOnly = configuration.resolvedPages(frontmostBundleID: nil)
        #expect(ControllerPresentation.layers(of: globalOnly, at: 1).layer == nil)
        #expect(ControllerPresentation.layers(of: globalOnly, at: 1).range == 0..<2)
        let model = ControllerPresentation.hudModel(pages: globalOnly, state: SessionHUDState(page: 2, highlightedCell: nil, lastTurn: .up), banner: nil)
        #expect(model.layer == .below)
        #expect(model.pageCount == 1)
        #expect(model.pageIndex == 0)

        let session = ControllerSession(configuration: configuration, frontmostApp: RunningAppInfo(app: ModelFixtures.xcode, processID: 1))
        #expect(session.engineConfiguration.layerStart == 2)
        #expect(session.engineConfiguration.belowStart == 4)
    }

    /// アプリのページと下のページだけ（グローバルの層が無い）並びでも、真ん中はアプリの層。下のページから戻る先はアプリのページ
    @Test func anAppLayerWithoutGlobalPagesIsStillTheAppLayer() {
        let app = UUID(), global = UUID()
        let pages = [
            ResolvedPage(profileID: app, profileName: "Xcode", pageIndex: 0, cells: []),
            ResolvedPage(profileID: app, profileName: "Xcode", pageIndex: 1, cells: []),
            ResolvedPage(profileID: global, profileName: "Global", pageIndex: 0, cells: [], isBelow: true),
        ]
        #expect(ControllerPresentation.hasAppLayer(pages))
        #expect(ControllerPresentation.globalPagesStart(pages) == nil)
        #expect(ControllerPresentation.layers(of: pages, at: 1).layer == .app)
        #expect(ControllerPresentation.layers(of: pages, at: 1).range == 0..<2)
        let state = SessionHUDState(page: 2, highlightedCell: nil, isInFrame: true, edgePaging: SessionEdgePaging(edge: .up, since: 0, duration: 0.5))
        let model = ControllerPresentation.hudModel(pages: pages, state: state, banner: nil)
        #expect(model.edgePaging?.destination == .app)
        #expect(model.edgePaging?.destinationTitle == "Xcode")
    }

    /// 止めているときの行き先の名前: 左右は隣のページの名前（無ければ「ページ N」）、下は下のページの名前、上はグローバル
    @Test func destinationTitlesAreShortNames() {
        var configuration = Self.configuration()
        let xcodeID = configuration.appProfile(forBundleID: ModelFixtures.xcode.bundleID)!.id
        configuration.renamePage(at: 1, profileID: xcodeID, to: "デバッグ")
        configuration.renamePage(at: 2, profileID: configuration.globalProfile.id, to: "ユーティリティ")
        let pages = configuration.resolvedPages(frontmostBundleID: ModelFixtures.xcode.bundleID)
        #expect(ControllerPresentation.destinationTitle(of: .right, pages: pages, at: 0, layer: nil) == "デバッグ")
        #expect(ControllerPresentation.destinationTitle(of: .left, pages: pages, at: 1, layer: nil) == ModelFixtures.text("ページ \(1)"))
        #expect(ControllerPresentation.destinationTitle(of: .down, pages: pages, at: 0, layer: .below) == "ユーティリティ")
        #expect(ControllerPresentation.destinationTitle(of: .up, pages: pages, at: 0, layer: .global) == ModelFixtures.globalName)
        // ページが1つの層の左右は無い
        let globalOnly = configuration.resolvedPages(frontmostBundleID: nil)
        #expect(ControllerPresentation.destinationTitle(of: .right, pages: [globalOnly[2]], at: 0, layer: nil) == nil)
    }

    /// 上下の帯に止めている間の行き先の層。エンジンの3段と同じ（上がグローバルの層、下が下のページ）
    @Test func destinationsFollowTheThreeRows() {
        #expect(ControllerPresentation.destination(of: .down, from: .app, hasAppLayer: true) == .below)
        #expect(ControllerPresentation.destination(of: .up, from: .app, hasAppLayer: true) == .global)
        #expect(ControllerPresentation.destination(of: .down, from: .global, hasAppLayer: true) == .app)
        #expect(ControllerPresentation.destination(of: .up, from: .below, hasAppLayer: true) == .app)
        #expect(ControllerPresentation.destination(of: .down, from: nil, hasAppLayer: false) == .below)
        #expect(ControllerPresentation.destination(of: .up, from: .below, hasAppLayer: false) == .global)
        #expect(ControllerPresentation.destination(of: .left, from: .app, hasAppLayer: true) == nil)

        let pages = Self.configuration().resolvedPages(frontmostBundleID: nil)
        let state = SessionHUDState(page: 0, highlightedCell: nil, isInFrame: true, edgePaging: SessionEdgePaging(edge: .down, since: 0, duration: 0.5))
        let model = ControllerPresentation.hudModel(pages: pages, state: state, banner: nil)
        #expect(model.edgePaging?.destination == .below)
        // 名前の無い下のページは、プロファイルの名前
        #expect(model.edgePaging?.destinationTitle == ModelFixtures.globalName)
    }
}
