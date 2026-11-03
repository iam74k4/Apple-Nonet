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

    @Test("HUD はポインタのある画面いっぱい（メニューバーと Dock も含む）に敷く")
    func hudFillsTheScreen() {
        #expect(HUDPlacement.hudFrame(on: Self.main) == Self.main.frame)
        #expect(HUDPlacement.hudFrame(on: Self.left) == Self.left.frame)
    }

    @Test("指の位置を画面に写す座標は、主画面の左上が原点で y が下向き（ほかの画面でも）")
    func pointerLocation() {
        let primary = Self.main.frame
        // 主画面: 奥の左が (0, 0)、手前の右が画面の右下
        #expect(HUDPlacement.pointerLocation(for: HUDFinger(x: 0, y: 1), on: Self.main, primaryScreen: primary) == .zero)
        #expect(HUDPlacement.pointerLocation(for: HUDFinger(x: 1, y: 0), on: Self.main, primaryScreen: primary) == CGPoint(x: 1440, y: 900))
        // 右の画面（下にずれている）: その画面の左上は、主画面の上端からのずれの分だけ下
        let topLeft = HUDPlacement.pointerLocation(for: HUDFinger(x: 0, y: 1), on: Self.right, primaryScreen: primary)
        #expect(topLeft == CGPoint(x: Self.right.frame.minX, y: primary.maxY - Self.right.frame.maxY))
    }

    @Test("結果のパネルは、その画面の使える範囲の中央")
    func resultAnchor() {
        let anchor = HUDPlacement.resultAnchor(on: Self.right)
        #expect(anchor == CGPoint(x: Self.right.visibleFrame.midX, y: Self.right.visibleFrame.midY))
    }

    @Test("中央にそろえた枠は使える範囲（余白つき）に収め、画面より大きければ中央にそろえ、原点は整数")
    func centeredFrames() {
        let frame = HUDPlacement.frame(size: Self.hudSize, centeredAt: CGPoint(x: 700.3, y: 450.7), in: Self.main)
        #expect(frame.size == Self.hudSize)
        #expect(frame.minX == frame.minX.rounded() && frame.minY == frame.minY.rounded())
        let edge = HUDPlacement.frame(size: Self.hudSize, centeredAt: CGPoint(x: 0, y: 899), in: Self.main)
        #expect(Self.main.visibleFrame.insetBy(dx: HUDPlacement.edgeMargin, dy: HUDPlacement.edgeMargin).contains(edge))
        let negative = HUDPlacement.frame(size: Self.hudSize, centeredAt: CGPoint(x: -1279, y: 899), in: Self.left)
        #expect(Self.left.visibleFrame.insetBy(dx: HUDPlacement.edgeMargin, dy: HUDPlacement.edgeMargin).contains(negative))
        let tiny = HUDScreenGeometry(frame: CGRect(x: 0, y: 0, width: 400, height: 300), visibleFrame: CGRect(x: 0, y: 0, width: 400, height: 280))
        let large = HUDPlacement.frame(size: Self.hudSize, centeredAt: CGPoint(x: 10, y: 10), in: tiny)
        #expect(large.midX == tiny.visibleFrame.midX)
        #expect(abs(large.midY - tiny.visibleFrame.midY) <= 0.5)
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
