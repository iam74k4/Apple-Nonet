// 担当: engine
// 9マスを開いてから閉じるまで（セッション）の状態遷移。時間とタッチを入力として受け、
// HUD・触覚・実行などの出力を返す純粋なロジックにする（docs/architecture.md の「操作の仕様」）。
// 公開 API は engine 担当が決めてよい（NonetController だけが使う）。
import Foundation

// MARK: - 設定

/// 1回のセッションで使う設定。開くときに渡し、そのセッションの間は変わらない
public struct SessionConfiguration: Equatable, Sendable {
    public static let defaultSwipeThreshold = 0.12
    /// これを超えたセッションは終える（指が離れたフレームを取りこぼしたときの安全装置）。
    /// ふつうのセッションは数秒で終わり、指を止めて迷っていても 20 秒あれば足りる
    public static let defaultMaxDuration: TimeInterval = 20
    /// ふつうのマスで、指を離して実行するまでに、そのマスに留まっている秒数。
    /// 滑らせて通りかかっただけのマス（滑らせながら指を離した・ポインタを動かすつもりで離した）を実行しないため。
    /// 狙ったマスへ滑らせてそのまま離す動きでも届く短さ（実機で 0.15 秒では「狙ったマスで離しても実行されない」となった。
    /// 隣のマスを通りかかる時間は、滑らせる速さ 10cm/秒 ほどで 0.04 秒ほどなので、0.1 秒でも通りかかっただけのマスは外せる）
    public static let defaultLiftDwell: TimeInterval = 0.1
    /// 少し長く止めてから実行するマス（Cell.requiresHold）の留まる秒数。送信・録画のように取り消せないマスで、
    /// 狙ったマスを確かめて止めたことをはっきりさせる。HUD はこの間の進み具合を見せ、止め終えたら触覚（holdReady）で知らせる
    /// （目で追えて、待つのがもどかしくない長さ。実機で 0.6 秒は長いとなったので縮めた）
    public static let defaultHoldDwell: TimeInterval = 0.45
    /// 2本以上の指から1本指に戻ったとき、残った指でまた選ぶのに要る動き（トラックパッドを 1 とした距離）。
    /// 2本の指は同時には離れにくく（0.1〜0.3 秒ほどずれる）、残った指の下のマスを、選んでいないのに実行しないため。
    /// 止めた指の揺れ（1mm より十分小さい）よりは大きく、滑らせればすぐに届く 2〜3mm
    public static let reselectTravel = 0.02
    /// 開いた後、マスを選び始めるのに要る動き（トラックパッドを 1 とした距離）。開いた瞬間は、指がどこにあっても上の外枠にいることにし、
    /// ここまで滑らせてからマスを選ぶ。開く動きの後の 0.04 秒の待ちの間に指が上の段まで進んでいても、止めて離せば何もせずに閉じる
    public static let openTravel = 0.02
    /// 外枠の帯で「止めている」とみなす、指の動きの許容（トラックパッドを 1 とした距離）。
    /// これより動かしたら、止め始めた時刻から数え直す（行き過ぎた指を、外枠の中でゆっくり戻している間に、ページが変わらないように）。
    /// 止めた指の揺れ（1mm より十分小さい）より大きく、狙って動かせば超える 4〜5mm
    public static let edgeRestTravel = 0.03
    /// 外枠の帯（左右はページ、上下は層）に指を止めてから、切り替えるまでの秒数。
    /// やめるつもりで外枠に出て離すまで（0.2〜0.3 秒ほど）よりは長く、待つのがもどかしくない短さ
    public static let defaultEdgePageDwell: TimeInterval = 0.5
    /// 切り替えた後も止めているとき、次に切り替えるまでの秒数。続けて送れるが、行き過ぎないよう最初より長くする
    public static let defaultEdgePageRepeat: TimeInterval = 0.9

    /// 前面アプリで使うページの数（resolvedPages の数）。1 未満は 1 とみなす
    public var pageCount: Int
    /// 2つ目の層（グローバルのページ）の最初のページ。アプリのページの後ろにグローバルのページをつなげたとき。
    /// 左右はその層の中だけでページを送り、下で止めるとこの層へ、上で止めるとアプリの層へ戻る。nil なら層は1つ（上下では何も起きない）
    public var layerStart: Int?
    /// マスの境界で今のマスを保つ余裕（トラックパッド全体を 1 とした割合）
    public var hysteresis: Double
    /// 9マスの外側の枠（やめる場所）の幅
    public var frame: GridInsets
    /// 外枠と9マスの境目で今の場所を保つ余裕
    public var frameHysteresis: Double
    /// 切り替える、2本の指の平均の移動量（トラックパッドの幅・奥行きを 1 とした割合）。横ならページ、縦なら層
    public var swipeThreshold: Double
    public var maxDuration: TimeInterval
    /// ページごとの、中身のあるマス（0〜8）。nil や範囲外のページは、すべてのマスに中身があるとみなす。
    /// 空きマスで指を離したら、実行せずにやめる（rejected の触覚）
    public var occupiedCells: [Set<Int>]?
    /// ページごとの、少し長く止めてから実行するマス（0〜8。`Cell.requiresHold`）。nil や範囲外のページは、どのマスもふつう
    public var holdCells: [Set<Int>]?
    /// 指を離しても実行しない、内側の境界の線の片側の幅（GridMapper.boundaryBand）
    public var boundaryBand: Double
    public var liftDwell: TimeInterval
    public var holdDwell: TimeInterval
    public var edgePageDwell: TimeInterval
    public var edgePageRepeat: TimeInterval

