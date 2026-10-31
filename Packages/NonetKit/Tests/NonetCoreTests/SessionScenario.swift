// SessionEngine のテストを仕様のように読めるようにする台本と補助
import Foundation
import NonetCore

/// トラックパッドの上の位置（x は左が 0、y は手前が 0）
enum Pad {
    /// マスの中央。9マスは外枠（GridInsets.cancelFrame）の内側に並ぶ
    static func center(_ cell: Int, in frame: GridInsets = .cancelFrame) -> (x: Double, y: Double) {
        let width = 1 - frame.left - frame.right
        let height = 1 - frame.bottom - frame.top
        let column = Double(cell % 3)
        let row = Double(cell / 3)
        return (frame.left + width * (column + 0.5) / 3, 1 - frame.top - height * (row + 0.5) / 3)
    }

    /// 外枠の中の点（上・下・左・右の帯の中ほど）
    static let topFrame = (x: 0.5, y: 0.94)
    static let bottomFrame = (x: 0.5, y: 0.04)
    static let leftFrame = (x: 0.03, y: 0.5)
    static let rightFrame = (x: 0.97, y: 0.5)
    /// 上の縁の帯で触れ始める点と、そこから下へ滑らせて開いた後の点（まだ上の外枠）
    static let edge = (x: 0.5, y: 0.98)
    static let slid = (x: 0.5, y: 0.92)
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

    init(pageCount: Int) {
        self.init(SessionConfiguration(pageCount: pageCount))
    }

    @discardableResult
    mutating func send(_ input: SessionInput) -> [SessionEffect] {
        let effects = engine.handle(input)
        log += effects
        return effects
    }

    /// 開く（コントローラーが開く動きを見分けた）
    @discardableResult
    mutating func open(at time: TimeInterval) -> [SessionEffect] {
        send(.open(at: time, configuration: configuration))
    }

    /// 上の縁で触れて下へ滑らせ（time と time + 0.05）、開く。開いた後の指は上の外枠にいる
    @discardableResult
    mutating func slideIn(_ id: Int = 1, at time: TimeInterval) -> [SessionEffect] {
        touch(id, x: Pad.edge.x, y: Pad.edge.y, at: time)
        touch(id, x: Pad.slid.x, y: Pad.slid.y, at: time + 0.05)
        return open(at: time + 0.05)
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
        let point = Pad.center(cell, in: configuration.frame)
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

    /// showHUD と updateHUD で出した HUD の中身（並び順）
    var hudStates: [SessionHUDState] {
        compactMap {
            switch $0 {
            case .showHUD(let state), .updateHUD(let state): state
            default: nil
            }
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
