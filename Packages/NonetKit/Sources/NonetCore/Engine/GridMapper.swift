// 担当: engine
// トラックパッド上の位置 → 3×3 のマス番号
import Foundation

/// トラックパッドの縁で使わない幅（トラックパッド全体を 1 とした割合）。
/// センサーが端の 0 や 1 をなかなか返さない機種でも、端のマスを等しい大きさで使えるようにする
public struct GridInsets: Equatable, Sendable {
    /// 1辺の上限。これより大きい値は切り詰める（使える範囲が半分未満にならないように）
    public static let maxInset = 0.25

    public let left: Double
    public let right: Double
    /// 手前の縁（y = 0 の側）
    public let bottom: Double
    /// 奥の縁（y = 1 の側）
    public let top: Double

    public init(left: Double = 0, right: Double = 0, bottom: Double = 0, top: Double = 0) {
        self.left = Self.sanitize(left)
        self.right = Self.sanitize(right)
        self.bottom = Self.sanitize(bottom)
        self.top = Self.sanitize(top)
    }

    public init(all inset: Double) {
        self.init(left: inset, right: inset, bottom: inset, top: inset)
    }

    public static let zero = GridInsets()

    private static func sanitize(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), maxInset)
    }
}

/// 指の位置（x は左が 0、y は手前が 0 の 0〜1）を 3×3 のマス番号（0〜8、左上から右へ、上の行から）に変える。
/// 境界付近では今のマスを保ち（ヒステリシス）、境界の上で指が震えてもハイライトがちらつかないようにする
public struct GridMapper: Equatable, Sendable {
    public static let columns = 3
    public static let rows = 3
    public static let cellCount = columns * rows
    public static let defaultHysteresis = 0.03
    /// 縁を使わないときのマスの半分。これより大きいと、隣のマスの中央に来ても切り替わらなくなる
    public static let maxHysteresis = 1.0 / Double(columns * 2)
    /// 余裕の上限（マス1つ分を 1 とした単位）。縁を除いてマスが小さくなっても、隣のマスの中央では必ず切り替わる。
    /// ちょうど半分だと中央が余裕の端と重なり、座標の丸め誤差で結果が変わるので、センサーの分解能よりずっと小さい分だけ引く
    static let maxMarginInCells = 0.5 - 1e-9
    /// すぐにタップ（速押し・HUD でのタップ）を受け付けない、内側の境界の線の片側の幅（トラックパッドの幅・奥行きを 1 とした割合）。
    /// 線に落ちたタップはどちらのマスを狙ったのか分からないので、隣のマスを実行するより何もしないほうがよい。
    /// - マスは 1/3（約 0.333）なので、1本の線の帯は幅 0.05、マスの 15%。両側に線がある中央のマスでも、タップを受け付ける
    ///   部分が幅・奥行きとも 85%（面積 72%）、角のマスは 92.5%（面積 86%）残る
    /// - ヒステリシス（0.03）より少し狭い。ヒステリシスの幅は、来た向きでどちらのマスにもなる（どちらとも言える）位置で、
    ///   帯はその内側に収める（滑らせて選ぶときに隣のマスに切り替わる位置より遠くは拒まない）
    /// - 幅 15cm ほどのトラックパッドで線の両側 4mm ほど（奥行き 10cm ほどで 2.5mm）。指の腹の接触は 1cm ほどあるので、
    ///   中心がこの中に落ちたタップは両方のマスにかかっている
    public static let defaultTapBoundaryBand = 0.025
    /// 帯の上限（マス1つ分を 1 とした単位）。縁を除いてマスが小さくなっても、中央のマスに半分は残す
    static let maxTapBoundaryBandInCells = 0.25

    /// 今のマスを保つ余裕（トラックパッド全体を 1 とした割合）。縁を除いてマスが小さくなっても、実際の余裕はマスの半分で止める
    public let hysteresis: Double
    public let insets: GridInsets
    /// すぐにタップを受け付けない、内側の境界の線の片側の幅（トラックパッド全体を 1 とした割合）。0 なら帯は無い
    public let tapBoundaryBand: Double

