import Foundation
import NonetCore
import Testing
@testable import NonetPlatform

@Suite struct InputHapticTuningTests {
    static let events: [HapticEvent] = [.boundary, .pageChange, .execute]

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

    @Test func fallbackPatterns() {
        #expect(HapticTuning.fallback(for: .boundary) == .alignment)
        #expect(HapticTuning.fallback(for: .pageChange) == .levelChange)
        #expect(HapticTuning.fallback(for: .execute) == .generic)
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

    let backend = FakeHapticBackend()
    let clock = Clock()
    let engine: HapticEngine

    init() {
        let clock = clock
        engine = HapticEngine(backend: backend, clock: { clock.now }, lastTouchedDevice: { clock.touched })
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
