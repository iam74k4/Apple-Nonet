// 担当: ui-shell
// メニューバーの「最近の実行」（MenuBarModel の並びと文言、SettingsWindowController.showRun の選び方）
import AppKit
import NonetCore
@testable import NonetUI
import Testing

@Suite("「最近の実行」")
@MainActor
struct ShellRecentRunsTests {
    static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    static func record(profile: String, profileID: UUID? = nil, title: String = "ビルド", page: Int = 0, index: Int = 0,
                       succeeded: Bool = true, message: String? = nil) -> ExecutionRecord {
        ExecutionRecord(
            cellTitle: title,
            profileName: profile,
            address: CellAddress(page: page, index: index),
            succeeded: succeeded,
            message: message,
            date: now,
            profileID: profileID
        )
    }

    @Test("実行の記録があれば「初回の案内をもう一度」の前に出し、無ければ出さない")
    func entryOnlyWithRuns() {
        var state = ShellMenuState.make()
        #expect(!MenuBarModel.entries(for: state).contains { if case .recentRuns = $0 { true } else { false } })
        let runs = [Self.record(profile: "Xcode"), Self.record(profile: "Safari", succeeded: false)]
        state.recentRuns = runs
        let entries = MenuBarModel.entries(for: state)
        let index = entries.firstIndex(of: .recentRuns(runs))
        #expect(index != nil)
        #expect(index.map { entries[$0 + 1] } == .showOnboarding)
        #expect(MenuBarEntry.recentRuns(runs).title == L10n.ui("最近の実行"))
    }

    @Test("成功は ✓、失敗は ✗ と理由の1行目")
    func titles() {
        let ok = Self.record(profile: "Xcode")
        #expect(MenuBarModel.recentRunTitle(ok) == L10n.ui("\("✓") \("Xcode") › \("ビルド")"))
        let failed = Self.record(profile: "Xcode", succeeded: false, message: "終了コード 1\n詳しいログ")
        let base = L10n.ui("\("✗") \("Xcode") › \("ビルド")")
        #expect(MenuBarModel.recentRunTitle(failed) == L10n.ui("\(base) — \("終了コード 1")"))
        let failedWithoutReason = Self.record(profile: "Xcode", succeeded: false, message: nil)
        #expect(MenuBarModel.recentRunTitle(failedWithoutReason) == base)
    }

    @Test("VoiceOver では ✓・✗ の代わりに、成功・失敗を言葉で読む")
    func accessibilityLabels() {
        let ok = Self.record(profile: "Xcode")
        #expect(MenuBarModel.recentRunAccessibilityLabel(ok) == L10n.ui("成功: \("Xcode") › \("ビルド")"))
        let failed = Self.record(profile: "Xcode", succeeded: false, message: "終了コード 1\n詳しいログ")
        let base = L10n.ui("失敗: \("Xcode") › \("ビルド")")
        #expect(MenuBarModel.recentRunAccessibilityLabel(failed) == L10n.ui("\(base) — \("終了コード 1")"))
        #expect(!MenuBarModel.recentRunAccessibilityLabel(failed).contains("✗"))
    }

    @Test("表示名の無いマスは、いまの設定のそのマスのアクションの説明で出す（「」と出さない）")
    func unnamedCellTitles() {
        let cell = Cell(title: "", icon: .symbol("keyboard"), action: .keystroke(.key("b", .command)))
        let global = Profile(kind: .global, pages: [Page(cells: [cell])])
        let configuration = NonetConfiguration(profiles: [global])
        let record = ExecutionRecord(
            cellTitle: "", profileName: "グローバル", address: CellAddress(page: 0, index: 0),
            succeeded: true, message: nil, date: Date(), profileID: global.id
        )
        let title = SettingsGrid.displayTitle(for: cell)
        #expect(!title.isEmpty)
        #expect(MenuBarModel.recentRunTitle(record, in: configuration) == L10n.ui("\("✓") \("グローバル") › \(title)"))
        // 名前のあるマスは記録の名前のまま
        let named = Self.record(profile: "Xcode")
        #expect(MenuBarModel.recentRunTitle(named, in: configuration) == MenuBarModel.recentRunTitle(named))
    }

    @Test("選ぶと、記録のプロファイル（id、無ければ名前）のページとマスを開く")
    func selectsTheRecordedCell() throws {
        _ = NSApplication.shared
        let harness = try SettingsHarness()
        let xcode = try #require(harness.xcodeProfile)
        harness.controller.update { _ = $0.addPage(profileID: xcode.id) }
        let window = ShellEditButtonsTests.makeWindow(harness)
        window.model.selectTab(.general)

        window.selectRun(Self.record(profile: "名前が違っても id で探す", profileID: xcode.id, page: 1, index: 4))
        #expect(window.model.tab == .profiles)
        #expect(window.model.selectedProfile.id == xcode.id)
        #expect(window.model.pageIndex == 1)
        #expect(window.model.selectedIndex == 4)

        window.selectRun(Self.record(profile: xcode.name, page: 0, index: 2))
        #expect(window.model.selectedProfile.id == xcode.id)
        #expect(window.model.pageIndex == 0)
        #expect(window.model.selectedIndex == 2)
    }
}
