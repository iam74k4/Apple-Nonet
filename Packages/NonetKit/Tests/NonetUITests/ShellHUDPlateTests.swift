// 担当: ui-shell。HUD の台（HUDPlate）: どの画面の上でも、アイコンを暗い台に白で載せる
import CoreGraphics
import Foundation
import NonetCore
@testable import NonetUI
import SwiftUI
import Testing

@Suite("HUD の台")
@MainActor
struct ShellHUDPlateTests {
    @Test("相対輝度: 黒 0、白 1、sRGB のガンマを戻す")
    func luminance() {
        #expect(HUDLuminance.relative(red: 0, green: 0, blue: 0) == 0)
        #expect(abs(HUDLuminance.relative(red: 255, green: 255, blue: 255) - 1) < 1e-9)
        #expect(abs(HUDLuminance.relative(red: 0x80, green: 0x80, blue: 0x80) - 0.2158) < 0.001)
        // 緑がいちばん明るく見える
        #expect(HUDLuminance.relative(red: 0, green: 255, blue: 0) > HUDLuminance.relative(red: 255, green: 0, blue: 0))
        #expect(abs(HUDLuminance.contrastRatio(1, 0) - 21) < 1e-9)
    }

    /// 鍵を一色の下地に描いた画素。鍵の中心からの距離の範囲ごとに明るさ（0〜1）を見る
    private struct KeyPixels {
        let pixels: [UInt8]
        let width: Int
        let height: Int
        /// 1pt あたりの画素
        let scale: CGFloat

        @MainActor
        init(_ key: HUDKeyView, on backdrop: Color) throws {
            let side = HUDMetrics(scale: 1).selectionRadius * 2 + 16
            let renderer = ImageRenderer(content: key.frame(width: side, height: side).background(backdrop))
            renderer.scale = 2
            let image = try #require(renderer.cgImage)
            width = image.width
            height = image.height
            scale = CGFloat(width) / side
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            let context = try #require(CGContext(
                data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            self.pixels = pixels
        }

        /// 中心から distance（pt）の範囲にある画素の、いちばん明るい・いちばん暗い明るさ
        func range(_ distance: ClosedRange<CGFloat>) -> (brightest: Double, darkest: Double) {
            var brightest = 0.0
            var darkest = 1.0
            for y in 0..<height {
                for x in 0..<width {
                    let d = hypot(CGFloat(x) + 0.5 - CGFloat(width) / 2, CGFloat(y) + 0.5 - CGFloat(height) / 2) / scale
                    guard distance.contains(d) else { continue }
                    let offset = (y * width + x) * 4
                    let value = (Double(pixels[offset]) + Double(pixels[offset + 1]) + Double(pixels[offset + 2])) / (3 * 255)
                    brightest = max(brightest, value)
                    darkest = min(darkest, value)
                }
            }
            return (brightest, darkest)
        }
    }

    static let eraser = HUDCell(title: "クリーン", icon: .symbol("eraser"))

    @Test("台: どの組み合わせ（ガラス・ガラスなし・コントラストを上げる・透明度を下げる・グローバルの層の紺）でも、真っ白な画面の上で白いアイコンとの比が 4.5:1 以上")
    func plateKeepsWhiteIconsReadableOnWhite() {
        var styles = [
            HUDPlateStyle(surface: .glass),
            HUDPlateStyle(surface: .solid),
            HUDPlateStyle(increasedContrast: true, surface: .glass),
            HUDPlateStyle(reduceTransparency: true, surface: .glass),
        ]
        styles += styles.map { var global = $0; global.isGlobalLayer = true; return global }
        for style in styles {
            #expect(HUDLuminance.contrastRatio(1, style.luminance(over: 1)) >= 4.5)
            // 黒い画面の上ではなおさら（台はほぼ黒）
            #expect(HUDLuminance.contrastRatio(1, style.luminance(over: 0)) > 10)
        }
        // 「コントラストを上げる」は 7:1 以上。ガラスで下をぼかせない macOS 14・15 は、ガラスのときより濃い
        #expect(HUDLuminance.contrastRatio(1, HUDPlateStyle(increasedContrast: true).luminance(over: 1)) >= 7)
        #expect(HUDPlateStyle(surface: .solid).opacity > HUDPlateStyle(surface: .glass).opacity)
        // グローバルの層の台は、アプリの層と色が違う（紺に寄せる）
        #expect(HUDPlateStyle(isGlobalLayer: true).color != HUDPlateStyle().color)
    }

