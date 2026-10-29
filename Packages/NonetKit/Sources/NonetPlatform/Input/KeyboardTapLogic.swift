// 担当: platform-input
// イベントタップの判断（トリガーの検出・中断・ポインタの抑止）。CGEvent に触れず、テストできるようにしてある
import CoreGraphics
import NonetCore

/// CGEventFlags のうち、左右を区別するビット（IOLLEvent.h の NX_DEVICE*KEYMASK）
enum DeviceModifierMask {
    static let leftControl: UInt64 = 0x0001
    static let leftShift: UInt64 = 0x0002
    static let rightShift: UInt64 = 0x0004
    static let leftCommand: UInt64 = 0x0008
    static let rightCommand: UInt64 = 0x0010
    static let leftOption: UInt64 = 0x0020
    static let rightOption: UInt64 = 0x0040
    static let rightControl: UInt64 = 0x2000
}

extension TriggerKey {
    /// flagsChanged の仮想キーコード
    var keyCode: Int64 {
        switch self {
        case .rightCommand: 54
        case .rightOption: 61
        case .rightShift: 60
        case .function: 63
        }
    }

    /// 左右の区別が無い修飾キーのフラグ
    var modifierFlag: CGEventFlags {
        switch self {
        case .rightCommand: .maskCommand
        case .rightOption: .maskAlternate
        case .rightShift: .maskShift
        case .function: .maskSecondaryFn
        }
    }

    /// 右側のキーのビット。fn には左右が無い
    var deviceMask: UInt64? {
        switch self {
        case .rightCommand: DeviceModifierMask.rightCommand
        case .rightOption: DeviceModifierMask.rightOption
        case .rightShift: DeviceModifierMask.rightShift
        case .function: nil
        }
    }

    /// 同じ修飾キーの左側のビット
    var leftDeviceMask: UInt64? {
        switch self {
        case .rightCommand: DeviceModifierMask.leftCommand
        case .rightOption: DeviceModifierMask.leftOption
        case .rightShift: DeviceModifierMask.leftShift
        case .function: nil
        }
    }

    /// flags でこのキーが押されているか
    func isPressed(in flags: CGEventFlags) -> Bool {
        guard let right = deviceMask, let left = leftDeviceMask else {
            return flags.contains(modifierFlag)
        }
        if flags.rawValue & right != 0 { return true }
        if flags.rawValue & left != 0 { return false }
        // 左右のビットを付けないキーボードでは、左右の区別が無いフラグで判断する
        return flags.contains(modifierFlag)
    }

    /// トリガー以外の修飾キー（同じ修飾キーの左側を含む）が押されているか。Caps Lock は数えない
    func hasOtherModifiers(in flags: CGEventFlags) -> Bool {
        let modifiers: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand, .maskSecondaryFn]
        if !flags.intersection(modifiers).subtracting(modifierFlag).isEmpty { return true }
        if let left = leftDeviceMask, flags.rawValue & left != 0 { return true }
        return false
    }
}

/// トリガーキーの押下・解放と、押している間の中断を見分ける
struct TriggerDetector {
    struct Output: Equatable {
        var event: KeyboardEvent?
        /// false ならイベントを前面アプリに渡さない
        var pass: Bool

        static let passThrough = Output(event: nil, pass: true)
    }

    /// 押しているトリガー（押した時点の設定。押している間に設定が変わっても、離すまではこれで判断する）
    private(set) var heldTrigger: TriggerKey?
    /// 押している間にほかのキーが押された（.interrupted は1回だけ出す）
    private(set) var isInterrupted = false
    /// 押すイベントを捨てたトリガー。対になる離すイベントも捨てる
    private(set) var swallowedTrigger: TriggerKey?
    /// 捨てた押下が物理的な状態（hidSystemState）に反映されると確かめられた（実機では未確認）。
    /// 捨てて押している最中に押されて見えたら true にする。離れて見えたことからは決めない
    /// （その確認は、離すイベントを取りこぼした直後のことが多い）
    private(set) var swallowedStateIsReliable = false

    var isHeld: Bool { heldTrigger != nil }

