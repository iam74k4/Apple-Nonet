// 担当: engine
// トラックパッド上の位置 → 3×3 のマス番号
import Foundation

/// 9マスの外側に残す幅（トラックパッド全体を 1 とした割合）。9マスはその内側を 3×3 に分ける。
/// セッションでは、この部分が「外枠」（指を出して離すと何もせずに閉じる場所。GridInsets.cancelFrame）になる
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

    /// 外枠（やめる場所）の幅。9マスはその内側（幅の 86%・奥行きの 78%）に並ぶ。
    /// - 左右 0.07: 幅 15cm ほどで 1cm ほど。滑らせて出すには十分な幅で、9マスの幅は 86% 残る
    /// - 手前 0.10: 押し込むと奥より手前が沈み、手のひらや親指も手前の縁に来やすいので、左右より少し広くする
    /// - 奥 0.12: 開く動きは上の縁の帯（EdgeSlideRecognizer.entryBandHeight 0.06）から下へ entryTravel（0.05）動いた
    ///   ところで合図するので、開いた瞬間の指は奥から 0.11 までの外枠にいる（開いただけで上の段のマスを光らせない）
    public static let cancelFrame = GridInsets(left: 0.07, right: 0.07, bottom: 0.10, top: 0.12)

    private static func sanitize(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), maxInset)
    }
}

/// 指のいる場所。9マスのどれかか、その外側の枠（外枠。insets の部分）
public enum GridZone: Equatable, Sendable {
    /// マス（0〜8）
    case cell(Int)
    /// 外枠。ここで指を離すと何もせずに閉じる
    case frame

    public var cell: Int? {
        if case .cell(let index) = self { return index }
        return nil
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
    /// 指を離しても実行しない、内側の境界の線の片側の幅（トラックパッドの幅・奥行きを 1 とした割合）。
    /// 線の上で離した指はどちらのマスを狙ったのか分からないので、隣のマスを実行するより何もしないほうがよい。
    /// - 外枠（GridInsets.cancelFrame）の内側のマスは幅 0.287・奥行き 0.26 ほどなので、1本の線の帯は幅 0.05、
    ///   マスのおよそ 17〜19%。両側に線がある中央のマスでも、幅・奥行きとも 8 割ほど残る
    /// - ヒステリシス（0.03）より少し狭い。ヒステリシスの幅は、来た向きでどちらのマスにもなる（どちらとも言える）位置で、
    ///   帯はその内側に収める（滑らせて選ぶときに隣のマスに切り替わる位置より遠くは拒まない）
    /// - 幅 15cm ほどのトラックパッドで線の両側 4mm ほど（奥行き 10cm ほどで 2.5mm）。指の腹の接触は 1cm ほどあるので、
    ///   中心がこの中で離れた指は両方のマスにかかっている
    public static let defaultBoundaryBand = 0.025
    /// 帯の上限（マス1つ分を 1 とした単位）。縁を除いてマスが小さくなっても、中央のマスに半分は残す
    static let maxBoundaryBandInCells = 0.25
    /// 外枠と9マスの境目で今の場所を保つ余裕（トラックパッド全体を 1 とした割合）。幅 15cm ほどで 2mm ほど。
    /// 止めた指の揺れ（1mm より十分小さい）で、端のマスと外枠が入れ替わってハイライトと触覚がちらつかないようにし、
    /// 外枠（左右 0.07）の大半は残す
    public static let defaultFrameHysteresis = 0.015

    /// 今のマスを保つ余裕（トラックパッド全体を 1 とした割合）。縁を除いてマスが小さくなっても、実際の余裕はマスの半分で止める
    public let hysteresis: Double
    public let insets: GridInsets
    /// 指を離しても実行しない、内側の境界の線の片側の幅（トラックパッド全体を 1 とした割合）。0 なら帯は無い
    public let boundaryBand: Double
    /// 外枠と9マスの境目で今の場所を保つ余裕（トラックパッド全体を 1 とした割合）
    public let frameHysteresis: Double

    public init(
        hysteresis: Double = GridMapper.defaultHysteresis,
        insets: GridInsets = .zero,
        boundaryBand: Double = GridMapper.defaultBoundaryBand,
        frameHysteresis: Double = GridMapper.defaultFrameHysteresis
    ) {
        self.hysteresis = hysteresis.isFinite ? min(max(hysteresis, 0), Self.maxHysteresis) : Self.defaultHysteresis
        self.insets = insets
        self.boundaryBand = boundaryBand.isFinite ? max(boundaryBand, 0) : Self.defaultBoundaryBand
        // 外枠の幅を超える余裕は意味が無い（外枠に出ても切り替わらなくなる）ので、いちばん狭い外枠の半分で止める
        let narrowest = min(insets.left, insets.right, insets.bottom, insets.top)
        let frame = frameHysteresis.isFinite ? max(frameHysteresis, 0) : Self.defaultFrameHysteresis
        self.frameHysteresis = min(frame, narrowest / 2)
    }

    /// 内側の境界の線（縦2本・横2本）から boundaryBand 以内（ちょうども含む）か。2本の線が交わる角の近くは、どちらかの線の帯に入れば帯の中。
    /// 9マスの外周（外枠との境目）は境界ではない。指をここで離しても実行しない
    public func isInBoundaryBand(x: Double, y: Double) -> Bool {
        guard boundaryBand > 0 else { return false }
        let width = 1 - insets.left - insets.right
        let height = 1 - insets.bottom - insets.top
        let column = Self.normalize((x - insets.left) / width) * Double(Self.columns)
        let row = (1 - Self.normalize((y - insets.bottom) / height)) * Double(Self.rows)
        let bandX = min(boundaryBand / width * Double(Self.columns), Self.maxBoundaryBandInCells)
        let bandY = min(boundaryBand / height * Double(Self.rows), Self.maxBoundaryBandInCells)
        return Self.isNearInnerLine(column, count: Self.columns, band: bandX)
            || Self.isNearInnerLine(row, count: Self.rows, band: bandY)
    }

    public func isInBoundaryBand(_ point: TouchPoint) -> Bool {
        isInBoundaryBand(x: point.x, y: point.y)
    }

    /// 9マスの範囲（外枠の内側）に入っているか。margin だけ内側（負なら外側）に狭めた範囲で確かめる。境目ちょうどは中。NaN は外
    private func isInsideGrid(x: Double, y: Double, margin: Double) -> Bool {
        x >= insets.left + margin && x <= 1 - insets.right - margin
            && y >= insets.bottom + margin && y <= 1 - insets.top - margin
    }

    /// 指のいる場所。current は直前にこの指に割り当てた場所（新しく見る指なら nil）。
    /// 外枠と9マスの境目では frameHysteresis だけ今の場所を保ち、9マスの中ではマスの境界のヒステリシスで今のマスを保つ
    public func zone(x: Double, y: Double, current: GridZone? = nil) -> GridZone {
        let isInside: Bool = switch current {
        case nil: isInsideGrid(x: x, y: y, margin: 0)
        // 外枠から入るときは、境目から frameHysteresis 入ってから
        case .frame?: isInsideGrid(x: x, y: y, margin: frameHysteresis)
        // マスから出るときは、境目から frameHysteresis 出てから
        case .cell?: isInsideGrid(x: x, y: y, margin: -frameHysteresis)
        }
        guard isInside else { return .frame }
        return .cell(cell(x: x, y: y, current: current?.cell))
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
