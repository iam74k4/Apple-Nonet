import CoreGraphics
import Foundation
import NonetCore
import Testing
@testable import NonetPlatform

/// カーソルを実際には動かさない偽物
final class FakeCursor: CursorControlling {
    var location: CGPoint? = CGPoint(x: 100, y: 100)
    private(set) var warps: [CGPoint] = []
    private(set) var associations: [Bool] = []

    func warp(to point: CGPoint) {
        warps.append(point)
        location = point
    }

    func setAssociated(_ associated: Bool) {
        associations.append(associated)
    }
}

/// イベントタップは作らず、合成したイベントを handle に直接渡す
@MainActor
@Suite struct InputKeyboardMonitorTests {
    final class Physical {
        var pressedButtons: Set<Int64> = []
    }

    /// 手で進める単調な時計
    final class Clock {
        var now: TimeInterval = 1000
    }

    /// テストのプロセスが作ったイベントは送り元がこのプロセスになるので、Nonet 自身の pid は別の値にしておく
    static let fakeOwnPID: Int64 = 999_999

    let cursor = FakeCursor()
    let physical = Physical()
    let clock = Clock()
    let monitor: EventTapKeyboardMonitor
    let recorder = Recorder()

    @MainActor
    final class Recorder {
        var events: [KeyboardEvent] = []
        /// セッションを終えるときに、エンジンが遅れて届くクリックを捨てるよう頼むか（終わる直前に指が離れた）
        var dropsLateClicks = false
    }

    init() {
        let physical = physical
        let clock = clock
        monitor = EventTapKeyboardMonitor(
            cursor: cursor,
            physicalButton: { physical.pressedButtons.contains($0) },
            isAccessibilityTrusted: { false },
            ownProcessID: Self.fakeOwnPID,
            now: { clock.now }
        )
        let recorder = recorder
        let monitor = monitor
        // エンジンと同じく、キーやマウスで中断されたら抑止をやめる
        monitor.onEvent = { event in
            recorder.events.append(event)
            monitor.endPointerSuppression(dropsLateClicks: recorder.dropsLateClicks)
        }
    }

    // MARK: イベントを作る

    private func flagsEvent(keyCode: Int64, flags: CGEventFlags) throws -> CGEvent {
        let event = try #require(CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: true))
        event.type = .flagsChanged
        event.flags = flags
        return event
    }

    private func mouse(_ type: CGEventType, button: CGMouseButton = .left, at point: CGPoint = CGPoint(x: 10, y: 10)) throws -> CGEvent {
        try #require(CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: button))
    }

    /// 種類に合ったタップから届いたことにする
    @discardableResult
    private func send(_ type: CGEventType, _ event: CGEvent) -> Bool {
        let role: EventTapRole = PointerEventKind.isPointer(type.rawValue) ? .pointer : .keyboard
        return monitor.handle(type: type, event: event, from: role)
    }

    /// 9マスを開いた（コントローラーがエンジンの beginPointerSuppression で抑止を始める）
    private func open() {
        monitor.isSuppressingPointer = true
    }

    /// 指を離して閉じた（エンジンの endPointerSuppression）
    private func close() {
        monitor.endPointerSuppression(dropsLateClicks: recorder.dropsLateClicks)
    }

    private func keyDown() throws -> CGEvent {
        try #require(CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: true))
    }

    /// 抑止の直後にクリックを捨てる間を過ぎるまで時計を進め、タイマーの代わりに確かめ直させる
    private func passClickGrace() {
        clock.now += PointerSuppressor.clickGraceInterval
        monitor.clickGraceDidEnd()
    }

    // MARK: キーボード（開いている間だけ）

    /// どれかのボタンが物理的に押されているか（9マスを開く前に確かめる）
    @Test func reportsWhetherAnyMouseButtonIsPhysicallyDown() {
        #expect(!monitor.isMouseButtonDown)
        physical.pressedButtons = [0]
        #expect(monitor.isMouseButtonDown)
        physical.pressedButtons = [4]
        #expect(monitor.isMouseButtonDown)
        physical.pressedButtons = []
        #expect(!monitor.isMouseButtonDown)
    }

