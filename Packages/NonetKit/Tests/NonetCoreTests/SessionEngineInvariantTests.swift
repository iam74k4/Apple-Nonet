// 乱数で作った長い入力の並びで、出力がいつも守るべき決まりを確かめる（シードを固定して再現できるようにする）
import Foundation
import Testing
import NonetCore

/// SplitMix64
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// 物理的な指の動きと時刻を乱数で作る
private struct RandomInputs {
    var random: SeededGenerator
    let configuration: SessionConfiguration
    var time: TimeInterval = 100
    var fingers: [Int: (x: Double, y: Double)] = [:]
    var nextFingerID = 1
    var lastRequestedTick: TimeInterval?

    init(seed: UInt64) {
        random = SeededGenerator(state: seed)
        configuration = SessionConfiguration(
            pageCount: Int.random(in: 0...3, using: &random),
            maxDuration: Bool.random(using: &random) ? 20 : 3,
            occupiedCells: Bool.random(using: &random) ? [[0, 1, 2, 4, 6, 8], [3, 5]] : nil,
            holdCells: Bool.random(using: &random) ? [[4, 8], [5]] : nil
        )
    }

    mutating func next() -> SessionInput {
        advanceTime()
        let roll = Double.random(in: 0..<1, using: &random)
        switch roll {
        case ..<0.12:
            return .open(at: time, configuration: configuration)
        case ..<0.15:
            return .interrupted(at: time)
        case ..<0.33:
            // 頼まれた時刻ちょうどの tick も混ぜる
            if let requested = lastRequestedTick, Bool.random(using: &random) {
                time = max(time, requested)
            }
            return .tick(at: time)
        default:
            changeFingers()
            let points = fingers.keys.sorted().compactMap { id in
                fingers[id].map { TouchPoint(id: id, x: $0.x, y: $0.y) }
            }
            // まれに少し前の時刻のフレームが遅れて届く
            let stamp = Double.random(in: 0..<1, using: &random) < 0.03 ? time - 0.01 : time
            return .touches(TouchFrame(timestamp: stamp, points: points))
        }
    }

    private mutating func advanceTime() {
        let roll = Double.random(in: 0..<1, using: &random)
        if roll < 0.01 {
            time += Double.random(in: 3...25, using: &random)
        } else if roll < 0.1 {
            // 同じ時刻の入力
        } else {
            time += Double.random(in: 0.001...0.25, using: &random)
        }
    }

    private mutating func changeFingers() {
        let roll = Double.random(in: 0..<1, using: &random)
        if roll < 0.25, fingers.count < 3 {
            fingers[nextFingerID] = (Double.random(in: -0.05...1.05, using: &random), Double.random(in: -0.05...1.05, using: &random))
            nextFingerID += 1
        } else if roll < 0.5, let id = fingers.keys.sorted().randomElement(using: &random) {
            fingers[id] = nil
        } else {
            let step = Bool.random(using: &random) ? 0.02 : 0.2
            let dx = Double.random(in: -step...step, using: &random)
            // 辞書の並びはインスタンスごとに変わりうるので、id の順に乱数を使う（同じシードで同じ入力にする）
            for id in fingers.keys.sorted() {
                if let point = fingers[id] {
                    fingers[id] = (point.x + dx, point.y + Double.random(in: -step...step, using: &random))
                }
            }
        }
    }
}

/// 出力の並びと、エンジンの見える状態の決まり
private struct InvariantChecker {
    let pageCount: Int
    var inSession = false
    var hud: SessionHUDState?
    var latestTime = -Double.infinity
    /// 直前のフレームで触れていた指
    var touchingIDs: Set<Int> = []
    var issues: [String] = []

    init(configuration: SessionConfiguration) {
        pageCount = max(configuration.pageCount, 1)
    }

