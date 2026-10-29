// 担当: platform-input
// クラス名・public init・protocol への準拠は契約（NonetServices.live() が使う）
import AppKit
import ApplicationServices
import NonetCore

/// イベントタップでトリガーキーを検出し、セッション中はポインタ系のイベントを止める
@MainActor
public final class EventTapKeyboardMonitor: KeyboardMonitor {
    public var trigger: TriggerKey = .rightCommand
    public var passTriggerToApps = true
    public var cursorLock: CursorLockMethod = .automatic
    public var isSuppressingPointer = false {
        didSet {
            guard isSuppressingPointer != oldValue else { return }
            isSuppressingPointer ? beginSuppression() : endSuppression()
        }
    }
    public var onEvent: ((KeyboardEvent) -> Void)?

    public var isRunning: Bool { connection != nil }

    /// トリガーを押している間、取りこぼしが無いか物理的な状態を確かめる間隔
    static let watchdogInterval: TimeInterval = 0.3

    private var detector = TriggerDetector()
    private var suppressor = PointerSuppressor()
    /// 抑止を始めたときの方式と、カーソルの位置
    private var activePlan: CursorLockPlan?
    private var anchor: CGPoint?
    private var connection: EventTapConnection?
    private var watchdog: Timer?
    private let cursor: any CursorControlling
    private let association: CursorAssociationGuard
    private let physicalFlags: () -> CGEventFlags
    private let isAccessibilityTrusted: () -> Bool

    public convenience init() {
        self.init(
            cursor: SystemCursorControl(),
            physicalFlags: { CGEventSource.flagsState(.hidSystemState) },
            isAccessibilityTrusted: { AXIsProcessTrusted() }
        )
    }

    init(cursor: any CursorControlling, physicalFlags: @escaping () -> CGEventFlags, isAccessibilityTrusted: @escaping () -> Bool) {
        self.cursor = cursor
        association = CursorAssociationGuard(cursor: cursor)
        self.physicalFlags = physicalFlags
        self.isAccessibilityTrusted = isAccessibilityTrusted
    }

    public func start() throws {
        guard !isRunning else { return }
        guard isAccessibilityTrusted() else {
            throw NonetError.permissionDenied(InputText.accessibility)
        }
        let box = EventTapBox(monitor: self)
        guard let connection = EventTapConnection(box: box) else {
            inputLogger.error("イベントタップを作れない")
            throw NonetError.permissionDenied(InputText.accessibility)
        }
        self.connection = connection
        detector.reset()
        suppressor = PointerSuppressor()
        inputLogger.info("イベントタップを開始（\(connection.levelName, privacy: .public)）")
    }

    public func stop() {
        connection?.invalidate()
        connection = nil
        stopWatchdog()
        detector.reset()
        suppressor = PointerSuppressor()
        isSuppressingPointer = false
        association.restore()
    }

    // MARK: イベント

    /// イベントタップのコールバック（メインスレッド）。false なら前面アプリに渡さない。
    /// すべての入力がここを通るので、ログを書かず、すぐ戻る
    func handle(type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            connection?.enable()
            inputLogger.notice("イベントタップが無効にされたので有効にし直した（\(type.rawValue)）")
            // 無効だった間の離すイベントを取りこぼしたかもしれない
            reconcileTrigger()
            return true
        case .flagsChanged:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            return apply(detector.flagsChanged(keyCode: keyCode, flags: event.flags, trigger: trigger, passTrigger: passTriggerToApps))
        case .keyDown:
            return apply(detector.keyDown())
        default:
            return handlePointer(type: type.rawValue, event: event)
        }
    }

    private func handlePointer(type: UInt32, event: CGEvent) -> Bool {
        guard PointerEventKind.isPointer(type) else { return true }
        var info = PointerEventInfo(type: type)
        if PointerEventKind.needsButtonNumber(type) {
            info.buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
        } else if type == PointerEventKind.scrollWheel {
            info.scrollPhase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
            info.momentumPhase = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
        }
        switch suppressor.decide(info, suppressing: isSuppressingPointer, dropsMoves: activePlan?.dropsMoves ?? false) {
        case .pass:
            return true
        case .passAsMove:
            event.type = .mouseMoved
            return true
        case .drop:
            if activePlan?.warpsBack == true, PointerEventKind.isMove(type) {
                holdCursorAtAnchor()
            }
            return false
        }
    }

    private func apply(_ output: TriggerDetector.Output) -> Bool {
        if let event = output.event { emit(event) }
        return output.pass
    }

    private func emit(_ event: KeyboardEvent) {
        switch event {
        case .triggerDown: startWatchdog()
        case .triggerUp: stopWatchdog()
        case .interrupted: break
        }
        onEvent?(event)
    }

    /// 物理的にはトリガーが離れているのに押したままだと思っていたら、離したことにする
    func reconcileTrigger() {
        if let event = detector.reconcile(physicalFlags: physicalFlags()) {
            inputLogger.notice("トリガーを離すイベントを取りこぼしたので、離したことにした")
            emit(event)
        }
    }

    private func startWatchdog() {
        watchdog?.invalidate()
        let timer = Timer(timeInterval: Self.watchdogInterval, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else {
                    timer.invalidate()
                    return
                }
                self.reconcileTrigger()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }

    private func stopWatchdog() {
        watchdog?.invalidate()
        watchdog = nil
    }

    // MARK: カーソル

    private func beginSuppression() {
        let plan = CursorLockPlan(cursorLock)
        activePlan = plan
        anchor = cursor.location
        if plan.decouples { association.decouple() }
    }

    private func endSuppression() {
        if activePlan?.warpsBack == true { holdCursorAtAnchor() }
        association.restore()
        activePlan = nil
        anchor = nil
    }

    private func holdCursorAtAnchor() {
        guard let anchor, let current = cursor.location, CursorLockPlan.needsWarp(from: anchor, to: current) else { return }
        cursor.warp(to: anchor)
    }
}

