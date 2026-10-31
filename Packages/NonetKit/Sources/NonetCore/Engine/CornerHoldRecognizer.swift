// 担当: engine
// トラックパッドの角の長押し（GlobalSettings.touchActivation）を見分ける純粋なロジック。
// NonetController がセッションの外のフレームも含めてすべて渡し、長押しになったらトリガーキーと同じ道筋でセッションを始める
import Foundation

/// 上の角に1本指を置いて、ほとんど動かさずに holdDuration 待ったら、9マスを出す合図を1回だけ返す。
/// 次のときは合図しない（そのタッチの間は、もう待たない）:
/// - 角の外で触れ始めた（外から角に入ってきた指を含む）。最初から2本以上で触れた
/// - 待っている間に、ほかの指が触れた・movementTolerance より動いた・離れた
/// - 接触が手のひらの大きさ（palmMajorAxis 以上）になった
/// - 設定が「使わない」か、セッション中に触れ始めた（キーで始めたセッションの指を、終わった後に長押しとみなさない）
/// 指の出入りは設定やセッションに関係なく数え続ける。時刻は TouchFrame.timestamp と同じ時計の秒
public struct CornerHoldRecognizer: Sendable {
    /// 角の範囲の幅（トラックパッドの幅を 1 とした割合）。角の縁から数える
    public static let zoneWidth = 0.12
    /// 角の範囲の高さ（トラックパッドの奥行きを 1 とした割合）。奥の縁（y = 1）から数える
    public static let zoneHeight = 0.18
    /// 指を置いてから合図するまで
    public static let holdDuration: TimeInterval = 0.4
    /// 止めているとみなす動きの範囲（トラックパッドを 1 とした割合での距離）。
    /// 始まったセッションで「指を滑らせた」とみなすのも、これより動いたとき
    public static let movementTolerance = 0.02
    /// これ以上の長径（TouchPoint.majorAxis）の接触は手のひらとみなし、長押しを待たない。
    /// 指先はおよそ 8〜15、平らに置いた親指でも 20 ほどなので、それより大きいものだけを外す控えめな値にしている
    /// （単位は MultitouchSupport の majorAxis のまま。実機では確かめていない。値が取れない接触は外さない）
    public static let palmMajorAxis = 25.0
    /// 始まったセッションで、滑らせた後に光っているマスにこの秒数以上留まってから離したときだけ実行する
    /// （置いて止めていた指が、そのままカーソルの移動やドラッグで動いて離れたのを、選んだとみなさない）。
    /// 留まり始めるのは、そのマスになった時刻と、滑らせたとみなした時刻の遅いほう。足りなければキャンセル
    public static let liftDwell: TimeInterval = 0.15

    private struct Candidate: Sendable {
        var corner: TouchActivation
        var fingerID: Int
        var x: Double
        var y: Double
        var start: TimeInterval
    }

    private var tracker = FingerTracker()
    /// 長押しを待っているタッチ。合図した・取り消したら nil にし、そのタッチの間は作り直さない
    private var candidate: Candidate?

    public init() {}

    /// 長押しを待っている間、合図する時刻（この時刻に tick(at:) を呼ぶと合図する）。待っていなければ nil
    public var deadline: TimeInterval? {
        candidate.map { $0.start + Self.holdDuration }
    }

    /// 手のひらの大きさの接触か。大きさが分からなければ false
    public static func isPalmSized(_ point: TouchPoint) -> Bool {
        guard let majorAxis = point.majorAxis else { return false }
        return majorAxis >= palmMajorAxis
    }

    /// (x, y) が corner の範囲の中か。縁ちょうどは中。off ならいつも外
    public static func isInZone(x: Double, y: Double, corner: TouchActivation) -> Bool {
        guard y >= 1 - zoneHeight else { return false }
        switch corner {
        case .off: return false
        case .topLeft: return x <= zoneWidth
        case .topRight: return x >= 1 - zoneWidth
        }
    }

    /// フレームを1つ渡す。長押しになったら true（そのタッチでは二度と true を返さない）。
    /// corner が off か変わった・isSessionActive なら、待っている長押しを取り消し、新しく触れた指も待たない
    public mutating func apply(_ frame: TouchFrame, corner: TouchActivation, isSessionActive: Bool) -> Bool {
        let time = frame.timestamp
        let change = tracker.apply(frame.points, at: time)
        let isWatching = corner != .off && !isSessionActive
        switch change {
        case .none:
            return false
        case .ended:
            candidate = nil
            return false
        case .began, .restarted:
            candidate = nil
            guard isWatching, tracker.count == 1, let finger = tracker.lastPlaced,
                  Self.isInZone(x: finger.x, y: finger.y, corner: corner),
                  !Self.isPalmSized(finger.id, in: frame) else { return false }
            candidate = Candidate(corner: corner, fingerID: finger.id, x: finger.x, y: finger.y, start: tracker.gestureStart)
            return fireIfDue(at: time)
        case .moved:
            guard let waiting = candidate else { return false }
            guard isWatching, corner == waiting.corner, tracker.count == 1, let finger = tracker.lastPlaced, finger.id == waiting.fingerID,
                  hypot(finger.x - waiting.x, finger.y - waiting.y) <= Self.movementTolerance,
                  !Self.isPalmSized(finger.id, in: frame) else {
                candidate = nil
                return false
            }
            return fireIfDue(at: time)
        }
    }

    /// deadline が来た。フレームの間隔に頼らず、ちょうど holdDuration で合図するため。
    /// 長押しになったら true。corner が off か変わった・isSessionActive なら取り消す
    public mutating func tick(at time: TimeInterval, corner: TouchActivation, isSessionActive: Bool) -> Bool {
        guard let waiting = candidate else { return false }
        guard corner == waiting.corner, !isSessionActive else {
            candidate = nil
            return false
        }
        return fireIfDue(at: time)
    }

    /// frame の中の、id の触れている接触が手のひらの大きさか
    private static func isPalmSized(_ id: Int, in frame: TouchFrame) -> Bool {
        guard let point = frame.points.last(where: { $0.id == id && $0.isTouching }) else { return false }
        return isPalmSized(point)
    }

    private mutating func fireIfDue(at time: TimeInterval) -> Bool {
        guard let deadline, time >= deadline else { return false }
        candidate = nil
        return true
    }
}
