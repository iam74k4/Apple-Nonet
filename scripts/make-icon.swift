#!/usr/bin/env swift
// アプリのアイコンを描いて App/Assets.xcassets/AppIcon.appiconset に書き出す。
// 使い方: swift scripts/make-icon.swift [出力先の .appiconset] [--accent RRGGBB か RRGGBB-RRGGBB] [--preview 1024px の PNG]
//        [--site-icon AstLog のアイコンにする 256px の PNG（影なし）]
// HUD と同じ形にする: HUD はポインタの周りに9つのアイコンが輪になって出るので、黒い板に8つの白い点を輪に置き、
// 真ん中（ポインタのいるところ。指を離して実行するマス）だけを差し色で塗る。差し色は青から紫へのグラデーション
// （同じ作者の AppMixer は青、SaifuLog はオレンジなので、それらとかぶらない色）。
// 板の作り（824 の角丸・100 の余白・影・上から下へ暗くなるグラデーション）は AppMixer・SaifuLog と同じ
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 色。板は #1C1C1E から #000000 へ暗くなる黒い板、影は下へ 18・ぼかし 44・不透明度 0.38
enum IconPalette {
    static let plateTop = (r: 0x1C, g: 0x1C, b: 0x1E)
    static let plateBottom = (r: 0x00, g: 0x00, b: 0x00)
    /// 輪の8つの点（白。わずかに透かして板になじませる）
    static let ringDotAlpha: CGFloat = 0.92
    /// 真ん中の点の差し色。左上から右下へ、システムの青（#0A84FF）からシステムの紫（#BF5AF2）へ
    static let accent = "0A84FF-BF5AF2"
}

/// 1024 の下絵での寸法（macOS 11 以降のアイコンのテンプレート: 824 の板を 100 の余白で置く）
enum IconGeometry {
    static let canvas: CGFloat = 1024
    static let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
    static let plateRadius: CGFloat = 185.4
    /// AstLog（https://astlog.dev）の作品のアイコンの大きさ。AppMixer・SaifuLog も 256×256
    static let sitePixels = 256
    static var center: CGPoint { CGPoint(x: plate.midX, y: plate.midY) }
    /// 板の幅に対する輪の半径と点の半径。小さいサイズ（32px 以下）は点を大きく、輪を少し広げて読めるようにする
    static func ringRadius(simplified: Bool) -> CGFloat { plate.width * (simplified ? 0.32 : 0.30) }
    static func dotRadius(simplified: Bool) -> CGFloat { plate.width * (simplified ? 0.1 : 0.072) }

    /// 輪の8つの点の中心（左下が原点の座標）。上から時計回り（HUD のアイコンの並びと同じ: 0 が上、1 が右上…）
    static func ringPoints(simplified: Bool) -> [CGPoint] {
        let radius = ringRadius(simplified: simplified)
        return (0..<8).map { slot in
            let angle = (-90 + 45 * Double(slot)) * .pi / 180
            return CGPoint(x: center.x + radius * cos(angle), y: center.y - radius * sin(angle))
        }
    }

    static func circle(at point: CGPoint, radius: CGFloat) -> CGPath {
        CGPath(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2), transform: nil)
    }
}

struct IconSize {
    var points: Int
    var scale: Int

    var pixels: Int { points * scale }
    var filename: String { scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@\(scale)x.png" }
}

let sizes = [16, 32, 128, 256, 512].flatMap { points in [1, 2].map { IconSize(points: points, scale: $0) } }

func color(hex: String, alpha: CGFloat = 1) -> CGColor {
    let value = Int(hex, radix: 16) ?? 0
    return CGColor(
        srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
        green: CGFloat((value >> 8) & 0xFF) / 255,
        blue: CGFloat(value & 0xFF) / 255,
        alpha: alpha
    )
}

func color(_ rgb: (r: Int, g: Int, b: Int)) -> CGColor {
    CGColor(srgbRed: CGFloat(rgb.r) / 255, green: CGFloat(rgb.g) / 255, blue: CGFloat(rgb.b) / 255, alpha: 1)
}

/// 差し色。1色（RRGGBB）か、左上から右下へのグラデーション（RRGGBB-RRGGBB）
struct Accent {
    var top: CGColor
    var bottom: CGColor

    init?(_ text: String) {
        let parts = text.split(separator: "-").map(String.init)
        guard (1...2).contains(parts.count), parts.allSatisfy({ $0.count == 6 && Int($0, radix: 16) != nil }) else { return nil }
        top = color(hex: parts[0])
        bottom = color(hex: parts.count == 2 ? parts[1] : parts[0])
    }

    func fill(_ path: CGPath, in context: CGContext, space: CGColorSpace) {
        context.saveGState()
        defer { context.restoreGState() }
        context.addPath(path)
        guard top != bottom, let gradient = CGGradient(colorsSpace: space, colors: [top, bottom] as CFArray, locations: [0, 1]) else {
            context.setFillColor(top)
            context.fillPath()
            return
        }
        context.clip()
        let box = path.boundingBox
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: box.minX, y: box.maxY),
            end: CGPoint(x: box.maxX, y: box.minY),
            options: []
        )
    }
}