    mutating func check(_ input: SessionInput, _ effects: [SessionEffect], engine: SessionEngine, step: Int) {
        func fail(_ message: String) {
            issues.append("step \(step) \(input): \(message) in \(effects)")
        }
        let inputTime: TimeInterval
        let touchingBefore = touchingIDs
        var liftedEveryFinger = false
        switch input {
        case .open(let time, _), .interrupted(let time), .tick(let time):
            inputTime = time
        case .touches(let frame):
            inputTime = frame.timestamp
            let ids = Set(frame.touching.map(\.id))
            // 前のフレームの指がすべて離れた（離すと同時に置いた指は、新しいタッチ）
            liftedEveryFinger = !touchingIDs.isEmpty && touchingIDs.isDisjoint(with: ids)
            touchingIDs = ids
        }
        latestTime = max(latestTime, inputTime)

        if effects.filter({ if case .execute = $0 { true } else { false } }).count > 1 {
            fail("1つの入力で2回以上実行した")
        }
        for (index, effect) in effects.enumerated() {
            let next = effects.indices.contains(index + 1) ? effects[index + 1] : nil
            let previous = index > 0 ? effects[index - 1] : nil
            switch effect {
            case .beginPointerSuppression:
                if inSession { fail("セッション中に begin") }
                guard case .open = input else { fail("open 以外で begin"); break }
                if touchingIDs.isEmpty { fail("指が触れていないのに開いた") }
                if !Self.isShow(next) { fail("begin の次が showHUD でない") }
                inSession = true
            case .endPointerSuppression:
                if !inSession { fail("セッション外で end") }
                guard case .sessionEnded = next else { fail("end の次が sessionEnded でない"); break }
            case .sessionEnded:
                if case .endPointerSuppression? = previous {} else { fail("sessionEnded の前が end でない") }
                if hud != nil { fail("HUD を出したまま終えた") }
                inSession = false
            case .showHUD(let state):
                if !inSession || hud != nil { fail("show できない状態") }
                Self.check(state, pageCount: pageCount, fail: fail)
                hud = state
            case .updateHUD(let state):
                if hud == nil { fail("HUD が無いのに update") }
                if hud == state { fail("何も変わらない update") }
                Self.check(state, pageCount: pageCount, fail: fail)
                hud = state
            case .hideHUD:
                if hud == nil { fail("HUD が無いのに hide") }
                hud = nil
            case .haptic(let event):
                if !inSession { fail("セッション外の触覚") }
                if event == .execute { fail("execute の触覚はエンジンが出さない") }
                if event == .boundary, hud == nil { fail("HUD が無いのに boundary") }
                if event == .activation, !Self.isShow(previous) { fail("開いたとき以外の activation") }
            case .execute(let page, let cell):
                if !inSession { fail("セッション外で実行") }
                Self.checkRange(page: page, cell: cell, pageCount: pageCount, fail: fail)
                guard case .touches = input else { fail("指を離したフレーム以外で実行"); break }
                if !liftedEveryFinger { fail("指が離れていないのに実行") }
                if touchingBefore.count != 1 { fail("1本指で離していないのに実行") }
                // 先に HUD を閉じ、その後に抑止をやめて released で終える
                if previous != .hideHUD { fail("HUD を閉じずに実行") }
                if next != .endPointerSuppression(dropsLateClicks: true) { fail("実行の後に抑止をやめていない") }
            case .requestTick(let time):
                if next != nil { fail("requestTick が最後でない") }
                if !inSession { fail("セッション外で tick を頼んだ") }
                if !(time > latestTime) { fail("過去の tick を頼んだ") }
            }
            if case .sessionEnded(let reason) = effect {
                let ran = effects.contains { if case .execute = $0 { true } else { false } }
                if (reason == .released) != ran { fail("released と実行が合わない") }
                if case .cancelled = reason, !effects.contains(.haptic(.rejected)) { fail("指を離してやめたのに rejected が無い") }
            }
        }
        if engine.isInSession != inSession { fail("isInSession が出力と合わない") }
        if engine.hud != hud { fail("hud が出力と合わない") }
        if let page = engine.pageIndex, !(0..<pageCount).contains(page) { fail("ページが範囲外") }
    }

