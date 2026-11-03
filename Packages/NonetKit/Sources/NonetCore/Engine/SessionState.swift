// 担当: engine
// SessionEngine の1セッション分の状態と、操作の仕様（docs/architecture.md の 5.）の規則
import Foundation

private struct SwipeBaseline: Sendable {
    var fingerIDs: [Int]
    var x: Double
}

/// 1回のセッション。開いたときに触れていた指のタッチ1つで、すべての指が離れたら終える
struct SessionState: Sendable {
    private let configuration: SessionConfiguration
    private let grid: GridMapper
    private let start: TimeInterval
    /// 開いたタッチの最初の指が触れた時刻（遅れて届くクリックの判断に使う）
    private let touchStart: TimeInterval
    private(set) var page = 0
    private var endReason: SessionEndReason?
    /// HUD を出している（開いてから、閉じるまで）
    private var isHUDVisible = false
    /// 最後に HUD に出した中身（変わったときだけ updateHUD を出す）
    private var shownState: SessionHUDState?
    /// 選んでいる指（最後に置いた指）と、その場所（外枠かマス）・最後の位置
    private var fingerID: Int?
    private var zone: GridZone?
    private var lastPosition: FingerTracker.Finger?
    /// zone になった時刻。そこに留まった時間を測る
    private var zoneSince: TimeInterval
    /// 少し長く止めるマスを止め終えたと HUD に知らせた
    private var isHoldReady = false
    /// 2本以上の指が触れている
    private var isMultiFinger = false
    /// 2本以上の指の間にページを切り替えた（1回のスワイプで1ページ）。端で止まったときも含む
    private var hasTurnedPage = false
    private var swipeBaseline: SwipeBaseline?
    /// 2本以上から1本指に戻った後、残った指を滑らせるのを待っている（滑らせるまでは離しても実行しない）。測り始めた位置
    private var reselectAnchor: FingerTracker.Finger?
    /// 開いたときの指の位置。ここから openTravel 滑らせるまでは上の外枠にいることにする（開いた瞬間に離せば、必ず何もせずに閉じる）
    private var openAnchor: FingerTracker.Finger?
    /// 指が止まっている左右の外枠（そちらにページがあるときだけ）。止め続けるとページを切り替える
    private var pagingEdge: PageEdge?
    /// pagingEdge に入った時刻か、前に切り替えた時刻。外枠の中で edgeRestTravel より動かしたときも数え直す
    private var edgeSince: TimeInterval
    /// 止めている位置（edgeSince に数え始めたときの指の位置）
    private var edgeAnchor: FingerTracker.Finger?
    /// pagingEdge に止めたまま切り替えた回数（2回目からは edgePageRepeat ごと）
    private var edgeTurns = 0
    /// すべての指が離れた時刻（遅れて届くクリックの判断に使う）
    private var lastLiftAt: TimeInterval?

    /// configuration は sanitized 済みのもの。触れている指が無ければ nil（開けない）
    init?(configuration: SessionConfiguration, start: TimeInterval, tracker: FingerTracker) {
        guard tracker.isTouching else { return nil }
        self.configuration = configuration
        grid = configuration.grid
        self.start = start
        touchStart = tracker.gestureStart
        zoneSince = start
        edgeSince = start
        isMultiFinger = tracker.count >= 2
        if !isMultiFinger, let finger = tracker.lastPlaced {
            fingerID = finger.id
            lastPosition = finger
            // 開いた瞬間は外枠にいる（開く動きの直後の指が、もう上の段のマスに入っていても選ばない）
            zone = .frame
            openAnchor = finger
            pagingEdge = availableEdge(at: finger)
            edgeAnchor = pagingEdge == nil ? nil : finger
        }
    }

    var isEnded: Bool { endReason != nil }

    var hudState: SessionHUDState {
        let shown = isMultiFinger ? nil : zone
        // 2本指から1本指に戻った後は、滑らせ直すまで離しても実行しない（reselectAnchor）ので、マスを光らせない
        let cell = reselectAnchor == nil ? shown?.cell : nil
        return SessionHUDState(
            page: page,
            highlightedCell: cell,
            isInFrame: shown == .frame,
            hold: cell.flatMap { isHoldCell($0) ? SessionHold(cell: $0, since: zoneSince, duration: configuration.holdDwell, isReady: isHoldReady) : nil },
            edgePaging: isMultiFinger ? nil : pagingEdge.map { SessionEdgePaging(edge: $0, since: edgeSince, duration: edgeDuration) }
        )
    }

