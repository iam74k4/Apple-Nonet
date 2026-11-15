// 担当: platform-input
// クラス名・public init・protocol への準拠は契約（NonetServices.live() が使う）
import AppKit
import CMultitouch
import IOKit
import NonetCore
import os

/// MultitouchSupport.framework（CMultitouch）から指の位置を受け取る。権限は要らない
@MainActor
public final class MultitouchTouchSource: TouchSource {
    public var onFrame: ((TouchFrame) -> Void)?
    private(set) var isRunning = false

    private var connection: MultitouchConnection?
    private var watcher: MultitouchDeviceWatcher?
    /// スリープ・ユーザーの切り替え・ディスプレイの変化
    private var observations: [NotificationObservation] = []
    /// デバイスの一覧を見直すタイマー
    private var listCheck: Timer?
    private var pendingRestart: DispatchWorkItem?
    private var runningDeviceIDs: [UInt64] = []
    private var planner = MultitouchRestartPlanner()
    private var recovery = MultitouchRecovery()
    /// このユーザーのセッションが前面（画面に出ている）。ユーザーを切り替えて裏に回っている間は、届いた指を渡さない
    /// （見えない9マスを開いて、裏から何かを実行しないため）
    private var isSessionActive = true

    /// 抜き差しやスリープ復帰の後、デバイスが使えるようになるまで待つ秒数。指が離れるのを待つ間は、この間隔で確かめ直す
    nonisolated static let restartDelay: TimeInterval = 1

    public init() {}

    public var isAvailable: Bool {
        if isRunning { return !runningDeviceIDs.isEmpty }
        return !MultitouchDeviceInfo.usable(MultitouchLibrary.devices()).isEmpty
    }

