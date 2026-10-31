// 担当: core-model。共通マス（NonetConfiguration.sharedCells）: どのプロファイルのどのページでも同じ位置に出る・
// プロファイルのマスは残る・保存の書式・書き出しと読み込み
import Foundation
@testable import NonetCore
import Testing

@Suite("共通マス")
struct ConfigurationSharedCellsTests {
    typealias F = ModelFixtures

    static let mute = F.cell("ミュート", action: .keystroke(.key("m", [.command, .shift])))
    static let screenshot = F.cell("スクショ", action: .keystroke(.key("4", [.command, .shift])))

    /// グローバル3ページ・Safari（無効）・Xcode（2ページ）に、共通マスを 0 と 8 に置いた設定
    static func configuration(autoSwitch: Bool = true, append: Bool = true) -> NonetConfiguration {
        var configuration = NonetConfiguration(
            settings: GlobalSettings(autoSwitchProfiles: autoSwitch, appendGlobalPages: append),
            profiles: [
                F.globalProfile(pageCount: 3),
                F.profile(F.safari, isEnabled: false),
                F.profile(F.xcode, pageCount: 2),
            ]
        )
        configuration.setSharedCell(mute, at: 0)
        configuration.setSharedCell(screenshot, at: 8)
        return configuration.validated()
    }

    // MARK: - どのページでも同じ位置

    @Test("アプリのページとつなげたグローバルのページの、すべてのページで同じ位置に共通マスが出る")
    func everyPageOfTheAppAndTheAppendedGlobalPagesShowsTheSharedCells() {
        let configuration = Self.configuration()
        let pages = configuration.resolvedPages(frontmostBundleID: F.xcode.bundleID)
        #expect(pages.count == 5)
        for page in pages {
            #expect(page.cells[0]?.title == "ミュート")
            #expect(page.cells[8]?.title == "スクショ")
            #expect(page.sharedIndices == [0, 8])
            #expect(page.cells.count == Page.cellCount)
        }
        // 共通マスの無い位置は、そのプロファイルのマスのまま（Xcode の2ページ目の 2、グローバルの1ページ目の 1）
        #expect(pages[1].cells[2]?.title == "Xcode-1b")
        #expect(pages[2].profileID == configuration.globalProfile.id)
        #expect(pages[2].cells[1] == nil)
    }

    @Test("プロファイルの無いアプリ・前面のアプリで切り替えない・前面のアプリが分からないときのグローバルのページにも出る",
          arguments: [(true, "com.apple.Notes"), (false, "com.apple.dt.Xcode"), (true, nil)] as [(Bool, String?)])
    func theGlobalPagesShowTheSharedCells(autoSwitch: Bool, bundleID: String?) {
        let configuration = Self.configuration(autoSwitch: autoSwitch, append: false)
        let pages = configuration.resolvedPages(frontmostBundleID: bundleID)
        #expect(pages.map(\.profileID) == Array(repeating: configuration.globalProfile.id, count: 3))
        #expect(pages.allSatisfy { $0.cells[0]?.title == "ミュート" && $0.cells[8]?.title == "スクショ" && $0.sharedIndices == [0, 8] })
    }

    @Test("ランチャーのグローバル（初回の設定）のページでも、共通マスがその位置のアプリの代わりに出る")
    func theLauncherPagesShowTheSharedCells() throws {
        let installed = PresetLibrary.launcherCandidates.prefix(12).map(\.bundleID)
        let global = PresetLibrary.makeGlobalProfile(installedBundleIDs: Set(installed))
        try #require(global.pages.count == 2)
        let launcherApp = try #require(global.pages[1].cells[0])
        var configuration = NonetConfiguration(profiles: [global])
        configuration.setSharedCell(Self.mute, at: 0)
        let pages = configuration.resolvedPages(frontmostBundleID: nil)
        #expect(pages.count == 2)
        #expect(pages.allSatisfy { $0.cells[0]?.title == "ミュート" })
        // 共通マスの無い位置はランチャーのアプリのまま
        #expect(pages[0].cells[1] == global.pages[0].cells[1])
        // ランチャーのアプリは消えていない
        #expect(configuration.globalProfile.pages[1].cells[0] == launcherApp)
    }

