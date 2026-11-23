// 担当: platform-input
// クラス名・public init・protocol への準拠は契約（NonetServices.live() が使う）
import AppKit
import ApplicationServices
import NonetCore

/// セッション（9マスを開いている間）のポインタ系のイベントを止め、キーが押されたら知らせるイベントタップ。
/// タップはキーボード用・ポインタ用・クリック用に分ける。キーボード用は抑止中だけ有効にし、9マスを開いていない間はキーボードを見ない。
/// クリック用は強く長押しで開けるとき（forcePressHold）だけ有効にし、左ボタンの押下だけを見る。トラックパッドで押した左クリックを
/// 預かり（ForceClickHolder）、預かっている間はポインタ用も有効にして、その離す・押したままの動き・感圧を見る。
/// ポインタ用は抑止中とその後片付け（指が離れた直後などに終えたときに、遅れて届くクリックを捨てる短い間を含む）の間だけ有効にして、
/// ふだんのマウス・トラックパッドのイベントを Nonet のメインスレッドに通さない（メインスレッドが詰まったときに、システム全体のカーソルが止まらないように）
@MainActor
public final class EventTapKeyboardMonitor: KeyboardMonitor {
    /// 9マスを開いている間もポインタはふだんどおり動く（HUD の地図の上でポインタが乗っているマスを選ぶ）。
    /// イベントタップで移動のイベントを捨てるとポインタそのものが止まるので、移動は捨てずに前面のアプリへ渡し、クリック・スクロール・ジェスチャーだけ捨てる
    public var cursorLock: CursorLockMethod = .none
    public var isSuppressingPointer = false {
        didSet {
            guard isSuppressingPointer != oldValue else { return }
            isSuppressingPointer ? beginSuppression() : endSuppression()
        }
    }
    public var onEvent: ((KeyboardEvent) -> Void)?
    /// トラックパッドにいま指が触れているか。抑止中に、触れていない間に届いたマウスやホイールのイベントでセッションを終える
    public var isTrackpadTouched: Bool {
        get { contact.isTouched }
        set { contact.update(isTouched: newValue, at: now()) }
    }

    /// 両方のタップがあり、システムに無効にされていない（アクセシビリティを切ると、タップの Mach ポートが無効になることがある。
    /// 2秒ごとの確かめの間に切って入れ直しても、ここが false になれば start で作り直す）
    public var isRunning: Bool { keyboardTap?.isAlive == true && pointerTap?.isAlive == true && clickTap?.isAlive == true }

    /// 強く押し込んでから .forcePressed を送るまで止めておく秒数。nil の間はクリックを預からない（クリック用のタップも止める）
    public var forcePressHold: TimeInterval? {
        didSet {
            guard forcePressHold != oldValue else { return }
            if forcePressHold == nil {
                returnHeldClick()
            }
            updateClickTap()
            scheduleHolderTimer()
        }
    }

    /// .forcePressed への答え。開いたならクリックを捨て、開かなかったなら前面アプリに返す
    public func finishForcePress(opened: Bool) {
        if case .giveBack(let withUp) = holder.finish(opened: opened) {
            giveBackHeldClick(withUp: withUp)
        }
        if !holder.isActive { heldDown = nil }
        updatePointerTap()
    }

    /// 見るボタンの番号（0: 左・1: 右・2: 真ん中、その先はマウスの追加のボタン。CGMouseButton は 32 個まで）
    static let watchedButtons: Range<Int64> = 0..<32

    /// どれかのボタンがいま物理的に押されているか（hidSystemState）。9マスを開く前に確かめる
    public var isMouseButtonDown: Bool {
        Self.watchedButtons.contains(where: physicalButton)
    }

    /// 抑止をやめる。dropsLateClicks なら、その直後の clickGraceInterval の間に届く「押す」も捨てる
    public func endPointerSuppression(dropsLateClicks: Bool) {
        endsWithClickGrace = dropsLateClicks
        defer { endsWithClickGrace = false }
        isSuppressingPointer = false
    }

    /// 抑止の後でポインタのタップを残している間、もう届かないものを片付ける間隔
    static let sweepInterval: TimeInterval = 0.5