    public init(hysteresis: Double = GridMapper.defaultHysteresis, insets: GridInsets = .zero, tapBoundaryBand: Double = GridMapper.defaultTapBoundaryBand) {
        self.hysteresis = hysteresis.isFinite ? min(max(hysteresis, 0), Self.maxHysteresis) : Self.defaultHysteresis
        self.insets = insets
        self.tapBoundaryBand = tapBoundaryBand.isFinite ? max(tapBoundaryBand, 0) : Self.defaultTapBoundaryBand
    }

    /// 内側の境界の線（縦2本・横2本）から tapBoundaryBand 以内（ちょうども含む）か。2本の線が交わる角の近くは、どちらかの線の帯に入れば帯の中。
    /// トラックパッドの縁は境界ではない。速押しと HUD でのタップは、置いた位置がこの中なら実行しない
    public func isInTapBoundaryBand(x: Double, y: Double) -> Bool {
        guard tapBoundaryBand > 0 else { return false }
        let width = 1 - insets.left - insets.right
        let height = 1 - insets.bottom - insets.top
        let column = Self.normalize((x - insets.left) / width) * Double(Self.columns)
        let row = (1 - Self.normalize((y - insets.bottom) / height)) * Double(Self.rows)
        let bandX = min(tapBoundaryBand / width * Double(Self.columns), Self.maxTapBoundaryBandInCells)
        let bandY = min(tapBoundaryBand / height * Double(Self.rows), Self.maxTapBoundaryBandInCells)
        return Self.isNearInnerLine(column, count: Self.columns, band: bandX)
            || Self.isNearInnerLine(row, count: Self.rows, band: bandY)
    }

    public func isInTapBoundaryBand(_ point: TouchPoint) -> Bool {
        isInTapBoundaryBand(x: point.x, y: point.y)
    }

    /// position（マス1つ分を 1 とした単位）が、内側の線（1〜count-1）から band 以内か。縁（0 と count）は線ではない
    private static func isNearInnerLine(_ position: Double, count: Int, band: Double) -> Bool {
        let nearest = min(max(position.rounded(), 1), Double(count - 1))
        return abs(position - nearest) <= band
    }

    /// current は直前にこの指に割り当てたマス。新しく置いた指なら nil
    public func cell(x: Double, y: Double, current: Int? = nil) -> Int {
        let width = 1 - insets.left - insets.right
        let height = 1 - insets.bottom - insets.top
        // 列は左から、行は奥（y = 1）から数える。単位はマス1つ分
        let column = Self.normalize((x - insets.left) / width) * Double(Self.columns)
        let row = (1 - Self.normalize((y - insets.bottom) / height)) * Double(Self.rows)
        let candidate = Self.index(column: column, row: row)

        guard let current, (0..<Self.cellCount).contains(current), current != candidate, hysteresis > 0 else {
            return candidate
        }
        // 縁を除くとマスが小さくなり、トラックパッド単位の余裕がマスの半分を超えうるので、軸ごとにマス単位で抑える
        let marginX = min(hysteresis / width * Double(Self.columns), Self.maxMarginInCells)
        let marginY = min(hysteresis / height * Double(Self.rows), Self.maxMarginInCells)
        let currentColumn = Double(current % Self.columns)
        let currentRow = Double(current / Self.columns)
        let staysInside = column >= currentColumn - marginX && column <= currentColumn + 1 + marginX
            && row >= currentRow - marginY && row <= currentRow + 1 + marginY
        return staysInside ? current : candidate
    }

    public func cell(for point: TouchPoint, current: Int? = nil) -> Int {
        cell(x: point.x, y: point.y, current: current)
    }

    /// 0〜1 に収める。NaN は中央とみなす（センサーの異常値でマスが決まらないことを避ける）
    private static func normalize(_ value: Double) -> Double {
        guard !value.isNaN else { return 0.5 }
        return min(max(value, 0), 1)
    }

    private static func index(column: Double, row: Double) -> Int {
        let c = min(Int(column), columns - 1)
        let r = min(Int(row), rows - 1)
        return r * columns + c
    }
}
