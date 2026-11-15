import AppKit
import ApplicationServices
import Observation

struct Permissions: Equatable {
    var accessibility = false
    var listen = false
    var post = false

    var summary: String {
        "アクセシビリティ=\(accessibility ? "○" : "×") 入力監視=\(listen ? "○" : "×") イベント送出=\(post ? "○" : "×")"
    }
}

struct ObservedRange {
    var minX: Float = 1
    var maxX: Float = 0
    var minY: Float = 1
    var maxY: Float = 0

    mutating func include(x: Float, y: Float) {
        minX = min(minX, x)
        maxX = max(maxX, x)
        minY = min(minY, y)
        maxY = max(maxY, y)
    }

    var description: String {
        maxX < minX ? "—" : String(format: "x %.2f〜%.2f / y %.2f〜%.2f", minX, maxX, minY, maxY)
    }
}

/// トリガーを押してから離すまでの1回分
private struct Session {
    let startedAt: CFTimeInterval
    /// トリガーを押したときのカーソル位置（グローバル座標、左上原点）
    let anchor: CGPoint
    let swallowedTriggerDown: Bool
    let suppression: Suppression
    var executedFast = false
    var cellChanges = 0
    var swipeStartX: Float?
    var swipeLogged = false
    var dropped: [UInt32: Int] = [:]
    var passed: [UInt32: Int] = [:]

    var elapsedMS: Int { Int((CACurrentMediaTime() - startedAt) * 1000) }

    mutating func count(_ raw: UInt32, dropped isDropped: Bool) {
        if isDropped {
            dropped[raw, default: 0] += 1
        } else {
            passed[raw, default: 0] += 1
        }
    }

    static func describe(_ counts: [UInt32: Int]) -> String {
        guard !counts.isEmpty else { return "なし" }
        return counts.sorted { $0.key < $1.key }.map { "\(EventKind.name($0.key))×\($0.value)" }.joined(separator: " ")
    }
}

private struct TouchStart {
    let time: CFTimeInterval
    let x: Float
    let y: Float
    let cell: Int?
    let inSession: Bool
    var maxFingers: Int
}

/// 検証用の Nonet 本体。トリガー → 速押し or HUD → 実行 の流れと、計測・ログを受け持つ
@Observable
final class SpikeController {
    // MARK: 設定

    var trigger: TriggerKey = KeyboardInfo.isJIS ? .rightCommand : .rightOption
    var fireMode: FireMode = .onRelease
    var hudDelay = 0.3
    var hudPosition: HUDPosition = .center
    var suppression: Suppression = .drop
    var tapLocation: EventTap.Location = .hid
    var swallowTrigger = false
    /// マスの境界をまたいだと判定するまでの余裕（トラックパッド全体を 1 とした割合）
    var hysteresis = 0.03
    var hapticMode: HapticMode = .alignment
    var actuationID = 6
    var actuationUnknown2 = 0.0
    var actuationUnknown3 = 2.0
    var currentTest: SpikeTest = .t1
    var memo = ""

    // MARK: 状態

    var permissions = Permissions()
    var tapStatus = "未作成"
    var devices: [MultitouchDevice] = []
    var multitouchError: String?
    var actuatorStatus = "未接続"
    var frameCount = 0
    var fingerCount = 0
    /// 0〜1。y は手前が 0
    var position: CGPoint?
    var currentCell: Int?
    var range = ObservedRange()
    var phase: Phase = .idle
    var lastExecuted = "—"
    var lastSessionSummary = "—"
    var lastSwipe = "—"
    var hapticTestLabel = ""
    var logLines: [String] = []

    let logPath = SpikeLog.shared.fileURL.path

    @ObservationIgnored private let tap = EventTap()
    @ObservationIgnored private let haptics = Haptics()
    @ObservationIgnored private var hud: HUDController?
    @ObservationIgnored private var session: Session?
    @ObservationIgnored private var hudTimer: DispatchWorkItem?
    @ObservationIgnored private var droppedButtons = Set<Int64>()
    @ObservationIgnored private var activeDevice: Int32 = 0
    @ObservationIgnored private var touchStart: TouchStart?
    @ObservationIgnored private var lastPoint: TouchPoint?
    @ObservationIgnored private var pollTimer: Timer?
    @ObservationIgnored private var tapAttempted = false

