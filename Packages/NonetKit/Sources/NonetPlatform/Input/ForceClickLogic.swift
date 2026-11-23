// 担当: platform-input
// 強く長押しで9マスを開くための、トラックパッドの左クリックの預かり（docs/architecture.md §5「開く」）。
// CGEvent に触れず、テストできるようにしてある。時刻（now）はどれも同じ単調な時計の秒
import CoreGraphics
import Foundation

/// トラックパッドで押した左クリックを、強く押し込んで止めたかが分かるまで前面のアプリに渡さずに預かる。
/// 強く押し込んで止めたら9マスを開き、そのクリックは捨てる（ポインタの下のボタンやリンクを押さない）。
/// そうでなければ、押下をそのまま返す:
/// - 離した: 押下と離すを続けて返す（ふつうのクリック。アプリに届くのが押したときから離したときに変わるだけ）
/// - slop より動かした: 押下と、その動きを返す（ドラッグや範囲の選択）
/// - 強く押し込まないまま lightPressLimit 押し続けた: 押下を返す（押したままのメニューなど。その分だけ遅れる）
struct ForceClickHolder: Equatable {
    /// 強く押し込まないまま、これだけ押し続けたら押下を返す（秒）。強く押す人は 0.2〜0.4 秒で押し込む
    static let lightPressLimit: TimeInterval = 0.6
    /// 押したまま、これより動かしたら押下を返す（ポイント）。押し込むときの指のずれではドラッグにしない
    static let slop: CGFloat = 6

    struct Held: Equatable {
        /// 押した時刻と位置（グローバル座標）
        var downAt: TimeInterval
        var location: CGPoint
        /// 強めのクリックの2段目まで押し込んだ時刻（まだなら nil）
        var forceAt: TimeInterval?
    }

    enum Phase: Equatable {
        /// 預かっていない
        case idle
        /// 押下を預かり、強く押し込んで止めるのを待っている
        case holding(Held)
        /// 止め終えて、開くかどうかの答え（finish）を待っている。待つ間に離したら upArrived
        case deciding(Held, upArrived: Bool)
        /// 開いた: このクリックの離すを捨て、押したままの動きはボタンを押していない移動として渡す
        case consumed
    }

    /// イベント1つの扱い
    enum Decision: Equatable {
        case pass
        case drop
        /// ボタンを押していない移動として渡す
        case passAsMove
        /// 預かった押下を返す: 今のイベントは捨て、押下の写しを送ってから、今のイベントの写しを送る
        case giveBackWithCurrent
    }

    /// 時間が来たときにすること
    enum TickOutcome: Equatable {
        case none
        /// 預かった押下を返す（強く押し込まないまま押し続けた）
        case giveBack
        /// 強く押し込んで止めた: 開くかどうかを聞く（finish で答えてもらう）
        case requestOpen
    }

    /// 預かったクリックを片付けるときにすること
    enum ReturnOutcome: Equatable {
        case none
        /// 預かった押下を返す。withUp なら、続けて離すも送る（離したのを捨てた・もう離れている）
        case giveBack(withUp: Bool)
    }

    private(set) var phase: Phase = .idle

    /// 押下を預かっている・答えを待っている・開いたクリックの離すを待っている
    var isActive: Bool { phase != .idle }

    /// 押下を預かっていて、強めのクリックの2段目まで押し込んである（止め終えるのを待っている）
    var isForcePressed: Bool {
        if case .holding(let held) = phase { return held.forceAt != nil }
        return false
    }

    /// 預かっている押下の位置（返すときに離すを作る）
    var heldLocation: CGPoint? {
        switch phase {
        case .holding(let held), .deciding(let held, _): held.location
        case .idle, .consumed: nil
        }
    }

