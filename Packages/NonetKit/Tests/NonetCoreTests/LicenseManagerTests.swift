import Foundation
import Observation
import Testing
@testable import NonetCore

private final class MemoryLicenseStorage: LicenseStorage {
    var trialStartDate: Date? {
        didSet { trialWrites += 1 }
    }
    var licenseKey: String?
    var trialLastSeenDate: Date? {
        didSet { trialWrites += 1 }
    }
    var trialUsedTime: TimeInterval? {
        didSet { trialWrites += 1 }
    }
    /// 試用の記録（開始日・最後に数えた時刻・使った時間）を書いた回数
    private(set) var trialWrites = 0
    /// didSaveTrialProgress が呼ばれた回数
    private(set) var savedProgressCount = 0

    init(trialStartDate: Date? = nil, licenseKey: String? = nil) {
        self.trialStartDate = trialStartDate
        self.licenseKey = licenseKey
    }

    func didSaveTrialProgress() {
        savedProgressCount += 1
    }
}

/// 開始日とキーしか持たない保存先（使った時間は既定の実装で、保存しない）
private final class StartOnlyLicenseStorage: LicenseStorage {
    var trialStartDate: Date?
    var licenseKey: String?
}

/// 進めたり戻したりできる時計と、スリープ中も進む単調な時計
private final class ManualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    private var monotonic: TimeInterval = 1_000

    init(_ start: Date) {
        current = start
    }

    var now: Date {
        lock.withLock { current }
    }

    var uptime: TimeInterval {
        lock.withLock { monotonic }
    }

    /// 時計を変える（実際の時間は経たない）
    func set(_ date: Date) {
        lock.withLock { current = date }
    }

    /// 実際に時間が経つ
    func advance(days: Double) {
        advance(seconds: days * 86_400)
    }

    func advance(seconds: TimeInterval) {
        lock.withLock {
            current = current.addingTimeInterval(seconds)
            monotonic += seconds
        }
    }

    var closure: @Sendable () -> Date {
        { [self] in now }
    }

    var uptimeClosure: @Sendable () -> TimeInterval {
        { [self] in uptime }
    }
}

@MainActor
@Suite struct LicenseManagerTests {
    private let start = Date(timeIntervalSinceReferenceDate: 815_000_000)
    private let clock: ManualClock
    private let storage = MemoryLicenseStorage()

    init() {
        clock = ManualClock(start)
    }

    private func makeManager(verifier: LicenseVerifier? = nil, monotonic: Bool = false, storage: (any LicenseStorage)? = nil) -> LicenseManager {
        LicenseManager(verifier: verifier, storage: storage ?? self.storage, now: clock.closure, uptime: monotonic ? clock.uptimeClosure : nil)
    }

    private func verifier() throws -> LicenseVerifier {
        try LicenseTestFixtures.verifier()
    }

    private func days(_ count: Double) -> Date {
        start.addingTimeInterval(count * 86_400)
    }

    // MARK: - 試用

    @Test func firstLaunchStartsTheTrial() throws {
        let manager = makeManager()
        #expect(storage.trialStartDate == start)
        #expect(storage.trialLastSeenDate == start)
        #expect(storage.trialUsedTime == 0.0)
        #expect(manager.entitlement == .trial(daysLeft: 14))
        #expect(manager.canExecuteActions)
    }

    @Test func keepsAnExistingTrialStart() throws {
        // 使った時間の記録が無ければ、開始日から数える
        storage.trialStartDate = days(-3)
        let manager = makeManager()
        #expect(storage.trialStartDate == days(-3))
        #expect(storage.trialUsedTime == 3.0 * 86_400)
        #expect(storage.trialLastSeenDate == start)
        #expect(manager.entitlement == .trial(daysLeft: 11))
    }

    @Test func resumesFromTheStoredUsage() throws {
        storage.trialStartDate = days(-30)
        storage.trialLastSeenDate = days(-1)
        storage.trialUsedTime = 5 * 86_400
        let manager = makeManager()
        #expect(manager.entitlement == .trial(daysLeft: 8))
        #expect(storage.trialUsedTime == 6.0 * 86_400)
        #expect(storage.trialStartDate == days(-30))
    }

