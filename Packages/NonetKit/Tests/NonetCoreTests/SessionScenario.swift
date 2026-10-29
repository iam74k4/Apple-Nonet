// SessionEngine のテストを仕様のように読めるようにする台本と補助
import Foundation
import NonetCore

/// マスの中央の座標（x は左が 0、y は手前が 0）
enum Pad {
    static func center(_ cell: Int) -> (x: Double, y: Double) {
        let column = Double(cell % 3)
        let row = Double(cell / 3)
        return ((column + 0.5) / 3, 1 - (row + 0.5) / 3)
    }
}

/// 時刻つきの操作を順にエンジンへ流す。各操作はその入力で出た出力を返す
struct SessionScenario {
    var engine = SessionEngine()
    var configuration: SessionConfiguration
    /// これまでのすべての出力
    private(set) var log: [SessionEffect] = []
    /// いま触れている指
    private(set) var fingers: [Int: (x: Double, y: Double)] = [:]

    init(_ configuration: SessionConfiguration = SessionConfiguration()) {
        self.configuration = configuration
    }

    init(hudDelay: TimeInterval = 0.3, fireMode: FireMode = .onTriggerRelease, pageCount: Int = 1) {
        self.init(SessionConfiguration(hudDelay: hudDelay, fireMode: fireMode, pageCount: pageCount))
    }

    @discardableResult
    mutating func send(_ input: SessionInput) -> [SessionEffect] {
        let effects = engine.handle(input)
        log += effects
        return effects
    }

    @discardableResult
    mutating func pressTrigger(at time: TimeInterval) -> [SessionEffect] {
        send(.triggerDown(at: time, configuration: configuration))
    }

    @discardableResult
    mutating func releaseTrigger(at time: TimeInterval) -> [SessionEffect] {
        send(.triggerUp(at: time))
    }

    @discardableResult
    mutating func interrupt(at time: TimeInterval) -> [SessionEffect] {
        send(.interrupted(at: time))
    }

    @discardableResult
    mutating func tick(at time: TimeInterval) -> [SessionEffect] {
        send(.tick(at: time))
    }

    /// 指を置く・動かす（マスの中央へ）
    @discardableResult
    mutating func touch(_ id: Int = 1, on cell: Int, at time: TimeInterval) -> [SessionEffect] {
        let point = Pad.center(cell)
        return touch(id, x: point.x, y: point.y, at: time)
    }

    @discardableResult
    mutating func touch(_ id: Int = 1, x: Double, y: Double, at time: TimeInterval) -> [SessionEffect] {
        fingers[id] = (x, y)
        return sendFrame(at: time)
    }

    /// 触れている指をまとめて置き換える（2本指のスワイプなど）
    @discardableResult
    mutating func setFingers(_ points: [(id: Int, x: Double, y: Double)], at time: TimeInterval) -> [SessionEffect] {
        fingers = [:]
        for point in points {
            fingers[point.id] = (point.x, point.y)
        }
        return sendFrame(at: time)
    }

    @discardableResult
    mutating func lift(_ id: Int = 1, at time: TimeInterval) -> [SessionEffect] {
        fingers[id] = nil
        return sendFrame(at: time)
    }

    @discardableResult
    mutating func liftAll(at time: TimeInterval) -> [SessionEffect] {
        fingers.removeAll()
        return sendFrame(at: time)
    }

    /// いまの指をそのまま送り直す（トラックパッドは触れている間フレームを送り続ける）
    @discardableResult
    mutating func sendFrame(at time: TimeInterval) -> [SessionEffect] {
        let points = fingers.keys.sorted().compactMap { id in
            fingers[id].map { TouchPoint(id: id, x: $0.x, y: $0.y) }
        }
        return send(.touches(TouchFrame(timestamp: time, points: points)))
    }
}

extension Array where Element == SessionEffect {
    /// requestTick を除いたもの（タイマーの依頼を気にしないテスト用）
    var visible: [SessionEffect] {
        filter {
            if case .requestTick = $0 { return false }
            return true
        }
    }

    var executions: [SessionEffect] {
        filter {
            if case .execute = $0 { return true }
            return false
        }
    }

    var tickRequests: [TimeInterval] {
        compactMap {
            if case .requestTick(let time) = $0 { return time }
            return nil
        }
    }

    var showsHUD: Bool {
        contains {
            if case .showHUD = $0 { return true }
            return false
        }
    }

    var hapticEvents: [HapticEvent] {
        compactMap {
            if case .haptic(let event) = $0 { return event }
            return nil
        }
    }

    var endReason: SessionEndReason? {
        compactMap {
            if case .sessionEnded(let reason) = $0 { return reason }
            return nil
        }.last
    }
}
