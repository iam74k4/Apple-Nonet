#!/usr/bin/env swift
// アプリのアイコンを描いて App/Assets.xcassets/AppIcon.appiconset に書き出す。
// 使い方: swift scripts/make-icon.swift [出力先の .appiconset] [--accent RRGGBB] [--preview 1024px の PNG]
// 同じ作者の AppMixer・SaifuLog のアイコンに合わせる: 上から下へ暗くなる無彩色の角丸の板に、触るところだけを
// システムの色1つで塗る。Nonet では 3×3 のうち、指を離して実行するマス（中央）だけを塗り、ほかの8マスは薄い白にする
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 色（AppMixer の make_icon.py と同じ値。板は #3A3A3C から #0B0B0D、影は下へ 18・ぼかし 22・不透明度 0.38）
enum IconPalette {
    static let plateTop = (r: 0x3A, g: 0x3A, b: 0x3C)
    static let plateBottom = (r: 0x0B, g: 0x0B, b: 0x0D)
    /// 使っていないマス（AppMixer のフェーダーの溝と同じ、白の 16%）。小さいサイズは潰れないよう濃くする
    static let restingCellAlpha: CGFloat = 0.16
    static let restingCellAlphaSimplified: CGFloat = 0.3
    /// 指を離して実行するマスの色（システムの緑。AppMixer は青、SaifuLog はオレンジ）
    static let accent = "30D158"
}

/// 1024 の下絵での寸法（macOS 11 以降のアイコンのテンプレート: 824 の板を 100 の余白で置く）
enum IconGeometry {
    static let canvas: CGFloat = 1024
    static let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
    static let plateRadius: CGFloat = 185.4
    /// 板の幅に対する 3×3 の幅（小さいサイズは大きめにして読めるようにする）。
    /// AppMixer のフェーダーの高さ（板の 60%）とそろえる
    static func gridRatio(simplified: Bool) -> CGFloat { simplified ? 0.66 : 0.6 }
    /// マスと隙間の比はロゴと同じ（マス 5、隙間 2.5）
    static let cellToGap: CGFloat = 2
    static let cornerRatio: CGFloat = 0.28

    /// 9つのマス（左下が原点の座標）。左上から右へ、上の行から
    static func cells(simplified: Bool) -> [CGRect] {
        let gridSize = plate.width * gridRatio(simplified: simplified)
        let cell = gridSize / (3 + 2 / cellToGap)
        let gap = cell / cellToGap
        let origin = CGPoint(x: plate.midX - gridSize / 2, y: plate.midY - gridSize / 2)
        return (0..<9).map { index in
            let row = CGFloat(index / 3)
            let column = CGFloat(index % 3)
            return CGRect(
                x: origin.x + column * (cell + gap),
                y: origin.y + (2 - row) * (cell + gap),
                width: cell,
                height: cell
            )
        }
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

func render(pixels: Int, accent: String) -> CGImage? {
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
    if !simplified {
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

    // 3×3。中央（指を離して実行するマス）だけを差し色で塗り、ほかは薄い白
    let restingAlpha = simplified ? IconPalette.restingCellAlphaSimplified : IconPalette.restingCellAlpha
    for (index, rect) in IconGeometry.cells(simplified: simplified).enumerated() {
        let radius = rect.width * IconGeometry.cornerRatio
        context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.setFillColor(index == 4 ? color(hex: accent) : CGColor(gray: 1, alpha: restingAlpha))
        context.fillPath()
    }
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

let accent = option("--accent") ?? IconPalette.accent
let preview = option("--preview")
let output = arguments.first.map { URL(fileURLWithPath: $0, isDirectory: true) }
    ?? root.appendingPathComponent("App/Assets.xcassets/AppIcon.appiconset", isDirectory: true)

do {
    if let preview {
        guard let image = render(pixels: Int(IconGeometry.canvas), accent: accent) else {
            throw NSError(domain: "make-icon", code: 3, userInfo: [NSLocalizedDescriptionKey: "下絵を描けません"])
        }
        try writePNG(image, to: URL(fileURLWithPath: preview))
        print("書き出しました: \(preview)")
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
