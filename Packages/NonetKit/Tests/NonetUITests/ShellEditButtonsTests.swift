// 担当: ui-shell
// メニューバーの「◯◯のボタンを編集…」から開く設定（SettingsWindowController.showButtons とその選び方）
import AppKit
import NonetCore
@testable import NonetUI
import Testing

@Suite("「◯◯のボタンを編集…」で開く設定")
@MainActor
struct ShellEditButtonsTests {
    static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    static func makeWindow(_ harness: SettingsHarness) -> SettingsWindowController {
        let window = SettingsWindowController(
            controller: harness.controller,
            license: harness.license,
            services: harness.services,
            links: AppLinks(),
            onCheckForUpdates: nil
        )
        window.autosavesFrame = false
        return window
    }

    static func record(profile: String, page: Int, index: Int, date: Date) -> ExecutionRecord {
        ExecutionRecord(
            cellTitle: "マス",
            profileName: profile,
            address: CellAddress(page: page, index: index),
            succeeded: true,
            message: nil,
            date: date
        )
    }

    @Test("アプリのプロファイルをプロファイルのタブで選ぶ（ほかのタブを開いていても）")
    func selectsTheAppProfile() throws {
        _ = NSApplication.shared
        let harness = try SettingsHarness()
        let window = Self.makeWindow(harness)
        window.model.selectTab(.general)
        window.selectButtons(for: SettingsFixtures.xcode, now: Self.now)
        #expect(window.model.tab == .profiles)
        #expect(window.model.selectedProfile.id == harness.xcodeProfile?.id)
        #expect(window.model.pageIndex == 0)
        #expect(window.model.selectedIndex == 0)
    }

    @Test("「複製して別のアプリに使う…」のシートが開いていても、メニューバーから作るプロファイルはプリセットから作る（複製の元を写さない）")
    func makingButtonsClosesTheDuplicateSheet() throws {
        _ = NSApplication.shared
        let harness = try SettingsHarness()
        let window = Self.makeWindow(harness)
        let xcode = try #require(harness.xcodeProfile)
        window.model.beginDuplicatingProfile(xcode.id)
        window.selectButtons(for: SettingsFixtures.notes, now: Self.now)
        #expect(!window.model.isAddingProfile)
        #expect(window.model.duplicatingProfileID == nil)
        let notes = try #require(harness.controller.configuration.profiles.first { $0.app?.bundleID == SettingsFixtures.notes.bundleID })
        #expect(window.model.selectedProfile.id == notes.id)
        let titles = { (profile: Profile) in profile.pages.flatMap(\.cells).map { $0?.title } }
        #expect(titles(notes) != titles(xcode))
    }

    @Test("最近実行したマスは、プロファイルの id で見分ける（名前が同じ別のプロファイルを選ばない。id の無い記録は名前で）")
    func recentCellsAreMatchedByProfileID() throws {
        _ = NSApplication.shared
        let harness = try SettingsHarness()
        let profile = try #require(harness.xcodeProfile)
        var byID = Self.record(profile: "名前が変わった", page: 0, index: 5, date: Self.now)
        byID.profileID = profile.id
        #expect(SettingsWindowController.recentAddress(of: byID, in: profile, now: Self.now) == CellAddress(page: 0, index: 5))
        var sameName = Self.record(profile: profile.name, page: 0, index: 5, date: Self.now)
        sameName.profileID = UUID()
        #expect(SettingsWindowController.recentAddress(of: sameName, in: profile, now: Self.now) == nil)
    }

