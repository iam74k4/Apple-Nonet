// 担当: platform-input
// MultitouchSupport から届いたフレームを TouchFrame にしてメインスレッドへ渡すまでの、ハードウェアに触れない部分
import Foundation
import NonetCore
import os

/// MultitouchSupport の接触点のうち、Nonet が使う値
struct MultitouchContact: Equatable, Sendable {
    var identifier: Int32
    /// 1-2: 近接, 3: 接触開始, 4: 接触中, 5: 離れる, 6-7: 範囲外
    var state: Int32
    /// 0〜1。y は手前が 0
    var x: Float
    var y: Float
    /// 接触の楕円の長径（CMTTouch.majorAxis）。0 以下・NaN なら分からないとみなす
    var majorAxis: Float = 0

    static let touchingStates: ClosedRange<Int32> = 3...4

    var isTouching: Bool { Self.touchingStates.contains(state) }
}

extension TouchPoint {
    /// 座標は 0〜1 に収める。NaN などの壊れた値なら nil
    init?(contact: MultitouchContact) {
        guard contact.x.isFinite, contact.y.isFinite else { return nil }
        self.init(
            id: Int(contact.identifier),
            x: Double(min(max(contact.x, 0), 1)),
            y: Double(min(max(contact.y, 0), 1)),
            isTouching: contact.isTouching,
            majorAxis: contact.majorAxis.isFinite && contact.majorAxis > 0 ? Double(contact.majorAxis) : nil
        )
    }

    static func points(from contacts: some Sequence<MultitouchContact>) -> [TouchPoint] {
        contacts.compactMap(TouchPoint.init(contact:))
    }
}

extension TouchFrame {
    /// 触れている指の ID（並びは届いた順）
    var touchingIDs: [Int] { points.filter(\.isTouching).map(\.id) }
}

/// MultitouchSupport のデバイス
struct MultitouchDeviceInfo: Equatable, Sendable {
    var id: UInt64
    var familyID: Int32
    var isBuiltIn: Bool
    /// 単位は 0.01mm。取れなければ 0
    var surfaceWidth: Int32 = 0
    var surfaceHeight: Int32 = 0

    /// Magic Mouse もマルチタッチのデバイスとして見えるので外す（112: Magic Mouse, 113: Magic Mouse 2）
    static let mouseFamilyIDs: Set<Int32> = [112, 113]

    /// 内蔵はマウスではあり得ないので、family ID に関係なくトラックパッドとみなす
    var isTrackpad: Bool { isBuiltIn || !Self.mouseFamilyIDs.contains(familyID) }

    /// 使うデバイス。トラックパッドだけを、内蔵を先にして並べる
    static func usable(_ devices: [MultitouchDeviceInfo]) -> [MultitouchDeviceInfo] {
        let trackpads = devices.filter(\.isTrackpad)
        return trackpads.filter(\.isBuiltIn) + trackpads.filter { !$0.isBuiltIn }
    }
}

/// 複数のデバイスがあるとき、指が触れているデバイスのフレームだけを通す。2台の指を1フレームに混ぜない
struct TouchDeviceSelector: Sendable {
    struct Decision: Equatable, Sendable {
        var deliver: Bool
        /// 前のデバイスの指が離れたことにするフレームを先に渡す（抜かれたなどで、離れたフレームが来なかった）
        var liftPrevious = false

        static let drop = Decision(deliver: false)
    }

    /// これだけフレームが来なければ、そのデバイスの指は離れたものとみなす
    var staleInterval: TimeInterval = 0.5
    private(set) var activeDevice: UInt64?
    private var lastActiveFrame: TimeInterval = 0

    mutating func accept(device: UInt64, touchingCount: Int, at time: TimeInterval) -> Decision {
        var liftPrevious = false
        if let active = activeDevice, active != device {
            guard time - lastActiveFrame > staleInterval, touchingCount > 0 else { return .drop }
            activeDevice = nil
            liftPrevious = true
        }
        if activeDevice != nil {
            lastActiveFrame = time
            if touchingCount == 0 { activeDevice = nil }
            return Decision(deliver: true)
        }
        // どのデバイスも使っていないときは、指が触れたフレームから使い始める
        guard touchingCount > 0 else { return .drop }
        activeDevice = device
        lastActiveFrame = time
        return Decision(deliver: true, liftPrevious: liftPrevious)
    }

    mutating func reset() {
        activeDevice = nil
    }
}

