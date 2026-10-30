import Foundation
import Testing
@testable import NonetCore

/// メモリの上のキーチェーン。読み書きの回数を数える
private final class MemoryTrialKeychain: TrialRecordKeychain {
    var data: Data?
    var reads = 0
    var writes = 0

    func readTrialRecord() -> Data? {
        reads += 1
        return data
    }

    func writeTrialRecord(_ data: Data) {
        writes += 1
        self.data = data
    }

    var record: TrialRecord? {
        data.flatMap(UserDefaultsLicenseStorage.decodeKeychainRecord)
    }
}

/// 専用の UserDefaults と一時フォルダ。テストごとに作って消す
private final class StorageSandbox {
    let suiteName = "com.iam74k4.Nonet.tests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let directory: URL

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NonetLicenseStorageTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Nonet", isDirectory: true)
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory.deletingLastPathComponent())
    }

    func makeStorage(keychain: (any TrialRecordKeychain)? = nil) -> UserDefaultsLicenseStorage {
        UserDefaultsLicenseStorage(defaults: defaults, supportDirectory: directory, keychain: keychain)
    }

    private static let mirrorFileNames = [
        UserDefaultsLicenseStorage.mirrorFileName, UserDefaultsLicenseStorage.lastSeenFileName, UserDefaultsLicenseStorage.usedFileName,
    ]

    /// フォルダの試用の記録（バックアップの代わり）
    func snapshotFolder() throws -> [String: Data] {
        var files: [String: Data] = [:]
        for name in Self.mirrorFileNames {
            files[name] = try Data(contentsOf: directory.appendingPathComponent(name))
        }
        return files
    }

    func restoreFolder(_ files: [String: Data]) throws {
        for (name, data) in files {
            try data.write(to: directory.appendingPathComponent(name))
        }
    }

    /// フォルダとファイルを書けなくする（復元で持ち主や権限が変わったとき）
    func setFolderWritable(_ writable: Bool) throws {
        let fileManager = FileManager.default
        if writable {
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        }
        for name in Self.mirrorFileNames where fileExists(name) {
            try fileManager.setAttributes([.posixPermissions: writable ? 0o644 : 0o444], ofItemAtPath: directory.appendingPathComponent(name).path)
        }
        if !writable {
            try fileManager.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        }
    }

    var mirrorFile: URL {
        directory.appendingPathComponent(UserDefaultsLicenseStorage.mirrorFileName)
    }

    var storedDefaultsDate: Date? {
        defaults.object(forKey: UserDefaultsLicenseStorage.trialStartKey) as? Date
    }

    func mirrorText(_ name: String = UserDefaultsLicenseStorage.mirrorFileName) -> String? {
        try? String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
    }

    func writeMirror(_ text: String, _ name: String = UserDefaultsLicenseStorage.mirrorFileName) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: directory.appendingPathComponent(name))
    }

    func fileExists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path)
    }
}

@Suite struct LicenseStorageTests {
    private let sandbox: StorageSandbox
    private let date = Date(timeIntervalSinceReferenceDate: 815_000_000.123_456_789)

    init() throws {
        sandbox = try StorageSandbox()
    }

    @Test func startsEmpty() {
        let storage = sandbox.makeStorage()
        #expect(storage.trialStartDate == nil)
        #expect(storage.licenseKey == nil)
        #expect(FileManager.default.fileExists(atPath: sandbox.mirrorFile.path) == false)
    }

    @Test func storesTheTrialStartInDefaultsAndFile() {
        let storage = sandbox.makeStorage()
        storage.trialStartDate = date
        #expect(sandbox.storedDefaultsDate == date)
        #expect(sandbox.mirrorText() != nil)
        // 別のインスタンス（次回の起動）でも同じ日付が読める。精度も落ちない
        #expect(sandbox.makeStorage().trialStartDate == date)
    }

    @Test func usesTheFileWhenDefaultsAreDeleted() {
        sandbox.makeStorage().trialStartDate = date
        sandbox.defaults.removeObject(forKey: UserDefaultsLicenseStorage.trialStartKey)
        #expect(sandbox.makeStorage().trialStartDate == date)
        // 消された方も戻す
        #expect(sandbox.storedDefaultsDate == date)
    }