    var triggerName: String { "右\(trigger.symbol)" }

    // MARK: 起動・終了

    func start() {
        SpikeLog.shared.onLine = { [weak self] line in
            guard let self else { return }
            logLines.append(line)
            if logLines.count > 300 { logLines.removeFirst(logLines.count - 300) }
        }
        hud = HUDController(controller: self)
        log("起動", "======== Nonet 技術検証 ========")
        log("起動", "macOS \(ProcessInfo.processInfo.operatingSystemVersionString) / キーボード \(KeyboardInfo.layoutName) / 既定のトリガー \(trigger.rawValue)")
        startMultitouch()
        tap.handler = { [unowned self] type, event in self.handle(type: type, event: event) }
        tap.onDisabled = { type in
            log("タップ", type == .tapDisabledByTimeout ? "タイムアウトで無効化された → 再有効化" : "ユーザー入力で無効化された → 再有効化")
        }
        refreshPermissions()
        log("権限", permissions.summary)
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        log("テスト", "======== \(currentTest.title) ========")
    }

    func stop() {
        if session != nil { finishSession(reason: "アプリ終了") }
        Multitouch.stop()
        haptics.close()
        tap.uninstall()
        log("終了", "アプリを終了")
    }

    private func startMultitouch() {
        let (devices, error) = Multitouch.load()
        self.devices = devices
        multitouchError = error
        if let error {
            log("マルチタッチ", "読み込み失敗: \(error)")
            return
        }
        devices.forEach { log("マルチタッチ", $0.summary) }
        activeDevice = devices.first(where: \.builtIn)?.index ?? devices.first?.index ?? 0
        let result = haptics.openActuator(deviceIndex: activeDevice)
        actuatorStatus = result == 0 ? "デバイス #\(activeDevice) に接続" : String(format: "接続失敗 0x%08x", UInt32(bitPattern: result))
        log("触覚", "アクチュエータ: \(actuatorStatus)")
        Multitouch.start { [weak self] deviceIndex, touches in
            DispatchQueue.main.async { self?.handle(deviceIndex: deviceIndex, touches: touches) }
        }
    }

    // MARK: 権限

    func refreshPermissions() {
        let current = Permissions(
            accessibility: AXIsProcessTrusted(),
            listen: CGPreflightListenEventAccess(),
            post: CGPreflightPostEventAccess()
        )
        let changed = current != permissions
        if changed {
            permissions = current
            log("権限", current.summary)
        }
        if !tap.isInstalled, current.accessibility, !tapAttempted || changed {
            installTap()
        }
    }

    func installTap() {
        tapAttempted = true
        tapStatus = tap.install(at: tapLocation)
            ? "\(tapLocation.rawValue) レベルで動作中"
            : "作成できない（アクセシビリティの許可が必要）"
        log("タップ", tapStatus)
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func requestListenAccess() {
        _ = CGRequestListenEventAccess()
    }

    func openPrivacySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    func revealLog() {
        NSWorkspace.shared.activateFileViewerSelecting([SpikeLog.shared.fileURL])
    }

    func resetRange() {
        range = ObservedRange()
    }

    /// トリガーなしで HUD の見た目だけ確かめる
    func previewHUD() {
        guard session == nil else { return }
        hud?.show(at: hudPosition)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, session == nil else { return }
            hud?.hide()
        }
    }

    func testChanged() {
        log("テスト", "======== \(currentTest.title) ========")
    }

    func submitMemo() {
        let text = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        log("メモ", "[\(currentTest.title)] \(text)")
        memo = ""
    }

