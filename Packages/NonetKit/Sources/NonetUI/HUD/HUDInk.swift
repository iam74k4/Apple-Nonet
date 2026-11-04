// 担当: ui-shell
// HUD のアイコンの色。皿も輪も無いので、下地（HUD の下の画面）の明るさに合わせて、鍵ごとに白か濃い色かを決める
import Foundation
import SwiftUI

/// 1つの鍵の色
enum HUDInk: Equatable, Sendable {
    /// 明るい下地: 濃いアイコンに白い縁
    case onLight
    /// 暗い下地: 白いアイコンに黒い影
    case onDark

    var color: Color {
        switch self {
        case .onLight: HUDInkPalette.dark
        case .onDark: .white
        }
    }
}

/// 9つの鍵（マスの番号順）の色
struct HUDInks: Equatable, Sendable {
    var keys: [HUDInk]

    init(keys: [HUDInk]) {
        self.keys = keys
    }

    init(all ink: HUDInk) {
        keys = Array(repeating: ink, count: 9)
    }

    /// 下地を測れないとき（画面収録の許可が無い・設定でオフ・測り終える前）: ポインタと同じ、黒いアイコンに白い縁で全部描く。
    /// どの下地でも読める
    static let fallback = HUDInks(all: .onLight)

    func ink(at index: Int) -> HUDInk {
        keys.indices.contains(index) ? keys[index] : .onLight
    }
}

/// HUD の色の値
enum HUDInkPalette {
    /// 明るい下地のアイコンと、白い円の上のアイコン
    static let dark = Color(white: 0x1A / 255)
    static let onSelection = Color(white: 0x10 / 255)
    /// 外枠にいる・2本の指のときの、鍵の不透明度（離しても実行しないことを見せる）。「コントラストを上げる」では薄くしすぎない
    static let dimmedOpacity = 0.35
    static let dimmedOpacityIncreased = 0.5
}

/// 下地の明るさから色を決める
enum HUDInkDecision {
    /// 相対輝度のしきい値。白と黒のコントラスト比（WCAG 2）が同じになる明るさ: (L + 0.05)² = 1.05 × 0.05 → L ≈ 0.179。
    /// これより明るい下地では黒のほうが、暗い下地では白のほうが読みやすい
    static let threshold = 0.179

    static func ink(forLuminance luminance: Double) -> HUDInk {
        guard luminance.isFinite else { return .onLight }
        return luminance >= threshold ? .onLight : .onDark
    }

    /// 鍵ごとの相対輝度（マスの番号順に 9 つ）から。足りない・測れなければ fallback
    static func inks(forLuminances luminances: [Double]?) -> HUDInks {
        guard let luminances, luminances.count >= 9 else { return .fallback }
        return HUDInks(keys: luminances.prefix(9).map(ink(forLuminance:)))
    }
}

/// 撮った画像から、各鍵の下の平均の明るさを出す
enum HUDBackdropLuminance {
    /// 8ビットの RGBA（行ごとに bytesPerRow）の画像
    struct Image {
        var width: Int
        var height: Int
        var bytesPerRow: Int
        var pixels: [UInt8]
        /// 1ピクセルの中の、赤・緑・青の位置（RGBA なら 0・1・2、BGRA なら 2・1・0）
        var redOffset = 0
        var greenOffset = 1
        var blueOffset = 2
    }

    /// sRGB の 0〜255 を線形の明るさにする（WCAG 2）
    static func linear(_ channel: UInt8) -> Double {
        let value = Double(channel) / 255
        return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    /// 相対輝度（0 が黒、1 が白）
    static func luminance(red: UInt8, green: UInt8, blue: UInt8) -> Double {
        0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// 灰色どうしのコントラスト比（WCAG 2。相対輝度で渡す）
    static func contrastRatio(_ first: Double, _ second: Double) -> Double {
        (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    /// 各点（画像の座標。左上が原点）の周り radius の中の、平均の相対輝度。画像の外は数えない。
    /// 1ピクセルも入らない点は、その点にいちばん近いピクセル
    static func averages(in image: Image, around points: [CGPoint], radius: CGFloat) -> [Double] {
        points.map { point in
            var total = 0.0
            var count = 0
            let minX = max(Int((point.x - radius).rounded(.down)), 0)
            let maxX = min(Int((point.x + radius).rounded(.up)), image.width - 1)
            let minY = max(Int((point.y - radius).rounded(.down)), 0)
            let maxY = min(Int((point.y + radius).rounded(.up)), image.height - 1)
            if minX <= maxX, minY <= maxY {
                for y in minY...maxY {
                    for x in minX...maxX {
                        let dx = CGFloat(x) + 0.5 - point.x
                        let dy = CGFloat(y) + 0.5 - point.y
                        guard dx * dx + dy * dy <= radius * radius else { continue }
                        guard let value = luminance(in: image, x: x, y: y) else { continue }
                        total += value
                        count += 1
                    }
                }
            }
            if count > 0 { return total / Double(count) }
            let x = min(max(Int(point.x.rounded(.down)), 0), image.width - 1)
            let y = min(max(Int(point.y.rounded(.down)), 0), image.height - 1)
            return luminance(in: image, x: x, y: y) ?? 1
        }
    }

    static func luminance(in image: Image, x: Int, y: Int) -> Double? {
        guard x >= 0, y >= 0, x < image.width, y < image.height else { return nil }
        let base = y * image.bytesPerRow + x * 4
        guard base + 3 < image.pixels.count else { return nil }
        return luminance(red: image.pixels[base + image.redOffset], green: image.pixels[base + image.greenOffset], blue: image.pixels[base + image.blueOffset])
    }
}
