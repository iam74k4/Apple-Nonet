import CoreGraphics
import Foundation
@testable import NonetPlatform
import Testing

/// 「画面に置く」の座標の計算（AppKit と AX の行き来・ウインドウのある画面・置けたかの判断）。ウインドウは動かさない
@Suite("画面に置く（座標）")
struct ActionWindowPlacementTests {
    /// AppKit（主画面の左下が原点、y は上向き）と AX（左上が原点、y は下向き）は、主画面の高さで折り返す。2回折り返すと元に戻る
    @Test func flippingSwapsTheOrigin() {
        let appKit = CGRect(x: 100, y: 70, width: 600, height: 400)
        let ax = WindowPlacementMath.flipped(appKit, primaryHeight: 900)
        #expect(ax == CGRect(x: 100, y: 430, width: 600, height: 400))
        #expect(WindowPlacementMath.flipped(ax, primaryHeight: 900) == appKit)
        // 主画面より上や左の画面（負の座標）でも同じ決まり
        let above = CGRect(x: -1280, y: 900, width: 1280, height: 800)
        #expect(WindowPlacementMath.flipped(above, primaryHeight: 900) == CGRect(x: -1280, y: -800, width: 1280, height: 800))
    }

    @Test func theScreenIsTheOneHoldingTheWindowCenter() {
        let main = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let right = CGRect(x: 1440, y: -300, width: 1920, height: 1080)
        #expect(WindowPlacementMath.screenIndex(containing: CGRect(x: 100, y: 100, width: 600, height: 400), in: [main, right]) == 0)
        #expect(WindowPlacementMath.screenIndex(containing: CGRect(x: 1500, y: 0, width: 600, height: 400), in: [main, right]) == 1)
        // 中心が画面の境目の外（画面の間の隙間など）なら、重なりが大きいほう
        #expect(WindowPlacementMath.screenIndex(containing: CGRect(x: 1200, y: -500, width: 600, height: 300), in: [main, right]) == 1)
        // どの画面にも掛かっていなければ nil
        #expect(WindowPlacementMath.screenIndex(containing: CGRect(x: 5000, y: 5000, width: 10, height: 10), in: [main, right]) == nil)
        #expect(WindowPlacementMath.screenIndex(containing: main, in: []) == nil)
    }

    /// 置けたかは位置で見る（大きさに下限のあるアプリは、大きさが違っても位置が合えばよい）
    @Test func placedMeansThePositionIsClose() {
        let target = CGRect(x: 0, y: 25, width: 720, height: 875)
        #expect(WindowPlacementMath.isPlaced(CGRect(x: 2, y: 25, width: 720, height: 875), at: target))
        #expect(WindowPlacementMath.isPlaced(CGRect(x: 0, y: 25, width: 900, height: 875), at: target))
        #expect(!WindowPlacementMath.isPlaced(CGRect(x: 300, y: 25, width: 720, height: 875), at: target))
    }

    @Test("大きさに下限があって置く枠より大きくなったウインドウは、使える範囲からはみ出さない所までずらす")
    func shiftedIntoTheVisibleArea() {
        // AX の座標（y は下向き）。使える範囲は x 0〜1440、y 25〜875
        let visible = CGRect(x: 0, y: 25, width: 1440, height: 850)
        // 右半分に置いたが幅が 900 になった: 右の端にそろえる
        let wide = CGRect(x: 720, y: 25, width: 900, height: 850)
        #expect(WindowPlacementMath.shifted(wide, into: visible) == CGRect(x: 540, y: 25, width: 900, height: 850))
        // 下半分に置いたが高さが 600 になった: 下の端にそろえる
        let tall = CGRect(x: 0, y: 450, width: 1440, height: 600)
        #expect(WindowPlacementMath.shifted(tall, into: visible) == CGRect(x: 0, y: 275, width: 1440, height: 600))
        // 収まっていれば動かさない。範囲より大きければ左上にそろえる
        let inside = CGRect(x: 100, y: 100, width: 400, height: 300)
        #expect(WindowPlacementMath.shifted(inside, into: visible) == inside)
        #expect(WindowPlacementMath.shifted(CGRect(x: 300, y: 300, width: 2000, height: 1000), into: visible)
            == CGRect(x: 0, y: 25, width: 2000, height: 1000))
    }
}