    private func tick() {
        refreshPermissions()
        guard let session else { return }
        let age = CACurrentMediaTime() - session.startedAt
        if age > 15 {
            abortSession(reason: "15秒を超えた（安全装置）")
        } else if !session.swallowedTriggerDown, age > 1,
                  CGEventSource.flagsState(.hidSystemState).rawValue & trigger.deviceMask == 0 {
            abortSession(reason: "トリガーが押されていない（離したイベントを取りこぼした？）")
        }
    }

    // MARK: トラックパッド

    private func handle(deviceIndex: Int32, touches: [TouchPoint]) {
        guard deviceIndex == activeDevice else { return }
        frameCount += 1
        let touching = touches.filter(\.isTouching)
        let previousCount = fingerCount
        fingerCount = touching.count
        let began = previousCount == 0 && fingerCount > 0
        if began { currentCell = nil }

        // 複数の指があるときは、最後に置いた指を使う
        if let point = touching.max(by: { $0.id < $1.id }) {
            lastPoint = point
            position = CGPoint(x: CGFloat(point.x), y: CGFloat(point.y))
            range.include(x: point.x, y: point.y)
            let cell = cellFor(x: point.x, y: point.y)
            if cell != currentCell {
                let old = currentCell
                currentCell = cell
                cellChanged(from: old, to: cell)
            }
        } else {
            position = nil
        }

        if began, let point = lastPoint {
            touchStart = TouchStart(time: CACurrentMediaTime(), x: point.x, y: point.y, cell: currentCell, inSession: session != nil, maxFingers: fingerCount)
        }
        if let start = touchStart, fingerCount > start.maxFingers {
            touchStart?.maxFingers = fingerCount
        }
        if previousCount > 0 && fingerCount == 0 { touchEnded() }
        trackSwipe(touching)
    }

    /// 3×3 のマス番号（0〜8、左上から）。境界付近では今のマスを保つ
    private func cellFor(x: Float, y: Float) -> Int {
        let fx = Double(x) * 3
        let fy = (1 - Double(y)) * 3
        let candidate = min(2, max(0, Int(fy))) * 3 + min(2, max(0, Int(fx)))
        guard let current = currentCell, current != candidate, hysteresis > 0 else { return candidate }
        let margin = hysteresis * 3
        let col = Double(current % 3)
        let row = Double(current / 3)
        let inside = fx >= col - margin && fx <= col + 1 + margin && fy >= row - margin && fy <= row + 1 + margin
        return inside ? current : candidate
    }

    private func cellChanged(from old: Int?, to new: Int) {
        guard session != nil, let old else { return }
        session?.cellChanges += 1
        let error = haptics.play(hapticMode, actuationID: Int32(actuationID), unknown2: Float(actuationUnknown2), unknown3: Float(actuationUnknown3))
        log("マス", "\(old + 1) → \(new + 1)  触覚=\(hapticMode.rawValue)\(error.map { "（\($0)）" } ?? "")")
    }

    private func touchEnded() {
        guard let start = touchStart else { return }
        touchStart = nil
        let duration = Int((CACurrentMediaTime() - start.time) * 1000)
        // ふだんの操作のタッチまで残すとログが埋まるので、セッション外は T1 のときだけ
        if start.inSession || currentTest == .t1 {
            log("タッチ", String(
                format: "マス%@ 開始(%.2f, %.2f) → 終了(%.2f, %.2f) %dms 最大%d本",
                cellName(start.cell), start.x, start.y, lastPoint?.x ?? 0, lastPoint?.y ?? 0, duration, start.maxFingers
            ))
        }
        // トリガーを押してから置いた1本指のタッチだけを、マスのタップとして扱う
        guard session != nil, start.inSession, start.maxFingers == 1 else { return }
        switch phase {
        case .armed:
            if let cell = start.cell { execute(cell: cell, path: "速押し") }
            session?.executedFast = true
            hudTimer?.cancel()
        case .hud where fireMode == .onTap:
            if let cell = currentCell { execute(cell: cell, path: "HUD・指を離す") }
        default:
            break
        }
    }

