import CoreGraphics
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
    }

    let cursor = FakeCursor()
    let physical = Physical()
    let monitor: EventTapKeyboardMonitor
    let recorder = Recorder()

    @MainActor
    final class Recorder {
        var events: [KeyboardEvent] = []
    }

    init() {
        let physical = physical
        monitor = EventTapKeyboardMonitor(cursor: cursor, physicalFlags: { physical.flags }, isAccessibilityTrusted: { false })
        monitor.trigger = .rightCommand
        let recorder = recorder
        let monitor = monitor
        // エンジンと同じく、トリガーを押したらすぐに抑止を始め、終わったら止める
        monitor.onEvent = { event in
            recorder.events.append(event)
            monitor.isSuppressingPointer = event == .triggerDown
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

    @discardableResult
    private func send(_ type: CGEventType, _ event: CGEvent) -> Bool {
        monitor.handle(type: type, event: event)
    }

    private func pressTrigger() throws -> Bool {
        send(.flagsChanged, try flagsEvent(keyCode: 54, flags: TriggerKey.rightCommand.pressedFlags))
    }

    private func releaseTrigger() throws -> Bool {
        send(.flagsChanged, try flagsEvent(keyCode: 54, flags: inputFlags()))
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
            let monitor = EventTapKeyboardMonitor(cursor: cursor, physicalFlags: { inputFlags() }, isAccessibilityTrusted: { false })
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

    @Test func eventMaskCoversKeyboardAndPointerEvents() {
        let mask = EventTapConnection.eventsOfInterest
        func has(_ raw: UInt32) -> Bool { mask & (CGEventMask(1) << CGEventMask(raw)) != 0 }
        #expect(has(CGEventType.keyDown.rawValue))
        #expect(has(CGEventType.flagsChanged.rawValue))
        #expect(!has(CGEventType.keyUp.rawValue))
        for type in PointerEventKind.all {
            #expect(has(type), "type \(type)")
        }
    }
}
