import CoreGraphics
import NonetCore
import Testing
@testable import NonetPlatform

/// 実際のイベントと同じく、合体しないことを示すビット（NX_NONCOALESCEDMASK）も立てる
func inputFlags(_ independent: CGEventFlags = [], device: UInt64 = 0) -> CGEventFlags {
    CGEventFlags(rawValue: independent.rawValue | device | 0x100)
}

extension TriggerKey {
    /// このキーだけを押したときの flags
    var pressedFlags: CGEventFlags {
        inputFlags(modifierFlag, device: deviceMask ?? 0)
    }
}

@Suite struct InputTriggerDetectorTests {
    typealias Output = TriggerDetector.Output

    @Test(arguments: TriggerKey.allCases)
    func triggerAloneEmitsDownAndUp(trigger: TriggerKey) {
        var detector = TriggerDetector()
        let down = detector.flagsChanged(keyCode: trigger.keyCode, flags: trigger.pressedFlags, trigger: trigger, passTrigger: true)
        #expect(down == Output(event: .triggerDown, pass: true))
        #expect(detector.heldTrigger == trigger)
        let up = detector.flagsChanged(keyCode: trigger.keyCode, flags: inputFlags(), trigger: trigger, passTrigger: true)
        #expect(up == Output(event: .triggerUp, pass: true))
        #expect(!detector.isHeld)
    }

    @Test func keyCodesAndMasksMatchTheHardware() {
        #expect(TriggerKey.rightCommand.keyCode == 54)
        #expect(TriggerKey.rightOption.keyCode == 61)
        #expect(TriggerKey.rightShift.keyCode == 60)
        #expect(TriggerKey.function.keyCode == 63)
        #expect(TriggerKey.rightCommand.deviceMask == 0x10)
        #expect(TriggerKey.rightOption.deviceMask == 0x40)
        #expect(TriggerKey.rightShift.deviceMask == 0x04)
        #expect(TriggerKey.function.deviceMask == nil)
        #expect(TriggerKey.function.modifierFlag == .maskSecondaryFn)
    }

    @Test func leftCommandDoesNotTrigger() {
        var detector = TriggerDetector()
        let output = detector.flagsChanged(keyCode: 55, flags: inputFlags(.maskCommand, device: DeviceModifierMask.leftCommand), trigger: .rightCommand, passTrigger: false)
        #expect(output == .passThrough)
        #expect(!detector.isHeld)
    }

    @Test func rightCommandWhileLeftCommandHeldDoesNotTrigger() {
        var detector = TriggerDetector()
        let flags = inputFlags(.maskCommand, device: DeviceModifierMask.leftCommand | DeviceModifierMask.rightCommand)
        #expect(detector.flagsChanged(keyCode: 54, flags: flags, trigger: .rightCommand, passTrigger: false) == .passThrough)
        #expect(!detector.isHeld)
    }

    @Test(arguments: [
        (CGEventFlags.maskShift, DeviceModifierMask.leftShift),
        (CGEventFlags.maskControl, DeviceModifierMask.leftControl),
        (CGEventFlags.maskAlternate, DeviceModifierMask.rightOption),
        (CGEventFlags.maskSecondaryFn, UInt64(0)),
    ])
    func otherModifierHeldPreventsTrigger(other: CGEventFlags, device: UInt64) {
        var detector = TriggerDetector()
        let flags = inputFlags([.maskCommand, other], device: DeviceModifierMask.rightCommand | device)
        #expect(detector.flagsChanged(keyCode: 54, flags: flags, trigger: .rightCommand, passTrigger: true) == .passThrough)
        #expect(!detector.isHeld)
    }

    @Test func functionTriggerRequiresNoOtherModifier() {
        var detector = TriggerDetector()
        let withShift = inputFlags([.maskSecondaryFn, .maskShift], device: DeviceModifierMask.leftShift)
        #expect(detector.flagsChanged(keyCode: 63, flags: withShift, trigger: .function, passTrigger: true) == .passThrough)
        #expect(detector.flagsChanged(keyCode: 63, flags: inputFlags(.maskSecondaryFn), trigger: .function, passTrigger: true).event == .triggerDown)
    }

