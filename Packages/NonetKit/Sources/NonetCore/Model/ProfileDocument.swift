// 担当: core-model。プロファイルの書き出し・読み込み（.nonetprofile）の書式（内部用）
import Foundation

/// .nonetprofile の中身。
/// {"format": "com.iam74k4.Nonet.profiles", "version": 1, "exportedAt": "...", "profiles": [...]}
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
    /// 読めないプロファイル・bundleID の無いアプリ・2つ目以降のグローバルや同じアプリは外す
    static func decode(_ data: Data) throws -> [Profile] {
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

        var profiles: [Profile] = []
        var seenBundleIDs = Set<String>()
        var hasGlobal = false
        for profile in body.profiles.compactMap(\.value) {
            switch profile.kind {
            case .global:
                guard !hasGlobal else { continue }
                hasGlobal = true
            case .app(let app):
                let key = NonetConfiguration.bundleIDKey(app.bundleID)
                guard !key.isEmpty, seenBundleIDs.insert(key).inserted else { continue }
            }
            profiles.append(profile.normalizedForStorage().reidentified())
        }
        let dropped = body.profiles.count - profiles.count
        if dropped > 0 {
            modelLogger.warning("読み込んだプロファイルのうち \(dropped) 個を使わなかった")
        }
        guard !profiles.isEmpty else { throw ConfigurationStoreError.noProfiles }
        return profiles
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
