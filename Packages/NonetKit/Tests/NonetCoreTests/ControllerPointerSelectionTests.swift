// 担当: engine。ポインタで選ぶ: 開いている間、HUD（ポインタを中心にした円）の上のポインタの向きと距離でマスを選ぶ
import CoreGraphics
import Foundation
@testable import NonetCore
import Testing

@MainActor
@Suite struct ControllerPointerSelectionTests {
    /// HUD の枠（円を囲む正方形。主画面の左上が原点、y が下向き）。中心は (234, 234)
    static let map = CGRect(x: 100, y: 100, width: 268, height: 268)
    static let center = CGPoint(x: 234, y: 234)

    static func pointer(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint {
        CGPoint(x: center.x + dx, y: center.y + dy)
    }

    static func near(_ a: (x: Double, y: Double)?, _ b: (x: Double, y: Double)) -> Bool {
        guard let a else { return false }
        return abs(a.x - b.x) < 1e-9 && abs(a.y - b.y) < 1e-9
    }

    @Test("合成する位置: マスはその中央、外枠は奥の帯の中央、止めている側があれば左右の帯の中央")
    func gridPositions() {
        let frame = GridInsets.cancelFrame
        let width = 1 - frame.left - frame.right
        let height = 1 - frame.bottom - frame.top
        // 中央のマスの中央。外枠は奥が手前より広いので、y はちょうど 0.5 ではない
        #expect(Self.near(ControllerPointerSelection.cellCenter(4), (0.5, frame.bottom + height / 2)))
        #expect(Self.near(ControllerPointerSelection.cellCenter(0), (frame.left + width / 6, frame.bottom + height * 5 / 6)))
        #expect(Self.near(ControllerPointerSelection.cellCenter(8), (1 - frame.right - width / 6, frame.bottom + height / 6)))
        #expect(Self.near(ControllerPointerSelection.cellCenter(-1), ControllerPointerSelection.cellCenter(0)))
        #expect(Self.near(ControllerPointerSelection.cellCenter(20), ControllerPointerSelection.cellCenter(8)))
        // どの側でもない外枠は奥の左の角、切り替える側があればその帯の中央
        #expect(Self.near(ControllerPointerSelection.gridPosition(for: .frame, pagingEdge: nil), (frame.left / 2, 1 - frame.top / 2)))
        #expect(Self.near(ControllerPointerSelection.gridPosition(for: .frame, pagingEdge: .left), (frame.left / 2, 0.5)))
        #expect(Self.near(ControllerPointerSelection.gridPosition(for: .frame, pagingEdge: .right), (1 - frame.right / 2, 0.5)))
        #expect(Self.near(ControllerPointerSelection.gridPosition(for: .frame, pagingEdge: .up), (0.5, 1 - frame.top / 2)))
        #expect(Self.near(ControllerPointerSelection.gridPosition(for: .frame, pagingEdge: .down), (0.5, frame.bottom / 2)))
        // 合成した位置は、エンジンのマス分けでそのマスになる（外枠の帯の中央は外枠で、左右ならページを切り替える側）
        let grid = GridMapper(insets: frame)
        for index in 0..<9 {
            let p = ControllerPointerSelection.cellCenter(index)
            #expect(grid.zone(x: p.x, y: p.y) == .cell(index))
            #expect(!grid.isInBoundaryBand(x: p.x, y: p.y))
        }
        let neutral = ControllerPointerSelection.gridPosition(for: .frame, pagingEdge: nil)
        #expect(grid.zone(x: neutral.x, y: neutral.y) == .frame && grid.pagingEdge(x: neutral.x, y: neutral.y) == nil)
        for edge in [PageEdge.left, .right, .up, .down] {
            let p = ControllerPointerSelection.gridPosition(for: .frame, pagingEdge: edge)
            #expect(grid.zone(x: p.x, y: p.y) == .frame && grid.pagingEdge(x: p.x, y: p.y) == edge)
        }
    }

    @Test("開いたときのポインタは円の中心")
    func startPoint() {
        #expect(ControllerPointerSelection.startPoint(in: Self.map) == Self.center)
    }

    @Test("ポインタの向きと距離でマスを決め、そのマスの中央の座標にする。中央のマスは、一度外へ出てから戻したときだけ")
    func positions() {
        var selection = ControllerPointerSelection()
        let frame = GridInsets.cancelFrame
        // 開いた直後（中心）: 外へ出るまでは外枠（どの側でもない角）
        let neutral = (frame.left / 2, 1 - frame.top / 2)
        #expect(Self.near(selection.position(of: Self.center, in: Self.map), neutral))
        #expect(selection.zone == .cell(4) && !selection.hasLeftCenter && selection.isWaitingAtCenter)
        #expect(Self.near(selection.position(of: Self.pointer(30, 0), in: Self.map), neutral))
        // 右の鍵
        #expect(Self.near(selection.position(of: Self.pointer(108, 0), in: Self.map), ControllerPointerSelection.cellCenter(5)))
        #expect(selection.hasLeftCenter && !selection.isWaitingAtCenter)
        // 戻せば中央のマス
        #expect(Self.near(selection.position(of: Self.center, in: Self.map), ControllerPointerSelection.cellCenter(4)))
        // 上・左下
        #expect(Self.near(selection.position(of: Self.pointer(0, -100), in: Self.map), ControllerPointerSelection.cellCenter(1)))
        #expect(Self.near(selection.position(of: Self.pointer(-76, 76), in: Self.map), ControllerPointerSelection.cellCenter(6)))
        // 外（上の帯）: 止めると層を切り替える側。帯の外端より遠ければどの側でもない。右へ出れば、止めるとページの側
        #expect(Self.near(selection.position(of: Self.pointer(0, -150), in: Self.map), (0.5, 1 - frame.top / 2)))
        #expect(selection.pagingEdge == .up)
        #expect(Self.near(selection.position(of: Self.pointer(0, -260), in: Self.map), neutral))
        #expect(selection.pagingEdge == nil)
        #expect(Self.near(selection.position(of: Self.pointer(150, 20), in: Self.map), (1 - frame.right / 2, 0.5)))
        #expect(selection.pagingEdge == .right)
        #expect(Self.near(selection.position(of: Self.pointer(-150, 0), in: Self.map), (frame.left / 2, 0.5)))
        #expect(selection.pagingEdge == .left)
        // 鍵に戻れば、止めている側は無い
        #expect(Self.near(selection.position(of: Self.pointer(-108, 0), in: Self.map), ControllerPointerSelection.cellCenter(3)))
        #expect(selection.pagingEdge == nil)
    }

    @Test("鍵の境目では今の鍵を保つ（ヒステリシス）。倍率を掛けた枠でも同じ向きと距離で決める")
    func hysteresisAndScale() {
        var selection = ControllerPointerSelection()
        _ = selection.position(of: Self.pointer(108, 0), in: Self.map)
        // 右（0°）と右下（45°）の境目 22.5° を少し過ぎても右のまま
        let past = Self.pointer(108 * cos(25 * .pi / 180), 108 * sin(25 * .pi / 180))
        #expect(Self.near(selection.position(of: past, in: Self.map), ControllerPointerSelection.cellCenter(5)))
        var fresh = ControllerPointerSelection()
        #expect(Self.near(fresh.position(of: past, in: Self.map), ControllerPointerSelection.cellCenter(8)))
        // 1.5 倍の枠: 中心から 162pt が鍵の円、201pt の外が外枠（鍵からは、余裕 6pt × 1.5 の先）
        let large = CGRect(x: 0, y: 0, width: 402, height: 402)
        var scaled = ControllerPointerSelection()
        #expect(Self.near(scaled.position(of: CGPoint(x: 201 + 162, y: 201), in: large), ControllerPointerSelection.cellCenter(5)))
        #expect(Self.near(scaled.position(of: CGPoint(x: 201 + 140, y: 201), in: large), ControllerPointerSelection.cellCenter(5)))
        #expect(Self.near(scaled.position(of: CGPoint(x: 201 + 209, y: 201), in: large), ControllerPointerSelection.cellCenter(5)))
        #expect(scaled.position(of: CGPoint(x: 201 + 211, y: 201), in: large)?.x == 1 - GridInsets.cancelFrame.right / 2)
        // 壊れた枠や位置
        #expect(selection.position(of: .zero, in: .zero) == nil)
        #expect(selection.position(of: CGPoint(x: CGFloat.nan, y: 0), in: Self.map) == nil)
    }

    @Test("1本指のフレームだけ置き換える。ポインタか枠が分からなければ、2本以上の指なら実物のまま")
    func frames() {
        var selection = ControllerPointerSelection()
        let one = TouchFrame(timestamp: 1, points: [TouchPoint(id: 1, x: 0.1, y: 0.9)])
        let replaced = selection.frame(one, pointer: Self.pointer(108, 0), map: Self.map)
        let right = ControllerPointerSelection.cellCenter(5)
        #expect(abs(replaced.points[0].x - right.x) < 1e-9 && abs(replaced.points[0].y - right.y) < 1e-9 && replaced.points[0].id == 1)
        #expect(selection.frame(one, pointer: nil, map: Self.map) == one)
        #expect(selection.frame(one, pointer: Self.center, map: nil) == one)
        let two = TouchFrame(timestamp: 1, points: [TouchPoint(id: 1, x: 0.1, y: 0.9), TouchPoint(id: 2, x: 0.2, y: 0.9)])
        #expect(selection.frame(two, pointer: Self.center, map: Self.map) == two)
    }

    @Test("開いたとき、ポインタが円の中心に無ければ（画面の端で枠を寄せた）、一度だけそこへ動かす")
    func pointerIsPlacedAtTheCenterWhenTheFrameWasClamped() throws {
        let h = try ControllerHarness()
        h.start()
        h.hud.mapFrame = Self.map
        // 寄せていない: ポインタはすでに中心
        h.keyboard.pointerLocation = Self.center
        h.open()
        #expect(h.keyboard.movedPointers.isEmpty)
        h.keyboard.pressKey()
        h.lift()
        h.advance(1)
        // 寄せた: ポインタは右の鍵の上 → 中心へ
        h.keyboard.pointerLocation = Self.pointer(108, 0)
        h.open()
        #expect(h.keyboard.movedPointers == [Self.center])
        h.keyboard.pressKey()
        h.lift()
        h.advance(1)
        // ポインタが分からなければ動かさない
        h.keyboard.pointerLocation = nil
        h.open()
        #expect(h.keyboard.movedPointers.count == 1)
        h.keyboard.pressKey()
        h.lift()
    }

    @Test("開いている間はポインタで選ぶ: 向きの鍵、外は外枠、外へ出てから戻せば中央。ポインタが分からなければ指の位置")
    func pointerSelectsTheCell() throws {
        let h = try ControllerHarness()
        h.start()
        h.hud.mapFrame = Self.map
        h.keyboard.pointerLocation = Self.center
        h.open()
        #expect(h.hud.shown.count == 1)
        h.advance(0.05)
        // 開いた直後に中心で動いても外枠（離せば何もしない）
        h.keyboard.pointerLocation = Self.pointer(20, 10)
        h.touch(x: 0.1, y: 0.9)
        #expect(h.hud.current?.isFingerInFrame == true)
        // 右上の鍵
        h.keyboard.pointerLocation = Self.pointer(76, -76)
        h.touch(x: 0.1, y: 0.9)
        #expect(h.hud.current?.highlightedIndex == 2)
        // 戻せば中央のマス
        h.keyboard.pointerLocation = Self.center
        h.touch(x: 0.1, y: 0.9)
        #expect(h.hud.current?.highlightedIndex == 4)
        // 円の外は外枠
        h.keyboard.pointerLocation = Self.pointer(0, 150)
        h.touch(x: 0.5, y: 0.5)
        #expect(h.hud.current?.isFingerInFrame == true)
        // ポインタが分からなければ、指の位置
        h.keyboard.pointerLocation = nil
        h.touch(on: 0)
        #expect(h.hud.current?.highlightedIndex == 0)
        h.keyboard.pressKey()
    }

    @Test("右の外へ出して止めると次のページ。外枠の中で動かしても数え直さない")
    func holdingOutsideToTheRightTurnsThePage() throws {
        let h = try ControllerHarness()
        h.start()
        h.hud.mapFrame = Self.map
        h.keyboard.pointerLocation = Self.center
        h.open()
        h.advance(0.05)
        h.keyboard.pointerLocation = Self.pointer(150, 10)
        h.touch(x: 0.5, y: 0.5)
        #expect(h.hud.current?.isFingerInFrame == true)
        #expect(h.hud.current?.edgePaging?.edge == .right)
        let since = h.hud.current?.edgePaging?.since
        h.advance(0.2)
        h.keyboard.pointerLocation = Self.pointer(170, -30)
        h.touch(x: 0.5, y: 0.5)
        #expect(h.hud.current?.edgePaging?.since == since)
        h.advance(SessionConfiguration.defaultEdgePageDwell)
        #expect(h.hud.current?.pageIndex == 1)
        h.keyboard.pressKey()
    }
}
