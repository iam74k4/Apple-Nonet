// 担当: ui-settings
// インストール済みアプリの一覧（プロファイルの追加・アプリ起動のアプリ選び）
import Foundation
import NonetCore

struct SettingsAppEntry: Identifiable, Equatable {
    var app: AppReference
    /// プリセット（最初から用意した9マス）がある
    var hasPreset: Bool
    /// すでにプロファイルがある
    var hasProfile: Bool

    var id: String { app.bundleID.lowercased() }
}

enum SettingsAppCatalog {
    /// 検索して並べる。検索語が空なら、プリセットのあるアプリを先に
    static func entries(apps: [AppReference], query: String, existingBundleIDs: Set<String>, presetsFirst: Bool) -> [SettingsAppEntry] {
        let existing = Set(existingBundleIDs.map { $0.lowercased() })
        var seen = Set<String>()
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        let all = apps.compactMap { app -> SettingsAppEntry? in
            let key = app.bundleID.lowercased()
            guard !key.isEmpty, seen.insert(key).inserted else { return nil }
            let matches = words.allSatisfy { word in
                [app.name, app.bundleID].contains {
                    $0.range(of: word, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) != nil
                }
            }
            guard matches else { return nil }
            return SettingsAppEntry(
                app: app,
                hasPreset: PresetLibrary.preset(forBundleID: app.bundleID) != nil,
                hasProfile: existing.contains(key)
            )
        }
        guard presetsFirst, words.isEmpty else { return all }
        return all.filter(\.hasPreset) + all.filter { !$0.hasPreset }
    }

    /// .app のバンドルからアプリを指す値を作る（一覧に無いアプリを選んだとき）。bundleID が無ければ nil
    static func appReference(forBundleAt url: URL) -> AppReference? {
        guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier, !bundleID.isEmpty else { return nil }
        let info = bundle.localizedInfoDictionary ?? [:]
        let base = bundle.infoDictionary ?? [:]
        let name = (info["CFBundleDisplayName"] as? String) ?? (base["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String) ?? (base["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return AppReference(bundleID: bundleID, name: name)
    }
}
