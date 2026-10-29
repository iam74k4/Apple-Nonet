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
    private var wakeObservation: NotificationObservation?
    private var pendingRestart: DispatchWorkItem?
    private var runningDeviceIDs: [UInt64] = []
    private var planner = MultitouchRestartPlanner()

    /// 抜き差しやスリープ復帰の後、デバイスが使えるようになるまで待つ秒数。指が離れるのを待つ間は、この間隔で確かめ直す
    static let restartDelay: TimeInterval = 1

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
            inputLogger.error("トラックパッドの抜き差しを監視できない（開始時の一覧だけを使う）")
        }
        self.watcher = watcher
        wakeObservation = NotificationObservation(center: NSWorkspace.shared.notificationCenter, name: NSWorkspace.didWakeNotification) { [weak self] _ in
            self?.scheduleRestart(.wake)
        }
        restartDevices(.start, devices: MultitouchLibrary.devices(), liftFirst: false)
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        pendingRestart?.cancel()
        pendingRestart = nil
        watcher?.stop()
        watcher = nil
        wakeObservation = nil
        connection?.stop()
        connection = nil
        runningDeviceIDs = []
        planner.reset()
        inputLogger.info("トラックパッドの読み取りを止めた")
    }

    private func scheduleRestart(_ reason: MultitouchRestartPlanner.Reason) {
        guard isRunning else { return }
        planner.request(reason)
        pendingRestart?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.restartWhenReady() }
        }
        pendingRestart = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.restartDelay, execute: work)
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
            deliver(TouchFrame(timestamp: ProcessInfo.processInfo.systemUptime, points: []), from: nil)
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
    }

    private func drainFrames() {
        guard isRunning, let connection else { return }
        let (frames, device) = connection.pipeline.drain()
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
        self.init(identifier: touch.identifier, state: touch.state, x: touch.normalized.position.x, y: touch.normalized.position.y)
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
    if let touches, count > 0 {
        let buffer = UnsafeBufferPointer(start: touches, count: min(Int(count), MultitouchContact.maxPerFrame))
        points = TouchPoint.points(from: buffer.lazy.map(MultitouchContact.init))
    }
    pipeline.receive(deviceID: deviceID, points: points, timestamp: now)
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
