// 担当: engine。NonetController のテストで使う偽物のサービス。どれも本物の入出力に触れない
import Foundation
@testable import NonetCore

/// 非同期の処理が進むまで待つ（条件が成り立つか、十分に譲るまで）
@MainActor
func controllerWaitUntil(_ condition: () -> Bool) async {
    for _ in 0..<10_000 {
        if condition() { return }
        await Task.yield()
    }
}

/// 開くまで待たせる（テストで実行を止めておく）
@MainActor
final class ControllerFakeLatch {
    private(set) var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let waiting = waiters
        waiters.removeAll()
        for waiter in waiting {
            waiter.resume()
        }
    }
}

/// 偽物どうしの呼ばれた順番（ポインタの抑止と HUD・実行の前後を確かめる）
@MainActor
final class ControllerFakeRecorder {
    private(set) var events: [String] = []

    func log(_ event: String) {
        events.append(event)
    }

    func clear() {
        events.removeAll()
    }
}

// MARK: - 時間

@MainActor
final class ControllerFakeScheduledTask: ScheduledTask {
    let id: Int
    let delay: TimeInterval
    let fireAt: TimeInterval
    private var action: (@MainActor () -> Void)?

    init(id: Int, delay: TimeInterval, fireAt: TimeInterval, action: @escaping @MainActor () -> Void) {
        self.id = id
        self.delay = delay
        self.fireAt = fireAt
        self.action = action
    }

    var isPending: Bool { action != nil }

    func cancel() {
        action = nil
    }

    func fire() {
        guard let action else { return }
        self.action = nil
        action()
    }
}

/// 手で進める時計。advance で期限が来た予定を時刻順に実行する
@MainActor
final class ControllerFakeScheduler: Scheduler {
    private(set) var now: TimeInterval = 100
    private var tasks: [ControllerFakeScheduledTask] = []
    private var nextID = 0
    /// これまでに頼まれた待ち時間
    private(set) var requestedDelays: [TimeInterval] = []

    @discardableResult
    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> any ScheduledTask {
        let task = ControllerFakeScheduledTask(id: nextID, delay: delay, fireAt: now + max(0, delay), action: action)
        nextID += 1
        tasks.append(task)
        requestedDelays.append(delay)
        return task
    }

    /// time までに期限が来た予定を時刻順に実行しながら、now を time まで進める（実行中に頼まれた予定も含む）
    func advance(to time: TimeInterval) {
        while let next = tasks.filter({ $0.isPending && $0.fireAt <= time }).min(by: { ($0.fireAt, $0.id) < ($1.fireAt, $1.id) }) {
            now = max(now, next.fireAt)
            next.fire()
        }
        now = max(now, time)
        tasks.removeAll { !$0.isPending }
    }

    func advance(by seconds: TimeInterval) {
        advance(to: now + seconds)
    }

    var pending: [ControllerFakeScheduledTask] {
        tasks.filter(\.isPending)
    }

    func hasPending(delay: TimeInterval) -> Bool {
        pending.contains { $0.delay == delay }
    }
}

/// LicenseManager に渡す、進められる時計
final class ControllerFakeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date) {
        current = start
    }

    var now: Date {
        lock.withLock { current }
    }

    func advance(days: Double) {
        lock.withLock { current = current.addingTimeInterval(days * 86_400) }
    }

    var closure: @Sendable () -> Date {
        { [self] in now }
    }
}

final class ControllerFakeLicenseStorage: LicenseStorage {
    var trialStartDate: Date?
    var licenseKey: String?
    var trialLastSeenDate: Date?
    var trialUsedTime: TimeInterval?
    /// 試用を数えて保存先に渡した回数（ライセンスが無いときの license.refresh() のたびに1回。記録そのものは変わったときだけ書く）
    private(set) var trialWrites = 0

    func didSaveTrialProgress() {
        trialWrites += 1
    }
}

// MARK: - 入力