    @Test func capsLockDoesNotCountAsAModifier() {
        var detector = TriggerDetector()
        let flags = inputFlags([.maskCommand, .maskAlphaShift], device: DeviceModifierMask.rightCommand)
        #expect(detector.flagsChanged(keyCode: 54, flags: flags, trigger: .rightCommand, passTrigger: true).event == .triggerDown)
    }

    @Test func keyboardsWithoutDeviceBitsFallBackToIndependentFlag() {
        var detector = TriggerDetector()
        #expect(detector.flagsChanged(keyCode: 61, flags: inputFlags(.maskAlternate), trigger: .rightOption, passTrigger: true).event == .triggerDown)
        #expect(detector.flagsChanged(keyCode: 61, flags: inputFlags(), trigger: .rightOption, passTrigger: true).event == .triggerUp)
    }

    @Test func isPressedDistinguishesLeftAndRight() {
        let trigger = TriggerKey.rightShift
        #expect(trigger.isPressed(in: inputFlags(.maskShift, device: DeviceModifierMask.rightShift)))
        #expect(!trigger.isPressed(in: inputFlags(.maskShift, device: DeviceModifierMask.leftShift)))
        #expect(trigger.isPressed(in: inputFlags(.maskShift, device: DeviceModifierMask.leftShift | DeviceModifierMask.rightShift)))
        #expect(!trigger.isPressed(in: inputFlags()))
    }

    @Test func otherTriggerKeyCodeIsIgnored() {
        var detector = TriggerDetector()
        // 右⌘を押したが、設定は右⌥
        let output = detector.flagsChanged(keyCode: 54, flags: TriggerKey.rightCommand.pressedFlags, trigger: .rightOption, passTrigger: false)
        #expect(output == .passThrough)
    }

    @Test func keyDownWhileHeldInterruptsOnceAndPasses() {
        var detector = TriggerDetector()
        _ = detector.flagsChanged(keyCode: 54, flags: TriggerKey.rightCommand.pressedFlags, trigger: .rightCommand, passTrigger: true)
        #expect(detector.keyDown() == Output(event: .interrupted, pass: true))
        #expect(detector.keyDown() == .passThrough)
        #expect(detector.isInterrupted)
        // 中断の後でも、離したことは知らせる
        #expect(detector.flagsChanged(keyCode: 54, flags: inputFlags(), trigger: .rightCommand, passTrigger: true).event == .triggerUp)
        #expect(!detector.isInterrupted)
    }

    @Test func keyDownWithoutTriggerPasses() {
        var detector = TriggerDetector()
        #expect(detector.keyDown() == .passThrough)
    }

    @Test func otherModifierWhileHeldInterrupts() {
        var detector = TriggerDetector()
        _ = detector.flagsChanged(keyCode: 54, flags: TriggerKey.rightCommand.pressedFlags, trigger: .rightCommand, passTrigger: true)
        let shiftDown = inputFlags([.maskCommand, .maskShift], device: DeviceModifierMask.rightCommand | DeviceModifierMask.leftShift)
        #expect(detector.flagsChanged(keyCode: 56, flags: shiftDown, trigger: .rightCommand, passTrigger: true) == Output(event: .interrupted, pass: true))
        // シフトを離しても、もう一度は出さない
        #expect(detector.flagsChanged(keyCode: 56, flags: TriggerKey.rightCommand.pressedFlags, trigger: .rightCommand, passTrigger: true) == .passThrough)
        #expect(detector.flagsChanged(keyCode: 54, flags: inputFlags(), trigger: .rightCommand, passTrigger: true).event == .triggerUp)
    }

    @Test func leftCounterpartWhileHeldInterruptsAndRightReleaseStillEnds() {
        var detector = TriggerDetector()
        _ = detector.flagsChanged(keyCode: 54, flags: TriggerKey.rightCommand.pressedFlags, trigger: .rightCommand, passTrigger: true)
        let both = inputFlags(.maskCommand, device: DeviceModifierMask.leftCommand | DeviceModifierMask.rightCommand)
        #expect(detector.flagsChanged(keyCode: 55, flags: both, trigger: .rightCommand, passTrigger: true).event == .interrupted)
        // 左⌘を押したまま右⌘を離す
        let leftOnly = inputFlags(.maskCommand, device: DeviceModifierMask.leftCommand)
        #expect(detector.flagsChanged(keyCode: 54, flags: leftOnly, trigger: .rightCommand, passTrigger: true).event == .triggerUp)
    }

