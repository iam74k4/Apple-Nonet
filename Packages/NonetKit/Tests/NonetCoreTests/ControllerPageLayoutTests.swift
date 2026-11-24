// 担当: engine。ボタンの数が 9 でないページ: 円に並べた鍵をポインタの向きで選び、離すと実行する。真ん中は離すとやめる
import CoreGraphics
import Foundation
@testable import NonetCore
import Testing

@MainActor
@Suite struct ControllerPageLayoutTests {
    typealias P = ControllerPointerSelectionTests

    static func cells(_ count: Int) -> [Cell] {
        (0..<count).map { Cell(title: "ボタン\($0)", icon: .text("\($0)"), action: .keystroke(.key("\($0 % 10)", [.command]))) }
    }

    /// グローバルが 12 のボタンのページ（全部に中身）と、6 のページ
    static func configuration() -> NonetConfiguration {
        let global = Profile(kind: .global, pages: [
            Page(cells: cells(12), layout: .twelve),
            Page(cells: cells(6), layout: .six),
        ])
        return NonetConfiguration(profiles: [global]).validated()
    }

    /// 鍵 cell（layout の円の上）にポインタを置く
    static func pointer(at cell: Int, layout: PageLayout) -> CGPoint {
        let position = RadialLayout.position(ofCell: cell, layout: layout)!
        return P.pointer(position.x, position.y)
    }

    @Test("12 のページ: 向きの鍵を光らせ、離すとそのマスを実行する")
    func twelveButtons() async throws {
        let h = try ControllerHarness(configuration: Self.configuration(), frontmost: nil)
        h.start()
        h.hud.mapFrame = P.map
        h.keyboard.pointerLocation = P.center
        h.open()
        #expect(h.hud.current?.layout == .twelve)
        #expect(h.hud.current?.cells.count == 12)
        h.advance(0.05)
        for cell in [3, 11, 7] {
            h.keyboard.pointerLocation = Self.pointer(at: cell, layout: .twelve)
            h.touch(x: 0.5, y: 0.5)
            #expect(h.hud.current?.highlightedIndex == cell)
        }
        h.advance(0.3)
        h.touch(x: 0.5, y: 0.5)
        h.lift()
        await h.settle()
        #expect(h.performer.actions == [Self.cells(12)[7].action])
    }

    @Test("真ん中のマスが無いページでは、真ん中に戻して離すとやめる")
    func theCenterCancels() async throws {
        let h = try ControllerHarness(configuration: Self.configuration(), frontmost: nil)
        h.start()
        h.hud.mapFrame = P.map
        h.keyboard.pointerLocation = P.center
        h.open()
        h.advance(0.05)
        h.keyboard.pointerLocation = Self.pointer(at: 0, layout: .twelve)
        h.touch(x: 0.5, y: 0.5)
        #expect(h.hud.current?.highlightedIndex == 0)
        h.keyboard.pointerLocation = P.pointer(3, 2)
        h.touch(x: 0.5, y: 0.5)
        #expect(h.hud.current?.highlightedIndex == nil)
        #expect(h.hud.current?.isFingerInFrame == true)
        h.advance(0.3)
        h.touch(x: 0.5, y: 0.5)
        h.lift()
        await h.settle()
        #expect(h.performer.actions.isEmpty)
    }

    @Test("開いた直後、真ん中のマスが無いページでも、真ん中から出るまでは薄くしない")
    func waitingAtTheCenter() throws {
        let h = try ControllerHarness(configuration: Self.configuration(), frontmost: nil)
        h.start()
        h.hud.mapFrame = P.map
        h.keyboard.pointerLocation = P.center
        h.open()
        h.advance(0.05)
        h.keyboard.pointerLocation = P.pointer(4, 4)
        h.touch(x: 0.5, y: 0.5)
        #expect(h.hud.current?.isWaitingAtCenter == true)
        h.keyboard.pointerLocation = Self.pointer(at: 2, layout: .twelve)
        h.touch(x: 0.5, y: 0.5)
        #expect(h.hud.current?.isWaitingAtCenter == false)
        #expect(h.hud.current?.highlightedIndex == 2)
        h.keyboard.pressKey()
    }

    @Test("ページを送ると、次のページのボタンの数で並べて選ぶ")
    func pagingSwitchesTheLayout() async throws {
        let h = try ControllerHarness(configuration: Self.configuration(), frontmost: nil)
        h.start()
        h.hud.mapFrame = P.map
        h.keyboard.pointerLocation = P.center
        h.open()
        h.advance(0.05)
        // 右の外の帯に止めて、次のページへ
        h.keyboard.pointerLocation = P.pointer(170, 0)
        h.touch(x: 0.5, y: 0.5)
        h.advance(SessionConfiguration.defaultEdgePageDwell + 0.05)
        h.touch(x: 0.5, y: 0.5)
        #expect(h.hud.current?.layout == .six)
        #expect(h.hud.current?.cells.count == 6)
        // 6 の右下（2時と4時の間の 120°）の鍵
        h.keyboard.pointerLocation = Self.pointer(at: 2, layout: .six)
        h.touch(x: 0.5, y: 0.5)
        #expect(h.hud.current?.highlightedIndex == 2)
        h.advance(0.3)
        h.touch(x: 0.5, y: 0.5)
        h.lift()
        await h.settle()
        #expect(h.performer.actions == [Self.cells(6)[2].action])
    }
}
