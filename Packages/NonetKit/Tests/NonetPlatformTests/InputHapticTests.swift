import Foundation
import NonetCore
import Testing
@testable import NonetPlatform

@Suite struct InputHapticTuningTests {
    static let events: [HapticEvent] = [.boundary, .pageChange, .layerChange, .execute, .activation, .rejected]

    @Test(arguments: events)
    func offPlaysNothing(event: HapticEvent) {
        #expect(HapticTuning.actuation(for: event, strength: .off) == nil)
    }

    @Test(arguments: events)
    func everyStrengthHasAnActuationThatGrowsWithStrength(event: HapticEvent) throws {
        let light = try #require(HapticTuning.actuation(for: event, strength: .light))
        let medium = try #require(HapticTuning.actuation(for: event, strength: .medium))
        let strong = try #require(HapticTuning.actuation(for: event, strength: .strong))
        #expect(light.actuationID <= medium.actuationID)
        #expect(medium.actuationID <= strong.actuationID)
        #expect(HapticTuning.minimumIntervals[event] != nil)
    }

    @Test func boundaryIsTheGentlest() throws {
        for strength in [HapticStrength.light, .medium, .strong] {
            let boundary = try #require(HapticTuning.actuation(for: .boundary, strength: strength))
            let execute = try #require(HapticTuning.actuation(for: .execute, strength: strength))
            #expect(boundary.actuationID <= execute.actuationID)
        }
    }

    /// 種類ごとに強さか打つ回数が違い、どの強さでも指で見分けられる（境界・ページ・実行・受け付けなかった）
    @Test(arguments: [HapticStrength.light, .medium, .strong])
    func eachKindFeelsDifferentAtEveryStrength(strength: HapticStrength) {
        let kinds: [HapticEvent] = [.boundary, .pageChange, .execute, .rejected]
        let feels = kinds.map { event in
            HapticTuning.pulses(for: event, strength: strength).map { "\($0.actuation.actuationID)@\($0.delay)" }
        }
        #expect(Set(feels).count == kinds.count)
    }

    @Test func pageChangesAndRejectionsAreTwoPulses() throws {
        let page = HapticTuning.pulses(for: .pageChange, strength: .medium)
        #expect(page.map(\.delay) == [0, 0.05])
        #expect(page.map(\.actuation.actuationID) == [4, 4])
        for strength in [HapticStrength.light, .medium, .strong] {
            let rejected = HapticTuning.pulses(for: .rejected, strength: strength)
            #expect(rejected.map(\.delay) == [0, 0.04])
            #expect(rejected.map(\.actuation.actuationID) == [3, 3])
            #expect(HapticTuning.pulses(for: .execute, strength: strength).count == 1)
            #expect(HapticTuning.pulses(for: .boundary, strength: strength).count == 1)
        }
        #expect(HapticTuning.pulses(for: .rejected, strength: .off).isEmpty)
        // 境界の強さ（弱 / 中 / 強）
        #expect([HapticStrength.light, .medium, .strong].map { HapticTuning.actuation(for: .boundary, strength: $0)?.actuationID } == [3, 4, 5])
        #expect([HapticStrength.light, .medium, .strong].map { HapticTuning.actuation(for: .execute, strength: $0)?.actuationID } == [4, 6, 6])
    }

    /// 層の切り替えは強めの1打。帯で止めている間に鳴りうるページの切り替え（2打）・境界と、どの強さでも違う
    @Test(arguments: [HapticStrength.light, .medium, .strong])
    func aLayerChangeIsOneStrongPulse(strength: HapticStrength) throws {
        let layer = HapticTuning.pulses(for: .layerChange, strength: strength)
        #expect(layer.count == 1)
        let feel = { (event: HapticEvent) in HapticTuning.pulses(for: event, strength: strength).map { "\($0.actuation.actuationID)@\($0.delay)" } }
        #expect(feel(.layerChange) != feel(.pageChange))
        #expect(feel(.layerChange) != feel(.boundary))
        let boundary = try #require(HapticTuning.actuation(for: .boundary, strength: strength))
        #expect(layer[0].actuation.actuationID > boundary.actuationID)
        #expect(HapticTuning.fallback(for: .layerChange) == .levelChange)
    }

    @Test func fallbackPatterns() {
        #expect(HapticTuning.fallback(for: .boundary) == .alignment)
        #expect(HapticTuning.fallback(for: .pageChange) == .levelChange)
        #expect(HapticTuning.fallback(for: .execute) == .generic)
        #expect(HapticTuning.fallback(for: .rejected) == .generic)
        #expect(HapticFallbackPattern.alignment.nsPattern == .alignment)
        #expect(HapticFallbackPattern.levelChange.nsPattern == .levelChange)
        #expect(HapticFallbackPattern.generic.nsPattern == .generic)
    }
}

