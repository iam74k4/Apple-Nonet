// 担当: engine
// トリガーを押してから離すまで（セッション）の状態遷移。時間とタッチを入力として受け、
// HUD・触覚・実行などの出力を返す純粋なロジックにする（docs/architecture.md の「操作の仕様」）。
// 公開 API は engine 担当が決めてよい（NonetController だけが使う）。
import Foundation

// MARK: - 設定

/// セッションの始まり方
public enum SessionActivation: Equatable, Sendable {
    /// トリガーキーを押した（docs/architecture.md の「操作の仕様」1〜14）
    case triggerKey
    /// トラックパッドの角の長押し（CornerHoldRecognizer）。HUD をすぐに出し、指を滑らせてから離すと実行する。
    /// 速押しも、トリガーを離して実行することも無い
    case cornerHold
}

/// 1回のセッションで使う設定。トリガーを押したときに渡し、そのセッションの間は変わらない
public struct SessionConfiguration: Equatable, Sendable {
    public static let defaultHUDDelay: TimeInterval = 0.3
    public static let defaultSwipeThreshold = 0.12
    public static let defaultMaxDuration: TimeInterval = 20

    /// トリガーを押してから / 指を置いてから HUD を出すまでの秒数。速押しの判定にも使う
    public var hudDelay: TimeInterval
    public var fireMode: FireMode
    /// 前面アプリで使うページの数（resolvedPages の数）。1 未満は 1 とみなす
    public var pageCount: Int
    /// マスの境界で今のマスを保つ余裕（トラックパッド全体を 1 とした割合）
    public var hysteresis: Double
    public var edgeInsets: GridInsets
    /// ページを切り替える、2本の指の平均の横の移動量（トラックパッドの幅を 1 とした割合）
    public var swipeThreshold: Double
    /// これを超えたセッションは終える（トリガーを離したイベントを取りこぼしたときの安全装置）
    public var maxDuration: TimeInterval
    /// ページごとの、中身のあるマス（0〜8）。nil や範囲外のページは、すべてのマスに中身があるとみなす。
    /// 空きマス（仕様 12）の速押しを「実行せずに離した」と扱い、6 の (a) の HUD を止めないために使う
    public var occupiedCells: [Set<Int>]?
    public var activation: SessionActivation

    public init(
        hudDelay: TimeInterval = SessionConfiguration.defaultHUDDelay,
        fireMode: FireMode = .onTriggerRelease,
        pageCount: Int = 1,
        hysteresis: Double = GridMapper.defaultHysteresis,
        edgeInsets: GridInsets = .zero,
        swipeThreshold: Double = SessionConfiguration.defaultSwipeThreshold,
        maxDuration: TimeInterval = SessionConfiguration.defaultMaxDuration,
        occupiedCells: [Set<Int>]? = nil,
        activation: SessionActivation = .triggerKey
    ) {
        self.hudDelay = hudDelay
        self.fireMode = fireMode
        self.pageCount = pageCount
        self.hysteresis = hysteresis
        self.edgeInsets = edgeInsets
        self.swipeThreshold = swipeThreshold
        self.maxDuration = maxDuration
        self.occupiedCells = occupiedCells
        self.activation = activation
    }

    /// 全体の設定から作る。pageCount は前面アプリの resolvedPages の数
    public init(settings: GlobalSettings, pageCount: Int, occupiedCells: [Set<Int>]? = nil) {
        self.init(hudDelay: settings.hudDelay, fireMode: settings.fireMode, pageCount: pageCount, occupiedCells: occupiedCells)
    }

    /// 範囲外の値を直したもの。エンジンはセッションの開始時にこれを使う
    public var sanitized: SessionConfiguration {
        var result = self
        result.maxDuration = maxDuration.isFinite && maxDuration > 0 ? maxDuration : Self.defaultMaxDuration
        let delay = hudDelay.isFinite && hudDelay >= 0 ? hudDelay : Self.defaultHUDDelay
        result.hudDelay = min(delay, result.maxDuration)
        result.pageCount = max(pageCount, 1)
        result.hysteresis = GridMapper(hysteresis: hysteresis).hysteresis
        result.swipeThreshold = swipeThreshold.isFinite && swipeThreshold > 0 ? min(swipeThreshold, 1) : Self.defaultSwipeThreshold
        return result
    }

    var grid: GridMapper {
        GridMapper(hysteresis: hysteresis, insets: edgeInsets)
    }
}

// MARK: - 入力と出力

