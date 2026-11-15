// 担当: ui-settings
// 読み込むキー入力が、今のキー配列で実際に入力する文字。Return と同じ文字（⌃M・⌃J・テンキーの Enter など）を押すかを確かめるのに使う
import Carbon.HIToolbox
import Foundation
import NonetCore

/// 打鍵が今のキー配列で入力する文字（修飾キー込み）。分からなければ nil
protocol SettingsKeyCharacterTranslating: AnyObject {
    func characters(for chord: KeyChord) -> String?
}

/// 今のキー配列（UCKeyTranslate）で調べる。入力メソッドが指定するキー配列、今のキー配列、ASCII を打てるキー配列の順
/// （送るとき（NonetPlatform の KeyboardLayoutResolver）と同じ順）
final class SettingsLayoutKeyTranslator: SettingsKeyCharacterTranslating {
    func characters(for chord: KeyChord) -> String? {
        for layout in Self.currentLayouts() {
            if let text = layout.withUnsafeBytes({ raw -> String? in
                guard let pointer = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
                return Self.characters(for: chord) { code, state in Self.translate(pointer, keyCode: code, modifierState: state) }
            }) {
                return text
            }
        }
        return nil
    }

    /// translate(キーコード, 修飾キーの状態) で、打鍵が入力する文字。文字のキーは、修飾キーなし（無ければ ⇧）でその文字になるキーを探す
    static func characters(for chord: KeyChord, translate: (UInt16, UInt32) -> String?) -> String? {
        var modifiers = chord.modifiers
        let keyCode: UInt16
        switch chord.key {
        case .keyCode(let code):
            keyCode = code
        case .character(let character):
            if let code = (0 ..< 128).map(UInt16.init).first(where: { translate($0, 0) == character }) {
                keyCode = code
            } else if let code = (0 ..< 128).map(UInt16.init).first(where: { translate($0, modifierState([.shift])) == character }) {
                keyCode = code
                modifiers.insert(.shift)
            } else {
                return nil
            }
        case .special:
            return nil
        }
        return translate(keyCode, modifierState(modifiers))
    }

    /// UCKeyTranslate に渡す修飾キーの状態（EventModifiers を 8 ビット右にずらした値）
    static func modifierState(_ modifiers: ModifierSet) -> UInt32 {
        var state = 0
        if modifiers.contains(.command) { state |= cmdKey }
        if modifiers.contains(.shift) { state |= shiftKey }
        if modifiers.contains(.option) { state |= optionKey }
        if modifiers.contains(.control) { state |= controlKey }
        return UInt32(state >> 8) & 0xFF
    }

    private static func currentLayouts() -> [Data] {
        let override = TISCopyInputMethodKeyboardLayoutOverride()?.takeRetainedValue()
        let current = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue()
        let ascii = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue()
        return [override, current, ascii].compactMap { source -> Data? in
            guard let source, let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
            let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
            return data.isEmpty ? nil : data
        }
    }

    private static func translate(_ layout: UnsafePointer<UCKeyboardLayout>, keyCode: UInt16, modifierState: UInt32) -> String? {
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 8)
        let status = UCKeyTranslate(
            layout, keyCode, UInt16(kUCKeyActionDown), modifierState, UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeyState, characters.count, &length, &characters
        )
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length)
    }
}
