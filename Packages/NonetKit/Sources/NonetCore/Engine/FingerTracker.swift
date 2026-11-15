// 担当: engine
import Foundation

/// 触れている指を置いた順に覚える。セッションの外でも動かし続け、
/// 9マスを開いたときに触れている指（開く動きの指）を知っておけるようにする
struct FingerTracker: Sendable {
    struct Finger: Equatable, Sendable {
        var id: Int
        var x: Double
        var y: Double
    }

    /// 1フレームで起きたこと。「タッチ」は最初の指が触れてから、すべての指が離れるまで
    enum Change: Equatable, Sendable {
        /// 触れていない状態が続いている
        case none
        /// 新しいタッチが始まった
        case began
        /// タッチが続いている（指が増減・移動した）
        case moved
        /// すべての指が離れた
        case ended
        /// フレームの間に指がすべて入れ替わった（離すのと置くのが1フレームの間に起きた）。
        /// 前のタッチが終わり、新しいタッチが始まったとみなす
        case restarted
    }

    /// 置いた順
    private(set) var fingers: [Finger] = []
    /// いまのタッチが始まった時刻
    private(set) var gestureStart: TimeInterval = 0
    /// いまのタッチで同時に触れていた指の最大数
    private(set) var gestureMaxFingers = 0
    /// 直前のフレームで新しく置かれた指の id（置いた順）
    private(set) var placedInLastFrame: [Int] = []

    var isTouching: Bool { !fingers.isEmpty }
    var count: Int { fingers.count }
    /// 最後に置いた指（仕様 2: 複数の指があるときはこの指を使う）
    var lastPlaced: Finger? { fingers.last }

    mutating func apply(_ points: [TouchPoint], at time: TimeInterval) -> Change {
        // 同じ id が重なっていたら後のものを使う
        var latest: [Int: TouchPoint] = [:]
        for point in points where point.isTouching {
            latest[point.id] = point
        }
        let previousIDs = Set(fingers.map(\.id))
        let wasTouching = !fingers.isEmpty

        var next = fingers.compactMap { finger in
            latest[finger.id].map { Finger(id: finger.id, x: $0.x, y: $0.y) }
        }
        let continued = !next.isEmpty
        var placed: [Int] = []
        // 同じフレームで複数の指が増えたら、id の小さい順に置いたとみなす
        for id in latest.keys.sorted() where !previousIDs.contains(id) {
            if let point = latest[id] {
                next.append(Finger(id: id, x: point.x, y: point.y))
                placed.append(id)
            }
        }
        fingers = next
        placedInLastFrame = placed

        let change: Change = switch (wasTouching, !next.isEmpty) {
        case (false, false): .none
        case (false, true): .began
        case (true, false): .ended
        case (true, true): continued ? .moved : .restarted
        }
        if change == .began || change == .restarted {
            gestureStart = time
            gestureMaxFingers = 0
        }
        gestureMaxFingers = next.isEmpty ? 0 : max(gestureMaxFingers, next.count)
        return change
    }
}
