#if DEBUG
// 販売ページ・ポートフォリオ用のデモ動画を撮るための組み立て（DEBUG ビルドだけ。--demo。一覧は App/DebugPreview.swift）。
// 操作のロジック（EdgeSlideRecognizer・SessionEngine）・NonetController・HUD は本物。差し替えるのは次のものだけ:
// - 何も実行しない（performer）。実行するはずだった操作の結果は、背景の上の見本の窓で見せる（DemoStage。画面に置く・アプリを開く・キーを送る）
// - ポインタを抑止せず、アクセシビリティの許可も要らない（keyboard・permissions）。置く枠は主の画面で決める（windowPlacer）
// - 前面のアプリを固定する（--demo-app）
// - --demo-script のとき、実機の指の代わりに台本どおりの指の動きを入れる（内蔵の台本。--demo-script-file <JSON> ならその台本）。
//   付けなければ実機の指をそのまま使う
// 画面の隅のトラックパッドの図は、どちらのときも指の位置（TouchFrame）をそのまま示す
// 画面には必ず共通の背景（--demo-backdrop。scripts/make-backdrop.swift の墨の無地とメニューバー）を敷き、実際の画面を写さない
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
    /// 入れる台本。nil なら実機の指をそのまま使う
    private let script: DemoScript?
    /// このファイルができてから台本を始める。nil ならすぐ
    private let startFile: URL?
    private var timer: Timer?
    private var startedAt: TimeInterval = 0
    private var wasTouching = false
    var onFinished: (() -> Void)?
    var onFrame: ((TouchFrame) -> Void)?
    /// 表示中の HUD の枠（円を囲む正方形。主画面の左上が原点）。台本の指の位置をこの枠に写してポインタを動かす
    /// （本物はポインタでマスを選ぶため。写し方は DemoScript.pointer(for:in:)）
    var mapFrame: (() -> CGRect?)?

    var isAvailable: Bool { script != nil || base.isAvailable }

    init(base: any TouchSource, scheduler: any Scheduler, model: DemoTrackpadModel, script: DemoScript?, startFile: URL?) {
        self.base = base
        self.scheduler = scheduler
        self.model = model
        self.script = script
        self.startFile = startFile
        base.onFrame = { [weak self] frame in
            MainActor.assumeIsolated { self?.deliver(frame) }
        }
    }

    func start() throws {
        guard script != nil else {
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
        guard let script else { return }
        let now = scheduler.now
        if startedAt == .infinity {
            guard let startFile, FileManager.default.fileExists(atPath: startFile.path) else { return }
            startedAt = now
            DemoLog.write("demo: started")
        }
        let time = now - startedAt
        guard time >= 0 else { return }
        if let point = script.sample(at: time) {
            wasTouching = true
            if let map = mapFrame?() {
                CGWarpMouseCursorPosition(DemoScript.pointer(for: point, in: map))
            }
            deliver(TouchFrame(timestamp: now, points: [TouchPoint(id: 1, x: point.x, y: point.y, isTouching: true, majorAxis: 12)]))
        } else if wasTouching {
            wasTouching = false
            deliver(TouchFrame(timestamp: now, points: []))
        }
        // 終わりは、指を離すフレームを送ってから（台本の終わりの時刻まで触れていた指を、触れたままにしない。HUD が開いたまま残る）
        if time >= script.duration {
            timer?.invalidate()
            timer = nil
            onFinished?()
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

/// 何も実行しない。何を実行するところだったかを標準エラーに書き、見本の窓（DemoStage）に結果を見せさせる
@MainActor
final class DemoPerformer: ActionPerforming {
    var onPerform: ((Action) -> Void)?

    func perform(_ action: Action, context: ActionContext) async throws {
        DemoLog.write("demo: perform \(action)")
        onPerform?(action)
    }
}

/// 「画面に置く」の置く枠。本物は前面のアプリの窓がある画面を調べるが、デモの窓は見本なので、主の画面の使える範囲で決める
/// （HUD で光らせている間に出る枠と、離したあと見本の窓が動く先を同じにする）
@MainActor
final class DemoWindowPlacer: WindowPlacing {
    func place(_ region: WindowRegion, app: RunningAppInfo?) async throws {}

    func targetFrame(for region: WindowRegion, app: RunningAppInfo?) -> CGRect? {
        NSScreen.screens.first.map { region.frame(in: $0.visibleFrame) }
    }
}

// MARK: - 見本の窓（操作の結果を見せる）

/// 操作の結果を、背景の上の見本の窓で見せる（2026-11-27 の所有者の決定「ウィンドウ移動などは、ウィンドウが実際に移動するのを見せる」）。
/// 窓は前面のアプリの本物のアイコンと名前だけを持つ無地のもので、アプリの中身（UI）は描かない。
/// - 画面に置く: 前面のアプリの窓が、HUD で光らせている間に出ていた枠（DemoWindowPlacer）へ動く
/// - アプリを開く: そのアプリの窓が手前に開く
/// - キーを送る: 送ったキー（⌘R など）の札を、HUD が閉じた場所（画面の真ん中）に出す
/// 段は背景・置く枠と同じ（screenSaver − 1）で、あとから出したものが手前。置く枠は出るたびに手前に来るので、窓より上に見える
@MainActor
final class DemoStage {
    private let screen: NSScreen
    private var front: NSWindow?
    private var windows: [NSWindow] = []
    private var keycap: NSWindow?
    private let keycapModel = DemoKeycapModel()

    init(screen: NSScreen) {
        self.screen = screen
    }

    /// 前面のアプリの窓。仕上げで真ん中を2倍に寄せても、題の帯と四隅が見える大きさ（画面の 40%）にして、画面の真ん中に置く
    func showFrontmost(_ app: AppReference) {
        let size = CGSize(width: (screen.frame.width * 0.40).rounded(), height: (screen.frame.height * 0.40).rounded())
        let frame = CGRect(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2, width: size.width, height: size.height)
        front = open(app, frame: frame, animated: false)
    }

    func perform(_ action: Action) {
        switch action {
        case .placeWindow(let place):
            guard let front, let target = NSScreen.screens.first.map({ place.region.frame(in: $0.visibleFrame) }) else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.35
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                front.animator().setFrame(target, display: true)
            }
        case .launchApp(let launch):
            // 置いた窓の反対側（右寄り）に開く。仕上げで寄せた範囲に収まる大きさ
            let size = CGSize(width: (screen.frame.width * 0.22).rounded(), height: (screen.frame.height * 0.34).rounded())
            let frame = CGRect(x: screen.frame.midX + screen.frame.width * 0.02, y: screen.frame.midY - size.height / 2, width: size.width, height: size.height)
            _ = open(Self.reference(launch.app.bundleID, fallback: launch.app.name), frame: frame, animated: true)
        case .keystroke(let keys):
            showKeycap(keys.displayString)
        default:
            break
        }
    }

    private func open(_ app: AppReference, frame: CGRect, animated: Bool) -> NSWindow {
        let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
        let window = Self.window(frame: frame) { NSHostingView(rootView: DemoAppWindowView(name: app.name, icon: icon)) }
        windows.append(window)
        if animated {
            // 少し小さく薄いところから開く（アプリが開いたと分かるように）
            let start = frame.insetBy(dx: frame.width * 0.06, dy: frame.height * 0.06)
            window.setFrame(start, display: false)
            window.alphaValue = 0
            window.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().setFrame(frame, display: true)
                window.animator().alphaValue = 1
            }
        } else {
            window.orderFrontRegardless()
        }
        return window
    }

    private func showKeycap(_ text: String) {
        let size = CGSize(width: 360, height: 120)
        if keycap == nil {
            let frame = CGRect(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2, width: size.width, height: size.height)
            keycap = Self.window(frame: frame) { NSHostingView(rootView: DemoKeycapView(model: keycapModel)) }
        }
        keycap?.orderFrontRegardless()
        keycapModel.show(text)
    }

    private static func window(frame: CGRect, content: () -> NSView) -> NSWindow {
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 1)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.contentView = content()
        return window
    }

    /// アプリの表示名（いまの言語のもの。英語で撮るときは「Mail」）
    static func reference(_ bundleID: String, fallback: String) -> AppReference {
        let name = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
        return AppReference(bundleID: bundleID, name: name ?? fallback)
    }
}