    private var keys = SessionKeyWatcher()
    private var suppressor = PointerSuppressor()
    private var contact = TrackpadContact()
    /// 強く長押しで開くために預かっているクリック
    private var holder = ForceClickHolder()
    /// 預かっている左ボタンの押下の写し（返すときに送る）
    private var heldDown: CGEvent?
    /// 預かったクリックの、強く押し込んで止め終える時刻か、返す時刻
    private var holderTimer: Timer?
    /// この抑止の間に、マウスやホイールで .interrupted を送った（1回だけ送る）
    private var didInterruptForOtherDevice = false
    /// 抑止を始めたときの方式と、カーソルの位置
    private var activePlan: CursorLockPlan?
    private var anchor: CGPoint?
    /// rememberPointerLocation で覚えた位置。次の抑止の始まりでそこへ戻し、使ったら忘れる
    private(set) var rememberedLocation: CGPoint?
    /// 抑止中だけ有効
    private var keyboardTap: EventTapConnection?
    /// 抑止中と、捨てた押下の離す・スクロールの続きを待っている間だけ有効
    private var pointerTap: EventTapConnection?
    /// 強く長押しで開けるときだけ有効（左ボタンの押下だけを見る）
    private var clickTap: EventTapConnection?
    /// クリック用のタップを有効にしているか
    private(set) var isClickTapEnabled = false
    /// ポインタのタップを有効にしているか（タップが無いときも、有効にしたいかを覚えておく）
    private(set) var isPointerTapEnabled = false
    /// キーボードのタップを有効にしているか（抑止中だけ。タップが無いときも、有効にしたいかを覚えておく）
    private(set) var isKeyboardTapEnabled = false
    private var sweeper: Timer?
    /// 抑止の直後にクリックを捨てる間が終わったら、ポインタのタップを止めるか確かめ直す
    private var clickGraceTimer: Timer?
    /// endPointerSuppression(dropsLateClicks: true) で抑止をやめているところ
    private var endsWithClickGrace = false
    private let cursor: any CursorControlling
    private let association: CursorAssociationGuard
    private let physicalButton: (Int64) -> Bool
    private let isAccessibilityTrusted: () -> Bool
    /// 返すイベントを送る（テストでは送らずに記録する）
    private let postEvent: (CGEvent) -> Void
    /// 感圧のイベントの段階（NSEvent.stage。1: ふつうのクリック、2: 強めのクリック）
    private let pressureStage: @MainActor (CGEvent) -> Int
    private let ownProcessID: Int64
    /// 単調な時計の秒
    private let now: () -> TimeInterval

    public convenience init() {
        self.init(
            cursor: SystemCursorControl(),
            physicalButton: { number in
                guard let raw = UInt32(exactly: number), let button = CGMouseButton(rawValue: raw) else { return false }
                return CGEventSource.buttonState(.hidSystemState, button: button)
            },
            isAccessibilityTrusted: { AXIsProcessTrusted() },
            ownProcessID: Int64(getpid())
        )
    }

    init(
        cursor: any CursorControlling,
        physicalButton: @escaping (Int64) -> Bool,
        isAccessibilityTrusted: @escaping () -> Bool,
        ownProcessID: Int64,
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        postEvent: @escaping (CGEvent) -> Void = { $0.post(tap: .cghidEventTap) },
        pressureStage: @escaping @MainActor (CGEvent) -> Int = { NSEvent(cgEvent: $0)?.stage ?? 0 }
    ) {
        self.postEvent = postEvent
        self.pressureStage = pressureStage
        self.cursor = cursor
        association = CursorAssociationGuard(cursor: cursor)
        self.physicalButton = physicalButton
        self.isAccessibilityTrusted = isAccessibilityTrusted
        self.ownProcessID = ownProcessID
        self.now = now
    }

