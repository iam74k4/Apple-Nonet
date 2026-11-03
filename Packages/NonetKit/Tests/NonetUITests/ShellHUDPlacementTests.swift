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

    @Test("HUD はポインタを中心に置き、画面の端では使える範囲（余白つき）に収める", arguments: [
        CGPoint(x: 700, y: 450),
        CGPoint(x: 0, y: 899),
        CGPoint(x: 1439, y: 0),
        CGPoint(x: 5, y: 75),
        CGPoint(x: 1435, y: 870),
    ])
    func centeredOnTheCursor(cursor: CGPoint) {
        let frame = HUDPlacement.hudFrame(size: Self.hudSize, metrics: HUDMetrics(scale: 1), cursor: cursor, screen: Self.main)
        let bounds = Self.main.visibleFrame.insetBy(dx: HUDPlacement.edgeMargin, dy: HUDPlacement.edgeMargin)
        #expect(bounds.contains(frame))
        #expect(frame.size == Self.hudSize)
        // 収まるところでは、ポインタが横の中心で、地図の奥の帯の中央
        if cursor == CGPoint(x: 700, y: 450) {
            #expect(abs(frame.midX - 700) <= 0.5)
            #expect(abs(frame.minY + HUDLayout.padding + HUDLayout.mapHeight - HUDLayout.bandTop / 2 - 450) <= 0.5)
        }
    }

    @Test("負の座標の画面でも収める（メニューバーや Dock に重ならない）")
    func negativeCoordinates() {
        let frame = HUDPlacement.hudFrame(size: Self.hudSize, metrics: HUDMetrics(scale: 1), cursor: CGPoint(x: -1279, y: 899), screen: Self.left)
        #expect(Self.left.visibleFrame.insetBy(dx: HUDPlacement.edgeMargin, dy: HUDPlacement.edgeMargin).contains(frame))
        let low = HUDPlacement.hudFrame(size: Self.hudSize, metrics: HUDMetrics(scale: 1), cursor: CGPoint(x: 2000, y: -299), screen: Self.right)
        #expect(Self.right.visibleFrame.insetBy(dx: HUDPlacement.edgeMargin, dy: HUDPlacement.edgeMargin).contains(low))
    }

    @Test("画面より大きいときは使える範囲の中央にそろえる")
    func largerThanScreen() {
        let tiny = HUDScreenGeometry(frame: CGRect(x: 0, y: 0, width: 400, height: 300), visibleFrame: CGRect(x: 0, y: 0, width: 400, height: 280))
        let frame = HUDPlacement.hudFrame(size: Self.hudSize, metrics: HUDMetrics(scale: 1), cursor: CGPoint(x: 10, y: 10), screen: tiny)
        #expect(frame.midX == tiny.visibleFrame.midX)
        #expect(abs(frame.midY - tiny.visibleFrame.midY) <= 0.5)
    }

    @Test("原点は整数の座標（文字がにじまない）")
    func integralOrigin() {
        let frame = HUDPlacement.hudFrame(size: CGSize(width: 504, height: 315), metrics: HUDMetrics(scale: 1), cursor: CGPoint(x: 700.3, y: 450.7), screen: Self.main)
        #expect(frame.minX == frame.minX.rounded())
        #expect(frame.minY == frame.minY.rounded())
    }

    @Test("地図の枠は、HUD の枠の余白の内側の下側（題名の下）。座標は主画面の左上が原点で y が下向き。倍率は地図の大きさに掛かる")
    func mapFrame() {
        let primary = Self.main.frame
        let hud = CGRect(x: 100, y: 100, width: HUDLayout.width, height: 269)
        let map = HUDPlacement.mapFrame(hudFrame: hud, metrics: HUDMetrics(scale: 1), primaryScreen: primary)
        #expect(map == CGRect(x: 110, y: 900 - (110 + HUDLayout.mapHeight), width: HUDLayout.mapWidth, height: HUDLayout.mapHeight))
        let large = HUDPlacement.mapFrame(hudFrame: hud, metrics: HUDMetrics(scale: 1.5), primaryScreen: primary)
        #expect(large.width == HUDLayout.mapWidth * 1.5 && large.minX == 115)
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
