import NonetCore
@testable import NonetPlatform
import Testing

/// メニューバーの偽物
private final class FakeMenu {
    var attributes: MenuEntryAttributes
    var children: [FakeMenu]

    init(_ title: String?, enabled: Bool = true, char: String? = nil, modifiers: Int? = nil, glyph: Int? = nil, _ children: [FakeMenu] = []) {
        attributes = MenuEntryAttributes(title: title, isEnabled: enabled, cmdChar: char, cmdModifiers: modifiers, cmdGlyph: glyph)
        self.children = children
    }

    static let separator = FakeMenu("")
}

private struct FakeMenuTree: MenuTree {
    var bar: [FakeMenu]
    var error: AXCallError?

    func menuBarItems() throws -> [FakeMenu] {
        if let error { throw error }
        return bar
    }

    func attributes(of node: FakeMenu) -> MenuEntryAttributes { node.attributes }
    func submenuItems(of node: FakeMenu) -> [FakeMenu] { node.children }
}

@Suite("メニューの木とパス")
struct ActionMenuTreeTests {
    private static let sample = FakeMenuTree(bar: [
        FakeMenu("Apple", [FakeMenu("このMacについて"), FakeMenu("システム設定…")]),
        FakeMenu("Xcode", [FakeMenu("Settings…", char: ","), .separator, FakeMenu("Quit Xcode", char: "Q")]),
        FakeMenu("  File ", [
            FakeMenu("New", [FakeMenu("File…", char: "N"), FakeMenu("Project…", char: "N", modifiers: 1)]),
            FakeMenu("Save As...", char: "S", modifiers: 1),
            .separator,
            FakeMenu(nil),
            FakeMenu("Close", enabled: false, char: "W"),
        ]),
        FakeMenu("Edit", [FakeMenu("Delete", glyph: 0x17), FakeMenu("コピー", char: "C")]),
    ])

    @Test("Apple メニューと区切り線を除き、タイトルを整えてパスを付ける")
    func buildsTree() throws {
        let items = try MenuTreeBuilder.build(Self.sample)
        #expect(items.map(\.title) == ["Xcode", "File", "Edit"])
        let xcode = items[0]
        #expect(xcode.path == ["Xcode"])
        #expect(xcode.keyEquivalent == nil)
        #expect(xcode.children.map(\.title) == ["Settings…", "Quit Xcode"])
        #expect(xcode.children[0].path == ["Xcode", "Settings…"])
        #expect(xcode.children[0].keyEquivalent == .key(",", .command))

        let file = items[1]
        #expect(file.children.map(\.title) == ["New", "Save As...", "Close"])
        let new = file.children[0]
        #expect(new.keyEquivalent == nil)
        #expect(new.children.map(\.path) == [["File", "New", "File…"], ["File", "New", "Project…"]])
        #expect(new.children[1].keyEquivalent == .key("n", [.command, .shift]))
        #expect(file.children[2].isEnabled == false)
        #expect(file.children[2].keyEquivalent == .key("w", .command))

        #expect(items[2].children[0].keyEquivalent == .special(.delete, .command))
        #expect(items[2].children[1].id == "Edit\u{1F}コピー")
    }

    @Test("深さと項目数に上限がある")
    func limits() throws {
        func chain(_ depth: Int) -> FakeMenu {
            depth == 0 ? FakeMenu("leaf") : FakeMenu("level\(depth)", [chain(depth - 1)])
        }
        let tree = FakeMenuTree(bar: [FakeMenu("Apple"), chain(10)])
        let items = try MenuTreeBuilder.build(tree, limits: MenuTreeLimits(maxDepth: 2, maxItems: 100))
        #expect(items[0].children.count == 1)
        #expect(items[0].children[0].children.count == 1)
        #expect(items[0].children[0].children[0].children.isEmpty)

        let wide = FakeMenuTree(bar: [FakeMenu("Apple"), FakeMenu("History", (0 ..< 50).map { FakeMenu("Page \($0)") })])
        let limited = try MenuTreeBuilder.build(wide, limits: MenuTreeLimits(maxDepth: 5, maxItems: 10))
        #expect(limited[0].children.count == 9)
    }

    @Test("メニューバーを読めなければ投げる")
    func propagatesErrors() {
        let tree = FakeMenuTree(bar: [], error: AXCallError(code: .apiDisabled))
        #expect(throws: AXCallError(code: .apiDisabled)) { try MenuTreeBuilder.build(tree) }
        #expect(AXCallError(code: .apiDisabled).nonetError(appName: "X") == .permissionDenied(ActionText.accessibility))
        #expect(AXCallError(code: .cannotComplete).nonetError(appName: "X") != .permissionDenied(ActionText.accessibility))
    }