    @Test("共通マスが無ければ、どのページも今までどおり（sharedIndices は空）")
    func withoutSharedCellsNothingChanges() {
        var configuration = Self.configuration()
        configuration.sharedCells = .empty
        let pages = configuration.resolvedPages(frontmostBundleID: F.xcode.bundleID)
        #expect(pages.allSatisfy { $0.sharedIndices.isEmpty })
        #expect(pages[0].cells == configuration.profile(id: pages[0].profileID)?.pages[0].cells)
    }

    // MARK: - プロファイルのマスは残る

    @Test("共通マスが出ている間もプロファイルのマスは残り、共通マスを外すと元のマスがまた出る")
    func theProfileCellIsKeptAndComesBack() throws {
        var configuration = Self.configuration()
        let xcode = try #require(configuration.appProfile(forBundleID: F.xcode.bundleID))
        let own = try #require(xcode.pages[0].cells[0])
        #expect(configuration.resolvedPages(frontmostBundleID: F.xcode.bundleID)[0].cells[0]?.title == "ミュート")
        // 共通マスがある間も、プロファイルのマスは設定に残っている
        #expect(configuration.profile(id: xcode.id)?.pages[0].cells[0] == own)

        configuration.setSharedCell(nil, at: 0)
        let pages = configuration.resolvedPages(frontmostBundleID: F.xcode.bundleID)
        #expect(pages[0].cells[0] == own)
        #expect(pages[0].sharedIndices == [8])
        // 保存して読み直しても同じ
        let reloaded = try F.roundTrip(configuration).validated()
        #expect(reloaded.resolvedPages(frontmostBundleID: F.xcode.bundleID)[0].cells[0] == own)
    }

    @Test("「このアプリでは Nonet を使わない」のアプリは、共通マスがあっても使わないまま")
    func aTurnedOffAppStaysOff() {
        var configuration = Self.configuration()
        configuration.setAppMode(.off, for: F.xcode)
        #expect(configuration.isTurnedOff(forBundleID: F.xcode.bundleID))
        #expect(!configuration.isTurnedOff(forBundleID: F.safari.bundleID))
    }

    // MARK: - 編集

    @Test("SharedCells.profileID の setCell と swapCells は共通マスを変える。2ページ目以降と範囲外は何もしない")
    func editingThroughTheSharedProfileID() {
        var configuration = Self.configuration()
        let before = configuration.profiles
        configuration.setCell(F.cell("新しい"), at: CellAddress(page: 0, index: 4), profileID: SharedCells.profileID)
        #expect(configuration.sharedCells[4]?.title == "新しい")
        configuration.setCell(F.cell("無視"), at: CellAddress(page: 1, index: 3), profileID: SharedCells.profileID)
        configuration.setSharedCell(F.cell("範囲外"), at: 9)
        #expect(configuration.sharedCells.occupiedPositions == [0, 4, 8])

        configuration.swapCells(CellAddress(page: 0, index: 0), CellAddress(page: 0, index: 1), profileID: SharedCells.profileID)
        #expect(configuration.sharedCells[0] == nil)
        #expect(configuration.sharedCells[1]?.title == "ミュート")
        // プロファイルには触れない
        #expect(configuration.profiles == before)
    }

