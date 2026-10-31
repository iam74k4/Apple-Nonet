// 担当: engine
// SessionEngine の1セッション分の状態と、操作の仕様（docs/architecture.md の 5.）の規則
import Foundation

/// セッション中のタッチ（最初の指が触れてから、すべての指が離れるまで）。
/// トリガーより前から休めている指（restingFingers）があれば、その指を除いた指のタッチ
private struct SessionTouch: Sendable {
    /// 最初の指が触れた時刻
    var physicalStart: TimeInterval
    /// HUD を出すまでの待ち時間を数え始めた時刻。トリガーより前から置いていた指はトリガーの時刻
    var restStart: TimeInterval
    /// HUD を出していないときにセッション中に置いた指。1本のまま hudDelay 未満で離れたら速押し
    var isTapCandidate: Bool
    /// 置いた位置のマス（速押しと、HUD でのタップで実行するマス）
    var downCell: Int?
    /// 2本以上の指が触れたことがある。このタッチでは実行しない（仕様 9）
    var isMultiFinger: Bool
    /// このタッチでページを切り替えた（1回のスワイプで1ページ。仕様 8）。端で止まったときも含む
    var hasTurnedPage = false
    /// トリガーを押したときに触れていた指だけのタッチ（セッションの始めのタッチ）。休めている指も数え、
    /// 速押しにも HUD でのタップにもしない
    var isPreTrigger = false
    /// 最初に置いた指とその位置。HUD でのタップの移動量を測る
    var origin: FingerTracker.Finger?
    /// origin の指が、置いた位置から最も離れた距離
    var travel: Double = 0
}

private struct TrackedCell: Sendable {
    var fingerID: Int
    var cell: Int
}

private struct SwipeBaseline: Sendable {
    var fingerIDs: [Int]
    var x: Double
}

/// 角の長押しのセッションで、指を滑らせたか（滑らせずに離したらキャンセル）。
/// 測り始めた位置から CornerHoldRecognizer.movementTolerance より動いたら滑らせたとみなす
private struct CornerSlide: Sendable {
    /// 測り始めた指と位置（セッションの始まりと、2本以上から1本指に戻ったとき）
    private var anchor: FingerTracker.Finger?
    private(set) var hasMoved = false

    init(anchor: FingerTracker.Finger?) {
        self.anchor = anchor
    }

    /// 測り直す。滑らせていないことにする
    mutating func restart(at finger: FingerTracker.Finger?) {
        anchor = finger
        hasMoved = false
    }

    /// 1本だけ触れている指の位置
    mutating func follow(_ finger: FingerTracker.Finger?) {
        guard let finger, let anchor, anchor.id == finger.id else { return }
        if hypot(finger.x - anchor.x, finger.y - anchor.y) > CornerHoldRecognizer.movementTolerance {
            hasMoved = true
        }
    }
}

/// トリガーを離した後、置いたばかりの指が離れるのを待っている
private struct Drain: Sendable {
    var deadline: TimeInterval
    var reason: SessionEndReason
    /// 指が離れたら速押しとして実行してよい
    var allowsTap: Bool
}

struct SessionState: Sendable {
    private let configuration: SessionConfiguration
    private let grid: GridMapper
    private let start: TimeInterval
    private(set) var page = 0
    private var isHUDVisible = false
    private var highlight: Int?
    private var hasExecuted = false
    private var touch: SessionTouch?
    private var tracked: TrackedCell?
    private var swipeBaseline: SwipeBaseline?
    private var drain: Drain?
    private var endReason: SessionEndReason?
    /// このセッションで最後にタッチが離れた（すべての指が離れた）時刻。遅れて届くクリックの判断に使う
    private var lastLiftAt: TimeInterval?
    /// 角の長押しのセッションだけ
    private var slide: CornerSlide?
    /// トリガーより前から置いていて、まだ動かしていない指（id → 測り始めた位置）。トリガーキーのセッションだけ。
    /// ほかの指を置いたら数えず（親指を手前に休めたままタップできるように）、restingTolerance より動かしたらふつうの指にする
    private var restingFingers: [Int: FingerTracker.Finger] = [:]

