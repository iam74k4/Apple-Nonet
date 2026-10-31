// 担当: core-model。プロファイルの書き出し・読み込み（.nonetprofile）の書式（内部用）
import Foundation

/// .nonetprofile の中身。
/// {"format": "com.iam74k4.Nonet.profiles", "version": 1, "exportedAt": "...", "profiles": [...]}。
/// すべての書き出しで共通マスがあれば "sharedCells"（設定ファイルと同じ書式）も書く。前の版の Nonet はこれを読まずにプロファイルだけ読む
struct ProfileDocument: Encodable {
    static let formatIdentifier = "com.iam74k4.Nonet.profiles"
    static let currentVersion = 1

    var format = ProfileDocument.formatIdentifier
    var version = ProfileDocument.currentVersion
    var exportedAt: Date
    var profiles: [Profile]
    /// 共通マス。無ければ書かない
    var sharedCells: SharedCells?

    static func encode(_ profiles: [Profile], sharedCells: SharedCells = .empty, exportedAt: Date = Date()) throws -> Data {
        guard !profiles.isEmpty else { throw ConfigurationStoreError.noProfiles }
        let document = ProfileDocument(
            exportedAt: exportedAt,
            profiles: profiles.map { $0.normalizedForStorage() },
            sharedCells: sharedCells.isEmpty ? nil : sharedCells.normalizedForStorage()
        )
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
        guard profiles.contains(where: isUsable) else { throw ConfigurationStoreError.noProfiles }
        let sharedCells = (body.sharedCells ?? .empty).normalizedForStorage().reidentified()
        return ConfigurationStore.ImportedProfiles(profiles: profiles, unreadableCount: unreadable, sharedCells: sharedCells)
    }

    /// 設定に加えられるプロファイル（グローバルか、bundleID のあるアプリ）
    private static func isUsable(_ profile: Profile) -> Bool {
        switch profile.kind {
        case .global: true
        case .app(let app): !NonetConfiguration.bundleIDKey(app.bundleID).isEmpty
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
        /// 読めなければ共通マス無し（プロファイルは読む）
        var sharedCells: SharedCells?

        private enum CodingKeys: String, CodingKey {
            case profiles, sharedCells
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            profiles = try container.decode([LossyElement<Profile>].self, forKey: .profiles)
            sharedCells = container.decodeLossy(SharedCells?.self, forKey: .sharedCells, default: nil)
        }
    }
}

extension SharedCells {
    /// 値の範囲を揃えたもの（Profile.normalizedForStorage() と同じ）
    func normalizedForStorage() -> SharedCells {
        SharedCells(cells: cells.map { cell in
            cell.map { cell in
                var cell = cell
                cell.action = cell.action.validated()
                return cell
            }
        })
    }

    /// マスの id を新しくしたもの
    func reidentified() -> SharedCells {
        SharedCells(cells: cells.map { cell in
            cell.map { cell in
                var cell = cell
                cell.id = UUID()
                return cell
            }
        })
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