    nonisolated static let dayCases: [(Double, Entitlement)] = [
        (0.0, .trial(daysLeft: 14)),
        (0.000_01, .trial(daysLeft: 14)),
        (0.5, .trial(daysLeft: 14)),
        (1.0, .trial(daysLeft: 13)),
        (12.0001, .trial(daysLeft: 2)),
        (13.0, .trial(daysLeft: 1)),
        (13.5, .trial(daysLeft: 1)),
        (14.0 - 1.0 / 86_400, .trial(daysLeft: 1)),
        (14.0, .expired),
        (14.000_01, .expired),
        (20.0, .expired),
        (400.0, .expired),
    ]

    @Test(arguments: dayCases)
    func daysLeftRoundsUpUntilExactlyFourteenDays(day: Double, expected: Entitlement) throws {
        for monotonic in [false, true] {
            let storage = MemoryLicenseStorage()
            let clock = ManualClock(start)
            let manager = LicenseManager(verifier: nil, storage: storage, now: clock.closure, uptime: monotonic ? clock.uptimeClosure : nil)
            clock.advance(days: day)
            manager.refresh()
            #expect(manager.entitlement == expected)
            #expect(manager.canExecuteActions == (expected != .expired))
        }
    }

    @Test func daysLeftAcrossRelaunches() throws {
        _ = makeManager()
        clock.advance(days: 13.5)
        #expect(makeManager().entitlement == .trial(daysLeft: 1))
        clock.advance(days: 0.5)
        #expect(makeManager().entitlement == .expired)
    }

    @Test func trialEndsAfterExactlyFourteenTimesTwentyFourHours() {
        let duration: TimeInterval = 14 * 24 * 60 * 60
        #expect(TrialProgress(start: start, lastSeen: start, used: 0).entitlement == .trial(daysLeft: 14))
        #expect(TrialProgress(start: start, lastSeen: start, used: duration - 0.001).entitlement == .trial(daysLeft: 1))
        #expect(TrialProgress(start: start, lastSeen: start, used: duration).entitlement == .expired)
        #expect(TrialProgress(start: start, lastSeen: start, used: duration - 0.001).isActive)
        #expect(TrialProgress(start: start, lastSeen: start, used: duration).isActive == false)
    }

    // MARK: - 時計の変更

    @Test func clockMovedBeforeTheTrialStartKeepsTheDaysLeft() throws {
        storage.trialStartDate = days(-10)
        storage.trialLastSeenDate = start
        storage.trialUsedTime = 10 * 86_400
        clock.set(days(-40))
        let manager = makeManager()
        // 戻した分は数えないが、試用もやり直さない
        #expect(manager.entitlement == .trial(daysLeft: 4))
        #expect(storage.trialStartDate == days(-10))
        #expect(storage.trialUsedTime == 10.0 * 86_400)
        clock.advance(days: 4)
        manager.refresh()
        #expect(manager.entitlement == .expired)
    }

    @Test func clockBeforeTheTrialStartWithoutAUsageRecordIsExpired() throws {
        // 開始日しか無く、時計がそれより前: どれだけ使ったか分からない
        let storage = StartOnlyLicenseStorage()
        storage.trialStartDate = days(5)
        let manager = makeManager(storage: storage)
        #expect(manager.entitlement == .expired)
        #expect(manager.canExecuteActions == false)
        // 開始日を書き換えない
        #expect(storage.trialStartDate == days(5))

        // 時計が開始日に追いつけば、開始日から数える
        clock.advance(days: 5)
        manager.refresh()
        #expect(manager.entitlement == .trial(daysLeft: 14))
        clock.advance(days: 14)
        manager.refresh()
        #expect(manager.entitlement == .expired)
    }

    @Test func toleratesSmallCorrectionsAroundTheTrialStart() throws {
        let storage = StartOnlyLicenseStorage()
        storage.trialStartDate = start.addingTimeInterval(120)
        #expect(makeManager(storage: storage).entitlement == .trial(daysLeft: 14))
        storage.trialStartDate = start.addingTimeInterval(TrialProgress.clockTolerance + 1)
        #expect(makeManager(storage: storage).entitlement == .expired)
    }