// MARK: - カーソルの操作

protocol CursorControlling: AnyObject {
    /// グローバル座標（左上が原点）
    var location: CGPoint? { get }
    func warp(to point: CGPoint)
    func setAssociated(_ associated: Bool)
}

final class SystemCursorControl: CursorControlling {
    var location: CGPoint? { CGEvent(source: nil)?.location }

    func warp(to point: CGPoint) {
        CGWarpMouseCursorPosition(point)
        // ワープの直後はしばらく移動が止まる。結び付け直すと止まらない（automatic でしかワープしないので、切り離しは使っていない）
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    func setAssociated(_ associated: Bool) {
        let result = CGAssociateMouseAndMouseCursorPosition(associated ? 1 : 0)
        if result != .success {
            inputLogger.error("カーソルの結び付けを変えられない（CGError \(result.rawValue)）")
        }
    }
}

/// カーソルの切り離しを必ず元に戻すための持ち主。解放されるときにも戻す
final class CursorAssociationGuard {
    private let cursor: any CursorControlling
    private(set) var isDecoupled = false

    init(cursor: any CursorControlling) {
        self.cursor = cursor
    }

    func decouple() {
        guard !isDecoupled else { return }
        cursor.setAssociated(false)
        isDecoupled = true
    }

    func restore() {
        guard isDecoupled else { return }
        cursor.setAssociated(true)
        isDecoupled = false
    }

    deinit {
        restore()
    }
}

// MARK: - イベントタップ

/// コールバックからモニタを引くための箱。タップが持ち、モニタは弱参照
final class EventTapBox {
    weak var monitor: EventTapKeyboardMonitor?

    init(monitor: EventTapKeyboardMonitor) {
        self.monitor = monitor
    }
}

/// CGEventTap と run loop source の持ち主。解放されるときに必ず外す
final class EventTapConnection {
    private let tap: CFMachPort
    private let source: CFRunLoopSource
    private let box: Unmanaged<EventTapBox>
    private var isValid = true
    let levelName: String

    /// 受け取るイベント。tapDisabled* はマスクに関係なく届く
    static let eventsOfInterest: CGEventMask = {
        let types = PointerEventKind.all.union([CGEventType.keyDown.rawValue, CGEventType.flagsChanged.rawValue])
        return types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1)) }
    }()

    /// HID レベルで作れなければセッションレベルで作る。どちらも作れなければ nil
    init?(box: EventTapBox) {
        let retained = Unmanaged.passRetained(box)
        let levels: [(CGEventTapLocation, String)] = [(.cghidEventTap, "HID"), (.cgSessionEventTap, "セッション")]
        for (location, name) in levels {
            guard let tap = CGEvent.tapCreate(
                tap: location,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: Self.eventsOfInterest,
                callback: eventTapCallback,
                userInfo: retained.toOpaque()
            ) else { continue }
            guard let source = CFMachPortCreateRunLoopSource(nil, tap, 0) else {
                CFMachPortInvalidate(tap)
                continue
            }
            // メニューを開いている間（イベントトラッキング中）も動くように common モードに置く
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            self.tap = tap
            self.source = source
            self.box = retained
            levelName = name
            return
        }
        retained.release()
        return nil
    }

    func enable() {
        guard isValid else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func invalidate() {
        guard isValid else { return }
        isValid = false
        CGEvent.tapEnable(tap: tap, enable: false)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        CFMachPortInvalidate(tap)
        box.release()
    }

    deinit {
        invalidate()
    }
}

/// メインの run loop に置いたタップのコールバックなので、メインスレッドで呼ばれる
private func eventTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let box = Unmanaged<EventTapBox>.fromOpaque(userInfo).takeUnretainedValue()
    let pass = MainActor.assumeIsolated {
        box.monitor?.handle(type: type, event: event) ?? true
    }
    return pass ? Unmanaged.passUnretained(event) : nil
}
