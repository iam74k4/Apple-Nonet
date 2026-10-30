// 担当: core-model。以前の設定の控え（Backups フォルダ。1時間に1回まで・削除や読み込みの前・10個まで）
import Foundation
@testable import NonetCore
import Testing

@Suite("ConfigurationStore: 以前の設定の控え")
struct StoreBackupTests {
    private static let start = Date(timeIntervalSinceReferenceDate: 815_000_000)

    /// プロファイルの id はいつも同じ（何度作っても等しい）
    private static let base = ModelFixtures.configuration().validated()

    private func configuration(_ haptics: HapticStrength = .medium, hudDelay: Double = 0.3) -> NonetConfiguration {
        var configuration = Self.base
        configuration.settings = GlobalSettings(hudDelay: hudDelay, haptics: haptics)
        return configuration.validated()
    }

    @Test("変えている間、変える前の設定を1時間に1回まで残す")
    func automaticBackupsAtMostHourly() throws {
        try ModelFixtures.withTemporaryDirectory { directory throws in
            let store = ConfigurationStore(directory: directory)
            let first = configuration(.off)
            try store.save(first, now: Self.start)
            // 初めての保存では控えるものが無い
            #expect(store.backups().isEmpty)

            try store.save(configuration(.light), now: Self.start + 10)
            try store.save(configuration(.strong), now: Self.start + 1800)
            #expect(try store.backups().map { try store.loadBackup($0) } == [first])
            #expect(store.backups().map(\.reason) == [.automatic])

            // 1時間たったら、そのときの（変える前の）設定を残す
            try store.save(configuration(.medium), now: Self.start + 3600 + 10)
            #expect(try store.backups().map { try store.loadBackup($0) } == [configuration(.strong), first])
            #expect(store.backups().first?.date == Self.start + 3600 + 10)
        }
    }

    @Test("時計が戻っていたら、待たずに残す")
    func clockGoingBackwards() throws {
        try ModelFixtures.withTemporaryDirectory { directory throws in
            let store = ConfigurationStore(directory: directory)
            try store.save(configuration(.off), now: Self.start)
            try store.save(configuration(.light), now: Self.start + 10)
            try store.save(configuration(.strong), now: Self.start - 100)
            #expect(store.backups().count == 2)
        }
    }

    @Test("削除や読み込みの前の控えは、理由をファイル名に入れて残す。同じ中身が続けば作り直さない")
    func explicitBackups() throws {
        try ModelFixtures.withTemporaryDirectory { directory throws in
            let store = ConfigurationStore(directory: directory)
            let current = configuration(.light)
            let backup = try #require(store.makeBackup(of: current, reason: .beforeDeletingProfile, now: Self.start))
            #expect(backup.reason == .beforeDeletingProfile)
            #expect(backup.url.lastPathComponent == "configuration-\(ConfigurationStore.backupTimestamp(for: Self.start))-delete-profile.json")
            #expect(backup.url.deletingLastPathComponent().lastPathComponent == "Backups")
            #expect(try store.loadBackup(backup) == current)

            // 中身が同じなら新しく作らない
            #expect(store.makeBackup(of: current, reason: .beforeImport, now: Self.start + 1) == backup)
            // 同じ秒でも別の名前で残す
            let other = try #require(store.makeBackup(of: configuration(.strong), reason: .beforeDeletingProfile, now: Self.start))
            #expect(other.url != backup.url)
            #expect(store.backups().count == 2)
        }
    }

    @Test("控えは新しいものから10個まで")
    func keepsTheNewestTen() throws {
        try ModelFixtures.withTemporaryDirectory { directory throws in
            let store = ConfigurationStore(directory: directory)
            for index in 0..<13 {
                store.makeBackup(of: configuration(hudDelay: 0.2 + Double(index) * 0.01), reason: .beforeDeletingPage, now: Self.start + Double(index))
            }
            let backups = store.backups()
            #expect(backups.count == ConfigurationStore.maxBackups)
            #expect(backups.first?.date == Self.start + 12)
            #expect(backups.last?.date == Self.start + 3)
            #expect(try store.loadBackup(backups[0]).settings.hudDelay == 0.32)
        }
    }

    @Test("控えのファイル名の読み取り", arguments: ConfigurationBackup.Reason.allCases)
    func parsesNames(_ reason: ConfigurationBackup.Reason) throws {
        let stamp = ConfigurationStore.backupTimestamp(for: Self.start)
        let parsed = try #require(ConfigurationStore.parseBackupName("configuration-\(stamp)-\(reason.rawValue).json"))
        #expect(parsed.reason == reason)
        #expect(parsed.date == Self.start)
        #expect(ConfigurationStore.parseBackupName("configuration-\(stamp)-\(reason.rawValue)-3.json")?.reason == reason)
    }

    @Test("控えでないファイルは数えない")
    func ignoresOtherFiles() throws {
        #expect(ConfigurationStore.parseBackupName("configuration.json") == nil)
        #expect(ConfigurationStore.parseBackupName("configuration-20261031T101500Z-unknown.json") == nil)
        #expect(ConfigurationStore.parseBackupName("configuration-20261031T101500Z-import-x.json") == nil)
        #expect(ConfigurationStore.parseBackupName("notes.txt") == nil)
        try ModelFixtures.withTemporaryDirectory { directory throws in
            let store = ConfigurationStore(directory: directory)
            try FileManager.default.createDirectory(at: store.backupsDirectory, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: store.backupsDirectory.appending(path: ".DS_Store"))
            #expect(store.backups().isEmpty)
        }
    }

    @Test("壊れた控えは読めないと知らせる")
    func corruptBackup() throws {
        try ModelFixtures.withTemporaryDirectory { directory throws in
            let store = ConfigurationStore(directory: directory)
            let backup = try #require(store.makeBackup(of: configuration(), reason: .beforeImport, now: Self.start))
            try Data("{".utf8).write(to: backup.url)
            #expect(throws: ConfigurationStoreError.self) { try store.loadBackup(backup) }
        }
    }

    @Test("最後に読み込んだ場所を覚える（設定画面が控えを読む場所）")
    func remembersTheLoadedDirectory() throws {
        try ModelFixtures.withTemporaryDirectory { directory throws in
            _ = try ConfigurationStore(directory: directory).load()
            // ほかのテストも読み込むので、ここで読み込んだ直後の値は確かめられない。少なくとも空ではない
            #expect(ConfigurationStore.lastLoadedDirectory != nil)
        }
    }
}