    private static func isShow(_ effect: SessionEffect?) -> Bool {
        guard case .showHUD? = effect else { return false }
        return true
    }

    private static func check(_ state: SessionHUDState, pageCount: Int, fail: (String) -> Void) {
        checkRange(page: state.page, cell: state.highlightedCell, pageCount: pageCount, fail: fail)
        if state.isInFrame, state.highlightedCell != nil { fail("外枠にいるのにマスが光っている") }
        if let hold = state.hold, hold.cell != state.highlightedCell { fail("進み具合が光っているマスのものでない") }
    }

    private static func checkRange(page: Int, cell: Int?, pageCount: Int, fail: (String) -> Void) {
        if !(0..<pageCount).contains(page) { fail("ページ \(page) が範囲外") }
        if let cell, !(0..<GridMapper.cellCount).contains(cell) { fail("マス \(cell) が範囲外") }
    }
}

@Suite struct SessionEngineInvariantTests {
    private static func run(seed: UInt64, steps: Int) -> (log: [[SessionEffect]], issues: [String], engine: SessionEngine) {
        var inputs = RandomInputs(seed: seed)
        var checker = InvariantChecker(configuration: inputs.configuration)
        var engine = SessionEngine()
        var log: [[SessionEffect]] = []
        for step in 0..<steps {
            let input = inputs.next()
            let effects = engine.handle(input)
            if let time = effects.tickRequests.last {
                inputs.lastRequestedTick = time
            }
            checker.check(input, effects, engine: engine, step: step)
            log.append(effects)
        }
        return (log, checker.issues, engine)
    }

    @Test(arguments: 0..<60)
    func randomInputsKeepTheEffectInvariants(batch: Int) {
        for offset in 0..<5 {
            let seed = UInt64(batch * 5 + offset) &* 7919 &+ 1
            let result = Self.run(seed: seed, steps: 400)
            #expect(result.issues.isEmpty, "seed \(seed): \(result.issues.prefix(3))")
        }
    }

    @Test func sameInputsAlwaysGiveTheSameEffects() {
        for seed: UInt64 in [3, 17, 99, 2026] {
            #expect(Self.run(seed: seed, steps: 500).log == Self.run(seed: seed, steps: 500).log)
        }
    }

    @Test func everySessionEventuallyEnds() {
        for seed: UInt64 in 1...40 {
            var engine = Self.run(seed: seed, steps: 200).engine
            // どんな状態からでも、指を離して時間が経てば必ず終わる
            _ = engine.handle(.touches(TouchFrame(timestamp: 10_000, points: [])))
            _ = engine.handle(.tick(at: 10_100))
            #expect(!engine.isInSession, "seed \(seed)")
        }
    }

    @Test func randomRunsActuallyExerciseEveryKindOfEffect() {
        var seen = Set<String>()
        for seed: UInt64 in 1...40 {
            for effects in Self.run(seed: seed, steps: 400).log {
                for effect in effects {
                    seen.insert(Self.kind(of: effect))
                }
            }
        }
        #expect(seen == [
            "begin", "end", "show", "update", "hide", "activation", "boundary", "pageChange", "rejected",
            "execute", "tick", "released", "cancelled", "interrupted", "timeout",
        ])
    }

    private static func kind(of effect: SessionEffect) -> String {
        switch effect {
        case .beginPointerSuppression: "begin"
        case .endPointerSuppression: "end"
        case .showHUD: "show"
        case .updateHUD: "update"
        case .hideHUD: "hide"
        case .haptic(let event): "\(event)"
        case .execute: "execute"
        case .requestTick: "tick"
        case .sessionEnded(let reason):
            switch reason {
            case .released: "released"
            case .cancelled: "cancelled"
            case .interrupted: "interrupted"
            case .timeout: "timeout"
            }
        }
    }
}
