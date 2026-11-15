import Foundation
import NonetCore
@testable import NonetPlatform
import Testing

@Suite("インストール済みアプリを集める")
struct ActionInstalledAppsTests {
    /// Info.plist だけを持つ偽物の .app を作る
    @discardableResult
    private func makeApp(
        _ name: String,
        in folder: URL,
        bundleID: String?,
        extra: [String: Any] = [:],
        plistPath: String = "Contents/Info.plist"
    ) throws -> URL {
        let bundle = folder.appendingPathComponent("\(name).app", isDirectory: true)
        let plistURL = bundle.appendingPathComponent(plistPath)
        try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var info: [String: Any] = ["CFBundleName": name, "CFBundlePackageType": "APPL"]
        if let bundleID { info["CFBundleIdentifier"] = bundleID }
        info.merge(extra) { _, new in new }
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: plistURL)
        return bundle
    }

    @Test(".app と1つ下のフォルダの .app を読み、名前順に並べる")
    func scansRootsAndOneLevel() throws {
        let directory = try ActionTemporaryDirectory()
        let applications = try directory.subdirectory("Applications")
        let utilities = try directory.subdirectory("Applications/Utilities")
        let vendor = try directory.subdirectory("Applications/Vendor Tools")
        let deep = try directory.subdirectory("Applications/Vendor Tools/Deeper")
        try makeApp("Zeta", in: applications, bundleID: "com.example.zeta")
        try makeApp("alpha", in: applications, bundleID: "com.example.alpha")
        try makeApp("App 10", in: applications, bundleID: "com.example.app10")
        try makeApp("App 2", in: applications, bundleID: "com.example.app2")
        try makeApp("Terminal Helper", in: utilities, bundleID: "com.example.utility")
        try makeApp("Vendor App", in: vendor, bundleID: "com.example.vendor")
        try makeApp("Too Deep", in: deep, bundleID: "com.example.deep")
        try Data("not an app".utf8).write(to: applications.appendingPathComponent("readme.txt"))

        let apps = InstalledAppScanner(roots: [applications]).scan()
        #expect(apps.map(\.name) == ["alpha", "App 2", "App 10", "Terminal Helper", "Vendor App", "Zeta"])
        #expect(apps.first { $0.name == "Vendor App" }?.bundleID == "com.example.vendor")
        #expect(!apps.contains { $0.bundleID == "com.example.deep" })
    }

    @Test("bundleID の無いもの・裏で動くだけのものは除く")
    func skipsInvalidBundles() throws {
        let directory = try ActionTemporaryDirectory()
        let root = try directory.subdirectory("Applications")
        try makeApp("No ID", in: root, bundleID: nil)
        try makeApp("Empty ID", in: root, bundleID: "  ")
        try makeApp("Background", in: root, bundleID: "com.example.bg", extra: ["LSBackgroundOnly": true])
        try makeApp("Menu Bar", in: root, bundleID: "com.example.menubar", extra: ["LSUIElement": true])
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Broken.app"), withIntermediateDirectories: true)
        let apps = InstalledAppScanner(roots: [root]).scan()
        #expect(apps == [AppReference(bundleID: "com.example.menubar", name: "Menu Bar")])
    }

    @Test("同じ bundleID は先のフォルダのものを残す（大文字小文字は区別しない）")
    func deduplicates() throws {
        let directory = try ActionTemporaryDirectory()
        let first = try directory.subdirectory("Applications")
        let second = try directory.subdirectory("System/Applications")
        try makeApp("Safari", in: first, bundleID: "com.apple.Safari")
        try makeApp("Safari Copy", in: second, bundleID: "com.apple.safari")
        try makeApp("Notes", in: second, bundleID: "com.apple.Notes")
        let apps = InstalledAppScanner(roots: [first, second, directory.url.appendingPathComponent("missing")]).scan()
        #expect(apps.map(\.name) == ["Notes", "Safari"])
    }

    @Test("フォルダの外のアプリ（Finder）も、あれば加える。無ければ何もしない")
    func addsExtraBundles() throws {
        let directory = try ActionTemporaryDirectory()
        let root = try directory.subdirectory("Applications")
        let coreServices = try directory.subdirectory("CoreServices")
        try makeApp("Notes", in: root, bundleID: "com.apple.Notes")
        let finder = try makeApp("Finder", in: coreServices, bundleID: "com.apple.finder")
        let apps = InstalledAppScanner(roots: [root], extraBundles: [finder, coreServices.appendingPathComponent("Missing.app")]).scan()
        #expect(apps.map(\.bundleID) == ["com.apple.finder", "com.apple.Notes"])
        // 本物の Mac の Finder
        #expect(InstalledAppScanner.defaultExtraBundles.map(\.lastPathComponent) == ["Finder.app"])
        #expect(InstalledAppScanner(roots: [], extraBundles: InstalledAppScanner.defaultExtraBundles).scan().map(\.bundleID) == ["com.apple.finder"])
    }

    @Test("iPhone / iPad 用のアプリは WrappedBundle の Info.plist を読む")
    func wrappedBundles() throws {
        let directory = try ActionTemporaryDirectory()
        let root = try directory.subdirectory("Applications")
        try makeApp("Game", in: root, bundleID: "com.example.ios", plistPath: "WrappedBundle/Info.plist")
        #expect(InstalledAppScanner(roots: [root]).scan() == [AppReference(bundleID: "com.example.ios", name: "Game")])
    }

    @Test("既定のフォルダ")
    func defaultRoots() {
        let roots = InstalledAppScanner.defaultRoots(home: URL(fileURLWithPath: "/Users/me", isDirectory: true)).map(\.path)
        #expect(roots == [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "/System/Applications/Utilities",
            "/Users/me/Applications",
        ])
    }

    @Test("一覧はとっておき、refresh で読み直す")
    @MainActor
    func cachesUntilRefresh() throws {
        let directory = try ActionTemporaryDirectory()
        let root = try directory.subdirectory("Applications")
        try makeApp("One", in: root, bundleID: "com.example.one")
        let provider = WorkspaceInstalledApps(scanner: InstalledAppScanner(roots: [root]))
        #expect(provider.installedApps().map(\.bundleID) == ["com.example.one"])
        try makeApp("Two", in: root, bundleID: "com.example.two")
        #expect(provider.installedApps().map(\.bundleID) == ["com.example.one"])
        provider.refresh()
        #expect(provider.installedApps().map(\.bundleID) == ["com.example.one", "com.example.two"])
    }

    @Test("空の bundleID はインストールされていない")
    @MainActor
    func emptyBundleIDIsNotInstalled() {
        #expect(!WorkspaceInstalledApps().isInstalled(bundleID: ""))
    }
}

