// 担当: engine。ポインタで選ぶ: 9マスを開いている間、ポインタはふだんどおり動き、HUD（ポインタを中心にした円）の上の向きと距離でマスを選ぶ
import CoreGraphics
import Foundation

/// ポインタの位置を、エンジンが受け取る指の位置（0〜1。x は左が 0、y は手前が 0）に合成する。
/// HUD の枠（HUDPresenting.show が返す、円を囲む正方形。主画面の左上が原点で y が下向き）の中心からの向きと距離を
/// RadialMapper でマスか外枠に変え、そのマスの中央（外枠なら帯の中央）の座標をエンジンに渡す。
/// エンジン（SessionEngine・GridMapper）は 3×3 の座標のまま変えない: 留まる時間・少し長く止めるマス・外枠に止めるとページや層、はそのまま働く。
/// 鍵の境目のちらつきは RadialMapper のヒステリシスで防ぐので、エンジンのヒステリシスと境目の帯（マスの中央には無い）は働かない
public struct ControllerPointerSelection: Equatable, Sendable {
    public static let mapper = RadialMapper()

    /// 直前の場所（ヒステリシス用）。開いた直後は nil
    public private(set) var zone: GridZone?
    /// 外枠で止めている側
    public private(set) var pagingEdge: PageEdge?
    /// 開いてから、ポインタが中央の外へ出た。それまでは中央にいても外枠にいることにする（開いた瞬間に離せば、必ず何もせずに閉じる）。
    /// 外へ出てから中央へ戻せば、中央のマスを選ぶ
    public private(set) var hasLeftCenter = false

    /// 開いた直後で、ポインタがまだ中央から出ていない。エンジンには外枠として伝えているが、HUD は薄くしない（HUDModel.isWaitingAtCenter）
    public var isWaitingAtCenter: Bool { !hasLeftCenter }

    public init() {}

    /// 開いたときにポインタを置く場所: 円の中心
    public static func startPoint(in map: CGRect) -> CGPoint {
        CGPoint(x: map.midX, y: map.midY)
    }

    /// ポインタの位置をマスか外枠に変え、エンジンに渡す指の位置にする。枠の大きさが 0 や、位置が NaN なら nil
    public mutating func position(of pointer: CGPoint, in map: CGRect) -> (x: Double, y: Double)? {
        guard map.width > 0, map.height > 0, pointer.x.isFinite, pointer.y.isFinite else { return nil }
        // 枠は倍率（HUDModel.scale）を掛けた大きさなので、倍率 1 のポイントに戻す
        let unit = map.width / 2 / RadialLayout.outerRadius
        let dx = (pointer.x - map.midX) / unit
        let dy = (pointer.y - map.midY) / unit
        let next = Self.mapper.zone(dx: dx, dy: dy, current: zone)
        zone = next
        pagingEdge = next == .frame ? Self.mapper.pagingEdge(dx: dx, dy: dy, current: pagingEdge) : nil
        if next == .cell(RadialLayout.centerCell) {
            guard hasLeftCenter else { return Self.gridPosition(for: .frame, pagingEdge: nil) }
        } else {
            hasLeftCenter = true
        }
        return Self.gridPosition(for: next, pagingEdge: pagingEdge)
    }

    /// 1本指のフレームなら、その指の位置をポインタから合成した位置に置き換える。2本以上の指（スワイプでページを切り替える）は実物の位置のまま。
    /// ポインタの位置か HUD の枠が分からなければ、実物の位置のまま
    public mutating func frame(_ frame: TouchFrame, pointer: CGPoint?, map: CGRect?) -> TouchFrame {
        guard let pointer, let map, frame.touching.count == 1,
              let index = frame.points.firstIndex(where: \.isTouching),
              let position = position(of: pointer, in: map) else { return frame }
        var result = frame
        result.points[index].x = position.x
        result.points[index].y = position.y
        return result
    }

    /// 合成する指の位置。マスはその中央、外枠は切り替える側の帯の中央（左右・上下）。
    /// どの側でもない外枠（帯の外端より遠い・開いた直後）は奥の左の角: GridMapper.pagingEdge がどの側にもしない場所
    public static func gridPosition(for zone: GridZone, pagingEdge: PageEdge?) -> (x: Double, y: Double) {
        let insets = GridInsets.cancelFrame
        switch zone {
        case .cell(let index):
            return cellCenter(index)
        case .frame:
            switch pagingEdge {
            case .left?: return (insets.left / 2, 0.5)
            case .right?: return (1 - insets.right / 2, 0.5)
            case .up?: return (0.5, 1 - insets.top / 2)
            case .down?: return (0.5, insets.bottom / 2)
            case nil: return (insets.left / 2, 1 - insets.top / 2)
            }
        }
    }

    /// マスの中央（外枠 GridInsets.cancelFrame の内側を 3×3 に分けたもの。行は奥から）。範囲外は端のマス
    public static func cellCenter(_ index: Int) -> (x: Double, y: Double) {
        let insets = GridInsets.cancelFrame
        let clamped = min(max(index, 0), GridMapper.cellCount - 1)
        let column = Double(clamped % GridMapper.columns)
        let row = Double(clamped / GridMapper.columns)
        let width = 1 - insets.left - insets.right
        let height = 1 - insets.bottom - insets.top
        return (
            insets.left + width * (column + 0.5) / Double(GridMapper.columns),
            insets.bottom + height * (1 - (row + 0.5) / Double(GridMapper.rows))
        )
    }
}