    @Test("「透明度を下げる」では、台の下にガラスを敷かず、台を不透明にする（下の画面が透けない）")
    func reduceTransparencyMakesPlatesOpaque() {
        let reduced = HUDPlateStyle(reduceTransparency: true, surface: .glass)
        #expect(!reduced.usesGlass)
        #expect(reduced.opacity == 1)
        #expect(abs(reduced.luminance(over: 1) - HUDLuminance.relative(white: HUDKeyPalette.plateWhite)) < 1e-9)
        #expect(HUDPlateStyle(surface: .glass).usesGlass)
        #expect(!HUDPlateStyle(surface: .solid).usesGlass)
        // 押し出している間はガラスを外すが、濃さはガラスのときのまま（止まってガラスを戻しても濃さが跳ねない）
        let moving = HUDPlateStyle(showsGlass: false, surface: .glass)
        #expect(!moving.usesGlass)
        #expect(moving.opacity == HUDPlateStyle(surface: .glass).opacity)
    }

    static let main = HUDScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: CGRect(x: 0, y: 70, width: 1440, height: 805))

    @Test("HUD を出すたびに「透明度を下げる」を読み直す")
    func reduceTransparencyIsReadOnShow() {
        var reduce = true
        let hud = HUDWindowController(screens: { [Self.main] }, mouseLocation: { CGPoint(x: 720, y: 450) }, prefersReducedTransparency: { reduce })
        let model = HUDModel(title: "Xcode", pageIndex: 0, pageCount: 1, cells: Array(repeating: nil, count: 9), highlightedIndex: nil)
        hud.show(model)
        #expect(hud.reduceTransparency)
        hud.hide()
        reduce = false
        hud.show(model)
        #expect(!hud.reduceTransparency)
        hud.hide()
    }

    @Test("外枠などで薄くするときは、アイコンだけを薄くし、台は残す。白い画面でもアイコンの形は見える")
    func dimmingFadesIconsButKeepsPlates() throws {
        let metrics = HUDMetrics(scale: 1)
        let dimmed = HUDKeyView(cell: Self.eraser, index: 7, isHighlighted: false, isDimmed: true)
        let onWhite = try KeyPixels(dimmed, on: .white)
        let face = onWhite.range(12...(metrics.plateRadius - 2))
        let icon = onWhite.range(0...10)
        // 台は薄くならない（白い画面の上でも暗いまま）
        #expect(face.brightest < 0.5)
        // アイコンは台より明るいが、薄くしないときほどは白くない
        #expect(icon.brightest > face.brightest + 0.15)
        #expect(icon.brightest < 0.9)
        // 比で見ても、薄くしたアイコンは台の上で 2:1 以上（ガラスの台・真っ白な画面）
        let style = HUDPlateStyle(surface: .glass)
        let plate = HUDKeyPalette.plateWhite * style.opacity + (1 - style.opacity)
        let faded = style.dimmedIconOpacity + (1 - style.dimmedIconOpacity) * plate
        #expect(HUDLuminance.contrastRatio(white: faded, white: plate) >= 2)
        #expect(HUDPlateStyle().dimmedIconOpacity < HUDPlateStyle(increasedContrast: true).dimmedIconOpacity)
    }

    @Test("台: 白い画面でも黒い画面でも、アイコンは暗い台の上に白で載る")
    func iconsSitWhiteOnADarkPlate() throws {
        let metrics = HUDMetrics(scale: 1)
        let idle = HUDKeyView(cell: Self.eraser, index: 7, isHighlighted: false)
        for backdrop in [Color.white, Color.black] {
            let pixels = try KeyPixels(idle, on: backdrop)
            // アイコン（中心から 10pt 以内）に白い画素がある
            #expect(pixels.range(0...10).brightest > 0.9)
        }
        // 白い画面の上で、アイコンと台の縁の間（台の面）は暗い
        let onWhite = try KeyPixels(idle, on: .white)
        let face = onWhite.range(12...(metrics.plateRadius - 2))
        #expect(face.brightest < 0.5)
    }

    @Test("少し長く止める線と空きマスの点線は、台の縁の内側に白く引く。外側に台の暗さが残るので、白い画面でも黒い画面でも見える")
    func holdRingAndEmptyOutlineShowOnAnyBackdrop() throws {
        let metrics = HUDMetrics(scale: 1)
        let holding = HUDKeyView(
            cell: Self.eraser,
            index: 7,
            isHighlighted: true,
            hold: HUDHold(cellIndex: 7, duration: 0.45, isReady: false),
            fixedHoldProgress: 1
        )
        let emptyCell = HUDKeyView(cell: nil, index: 0, isHighlighted: true)
        // 線（台の縁から ringInset 内側の、holdLineWidth の幅）と、その外側から台の縁まで（2x で 3 画素ほどの幅を見る）
        let line = (metrics.selectionRadius - metrics.ringInset - metrics.holdLineWidth)...(metrics.selectionRadius - metrics.ringInset)
        let margin = (metrics.selectionRadius - metrics.ringInset + 0.2)...(metrics.selectionRadius - 0.2)
        for key in [holding, emptyCell] {
            for backdrop in [Color.white, Color.black] {
                let pixels = try KeyPixels(key, on: backdrop)
                #expect(pixels.range(line).brightest > 0.8)
                #expect(pixels.range(margin).darkest < 0.5)
            }
        }
    }
}
