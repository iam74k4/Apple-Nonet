// 担当: ui-settings
// キー入力の記録。NSEvent の値（キーコード・文字・修飾キー）から KeyChord を作る決まりと、記録の状態
import AppKit
import NonetCore

/// NSEvent の値から KeyChord を作る。NSEvent そのものは受け取らないので、テストで確かめられる
enum SettingsKeyChordConverter {
    static let escapeKeyCode: UInt16 = 0x35

    /// 修飾キーそのもの（⌘・⇧・Caps Lock・⌥・⌃・fn。左右とも）
    static let modifierKeyCodes: Set<UInt16> = [0x36, 0x37, 0x38, 0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E, 0x3F]

    /// 文字で表せないキー（kVK_*）。テンキーの Enter（0x4C）は Return と別のキーなので入れない
    static let specialKeys: [UInt16: SpecialKey] = [
        0x24: .returnKey, 0x30: .tab, 0x31: .space, 0x33: .delete, 0x75: .forwardDelete, 0x35: .escape,
        0x7B: .leftArrow, 0x7C: .rightArrow, 0x7D: .downArrow, 0x7E: .upArrow,
        0x73: .home, 0x77: .end, 0x74: .pageUp, 0x79: .pageDown,
        0x7A: .f1, 0x78: .f2, 0x63: .f3, 0x76: .f4, 0x60: .f5, 0x61: .f6, 0x62: .f7, 0x64: .f8,
        0x65: .f9, 0x6D: .f10, 0x67: .f11, 0x6F: .f12, 0x69: .f13, 0x6B: .f14, 0x71: .f15, 0x6A: .f16,
        0x40: .f17, 0x4F: .f18, 0x50: .f19, 0x5A: .f20,
        0x66: .eisu, 0x68: .kana,
    ]

    /// macOS が fn の印を自動で付けるキー。押した人は fn を押していないので外す
    static let keysWithImplicitFunction: Set<SpecialKey> = {
        var keys: Set<SpecialKey> = [.leftArrow, .rightArrow, .upArrow, .downArrow, .home, .end, .pageUp, .pageDown, .forwardDelete]
        let functionKeys: [SpecialKey] = [.f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10,
                                          .f11, .f12, .f13, .f14, .f15, .f16, .f17, .f18, .f19, .f20]
        keys.formUnion(functionKeys)
        return keys
    }()