/// shadow を外すのは AstLog に載せるアイコン（--site-icon）だけ。影は板の外の余白を薄い黒で埋め、
/// 絵の端で四角く切れるので、Web ページの明るい地に置くと板のまわりに灰色の四角が見える
/// （AstLog の AppMixer・SaifuLog のアイコンも影なし。板の外は透明）
func render(pixels: Int, accent: Accent, shadow: Bool = true) -> CGImage? {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
              data: nil,
              width: pixels,
              height: pixels,
              bitsPerComponent: 8,
              bytesPerRow: 0,
              space: space,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ) else { return nil }
    let scale = CGFloat(pixels) / IconGeometry.canvas
    context.scaleBy(x: scale, y: scale)
    context.interpolationQuality = .high
    let simplified = pixels <= 32

    // 板（影つき）
    let plate = CGPath(
        roundedRect: IconGeometry.plate,
        cornerWidth: IconGeometry.plateRadius,
        cornerHeight: IconGeometry.plateRadius,
        transform: nil
    )
    context.saveGState()
    if shadow && !simplified {
        context.setShadow(offset: CGSize(width: 0, height: -18), blur: 44, color: CGColor(gray: 0, alpha: 0.38))
    }
    context.addPath(plate)
    context.setFillColor(color(IconPalette.plateBottom))
    context.fillPath()
    context.restoreGState()

    // 上から下へ暗くする
    context.saveGState()
    context.addPath(plate)
    context.clip()
    if let gradient = CGGradient(
        colorsSpace: space,
        colors: [color(IconPalette.plateTop), color(IconPalette.plateBottom)] as CFArray,
        locations: [0, 1]
    ) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: IconGeometry.plate.maxY),
            end: CGPoint(x: 0, y: IconGeometry.plate.minY),
            options: []
        )
    }
    context.restoreGState()

    // 輪の8つの点は白、真ん中（ポインタのいるところ）だけ差し色
    let radius = IconGeometry.dotRadius(simplified: simplified)
    context.setFillColor(CGColor(gray: 1, alpha: IconPalette.ringDotAlpha))
    for point in IconGeometry.ringPoints(simplified: simplified) {
        context.addPath(IconGeometry.circle(at: point, radius: radius))
        context.fillPath()
    }
    accent.fill(IconGeometry.circle(at: IconGeometry.center, radius: radius), in: context, space: space)
    return context.makeImage()
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "make-icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "PNG を作れません: \(url.path)"])
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "make-icon", code: 2, userInfo: [NSLocalizedDescriptionKey: "PNG を書けません: \(url.path)"])
    }
}

func contentsJSON() -> String {
    let images = sizes.map { size in
        """
            { "filename" : "\(size.filename)", "idiom" : "mac", "scale" : "\(size.scale)x", "size" : "\(size.points)x\(size.points)" }
        """
    }
    return """
    {
      "images" : [
    \(images.joined(separator: ",\n"))
      ],
      "info" : {
        "author" : "xcode",
        "version" : 1
      }
    }

    """
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
var arguments = Array(CommandLine.arguments.dropFirst())

/// `--name 値` を取り出す
func option(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
    let value = arguments[index + 1]
    arguments.removeSubrange(index...(index + 1))
    return value
}

let accentText = option("--accent") ?? IconPalette.accent
let preview = option("--preview")
let siteIcon = option("--site-icon")
let output = arguments.first.map { URL(fileURLWithPath: $0, isDirectory: true) }
    ?? root.appendingPathComponent("App/Assets.xcassets/AppIcon.appiconset", isDirectory: true)

do {
    guard let accent = Accent(accentText) else {
        throw NSError(domain: "make-icon", code: 4, userInfo: [NSLocalizedDescriptionKey: "--accent は RRGGBB か RRGGBB-RRGGBB で: \(accentText)"])
    }
    if let preview {
        guard let image = render(pixels: Int(IconGeometry.canvas), accent: accent) else {
            throw NSError(domain: "make-icon", code: 3, userInfo: [NSLocalizedDescriptionKey: "下絵を描けません"])
        }
        try writePNG(image, to: URL(fileURLWithPath: preview))
        print("書き出しました: \(preview)")
        exit(0)
    }
    if let siteIcon {
        guard let image = render(pixels: IconGeometry.sitePixels, accent: accent, shadow: false) else {
            throw NSError(domain: "make-icon", code: 3, userInfo: [NSLocalizedDescriptionKey: "AstLog のアイコンを描けません"])
        }
        try writePNG(image, to: URL(fileURLWithPath: siteIcon))
        print("書き出しました: \(siteIcon)")
        exit(0)
    }
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    for size in sizes {
        guard let image = render(pixels: size.pixels, accent: accent) else {
            throw NSError(domain: "make-icon", code: 3, userInfo: [NSLocalizedDescriptionKey: "\(size.pixels)px を描けません"])
        }
        try writePNG(image, to: output.appendingPathComponent(size.filename))
        print("\(size.filename) (\(size.pixels)px)")
    }
    try Data(contentsJSON().utf8).write(to: output.appendingPathComponent("Contents.json"), options: .atomic)
    print("書き出しました: \(output.path)")
} catch {
    FileHandle.standardError.write(Data("make-icon: \(error.localizedDescription)\n".utf8))
    exit(1)
}
