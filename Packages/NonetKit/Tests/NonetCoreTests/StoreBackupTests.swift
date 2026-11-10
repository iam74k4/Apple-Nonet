// 担当: core-model。以前の設定の控え（Backups フォルダ。1時間に1回まで・削除や読み込みの前・10個まで）
import Foundation
@testable import NonetCore
import Testing

@Suite("ConfigurationStore: 以前の設定の控え")
struct StoreBackupTests {
    private static let start = Date(timeIntervalSinceReferenceDate: 815_000_000)

    /// プロファイルの id はいつも同じ（何度作っても等しい）
    private static let base = ModelFixtures.configuration().validated()

    private func configuration(_ haptics: HapticStrength = .medium, profileName: String = "base") -> NonetConfiguration {
        var configuration = Self.base
        configuration.settings = GlobalSettings(haptics: haptics)
        configuration.profiles[0].pages[0].name = profileName
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
                store.makeBackup(of: configuration(profileName: "p\(index)"), reason: .beforeDeletingPage, now: Self.start + Double(index))
            }
            let backups = store.backups()
            #expect(backups.count == ConfigurationStore.maxBackups)
            #expect(backups.first?.date == Self.start + 12)
            #expect(backups.last?.date == Self.start + 3)
            #expect(try store.loadBackup(backups[0]).profiles[0].pages[0].name == "p12")
        }
    }

    @Test("同じ秒に作った控えは、後から作ったものを新しいとして並べ、比べ、残す")
    func sameSecondBackupsAreNewestFirst() throws {
        try ModelFixtures.withTemporaryDirectory { directory throws in
            let store = ConfigurationStore(directory: directory)
            let first = store.makeBackup(of: configuration(.off), reason: .beforeDeletingProfile, now: Self.start)
            let second = store.makeBackup(of: configuration(.strong), reason: .beforeDeletingProfile, now: Self.start)
            #expect(first != nil && second != nil)
            #expect(store.backups().map(\.url) == [second?.url, first?.url].compactMap { $0 })
            // いちばん新しい控え（second）と同じ中身なら作らない
            let third = store.makeBackup(of: configuration(.strong), reason: .beforeDeletingProfile, now: Self.start)
            #expect(third?.url == second?.url)
            #expect(store.backups().count == 2)
            // 理由が違っても、同じ秒なら後から作ったものが先
            let fourth = try #require(store.makeBackup(of: configuration(.light), reason: .beforeImport, now: Self.start))
            #expect(store.backups().first?.url == fourth.url)
            #expect(fourth.url.lastPathComponent.hasSuffix("-import-3.json"))
        }
    }

    @Test("同じ秒に10個を超えても、刈り込むのは古い方")
    func pruningSameSecondKeepsTheNewest() throws {
        try ModelFixtures.withTemporaryDirectory { directory throws in
            let store = ConfigurationStore(directory: directory)
            var made: [URL] = []
            for index in 0..<(ConfigurationStore.maxBackups + 2) {
                let backup = try #require(store.makeBackup(of: configuration(profileName: "p\(index)"), reason: .beforeDeletingPage, now: Self.start))
                made.append(backup.url)
            }
            #expect(store.backups().map(\.url) == Array(made.reversed().prefix(ConfigurationStore.maxBackups)))
            #expect(try store.loadBackup(try #require(store.backups().first)) == configuration(profileName: "p\(ConfigurationStore.maxBackups + 1)"))
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

    /// 時計が進んでいた間の控えが 10 個あっても、いま書いた控えはすぐには消さない（前は日時で並べて 11 番目になり、書いたそばから消えていた）
    @Test("時計が進んでいた間の控えがあっても、いま書いた控えは残す")
    func aNewBackupSurvivesFutureDatedOnes() throws {
        try ModelFixtures.withTemporaryDirectory { directory throws in
            let store = ConfigurationStore(directory: directory)
            let future = Self.start + 365 * 86_400
            for index in 0..<ConfigurationStore.maxBackups {
                _ = store.makeBackup(of: configuration(profileName: "future \(index)"), reason: .automatic, now: future + Double(index))
            }
            let made = try #require(store.makeBackup(of: configuration(profileName: "now"), reason: .beforeRestoring, now: Self.start))
            #expect(FileManager.default.fileExists(atPath: made.url.path(percentEncoded: false)))
            #expect(store.backups().contains(made))
            #expect(store.backups().count == ConfigurationStore.maxBackups)
        }
    }

    /// 時計を進めていた間の控えが1つあっても、時計を戻した後の保存のたびに控えを残さず、本当の控えを消さない
    @Test("時計を進めていた間の控えがあっても、本当の控えの履歴を消さない")
    func aFutureBackupDoesNotWipeTheHistory() throws {
        try ModelFixtures.withTemporaryDirectory { directory throws in
            let store = ConfigurationStore(directory: directory)
            try store.save(configuration(profileName: "start"), now: Self.start)
            for hour in 1...5 {
                try store.save(configuration(profileName: "h\(hour)"), now: Self.start + Double(hour) * 3600 + 10)
            }
            #expect(store.backups().count == 5)
            // 時計を1年進めて1回変えた
            try store.save(configuration(profileName: "future"), now: Self.start + 365 * 86_400)
            // 時計を戻してから、続けて変えた（1時間たっていない）
            for edit in 1...9 {
                try store.save(configuration(profileName: "e\(edit)"), now: Self.start + 6 * 3600 + Double(edit))
            }
            let real = store.backups().filter { $0.date <= Self.start + 6 * 3600 + 9 }
            #expect(real.count == 5)
        }
    }

    @Test("数を減らすときは、日時が今より後の控えから消す")
    func pruningDropsFutureBackupsFirst() throws {
        try ModelFixtures.withTemporaryDirectory { directory throws in
            let store = ConfigurationStore(directory: directory)
            for index in 0..<(ConfigurationStore.maxBackups - 1) {
                _ = store.makeBackup(of: configuration(profileName: "real \(index)"), reason: .automatic, now: Self.start + Double(index))
            }
            let future = try #require(store.makeBackup(of: configuration(profileName: "future"), reason: .automatic, now: Self.start + 365 * 86_400))
            _ = store.makeBackup(of: configuration(profileName: "real later"), reason: .beforeImport, now: Self.start + 100)
            #expect(!store.backups().contains(future))
            #expect(store.backups().count == ConfigurationStore.maxBackups)
        }
    }

    @Test("戻す前の控えを残すときに、戻す控え（いちばん古いもの）を消さない")
    func restoringKeepsTheRestoredBackup() throws {
        try ModelFixtures.withTemporaryDirectory { directory throws in
            let store = ConfigurationStore(directory: directory)
            for index in 0..<ConfigurationStore.maxBackups {
                _ = store.makeBackup(of: configuration(profileName: "b\(index)"), reason: .automatic, now: Self.start + Double(index))
            }
            let oldest = try #require(store.backups().last)
            _ = store.makeBackup(of: configuration(profileName: "before restore"), reason: .beforeRestoring, now: Self.start + 100, alsoKeeping: oldest)
            #expect(store.backups().contains(oldest))
            #expect(store.backups().count == ConfigurationStore.maxBackups)
        }
    }

    @Test("戻すときに、この版では失う値のある控えなら、原本を設定のフォルダに残す（一覧を読むだけでは残さない）")
    func restoringALossyBackupKeepsItsOriginal() throws {
        try ModelFixtures.withTemporaryDirectory { directory throws in
            let store = ConfigurationStore(directory: directory)
            let backup = try #require(store.makeBackup(of: configuration(), reason: .automatic, now: Self.start))
            let lossy = #"{"version": 1, "settings": {"newThing": 1}, "profiles": [{"kind": {"type": "global"}, "pages": [{"cells": [{"title": "未来", "action": {"type": "hologram"}}]}]}]}"#
            try Data(lossy.utf8).write(to: backup.url)
            _ = try store.loadBackup(backup)
            #expect(try !ModelFixtures.fileNames(in: directory).contains { $0.hasPrefix("configuration.lossy") })
            _ = try store.loadBackup(backup, preservingOriginal: true)
            #expect(try ModelFixtures.fileNames(in: directory).contains { $0.hasPrefix("configuration.lossy") })
        }
    }
}
