// 担当: keys-license（公開 API は契約。displayString / parsing の実装を担当する）
import Foundation

/// 修飾キー
public struct ModifierSet: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let control = ModifierSet(rawValue: 1 << 0)
    public static let option = ModifierSet(rawValue: 1 << 1)
    public static let shift = ModifierSet(rawValue: 1 << 2)
    public static let command = ModifierSet(rawValue: 1 << 3)
    /// fn（🌐）
    public static let function = ModifierSet(rawValue: 1 << 4)
}

/// 文字で表せないキー
public enum SpecialKey: String, Codable, CaseIterable, Hashable, Sendable {
    case returnKey, tab, space, delete, forwardDelete, escape
    case leftArrow, rightArrow, upArrow, downArrow
    case home, end, pageUp, pageDown
    case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10
    case f11, f12, f13, f14, f15, f16, f17, f18, f19, f20
    /// JIS 配列の「英数」「かな」
    case eisu, kana
}

public enum Key: Codable, Hashable, Sendable {
    /// 修飾キーなしで入力される1文字（英字は小文字）。送るときに現在のキー配列から仮想キーコードを探す
    case character(String)
    case special(SpecialKey)
    /// 仮想キーコード（kVK_*）をそのまま送る
    case keyCode(UInt16)
}

/// 同時に押すキーの組み合わせ（例: ⇧⌘4）
public struct KeyChord: Codable, Hashable, Sendable {
    public var key: Key
    public var modifiers: ModifierSet

    public init(_ key: Key, modifiers: ModifierSet = []) {
        self.key = key
        self.modifiers = modifiers
    }
}

/// 順に押す組み合わせ（例: ⌘L → ⌘C）
public struct KeySequence: Codable, Hashable, Sendable {
    public var chords: [KeyChord]

    public init(_ chords: [KeyChord]) {
        self.chords = chords
    }

    /// 1文字＋修飾キーの1打。プリセットを書くための近道
    public static func key(_ character: String, _ modifiers: ModifierSet = []) -> KeySequence {
        KeySequence([KeyChord(.character(character.lowercased()), modifiers: modifiers)])
    }

    public static func special(_ key: SpecialKey, _ modifiers: ModifierSet = []) -> KeySequence {
        KeySequence([KeyChord(.special(key), modifiers: modifiers)])
    }

    /// 複数の打鍵をつなげる
    public static func sequence(_ parts: KeySequence...) -> KeySequence {
        KeySequence(parts.flatMap(\.chords))
    }
}

extension KeyChord {
    /// "⇧⌘4" のような表記。修飾キーは ⌃⌥⇧⌘ の順で、英字は大文字で表示する
    public var displayString: String {
        KeyNotation.prefix(for: modifiers) + KeyNotation.display(key)
    }
}

extension KeySequence {
    /// "⌘L → ⌘C" のような表記
    public var displayString: String {
        chords.map(\.displayString).joined(separator: KeyNotation.sequenceSeparator)
    }

    /// displayString と同じ書式を読む。読めなければ nil。
    /// 修飾キーの順は問わず、空白は省略できる。打鍵の区切りは「→」「->」「,」。
    /// 修飾キーは「cmd+shift+4」のような英語の名前と「+」でも書ける
    public init?(parsing text: String) {
        var parser = KeyNotationParser(text)
        guard let chords = parser?.parse() else { return nil }
        self.init(chords)
    }
}

// MARK: - 表記

/// キーの表記の決まり。表示と読み取りで同じ表を使う
enum KeyNotation {
    static let sequenceSeparator = " → "
    /// fn は記号ではなく文字で出す。続く記号と区別するため空白を空ける
    static let functionPrefix = "fn "

