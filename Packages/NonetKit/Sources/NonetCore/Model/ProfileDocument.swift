// 担当: core-model。プロファイルの書き出し・読み込み（.nonetprofile）の書式（内部用）
import Foundation

/// .nonetprofile の中身。
/// {"format": "com.iam74k4.Nonet.profiles", "version": 1, "exportedAt": "...", "profiles": [...]}。
/// 前の版が書いた "sharedCells" は読まない
struct ProfileDocument: Encodable {
    static let formatIdentifier = "com.iam74k4.Nonet.profiles"
    static let currentVersion = 1

    var format = ProfileDocument.formatIdentifier
    var version = ProfileDocument.currentVersion
    var exportedAt: Date
    var profiles: [Profile]

    static func encode(_ profiles: [Profile], exportedAt: Date = Date()) throws -> Data {
        guard !profiles.isEmpty else { throw ConfigurationStoreError.noProfiles }
        let document = ProfileDocument(exportedAt: exportedAt, profiles: profiles.map { $0.normalizedForStorage() })
        do {
            return try ModelJSON.makeEncoder().encode(document)
        } catch {
            throw ConfigurationStoreError.exportFailed(reason: DecodingIssue.describe(error))
        }
    }

    /// 書式と版を確かめ、プロファイルを取り出す。id はすべて振り直す。
    /// 2つ目以降のグローバル・同じアプリ・bundleID の無いアプリも外さずに返す（NonetConfiguration.importProfiles(_:) が外して数える）。
    /// 読めないプロファイルは外して数える。使えるプロファイルが1つも無ければ noProfiles
    static func decode(_ data: Data) throws -> ConfigurationStore.ImportedProfiles {
        let decoder = ModelJSON.makeDecoder()
        guard let header = try? decoder.decode(Header.self, from: data),
              header.format == formatIdentifier else {
            throw ConfigurationStoreError.notAProfileDocument
        }
        let version: Int
        do {
            version = try decoder.decode(VersionField.self, from: data).version
        } catch {
            throw ConfigurationStoreError.invalidProfileDocument(reason: DecodingIssue.describe(error))
        }
        guard version <= currentVersion else {
            throw ConfigurationStoreError.unsupportedProfileDocumentVersion(version)
        }
        guard version >= 1 else {
            throw ConfigurationStoreError.invalidProfileDocument(reason: "版 \(version) は無い")
        }

        let body: Body
        do {
            body = try decoder.decode(Body.self, from: data)
        } catch {
            throw ConfigurationStoreError.invalidProfileDocument(reason: DecodingIssue.describe(error))
        }

        let profiles = body.profiles.compactMap(\.value).map { $0.normalizedForStorage().reidentified() }
        let unreadable = body.profiles.filter(\.isUnreadable).count
        if unreadable > 0 {
            modelLogger.warning("読み込んだプロファイルのうち \(unreadable) 個を読めなかった")
        }
        let incomplete = incompleteIndices(in: data, decoded: body.profiles.map(\.value))
        if !incomplete.isEmpty {
            modelLogger.warning("読み込んだプロファイルのうち \(incomplete.count) 個は、中身の一部を読めなかった")
        }
        guard profiles.contains(where: isUsable) else { throw ConfigurationStoreError.noProfiles }
        return ConfigurationStore.ImportedProfiles(profiles: profiles, unreadableCount: unreadable, incompleteIndices: incomplete)
    }

    /// 読めたプロファイルのうち、ファイルにあった値をこの版では残せないもの（知らない種類のマスが空きマスになる・
    /// 多すぎるページやマスを落とす など）の、読めたプロファイルの中での位置。書き出したときと同じ形にして、元の値がすべて残るかで決める。
    /// 前の版が書いた、もう使わない値（スクリプトとショートカットの output）は数えない
    private static func incompleteIndices(in data: Data, decoded: [Profile?]) -> Set<Int> {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let raw = root["profiles"] as? [Any], raw.count == decoded.count else { return [] }
        var indices = Set<Int>()
        var readable = 0
        for (original, profile) in zip(raw, decoded) {
            guard let profile else { continue }
            defer { readable += 1 }
            guard let saved = try? ModelJSON.makeEncoder().encode(profile.normalizedForStorage()),
                  let savedObject = try? JSONSerialization.jsonObject(with: saved),
                  JSONContent.isPreserved(removingRetiredKeys(from: original), in: savedObject) else {
                indices.insert(readable)
                continue
            }
        }
        return indices
    }

    /// 前の版の、もう読まない値を除いたもの（スクリプトとショートカットの output。Action.swift の決まりと同じ）
    static func removingRetiredKeys(from object: Any) -> Any {
        if var dictionary = object as? [String: Any] {
            if let type = dictionary["type"] as? String, type == "script" || type == "shortcut" {
                dictionary["output"] = nil
            }
            return dictionary.mapValues(removingRetiredKeys(from:))
        }
        if let array = object as? [Any] {
            return array.map(removingRetiredKeys(from:))
        }
        return object
    }

    /// 設定に加えられるプロファイル（グローバルか、bundleID のあるアプリ）
    private static func isUsable(_ profile: Profile) -> Bool {
        switch profile.kind {
        case .global: true
        case .app(let app): !NonetConfiguration.bundleIDKey(app.bundleID).isEmpty
        case .site(let site): SiteReference.normalizedHost(site.host) != nil
        }
    }

    private struct Header: Decodable {
        var format: String?
    }

    private struct VersionField: Decodable {
        var version: Int
    }

    private struct Body: Decodable {
        var profiles: [LossyElement<Profile>]
    }
}


extension Profile {
    /// ページ数・マス数・値の範囲を揃えたもの
    func normalizedForStorage() -> Profile {
        var profile = self
        profile.normalizePages()
        for page in profile.pages.indices {
            profile.pages[page].cells = profile.pages[page].cells.map { cell in
                cell.map { cell in
                    var cell = cell
                    cell.action = cell.action.validated()
                    return cell
                }
            }
        }
        return profile
    }

    /// プロファイルとマスの id を新しくしたもの
    func reidentified() -> Profile {
        var profile = self
        profile.id = UUID()
        for page in profile.pages.indices {
            profile.pages[page].cells = profile.pages[page].cells.map { cell in
                cell.map { cell in
                    var cell = cell
                    cell.id = UUID()
                    return cell
                }
            }
        }
        return profile
    }
}
