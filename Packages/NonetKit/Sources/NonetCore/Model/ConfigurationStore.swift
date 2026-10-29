// 担当: core-model（公開 API は契約）
import Foundation

/// 設定を JSON で保存する。書き込みはアトミックで、直前の版を1つバックアップとして残す
public struct ConfigurationStore: Sendable {
    /// プロファイルの書き出しファイルの拡張子
    public static let profileDocumentExtension = "nonetprofile"

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// ~/Library/Application Support/Nonet
    public static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Nonet", directoryHint: .isDirectory)
    }

    public var fileURL: URL {
        directory.appending(path: "configuration.json", directoryHint: .notDirectory)
    }

    /// save() の直前に保存されていた版
    var backupFileURL: URL {
        directory.appending(path: "configuration.backup.json", directoryHint: .notDirectory)
    }

    /// 保存された設定。ファイルが無ければ nil。古い版は移行し、validated() してから返す。
    /// 読めないファイルは上書きされないよう configuration.corrupt-<日時>.json に移してから
    /// ConfigurationStoreError.corrupted を投げる
    public func load() throws -> NonetConfiguration? {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch CocoaError.fileReadNoSuchFile, CocoaError.fileNoSuchFile {
            return nil
        } catch {
            modelLogger.error("設定ファイルを読めない: \(error.localizedDescription, privacy: .public)")
            throw ConfigurationStoreError.readFailed(reason: error.localizedDescription)
        }

        do {
            let (configuration, fileVersion) = try Self.decodeConfiguration(from: data)
            if fileVersion > NonetConfiguration.currentVersion {
                // 新しい版の Nonet で書いたファイル。分かる範囲で読むが、元に戻したときのために原本を残す
                preserveNewerVersionFile(data, version: fileVersion)
            }
            return configuration.validated()
        } catch {
            let reason = Self.describe(error)
            let movedTo = moveCorruptFileAside()
            modelLogger.error("設定ファイルが壊れている（\(reason, privacy: .public)）。退避先: \(movedTo?.lastPathComponent ?? "なし", privacy: .public)")
            throw ConfigurationStoreError.corrupted(movedTo: movedTo, reason: reason)
        }
    }

    public func save(_ configuration: NonetConfiguration) throws {
        // 読み込むときと同じ形で書く（範囲外の値があると JSON にできないこともある）
        let data: Data
        do {
            data = try ModelJSON.makeEncoder().encode(configuration.validated())
        } catch {
            throw ConfigurationStoreError.writeFailed(reason: Self.describe(error))
        }

        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw ConfigurationStoreError.writeFailed(reason: error.localizedDescription)
        }

        let current: Data?
        do {
            current = try Data(contentsOf: fileURL)
        } catch CocoaError.fileReadNoSuchFile, CocoaError.fileNoSuchFile {
            current = nil
        } catch {
            // 読めないファイルを上書きすると、バックアップも残せずに元の設定を失う
            modelLogger.error("今の設定ファイルを読めないので上書きしない: \(error.localizedDescription, privacy: .public)")
            throw ConfigurationStoreError.writeFailed(reason: error.localizedDescription)
        }

        if let current {
            // 同じ中身なら書かない（バックアップが今と同じ版で上書きされ、直前の版を失わないように）
            if current == data { return }
            do {
                try current.write(to: backupFileURL, options: .atomic)
            } catch {
                // バックアップが作れなくても保存は続ける
                modelLogger.error("バックアップを作れない: \(error.localizedDescription, privacy: .public)")
            }
        }

        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            modelLogger.error("設定を保存できない: \(error.localizedDescription, privacy: .public)")
            throw ConfigurationStoreError.writeFailed(reason: error.localizedDescription)
        }
    }

    /// プロファイルの書き出し（.nonetprofile の中身）
    public static func exportData(profiles: [Profile]) throws -> Data {
        try ProfileDocument.encode(profiles)
    }

    /// 読み込んだプロファイル。id は振り直す
    public static func importProfiles(from data: Data) throws -> [Profile] {
        try ProfileDocument.decode(data)
    }
}

// MARK: - 内部

