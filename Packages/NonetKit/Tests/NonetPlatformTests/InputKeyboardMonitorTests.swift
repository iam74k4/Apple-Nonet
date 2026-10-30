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
        var flags = inputFlags()
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
            physicalFlags: { physical.flags },
            physicalButton: { physical.pressedButtons.contains($0) },
            isAccessibilityTrusted: { false },
            ownProcessID: Self.fakeOwnPID,
            now: { clock.now }
        )
        monitor.trigger = .rightCommand
        let recorder = recorder
        let monitor = monitor
        // エンジンと同じく、トリガーを押したらすぐに抑止を始め、終わったら止める
        monitor.onEvent = { event in
            recorder.events.append(event)
            if event == .triggerDown {
                monitor.isSuppressingPointer = true
            } else {
                monitor.endPointerSuppression(dropsLateClicks: recorder.dropsLateClicks)
            }
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

    private func pressTrigger() throws -> Bool {
        send(.flagsChanged, try flagsEvent(keyCode: 54, flags: TriggerKey.rightCommand.pressedFlags))
    }

    private func releaseTrigger() throws -> Bool {
        send(.flagsChanged, try flagsEvent(keyCode: 54, flags: inputFlags()))
    }

    /// 抑止の直後にクリックを捨てる間を過ぎるまで時計を進め、タイマーの代わりに確かめ直させる
    private func passClickGrace() {
        clock.now += PointerSuppressor.clickGraceInterval
        monitor.clickGraceDidEnd()
    }

    // MARK: トリガー

    @Test func emitsTriggerEventsFromFlagsChanged() throws {
        #expect(try pressTrigger())
        #expect(recorder.events == [.triggerDown])
        #expect(monitor.isSuppressingPointer)
        #expect(try releaseTrigger())
        #expect(recorder.events == [.triggerDown, .triggerUp])
        #expect(!monitor.isSuppressingPointer)
    }

    @Test func swallowsTriggerWhenNotPassingToApps() throws {
        monitor.passTriggerToApps = false
        #expect(try !pressTrigger())
        #expect(try !releaseTrigger())
        #expect(recorder.events == [.triggerDown, .triggerUp])
    }

    @Test func keyDownWhileHeldInterruptsAndPasses() throws {
        _ = try pressTrigger()
        let key = try #require(CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: true))
        #expect(send(.keyDown, key))
        #expect(recorder.events == [.triggerDown, .interrupted])
    }

    @Test func reconcileEmitsTriggerUpWhenPhysicallyReleased() throws {
        _ = try pressTrigger()
        physical.flags = TriggerKey.rightCommand.pressedFlags
        monitor.reconcileTrigger()
        #expect(recorder.events == [.triggerDown])
        physical.flags = inputFlags()
        monitor.reconcileTrigger()
        #expect(recorder.events == [.triggerDown, .triggerUp])
        #expect(!monitor.isSuppressingPointer)
    }

    @Test func tapDisabledWithoutConnectionReconcilesAndPasses() throws {
        _ = try pressTrigger()
        let event = try #require(CGEvent(source: nil))
        #expect(send(.tapDisabledByTimeout, event))
        #expect(recorder.events == [.triggerDown, .triggerUp])
        #expect(send(.tapDisabledByUserInput, event))
    }

    @Test func swallowedTriggerWhoseUpWasLostWhileTheTapWasDisabledEnds() throws {
        monitor.passTriggerToApps = false
        #expect(try !pressTrigger())
        // メインスレッドが詰まっている間に右⌘を離し、タップが無効にされて離すイベントが届かなかった
        physical.flags = inputFlags()
        let disabled = try #require(CGEvent(source: nil))
        #expect(send(.tapDisabledByTimeout, disabled))
        #expect(recorder.events == [.triggerDown, .triggerUp])
        #expect(!monitor.isSuppressingPointer)
        // 次に押したら、押したままの重複ではなく新しい押下として扱う
        physical.flags = TriggerKey.rightCommand.pressedFlags
        #expect(try !pressTrigger())
        #expect(recorder.events == [.triggerDown, .triggerUp, .triggerDown])
        #expect(try !releaseTrigger())
        #expect(recorder.events == [.triggerDown, .triggerUp, .triggerDown, .triggerUp])
    }

    @Test func swallowedTriggerSurvivesWatchdogTicksBeforeTheHIDStateIsKnown() throws {
        monitor.passTriggerToApps = false
        _ = try pressTrigger()
        // 捨てた押下が物理的な状態に反映されるかは分からない。見張りの確認だけでは終えない
        physical.flags = inputFlags()
        monitor.reconcileTrigger()
        monitor.reconcileTrigger()
        #expect(recorder.events == [.triggerDown])
        #expect(monitor.isSuppressingPointer)
        #expect(try !releaseTrigger())
        #expect(recorder.events == [.triggerDown, .triggerUp])
    }

    @Test func pointerTapDisabledDoesNotReconcileTheTrigger() throws {
        _ = try pressTrigger()
        physical.flags = inputFlags()
        let disabled = try #require(CGEvent(source: nil))
        #expect(monitor.handle(type: .tapDisabledByTimeout, event: disabled, from: .pointer))
        #expect(recorder.events == [.triggerDown])
        #expect(monitor.isPointerTapEnabled)
    }

    // MARK: Nonet 自身が送ったキー

    private func ownKeyDown(_ keyCode: CGKeyCode = 8) throws -> CGEvent {
        let event = try #require(CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true))
        event.flags = inputFlags(.maskCommand)
        event.setIntegerValueField(.eventSourceUserData, value: OwnEventFilter.userData)
        return event
    }

    @Test func ownKeystrokesWhileHeldDoNotInterrupt() throws {
        _ = try pressTrigger()
        // キー入力のアクション（⌘C）を、トリガーを押したまま実行した
        #expect(send(.keyDown, try ownKeyDown()))
        #expect(send(.keyDown, try ownKeyDown(9)))
        #expect(recorder.events == [.triggerDown])
        #expect(monitor.isSuppressingPointer)
        // 続けて実行できるよう、セッションは続く。本物のキーは中断にする
        let key = try #require(CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: true))
        #expect(send(.keyDown, key))
        #expect(recorder.events == [.triggerDown, .interrupted])
    }

    @Test func ownModifierChangesDoNotTouchTheTriggerState() throws {
        _ = try pressTrigger()
        let ownShift = try flagsEvent(keyCode: 56, flags: inputFlags([.maskCommand, .maskShift], device: DeviceModifierMask.leftShift))
        ownShift.setIntegerValueField(.eventSourceUserData, value: OwnEventFilter.userData)
        #expect(send(.flagsChanged, ownShift))
        // トリガーと同じキーコードで離れたように見えても、自分のイベントなら離したことにしない
        let ownRelease = try flagsEvent(keyCode: 54, flags: inputFlags())
        ownRelease.setIntegerValueField(.eventSourceUserData, value: OwnEventFilter.userData)
        #expect(send(.flagsChanged, ownRelease))
        #expect(recorder.events == [.triggerDown])
        #expect(try releaseTrigger())
        #expect(recorder.events == [.triggerDown, .triggerUp])
    }

    @Test func eventsFromThisProcessAreIgnoredEvenWithoutTheMarker() throws {
        let recorder = Recorder()
        let monitor = EventTapKeyboardMonitor(
            cursor: FakeCursor(),
            physicalFlags: { TriggerKey.rightCommand.pressedFlags },
            physicalButton: { _ in false },
            isAccessibilityTrusted: { false },
            ownProcessID: Int64(getpid())
        )
        monitor.onEvent = { recorder.events.append($0) }
        // 本物のキーボードのイベントは送り元のプロセスが別
        let press = try flagsEvent(keyCode: 54, flags: TriggerKey.rightCommand.pressedFlags)
        press.setIntegerValueField(.eventSourceUnixProcessID, value: 0)
        #expect(monitor.handle(type: .flagsChanged, event: press, from: .keyboard))
        #expect(recorder.events == [.triggerDown])
        // このプロセスが作ったイベント（印なし）
        let own = try #require(CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: true))
        #expect(own.getIntegerValueField(.eventSourceUnixProcessID) == Int64(getpid()))
        #expect(monitor.handle(type: .keyDown, event: own, from: .keyboard))
        #expect(recorder.events == [.triggerDown])
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
        _ = try pressTrigger()
        // セッションの前に押したボタンの離すは渡す
        #expect(send(.leftMouseUp, try mouse(.leftMouseUp)))
        #expect(!send(.rightMouseDown, try mouse(.rightMouseDown, button: .right)))
        #expect(!send(.scrollWheel, try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 3, wheel2: 0, wheel3: 0))))
        _ = try releaseTrigger()
        #expect(!send(.rightMouseUp, try mouse(.rightMouseUp, button: .right)))
        passClickGrace()
        #expect(send(.rightMouseDown, try mouse(.rightMouseDown, button: .right)))
    }

    @Test func dropsGestureEventsDuringSession() throws {
        let gesture = try #require(CGEvent(source: nil))
        let swipe = try #require(CGEventType(rawValue: 31))
        #expect(send(swipe, gesture))
        _ = try pressTrigger()
        #expect(!send(swipe, gesture))
        #expect(!send(try #require(CGEventType(rawValue: 29)), gesture))
    }

    @Test func otherMouseButtonsArePairedByNumber() throws {
        _ = try pressTrigger()
        let button3 = try #require(CGMouseButton(rawValue: 3))
        #expect(!send(.otherMouseDown, try mouse(.otherMouseDown, button: button3)))
        _ = try releaseTrigger()
        #expect(send(.otherMouseUp, try mouse(.otherMouseUp, button: .center)))
        #expect(!send(.otherMouseUp, try mouse(.otherMouseUp, button: button3)))
    }

    @Test func dragOfADroppedButtonIsPassedAsAMoveAfterSession() throws {
        _ = try pressTrigger()
        _ = send(.leftMouseDown, try mouse(.leftMouseDown))
        _ = try releaseTrigger()
        let drag = try mouse(.leftMouseDragged)
        #expect(send(.leftMouseDragged, drag))
        #expect(drag.type == .mouseMoved)
    }

    @Test func nonPointerEventsPass() throws {
        _ = try pressTrigger()
        let event = try #require(CGEvent(source: nil))
        #expect(send(try #require(CGEventType(rawValue: 14)), event))
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
        _ = try pressTrigger()
        #expect(monitor.isPointerTapEnabled)
        #expect(!monitor.isSweeping)
        #expect(!monitor.isWaitingForClickGrace)
        _ = try releaseTrigger()
        // 遅れて届くクリックを捨てる間だけ残す
        #expect(monitor.isPointerTapEnabled)
        #expect(monitor.isWaitingForClickGrace)
        passClickGrace()
        #expect(!monitor.isPointerTapEnabled)
        #expect(!monitor.isSweeping)
        #expect(!monitor.isWaitingForClickGrace)
        // 中断で抑止が終わっても止める
        _ = try pressTrigger()
        monitor.isSuppressingPointer = false
        #expect(!monitor.isPointerTapEnabled)
        #expect(!monitor.isWaitingForClickGrace)
    }

    @Test func aClickRightAfterASessionWithoutARecentLiftPasses() throws {
        // 指に触れていないセッション（右⌘＋C のようにトリガーをほかのキーと組み合わせただけ など）
        recorder.dropsLateClicks = false
        _ = try pressTrigger()
        #expect(send(.keyDown, try #require(CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: true))))
        #expect(!monitor.isPointerTapEnabled)
        #expect(!monitor.isWaitingForClickGrace)
        clock.now += 0.03
        #expect(send(.leftMouseDown, try mouse(.leftMouseDown)))
        #expect(send(.leftMouseUp, try mouse(.leftMouseUp)))
        // トリガーを離して終えたときも同じ
        _ = try releaseTrigger()
        _ = try pressTrigger()
        _ = try releaseTrigger()
        #expect(!monitor.isPointerTapEnabled)
        clock.now += 0.03
        #expect(send(.rightMouseDown, try mouse(.rightMouseDown, button: .right)))
    }

    @Test func aTapToClickThatArrivesJustAfterTheSessionEndsIsDropped() throws {
        recorder.dropsLateClicks = true
        _ = try pressTrigger()
        // セッションは指を離したフレームで終わり、そのタップが作ったクリックが後から届く
        _ = try releaseTrigger()
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
        _ = try pressTrigger()
        _ = try releaseTrigger()
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
        _ = try pressTrigger()
        _ = try releaseTrigger()
        #expect(monitor.isWaitingForClickGrace)
        _ = try pressTrigger()
        #expect(!monitor.isWaitingForClickGrace)
        #expect(monitor.isPointerTapEnabled)
        #expect(!send(.leftMouseDown, try mouse(.leftMouseDown)))
    }

    @Test func pointerTapStaysUntilTheUpOfADroppedClick() throws {
        _ = try pressTrigger()
        #expect(!send(.leftMouseDown, try mouse(.leftMouseDown)))
        _ = try releaseTrigger()
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
        _ = try pressTrigger()
        #expect(!send(.scrollWheel, try scroll(phase: 1, momentum: 0)))
        _ = try releaseTrigger()
        passClickGrace()
        #expect(monitor.isPointerTapEnabled)
        #expect(!send(.scrollWheel, try scroll(phase: 4, momentum: 0)))
        #expect(!send(.scrollWheel, try scroll(phase: 0, momentum: 1)))
        #expect(monitor.isPointerTapEnabled)
        #expect(!send(.scrollWheel, try scroll(phase: 0, momentum: 3)))
        #expect(!monitor.isPointerTapEnabled)
    }

    @Test func sweepEndsAScrollTailThatNeverGetsAnEnd() throws {
        _ = try pressTrigger()
        // 2本指のスワイプ（ページ送り）。慣性なしで指を離したので、終わりの印は来ない
        #expect(!send(.scrollWheel, try scroll(phase: 1, momentum: 0)))
        _ = try releaseTrigger()
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
        _ = try pressTrigger()
        physical.pressedButtons = [0, 1]
        #expect(!send(.leftMouseDown, try mouse(.leftMouseDown)))
        #expect(!send(.rightMouseDown, try mouse(.rightMouseDown, button: .right)))
        let disabled = try #require(CGEvent(source: nil))
        #expect(monitor.handle(type: .tapDisabledByTimeout, event: disabled, from: .pointer))
        // 無効だった間に左を離した（離すイベントは届かない）。右はまだ押している
        physical.pressedButtons = [1]
        _ = try releaseTrigger()
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
        _ = try pressTrigger()
        #expect(!send(.leftMouseDown, try mouse(.leftMouseDown)))
        _ = try releaseTrigger()
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
        _ = try pressTrigger()
        #expect(!send(.rightMouseDown, try mouse(.rightMouseDown, button: .right)))
        _ = try releaseTrigger()
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
        _ = try pressTrigger()
        _ = send(.leftMouseDown, try mouse(.leftMouseDown))
        monitor.stop()
        #expect(!monitor.isPointerTapEnabled)
        #expect(!monitor.isSweeping)
    }

    // MARK: カーソルの固定

    @Test func automaticDropsMovesAndWarpsBackOnlyWhenTheCursorMoved() throws {
        monitor.cursorLock = .automatic
        let anchor = try #require(cursor.location)
        _ = try pressTrigger()
        #expect(!send(.mouseMoved, try mouse(.mouseMoved)))
        #expect(cursor.warps.isEmpty)
        cursor.location = CGPoint(x: anchor.x + 8, y: anchor.y)
        #expect(!send(.mouseMoved, try mouse(.mouseMoved)))
        #expect(cursor.warps == [anchor])
        cursor.location = CGPoint(x: anchor.x, y: anchor.y - 3)
        _ = try releaseTrigger()
        #expect(cursor.warps == [anchor, anchor])
        #expect(cursor.associations.isEmpty)
    }

    @Test func dropEventsNeverWarps() throws {
        monitor.cursorLock = .dropEvents
        _ = try pressTrigger()
        cursor.location = CGPoint(x: 500, y: 500)
        #expect(!send(.mouseMoved, try mouse(.mouseMoved)))
        #expect(!send(.leftMouseDragged, try mouse(.leftMouseDragged)))
        _ = try releaseTrigger()
        #expect(cursor.warps.isEmpty)
    }

    @Test func decoupleRestoresTheAssociationWhenSuppressionEnds() throws {
        monitor.cursorLock = .decouple
        _ = try pressTrigger()
        #expect(cursor.associations == [false])
        #expect(!send(.mouseMoved, try mouse(.mouseMoved)))
        // 途中で設定を変えても、始めたときの方式で戻す
        monitor.cursorLock = .none
        _ = try releaseTrigger()
        #expect(cursor.associations == [false, true])
        #expect(cursor.warps.isEmpty)
    }

    @Test func noneLetsTheCursorMove() throws {
        monitor.cursorLock = .none
        _ = try pressTrigger()
        #expect(send(.mouseMoved, try mouse(.mouseMoved)))
        #expect(!send(.leftMouseDown, try mouse(.leftMouseDown)))
        #expect(cursor.associations.isEmpty)
    }

    @Test func stopRestoresTheCursorAndEndsSuppression() throws {
        monitor.cursorLock = .decouple
        _ = try pressTrigger()
        monitor.stop()
        #expect(!monitor.isSuppressingPointer)
        #expect(cursor.associations == [false, true])
        #expect(!monitor.isRunning)
        // 止めた後は押していないことになっている
        #expect(try releaseTrigger())
        #expect(recorder.events == [.triggerDown])
    }

    @Test func releasingTheMonitorRestoresTheCursor() {
        let cursor = FakeCursor()
        do {
            let monitor = EventTapKeyboardMonitor(
                cursor: cursor,
                physicalFlags: { inputFlags() },
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
        // ふだん有効にしておくキーボードのタップは、ポインタのイベントを受け取らない
        for type in UInt32(0)..<64 {
            #expect(EventTapMask.contains(keyboard, type) == [CGEventType.keyDown.rawValue, CGEventType.flagsChanged.rawValue].contains(type), "type \(type)")
            #expect(EventTapMask.contains(pointer, type) == PointerEventKind.all.contains(type), "type \(type)")
        }
    }
}