    /// Apple の順（⌃⌥⇧⌘）
    static let modifierGlyphs: [(ModifierSet, Character)] = [
        (.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘"),
    ]

    static func prefix(for modifiers: ModifierSet) -> String {
        var text = modifiers.contains(.function) ? functionPrefix : ""
        for (modifier, glyph) in modifierGlyphs where modifiers.contains(modifier) {
            text.append(glyph)
        }
        return text
    }

    static func display(_ key: Key) -> String {
        switch key {
        case .character(let character): display(character: character)
        case .special(let special): symbol(for: special)
        case .keyCode(let code): "keyCode(\(code))"
        }
    }

    static func symbol(for key: SpecialKey) -> String {
        switch key {
        case .returnKey: "↩"
        case .tab: "⇥"
        case .space: "Space"
        case .delete: "⌫"
        case .forwardDelete: "⌦"
        case .escape: "⎋"
        case .leftArrow: "←"
        case .rightArrow: "→"
        case .upArrow: "↑"
        case .downArrow: "↓"
        case .home: "↖"
        case .end: "↘"
        case .pageUp: "⇞"
        case .pageDown: "⇟"
        case .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10,
             .f11, .f12, .f13, .f14, .f15, .f16, .f17, .f18, .f19, .f20:
            key.rawValue.uppercased()
        case .eisu: "英数"
        case .kana: "かな"
        }
    }

    static func display(character: String) -> String {
        // メニューのキー（NSMenuItem.keyEquivalent）では制御文字で表されるもの
        switch character {
        case " ": return symbol(for: .space)
        case "\r", "\n", "\r\n", "\u{3}": return symbol(for: .returnKey)
        case "\t": return symbol(for: .tab)
        case "\u{8}", "\u{7F}": return symbol(for: .delete)
        case "\u{1B}": return symbol(for: .escape)
        default: break
        }
        let scalars = character.unicodeScalars
        if scalars.count == 1, let scalar = scalars.first, isInvisible(scalar) {
            return unicodeEscape(scalar)
        }
        // "ß" → "SS" のように元に戻せない大文字にはしない
        let uppercased = character.uppercased()
        return uppercased.count == 1 && uppercased.lowercased() == character ? uppercased : character
    }

    static func unicodeEscape(_ scalar: Unicode.Scalar) -> String {
        let hex = String(scalar.value, radix: 16, uppercase: true)
        return "U+" + String(repeating: "0", count: max(0, 4 - hex.count)) + hex
    }

    /// 見えない文字。表示では U+XXXX と書く
    static func isInvisible(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.properties.isWhitespace { return true }
        switch scalar.properties.generalCategory {
        case .control, .format, .lineSeparator, .paragraphSeparator, .spaceSeparator, .privateUse, .surrogate, .unassigned:
            return true
        default:
            return false
        }
    }

    // MARK: 読み取りの表

    static let modifierForGlyph: [Character: ModifierSet] = [
        "⌃": .control, "⌥": .option, "⇧": .shift, "⌘": .command,
        "🌐": .function, "🌐\u{FE0F}": .function,
    ]

    /// 小文字で引く
    static let modifierWords: [String: ModifierSet] = [
        "cmd": .command, "command": .command,
        "opt": .option, "option": .option, "alt": .option,
        "ctrl": .control, "control": .control,
        "shift": .shift,
        "fn": .function, "function": .function, "globe": .function,
    ]

    static let keyForGlyph: [Character: Key] = [
        "↩": .special(.returnKey), "⏎": .special(.returnKey), "⌤": .special(.returnKey),
        "⇥": .special(.tab), "␣": .special(.space),
        "⌫": .special(.delete), "⌦": .special(.forwardDelete), "⎋": .special(.escape),
        "←": .special(.leftArrow), "→": .special(.rightArrow), "↑": .special(.upArrow), "↓": .special(.downArrow),
        "↖": .special(.home), "↘": .special(.end), "⇞": .special(.pageUp), "⇟": .special(.pageDown),
    ]

    /// 英数字以外を含む、2文字以上のキーの名前
    static let multiCharacterNames: [(name: [Character], key: Key)] = [
        (Array("英数"), .special(.eisu)), (Array("かな"), .special(.kana)), (Array("スペース"), .special(.space)),
    ]

    /// 2文字以上の英数字のキーの名前（小文字で引く）。SpecialKey の rawValue も読める
    static let keyWords: [String: Key] = {
        var words: [String: Key] = [:]
        for key in SpecialKey.allCases {
            words[key.rawValue.lowercased()] = .special(key)
        }
        let aliases: [String: SpecialKey] = [
            "return": .returnKey, "enter": .returnKey,
            "spacebar": .space, "backspace": .delete, "fwddelete": .forwardDelete, "esc": .escape,
            "left": .leftArrow, "right": .rightArrow, "up": .upArrow, "down": .downArrow,
            "pgup": .pageUp, "pgdn": .pageDown,
        ]
        for (word, key) in aliases {
            words[word] = .special(key)
        }
        // 区切りや記号と紛らわしい文字を名前で書けるようにする（例: command+plus）
        let characters: [String: String] = [
            "plus": "+", "minus": "-", "hyphen": "-", "equal": "=", "equals": "=",
            "comma": ",", "period": ".", "dot": ".", "slash": "/", "backslash": "\\",
            "semicolon": ";", "colon": ":", "quote": "'", "apostrophe": "'",
            "grave": "`", "backquote": "`", "backtick": "`",
            "leftbracket": "[", "rightbracket": "]", "caret": "^", "underscore": "_", "yen": "¥",
        ]
        for (word, character) in characters {
            words[word] = .character(character)
        }
        return words
    }()
}

// MARK: - 読み取り

/// KeySequence(parsing:) の中身。
/// 打鍵 = 修飾キー* キー。修飾キーの後の「+」はつなぎか「+」キーのどちらにもなり得るので、
/// つなぎとして読む方を先に試し、全体が読めなければ「+」キーとして読み直す
struct KeyNotationParser {
    /// これより長い入力は表記として扱わない
    static let maximumLength = 1000

