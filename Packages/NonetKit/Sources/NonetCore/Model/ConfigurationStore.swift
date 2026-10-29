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
    /// ConfigurationStoreError.corrupted を投げる。
    /// 読めても、保存すると失う値（知らない種類のマスやプロファイル、知らない設定など）があれば、原本を
    /// configuration.lossy-<日時>.json に残す。版の違うファイルは configuration.v<版>.json に残す
    public func load() throws -> NonetConfiguration? {
        try load(currentVersion: NonetConfiguration.currentVersion, steps: ConfigurationMigration.steps)
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

    /// 読み込んだプロファイル。id は振り直す。同じアプリやグローバルが重なっていてもそのまま返す
    /// （NonetConfiguration.importProfiles(_:) が外して数える）。読めなかったプロファイルの数も要るときは importDocument(from:)
    public static func importProfiles(from data: Data) throws -> [Profile] {
        try importDocument(from: data).profiles
    }

    /// 書き出しファイル（.nonetprofile）から読めたものと、読めなかったプロファイルの数。
    /// NonetConfiguration.importProfiles(_:) に渡すと、読めなかったものも ImportResult.skipped に数える
    public static func importDocument(from data: Data) throws -> ImportedProfiles {
        try ProfileDocument.decode(data)
    }

    /// 書き出しファイルから読めたもの
    public struct ImportedProfiles: Equatable, Sendable {
        /// 読めたプロファイル。id は振り直してある
        public var profiles: [Profile]
        /// 読めなかったプロファイル（新しい版の Nonet の種類など）の数
        public var unreadableCount: Int

        public init(profiles: [Profile], unreadableCount: Int = 0) {
            self.profiles = profiles
            self.unreadableCount = unreadableCount
        }
    }
}

// MARK: - 内部

extension ConfigurationStore {
    func load(currentVersion: Int, steps: [Int: ConfigurationMigration.Step]) throws -> NonetConfiguration? {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch CocoaError.fileReadNoSuchFile, CocoaError.fileNoSuchFile {
            return nil
        } catch {
            modelLogger.error("設定ファイルを読めない: \(error.localizedDescription, privacy: .public)")
            throw ConfigurationStoreError.readFailed(reason: error.localizedDescription)
        }

        let decoded: (configuration: NonetConfiguration, fileVersion: Int)
        do {
            decoded = try Self.decodeConfiguration(from: data, currentVersion: currentVersion, steps: steps)
        } catch {
            let reason = Self.describe(error)
            let movedTo = moveCorruptFileAside()
            modelLogger.error("設定ファイルが壊れている（\(reason, privacy: .public)）。退避先: \(movedTo?.lastPathComponent ?? "なし", privacy: .public)")
            throw ConfigurationStoreError.corrupted(movedTo: movedTo, reason: reason)
        }

        let configuration = decoded.configuration.validated()
        // 次の save() で原本は configuration.backup.json に移り、その次の save() で消える。
        // 原本にしか無い値が消えないよう、ここで別の名前で残す
        if decoded.fileVersion != currentVersion {
            // 版の違う Nonet で書いたファイル。その版に戻したときに使えるように
            preserveOriginal(data, family: "configuration.v\(decoded.fileVersion)", preferPlainName: true)
        } else if Self.losesContent(data, whenSaving: configuration) {
            preserveOriginal(data, family: "configuration.lossy", preferPlainName: false)
        }
        return configuration
    }

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

    /// data から読んだ configuration を保存すると、data にあった値のどれかを失うか
    static func losesContent(_ data: Data, whenSaving configuration: NonetConfiguration) -> Bool {
        // save() と同じ形で書く。書けなければ失うものとみなす
        guard let saved = try? ModelJSON.makeEncoder().encode(configuration.validated()) else { return true }
        if saved == data { return false }
        guard let original = try? JSONSerialization.jsonObject(with: data),
              let savedObject = try? JSONSerialization.jsonObject(with: saved) else { return true }
        return !JSONContent.isPreserved(original, in: savedObject)
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
        let destination = unusedURL(base: "configuration.corrupt-\(Self.timestamp(for: Date()))")
        do {
            try FileManager.default.moveItem(at: fileURL, to: destination)
            return destination
        } catch {
            // 移せなくても、次の save() でバックアップに残る
            modelLogger.error("壊れた設定ファイルを移せない: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// 原本を <family>.json（preferPlainName のとき。使われていれば <family>-<日時>.json）として残す。
    /// 同じ中身のもの（<family>.json・<family>-*.json）がすでにあれば書かない。
    /// 残したファイル（すでにあったものを含む）。残せなければ nil
    @discardableResult
    func preserveOriginal(_ data: Data, family: String, preferPlainName: Bool) -> URL? {
        if let existing = existingCopy(of: data, family: family) {
            return existing
        }
        let plain = directory.appending(path: "\(family).json", directoryHint: .notDirectory)
        let destination = preferPlainName && !Self.fileExists(plain)
            ? plain
            : unusedURL(base: "\(family)-\(Self.timestamp(for: Date()))")
        do {
            try data.write(to: destination, options: .atomic)
            modelLogger.notice("設定ファイルの原本を \(destination.lastPathComponent, privacy: .public) に残した")
            return destination
        } catch {
            modelLogger.error("設定ファイルの原本を残せない: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// <family>.json・<family>-*.json のうち、中身が data と同じもの
    private func existingCopy(of data: Data, family: String) -> URL? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? []
        for name in names.sorted() where name == "\(family).json" || (name.hasPrefix("\(family)-") && name.hasSuffix(".json")) {
            let url = directory.appending(path: name, directoryHint: .notDirectory)
            if (try? Data(contentsOf: url)) == data {
                return url
            }
        }
        return nil
    }

    /// directory の中の使われていない名前: <base>.json、<base>-2.json、…
    private func unusedURL(base: String) -> URL {
        var destination = directory.appending(path: "\(base).json", directoryHint: .notDirectory)
        var suffix = 2
        while Self.fileExists(destination) {
            destination = directory.appending(path: "\(base)-\(suffix).json", directoryHint: .notDirectory)
            suffix += 1
        }
        return destination
    }

    private static func fileExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
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