    public func start() throws {
        guard !isRunning else { return }
        try MultitouchLibrary.load()
        isRunning = true
        planner.reset()
        let pipeline = TouchPipeline { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.drainFrames() }
            }
        }
        connection = MultitouchConnection(pipeline: pipeline)

        let watcher = MultitouchDeviceWatcher { [weak self] in
            self?.scheduleRestart(.hotPlug)
        }
        if !watcher.start() {
            inputLogger.error("トラックパッドの抜き差しを監視できない（一覧を定期的に見直すだけにする）")
        }
        self.watcher = watcher
        let workspace = NSWorkspace.shared.notificationCenter
        let restarts: [(NotificationCenter, Notification.Name, MultitouchRestartPlanner.Reason)] = [
            (workspace, NSWorkspace.didWakeNotification, .wake),
            (workspace, NSWorkspace.sessionDidBecomeActiveNotification, .sessionActive),
            (workspace, NSWorkspace.screensDidWakeNotification, .display),
            (NotificationCenter.default, NSApplication.didChangeScreenParametersNotification, .display),
        ]
        observations = restarts.map { center, name, reason in
            NotificationObservation(center: center, name: name) { [weak self] _ in
                if reason == .sessionActive { self?.isSessionActive = true }
                self?.scheduleRestart(reason)
            }
        }
        // ユーザーを切り替えて裏に回った: 開いていれば何もせずに閉じ（指が離れたことにする）、前面に戻るまで指を渡さない
        isSessionActive = MultitouchSession.isOnConsole()
        observations.append(NotificationObservation(center: workspace, name: NSWorkspace.sessionDidResignActiveNotification) { [weak self] _ in
            self?.sessionDidResign()
        })
        // 通知を取りこぼしても追いつけるよう、一覧をときどき見直す（間隔は長く、時刻はゆるくして電力を使わない）
        let timer = Timer(timeInterval: MultitouchRecovery.listCheckInterval, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else {
                    timer.invalidate()
                    return
                }
                self.checkDeviceList()
            }
        }
        timer.tolerance = MultitouchRecovery.listCheckInterval / 2
        RunLoop.main.add(timer, forMode: .common)
        listCheck = timer
        restartDevices(.start, devices: MultitouchLibrary.devices(), liftFirst: false)
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        pendingRestart?.cancel()
        pendingRestart = nil
        watcher?.stop()
        watcher = nil
        observations = []
        listCheck?.invalidate()
        listCheck = nil
        connection?.stop()
        connection = nil
        runningDeviceIDs = []
        planner.reset()
        recovery.reset()
        inputLogger.info("トラックパッドの読み取りを止めた")
    }

    /// 一覧が開始しようとしたデバイスと違えば（抜き差しの通知を取りこぼした）開始し直す
    private func checkDeviceList() {
        guard isRunning, pendingRestart == nil else { return }
        let listed = MultitouchDeviceInfo.usable(MultitouchLibrary.devices()).map(\.id)
        guard recovery.needsRestart(listed: listed) else { return }
        scheduleRestart(.deviceListChanged)
    }

    private func scheduleRestart(_ reason: MultitouchRestartPlanner.Reason, after delay: TimeInterval = MultitouchTouchSource.restartDelay) {
        guard isRunning else { return }
        planner.request(reason)
        pendingRestart?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.restartWhenReady() }
        }
        pendingRestart = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func restartWhenReady() {
        guard isRunning else { return }
        pendingRestart = nil
        let reason = planner.pendingReason ?? .hotPlug
        let devices = MultitouchLibrary.devices()
        switch planner.decide(connectedDevices: Set(devices.map(\.id)), now: ProcessInfo.processInfo.systemUptime) {
        case .waitForLift:
            inputLogger.debug("指が触れているので、トラックパッドの開始し直しを待つ")
            scheduleRestart(reason)
        case .restart(let liftFirst):
            restartDevices(reason, devices: devices, liftFirst: liftFirst)
        }
    }

    /// デバイスの一覧を作り直して開始し直す
    private func restartDevices(_ reason: MultitouchRestartPlanner.Reason, devices: [MultitouchDeviceInfo], liftFirst: Bool) {
        guard isRunning, let connection else { return }
        connection.stop()
        connection.pipeline.reset()
        // 触れていた指のフレームはもう来ないので、離れたことにする（エンジンが指を置いたままだと思い込まないように）
        if liftFirst {
            deliver(TouchFrame(timestamp: ProcessInfo.processInfo.systemUptime, points: [], isSynthesizedLift: true), from: nil)
            guard isRunning else { return }
        }
        let usable = MultitouchDeviceInfo.usable(devices)
        let started = connection.start(deviceIDs: usable.map(\.id))
        if reason == .start || started != runningDeviceIDs {
            let summary = usable.map { "\($0.isBuiltIn ? "内蔵" : "外付け") family=\($0.familyID)" }.joined(separator: ", ")
            inputLogger.info("トラックパッド（\(reason.logName, privacy: .public)）: \(started.count) 台を開始 [\(summary, privacy: .public)]")
        }
        runningDeviceIDs = started
        // 抜かれたデバイスで触覚を鳴らそうとしないように
        if let last = MultitouchActivity.lastTouchedDeviceID, !started.contains(last) {
            MultitouchActivity.lastTouchedDeviceID = nil
        }
        // 起動の途中などで開始できなかったデバイスは、間を置いて開始し直す
        if let retry = recovery.restarted(attempted: usable.map(\.id), started: started, at: ProcessInfo.processInfo.systemUptime) {
            if recovery.failures == 1 {
                inputLogger.notice("トラックパッド \(usable.count) 台のうち \(started.count) 台しか開始できないので、開始し直す")
            }
            scheduleRestart(.retry, after: retry)
        }
    }

    private func sessionDidResign() {
        guard isRunning, isSessionActive else { return }
        isSessionActive = false
        inputLogger.info("ユーザーが切り替わったので、前面に戻るまで指を受け取らない")
        deliver(TouchFrame(timestamp: ProcessInfo.processInfo.systemUptime, points: [], isSynthesizedLift: true), from: nil)
    }

    private func drainFrames() {
        guard isRunning, let connection else { return }
        let (frames, device) = connection.pipeline.drain()
        // 裏に回っている間に届いた指は捨てる（ためておくと、前面に戻ったときに古い指が届く）
        guard isSessionActive else { return }
        if let device { MultitouchActivity.lastTouchedDeviceID = device }
        for frame in frames {
            guard isRunning else { return }
            deliver(frame, from: device)
        }
    }

    private func deliver(_ frame: TouchFrame, from device: UInt64?) {
        planner.delivered(frame, from: device)
        onFrame?(frame)
    }
}