    /// キーボードのタップは開いている間だけ有効にする（開いていない間はキーボードを見ない）
    @Test func theKeyboardTapIsEnabledOnlyWhileOpen() {
        #expect(!monitor.isKeyboardTapEnabled)
        open()
        #expect(monitor.isKeyboardTapEnabled)
        close()
        #expect(!monitor.isKeyboardTapEnabled)
        open()
        monitor.stop()
        #expect(!monitor.isKeyboardTapEnabled)
    }

    /// 開いている間にキーを押したら閉じる（.interrupted を1回）。キーは前面アプリに渡す
    @Test func aKeyWhileOpenInterruptsAndPasses() throws {
        open()
        #expect(send(.keyDown, try keyDown()))
        #expect(recorder.events == [.interrupted])
        #expect(!monitor.isSuppressingPointer)
        #expect(send(.keyDown, try keyDown()))
        #expect(recorder.events == [.interrupted])
    }

    /// 開いていない間のキーは何も知らせない（タップは止めてあるが、届いても渡すだけ）
    @Test func keysOutsideASessionAreIgnored() throws {
        #expect(send(.keyDown, try keyDown()))
        #expect(send(.flagsChanged, try flagsEvent(keyCode: 55, flags: inputFlags(.maskCommand, device: DeviceModifierMask.leftCommand))))
        #expect(recorder.events.isEmpty)
    }

    /// 修飾キーを押しても閉じる。開く前から押していた修飾キーを離しただけでは閉じない
    @Test func modifiersWhileOpen() throws {
        open()
        #expect(send(.flagsChanged, try flagsEvent(keyCode: 56, flags: inputFlags())))
        #expect(recorder.events.isEmpty)
        #expect(send(.flagsChanged, try flagsEvent(keyCode: 54, flags: inputFlags(.maskCommand, device: DeviceModifierMask.rightCommand))))
        #expect(recorder.events == [.interrupted])
    }

    /// 次に開いたときも、キーでまた閉じる
    @Test func everySessionCanBeInterruptedOnce() throws {
        open()
        _ = send(.keyDown, try keyDown())
        open()
        _ = send(.keyDown, try keyDown())
        #expect(recorder.events == [.interrupted, .interrupted])
    }

    @Test func tapDisabledWithoutConnectionPasses() throws {
        let event = try #require(CGEvent(source: nil))
        #expect(send(.tapDisabledByTimeout, event))
        #expect(send(.tapDisabledByUserInput, event))
        #expect(recorder.events.isEmpty)
    }

    // MARK: ポインタを触れ始めた位置に戻す

    /// 指が上の縁で触れ始めたときの位置を覚え、開いたらそこへ戻してから止める（開く動きでポインタが少し動くため）
    @Test func openingRestoresThePointerToWhereTheTouchBegan() throws {
        monitor.cursorLock = .automatic
        cursor.location = CGPoint(x: 300, y: 200)
        monitor.rememberPointerLocation()
        // 開く動きの間に、ポインタが少し下へ動いた
        cursor.location = CGPoint(x: 300, y: 230)
        open()
        #expect(cursor.warps == [CGPoint(x: 300, y: 200)])
        #expect(monitor.rememberedLocation == nil)
        // その位置で止める（ずれたら戻す）
        cursor.location = CGPoint(x: 310, y: 200)
        #expect(!send(.mouseMoved, try mouse(.mouseMoved)))
        #expect(cursor.warps.last == CGPoint(x: 300, y: 200))
    }

    /// 開いている間、ポインタは指の位置へ動いてそこで止まり、閉じたら動かす前の位置に戻る
    @Test func aMovedPointerStaysThereAndReturnsWhenClosed() throws {
        monitor.cursorLock = .automatic
        cursor.location = CGPoint(x: 300, y: 200)
        monitor.movePointer(to: CGPoint(x: 1, y: 1))
        // 開いていないときは動かさない
        #expect(cursor.warps.isEmpty)
        open()
        monitor.movePointer(to: CGPoint(x: 300, y: 600))
        #expect(cursor.warps == [CGPoint(x: 300, y: 600)])
        // 動かした先で止める（ずれたら動かした先へ戻す）
        cursor.location = CGPoint(x: 310, y: 600)
        #expect(!send(.mouseMoved, try mouse(.mouseMoved)))
        #expect(cursor.warps.last == CGPoint(x: 300, y: 600))
        // もう一度動かしても、閉じたら最初の位置に戻す
        monitor.movePointer(to: CGPoint(x: 300, y: 650))
        close()
        #expect(cursor.warps.last == CGPoint(x: 300, y: 200))
        // 次に開いたときは、前の動かす前の位置を引きずらない
        cursor.location = CGPoint(x: 50, y: 50)
        open()
        close()
        #expect(cursor.warps.last == CGPoint(x: 300, y: 200))
    }