    @Test(arguments: [false, true])
    func clockMovedBackWhileRunningNeverGivesMoreThanFourteenDays(monotonic: Bool) throws {
        let manager = makeManager(monotonic: monotonic)
        clock.advance(days: 10)
        manager.refresh()
        #expect(manager.entitlement == .trial(daysLeft: 4))
        clock.set(days(-365))
        manager.refresh()
        #expect(manager.entitlement == .trial(daysLeft: 4))
        #expect(storage.trialStartDate == start)
        clock.advance(days: 2)
        manager.refresh()
        #expect(manager.entitlement == .trial(daysLeft: 2))
        clock.advance(days: 2)
        manager.refresh()
        #expect(manager.entitlement == .expired)
        #expect(manager.canExecuteActions == false)
    }

    @Test(arguments: [false, true])
    func repeatedRollbacksDoNotExtendTheTrial(monotonic: Bool) throws {
        // 13日使うたびに日付を30日戻す
        let manager = makeManager(monotonic: monotonic)
        clock.advance(days: 13)
        manager.refresh()
        #expect(manager.entitlement == .trial(daysLeft: 1))
        var used = 13.0
        for _ in 0..<5 {
            clock.set(clock.now.addingTimeInterval(-30 * 86_400))
            manager.refresh()
            clock.advance(days: 13)
            manager.refresh()
            used += 13
            #expect(manager.entitlement == .expired)
            #expect(manager.canExecuteActions == false)
            #expect(storage.trialUsedTime == used * 86_400)
        }
        // 起動し直しても同じ
        #expect(makeManager(monotonic: monotonic).entitlement == .expired)
    }

    @Test func rollbackAcrossRelaunchesDoesNotExtendTheTrial() throws {
        _ = makeManager()
        clock.advance(days: 13)
        _ = makeManager()
        clock.set(days(-30))
        let manager = makeManager()
        #expect(manager.entitlement == .trial(daysLeft: 1))
        clock.advance(days: 1)
        manager.refresh()
        #expect(manager.entitlement == .expired)
    }

    @Test func monotonicClockCountsRealTimeWhenTheClockIsChangedBetweenRefreshes() throws {
        let manager = makeManager(monotonic: true)
        clock.advance(days: 13)
        manager.refresh()
        // refresh の前に13日経ち、その間に日付を30日戻された
        clock.advance(days: 13)
        clock.set(clock.now.addingTimeInterval(-30 * 86_400))
        #expect(manager.canExecuteActions == false)
        manager.refresh()
        #expect(manager.entitlement == .expired)
    }

    @Test func monotonicClockIgnoresAClockSetAheadAndBack() throws {
        // 時計が一時的にずれていた（電池切れや手で変えた）ときに、試用を失わない
        let manager = makeManager(monotonic: true)
        clock.advance(days: 1)
        manager.refresh()
        clock.set(days(400))
        manager.refresh()
        #expect(manager.entitlement == .trial(daysLeft: 13))
        #expect(manager.canExecuteActions)
        clock.set(days(1))
        manager.refresh()
        #expect(manager.entitlement == .trial(daysLeft: 13))
        // 過去に戻してから正しい時刻に戻しても同じ
        clock.set(days(-400))
        manager.refresh()
        clock.set(days(1))
        manager.refresh()
        #expect(manager.entitlement == .trial(daysLeft: 13))
        clock.advance(days: 13)
        manager.refresh()
        #expect(manager.entitlement == .expired)
    }

    @Test func withoutAMonotonicClockAJumpForwardCounts() throws {
        // 単調な時計が無ければ、時計の進みと実際の時間を区別できない
        let manager = makeManager()
        clock.set(days(20))
        manager.refresh()
        #expect(manager.entitlement == .expired)
    }

