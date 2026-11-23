#if DEBUG
// 販売ページ・ポートフォリオ用のデモ動画を撮るための組み立て（DEBUG ビルドだけ。--demo。一覧は App/DebugPreview.swift）。
// 操作のロジック（SessionEngine）・NonetController・HUD は本物。差し替えるのは次のものだけ:
// - 何も実行しない（performer）。ポインタを抑止せず、アクセシビリティの許可も要らない（keyboard・permissions）
// - 前面のアプリを固定する（--demo-app）
// - --demo-script のとき、実機の指の代わりに台本どおりの指の動きを入れ、台本の時刻に強く押し込んだことにする。
//   付けなければ実機の指をそのまま使う（ポインタを抑止しないのでクリックを預からず、強く押し込んでも開かない。台本で撮る）
// 画面の隅のトラックパッドの図は、どちらのときも指の位置（TouchFrame）をそのまま示す
// 画面には必ず共通の背景（--demo-backdrop。scripts/make-backdrop.swift の暗いグラデーションとメニューバー）を敷き、実際の画面を写さない
import AppKit
import NonetCore
import NonetUI
import SwiftUI

// MARK: - 差し替えるサービス

/// 標準エラーに1行ずつ書く（標準出力はファイルにつなぐと、終わるまで溜まって、録画を始める目印にならない）
enum DemoLog {
    static func write(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
}

@MainActor
final class DemoTouchSource: TouchSource {
    /// 台本の最初の時刻までの、最初の画面（背景と図だけ）を見せる秒数（開始のファイルを待つときは 0）
    static let leadIn: TimeInterval = 1.0

    private let base: any TouchSource
    private let scheduler: any Scheduler
    private let model: DemoTrackpadModel
    private let scripted: Bool
    /// このファイルができてから台本を始める。nil ならすぐ
    private let startFile: URL?
    private var timer: Timer?
    private var startedAt: TimeInterval = 0
    private var wasTouching = false
    var onFinished: (() -> Void)?
    var onFrame: ((TouchFrame) -> Void)?
    /// 台本の押し込みの時刻（DemoScript.forcePresses）が来た
    var onForcePress: (() -> Void)?
    /// 前の step の台本の時刻（その間に来た押し込みを知らせる）
    private var lastTime: TimeInterval = -1
    /// 表示中の HUD の枠（円を囲む正方形。主画面の左上が原点）。台本の指の位置をこの枠に写してポインタを動かす（本物はポインタでマスを選ぶため）
    var mapFrame: (() -> CGRect?)?
    /// 台本の指の位置（トラックパッドの 0〜1）を枠に写すときの倍率。指がトラックパッドの端まで行けば、ポインタが円の外（外枠）に出るように
    static let pointerTravel: CGFloat = 1.3

    var isAvailable: Bool { scripted || base.isAvailable }

    init(base: any TouchSource, scheduler: any Scheduler, model: DemoTrackpadModel, scripted: Bool, startFile: URL?) {
        self.base = base
        self.scheduler = scheduler
        self.model = model
        self.scripted = scripted
        self.startFile = startFile
        base.onFrame = { [weak self] frame in
            MainActor.assumeIsolated { self?.deliver(frame) }
        }
    }

    func start() throws {
        guard scripted else {
            try base.start()
            return
        }
        // 開始のファイルを待つ間は、台本の時刻を進めない（録画が始まったあとで動かす）
        startedAt = startFile == nil ? scheduler.now + Self.leadIn : .infinity
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        base.stop()
    }

    /// 台本の指を、いまの時刻の分だけ進める（実機のフレームと同じく、触れている間だけ指を入れ、離れたら空のフレームを1回送る）
    private func step() {
        let now = scheduler.now
        if startedAt == .infinity {
            guard let startFile, FileManager.default.fileExists(atPath: startFile.path) else { return }
            startedAt = now
            DemoLog.write("demo: started")
        }
        let time = now - startedAt
        guard time >= 0 else { return }
        if time >= DemoScript.duration {
            timer?.invalidate()
            timer = nil
            onFinished?()
            return
        }
        defer { lastTime = time }
        if let point = DemoScript.sample(at: time) {
            wasTouching = true
            if let map = mapFrame?() {
                // トラックパッドの真ん中が円の中心。そこからの動きを倍率で広げる
                CGWarpMouseCursorPosition(CGPoint(
                    x: map.midX + (point.x - 0.5) * map.width * Self.pointerTravel,
                    y: map.midY + (0.5 - point.y) * map.height * Self.pointerTravel
                ))
            }
            deliver(TouchFrame(timestamp: now, points: [TouchPoint(id: 1, x: point.x, y: point.y, isTouching: true, majorAxis: 12)]))
        } else if wasTouching {
            wasTouching = false
            deliver(TouchFrame(timestamp: now, points: []))
        }
        for press in DemoScript.forcePresses where press > lastTime && press <= time {
            onForcePress?()
        }
    }