@Suite struct InputHapticRateLimiterTests {
    @Test func rapidBoundaryCrossingsAreThinnedOut() {
        var limiter = HapticRateLimiter()
        let interval = HapticTuning.minimumIntervals[.boundary, default: 0]
        #expect(limiter.shouldPlay(.boundary, at: 1) == true)
        #expect(limiter.shouldPlay(.boundary, at: 1 + interval / 2) == false)
        #expect(limiter.shouldPlay(.boundary, at: 1 + interval) == true)
        // 1秒間に100回またいでも、鳴るのは間隔ぶんだけ
        var played = 0
        for i in 0..<100 where limiter.shouldPlay(.boundary, at: 10 + Double(i) * 0.01) {
            played += 1
        }
        #expect(played <= Int(1 / interval) + 1)
        #expect(played >= 2)
    }

    @Test func eventsAreLimitedIndependently() {
        var limiter = HapticRateLimiter()
        #expect(limiter.shouldPlay(.boundary, at: 0) == true)
        #expect(limiter.shouldPlay(.execute, at: 0.001) == true)
        #expect(limiter.shouldPlay(.pageChange, at: 0.002) == true)
        #expect(limiter.shouldPlay(.execute, at: 0.01) == false)
    }

    @Test func boundaryStaysQuietRightAfterAnotherHaptic() {
        var limiter = HapticRateLimiter()
        #expect(limiter.shouldPlay(.execute, at: 5) == true)
        #expect(limiter.shouldPlay(.boundary, at: 5 + HapticTuning.boundaryQuietPeriod / 2) == false)
        #expect(limiter.shouldPlay(.boundary, at: 5 + HapticTuning.boundaryQuietPeriod) == true)
    }
}

@MainActor
final class FakeHapticBackend: HapticBackend {
    enum Call: Equatable {
        case open(UInt64)
        case actuate(Int32)
        case close
        case fallback(HapticFallbackPattern)
        case defaultDevice
    }

    var failingOpens: Set<UInt64> = []
    /// 先頭から順に actuate の結果に使う。空なら成功
    var actuateResults: [Bool] = []
    var defaultDevice: UInt64? = 1
    private(set) var calls: [Call] = []

    func openActuator(deviceID: UInt64) -> Bool {
        calls.append(.open(deviceID))
        return !failingOpens.contains(deviceID)
    }

    func actuate(_ actuation: HapticActuation) -> Bool {
        calls.append(.actuate(actuation.actuationID))
        return actuateResults.isEmpty ? true : actuateResults.removeFirst()
    }

    func closeActuator() {
        calls.append(.close)
    }

    func defaultDeviceID() -> UInt64? {
        calls.append(.defaultDevice)
        return defaultDevice
    }

    func performFallback(_ pattern: HapticFallbackPattern) {
        calls.append(.fallback(pattern))
    }

    func clear() {
        calls = []
    }
}

@MainActor
@Suite struct InputHapticEngineTests {
    final class Clock {
        var now: TimeInterval = 100
        var touched: UInt64?
    }

    /// 2打目の予定（手で進める）
    final class Pending {
        var pulses: [(delay: TimeInterval, action: @MainActor () -> Void)] = []
    }

    let backend = FakeHapticBackend()
    let clock = Clock()
    let pending = Pending()
    let engine: HapticEngine

    init() {
        let clock = clock
        let pending = pending
        engine = HapticEngine(
            backend: backend,
            clock: { clock.now },
            lastTouchedDevice: { clock.touched },
            schedule: { delay, action in pending.pulses.append((delay, action)) }
        )
    }

    /// 予定した2打目を打つ
    private func firePending() {
        let pulses = pending.pulses
        pending.pulses = []
        for pulse in pulses {
            clock.now += pulse.delay
            pulse.action()
        }
    }

    @Test func aPageChangePlaysTheSecondPulseLaterEvenWithinTheRateLimit() throws {
        engine.play(.pageChange, strength: .medium)
        #expect(pending.pulses.map(\.delay) == [0.05])
        let page = try #require(HapticTuning.actuation(for: .pageChange, strength: .medium)).actuationID
        #expect(backend.calls == [.defaultDevice, .close, .open(1), .actuate(page)])
        backend.clear()
        firePending()
        #expect(backend.calls == [.actuate(page)])
    }