    public init(
        pageCount: Int = 1,
        layerStart: Int? = nil,
        hysteresis: Double = GridMapper.defaultHysteresis,
        frame: GridInsets = .cancelFrame,
        frameHysteresis: Double = GridMapper.defaultFrameHysteresis,
        swipeThreshold: Double = SessionConfiguration.defaultSwipeThreshold,
        maxDuration: TimeInterval = SessionConfiguration.defaultMaxDuration,
        occupiedCells: [Set<Int>]? = nil,
        holdCells: [Set<Int>]? = nil,
        boundaryBand: Double = GridMapper.defaultBoundaryBand,
        liftDwell: TimeInterval = SessionConfiguration.defaultLiftDwell,
        holdDwell: TimeInterval = SessionConfiguration.defaultHoldDwell,
        edgePageDwell: TimeInterval = SessionConfiguration.defaultEdgePageDwell,
        edgePageRepeat: TimeInterval = SessionConfiguration.defaultEdgePageRepeat
    ) {
        self.pageCount = pageCount
        self.layerStart = layerStart
        self.hysteresis = hysteresis
        self.frame = frame
        self.frameHysteresis = frameHysteresis
        self.swipeThreshold = swipeThreshold
        self.maxDuration = maxDuration
        self.occupiedCells = occupiedCells
        self.holdCells = holdCells
        self.boundaryBand = boundaryBand
        self.liftDwell = liftDwell
        self.holdDwell = holdDwell
        self.edgePageDwell = edgePageDwell
        self.edgePageRepeat = edgePageRepeat
    }

    /// 範囲外の値を直したもの。エンジンはセッションの開始時にこれを使う
    public var sanitized: SessionConfiguration {
        var result = self
        result.maxDuration = maxDuration.isFinite && maxDuration > 0 ? maxDuration : Self.defaultMaxDuration
        result.pageCount = max(pageCount, 1)
        // 層の境目は、どちらの層にも1ページ以上あるときだけ
        result.layerStart = layerStart.flatMap { $0 > 0 && $0 < result.pageCount ? $0 : nil }
        let grid = self.grid
        result.hysteresis = grid.hysteresis
        result.boundaryBand = grid.boundaryBand
        result.frameHysteresis = grid.frameHysteresis
        result.swipeThreshold = swipeThreshold.isFinite && swipeThreshold > 0 ? min(swipeThreshold, 1) : Self.defaultSwipeThreshold
        result.liftDwell = liftDwell.isFinite && liftDwell >= 0 ? liftDwell : Self.defaultLiftDwell
        // 少し長く止めるマスは、ふつうのマスより短くしない
        let hold = holdDwell.isFinite && holdDwell >= 0 ? holdDwell : Self.defaultHoldDwell
        result.holdDwell = max(hold, result.liftDwell)
        result.edgePageDwell = edgePageDwell.isFinite && edgePageDwell > 0 ? edgePageDwell : Self.defaultEdgePageDwell
        result.edgePageRepeat = edgePageRepeat.isFinite && edgePageRepeat > 0 ? edgePageRepeat : Self.defaultEdgePageRepeat
        return result
    }

    var grid: GridMapper {
        GridMapper(hysteresis: hysteresis, insets: frame, boundaryBand: boundaryBand, frameHysteresis: frameHysteresis)
    }
}

// MARK: - 入力と出力

/// エンジンへの入力。時刻はすべて Scheduler.now と同じ時計の秒
public enum SessionInput: Equatable, Sendable {
    /// 9マスを開く（EdgeSlideRecognizer が上の縁からの滑り込みを見分け、NonetController が開いてよいと決めた）。
    /// 触れている指でそのまま選び始める。セッション中なら、そのセッションを何も実行せずに終えてから開く。
    /// 触れている指が無ければ（もう離れていた）何もしない
    case open(at: TimeInterval, configuration: SessionConfiguration)
    /// 開いている間に、キーや修飾キーが押された・マウスやホイールを使った
    case interrupted(at: TimeInterval)
    /// トラックパッドのフレーム。セッションの外でも渡す（開いたときに触れている指を知っておくため）
    case touches(TouchFrame)
    /// requestTick で頼まれた時刻が来た。多少早くても遅くてもよい
    case tick(at: TimeInterval)
}

