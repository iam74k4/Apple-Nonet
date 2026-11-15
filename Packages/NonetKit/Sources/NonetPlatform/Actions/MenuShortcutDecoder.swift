// 担当: platform-actions
import Carbon.HIToolbox
import NonetCore

/// アクセシビリティ API のメニュー項目のショートカット（AXMenuItemCmd*）を KeySequence にする
enum MenuShortcutDecoder {
    // AXMenuItemCmdModifiers のビット（AXAttributeConstants.h）。何も無ければ ⌘ だけ
    static let shiftBit = 1 << 0
    static let optionBit = 1 << 1
    static let controlBit = 1 << 2
    static let noCommandBit = 1 << 3
    /// ヘッダには無いが、fn（🌐）付きの項目（例: fn F でフルスクリーン）はこのビットが立つ
    static let functionBit = 1 << 4

    static func modifiers(fromAXMask mask: Int) -> ModifierSet {
        var modifiers: ModifierSet = []
        if mask & noCommandBit == 0 { modifiers.insert(.command) }
        if mask & shiftBit != 0 { modifiers.insert(.shift) }
        if mask & optionBit != 0 { modifiers.insert(.option) }
        if mask & controlBit != 0 { modifiers.insert(.control) }
        if mask & functionBit != 0 { modifiers.insert(.function) }
        return modifiers
    }

    /// AXMenuItemCmdGlyph（Carbon の kMenu*Glyph）。修飾キーや飾りの記号はキーではないので nil
    static func key(fromGlyph glyph: Int) -> Key? {
        switch glyph {
        case 0x02, 0x03: .special(.tab)
        case 0x04: .keyCode(UInt16(kVK_ANSI_KeypadEnter))
        case 0x09: .special(.space)
        case 0x0A: .special(.forwardDelete)
        case 0x0B, 0x0C, 0x0D: .special(.returnKey)
        case 0x17: .special(.delete)
        case 0x1B: .special(.escape)
        case 0x1C: .keyCode(UInt16(kVK_ANSI_KeypadClear))
        case 0x62: .special(.pageUp)
        case 0x64: .special(.leftArrow)
        case 0x65: .special(.rightArrow)
        case 0x66: .special(.home)
        case 0x67: .keyCode(UInt16(kVK_Help))
        case 0x68: .special(.upArrow)
        case 0x69: .special(.end)
        case 0x6A: .special(.downArrow)
        case 0x6B: .special(.pageDown)
        case 0x6F: .special(.f1)
        case 0x70: .special(.f2)
        case 0x71: .special(.f3)
        case 0x72: .special(.f4)
        case 0x73: .special(.f5)
        case 0x74: .special(.f6)
        case 0x75: .special(.f7)
        case 0x76: .special(.f8)
        case 0x77: .special(.f9)
        case 0x78: .special(.f10)
        case 0x79: .special(.f11)
        case 0x7A: .special(.f12)
        case 0x87: .special(.f13)
        case 0x88: .special(.f14)
        case 0x89: .special(.f15)
        case 0x8D: .special(.eisu)
        case 0x8E: .special(.kana)
        case 0x8F: .special(.f16)
        case 0x90: .special(.f17)
        case 0x91: .special(.f18)
        case 0x92: .special(.f19)
        default: nil
        }
    }

    /// AXMenuItemCmdVirtualKey。名前のあるキーはそれに、ほかはキーコードのまま
    static func key(fromVirtualKey code: Int) -> Key? {
        guard (0 ... Int(UInt16.max)).contains(code) else { return nil }
        if let special = VirtualKeyTable.specialKey(forKeyCode: CGKeyCode(code)) { return .special(special) }
        return .keyCode(UInt16(code))
    }

    /// AXMenuItemCmdChar のうち、文字ではないもの（制御文字・NSEvent の F キーなどの私用領域の文字）
    static func specialKey(fromCharacter character: String) -> SpecialKey? {
        guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first else { return nil }
        switch scalar.value {
        case 0x03, 0x0D: return .returnKey
        case 0x09: return .tab
        case 0x20: return .space
        case 0x08, 0x7F: return .delete
        case 0x1B: return .escape
        case 0xF700: return .upArrow
        case 0xF701: return .downArrow
        case 0xF702: return .leftArrow
        case 0xF703: return .rightArrow
        case 0xF704 ... 0xF717:
            return SpecialKey(rawValue: "f\(scalar.value - 0xF704 + 1)")
        case 0xF728: return .forwardDelete
        case 0xF729: return .home
        case 0xF72B: return .end
        case 0xF72C: return .pageUp
        case 0xF72D: return .pageDown
        default: return nil
        }
    }

    private static func isPrintable(_ character: String) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        let value = scalar.value
        return value > 0x20 && value != 0x7F && !(0xF700 ... 0xF8FF).contains(value)
    }

    /// 文字（印字できるもの）→ グリフ → 文字の形の特殊キー → 仮想キーコード の順に見る。どれも無ければショートカットは無い
    static func keySequence(cmdChar: String?, modifiers: Int?, virtualKey: Int?, glyph: Int?) -> KeySequence? {
        let modifierSet = self.modifiers(fromAXMask: modifiers ?? 0)
        let character = cmdChar ?? ""
        let key: Key?
        if character.count == 1, isPrintable(character) {
            key = .character(character.lowercased())
        } else if let glyph, glyph != 0, let glyphKey = self.key(fromGlyph: glyph) {
            key = glyphKey
        } else if let special = specialKey(fromCharacter: character) {
            key = .special(special)
        } else if let virtualKey, virtualKey > 0 {
            // 0 は kVK_ANSI_A だが、ショートカットの無い項目でも 0 が返ることがあるので使わない
            key = self.key(fromVirtualKey: virtualKey)
        } else {
            key = nil
        }
        return key.map { KeySequence([KeyChord($0, modifiers: modifierSet)]) }
    }
}