@MainActor
final class ControllerFakeTouchSource: TouchSource {
    var isAvailable = true
    var onFrame: ((TouchFrame) -> Void)?
    /// start() で投げるもの
    var startError: (any Error)?
    private(set) var isRunning = false
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start() throws {
        startCount += 1
        if let startError { throw startError }
        isRunning = true
    }

    func stop() {
        stopCount += 1
        isRunning = false
    }

    /// 本物と同じく、動いている間だけフレームを渡す
    func send(_ frame: TouchFrame) {
        guard isRunning else { return }
        onFrame?(frame)
    }
}

@MainActor
final class ControllerFakeKeyboard: KeyboardMonitor {
    var cursorLock: CursorLockMethod = .none
    /// いまのポインタの位置（主画面の左上が原点）。nil なら、マスはトラックパッドの上の指の位置で選ぶ
    var pointerLocation: CGPoint?
    var isSuppressingPointer = false {
        didSet {
            guard isSuppressingPointer != oldValue else { return }
            suppressionChanges.append(isSuppressingPointer)
            recorder.log(isSuppressingPointer ? "suppress:on" : "suppress:off")
        }
    }
    var onEvent: ((KeyboardEvent) -> Void)?
    /// rememberPointerLocation が呼ばれた回数（本物は、次の抑止の始まりでポインタをそこへ戻す）
    private(set) var rememberedPointerCount = 0
    /// コントローラーが知らせた、トラックパッドに触れているか（知らされた順）
    var isTrackpadTouched = false {
        didSet { trackpadTouchReports.append(isTrackpadTouched) }
    }
    private(set) var trackpadTouchReports: [Bool] = []
    /// マウスやトラックパッドのボタンを物理的に押し込んでいるか（テストで変える）
    var isMouseButtonDown = false
    private(set) var isRunning = false
    /// start() で投げるもの（アクセシビリティの許可が無いときは別に permissionDenied を投げる）
    var startError: (any Error)?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var suppressionChanges: [Bool] = []
    /// send で渡したイベントを処理し終えた直後の isSuppressingPointer
    private(set) var suppressionAfterEvent: [Bool] = []

    private let recorder: ControllerFakeRecorder
    private let permissions: ControllerFakePermissions

    init(recorder: ControllerFakeRecorder, permissions: ControllerFakePermissions) {
        self.recorder = recorder
        self.permissions = permissions
    }

    func start() throws {
        startCount += 1
        guard permissions.isAccessibilityGranted else {
            throw NonetError.permissionDenied("アクセシビリティ")
        }
        if let startError { throw startError }
        isRunning = true
    }

    /// 本物と同じく、止めるとポインタの抑止もやめる
    func stop() {
        stopCount += 1
        isRunning = false
        isSuppressingPointer = false
    }

    /// endPointerSuppression で抑止をやめたときの dropsLateClicks（抑止していなかったときは数えない）
    private(set) var lateClickGraces: [Bool] = []

    func endPointerSuppression(dropsLateClicks: Bool) {
        if isSuppressingPointer {
            lateClickGraces.append(dropsLateClicks)
        }
        isSuppressingPointer = false
    }

    func rememberPointerLocation() {
        rememberedPointerCount += 1
        recorder.log("pointer:remember")
    }

    /// 本物のモニターは動いている間だけイベントを渡す（キーは抑止している間だけ見る）
    func send(_ event: KeyboardEvent) {
        guard isRunning else { return }
        onEvent?(event)
        suppressionAfterEvent.append(isSuppressingPointer)
    }

    /// キーが押された。本物と同じく、抑止している（9マスを開いている）間だけ .interrupted を送る
    func pressKey() {
        guard isSuppressingPointer else { return }
        send(.interrupted)
    }
}

@MainActor
final class ControllerFakeFrontmostApp: FrontmostAppObserving {
    var current: RunningAppInfo?
    var onChange: ((RunningAppInfo?) -> Void)?
    /// Nonet の設定ウィンドウなどがキー（current は変えない）
    var isOwnWindowKey = false
    private(set) var isRunning = false

