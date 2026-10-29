// 担当: ui-settings
import Foundation
import NonetCore
@testable import NonetUI
import Testing

@Suite struct SettingsGridLogicTests {
    @Test(arguments: [
        (4, SettingsGridDirection.up, 1), (4, .down, 7), (4, .left, 3), (4, .right, 5),
        (0, .up, 0), (0, .left, 0), (2, .right, 2), (8, .down, 8), (6, .left, 6), (3, .up, 0), (5, .down, 8),
    ])
    func neighborStopsAtEdges(index: Int, direction: SettingsGridDirection, expected: Int) {
        #expect(SettingsGrid.neighbor(of: index, direction) == expected)
    }

    @Test func neighborClampsOutOfRangeIndex() {
        #expect(SettingsGrid.neighbor(of: -3, .right) == 1)
        #expect(SettingsGrid.neighbor(of: 42, .left) == 7)
    }

    private func profile(pages: [[Bool]]) -> Profile {
        Profile(kind: .global, pages: pages.map { filled in
            Page(cells: filled.map { $0 ? SettingsFixtures.launch(SettingsFixtures.safari) : nil })
        })
    }

    @Test func nextEmptyWrapsWithinThePageFirst() {
        // 0〜3 と 5〜8 が埋まり、4 だけ空き。8 の次を探すと折り返して 4
        let profile = profile(pages: [[true, true, true, true, false, true, true, true, true]])
        #expect(SettingsGrid.nextEmptyAddress(after: CellAddress(page: 0, index: 8), in: profile) == CellAddress(page: 0, index: 4))
        #expect(SettingsGrid.nextEmptyAddress(after: CellAddress(page: 0, index: 2), in: profile) == CellAddress(page: 0, index: 4))
    }

    @Test func nextEmptyLooksAtOtherPagesWhenThePageIsFull() {
        let full = Array(repeating: true, count: 9)
        let profile = profile(pages: [[false] + Array(repeating: true, count: 8), full, [true, true, false]])
        // ページ 2 は満杯。ほかのページを前から探すので、ページ 1 の 0
        #expect(SettingsGrid.nextEmptyAddress(after: CellAddress(page: 1, index: 3), in: profile) == CellAddress(page: 0, index: 0))
    }

    @Test func nextEmptyIsNilWhenEverythingIsFull() {
        let full = Array(repeating: true, count: 9)
        #expect(SettingsGrid.nextEmptyAddress(after: CellAddress(page: 0, index: 0), in: profile(pages: [full, full])) == nil)
    }

    @Test func assignmentTargetPrefersTheSelectedEmptyCell() {
        let profile = profile(pages: [[true, false, false]])
        #expect(SettingsGrid.assignmentTarget(selected: CellAddress(page: 0, index: 2), currentPage: 0, in: profile) == CellAddress(page: 0, index: 2))
        // 選んでいるマスが埋まっていれば、そのページの最初の空き
        #expect(SettingsGrid.assignmentTarget(selected: CellAddress(page: 0, index: 0), currentPage: 0, in: profile) == CellAddress(page: 0, index: 1))
        #expect(SettingsGrid.assignmentTarget(selected: nil, currentPage: 0, in: profile) == CellAddress(page: 0, index: 1))
    }

    @Test func assignmentTargetFallsBackToOtherPagesAndNil() {
        let full = Array(repeating: true, count: 9)
        #expect(SettingsGrid.assignmentTarget(selected: nil, currentPage: 0, in: profile(pages: [full, [true, true, true, false]])) == CellAddress(page: 1, index: 3))
        #expect(SettingsGrid.assignmentTarget(selected: CellAddress(page: 0, index: 4), currentPage: 0, in: profile(pages: [full])) == nil)
    }