@Suite("ショートカット")
struct ActionShortcutsTests {
    @Test("shortcuts list の出力: 空行・前後の空白・重複を除き、名前順")
    func parsesList() {
        let output = "ミュージックコントローラー\r\n  Wallet  \n\nShortcut 10\nShortcut 2\nWallet\nalpha\n"
        #expect(ShortcutListParser.names(from: output) == ["alpha", "Shortcut 2", "Shortcut 10", "Wallet", "ミュージックコントローラー"])
        #expect(ShortcutListParser.names(from: "") == [])
        #expect(ShortcutListParser.names(from: "\n \n") == [])
    }

    @Test("shortcuts run の引数。名前は -- の後")
    func runArguments() {
        #expect(ShortcutRunner.arguments(name: "Toggle Mute", inputPath: nil) == ["run", "--", "Toggle Mute"])
        #expect(ShortcutRunner.arguments(name: "-weird", inputPath: "/tmp/in.txt") == ["run", "--input-path", "/tmp/in.txt", "--", "-weird"])
    }

    @Test("失敗の説明。時間切れは timedOut、成功なら無し")
    func failures() {
        let ok = ProcessOutput(status: 0, wasSignaled: false, timedOut: false, stdout: "", stderr: "")
        #expect(ShortcutRunner.failure(for: ok, name: "X") == nil)
        let timedOut = ProcessOutput(status: 15, wasSignaled: true, timedOut: true, stdout: "", stderr: "")
        #expect(ShortcutRunner.failure(for: timedOut, name: "X") == .timedOut)
        let failed = ProcessOutput(status: 1, wasSignaled: false, timedOut: false, stdout: "", stderr: "Error: not found\n")
        guard case .actionFailed(let message)? = ShortcutRunner.failure(for: failed, name: "X") else {
            Issue.record("actionFailed になるはず")
            return
        }
        #expect(message.hasSuffix("Error: not found"))
    }

    @Test("名前が空なら実行しない")
    func emptyName() async {
        await #expect(throws: NonetError.self) { try await ShortcutRunner.run(name: "  ", input: nil) }
    }
}
