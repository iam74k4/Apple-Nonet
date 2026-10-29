// 担当: 統合（すべての String Catalog に英語の訳があり、書式指定子が元の文と合っているか）
import Foundation
import Testing

@Suite("String Catalog")
struct LocalizationCatalogTests {
    /// リポジトリの中のカタログ。scripts/sync-strings.sh が文言を集める
    static let catalogs = [
        "Packages/NonetKit/Sources/NonetCore/Resources/Localizable.xcstrings",
        "Packages/NonetKit/Sources/NonetPlatform/Resources/Localizable.xcstrings",
        "Packages/NonetKit/Sources/NonetUI/Resources/Localizable.xcstrings",
        "App/Localizable.xcstrings",
        "App/InfoPlist.xcstrings",
    ]

    static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // NonetCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // NonetKit
            .deletingLastPathComponent() // Packages
            .deletingLastPathComponent()
    }

    struct Entry {
        var key: String
        /// 英語の訳。複数形などの分岐があれば、そのすべて
        var english: [String]
        var hasVariations: Bool
        var states: [String]
    }

    static func entries(in path: String) throws -> [Entry] {
        let data = try Data(contentsOf: repositoryRoot.appendingPathComponent(path))
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(root["sourceLanguage"] as? String == "ja", "\(path) の元の言語は日本語")
        let strings = try #require(root["strings"] as? [String: Any])
        return strings.compactMap { key, value -> Entry? in
            let value = value as? [String: Any] ?? [:]
            if value["extractionState"] as? String == "stale" { return nil }
            if value["shouldTranslate"] as? Bool == false { return nil }
            let localizations = value["localizations"] as? [String: Any] ?? [:]
            guard let english = localizations["en"] as? [String: Any] else {
                return Entry(key: key, english: [], hasVariations: false, states: [])
            }
            var units: [[String: Any]] = []
            collectStringUnits(english, into: &units)
            return Entry(
                key: key,
                english: units.compactMap { $0["value"] as? String },
                hasVariations: english["variations"] != nil,
                states: units.compactMap { $0["state"] as? String }
            )
        }
    }

    static func collectStringUnits(_ node: [String: Any], into units: inout [[String: Any]]) {
        if let unit = node["stringUnit"] as? [String: Any] { units.append(unit) }
        if let variations = node["variations"] as? [String: Any] {
            for case let group as [String: Any] in variations.values {
                for case let child as [String: Any] in group.values {
                    collectStringUnits(child, into: &units)
                }
            }
        }
    }

    /// 書式指定子（%@・%lld・%1$@ など）。位置の番号は無視し、型だけを並べる
    static func specifiers(in text: String) -> [String] {
        let pattern = #"%(?:\d+\$)?[-+ #0]*\d*(?:\.\d+)?(hh|h|ll|l|q|z|t|j)?([@dDiuUxXoOfFeEgGcCsSpaA%])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let conversionRange = Range(match.range(at: 2), in: text) else { return nil }
            let conversion = String(text[conversionRange])
            if conversion == "%" { return nil }
            let length = Range(match.range(at: 1), in: text).map { String(text[$0]) } ?? ""
            return length + conversion
        }
        .sorted()
    }

    @Test("書式指定子の読み取り")
    func specifierParsing() {
        #expect(Self.specifiers(in: "%@ と %lld 個") == ["@", "lld"])
        #expect(Self.specifiers(in: "%2$@ then %1$lld") == ["@", "lld"])
        #expect(Self.specifiers(in: "100%% done") == [])
    }

    @Test("どの文言にも英語の訳がある", arguments: catalogs)
    func everyStringHasEnglish(path: String) throws {
        let missing = try Self.entries(in: path).filter { $0.english.isEmpty }.map(\.key).sorted()
        #expect(missing.isEmpty, "\(path) で英語が無い文言: \(missing)")
    }

    @Test("英語の訳は確定している", arguments: catalogs)
    func translationsAreFinal(path: String) throws {
        let pending = try Self.entries(in: path)
            .filter { entry in entry.states.contains { $0 != "translated" } }
            .map(\.key)
            .sorted()
        #expect(pending.isEmpty, "\(path) で確定していない訳: \(pending)")
    }

    @Test("英語の書式指定子が元の文と合う", arguments: catalogs)
    func specifiersMatch(path: String) throws {
        for entry in try Self.entries(in: path) where !entry.english.isEmpty {
            let source = Self.specifiers(in: entry.key)
            for english in entry.english {
                let translated = Self.specifiers(in: english)
                if entry.hasVariations {
                    // 複数形の one などでは数字を省いてよい
                    #expect(Set(translated).isSubset(of: Set(source)), "\(path): 「\(entry.key)」→「\(english)」")
                } else {
                    #expect(translated == source, "\(path): 「\(entry.key)」→「\(english)」")
                }
            }
        }
    }

    @Test("英語の訳に日本語が残っていない", arguments: catalogs)
    func englishHasNoJapanese(path: String) throws {
        // アプリ名などの固有名詞は英字なので、かな・漢字が残っていれば訳し忘れ
        let japanese = try NSRegularExpression(pattern: #"[\p{Hiragana}\p{Katakana}\p{Han}]"#)
        for entry in try Self.entries(in: path) {
            for english in entry.english {
                let range = NSRange(english.startIndex..., in: english)
                #expect(japanese.firstMatch(in: english, range: range) == nil, "\(path): 「\(english)」")
            }
        }
    }
}