    @Test func usesDefaultsWhenTheFileIsDeleted() throws {
        sandbox.makeStorage().trialStartDate = date
        try FileManager.default.removeItem(at: sandbox.mirrorFile)
        #expect(sandbox.makeStorage().trialStartDate == date)
        #expect(sandbox.mirrorText() != nil)
        #expect(sandbox.makeStorage().trialStartDate == date)
    }

    @Test func usesTheEarliestOfTheTwoDates() throws {
        let storage = sandbox.makeStorage()
        storage.trialStartDate = date
        // UserDefaults だけ新しい日付に書き換えても、ファイルの古い日付が勝つ
        sandbox.defaults.set(date.addingTimeInterval(30 * 86_400), forKey: UserDefaultsLicenseStorage.trialStartKey)
        #expect(storage.trialStartDate == date)
        #expect(sandbox.storedDefaultsDate == date)

        // ファイルだけ新しい日付に書き換えても同じ
        try sandbox.writeMirror(String(date.addingTimeInterval(30 * 86_400).timeIntervalSinceReferenceDate))
        #expect(storage.trialStartDate == date)
        #expect(sandbox.mirrorText() == String(date.timeIntervalSinceReferenceDate))
    }

    @Test func ignoresACorruptFile() throws {
        try sandbox.writeMirror("not a date")
        let storage = sandbox.makeStorage()
        #expect(storage.trialStartDate == nil)
        sandbox.defaults.set(date, forKey: UserDefaultsLicenseStorage.trialStartKey)
        #expect(storage.trialStartDate == date)
        #expect(sandbox.mirrorText() == String(date.timeIntervalSinceReferenceDate))
        try sandbox.writeMirror("nan")
        #expect(storage.trialStartDate == date)
    }

    @Test func settingNilRemovesBoth() {
        let storage = sandbox.makeStorage()
        storage.trialStartDate = date
        storage.trialStartDate = nil
        #expect(storage.trialStartDate == nil)
        #expect(sandbox.storedDefaultsDate == nil)
        #expect(FileManager.default.fileExists(atPath: sandbox.mirrorFile.path) == false)
        // 無いものを消しても問題ない
        storage.trialStartDate = nil
    }

    @Test func worksWithoutAMirrorDirectory() {
        let storage = UserDefaultsLicenseStorage(defaults: sandbox.defaults, supportDirectory: nil)
        storage.trialStartDate = date
        #expect(storage.trialStartDate == date)
        #expect(FileManager.default.fileExists(atPath: sandbox.directory.path) == false)
    }

    @Test func keepsWorkingWhenTheFileCannotBeWritten() throws {
        // フォルダの場所にファイルがあって書けない
        try FileManager.default.createDirectory(at: sandbox.directory.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: sandbox.directory)
        let storage = sandbox.makeStorage()
        storage.trialStartDate = date
        #expect(storage.trialStartDate == date)
    }

    @Test func storesTheLicenseKey() {
        let storage = sandbox.makeStorage()
        storage.licenseKey = "abc.def"
        #expect(storage.licenseKey == "abc.def")
        #expect(sandbox.makeStorage().licenseKey == "abc.def")
        storage.licenseKey = ""
        #expect(storage.licenseKey == nil)
        storage.licenseKey = "abc.def"
        storage.licenseKey = nil
        #expect(storage.licenseKey == nil)
        #expect(sandbox.defaults.object(forKey: UserDefaultsLicenseStorage.licenseKeyKey) == nil)
    }