    private var timeoutAt: TimeInterval { start + configuration.maxDuration }

    /// 少し長く止めるマスを止め終える時刻。止め終えた・そのマスにいなければ nil
    private var holdDeadline: TimeInterval? {
        guard !isHoldReady, !isMultiFinger, reselectAnchor == nil, let cell = zone?.cell, isHoldCell(cell) else { return nil }
        return zoneSince + configuration.holdDwell
    }

    /// 左右の外枠に止めてから、ページを切り替えるまでの秒数（切り替えた後も止めていれば edgePageRepeat）
    private var edgeDuration: TimeInterval {
        edgeTurns == 0 ? configuration.edgePageDwell : configuration.edgePageRepeat
    }

    /// 左右の外枠に止めた指で、ページを切り替える時刻。止めていなければ nil
    private var edgeDeadline: TimeInterval? {
        guard !isMultiFinger, pagingEdge != nil else { return nil }
        return edgeSince + edgeDuration
    }

    /// 次に tick がほしい時刻
    var nextDeadline: TimeInterval? {
        guard endReason == nil else { return nil }
        return [holdDeadline, edgeDeadline, timeoutAt].compactMap { $0 }.min()
    }

    // MARK: 開く・時間

    /// 開いた: ポインタの抑止を始め、HUD をすぐに出して指の下の場所を見せ、触覚で知らせる
    mutating func open(effects: inout [SessionEffect]) {
        effects.append(.beginPointerSuppression)
        isHUDVisible = true
        shownState = hudState
        effects.append(.showHUD(hudState))
        effects.append(.haptic(.activation))
    }

    /// HUD の中身が変わっていれば updateHUD を出す。変わったら true
    @discardableResult
    private mutating func refreshHUD(effects: inout [SessionEffect]) -> Bool {
        let state = hudState
        guard isHUDVisible, state != shownState else { return false }
        shownState = state
        effects.append(.updateHUD(state))
        return true
    }

    private mutating func hideHUD(effects: inout [SessionEffect]) {
        guard isHUDVisible else { return }
        isHUDVisible = false
        shownState = nil
        effects.append(.hideHUD)
    }

    /// now までに期限が来たものを処理する。期限ちょうどは「来た」とみなす
    mutating func fireDeadlines(now: TimeInterval, effects: inout [SessionEffect]) {
        guard endReason == nil else { return }
        if now >= timeoutAt {
            end(.timeout, now: now, effects: &effects)
            return
        }
        if let deadline = holdDeadline, now >= deadline {
            // 止め終えた: いま離すと実行することを HUD と触覚で知らせる
            isHoldReady = true
            refreshHUD(effects: &effects)
            effects.append(.haptic(.holdReady))
        }
        if let deadline = edgeDeadline, now >= deadline {
            turnPageAtEdge(now: now, effects: &effects)
        }
    }

    /// 左右の外枠に止め続けた: 右なら次、左なら前のページにする。端のページまで来たら、それ以上は待たない
    private mutating func turnPageAtEdge(now: TimeInterval, effects: inout [SessionEffect]) {
        guard let edge = pagingEdge else { return }
        page = min(max(edge == .right ? page + 1 : page - 1, 0), configuration.pageCount - 1)
        edgeTurns += 1
        edgeSince = now
        pagingEdge = availableEdge(edge)
        if pagingEdge == nil { edgeAnchor = nil }
        refreshHUD(effects: &effects)
        effects.append(.haptic(.pageChange))
    }

    /// その側にページがあれば edge、無ければ nil
    private func availableEdge(_ edge: PageEdge?) -> PageEdge? {
        switch edge {
        case .left?: page > 0 ? .left : nil
        case .right?: page < configuration.pageCount - 1 ? .right : nil
        case nil: nil
        }
    }

    /// finger が左右の外枠（9マスの行の横）にあり、そちらにページがあればその側
    private func availableEdge(at finger: FingerTracker.Finger) -> PageEdge? {
        guard zone == .frame else { return nil }
        return availableEdge(grid.pagingEdge(x: finger.x, y: finger.y))
    }

