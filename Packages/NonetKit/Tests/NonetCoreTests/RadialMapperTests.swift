// 担当: engine。円形の HUD: ポインタの向きと距離 → マスか外枠
import Foundation
@testable import NonetCore
import Testing

@Suite struct RadialMapperTests {
    let mapper = RadialMapper()

    /// 向き（度）と距離から、中心からの位置にする
    static func point(_ angle: Double, _ distance: Double) -> (dx: Double, dy: Double) {
        let radians = angle * .pi / 180
        return (distance * cos(radians), distance * sin(radians))
    }

    @Test("鍵の並び: 上から時計回りに 上・右上・右・右下・下・左下・左・左上（設定の 3×3 と同じ向き）")
    func slots() {
        #expect(RadialLayout.ringCells == [1, 2, 5, 8, 7, 6, 3, 0])
        #expect(RadialLayout.slot(ofCell: 1) == 0 && RadialLayout.slot(ofCell: 5) == 2 && RadialLayout.slot(ofCell: 0) == 7)
        #expect(RadialLayout.slot(ofCell: 4) == nil && RadialLayout.slot(ofCell: 9) == nil)
        #expect(RadialLayout.angle(ofSlot: 0) == -90 && RadialLayout.angle(ofSlot: 2) == 0 && RadialLayout.angle(ofSlot: 4) == 90)
        let up = RadialLayout.position(ofCell: 1)!
        #expect(abs(up.x) < 1e-9 && abs(up.y + RadialLayout.keyRadius) < 1e-9)
        let right = RadialLayout.position(ofCell: 5)!
        #expect(abs(right.x - RadialLayout.keyRadius) < 1e-9 && abs(right.y) < 1e-9)
        #expect(RadialLayout.position(ofCell: 4)! == (0, 0))
        #expect(RadialLayout.position(ofCell: 9) == nil)
    }

    @Test("向きからいちばん近い鍵を選ぶ。境目の向きも、360° を回った向きも")
    func nearestSlot() {
        #expect(RadialMapper.slot(at: -90) == 0)
        #expect(RadialMapper.slot(at: -45) == 1)
        #expect(RadialMapper.slot(at: 0) == 2)
        #expect(RadialMapper.slot(at: 45) == 3)
        #expect(RadialMapper.slot(at: 90) == 4)
        #expect(RadialMapper.slot(at: 135) == 5)
        #expect(RadialMapper.slot(at: 180) == 6)
        #expect(RadialMapper.slot(at: -135) == 7)
        #expect(RadialMapper.slot(at: -100) == 0 && RadialMapper.slot(at: -80) == 0)
        #expect(RadialMapper.slot(at: 170) == 6 && RadialMapper.slot(at: -170) == 6)
        #expect(RadialMapper.difference(170, -170) == -20)
        #expect(RadialMapper.difference(-170, 170) == 20)
    }

    @Test("距離で中央・鍵・外枠、向きで鍵が決まる", arguments: [
        (0.0, 0.0, GridZone.cell(4)),
        (0.0, 49.0, .cell(4)),
        (-90.0, 108.0, .cell(1)),
        (-45.0, 108.0, .cell(2)),
        (0.0, 60.0, .cell(5)),
        (45.0, 130.0, .cell(8)),
        (90.0, 108.0, .cell(7)),
        (135.0, 108.0, .cell(6)),
        (180.0, 108.0, .cell(3)),
        (-135.0, 108.0, .cell(0)),
        (0.0, 134.0, .cell(5)),
        (0.0, 135.0, .frame),
        (-90.0, 500.0, .frame),
    ])
    func zones(angle: Double, distance: Double, expected: GridZone) {
        let p = Self.point(angle, distance)
        #expect(mapper.zone(dx: p.dx, dy: p.dy) == expected)
    }

    @Test("鍵の境目では今の鍵を保つ（角度のヒステリシス 4°）")
    func angularHysteresis() {
        // 右（0°）と右下（45°）の境目は 22.5°
        let past = Self.point(25, 108)
        #expect(mapper.zone(dx: past.dx, dy: past.dy, current: .cell(5)) == .cell(5))
        #expect(mapper.zone(dx: past.dx, dy: past.dy) == .cell(8))
        let farther = Self.point(27, 108)
        #expect(mapper.zone(dx: farther.dx, dy: farther.dy, current: .cell(5)) == .cell(8))
        // 反対側も同じ。外枠や中央から来たときは保たない
        let other = Self.point(-25, 108)
        #expect(mapper.zone(dx: other.dx, dy: other.dy, current: .cell(5)) == .cell(5))
        #expect(mapper.zone(dx: past.dx, dy: past.dy, current: .frame) == .cell(8))
        #expect(mapper.zone(dx: past.dx, dy: past.dy, current: .cell(4)) == .cell(8))
        // 上（-90°）と左上（-135°）の境目（-112.5°）: 360° を回る向きでも保つ
        let wrap = Self.point(-115, 108)
        #expect(mapper.zone(dx: wrap.dx, dy: wrap.dy, current: .cell(1)) == .cell(1))
        #expect(mapper.zone(dx: wrap.dx, dy: wrap.dy, current: .cell(0)) == .cell(0))
    }