    @Test func usesNamespacedDefaultsKeys() {
        let storage = sandbox.makeStorage()
        storage.trialStartDate = date
        storage.trialLastSeenDate = date
        storage.trialUsedTime = 60
        storage.licenseKey = "abc.def"
        let keys = sandbox.defaults.persistentDomain(forName: sandbox.suiteName)?.keys.sorted() ?? []
        #expect(keys == [
            "com.iam74k4.Nonet.license.key",
            "com.iam74k4.Nonet.license.trialLastSeen",
            "com.iam74k4.Nonet.license.trialStart",
            "com.iam74k4.Nonet.license.trialUsed",
        ])
    }

    // MARK: - 使った時間

    private typealias Storage = UserDefaultsLicenseStorage

    @Test func storesTheUsageRecordInDefaultsAndFiles() {
        let storage = sandbox.makeStorage()
        #expect(storage.trialLastSeenDate == nil)
        #expect(storage.trialUsedTime == nil)
        storage.trialLastSeenDate = date
        storage.trialUsedTime = 12_345.5
        #expect(sandbox.defaults.object(forKey: Storage.trialLastSeenKey) as? Date == date)
        #expect(sandbox.defaults.object(forKey: Storage.trialUsedKey) as? Double == 12_345.5)
        #expect(sandbox.mirrorText(Storage.lastSeenFileName) == String(date.timeIntervalSinceReferenceDate))
        #expect(sandbox.mirrorText(Storage.usedFileName) == "12345.5")
        let reopened = sandbox.makeStorage()
        #expect(reopened.trialLastSeenDate == date)
        #expect(reopened.trialUsedTime == 12_345.5)
    }

    @Test func usageRecordSurvivesDeletingEitherCopy() throws {
        sandbox.makeStorage().trialUsedTime = 600
        sandbox.makeStorage().trialLastSeenDate = date
        sandbox.defaults.removePersistentDomain(forName: sandbox.suiteName)
        #expect(sandbox.makeStorage().trialUsedTime == 600.0)
        #expect(sandbox.makeStorage().trialLastSeenDate == date)
        #expect(sandbox.defaults.object(forKey: Storage.trialUsedKey) as? Double == 600)

        try FileManager.default.removeItem(at: sandbox.directory)
        #expect(sandbox.makeStorage().trialUsedTime == 600.0)
        #expect(sandbox.mirrorText(Storage.usedFileName) == "600.0")
    }

    @Test func conflictingUsageRecordsUseTheStricterValue() throws {
        let storage = sandbox.makeStorage()
        storage.trialUsedTime = 5 * 86_400
        storage.trialLastSeenDate = date
        // 使った時間を減らしても、大きい方が勝つ
        sandbox.defaults.set(0.0, forKey: Storage.trialUsedKey)
        #expect(storage.trialUsedTime == 5.0 * 86_400)
        try sandbox.writeMirror("0", Storage.usedFileName)
        #expect(storage.trialUsedTime == 5.0 * 86_400)
        #expect(sandbox.mirrorText(Storage.usedFileName) == String(5.0 * 86_400))
        // 最後に数えた時刻を先に進めても、早い方が勝つ
        sandbox.defaults.set(date.addingTimeInterval(30 * 86_400), forKey: Storage.trialLastSeenKey)
        #expect(storage.trialLastSeenDate == date)
        try sandbox.writeMirror(String(date.addingTimeInterval(30 * 86_400).timeIntervalSinceReferenceDate), Storage.lastSeenFileName)
        #expect(storage.trialLastSeenDate == date)
    }

    @Test func ignoresInvalidUsageValues() throws {
        let storage = sandbox.makeStorage()
        storage.trialUsedTime = -1
        #expect(storage.trialUsedTime == nil)
        #expect(sandbox.fileExists(Storage.usedFileName) == false)
        storage.trialUsedTime = .nan
        #expect(storage.trialUsedTime == nil)
        try sandbox.writeMirror("-5", Storage.usedFileName)
        #expect(storage.trialUsedTime == nil)
        sandbox.defaults.set("text", forKey: Storage.trialUsedKey)
        #expect(storage.trialUsedTime == nil)
        try sandbox.writeMirror("inf", Storage.usedFileName)
        sandbox.defaults.set(30.0, forKey: Storage.trialUsedKey)
        #expect(storage.trialUsedTime == 30.0)
        #expect(sandbox.mirrorText(Storage.usedFileName) == "30.0")
    }

    @Test func settingNilRemovesTheUsageRecord() {
        let storage = sandbox.makeStorage()
        storage.trialLastSeenDate = date
        storage.trialUsedTime = 1
        storage.trialLastSeenDate = nil
        storage.trialUsedTime = nil
        #expect(storage.trialLastSeenDate == nil)
        #expect(storage.trialUsedTime == nil)
        #expect(sandbox.fileExists(Storage.lastSeenFileName) == false)
        #expect(sandbox.fileExists(Storage.usedFileName) == false)
    }

    @MainActor
    @Test func clockRollbackAfterRelaunchDoesNotRestartTheTrial() throws {
        let start = Date(timeIntervalSinceReferenceDate: 815_000_000)
        _ = LicenseManager(verifier: nil, storage: sandbox.makeStorage(), now: { start })
        let later = start.addingTimeInterval(13 * 86_400)
        _ = LicenseManager(verifier: nil, storage: sandbox.makeStorage(), now: { later })
        // 日付を1年戻し、UserDefaults も消してから起動し直す
        sandbox.defaults.removePersistentDomain(forName: sandbox.suiteName)
        let rolledBack = start.addingTimeInterval(-365 * 86_400)
        let manager = LicenseManager(verifier: nil, storage: sandbox.makeStorage(), now: { rolledBack })
        #expect(manager.entitlement == .trial(daysLeft: 1))
    }

    @MainActor
    @Test func deletingDefaultsDoesNotRestartTheTrial() throws {
        let start = Date(timeIntervalSinceReferenceDate: 815_000_000)
        _ = LicenseManager(verifier: nil, storage: sandbox.makeStorage(), now: { start })
        // `defaults delete` で消してから、20日後に起動し直す
        sandbox.defaults.removePersistentDomain(forName: sandbox.suiteName)
        let later = start.addingTimeInterval(20 * 86_400)
        let manager = LicenseManager(verifier: nil, storage: sandbox.makeStorage(), now: { later })
        #expect(manager.entitlement == .expired)
    }

    // MARK: - 食い違った記録

    private static let trialStart = Date(timeIntervalSinceReferenceDate: 815_000_000)

    private static func day(_ count: Double) -> Date {
        trialStart.addingTimeInterval(count * 86_400)
    }

    /// その日に起動する
    @MainActor
    private func launch(day: Double, keychain: (any TrialRecordKeychain)? = nil) -> LicenseManager {
        let now = Self.day(day)
        return LicenseManager(verifier: nil, storage: sandbox.makeStorage(keychain: keychain), now: { now })
    }

    @MainActor
    @Test func aStaleFolderFromABackupDoesNotCountTheSameDaysTwice() throws {
        _ = launch(day: 0)
        _ = launch(day: 1)
        let backup = try sandbox.snapshotFolder()
        _ = launch(day: 6)
        // 設定を戻すために、1日目の Application Support/Nonet をバックアップから戻した
        try sandbox.restoreFolder(backup)
        #expect(launch(day: 6).entitlement == .trial(daysLeft: 8))
        #expect(sandbox.makeStorage().trialUsedTime == 6.0 * 86_400)
        // 古い記録はそろえ直したので、次の起動も同じ
        #expect(launch(day: 6).entitlement == .trial(daysLeft: 8))
        #expect(sandbox.mirrorText(Storage.usedFileName) == String(6.0 * 86_400))
    }

    @MainActor
    @Test func aFolderThatCannotBeWrittenDoesNotShortenTheTrial() throws {
        _ = launch(day: 0)
        try sandbox.setFolderWritable(false)
        defer { try? sandbox.setFolderWritable(true) }
        // ファイルは0日目のまま。毎日起動し直しても、実際の日数だけ減る
        for day in 1...5 {
            #expect(launch(day: Double(day)).entitlement == .trial(daysLeft: 14 - day))
        }
        #expect(sandbox.mirrorText(Storage.usedFileName) == "0.0")
    }

    @MainActor
    @Test func turningTheClockBackWithAStaleFolderNeitherRestartsNorExtendsTheTrial() throws {
        _ = launch(day: 0)
        _ = launch(day: 1)
        let backup = try sandbox.snapshotFolder()
        _ = launch(day: 6)
        try sandbox.restoreFolder(backup)
        // 日付を30日前に戻して起動する: 戻した分は数えないが、使った6日は減らない
        #expect(launch(day: -30).entitlement == .trial(daysLeft: 8))
        #expect(sandbox.makeStorage().trialUsedTime == 6.0 * 86_400)
        #expect(launch(day: -29).entitlement == .trial(daysLeft: 7))
    }

    @Test func oneCopyMovedForwardOrReducedIsIgnored() {
        let storage = sandbox.makeStorage()
        storage.trialStartDate = Self.day(0)
        storage.trialLastSeenDate = Self.day(5)
        storage.trialUsedTime = 5 * 86_400
        // UserDefaults だけ「最後に数えたのは20日後で、使ったのは1日」に書き換える
        sandbox.defaults.set(Self.day(20), forKey: Storage.trialLastSeenKey)
        sandbox.defaults.set(86_400.0, forKey: Storage.trialUsedKey)
        // ファイルの組（5日目に5日）が、どの時刻でも厳しい
        #expect(storage.trialUsedTime == 5.0 * 86_400)
        #expect(storage.trialLastSeenDate == Self.day(5))
        #expect(sandbox.defaults.object(forKey: Storage.trialLastSeenKey) as? Date == Self.day(5))
    }

    /// (最後に数えた日, 使った日数) の組。nil はその値が無い
    nonisolated static let recordCases: [[(lastSeen: Double?, used: Double?)]] = [
        [(5, 5), (5, 5)],
        [(6, 6), (1, 1)],
        [(6, 6), (1, 0.5)],
        [(20, 1), (5, 5)],
        [(3, 10), (6, 6)],
        [(6, 6), (nil, 8)],
        [(6, 6), (9, nil)],
        [(6, 6), (1, 1), (-30, 6)],
        [(nil, 4)],
    ]

    @Test(arguments: recordCases.indices)
    func reconciledRecordCountsLikeTheStrictestCopy(index: Int) throws {
        let records = Self.recordCases[index].map { TrialRecord(start: 0, lastSeen: $0.lastSeen, used: $0.used) }
        let chosen = TrialRecord.reconciled(records)
        // 時計を戻したとき（-40）から、ずっと後まで
        for now in [-40.0, 0, 1, 3, 5.5, 6, 10, 30] {
            let strictest = try #require(records.compactMap { record -> Double? in
                guard let used = record.used else { return nil }
                return record.lastSeen.map { used + max(0, now - $0) } ?? used
            }.max())
            let used = try #require(chosen.used)
            let counted = chosen.lastSeen.map { used + max(0, now - $0) } ?? used
            #expect(abs(counted - strictest) < 1e-9, "組 \(Self.recordCases[index])・時刻 \(now)")
        }
    }

    @Test func reconciledKeepsTheExactValuesWhenTheCopiesAgree() {
        let record = TrialRecord(start: 815_000_000.123_456_789, lastSeen: 815_400_000.987_654_321, used: 12_345.678_9)
        #expect(TrialRecord.reconciled([record, record]) == record)
        #expect(TrialRecord.reconciled([record, TrialRecord()]) == record)
        #expect(TrialRecord.reconciled([]) == TrialRecord())
    }

    @Test func aMissingStartIsWorkedOutFromTheUsage() {
        // 開始日だけが消されていても、試用をやり直さない
        let chosen = TrialRecord.reconciled([TrialRecord(lastSeen: 10, used: 4), TrialRecord(lastSeen: 12, used: 5)])
        #expect(chosen.start == 6)
        #expect(TrialRecord.reconciled([TrialRecord(start: 2, lastSeen: 10, used: 4)]).start == 2)
    }

    // MARK: - キーチェーン

    @MainActor
    @Test func theKeychainCopyKeepsTheTrialWhenPreferencesAndFolderAreDeleted() throws {
        let keychain = MemoryTrialKeychain()
        _ = launch(day: 0, keychain: keychain)
        _ = launch(day: 5, keychain: keychain)
        // アンインストールツールで環境設定と Application Support/Nonet を消してから、入れ直した
        sandbox.defaults.removePersistentDomain(forName: sandbox.suiteName)
        try FileManager.default.removeItem(at: sandbox.directory)
        #expect(launch(day: 7, keychain: keychain).entitlement == .trial(daysLeft: 7))
        // 消された置き場所も戻す
        #expect(sandbox.storedDefaultsDate == Self.day(0))
        #expect(sandbox.mirrorText(Storage.usedFileName) == String(7.0 * 86_400))
        #expect(launch(day: 15, keychain: keychain).entitlement == .expired)
    }

    @MainActor
    @Test func withoutTheKeychainDeletingBothRestartsTheTrial() throws {
        // --self-check と Debug の --config-dir はキーチェーンを使わない（この挙動のまま）
        _ = launch(day: 0)
        _ = launch(day: 5)
        sandbox.defaults.removePersistentDomain(forName: sandbox.suiteName)
        try FileManager.default.removeItem(at: sandbox.directory)
        #expect(launch(day: 7).entitlement == .trial(daysLeft: 14))
    }

    /// 起動したまま時計を進めたり戻したりする（refresh で数える）
    private final class TestClock: @unchecked Sendable {
        private let lock = NSLock()
        private var date: Date

        init(_ date: Date) {
            self.date = date
        }

        var now: Date {
            get { lock.withLock { date } }
            set { lock.withLock { date = newValue } }
        }
    }

    @MainActor
    @Test func theKeychainIsReadOncePerLaunchAndWrittenWhenTheRecordMovesOn() throws {
        let keychain = MemoryTrialKeychain()
        let clock = TestClock(Self.day(0))
        let manager = LicenseManager(verifier: nil, storage: sandbox.makeStorage(keychain: keychain), now: { clock.now })
        #expect(keychain.reads == 1)
        #expect(keychain.writes == 1)
        #expect(keychain.record == TrialRecord(start: Self.day(0).timeIntervalSinceReferenceDate, lastSeen: Self.day(0).timeIntervalSinceReferenceDate, used: 0))
        // 使った時間が1時間に満たない間は書かない
        clock.now = Self.day(0).addingTimeInterval(30 * 60)
        manager.refresh()
        manager.refresh()
        #expect(keychain.reads == 1)
        #expect(keychain.writes == 1)
        // 1時間たったら書く
        clock.now = Self.day(0).addingTimeInterval(60 * 60)
        manager.refresh()
        #expect(keychain.writes == 2)
        #expect(keychain.record?.used == 60.0 * 60)
        // 時計を戻したときは、使った時間が増えなくても書く（最後に数えた時刻をそろえる）
        clock.now = Self.day(-2)
        manager.refresh()
        #expect(keychain.writes == 3)
        #expect(keychain.record?.used == 60.0 * 60)
        #expect(keychain.record?.lastSeen == Self.day(-2).timeIntervalSinceReferenceDate)

        // 次の起動でも一度だけ読み、起動したときの記録を書く
        let next = launch(day: 2, keychain: keychain)
        next.refresh()
        #expect(keychain.reads == 2)
        #expect(keychain.writes == 4)
        #expect(keychain.record?.lastSeen == Self.day(2).timeIntervalSinceReferenceDate)
    }

    @MainActor
    @Test func theKeychainKeepsUpWhileTheAppKeepsRunning() throws {
        // 0日目に起動し、そのまま13日使った（メニューバーのアプリは何日も起動したまま）
        let keychain = MemoryTrialKeychain()
        let clock = TestClock(Self.day(0))
        let manager = LicenseManager(verifier: nil, storage: sandbox.makeStorage(keychain: keychain), now: { clock.now })
        clock.now = Self.day(13)
        manager.refresh()
        #expect(manager.entitlement == .trial(daysLeft: 1))
        #expect(keychain.record?.used == 13.0 * 86_400)
        // 環境設定とフォルダを消し、時計を0日目に戻して起動し直しても、使った13日は減らない
        sandbox.defaults.removePersistentDomain(forName: sandbox.suiteName)
        try FileManager.default.removeItem(at: sandbox.directory)
        #expect(launch(day: 0, keychain: keychain).entitlement == .trial(daysLeft: 1))
    }

    @MainActor
    @Test func aForgedRecordInPreferencesDoesNotHideTheKeychain() throws {
        let keychain = MemoryTrialKeychain()
        _ = launch(day: 0, keychain: keychain)
        #expect(launch(day: 20, keychain: keychain).entitlement == .expired)
        // 環境設定とフォルダを消し、環境設定に「最後に数えたのは20日目で、使った時間は 0」と書き込んだ
        sandbox.defaults.removePersistentDomain(forName: sandbox.suiteName)
        try FileManager.default.removeItem(at: sandbox.directory)
        sandbox.defaults.set(Self.day(20), forKey: Storage.trialLastSeenKey)
        sandbox.defaults.set(0.0, forKey: Storage.trialUsedKey)
        #expect(launch(day: 20, keychain: keychain).entitlement == .expired)
        #expect(sandbox.makeStorage().trialUsedTime == 20.0 * 86_400)
    }

    @MainActor
    @Test func aStaleKeychainCopyOnlyAddsItsUsedTimeWhileTheOtherCopiesExist() {
        // 時計が30日遅れていたときに書いた記録。組で数えると30日余計に数える
        let keychain = MemoryTrialKeychain()
        keychain.data = Data(#"{"lastSeen":\#(Self.day(-30).timeIntervalSinceReferenceDate),"start":\#(Self.day(-30).timeIntervalSinceReferenceDate),"used":0}"#.utf8)
        sandbox.makeStorage().trialStartDate = Self.day(0)
        sandbox.makeStorage().trialLastSeenDate = Self.day(0)
        sandbox.makeStorage().trialUsedTime = 0
        #expect(launch(day: 2, keychain: keychain).entitlement == .trial(daysLeft: 12))
        #expect(keychain.reads == 1)
        // 開始日と時刻は取り込まず、キーチェーンの方を書き直す
        #expect(sandbox.makeStorage().trialStartDate == Self.day(0))
        #expect(keychain.record?.start == Self.day(0).timeIntervalSinceReferenceDate)
        #expect(keychain.record?.lastSeen == Self.day(2).timeIntervalSinceReferenceDate)
    }

    @Test func keychainWritesFollowTheRecord() {
        let base = TrialRecord(start: 0, lastSeen: 1_000, used: 500)
        #expect(Storage.needsKeychainWrite(base, after: nil))
        #expect(Storage.needsKeychainWrite(base, after: base) == false)
        // 使った時間と時刻が同じだけ進んだ（ふつうの経過）
        #expect(Storage.needsKeychainWrite(TrialRecord(start: 0, lastSeen: 1_100, used: 600), after: base) == false)
        #expect(Storage.needsKeychainWrite(TrialRecord(start: 0, lastSeen: 1_000 + 3_600, used: 500 + 3_600), after: base))
        // 開始日が変わった・時計がずれた
        #expect(Storage.needsKeychainWrite(TrialRecord(start: -10, lastSeen: 1_000, used: 500), after: base))
        #expect(Storage.needsKeychainWrite(TrialRecord(start: 0, lastSeen: 1_000 + 600, used: 500), after: base))
        #expect(Storage.needsKeychainWrite(TrialRecord(start: 0, lastSeen: 1_000 + 60, used: 500), after: base) == false)
    }

    @MainActor
    @Test(arguments: ["garbage", "{}", #"{"used":-5,"lastSeen":"x"}"#, #"{"used":1e999}"#])
    func unreadableKeychainDataIsIgnored(text: String) {
        let keychain = MemoryTrialKeychain()
        keychain.data = Data(text.utf8)
        #expect(launch(day: 0, keychain: keychain).entitlement == .trial(daysLeft: 14))
        // 読めるものに書き直す
        #expect(keychain.record?.used == 0)
    }

    @Test func keychainValuesAreCheckedLikeTheOtherCopies() {
        let record = UserDefaultsLicenseStorage.decodeKeychainRecord(Data(#"{"start":100,"lastSeen":200,"used":-1}"#.utf8))
        #expect(record == TrialRecord(start: 100, lastSeen: 200, used: nil))
    }

    @Test func theSystemKeychainIsOnlyUsedByTheDistributedApp() {
        // テストは Developer ID で署名した Nonet ではないので、本物のキーチェーンに触れない
        #expect(SystemTrialRecordKeychain.isDistributedApp() == false)
        let keychain = SystemTrialRecordKeychain()
        #expect(keychain.isEnabled == false)
        #expect(keychain.readTrialRecord() == nil)
        keychain.writeTrialRecord(Data("{}".utf8))
        #expect(keychain.readTrialRecord() == nil)
    }
}