    @Test func smallClockCorrectionsAreHarmless() throws {
        let manager = makeManager(monotonic: true)
        clock.advance(days: 1)
        manager.refresh()
        clock.set(clock.now.addingTimeInterval(-90))
        manager.refresh()
        clock.set(clock.now.addingTimeInterval(120))
        manager.refresh()
        #expect(manager.entitlement == .trial(daysLeft: 13))
        // 小さなずれだけでは記録を書き直さない
        #expect(storage.trialUsedTime == 86_400.0)
        // 次に書くときには、進めた120秒も数えてある
        clock.advance(days: 1)
        manager.refresh()
        let used = try #require(storage.trialUsedTime)
        #expect(abs(used - (2 * 86_400 + 120)) < 0.001)
    }

    @Test func canExecuteActionsChecksTheClockEvenWithoutRefresh() throws {
        let manager = makeManager()
        clock.advance(days: 13.5)
        manager.refresh()
        #expect(manager.entitlement == .trial(daysLeft: 1))
        clock.advance(days: 1)
        #expect(manager.canExecuteActions == false)
        manager.refresh()
        #expect(manager.entitlement == .expired)
    }

    @Test func canExecuteActionsUsesTheMonotonicClockWithoutRefresh() throws {
        let manager = makeManager(monotonic: true)
        clock.advance(days: 13.5)
        manager.refresh()
        // 日付を戻しても、実際に経った時間で期限を過ぎる
        clock.set(days(-100))
        #expect(manager.canExecuteActions)
        clock.advance(days: 0.6)
        #expect(manager.canExecuteActions == false)
        // canExecuteActions は保存しない
        #expect(storage.trialUsedTime == 13.5 * 86_400)
    }

    // MARK: - 保存先

    @Test func keepsCountingWhenStorageLosesTheRecord() throws {
        let manager = makeManager()
        clock.advance(days: 2)
        storage.trialStartDate = nil
        storage.trialLastSeenDate = nil
        storage.trialUsedTime = nil
        manager.refresh()
        // このプロセスで数えた分から続け、保存先も戻す
        #expect(manager.entitlement == .trial(daysLeft: 12))
        #expect(storage.trialStartDate == start)
        #expect(storage.trialUsedTime == 2.0 * 86_400)
    }

    @Test func storageTamperedWhileRunningDoesNotExtendTheTrial() throws {
        let manager = makeManager()
        clock.advance(days: 5)
        manager.refresh()
        storage.trialStartDate = days(5)
        storage.trialUsedTime = 0
        manager.refresh()
        #expect(manager.entitlement == .trial(daysLeft: 9))
        #expect(storage.trialStartDate == start)
        #expect(storage.trialUsedTime == 5.0 * 86_400)
    }

    @Test func largerStoredUsageWins() throws {
        let manager = makeManager()
        clock.advance(days: 1)
        storage.trialUsedTime = 10 * 86_400
        manager.refresh()
        #expect(manager.entitlement == .trial(daysLeft: 3))
    }

    @Test(arguments: [-86_400.0, .nan, .infinity])
    func invalidStoredUsageFallsBackToTheStartDate(used: Double) throws {
        storage.trialStartDate = days(-3)
        storage.trialLastSeenDate = days(-1)
        storage.trialUsedTime = used
        let manager = makeManager()
        #expect(manager.entitlement == .trial(daysLeft: 11))
        #expect(storage.trialUsedTime == 3.0 * 86_400)
    }

    @Test func storageWithoutUsageStillCountsWithinAProcess() throws {
        // 使った時間を保存しない保存先でも、起動中は時計を戻して延ばせない
        let storage = StartOnlyLicenseStorage()
        let manager = makeManager(storage: storage)
        clock.advance(days: 10)
        manager.refresh()
        clock.set(start)
        manager.refresh()
        #expect(manager.entitlement == .trial(daysLeft: 4))
        #expect(storage.trialLastSeenDate == nil)
        #expect(storage.trialUsedTime == nil)
    }

    @Test func restartsTheTrialOnlyWhenEverythingIsGone() throws {
        _ = makeManager()
        clock.advance(days: 20)
        storage.trialStartDate = nil
        storage.trialLastSeenDate = nil
        storage.trialUsedTime = nil
        #expect(makeManager().entitlement == .trial(daysLeft: 14))
        #expect(storage.trialStartDate == days(20))
    }