/// 指を離したのに実行しなかった理由
public enum SessionCancellation: Equatable, Sendable {
    /// 外枠で離した（やめる操作）
    case liftedInFrame
    /// マスの境界の帯（GridMapper.boundaryBand）で離した。どちらのマスを狙ったか分からない
    case liftedOnBoundary
    /// 空きマスで離した
    case liftedOnEmptyCell
    /// マスに留まる時間（liftDwell・少し長く止めるマスは holdDwell）が足りないうちに離した
    case liftedTooSoon
    /// 2本以上の指が触れたまま離した
    case liftedWithSeveralFingers
    /// 2本以上の指から1本指に戻った後、残った指を滑らせずに離した（SessionConfiguration.reselectTravel）
    case liftedWithoutSliding
}

public enum SessionEndReason: Equatable, Sendable {
    /// マスで指を離して実行した
    case released
    /// 指を離したが、何も実行しなかった
    case cancelled(SessionCancellation)
    /// キーや修飾キーが押された・マウスやホイールを使った・開いている間にもう一度開いた
    case interrupted
    /// maxDuration を超えた
    case timeout
}

/// 少し長く止めてから実行するマスに、指を止めている間の進み具合
public struct SessionHold: Equatable, Sendable {
    /// 止めているマス（0〜8）
    public var cell: Int
    /// 止め始めた時刻（このマスになった時刻か、2本指の後に滑らせ直した時刻）
    public var since: TimeInterval
    /// 止める必要のある秒数（holdDwell）
    public var duration: TimeInterval
    /// 止め終えた。いま指を離すと実行する
    public var isReady: Bool

    public init(cell: Int, since: TimeInterval, duration: TimeInterval, isReady: Bool) {
        self.cell = cell
        self.since = since
        self.duration = duration
        self.isReady = isReady
    }
}

/// 外枠の帯に指を止めている間の、ページか層を切り替えるまでの進み具合
public struct SessionEdgePaging: Equatable, Sendable {
    public var edge: PageEdge
    /// 止め始めた時刻（外枠のその側に入った時刻か、前に切り替えた時刻）
    public var since: TimeInterval
    /// 切り替えるまでの秒数（edgePageDwell。続けて止めているときは edgePageRepeat）
    public var duration: TimeInterval

    public init(edge: PageEdge, since: TimeInterval, duration: TimeInterval) {
        self.edge = edge
        self.since = since
        self.duration = duration
    }
}

/// 表示中の HUD の中身
public struct SessionHUDState: Equatable, Sendable {
    /// resolvedPages での位置
    public var page: Int
    /// 指の下のマス（0〜8）。指が外枠にある・2本以上の指が触れているときは nil
    public var highlightedCell: Int?
    /// 指が外枠（やめる場所）にある。2本以上の指が触れているときは false
    public var isInFrame: Bool
    /// 光っているマスが少し長く止めるマスなら、その進み具合
    public var hold: SessionHold?
    /// 指が外枠の帯にあり、その側に切り替える先（ページか層）があれば、切り替えるまでの進み具合
    public var edgePaging: SessionEdgePaging?
    /// 指が、光っているマスと隣との境目の線の上にあり、いま離しても実行しない（止め終えた少し長く止めるマスは別。離せば実行する）
    public var isOnBoundary: Bool
    /// 最後にページか層を切り替えた向き（右・左は次・前のページ、下・上は次・前の層。2本指のスワイプは右・左）。
    /// HUD は、切り替わったときにこの向きへ輪を押し出す。このセッションでまだ切り替えていなければ nil
    public var lastTurn: PageEdge?

    public init(
        page: Int,
        highlightedCell: Int?,
        isInFrame: Bool = false,
        hold: SessionHold? = nil,
        edgePaging: SessionEdgePaging? = nil,
        isOnBoundary: Bool = false,
        lastTurn: PageEdge? = nil
    ) {
        self.page = page
        self.highlightedCell = highlightedCell
        self.isInFrame = isInFrame
        self.hold = hold
        self.edgePaging = edgePaging
        self.isOnBoundary = isOnBoundary
        self.lastTurn = lastTurn
    }
}