    /// ずれたら戻す方式でなければ、ポインタを動かさない
    @Test func otherLockMethodsNeverMoveThePointer() {
        monitor.cursorLock = .dropEvents
        open()
        monitor.movePointer(to: CGPoint(x: 300, y: 600))
        close()
        #expect(cursor.warps.isEmpty)
    }

    /// 覚えた位置は1回だけ使う。覚えていなければ戻さない
    @Test func theRememberedLocationIsUsedOnce() {
        monitor.cursorLock = .dropEvents
        monitor.rememberPointerLocation()
        open()
        close()
        #expect(cursor.warps == [CGPoint(x: 100, y: 100)])
        open()
        #expect(cursor.warps.count == 1)
    }

    /// 「固定しない」なら戻さない。「切り離す」でも戻してから切り離す
    @Test func onlyLockingMethodsRestoreThePointer() {
        monitor.cursorLock = .none
        monitor.rememberPointerLocation()
        cursor.location = CGPoint(x: 1, y: 1)
        open()
        #expect(cursor.warps.isEmpty)
        close()
        monitor.cursorLock = .decouple
        monitor.rememberPointerLocation()
        cursor.location = CGPoint(x: 2, y: 2)
        open()
        #expect(cursor.warps == [CGPoint(x: 1, y: 1)])
        #expect(cursor.associations == [false])
        #expect(CursorLockPlan(.none).restoresTouchStart == false)
        #expect(CursorLockPlan(.automatic).restoresTouchStart)
    }

    // MARK: Nonet 自身が送ったキー

    private func ownKeyDown(_ keyCode: CGKeyCode = 8) throws -> CGEvent {
        let event = try #require(CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true))
        event.flags = inputFlags(.maskCommand)
        event.setIntegerValueField(.eventSourceUserData, value: OwnEventFilter.userData)
        return event
    }

    /// キー入力のアクションが送ったキーは、押したキーとして数えない（Nonet 自身が送ったキーで閉じない）
    @Test func ownKeystrokesDoNotInterrupt() throws {
        open()
        #expect(send(.keyDown, try ownKeyDown()))
        #expect(send(.keyDown, try ownKeyDown(9)))
        let ownShift = try flagsEvent(keyCode: 56, flags: inputFlags([.maskCommand, .maskShift], device: DeviceModifierMask.leftShift))
        ownShift.setIntegerValueField(.eventSourceUserData, value: OwnEventFilter.userData)
        #expect(send(.flagsChanged, ownShift))
        #expect(recorder.events.isEmpty)
        #expect(monitor.isSuppressingPointer)
        // 本物のキーは中断にする
        #expect(send(.keyDown, try keyDown()))
        #expect(recorder.events == [.interrupted])
    }

    @Test func eventsFromThisProcessAreIgnoredEvenWithoutTheMarker() throws {
        let recorder = Recorder()
        let monitor = EventTapKeyboardMonitor(
            cursor: FakeCursor(),
            physicalButton: { _ in false },
            isAccessibilityTrusted: { false },
            ownProcessID: Int64(getpid())
        )
        monitor.onEvent = { recorder.events.append($0) }
        monitor.isSuppressingPointer = true
        // このプロセスが作ったイベント（印なし）
        let own = try #require(CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: true))
        #expect(own.getIntegerValueField(.eventSourceUnixProcessID) == Int64(getpid()))
        #expect(monitor.handle(type: .keyDown, event: own, from: .keyboard))
        #expect(recorder.events.isEmpty)
        // 本物のキーボードのイベントは送り元のプロセスが別
        let press = try #require(CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: true))
        press.setIntegerValueField(.eventSourceUnixProcessID, value: 0)
        #expect(monitor.handle(type: .keyDown, event: press, from: .keyboard))
        #expect(recorder.events == [.interrupted])
        monitor.stop()
    }

