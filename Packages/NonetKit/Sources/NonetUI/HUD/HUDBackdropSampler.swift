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

/// ScreenCaptureKit で撮る。Nonet 自身のウィンドウ（HUD・置く枠のプレビュー）は撮らない。
/// 撮る前準備（ディスプレイの一覧と自分のアプリ。SCShareableContent は画面上の全ウインドウを列挙する重い呼び出し）は
/// 1 回取って使い回し、古くなったら撮り終えた後に裏で取り直す。開いた瞬間にかかるのは撮影だけにして、色が切り替わるまでを短くする
@MainActor
final class ScreenCaptureBackdropSampler: HUDBackdropSampling {
    /// 撮る画像の一辺（ピクセル）。明るさの平均を取るだけなので小さくてよい（撮る時間も短い）
    static let imageSide = 48
    /// 前準備をこの秒数より古くなってから使ったら、撮り終えた後に取り直す（ウインドウの出入りには付いていかなくてよい。除くのは自分だけ）
    static let shareableContentMaxAge: TimeInterval = 10

    /// 直近の撮影の結果。設定画面が「許可は開き直すと効く」を出す手がかり（許可があるのに撮れない）
    enum Outcome: Equatable {
        case notTried
        case succeeded
        case failed
    }

    nonisolated(unsafe) private(set) static var lastOutcome = Outcome.notTried

    var isAvailable: Bool { CGPreflightScreenCaptureAccess() }

    private var shareableContent: SCShareableContent?
    private var shareableContentDate = Date.distantPast
    private var refreshTask: Task<Void, Never>?
    private var screenObserver: (any NSObjectProtocol)?

    init() {
        // 画面の構成が変わったら、ディスプレイの一覧を取り直す
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.dropShareableContent() }
        }
    }

    deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    func sample(_ rect: CGRect, keys: [CGPoint], radius: CGFloat, completion: @escaping @MainActor ([Double]?) -> Void) {
        guard rect.width > 0, rect.height > 0 else {
            completion(nil)
            return
        }
        let processID = ProcessInfo.processInfo.processIdentifier
        Task { @MainActor in
            let result = await capture(rect, keys: keys, radius: radius, ownProcessID: processID)
            completion(result)
            refreshShareableContentIfStale()
        }
    }

    /// 撮って測る。失敗したら nil（ログに理由を書く。開くたびに書かないよう、同じ理由は1回だけ）
    private func capture(_ rect: CGRect, keys: [CGPoint], radius: CGFloat, ownProcessID: Int32) async -> [Double]? {
        do {
            let content = try await shareableContent(includingProcess: ownProcessID)
            let center = CGPoint(x: rect.midX, y: rect.midY)
            guard let display = content.displays.first(where: { $0.frame.contains(center) }) ?? content.displays.first else {
                return nil
            }
            let own = content.applications.filter { $0.processID == ownProcessID }
            let filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.sourceRect = CGRect(x: rect.minX - display.frame.minX, y: rect.minY - display.frame.minY, width: rect.width, height: rect.height)
            configuration.width = Self.imageSide
            configuration.height = Self.imageSide
            configuration.showsCursor = false
            configuration.scalesToFit = true
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            Self.lastOutcome = .succeeded
            return Self.measure(image, rect: rect, keys: keys, radius: radius)
        } catch {
            Self.lastOutcome = .failed
            // 古いディスプレイの一覧のせいかもしれないので、次は取り直す
            dropShareableContent()
            logFailure(error.localizedDescription)
            return nil
        }
    }

    /// 前準備。無ければ取る。自分のアプリが入っていなければ（HUD を出す前に取ったもの）取り直す（自分のウィンドウを撮らないため）
    private func shareableContent(includingProcess processID: Int32) async throws -> SCShareableContent {
        if let cached = shareableContent, cached.applications.contains(where: { $0.processID == processID }) {
            return cached
        }
        let content = try await Self.fetchShareableContent()
        shareableContent = content
        shareableContentDate = Date()
        return content
    }

    /// 前準備が古ければ、裏で取り直しておく（次に開いたときに待たないため）
    private func refreshShareableContentIfStale() {
        guard refreshTask == nil, Date().timeIntervalSince(shareableContentDate) > Self.shareableContentMaxAge else { return }
        refreshTask = Task { @MainActor [weak self] in
            defer { self?.refreshTask = nil }
            guard let content = try? await Self.fetchShareableContent() else { return }
            self?.shareableContent = content
            self?.shareableContentDate = Date()
        }
    }

    private func dropShareableContent() {
        shareableContent = nil
        shareableContentDate = .distantPast
    }

    private static func fetchShareableContent() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
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

    private func logFailure(_ message: String) {
        guard Self.lastFailure != message else { return }
        Self.lastFailure = message
        samplerLogger.error("HUD の下の画面を撮れないので、色を下地に合わせない: \(message, privacy: .public)")
    }
}