    func start() {
        isRunning = true
    }

    func stop() {
        isRunning = false
    }

    func activate(_ app: RunningAppInfo?) {
        current = app
        onChange?(app)
    }
}

@MainActor
final class ControllerFakePermissions: PermissionsProviding {
    var isAccessibilityGranted = true
    var isSecureInputActive = false
    private(set) var requestCount = 0
    private(set) var openSettingsCount = 0

    func requestAccessibility() {
        requestCount += 1
    }

    func openAccessibilitySettings() {
        openSettingsCount += 1
    }
}

// MARK: - 出力

@MainActor
final class ControllerFakeHaptics: HapticPlayer {
    struct Play: Equatable {
        var event: HapticEvent
        var strength: HapticStrength
    }

    private(set) var plays: [Play] = []
    private let recorder: ControllerFakeRecorder

    init(recorder: ControllerFakeRecorder) {
        self.recorder = recorder
    }

    var events: [HapticEvent] { plays.map(\.event) }

    func play(_ event: HapticEvent, strength: HapticStrength) {
        plays.append(Play(event: event, strength: strength))
        recorder.log("haptic:\(event)")
    }
}

@MainActor
final class ControllerFakePerformer: ActionPerforming {
    struct Call {
        var action: Action
        var frontmostApp: RunningAppInfo?
    }

    private(set) var calls: [Call] = []
    /// 終わった順
    private(set) var finished: [Action] = []
    /// 失敗させるアクション
    var failure: ((Action) -> (any Error)?)?
    /// 返す文字列（AI の「結果を表示」）
    var output: ((Action) -> String?)?
    /// 呼ばれたときにすること（アプリを前面に出したことにする など）
    var onPerform: ((Action) -> Void)?
    /// true の間、呼ばれた実行は releaseOne() / release(_:) まで終わらない
    var holds = false
    /// true を返すアクションだけ止める（holds が false のとき）
    var holdsAction: ((Action) -> Bool)?
    private var waiting: [(action: Action, continuation: CheckedContinuation<Void, Never>)] = []
    private(set) var running = 0
    private(set) var maxRunning = 0
    private let recorder: ControllerFakeRecorder

    init(recorder: ControllerFakeRecorder) {
        self.recorder = recorder
    }

    var actions: [Action] { calls.map(\.action) }
    var waitingCount: Int { waiting.count }

    func perform(_ action: Action, context: ActionContext) async throws {
        _ = try await performReturningOutput(action, context: context)
    }

    func performReturningOutput(_ action: Action, context: ActionContext) async throws -> String? {
        calls.append(Call(action: action, frontmostApp: context.frontmostApp))
        recorder.log("perform:\(action.kind.rawValue)")
        running += 1
        maxRunning = max(maxRunning, running)
        defer { running -= 1 }
        onPerform?(action)
        if holds || holdsAction?(action) == true {
            await withCheckedContinuation { waiting.append((action, $0)) }
        }
        finished.append(action)
        if let error = failure?(action) { throw error }
        return output?(action)
    }

    /// 止めている実行を1つ（最初に止めたもの）終わらせる
    func releaseOne() {
        guard !waiting.isEmpty else { return }
        waiting.removeFirst().continuation.resume()
    }

    /// action を実行していて止めているもののうち、最初のものを終わらせる
    func release(_ action: Action) {
        guard let index = waiting.firstIndex(where: { $0.action == action }) else { return }
        waiting.remove(at: index).continuation.resume()
    }

    /// 止めているアクション（止めた順）
    var waitingActions: [Action] { waiting.map(\.action) }
}