    @Test func ownEventFilterMatchesThePIDOrTheMarker() {
        #expect(OwnEventFilter.userData == 0x4E6F6E6574)
        #expect(OwnEventFilter.isOwn(sourcePID: 42, userData: 0, ownPID: 42))
        #expect(OwnEventFilter.isOwn(sourcePID: 7, userData: 0x4E6F6E6574, ownPID: 42))
        #expect(!OwnEventFilter.isOwn(sourcePID: 0, userData: 0, ownPID: 42))
        #expect(!OwnEventFilter.isOwn(sourcePID: 7, userData: 1, ownPID: 42))
    }

    // MARK: ポインタ

    @Test func dropsClicksDuringSessionAndTheirUpsAfterwards() throws {
        #expect(send(.leftMouseDown, try mouse(.leftMouseDown)))
        open()
        // セッションの前に押したボタンの離すは渡す
        #expect(send(.leftMouseUp, try mouse(.leftMouseUp)))
        #expect(!send(.rightMouseDown, try mouse(.rightMouseDown, button: .right)))
        #expect(!send(.scrollWheel, try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 3, wheel2: 0, wheel3: 0))))
        close()
        #expect(!send(.rightMouseUp, try mouse(.rightMouseUp, button: .right)))
        passClickGrace()
        #expect(send(.rightMouseDown, try mouse(.rightMouseDown, button: .right)))
    }

    @Test func dropsGestureEventsDuringSession() throws {
        let gesture = try #require(CGEvent(source: nil))
        let swipe = try #require(CGEventType(rawValue: 31))
        #expect(send(swipe, gesture))
        open()
        #expect(!send(swipe, gesture))
        #expect(!send(try #require(CGEventType(rawValue: 29)), gesture))
    }

    @Test func otherMouseButtonsArePairedByNumber() throws {
        open()
        let button3 = try #require(CGMouseButton(rawValue: 3))
        #expect(!send(.otherMouseDown, try mouse(.otherMouseDown, button: button3)))
        close()
        #expect(send(.otherMouseUp, try mouse(.otherMouseUp, button: .center)))
        #expect(!send(.otherMouseUp, try mouse(.otherMouseUp, button: button3)))
    }

    @Test func dragOfADroppedButtonIsPassedAsAMoveAfterSession() throws {
        open()
        _ = send(.leftMouseDown, try mouse(.leftMouseDown))
        close()
        let drag = try mouse(.leftMouseDragged)
        #expect(send(.leftMouseDragged, drag))
        #expect(drag.type == .mouseMoved)
    }

    @Test func nonPointerEventsPass() throws {
        open()
        let event = try #require(CGEvent(source: nil))
        #expect(send(try #require(CGEventType(rawValue: 14)), event))
    }

    // MARK: マウスとホイール

    /// トラックパッドに触れていない間の押す・移動・ホイールはマウスのもの: セッションを終えてもらい、そのまま渡す（⌘クリックなど）
    @Test(arguments: [CGEventType.leftMouseDown, .rightMouseDown, .mouseMoved, .leftMouseDragged])
    func aMouseEventWithoutATrackpadTouchEndsTheSessionAndPasses(_ type: CGEventType) throws {
        monitor.isTrackpadTouched = false
        clock.now += TrackpadContact.releaseGrace
        open()
        let button: CGMouseButton = type == .rightMouseDown ? .right : .left
        let event = try mouse(type, button: button)
        #expect(send(type, event))
        #expect(event.type == type)
        #expect(recorder.events == [.interrupted])
        #expect(!monitor.isSuppressingPointer)
        // その後のイベントもふつうに渡し、.interrupted は1回だけ
        #expect(send(.mouseMoved, try mouse(.mouseMoved)))
        #expect(recorder.events == [.interrupted])
    }

    @Test func aWheelScrollWithoutATrackpadTouchEndsTheSessionAndPasses() throws {
        monitor.isTrackpadTouched = false
        clock.now += TrackpadContact.releaseGrace
        open()
        #expect(send(.scrollWheel, try scroll(phase: 0, momentum: 0)))
        #expect(recorder.events == [.interrupted])
    }

    /// 指が触れている間は、トラックパッドのクリックや移動として捨てる（これまでどおり）
    @Test func pointerEventsWhileTheTrackpadIsTouchedAreStillDropped() throws {
        monitor.isTrackpadTouched = true
        open()
        #expect(!send(.leftMouseDown, try mouse(.leftMouseDown)))
        #expect(!send(.mouseMoved, try mouse(.mouseMoved)))
        #expect(recorder.events.isEmpty)
        #expect(monitor.isSuppressingPointer)
    }

