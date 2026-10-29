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
        fatalError("未実装: keys-license")
    }
}

extension KeySequence {
    /// "⌘L → ⌘C" のような表記
    public var displayString: String {
        fatalError("未実装: keys-license")
    }

    /// displayString と同じ書式を読む。読めなければ nil
    public init?(parsing text: String) {
        fatalError("未実装: keys-license")
    }
}