/// エンジンからの出力。並び順どおりに処理する
public enum SessionEffect: Equatable, Sendable {
    /// セッションが始まった。ポインタの抑止を始め（ポインタは指が触れ始めた位置に戻す）、キーボードを見始める
    case beginPointerSuppression
    /// ポインタの抑止をやめる。必ず sessionEnded の直前に来る。dropsLateClicks なら、やめた直後の短い間に届く
    /// クリックの「押す」も捨ててもらう（終わる直前に指が離れた・置いたばかりの指がまだ触れているとき。
    /// その指の「タップでクリック」が抑止の後に届くことがある。SessionEngine.lateClickWindow）
    case endPointerSuppression(dropsLateClicks: Bool)
    /// HUD を出す
    case showHUD(SessionHUDState)
    /// 表示中の HUD のページ・ハイライト・外枠・進み具合が変わった
    case updateHUD(SessionHUDState)
    case hideHUD
    /// activation（開いた）・boundary（マスと外枠の境目をまたいだ）・pageChange・holdReady（少し長く止めるマスを止め終えた）・
    /// rejected（何も実行せずに指を離した・端のページから先へのスワイプ）だけを出す。execute の触覚は、実際に何かを実行したときに controller が鳴らす
    case haptic(HapticEvent)
    /// マスを実行する。occupiedCells で空きと分かっているマスには出さない。
    /// それ以外の空きマス・ライセンス・練習モード・トーストの判断は controller がする
    case execute(page: Int, cell: Int)
    /// この時刻に tick を渡してほしい。前の依頼を置き換える（タイマーは常に1つでよい）
    case requestTick(at: TimeInterval)
    /// セッションが終わった。待っている tick は取り消してよい
    case sessionEnded(SessionEndReason)
}

// MARK: - エンジン

/// 1回のセッション（9マスを開いてから、すべての指が離れるまで）の状態遷移。docs/architecture.md の「操作の仕様」を受け持つ。
/// 時刻はすべて入力で受け取り、タイマーも持たない（同じ入力には必ず同じ出力を返す）。
///
/// NonetController からの使い方:
/// - トラックパッド・キーボード・tick を `handle(_:)` に渡し、返ってきた出力を並び順どおりに処理する
/// - トラックパッドのフレームはセッションの外でも渡す。セッションの外では何も出力しない
/// - 開く動き（EdgeSlideRecognizer）を見分けて開いてよければ `.open` を渡す。HUD をすぐに出し、指の下の場所を見せる
/// - `requestTick(at:)` を受けたら、その時刻に `.tick` を渡す。時刻を過ぎた入力が来れば、エンジンはその時刻までに起きるべきことを先に処理する
/// - すべての指が離れたら終える。光っているマスに liftDwell（少し長く止めるマスは holdDwell）以上留まって1本指で離せば、
///   そのマスを実行する。外枠・境界の帯・空きマスで離した・留まる時間が足りない・2本以上で離したなら、何もせずに rejected の触覚
public struct SessionEngine: Sendable {
    /// セッションの終わりの前のこの秒数のうちに指が離れたか、この秒数より新しい指がまだ触れていれば、
    /// その指の「タップでクリック」が抑止の後に届きうるとみなす（endPointerSuppression の dropsLateClicks）
    public static let lateClickWindow: TimeInterval = 0.5

    /// 入力で受け取った最新の時刻。時刻が戻った入力は、この時刻に起きたものとして扱う
    private var clock: TimeInterval = -.infinity
    private var tracker = FingerTracker()
    private var session: SessionState?
    private var requestedTick: TimeInterval?

    public init() {}

    /// セッション中
    public var isInSession: Bool { session != nil }

    /// いまのページ（resolvedPages での位置）。セッション外は nil
    public var pageIndex: Int? { session?.page }

    /// 表示中の HUD。セッション外は nil
    public var hud: SessionHUDState? { session?.hudState }

    public mutating func handle(_ input: SessionInput) -> [SessionEffect] {
        var effects: [SessionEffect] = []
        var isTick = false
        switch input {
        case .open(let time, let configuration):
            advance(to: time, effects: &effects)
            if session != nil {
                session?.end(.interrupted, now: clock, effects: &effects)
                finishIfEnded()
            }
            if !clock.isFinite { clock = 0 }
            if let opened = SessionState(configuration: configuration.sanitized, start: clock, tracker: tracker) {
                session = opened
                session?.open(effects: &effects)
            }
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
        session?.fireDeadlines(now: clock, effects: &effects)
        finishIfEnded()
        requestNextTick(force: isTick, effects: &effects)
        return effects
    }

    /// 時刻を進め、その時刻までに期限が来たもの（進み具合・時間切れ）を入力より先に処理する
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
        guard let deadline = session?.nextDeadline else {
            requestedTick = nil
            return
        }
        guard force || deadline != requestedTick else { return }
        requestedTick = deadline
        effects.append(.requestTick(at: deadline))
    }
}
