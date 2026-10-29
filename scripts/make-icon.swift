#!/usr/bin/env swift
// アプリのアイコンを描いて App/Assets.xcassets/AppIcon.appiconset に書き出す。
// 使い方: swift scripts/make-icon.swift [出力先の .appiconset]
// 形はモックのロゴ（角の丸い 3×3、中央が塗り）。黒い角丸の板に白で描く。小さいサイズは線が潰れるので塗りで描く
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 1024 の下絵での寸法（macOS 11 以降のアイコンのテンプレート: 824 の板を 100 の余白で置く）
enum IconGeometry {
    static let canvas: CGFloat = 1024
    static let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
    static let plateRadius: CGFloat = 185.4
    /// 板の幅に対する 3×3 の幅（小さいサイズは大きめにして読めるようにする）
    static func gridRatio(simplified: Bool) -> CGFloat { simplified ? 0.62 : 0.54 }
    /// マスと隙間の比はロゴと同じ（マス 5、隙間 2.5）
    static let cellToGap: CGFloat = 2
    static let strokeRatio: CGFloat = 0.2
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

func render(pixels: Int) -> CGImage? {
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
        context.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: CGColor(gray: 0, alpha: 0.35))
    }
    context.addPath(plate)
    context.setFillColor(CGColor(gray: 0.07, alpha: 1))
    context.fillPath()
    context.restoreGState()

    // 上から下へわずかに暗くする
    context.saveGState()
    context.addPath(plate)
    context.clip()
    if let gradient = CGGradient(
        colorsSpace: space,
        colors: [CGColor(gray: 0.17, alpha: 1), CGColor(gray: 0.05, alpha: 1)] as CFArray,
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

    // 板の縁のかすかな光
    if !simplified {
        context.saveGState()
        context.addPath(CGPath(
            roundedRect: IconGeometry.plate.insetBy(dx: 1.5, dy: 1.5),
            cornerWidth: IconGeometry.plateRadius - 1.5,
            cornerHeight: IconGeometry.plateRadius - 1.5,
            transform: nil
        ))
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.10))
        context.setLineWidth(3)
        context.strokePath()
        context.restoreGState()
    }

    // 3×3。中央は白で塗り、ほかは白い線（小さいサイズは薄い塗り）
    for (index, rect) in IconGeometry.cells(simplified: simplified).enumerated() {
        let radius = rect.width * IconGeometry.cornerRatio
        let isCenter = index == 4
        if isCenter || simplified {
            context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.setFillColor(CGColor(gray: 1, alpha: isCenter ? 1 : 0.42))
            context.fillPath()
        } else {
            let line = rect.width * IconGeometry.strokeRatio
            let inner = rect.insetBy(dx: line / 2, dy: line / 2)
            let innerRadius = max(0, radius - line / 2)
            context.addPath(CGPath(roundedRect: inner, cornerWidth: innerRadius, cornerHeight: innerRadius, transform: nil))
            context.setStrokeColor(CGColor(gray: 1, alpha: 0.92))
            context.setLineWidth(line)
            context.strokePath()
        }
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
let output = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    : root.appendingPathComponent("App/Assets.xcassets/AppIcon.appiconset", isDirectory: true)

do {
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    for size in sizes {
        guard let image = render(pixels: size.pixels) else {
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
