import CoreGraphics
import Foundation
import NonetCore
import Testing
@testable import NonetPlatform

/// 強く長押しで開くための、クリックの預かり。イベントタップは作らず、合成したイベントを handle に直接渡し、
/// 返すイベントは送らずに記録する
@MainActor
@Suite struct InputForcePressMonitorTests {
    final class State {
        var now: TimeInterval = 1000
        var pressedButtons: Set<Int64> = [0]
        var stage = 1
        var posted: [(type: CGEventType, location: CGPoint, userData: Int64)] = []
        var events: [KeyboardEvent] = []
    }

    let state = State()
    let monitor: EventTapKeyboardMonitor
    let point = CGPoint(x: 40, y: 60)

    init() {
        let state = state
        monitor = EventTapKeyboardMonitor(
            cursor: FakeCursor(),
            physicalButton: { state.pressedButtons.contains($0) },
            isAccessibilityTrusted: { false },
            ownProcessID: InputKeyboardMonitorTests.fakeOwnPID,
            now: { state.now },
            postEvent: { event in
                state.posted.append((event.type, event.location, event.getIntegerValueField(.eventSourceUserData)))
            },
            pressureStage: { _ in state.stage }
        )
        monitor.onEvent = { state.events.append($0) }
        monitor.forcePressHold = 0.25
        monitor.isTrackpadTouched = true
    }

    private func mouse(_ type: CGEventType, at location: CGPoint? = nil) throws -> CGEvent {
        try #require(CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: location ?? point, mouseButton: .left))
    }

    private func pressure() throws -> CGEvent {
        let event = try mouse(.leftMouseDragged)
        event.type = try #require(CGEventType(rawValue: PointerEventKind.pressure))
        return event
    }

    private func press() throws -> Bool {
        monitor.handle(type: .leftMouseDown, event: try mouse(.leftMouseDown), from: .click)
    }

    private var postedTypes: [CGEventType] { state.posted.map(\.type) }

    @Test func holdsATrackpadClickAndGivesItBackWhenReleased() throws {
        #expect(try press() == false)
        #expect(monitor.isPointerTapEnabled)
        #expect(monitor.isWaitingForHolderDeadline)
        #expect(monitor.handle(type: .leftMouseUp, event: try mouse(.leftMouseUp), from: .pointer) == false)
        #expect(postedTypes == [.leftMouseDown, .leftMouseUp])
        #expect(state.posted.allSatisfy { $0.userData == OwnEventFilter.userData })
        #expect(state.posted.first?.location == point)
        #expect(!monitor.isPointerTapEnabled)
        #expect(!monitor.isWaitingForHolderDeadline)
    }

    @Test func passesTheClicksItGaveBack() throws {
        _ = try press()
        _ = monitor.handle(type: .leftMouseUp, event: try mouse(.leftMouseUp), from: .pointer)
        let replayed = try mouse(.leftMouseDown)
        replayed.setIntegerValueField(.eventSourceUserData, value: OwnEventFilter.userData)
        #expect(monitor.handle(type: .leftMouseDown, event: replayed, from: .click))
    }

    @Test func doesNotHoldMouseClicksOrClicksWhileItCannotOpen() throws {
        monitor.isTrackpadTouched = false
        #expect(try press())
        monitor.isTrackpadTouched = true
        monitor.forcePressHold = nil
        #expect(try press())
        monitor.forcePressHold = 0.25
        monitor.isSuppressingPointer = true
        #expect(try press())
        #expect(state.posted.isEmpty)
    }

    @Test func draggingGivesTheClickBackFollowedByTheDrag() throws {
        _ = try press()
        let far = CGPoint(x: point.x + 20, y: point.y)
        #expect(monitor.handle(type: .leftMouseDragged, event: try mouse(.leftMouseDragged, at: far), from: .pointer) == false)
        #expect(postedTypes == [.leftMouseDown, .leftMouseDragged])
        #expect(state.posted.last?.location == far)
    }

    @Test func aLightLongPressIsGivenBackAfterTheLimit() throws {
        _ = try press()
        state.now += ForceClickHolder.lightPressLimit
        monitor.holderDeadlineDidPass()
        #expect(postedTypes == [.leftMouseDown])
        #expect(state.events.isEmpty)
        // 返した後の離すはそのまま渡す
        #expect(monitor.handle(type: .leftMouseUp, event: try mouse(.leftMouseUp), from: .pointer))
    }

    @Test func pressingHardAndHoldingAsksToOpenAndOpeningDropsTheClick() throws {
        _ = try press()
        state.now += 0.1
        state.stage = 2
        #expect(monitor.handle(type: try #require(CGEventType(rawValue: PointerEventKind.pressure)), event: try pressure(), from: .pointer) == false)
        state.now += 0.25
        monitor.holderDeadlineDidPass()
        #expect(state.events == [.forcePressed])
        monitor.isSuppressingPointer = true
        monitor.finishForcePress(opened: true)
        #expect(state.posted.isEmpty)
        // 押したままの動きは移動として渡し、離すは捨てる
        let drag = try mouse(.leftMouseDragged, at: CGPoint(x: 90, y: 90))
        #expect(monitor.handle(type: .leftMouseDragged, event: drag, from: .pointer))
        #expect(drag.type == .mouseMoved)
        #expect(monitor.handle(type: .leftMouseUp, event: try mouse(.leftMouseUp), from: .pointer) == false)
        #expect(state.posted.isEmpty)
    }

    @Test func notOpeningGivesTheClickBack() throws {
        _ = try press()
        state.stage = 2
        _ = monitor.handle(type: try #require(CGEventType(rawValue: PointerEventKind.pressure)), event: try pressure(), from: .pointer)
        state.now += 1
        monitor.holderDeadlineDidPass()
        monitor.finishForcePress(opened: false)
        #expect(postedTypes == [.leftMouseDown])
    }

    @Test func turningForcePressOffGivesBackWhatIsHeld() throws {
        _ = try press()
        state.pressedButtons = []
        monitor.forcePressHold = nil
        #expect(postedTypes == [.leftMouseDown, .leftMouseUp])
        #expect(!monitor.isPointerTapEnabled)
    }
}