    @Test func addressAndCellLookups() {
        let cell = SettingsFixtures.key("ビルド", .key("b", .command))
        let profile = Profile(kind: .global, pages: [.empty, Page(cells: [nil, nil, cell])])
        #expect(SettingsGrid.address(ofCell: cell.id, in: profile) == CellAddress(page: 1, index: 2))
        #expect(SettingsGrid.address(ofCell: UUID(), in: profile) == nil)
        #expect(SettingsGrid.cell(at: CellAddress(page: 1, index: 2), in: profile) == cell)
        #expect(SettingsGrid.cell(at: CellAddress(page: 5, index: 0), in: profile) == nil)
        #expect(SettingsGrid.cell(at: CellAddress(page: 0, index: 9), in: profile) == nil)
        #expect(SettingsGrid.isEmpty(CellAddress(page: 0, index: 0), in: profile))
        #expect(!SettingsGrid.isEmpty(CellAddress(page: 1, index: 2), in: profile))
        #expect(!SettingsGrid.isEmpty(CellAddress(page: 3, index: 0), in: profile))
    }

    @Test func namesAndAccessibilityLabels() {
        #expect(SettingsGrid.cellName(4) == "マス 5（中央）")
        #expect(SettingsGrid.positionName(0) == "左上")
        #expect(SettingsGrid.positionName(8) == "右下")
        #expect(SettingsGrid.accessibilityLabel(index: 2, cell: nil) == "3番目のマス（右上）：空き")
        let cell = SettingsFixtures.key("ビルド", .key("b", .command))
        #expect(SettingsGrid.accessibilityLabel(index: 0, cell: cell) == "1番目のマス（左上）：ビルド、⌘B")
    }

    @Test func untitledAndIncompleteCellsShowUsefulText() {
        let empty = Cell(title: "  ", icon: .symbol("keyboard"), action: .keystroke(KeySequence([])))
        #expect(SettingsGrid.displayTitle(for: empty) == "キー入力")
        #expect(SettingsGrid.subtitle(for: empty) == "未設定")
        let shortcut = Cell(title: "", icon: .symbol("bolt"), action: .shortcut(ShortcutAction(name: "マイクを切る")))
        #expect(SettingsGrid.displayTitle(for: shortcut) == "マイクを切る")
        // 名前と同じ説明は出さず、種類の名前にする
        #expect(SettingsGrid.subtitle(for: shortcut) == "ショートカット")
        let app = SettingsFixtures.launch(SettingsFixtures.safari)
        #expect(SettingsGrid.subtitle(for: app) == "アプリ起動")
        var renamed = app
        renamed.title = "ブラウザ"
        #expect(SettingsGrid.subtitle(for: renamed) == "Safari")
    }

    @Test func menuItemsShowTheirKey() {
        let withKey = Cell(title: "自動レイアウトを追加", icon: .symbol("filemenu.and.selection"),
                           action: .menuItem(MenuItemAction(path: ["オブジェクト", "自動レイアウトを追加"], keyEquivalent: .key("a", .shift))))
        #expect(SettingsGrid.subtitle(for: withKey) == "⇧A")
        let withoutKey = Cell(title: "整列", icon: .symbol("filemenu.and.selection"),
                              action: .menuItem(MenuItemAction(path: ["オブジェクト", "整列"])))
        #expect(SettingsGrid.subtitle(for: withoutKey) == "メニュー項目")
    }

    @Test func dragPayloadRoundTrips() {
        let id = UUID()
        let cell = SettingsDragPayload.cell(profileID: id, address: CellAddress(page: 2, index: 8))
        #expect(SettingsDragPayload(token: cell.token) == cell)
        let menu = SettingsDragPayload.menuItem(id: "編集\u{1F}コピー")
        #expect(SettingsDragPayload(token: menu.token) == menu)
    }

    @Test(arguments: [
        "", "hello", "nonet-settings-cell|", "nonet-settings-cell|not-a-uuid|0|0",
        "nonet-settings-cell|\(UUID().uuidString)|0|9", "nonet-settings-cell|\(UUID().uuidString)|-1|0",
        "nonet-settings-cell|\(UUID().uuidString)|0", "nonet-settings-menu|",
    ])
    func dragPayloadRejectsForeignText(token: String) {
        #expect(SettingsDragPayload(token: token) == nil)
    }
}
