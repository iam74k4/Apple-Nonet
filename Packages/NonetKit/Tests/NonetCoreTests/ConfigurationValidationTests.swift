// 担当: core-model。validated() による修復
import Foundation
@testable import NonetCore
import Testing

@Suite("validated()")
struct ConfigurationValidationTests {
    @Test("正しい設定は変えない。何度かけても同じ")
    func validConfigurationUnchanged() {
        let configuration = ModelFixtures.configuration()
        #expect(configuration.validated() == configuration)
        #expect(configuration.validated().validated() == configuration)
    }

    @Test("グローバルが無ければ空のものを先頭に加える")
    func insertsMissingGlobal() {
        let configuration = NonetConfiguration(profiles: [ModelFixtures.profile(ModelFixtures.safari)]).validated()
        #expect(configuration.profiles.count == 2)
        #expect(configuration.profiles[0].isGlobal)
        #expect(configuration.profiles[0].pages == [.empty])
        #expect(configuration.profiles[1].app == ModelFixtures.safari)
        #expect(configuration.validated() == configuration)

        let empty = NonetConfiguration(profiles: []).validated()
        #expect(empty.profiles.count == 1)
        #expect(empty.globalProfile.isGlobal)
    }

    @Test("グローバルが先頭でなければ先頭に移し、アプリの並びは保つ")
    func movesGlobalFirst() {
        let a = ModelFixtures.profile(ModelFixtures.safari)
        let b = ModelFixtures.profile(ModelFixtures.xcode)
        let global = ModelFixtures.globalProfile()
        let configuration = NonetConfiguration(profiles: [a, global, b]).validated()
        #expect(configuration.profiles.map(\.id) == [global.id, a.id, b.id])
    }

    @Test("グローバルが2つ以上あれば最初のものを残す")
    func dropsExtraGlobals() {
        let first = ModelFixtures.globalProfile()
        let second = ModelFixtures.globalProfile(pageCount: 2)
        let configuration = NonetConfiguration(profiles: [ModelFixtures.profile(ModelFixtures.safari), first, second]).validated()
        #expect(configuration.profiles.filter(\.isGlobal).map(\.id) == [first.id])
        #expect(configuration.profiles.count == 2)
    }

    @Test("同じアプリのプロファイルは最初のものを残す（大文字と小文字は区別しない）")
    func dropsDuplicateApps() {
        let first = ModelFixtures.profile(ModelFixtures.safari, prefix: "1")
        let second = ModelFixtures.profile(AppReference(bundleID: "com.apple.safari", name: "safari"), prefix: "2")
        let third = ModelFixtures.profile(ModelFixtures.safari, isEnabled: false, prefix: "3")
        let configuration = NonetConfiguration(profiles: [ModelFixtures.globalProfile(), first, second, third]).validated()
        #expect(configuration.modelAppProfiles.map(\.id) == [first.id])
    }

    @Test("プロファイルの id が重なれば、後のものを振り直す")
    func uniqueProfileIDs() {
        let global = ModelFixtures.globalProfile()
        var safari = ModelFixtures.profile(ModelFixtures.safari)
        var xcode = ModelFixtures.profile(ModelFixtures.xcode)
        safari.id = global.id
        xcode.id = global.id
        let configuration = NonetConfiguration(profiles: [global, safari, xcode]).validated()
        #expect(configuration.profiles[0].id == global.id)
        #expect(Set(configuration.profiles.map(\.id)).count == 3)
        #expect(configuration.profiles.map(\.name) == [ModelFixtures.globalName, "Safari", "Xcode"])
    }

    @Test("マスの id が重なれば（プロファイルをまたいでも）、後のものを振り直す")
    func uniqueCellIDs() throws {
        let shared = UUID()
        let global = Profile(kind: .global, pages: [Page(cells: [ModelFixtures.cell("g", id: shared), ModelFixtures.cell("g2", id: shared)])])
        let safari = Profile(kind: .app(ModelFixtures.safari), pages: [Page(cells: [ModelFixtures.cell("s", id: shared)])])
        let configuration = NonetConfiguration(profiles: [global, safari]).validated()
        #expect(configuration.profiles[0].pages[0].cells[0]?.id == shared)
        #expect(Set(configuration.modelCellIDs).count == 3)
        #expect(configuration.profiles[0].modelTitles[0][0...1] == ["g", "g2"])
        #expect(configuration.profiles[1].modelTitles[0][0] == "s")
    }