    @Test func swallowsTheTriggerPairWhenNotPassing() {
        var detector = TriggerDetector()
        #expect(detector.flagsChanged(keyCode: 54, flags: TriggerKey.rightCommand.pressedFlags, trigger: .rightCommand, passTrigger: false) == Output(event: .triggerDown, pass: false))
        // 押している間のほかのキーは渡す
        #expect(detector.keyDown() == Output(event: .interrupted, pass: true))
        #expect(detector.flagsChanged(keyCode: 54, flags: inputFlags(), trigger: .rightCommand, passTrigger: false) == Output(event: .triggerUp, pass: false))
        // 次のトリガー以外の修飾キーは渡す
        #expect(detector.flagsChanged(keyCode: 56, flags: inputFlags(.maskShift, device: DeviceModifierMask.leftShift), trigger: .rightCommand, passTrigger: false) == .passThrough)
    }

    @Test func onlySwallowsPairsItStartedSwallowing() {
        var detector = TriggerDetector()
        // 渡していた押下の離すは、途中で設定が変わっても渡す
        _ = detector.flagsChanged(keyCode: 54, flags: TriggerKey.rightCommand.pressedFlags, trigger: .rightCommand, passTrigger: true)
        #expect(detector.flagsChanged(keyCode: 54, flags: inputFlags(), trigger: .rightCommand, passTrigger: false).pass)
        // 捨てた押下の離すは、途中で設定が変わっても捨てる
        _ = detector.flagsChanged(keyCode: 54, flags: TriggerKey.rightCommand.pressedFlags, trigger: .rightCommand, passTrigger: false)
        #expect(!detector.flagsChanged(keyCode: 54, flags: inputFlags(), trigger: .rightCommand, passTrigger: true).pass)
    }

    @Test func duplicatePressWhileHeldFollowsTheOriginalDecision() {
        var detector = TriggerDetector()
        _ = detector.flagsChanged(keyCode: 54, flags: TriggerKey.rightCommand.pressedFlags, trigger: .rightCommand, passTrigger: false)
        #expect(detector.flagsChanged(keyCode: 54, flags: TriggerKey.rightCommand.pressedFlags, trigger: .rightCommand, passTrigger: true) == Output(event: nil, pass: false))
        #expect(detector.isHeld)
    }

    @Test func triggerSettingChangedWhileHeldStillEndsTheHeldKey() {
        var detector = TriggerDetector()
        _ = detector.flagsChanged(keyCode: 54, flags: TriggerKey.rightCommand.pressedFlags, trigger: .rightCommand, passTrigger: false)
        let up = detector.flagsChanged(keyCode: 54, flags: inputFlags(), trigger: .rightOption, passTrigger: true)
        #expect(up == Output(event: .triggerUp, pass: false))
        #expect(detector.flagsChanged(keyCode: 61, flags: TriggerKey.rightOption.pressedFlags, trigger: .rightOption, passTrigger: true).event == .triggerDown)
    }

    @Test func reconcileReleasesWhenPhysicallyUp() {
        var detector = TriggerDetector()
        #expect(detector.reconcile(physicalFlags: inputFlags()) == nil)
        _ = detector.flagsChanged(keyCode: 54, flags: TriggerKey.rightCommand.pressedFlags, trigger: .rightCommand, passTrigger: true)
        #expect(detector.reconcile(physicalFlags: TriggerKey.rightCommand.pressedFlags) == nil)
        #expect(detector.isHeld)
        #expect(detector.reconcile(physicalFlags: inputFlags()) == .triggerUp)
        #expect(!detector.isHeld)
        #expect(detector.reconcile(physicalFlags: inputFlags()) == nil)
        // 遅れて届いた離すイベントは、もう押していないので何も出さずに渡す
        #expect(detector.flagsChanged(keyCode: 54, flags: inputFlags(), trigger: .rightCommand, passTrigger: true) == .passThrough)
    }