/// このプロセスのユーザーのセッションが、画面に出ている（ユーザーの切り替えで裏に回っていない）か
enum MultitouchSession {
    /// 分からなければ（辞書が無い・キーが無い）前面とみなす（指を受け取らなくなるより安全）
    static func isOnConsole() -> Bool {
        guard let info = CGSessionCopyCurrentDictionary() as? [String: Any],
              let onConsole = info[kCGSessionOnConsoleKey as String] as? Bool else { return true }
        return onConsole
    }
}

/// 自己チェック（--self-check）用: MultitouchSupport を、アプリが使うのと同じ読み込みで読めるか
public enum MultitouchLoadCheck {
    /// 読めなければ理由（使う関数のどれかが無い など）。読めれば nil
    @MainActor
    public static func loadError() -> String? {
        MultitouchLibrary.loadError()
    }
}

/// 最後に指が触れたトラックパッド。触覚をそのデバイスで鳴らすために使う
@MainActor
enum MultitouchActivity {
    static var lastTouchedDeviceID: UInt64?
}

// MARK: - CMultitouch

/// CMultitouch の Swift 側
enum MultitouchLibrary {
    private static let loadFailureLogged = OSAllocatedUnfairLock(initialState: false)

    /// 読み込めなければ NonetError.unavailable
    static func load() throws {
        var buffer = [CChar](repeating: 0, count: 256)
        if cmt_load(&buffer, Int32(buffer.count)) { return }
        let reason = buffer.withUnsafeBufferPointer { $0.baseAddress.map { String(cString: $0) } } ?? ""
        let firstFailure = loadFailureLogged.withLock { logged in
            defer { logged = true }
            return !logged
        }
        if firstFailure {
            inputLogger.error("MultitouchSupport を読み込めない: \(reason, privacy: .public)")
        }
        throw NonetError.unavailable(InputText.multitouchUnavailable)
    }

    /// アプリと同じ読み込み（cmt_load: 使う関数がすべてそろっているかまで見る）で読めなければ、その理由。読めれば nil
    static func loadError() -> String? {
        var buffer = [CChar](repeating: 0, count: 256)
        if cmt_load(&buffer, Int32(buffer.count)) { return nil }
        let reason = buffer.withUnsafeBufferPointer { $0.baseAddress.map { String(cString: $0) } } ?? ""
        return reason.isEmpty ? "cmt_load failed" : reason
    }

    /// いまつながっているデバイス。読み込めなければ空
    static func devices() -> [MultitouchDeviceInfo] {
        guard (try? load()) != nil else { return [] }
        var capacity = 8
        // 調べている間に増えたら、大きい入れ物で数え直す
        for _ in 0..<3 {
            var buffer = [CMTDeviceInfo](repeating: CMTDeviceInfo(), count: capacity)
            let count = Int(cmt_list_devices(&buffer, Int32(capacity)))
            guard count >= 0 else { return [] }
            if count <= capacity {
                return buffer.prefix(count).map(MultitouchDeviceInfo.init)
            }
            capacity = count
        }
        return []
    }
}

extension MultitouchDeviceInfo {
    init(_ info: CMTDeviceInfo) {
        self.init(id: info.deviceID, familyID: info.familyID, isBuiltIn: info.builtIn, surfaceWidth: info.surfaceWidth, surfaceHeight: info.surfaceHeight)
    }
}

extension MultitouchContact {
    init(_ touch: CMTTouch) {
        self.init(
            identifier: touch.identifier,
            state: touch.state,
            x: touch.normalized.position.x,
            y: touch.normalized.position.y,
            majorAxis: touch.majorAxis
        )
    }

    /// 1フレームの接触点の上限。壊れた count で大きな領域を読まないように
    static let maxPerFrame = 32
}

/// cmt_start に渡す context（TouchPipeline）の持ち主。解放されるときに必ず止める。
/// CMultitouch は1つの接続しか持てないので、同時に使うのは1つだけ
final class MultitouchConnection {
    let pipeline: TouchPipeline
    private var isStarted = false