    /// configuration は sanitized 済みのもの
    init(configuration: SessionConfiguration, start: TimeInterval, tracker: FingerTracker) {
        self.configuration = configuration
        self.grid = configuration.grid
        self.start = start
        // トリガーより前から置いていた指は速押しにしないが、位置はハイライトできる
        if tracker.isTouching {
            let isTriggerKey = configuration.activation == .triggerKey
            touch = SessionTouch(
                physicalStart: tracker.gestureStart,
                restStart: start,
                isTapCandidate: false,
                downCell: nil,
                isMultiFinger: tracker.gestureMaxFingers >= 2,
                isPreTrigger: isTriggerKey
            )
            if isTriggerKey {
                restingFingers = Dictionary(tracker.fingers.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
            }
            trackFinger(tracker)
        }
        if configuration.activation == .cornerHold {
            slide = CornerSlide(anchor: tracker.lastPlaced)
        }
    }

    var isEnded: Bool { endReason != nil }
    var isCornerHold: Bool { configuration.activation == .cornerHold }
    var isDraining: Bool { drain != nil }
    /// トリガーを離したときに決めた終わり方
    var releaseReason: SessionEndReason { drain?.reason ?? .released }

    var hudState: SessionHUDState? {
        isHUDVisible ? SessionHUDState(page: page, highlightedCell: highlight) : nil
    }

    private var timeoutAt: TimeInterval { start + configuration.maxDuration }

    /// 次に tick がほしい時刻
    func nextDeadline(now: TimeInterval) -> TimeInterval? {
        guard endReason == nil else { return nil }
        if let drain {
            return min(drain.deadline, timeoutAt)
        }
        var deadline = timeoutAt
        if !isHUDVisible {
            if let touch {
                deadline = min(deadline, touch.restStart + configuration.hudDelay)
            } else if !hasExecuted, start + configuration.placementWindow > now {
                deadline = min(deadline, start + configuration.placementWindow)
            }
        }
        return deadline
    }

    // MARK: 時間

    /// now までに期限が来たものを処理する。期限ちょうどは「来た」とみなす
    mutating func fireDeadlines(now: TimeInterval, effects: inout [SessionEffect]) {
        guard endReason == nil else { return }
        if let drain {
            if now >= timeoutAt, timeoutAt < drain.deadline {
                end(.timeout, now: now, effects: &effects)
            } else if now >= drain.deadline {
                end(drain.reason, now: now, effects: &effects)
            }
            return
        }
        if now >= timeoutAt {
            end(.timeout, now: now, effects: &effects)
            return
        }
        guard !isHUDVisible else { return }
        let isDue = if let touch {
            // 仕様 4 (b): 置いた指が hudDelay 以上触れたままになった
            now >= touch.restStart + configuration.hudDelay
        } else {
            // 仕様 4 (a)・6: 指を置かずに placementWindow が過ぎた。一度実行した後は出さない。
            // 待ち時間中に置いた指が実行せずに離れたときも、その時点で迷っているとみなして出す
            !hasExecuted && now >= start + configuration.placementWindow
        }
        if isDue {
            showHUD(effects: &effects)
        }
    }

    // MARK: 角の長押し

    /// 角の長押しで始めた。速押しの段階は無く、HUD をすぐに出して指の下のマスを光らせ、触覚で知らせる
    mutating func activateFromCorner(now: TimeInterval, effects: inout [SessionEffect]) {
        guard endReason == nil else { return }
        guard touch != nil else {
            // 長押しの指がもう離れていた。選ぶ指が無いので、何も出さずに終える
            end(.cancelled, now: now, effects: &effects)
            return
        }
        showHUD(effects: &effects)
        effects.append(.haptic(.activation))
    }

    /// 角の長押しのセッションのタッチ。セッションはこのタッチ1つで、すべての指が離れたら終える
    private mutating func applyCornerHold(_ change: FingerTracker.Change, tracker: FingerTracker, now: TimeInterval, effects: inout [SessionEffect]) {
        switch change {
        case .none:
            return
        case .ended, .restarted:
            // 離すと同時に置いた指（restarted）は、セッションの外の新しいタッチになる
            liftCornerHold(now: now, effects: &effects)
            return
        case .began, .moved:
            if tracker.count >= 2 {
                touch?.isMultiFinger = true
            } else if touch?.isMultiFinger == true {
                // 1本指に戻った（2本指のスワイプでページを変えた後など）: 残った指でまた選べ、次の2本指のスワイプでもページを変えられる。
                // 滑らせていないことにするので、すぐに離すとキャンセル（選ぶには、もう一度滑らせる）
                touch?.isMultiFinger = false
                touch?.hasTurnedPage = false
                slide?.restart(at: tracker.lastPlaced)
            }
        }
        follow(tracker, effects: &effects)
        if tracker.count == 1, touch?.isMultiFinger == false {
            slide?.follow(tracker.lastPlaced)
        }
    }

    /// すべての指が離れた。滑らせてから1本指で離したなら、光っているマスを実行する。
    /// 滑らせずに離した・2本以上で離した・空きマス（仕様 12）なら、何もせずにキャンセルとして終える
    private mutating func liftCornerHold(now: TimeInterval, effects: inout [SessionEffect]) {
        var reason = SessionEndReason.cancelled
        if let touch, !touch.isMultiFinger, slide?.hasMoved == true, let cell = highlight, !isEmptyCell(cell) {
            hideHUD(effects: &effects)
            execute(cell: cell, wasFastTap: false, effects: &effects)
            reason = .released
        } else if let touch, touch.isMultiFinger, !touch.hasTurnedPage {
            // 2本以上で離した（ページも変えていない）。受け付けなかったことを指に知らせる
            effects.append(.haptic(.rejected))
        }
        recordLift(now: now)
        tracked = nil
        swipeBaseline = nil
        end(reason, now: now, effects: &effects)
    }

    // MARK: キーボード

    mutating func releaseTrigger(now: TimeInterval, effects: inout [SessionEffect]) {
        // 角の長押しのセッションはトリガーを押していないので、離したイベントは関係ない
        guard endReason == nil, drain == nil, !isCornerHold else { return }
        var reason = SessionEndReason.released
        let wasHUDVisible = isHUDVisible
        if isHUDVisible {
            // 仕様 5: onTriggerRelease なら指を置いたまま離すとハイライト中のマスを実行。指を先に離していたらキャンセル
            let cell = configuration.fireMode == .onTriggerRelease && touch?.isMultiFinger == false ? highlight : nil
            hideHUD(effects: &effects)
            if let cell, !isEmptyCell(cell) {
                execute(cell: cell, wasFastTap: false, effects: &effects)
            } else {
                reason = .cancelled
            }
        }
        // 置いたばかりの指が残っていれば、離れるまで（最長 hudDelay）続ける。すぐに抑止をやめると
        // その指のタップがクリックとして前面アプリに届き、トリガーを指より少し先に離した速押しも取りこぼすため
        if let touch, now < touch.physicalStart + configuration.hudDelay {
            drain = Drain(
                deadline: touch.physicalStart + configuration.hudDelay,
                reason: reason,
                allowsTap: !wasHUDVisible && touch.isTapCandidate
            )
        } else {
            end(reason, now: now, effects: &effects)
        }
    }

    /// HUD を閉じ、ポインタの抑止をやめて終える
    mutating func end(_ reason: SessionEndReason, now: TimeInterval, effects: inout [SessionEffect]) {
        guard endReason == nil else { return }
        if isHUDVisible {
            hideHUD(effects: &effects)
        }
        effects.append(.endPointerSuppression(dropsLateClicks: mayClickLate(at: now)))
        effects.append(.sessionEnded(reason))
        endReason = reason
    }

    /// now に終えると、指の「タップでクリック」が抑止の後に届きうるか（SessionEngine.lateClickWindow）。
    /// まだ触れている指は、置いてから長ければタップにならない。トリガーより前から置いていた指も同じく数える
    private func mayClickLate(at now: TimeInterval) -> Bool {
        let window = SessionEngine.lateClickWindow
        if let touch, now - touch.physicalStart < window { return true }
        if let lastLiftAt, now - lastLiftAt < window { return true }
        return false
    }

    // MARK: トラックパッド

    mutating func apply(_ change: FingerTracker.Change, tracker: FingerTracker, now: TimeInterval, effects: inout [SessionEffect]) {
        guard endReason == nil else { return }
        if isCornerHold {
            applyCornerHold(change, tracker: tracker, now: now, effects: &effects)
            return
        }
        forgetLiftedRestingFingers(tracker)
        if let drain {
            applyWhileDraining(change, drain: drain, tracker: tracker, now: now, effects: &effects)
            return
        }
        /// 指を置いただけ（滑らせていない）なら、ハイライトが変わっても境界の触覚は鳴らさない（仕様 7）
        var placedNewTouch = false
        switch change {
        case .none:
            return
        case .began:
            beginTouch(tracker, now: now)
        case .moved:
            if startsTouchBesideRestingFingers(tracker) {
                // トリガーより前から休めている指のほかに置いた: その指だけの新しいタッチ（すぐにタップの候補）
                beginTouch(tracker, now: now)
                placedNewTouch = true
            } else if endsTouchBesideRestingFingers(tracker) {
                // このタッチの指がすべて離れ、休めている指だけが残った
                liftTouch(now: now, effects: &effects)
                reanchorRestingFingers(tracker)
                return
            } else {
                releaseMovedRestingFingers(tracker, now: now)
                let fingers = countedFingers(tracker)
                if fingers.count >= 2 {
                    touch?.isMultiFinger = true
                }
                measureTravel(fingers)
            }
        case .ended:
            liftTouch(now: now, effects: &effects)
            return
        case .restarted:
            liftTouch(now: now, effects: &effects)
            beginTouch(tracker, now: now)
        }
        follow(tracker, effects: &effects, buzzesOnBoundary: !placedNewTouch)
    }

    private mutating func applyWhileDraining(_ change: FingerTracker.Change, drain: Drain, tracker: FingerTracker, now: TimeInterval, effects: inout [SessionEffect]) {
        switch change {
        case .none, .began:
            return
        case .moved:
            guard endsTouchBesideRestingFingers(tracker) else {
                if countedFingers(tracker).count >= 2 {
                    touch?.isMultiFinger = true
                }
                return
            }
        case .ended, .restarted:
            break
        }
        // タッチが離れた
        if let touch {
            if touch.isMultiFinger {
                rejectMultiFingerLift(touch, effects: &effects)
            } else if drain.allowsTap, now < drain.deadline, let cell = touch.downCell {
                if isEmptyCell(cell) {
                    effects.append(.haptic(.rejected))
                } else {
                    execute(cell: cell, wasFastTap: true, effects: &effects)
                }
            }
        }
        recordLift(now: now)
        if case .restarted = change {
            // 離すと同時に新しく置いた指は、まだ触れている
            beginTouch(tracker, now: now)
        }
        end(drain.reason, now: now, effects: &effects)
    }

    // MARK: トリガーより前から休めている指

    private mutating func forgetLiftedRestingFingers(_ tracker: FingerTracker) {
        guard !restingFingers.isEmpty else { return }
        let touching = Set(tracker.fingers.map(\.id))
        restingFingers = restingFingers.filter { touching.contains($0.key) }
    }

    /// 休めている指のほかに、このフレームで新しく指が置かれた（休めている指と置いた指だけが触れている）
    private func startsTouchBesideRestingFingers(_ tracker: FingerTracker) -> Bool {
        guard !restingFingers.isEmpty, !tracker.placedInLastFrame.isEmpty, touch == nil || touch?.isPreTrigger == true else { return false }
        let placed = Set(tracker.placedInLastFrame)
        return tracker.fingers.allSatisfy { placed.contains($0.id) || restingFingers[$0.id] != nil }
    }

    /// 休めている指を除いたタッチの指が、すべて離れた
    private func endsTouchBesideRestingFingers(_ tracker: FingerTracker) -> Bool {
        guard !restingFingers.isEmpty, let touch, !touch.isPreTrigger else { return false }
        return countedFingers(tracker).isEmpty
    }

    /// 休めている指が restingTolerance より動いたら、ふつうの指として数える。
    /// ほかの指でタップしている間の小さなずれでは外さない（そのタッチが終わったら測り直す）
    private mutating func releaseMovedRestingFingers(_ tracker: FingerTracker, now: TimeInterval) {
        guard !restingFingers.isEmpty, touch == nil || touch?.isPreTrigger == true else { return }
        var released = false
        for finger in tracker.fingers {
            guard let anchor = restingFingers[finger.id],
                  hypot(finger.x - anchor.x, finger.y - anchor.y) >= SessionConfiguration.restingTolerance else { continue }
            restingFingers[finger.id] = nil
            released = true
        }
        guard released else { return }
        if touch == nil {
            // 休めていた指を滑らせ始めた: ハイライトで追えるよう、その指のタッチにする（トリガーより前から置いていたので、速押しにはしない）
            touch = SessionTouch(
                physicalStart: tracker.gestureStart,
                restStart: now,
                isTapCandidate: false,
                downCell: nil,
                isMultiFinger: countedFingers(tracker).count >= 2
            )
        } else {
            touch?.isPreTrigger = false
        }
    }

    /// 休めている指の位置を測り直す（ほかの指でタップしている間にずれた分を、動かしたことにしない）
    private mutating func reanchorRestingFingers(_ tracker: FingerTracker) {
        for finger in tracker.fingers where restingFingers[finger.id] != nil {
            restingFingers[finger.id] = finger
        }
    }

    /// このタッチで数える指（置いた順）。休めている指は、セッションの始めのタッチ（その指だけのタッチ）でだけ数える
    private func countedFingers(_ tracker: FingerTracker) -> [FingerTracker.Finger] {
        guard !restingFingers.isEmpty, touch?.isPreTrigger != true else { return tracker.fingers }
        return tracker.fingers.filter { restingFingers[$0.id] == nil }
    }

    /// HUD でのタップの移動量（最初に置いた指の、置いた位置からの距離）
    private mutating func measureTravel(_ fingers: [FingerTracker.Finger]) {
        guard let origin = touch?.origin, let finger = fingers.first(where: { $0.id == origin.id }) else { return }
        let distance = hypot(finger.x - origin.x, finger.y - origin.y)
        if distance > touch?.travel ?? 0 {
            touch?.travel = distance
        }
    }

    /// 今のタッチが離れた
    private mutating func recordLift(now: TimeInterval) {
        guard touch != nil else { return }
        lastLiftAt = now
        touch = nil
    }

    /// 新しいタッチを始める。休めている指は数えない（このタッチの指は、休めている指のほかに置いた指）
    private mutating func beginTouch(_ tracker: FingerTracker, now: TimeInterval) {
        let fingers = tracker.fingers.filter { restingFingers[$0.id] == nil }
        let first = fingers.last
        touch = SessionTouch(
            physicalStart: now,
            restStart: now,
            // HUD を出していなければ速押しの候補（仕様 3・6）。HUD を出していれば HUD での選択（短ければタップ）
            isTapCandidate: !isHUDVisible,
            downCell: first.map { grid.cell(x: $0.x, y: $0.y) },
            isMultiFinger: fingers.count >= 2,
            origin: first
        )
        tracked = nil
        swipeBaseline = nil
    }

    private mutating func liftTouch(now: TimeInterval, effects: inout [SessionEffect]) {
        defer {
            recordLift(now: now)
            tracked = nil
            swipeBaseline = nil
        }
        guard let touch else { return }
        if touch.isMultiFinger {
            // 仕様 9: 2本以上の指のタッチは実行しない
            rejectMultiFingerLift(touch, effects: &effects)
            clearHighlight(effects: &effects)
        } else if isHUDVisible {
            if configuration.fireMode == .onFingerLift, let cell = highlight, !isEmptyCell(cell) {
                // 仕様 5: onFingerLift なら1本指を離したときにハイライト中のマスを実行し、HUD を閉じる。
                // 空きマスなら何もしない（仕様 12）ので、HUD は出したまま選び直せるようにする
                hideHUD(effects: &effects)
                execute(cell: cell, wasFastTap: false, effects: &effects)
            } else if isTapInHUD(touch, now: now), let cell = touch.downCell {
                // 仕様 5: HUD が出ていても、短いタップは置いたマスをその場で実行し、HUD を閉じる（セッションは続く。仕様 6）
                if isEmptyCell(cell) {
                    effects.append(.haptic(.rejected))
                    clearHighlight(effects: &effects)
                } else {
                    hideHUD(effects: &effects)
                    execute(cell: cell, wasFastTap: false, effects: &effects)
                }
            } else {
                clearHighlight(effects: &effects)
            }
        } else if touch.isTapCandidate, now < touch.restStart + configuration.hudDelay, let cell = touch.downCell {
            // 仕様 3: 速押し。置いた位置のマスを HUD なしで実行する。
            // 空きマスは実行せずに離したのと同じ（hasExecuted にしないので、迷っていれば (a) の HUD が出る）。触覚で知らせる
            if isEmptyCell(cell) {
                effects.append(.haptic(.rejected))
            } else {
                execute(cell: cell, wasFastTap: true, effects: &effects)
            }
        }
    }

    /// HUD が出ているときの、短く動かさない1本指のタップ。実行のタイミングが「キーを離したとき」のときだけ
    /// （「指を離したとき」は、離せばいつも光っているマスを実行する）。トリガーより前から置いていた指はタップにしない
    private func isTapInHUD(_ touch: SessionTouch, now: TimeInterval) -> Bool {
        configuration.fireMode == .onTriggerRelease
            && !touch.isPreTrigger
            && now - touch.physicalStart < SessionConfiguration.tapMaxDuration
            && touch.travel < SessionConfiguration.tapMaxTravel
    }

    /// 2本以上の指のタッチが離れた。ページを変えて（変えようとして）いなければ、受け付けなかったことを指に知らせる
    private func rejectMultiFingerLift(_ touch: SessionTouch, effects: inout [SessionEffect]) {
        guard !touch.hasTurnedPage, !touch.isPreTrigger else { return }
        effects.append(.haptic(.rejected))
    }

    private mutating func clearHighlight(effects: inout [SessionEffect]) {
        guard isHUDVisible, highlight != nil else { return }
        highlight = nil
        effects.append(.updateHUD(page: page, highlightedCell: nil))
    }

    /// 最後に置いた指のマスを追い、スワイプとハイライトを更新する
    private mutating func follow(_ tracker: FingerTracker, effects: inout [SessionEffect], buzzesOnBoundary: Bool = true) {
        trackFinger(tracker)
        trackSwipe(tracker, effects: &effects)
        refreshHighlight(effects: &effects, buzzesOnBoundary: buzzesOnBoundary)
    }

    /// 最後に置いた指のマス（ヒステリシスつき）と、スワイプの起点を更新する。休めている指は数えない
    private mutating func trackFinger(_ tracker: FingerTracker) {
        let fingers = countedFingers(tracker)
        guard let finger = fingers.last else {
            tracked = nil
            return
        }
        let current = tracked?.fingerID == finger.id ? tracked?.cell : nil
        tracked = TrackedCell(fingerID: finger.id, cell: grid.cell(x: finger.x, y: finger.y, current: current))
        guard fingers.count == 2 else {
            swipeBaseline = nil
            return
        }
        // 2本がそろった時点（指が入れ替わったら、その時点）の平均を起点にする
        let ids = fingers.map(\.id).sorted()
        if swipeBaseline?.fingerIDs != ids {
            swipeBaseline = SwipeBaseline(fingerIDs: ids, x: Self.averageX(fingers))
        }
    }

    /// 仕様 8: 2本指で横にスワイプしたら前後のページへ。端のページから先へは行かず、触覚で知らせる
    private mutating func trackSwipe(_ tracker: FingerTracker, effects: inout [SessionEffect]) {
        let fingers = countedFingers(tracker)
        guard fingers.count == 2, let baseline = swipeBaseline, let touch, !touch.hasTurnedPage else { return }
        let dx = Self.averageX(fingers) - baseline.x
        guard abs(dx) >= configuration.swipeThreshold else { return }
        self.touch?.hasTurnedPage = true
        // Launchpad などと同じく、指を左へ動かすと次のページ
        let target = min(max(dx < 0 ? page + 1 : page - 1, 0), configuration.pageCount - 1)
        let didChange = target != page
        page = target
        if !isHUDVisible {
            showHUD(effects: &effects)
        } else if didChange {
            effects.append(.updateHUD(page: page, highlightedCell: highlight))
        }
        effects.append(.haptic(didChange ? .pageChange : .rejected))
    }

    private static func averageX(_ fingers: [FingerTracker.Finger]) -> Double {
        fingers.reduce(0) { $0 + $1.x } / Double(max(fingers.count, 1))
    }

    // MARK: HUD・実行

    /// 2本以上の指が触れたタッチはハイライトしない（実行されないマスを光らせないため）
    private var currentHighlight: Int? {
        guard let touch, !touch.isMultiFinger else { return nil }
        return tracked?.cell
    }

    /// buzzesOnBoundary が false なら、ハイライトが変わっても境界の触覚を鳴らさない（休めている指のほかに新しく置いたとき）
    private mutating func refreshHighlight(effects: inout [SessionEffect], buzzesOnBoundary: Bool = true) {
        guard isHUDVisible else { return }
        let next = currentHighlight
        guard next != highlight else { return }
        let previous = highlight
        highlight = next
        effects.append(.updateHUD(page: page, highlightedCell: next))
        // 仕様 7: ハイライトするマスが変わるたびに。指を置いた・離しただけでは鳴らさない
        if buzzesOnBoundary, previous != nil, next != nil {
            effects.append(.haptic(.boundary))
        }
    }

    private mutating func showHUD(effects: inout [SessionEffect]) {
        isHUDVisible = true
        highlight = currentHighlight
        effects.append(.showHUD(page: page, highlightedCell: highlight))
    }

    private mutating func hideHUD(effects: inout [SessionEffect]) {
        isHUDVisible = false
        highlight = nil
        effects.append(.hideHUD)
    }

    /// 今のページで中身が無いと分かっているマス（仕様 12）。分からなければ false（controller が判断する）
    private func isEmptyCell(_ cell: Int) -> Bool {
        guard let occupied = configuration.occupiedCells, occupied.indices.contains(page) else { return false }
        return !occupied[page].contains(cell)
    }

    private mutating func execute(cell: Int, wasFastTap: Bool, effects: inout [SessionEffect]) {
        hasExecuted = true
        effects.append(.execute(page: page, cell: cell, wasFastTap: wasFastTap))
    }
}
