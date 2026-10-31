// 担当: keys-license
// 試用の記録をすべて消しても、2つ目のキーチェーンの項目（marker）と以前に使った跡で、試用をやり直させない。
// キーチェーンも跡もメモリの偽物（本物のキーチェーン・~/Library には触れない）
import Foundation
import Testing
@testable import NonetCore

/// メモリの上のキーチェーンの項目
private final class FakeKeychainItem: TrialRecordKeychain {
    var data: Data?
    var writes = 0

    init(_ data: Data? = nil) {
        self.data = data
    }

    func readTrialRecord() -> Data? { data }

    func writeTrialRecord(_ data: Data) {
        writes += 1
        self.data = data
    }

    var record: TrialRecord? {
        data.flatMap(UserDefaultsLicenseStorage.decodeKeychainRecord)
    }
}

/// 以前に使った跡（フォルダの作成日）の偽物
private final class FakeEvidence: TrialUsageEvidence {
    var date: Date?
    var reads = 0

    init(_ date: Date?) {
        self.date = date
    }

    func earliestUse() -> Date? {
        reads += 1
        return date
    }
}

/// 専用の UserDefaults と一時フォルダ（試用の記録の写し）。テストごとに作って消す
private final class EvidenceSandbox {
    let suiteName = "com.iam74k4.Nonet.tests.evidence.\(UUID().uuidString)"
    let defaults: UserDefaults
    let root: URL
    var directory: URL { root.appendingPathComponent("Nonet", isDirectory: true) }

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
        root = FileManager.default.temporaryDirectory.appendingPathComponent("NonetTrialEvidenceTests-\(UUID().uuidString)", isDirectory: true)
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: root)
    }

    /// 環境設定と Application Support/Nonet の記録を消す（`defaults delete` と `rm .install*`）
    func eraseDefaultsAndFolder() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
@Suite struct LicenseTrialEvidenceTests {
    private static let trialStart = Date(timeIntervalSinceReferenceDate: 815_000_000)
    private let sandbox: EvidenceSandbox

    init() throws {
        sandbox = try EvidenceSandbox()
    }

    private static func day(_ count: Double) -> Date {
        trialStart.addingTimeInterval(count * 86_400)
    }

    private func storage(
        keychain: FakeKeychainItem? = nil, marker: FakeKeychainItem? = nil, evidence: FakeEvidence? = nil, now: Date
    ) -> UserDefaultsLicenseStorage {
        UserDefaultsLicenseStorage(
            defaults: sandbox.defaults, supportDirectory: sandbox.directory, keychain: keychain, marker: marker, evidence: evidence, now: { now }
        )
    }

    private func launch(day: Double, keychain: FakeKeychainItem? = nil, marker: FakeKeychainItem? = nil, evidence: FakeEvidence? = nil) -> LicenseManager {
        let now = Self.day(day)
        return LicenseManager(
            verifier: nil, storage: storage(keychain: keychain, marker: marker, evidence: evidence, now: now), now: { now }, revocations: .empty
        )
    }

    // MARK: - 2つ目のキーチェーンの項目

    /// 使った時間を2つ目の項目にも書き、ほかをすべて消されたら、そこから続ける
    @Test func theMarkerKeepsTheTrialAfterEverythingElseIsErased() throws {
        let keychain = FakeKeychainItem()
        let marker = FakeKeychainItem()
        _ = launch(day: 0, keychain: keychain, marker: marker)
        #expect(launch(day: 10, keychain: keychain, marker: marker).entitlement == .trial(daysLeft: 4))
        #expect(marker.record == keychain.record)
        #expect(marker.record?.used == 10.0 * 86_400)

        // `defaults delete`・`rm .install*`・キーチェーンアクセスで com.iam74k4.Nonet.license.trial を消す
        sandbox.eraseDefaultsAndFolder()
        keychain.data = nil
        #expect(launch(day: 12, keychain: keychain, marker: marker).entitlement == .trial(daysLeft: 2))
        // 消された置き場所にも書き直す
        #expect(keychain.record?.start == Self.trialStart.timeIntervalSinceReferenceDate)
        #expect(storage(now: Self.day(12)).trialStartDate == Self.trialStart)
        sandbox.eraseDefaultsAndFolder()
        keychain.data = nil
        #expect(launch(day: 15, keychain: keychain, marker: marker).entitlement == .expired)
    }