    private func deliver(_ frame: TouchFrame) {
        model.update(frame)
        onFrame?(frame)
    }
}

/// ポインタを抑止せず、キーも見ない（デモの間、Mac のポインタとキーボードはそのまま使える）。
/// ポインタの位置は本物を知らせる（DemoTouchSource が台本の指の位置へポインタを動かすので、本物と同じくポインタでマスを選ぶ）。
/// 開いている間に動かしたポインタは、閉じたら元の位置に戻す
@MainActor
final class DemoKeyboardMonitor: KeyboardMonitor {
    var cursorLock: CursorLockMethod = .none
    var isSuppressingPointer = false {
        didSet {
            guard isSuppressingPointer != oldValue else { return }
            if isSuppressingPointer {
                movedFrom = pointerLocation
            } else if let movedFrom {
                CGWarpMouseCursorPosition(movedFrom)
                self.movedFrom = nil
            }
        }
    }
    var onEvent: ((KeyboardEvent) -> Void)?
    var isRunning = false
    private var movedFrom: CGPoint?

    var pointerLocation: CGPoint? { CGEvent(source: nil)?.location }

    func start() throws { isRunning = true }
    func stop() { isRunning = false }

    func movePointer(to point: CGPoint) {
        guard isSuppressingPointer else { return }
        CGWarpMouseCursorPosition(point)
    }
}

/// 何も実行しない。何を実行するところだったかだけを標準出力に書く
@MainActor
final class DemoPerformer: ActionPerforming {
    func perform(_ action: Action, context: ActionContext) async throws {
        DemoLog.write("demo: perform \(action)")
    }
}

@MainActor
final class DemoPermissions: PermissionsProviding {
    var isAccessibilityGranted: Bool { true }
    var isSecureInputActive: Bool { false }
    func requestAccessibility() {}
    func openAccessibilitySettings() {}
}

/// 前面のアプリをいつも同じアプリにする
@MainActor
final class DemoFrontmostApp: FrontmostAppObserving {
    let current: RunningAppInfo?
    var onChange: ((RunningAppInfo?) -> Void)?

    init(app: AppReference) {
        current = RunningAppInfo(app: app, processID: ProcessInfo.processInfo.processIdentifier)
    }

    func start() {}
    func stop() {}
}

// MARK: - トラックパッドの図

/// 指の位置。座標は TouchPoint と同じ（x は左が 0、y は手前が 0）
@MainActor
@Observable
final class DemoTrackpadModel {
    struct Mark: Identifiable {
        var id: Int
        var point: CGPoint
        var time: TimeInterval
    }

    /// 触れている指と、その少し前までの軌跡（古いものほど薄く描く）
    private(set) var fingers: [CGPoint] = []
    private(set) var trail: [Mark] = []
    private var counter = 0
    static let trailDuration: TimeInterval = 0.45

    func update(_ frame: TouchFrame) {
        let touching = frame.touching
        fingers = touching.map { CGPoint(x: $0.x, y: $0.y) }
        guard let first = touching.first else {
            trail = []
            return
        }
        counter += 1
        trail.append(Mark(id: counter, point: CGPoint(x: first.x, y: first.y), time: frame.timestamp))
        trail.removeAll { frame.timestamp - $0.time > Self.trailDuration }
    }
}

struct DemoTrackpadView: View {
    var model: DemoTrackpadModel

    private let accent = Color(red: 0x30 / 255, green: 0xD1 / 255, blue: 0x58 / 255)

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            // マスはポインタで選ぶので、トラックパッドには何も描かない（上の縁の帯だけ: 開く場所）
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color.white.opacity(0.07))
                RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.white.opacity(0.22), lineWidth: 1.5)
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: size.width, height: size.height * 0.09)
                ForEach(model.trail) { mark in
                    let age = (model.trail.last?.time ?? mark.time) - mark.time
                    let strength = max(0, 1 - age / DemoTrackpadModel.trailDuration)
                    Circle()
                        .fill(Color.white.opacity(0.35 * strength))
                        .frame(width: 22 * (0.5 + 0.5 * strength), height: 22 * (0.5 + 0.5 * strength))
                        .position(position(mark.point, in: size))
                }
                ForEach(Array(model.fingers.enumerated()), id: \.offset) { _, finger in
                    Circle()
                        .fill(Color.white)
                        .frame(width: 30, height: 30)
                        .overlay(Circle().strokeBorder(accent, lineWidth: 4))
                        .shadow(color: accent.opacity(0.6), radius: 10)
                        .position(position(finger, in: size))
                }
            }
        }
    }

    private func position(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: point.x * size.width, y: (1 - point.y) * size.height)
    }
}

// MARK: - 画面

/// --demo の画面まわり。背景・図のウィンドウと、サービスの差し替え
@MainActor
final class DemoSession {
    /// 撮る範囲の縦横比（AstLog の画像と同じ 16:10）。画面の上の端から、幅いっぱいに撮る
    static let aspect: CGFloat = 1.6
    static let padSize = CGSize(width: 380, height: 253)

    let model = DemoTrackpadModel()
    /// 表示中の HUD の地図の枠（AppDelegate が HUDWindowController.mapFrame につなぐ）
    var mapFrame: (() -> CGRect?)?
    private let options: ShellLaunchOptions
    private var backdrop: NSWindow?
    private var overlay: NSWindow?