    private let characters: [Character]
    /// 位置ごとの、そこから最後までの読み取り結果
    private var memo: [Int: [KeyChord]?] = [:]

    init?(_ text: String) {
        let characters = Array(text)
        guard characters.count <= Self.maximumLength else { return nil }
        self.characters = characters
    }

    mutating func parse() -> [KeyChord]? {
        sequence(from: 0)
    }

    private mutating func sequence(from start: Int) -> [KeyChord]? {
        if let cached = memo[start] {
            return cached
        }
        var result: [KeyChord]?
        for (chord, end) in chords(at: start, modifiers: []) {
            let next = skipWhitespace(from: end)
            if next == characters.count {
                result = [chord]
                break
            }
            if let afterSeparator = separatorEnd(at: next), let rest = sequence(from: afterSeparator) {
                result = [chord] + rest
                break
            }
        }
        memo[start] = .some(result)
        return result
    }

    /// start から読める打鍵の候補（優先順）と、その終わりの位置
    private func chords(at start: Int, modifiers: ModifierSet) -> [(KeyChord, Int)] {
        let position = skipWhitespace(from: start)
        if let (modifier, end) = modifier(at: position) {
            let combined = modifiers.union(modifier)
            let next = skipWhitespace(from: end)
            guard next < characters.count, characters[next] == "+" else {
                return chords(at: end, modifiers: combined)
            }
            return chords(at: next + 1, modifiers: combined) + [(KeyChord(.character("+"), modifiers: combined), next + 1)]
        }
        if let (key, end) = key(at: position) {
            return [(KeyChord(key, modifiers: modifiers), end)]
        }
        return []
    }

    private func modifier(at position: Int) -> (ModifierSet, Int)? {
        guard position < characters.count else { return nil }
        if let modifier = KeyNotation.modifierForGlyph[characters[position]] {
            return (modifier, position + 1)
        }
        let end = asciiWordEnd(from: position)
        guard end > position, let modifier = KeyNotation.modifierWords[word(position, end).lowercased()] else { return nil }
        return (modifier, end)
    }

