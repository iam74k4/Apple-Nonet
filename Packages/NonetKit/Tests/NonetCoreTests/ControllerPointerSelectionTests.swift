// 担当: engine。ポインタで選ぶ: 開いている間、HUD の地図の上でポインタが乗っているマスを選ぶ
import CoreGraphics
import Foundation
@testable import NonetCore
import Testing

@MainActor
@Suite struct ControllerPointerSelectionTests {
    /// 地図の枠（主画面の左上が原点、y が下向き）
    static let map = CGRect(x: 100, y: 100, width: 300, height: 200)

    @Test("ポインタの位置を指の位置に写す: 枠の左下が (0, 0)、右上が (1, 1)。外は縁に収める")
    func positions() {
        #expect(ControllerPointerSelection.position(of: CGPoint(x: 100, y: 300), in: Self.map)! == (0, 0))
        #expect(ControllerPointerSelection.position(of: CGPoint(x: 400, y: 100), in: Self.map)! == (1, 1))
        #expect(ControllerPointerSelection.position(of: CGPoint(x: 250, y: 200), in: Self.map)! == (0.5, 0.5))
        #expect(ControllerPointerSelection.position(of: CGPoint(x: -50, y: 900), in: Self.map)! == (0, 0))
        #expect(ControllerPointerSelection.position(of: .zero, in: .zero) == nil)
    }

    @Test("1本指のフレームだけ置き換える。ポインタか枠が分からなければ、2本以上の指なら実物のまま")
    func frames() {
        let one = TouchFrame(timestamp: 1, points: [TouchPoint(id: 1, x: 0.1, y: 0.9)])
        let replaced = ControllerPointerSelection.frame(one, pointer: CGPoint(x: 250, y: 200), map: Self.map)
        #expect(replaced.points[0].x == 0.5 && replaced.points[0].y == 0.5 && replaced.points[0].id == 1)
        #expect(ControllerPointerSelection.frame(one, pointer: nil, map: Self.map) == one)
        #expect(ControllerPointerSelection.frame(one, pointer: CGPoint(x: 250, y: 200), map: nil) == one)
        let two = TouchFrame(timestamp: 1, points: [TouchPoint(id: 1, x: 0.1, y: 0.9), TouchPoint(id: 2, x: 0.2, y: 0.9)])
        #expect(ControllerPointerSelection.frame(two, pointer: CGPoint(x: 250, y: 200), map: Self.map) == two)
    }

    @Test("開いたとき、ポインタが地図の奥の帯の中央に無ければ（画面の端で枠を寄せた）、一度だけそこへ動かす")
    func pointerIsPlacedInTheFarBandWhenTheFrameWasClamped() throws {
        let h = try ControllerHarness()
        h.start()
        h.hud.mapFrame = Self.map
        // 寄せていない: ポインタはすでに帯の中央
        let start = ControllerPointerSelection.startPoint(in: Self.map)
        #expect(start == CGPoint(x: 250, y: 100 + 200 * GridInsets.cancelFrame.top / 2))
        h.keyboard.pointerLocation = start
        h.open()
        #expect(h.keyboard.movedPointers.isEmpty)
        h.keyboard.pressKey()
        h.lift()
        h.advance(1)
        // 寄せた: ポインタはマスの上 → 帯の中央へ
        h.keyboard.pointerLocation = CGPoint(x: 250, y: 200)
        h.open()
        #expect(h.keyboard.movedPointers == [start])
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

    @Test("開いている間はポインタで選ぶ: ポインタが地図の中央ならそのマス、奥の帯か地図の外なら外枠。ポインタが分からなければ指の位置")
    func pointerSelectsTheCell() throws {
        let h = try ControllerHarness()
        h.start()
        h.hud.mapFrame = Self.map
        h.open()
        #expect(h.hud.shown.count == 1)
        h.advance(0.05)
        h.keyboard.pointerLocation = CGPoint(x: 250, y: 200)
        h.touch(x: 0.1, y: 0.9)
        #expect(h.hud.current?.highlightedIndex == 4)
        // 奥の帯（地図の上辺のすぐ下）は外枠
        h.keyboard.pointerLocation = CGPoint(x: 250, y: 110)
        h.touch(x: 0.1, y: 0.9)
        #expect(h.hud.current?.isFingerInFrame == true)
        // 地図の外（右下の遠く）も外枠（縁に収める）
        h.keyboard.pointerLocation = CGPoint(x: 900, y: 900)
        h.touch(x: 0.5, y: 0.5)
        #expect(h.hud.current?.isFingerInFrame == true)
        // ポインタが分からなければ、指の位置
        h.keyboard.pointerLocation = nil
        h.touch(on: 0)
        #expect(h.hud.current?.highlightedIndex == 0)
        h.keyboard.pressKey()
    }
}