    init(options: ShellLaunchOptions) {
        self.options = options
    }

    func services(from live: NonetServices) -> NonetServices {
        var services = live
        let source = DemoTouchSource(
            base: live.touchSource,
            scheduler: live.scheduler,
            model: model,
            scripted: options.demoScript,
            startFile: options.demoStartFile
        )
        source.onFinished = { [weak self] in self?.finish() }
        source.mapFrame = { [weak self] in self?.mapFrame?() }
        services.touchSource = source
        let keyboard = DemoKeyboardMonitor()
        // 台本の押し込み: 本物のモニターが強く押し込んで止めたクリックを見つけたときと同じく知らせる
        source.onForcePress = { [weak keyboard] in keyboard?.onEvent?(.forcePressed) }
        services.keyboard = keyboard
        services.performer = DemoPerformer()
        services.permissions = DemoPermissions()
        services.frontmostApp = DemoFrontmostApp(app: app(for: options.demoBundleID ?? "com.apple.dt.Xcode"))
        return services
    }

    /// 背景と図を出し、撮る範囲を標準出力に書く（screencapture -R の x,y,幅,高さ。左上が原点）。
    /// 背景（--demo-backdrop）は必ず敷く。敷かずに撮ると、ユーザーの画面（壁紙・ほかのウインドウ）が写る。
    /// 背景はどのデモ動画も scripts/make-backdrop.swift の同じもの（暗いグラデーションとメニューバー）にそろえる
    func present() {
        // 主の画面（メニューバーのある画面。左上が撮る範囲の原点）に敷く。scripts/record-screen.swift も主の画面を撮る。
        // NSScreen.main（いま使っている画面）にすると、外付けの画面から始めたときに、背景の無い主の画面を撮ってしまう
        guard let screen = NSScreen.screens.first else { return }
        let region = CGRect(x: 0, y: 0, width: screen.frame.width, height: (screen.frame.width / Self.aspect).rounded())
        guard let image = Self.backdropImage(options.demoBackdrop, fitting: screen.frame.size) else {
            exit(2)
        }
        backdrop = window(frame: screen.frame, level: NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 1)) {
            let view = NSImageView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.image = image
            view.imageScaling = .scaleAxesIndependently
            return view
        }
        // 撮る範囲の右下（下の端から 40pt、右の端から 44pt）
        let origin = NSPoint(
            x: screen.frame.maxX - Self.padSize.width - 44,
            y: screen.frame.maxY - region.height + 40
        )
        overlay = window(frame: NSRect(origin: origin, size: Self.padSize), level: NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)) {
            NSHostingView(rootView: DemoTrackpadView(model: model))
        }
        DemoLog.write("demo: capture-region=\(Int(region.minX)),\(Int(region.minY)),\(Int(region.width)),\(Int(region.height))")
    }

    /// 敷く背景の画像。無い・読めない・画面と縦横比が違う（引き伸ばすとメニューバーの字がゆがむ）ときは、理由を書いて nil
    private static func backdropImage(_ url: URL?, fitting screen: CGSize) -> NSImage? {
        let hint = "scripts/make-backdrop.swift で画面と同じ大きさに作る（swift scripts/make-backdrop.swift backdrop.png）"
        guard let url else {
            DemoLog.write("demo: error: --demo-backdrop <画像> が要ります。\(hint)")
            return nil
        }
        guard let image = NSImage(contentsOf: url), let rep = image.representations.first, rep.pixelsWide > 0, rep.pixelsHigh > 0 else {
            DemoLog.write("demo: error: 背景の画像を読めません: \(url.path)")
            return nil
        }
        let ratio = CGFloat(rep.pixelsWide) / CGFloat(rep.pixelsHigh)
        guard abs(ratio - screen.width / screen.height) < 0.01 else {
            DemoLog.write("demo: error: 背景の縦横比（\(rep.pixelsWide)×\(rep.pixelsHigh)）が画面（\(Int(screen.width))×\(Int(screen.height)) pt）と違います。\(hint)")
            return nil
        }
        return image
    }

    private func window(frame: NSRect, level: NSWindow.Level, content: () -> NSView) -> NSWindow {
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = level
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.contentView = content()
        window.orderFrontRegardless()
        return window
    }

    /// 台本が終わった。開始のファイルがあるときは、呼ぶ側が録画を止めてそのファイルを消すまで、背景を出したままにする
    /// （背景が消えると、録画にユーザーの画面が写る）。ファイルを使わないときは、少し見せてから終える
    private func finish() {
        DemoLog.write("demo: finished")
        guard let file = options.demoStartFile else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { NSApplication.shared.terminate(nil) }
            return
        }
        let deadline = Date().addingTimeInterval(60)
        let timer = Timer(timeInterval: 0.1, repeats: true) { timer in
            MainActor.assumeIsolated {
                guard !FileManager.default.fileExists(atPath: file.path) || Date() > deadline else { return }
                timer.invalidate()
                NSApplication.shared.terminate(nil)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    private func app(for bundleID: String) -> AppReference {
        let name = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
        return AppReference(bundleID: bundleID, name: name ?? bundleID)
    }
}
#endif