    @Test("パスをたどる。大文字小文字・空白・末尾の「…」の違いは許す")
    func resolvesPaths() throws {
        let saveAs = try MenuPathResolver.resolve(["File", "Save As…"], in: Self.sample)
        #expect(saveAs?.attributes.title == "Save As...")
        let project = try MenuPathResolver.resolve(["file", "NEW", "project"], in: Self.sample)
        #expect(project?.attributes.title == "Project…")
        let copy = try MenuPathResolver.resolve(["Edit", "コピー"], in: Self.sample)
        #expect(copy?.attributes.cmdChar == "C")
    }

    @Test("見つからなければ nil。Apple メニューはたどらない")
    func missingPaths() throws {
        #expect(try MenuPathResolver.resolve(["File", "Print"], in: Self.sample) == nil)
        #expect(try MenuPathResolver.resolve(["Apple", "このMacについて"], in: Self.sample) == nil)
        #expect(try MenuPathResolver.resolve([], in: Self.sample) == nil)
        #expect(try MenuPathResolver.resolve(["File", "New", "File…", "More"], in: Self.sample) == nil)
    }
}

@Suite("メニューのタイトルの比べ方")
struct ActionMenuTitleMatcherTests {
    @Test("正規化", arguments: [
        ("Save As…", "save as"),
        ("Save As...", "save as"),
        ("  Save   As \u{2026} ", "save as"),
        ("Export\u{00A0}PDF", "export pdf"),
        ("ｺﾋﾟｰ", "コピー"),
        ("ＡＢＣ", "abc"),
        ("…", ""),
    ])
    func normalization(title: String, expected: String) {
        #expect(MenuTitleMatcher.normalized(title) == expected)
    }

    @Test("完全一致を優先する")
    func exactFirst() {
        #expect(MenuTitleMatcher.index(of: "copy", in: ["Copy", "copy"]) == 1)
        #expect(MenuTitleMatcher.index(of: "Copy", in: ["copy", "Copy"]) == 1)
        #expect(MenuTitleMatcher.index(of: "Copy", in: ["copy", nil]) == 0)
        #expect(MenuTitleMatcher.index(of: " Copy ", in: [nil, "Copy"]) == 1)
    }

    @Test("見つからない・空のタイトルは nil")
    func noMatch() {
        #expect(MenuTitleMatcher.index(of: "Paste", in: ["Copy", "Cut"]) == nil)
        #expect(MenuTitleMatcher.index(of: "", in: ["Copy"]) == nil)
        #expect(MenuTitleMatcher.index(of: "…", in: ["", "Copy"]) == nil)
        #expect(MenuTitleMatcher.index(of: "Copy", in: []) == nil)
    }

    @Test("表示用のパス")
    func displayPath() {
        #expect(MenuTitleMatcher.displayPath(["編集", "コピー"]) == "編集 > コピー")
    }
}

@Suite("メニュー項目の押し方")
struct ActionMenuPlanTests {
    @Test("対象が前面でショートカットがあればキーを送り、ほかはメニューを押す")
    func plan() {
        let keys = KeySequence.key("b", .command)
        #expect(MenuActionPlan.decide(isTargetFrontmost: true, keyEquivalent: keys) == .sendKeys)
        #expect(MenuActionPlan.decide(isTargetFrontmost: false, keyEquivalent: keys) == .pressMenu)
        #expect(MenuActionPlan.decide(isTargetFrontmost: true, keyEquivalent: nil) == .pressMenu)
        #expect(MenuActionPlan.decide(isTargetFrontmost: true, keyEquivalent: KeySequence([])) == .pressMenu)
    }
}

@Suite("起動中アプリの一覧")
struct ActionRunningAppsTests {
    @Test("Dock に出るアプリだけ。bundleID の無いもの・終了したもの・Nonet は除き、名前順")
    func filters() {
        let candidates = [
            RunningAppCandidate(bundleID: "com.apple.Safari", name: "Safari", processID: 10, isRegular: true),
            RunningAppCandidate(bundleID: nil, name: "NoID", processID: 11, isRegular: true),
            RunningAppCandidate(bundleID: "com.example.agent", name: "Agent", processID: 12, isRegular: false),
            RunningAppCandidate(bundleID: "com.iam74k4.Nonet", name: "Nonet", processID: 13, isRegular: true),
            RunningAppCandidate(bundleID: "com.example.gone", name: "Gone", processID: 14, isRegular: true, isTerminated: true),
            RunningAppCandidate(bundleID: "com.apple.dt.Xcode", name: "Xcode", processID: 15, isRegular: true),
            RunningAppCandidate(bundleID: "com.example.unnamed", name: nil, processID: 16, isRegular: true),
            RunningAppCandidate(bundleID: "com.example.app2", name: "App 2", processID: 17, isRegular: true),
            RunningAppCandidate(bundleID: "com.example.app10", name: "App 10", processID: 18, isRegular: true),
        ]
        let apps = RunningAppFilter.menuBarApps(from: candidates, excluding: ["com.iam74k4.Nonet"])
        #expect(apps.map(\.app.name) == ["App 2", "App 10", "com.example.unnamed", "Safari", "Xcode"])
        #expect(apps.first { $0.app.bundleID == "com.apple.Safari" }?.processID == 10)
    }
}
