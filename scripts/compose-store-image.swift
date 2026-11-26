// AstLog の画像（1440×900 の JPEG）を作る。共通の背景（真っ黒の無地とメニューバー。scripts/make-backdrop.swift）の上に、
// 左に小見出し・見出し・説明・3 行の箇条、右に HUD の窓の画像（--snapshot の PNG）とポインタ。
// 背景はここで描かず、デモ動画と同じ make-backdrop.swift の PNG（2880×1800）を敷く（画像と動画の背景を1か所で決める）。
// 使い方: swift scripts/make-backdrop.swift backdrop.png 2880 1800
//         swift scripts/compose-store-image.swift <spec.json> <out.jpg> backdrop.png
import AppKit
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct Bullet: Decodable { var symbol: String; var text: String; var tag: String? }
struct Spec: Decodable {
    var hud: String            // HUD の窓の PNG（348pt 四方、@2x）
    var hudScale: Double       // 1pt を何 px に（1.7 なら 268pt の円が 456px）
    var pointer: [Double]      // ポインタの先端（HUD の正方形の pt 座標。中心が 134,134）
    var eyebrow: String
    var headline: [String]
    var description: [String]
    var bullets: [Bullet]
    var hudDim: Double?        // 外枠の絵のとき、HUD 全体の不透明度（薄さは窓の画像に入っているので普通は 1）
}
let args = CommandLine.arguments
let spec = try! JSONDecoder().decode(Spec.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
let W = 1440, H = 900, scale = 2
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: W * scale, height: H * scale, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
ctx.interpolationQuality = .high
func rgb(_ hex: Int, _ a: CGFloat = 1) -> CGColor { CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: a) }
// 背景: make-backdrop.swift の PNG（2880×1800。真っ黒の無地とメニューバー）を 1px ずつそのまま敷く
guard args.count == 4,
      let backdropSource = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[3]) as CFURL, nil),
      let backdrop = CGImageSourceCreateImageAtIndex(backdropSource, 0, nil) else {
    FileHandle.standardError.write(Data("使い方: swift scripts/compose-store-image.swift <spec.json> <out.jpg> <backdrop.png>（背景は swift scripts/make-backdrop.swift backdrop.png 2880 1800）\n".utf8)); exit(2)
}
guard backdrop.width == W * scale, backdrop.height == H * scale else {
    FileHandle.standardError.write(Data("背景は \(W * scale)×\(H * scale) で作ってください（いまは \(backdrop.width)×\(backdrop.height)）\n".utf8)); exit(2)
}
ctx.draw(backdrop, in: CGRect(x: 0, y: 0, width: CGFloat(W), height: CGFloat(H)))
func text(_ s: String, font: CTFont, color: CGColor, at p: CGPoint, align: String = "left") -> CGFloat {
    let attr = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color] as CFDictionary
    let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, s as CFString, attr))
    let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    ctx.textPosition = CGPoint(x: align == "right" ? p.x - width : p.x, y: p.y)
    CTLineDraw(line, ctx); return width
}
func hira(_ weight: String, _ size: CGFloat) -> CTFont { CTFontCreateWithName("HiraginoSans-\(weight)" as CFString, size, nil) }
func symbol(_ name: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> CGImage? {
    guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: size, weight: weight)) else { return nil }
    let tinted = NSImage(size: image.size, flipped: false) { rect in
        image.draw(in: rect); color.set(); rect.fill(using: .sourceAtop); return true
    }
    return tinted.cgImage(forProposedRect: nil, context: nil, hints: nil)
}
func drawSymbol(_ name: String, center: CGPoint, size: CGFloat, weight: NSFont.Weight = .semibold, color: NSColor = .white) {
    guard let img = symbol(name, size: size, weight: weight, color: color) else { return }
    let w = CGFloat(img.width) / 2, h = CGFloat(img.height) / 2  // NSImage は @2x で出るので半分に
    ctx.draw(img, in: CGRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h))
}
// 左の文: 小見出し（差し色）・見出し・説明・箇条
let accent = rgb(0x8C8BFF)
_ = text(spec.eyebrow, font: hira("W6", 17), color: accent, at: CGPoint(x: 80, y: 636))
var y: CGFloat = 582
for line in spec.headline { _ = text(line, font: hira("W7", 46), color: rgb(0xFFFFFF), at: CGPoint(x: 78, y: y)); y -= 60 }
y = 444
for line in spec.description { _ = text(line, font: hira("W3", 17), color: rgb(0xB9BEC4), at: CGPoint(x: 80, y: y)); y -= 33 }
y = 348
for b in spec.bullets {
    ctx.setFillColor(rgb(0x8C8BFF, 0.22)); let box = CGRect(x: 80, y: y - 11, width: 36, height: 36)
    ctx.addPath(CGPath(roundedRect: box, cornerWidth: 8, cornerHeight: 8, transform: nil)); ctx.fillPath()
    drawSymbol(b.symbol, center: CGPoint(x: box.midX, y: box.midY), size: 15, color: NSColor(red: 0.72, green: 0.72, blue: 1, alpha: 1))
    _ = text(b.text, font: hira("W6", 18), color: rgb(0xFFFFFF), at: CGPoint(x: 132, y: y))
    if let tag = b.tag {
        let f = hira("W6", 14); let attr = [kCTFontAttributeName: f, kCTForegroundColorAttributeName: rgb(0xFFFFFF)] as CFDictionary
        let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, tag as CFString, attr)); let tw = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let pill = CGRect(x: 580 - tw - 28, y: y - 9, width: tw + 28, height: 32)
        ctx.setFillColor(rgb(0xFFFFFF, 0.1)); ctx.addPath(CGPath(roundedRect: pill, cornerWidth: 16, cornerHeight: 16, transform: nil)); ctx.fillPath()
        ctx.textPosition = CGPoint(x: pill.minX + 14, y: y + 1); CTLineDraw(line, ctx)
    }
    y -= 52
}
// 右: HUD の窓（透明な PNG。348pt 四方、中心が円の中心）
let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: spec.hud) as CFURL, nil)!
let hud = CGImageSourceCreateImageAtIndex(src, 0, nil)!
let side = CGFloat(348) * CGFloat(spec.hudScale)
let center = CGPoint(x: 1015, y: 455)
ctx.saveGState(); ctx.setAlpha(CGFloat(spec.hudDim ?? 1))
ctx.draw(hud, in: CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side))
ctx.restoreGState()
// ポインタ（macOS の矢印。先端を指定の位置に）
do {
    let px = center.x + (CGFloat(spec.pointer[0]) - 174) * CGFloat(spec.hudScale)
    let py = center.y - (CGFloat(spec.pointer[1]) - 174) * CGFloat(spec.hudScale)
    let h: CGFloat = 26 * CGFloat(spec.hudScale) / 1.7
    let pts: [(CGFloat, CGFloat)] = [(0, 0), (0, 0.80), (0.20, 0.62), (0.33, 0.95), (0.46, 0.90), (0.33, 0.58), (0.58, 0.58)]
    let path = CGMutablePath()
    for (i, p) in pts.enumerated() { let q = CGPoint(x: px + p.0 * h, y: py - p.1 * h); i == 0 ? path.move(to: q) : path.addLine(to: q) }
    path.closeSubpath()
    ctx.saveGState(); ctx.setShadow(offset: CGSize(width: 0, height: -1.5), blur: 3, color: rgb(0x000000, 0.45))
    ctx.addPath(path); ctx.setFillColor(rgb(0x000000)); ctx.fillPath(); ctx.restoreGState()
    ctx.addPath(path); ctx.setStrokeColor(rgb(0xFFFFFF)); ctx.setLineWidth(1.6); ctx.setLineJoin(.round); ctx.strokePath()
}
let image = ctx.makeImage()!
// 1440×900 の JPEG（品質 85）
let out = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
out.interpolationQuality = .high; out.draw(image, in: CGRect(x: 0, y: 0, width: W, height: H))
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[2]) as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, out.makeImage()!, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary); CGImageDestinationFinalize(dest)
print("wrote \(args[2])")
