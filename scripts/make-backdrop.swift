// 宣伝用の画像とデモ動画に敷く背景（暗いグラデーションとメニューバー）を PNG に書き出す。
// 販売ページ・AstLog の画像（scripts/compose-store-image.swift）とデモ動画（--demo-backdrop）・HUD の写真（--preview-backdrop）は、
// どれもこの背景の上で作る。実際の画面（壁紙・ほかのアプリのウインドウ）は写さない。
// ほかのアプリ（AppMixer・NotchPocket など）のデモ動画も同じ背景にそろえる（~/.claude/rules/demo-video.md）。色と寸法は変えない。
// 変えてよいのは、メニューバーの右に描くアプリ自身のアイコン（statusIcon）だけ。
//
// 寸法は 1440×900 の絵を基準にし、幅に合わせて拡大する（上端にそろえる。16:10 より縦長の画面では、下はグラデーションの続き）。
// 使い方: swift scripts/make-backdrop.swift <out.png> [<幅 px> <高さ px>] [--no-status-icon]
//   幅と高さを省くと、いまのメインの画面の大きさ（ピクセル）。デモ動画にはこれを使う。画像の合成（1440×900 の @2x）には 2880 1800
import AppKit
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let usage = "使い方: swift scripts/make-backdrop.swift <out.png> [<幅 px> <高さ px>] [--no-status-icon]\n"
var args = Array(CommandLine.arguments.dropFirst())
let statusIcon = !args.contains("--no-status-icon")
args.removeAll { $0 == "--no-status-icon" }
guard args.count == 1 || args.count == 3 else {
    FileHandle.standardError.write(Data(usage.utf8)); exit(2)
}
let size: (width: Int, height: Int)
if args.count == 3 {
    guard let w = Int(args[1]), let h = Int(args[2]), w > 0, h > 0 else { FileHandle.standardError.write(Data(usage.utf8)); exit(2) }
    size = (w, h)
} else {
    // 主の画面（デモの背景を敷き、収録する画面）の大きさ
    guard let screen = NSScreen.screens.first else { FileHandle.standardError.write(Data("画面が見つかりません。幅と高さを指定してください\n".utf8)); exit(2) }
    size = (Int(screen.frame.width * screen.backingScaleFactor), Int(screen.frame.height * screen.backingScaleFactor))
}

let W: CGFloat = 1440, H: CGFloat = 900
let s = CGFloat(size.width) / W   // 基準の 1pt が何 px か
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size.width, height: size.height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
// 基準の 1440×900 を上端にそろえて置く（y は上向き）
ctx.translateBy(x: 0, y: CGFloat(size.height) - H * s)
ctx.scaleBy(x: s, y: s)
ctx.interpolationQuality = .high
func rgb(_ hex: Int, _ a: CGFloat = 1) -> CGColor { CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: a) }

// 背景: 暗い無彩色のグラデーション（左上 #1F1F21 → 右下 #0E0E0F。macOS のダークに近い灰。色みを持たせず、どのアプリの差し色にも合う。2026-11-09 に所有者が選んだ）
let bg = CGGradient(colorsSpace: space, colors: [rgb(0x1F1F21), rgb(0x0E0E0F)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: H), end: CGPoint(x: W, y: 0), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
// メニューバー（高さ 34・#161617。下に白 6% の 1pt の線）
ctx.setFillColor(rgb(0x161617)); ctx.fill(CGRect(x: 0, y: H - 34, width: W, height: 34))
ctx.setFillColor(rgb(0xFFFFFF, 0.06)); ctx.fill(CGRect(x: 0, y: H - 35, width: W, height: 1))

func text(_ string: String, font: CTFont, color: CGColor, rightEdge x: CGFloat, baseline y: CGFloat) {
    let attr = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color] as CFDictionary
    let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, string as CFString, attr))
    let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    ctx.textPosition = CGPoint(x: x - width, y: y)
    CTLineDraw(line, ctx)
}
// SF Symbols を色を付けて、出す大きさの解像度で描く
func drawSymbol(_ name: String, center: CGPoint, size points: CGFloat, weight: NSFont.Weight = .semibold, color: NSColor = .white) {
    guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: points, weight: weight)) else { return }
    let box = image.size
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int((box.width * s).rounded(.up)), pixelsHigh: Int((box.height * s).rounded(.up)), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
    rep.size = box
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let rect = NSRect(origin: .zero, size: box)
    image.draw(in: rect); color.set(); rect.fill(using: .sourceAtop)
    NSGraphicsContext.restoreGraphicsState()
    guard let cg = rep.cgImage else { return }
    ctx.draw(cg, in: CGRect(x: center.x - box.width / 2, y: center.y - box.height / 2, width: box.width, height: box.height))
}

// メニューバーの右側（右から: 日付・コントロールセンター・Wi-Fi・電池・アプリのアイコン）
let barY = H - 17
text("11月7日(土) 9:41", font: CTFontCreateUIFontForLanguage(.system, 13, nil)!, color: rgb(0xF2F2F2), rightEdge: 1416, baseline: barY - 5)
drawSymbol("switch.2", center: CGPoint(x: 1222, y: barY), size: 13)
drawSymbol("wifi", center: CGPoint(x: 1172, y: barY), size: 13)
drawSymbol("battery.100percent", center: CGPoint(x: 1116, y: barY), size: 15, weight: .regular)
// アプリ自身のメニューバーのアイコン（中心 x=1066）。ほかのアプリでは、ここだけをそのアプリのアイコンに替える
func drawStatusIcon(center c: CGPoint) {
    // Nonet: 輪の 8 点と真ん中
    ctx.setFillColor(rgb(0xF2F2F2))
    for slot in 0..<8 {
        let a = (-90 + 45 * Double(slot)) * .pi / 180
        let p = CGPoint(x: c.x + 6.3 * cos(a), y: c.y - 6.3 * sin(a))
        ctx.fillEllipse(in: CGRect(x: p.x - 1.7, y: p.y - 1.7, width: 3.4, height: 3.4))
    }
    ctx.fillEllipse(in: CGRect(x: c.x - 2.1, y: c.y - 2.1, width: 4.2, height: 4.2))
}
if statusIcon { drawStatusIcon(center: CGPoint(x: 1066, y: barY)) }

let out = URL(fileURLWithPath: (args[0] as NSString).expandingTildeInPath)
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
guard CGImageDestinationFinalize(dest) else { FileHandle.standardError.write(Data("書き出せません: \(out.path)\n".utf8)); exit(1) }
print("wrote \(out.path) (\(size.width)×\(size.height))")
