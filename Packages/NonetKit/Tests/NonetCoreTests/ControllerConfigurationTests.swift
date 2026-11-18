// 担当: engine。NonetController の設定の読み込み（初回・壊れたファイル・読めないファイル）と、まとめた保存
import Foundation
import Testing
@testable import NonetCore

@MainActor
@Suite struct ControllerConfigurationTests {
    typealias F = ControllerFixtures

    private func fileNames(_ h: ControllerHarness) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: h.directory.path(percentEncoded: false)).sorted()
    }

    private func setPermissions(_ h: ControllerHarness, _ mode: Int) throws {
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: h.directory.path(percentEncoded: false))
    }

    // MARK: 読み込み

    @Test func firstLaunchBuildsAndSavesTheInitialConfiguration() throws {
        let h = try ControllerHarness(configuration: nil, installed: [F.safari.bundleID])
        h.start()

        #expect(h.controller.isFirstLaunch)
        #expect(h.controller.notice == nil)
        let configuration = h.controller.configuration
        #expect(configuration.settings == GlobalSettings())
        #expect(configuration.appProfile(forBundleID: F.safari.bundleID) != nil)
        #expect(configuration.profiles.count == 2)
        // グローバルの最初のページは「画面に置く」、次は「ユーティリティ」。ランチャー（3ページ目）にはインストール済みのアプリだけ
        #expect(configuration.globalProfile.pages[0].cells.allSatisfy { $0?.action.kind == .placeWindow })
        #expect(configuration.globalProfile.pages[1].name == PresetBuilder.text("ユーティリティ"))
        let launcher = configuration.globalProfile.pages[2].cells.compactMap { $0?.action }
        #expect(launcher == [.launchApp(LaunchAppAction(app: F.safari))])
        // 待たずに保存する
        #expect(try h.savedConfiguration() == configuration)
    }

    @Test func withoutInstalledPresetAppsOnlyTheGlobalProfileIsMade() throws {
        let h = try ControllerHarness(configuration: nil)
        h.start()
        #expect(h.controller.configuration.profiles.count == 1)
    }

    @Test func aSavedConfigurationIsNotAFirstLaunch() throws {
        let h = try ControllerHarness()
        h.start()
        #expect(!h.controller.isFirstLaunch)
        #expect(h.controller.configuration == (try h.savedConfiguration()))
    }

    @Test func aCorruptFileIsReplacedWithTheInitialConfiguration() throws {
        let h = try ControllerHarness(configuration: nil, installed: [F.safari.bundleID])
        try Data("{ これは JSON ではない".utf8).write(to: h.store.fileURL)
        h.start()

        #expect(!h.controller.isFirstLaunch)
        let notice = try #require(h.controller.notice)
        #expect(notice.contains("configuration.corrupt-"))
        #expect(h.controller.configuration.appProfile(forBundleID: F.safari.bundleID) != nil)
        #expect(try h.savedConfiguration() == h.controller.configuration)
        // 壊れたファイルは別の名前で残っている
        #expect(try fileNames(h).contains { $0.hasPrefix("configuration.corrupt-") })
        #expect(h.controller.status == .running)

        h.controller.dismissNotice()
        #expect(h.controller.notice == nil)
    }

    @Test func anUnreadableFileIsNeverOverwritten() throws {
        let h = try ControllerHarness(configuration: nil)
        try FileManager.default.createDirectory(at: h.store.fileURL, withIntermediateDirectories: false)
        h.start()

        #expect(!h.controller.isFirstLaunch)
        let notice = try #require(h.controller.notice)
        // readFailed の説明は理由を含まないので、知らせの文全体を比べられる
        let reason = try #require(ConfigurationStoreError.readFailed(reason: "").errorDescription)
        #expect(notice == ModelFixtures.text("\(reason)。設定の変更は保存されません。「以前の設定に戻す…」で控えに戻すと、また保存します。"))
        // 初期の設定のまま動く
        #expect(h.controller.status == .running)
        #expect(h.controller.configuration.settings == GlobalSettings())

        h.controller.update { $0.settings.haptics = .off }
        #expect(h.controller.configuration.settings.haptics == .off)
        h.advance(5)
        h.controller.stop()
        #expect(try fileNames(h) == ["configuration.json"])
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: h.store.fileURL.path(percentEncoded: false), isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
    }

    /// 新しい版の Nonet で書いた、この版では読めないファイル: 写しを残し、保存しない。控えに戻すと（resumeSaving）、また保存する
    @Test func aNewerVersionFileStopsSavingUntilABackupIsRestored() throws {
        let h = try ControllerHarness(configuration: nil)
        let future = #"{"version": 9, "profiles": "新しい形"}"#
        try FileManager.default.createDirectory(at: h.store.directory, withIntermediateDirectories: true)
        try Data(future.utf8).write(to: h.store.fileURL)
        h.start()
        #expect(!h.controller.isFirstLaunch)
        #expect(!h.controller.isSavingConfiguration)
        #expect(try String(contentsOf: h.store.fileURL, encoding: .utf8) == future)
        #expect(try fileNames(h).contains("configuration.v9.json"))

        h.controller.update { $0.settings.haptics = .off }
        h.controller.resumeSaving()
        #expect(h.controller.isSavingConfiguration)
        #expect(h.controller.notice == nil)
        #expect(try h.savedConfiguration()?.settings.haptics == .off)
        // 元のファイルは写しに残っている
        #expect(try String(contentsOf: h.store.directory.appending(path: "configuration.v9.json"), encoding: .utf8) == future)
        h.controller.stop()
    }

    @Test func changesBeforeStartAreNotSaved() throws {
        let h = try ControllerHarness()
        let original = try h.fileData()
        h.controller.update { $0.settings.haptics = .off }
        h.advance(1)
        #expect(try h.fileData() == original)
        h.start()
        #expect(h.controller.configuration.settings.haptics == .medium)
    }

    // MARK: 保存

    @Test func savesAreCoalescedIntoOneWrite() throws {
        let h = try ControllerHarness()
        let original = try h.fileData()
        h.start()
        h.controller.update { $0.settings.haptics = .light }
        h.controller.update { $0.settings.haptics = .strong }
        h.controller.update { $0.settings.haptics = .off }
        // 変更はすぐに反映するが、書くのは後でまとめて
        #expect(h.controller.configuration.settings.haptics == .off)
        #expect(try h.fileData() == original)
        h.advance(0.49)
        #expect(try h.fileData() == original)
        h.advance(0.02)
        #expect(try h.savedConfiguration()?.settings.haptics == .off)
        // 書いたのは1回だけ（バックアップは途中の値でなく元の設定）
        #expect(try Data(contentsOf: h.store.backupFileURL) == original)

        h.controller.update { $0.settings.haptics = .light }
        h.advance(0.5)
        #expect(try h.savedConfiguration()?.settings.haptics == .light)
    }

    @Test func stopWritesThePendingSave() throws {
        let h = try ControllerHarness()
        h.start()
        h.controller.update { $0.settings.haptics = .strong }
        h.controller.stop()
        #expect(try h.savedConfiguration()?.settings.haptics == .strong)
    }

    @Test func updatesAreValidatedAndUnchangedConfigurationsAreNotSaved() throws {
        let h = try ControllerHarness()
        h.start()
        h.controller.update { $0.profiles[0].pages = [] }
        #expect(h.controller.configuration.profiles[0].pages.count == 1)
        h.advance(1)
        #expect(h.scheduler.pending.map(\.delay) == [NonetController.pollInterval])

        let delays = h.scheduler.requestedDelays.count
        h.controller.replaceConfiguration(h.controller.configuration)
        h.controller.update { _ in }
        #expect(h.scheduler.requestedDelays.count == delays)
    }

    @Test func aSaveFailureShowsANoticeUntilASaveSucceeds() throws {
        let h = try ControllerHarness()
        h.start()
        try setPermissions(h, 0o500)
        h.controller.update { $0.settings.haptics = .light }
        h.advance(0.5)
        let failure = ConfigurationStoreError.writeFailed(reason: "").errorDescription
        #expect(h.controller.notice == failure)

        try setPermissions(h, 0o755)
        h.controller.update { $0.settings.haptics = .strong }
        h.advance(0.5)
        #expect(h.controller.notice == nil)
        #expect(try h.savedConfiguration()?.settings.haptics == .strong)
    }

    @Test func aSuccessfulSaveKeepsOtherNotices() throws {
        let h = try ControllerHarness(configuration: nil)
        try Data("壊れている".utf8).write(to: h.store.fileURL)
        h.start()
        let corrupt = try #require(h.controller.notice)
        h.controller.update { $0.settings.haptics = .light }
        h.advance(0.5)
        #expect(try h.savedConfiguration()?.settings.haptics == .light)
        #expect(h.controller.notice == corrupt)
    }

    @Test func firstLaunchWithAnUnwritableFolderShowsANotice() throws {
        let h = try ControllerHarness(configuration: nil)
        try setPermissions(h, 0o500)
        h.start()
        #expect(h.controller.isFirstLaunch)
        #expect(h.controller.notice == ConfigurationStoreError.writeFailed(reason: "").errorDescription)
        try setPermissions(h, 0o755)
    }
}
