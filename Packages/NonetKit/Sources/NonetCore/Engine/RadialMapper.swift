// 担当: engine
// 円形の HUD: ポインタの中心からの向きと距離 → 9マスの番号か外枠
import Foundation

/// 円形の HUD の寸法（倍率 1 のポイント。HUD の中心が原点、y は下向き）。
/// HUD（NonetUI）が描く位置と、ポインタの位置をマスに写す RadialMapper が同じ値を使う。
/// 8つの鍵（アイコン）が半径 keyRadius の円の上に 45° おきに並び、真ん中に 9つ目（中央のマス）。皿も輪も無く、アイコンだけ
public enum RadialLayout {
    /// ここより外は外枠（離すとやめる。止めると、左右はページ、上下は層を切り替える）。見えない線だが、越えるとアイコンが全部薄くなるので手がすぐ覚える
    public static let outerRadius: Double = 134
    /// 外枠のうち、止めると切り替える帯の外端。これより遠くで止めても何も起きない（迷って止まりたいときの逃げ場。離せばどこでもやめる）
    public static let pagingOuterRadius: Double = 210
    /// 8つの鍵の中心が乗る円
    public static let keyRadius: Double = 108
    /// ここより内側は中央のマス（鍵と中央の中ほど。鍵の円 108 と中央の間で、中央の玉（半径 22）より十分広い）
    public static let centerRadius: Double = 50
    /// 鍵の並び: 上から時計回りに、マスの番号（上 1・右上 2・右 5・右下 8・下 7・左下 6・左 3・左上 0）。
    /// 設定画面の 3×3 と同じ向き（左上のマスは左上の鍵）
    public static let ringCells = [1, 2, 5, 8, 7, 6, 3, 0]
    public static let centerCell = 4
    /// 鍵と鍵の間の角度
    public static let slotAngle: Double = 360 / Double(ringCells.count)
    /// 外枠の帯を上下左右に分ける角度（それぞれの真ん中の向きから、この角度まで。斜めは左右に入る）
    public static let pagingHalfAngle: Double = 45

    /// 鍵 slot（0 が上、時計回り）の中心の向き（度。右が 0、時計回り）
    public static func angle(ofSlot slot: Int) -> Double {
        -90 + slotAngle * Double(slot)
    }

    /// マスの番号 → 鍵の位置（0 が上、時計回り）。中央のマスと範囲外は nil
    public static func slot(ofCell cell: Int) -> Int? {
        ringCells.firstIndex(of: cell)
    }

    /// マスの番号 → 中心の位置（倍率 1 のポイント）。中央のマスは原点、範囲外は nil
    public static func position(ofCell cell: Int) -> (x: Double, y: Double)? {
        if cell == centerCell { return (0, 0) }
        guard let slot = slot(ofCell: cell) else { return nil }
        let radians = angle(ofSlot: slot) * .pi / 180
        return (keyRadius * cos(radians), keyRadius * sin(radians))
    }
}

/// ポインタの中心からの位置（倍率 1 のポイント）を、マスか外枠に変える。
/// 鍵と鍵の境目では今の鍵を保ち（角度のヒステリシス）、中央・鍵・外枠の境目では今の場所を保つ（距離のヒステリシス）ので、
/// 境目で指が震えてもハイライトと触覚がちらつかない
public struct RadialMapper: Equatable, Sendable {
    /// 鍵の境目で今の鍵を保つ角度（度）。鍵の間は 45° なので、境目の両側 4° まで
    public static let defaultAngularHysteresis: Double = 4
    /// 中央・鍵・外枠の境目で今の場所を保つ距離（倍率 1 のポイント）
    public static let defaultRadialHysteresis: Double = 6

    public let angularHysteresis: Double
    public let radialHysteresis: Double

