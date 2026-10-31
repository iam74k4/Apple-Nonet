// 担当: platform-input。9マスを開いている間のキー（押されたら閉じる）と、開いたときの触覚
import CoreGraphics
import Foundation
import NonetCore
import Testing
@testable import NonetPlatform

/// テストで作る flagsChanged の flags（0x100 は、キーボードがいつも立てる、左右の区別の無いビット）
func inputFlags(_ independent: CGEventFlags = [], device: UInt64 = 0) -> CGEventFlags {
    CGEventFlags(rawValue: independent.rawValue | device | 0x100)
}

@Suite struct InputSessionKeyWatcherTests {
    /// キーは押されたら .interrupted を1回だけ出す（そのキーはいつも前面アプリに渡すので、渡すかどうかは返さない）
    @Test func aKeyInterruptsOnce() {
        var watcher = SessionKeyWatcher()
        watcher.sessionBegan()
        #expect(watcher.keyDown() == .interrupted)
        #expect(watcher.keyDown() == nil)
        // 次のセッションでは、また1回
        watcher.sessionBegan()
        #expect(watcher.keyDown() == .interrupted)
    }

    /// 修飾キーを押したら閉じる（右⌘・左⇧・fn・Caps Lock も）。離しただけ（開く前から押していたキーを離した）では閉じない
    @Test(arguments: [
        (Int64(55), CGEventFlags.maskCommand, DeviceModifierMask.leftCommand),
        (54, .maskCommand, DeviceModifierMask.rightCommand),
        (56, .maskShift, DeviceModifierMask.leftShift),
        (61, .maskAlternate, DeviceModifierMask.rightOption),
        (59, .maskControl, DeviceModifierMask.leftControl),
        (63, .maskSecondaryFn, 0),
    ])
    func pressingAModifierInterrupts(keyCode: Int64, flag: CGEventFlags, device: UInt64) {
        var watcher = SessionKeyWatcher()
        watcher.sessionBegan()
        #expect(watcher.flagsChanged(keyCode: keyCode, flags: inputFlags(flag, device: device)) == .interrupted)
    }

    @Test func releasingAModifierDoesNotInterrupt() {
        var watcher = SessionKeyWatcher()
        watcher.sessionBegan()
        #expect(watcher.flagsChanged(keyCode: 56, flags: inputFlags()) == nil)
        #expect(!watcher.hasInterrupted)
        #expect(watcher.flagsChanged(keyCode: 57, flags: inputFlags()) == .interrupted)
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
        // 表に無いキー（Caps Lock など）は押したとみなす
        #expect(ModifierKeyCode.isPress(keyCode: 179, flags: inputFlags()))
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

    /// 開いたときの触覚は軽い1打: どの強さでも境界（マスをまたいだ）より強くしない
    @Test(arguments: [HapticStrength.light, .medium, .strong])
    func theActivationHapticIsLight(strength: HapticStrength) throws {
        let activation = try #require(HapticTuning.actuation(for: .activation, strength: strength))
        let boundary = try #require(HapticTuning.actuation(for: .boundary, strength: strength))
        #expect(activation.actuationID <= boundary.actuationID)
        #expect(HapticTuning.secondPulseDelays[.activation] == nil)
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
