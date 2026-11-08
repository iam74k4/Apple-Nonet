// 担当: ui-shell。ページと層を切り替えるときの押し出しの動き（HUDMotion・HUDTurn）と、上下の帯の矢印・読み上げ
import CoreGraphics
import Foundation
import NonetCore
@testable import NonetUI
import Testing

@Suite("HUD のページと層の切り替え")
@MainActor
struct ShellHUDTurnTests {
    static let main = HUDScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: CGRect(x: 0, y: 70, width: 1440, height: 805))

    static func model(pageIndex: Int = 0, layer: HUDLayer? = .app, title: String = "Xcode", lastTurn: PageEdge? = nil) -> HUDModel {
        HUDModel(title: title, pageIndex: pageIndex, pageCount: 2, cells: Array(repeating: nil, count: 9), highlightedIndex: nil, layer: layer, lastTurn: lastTurn)
    }

    @Test("押し出し: 出ていく輪は反対へ縮みながら消え、入る輪は進んだ側から少し大きめに入って落ち着く。終わりはどちらも止まった形")
    func turnFrames() {
        let start = HUDMotion.turnFrame(progress: 0, isOutgoing: false, reduceMotion: false)
        #expect(start.shift == 1 && start.opacity == 0 && start.scale > 1)
        let end = HUDMotion.turnFrame(progress: 1, isOutgoing: false, reduceMotion: false)
        #expect(end.shift == 0 && end.opacity == 1 && end.scale == 1)
        let outStart = HUDMotion.turnFrame(progress: 0, isOutgoing: true, reduceMotion: false)
        #expect(outStart.shift == 0 && outStart.opacity == 1 && outStart.scale == 1)
        let outEnd = HUDMotion.turnFrame(progress: 1, isOutgoing: true, reduceMotion: false)
        #expect(outEnd.shift == -1 && outEnd.opacity == 0 && outEnd.scale < 1)
        // 出ていく輪は 150ms で消え終わり、入る輪は 40ms までは見えない
        let at150 = 0.15 / HUDMotion.turnDuration
        #expect(HUDMotion.turnFrame(progress: at150, isOutgoing: true, reduceMotion: false).opacity == 0)
        #expect(HUDMotion.turnFrame(progress: 0.03 / HUDMotion.turnDuration, isOutgoing: false, reduceMotion: false).opacity == 0)
        // 入る輪は減速して止まる（前半で大半を進む）
        #expect(HUDMotion.turnFrame(progress: 0.6, isOutgoing: false, reduceMotion: false).shift < 0.2)
        // 「視差効果を減らす」: 動かさず入れ替えるだけ
        let reduced = HUDMotion.turnFrame(progress: 0.5, isOutgoing: false, reduceMotion: true)
        #expect(reduced.shift == 0 && reduced.scale == 1 && reduced.opacity == 0.5)
        #expect(HUDMotion.reducedTurnDuration < HUDMotion.turnDuration)
    }

    @Test("押し出す向き: 右・左・下・上（画面の座標。y は下向き）")
    func vectors() {
        #expect(HUDMotion.vector(.right) == (1, 0))
        #expect(HUDMotion.vector(.left) == (-1, 0))
        #expect(HUDMotion.vector(.down) == (0, 1))
        #expect(HUDMotion.vector(.up) == (0, -1))
    }

    @Test("矢印は止めている側の円の縁の内側。上下にも出し、向きの記号を変える")
    func arrows() {
        let metrics = HUDMetrics(scale: 1)
        let c = metrics.center
        #expect(metrics.pageArrowPosition(.right).x > c.x && metrics.pageArrowPosition(.right).y == c.y)
        #expect(metrics.pageArrowPosition(.left).x < c.x)
        #expect(metrics.pageArrowPosition(.down).y > c.y && metrics.pageArrowPosition(.down).x == c.x)
        #expect(metrics.pageArrowPosition(.up).y < c.y)
        #expect(HUDPagingArrow.symbol(.up) == "chevron.up")
        #expect(HUDPagingArrow.symbol(.down) == "chevron.down")
        #expect(Set([PageEdge.left, .right, .up, .down].map(HUDPagingArrow.symbol)).count == 4)
    }

    @Test("上下の帯で止めているときは、層が変わることを読み上げる")
    func announcements() {
        #expect(HUDAnnouncement.edgePagingLabel(.up) == L10n.ui("止めるとアプリのページへ"))
        #expect(HUDAnnouncement.edgePagingLabel(.down) == L10n.ui("止めるとグローバルのページへ"))
        let paging = HUDEdgePaging(edge: .down, duration: 0.5)
        var model = Self.model()
        model.isFingerInFrame = true
        model.edgePaging = paging
        #expect(HUDAnnouncement.frameLabel(in: model).contains(L10n.ui("止めるとグローバルのページへ")))
    }

    @Test("ページか層が替わったら、前の輪を残して切り替えた向きへ押し出す。層が替わったら層の名前も出す。閉じたら捨てる")
    func controllerStartsATurn() {
        let hud = HUDWindowController(screens: { [Self.main] }, mouseLocation: { CGPoint(x: 720, y: 450) })
        hud.show(Self.model())
        #expect(hud.turn == nil)
        hud.update(Self.model(pageIndex: 1, lastTurn: .right))
        #expect(hud.turn?.direction == .right)
        #expect(hud.layerName == nil)
        hud.update(Self.model(pageIndex: 0, layer: .global, title: "グローバル", lastTurn: .down))
        #expect(hud.turn?.direction == .down)
        #expect(hud.turn?.outgoingLayer == .app)
        #expect(hud.layerName?.text == "グローバル")
        // ハイライトが変わっただけでは押し出さない（serial が変わらない）
        let serial = hud.turn?.serial
        var highlighted = Self.model(pageIndex: 0, layer: .global, title: "グローバル", lastTurn: .down)
        highlighted.highlightedIndex = 4
        hud.update(highlighted)
        #expect(hud.turn?.serial == serial)
        // 新しく出し直したら、動きの途中のものは捨てる
        hud.hide()
        hud.show(Self.model())
        #expect(hud.turn == nil && hud.layerName == nil)
        hud.hide()
    }

    @Test("ページか層の目印: 層・層の中のページの番号・題名のどれかが変われば違う")
    func pageKeys() {
        let base = Self.model()
        #expect(HUDTurn.pageKey(base) == HUDTurn.pageKey(Self.model(lastTurn: .right)))
        #expect(HUDTurn.pageKey(base) != HUDTurn.pageKey(Self.model(pageIndex: 1)))
        #expect(HUDTurn.pageKey(base) != HUDTurn.pageKey(Self.model(layer: .global)))
        #expect(HUDTurn.pageKey(base) != HUDTurn.pageKey(Self.model(title: "Xcode · デバッグ")))
    }
}