/// エンジンへの入力。時刻はすべて Scheduler.now と同じ時計の秒
public enum SessionInput: Equatable, Sendable {
    /// トリガーキーが押された。セッション中なら、そのセッションを何も実行せずに終えてから新しく始める。
    /// configuration.activation が .cornerHold なら、トリガーではなくトラックパッドの角の長押しで始める。
    /// そのときは触れている指をそのまま使う（指が触れていなければ、何も出さずにキャンセルとして終える）
    case triggerDown(at: TimeInterval, configuration: SessionConfiguration)
    case triggerUp(at: TimeInterval)
    /// トリガーを押している間に、ほかのキーや修飾キーが押された
    case interrupted(at: TimeInterval)
    /// トラックパッドのフレーム。セッションの外でも渡す（トリガーを押す前から置いていた指を、速押しと間違えないため）
    case touches(TouchFrame)
    /// requestTick で頼まれた時刻が来た。多少早くても遅くてもよい
    case tick(at: TimeInterval)
}

public enum SessionEndReason: Equatable, Sendable {
    /// トリガーを離して終えた（離したときに実行した場合も、何もしなかった場合も）。
    /// 角の長押しのセッションでは、指を滑らせてから離して終えた
    case released
    /// HUD を出したまま、何も実行せずにトリガーを離した（指を先に離した、など）。
    /// 角の長押しのセッションでは、指を滑らせずに離した
    case cancelled
    /// ほかのキーが押された。または、離したイベントを取りこぼしたままトリガーがもう一度押された
    case interrupted
    /// maxDuration を超えた
    case timeout
}

/// 表示中の HUD の中身
public struct SessionHUDState: Equatable, Sendable {
    /// resolvedPages での位置
    public var page: Int
    /// 指の下のマス（0〜8）。指が離れている・2本以上の指が触れているときは nil
    public var highlightedCell: Int?

    public init(page: Int, highlightedCell: Int?) {
        self.page = page
        self.highlightedCell = highlightedCell
    }
}

/// エンジンからの出力。並び順どおりに処理する
public enum SessionEffect: Equatable, Sendable {
    /// セッションが始まった。ポインタの抑止を始める
    case beginPointerSuppression
    /// ポインタの抑止をやめる。必ず sessionEnded の直前に来る。dropsLateClicks なら、やめた直後の短い間に届く
    /// クリックの「押す」も捨ててもらう（終わる直前に指が離れた・置いたばかりの指がまだ触れているとき。
    /// その指の「タップでクリック」が抑止の後に届くことがある。SessionEngine.lateClickWindow）
    case endPointerSuppression(dropsLateClicks: Bool)
    /// HUD を出す。page は resolvedPages での位置、highlightedCell は指の下のマス
    case showHUD(page: Int, highlightedCell: Int?)
    /// 表示中の HUD のページかハイライトが変わった
    case updateHUD(page: Int, highlightedCell: Int?)
    case hideHUD
    /// boundary・pageChange・activation（角の長押しで始めたとき）だけを出す。execute の触覚は、実際に何かを実行したとき（空きマスでないとき）に controller が鳴らす
    case haptic(HapticEvent)
    /// マスを実行する。occupiedCells で空きと分かっているマスには出さない。
    /// それ以外の空きマス・ライセンス・練習モード・トーストの判断は controller がする。
    /// wasFastTap は HUD を出さずに実行した（速押し）
    case execute(page: Int, cell: Int, wasFastTap: Bool)
    /// この時刻に tick を渡してほしい。前の依頼を置き換える（タイマーは常に1つでよい）
    case requestTick(at: TimeInterval)
    /// セッションが終わった。待っている tick は取り消してよい
    case sessionEnded(SessionEndReason)
}

// MARK: - エンジン