    private func trackSwipe(_ touching: [TouchPoint]) {
        guard session != nil else { return }
        guard touching.count == 2 else {
            session?.swipeStartX = nil
            session?.swipeLogged = false
            return
        }
        let x = (touching[0].x + touching[1].x) / 2
        guard let startX = session?.swipeStartX else {
            session?.swipeStartX = x
            return
        }
        let dx = x - startX
        if abs(dx) > 0.12, session?.swipeLogged == false {
            session?.swipeLogged = true
            lastSwipe = dx > 0 ? "→ 次のページ" : "← 前のページ"
            log("スワイプ", "2本指 \(lastSwipe)（前面: \(frontAppName)）")
        }
    }

    // MARK: キーボード・ポインタ

    /// false を返したイベントは前面アプリに届かない
    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        let raw = type.rawValue
        if type == .flagsChanged { return handleFlagsChanged(event) }

        // ボタンを離すイベントは、押すイベントを捨てたものだけ捨てる（セッションの外でも）
        if let button = EventKind.upButton(raw, event) {
            let drop = droppedButtons.remove(button) != nil
            session?.count(raw, dropped: drop)
            return !drop
        }
        guard session != nil else { return true }

        if type == .keyDown {
            abortSession(reason: "他のキー（keyCode \(event.getIntegerValueField(.keyboardEventKeycode))）")
            return true
        }
        guard EventKind.isPointer(raw), suppression != .none else {
            session?.count(raw, dropped: false)
            return true
        }
        if let button = EventKind.downButton(raw, event) { droppedButtons.insert(button) }
        if suppression == .dropWarp, EventKind.isMove(raw), let anchor = session?.anchor {
            CGWarpMouseCursorPosition(anchor)
        }
        session?.count(raw, dropped: true)
        return false
    }

    private func handleFlagsChanged(_ event: CGEvent) -> Bool {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        guard keyCode == trigger.keyCode else {
            if session != nil { abortSession(reason: "他の修飾キー（keyCode \(keyCode)）") }
            return true
        }
        if flags.rawValue & trigger.deviceMask != 0 {
            guard session == nil else { return true }
            let others = flags.intersection([.maskShift, .maskControl, .maskAlternate, .maskCommand]).subtracting(trigger.flag)
            if !others.isEmpty || flags.rawValue & trigger.leftDeviceMask != 0 {
                log("トリガー", "他の修飾キーと一緒に押されたので無視")
                return true
            }
            beginSession(anchor: event.location)
            return !swallowTrigger
        }
        guard let session else { return true }
        endSession()
        return !session.swallowedTriggerDown
    }

    // MARK: セッション

    private func beginSession(anchor: CGPoint) {
        session = Session(startedAt: CACurrentMediaTime(), anchor: anchor, swallowedTriggerDown: swallowTrigger, suppression: suppression)
        phase = .armed
        log("セッション", "\(triggerName) 押下  前面=\(frontAppName) 指=\(fingerCount)本 抑止=\(suppression.rawValue) タップ=\(tapLocation.rawValue) 渡さない=\(swallowTrigger)")
        if suppression == .dropDecouple {
            let error = CGAssociateMouseAndMouseCursorPosition(0)
            if error != .success { log("抑止", "カーソルの切り離しに失敗（CGError \(error.rawValue)）") }
        }
        scheduleHUD(after: hudDelay)
    }

    private func scheduleHUD(after delay: Double) {
        let work = DispatchWorkItem { [weak self] in self?.showHUD() }
        hudTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func showHUD() {
        guard let session, phase == .armed, !session.executedFast else { return }
        // 待ち時間内に指を置いていたら速押しとみなし、その指が置かれたまま止まったときだけ HUD を出す
        if let start = touchStart, start.inSession {
            let remaining = start.time + hudDelay - CACurrentMediaTime()
            if remaining > 0 {
                scheduleHUD(after: remaining)
                return
            }
        }
        phase = .hud
        hud?.show(at: hudPosition)
        log("HUD", "表示（押下から \(session.elapsedMS)ms、指=\(fingerCount)本）")
    }

    /// トリガーを離したとき
    private func endSession() {
        guard let session else { return }
        switch phase {
        case .hud where fireMode == .onRelease:
            if fingerCount > 0, let cell = currentCell {
                execute(cell: cell, path: "HUD・キーを離す")
            } else {
                log("セッション", "指が離れていたのでキャンセル")
            }
        case .armed where !session.executedFast:
            log("セッション", fingerCount > 0
                ? "HUD が出る前にキーを離した（指はマス\(cellName(currentCell))）→ 実行しない"
                : "何もせずにキーを離した")
        default:
            break
        }
        finishSession(reason: "\(triggerName) を離した")
    }

    private func abortSession(reason: String) {
        log("セッション", "中断: \(reason)")
        finishSession(reason: reason)
    }

    private func finishSession(reason: String) {
        guard let session else { return }
        hudTimer?.cancel()
        hudTimer = nil
        hud?.hide()
        if session.suppression == .dropDecouple { CGAssociateMouseAndMouseCursorPosition(1) }
        let cursor = CGEvent(source: nil)?.location ?? session.anchor
        let drift = Int(hypot(cursor.x - session.anchor.x, cursor.y - session.anchor.y).rounded())
        let dropped = Session.describe(session.dropped)
        let passed = Session.describe(session.passed)
        lastSessionSummary = "\(session.elapsedMS)ms / カーソルのずれ \(drift)pt / マス移動 \(session.cellChanges)回\n捨てた: \(dropped)\n通した: \(passed)"
        log("セッション", "終了（\(reason)） \(session.elapsedMS)ms カーソルのずれ=\(drift)pt マス移動=\(session.cellChanges)回 捨てた=[\(dropped)] 通した=[\(passed)]")
        self.session = nil
        phase = .idle
    }

    private func execute(cell: Int, path: String) {
        let item = sampleCells[cell]
        lastExecuted = "マス\(cell + 1)「\(item.label)」（\(path)、押下から \(session?.elapsedMS ?? 0)ms）"
        log("実行", lastExecuted)
        hud?.toast("▶ \(item.label)")
    }

    // MARK: 触覚テスト

    func playHapticTest() {
        let mode = hapticMode
        hapticTestLabel = "2秒後に「\(mode.rawValue)」…"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [self] in
            playTestHaptic(mode, actuationID: actuationID, label: mode.rawValue)
            hapticTestLabel = "鳴らした: \(mode.rawValue)"
        }
    }

    func runHapticSequence() {
        var steps: [(label: String, mode: HapticMode, id: Int)] = [
            ("NSHaptic alignment", .alignment, 0),
            ("NSHaptic generic", .generic, 0),
            ("NSHaptic levelChange", .levelChange, 0),
        ]
        steps += [1, 2, 3, 4, 5, 6, 15, 16].map { ("MTActuator ID \($0)", .actuator, $0) }
        hapticTestLabel = "指をトラックパッドに置いて待ってください"
        log("触覚テスト", "\(steps.count) 種類を2秒おきに鳴らす")
        for (index, step) in steps.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2 + Double(index) * 2) { [self] in
                hapticTestLabel = "\(index + 1)/\(steps.count): \(step.label)"
                playTestHaptic(step.mode, actuationID: step.id, label: "\(index + 1). \(step.label)")
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2 + Double(steps.count) * 2) { [self] in
            hapticTestLabel = "完了。感じた番号をメモに書いてください"
        }
    }

    private func playTestHaptic(_ mode: HapticMode, actuationID: Int, label: String) {
        let error = haptics.play(mode, actuationID: Int32(actuationID), unknown2: Float(actuationUnknown2), unknown3: Float(actuationUnknown3))
        log("触覚テスト", "\(label) → \(error ?? "OK")（指=\(fingerCount)本、このアプリが前面=\(NSApp.isActive)）")
    }

    // MARK: 補助

    private var frontAppName: String {
        NSWorkspace.shared.frontmostApplication?.localizedName ?? "不明"
    }

    private func cellName(_ cell: Int?) -> String {
        cell.map { "\($0 + 1)" } ?? "-"
    }
}
