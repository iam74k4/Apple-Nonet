// 担当: engine
// もう1つの開き方（トラックパッドの上の縁から1本指を下へ滑り込ませる。GlobalSettings.openGesture が edgeSlide か both）を
// 見分ける純粋なロジック（docs/architecture.md §5「開く」）。NonetController がセッションの外も含めてすべてのフレームを渡し、
// 見分けたら、開いてよいか（無効・このアプリでは使わない・Nonet のウィンドウ・試用期間など）を確かめてからセッションを始める
import Foundation

/// 上の縁の帯（entryBandHeight）で触れ始めた1本指が、触れてから entryWindow のうちに entryTravel 以上、
/// 真下から斜めまで（|dx| ≤ maxEntrySlope × dy）下へ動いたら、開く合図を1回だけ返す。次のときは合図しない（そのタッチの間は、もう待たない）:
/// - 帯の外で触れ始めた（外から帯に入ってきた指を含む）。最初から2本以上で触れた・ほかの指が触れているところに置いた
/// - 待っている間に、ほかの指が触れた・離れた・entryWindow を過ぎた・斜めより横へ entryTravel 以上動いた
/// - 接触が手のひらの大きさ（palmMajorAxis 以上）になった
/// - セッション中に触れ始めた（開いている9マスの指を、閉じた後に開く動きとみなさない）
/// 指の出入りはセッションに関係なく数え続ける。時刻は TouchFrame.timestamp と同じ時計の秒
public struct EdgeSlideRecognizer: Sendable {
    /// 開きやすさごとの、帯の高さ・動きの量・時間（GlobalSettings.openSensitivity）。
    /// 標準は下の定数。控えめは帯を 6mm ほどに狭め、7mm ほど動かすのを 0.4 秒のうちに求める（ふだんのポインタ操作で開いてしまう人向け。
    /// 6mm は実機で「縁から滑らせても開かないことがある」となった値なので、狙って縁に当てる人向け）。
    /// 開きやすいは帯を 13mm ほどに広げ、4mm 動かせば 1 秒のうちならよい（縁から滑らせても開かないことがある人向け）。
    /// どの段でも、開いた瞬間の指は上の外枠にいることにし、そこから滑らせてからマスを選ぶ（SessionConfiguration.openTravel）。
    /// 開きやすいでは、帯の下の縁から travel 動いたところが外枠の境目（奥 0.17）に届くので、外枠の中だけには頼らない
    public struct Thresholds: Equatable, Sendable {
        public var bandHeight: Double
        public var travel: Double
        public var window: TimeInterval

        public init(bandHeight: Double, travel: Double, window: TimeInterval) {
            self.bandHeight = bandHeight
            self.travel = travel
            self.window = window
        }

        public static let standard = Thresholds(bandHeight: entryBandHeight, travel: entryTravel, window: entryWindow)

        public init(_ sensitivity: OpenSensitivity) {
            switch sensitivity {
            case .low: self.init(bandHeight: 0.06, travel: 0.07, window: 0.4)
            case .standard: self = .standard
            case .high: self.init(bandHeight: 0.13, travel: 0.04, window: 1.0)
            }
        }
    }

    /// 触れ始めると開く動きの候補になる、上の縁の帯の高さ（トラックパッドの奥行きを 1 とした割合。幅はすべて）。
    /// 奥行き 10cm ほどのトラックパッドで 9mm ほど: 縁のあたりに指を置けば、指先を縁に当てなくても中心がこの中に入り、
    /// ふだんポインタを動かすために指を置く場所（手前と中ほど）からは離れている。
    /// 実機で 6mm では「縁から滑らせても開かないことがある」となったので広げた
    public static let entryBandHeight = 0.09
    /// 開くのに要る、下への動き（トラックパッドの奥行きを 1 とした割合）。5mm ほど。
    /// 止めた指の揺れ（1mm より十分小さい）や、置いたときのずれでは届かず、ひと撫ででは確実に届く
    public static let entryTravel = 0.05
    /// 触れてからこの秒数のうちに entryTravel 動かなければ、そのタッチでは開かない。
    /// 狙って滑り込ませると 0.1〜0.25 秒ほどで届くが、置いてひと呼吸おいてから滑らせる人もいるので余裕を持たせる。
    /// 上の縁からゆっくり動かすのは、ふだんのポインタの移動とみなす
    public static let entryWindow: TimeInterval = 0.6
    /// 下への動きに対する横の動きの上限（真下から 56° ほどまで）。上の段の角のマスへ斜めに滑らせても開く。
    /// これより横へ寝た動きは、上の縁に沿ってポインタを動かしているとみなす
    public static let maxEntrySlope = 1.5
    /// 開く動きを見分けてから、実際に開くまで待つ秒数（NonetController が待つ）。待つ間に2本目の指が触れたら開かない。
    /// 2本指のスクロールは、1本目が5mm動く間に2本目が少し遅れて触れることがある（実機の着地の間隔は 10〜50 ms ほどと見込む）。
    /// 狙って滑り込ませるときは、HUD がこの分だけ遅れても気にならない短さ
    public static let entryConfirmDelay: TimeInterval = 0.04
    /// これ以上の長径（TouchPoint.majorAxis）の接触は手のひらとみなし、開かない。
    /// 指先はおよそ 8〜15、平らに置いた親指でも 20 ほどなので、それより大きいものだけを外す控えめな値にしている
    /// （単位は MultitouchSupport の majorAxis のまま。実機では確かめていない。値が取れない接触は外さない）
    public static let palmMajorAxis = 25.0

