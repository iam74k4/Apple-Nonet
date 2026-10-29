import Foundation
import Testing
@testable import NonetCore

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

    func makeStorage() -> UserDefaultsLicenseStorage {
        UserDefaultsLicenseStorage(defaults: defaults, supportDirectory: directory)
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
}
