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
    /// マスの半分。これより大きいと、隣のマスの中央に来ても切り替わらなくなる
    public static let maxHysteresis = 1.0 / Double(columns * 2)

    /// 今のマスを保つ余裕（トラックパッド全体を 1 とした割合）
    public let hysteresis: Double
    public let insets: GridInsets

    public init(hysteresis: Double = GridMapper.defaultHysteresis, insets: GridInsets = .zero) {
        self.hysteresis = hysteresis.isFinite ? min(max(hysteresis, 0), Self.maxHysteresis) : Self.defaultHysteresis
        self.insets = insets
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
        let marginX = hysteresis / width * Double(Self.columns)
        let marginY = hysteresis / height * Double(Self.rows)
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