    @Test func reconcileWithSwallowedPairKeepsDroppingTheLateUp() {
        var detector = TriggerDetector()
        _ = detector.flagsChanged(keyCode: 54, flags: TriggerKey.rightCommand.pressedFlags, trigger: .rightCommand, passTrigger: false)
        // 最初の確認で押されて見える → 物理的な状態は信頼できる
        #expect(detector.reconcile(physicalFlags: TriggerKey.rightCommand.pressedFlags) == nil)
        #expect(detector.swallowedStateIsReliable == true)
        #expect(detector.reconcile(physicalFlags: inputFlags()) == .triggerUp)
        // 対になる離すイベントが遅れて届いたら捨てる
        #expect(detector.flagsChanged(keyCode: 54, flags: inputFlags(), trigger: .rightCommand, passTrigger: false) == Output(event: nil, pass: false))
        // その後は普通に動く
        #expect(detector.flagsChanged(keyCode: 54, flags: TriggerKey.rightCommand.pressedFlags, trigger: .rightCommand, passTrigger: true) == Output(event: .triggerDown, pass: true))
    }

    @Test func swallowedPairIsNotReconciledWhenHIDStateDoesNotReflectIt() {
        var detector = TriggerDetector()
        _ = detector.flagsChanged(keyCode: 54, flags: TriggerKey.rightCommand.pressedFlags, trigger: .rightCommand, passTrigger: false)
        // 押している最中なのに離れて見える → 捨てた押下は反映されないとみなす
        #expect(detector.reconcile(physicalFlags: inputFlags()) == nil)
        #expect(detector.swallowedStateIsReliable == false)
        #expect(detector.reconcile(physicalFlags: inputFlags()) == nil)
        #expect(detector.isHeld)
        _ = detector.flagsChanged(keyCode: 54, flags: inputFlags(), trigger: .rightCommand, passTrigger: false)
        // 渡している押下は、引き続き確かめる
        _ = detector.flagsChanged(keyCode: 54, flags: TriggerKey.rightCommand.pressedFlags, trigger: .rightCommand, passTrigger: true)
        #expect(detector.reconcile(physicalFlags: inputFlags()) == .triggerUp)
    }

    @Test func newPressClearsALingeringSwallowedRelease() {
        var detector = TriggerDetector()
        _ = detector.flagsChanged(keyCode: 54, flags: TriggerKey.rightCommand.pressedFlags, trigger: .rightCommand, passTrigger: false)
        _ = detector.reconcile(physicalFlags: TriggerKey.rightCommand.pressedFlags)
        #expect(detector.reconcile(physicalFlags: inputFlags()) == .triggerUp)
        // 離すイベントは届かないまま、シフトと一緒に右⌘を押す（トリガーではない）
        let withShift = inputFlags([.maskCommand, .maskShift], device: DeviceModifierMask.rightCommand | DeviceModifierMask.leftShift)
        #expect(detector.flagsChanged(keyCode: 54, flags: withShift, trigger: .rightCommand, passTrigger: false) == .passThrough)
        // この離すは渡した押下の対なので、渡す
        #expect(detector.flagsChanged(keyCode: 54, flags: inputFlags(.maskShift, device: DeviceModifierMask.leftShift), trigger: .rightCommand, passTrigger: false) == .passThrough)
    }

    @Test func resetForgetsEverything() {
        var detector = TriggerDetector()
        _ = detector.flagsChanged(keyCode: 54, flags: TriggerKey.rightCommand.pressedFlags, trigger: .rightCommand, passTrigger: false)
        _ = detector.keyDown()
        detector.reset()
        #expect(!detector.isHeld)
        #expect(!detector.isInterrupted)
        #expect(detector.swallowedTrigger == nil)
        #expect(detector.flagsChanged(keyCode: 54, flags: inputFlags(), trigger: .rightCommand, passTrigger: false) == .passThrough)
    }
}
