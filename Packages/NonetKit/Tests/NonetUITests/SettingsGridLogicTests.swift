// 担当: ui-settings
import AppKit
import Foundation
import NonetCore
@testable import NonetUI
import Testing
import UniformTypeIdentifiers

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

    /// インスペクタの「メニューから選ぶ…」から来たとき・割り当て直すとき: 選んでいるメニュー項目のマスに入れる（項目を選ぶ前のものも）
    @Test func assignmentTargetUsesTheSelectedMenuItemCell() {
        let unset = Cell(title: "", icon: .symbol("filemenu.and.selection"), action: .menuItem(MenuItemAction(path: [])))
        var profile = profile(pages: [[true, false, false]])
        profile.pages[0].cells[0] = unset
        #expect(SettingsGrid.assignmentTarget(selected: CellAddress(page: 0, index: 0), currentPage: 0, in: profile) == CellAddress(page: 0, index: 0))
        #expect(SettingsGrid.isMenuItem(CellAddress(page: 0, index: 0), in: profile))
        #expect(!SettingsGrid.isMenuItem(CellAddress(page: 0, index: 1), in: profile))
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
        #expect(SettingsGrid.cellName(4) == L10n.ui("マス \(5)（\(L10n.ui("中央"))）"))
        #expect(SettingsGrid.positionName(0) == L10n.ui("左上"))
        #expect(SettingsGrid.positionName(8) == L10n.ui("右下"))
        let topRight = L10n.ui("\(3)番目のマス（\(L10n.ui("右上"))）")
        #expect(SettingsGrid.accessibilityLabel(index: 2, cell: nil) == L10n.ui("\(topRight)：空き"))
        let cell = SettingsFixtures.key("ビルド", .key("b", .command))
        let topLeft = L10n.ui("\(1)番目のマス（\(L10n.ui("左上"))）")
        #expect(SettingsGrid.accessibilityLabel(index: 0, cell: cell) == L10n.ui("\(topLeft)：\("ビルド")、\("⌘B")"))
    }

    @Test func untitledAndIncompleteCellsShowUsefulText() {
        let empty = Cell(title: "  ", icon: .symbol("keyboard"), action: .keystroke(KeySequence([])))
        #expect(SettingsGrid.displayTitle(for: empty) == L10n.ui("キー入力"))
        #expect(SettingsGrid.subtitle(for: empty) == L10n.ui("未設定"))
        let shortcut = Cell(title: "", icon: .symbol("bolt"), action: .shortcut(ShortcutAction(name: "マイクを切る")))
        #expect(SettingsGrid.displayTitle(for: shortcut) == "マイクを切る")
        // 名前と同じ説明は出さず、種類の名前にする
        #expect(SettingsGrid.subtitle(for: shortcut) == L10n.ui("ショートカット"))
        let app = SettingsFixtures.launch(SettingsFixtures.safari)
        #expect(SettingsGrid.subtitle(for: app) == L10n.ui("開く"))
        var renamed = app
        renamed.title = "ブラウザ"
        // アプリ起動はいつも種類の名前。開くアプリの名前はヘルプ・検索・VoiceOver に残す
        #expect(SettingsGrid.subtitle(for: renamed) == L10n.ui("開く"))
        #expect(SettingsGrid.detailContent(for: renamed).text == "Safari")
        // ヘルプは、切れているかもしれない名前と、何をするか
        #expect(SettingsGrid.tooltip(for: renamed) == "ブラウザ\nSafari")
        #expect(SettingsGrid.tooltip(for: shortcut) == "マイクを切る\n\(L10n.ui("ショートカット"))")
        #expect(SettingsGrid.tooltip(for: SettingsFixtures.key("ビルド", .key("b", .command))) == "ビルド\n⌘B")
        #expect(SettingsGrid.tooltip(for: nil) == nil)
        #expect(SettingsGrid.accessibilityLabel(index: 0, cell: renamed).contains("Safari"))
    }

    @Test func menuItemsShowTheirKey() {
        let withKey = Cell(title: "自動レイアウトを追加", icon: .symbol("filemenu.and.selection"),
                           action: .menuItem(MenuItemAction(path: ["オブジェクト", "自動レイアウトを追加"], keyEquivalent: .key("a", .shift))))
        #expect(SettingsGrid.subtitle(for: withKey) == "⇧A")
        let withoutKey = Cell(title: "整列", icon: .symbol("filemenu.and.selection"),
                              action: .menuItem(MenuItemAction(path: ["オブジェクト", "整列"])))
        #expect(SettingsGrid.subtitle(for: withoutKey) == L10n.ui("メニュー項目"))
    }

    /// 等幅で出すのはキーの表記だけ。「スクリプト」「アプリ起動」などの言葉は普通の字で出す
    @Test func onlyKeyStringsAreMarkedAsKeys() {
        #expect(SettingsGrid.subtitleContent(for: SettingsFixtures.key("ビルド", .key("b", .command))) == ("⌘B", true))
        let menu = Cell(title: "自動レイアウトを追加", icon: .symbol("filemenu.and.selection"),
                        action: .menuItem(MenuItemAction(path: ["オブジェクト", "自動レイアウトを追加"], keyEquivalent: .key("a", .shift))))
        #expect(SettingsGrid.subtitleContent(for: menu) == ("⇧A", true))
        let menuWithoutKey = Cell(title: "揃える", icon: .symbol("filemenu.and.selection"),
                                  action: .menuItem(MenuItemAction(path: ["オブジェクト", "整列"])))
        #expect(SettingsGrid.subtitleContent(for: menuWithoutKey) == ("整列", false))
        let script = Cell(title: "Claude Code", icon: .symbol("sparkles"), action: .script(ScriptAction(source: "claude", runMode: .terminal)))
        #expect(SettingsGrid.subtitleContent(for: script) == (L10n.core("ターミナル"), false))
        #expect(SettingsGrid.subtitleContent(for: SettingsFixtures.launch(SettingsFixtures.safari)) == (L10n.ui("開く"), false))
        let unset = Cell(title: "", icon: .symbol("keyboard"), action: .keystroke(KeySequence([])))
        #expect(SettingsGrid.subtitleContent(for: unset) == (L10n.ui("未設定"), false))
        // 名前と同じキーの表記は種類の名前に変わるので、等幅にしない
        #expect(SettingsGrid.subtitleContent(for: SettingsFixtures.key("⌘B", .key("b", .command))) == (L10n.ui("キー入力"), false))
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

/// ドラッグの中身は専用の種類だけで運ぶ（テキストの欄やほかのアプリに落ちないこと）
@Suite struct SettingsDragItemTests {
    @Test func providersCarryOnlyThePrivateType() async throws {
        let item = SettingsDragItem(payload: .cell(profileID: UUID(), address: CellAddress(page: 1, index: 4)))
        let provider = NSItemProvider()
        provider.register(item)
        #expect(provider.registeredTypeIdentifiers == [UTType.nonetSettingsDrag.identifier])
        #expect(!provider.hasItemConformingToTypeIdentifier(UTType.text.identifier))
        #expect(!provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier))
        #expect(!provider.hasItemConformingToTypeIdentifier(UTType.url.identifier))
        #expect(!provider.canLoadObject(ofClass: NSString.self))
        #expect(!provider.canLoadObject(ofClass: NSURL.self))
        #expect(!provider.hasItemConformingToTypeIdentifier(UTType.rtf.identifier))

        let loaded: SettingsDragItem = try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadTransferable(type: SettingsDragItem.self) { continuation.resume(with: $0) }
        }
        #expect(loaded == item)
    }

    @Test func foreignDataIsRejected() async {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.nonetSettingsDrag.identifier, visibility: .all) { completion in
            completion(Data("https://example.com".utf8), nil)
            return nil
        }
        let result: Result<SettingsDragItem, any Error> = await withCheckedContinuation { continuation in
            _ = provider.loadTransferable(type: SettingsDragItem.self) { continuation.resume(returning: $0) }
        }
        #expect((try? result.get()) == nil)
    }
}