/// 1回のセッション（トリガーを押してから離すまで）の状態遷移。docs/architecture.md の「操作の仕様」1〜11 を受け持つ。
/// 時刻はすべて入力で受け取り、タイマーも持たない（同じ入力には必ず同じ出力を返す）。
///
/// NonetController からの使い方:
/// - キーボード・トラックパッド・tick を `handle(_:)` に渡し、返ってきた出力を並び順どおりに処理する
/// - トラックパッドのフレームはセッションの外でも渡す。セッションの外では何も出力しない
/// - `requestTick(at:)` を受けたら、その時刻に `.tick` を渡す。時刻を過ぎた入力が来れば、エンジンはその時刻までに起きるべきことを先に処理する
/// - トリガーを離したとき、置いたばかりの指（hudDelay 未満）が残っていれば、その指が離れるまで（最長 hudDelay）セッションを続ける。
///   その指のタップがクリックとして前面アプリに届かないようにし、トリガーを指より少し先に離した速押しも拾うため。
///   終わりは必ず `sessionEnded` で知らせる
/// - 空きマス（仕様 12）は、`occupiedCells` で分かればエンジンが実行しない（速押しは「実行せずに離した」とみなし、
///   6 の (a) の HUD を止めない。HUD で選んだ空きマスは選ばなかったことにする）。
///   分からないマス・ライセンス（13）・練習モード（14）は controller が `execute` を受けて判断する
/// - 角の長押し（`SessionActivation.cornerHold`）で始めたセッションは、HUD をすぐに出し、すべての指が離れたら終える。
///   滑らせてから1本指で離せば光っているマスを実行し、滑らせずに離せばキャンセル。トリガーを離したイベントは使わない
public struct SessionEngine: Sendable {
    /// セッションの終わりの前のこの秒数のうちに指が離れたか、この秒数より新しい指がまだ触れていれば、
    /// その指の「タップでクリック」が抑止の後に届きうるとみなす（endPointerSuppression の dropsLateClicks）。
    /// 指に触れていないセッション（トリガーをほかのキーと組み合わせただけ など）の後のクリックは捨てない
    public static let lateClickWindow: TimeInterval = 0.5

    /// 入力で受け取った最新の時刻。時刻が戻った入力は、この時刻に起きたものとして扱う
    private var clock: TimeInterval = -.infinity
    private var tracker = FingerTracker()
    private var session: SessionState?
    private var requestedTick: TimeInterval?

    public init() {}

    /// セッション中（トリガーを離した後、指が離れるのを待っている間も含む）
    public var isInSession: Bool { session != nil }

    /// トリガーを押している間 true。離した後、指が離れるのを待っている間と、角の長押しのセッションでは false
    public var isTriggerHeld: Bool { session.map { !$0.isDraining && !$0.isCornerHold } ?? false }

    /// 角の長押しで始めたセッション中
    public var isCornerHoldSession: Bool { session?.isCornerHold ?? false }

    /// いまのページ（resolvedPages での位置）。セッション外は nil
    public var pageIndex: Int? { session?.page }

    /// 表示中の HUD。出していなければ nil
    public var hud: SessionHUDState? { session?.hudState }

    public mutating func handle(_ input: SessionInput) -> [SessionEffect] {
        var effects: [SessionEffect] = []
        var isTick = false
        switch input {
        case .triggerDown(let time, let configuration):
            advance(to: time, effects: &effects)
            if let session {
                self.session?.end(session.isDraining ? session.releaseReason : .interrupted, now: clock, effects: &effects)
                finishIfEnded()
            }
            if !clock.isFinite { clock = 0 }
            effects.append(.beginPointerSuppression)
            session = SessionState(configuration: configuration.sanitized, start: clock, tracker: tracker)
            if configuration.activation == .cornerHold {
                session?.activateFromCorner(now: clock, effects: &effects)
            }
        case .triggerUp(let time):
            advance(to: time, effects: &effects)
            session?.releaseTrigger(now: clock, effects: &effects)
        case .interrupted(let time):
            advance(to: time, effects: &effects)
            session?.end(.interrupted, now: clock, effects: &effects)
        case .touches(let frame):
            advance(to: frame.timestamp, effects: &effects)
            let change = tracker.apply(frame.points, at: clock)
            session?.apply(change, tracker: tracker, now: clock, effects: &effects)
        case .tick(let time):
            isTick = true
            advance(to: time, effects: &effects)
        }
        // 入力で新しく期限が来たもの（hudDelay が 0 のときなど）
        session?.fireDeadlines(now: clock, effects: &effects)
        finishIfEnded()
        requestNextTick(force: isTick, effects: &effects)
        return effects
    }

    /// 時刻を進め、その時刻までに期限が来たもの（HUD・時間切れ）を入力より先に処理する
    private mutating func advance(to time: TimeInterval, effects: inout [SessionEffect]) {
        if time.isFinite, !(time < clock) {
            clock = time
        }
        session?.fireDeadlines(now: clock, effects: &effects)
        finishIfEnded()
    }

    private mutating func finishIfEnded() {
        guard session?.isEnded == true else { return }
        session = nil
        requestedTick = nil
    }

    /// 期限が変わったときだけ頼む。tick を受けたときは、タイマーを使い切ったので必ず頼み直す
    private mutating func requestNextTick(force: Bool, effects: inout [SessionEffect]) {
        guard let deadline = session?.nextDeadline(now: clock) else {
            requestedTick = nil
            return
        }
        guard force || deadline != requestedTick else { return }
        requestedTick = deadline
        effects.append(.requestTick(at: deadline))
    }
}