    /// 指を離した直後に届く「タップでクリック」や慣性のスクロールは、トラックパッドのものとして捨てる
    @Test func eventsRightAfterTheFingerLiftsAreStillTheTrackpads() throws {
        monitor.isTrackpadTouched = true
        open()
        monitor.isTrackpadTouched = false
        clock.now += TrackpadContact.releaseGrace - 0.01
        #expect(!send(.leftMouseDown, try mouse(.leftMouseDown)))
        clock.now += 1
        // 慣性のスクロールは、離してから長く続いてもトラックパッドのもの
        #expect(!send(.scrollWheel, try scroll(phase: 0, momentum: 2)))
        #expect(recorder.events.isEmpty)
    }

    /// 触れているかを知らされていない（指の位置を読まない）間は見分けない
    @Test func withoutTouchInformationEveryPointerEventIsDropped() throws {
        open()
        #expect(!send(.leftMouseDown, try mouse(.leftMouseDown)))
        #expect(recorder.events.isEmpty)
    }

    @Test func trackpadContactDecidesByDeviceAndTime() {
        var contact = TrackpadContact()
        let click = PointerEventInfo(type: PointerEventKind.leftMouseDown)
        #expect(!contact.isFromAnotherDevice(click, now: 10))
        contact.update(isTouched: false, at: 10)
        #expect(contact.isFromAnotherDevice(click, now: 10))
        contact.update(isTouched: true, at: 11)
        #expect(!contact.isFromAnotherDevice(click, now: 11))
        contact.update(isTouched: false, at: 12)
        #expect(!contact.isFromAnotherDevice(click, now: 12 + TrackpadContact.releaseGrace - 0.01))
        #expect(contact.isFromAnotherDevice(click, now: 12 + TrackpadContact.releaseGrace))
        // 離すと、ジェスチャーは見分けない
        #expect(!contact.isFromAnotherDevice(PointerEventInfo(type: PointerEventKind.leftMouseUp), now: 20))
        #expect(!contact.isFromAnotherDevice(PointerEventInfo(type: 31), now: 20))
        #expect(contact.isFromAnotherDevice(PointerEventInfo(type: PointerEventKind.scrollWheel, scrollPhase: 1), now: 20))
        #expect(!contact.isFromAnotherDevice(PointerEventInfo(type: PointerEventKind.scrollWheel, momentumPhase: 1), now: 20))
        #expect(contact.isFromAnotherDevice(PointerEventInfo(type: PointerEventKind.otherMouseDown, buttonNumber: 3), now: 20))
    }

    // MARK: ポインタのタップが無効にされたとき

    /// 自分で無効にした直後の tapDisabledByUserInput は取りこぼしではない。時間切れと、有効にしておくはずの間の無効化は取りこぼし
    @Test func onlyUnexpectedPointerTapDisablesAreTreatedAsMissedEvents() {
        #expect(PointerTapDisableResponse.response(to: .tapDisabledByUserInput, isPointerTapEnabled: false) == .ignore)
        #expect(PointerTapDisableResponse.response(to: .tapDisabledByUserInput, isPointerTapEnabled: true) == .recover)
        #expect(PointerTapDisableResponse.response(to: .tapDisabledByTimeout, isPointerTapEnabled: false) == .recover)
        #expect(PointerTapDisableResponse.response(to: .tapDisabledByTimeout, isPointerTapEnabled: true) == .recover)
    }

    /// セッションの後片付けを終えて自分で無効にした後に届く知らせでは、何もしない（有効にし直さず、見直しも始めない）
    @Test func ourOwnPointerTapDisableIsIgnored() throws {
        recorder.dropsLateClicks = true
        open()
        close()
        passClickGrace()
        #expect(!monitor.isPointerTapEnabled)
        #expect(monitor.handle(type: .tapDisabledByUserInput, event: try #require(CGEvent(source: nil)), from: .pointer))
        #expect(!monitor.isPointerTapEnabled)
        #expect(!monitor.isSweeping)
    }

    // MARK: ポインタのタップ