    /// HUD を閉じ、ポインタの抑止をやめて終える
    mutating func end(_ reason: SessionEndReason, now: TimeInterval, effects: inout [SessionEffect]) {
        guard endReason == nil else { return }
        hideHUD(effects: &effects)
        effects.append(.endPointerSuppression(dropsLateClicks: mayClickLate(at: now)))
        effects.append(.sessionEnded(reason))
        endReason = reason
    }

    /// now に終えると、指の「タップでクリック」が抑止の後に届きうるか（SessionEngine.lateClickWindow）。
    /// まだ触れている指は、置いてから長ければタップにならない
    private func mayClickLate(at now: TimeInterval) -> Bool {
        let window = SessionEngine.lateClickWindow
        if lastLiftAt == nil, now - touchStart < window { return true }
        if let lastLiftAt, now - lastLiftAt < window { return true }
        return false
    }

    // MARK: トラックパッド

    mutating func apply(_ change: FingerTracker.Change, tracker: FingerTracker, now: TimeInterval, effects: inout [SessionEffect]) {
        guard endReason == nil else { return }
        switch change {
        case .none, .began:
            // セッション中は触れているので began は来ない（来ても新しいタッチとしては扱わない）
            return
        case .ended, .restarted:
            // 離すと同時に置いた指（restarted）は、セッションの外の新しいタッチになる
            lift(now: now, effects: &effects)
        case .moved:
            if tracker.count >= 2 {
                followSeveralFingers(tracker, effects: &effects)
            } else if let finger = tracker.lastPlaced {
                followOneFinger(finger, now: now, effects: &effects)
            }
        }
    }

    /// 2本以上の指: ハイライトを消し（実行しないマスを光らせない）、2本指の横のスワイプでページを変える
    private mutating func followSeveralFingers(_ tracker: FingerTracker, effects: inout [SessionEffect]) {
        if !isMultiFinger {
            isMultiFinger = true
            hasTurnedPage = false
            pagingEdge = nil
            edgeAnchor = nil
            refreshHUD(effects: &effects)
        }
        guard tracker.count == 2 else {
            swipeBaseline = nil
            return
        }
        let fingers = tracker.fingers
        // 2本がそろった時点（指が入れ替わったら、その時点）の平均を起点にする
        let ids = fingers.map(\.id).sorted()
        if swipeBaseline?.fingerIDs != ids {
            swipeBaseline = SwipeBaseline(fingerIDs: ids, x: Self.averageX(fingers))
            return
        }
        guard let baseline = swipeBaseline, !hasTurnedPage else { return }
        let dx = Self.averageX(fingers) - baseline.x
        guard abs(dx) >= configuration.swipeThreshold else { return }
        hasTurnedPage = true
        // Launchpad などと同じく、指を左へ動かすと次のページ
        let target = min(max(dx < 0 ? page + 1 : page - 1, 0), configuration.pageCount - 1)
        let didChange = target != page
        page = target
        if didChange {
            refreshHUD(effects: &effects)
        }
        effects.append(.haptic(didChange ? .pageChange : .rejected))
    }

