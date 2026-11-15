// 担当: platform-actions
import AppKit
import NonetCore

/// プリセットを組み立てるときに見る、この Mac の状態（AI と Claude Code を使えるか、Dock のアプリ）
@MainActor
public final class SystemPresetEnvironment: PresetEnvironmentProviding {
    private let shell: UserShell

    public convenience init() {
        self.init(shell: .shared)
    }

    init(shell: UserShell) {
        self.shell = shell
        // claude を探すのは、裏のスクリプトの PATH を調べるのと同じ1回のシェルの起動（起動ごとに1回）
        shell.start()
    }

    public var capabilities: PresetCapabilities {
        Self.capabilities(aiUsable: OnDeviceAI.isUsableForPresets, shell: shell.finishedInfo ?? nil)
    }

    public func resolvedCapabilities() async -> PresetCapabilities {
        let info = await shell.info()
        return Self.capabilities(aiUsable: OnDeviceAI.isUsableForPresets, shell: info)
    }

    /// シェルを調べ終えていない・調べられなかったときは、claude は見つからない扱い（動かないマスを置かない）
    nonisolated static func capabilities(aiUsable: Bool, shell: UserShellInfo?) -> PresetCapabilities {
        PresetCapabilities(appleIntelligence: aiUsable, claudeCode: shell?.hasClaudeCode ?? false)
    }

    public func dockApps() -> [AppReference] {
        DockApps.apps(
            from: DockApps.readTiles(),
            excluding: Bundle.main.bundleIdentifier,
            locate: DockApps.locate,
            name: DockApps.displayName(of:)
        )
    }
}

/// Dock に置いてあるアプリのタイル（com.apple.dock の persistent-apps の1つ）
struct DockTile: Equatable, Sendable {
    var bundleID: String
    /// タイルが指しているアプリの場所
    var url: URL?
    /// Dock に出る名前（置いたときの言語のまま残っていることがある）
    var label: String?
}

/// Dock の並び。サンドボックスの外のアプリは、確認なしで読める（読むだけで書き換えない）
enum DockApps {
    static let domain = "com.apple.dock"
    static let key = "persistent-apps"

    /// 設定を読む。読めなければ空
    static func readTiles() -> [DockTile] {
        tiles(from: CFPreferencesCopyAppValue(key as CFString, domain as CFString))
    }

    /// persistent-apps の値（辞書の配列）から、アプリのタイルを Dock の順に読む。仕切りなど bundleID の無いものは飛ばす
    static func tiles(from value: Any?) -> [DockTile] {
        guard let items = value as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let data = item["tile-data"] as? [String: Any],
                  let bundleID = (data["bundle-identifier"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !bundleID.isEmpty
            else { return nil }
            let file = data["file-data"] as? [String: Any]
            return DockTile(
                bundleID: bundleID,
                url: (file?["_CFURLString"] as? String).flatMap(fileURL),
                label: (data["file-label"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    /// "file:///Applications/Xcode.app/" か、まれにパスそのもの
    static func fileURL(_ string: String) -> URL? {
        if string.hasPrefix("/") { return URL(fileURLWithPath: string, isDirectory: true) }
        guard let url = URL(string: string), url.isFileURL else { return nil }
        return url
    }

    /// インストール済みのアプリだけを Dock の順に。名前は Finder と同じもの（分からなければ Dock の名前）。
    /// Nonet 自身と、同じアプリの2つ目は除く。bundleID の大文字・小文字は区別しない
    static func apps(
        from tiles: [DockTile],
        excluding ownBundleID: String?,
        locate: (DockTile) -> URL?,
        name: (URL) -> String?
    ) -> [AppReference] {
        var seen = Set<String>()
        if let ownBundleID { seen.insert(ownBundleID.lowercased()) }
        return tiles.compactMap { tile in
            guard seen.insert(tile.bundleID.lowercased()).inserted, let url = locate(tile) else { return nil }
            let displayName = name(url) ?? tile.label.flatMap { $0.isEmpty ? nil : $0 } ?? tile.bundleID
            return AppReference(bundleID: tile.bundleID, name: displayName)
        }
    }

    /// タイルが指す場所にアプリがあればそこ。移したアプリは Launch Services に bundleID で聞く。どちらにも無ければ nil
    static func locate(_ tile: DockTile) -> URL? {
        if let url = tile.url, FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: tile.bundleID)
    }

    static func displayName(of url: URL) -> String? {
        InstalledAppScanner.app(at: url, fileManager: .default)?.name
    }
}