    public init(angularHysteresis: Double = RadialMapper.defaultAngularHysteresis, radialHysteresis: Double = RadialMapper.defaultRadialHysteresis) {
        self.angularHysteresis = angularHysteresis.isFinite ? min(max(angularHysteresis, 0), RadialLayout.slotAngle / 2) : Self.defaultAngularHysteresis
        let maxRadial = (RadialLayout.outerRadius - RadialLayout.centerRadius) / 2
        self.radialHysteresis = radialHysteresis.isFinite ? min(max(radialHysteresis, 0), maxRadial) : Self.defaultRadialHysteresis
    }

    /// current は直前にこのポインタに割り当てた場所（開いた直後なら nil）
    public func zone(dx: Double, dy: Double, current: GridZone? = nil) -> GridZone {
        guard dx.isFinite, dy.isFinite else { return current ?? .frame }
        let distance = hypot(dx, dy)
        let currentSlot = current?.cell.flatMap(RadialLayout.slot(ofCell:))
        let isCenter = current?.cell == RadialLayout.centerCell
        let isFrame = current == .frame
        // 中央との境目: 中央にいるときは出るまで、鍵にいるときは入るまで余裕を持たせる
        let centerLimit = RadialLayout.centerRadius + (isCenter ? radialHysteresis : currentSlot != nil ? -radialHysteresis : 0)
        if distance <= centerLimit { return .cell(RadialLayout.centerCell) }
        // 外枠との境目: 外枠にいるときは戻るまで、鍵にいるときは出るまで余裕を持たせる
        let outerLimit = RadialLayout.outerRadius + (isFrame ? -radialHysteresis : currentSlot != nil ? radialHysteresis : 0)
        if distance > outerLimit { return .frame }
        let angle = atan2(dy, dx) * 180 / .pi
        if let currentSlot, abs(Self.difference(angle, RadialLayout.angle(ofSlot: currentSlot))) <= RadialLayout.slotAngle / 2 + angularHysteresis {
            return .cell(RadialLayout.ringCells[currentSlot])
        }
        return .cell(RadialLayout.ringCells[Self.slot(at: angle)])
    }

    /// 外枠のうち、止めると切り替える側（左右はページ、上は前の層、下は次の層）。外枠にいるとき（zone が .frame）だけ呼ぶ。
    /// 帯の外端（pagingOuterRadius）より遠ければ nil（止めても何も起きない）。
    /// current はいま止めている側。その側の端と帯の外端では、ヒステリシスの分だけ保つ（境目で止めた指の揺れで数え直さないように）
    public func pagingEdge(dx: Double, dy: Double, current: PageEdge? = nil) -> PageEdge? {
        guard dx.isFinite, dy.isFinite, dx != 0 || dy != 0 else { return nil }
        let outerLimit = RadialLayout.pagingOuterRadius + (current == nil ? 0 : radialHysteresis)
        guard hypot(dx, dy) <= outerLimit else { return nil }
        let angle = atan2(dy, dx) * 180 / .pi
        // y は下向きなので、上は -90°、下は 90°
        let centers: [(PageEdge, Double)] = [(.right, 0), (.left, 180), (.up, -90), (.down, 90)]
        let limit = RadialLayout.pagingHalfAngle
        if let current, let center = centers.first(where: { $0.0 == current })?.1,
           abs(Self.difference(angle, center)) <= limit + angularHysteresis {
            return current
        }
        return centers.first { abs(Self.difference(angle, $0.1)) <= limit }?.0
    }

    /// 向き（度）にいちばん近い鍵（0 が上、時計回り）
    static func slot(at angle: Double) -> Int {
        let count = RadialLayout.ringCells.count
        let turns = (angle + 90) / RadialLayout.slotAngle
        let rounded = Int(turns.rounded()) % count
        return rounded < 0 ? rounded + count : rounded
    }

    /// 2つの向きの差（-180〜180）
    static func difference(_ a: Double, _ b: Double) -> Double {
        var delta = (a - b).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta <= -180 { delta += 360 }
        return delta
    }
}
