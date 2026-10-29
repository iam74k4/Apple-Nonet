// 担当: ui-settings
// プロファイルの読み込みを、実際に設定へ入れる前に写しで試した結果。置き換わるものがあれば先に確かめる
import Foundation
import NonetCore

struct SettingsImportPlan: Identifiable, Equatable {
    let id = UUID()
    /// 読み込むファイルの名前（確かめるときに出す）
    var fileName: String
    var document: ConfigurationStore.ImportedProfiles
    /// 写しに読み込んだときの結果
    var result: NonetConfiguration.ImportResult
    /// 置き換わる自分のアプリのプロファイルの名前（設定の並び順）
    var replacedNames: [String]

    init(document: ConfigurationStore.ImportedProfiles, configuration: NonetConfiguration, fileName: String) {
        self.fileName = fileName
        self.document = document
        var preview = configuration
        result = preview.importProfiles(document)
        let replacedIDs = Set(Self.importedApps(in: document).compactMap { app in
            Self.existingProfile(for: app, in: configuration)?.id
        })
        replacedNames = configuration.profiles.filter { replacedIDs.contains($0.id) }.map(\.name)
    }

    /// 今の設定を上書きする（グローバルのページか、同じアプリのプロファイル）
    var replacesExisting: Bool { result.replacedGlobal || !replacedNames.isEmpty }

    /// 新しく加わるアプリのプロファイルがある
    var addsProfiles: Bool { result.added > 0 }

    /// スクリプトのマスを含む（読み込んだ後に中身を確かめるよう知らせる）
    var containsScripts: Bool {
        Self.containsScripts(document.profiles)
    }

    /// 置き換えるものを除いた中身（新しいアプリのプロファイルだけ加えるとき）。設定はその時点のもので決める
    func newProfilesOnly(in configuration: NonetConfiguration) -> ConfigurationStore.ImportedProfiles {
        let profiles = document.profiles.filter { profile in
            guard let app = profile.app else { return false }
            return Self.existingProfile(for: app, in: configuration) == nil
        }
        return ConfigurationStore.ImportedProfiles(profiles: profiles, unreadableCount: document.unreadableCount)
    }

    static func containsScripts(_ profiles: [Profile]) -> Bool {
        profiles.contains { profile in
            profile.pages.contains { page in
                page.cells.contains { cell in
                    if case .script = cell?.action { return true }
                    return false
                }
            }
        }
    }

    /// ファイルの中のアプリ。同じアプリが重なっていれば最初のものだけ（読み込みと同じ決まり）
    private static func importedApps(in document: ConfigurationStore.ImportedProfiles) -> [AppReference] {
        var seen = Set<String>()
        return document.profiles.compactMap { profile in
            guard let app = profile.app else { return nil }
            let key = bundleIDKey(app.bundleID)
            guard !key.isEmpty, seen.insert(key).inserted else { return nil }
            return app
        }
    }

    /// 有効・無効にかかわらず、同じアプリのプロファイル（読み込みはこれを置き換える）
    private static func existingProfile(for app: AppReference, in configuration: NonetConfiguration) -> Profile? {
        let key = bundleIDKey(app.bundleID)
        guard !key.isEmpty else { return nil }
        return configuration.profiles.first { $0.app.map { bundleIDKey($0.bundleID) == key } == true }
    }

    /// bundle ID は大文字と小文字を区別しない（NonetConfiguration と同じ）
    private static func bundleIDKey(_ bundleID: String) -> String {
        bundleID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