    init(pipeline: TouchPipeline) {
        self.pipeline = pipeline
    }

    /// deviceIDs のデバイスを開始し、開始できたものの ID を返す
    func start(deviceIDs: [UInt64]) -> [UInt64] {
        stop()
        guard !deviceIDs.isEmpty else { return [] }
        var started = [UInt64](repeating: 0, count: deviceIDs.count)
        // cmt_stop が戻るまで context を使うので、pipeline はこのオブジェクトが持ち続ける
        let context = Unmanaged.passUnretained(pipeline).toOpaque()
        let count = deviceIDs.withUnsafeBufferPointer { ids in
            cmt_start(ids.baseAddress, Int32(ids.count), multitouchFrameHandler, context, &started)
        }
        isStarted = true
        return Array(started.prefix(max(0, Int(count))))
    }

    func stop() {
        guard isStarted else { return }
        cmt_stop()
        isStarted = false
    }

    deinit {
        stop()
    }
}

/// MultitouchSupport のスレッドで呼ばれる
private let multitouchFrameHandler: CMTFrameHandler = { context, deviceID, touches, count, _ in
    guard let context else { return }
    let pipeline = Unmanaged<TouchPipeline>.fromOpaque(context).takeUnretainedValue()
    // 時刻は Scheduler と同じ時計（systemUptime）にそろえる。MultitouchSupport の timestamp の時計は確かめていない
    let now = ProcessInfo.processInfo.systemUptime
    var points: [TouchPoint] = []
    var pointer: CGPoint?
    if let touches, count > 0 {
        let buffer = UnsafeBufferPointer(start: touches, count: min(Int(count), MultitouchContact.maxPerFrame))
        points = TouchPoint.points(from: buffer.lazy.map(MultitouchContact.init))
        // 開いている間はポインタの位置でマスを選ぶ。届けたとき（メインスレッド）に読むと、まとめて届いた古いフレームまで今の位置になる
        pointer = CGEvent(source: nil)?.location
    }
    pipeline.receive(deviceID: deviceID, points: points, timestamp: now, pointer: pointer)
}

// MARK: - 抜き差しの監視

/// AppleMultitouchDevice（内蔵・Magic Trackpad・Magic Mouse）の抜き差しを IOKit の通知で知る
final class MultitouchDeviceWatcher {
    private let onChange: @MainActor () -> Void
    private var port: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []

    /// onChange はメインスレッドで呼ばれる
    init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
    }

    func start() -> Bool {
        guard port == nil else { return true }
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return false }
        IONotificationPortSetDispatchQueue(port, DispatchQueue.main)
        self.port = port
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for type in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            var iterator: io_iterator_t = 0
            let result = IOServiceAddMatchingNotification(port, type, IOServiceMatching("AppleMultitouchDevice"), multitouchDeviceCallback, refcon, &iterator)
            guard result == KERN_SUCCESS else { continue }
            // 読み切らないと次の通知が来ない。今あるデバイスはここで読み飛ばす
            Self.drain(iterator)
            iterators.append(iterator)
        }
        guard !iterators.isEmpty else {
            stop()
            return false
        }
        return true
    }

    func stop() {
        iterators.forEach { IOObjectRelease($0) }
        iterators = []
        if let port { IONotificationPortDestroy(port) }
        port = nil
    }

    deinit {
        stop()
    }

    static func drain(_ iterator: io_iterator_t) {
        var object = IOIteratorNext(iterator)
        while object != 0 {
            IOObjectRelease(object)
            object = IOIteratorNext(iterator)
        }
    }

    fileprivate func notify() {
        MainActor.assumeIsolated { onChange() }
    }
}

/// IONotificationPortSetDispatchQueue でメインキューを指定しているので、メインスレッドで呼ばれる
private func multitouchDeviceCallback(refcon: UnsafeMutableRawPointer?, iterator: io_iterator_t) {
    MultitouchDeviceWatcher.drain(iterator)
    guard let refcon else { return }
    Unmanaged<MultitouchDeviceWatcher>.fromOpaque(refcon).takeUnretainedValue().notify()
}