    mutating func flagsChanged(keyCode: Int64, flags: CGEventFlags, trigger: TriggerKey, passTrigger: Bool) -> Output {
        if let held = heldTrigger {
            guard keyCode == held.keyCode else { return interrupt() }
            if held.isPressed(in: flags) {
                // 押したままの重複。渡すかどうかは押したときに合わせる
                return Output(event: nil, pass: swallowedTrigger != held)
            }
            endHold()
            let swallow = swallowedTrigger == held
            swallowedTrigger = nil
            return Output(event: .triggerUp, pass: !swallow)
        }

        if let swallowed = swallowedTrigger, keyCode == swallowed.keyCode {
            swallowedTrigger = nil
            // 安全装置で離したことにした後で届いた、捨てた押下と対になる離すイベント
            if !swallowed.isPressed(in: flags) { return Output(event: nil, pass: false) }
            // 新しい押下なら、前の対は終わっている
        }

        guard keyCode == trigger.keyCode, trigger.isPressed(in: flags), !trigger.hasOtherModifiers(in: flags) else {
            return .passThrough
        }
        heldTrigger = trigger
        isInterrupted = false
        swallowedTrigger = passTrigger ? nil : trigger
        return Output(event: .triggerDown, pass: passTrigger)
    }

    mutating func keyDown() -> Output {
        isHeld ? interrupt() : .passThrough
    }

    /// 物理的な状態と食い違っていたら（離すイベントを取りこぼしたら）離したことにする。
    /// tapWasDisabled: タップが無効にされていた直後（その間のイベントを取りこぼしたかもしれない）
    mutating func reconcile(physicalFlags: CGEventFlags, tapWasDisabled: Bool) -> KeyboardEvent? {
        guard let held = heldTrigger else { return nil }
        let pressed = held.isPressed(in: physicalFlags)
        if swallowedTrigger == held {
            if pressed { swallowedStateIsReliable = true }
            // 反映されると分かるまでは、離れて見えても信じない。ただしタップが無効にされていたなら、
            // 離すイベントを取りこぼした見込みが高いので終える（押したままだと思い込むより安全）
            guard swallowedStateIsReliable || tapWasDisabled else { return nil }
        }
        guard !pressed else { return nil }
        // 捨てた押下の対になる離すイベントが後から届いたら捨てられるよう、swallowedTrigger は残す
        endHold()
        return .triggerUp
    }

    mutating func reset() {
        endHold()
        swallowedTrigger = nil
    }

    private mutating func interrupt() -> Output {
        guard !isInterrupted else { return .passThrough }
        isInterrupted = true
        return Output(event: .interrupted, pass: true)
    }

    private mutating func endHold() {
        heldTrigger = nil
        isInterrupted = false
    }
}

/// Nonet 自身が送ったイベント（キー入力のアクションなど）。HID の位置に送るのでタップを通るが、
/// ユーザーが押したキーとして数えない
enum OwnEventFilter {
    /// Nonet が送るイベントの kCGEventSourceUserData（"Nonet" の ASCII）。
    /// platform-actions の SyntheticKeyEvent.userData と同じ値にする
    static let userData: Int64 = 0x4E_6F_6E_65_74

    static func isOwn(sourcePID: Int64, userData: Int64, ownPID: Int64) -> Bool {
        sourcePID == ownPID || userData == Self.userData
    }
}

/// タップごとに受け取るイベント。tapDisabled* はマスクに関係なく届く
enum EventTapMask {
    /// 動いている間ずっと受け取る
    static let keyboard = mask(of: [CGEventType.keyDown.rawValue, CGEventType.flagsChanged.rawValue])
    /// 抑止中とその後片付けの間だけ受け取る
    static let pointer = mask(of: PointerEventKind.all)

    static func mask(of types: some Sequence<UInt32>) -> CGEventMask {
        types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1)) }
    }

    static func contains(_ mask: CGEventMask, _ type: UInt32) -> Bool {
        mask & (CGEventMask(1) << CGEventMask(type)) != 0
    }
}

/// イベントの種類（rawValue）。CGEventType に無いジェスチャー系は NSEvent.EventType の値
enum PointerEventKind {
    static let leftMouseDown: UInt32 = 1
    static let leftMouseUp: UInt32 = 2
    static let rightMouseDown: UInt32 = 3
    static let rightMouseUp: UInt32 = 4
    static let mouseMoved: UInt32 = 5
    static let leftMouseDragged: UInt32 = 6
    static let rightMouseDragged: UInt32 = 7
    static let scrollWheel: UInt32 = 22
    static let otherMouseDown: UInt32 = 25
    static let otherMouseUp: UInt32 = 26
    static let otherMouseDragged: UInt32 = 27