    @Test("60秒以内にそのプロファイルのマスを実行していれば、そのページとマスを選ぶ")
    func selectsTheRecentCell() async throws {
        _ = NSApplication.shared
        let harness = try SettingsHarness()
        let xcode = try #require(harness.xcodeProfile)
        // 2ページ目を作っておく
        harness.controller.update { _ = $0.addPage(profileID: xcode.id) }
        let profile = try #require(harness.xcodeProfile)
        let recent = Self.record(profile: profile.name, page: 1, index: 5, date: Self.now.addingTimeInterval(-30))
        #expect(SettingsWindowController.recentAddress(of: recent, in: profile, now: Self.now) == CellAddress(page: 1, index: 5))
        // 古い・ほかのプロファイル・無いページ・先の時刻は選ばない
        let old = Self.record(profile: profile.name, page: 1, index: 5, date: Self.now.addingTimeInterval(-61))
        #expect(SettingsWindowController.recentAddress(of: old, in: profile, now: Self.now) == nil)
        let other = Self.record(profile: "Safari", page: 0, index: 5, date: Self.now)
        #expect(SettingsWindowController.recentAddress(of: other, in: profile, now: Self.now) == nil)
        let missingPage = Self.record(profile: profile.name, page: 2, index: 5, date: Self.now)
        #expect(SettingsWindowController.recentAddress(of: missingPage, in: profile, now: Self.now) == nil)
        let future = Self.record(profile: profile.name, page: 0, index: 5, date: Self.now.addingTimeInterval(5))
        #expect(SettingsWindowController.recentAddress(of: future, in: profile, now: Self.now) == nil)
        #expect(SettingsWindowController.recentAddress(of: nil, in: profile, now: Self.now) == nil)
        #expect(SettingsWindowController.recentExecutionWindow == 60)

        // 実際に実行した記録（テスト実行。グローバルの右上の「ターミナル」）で開く
        let window = Self.makeWindow(harness)
        let global = harness.controller.configuration.globalProfile
        let cell = try #require(global.pages[0].cells[2])
        _ = await harness.controller.testRun(cell, profileID: global.id)
        let executed = try #require(harness.controller.lastExecution)
        #expect(executed.address == CellAddress(page: 0, index: 2))
        window.selectButtons(for: nil, now: executed.date.addingTimeInterval(10))
        #expect(window.model.selectedProfile.id == global.id)
        #expect(window.model.selectedAddress == executed.address)
    }

    @Test("プロファイルの無いアプリなら、プリセットで作って選ぶ")
    func createsTheProfile() throws {
        _ = NSApplication.shared
        let harness = try SettingsHarness()
        let window = Self.makeWindow(harness)
        #expect(OnboardingModel.profile(forBundleID: SettingsFixtures.figma.bundleID, in: harness.controller.configuration.profiles) == nil)
        window.selectButtons(for: SettingsFixtures.figma, now: Self.now)
        let figma = try #require(OnboardingModel.profile(forBundleID: SettingsFixtures.figma.bundleID, in: harness.controller.configuration.profiles))
        #expect(window.model.selectedProfile.id == figma.id)
        #expect(window.model.tab == .profiles)
        // プリセットがあれば、その中身で作る
        if let preset = PresetLibrary.preset(forBundleID: SettingsFixtures.figma.bundleID) {
            #expect(figma.pages.first?.cells.map { $0?.title } == preset.pages.first?.cells.map { $0?.title })
        }
        // もう一度選んでも増やさない
        window.selectButtons(for: SettingsFixtures.figma, now: Self.now)
        #expect(harness.controller.configuration.profiles.filter { $0.app?.bundleID == SettingsFixtures.figma.bundleID }.count == 1)
    }

    @Test("アプリが無ければ（nil）グローバルを選ぶ。無効のプロファイルも選べる")
    func selectsGlobalAndDisabled() throws {
        _ = NSApplication.shared
        let harness = try SettingsHarness()
        let window = Self.makeWindow(harness)
        window.selectButtons(for: SettingsFixtures.xcode, now: Self.now)
        window.selectButtons(for: nil, now: Self.now)
        #expect(window.model.selectedProfile.id == harness.controller.configuration.globalProfile.id)
        // Safari のプロファイルは無効
        window.selectButtons(for: SettingsFixtures.safari, now: Self.now)
        #expect(window.model.selectedProfile.id == harness.safariProfile?.id)
    }

    @Test("同じプロファイルを開き直しても、選んでいたページとマスはそのまま（実行した記録が無ければ）")
    func keepsSelectionWithoutRecord() throws {
        _ = NSApplication.shared
        let harness = try SettingsHarness()
        let window = Self.makeWindow(harness)
        window.selectButtons(for: SettingsFixtures.xcode, now: Self.now)
        window.model.selectCell(7)
        window.selectButtons(for: SettingsFixtures.xcode, now: Self.now)
        #expect(window.model.selectedIndex == 7)
    }

    @Test("サイドバーの「使用中」: 前面のアプリでいま使われるプロファイル（無効なら・アプリが分からなければグローバル）")
    func inUseProfile() throws {
        let harness = try SettingsHarness()
        let model = harness.model
        #expect(model.inUseProfileID == harness.controller.configuration.globalProfile.id)
        harness.frontmost.current = RunningAppInfo(app: SettingsFixtures.xcode, processID: 10)
        #expect(model.inUseProfileID == harness.xcodeProfile?.id)
        harness.frontmost.current = RunningAppInfo(app: SettingsFixtures.safari, processID: 11)
        #expect(model.inUseProfileID == harness.controller.configuration.globalProfile.id)
    }
}