extension ConfigurationStore {
    /// ファイルの中身を今の版の設定にする（validated() はしない）。返す版はファイルに書かれていた版
    static func decodeConfiguration(
        from data: Data,
        currentVersion: Int = NonetConfiguration.currentVersion,
        steps: [Int: ConfigurationMigration.Step] = ConfigurationMigration.steps
    ) throws -> (configuration: NonetConfiguration, fileVersion: Int) {
        let fileVersion = try ConfigurationMigration.version(of: data)
        let upgraded = try ConfigurationMigration.upgrade(data, from: fileVersion, to: currentVersion, steps: steps)
        let configuration = try ModelJSON.makeDecoder().decode(NonetConfiguration.self, from: upgraded)
        return (configuration, fileVersion)
    }

    static func describe(_ error: any Error) -> String {
        switch error {
        case let failure as ConfigurationMigration.Failure: failure.description
        case is DecodingError, is EncodingError: DecodingIssue.describe(error)
        default: error.localizedDescription
        }
    }

    /// 壊れたファイルを configuration.corrupt-<日時>.json に移す。移せなければ nil
    private func moveCorruptFileAside() -> URL? {
        let fileManager = FileManager.default
        let stamp = Self.timestamp(for: Date())
        var destination = directory.appending(path: "configuration.corrupt-\(stamp).json")
        var suffix = 2
        while fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
            destination = directory.appending(path: "configuration.corrupt-\(stamp)-\(suffix).json")
            suffix += 1
        }
        do {
            try fileManager.moveItem(at: fileURL, to: destination)
            return destination
        } catch {
            // 移せなくても、次の save() でバックアップに残る
            modelLogger.error("壊れた設定ファイルを移せない: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// 新しい版のファイルを configuration.v<版>.json として残す。すでにあれば最初のものを残す
    private func preserveNewerVersionFile(_ data: Data, version: Int) {
        let url = directory.appending(path: "configuration.v\(version).json")
        guard !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        do {
            try data.write(to: url, options: .atomic)
            modelLogger.notice("新しい版（\(version)）の設定ファイルを \(url.lastPathComponent, privacy: .public) に残した")
        } catch {
            modelLogger.error("新しい版の設定ファイルを残せない: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func timestamp(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}

// MARK: - エラー

/// 設定の読み書きと、プロファイルの書き出し・読み込みの失敗。errorDescription はそのまま画面に出せる。
/// reason は調査用の短い説明（ログにも残す）
public enum ConfigurationStoreError: Error, Equatable, LocalizedError, Sendable {
    /// 設定ファイルを読めなかった（権限など）。ファイルには手を付けていない
    case readFailed(reason: String)
    /// 設定ファイルが壊れていた。上書きしないよう movedTo に移した（移せなかったら nil）
    case corrupted(movedTo: URL?, reason: String)
    /// 設定を保存できなかった
    case writeFailed(reason: String)
    /// 書き出せなかった
    case exportFailed(reason: String)
    /// Nonet のプロファイルの書き出しファイルではない
    case notAProfileDocument
    /// 新しい版の Nonet で書き出されたファイル
    case unsupportedProfileDocumentVersion(Int)
    /// 書き出しファイルが壊れている
    case invalidProfileDocument(reason: String)
    /// プロファイルが1つも無い
    case noProfiles

    public var errorDescription: String? {
        switch self {
        case .readFailed:
            String(localized: "設定ファイルを読み込めませんでした", bundle: .module)
        case .corrupted(let movedTo?, _):
            String(localized: "設定ファイルが壊れていたため読み込めませんでした。元のファイルは「\(movedTo.lastPathComponent)」として残しています", bundle: .module)
        case .corrupted(nil, _):
            String(localized: "設定ファイルが壊れていたため読み込めませんでした", bundle: .module)
        case .writeFailed:
            String(localized: "設定を保存できませんでした", bundle: .module)
        case .exportFailed:
            String(localized: "プロファイルを書き出せませんでした", bundle: .module)
        case .notAProfileDocument:
            String(localized: "Nonet のプロファイルのファイルではありません", bundle: .module)
        case .unsupportedProfileDocumentVersion:
            String(localized: "新しい版の Nonet で書き出されたファイルです。Nonet をアップデートしてください", bundle: .module)
        case .invalidProfileDocument:
            String(localized: "プロファイルのファイルが壊れています", bundle: .module)
        case .noProfiles:
            String(localized: "プロファイルが入っていません", bundle: .module)
        }
    }
}
