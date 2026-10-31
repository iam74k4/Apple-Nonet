// 担当: core-model。モデルのテストで使う部品
import Foundation
@testable import NonetCore
import Testing

enum ModelFixtures {
    /// 実行環境の言語で引いた NonetCore の文言。テストが日本語・英語のどちらでも通るように
    static func text(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .nonetCore)
    }

    static var globalName: String { text("グローバル") }

    static let safari = AppReference(bundleID: "com.apple.Safari", name: "Safari")
    static let xcode = AppReference(bundleID: "com.apple.dt.Xcode", name: "Xcode")
    static let figma = AppReference(bundleID: "com.figma.Desktop", name: "Figma")
    static let slack = AppReference(bundleID: "com.tinyspeck.slackmacgap", name: "Slack")

    static func cell(_ title: String, id: UUID = UUID(), action: Action? = nil) -> Cell {
        Cell(id: id, title: title, icon: .symbol("star"), action: action ?? .openURL(URLAction(url: "https://example.com/\(title)")))
    }

    /// タイトルを並べたページ。nil は空きマス
    static func page(_ titles: [String?]) -> Page {
        Page(cells: titles.map { $0.map { cell($0) } })
    }

    static func profile(_ app: AppReference, pageCount: Int = 1, isEnabled: Bool = true, prefix: String? = nil) -> Profile {
        let name = prefix ?? app.name
        let pages = (0..<pageCount).map { page($0 == 0 ? ["\(name)-\($0)"] : ["\(name)-\($0)", nil, "\(name)-\($0)b"]) }
        return Profile(kind: .app(app), pages: pages, isEnabled: isEnabled)
    }

    static func globalProfile(pageCount: Int = 1) -> Profile {
        Profile(kind: .global, pages: (0..<pageCount).map { page(["global-\($0)"]) })
    }

    /// グローバル＋Safari＋Xcode
    static func configuration(settings: GlobalSettings = GlobalSettings()) -> NonetConfiguration {
        NonetConfiguration(settings: settings, profiles: [globalProfile(), profile(safari), profile(xcode, pageCount: 2)])
    }

    /// keystroke 以外のすべての種類（summary を呼べるもの）
    static let nonKeystrokeActions: [Action] = [
        .launchApp(LaunchAppAction(app: safari, hideIfFrontmost: true)),
        .openURL(URLAction(url: "https://www.apple.com/jp/")),
        .script(ScriptAction(source: "cd \"$PROJECT_DIR\" && claude", runMode: .terminal, timeout: 120)),
        .shortcut(ShortcutAction(name: "マイクのミュート", passSelectedText: true)),
        .menuItem(MenuItemAction(app: figma, path: ["オブジェクト", "自動レイアウトを追加"], keyEquivalent: .key("a", [.shift]))),
        .ai(AIAction(prompt: "要約して", output: .copyToClipboard)),
        .file(FileAction(operation: .trash)),
        .file(FileAction(operation: .move, destination: "~/Documents/整理")),
    ]

    static let allActions: [Action] = [
        .keystroke(.key("b", [.command])),
        .keystroke(.sequence(.key("l", [.command]), .key("c", [.command]))),
        .keystroke(.special(.returnKey, [.control, .option, .shift, .command, .function])),
        .keystroke(KeySequence([KeyChord(.keyCode(0x66))])),
        .keystroke(KeySequence([])),
        .menuItem(MenuItemAction(path: ["編集", "コピー"])),
        .script(ScriptAction(source: "echo hi")),
        .ai(AIAction(prompt: "直して", output: .replaceSelection)),
    ] + nonKeystrokeActions

    // MARK: JSON

    static func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try ModelJSON.makeDecoder().decode(T.self, from: Data(json.utf8))
    }

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        try ModelJSON.makeEncoder().encode(value)
    }

    static func roundTrip<T: Codable>(_ value: T) throws -> T {
        try ModelJSON.makeDecoder().decode(T.self, from: encode(value))
    }

    /// 書いた JSON をオブジェクトとして比べるため
    static func jsonObject<T: Encodable>(_ value: T) throws -> NSDictionary {
        try #require(JSONSerialization.jsonObject(with: encode(value)) as? NSDictionary)
    }

    static func jsonObject(_ json: String) throws -> NSDictionary {
        try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? NSDictionary)
    }

    static func string(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self)
    }

    // MARK: ファイル

    /// テストごとの一時フォルダ。終わったら消す
    static func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "NonetModelTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url) }
        try body(url)
    }

    static func fileNames(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)).sorted()
    }
}

extension NonetConfiguration {
    /// テスト用: すべてのマスの id
    var modelCellIDs: [UUID] {
        profiles.flatMap { $0.pages.flatMap { $0.cells.compactMap { $0?.id } } }
    }

    var modelAppProfiles: [Profile] {
        profiles.filter { !$0.isGlobal }
    }
}

extension Profile {
    /// テスト用: マスのタイトル（空きマスは nil）
    var modelTitles: [[String?]] {
        pages.map { $0.cells.map { $0?.title } }
    }
}
