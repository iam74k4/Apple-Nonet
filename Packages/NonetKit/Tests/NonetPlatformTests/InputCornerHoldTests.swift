// 担当: platform-input。角の長押しで始めたセッション（トリガーを押していない）を、キーで終えるための見分けと、その触覚
import CoreGraphics
import Foundation
import NonetCore
import Testing
@testable import NonetPlatform

@Suite struct InputUntriggeredInterruptionTests {
    typealias Output = TriggerDetector.Output

    private func watching() -> TriggerDetector {
        var detector = TriggerDetector()
        detector.interruptsWithoutTrigger = true
        return detector
    }

    @Test func keysPassWithoutEventsUnlessWatching() {
        var detector = TriggerDetector()
        #expect(detector.keyDown() == .passThrough)
        #expect(detector.flagsChanged(keyCode: 56, flags: inputFlags(.maskShift, device: DeviceModifierMask.leftShift), trigger: .rightCommand, passTrigger: true) == .passThrough)
    }

    /// 押したキーは前面アプリに渡し、.interrupted は1回だけ
    @Test func aKeyInterruptsOnceAndPasses() {
        var detector = watching()
        #expect(detector.keyDown() == Output(event: .interrupted, pass: true))
        #expect(detector.keyDown() == .passThrough)
        #expect(!detector.isHeld)
        // 次のセッションでまた見る
        detector.interruptsWithoutTrigger = false
        detector.interruptsWithoutTrigger = true
        #expect(detector.keyDown() == Output(event: .interrupted, pass: true))
    }

    @Test(arguments: [
        (Int64(56), CGEventFlags.maskShift, DeviceModifierMask.leftShift),
        (Int64(55), CGEventFlags.maskCommand, DeviceModifierMask.leftCommand),
        (Int64(62), CGEventFlags.maskControl, DeviceModifierMask.rightControl),
        (Int64(58), CGEventFlags.maskAlternate, DeviceModifierMask.leftOption),
        (Int64(63), CGEventFlags.maskSecondaryFn, UInt64(0)),
    ])
    func pressingAModifierInterrupts(keyCode: Int64, flag: CGEventFlags, device: UInt64) {
        var detector = watching()
        #expect(detector.flagsChanged(keyCode: keyCode, flags: inputFlags(flag, device: device), trigger: .rightCommand, passTrigger: true) == Output(event: .interrupted, pass: true))
    }

    /// セッションの前から押していた修飾キーを離しただけでは終えない
    @Test func releasingAModifierDoesNotInterrupt() {
        var detector = watching()
        #expect(detector.flagsChanged(keyCode: 56, flags: inputFlags(), trigger: .rightCommand, passTrigger: true) == .passThrough)
        // 右⇧を押したまま左⇧を離した
        #expect(detector.flagsChanged(keyCode: 56, flags: inputFlags(.maskShift, device: DeviceModifierMask.rightShift), trigger: .rightCommand, passTrigger: true) == .passThrough)
        #expect(detector.keyDown() == Output(event: .interrupted, pass: true))
    }

    /// トリガーキーはふだんどおり .triggerDown（controller がトリガーキーのセッションに替える）
    @Test func theTriggerStillStartsAKeySession() {
        var detector = watching()
        #expect(detector.flagsChanged(keyCode: 54, flags: TriggerKey.rightCommand.pressedFlags, trigger: .rightCommand, passTrigger: false) == Output(event: .triggerDown, pass: false))
        #expect(detector.isHeld)
        // 押している間のキーは、トリガーのときの中断
        #expect(detector.keyDown() == Output(event: .interrupted, pass: true))
        #expect(detector.flagsChanged(keyCode: 54, flags: inputFlags(), trigger: .rightCommand, passTrigger: false) == Output(event: .triggerUp, pass: false))
    }

    /// トリガーを押したまま ⌘C などで一度中断した後に、押したまま角の長押しのセッションが始まったら、
    /// 次のキーや修飾キーでそのセッションを終える（.interrupted をもう1回出す）
    @Test func aKeyAfterAnEarlierInterruptionEndsACornerSession() {
        var detector = TriggerDetector()
        let trigger = TriggerKey.rightCommand
        _ = detector.flagsChanged(keyCode: trigger.keyCode, flags: trigger.pressedFlags, trigger: trigger, passTrigger: true)
        // ⌘C: トリガーのセッションを終える
        #expect(detector.keyDown() == Output(event: .interrupted, pass: true))
        // まだ右⌘を押したまま。角の長押しでセッションが始まる
        detector.interruptsWithoutTrigger = true
        // ⌘V: 角のセッションを終える。キーは前面アプリに渡す
        #expect(detector.keyDown() == Output(event: .interrupted, pass: true))
        // 出すのは1回だけ
        #expect(detector.keyDown() == .passThrough)
        #expect(detector.isHeld)
    }

    /// 押したままの修飾キーでも同じ。修飾キーを離しただけでは終えない
    @Test func aModifierAfterAnEarlierInterruptionEndsACornerSession() {
        var detector = TriggerDetector()
        let trigger = TriggerKey.rightCommand
        let held = trigger.pressedFlags
        _ = detector.flagsChanged(keyCode: trigger.keyCode, flags: held, trigger: trigger, passTrigger: true)
        #expect(detector.keyDown() == Output(event: .interrupted, pass: true))
        detector.interruptsWithoutTrigger = true
        // 左⇧を離した（押していたのはセッションの前から）
        let released = inputFlags(.maskCommand, device: DeviceModifierMask.rightCommand)
        #expect(detector.flagsChanged(keyCode: 56, flags: released, trigger: trigger, passTrigger: true) == .passThrough)
        // 左⇧を押した
        let shift = inputFlags([.maskCommand, .maskShift], device: DeviceModifierMask.rightCommand | DeviceModifierMask.leftShift)
        #expect(detector.flagsChanged(keyCode: 56, flags: shift, trigger: trigger, passTrigger: true) == Output(event: .interrupted, pass: true))
    }