    @Test func aRejectionIsTwoGentlePulses() throws {
        engine.play(.rejected, strength: .strong)
        firePending()
        #expect(backend.calls == [.defaultDevice, .close, .open(1), .actuate(3), .actuate(3)])
        backend.clear()
        // 続けて鳴らしすぎない
        clock.now += 0.01
        engine.play(.rejected, strength: .strong)
        #expect(backend.calls.isEmpty)
        #expect(pending.pulses.isEmpty)
    }

    private func execute() throws -> Int32 {
        try #require(HapticTuning.actuation(for: .execute, strength: .medium)).actuationID
    }

    @Test func offDoesNothing() {
        engine.play(.execute, strength: .off)
        #expect(backend.calls.isEmpty)
    }

    @Test func opensTheActuatorLazilyOnTheDefaultDevice() throws {
        #expect(backend.calls.isEmpty)
        engine.play(.execute, strength: .medium)
        #expect(backend.calls == [.defaultDevice, .close, .open(1), .actuate(try execute())])
        #expect(engine.openDeviceID == 1)
        backend.clear()
        clock.now += 1
        engine.play(.execute, strength: .medium)
        // 開いたままのアクチュエータを使い、既定のデバイスは調べ直さない
        #expect(backend.calls == [.actuate(try execute())])
    }

    @Test func usesTheLastTouchedDeviceAndReopensWhenItChanges() throws {
        clock.touched = 7
        engine.play(.execute, strength: .medium)
        #expect(backend.calls == [.close, .open(7), .actuate(try execute())])
        backend.clear()
        clock.touched = 8
        clock.now += 1
        engine.play(.execute, strength: .medium)
        #expect(backend.calls == [.close, .open(8), .actuate(try execute())])
        #expect(engine.openDeviceID == 8)
    }

    @Test func fallsBackWhenTheActuatorCannotOpenAndRetriesLater() throws {
        backend.failingOpens = [1]
        engine.play(.boundary, strength: .light)
        #expect(backend.calls == [.defaultDevice, .close, .open(1), .fallback(.alignment)])
        backend.clear()
        // しばらくは開こうとしない
        clock.now += 1
        engine.play(.execute, strength: .medium)
        #expect(backend.calls == [.close, .fallback(.generic)])
        backend.clear()
        backend.failingOpens = []
        clock.now += HapticTuning.actuatorRetryInterval
        engine.play(.execute, strength: .medium)
        #expect(backend.calls == [.close, .open(1), .actuate(try execute())])
    }

    @Test func reopensOnceWhenAnOpenActuatorStopsWorking() throws {
        engine.play(.execute, strength: .medium)
        backend.clear()
        backend.actuateResults = [false, true]
        clock.now += 1
        engine.play(.execute, strength: .medium)
        #expect(backend.calls == [.actuate(try execute()), .close, .open(1), .actuate(try execute())])
        #expect(engine.openDeviceID == 1)
    }

    @Test func fallsBackWhenActuationKeepsFailing() throws {
        backend.actuateResults = [false]
        engine.play(.pageChange, strength: .strong)
        let page = try #require(HapticTuning.actuation(for: .pageChange, strength: .strong)).actuationID
        #expect(backend.calls == [.defaultDevice, .close, .open(1), .actuate(page), .close, .fallback(.levelChange)])
        #expect(engine.openDeviceID == nil)
        // 2打目も同じく、開けなければ公開 API で鳴らす
        backend.clear()
        firePending()
        #expect(backend.calls == [.close, .fallback(.levelChange)])
    }

    @Test func fallsBackWithoutAnyDevice() {
        backend.defaultDevice = nil
        engine.play(.execute, strength: .strong)
        #expect(backend.calls == [.defaultDevice, .fallback(.generic)])
        backend.clear()
        clock.now += 1
        engine.play(.execute, strength: .strong)
        // 無いことも覚えておく
        #expect(backend.calls == [.fallback(.generic)])
    }

    @Test func rateLimitedPlaysDoNotTouchTheBackend() {
        engine.play(.boundary, strength: .medium)
        backend.clear()
        clock.now += 0.001
        engine.play(.boundary, strength: .medium)
        #expect(backend.calls.isEmpty)
    }

    @Test func resetClosesAndForgetsFailures() throws {
        backend.failingOpens = [1]
        engine.play(.execute, strength: .medium)
        backend.failingOpens = []
        backend.defaultDevice = 2
        engine.reset()
        #expect(backend.calls.last == .close)
        backend.clear()
        clock.now += 1
        engine.play(.execute, strength: .medium)
        #expect(backend.calls == [.defaultDevice, .close, .open(2), .actuate(try execute())])
    }
}