    @Test("共通マスの id がプロファイルのマスと重なれば振り直す。共通マスの id を使うプロファイルも振り直す")
    func validatedKeepsIDsUnique() throws {
        var configuration = Self.configuration()
        let xcodeCell = try #require(configuration.appProfile(forBundleID: F.xcode.bundleID)?.pages[0].cells[0])
        // 置くときに重なれば新しい id にする
        configuration.setSharedCell(xcodeCell, at: 4)
        #expect(configuration.sharedCells[4]?.id != xcodeCell.id)
        #expect(configuration.sharedCells[4]?.title == xcodeCell.title)

        // ファイルで重なっていたら validated() が振り直す
        var broken = configuration
        broken.sharedCells[4] = xcodeCell
        broken.profiles[1].id = SharedCells.profileID
        let fixed = broken.validated()
        let ids = fixed.modelCellIDs + fixed.sharedCells.cells.compactMap { $0?.id }
        #expect(Set(ids).count == ids.count)
        #expect(!fixed.profiles.contains { $0.id == SharedCells.profileID })
        #expect(fixed.sharedCells.count == 3)
    }

    // MARK: - 保存の書式

    @Test("位置とマスの組で書き、読み直すと同じ")
    func codingRoundTrip() throws {
        let configuration = Self.configuration()
        let object = try F.jsonObject(configuration)
        let entries = try #require(object["sharedCells"] as? [[String: Any]])
        #expect(entries.map { $0["position"] as? Int } == [0, 8])
        #expect((entries[0]["cell"] as? [String: Any])?["title"] as? String == "ミュート")
        #expect(try F.roundTrip(configuration) == configuration)
    }

    @Test("共通マスが無ければ書かない（前の版と同じ書式）。前の版のファイルは共通マス無しで読む")
    func noSharedCellsKeepsTheOldFormat() throws {
        let configuration = F.configuration()
        #expect(try F.jsonObject(configuration)["sharedCells"] == nil)
        let old = #"{"version": 1, "settings": {}, "profiles": [{"id": "6B1A4C2E-3D5F-4A7B-8C9D-0E1F2A3B4C5D", "kind": {"type": "global"}, "pages": [{"cells": []}], "isEnabled": true}]}"#
        let decoded = try F.decode(NonetConfiguration.self, old)
        #expect(decoded.sharedCells.isEmpty)
        #expect(decoded.profiles.count == 1)
    }