    @Test func theTriggerWithAnotherModifierInterrupts() {
        var detector = watching()
        let flags = inputFlags([.maskCommand, .maskShift], device: DeviceModifierMask.rightCommand | DeviceModifierMask.leftShift)
        #expect(detector.flagsChanged(keyCode: 54, flags: flags, trigger: .rightCommand, passTrigger: true) == Output(event: .interrupted, pass: true))
        #expect(!detector.isHeld)
    }

    @Test func capsLockCountsAsAKeyPress() {
        var detector = watching()
        #expect(detector.flagsChanged(keyCode: 57, flags: inputFlags(), trigger: .rightCommand, passTrigger: true) == Output(event: .interrupted, pass: true))
    }

    @Test func modifierKeyCodesTellPressFromRelease() {
        // 左右のビットがあれば、そのキーのビットで判断する
        #expect(ModifierKeyCode.isPress(keyCode: 55, flags: inputFlags(.maskCommand, device: DeviceModifierMask.leftCommand)))
        #expect(!ModifierKeyCode.isPress(keyCode: 55, flags: inputFlags(.maskCommand, device: DeviceModifierMask.rightCommand)))
        #expect(ModifierKeyCode.isPress(keyCode: 54, flags: inputFlags(.maskCommand, device: DeviceModifierMask.leftCommand | DeviceModifierMask.rightCommand)))
        #expect(!ModifierKeyCode.isPress(keyCode: 61, flags: inputFlags()))
        // 左右のビットを付けないキーボードでは、区別の無いフラグで判断する
        #expect(ModifierKeyCode.isPress(keyCode: 59, flags: inputFlags(.maskControl)))
        #expect(!ModifierKeyCode.isPress(keyCode: 59, flags: inputFlags(.maskShift)))
        #expect(ModifierKeyCode.isPress(keyCode: 63, flags: inputFlags(.maskSecondaryFn)))
        #expect(!ModifierKeyCode.isPress(keyCode: 63, flags: inputFlags()))
        // 表に無いキーは押したとみなす
        #expect(ModifierKeyCode.isPress(keyCode: 179, flags: inputFlags()))
    }
}

/// イベントタップは作らず、合成したイベントを handle に直接渡す
@MainActor
@Suite struct InputUntriggeredInterruptionMonitorTests {
    let monitor = EventTapKeyboardMonitor(
        cursor: FakeCursor(),
        physicalFlags: { inputFlags() },
        physicalButton: { _ in false },
        isAccessibilityTrusted: { false },
        ownProcessID: 999_999
    )
    let events = Events()

    @MainActor
    final class Events {
        var received: [KeyboardEvent] = []
    }

    init() {
        monitor.trigger = .rightCommand
        let events = events
        monitor.onEvent = { events.received.append($0) }
    }

    private func keyDown(own: Bool = false) throws -> CGEvent {
        let event = try #require(CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: true))
        if own {
            event.setIntegerValueField(.eventSourceUserData, value: OwnEventFilter.userData)
        }
        return event
    }

    @Test func theMonitorReportsKeysOnlyWhileAskedTo() throws {
        #expect(!monitor.interruptsWithoutTrigger)
        #expect(monitor.handle(type: .keyDown, event: try keyDown(), from: .keyboard))
        #expect(events.received.isEmpty)

        monitor.interruptsWithoutTrigger = true
        #expect(monitor.interruptsWithoutTrigger)
        // Nonet 自身が送ったキーは数えない
        #expect(monitor.handle(type: .keyDown, event: try keyDown(own: true), from: .keyboard))
        #expect(events.received.isEmpty)
        #expect(monitor.handle(type: .keyDown, event: try keyDown(), from: .keyboard))
        #expect(events.received == [.interrupted])

        monitor.interruptsWithoutTrigger = false
        #expect(monitor.handle(type: .keyDown, event: try keyDown(), from: .keyboard))
        #expect(events.received == [.interrupted])
    }
}

@Suite struct InputActivationHapticTests {
    @Test func theActivationHapticHasATuningForEveryStrength() throws {
        #expect(HapticTuning.actuation(for: .activation, strength: .off) == nil)
        let light = try #require(HapticTuning.actuation(for: .activation, strength: .light))
        let medium = try #require(HapticTuning.actuation(for: .activation, strength: .medium))
        let strong = try #require(HapticTuning.actuation(for: .activation, strength: .strong))
        #expect(light.actuationID <= medium.actuationID)
        #expect(medium.actuationID <= strong.actuationID)
        #expect(HapticTuning.minimumIntervals[.activation] != nil)
        #expect(HapticTuning.fallback(for: .activation) == .levelChange)
    }

    @MainActor
    @Test func theEnginePlaysIt() throws {
        let backend = FakeHapticBackend()
        let engine = HapticEngine(backend: backend, clock: { 100 }, lastTouchedDevice: { 7 })
        engine.play(.activation, strength: .medium)
        let id = try #require(HapticTuning.actuation(for: .activation, strength: .medium)).actuationID
        #expect(backend.calls == [.close, .open(7), .actuate(id)])
    }
}