/// メインスレッドが遅れたときにフレームをまとめる。触れている指の組み合わせが同じ間は、
/// その最初のフレームと最新のフレームだけを残す（指を置いた時刻と今の位置は失わない）。
/// 指が増えた・減ったフレームは残すので、短いタップも取りこぼさない。上限を超えたら古いものから捨てる
struct TouchFrameCoalescer: Sendable {
    let capacity: Int
    private var pending: [(frame: TouchFrame, ids: [Int])] = []

    init(capacity: Int) {
        self.capacity = max(2, capacity)
    }

    var count: Int { pending.count }

    mutating func push(_ frame: TouchFrame) {
        let ids = frame.touchingIDs
        let n = pending.count
        if n >= 2, pending[n - 1].ids == ids, pending[n - 2].ids == ids {
            pending[n - 1] = (frame, ids)
        } else {
            pending.append((frame, ids))
            if pending.count > capacity {
                pending.removeFirst(pending.count - capacity)
            }
        }
    }

    mutating func drain() -> [TouchFrame] {
        defer { pending.removeAll(keepingCapacity: true) }
        return pending.map(\.frame)
    }

    mutating func removeAll() {
        pending.removeAll()
    }
}

/// MultitouchSupport のスレッドで受けたフレームを選んでまとめ、メインスレッドでまとめて受け取る。
/// 受け取りの予約（scheduleDrain）は、前の予約が受け取られるまで1回だけ
final class TouchPipeline: @unchecked Sendable {
    private struct State: Sendable {
        var selector: TouchDeviceSelector
        var coalescer: TouchFrameCoalescer
        var drainScheduled = false
        var lastDevice: UInt64?
    }

    private let state: OSAllocatedUnfairLock<State>
    private let scheduleDrain: @Sendable () -> Void

    init(capacity: Int = 32, staleInterval: TimeInterval = 0.5, scheduleDrain: @escaping @Sendable () -> Void) {
        var selector = TouchDeviceSelector()
        selector.staleInterval = staleInterval
        state = OSAllocatedUnfairLock(initialState: State(selector: selector, coalescer: TouchFrameCoalescer(capacity: capacity)))
        self.scheduleDrain = scheduleDrain
    }

    /// どのスレッドから呼んでもよい
    func receive(deviceID: UInt64, points: [TouchPoint], timestamp: TimeInterval) {
        let touchingCount = points.reduce(0) { $0 + ($1.isTouching ? 1 : 0) }
        let shouldSchedule = state.withLock { state -> Bool in
            let decision = state.selector.accept(device: deviceID, touchingCount: touchingCount, at: timestamp)
            guard decision.deliver else { return false }
            if decision.liftPrevious {
                state.coalescer.push(TouchFrame(timestamp: timestamp, points: []))
            }
            state.coalescer.push(TouchFrame(timestamp: timestamp, points: points))
            state.lastDevice = deviceID
            guard !state.drainScheduled else { return false }
            state.drainScheduled = true
            return true
        }
        if shouldSchedule { scheduleDrain() }
    }

    /// たまったフレームと、最後にフレームを通したデバイス
    func drain() -> (frames: [TouchFrame], device: UInt64?) {
        state.withLock { state in
            state.drainScheduled = false
            return (state.coalescer.drain(), state.lastDevice)
        }
    }

    /// デバイスを開始し直すとき。予約済みの受け取りはそのまま（新しいフレームを受け取る）
    func reset() {
        state.withLock { state in
            state.selector.reset()
            state.coalescer.removeAll()
            state.lastDevice = nil
        }
    }
}

/// デバイスを開始し直す時機を決める。開始し直すと、触れていた指はフレームが途切れて離れたように見える。
/// 指が触れている間の抜き差し（Magic Mouse の再接続など、触れているデバイスとは関係ないことが多い）では、
/// 指が離れるまで待つ。触れているデバイスが無くなった・止まったときと、スリープからの復帰では、
/// すぐに開始し直して、先に指が離れたことにする（エンジンが指を置いたままだと思い込まないように）
struct MultitouchRestartPlanner: Sendable {
    enum Reason: Equatable, Sendable {
        case start
        case hotPlug
        case wake
        /// ログインし直した・ユーザーの切り替えから戻った
        case sessionActive
        /// ディスプレイの構成が変わった（蓋を閉じた・外部ディスプレイの抜き差し）・ディスプレイがスリープから戻った
        case display
        /// 開始できなかったデバイスを、間を置いて開始し直す
        case retry
        /// 一覧を見直したら、開始しようとしたデバイスと違っていた（抜き差しの通知を取りこぼした）
        case deviceListChanged