    /// フレームを渡した結果
    public enum Event: Equatable, Sendable {
        case none
        /// 1本指が上の縁の帯で触れ始めた（開く動きの候補）。NonetController はここでポインタの位置を覚え、開いたらそこへ戻す
        case touchBeganInBand
        /// 開く動きになった（そのタッチでは二度と返さない）
        case slid
    }

    private struct Candidate: Sendable {
        var fingerID: Int
        var x: Double
        var y: Double
        var start: TimeInterval
        /// 触れ始めたときの開きやすさ（途中で設定が変わっても、このタッチは同じ決まりで見る）
        var thresholds: Thresholds
    }

    private var tracker = FingerTracker()
    /// 開く動きを待っているタッチ。合図した・取り消したら nil にし、そのタッチの間は作り直さない
    private var candidate: Candidate?
    /// 今の開きやすさ。NonetController が設定から入れる。待っている途中で変わっても、次のタッチから効く
    public var thresholds: Thresholds

    public init(thresholds: Thresholds = .standard) {
        self.thresholds = thresholds
    }

    /// 開く動きを待っているか
    public var isWaiting: Bool { candidate != nil }

    /// 手のひらの大きさの接触か。大きさが分からなければ false
    public static func isPalmSized(_ point: TouchPoint) -> Bool {
        guard let majorAxis = point.majorAxis else { return false }
        return majorAxis >= palmMajorAxis
    }

    /// (x, y) が上の縁の帯の中か。帯の下の縁ちょうどは中。幅はすべてなので x は見ない。NaN は外
    public static func isInEntryBand(x: Double, y: Double, thresholds: Thresholds = .standard) -> Bool {
        y >= 1 - thresholds.bandHeight
    }

    /// 触れ始めた位置からの動き（dx は右が正、dy は下（手前）が正）が開く動きか。
    /// travel 以上下へ動き、横の動きが下への動きの maxEntrySlope 倍を超えない
    public static func isEntrySlide(dx: Double, dy: Double, thresholds: Thresholds = .standard) -> Bool {
        guard dx.isFinite, dy.isFinite else { return false }
        return dy >= thresholds.travel && abs(dx) <= maxEntrySlope * dy
    }

    /// フレームを1つ渡す。isSessionActive なら、待っている候補を取り消し、新しく触れた指も待たない
    public mutating func apply(_ frame: TouchFrame, isSessionActive: Bool) -> Event {
        let time = frame.timestamp
        let change = tracker.apply(frame.points, at: time)
        switch change {
        case .none:
            return .none
        case .ended:
            candidate = nil
            return .none
        case .began, .restarted:
            candidate = nil
            guard !isSessionActive, tracker.count == 1, let finger = tracker.lastPlaced,
                  Self.isInEntryBand(x: finger.x, y: finger.y, thresholds: thresholds),
                  !Self.isPalmSized(finger.id, in: frame) else { return .none }
            candidate = Candidate(fingerID: finger.id, x: finger.x, y: finger.y, start: tracker.gestureStart, thresholds: thresholds)
            return .touchBeganInBand
        case .moved:
            guard let waiting = candidate else { return .none }
            guard !isSessionActive, tracker.count == 1, let finger = tracker.lastPlaced, finger.id == waiting.fingerID,
                  time - waiting.start <= waiting.thresholds.window,
                  !Self.isPalmSized(finger.id, in: frame) else {
                candidate = nil
                return .none
            }
            let dx = finger.x - waiting.x
            let dy = waiting.y - finger.y
            if Self.isEntrySlide(dx: dx, dy: dy, thresholds: waiting.thresholds) {
                candidate = nil
                return .slid
            }
            // 横に滑らせた（上の縁に沿ってポインタを動かしている）: このタッチでは開かない
            if abs(dx) >= waiting.thresholds.travel, abs(dx) > Self.maxEntrySlope * dy {
                candidate = nil
            }
            return .none
        }
    }

    /// frame の中の、id の触れている接触が手のひらの大きさか
    private static func isPalmSized(_ id: Int, in frame: TouchFrame) -> Bool {
        guard let point = frame.points.last(where: { $0.id == id && $0.isTouching }) else { return false }
        return isPalmSized(point)
    }
}