    @Test("ページ数を 1〜3、マス数を 9 に揃える")
    func normalizesPagesAndCells() {
        var global = ModelFixtures.globalProfile()
        global.pages = []
        var safari = ModelFixtures.profile(ModelFixtures.safari)
        safari.pages = Array(repeating: ModelFixtures.page(["x"]), count: 5)
        safari.pages[0].cells = [nil, nil]
        safari.pages[1].cells += Array(repeating: nil, count: 4)
        let configuration = NonetConfiguration(profiles: [global, safari]).validated()
        #expect(configuration.profiles[0].pages == [.empty])
        #expect(configuration.profiles[1].pages.count == Profile.maxPages)
        #expect(configuration.profiles.allSatisfy { $0.pages.allSatisfy { $0.cells.count == Page.cellCount } })
        #expect(configuration.profiles[1].modelTitles[1][0] == "x")
    }

    @Test("全体の設定は変えない")
    func keepsSettings() {
        let settings = GlobalSettings(isEnabled: false, hudPosition: .nearCursor, haptics: .off, cursorLock: .none, hudScale: .large)
        #expect(NonetConfiguration(settings: settings, profiles: []).validated().settings == settings)
    }

    @Test("スクリプトの制限時間を範囲に収める", arguments: [
        (0.0, 1.0), (-5.0, 1.0), (30.0, 30.0), (1e9, 3600.0), (Double.nan, 60.0), (Double.infinity, 60.0),
    ])
    func clampsScriptTimeout(_ value: Double, _ expected: Double) throws {
        let cell = ModelFixtures.cell("s", action: .script(ScriptAction(source: "x", timeout: value)))
        let configuration = NonetConfiguration(profiles: [Profile(kind: .global, pages: [Page(cells: [cell])])]).validated()
        let action = try #require(configuration.profiles[0].pages[0].cells[0]?.action)
        #expect(action == .script(ScriptAction(source: "x", timeout: expected)))
    }

    @Test("グローバルは常に有効、アプリの無効はそのまま")
    func globalAlwaysEnabled() {
        var global = ModelFixtures.globalProfile()
        global.isEnabled = false
        let configuration = NonetConfiguration(profiles: [global, ModelFixtures.profile(ModelFixtures.safari, isEnabled: false)]).validated()
        #expect(configuration.profiles[0].isEnabled)
        #expect(!configuration.profiles[1].isEnabled)
    }

    @Test("版は今の版にする")
    func setsCurrentVersion() {
        #expect(NonetConfiguration(version: 0, profiles: []).validated().version == NonetConfiguration.currentVersion)
        #expect(NonetConfiguration(version: 7, profiles: []).validated().version == NonetConfiguration.currentVersion)
    }

    @Test("いろいろ壊れた設定も、一度で不変条件を満たす")
    func repairsEverythingAtOnce() {
        let shared = UUID()
        var broken = NonetConfiguration(
            settings: GlobalSettings(haptics: .strong),
            profiles: [
                ModelFixtures.profile(ModelFixtures.xcode, pageCount: 3),
                ModelFixtures.profile(ModelFixtures.xcode),
                Profile(kind: .app(ModelFixtures.safari), pages: [Page(cells: [ModelFixtures.cell("a", id: shared)])]),
                Profile(kind: .app(ModelFixtures.figma), pages: [Page(cells: [ModelFixtures.cell("b", id: shared)])]),
            ]
        )
        broken.profiles[0].pages.append(.empty)
        broken.profiles[3].id = broken.profiles[2].id

        let repaired = broken.validated()
        #expect(Self.satisfiesInvariants(repaired))
        #expect(repaired.validated() == repaired)
        #expect(repaired.modelAppProfiles.map(\.name) == ["Xcode", "Safari", "Figma"])
    }

    /// docs/architecture.md の不変条件
    static func satisfiesInvariants(_ configuration: NonetConfiguration) -> Bool {
        let profiles = configuration.profiles
        let bundleIDs = profiles.compactMap { $0.app?.bundleID.lowercased() }
        return profiles.first?.isGlobal == true
            && profiles.filter(\.isGlobal).count == 1
            && Set(bundleIDs).count == bundleIDs.count
            && profiles.allSatisfy { (1...Profile.maxPages).contains($0.pages.count) }
            && profiles.allSatisfy { $0.pages.allSatisfy { $0.cells.count == Page.cellCount } }
            && Set(profiles.map(\.id)).count == profiles.count
            && Set(configuration.modelCellIDs).count == configuration.modelCellIDs.count
    }
}