        /// 指が触れていても待たずに開始し直す。それ以外は、触れているデバイスとは関係ないことが多いので指が離れるまで待つ
        var isUnconditional: Bool {
            switch self {
            case .start, .wake, .sessionActive: true
            case .hotPlug, .display, .retry, .deviceListChanged: false
            }
        }

        var logName: String {
            switch self {
            case .start: "開始"
            case .hotPlug: "抜き差し"
            case .wake: "スリープからの復帰"
            case .sessionActive: "ユーザーの切り替えからの復帰"
            case .display: "ディスプレイの変化"
            case .retry: "再試行"
            case .deviceListChanged: "一覧の変化"
            }
        }
    }

    enum Decision: Equatable, Sendable {
        /// liftFirst: 指が離れたことにするフレームを先に渡す
        case restart(liftFirst: Bool)
        /// 指が離れてから、もう一度確かめる
        case waitForLift
    }

    /// これだけフレームが来なければ、触れていたデバイスは止まったものとみなす
    let staleInterval: TimeInterval
    /// 予約している開始し直しの理由
    private(set) var pendingReason: Reason?
    /// 最後に渡したフレームで指が触れていた
    private(set) var isTouching = false
    /// 最後にフレームを渡したデバイス
    private(set) var activeDevice: UInt64?
    private var lastFrameTime: TimeInterval = 0

    init(staleInterval: TimeInterval = 0.5) {
        self.staleInterval = staleInterval
    }

    /// 開始し直しを頼む。待っている理由と重なったら、待たずに開始し直す方を残す
    @discardableResult
    mutating func request(_ reason: Reason) -> Reason {
        let merged = pendingReason.map { $0.isUnconditional ? $0 : reason } ?? reason
        pendingReason = merged
        return merged
    }

    /// エンジンにフレームを渡した。device が nil なら（作ったフレーム）デバイスは変えない
    mutating func delivered(_ frame: TouchFrame, from device: UInt64?) {
        isTouching = !frame.touching.isEmpty
        if let device { activeDevice = device }
        lastFrameTime = frame.timestamp
    }

    /// 予約した時刻になった。connectedDevices はいまつながっているデバイスの ID
    mutating func decide(connectedDevices: Set<UInt64>, now: TimeInterval) -> Decision {
        let reason = pendingReason ?? .hotPlug
        if isTouching, !reason.isUnconditional, let activeDevice, connectedDevices.contains(activeDevice),
           now - lastFrameTime <= staleInterval {
            return .waitForLift
        }
        pendingReason = nil
        return .restart(liftFirst: isTouching)
    }

    mutating func reset() {
        self = MultitouchRestartPlanner(staleInterval: staleInterval)
    }
}

/// デバイスを開始し直した後の見張り。開始できなかったデバイスは間隔を延ばしながら開始し直し、
/// 一覧が変わっていれば（抜き差しの通知を取りこぼしても）開始し直す。どれも安く済むように間隔を置く
struct MultitouchRecovery: Sendable {
    /// 使えるはずのデバイスの一部を開始できなかったとき、次に開始し直すまでの秒数。最後の値で繰り返す
    static let retryDelays: [TimeInterval] = [1, 3, 10, 30, 60]
    /// デバイスの一覧を見直す間隔
    static let listCheckInterval: TimeInterval = 10

    /// 最後に開始しようとしたデバイス
    private(set) var attempted: Set<UInt64> = []
    /// 続けて一部のデバイスを開始できなかった回数
    private(set) var failures = 0

    /// 開始し直した。開始できなかったデバイスがあれば、次に開始し直すまでの秒数を返す
    mutating func restarted(attempted ids: [UInt64], started: [UInt64], at time: TimeInterval) -> TimeInterval? {
        let next = Set(ids)
        // 別の組み合わせになったら、数え直す
        if next != attempted { failures = 0 }
        attempted = next
        guard !next.isSubset(of: Set(started)) else {
            failures = 0
            return nil
        }
        let delay = Self.retryDelays[min(failures, Self.retryDelays.count - 1)]
        failures += 1
        return delay
    }

    /// 一覧を見直した。listed はいま使えるデバイス。開始しようとしたものと違えば開始し直す
    func needsRestart(listed: [UInt64]) -> Bool {
        Set(listed) != attempted
    }

    mutating func reset() {
        self = MultitouchRecovery()
    }
}