    /// 2つの項目が食い違えば、試用が短くなる方で数える
    @Test func theStricterOfTheTwoKeychainItemsWins() throws {
        let keychain = FakeKeychainItem()
        let marker = FakeKeychainItem()
        _ = launch(day: 0, keychain: keychain, marker: marker)
        _ = launch(day: 9, keychain: keychain, marker: marker)
        sandbox.eraseDefaultsAndFolder()
        // 1つ目の項目だけを初めの日の記録に書き換えた
        keychain.data = Data(#"{"lastSeen":\#(Self.day(0).timeIntervalSinceReferenceDate),"start":\#(Self.day(0).timeIntervalSinceReferenceDate),"used":0}"#.utf8)
        #expect(launch(day: 9, keychain: keychain, marker: marker).entitlement == .trial(daysLeft: 5))
    }

    /// 項目はあるのに読めない（書き換えられた）なら、使ったことは確かなので期限切れにする
    @Test func anUnreadableMarkerCountsAsExpired() throws {
        let marker = FakeKeychainItem(Data("not a record".utf8))
        let manager = launch(day: 0, marker: marker, evidence: FakeEvidence(nil))
        #expect(manager.entitlement == .expired)
        #expect(!manager.canExecuteActions)
        // 期限切れの記録を書くので、項目を消しても戻らない
        marker.data = nil
        #expect(launch(day: 1, marker: marker).entitlement == .expired)
    }

    /// 名前は Mac とアプリで決まり、Nonet のものとは読めない。テストでは本物のキーチェーンを使わない
    @Test func theMarkerNameIsAStableHash() {
        let name = SystemTrialRecordKeychain.markerName(platformUUID: "01234567-89AB-CDEF-0123-456789ABCDEF", bundleID: "com.iam74k4.Nonet")
        #expect(name == SystemTrialRecordKeychain.markerName(platformUUID: "01234567-89ab-cdef-0123-456789abcdef", bundleID: "com.iam74k4.Nonet"))
        #expect(name != SystemTrialRecordKeychain.markerName(platformUUID: "11234567-89AB-CDEF-0123-456789ABCDEF", bundleID: "com.iam74k4.Nonet"))
        #expect(name.count == 64)
        #expect(name.allSatisfy { $0.isHexDigit })
        #expect(!name.lowercased().contains("nonet"))
        #expect(name != SystemTrialRecordKeychain.service)
        // swift test は Developer ID で署名した Nonet ではないので、項目を読み書きしない
        let marker = SystemTrialRecordKeychain.machineMarker()
        #expect(!marker.isEnabled)
        #expect(marker.readTrialRecord() == nil)
        #expect(marker.itemService != SystemTrialRecordKeychain.service)
    }

    // MARK: - 以前に使った跡

    /// 記録がどこにも無くても、20日前に作られた Backups があれば、試用はその日に始まったので期限切れ
    @Test func evidenceOfEarlierUseExpiresAFullyResetTrial() {
        let evidence = FakeEvidence(Self.day(-20))
        let manager = launch(day: 0, evidence: evidence)
        #expect(manager.entitlement == .expired)
        #expect(storage(now: Self.day(0)).trialStartDate == Self.day(-20))
    }

    /// 跡が新しければ、その日から数える（実際より長くは数えない）
    @Test func recentEvidenceResumesFromItsDate() {
        #expect(launch(day: 0, evidence: FakeEvidence(Self.day(-3))).entitlement == .trial(daysLeft: 11))
        // 跡の日が書き残されるので、跡を消しても戻らない
        #expect(launch(day: 1).entitlement == .trial(daysLeft: 10))
    }

    /// 初めての人: 跡が無ければ、いつもどおり14日
    @Test func noEvidenceStartsAFreshTrial() {
        let evidence = FakeEvidence(nil)
        #expect(launch(day: 0, evidence: evidence).entitlement == .trial(daysLeft: 14))
        #expect(evidence.reads > 0)
    }

    /// 初めての起動の途中でフォルダが先にできても（作成日はほぼ今）、試用は減らない
    @Test func evidenceCreatedDuringTheFirstLaunchDoesNotShortenTheTrial() {
        #expect(launch(day: 0, evidence: FakeEvidence(Self.day(-0.001))).entitlement == .trial(daysLeft: 14))
    }

    /// 記録があるときは跡を見ない（キャッシュが試用より古くても期限切れにしない）
    @Test func evidenceIsIgnoredWhileRecordsExist() {
        _ = launch(day: 0)
        let evidence = FakeEvidence(Self.day(-100))
        #expect(launch(day: 2, evidence: evidence).entitlement == .trial(daysLeft: 12))
        #expect(evidence.reads == 0)
    }

    /// 作成日がおかしい（Nonet より前・時計より後）ときは、試用を縮めない
    @Test func implausibleEvidenceDatesAreNotHeldAgainstTheUser() {
        let ancient = Date(timeIntervalSince1970: 0)
        #expect(UserDefaultsLicenseStorage.earlierUseStart(markerIsUnreadable: false, evidence: ancient, now: Self.day(0)) == nil)
        #expect(launch(day: 0, evidence: FakeEvidence(ancient)).entitlement == .trial(daysLeft: 14))
        sandbox.eraseDefaultsAndFolder()
        #expect(launch(day: 0, evidence: FakeEvidence(Self.day(30))).entitlement == .trial(daysLeft: 14))
        #expect(storage(now: Self.day(0)).trialStartDate == Self.day(0))
    }

    /// 本物の跡: 中身を書き換えても変わらないフォルダの作成日のうち、いちばん古いもの。無いフォルダは数えない
    @Test func fileEvidenceReadsFolderCreationDates() throws {
        let backups = sandbox.root.appendingPathComponent("Backups", isDirectory: true)
        let caches = sandbox.root.appendingPathComponent("Caches", isDirectory: true)
        let missing = sandbox.root.appendingPathComponent("Missing", isDirectory: true)
        #expect(FileTrialUsageEvidence(locations: [missing]).earliestUse() == nil)
        let old = Self.day(-30)
        for (url, date) in [(backups, Self.day(-5)), (caches, old)] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.creationDate: date], ofItemAtPath: url.path)
        }
        try Data("x".utf8).write(to: caches.appendingPathComponent("file"))
        let found = try #require(FileTrialUsageEvidence(locations: [backups, caches, missing]).earliestUse())
        #expect(abs(found.timeIntervalSince(old)) < 1)
        // 本物の置き場所は Application Support/Nonet/Backups と Caches/<bundle id>
        let standard = FileTrialUsageEvidence.standard(bundleID: "com.iam74k4.Nonet").locations.map(\.path)
        #expect(standard.contains { $0.hasSuffix("/Application Support/Nonet/Backups") })
        #expect(standard.contains { $0.hasSuffix("/Caches/com.iam74k4.Nonet") })
    }

    /// 跡を渡さない保存先（--self-check の LicenseSnapshot・Debug の --config-dir）は、今までどおり何も見ない
    @Test func storageWithoutEvidenceStartsFresh() {
        let plain = UserDefaultsLicenseStorage(defaults: sandbox.defaults, supportDirectory: nil)
        #expect(plain.trialStartDate == nil)
        #expect(sandbox.defaults.dictionaryRepresentation().keys.allSatisfy { !$0.hasPrefix("com.iam74k4.Nonet.license") })
    }
}