    private func scroll(phase: Int64, momentum: Int64) throws -> CGEvent {
        let event = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 3, wheel2: 0, wheel3: 0))
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
        return event
    }

    @Test func pointerTapIsEnabledOnlyDuringSuppressionAndTheClickGrace() throws {
        recorder.dropsLateClicks = true
        #expect(!monitor.isPointerTapEnabled)
        open()
        #expect(monitor.isPointerTapEnabled)
        #expect(!monitor.isSweeping)
        #expect(!monitor.isWaitingForClickGrace)
        close()
        // 遅れて届くクリックを捨てる間だけ残す
        #expect(monitor.isPointerTapEnabled)
        #expect(monitor.isWaitingForClickGrace)
        passClickGrace()
        #expect(!monitor.isPointerTapEnabled)
        #expect(!monitor.isSweeping)
        #expect(!monitor.isWaitingForClickGrace)
        // 中断で抑止が終わっても止める
        open()
        monitor.isSuppressingPointer = false
        #expect(!monitor.isPointerTapEnabled)
        #expect(!monitor.isWaitingForClickGrace)
    }

    @Test func aClickRightAfterASessionWithoutARecentLiftPasses() throws {
        // 指が触れ始めてから長く経ったセッションをキーで閉じた（エンジンは遅れて届くクリックを捨てるよう頼まない）
        recorder.dropsLateClicks = false
        open()
        #expect(send(.keyDown, try keyDown()))
        #expect(!monitor.isPointerTapEnabled)
        #expect(!monitor.isWaitingForClickGrace)
        clock.now += 0.03
        #expect(send(.leftMouseDown, try mouse(.leftMouseDown)))
        #expect(send(.leftMouseUp, try mouse(.leftMouseUp)))
        open()
        close()
        #expect(!monitor.isPointerTapEnabled)
        clock.now += 0.03
        #expect(send(.rightMouseDown, try mouse(.rightMouseDown, button: .right)))
    }

    @Test func aTapToClickThatArrivesJustAfterTheSessionEndsIsDropped() throws {
        recorder.dropsLateClicks = true
        open()
        // セッションは指を離したフレームで終わり、そのタップが作ったクリックが後から届く
        close()
        clock.now += 0.03
        #expect(!send(.leftMouseDown, try mouse(.leftMouseDown)))
        clock.now += 0.01
        #expect(!send(.leftMouseUp, try mouse(.leftMouseUp)))
        // 移動は渡す
        #expect(send(.mouseMoved, try mouse(.mouseMoved)))
        passClickGrace()
        #expect(!monitor.isPointerTapEnabled)
        // その後のクリックは普通に通る
        #expect(send(.leftMouseDown, try mouse(.leftMouseDown)))
        #expect(send(.leftMouseUp, try mouse(.leftMouseUp)))
    }

    @Test func aClickWhoseUpComesAfterTheGraceKeepsTheTapUntilTheUp() throws {
        recorder.dropsLateClicks = true
        open()
        close()
        clock.now += 0.05
        #expect(!send(.leftMouseDown, try mouse(.leftMouseDown)))
        passClickGrace()
        #expect(monitor.isPointerTapEnabled)
        #expect(monitor.isSweeping)
        #expect(!send(.leftMouseUp, try mouse(.leftMouseUp)))
        #expect(!monitor.isPointerTapEnabled)
        #expect(!monitor.isSweeping)
    }

    @Test func aNewSessionDuringTheGraceStopsWaitingForIt() throws {
        recorder.dropsLateClicks = true
        open()
        close()
        #expect(monitor.isWaitingForClickGrace)
        open()
        #expect(!monitor.isWaitingForClickGrace)
        #expect(monitor.isPointerTapEnabled)
        #expect(!send(.leftMouseDown, try mouse(.leftMouseDown)))
    }

    @Test func pointerTapStaysUntilTheUpOfADroppedClick() throws {
        open()
        #expect(!send(.leftMouseDown, try mouse(.leftMouseDown)))
        close()
        // 捨てた押下の離すを捨てるまでは、タップを残す
        #expect(monitor.isPointerTapEnabled)
        #expect(monitor.isSweeping)
        let drag = try mouse(.leftMouseDragged)
        #expect(send(.leftMouseDragged, drag))
        #expect(drag.type == .mouseMoved)
        #expect(monitor.isPointerTapEnabled)
        passClickGrace()
        #expect(monitor.isPointerTapEnabled)
        #expect(!send(.leftMouseUp, try mouse(.leftMouseUp)))
        #expect(!monitor.isPointerTapEnabled)
        #expect(!monitor.isSweeping)
    }

    @Test func pointerTapStaysUntilTheScrollMomentumEnds() throws {
        open()
        #expect(!send(.scrollWheel, try scroll(phase: 1, momentum: 0)))
        close()
        passClickGrace()
        #expect(monitor.isPointerTapEnabled)
        #expect(!send(.scrollWheel, try scroll(phase: 4, momentum: 0)))
        #expect(!send(.scrollWheel, try scroll(phase: 0, momentum: 1)))
        #expect(monitor.isPointerTapEnabled)
        #expect(!send(.scrollWheel, try scroll(phase: 0, momentum: 3)))
        #expect(!monitor.isPointerTapEnabled)
    }

    @Test func sweepEndsAScrollTailThatNeverGetsAnEnd() throws {
        open()
        // 2本指のスワイプ（ページ送り）。慣性なしで指を離したので、終わりの印は来ない
        #expect(!send(.scrollWheel, try scroll(phase: 1, momentum: 0)))
        close()
        #expect(!send(.scrollWheel, try scroll(phase: 4, momentum: 0)))
        passClickGrace()
        monitor.sweepPointerState()
        #expect(monitor.isPointerTapEnabled)
        monitor.sweepPointerState()
        #expect(!monitor.isPointerTapEnabled)
        #expect(!monitor.isSweeping)
        #expect(send(.scrollWheel, try scroll(phase: 2, momentum: 0)))
    }

    @Test func sweepForgetsAClickWhoseUpWasLostWhileThePointerTapWasDisabled() throws {
        open()
        physical.pressedButtons = [0, 1]
        #expect(!send(.leftMouseDown, try mouse(.leftMouseDown)))
        #expect(!send(.rightMouseDown, try mouse(.rightMouseDown, button: .right)))
        let disabled = try #require(CGEvent(source: nil))
        #expect(monitor.handle(type: .tapDisabledByTimeout, event: disabled, from: .pointer))
        // 無効だった間に左を離した（離すイベントは届かない）。右はまだ押している
        physical.pressedButtons = [1]
        close()
        passClickGrace()
        #expect(monitor.isPointerTapEnabled)
        monitor.sweepPointerState()
        #expect(monitor.isPointerTapEnabled)
        // 右の離すは届くので、いつもどおり捨てて、タップを止める
        physical.pressedButtons = []
        #expect(!send(.rightMouseUp, try mouse(.rightMouseUp, button: .right)))
        #expect(!monitor.isPointerTapEnabled)
        #expect(send(.leftMouseUp, try mouse(.leftMouseUp)))
    }

    @Test func sweepKeepsARecentlyDroppedClickWhenNoEventsCanHaveBeenLost() throws {
        open()
        #expect(!send(.leftMouseDown, try mouse(.leftMouseDown)))
        close()
        passClickGrace()
        // 物理的な状態が離れて見えても、タップが無効にされていなければ離すイベントはこれから届くはず
        physical.pressedButtons = []
        monitor.sweepPointerState()
        monitor.sweepPointerState()
        #expect(monitor.isPointerTapEnabled)
        #expect(!send(.leftMouseUp, try mouse(.leftMouseUp)))
        #expect(!monitor.isPointerTapEnabled)
    }

    @Test func sweepEventuallyForgetsADroppedClickWhoseUpNeverComes() throws {
        open()
        #expect(!send(.rightMouseDown, try mouse(.rightMouseDown, button: .right)))
        close()
        passClickGrace()
        // 離すが届かないまま（デバイスが外れた など）、ボタンは物理的に離れている
        physical.pressedButtons = []
        let dropped = clock.now - PointerSuppressor.clickGraceInterval
        // 捨ててから staleButtonAge が経つまでは待つ
        while clock.now + EventTapKeyboardMonitor.sweepInterval - dropped < PointerSuppressor.staleButtonAge {
            clock.now += EventTapKeyboardMonitor.sweepInterval
            monitor.sweepPointerState()
            #expect(monitor.isPointerTapEnabled)
        }
        clock.now += EventTapKeyboardMonitor.sweepInterval
        monitor.sweepPointerState()
        #expect(!monitor.isPointerTapEnabled)
        #expect(!monitor.isSweeping)
    }

    @Test func stopDisablesThePointerTap() throws {
        open()
        _ = send(.leftMouseDown, try mouse(.leftMouseDown))
        monitor.stop()
        #expect(!monitor.isPointerTapEnabled)
        #expect(!monitor.isSweeping)
    }

    // MARK: カーソルの固定

    @Test func automaticDropsMovesAndWarpsBackOnlyWhenTheCursorMoved() throws {
        monitor.cursorLock = .automatic
        let anchor = try #require(cursor.location)
        open()
        #expect(!send(.mouseMoved, try mouse(.mouseMoved)))
        #expect(cursor.warps.isEmpty)
        cursor.location = CGPoint(x: anchor.x + 8, y: anchor.y)
        #expect(!send(.mouseMoved, try mouse(.mouseMoved)))
        #expect(cursor.warps == [anchor])
        cursor.location = CGPoint(x: anchor.x, y: anchor.y - 3)
        close()
        #expect(cursor.warps == [anchor, anchor])
        #expect(cursor.associations.isEmpty)
    }

    @Test func dropEventsNeverWarps() throws {
        monitor.cursorLock = .dropEvents
        open()
        cursor.location = CGPoint(x: 500, y: 500)
        #expect(!send(.mouseMoved, try mouse(.mouseMoved)))
        #expect(!send(.leftMouseDragged, try mouse(.leftMouseDragged)))
        close()
        #expect(cursor.warps.isEmpty)
    }

    @Test func decoupleRestoresTheAssociationWhenSuppressionEnds() throws {
        monitor.cursorLock = .decouple
        open()
        #expect(cursor.associations == [false])
        #expect(!send(.mouseMoved, try mouse(.mouseMoved)))
        // 途中で設定を変えても、始めたときの方式で戻す
        monitor.cursorLock = .none
        close()
        #expect(cursor.associations == [false, true])
        #expect(cursor.warps.isEmpty)
    }

    @Test func noneLetsTheCursorMove() throws {
        monitor.cursorLock = .none
        open()
        #expect(send(.mouseMoved, try mouse(.mouseMoved)))
        #expect(!send(.leftMouseDown, try mouse(.leftMouseDown)))
        #expect(cursor.associations.isEmpty)
    }

    @Test func stopRestoresTheCursorAndEndsSuppression() throws {
        monitor.cursorLock = .decouple
        open()
        monitor.stop()
        #expect(!monitor.isSuppressingPointer)
        #expect(cursor.associations == [false, true])
        #expect(!monitor.isRunning)
        // 止めた後のキーは何も知らせない
        #expect(send(.keyDown, try keyDown()))
        #expect(recorder.events.isEmpty)
    }

    @Test func releasingTheMonitorRestoresTheCursor() {
        let cursor = FakeCursor()
        do {
            let monitor = EventTapKeyboardMonitor(
                cursor: cursor,
                physicalButton: { _ in false },
                isAccessibilityTrusted: { false },
                ownProcessID: Self.fakeOwnPID
            )
            monitor.cursorLock = .decouple
            monitor.isSuppressingPointer = true
            #expect(cursor.associations == [false])
        }
        #expect(cursor.associations == [false, true])
    }

    // MARK: 開始

    @Test func startThrowsWithoutAccessibility() {
        #expect(throws: NonetError.permissionDenied(InputText.accessibility)) {
            try monitor.start()
        }
        #expect(!monitor.isRunning)
        monitor.stop()
    }

    @Test func keyboardAndPointerEventsGoToSeparateTaps() {
        let keyboard = EventTapMask.keyboard
        let pointer = EventTapMask.pointer
        #expect(EventTapMask.contains(keyboard, CGEventType.keyDown.rawValue))
        #expect(EventTapMask.contains(keyboard, CGEventType.flagsChanged.rawValue))
        #expect(!EventTapMask.contains(keyboard, CGEventType.keyUp.rawValue))
        #expect(!EventTapMask.contains(pointer, CGEventType.keyDown.rawValue))
        #expect(!EventTapMask.contains(pointer, CGEventType.flagsChanged.rawValue))
        // 開いている間だけ有効にするキーボードのタップは、ポインタのイベントを受け取らない
        for type in UInt32(0)..<64 {
            #expect(EventTapMask.contains(keyboard, type) == [CGEventType.keyDown.rawValue, CGEventType.flagsChanged.rawValue].contains(type), "type \(type)")
            #expect(EventTapMask.contains(pointer, type) == PointerEventKind.all.contains(type), "type \(type)")
        }
    }
}