    // MARK: - 同時に動く別のコピー

    @Test(arguments: [false, true])
    func twoCopiesRunningAtTheSameTimeCountEachMomentOnce(monotonic: Bool) throws {
        // 同じ記録を使う2つのコピー（別の場所に置いたアプリを両方起動した）が、交互に数える
        let first = makeManager(monotonic: monotonic)
        let second = makeManager(monotonic: monotonic)
        for day in 1...13 {
            clock.advance(days: 0.25)
            first.refresh()
            clock.advance(days: 0.5)
            second.refresh()
            clock.advance(days: 0.25)
            first.refresh()
            second.refresh()
            #expect(first.entitlement == .trial(daysLeft: 14 - day), "\(day)日目")
            #expect(second.entitlement == .trial(daysLeft: 14 - day), "\(day)日目")
            #expect(storage.trialUsedTime == Double(day) * 86_400, "\(day)日目")
        }
        clock.advance(days: 1)
        second.refresh()
        first.refresh()
        #expect(first.entitlement == .expired)
        #expect(second.entitlement == .expired)
    }

    @Test(arguments: [false, true])
    func aCopyThatCountedFurtherIsNeitherCountedTwiceNorLostWhenTheClockIsTurnedBack(monotonic: Bool) throws {
        let first = makeManager(monotonic: monotonic)
        let second = makeManager(monotonic: monotonic)
        clock.advance(days: 5)
        first.refresh()
        #expect(first.entitlement == .trial(daysLeft: 9))
        // もう一方が数える前に、日付を2日戻した（保存された記録の lastSeen は now より先）
        clock.set(days(3))
        second.refresh()
        #expect(second.entitlement == .trial(daysLeft: 9))
        #expect(storage.trialUsedTime == 5.0 * 86_400)
        #expect(storage.trialStartDate == start)
        // 戻した後の1日は、どちらも1回だけ数える
        clock.advance(days: 1)
        second.refresh()
        first.refresh()
        #expect(second.entitlement == .trial(daysLeft: 8))
        #expect(first.entitlement == .trial(daysLeft: 8))
        #expect(storage.trialUsedTime == 6.0 * 86_400)
    }

    // MARK: - 保存する回数

    @Test(arguments: [false, true])
    func aLicensedRefreshWritesNothing(monotonic: Bool) throws {
        storage.trialStartDate = days(-3)
        storage.trialLastSeenDate = days(-1)
        storage.trialUsedTime = 2 * 86_400
        storage.licenseKey = try LicenseTestFixtures.licenseKey()
        let writes = storage.trialWrites
        let manager = try makeManager(verifier: verifier(), monotonic: monotonic)
        clock.advance(days: 1)
        manager.refresh()
        clock.set(days(-30))
        manager.refresh()
        #expect(manager.entitlement == .licensed(LicenseTestFixtures.info()))
        #expect(manager.canExecuteActions)
        #expect(storage.trialWrites == writes)
        #expect(storage.savedProgressCount == 0)
        // ライセンスを外すと、保存してある記録から数え直す（ライセンスがあった間も時計のとおりに数える）
        clock.set(days(1))
        manager.deactivate()
        #expect(manager.entitlement == .trial(daysLeft: 10))
        #expect(storage.trialUsedTime == 4.0 * 86_400)
    }

