// 担当: platform-actions
import Carbon.HIToolbox
import CoreGraphics
import NonetCore

/// 仮想キーコード（kVK_*）とイベントのフラグの対応
enum VirtualKeyTable {
    static func keyCode(for key: SpecialKey) -> CGKeyCode {
        let code: Int = switch key {
        case .returnKey: kVK_Return
        case .tab: kVK_Tab
        case .space: kVK_Space
        case .delete: kVK_Delete
        case .forwardDelete: kVK_ForwardDelete
        case .escape: kVK_Escape
        case .leftArrow: kVK_LeftArrow
        case .rightArrow: kVK_RightArrow
        case .upArrow: kVK_UpArrow
        case .downArrow: kVK_DownArrow
        case .home: kVK_Home
        case .end: kVK_End
        case .pageUp: kVK_PageUp
        case .pageDown: kVK_PageDown
        case .f1: kVK_F1
        case .f2: kVK_F2
        case .f3: kVK_F3
        case .f4: kVK_F4
        case .f5: kVK_F5
        case .f6: kVK_F6
        case .f7: kVK_F7
        case .f8: kVK_F8
        case .f9: kVK_F9
        case .f10: kVK_F10
        case .f11: kVK_F11
        case .f12: kVK_F12
        case .f13: kVK_F13
        case .f14: kVK_F14
        case .f15: kVK_F15
        case .f16: kVK_F16
        case .f17: kVK_F17
        case .f18: kVK_F18
        case .f19: kVK_F19
        case .f20: kVK_F20
        case .eisu: kVK_JIS_Eisu
        case .kana: kVK_JIS_Kana
        }
        return CGKeyCode(code)
    }

    private static let specialKeysByCode: [CGKeyCode: SpecialKey] = Dictionary(
        SpecialKey.allCases.map { (keyCode(for: $0), $0) },
        uniquingKeysWith: { first, _ in first }
    )

    static func specialKey(forKeyCode code: CGKeyCode) -> SpecialKey? {
        specialKeysByCode[code]
    }

    /// テンキーのキー。文字を探すときは本体のキーを優先する
    static let keypadCodes: Set<CGKeyCode> = Set([
        kVK_ANSI_KeypadDecimal, kVK_ANSI_KeypadMultiply, kVK_ANSI_KeypadPlus, kVK_ANSI_KeypadClear,
        kVK_ANSI_KeypadDivide, kVK_ANSI_KeypadEnter, kVK_ANSI_KeypadMinus, kVK_ANSI_KeypadEquals,
        kVK_ANSI_Keypad0, kVK_ANSI_Keypad1, kVK_ANSI_Keypad2, kVK_ANSI_Keypad3, kVK_ANSI_Keypad4,
        kVK_ANSI_Keypad5, kVK_ANSI_Keypad6, kVK_ANSI_Keypad7, kVK_ANSI_Keypad8, kVK_ANSI_Keypad9,
        kVK_JIS_KeypadComma,
    ].map { CGKeyCode($0) })

    private static let arrowCodes: Set<CGKeyCode> = Set([
        kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow,
    ].map { CGKeyCode($0) })

    /// 本物のキーボードが fn のフラグを付けて送るキー（F キー・矢印・Home/End・PageUp/Down・前方削除・Help）
    private static let functionFlagCodes: Set<CGKeyCode> = Set([
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
        kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown, kVK_ForwardDelete, kVK_Help,
        kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow,
    ].map { CGKeyCode($0) })

    /// 修飾キーとは別に、そのキー自体が持つフラグ。これが無いと ⌘← などを別のキーとして扱うアプリがある
    static func implicitFlags(forKeyCode code: CGKeyCode) -> CGEventFlags {
        var flags: CGEventFlags = []
        if functionFlagCodes.contains(code) { flags.insert(.maskSecondaryFn) }
        if arrowCodes.contains(code) || keypadCodes.contains(code) { flags.insert(.maskNumericPad) }
        return flags
    }

    // IOKit の NX_DEVICEL*KEYMASK。本物のキーボードのイベントには左右どちらのキーかが入る
    private static let leftControlBit: UInt64 = 0x0000_0001
    private static let leftShiftBit: UInt64 = 0x0000_0002
    private static let leftCommandBit: UInt64 = 0x0000_0008
    private static let leftOptionBit: UInt64 = 0x0000_0020

    /// 修飾キーのフラグ。物理的に押されているキーとは関係なく、これだけを付ける
    static func flags(for modifiers: ModifierSet) -> CGEventFlags {
        var raw: UInt64 = CGEventFlags.maskNonCoalesced.rawValue
        if modifiers.contains(.control) { raw |= CGEventFlags.maskControl.rawValue | leftControlBit }
        if modifiers.contains(.option) { raw |= CGEventFlags.maskAlternate.rawValue | leftOptionBit }
        if modifiers.contains(.shift) { raw |= CGEventFlags.maskShift.rawValue | leftShiftBit }
        if modifiers.contains(.command) { raw |= CGEventFlags.maskCommand.rawValue | leftCommandBit }
        if modifiers.contains(.function) { raw |= CGEventFlags.maskSecondaryFn.rawValue }
        return CGEventFlags(rawValue: raw)
    }
}
