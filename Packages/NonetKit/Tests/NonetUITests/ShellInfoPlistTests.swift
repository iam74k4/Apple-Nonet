// 担当: ui-shell
// App/Info.plist（project.yml から XcodeGen で作る）と、その文言のカタログ（App/InfoPlist.xcstrings）
import Foundation
import Testing

@Suite("Info.plist")
struct ShellInfoPlistTests {
    static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // NonetUITests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // NonetKit
            .deletingLastPathComponent() // Packages
            .deletingLastPathComponent()
    }

    static func catalogValue(_ key: String, language: String) throws -> String {
        let data = try Data(contentsOf: repositoryRoot.appending(path: "App/InfoPlist.xcstrings"))
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try #require(root["strings"] as? [String: Any])
        let entry = try #require(strings[key] as? [String: Any])
        let localizations = try #require(entry["localizations"] as? [String: Any])
        let localization = try #require(localizations[language] as? [String: Any])
        let unit = try #require(localization["stringUnit"] as? [String: Any])
        return try #require(unit["value"] as? String)
    }

    /// Apple Events を送るのは、ブラウザに表示中のページの URL を尋ねるときだけ。書類の場所はアクセシビリティで読み、
    /// 「ターミナルで実行」は .command のファイルを NSWorkspace で開く。許可を求める説明にもそれだけを書く
    @Test("オートメーションの説明はブラウザの URL のことだけ。project.yml・Info.plist・カタログが同じ")
    func appleEventsUsageDescription() throws {
        let key = "NSAppleEventsUsageDescription"
        let data = try Data(contentsOf: Self.repositoryRoot.appending(path: "App/Info.plist"))
        let info = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let description = try #require(info[key] as? String)
        #expect(try Self.catalogValue(key, language: "ja") == description)
        let project = try String(contentsOf: Self.repositoryRoot.appending(path: "project.yml"), encoding: .utf8)
        #expect(project.contains("\(key): \"\(description)\""), "project.yml を変えたら xcodegen generate で Info.plist を作り直す")

        let english = try Self.catalogValue(key, language: "en")
        #expect(english.contains("browser"))
        #expect(english.contains("URL"))
        #expect(!english.contains("Terminal"))
        #expect(!english.contains("document"))
    }
}
