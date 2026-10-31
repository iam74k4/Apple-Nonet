// 担当: core-model。HUD で選んだときだけ実行するマス（Cell.requiresHUD）の保存と読み込み
import Foundation
@testable import NonetCore
import Testing

@Suite("モデルの Codable: HUD で選んだときだけ実行するマス")
struct ModelHUDOnlyCodingTests {
    static func cell(requiresHUD: Bool) -> Cell {
        Cell(title: "送信", icon: .symbol("paperplane"), action: .keystroke(.key("d", [.shift, .command])), requiresHUD: requiresHUD)
    }

    @Test func theDefaultIsOff() {
        #expect(!Cell(title: "t", icon: .symbol("star"), action: .openURL(URLAction(url: "u"))).requiresHUD)
    }

    @Test("どちらの値も往復する", arguments: [false, true])
    func roundTrips(_ requiresHUD: Bool) throws {
        let cell = Self.cell(requiresHUD: requiresHUD)
        #expect(try ModelFixtures.roundTrip(cell) == cell)
    }

    /// オフ（既定）なら書かない。この設定より前の版と同じ書式のまま
    @Test func offIsNotWrittenAndOnIsWrittenAsTrue() throws {
        let off = try ModelFixtures.jsonObject(Self.cell(requiresHUD: false))
        #expect(off["requiresHUD"] == nil)
        #expect(Set(off.allKeys.compactMap { $0 as? String }) == ["id", "title", "icon", "action"])
        #expect(try ModelFixtures.jsonObject(Self.cell(requiresHUD: true))["requiresHUD"] as? Bool == true)
    }

    @Test func anOldCellWithoutTheKeyReadsAsOff() throws {
        let cell = try ModelFixtures.decode(Cell.self, #"{"title": "送信", "action": {"type": "openURL", "url": "u"}}"#)
        #expect(!cell.requiresHUD)
        #expect(cell.title == "送信")
    }

    @Test func anUnreadableValueReadsAsOffAndKeepsTheCell() throws {
        let cell = try ModelFixtures.decode(Cell.self, #"{"title": "送信", "requiresHUD": "yes", "action": {"type": "openURL", "url": "u"}}"#)
        #expect(!cell.requiresHUD)
        #expect(cell.action == .openURL(URLAction(url: "u")))
        let null = try ModelFixtures.decode(Cell.self, #"{"title": "t", "requiresHUD": null, "action": {"type": "openURL", "url": "u"}}"#)
        #expect(!null.requiresHUD)
    }

    @Test func aWholeConfigurationKeepsTheFlag() throws {
        var configuration = ModelFixtures.configuration()
        let safari = try #require(configuration.appProfile(forBundleID: ModelFixtures.safari.bundleID))
        configuration.setCell(Self.cell(requiresHUD: true), at: CellAddress(page: 0, index: 8), profileID: safari.id)
        let read = try ModelFixtures.roundTrip(configuration)
        #expect(read.appProfile(forBundleID: ModelFixtures.safari.bundleID)?.pages[0].cells[8]?.requiresHUD == true)
        #expect(read.appProfile(forBundleID: ModelFixtures.safari.bundleID)?.pages[0].cells[0]?.requiresHUD == false)
    }
}
