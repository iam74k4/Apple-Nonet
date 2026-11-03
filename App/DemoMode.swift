#if DEBUG
// 販売ページ・ポートフォリオ用のデモ動画を撮るための組み立て（DEBUG ビルドだけ。--demo。一覧は App/DebugPreview.swift）。
// 操作のロジック（EdgeSlideRecognizer・SessionEngine）・NonetController・HUD は本物。差し替えるのは次のものだけ:
// - 何も実行しない（performer）。ポインタを抑止せず、アクセシビリティの許可も要らない（keyboard・permissions）
// - 前面のアプリを固定する（--demo-app）
// - --demo-script のとき、実機の指の代わりに台本どおりの指の動きを入れる。付けなければ実機の指をそのまま使う
// 画面の隅のトラックパッドの図は、どちらのときも指の位置（TouchFrame）をそのまま示す
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
    /// 表示中の HUD の地図の枠（主画面の左上が原点）。台本の指の位置をこの枠に写してポインタを動かす（本物はポインタでマスを選ぶため）
    var mapFrame: (() -> CGRect?)?

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
        if let point = DemoScript.sample(at: time) {
            wasTouching = true
            if let map = mapFrame?() {
                CGWarpMouseCursorPosition(CGPoint(x: map.minX + point.x * map.width, y: map.minY + (1 - point.y) * map.height))
            }
            deliver(TouchFrame(timestamp: now, points: [TouchPoint(id: 1, x: point.x, y: point.y, isTouching: true, majorAxis: 12)]))
        } else if wasTouching {
            wasTouching = false
            deliver(TouchFrame(timestamp: now, points: []))
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
            let frame = GridInsets.cancelFrame
            let grid = CGRect(
                x: frame.left * size.width,
                y: frame.top * size.height,
                width: (1 - frame.left - frame.right) * size.width,
                height: (1 - frame.top - frame.bottom) * size.height
            )
            let gap: CGFloat = 5
            let cellWidth = (grid.width - 2 * gap) / 3
            let cellHeight = (grid.height - 2 * gap) / 3
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color.white.opacity(0.07))
                RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.white.opacity(0.22), lineWidth: 1.5)
                ForEach(0..<9, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: cellWidth, height: cellHeight)
                        .offset(
                            x: grid.minX + CGFloat(index % 3) * (cellWidth + gap),
                            y: grid.minY + CGFloat(index / 3) * (cellHeight + gap)
                        )
                }
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
        services.keyboard = DemoKeyboardMonitor()
        services.performer = DemoPerformer()
        services.permissions = DemoPermissions()
        services.frontmostApp = DemoFrontmostApp(app: app(for: options.demoBundleID ?? "com.apple.dt.Xcode"))
        return services
    }

    /// 背景と図を出し、撮る範囲を標準出力に書く（screencapture -R の x,y,幅,高さ。左上が原点）
    func present() {
        guard let screen = NSScreen.main else { return }
        let region = CGRect(x: 0, y: 0, width: screen.frame.width, height: (screen.frame.width / Self.aspect).rounded())
        if let url = options.demoBackdrop, let image = NSImage(contentsOf: url) {
            backdrop = window(frame: screen.frame, level: NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 1)) {
                let view = NSImageView(frame: NSRect(origin: .zero, size: screen.frame.size))
                view.image = image
                view.imageScaling = .scaleAxesIndependently
                return view
            }
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