    public func start() throws {
        guard !isRunning else { return }
        // システムに無効にされたタップが残っていれば、外してから作り直す
        if keyboardTap != nil || pointerTap != nil || clickTap != nil {
            inputLogger.notice("イベントタップが無効になっていたので、作り直す")
            stop()
        }
        guard isAccessibilityTrusted() else {
            throw NonetError.permissionDenied(InputText.accessibility)
        }
        // 片方だけでは使えない（ポインタを止められないと、タップがそのままクリックになる）。作れなければ両方とも外す。
        // どちらも無効のまま作り、9マスを開いている間（とポインタの後片付けの間）だけ有効にする
        guard let keyboardTap = EventTapConnection(box: EventTapBox(monitor: self, role: .keyboard), events: EventTapMask.keyboard, enabled: false),
              let pointerTap = EventTapConnection(box: EventTapBox(monitor: self, role: .pointer), events: EventTapMask.pointer, enabled: false),
              let clickTap = EventTapConnection(box: EventTapBox(monitor: self, role: .click), events: EventTapMask.click, enabled: false)
        else {
            inputLogger.error("イベントタップを作れない")
            throw NonetError.permissionDenied(InputText.accessibility)
        }
        self.keyboardTap = keyboardTap
        self.pointerTap = pointerTap
        self.clickTap = clickTap
        suppressor = PointerSuppressor()
        holder = ForceClickHolder()
        heldDown = nil
        isPointerTapEnabled = false
        isKeyboardTapEnabled = false
        isClickTapEnabled = false
        updateKeyboardTap()
        updatePointerTap()
        updateClickTap()
        inputLogger.info("イベントタップを開始（キーボード: \(keyboardTap.levelName, privacy: .public)、ポインタ: \(pointerTap.levelName, privacy: .public)）")
    }

    public func stop() {
        // 預かっているクリックは返してから外す（押したままにも、押していないことにもしない）
        returnHeldClick()
        clickTap?.invalidate()
        clickTap = nil
        isClickTapEnabled = false
        keyboardTap?.invalidate()
        keyboardTap = nil
        pointerTap?.invalidate()
        pointerTap = nil
        isSuppressingPointer = false
        rememberedLocation = nil
        // 抑止の後片付け（クリックを捨てる間を含む）も残さない
        suppressor = PointerSuppressor()
        updatePointerTap()
        stopHolderTimer()
        association.restore()
    }

    // MARK: イベント

