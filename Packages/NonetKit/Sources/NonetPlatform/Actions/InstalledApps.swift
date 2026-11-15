// 担当: platform-actions
import AppKit
import NonetCore

/// アプリのフォルダを見て、インストール済みのアプリを集める
struct InstalledAppScanner {
    var roots: [URL]
    /// アプリのフォルダの外にあるが、選べるようにするアプリ（フォルダの後に見る）
    var extraBundles: [URL] = []

    /// Finder は /System/Library/CoreServices にある。プリセットの最初のアプリで、ファイルのアクションも Finder で使うので、
    /// プロファイルを消したあとも「プロファイルを追加」と「開くアプリ」で選べるようにする（CoreServices のほかのアプリは入れない）
    static let defaultExtraBundles = [URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app", isDirectory: true)]

    static func defaultRoots(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/Applications/Utilities", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications/Utilities", isDirectory: true),
            home.appendingPathComponent("Applications", isDirectory: true),
        ]
    }

    /// 各フォルダの .app と、その1つ下のフォルダの .app。bundleID が同じものは先に見つけた方を残し、名前順
    func scan(fileManager: FileManager = .default) -> [AppReference] {
        var seen = Set<String>()
        var apps: [AppReference] = []
        let extras = extraBundles.filter { fileManager.fileExists(atPath: $0.path) }
        for bundle in roots.flatMap({ Self.bundleURLs(in: $0, fileManager: fileManager) }) + extras {
            guard let app = Self.app(at: bundle, fileManager: fileManager),
                  seen.insert(app.bundleID.lowercased()).inserted
            else { continue }
            apps.append(app)
        }
        return apps.sorted { lhs, rhs in
            let order = lhs.name.localizedStandardCompare(rhs.name)
            return order == .orderedSame ? lhs.bundleID < rhs.bundleID : order == .orderedAscending
        }
    }

    static func bundleURLs(in root: URL, fileManager: FileManager) -> [URL] {
        let entries = contents(of: root, fileManager: fileManager)
        var bundles: [URL] = []
        for entry in entries {
            if isAppBundle(entry) {
                bundles.append(entry)
            } else if isDirectory(entry) {
                bundles += contents(of: entry, fileManager: fileManager).filter(isAppBundle)
            }
        }
        return bundles
    }

    private static func contents(of directory: URL, fileManager: FileManager) -> [URL] {
        let entries = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return entries.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func isAppBundle(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "app"
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    /// Info.plist の bundleID と、Finder に出る名前。iPhone / iPad 用のアプリは WrappedBundle の中を見る
    static func app(at bundle: URL, fileManager: FileManager) -> AppReference? {
        let candidates = [
            bundle.appendingPathComponent("Contents/Info.plist"),
            bundle.appendingPathComponent("WrappedBundle/Info.plist"),
        ]
        guard let info = candidates.lazy.compactMap(readPlist).first,
              let bundleID = (info["CFBundleIdentifier"] as? String)?.trimmingCharacters(in: .whitespaces),
              !bundleID.isEmpty
        else { return nil }
        // 裏で動くだけのアプリは起動しても何も出ない
        if info["LSBackgroundOnly"] as? Bool == true { return nil }
        return AppReference(bundleID: bundleID, name: displayName(of: bundle, info: info, fileManager: fileManager))
    }

    private static func readPlist(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }

    /// Finder と同じ名前（言語に合わせたもの）。拡張子を表示する設定でも ".app" は付けない
    static func displayName(of bundle: URL, info: [String: Any], fileManager: FileManager) -> String {
        var name = fileManager.displayName(atPath: bundle.path)
        if name.lowercased().hasSuffix(".app") { name = String(name.dropLast(4)) }
        if !name.isEmpty { return name }
        let fallback = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String)
        return fallback ?? bundle.deletingPathExtension().lastPathComponent
    }
}

@MainActor
public final class WorkspaceInstalledApps: InstalledAppsProviding {
    /// 一覧を作り直すまでの時間。設定画面を開くたびにフォルダを読み直さないように
    static let cacheLifetime: TimeInterval = 30

    private let scanner: InstalledAppScanner
    private var cache: (apps: [AppReference], date: Date)?

    public init() {
        scanner = InstalledAppScanner(roots: InstalledAppScanner.defaultRoots(), extraBundles: InstalledAppScanner.defaultExtraBundles)
    }

    init(scanner: InstalledAppScanner) {
        self.scanner = scanner
    }

    public func installedApps() -> [AppReference] {
        if let cache, Date().timeIntervalSince(cache.date) < Self.cacheLifetime {
            return cache.apps
        }
        let apps = scanner.scan()
        cache = (apps, Date())
        return apps
    }

    /// 次の installedApps() でフォルダを読み直す
    public func refresh() {
        cache = nil
    }

    public func isInstalled(bundleID: String) -> Bool {
        guard !bundleID.isEmpty else { return false }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }
}