/// 見本の窓: 題の帯（3つの丸・アイコン・名前）と無地の中身。黒い地の上で輪郭が分かるように、細い縁を引く
struct DemoAppWindowView: View {
    var name: String
    var icon: NSImage?

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack(spacing: 8) {
                    ForEach([Color(red: 1, green: 0.37, blue: 0.34), Color(red: 1, green: 0.74, blue: 0.18), Color(red: 0.16, green: 0.78, blue: 0.25)], id: \.self) { color in
                        Circle().fill(color).frame(width: 12, height: 12)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                HStack(spacing: 7) {
                    if let icon {
                        Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                    }
                    Text(verbatim: name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.88))
                }
            }
            .frame(height: 34)
            .background(Color(white: 0.17))
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            Color(white: 0.11)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
    }
}

/// 送ったキーの札。押したように少し沈んでから戻り、1 秒ほど見せて消える
@MainActor
@Observable
final class DemoKeycapModel {
    private(set) var text = ""
    private(set) var isVisible = false
    private(set) var isPressed = false
    private var generation = 0

    func show(_ text: String) {
        generation += 1
        let current = generation
        self.text = text
        isPressed = true
        withAnimation(.easeOut(duration: 0.15)) { isVisible = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            guard let self, self.generation == current else { return }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) { self.isPressed = false }
        }
        // 次の場面で HUD が開く（離してから 1.4 秒ほど）前に消す。重なると、次の HUD の上に前のキーが残って見える
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) { [weak self] in
            guard let self, self.generation == current else { return }
            withAnimation(.easeIn(duration: 0.25)) { self.isVisible = false }
        }
    }
}