    /// 回転・ジェスチャーの開始と終了・ジェスチャー・拡大縮小・スワイプ・スマートズーム・クイックルック・感圧・直接タッチ
    static let gestures: Set<UInt32> = [18, 19, 20, 29, 30, 31, 32, 33, 34, 37]

    /// 抑止の対象になるすべての種類
    static let all: Set<UInt32> = gestures.union([
        leftMouseDown, leftMouseUp, rightMouseDown, rightMouseUp, mouseMoved, leftMouseDragged, rightMouseDragged,
        scrollWheel, otherMouseDown, otherMouseUp, otherMouseDragged,
    ])

    static func isPointer(_ type: UInt32) -> Bool { all.contains(type) }

    /// ボタン番号を読む必要があるか（other のボタンだけ）
    static func needsButtonNumber(_ type: UInt32) -> Bool {
        type == otherMouseDown || type == otherMouseUp || type == otherMouseDragged
    }

    static func downButton(_ type: UInt32, buttonNumber: Int64) -> Int64? {
        switch type {
        case leftMouseDown: 0
        case rightMouseDown: 1
        case otherMouseDown: buttonNumber
        default: nil
        }
    }

    static func upButton(_ type: UInt32, buttonNumber: Int64) -> Int64? {
        switch type {
        case leftMouseUp: 0
        case rightMouseUp: 1
        case otherMouseUp: buttonNumber
        default: nil
        }
    }

    static func dragButton(_ type: UInt32, buttonNumber: Int64) -> Int64? {
        switch type {
        case leftMouseDragged: 0
        case rightMouseDragged: 1
        case otherMouseDragged: buttonNumber
        default: nil
        }
    }

    /// カーソルを動かすイベント
    static func isMove(_ type: UInt32) -> Bool {
        type == mouseMoved || dragButton(type, buttonNumber: 0) != nil
    }
}

/// ポインタ系のイベント1つ分。読む値は種類によって違う
struct PointerEventInfo: Equatable {
    var type: UInt32
    /// other のボタンのとき
    var buttonNumber: Int64 = 0
    /// スクロールのとき（CGScrollPhase: 1 開始, 2 変化, 4 終了, 8 取り消し, 128 開始しそう）
    var scrollPhase: Int64 = 0
    /// スクロールのとき（CGMomentumScrollPhase: 0 なし, 1 開始, 2 継続, 3 終了）
    var momentumPhase: Int64 = 0
}

/// 抑止中のポインタ系イベントを捨てる。捨てた「押す」と対になる「離す」は、抑止が終わった後でも捨てる
struct PointerSuppressor {
    enum Decision: Equatable {
        case pass
        case drop
        /// 押すイベントを捨てたボタンのドラッグ。前面アプリにはボタンを押していない移動として渡す
        case passAsMove
    }

    private(set) var droppedButtons: Set<Int64> = []
    /// 抑止中に始まったスクロールの続き（慣性を含む）を捨てている
    private(set) var isDroppingScrollTail = false
    /// タップが無効にされていた間に、離すイベントを取りこぼしたかもしれない捨てたボタン
    private(set) var buttonsWithPossiblyMissedUp: Set<Int64> = []
    /// 前回の sweep から、スクロールのイベントが届いた
    private var sawScrollSinceSweep = false

    /// 抑止が終わっても、捨てた押下の離す・スクロールの続きを待っている
    var isTracking: Bool { !droppedButtons.isEmpty || isDroppingScrollTail }

    /// ポインタ系のイベントを見ている必要があるか（ポインタのタップを有効にしておくか）
    func needsEvents(suppressing: Bool) -> Bool { suppressing || isTracking }

