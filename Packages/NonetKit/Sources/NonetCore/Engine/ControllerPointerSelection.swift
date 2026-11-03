// 担当: engine。ポインタで選ぶ: 9マスを開いている間、ポインタはふだんどおり動き、HUD の地図の上でポインタが乗っているマスを選ぶ
import CoreGraphics
import Foundation

/// ポインタの位置を、トラックパッドの上の指の位置（0〜1。x は左が 0、y は手前が 0）に写す。
/// 地図の枠（HUDPresenting.prepare）は主画面の左上が原点で y が下向きなので、枠の上辺が奥（y = 1）。
/// 枠の外は縁に収める（外枠の帯に入るので、離すとやめる・左右に止めるとページ、が地図の外でも効く）
enum ControllerPointerSelection {
    /// 開いたときにポインタを置く場所: 地図の奥の外枠の帯の中央（指は上の縁から入ってくるので、そのまま下へ動かすとマスに入る）
    static func startPoint(in map: CGRect) -> CGPoint {
        CGPoint(x: map.midX, y: map.minY + map.height * GridInsets.cancelFrame.top / 2)
    }

    static func position(of pointer: CGPoint, in map: CGRect) -> (x: Double, y: Double)? {
        guard map.width > 0, map.height > 0, pointer.x.isFinite, pointer.y.isFinite else { return nil }
        let x = min(max((pointer.x - map.minX) / map.width, 0), 1)
        let y = min(max(1 - (pointer.y - map.minY) / map.height, 0), 1)
        return (x, y)
    }

    /// 1本指のフレームなら、その指の位置をポインタの位置に置き換える。2本以上の指（スワイプでページを切り替える）は実物の位置のまま。
    /// ポインタの位置か地図の枠が分からなければ、実物の位置のまま
    static func frame(_ frame: TouchFrame, pointer: CGPoint?, map: CGRect?) -> TouchFrame {
        guard let pointer, let map, frame.touching.count == 1,
              let index = frame.points.firstIndex(where: \.isTouching),
              let position = position(of: pointer, in: map) else { return frame }
        var result = frame
        result.points[index].x = position.x
        result.points[index].y = position.y
        return result
    }
}