    /// トラックパッドの左ボタンの押下。canHold（強く長押しで開ける・トラックパッドに触れている・開いていない）のときだけ預かる
    mutating func leftDown(at location: CGPoint, now: TimeInterval, canHold: Bool) -> Decision {
        // 前のクリックの離すを取りこぼしていても、新しい押下で前の対は終わっている
        phase = .idle
        guard canHold, location.x.isFinite, location.y.isFinite else { return .pass }
        phase = .holding(Held(downAt: now, location: location, forceAt: nil))
        return .drop
    }

    mutating func leftDragged(to location: CGPoint) -> Decision {
        switch phase {
        case .idle:
            return .pass
        case .holding(let held):
            guard Self.distance(from: held.location, to: location) > Self.slop else { return .drop }
            phase = .idle
            return .giveBackWithCurrent
        case .deciding:
            // 答えはすぐ来る。返すことになったら、押下の後のこの動きは次の動きで追いつく
            return .drop
        case .consumed:
            return .passAsMove
        }
    }

    mutating func leftUp() -> Decision {
        switch phase {
        case .idle:
            return .pass
        case .holding:
            phase = .idle
            return .giveBackWithCurrent
        case .deciding(let held, _):
            phase = .deciding(held, upArrived: true)
            return .drop
        case .consumed:
            phase = .idle
            return .drop
        }
    }

    /// 感圧のイベント。stage は NSEvent.stage（1: ふつうのクリック、2: 強めのクリック）。
    /// 預かっている間は前面のアプリに渡さない（押下の無い感圧を渡さないため）
    mutating func pressure(stage: Int, now: TimeInterval) -> Decision {
        switch phase {
        case .idle:
            return .pass
        case .holding(var held):
            if stage >= 2, held.forceAt == nil {
                held.forceAt = now
                phase = .holding(held)
            }
            return .drop
        case .deciding, .consumed:
            return .drop
        }
    }

    /// 次に tick がほしい時刻。hold は強く押し込んでから止める秒数（ForcePress.hold）
    func nextDeadline(hold: TimeInterval) -> TimeInterval? {
        guard case .holding(let held) = phase else { return nil }
        if let forceAt = held.forceAt { return forceAt + max(hold, 0) }
        return held.downAt + Self.lightPressLimit
    }

    /// now までに来た時間を処理する。期限ちょうどは「来た」とみなす
    mutating func tick(now: TimeInterval, hold: TimeInterval) -> TickOutcome {
        guard case .holding(let held) = phase, let deadline = nextDeadline(hold: hold), now >= deadline else { return .none }
        if held.forceAt != nil {
            phase = .deciding(held, upArrived: false)
            return .requestOpen
        }
        phase = .idle
        return .giveBack
    }

    /// 開くかどうかの答え。開いたらクリックを捨て、開かなかったら預かった押下を前面のアプリに返す
    mutating func finish(opened: Bool) -> ReturnOutcome {
        guard case .deciding(_, let upArrived) = phase else { return .none }
        if opened {
            phase = upArrived ? .idle : .consumed
            return .none
        }
        phase = .idle
        return .giveBack(withUp: upArrived)
    }

    /// 預かるのをやめる（強く長押しで開くのを切った・タップが無効にされた・止める）。
    /// 預かっている押下は返し、ボタンがもう離れていれば（isPressed が false）離すも送る
    mutating func returnAll(isPressed: Bool) -> ReturnOutcome {
        switch phase {
        case .idle:
            return .none
        case .consumed:
            phase = .idle
            return .none
        case .holding:
            phase = .idle
            return .giveBack(withUp: !isPressed)
        case .deciding(_, let upArrived):
            phase = .idle
            return .giveBack(withUp: upArrived || !isPressed)
        }
    }

    /// 開いたクリックの離すを待っているが、ボタンがもう離れている（離すを取りこぼした）: 待つのをやめる
    mutating func forgetConsumedIfReleased(isPressed: Bool) {
        if phase == .consumed, !isPressed {
            phase = .idle
        }
    }

    private static func distance(from a: CGPoint, to b: CGPoint) -> CGFloat {
        guard b.x.isFinite, b.y.isFinite else { return 0 }
        return hypot(b.x - a.x, b.y - a.y)
    }
}