    private func key(at position: Int) -> (Key, Int)? {
        guard position < characters.count else { return nil }
        if let escaped = unicodeEscape(at: position) {
            return escaped
        }
        let end = asciiWordEnd(from: position)
        if end > position {
            let text = word(position, end)
            if end - position == 1 {
                return (.character(text.lowercased()), end)
            }
            let lowercased = text.lowercased()
            if let key = KeyNotation.keyWords[lowercased] {
                return (key, end)
            }
            return keyCode(name: lowercased, end: end)
        }
        for (name, key) in KeyNotation.multiCharacterNames where matches(name, at: position) {
            return (key, position + name.count)
        }
        let character = characters[position]
        if let key = KeyNotation.keyForGlyph[character] {
            return (key, position + 1)
        }
        guard let first = character.unicodeScalars.first, !KeyNotation.isInvisible(first),
              KeyNotation.modifierForGlyph[character] == nil else { return nil }
        return (.character(String(character).lowercased()), position + 1)
    }

    /// "keyCode(53)" または "keyCode53"
    private func keyCode(name: String, end: Int) -> (Key, Int)? {
        let prefix = "keycode"
        guard name.hasPrefix(prefix) else { return nil }
        let digits = name.dropFirst(prefix.count)
        if !digits.isEmpty {
            guard digits.allSatisfy(\.isASCIIDigit), let code = UInt16(digits) else { return nil }
            return (.keyCode(code), end)
        }
        var position = skipWhitespace(from: end)
        guard position < characters.count, characters[position] == "(" else { return nil }
        position = skipWhitespace(from: position + 1)
        var digitEnd = position
        while digitEnd < characters.count, characters[digitEnd].isASCIIDigit {
            digitEnd += 1
        }
        guard digitEnd > position, let code = UInt16(word(position, digitEnd)) else { return nil }
        position = skipWhitespace(from: digitEnd)
        guard position < characters.count, characters[position] == ")" else { return nil }
        return (.keyCode(code), position + 1)
    }

    /// 見えない文字の "U+XXXX"
    private func unicodeEscape(at position: Int) -> (Key, Int)? {
        guard position + 1 < characters.count, characters[position] == "U" || characters[position] == "u",
              characters[position + 1] == "+" else { return nil }
        let start = position + 2
        var end = start
        while end < characters.count, characters[end].isASCII, characters[end].isHexDigit {
            end += 1
        }
        guard (4...6).contains(end - start), !(end < characters.count && characters[end].isASCIIAlphanumeric),
              let value = UInt32(word(start, end), radix: 16), let scalar = Unicode.Scalar(value) else { return nil }
        return (.character(String(Character(scalar)).lowercased()), end)
    }

    private func separatorEnd(at position: Int) -> Int? {
        guard position < characters.count else { return nil }
        switch characters[position] {
        case "→", ",":
            return position + 1
        case "-" where position + 1 < characters.count && characters[position + 1] == ">":
            return position + 2
        default:
            return nil
        }
    }

    private func skipWhitespace(from position: Int) -> Int {
        var position = position
        while position < characters.count, characters[position].isWhitespace {
            position += 1
        }
        return position
    }

    private func asciiWordEnd(from position: Int) -> Int {
        var end = position
        while end < characters.count, characters[end].isASCIIAlphanumeric {
            end += 1
        }
        return end
    }

    private func matches(_ name: [Character], at position: Int) -> Bool {
        position + name.count <= characters.count && Array(characters[position..<(position + name.count)]) == name
    }

    private func word(_ start: Int, _ end: Int) -> String {
        String(characters[start..<end])
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isWholeNumber }
    var isASCIIAlphanumeric: Bool { isASCII && (isLetter || isNumber) }
}