    @Test(arguments: [false, true])
    func refreshRewritesTheRecordOnlyWhenItMeaningfullyChanges(monotonic: Bool) throws {
        let manager = makeManager(monotonic: monotonic)
        let launched = storage.trialWrites
        // 同じ時刻にもう一度・時間がふつうに進んだだけ（保存してある記録からでも同じだけ数えられる）
        manager.refresh()
        clock.advance(seconds: TrialProgress.saveInterval - 60)
        manager.refresh()
        #expect(storage.trialWrites == launched)
        #expect(storage.trialUsedTime == 0)
        // キーチェーンのような置き場所が書くかを決められるように、数えるたびに知らせる
        #expect(storage.savedProgressCount == 3)
        // 使った時間が saveInterval 増えたら書く
        clock.advance(seconds: 60)
        manager.refresh()
        #expect(storage.trialWrites == launched + 2)
        #expect(storage.trialUsedTime == TrialProgress.saveInterval)
        // 時計を戻したら、使った時間が増えなくても書く
        clock.set(days(-1))
        manager.refresh()
        #expect(storage.trialWrites == launched + 4)
        #expect(storage.trialLastSeenDate == days(-1))
        #expect(storage.trialUsedTime == TrialProgress.saveInterval)
        // 期限が切れたら、使った時間の増え方が saveInterval に満たなくても書く
        clock.advance(seconds: TrialProgress.duration - TrialProgress.saveInterval - 60)
        manager.refresh()
        #expect(manager.entitlement == .trial(daysLeft: 1))
        #expect(storage.trialWrites == launched + 6)
        clock.advance(seconds: 60)
        manager.refresh()
        #expect(manager.entitlement == .expired)
        #expect(storage.trialWrites == launched + 8)
        #expect(storage.trialUsedTime == TrialProgress.duration)
        // 期限が切れた後も、意味のある変化が無ければ書かない
        clock.advance(seconds: 60)
        manager.refresh()
        #expect(storage.trialWrites == launched + 8)
    }

    @Test func liveInitializerUsesTheRealClocks() throws {
        let manager = LicenseManager(verifier: nil, storage: storage)
        #expect(manager.entitlement == .trial(daysLeft: 14))
        #expect(manager.canExecuteActions)
        let first = LicenseManager.systemUptime()
        #expect(first > 0)
        #expect(LicenseManager.systemUptime() >= first)
    }

    // MARK: - ライセンス

    @Test func activateStoresTheKeyAndLicenses() throws {
        let manager = try makeManager(verifier: verifier())
        let key = try LicenseTestFixtures.licenseKey()
        let info = try manager.activate(licenseKey: "\n  \(key.prefix(30))\n\(key.dropFirst(30))  \n")
        #expect(info == LicenseTestFixtures.info())
        #expect(storage.licenseKey == key)
        #expect(manager.entitlement == .licensed(info))
        clock.advance(days: 100)
        manager.refresh()
        #expect(manager.entitlement == .licensed(info))
        #expect(manager.canExecuteActions)
    }