    @Test("中央・鍵・外枠の境目では今の場所を保つ（距離のヒステリシス 6pt）")
    func radialHysteresis() {
        // 中央にいる: 50 を超えても 56 までは中央
        #expect(mapper.zone(dx: 54, dy: 0, current: .cell(4)) == .cell(4))
        #expect(mapper.zone(dx: 57, dy: 0, current: .cell(4)) == .cell(5))
        // 鍵にいる: 50 を切っても 44 までは鍵
        #expect(mapper.zone(dx: 47, dy: 0, current: .cell(5)) == .cell(5))
        #expect(mapper.zone(dx: 43, dy: 0, current: .cell(5)) == .cell(4))
        // 鍵にいる: 134 を超えても 140 までは鍵
        #expect(mapper.zone(dx: 138, dy: 0, current: .cell(5)) == .cell(5))
        #expect(mapper.zone(dx: 141, dy: 0, current: .cell(5)) == .frame)
        // 外枠にいる: 134 を切っても 128 までは外枠
        #expect(mapper.zone(dx: 130, dy: 0, current: .frame) == .frame)
        #expect(mapper.zone(dx: 127, dy: 0, current: .frame) == .cell(5))
        // 外枠から一気に中央へ（ありえないが壊れない）
        #expect(mapper.zone(dx: 10, dy: 0, current: .frame) == .cell(4))
    }

    @Test("壊れた位置は今の場所（無ければ外枠）。余裕は上限で止める")
    func brokenInputs() {
        #expect(mapper.zone(dx: .nan, dy: 0) == .frame)
        #expect(mapper.zone(dx: .infinity, dy: 0, current: .cell(2)) == .cell(2))
        let wide = RadialMapper(angularHysteresis: 100, radialHysteresis: 1000)
        #expect(wide.angularHysteresis == RadialLayout.slotAngle / 2)
        #expect(wide.radialHysteresis == (RadialLayout.outerRadius - RadialLayout.centerRadius) / 2)
        let broken = RadialMapper(angularHysteresis: .nan, radialHysteresis: -1)
        #expect(broken.angularHysteresis == RadialMapper.defaultAngularHysteresis && broken.radialHysteresis == 0)
    }

    @Test("外枠の帯を上下左右に分ける: 真横から上下 45° までが左右（ページ）、残りが上下（層）。斜めは左右")
    func pagingEdges() {
        func edge(_ angle: Double, current: PageEdge? = nil, distance: Double = 150) -> PageEdge? {
            let p = Self.point(angle, distance)
            return mapper.pagingEdge(dx: p.dx, dy: p.dy, current: current)
        }
        #expect(edge(0) == .right && edge(44) == .right && edge(-44) == .right && edge(45) == .right)
        #expect(edge(180) == .left && edge(140) == .left && edge(-140) == .left)
        // y は下向き: 90° が下、-90° が上
        #expect(edge(46) == .down && edge(90) == .down && edge(130) == .down)
        #expect(edge(-46) == .up && edge(-90) == .up && edge(-130) == .up)
        // 止めている側の端では、角度のヒステリシスの分だけ保つ
        #expect(edge(48, current: .right) == .right)
        #expect(edge(50, current: .right) == .down)
        #expect(edge(-132, current: .left) == .left)
        #expect(edge(42, current: .down) == .down)
        #expect(edge(40, current: .down) == .right)
        #expect(mapper.pagingEdge(dx: 0, dy: 0) == nil)
        #expect(mapper.pagingEdge(dx: .nan, dy: 0) == nil)
    }

    @Test("帯の外端（pagingOuterRadius）より遠くでは、どの側でもない（止めても何も起きない）。止めている側は距離のヒステリシスの分だけ保つ")
    func beyondTheBandIsNoSide() {
        func edge(_ angle: Double, _ distance: Double, current: PageEdge? = nil) -> PageEdge? {
            let p = Self.point(angle, distance)
            return mapper.pagingEdge(dx: p.dx, dy: p.dy, current: current)
        }
        let outer = RadialLayout.pagingOuterRadius
        #expect(outer > RadialLayout.outerRadius)
        #expect(edge(0, outer - 1) == .right)
        #expect(edge(0, outer + 1) == nil)
        #expect(edge(90, outer + 1) == nil)
        #expect(edge(0, outer + mapper.radialHysteresis - 1, current: .right) == .right)
        #expect(edge(0, outer + mapper.radialHysteresis + 1, current: .right) == nil)
    }
}