    mutating func decide(_ event: PointerEventInfo, suppressing: Bool, dropsMoves: Bool) -> Decision {
        let type = event.type
        if let button = PointerEventKind.upButton(type, buttonNumber: event.buttonNumber) {
            buttonsWithPossiblyMissedUp.remove(button)
            // 押すイベントを渡したボタンの離すは、抑止中でも渡す（アプリのドラッグが終わらなくならないように）
            return droppedButtons.remove(button) == nil ? .pass : .drop
        }
        if let button = PointerEventKind.downButton(type, buttonNumber: event.buttonNumber) {
            buttonsWithPossiblyMissedUp.remove(button)
            guard suppressing else {
                // 新しい押下。離すを取りこぼして残っていても、前の対は終わっている
                droppedButtons.remove(button)
                return .pass
            }
            droppedButtons.insert(button)
            return .drop
        }
        if let button = PointerEventKind.dragButton(type, buttonNumber: event.buttonNumber) {
            if suppressing, dropsMoves { return .drop }
            return droppedButtons.contains(button) ? .passAsMove : .pass
        }
        if type == PointerEventKind.mouseMoved {
            return suppressing && dropsMoves ? .drop : .pass
        }
        if type == PointerEventKind.scrollWheel {
            return decideScroll(event, suppressing: suppressing)
        }
        return suppressing && PointerEventKind.gestures.contains(type) ? .drop : .pass
    }

    /// ポインタのタップが無効にされた。その間の離すイベントは届いていないかもしれない
    mutating func eventsMayHaveBeenMissed() {
        buttonsWithPossiblyMissedUp.formUnion(droppedButtons)
    }

    /// 抑止が終わった後、ポインタのタップを残している間に定期的に呼ぶ。もう届かないものを待つのをやめる。
    /// - 離すイベントを取りこぼしたかもしれないボタンは、物理的に離れていれば忘れる
    /// - 前回の sweep から1つも届いていないスクロールの続きは、終わったものとする
    ///   （慣性の無いスクロールは終わりの印が来ないので、次のスクロールまで待ち続けてしまう）
    mutating func sweep(isPhysicallyPressed: (Int64) -> Bool) {
        for button in buttonsWithPossiblyMissedUp where !isPhysicallyPressed(button) {
            droppedButtons.remove(button)
        }
        // まだ押されているボタンの離すは、有効なタップに届く
        buttonsWithPossiblyMissedUp = []
        if !sawScrollSinceSweep {
            isDroppingScrollTail = false
        }
        sawScrollSinceSweep = false
    }

    private mutating func decideScroll(_ event: PointerEventInfo, suppressing: Bool) -> Decision {
        sawScrollSinceSweep = true
        if suppressing {
            isDroppingScrollTail = true
            return .drop
        }
        guard isDroppingScrollTail else { return .pass }
        let beganNewGesture = event.scrollPhase == 1 || event.scrollPhase == 128
        let isWheel = event.scrollPhase == 0 && event.momentumPhase == 0
        if beganNewGesture || isWheel {
            isDroppingScrollTail = false
            return .pass
        }
        // 指を離した後に慣性が続くことがあるので、ジェスチャーの終了ではなく慣性の終了で区切る
        if event.momentumPhase == 3 {
            isDroppingScrollTail = false
        }
        return .drop
    }
}

/// CursorLockMethod ごとにすること
struct CursorLockPlan: Equatable {
    /// 移動・ドラッグのイベントを捨てる
    var dropsMoves: Bool
    /// それでもカーソルがずれたら、抑止を始めた位置に戻す
    var warpsBack: Bool
    /// カーソルとマウスの動きを切り離す
    var decouples: Bool

    init(dropsMoves: Bool, warpsBack: Bool, decouples: Bool) {
        self.dropsMoves = dropsMoves
        self.warpsBack = warpsBack
        self.decouples = decouples
    }

    init(_ method: CursorLockMethod) {
        switch method {
        case .automatic: self.init(dropsMoves: true, warpsBack: true, decouples: false)
        case .dropEvents: self.init(dropsMoves: true, warpsBack: false, decouples: false)
        case .decouple: self.init(dropsMoves: true, warpsBack: false, decouples: true)
        case .none: self.init(dropsMoves: false, warpsBack: false, decouples: false)
        }
    }

    /// これより大きくずれたら戻す（ポイント）
    static let warpThreshold: CGFloat = 0.5

    static func needsWarp(from anchor: CGPoint, to current: CGPoint) -> Bool {
        abs(current.x - anchor.x) > warpThreshold || abs(current.y - anchor.y) > warpThreshold
    }
}