    @Test func activateStoresOnlyTheKeyFromPastedText() throws {
        let manager = try makeManager(verifier: verifier())
        let key = try LicenseTestFixtures.licenseKey()
        let info = try manager.activate(licenseKey: "License key: “\(key)”\nThank you!")
        #expect(info == LicenseTestFixtures.info())
        #expect(storage.licenseKey == key)
        // 長すぎる貼り付けは調べない
        #expect(throws: LicenseError.malformed) {
            try manager.activate(licenseKey: key + String(repeating: " x", count: 10_000))
        }
        #expect(storage.licenseKey == key)
    }

    @Test func activateAfterTheTrialExpired() throws {
        let manager = try makeManager(verifier: verifier())
        clock.advance(days: 30)
        manager.refresh()
        #expect(manager.canExecuteActions == false)
        try manager.activate(licenseKey: LicenseTestFixtures.licenseKey())
        #expect(manager.canExecuteActions)
    }

    @Test func failedActivationChangesNothing() throws {
        let manager = try makeManager(verifier: verifier())
        let wrongProduct = try LicenseTestFixtures.licenseKey(LicenseTestFixtures.info(product: "com.example.Other"))
        #expect(throws: LicenseError.wrongProduct) { try manager.activate(licenseKey: wrongProduct) }
        #expect(throws: LicenseError.malformed) { try manager.activate(licenseKey: "not a key") }
        #expect(storage.licenseKey == nil)
        #expect(manager.entitlement == .trial(daysLeft: 14))

        // 登録済みのライセンスは、間違ったキーを入れても残る
        let validKey = try LicenseTestFixtures.licenseKey()
        let info = try manager.activate(licenseKey: validKey)
        let otherKey = try LicenseSigner(privateKeyBase64: LicenseTestFixtures.otherKeys.privateKeyBase64).sign(LicenseTestFixtures.info())
        #expect(throws: LicenseError.invalidSignature) { try manager.activate(licenseKey: otherKey) }
        #expect(manager.entitlement == .licensed(info))
        #expect(storage.licenseKey == validKey)
    }

    @Test func activateWithoutPublicKeyThrowsButTrialWorks() throws {
        let manager = makeManager(verifier: nil)
        #expect(throws: LicenseError.invalidPublicKey) {
            try manager.activate(licenseKey: LicenseTestFixtures.licenseKey())
        }
        #expect(storage.licenseKey == nil)
        #expect(manager.entitlement == .trial(daysLeft: 14))
        #expect(manager.canExecuteActions)
    }

    @Test func deactivateFallsBackToTrialOrExpired() throws {
        let manager = try makeManager(verifier: verifier())
        try manager.activate(licenseKey: LicenseTestFixtures.licenseKey())
        clock.advance(days: 3)
        manager.deactivate()
        #expect(storage.licenseKey == nil)
        #expect(manager.entitlement == .trial(daysLeft: 11))

        try manager.activate(licenseKey: LicenseTestFixtures.licenseKey())
        clock.advance(days: 20)
        manager.deactivate()
        #expect(manager.entitlement == .expired)
        #expect(manager.canExecuteActions == false)
    }

    @Test func verifiesAStoredKeyOnInit() throws {
        storage.licenseKey = try LicenseTestFixtures.licenseKey()
        storage.trialStartDate = start.addingTimeInterval(-60 * 86_400)
        let manager = try makeManager(verifier: verifier())
        #expect(manager.entitlement == .licensed(LicenseTestFixtures.info()))
        #expect(manager.canExecuteActions)
    }

    @Test func ignoresAnInvalidStoredKey() throws {
        let forged = try LicenseSigner(privateKeyBase64: LicenseTestFixtures.otherKeys.privateKeyBase64).sign(LicenseTestFixtures.info())
        for key in [forged, "garbage", try LicenseTestFixtures.licenseKey(LicenseTestFixtures.info(product: "x"))] {
            let storage = MemoryLicenseStorage(trialStartDate: start, licenseKey: key)
            let manager = LicenseManager(verifier: try verifier(), storage: storage, now: clock.closure)
            #expect(manager.entitlement == .trial(daysLeft: 14))
            // 消さない（公開鍵を差し替えたビルドなどで、後から使えることがある）
            #expect(storage.licenseKey == key)
        }
        let expiredStorage = MemoryLicenseStorage(trialStartDate: start.addingTimeInterval(-15 * 86_400), licenseKey: forged)
        let expired = LicenseManager(verifier: try verifier(), storage: expiredStorage, now: clock.closure)
        #expect(expired.entitlement == .expired)
    }

    @Test func ignoresAStoredKeyWithoutPublicKey() throws {
        storage.licenseKey = try LicenseTestFixtures.licenseKey()
        let manager = makeManager(verifier: nil)
        #expect(manager.entitlement == .trial(daysLeft: 14))
    }

    @Test func refreshPicksUpAKeyStoredElsewhere() throws {
        let manager = try makeManager(verifier: verifier())
        storage.licenseKey = try LicenseTestFixtures.licenseKey()
        manager.refresh()
        #expect(manager.entitlement == .licensed(LicenseTestFixtures.info()))
        storage.licenseKey = nil
        manager.refresh()
        #expect(manager.entitlement == .trial(daysLeft: 14))
    }

    // MARK: - 観測

    @Test func refreshNotifiesObserversOnlyWhenTheEntitlementChanges() throws {
        let manager = makeManager()
        let changes = ChangeCounter()
        func observe() {
            withObservationTracking {
                _ = manager.entitlement
            } onChange: {
                changes.increment()
            }
        }
        observe()
        clock.advance(days: 0.1)
        manager.refresh()
        #expect(changes.count == 0)
        clock.advance(days: 1)
        manager.refresh()
        #expect(changes.count == 1)
    }
}

private final class ChangeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int {
        lock.withLock { value }
    }

    func increment() {
        lock.withLock { value += 1 }
    }
}
