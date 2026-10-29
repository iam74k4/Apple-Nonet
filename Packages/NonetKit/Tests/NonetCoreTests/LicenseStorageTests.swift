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

    func mirrorText() -> String? {
        try? String(contentsOf: mirrorFile, encoding: .utf8)
    }

    func writeMirror(_ text: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: mirrorFile)
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
        storage.licenseKey = "abc.def"
        let keys = sandbox.defaults.persistentDomain(forName: sandbox.suiteName)?.keys.sorted() ?? []
        #expect(keys == ["com.iam74k4.Nonet.license.key", "com.iam74k4.Nonet.license.trialStart"])
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
