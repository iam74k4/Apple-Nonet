// 担当: ui-shell。HUD のアイコンの色: 下地の明るさから白か濃い色かを鍵ごとに決める
import CoreGraphics
import Foundation
import NonetCore
@testable import NonetUI
import Testing

@Suite("HUD のアイコンの色")
@MainActor
struct ShellHUDInkTests {
    /// 測った明るさを返す偽物（画面収録の許可の有無も決める）
    final class FakeSampler: HUDBackdropSampling {
        var isAvailable = true
        var luminances: [Double]?
        private(set) var requests: [(rect: CGRect, keys: [CGPoint], radius: CGFloat)] = []
        /// 測り終えるのを遅らせる（completion を手で呼ぶ）
        var pending: ((@MainActor ([Double]?) -> Void))?
        var defers = false

        func sample(_ rect: CGRect, keys: [CGPoint], radius: CGFloat, completion: @escaping @MainActor ([Double]?) -> Void) {
            requests.append((rect, keys, radius))
            if defers {
                pending = completion
            } else {
                completion(luminances)
            }
        }
    }

    static let main = HUDScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: CGRect(x: 0, y: 70, width: 1440, height: 805))

    static func model(adaptsInk: Bool = true) -> HUDModel {
        HUDModel(title: "Xcode", pageIndex: 0, pageCount: 1, cells: Array(repeating: nil, count: 9), highlightedIndex: nil, adaptsInk: adaptsInk)
    }

    @Test("しきい値: 白と黒のコントラスト比が同じになる明るさ。明るければ濃い色、暗ければ白")
    func threshold() {
        let threshold = HUDInkDecision.threshold
        #expect(abs(HUDLuminance.contrastRatio(1, threshold) - HUDLuminance.contrastRatio(threshold, 0)) < 0.01)
        #expect(HUDInkDecision.ink(forLuminance: 1) == .onLight)
        #expect(HUDInkDecision.ink(forLuminance: 0) == .onDark)
        #expect(HUDInkDecision.ink(forLuminance: threshold) == .onLight)
        #expect(HUDInkDecision.ink(forLuminance: threshold - 0.01) == .onDark)
        #expect(HUDInkDecision.ink(forLuminance: .nan) == .onLight)
        // 中くらいの灰色（#808080。相対輝度 0.22）は黒のほうが読みやすい
        #expect(HUDInkDecision.ink(forLuminance: HUDLuminance.relative(red: 0x80, green: 0x80, blue: 0x80)) == .onLight)
        #expect(HUDInkDecision.ink(forLuminance: HUDLuminance.relative(red: 0x50, green: 0x50, blue: 0x50)) == .onDark)
    }

    @Test("鍵ごとの色。測れなければ、黒に白い縁で全部（どの下地でも読める）")
    func inks() {
        let mixed = HUDInkDecision.inks(forLuminances: [1, 0, 1, 0, 1, 0, 1, 0, 1])
        #expect(mixed.keys == [.onLight, .onDark, .onLight, .onDark, .onLight, .onDark, .onLight, .onDark, .onLight])
        #expect(HUDInkDecision.inks(forLuminances: nil) == .fallback)
        #expect(HUDInkDecision.inks(forLuminances: [0, 0]) == .fallback)
        #expect(HUDInks.fallback.keys == Array(repeating: .onLight, count: 9))
        #expect(HUDInks.fallback.ink(at: 20) == .onLight)
        #expect(HUDInk.onDark.color == .white)
    }

    @Test("相対輝度: 黒 0、白 1、sRGB のガンマを戻す")
    func luminance() {
        #expect(HUDLuminance.relative(red: 0, green: 0, blue: 0) == 0)
        #expect(abs(HUDLuminance.relative(red: 255, green: 255, blue: 255) - 1) < 1e-9)
        #expect(abs(HUDLuminance.relative(red: 0x80, green: 0x80, blue: 0x80) - 0.2158) < 0.001)
        // 緑がいちばん明るく見える
        #expect(HUDLuminance.relative(red: 0, green: 255, blue: 0) > HUDLuminance.relative(red: 255, green: 0, blue: 0))
        #expect(abs(HUDLuminance.contrastRatio(1, 0) - 21) < 1e-9)
    }

    /// 左半分が黒、右半分が白の 8×8 の画像
    static func splitImage() -> HUDBackdropLuminance.Image {
        var pixels = [UInt8](repeating: 0, count: 8 * 8 * 4)
        for y in 0..<8 {
            for x in 0..<8 {
                let base = y * 32 + x * 4
                let value: UInt8 = x >= 4 ? 255 : 0
                pixels[base] = value
                pixels[base + 1] = value
                pixels[base + 2] = value
                pixels[base + 3] = 255
            }
        }
        return HUDBackdropLuminance.Image(width: 8, height: 8, bytesPerRow: 32, pixels: pixels)
    }

    @Test("各点の周りの平均の明るさ。画像の外は数えず、1ピクセルも入らなければいちばん近いピクセル")
    func averages() {
        let image = Self.splitImage()
        let values = HUDBackdropLuminance.averages(in: image, around: [CGPoint(x: 2, y: 4), CGPoint(x: 6, y: 4), CGPoint(x: 4, y: 4)], radius: 1.5)
        #expect(values[0] == 0)
        #expect(abs(values[1] - 1) < 1e-9)
        #expect(values[2] > 0.3 && values[2] < 0.7)
        // 画像の外の点: 近いピクセル
        let outside = HUDBackdropLuminance.averages(in: image, around: [CGPoint(x: -5, y: 4), CGPoint(x: 20, y: 4)], radius: 0.1)
        #expect(outside[0] == 0 && abs(outside[1] - 1) < 1e-9)
        // BGRA の並びも読める
        var bgra = image
        bgra.redOffset = 2
        bgra.blueOffset = 0
        #expect(HUDBackdropLuminance.averages(in: bgra, around: [CGPoint(x: 6, y: 4)], radius: 1)[0] > 0.99)
        #expect(HUDBackdropLuminance.luminance(in: image, x: 8, y: 0) == nil)
    }

    /// 上半分が白、下半分が黒の画像
    static func splitCGImage(side: Int) throws -> CGImage {
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        for y in 0..<side {
            for x in 0..<side {
                let base = (y * side + x) * 4
                let value: UInt8 = y < side / 2 ? 255 : 0
                pixels[base] = value
                pixels[base + 1] = value
                pixels[base + 2] = value
                pixels[base + 3] = 255
            }
        }
        let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        return try #require(CGImage(
            width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4, space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
    }

    @Test("撮った画像を縮めて測る: 上下を取り違えない（上の鍵は上の行、下の鍵は下の行）")
    func measuresTheCapturedImageUpright() throws {
        let image = try Self.splitCGImage(side: 96)
        let rect = CGRect(x: 100, y: 100, width: 268, height: 268)
        let metrics = HUDMetrics(scale: 1)
        let keys = [metrics.position(ofCell: 1), metrics.position(ofCell: 7), metrics.position(ofCell: 3)]
        let values = try #require(ScreenCaptureBackdropSampler.measure(image, rect: rect, keys: keys, radius: metrics.selectionRadius))
        #expect(values.count == 3)
        #expect(values[0] > 0.99)
        #expect(values[1] < 0.01)
        // 真横（左）の鍵は境目の上: 白と黒の間
        #expect(values[2] > 0.2 && values[2] < 0.8)
    }

    @Test("出すとき: 設定がオンで許可があれば、円の枠と 9 つの鍵の位置を渡して測り、測り終えたら鍵ごとの色にする")
    func samplesOnShow() throws {
        let sampler = FakeSampler()
        sampler.luminances = [1, 0, 1, 0, 1, 0, 1, 0, 1]
        let hud = HUDWindowController(screens: { [Self.main] }, mouseLocation: { CGPoint(x: 700, y: 450) }, backdropSampler: sampler)
        let map = try #require(hud.show(Self.model()))
        #expect(sampler.requests.count == 1)
        let request = try #require(sampler.requests.first)
        #expect(request.rect == map)
        #expect(request.keys.count == 9)
        #expect(request.keys[4] == CGPoint(x: HUDLayout.selectionRadius * 0 + RadialLayout.outerRadius, y: RadialLayout.outerRadius))
        #expect(request.keys[5].x > request.keys[4].x && abs(request.keys[5].y - request.keys[4].y) < 1e-9)
        #expect(request.radius == HUDLayout.selectionRadius)
        #expect(hud.inks.keys[0] == .onLight && hud.inks.keys[1] == .onDark)
        // 表示中の update では測り直さない
        hud.update(Self.model())
        #expect(sampler.requests.count == 1)
        hud.hide()
    }

    @Test("出すとき: 設定がオフ・許可が無い・測る部品が無いときは測らず、黒に白い縁のまま")
    func skipsSampling() {
        let sampler = FakeSampler()
        sampler.luminances = [0, 0, 0, 0, 0, 0, 0, 0, 0]
        let off = HUDWindowController(screens: { [Self.main] }, mouseLocation: { CGPoint(x: 700, y: 450) }, backdropSampler: sampler)
        off.show(Self.model(adaptsInk: false))
        #expect(sampler.requests.isEmpty)
        #expect(off.inks == .fallback)
        off.hide()
        sampler.isAvailable = false
        let denied = HUDWindowController(screens: { [Self.main] }, mouseLocation: { CGPoint(x: 700, y: 450) }, backdropSampler: sampler)
        denied.show(Self.model())
        #expect(sampler.requests.isEmpty)
        #expect(denied.inks == .fallback)
        denied.hide()
        let none = HUDWindowController(screens: { [Self.main] }, mouseLocation: { CGPoint(x: 700, y: 450) })
        none.show(Self.model())
        #expect(none.inks == .fallback)
        none.hide()
    }

    @Test("測り終える前に閉じた・出し直したら、その結果は使わない")
    func lateResultsAreDropped() throws {
        let sampler = FakeSampler()
        sampler.defers = true
        let hud = HUDWindowController(screens: { [Self.main] }, mouseLocation: { CGPoint(x: 700, y: 450) }, backdropSampler: sampler)
        hud.show(Self.model())
        let first = try #require(sampler.pending)
        hud.hide()
        first([0, 0, 0, 0, 0, 0, 0, 0, 0])
        #expect(hud.inks == .fallback)
        // 出し直した後に、前の結果が届いても使わない。新しい結果は使う
        hud.show(Self.model())
        let second = try #require(sampler.pending)
        first([0, 0, 0, 0, 0, 0, 0, 0, 0])
        #expect(hud.inks == .fallback)
        second([0, 0, 0, 0, 0, 0, 0, 0, 0])
        #expect(hud.inks == HUDInks(all: .onDark))
        hud.hide()
    }
}