    static func modifiers(from flags: NSEvent.ModifierFlags) -> ModifierSet {
        var modifiers: ModifierSet = []
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.function) { modifiers.insert(.function) }
        return modifiers
    }

    /// 押したキーの組み合わせ。修飾キーだけなら nil。
    /// characters は修飾キーを付けずに入力される文字（NSEvent.characters(byApplyingModifiers: [])）。
    /// ⇧4 を "$" ではなく "4"＋⇧ として残す（キーを送るときに配列から探すのと同じ書き方）
    static func chord(keyCode: UInt16, characters: String?, flags: NSEvent.ModifierFlags) -> KeyChord? {
        guard !modifierKeyCodes.contains(keyCode) else { return nil }
        var modifiers = modifiers(from: flags)
        if let special = specialKeys[keyCode] {
            if keysWithImplicitFunction.contains(special) {
                modifiers.remove(.function)
            }
            return KeyChord(.special(special), modifiers: modifiers)
        }
        // テンキーは本体の同じ文字のキーと区別するアプリがあるので、キーコードのまま残す
        if flags.contains(.numericPad) {
            return KeyChord(.keyCode(keyCode), modifiers: modifiers)
        }
        if let character = printableCharacter(characters) {
            return KeyChord(.character(character.lowercased()), modifiers: modifiers)
        }
        return KeyChord(.keyCode(keyCode), modifiers: modifiers)
    }

    /// 1文字で、見える文字なら返す（制御文字・空白・NSF1FunctionKey などの私用領域は除く）
    static func printableCharacter(_ characters: String?) -> String? {
        guard let characters, characters.count == 1, let scalar = characters.unicodeScalars.first else { return nil }
        let properties = scalar.properties
        if properties.isWhitespace { return nil }
        switch properties.generalCategory {
        case .control, .format, .privateUse, .surrogate, .unassigned, .lineSeparator, .paragraphSeparator,
             .spaceSeparator, .nonspacingMark, .enclosingMark, .spacingMark:
            return nil
        default:
            return characters
        }
    }

    /// 修飾キーだけの表記（"⌃⌥⇧⌘"・fn は先頭に "fn "）。KeyChord.displayString と同じ順
    static func modifierPrefix(_ modifiers: ModifierSet) -> String {
        var text = modifiers.contains(.function) ? "fn " : ""
        let ordered: [(ModifierSet, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        for (modifier, glyph) in ordered where modifiers.contains(modifier) {
            text += glyph
        }
        return text
    }
}

/// 記録欄の状態。キーを押すたびに打鍵を足し、最大4つで終わる。修飾キーなしの Esc で取り消す
struct SettingsKeyRecorder: Equatable {
    static let maximumChords = 4

    enum Outcome: Equatable {
        /// 記録を続ける
        case recording
        /// 記録を終えた。値を保存する
        case finished(KeySequence)
        /// 何も変えずに終えた
        case cancelled
    }

    private(set) var isRecording = false
    private(set) var chords: [KeyChord] = []
    /// いま押している修飾キー（表示用）
    private(set) var heldModifiers: ModifierSet = []

    mutating func start() {
        isRecording = true
        chords = []
        heldModifiers = []
    }

    mutating func keyDown(keyCode: UInt16, characters: String?, flags: NSEvent.ModifierFlags) -> Outcome {
        guard isRecording else { return .cancelled }
        let modifiers = SettingsKeyChordConverter.modifiers(from: flags)
        if keyCode == SettingsKeyChordConverter.escapeKeyCode, modifiers.subtracting(.function).isEmpty {
            cancel()
            return .cancelled
        }
        guard let chord = SettingsKeyChordConverter.chord(keyCode: keyCode, characters: characters, flags: flags) else {
            return .recording
        }
        return append(chord)
    }

    /// Esc を打鍵として足す（Esc を押すと取り消しになるため、ボタンから）
    mutating func appendEscape() -> Outcome {
        guard isRecording else { return .cancelled }
        return append(KeyChord(.special(.escape), modifiers: heldModifiers))
    }

    mutating func flagsChanged(_ flags: NSEvent.ModifierFlags) {
        guard isRecording else { return }
        heldModifiers = SettingsKeyChordConverter.modifiers(from: flags)
    }

    /// 最後の打鍵を消す
    mutating func removeLast() {
        guard isRecording, !chords.isEmpty else { return }
        chords.removeLast()
    }

    /// 記録を終える。1つも押していなければ取り消しと同じ
    mutating func finish() -> Outcome {
        guard isRecording else { return .cancelled }
        let recorded = chords
        cancel()
        return recorded.isEmpty ? .cancelled : .finished(KeySequence(recorded))
    }

    mutating func cancel() {
        isRecording = false
        chords = []
        heldModifiers = []
    }

    /// 記録中に出す文（"⌘L → ⌘…"）。何も押していなければ nil
    var progressText: String? {
        var parts = chords.map(\.displayString)
        if !heldModifiers.isEmpty, chords.count < Self.maximumChords {
            parts.append(SettingsKeyChordConverter.modifierPrefix(heldModifiers) + "…")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " → ")
    }

    private mutating func append(_ chord: KeyChord) -> Outcome {
        chords.append(chord)
        if chords.count >= Self.maximumChords {
            return finish()
        }
        return .recording
    }
}

/// 表記を打ち込んで決めるとき（"⌘L → ⌘C"・"cmd+shift+4"）
enum SettingsKeyNotationInput: Equatable {
    case empty
    case invalid
    /// 打鍵が多すぎる
    case tooLong
    case valid(KeySequence)

    init(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            self = .empty
            return
        }
        guard let sequence = KeySequence(parsing: trimmed), !sequence.chords.isEmpty else {
            self = .invalid
            return
        }
        self = sequence.chords.count > SettingsKeyRecorder.maximumChords ? .tooLong : .valid(sequence)
    }

    var message: String? {
        switch self {
        case .empty, .valid: nil
        case .invalid: String(localized: "キーの表記を読み取れませんでした（例: ⌘B、⇧⌘4、⌘L → ⌘C）", bundle: .module)
        case .tooLong: String(localized: "続けて押すキーは4つまでです", bundle: .module)
        }
    }
}