    /// イベントタップのコールバック（メインスレッド）。false なら前面アプリに渡さない。
    /// すべての入力がここを通るので、ログを書かず、すぐ戻る
    func handle(type: CGEventType, event: CGEvent, from role: EventTapRole) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            tapWasDisabled(role, type: type)
            return true
        case .flagsChanged, .keyDown:
            // キーはいつも前面アプリに渡す。開いている間に押されたら閉じてもらう。
            // キー入力のアクションが HID の位置に送ったキーは、押したキーとして数えない
            guard isSuppressingPointer, !isOwnEvent(event) else { return true }
            let output = if type == .keyDown {
                keys.keyDown()
            } else {
                keys.flagsChanged(keyCode: event.getIntegerValueField(.keyboardEventKeycode), flags: event.flags)
            }
            if let output { emit(output) }
            return true
        default:
            if role == .click {
                return handleClickDown(type: type.rawValue, event: event)
            }
            if holder.isActive, !isOwnEvent(event), let pass = handleHeldClick(type: type.rawValue, event: event) {
                return pass
            }
            return handlePointer(type: type.rawValue, event: event)
        }
    }

    private func isOwnEvent(_ event: CGEvent) -> Bool {
        OwnEventFilter.isOwn(
            sourcePID: event.getIntegerValueField(.eventSourceUnixProcessID),
            userData: event.getIntegerValueField(.eventSourceUserData),
            ownPID: ownProcessID
        )
    }

    private func tapWasDisabled(_ role: EventTapRole, type: CGEventType) {
        switch role {
        case .keyboard:
            // 有効にしておくはずのとき（開いている間）だけ有効にし直す。自分で無効にした直後の知らせは何もしない
            guard isKeyboardTapEnabled else { return }
            keyboardTap?.setEnabled(true)
            inputLogger.notice("キーボードのイベントタップが無効にされたので有効にし直した（\(type.rawValue)）")
        case .click:
            guard PointerTapDisableResponse.response(to: type, isPointerTapEnabled: isClickTapEnabled) == .recover else { return }
            // 無効にされた間の押下は前面アプリに渡っている。預かっているクリックがあれば返す
            returnHeldClick()
            if isClickTapEnabled { clickTap?.setEnabled(true) }
            inputLogger.notice("クリックのイベントタップが無効にされた（\(type.rawValue)）")
            updatePointerTap()
        case .pointer:
            // 自分で無効にした直後にも届く（start の後と、セッションの後片付けを終えるたび）。取りこぼしではない
            guard PointerTapDisableResponse.response(to: type, isPointerTapEnabled: isPointerTapEnabled) == .recover else { return }
            suppressor.eventsMayHaveBeenMissed()
            // 預かっているクリックの離すを取りこぼしたかもしれない
            returnHeldClick()
            // 有効にしておくはずのときだけ有効にし直す
            if isPointerTapEnabled { pointerTap?.setEnabled(true) }
            inputLogger.notice("ポインタのイベントタップが無効にされた（\(type.rawValue)）")
            updatePointerTap()
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
        if isSuppressingPointer, !didInterruptForOtherDevice, contact.isFromAnotherDevice(info, now: now()) {
            // マウスやホイールを使った: 何も実行せずにセッションを終えてもらい、イベントは手を加えずに渡す
            didInterruptForOtherDevice = true
            emit(.interrupted)
            updatePointerTap()
            return true
        }
        let decision = suppressor.decide(info, suppressing: isSuppressingPointer, dropsMoves: activePlan?.dropsMoves ?? false, now: now())
        updatePointerTap()
        switch decision {
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

    private func emit(_ event: KeyboardEvent) {
        onEvent?(event)
    }

    // MARK: キーボードのタップ

    /// キーボードのタップは抑止中だけ有効にする（9マスを開いていない間は、キーボードのイベントを Nonet に通さない）
    private func updateKeyboardTap() {
        let wanted = isSuppressingPointer
        guard wanted != isKeyboardTapEnabled else { return }
        isKeyboardTapEnabled = wanted
        keyboardTap?.setEnabled(wanted)
    }

    // MARK: ポインタのタップ

    /// ポインタのタップは、抑止中と、抑止の直後にクリックを捨てる間と、捨てた押下の離す・スクロールの続きを
    /// 待っている間だけ有効にする。判断を変えうること（抑止の開始・終了、ポインタのイベント、片付け）の後に毎回呼ぶ
    private func updatePointerTap() {
        let time = now()
        let wanted = suppressor.needsEvents(suppressing: isSuppressingPointer, now: time) || holder.isActive
        if wanted != isPointerTapEnabled {
            isPointerTapEnabled = wanted
            pointerTap?.setEnabled(wanted)
        }
        if wanted, !isSuppressingPointer {
            startSweeper()
        } else {
            stopSweeper()
        }
        // クリックを捨てる間が終わったら、イベントが来なくても確かめ直してタップを止める
        if !isSuppressingPointer, let deadline = suppressor.clickGraceDeadline, time < deadline {
            startClickGraceTimer(after: deadline - time)
        } else {
            stopClickGraceTimer()
        }
    }

    /// 抑止が終わった後、もう届かない離すイベントやスクロールの続きを待つのをやめる
    func sweepPointerState() {
        suppressor.sweep(isPhysicallyPressed: physicalButton, now: now())
        holder.forgetConsumedIfReleased(isPressed: physicalButton(0))
        updatePointerTap()
    }

    /// 抑止の直後にクリックを捨てる間が終わった（タイマーから呼ぶ）
    func clickGraceDidEnd() {
        clickGraceTimer?.invalidate()
        clickGraceTimer = nil
        updatePointerTap()
    }

    var isWaitingForClickGrace: Bool { clickGraceTimer != nil }

    private func startClickGraceTimer(after delay: TimeInterval) {
        guard clickGraceTimer == nil else { return }
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.clickGraceDidEnd() }
        }
        RunLoop.main.add(timer, forMode: .common)
        clickGraceTimer = timer
    }

    private func stopClickGraceTimer() {
        clickGraceTimer?.invalidate()
        clickGraceTimer = nil
    }

    var isSweeping: Bool { sweeper != nil }

    private func startSweeper() {
        guard sweeper == nil else { return }
        sweeper = repeatingTimer(interval: Self.sweepInterval) { $0.sweepPointerState() }
    }

    private func stopSweeper() {
        sweeper?.invalidate()
        sweeper = nil
    }

    /// メニューを開いている間も動くように common モードに置く。モニタが解放されたら止まる
    private func repeatingTimer(interval: TimeInterval, action: @escaping @MainActor (EventTapKeyboardMonitor) -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else {
                    timer.invalidate()
                    return
                }
                action(self)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    // MARK: 強く長押し（クリックの預かり）

    /// クリック用のタップは、強く長押しで開けるときだけ有効にする
    private func updateClickTap() {
        let wanted = forcePressHold != nil
        guard wanted != isClickTapEnabled else { return }
        isClickTapEnabled = wanted
        clickTap?.setEnabled(wanted)
    }

    /// クリック用のタップに届いた左ボタンの押下。開けるとき・開いていないとき・トラックパッドに触れているときだけ預かる
    /// （マウスのクリックや、指を離した後に届く「タップでクリック」は預からない）
    private func handleClickDown(type: UInt32, event: CGEvent) -> Bool {
        guard type == PointerEventKind.leftMouseDown, !isOwnEvent(event) else { return true }
        let canHold = forcePressHold != nil && !isSuppressingPointer && contact.isKnown && contact.isTouched
        let decision = holder.leftDown(at: event.location, now: now(), canHold: canHold)
        heldDown = holder.isActive ? event.copy() : nil
        updatePointerTap()
        scheduleHolderTimer()
        return apply(decision, to: event)
    }

    /// 預かっている間にポインタ用のタップに届いた、左ボタンの離す・押したままの動き・感圧。ほかのイベントなら nil（ふつうに扱う）
    private func handleHeldClick(type: UInt32, event: CGEvent) -> Bool? {
        let decision: ForceClickHolder.Decision
        switch type {
        case PointerEventKind.leftMouseUp:
            decision = holder.leftUp()
        case PointerEventKind.leftMouseDragged:
            decision = holder.leftDragged(to: event.location)
        case PointerEventKind.pressure:
            decision = holder.pressure(stage: pressureStage(event), now: now())
        default:
            return nil
        }
        let pass = apply(decision, to: event)
        if !holder.isActive { heldDown = nil }
        updatePointerTap()
        scheduleHolderTimer()
        return pass
    }

    private func apply(_ decision: ForceClickHolder.Decision, to event: CGEvent) -> Bool {
        switch decision {
        case .pass:
            return true
        case .drop:
            return false
        case .passAsMove:
            event.type = .mouseMoved
            return true
        case .giveBackWithCurrent:
            giveBackHeldClick(withUp: false, current: event)
            return false
        }
    }

    /// 止め終えた・強く押し込まないまま押し続けた（タイマーから呼ぶ）
    func holderDeadlineDidPass() {
        stopHolderTimer()
        switch holder.tick(now: now(), hold: forcePressHold ?? 0) {
        case .none:
            break
        case .giveBack:
            giveBackHeldClick(withUp: false)
        case .requestOpen:
            emit(.forcePressed)
        }
        if !holder.isActive { heldDown = nil }
        updatePointerTap()
        scheduleHolderTimer()
    }

    var isWaitingForHolderDeadline: Bool { holderTimer != nil }

    private func scheduleHolderTimer() {
        stopHolderTimer()
        guard let deadline = holder.nextDeadline(hold: forcePressHold ?? 0) else { return }
        let timer = Timer(timeInterval: max(deadline - now(), 0), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.holderDeadlineDidPass() }
        }
        RunLoop.main.add(timer, forMode: .common)
        holderTimer = timer
    }

    private func stopHolderTimer() {
        holderTimer?.invalidate()
        holderTimer = nil
    }

    /// 預かっているクリックを返し、預かるのをやめる（ボタンがもう離れていれば離すも送る）
    private func returnHeldClick() {
        if case .giveBack(let withUp) = holder.returnAll(isPressed: physicalButton(0)) {
            giveBackHeldClick(withUp: withUp)
        }
        heldDown = nil
        stopHolderTimer()
    }

    /// 預かった押下を前面アプリに返す。current があれば続けてその写しを、なければ withUp のとき離すを送る。
    /// 送るイベントには Nonet の印を付ける（このタップを素通りさせる）
    private func giveBackHeldClick(withUp: Bool, current: CGEvent? = nil) {
        guard let down = heldDown else { return }
        heldDown = nil
        post(down)
        if let current, let copy = current.copy() {
            post(copy)
        } else if withUp, let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: down.location, mouseButton: .left) {
            post(up)
        }
    }

    private func post(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: OwnEventFilter.userData)
        postEvent(event)
    }

    // MARK: カーソル

    /// いまのカーソルの位置を覚える。次の抑止の始まりでそこへ戻す（CursorLockMethod が none 以外のとき）
    public func rememberPointerLocation() {
        rememberedLocation = cursor.location
    }

    private func beginSuppression() {
        didInterruptForOtherDevice = false
        keys.sessionBegan()
        let plan = CursorLockPlan(cursorLock)
        activePlan = plan
        // 開く動きで指を滑らせた分だけカーソルが動いているので、触れ始めた位置に戻してからそこで止める
        if plan.restoresTouchStart, let remembered = rememberedLocation {
            cursor.warp(to: remembered)
        }
        rememberedLocation = nil
        anchor = cursor.location
        if plan.decouples { association.decouple() }
        suppressor.suppressionBegan()
        updateKeyboardTap()
        updatePointerTap()
    }

    /// いまのポインタの位置（主画面の左上が原点）
    public var pointerLocation: CGPoint? { cursor.location }

    /// 抑止中に、ポインタを point へ動かす（開いたときに一度だけ、地図の奥の帯の中央へ）。ずれたら戻す方式なら、戻す先もそこにする
    public func movePointer(to point: CGPoint) {
        guard isSuppressingPointer else { return }
        anchor = point
        cursor.warp(to: point)
    }

    private func endSuppression() {
        if activePlan?.warpsBack == true {
            holdCursorAtAnchor()
        }
        association.restore()
        activePlan = nil
        anchor = nil
        suppressor.suppressionEnded(at: now(), dropsLateClicks: endsWithClickGrace)
        updateKeyboardTap()
        updatePointerTap()
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
        // ワープの直後はしばらく移動が止まる。結び付け直すと止まらない（ワープするのは、開いたときに HUD の中心へ動かす（movePointer）のと、
        // none 以外の方式の戻し。切り離す decouple の方式では、これで結び付きが戻ってしまうが、その方式は使っていない）
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

/// どちらのタップのコールバックか（tapDisabled* を見分ける）
enum EventTapRole {
    case keyboard
    case pointer
    case click
}

/// コールバックからモニタを引くための箱。タップが持ち、モニタは弱参照
final class EventTapBox {
    weak var monitor: EventTapKeyboardMonitor?
    let role: EventTapRole

    init(monitor: EventTapKeyboardMonitor, role: EventTapRole) {
        self.monitor = monitor
        self.role = role
    }
}

/// CGEventTap と run loop source の持ち主。解放されるときに必ず外す
final class EventTapConnection {
    private let tap: CFMachPort
    private let source: CFRunLoopSource
    private let box: Unmanaged<EventTapBox>
    private var isValid = true
    let levelName: String

    /// HID レベルで作れなければセッションレベルで作る。どちらも作れなければ nil。
    /// enabled が false なら、無効のまま run loop に置く（setEnabled で有効にする）
    init?(box: EventTapBox, events: CGEventMask, enabled: Bool) {
        let retained = Unmanaged.passRetained(box)
        let levels: [(CGEventTapLocation, String)] = [(.cghidEventTap, "HID"), (.cgSessionEventTap, "セッション")]
        for (location, name) in levels {
            guard let tap = CGEvent.tapCreate(
                tap: location,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: events,
                callback: eventTapCallback,
                userInfo: retained.toOpaque()
            ) else { continue }
            // 作った直後は有効。run loop に置くまでの間にイベントを待たせないよう、先に決める
            CGEvent.tapEnable(tap: tap, enable: enabled)
            guard let source = CFMachPortCreateRunLoopSource(nil, tap, 0) else {
                CFMachPortInvalidate(tap)
                continue
            }
            // メニューを開いている間（イベントトラッキング中）も動くように common モードに置く
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            self.tap = tap
            self.source = source
            self.box = retained
            levelName = name
            return
        }
        retained.release()
        return nil
    }

    func setEnabled(_ enabled: Bool) {
        guard isValid else { return }
        CGEvent.tapEnable(tap: tap, enable: enabled)
    }

    /// 外していなくて、システムにも無効にされていない
    var isAlive: Bool {
        isValid && CFMachPortIsValid(tap)
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
        box.monitor?.handle(type: type, event: event, from: box.role) ?? true
    }
    return pass ? Unmanaged.passUnretained(event) : nil
}
