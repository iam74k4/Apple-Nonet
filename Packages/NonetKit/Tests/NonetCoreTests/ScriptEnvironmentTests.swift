import Foundation
import Testing
@testable import NonetCore

@Suite struct ScriptEnvironmentTests {
    private static let home = "/Users/me"

    private static func project(_ path: String, existing: Set<String>, home: String = home) -> String {
        ScriptEnvironment.projectDirectory(forDocumentPath: path, homeDirectory: home) { existing.contains($0) }
    }

    // MARK: - 環境変数

    @Test func includesEveryValue() {
        let info = ScriptContextInfo(
            app: AppReference(bundleID: "com.apple.dt.Xcode", name: "Xcode"),
            documentPath: "/Users/me/Dev/App/App.xcodeproj",
            browserURL: "https://example.com/a?b=c",
            selectedText: "選択中の\nテキスト"
        )
        let variables = ScriptEnvironment.variables(for: info, projectDirectory: "/Users/me/Dev/App")
        #expect(variables == [
            "NONET_APP_BUNDLE_ID": "com.apple.dt.Xcode",
            "NONET_APP_NAME": "Xcode",
            "NONET_DOCUMENT_PATH": "/Users/me/Dev/App/App.xcodeproj",
            "NONET_BROWSER_URL": "https://example.com/a?b=c",
            "NONET_SELECTED_TEXT": "選択中の\nテキスト",
            "NONET_PROJECT_DIR": "/Users/me/Dev/App",
            "PROJECT_DIR": "/Users/me/Dev/App",
        ])
    }

    /// 書類がホームそのもの（ホームで開いたターミナルのウインドウ）なら、その上の /Users ではなくホーム
    @Test func aHomeDocumentStaysAtHome() {
        #expect(Self.project("/Users/me", existing: []) == "/Users/me")
        #expect(Self.project("file:///Users/me/", existing: []) == "/Users/me")
        // ホームの中のフォルダはこれまでどおり
        #expect(Self.project("/Users/me/notes.txt", existing: []) == "/Users/me")
    }

    @Test func omitsMissingAndEmptyValues() {
        #expect(ScriptEnvironment.variables(for: ScriptContextInfo(), projectDirectory: nil).isEmpty)
        let empty = ScriptContextInfo(app: AppReference(bundleID: "", name: ""), documentPath: "", browserURL: "", selectedText: "")
        #expect(ScriptEnvironment.variables(for: empty, projectDirectory: "").isEmpty)
        let appOnly = ScriptEnvironment.variables(for: ScriptContextInfo(app: AppReference(bundleID: "com.figma.Desktop", name: "Figma")), projectDirectory: nil)
        #expect(appOnly == ["NONET_APP_BUNDLE_ID": "com.figma.Desktop", "NONET_APP_NAME": "Figma"])
    }

    @Test func normalizesDocumentAndProjectPaths() {
        // アクセシビリティの AXDocument は file:// の URL で、末尾に「/」が付くことがある
        let info = ScriptContextInfo(documentPath: "file:///Users/me/My%20App/App.xcodeproj/")
        let variables = ScriptEnvironment.variables(for: info, projectDirectory: "/Users/me/My App/")
        #expect(variables["NONET_DOCUMENT_PATH"] == "/Users/me/My App/App.xcodeproj")
        #expect(variables["NONET_PROJECT_DIR"] == "/Users/me/My App")
        #expect(variables["PROJECT_DIR"] == "/Users/me/My App")
    }

    @Test func removesNULAndTruncatesHugeValues() throws {
        let info = ScriptContextInfo(browserURL: "https://a\0b", selectedText: String(repeating: "あ", count: 100_000))
        let variables = ScriptEnvironment.variables(for: info, projectDirectory: nil)
        #expect(variables["NONET_BROWSER_URL"] == "https://ab")
        let text = try #require(variables["NONET_SELECTED_TEXT"])
        #expect(text.utf8.count <= ScriptEnvironment.maximumValueLength)
        #expect(text.utf8.count > ScriptEnvironment.maximumValueLength - 3)
        #expect(text.allSatisfy { $0 == "あ" })
        #expect(ScriptEnvironment.variables(for: ScriptContextInfo(selectedText: "\0\0"), projectDirectory: nil).isEmpty)
    }

    // MARK: - プロジェクトのフォルダ

    static let bundleCases: [(String, String)] = [
        ("/Users/me/Dev/App/App.xcodeproj", "/Users/me/Dev/App"),
        ("/Users/me/Dev/App/App.xcodeproj/", "/Users/me/Dev/App"),
        ("/Users/me/Dev/App/App.xcworkspace", "/Users/me/Dev/App"),
        ("/Users/me/Dev/App/App.xcodeproj/project.xcworkspace", "/Users/me/Dev/App"),
        ("/Users/me/Dev/App/App.xcodeproj/project.pbxproj", "/Users/me/Dev/App"),
        ("/Users/me/Dev/Kit/.swiftpm/xcode/package.xcworkspace", "/Users/me/Dev/Kit"),
        ("/Users/me/Dev/Kit/.swiftpm", "/Users/me/Dev/Kit"),
        ("/Users/me/Playgrounds/Try.playground", "/Users/me/Playgrounds"),
        ("/Users/me/Playgrounds/Try.playground/Contents.swift", "/Users/me/Playgrounds"),
        ("/Users/me/Dev/Kit/.SwiftPM/xcode/package.xcworkspace", "/Users/me/Dev/Kit"),
        ("/Users/me/Dev/App/APP.XCODEPROJ", "/Users/me/Dev/App"),
        ("file:///Users/me/Dev/App/App.xcodeproj/", "/Users/me/Dev/App"),
        ("/App.xcodeproj", "/"),
    ]

    @Test(arguments: bundleCases)
    func bundlesResolveToTheirParent(path: String, expected: String) {
        // 上に .git があっても、バンドルの親を使う
        #expect(Self.project(path, existing: ["/Users/me/.git", "/Users/me/Dev/.git"]) == expected)
    }

    static let swiftPlaygroundsCases: [(String, String)] = [
        // Swift Playgrounds のアプリ（Name.swiftpm）は Package.swift を含むパッケージそのもの
        ("/Users/me/Apps/Game.swiftpm", "/Users/me/Apps/Game.swiftpm"),
        ("/Users/me/Apps/Game.swiftpm/", "/Users/me/Apps/Game.swiftpm"),
        ("/Users/me/Apps/Game.swiftpm/Sources/App/ContentView.swift", "/Users/me/Apps/Game.swiftpm"),
        ("/Users/me/Apps/Game.swiftpm/.swiftpm/xcode/package.xcworkspace", "/Users/me/Apps/Game.swiftpm"),
        ("/Users/me/Apps/My Game.SwiftPM/Package.swift", "/Users/me/Apps/My Game.SwiftPM"),
        ("file:///Users/me/Apps/My%20Game.swiftpm/", "/Users/me/Apps/My Game.swiftpm"),
    ]

    @Test(arguments: swiftPlaygroundsCases)
    func swiftPlaygroundsAppIsItsOwnProject(path: String, expected: String) {
        #expect(Self.project(path, existing: ["/Users/me/.git", "/Users/me/Apps/.git"]) == expected)
    }

    @Test func distinguishesTheSwiftPMFolderFromAPackageBundle() {
        #expect(ScriptEnvironment.isProjectBundle(".swiftpm"))
        #expect(ScriptEnvironment.isPackageBundle(".swiftpm") == false)
        #expect(ScriptEnvironment.isPackageBundle("Game.swiftpm"))
        #expect(ScriptEnvironment.isProjectBundle("Game.swiftpm") == false)
        #expect(ScriptEnvironment.isProjectBundle("App.xcodeproj"))
        #expect(ScriptEnvironment.isPackageBundle("App.xcodeproj") == false)
        #expect(ScriptEnvironment.isProjectBundle("swiftpm") == false)
        #expect(ScriptEnvironment.isPackageBundle("swiftpm") == false)
    }

    @Test func walksUpToTheNearestGitOrPackage() {
        let existing: Set<String> = ["/Users/me/Dev/repo/.git", "/Users/me/Dev/repo/Packages/Kit/Package.swift"]
        #expect(Self.project("/Users/me/Dev/repo/src/app/main.swift", existing: existing) == "/Users/me/Dev/repo")
        #expect(Self.project("/Users/me/Dev/repo/README.md", existing: existing) == "/Users/me/Dev/repo")
        #expect(Self.project("/Users/me/Dev/repo/Packages/Kit/Sources/Kit/Kit.swift", existing: existing) == "/Users/me/Dev/repo/Packages/Kit")
        #expect(Self.project("/Users/me/Dev/repo/Packages/Kit/Package.swift", existing: existing) == "/Users/me/Dev/repo/Packages/Kit")
    }

    @Test func treatsADocumentThatIsAProjectFolderAsTheProject() {
        // VS Code などはフォルダを書類として返す
        let existing: Set<String> = ["/Users/me/Dev/repo/.git"]
        #expect(Self.project("/Users/me/Dev/repo", existing: existing) == "/Users/me/Dev/repo")
        #expect(Self.project("/Users/me/Dev/repo/", existing: existing) == "/Users/me/Dev/repo")
    }

    @Test func gitMayBeAFile() {
        // ワークツリーやサブモジュールの .git はファイル。fileExists で区別しない
        let existing: Set<String> = ["/Users/me/Dev/wt/.git"]
        #expect(Self.project("/Users/me/Dev/wt/Sources/a.swift", existing: existing) == "/Users/me/Dev/wt")
    }

    @Test func stopsAtTheHomeDirectory() {
        // ホームの dotfiles の .git はプロジェクトにしない
        let existing: Set<String> = ["/Users/me/.git", "/Users/me/Package.swift", "/Users/.git", "/.git"]
        #expect(Self.project("/Users/me/Documents/notes/todo.md", existing: existing) == "/Users/me/Documents/notes")
        #expect(Self.project("/Users/me/todo.md", existing: existing) == "/Users/me")
        #expect(Self.project("/Users/me/Documents/notes/todo.md", existing: existing, home: "/Users/me/") == "/Users/me/Documents/notes")
    }

    @Test func stopsAtTheRootOutsideTheHomeDirectory() {
        let existing: Set<String> = ["/.git", "/Package.swift"]
        #expect(Self.project("/Volumes/Data/work/file.txt", existing: existing) == "/Volumes/Data/work")
        #expect(Self.project("/file.txt", existing: existing) == "/")
        #expect(Self.project("/Volumes/Data/work/file.txt", existing: ["/Volumes/Data/.git"]) == "/Volumes/Data")
        #expect(Self.project("/Volumes/Data/work/file.txt", existing: ["/Volumes/.git"]) == "/Volumes")
    }

    @Test func fallsBackToTheFileDirectory() {
        #expect(Self.project("/Users/me/Desktop/memo.txt", existing: []) == "/Users/me/Desktop")
        #expect(Self.project("/Users/me/Desktop/folder/", existing: []) == "/Users/me/Desktop")
        #expect(Self.project("/", existing: []) == "/")
    }

    @Test func normalizesSlashesAndDots() {
        let existing: Set<String> = ["/Users/me/Dev/repo/.git"]
        #expect(Self.project("/Users/me//Dev/repo/./src//main.swift", existing: existing) == "/Users/me/Dev/repo")
        #expect(Self.project("/Users/me/Dev/other/../repo/src/main.swift", existing: existing) == "/Users/me/Dev/repo")
        #expect(Self.project("/../../Users/me/Desktop/a.txt", existing: []) == "/Users/me/Desktop")
    }

    @Test func doesNotExpandTilde() {
        var checked: [String] = []
        let result = ScriptEnvironment.projectDirectory(forDocumentPath: "~/Dev/a.swift", homeDirectory: Self.home) {
            checked.append($0)
            return false
        }
        #expect(result == "~/Dev")
        #expect(checked.allSatisfy { $0.hasPrefix("~") })
    }

    @Test func emptyPathGivesEmptyResult() {
        #expect(Self.project("", existing: []) == "")
    }

    @Test func checksOnlyAncestorsBelowHome() {
        var checked: [String] = []
        _ = ScriptEnvironment.projectDirectory(forDocumentPath: "/Users/me/a/b/c.txt", homeDirectory: Self.home) {
            checked.append($0)
            return false
        }
        #expect(checked == [
            "/Users/me/a/b/c.txt/.git", "/Users/me/a/b/c.txt/Package.swift",
            "/Users/me/a/b/.git", "/Users/me/a/b/Package.swift",
            "/Users/me/a/.git", "/Users/me/a/Package.swift",
        ])
    }

    @Test func defaultOverloadUsesTheRealHomeDirectory() {
        // 本物のホームの上は調べない
        let home = ScriptEnvironment.normalizedPath(NSHomeDirectory())
        var checked: [String] = []
        let result = ScriptEnvironment.projectDirectory(forDocumentPath: home + "/x/y.txt") {
            checked.append($0)
            return false
        }
        #expect(result == home + "/x")
        #expect(checked.allSatisfy { $0.hasPrefix(home + "/x") })
    }
}