struct DemoKeycapView: View {
    var model: DemoKeycapModel

    var body: some View {
        Text(verbatim: model.text)
            .font(.system(size: 44, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 30)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(white: 0.22)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.28), lineWidth: 1.5))
            .scaleEffect(model.isPressed ? 0.9 : 1)
            .opacity(model.isVisible ? 1 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    private var stage: DemoStage?
    private let performer = DemoPerformer()

    init(options: ShellLaunchOptions) {
        self.options = options
    }

    func services(from live: NonetServices) -> NonetServices {
        var services = live
        var script: DemoScript?
        if options.demoScript {
            // 読めない・検査に落ちた台本では、始めずに終える（背景が無いときと同じ）。内蔵の台本に替えて流すと、頼んだものと違う場面を撮ったことに気づけない
            guard let loaded = Self.script(options.demoScriptFile) else {
                exit(2)
            }
            script = loaded
        }
        let source = DemoTouchSource(
            base: live.touchSource,
            scheduler: live.scheduler,
            model: model,
            script: script,
            startFile: options.demoStartFile
        )
        source.onFinished = { [weak self] in self?.finish() }
        source.mapFrame = { [weak self] in self?.mapFrame?() }
        services.touchSource = source
        services.keyboard = DemoKeyboardMonitor()
        performer.onPerform = { [weak self] action in self?.stage?.perform(action) }
        services.performer = performer
        services.windowPlacer = DemoWindowPlacer()
        services.permissions = DemoPermissions()
        services.frontmostApp = DemoFrontmostApp(app: frontmostApp)
        return services
    }

    private var frontmostApp: AppReference {
        DemoStage.reference(options.demoBundleID ?? "com.apple.dt.Xcode", fallback: options.demoBundleID ?? "Xcode")
    }

    /// 背景と図を出し、撮る範囲を標準出力に書く（screencapture -R の x,y,幅,高さ。左上が原点）。
    /// 背景（--demo-backdrop）は必ず敷く。敷かずに撮ると、ユーザーの画面（壁紙・ほかのウインドウ）が写る。
    /// 背景はどのデモ動画も scripts/make-backdrop.swift の同じもの（墨の無地とメニューバー）にそろえる
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
        // 背景の手前に、前面のアプリの見本の窓（操作の結果をここで見せる）
        let stage = DemoStage(screen: screen)
        stage.showFrontmost(frontmostApp)
        self.stage = stage
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

    /// 入れる台本。--demo-script-file が無ければ内蔵のもの。ファイルを読めない・検査に落ちたときは、理由を書いて nil
    private static func script(_ url: URL?) -> DemoScript? {
        guard let url else { return .builtIn }
        do {
            return try DemoScript(contentsOf: url)
        } catch {
            DemoLog.write("demo: error: 台本を読めません: \(url.path): \(error)")
            return nil
        }
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

}
#endif
