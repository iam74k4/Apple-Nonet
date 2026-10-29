// 担当: core-model。設定ファイルの JSON の書式を支える部品（内部用）
import Foundation
import os

let modelLogger = Logger(subsystem: "com.iam74k4.Nonet", category: "core-model")

/// 設定ファイルと書き出しで使う JSON。キーを並べ替えて、保存のたびに同じ形になるようにする
enum ModelJSON {
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

// MARK: - 読めないところを飛ばす

enum DecodingIssue {
    /// ログ用の短い説明。値（キー入力やスクリプトの中身）は含めない
    static func describe(_ error: any Error) -> String {
        guard let error = error as? DecodingError else {
            return String(describing: type(of: error))
        }
        switch error {
        case .typeMismatch(_, let context):
            return "\(path(context.codingPath)): 型が違う"
        case .valueNotFound(_, let context):
            return "\(path(context.codingPath)): 値が無い"
        case .keyNotFound(let key, let context):
            return "\(path(context.codingPath + [key])): キーが無い"
        case .dataCorrupted(let context):
            return "\(path(context.codingPath)): 読めない値"
        @unknown default:
            return "DecodingError"
        }
    }

    static func path(_ codingPath: [any CodingKey]) -> String {
        guard !codingPath.isEmpty else { return "(root)" }
        return codingPath.map { key in
            key.intValue.map { "[\($0)]" } ?? ".\(key.stringValue)"
        }.joined()
    }

    /// 読めずに既定値（マスなら空きマス）にしたところを残す
    static func log(_ what: String, at codingPath: [any CodingKey], error: (any Error)? = nil) {
        let detail = error.map(describe) ?? path(codingPath)
        modelLogger.warning("読めない値を既定値にした（\(what, privacy: .public)）: \(detail, privacy: .public)")
    }
}

extension KeyedDecodingContainer {
    /// 無ければ既定値、読めなければログを残して既定値
    func decodeLossy<T: Decodable>(_ type: T.Type, forKey key: Key, default defaultValue: @autoclosure () -> T) -> T {
        guard contains(key) else { return defaultValue() }
        do {
            if try decodeNil(forKey: key) { return defaultValue() }
            return try decode(T.self, forKey: key)
        } catch {
            DecodingIssue.log(key.stringValue, at: codingPath + [key], error: error)
            return defaultValue()
        }
    }
}

/// 配列の中の、読めない要素だけを nil にする（配列全体を失敗させない）
struct LossyElement<Wrapped: Decodable>: Decodable {
    var value: Wrapped?

    init(from decoder: any Decoder) throws {
        do {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                value = nil
                return
            }
            value = try Wrapped(from: decoder)
        } catch {
            DecodingIssue.log(String(describing: Wrapped.self), at: decoder.codingPath, error: error)
            value = nil
        }
    }
}

// MARK: - キーの書式

/// KeySequence の設定ファイルでの書式。自動の Codable（"_0" や修飾キーのビット値）は読みにくく、
/// Keys.swift の変更にも左右されるので、ここで書式を決めておく。
/// [{"type": "character", "character": "b", "modifiers": ["command"]}, ...]
struct KeySequenceCoding: Codable, Equatable {
    var sequence: KeySequence

    init(_ sequence: KeySequence) {
        self.sequence = sequence
    }

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var chords: [KeyChord] = []
        while !container.isAtEnd {
            chords.append(try container.decode(KeyChordCoding.self).chord)
        }
        sequence = KeySequence(chords)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        for chord in sequence.chords {
            try container.encode(KeyChordCoding(chord))
        }
    }
}

struct KeyChordCoding: Codable, Equatable {
    var chord: KeyChord

    init(_ chord: KeyChord) {
        self.chord = chord
    }

    private enum CodingKeys: String, CodingKey {
        case type, character, special, keyCode, modifiers
    }

    /// 書く順。ModifierSet の表記の順（⌃⌥⇧⌘）と同じ
    static let modifierNames: [(name: String, modifier: ModifierSet)] = [
        ("control", .control),
        ("option", .option),
        ("shift", .shift),
        ("command", .command),
        ("function", .function),
    ]

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let key: Key
        switch type {
        case "character":
            key = .character(try container.decode(String.self, forKey: .character))
        case "special":
            key = .special(try container.decode(SpecialKey.self, forKey: .special))
        case "keyCode":
            key = .keyCode(try container.decode(UInt16.self, forKey: .keyCode))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "未知のキーの種類")
        }

        // 知らない修飾キーを無視すると別のキーを送ってしまうので、打鍵ごと読めないことにする
        var modifiers: ModifierSet = []
        for name in try container.decodeIfPresent([String].self, forKey: .modifiers) ?? [] {
            guard let entry = Self.modifierNames.first(where: { $0.name == name }) else {
                throw DecodingError.dataCorruptedError(forKey: .modifiers, in: container, debugDescription: "未知の修飾キー")
            }
            modifiers.insert(entry.modifier)
        }
        chord = KeyChord(key, modifiers: modifiers)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch chord.key {
        case .character(let character):
            try container.encode("character", forKey: .type)
            try container.encode(character, forKey: .character)
        case .special(let special):
            try container.encode("special", forKey: .type)
            try container.encode(special, forKey: .special)
        case .keyCode(let code):
            try container.encode("keyCode", forKey: .type)
            try container.encode(code, forKey: .keyCode)
        }
        let names = Self.modifierNames.filter { chord.modifiers.contains($0.modifier) }.map(\.name)
        try container.encode(names, forKey: .modifiers)
    }
}
