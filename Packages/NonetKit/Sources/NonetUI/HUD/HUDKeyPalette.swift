// 担当: ui-shell
// HUD の鍵の色。鍵ごとの暗い台（HUDPlate）に白いアイコンを載せ、向いている鍵だけ白い円に濃いアイコン。下の画面の明るさは測らない
import Foundation
import SwiftUI

/// HUD の鍵の色の値
enum HUDKeyPalette {
    /// 白い円・名前の帯の上のアイコンと文字
    static let onSelection = Color(white: 0x10 / 255)
    /// 外枠にいる・2本の指のときの、アイコン（と点・印）の不透明度（離しても実行しないことを見せる）。台は薄くしない:
    /// 台ごと薄くすると明るい画面で白いアイコンが消え、台の下のガラスは親の不透明度では薄くならない。「コントラストを上げる」では薄くしすぎない
    static let dimmedIconOpacity = 0.4
    static let dimmedIconOpacityIncreased = 0.55

    /// 台の色（白の量）
    static let plateWhite = 0.1
    /// グローバルの層の台の色（sRGB）。紺に寄せ、文字を出さずに層が分かるようにする。白いアイコンとの比は plateWhite と同じく確かめる
    static let globalPlate = (red: 0.055, green: 0.133, blue: 0.29)
    /// 台の不透明度。macOS 26 以降は下にガラスを敷いてぼかすので 0.68、それより前はぼかせないので、下の文字が透けにくい 0.8。
    /// 「コントラストを上げる」では 0.85。「透明度を下げる」では不透明（HUDPlateStyle.opacity）
    static let plateOpacityGlass = 0.68
    static let plateOpacitySolid = 0.8
    static let plateOpacityIncreased = 0.85
    /// 台の縁（暗い画面で台の形を見せる）
    static let plateBorderOpacity = 0.18
    static let plateBorderOpacityIncreased = 0.45
}

/// 台の描き方。システム設定の「コントラストを上げる」「透明度を下げる」と、面（HUDSurface: macOS 26 以降はガラス）で決まる。
/// どの組み合わせでも、真っ白な画面の上で白いアイコンとのコントラスト比が 4.5:1 以上（ガラスの 0.68 で約 6:1、0.8 で約 9:1、0.85 で約 11:1）
struct HUDPlateStyle: Equatable {
    var increasedContrast = false
    var reduceTransparency = false
    /// グローバルの層（アプリの層と2つあるとき）。台を紺に寄せる
    var isGlobalLayer = false
    /// ページか層を押し出している間は false: ガラスは親の不透明度で薄くならず、消えていく輪にぼけた丸だけが残るので、
    /// 動いている間はガラスを外す（濃さはガラスのときのまま。止まったら今の輪にガラスを戻す）
    var showsGlass = true
    var surface = HUDSurface.current

    /// 面がガラスの macOS で、「透明度を下げる」がオフ（台の濃さはガラスのときの値）
    private var isGlassSurface: Bool { surface == .glass && !reduceTransparency }

    /// 台の下にガラスを敷いてぼかすか。「透明度を下げる」では敷かず、不透明な台にする（トーストの面と同じ扱い）
    var usesGlass: Bool { isGlassSurface && showsGlass }

    var opacity: Double {
        if reduceTransparency { return 1 }
        if increasedContrast { return HUDKeyPalette.plateOpacityIncreased }
        return isGlassSurface ? HUDKeyPalette.plateOpacityGlass : HUDKeyPalette.plateOpacitySolid
    }

    /// 台の色（sRGB の 0〜1）
    var color: (red: Double, green: Double, blue: Double) {
        isGlobalLayer ? HUDKeyPalette.globalPlate : (HUDKeyPalette.plateWhite, HUDKeyPalette.plateWhite, HUDKeyPalette.plateWhite)
    }

    var fill: Color {
        let color = self.color
        return Color(red: color.red, green: color.green, blue: color.blue).opacity(opacity)
    }

    var borderOpacity: Double {
        increasedContrast ? HUDKeyPalette.plateBorderOpacityIncreased : HUDKeyPalette.plateBorderOpacity
    }

    /// 外枠などで薄くするときの、アイコン・点・印の不透明度
    var dimmedIconOpacity: Double {
        increasedContrast ? HUDKeyPalette.dimmedIconOpacityIncreased : HUDKeyPalette.dimmedIconOpacity
    }

    /// 台を灰色の下地（白の量 0〜1）に重ねたときの相対輝度。sRGB のまま混ぜる（画面の合成と同じ）。
    /// 下のガラスは数えない: ガラスがどれだけ明るくなっても白より明るくはならないので、真っ白な下地で比を確かめれば足りる
    func luminance(over backdropWhite: Double) -> Double {
        let mix = { (channel: Double) in channel * opacity + backdropWhite * (1 - opacity) }
        let color = self.color
        return 0.2126 * HUDLuminance.linear(mix(color.red)) + 0.7152 * HUDLuminance.linear(mix(color.green)) + 0.0722 * HUDLuminance.linear(mix(color.blue))
    }
}

/// WCAG 2 の相対輝度とコントラスト比。HUD の台（HUDPlateStyle）とトーストの色（HUDPalette）の確かめに使う
enum HUDLuminance {
    /// sRGB の 0〜1 を線形の明るさにする（ガンマを戻す）
    static func linear(_ value: Double) -> Double {
        value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    static func linear(_ channel: UInt8) -> Double {
        linear(Double(channel) / 255)
    }

    /// 相対輝度（0 が黒、1 が白）
    static func relative(red: UInt8, green: UInt8, blue: UInt8) -> Double {
        0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// 灰色（白の量 0〜1）の相対輝度
    static func relative(white: Double) -> Double {
        linear(white)
    }

    /// コントラスト比（相対輝度で渡す）
    static func contrastRatio(_ first: Double, _ second: Double) -> Double {
        (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    /// 灰色どうしのコントラスト比（白の量 0〜1 で渡す）
    static func contrastRatio(white first: Double, white second: Double) -> Double {
        contrastRatio(relative(white: first), relative(white: second))
    }
}
