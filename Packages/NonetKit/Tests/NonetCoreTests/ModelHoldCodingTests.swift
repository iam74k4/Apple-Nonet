// 担当: core-model。HUD で選んだときだけ実行するマス（Cell.requiresHold）の保存と読み込み
import Foundation
@testable import NonetCore
import Testing

@Suite("モデルの Codable: HUD で選んだときだけ実行するマス")
struct ModelHUDOnlyCodingTests {
    static func cell(requiresHold: Bool) -> Cell {
        Cell(title: "送信", icon: .symbol("paperplane"), action: .keystroke(.key("d", [.shift, .command])), requiresHold: requiresHold)
    }

    @Test func theDefaultIsOff() {
        #expect(!Cell(title: "t", icon: .symbol("star"), action: .openURL(URLAction(url: "u"))).requiresHold)
    }

    @Test("どちらの値も往復する", arguments: [false, true])
    func roundTrips(_ requiresHold: Bool) throws {
        let cell = Self.cell(requiresHold: requiresHold)
        #expect(try ModelFixtures.roundTrip(cell) == cell)
    }

    /// オフ（既定）なら書かない。この設定より前の版と同じ書式のまま
    @Test func offIsNotWrittenAndOnIsWrittenAsTrue() throws {
        let off = try ModelFixtures.jsonObject(Self.cell(requiresHold: false))
        #expect(off["requiresHUD"] == nil)
        #expect(Set(off.allKeys.compactMap { $0 as? String }) == ["id", "title", "icon", "action"])
        #expect(try ModelFixtures.jsonObject(Self.cell(requiresHold: true))["requiresHUD"] as? Bool == true)
    }

    @Test func anOldCellWithoutTheKeyReadsAsOff() throws {
        let cell = try ModelFixtures.decode(Cell.self, #"{"title": "送信", "action": {"type": "openURL", "url": "u"}}"#)
        #expect(!cell.requiresHold)
        #expect(cell.title == "送信")
    }

    @Test func anUnreadableValueReadsAsOffAndKeepsTheCell() throws {
        let cell = try ModelFixtures.decode(Cell.self, #"{"title": "送信", "requiresHUD": "yes", "action": {"type": "openURL", "url": "u"}}"#)
        #expect(!cell.requiresHold)
        #expect(cell.action == .openURL(URLAction(url: "u")))
        let null = try ModelFixtures.decode(Cell.self, #"{"title": "t", "requiresHUD": null, "action": {"type": "openURL", "url": "u"}}"#)
        #expect(!null.requiresHold)
    }

    @Test func aWholeConfigurationKeepsTheFlag() throws {
        var configuration = ModelFixtures.configuration()
        let safari = try #require(configuration.appProfile(forBundleID: ModelFixtures.safari.bundleID))
        configuration.setCell(Self.cell(requiresHold: true), at: CellAddress(page: 0, index: 8), profileID: safari.id)
        let read = try ModelFixtures.roundTrip(configuration)
        #expect(read.appProfile(forBundleID: ModelFixtures.safari.bundleID)?.pages[0].cells[8]?.requiresHold == true)
        #expect(read.appProfile(forBundleID: ModelFixtures.safari.bundleID)?.pages[0].cells[0]?.requiresHold == false)
    }
}