    @Test("0〜8 でない位置・同じ位置の2つ目・読めないマスは外し、ほかの共通マスと設定は読む")
    func lossyDecoding() throws {
        let cell = #"{"id": "11111111-2222-3333-4444-555555555555", "title": "A", "icon": {"type": "symbol", "symbol": "star"}, "action": {"type": "openURL", "url": "https://example.com"}}"#
        let second = #"{"title": "B", "icon": {"type": "symbol", "symbol": "star"}, "action": {"type": "openURL", "url": "https://example.com/b"}}"#
        let unknown = #"{"title": "C", "icon": {"type": "symbol", "symbol": "star"}, "action": {"type": "teleport"}}"#
        let json = """
        {"version": 1, "settings": {}, "profiles": [{"kind": {"type": "global"}, "pages": []}],
         "sharedCells": [
           {"position": 9, "cell": \(cell)},
           {"position": -1, "cell": \(cell)},
           {"position": 2, "cell": \(cell)},
           {"position": 2, "cell": \(second)},
           {"position": 5, "cell": \(unknown)},
           {"position": "4", "cell": \(second)},
           {"position": 7, "cell": \(second)}
         ]}
        """
        let decoded = try F.decode(NonetConfiguration.self, json)
        #expect(decoded.sharedCells.occupiedPositions == [2, 7])
        #expect(decoded.sharedCells[2]?.title == "A")
        #expect(decoded.sharedCells[7]?.title == "B")
        #expect(decoded.profiles.count == 1)

        // 配列でなければ共通マス無しで、プロファイルは読む
        let wrongType = try F.decode(NonetConfiguration.self, #"{"profiles": [{"kind": {"type": "global"}}], "sharedCells": {"cells": []}}"#)
        #expect(wrongType.sharedCells.isEmpty)
        #expect(wrongType.profiles.count == 1)
    }

    @Test("保存して読み込むと共通マスが残る。読めなかった共通マスがあれば原本を残す")
    func storeKeepsSharedCells() throws {
        try F.withTemporaryDirectory { directory in
            let store = ConfigurationStore(directory: directory)
            let configuration = Self.configuration()
            try store.save(configuration)
            #expect(try store.load()?.sharedCells == configuration.sharedCells)
            #expect(try F.fileNames(in: directory) == ["configuration.json"])

            // 新しい版の Nonet の位置（9）は読めないので、保存で失わないよう原本を残す
            var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: store.fileURL)) as? [String: Any])
            var entries = try #require(object["sharedCells"] as? [[String: Any]])
            entries[1]["position"] = 9
            object["sharedCells"] = entries
            try JSONSerialization.data(withJSONObject: object).write(to: store.fileURL)
            let loaded = try #require(try store.load())
            #expect(loaded.sharedCells.occupiedPositions == [0])
            #expect(try F.fileNames(in: directory).contains { $0.hasPrefix("configuration.lossy-") })
        }
    }

    // MARK: - 書き出しと読み込み

    @Test("すべての書き出しには共通マスが入り、読み込むと id は新しく中身は同じ。1つのプロファイルの書き出しには入らない")
    func exportIncludesSharedCellsOnlyForFullExports() throws {
        let configuration = Self.configuration()
        let full = try ConfigurationStore.exportData(profiles: configuration.profiles, sharedCells: configuration.sharedCells)
        let document = try ConfigurationStore.importDocument(from: full)
        #expect(document.sharedCells.occupiedPositions == [0, 8])
        #expect(document.sharedCells[0]?.action == Self.mute.action)
        #expect(document.sharedCells[0]?.id != configuration.sharedCells[0]?.id)

        let single = try ConfigurationStore.exportData(profiles: [configuration.profiles[2]])
        #expect(try F.jsonObject(F.string(single))["sharedCells"] == nil)
        #expect(try ConfigurationStore.importDocument(from: single).sharedCells.isEmpty)
        // 共通マスが無ければ、すべての書き出しでも書かない
        let empty = try ConfigurationStore.exportData(profiles: configuration.profiles, sharedCells: .empty)
        #expect(try F.jsonObject(F.string(empty))["sharedCells"] == nil)
    }

    @Test("読み込むと、ファイルの共通マスで今の共通マスを丸ごと置き換える。入っていなければ今のまま")
    func importReplacesSharedCells() throws {
        var current = Self.configuration()
        current.setSharedCell(F.cell("今だけ"), at: 4)
        var other = F.configuration()
        other.setSharedCell(F.cell("届いた"), at: 2)
        let full = try ConfigurationStore.importDocument(from: ConfigurationStore.exportData(profiles: other.profiles, sharedCells: other.sharedCells))

        var replaced = current
        let result = replaced.importProfiles(full)
        #expect(result.replacedSharedCells)
        #expect(replaced.sharedCells.occupiedPositions == [2])
        #expect(replaced.sharedCells[2]?.title == "届いた")

        var kept = current
        let single = try ConfigurationStore.importDocument(from: ConfigurationStore.exportData(profiles: [other.profiles[1]]))
        let singleResult = kept.importProfiles(single)
        #expect(!singleResult.replacedSharedCells)
        #expect(kept.sharedCells == current.sharedCells)
    }

    @Test("前の版の書き出しファイルは共通マス無しで読む。共通マスが壊れていてもプロファイルは読む")
    func oldDocumentsHaveNoSharedCells() throws {
        let profile = try F.string(F.encode(F.profile(F.safari)))
        let old = #"{"format": "com.iam74k4.Nonet.profiles", "version": 1, "exportedAt": "2026-01-01T00:00:00Z", "profiles": [\#(profile)]}"#
        #expect(try ConfigurationStore.importDocument(from: Data(old.utf8)).sharedCells.isEmpty)
        let broken = #"{"format": "com.iam74k4.Nonet.profiles", "version": 1, "exportedAt": "2026-01-01T00:00:00Z", "profiles": [\#(profile)], "sharedCells": 3}"#
        let document = try ConfigurationStore.importDocument(from: Data(broken.utf8))
        #expect(document.sharedCells.isEmpty)
        #expect(document.profiles.count == 1)
    }
}
