// 担当: platform-input
// クラス名・public init・protocol への準拠は契約（NonetServices.live() が使う）。
// 中身は担当が書き換え、必要ならファイルを分けてよい（Input/ 以下）。
import AppKit
import NonetCore

/// MultitouchSupport.framework（CMultitouch）から指の位置を受け取る
@MainActor
public final class MultitouchTouchSource: TouchSource {
    public var onFrame: ((TouchFrame) -> Void)?

    public init() {}

    public var isAvailable: Bool { false }

    public func start() throws {}

    public func stop() {}
}

/// イベントタップでトリガーキーを検出し、セッション中はポインタ系のイベントを止める
@MainActor
public final class EventTapKeyboardMonitor: KeyboardMonitor {
    public var trigger: TriggerKey = .rightCommand
    public var passTriggerToApps = true
    public var cursorLock: CursorLockMethod = .automatic
    public var isSuppressingPointer = false
    public var onEvent: ((KeyboardEvent) -> Void)?

    public init() {}

    public var isRunning: Bool { false }

    public func start() throws {
        throw NonetError.permissionDenied("アクセシビリティ")
    }

    public func stop() {}
}

/// トラックパッドの触覚。MTActuator（非公開）を優先し、使えなければ NSHapticFeedbackManager
@MainActor
public final class TrackpadHapticPlayer: HapticPlayer {
    public init() {}

    public func play(_ event: HapticEvent, strength: HapticStrength) {}
}

@MainActor
public final class SystemPermissions: PermissionsProviding {
    public init() {}

    public var isAccessibilityGranted: Bool { false }

    public func requestAccessibility() {}

    public func openAccessibilitySettings() {}

    public var isSecureInputActive: Bool { false }
}

@MainActor
public final class WorkspaceFrontmostAppObserver: FrontmostAppObserving {
    public var onChange: ((RunningAppInfo?) -> Void)?

    public init() {}

    public var current: RunningAppInfo? { nil }

    public func start() {}

    public func stop() {}
}

/// メインスレッドで動くタイマー。now は起動からの単調増加の秒
@MainActor
public final class MainRunLoopScheduler: Scheduler {
    public init() {}

    public var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    @discardableResult
    public func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> any ScheduledTask {
        fatalError("未実装: platform-input")
    }
}

public enum KeyboardLayout {
    /// 物理キーボードが JIS 配列か
    public static var isJIS: Bool { false }
}