@MainActor
final class ControllerFakeHUD: HUDPresenting {
    private(set) var shown: [HUDModel] = []
    private(set) var updates: [HUDModel] = []
    private(set) var hideCount = 0
    private(set) var toasts: [ToastModel] = []
    private(set) var results: [ResultModel] = []
    private(set) var isVisible = false
    /// いま出ている中身
    private(set) var current: HUDModel?
    /// 「画面に置く」の置く枠。出していなければ nil。変わるたびに記録する
    private(set) var placementPreview: CGRect?
    private(set) var placementPreviews: [CGRect?] = []
    private let recorder: ControllerFakeRecorder

    init(recorder: ControllerFakeRecorder) {
        self.recorder = recorder
    }

    /// prepare が返す地図の枠（主画面の左上が原点）。nil なら、マスはトラックパッドの上の指の位置で選ぶ
    var mapFrame: CGRect?
    private(set) var prepared: [HUDModel] = []

    func prepare(_ model: HUDModel) -> CGRect? {
        prepared.append(model)
        return mapFrame
    }

    func showPlacementPreview(_ frame: CGRect) {
        guard placementPreview != frame else { return }
        placementPreview = frame
        placementPreviews.append(frame)
        recorder.log("hud:preview")
    }

    func hidePlacementPreview() {
        guard placementPreview != nil else { return }
        placementPreview = nil
        placementPreviews.append(nil)
        recorder.log("hud:preview-off")
    }

    func show(_ model: HUDModel) {
        shown.append(model)
        current = model
        isVisible = true
        recorder.log("hud:show")
    }

    func update(_ model: HUDModel) {
        updates.append(model)
        current = model
        recorder.log("hud:update")
    }

    func hide() {
        hideCount += 1
        isVisible = false
        recorder.log("hud:hide")
    }

    func showToast(_ toast: ToastModel) {
        toasts.append(toast)
        recorder.log("toast:\(toast.style)")
    }

    func showResult(_ result: ResultModel) {
        results.append(result)
        recorder.log("result")
    }

    private(set) var toastHides = 0

    func hideToast() {
        toastHides += 1
        recorder.log("toast:hide")
    }
}

// MARK: - そのほか（コントローラーは使わない）

@MainActor
final class ControllerFakeInstalledApps: InstalledAppsProviding {
    var bundleIDs: Set<String>

    init(bundleIDs: Set<String> = []) {
        self.bundleIDs = bundleIDs
    }

    func installedApps() -> [AppReference] {
        bundleIDs.sorted().map { AppReference(bundleID: $0, name: $0) }
    }

    func isInstalled(bundleID: String) -> Bool {
        bundleIDs.contains(bundleID)
    }
}

@MainActor
final class ControllerFakeMenus: MenuReading {
    func runningApps() -> [RunningAppInfo] { [] }

    func menuItems(for app: RunningAppInfo) async throws -> [MenuItemNode] { [] }
}

@MainActor
final class ControllerFakeShortcuts: ShortcutsProviding {
    func shortcutNames() async -> [String] { [] }
}

@MainActor
final class ControllerFakeAI: AIAvailabilityProviding {
    var unavailableReason: String?
}

@MainActor
final class ControllerFakeLoginItem: LoginItemControlling {
    private(set) var isEnabled = false

    func setEnabled(_ enabled: Bool) throws {
        isEnabled = enabled
    }
}

/// 「画面に置く」の偽物。置く枠は決めた値を返し、置いた場所を記録する
@MainActor
final class ControllerFakeWindowPlacer: WindowPlacing {
    /// 画面の使える範囲（置く枠はここから決める）。nil なら、ウインドウが無い
    var visibleFrame: CGRect? = CGRect(x: 0, y: 0, width: 1440, height: 875)
    private(set) var placed: [WindowRegion] = []
    var failure: NonetError?

    func place(_ region: WindowRegion, app: RunningAppInfo?) throws {
        if let failure { throw failure }
        placed.append(region)
    }

    func targetFrame(for region: WindowRegion, app: RunningAppInfo?) -> CGRect? {
        visibleFrame.map(region.frame(in:))
    }
}
