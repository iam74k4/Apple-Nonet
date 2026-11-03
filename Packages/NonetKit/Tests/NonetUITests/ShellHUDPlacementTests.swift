// 担当: ui-shell
import CoreGraphics
import NonetCore
@testable import NonetUI
import Testing

@Suite("HUD の置き場所")
struct ShellHUDPlacementTests {
    /// 主画面（メニューバー 25pt・下に Dock 70pt）
    static let main = HUDScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: CGRect(x: 0, y: 70, width: 1440, height: 805)
    )
    /// 右に並べた外部ディスプレイ（下にずれている）
    static let right = HUDScreenGeometry(
        frame: CGRect(x: 1440, y: -300, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 1440, y: -300, width: 1920, height: 1055)
    )
    /// 左に並べた画面（座標が負）
    static let left = HUDScreenGeometry(
        frame: CGRect(x: -1280, y: 100, width: 1280, height: 800),
        visibleFrame: CGRect(x: -1280, y: 100, width: 1280, height: 775)
    )
    static let screens = [main, right, left]
    static let hudSize = CGSize(width: 504, height: 315)

    @Test("カーソルのある画面を選ぶ", arguments: [
        (CGPoint(x: 700, y: 400), 0),
        (CGPoint(x: 2000, y: -100), 1),
        (CGPoint(x: -500, y: 500), 2),
    ])
    func screenContainingCursor(cursor: CGPoint, expected: Int) {
        #expect(HUDPlacement.screenIndex(containing: cursor, in: Self.screens) == expected)
    }

    @Test("画面の境目は右（上）の画面に含める。隣り合う2つの画面のどちらか1つだけを選ぶ")
    func screenEdges() {
        #expect(HUDPlacement.screenIndex(containing: CGPoint(x: 1440, y: 200), in: Self.screens) == 1)
        #expect(HUDPlacement.screenIndex(containing: CGPoint(x: 1439.5, y: 200), in: Self.screens) == 0)
        #expect(HUDPlacement.screenIndex(containing: CGPoint(x: 0, y: 500), in: Self.screens) == 0)
    }

    @Test("どの画面の外でも一番近い画面を選ぶ。画面が無ければ nil")
    func cursorOutsideScreens() {
        #expect(HUDPlacement.screenIndex(containing: CGPoint(x: 700, y: 2000), in: Self.screens) == 0)
        #expect(HUDPlacement.screenIndex(containing: CGPoint(x: 5000, y: 0), in: Self.screens) == 1)
        #expect(HUDPlacement.screenIndex(containing: .zero, in: []) == nil)
        #expect(HUDPlacement.screen(containing: .zero, in: []) == nil)
    }

    @Test("中央: カーソルの位置によらず、その画面の使える範囲の中央")
    func centered() {
        for cursor in [CGPoint(x: 10, y: 80), CGPoint(x: 1400, y: 880)] {
            let frame = HUDPlacement.hudFrame(size: Self.hudSize, position: .screenCenter, cursor: cursor, screen: Self.main)
            #expect(frame.size == Self.hudSize)
            #expect(frame.midX == Self.main.visibleFrame.midX)
            #expect(abs(frame.midY - Self.main.visibleFrame.midY) <= 0.5)
        }
        let external = HUDPlacement.hudFrame(size: Self.hudSize, position: .screenCenter, cursor: CGPoint(x: 2000, y: 0), screen: Self.right)
        #expect(external.midX == Self.right.visibleFrame.midX)
        #expect(abs(external.midY - Self.right.visibleFrame.midY) <= 0.5)
    }

    @Test("カーソルの近く: カーソルのすぐ下に、ポインタに重ならないよう置く（横はカーソルを中心に）")
    func nearCursor() {
        let cursor = CGPoint(x: 700, y: 650)
        let frame = HUDPlacement.hudFrame(size: Self.hudSize, position: .nearCursor, cursor: cursor, screen: Self.main)
        #expect(frame.midX == 700)
        #expect(frame.maxY == cursor.y - HUDPlacement.pointerSize.height - HUDPlacement.pointerGap)
        #expect(!frame.intersects(HUDPlacement.pointerRect(at: cursor)))
        #expect(HUDPlacement.pointerParkingSpot(cursor: cursor, hudFrame: frame, screen: Self.main) == nil)
    }

    @Test("カーソルの近く: 下に入らなければすぐ上。どちらにも入らなければカーソルを中心に")
    func nearCursorAbove() {
        let cursor = CGPoint(x: 700, y: 200)
        let frame = HUDPlacement.hudFrame(size: Self.hudSize, position: .nearCursor, cursor: cursor, screen: Self.main)
        #expect(frame.minY == cursor.y + HUDPlacement.pointerGap)
        #expect(!frame.intersects(HUDPlacement.pointerRect(at: cursor)))

        let short = HUDScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1440, height: 500), visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 480))
        let middle = HUDPlacement.hudFrame(size: Self.hudSize, position: .nearCursor, cursor: CGPoint(x: 700, y: 240), screen: short)
        #expect(middle.midX == 700)
        #expect(abs(middle.midY - 240) <= 0.5)
    }

    @Test("止めたポインタが HUD に重なるときだけ、すぐ外（下か上の近いほう）へ寄せる。横の位置はそのまま")
    func pointerParking() throws {
        let frame = HUDPlacement.hudFrame(size: Self.hudSize, position: .screenCenter, cursor: .zero, screen: Self.main)
        // 重ならない
        #expect(HUDPlacement.pointerParkingSpot(cursor: CGPoint(x: 100, y: 800), hudFrame: frame, screen: Self.main) == nil)
        // HUD の下の方に重なる: 下へ
        let low = try #require(HUDPlacement.pointerParkingSpot(cursor: CGPoint(x: 600, y: frame.minY + 20), hudFrame: frame, screen: Self.main))
        #expect(low.x == 600)
        #expect(!HUDPlacement.pointerRect(at: low).intersects(frame))
        #expect(low.y < frame.minY)
        // HUD の上の方に重なる: 上へ
        let high = try #require(HUDPlacement.pointerParkingSpot(cursor: CGPoint(x: 600, y: frame.maxY - 20), hudFrame: frame, screen: Self.main))
        #expect(!HUDPlacement.pointerRect(at: high).intersects(frame))
        #expect(high.y > frame.maxY)
        #expect(Self.main.frame.contains(high))
    }

    @Test("ポインタを動かす座標は、主画面の左上が原点で y が下向き")
    func quartzCoordinates() {
        #expect(HUDPlacement.quartzPoint(CGPoint(x: 10, y: 890), primaryScreen: Self.main.frame) == CGPoint(x: 10, y: 10))
        #expect(HUDPlacement.quartzPoint(CGPoint(x: 2000, y: -100), primaryScreen: Self.main.frame) == CGPoint(x: 2000, y: 1000))
    }

    @Test("カーソルの近く: 画面の端では使える範囲（余白つき）に収める", arguments: [
        CGPoint(x: 0, y: 899),
        CGPoint(x: 1439, y: 0),
        CGPoint(x: 5, y: 75),
        CGPoint(x: 1435, y: 870),
    ])
    func nearCursorClamped(cursor: CGPoint) {
        let frame = HUDPlacement.hudFrame(size: Self.hudSize, position: .nearCursor, cursor: cursor, screen: Self.main)
        let bounds = Self.main.visibleFrame.insetBy(dx: HUDPlacement.edgeMargin, dy: HUDPlacement.edgeMargin)
        #expect(bounds.contains(frame))
        #expect(frame.size == Self.hudSize)
    }

    @Test("負の座標の画面でも収める（メニューバーや Dock に重ならない）")
    func negativeCoordinates() {
        let frame = HUDPlacement.hudFrame(size: Self.hudSize, position: .nearCursor, cursor: CGPoint(x: -1279, y: 899), screen: Self.left)
        #expect(Self.left.visibleFrame.insetBy(dx: HUDPlacement.edgeMargin, dy: HUDPlacement.edgeMargin).contains(frame))
        // 画面の下の端では、ポインタのすぐ上に出す
        let low = HUDPlacement.hudFrame(size: Self.hudSize, position: .nearCursor, cursor: CGPoint(x: 2000, y: -299), screen: Self.right)
        #expect(low.minY == -299 + HUDPlacement.pointerGap)
        #expect(Self.right.visibleFrame.insetBy(dx: HUDPlacement.edgeMargin, dy: HUDPlacement.edgeMargin).contains(low))
    }

    @Test("画面より大きいときは使える範囲の中央にそろえる")
    func largerThanScreen() {
        let tiny = HUDScreenGeometry(frame: CGRect(x: 0, y: 0, width: 400, height: 300), visibleFrame: CGRect(x: 0, y: 0, width: 400, height: 280))
        let frame = HUDPlacement.hudFrame(size: Self.hudSize, position: .nearCursor, cursor: CGPoint(x: 10, y: 10), screen: tiny)
        #expect(frame.midX == tiny.visibleFrame.midX)
        #expect(abs(frame.midY - tiny.visibleFrame.midY) <= 0.5)
    }

    @Test("原点は整数の座標（文字がにじまない）")
    func integralOrigin() {
        let frame = HUDPlacement.hudFrame(size: CGSize(width: 504, height: 315), position: .nearCursor, cursor: CGPoint(x: 700.3, y: 450.7), screen: Self.main)
        #expect(frame.minX == frame.minX.rounded())
        #expect(frame.minY == frame.minY.rounded())
    }

    @Test("トーストは使える範囲の下の中央（Dock の上）")
    func toast() {
        let size = CGSize(width: 220, height: 44)
        let frame = HUDPlacement.toastFrame(size: size, screen: Self.main)
        #expect(frame.midX == Self.main.visibleFrame.midX)
        #expect(frame.minY == Self.main.visibleFrame.minY + HUDPlacement.toastBottomInset)
        let wide = HUDPlacement.toastFrame(size: CGSize(width: 2000, height: 44), screen: Self.main)
        #expect(wide.midX == Self.main.visibleFrame.midX)
    }

    @Test("clamp は収まるものを動かさない")
    func clampKeepsInside() {
        let rect = CGRect(x: 100, y: 100, width: 50, height: 50)
        #expect(HUDPlacement.clamp(rect, into: CGRect(x: 0, y: 0, width: 500, height: 500)) == rect)
    }
}