    /// 1本指: 外枠かマスかを追い、変わったら HUD と境界の触覚で知らせる。
    /// 2本以上から戻った・指が入れ替わったら、ヒステリシス無しで測り直す（触覚は鳴らさない）
    private mutating func followOneFinger(_ finger: FingerTracker.Finger, now: TimeInterval, effects: inout [SessionEffect]) {
        let previous = isMultiFinger ? nil : zone
        let isNewFinger = isMultiFinger || finger.id != fingerID
        if isNewFinger {
            // 2本以上から1本指に戻った（ページを変えた後など）: 残った指でまた選べる。
            // 選ぶには滑らせ直す（2本の指は同時に離れにくく、残った指の下のマスを選んだとはみなさない）
            if isMultiFinger {
                reselectAnchor = finger
            }
            isMultiFinger = false
            hasTurnedPage = false
            swipeBaseline = nil
            fingerID = finger.id
        }
        lastPosition = finger
        var next = grid.zone(x: finger.x, y: finger.y, current: isNewFinger ? nil : zone)
        if let anchor = openAnchor {
            if !isNewFinger, hypot(finger.x - anchor.x, finger.y - anchor.y) <= SessionConfiguration.openTravel {
                next = .frame
            } else {
                openAnchor = nil
            }
        }
        if next != zone || isNewFinger {
            zone = next
            zoneSince = now
            isHoldReady = false
        }
        if let anchor = reselectAnchor, hypot(finger.x - anchor.x, finger.y - anchor.y) > SessionConfiguration.reselectTravel {
            // 滑らせ直した: ここから留まる時間を数える（少し長く止めるマスの進み具合も最初から）
            reselectAnchor = nil
            zoneSince = now
            isHoldReady = false
        }
        // 左右の外枠に入った・出た・反対の側へ移った、または外枠の中で動かした: ページを切り替えるまでの時間を最初から数える
        let edge = availableEdge(at: finger)
        if edge != pagingEdge {
            pagingEdge = edge
            edgeSince = now
            edgeTurns = 0
            edgeAnchor = edge == nil ? nil : finger
        } else if edge != nil, let anchor = edgeAnchor,
                  hypot(finger.x - anchor.x, finger.y - anchor.y) > SessionConfiguration.edgeRestTravel {
            edgeSince = now
            edgeTurns = 0
            edgeAnchor = finger
        }
        guard refreshHUD(effects: &effects) else { return }
        // 仕様: マスとマス・マスと外枠の境目をまたぐたびに。指を置き直した・2本指から戻っただけでは鳴らさない
        if !isNewFinger, let previous, previous != next {
            effects.append(.haptic(.boundary))
        }
    }

    private static func averageX(_ fingers: [FingerTracker.Finger]) -> Double {
        fingers.reduce(0) { $0 + $1.x } / Double(max(fingers.count, 1))
    }

    // MARK: 離す・実行

    /// すべての指が離れた。光っているマスに留まる時間だけ留まって1本指で離したなら、そのマスを実行する。
    /// そうでなければ何もせずに rejected の触覚で知らせる（外枠で離すのが、やめる操作）
    private mutating func lift(now: TimeInterval, effects: inout [SessionEffect]) {
        lastLiftAt = now
        let outcome = liftOutcome(now: now)
        switch outcome {
        case .success(let cell):
            hideHUD(effects: &effects)
            effects.append(.execute(page: page, cell: cell))
            end(.released, now: now, effects: &effects)
        case .failure(let cancellation):
            effects.append(.haptic(.rejected))
            end(.cancelled(cancellation.reason), now: now, effects: &effects)
        }
    }

    private struct Cancel: Error {
        var reason: SessionCancellation
    }

    private func liftOutcome(now: TimeInterval) -> Result<Int, Cancel> {
        if isMultiFinger { return .failure(Cancel(reason: .liftedWithSeveralFingers)) }
        guard let zone, let cell = zone.cell else { return .failure(Cancel(reason: .liftedInFrame)) }
        if isEmptyCell(cell) { return .failure(Cancel(reason: .liftedOnEmptyCell)) }
        // 少し長く止めるマスは、止め終えたと HUD と触覚で知らせた後なら、境目の近くでも実行する（狙ったマスで止めたことははっきりしている）
        let isHold = isHoldCell(cell)
        if !(isHold && isHoldReady), let position = lastPosition, grid.isInBoundaryBand(x: position.x, y: position.y) {
            return .failure(Cancel(reason: .liftedOnBoundary))
        }
        if reselectAnchor != nil { return .failure(Cancel(reason: .liftedWithoutSliding)) }
        // 止め終えた時刻は、進み具合の期限（holdDeadline）と同じ足し算で決める（HUD が止め終えたと見せたら、離せば必ず実行する）
        let readyAt = zoneSince + (isHold ? configuration.holdDwell : configuration.liftDwell)
        guard now >= readyAt || (isHold && isHoldReady) else { return .failure(Cancel(reason: .liftedTooSoon)) }
        return .success(cell)
    }

    /// 今のページで中身が無いと分かっているマス。分からなければ false（controller が判断する）
    private func isEmptyCell(_ cell: Int) -> Bool {
        guard let occupied = configuration.occupiedCells, occupied.indices.contains(page) else { return false }
        return !occupied[page].contains(cell)
    }

    /// 今のページで、少し長く止めてから実行するマス（Cell.requiresHold）。分からなければ false
    private func isHoldCell(_ cell: Int) -> Bool {
        guard let holds = configuration.holdCells, holds.indices.contains(page) else { return false }
        return holds[page].contains(cell)
    }
}
