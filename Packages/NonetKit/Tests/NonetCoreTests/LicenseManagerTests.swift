import Foundation
import Observation
import Testing
@testable import NonetCore

private final class MemoryLicenseStorage: LicenseStorage {
    var trialStartDate: Date?
    var licenseKey: String?

    init(trialStartDate: Date? = nil, licenseKey: String? = nil) {
        self.trialStartDate = trialStartDate
        self.licenseKey = licenseKey
    }
}

/// 進めたり戻したりできる時計
private final class ManualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date) {
        current = start
    }

    var now: Date {
        lock.withLock { current }
    }

    func set(_ date: Date) {
        lock.withLock { current = date }
    }

    func advance(days: Double) {
        lock.withLock { current = current.addingTimeInterval(days * 86_400) }
    }

    var closure: @Sendable () -> Date {
        { [self] in now }
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

    private func makeManager(verifier: LicenseVerifier? = nil) -> LicenseManager {
        LicenseManager(verifier: verifier, storage: storage, now: clock.closure)
    }

    private func verifier() throws -> LicenseVerifier {
        try LicenseTestFixtures.verifier()
    }

    // MARK: - 試用

    @Test func firstLaunchStartsTheTrial() throws {
        let manager = makeManager()
        #expect(storage.trialStartDate == start)
        #expect(manager.entitlement == .trial(daysLeft: 14))
        #expect(manager.canExecuteActions)
    }

    @Test func keepsAnExistingTrialStart() throws {
        storage.trialStartDate = start.addingTimeInterval(-3 * 86_400)
        let manager = makeManager()
        #expect(storage.trialStartDate == start.addingTimeInterval(-3 * 86_400))
        #expect(manager.entitlement == .trial(daysLeft: 11))
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
        let manager = makeManager()
        clock.advance(days: day)
        manager.refresh()
        #expect(manager.entitlement == expected)
        #expect(manager.canExecuteActions == (expected != .expired))
    }

    @Test func trialEndsExactlyFourteenTimesTwentyFourHoursAfterStart() {
        let end = start.addingTimeInterval(14 * 24 * 60 * 60)
        #expect(LicenseManager.trialEntitlement(start: start, now: end.addingTimeInterval(-0.001)) == .trial(daysLeft: 1))
        #expect(LicenseManager.trialEntitlement(start: start, now: end) == .expired)
    }

    @Test func clockMovedBeforeTheTrialStartDoesNotExtendTheTrial() throws {
        // 保存された開始日より前に時計が戻されている
        storage.trialStartDate = start.addingTimeInterval(5 * 86_400)
        let manager = makeManager()
        #expect(manager.entitlement == .trial(daysLeft: 14))
        #expect(storage.trialStartDate == start)
        clock.advance(days: 14)
        manager.refresh()
        #expect(manager.entitlement == .expired)
    }

    @Test func clockMovedBackWhileRunningNeverGivesMoreThanFourteenDays() throws {
        let manager = makeManager()
        clock.advance(days: 10)
        manager.refresh()
        #expect(manager.entitlement == .trial(daysLeft: 4))
        clock.set(start.addingTimeInterval(-365 * 86_400))
        manager.refresh()
        #expect(manager.entitlement == .trial(daysLeft: 14))
        // 正しい時刻に戻すと、試用はもう終わっている
        clock.set(start.addingTimeInterval(10 * 86_400))
        manager.refresh()
        #expect(manager.entitlement == .expired)
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

    @Test func restartsTheTrialRecordIfStorageLosesIt() throws {
        let manager = makeManager()
        clock.advance(days: 2)
        storage.trialStartDate = nil
        manager.refresh()
        #expect(storage.trialStartDate == start.addingTimeInterval(2 * 86_400))
        #expect(manager.entitlement == .trial(daysLeft: 14))
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
