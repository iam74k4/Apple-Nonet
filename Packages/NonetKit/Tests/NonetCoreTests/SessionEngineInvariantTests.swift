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
            hudDelay: [0, 0.15, 0.3, 0.5, 0.8].randomElement(using: &random) ?? 0.3,
            fireMode: Bool.random(using: &random) ? .onTriggerRelease : .onFingerLift,
            pageCount: Int.random(in: 0...3, using: &random),
            maxDuration: Bool.random(using: &random) ? 20 : 3
        )
    }

    mutating func next() -> SessionInput {
        advanceTime()
        let roll = Double.random(in: 0..<1, using: &random)
        switch roll {
        case ..<0.08:
            return .triggerDown(at: time, configuration: configuration)
        case ..<0.16:
            return .triggerUp(at: time)
        case ..<0.18:
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
    let fireMode: FireMode
    var inSession = false
    var hud: SessionHUDState?
    var latestTime = -Double.infinity
    /// 直前のフレームで触れていた指
    var touchingIDs: Set<Int> = []
    /// セッションを始めたときに触れていて、まだ離れていない指（エンジンはほかの指を置いたら数えない）
    var preTriggerIDs: Set<Int> = []
    /// トリガーより後に置いた指が、いまのタッチ（その数が 0 になるまで）で同時に触れた最大数
    var activeMaxFingers = 0
    var issues: [String] = []

    init(configuration: SessionConfiguration) {
        pageCount = max(configuration.pageCount, 1)
        fireMode = configuration.fireMode
    }

    mutating func check(_ input: SessionInput, _ effects: [SessionEffect], engine: SessionEngine, step: Int) {
        func fail(_ message: String) {
            issues.append("step \(step) \(input): \(message) in \(effects)")
        }
        let inputTime: TimeInterval
        let activeMaxBefore = activeMaxFingers
        var liftedInThisFrame = false
        var activeNow = 0
        switch input {
        case .triggerDown(let time, _), .triggerUp(let time), .interrupted(let time), .tick(let time):
            inputTime = time
        case .touches(let frame):
            inputTime = frame.timestamp
            let ids = Set(frame.touching.map(\.id))
            liftedInThisFrame = !touchingIDs.subtracting(ids).isEmpty
            touchingIDs = ids
            preTriggerIDs.formIntersection(ids)
            activeNow = ids.subtracting(preTriggerIDs).count
            activeMaxFingers = activeNow == 0 ? 0 : max(activeMaxFingers, activeNow)
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
                guard case .triggerDown = input else { fail("triggerDown 以外で begin"); break }
                inSession = true
                preTriggerIDs = touchingIDs
                activeMaxFingers = 0
            case .endPointerSuppression:
                if !inSession { fail("セッション外で end") }
                guard case .sessionEnded = next else { fail("end の次が sessionEnded でない"); break }
            case .sessionEnded:
                if case .endPointerSuppression? = previous {} else { fail("sessionEnded の前が end でない") }
                if hud != nil { fail("HUD を出したまま終えた") }
                inSession = false
            case .showHUD(let page, let cell):
                if !inSession || hud != nil { fail("show できない状態") }
                Self.checkRange(page: page, cell: cell, pageCount: pageCount, fail: fail)
                hud = SessionHUDState(page: page, highlightedCell: cell)
            case .updateHUD(let page, let cell):
                let state = SessionHUDState(page: page, highlightedCell: cell)
                if hud == nil { fail("HUD が無いのに update") }
                if hud == state { fail("何も変わらない update") }
                Self.checkRange(page: page, cell: cell, pageCount: pageCount, fail: fail)
                hud = state
            case .hideHUD:
                if hud == nil { fail("HUD が無いのに hide") }
                hud = nil
            case .haptic(let event):
                if !inSession { fail("セッション外の触覚") }
                if event == .execute { fail("execute の触覚はエンジンが出さない") }
                if event == .boundary, hud == nil { fail("HUD が無いのに boundary") }
            case .execute(let page, let cell, let wasFastTap):
                if !inSession { fail("セッション外で実行") }
                Self.checkRange(page: page, cell: cell, pageCount: pageCount, fail: fail)
                switch input {
                case .touches:
                    // トリガーより前から休めている指は触れたままでよい（エンジンは数えない）
                    if !liftedInThisFrame || activeNow != 0 { fail("指が離れていないのに実行") }
                    if activeMaxBefore > 1 { fail("2本以上の指のタッチで実行") }
                    // HUD から実行する（指を離したとき・HUD でのタップ）ときは、先に HUD を閉じる
                    if !wasFastTap, previous != .hideHUD { fail("HUD を閉じずに指を離して HUD から実行") }
                    if wasFastTap, hud != nil { fail("HUD を出したまま速押し") }
                case .triggerUp:
                    if wasFastTap || fireMode != .onTriggerRelease { fail("トリガーを離したときの実行の種類が違う") }
                    if activeMaxBefore > 1 { fail("2本以上の指のタッチで実行") }
                default:
                    fail("tick・中断・押下で実行")
                }
            case .requestTick(let time):
                if next != nil { fail("requestTick が最後でない") }
                if !inSession { fail("セッション外で tick を頼んだ") }
                if !(time > latestTime) { fail("過去の tick を頼んだ") }
            }
        }
        if engine.isInSession != inSession { fail("isInSession が出力と合わない") }
        if engine.hud != hud { fail("hud が出力と合わない") }
        if let page = engine.pageIndex, !(0..<pageCount).contains(page) { fail("ページが範囲外") }
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
            "begin", "end", "show", "update", "hide", "boundary", "pageChange", "rejected",
            "fastTap", "hudExecute", "tick", "released", "cancelled", "interrupted", "timeout",
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
        case .execute(_, _, let wasFastTap): wasFastTap ? "fastTap" : "hudExecute"
        case .requestTick: "tick"
        case .sessionEnded(let reason): "\(reason)"
        }
    }
}
