// 担当: ui-shell
// HUD の下の画面を 1 枚だけ撮り、鍵ごとの明るさを測る（アイコンの色を下地に合わせるため）。
// macOS の「画面収録」の許可が要る。画像はその場で捨て、保存も送信もしない
import AppKit
import CoreGraphics
import os
import ScreenCaptureKit

private let samplerLogger = Logger(subsystem: "com.iam74k4.Nonet", category: "ui-shell")

/// HUD の下の画面の明るさを測る
@MainActor
protocol HUDBackdropSampling: AnyObject {
    /// 測れるか（画面収録の許可があるか）。ダイアログは出さない
    var isAvailable: Bool { get }
    /// rect: HUD の円を囲む正方形（主画面の左上が原点、y が下向き。ポインタと同じ座標）。
    /// keys: 測る点（正方形の左上が原点、y が下向き、ポイント）。radius: 各点の周りで平均する円の半径（ポイント）。
    /// 結果は keys ごとの相対輝度（0〜1）。測れなければ nil。completion はメインスレッドで呼ぶ
    func sample(_ rect: CGRect, keys: [CGPoint], radius: CGFloat, completion: @escaping @MainActor ([Double]?) -> Void)
}

/// ScreenCaptureKit で撮る。Nonet 自身のウィンドウ（HUD・置く枠のプレビュー）は撮らない
@MainActor
final class ScreenCaptureBackdropSampler: HUDBackdropSampling {
    /// 撮る画像の一辺（ピクセル）。明るさの平均を取るだけなので小さくてよい（撮る時間も短い）
    static let imageSide = 48

    var isAvailable: Bool { CGPreflightScreenCaptureAccess() }

    func sample(_ rect: CGRect, keys: [CGPoint], radius: CGFloat, completion: @escaping @MainActor ([Double]?) -> Void) {
        guard rect.width > 0, rect.height > 0 else {
            completion(nil)
            return
        }
        let processID = ProcessInfo.processInfo.processIdentifier
        Task { @MainActor in
            let result = await Self.capture(rect, keys: keys, radius: radius, ownProcessID: processID)
            completion(result)
        }
    }

    /// 撮って測る。失敗したら nil（ログに理由を書く。開くたびに書かないよう、同じ理由は1回だけ）
    private static func capture(_ rect: CGRect, keys: [CGPoint], radius: CGFloat, ownProcessID: Int32) async -> [Double]? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let center = CGPoint(x: rect.midX, y: rect.midY)
            guard let display = content.displays.first(where: { $0.frame.contains(center) }) ?? content.displays.first else {
                return nil
            }
            let own = content.applications.filter { $0.processID == ownProcessID }
            let filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.sourceRect = CGRect(x: rect.minX - display.frame.minX, y: rect.minY - display.frame.minY, width: rect.width, height: rect.height)
            configuration.width = imageSide
            configuration.height = imageSide
            configuration.showsCursor = false
            configuration.scalesToFit = true
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            return measure(image, rect: rect, keys: keys, radius: radius)
        } catch {
            logFailure(error.localizedDescription)
            return nil
        }
    }

    /// 撮った画像を RGBA に描き直し、鍵の位置の明るさを測る（画像の座標に縮める）
    static func measure(_ image: CGImage, rect: CGRect, keys: [CGPoint], radius: CGFloat) -> [Double]? {
        let side = imageSide
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }
        // 描き直した画像のメモリは上の行から並ぶ（CGContext の描画の座標は左下が原点だが、画像は上下そのまま）ので、鍵の位置は縮めるだけ
        let scale = CGFloat(side) / rect.width
        let points = keys.map { CGPoint(x: $0.x * scale, y: $0.y * scale) }
        let backdrop = HUDBackdropLuminance.Image(width: side, height: side, bytesPerRow: side * 4, pixels: pixels)
        return HUDBackdropLuminance.averages(in: backdrop, around: points, radius: radius * scale)
    }

    nonisolated(unsafe) private static var lastFailure: String?

    private static func logFailure(_ message: String) {
        guard lastFailure != message else { return }
        lastFailure = message
        samplerLogger.error("HUD の下の画面を撮れないので、色を下地に合わせない: \(message, privacy: .public)")
    }
}
