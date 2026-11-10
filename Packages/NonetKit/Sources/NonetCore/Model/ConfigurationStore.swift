// 担当: core-model（公開 API は契約）
import Foundation
import os

/// 設定を JSON で保存する。書き込みはアトミックで、直前の版を1つバックアップとして残す。
/// ほかに、以前の設定の控え（ConfigurationBackup）を Backups フォルダに maxBackups 個まで残す
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

    /// 書く先。configuration.json がシンボリックリンクなら、その指す先（アトミックに書くとリンクそのものが普通のファイルに置き換わり、
    /// 指す先が古いまま残る）
    var writeURL: URL {
        Self.isSymbolicLink(fileURL) ? fileURL.resolvingSymlinksInPath() : fileURL
    }

    static func isSymbolicLink(_ url: URL) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path(percentEncoded: false))) != nil
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
        Self.loadedDirectory.withLock { $0 = directory }
        return try load(currentVersion: NonetConfiguration.currentVersion, steps: ConfigurationMigration.steps)
    }

    /// この処理の中で最後に load() した設定の置き場所。アプリでは NonetController が持つ1つだけなので、
    /// 設定画面はここから「以前の設定に戻す」の控えを読み書きする（Debug の --config-dir で場所を変えても同じ場所を指す）
    public static var lastLoadedDirectory: URL? {
        loadedDirectory.withLock { $0 }
    }

    private static let loadedDirectory = OSAllocatedUnfairLock<URL?>(initialState: nil)

    /// 最後の load() で、この版では残せない値のある原本（新しい版の Nonet で書いたもの・失う値のあるもの）を新しく残した場所。
    /// 取ると消える（起動のたびに同じことを知らせない）。古い版からのふつうの移行では残すが、ここには入れない
    public static func takeLastPreservedOriginal() -> URL? {
        preservedOriginal.withLock { url in
            defer { url = nil }
            return url
        }
    }

    private static let preservedOriginal = OSAllocatedUnfairLock<URL?>(initialState: nil)

    public func save(_ configuration: NonetConfiguration) throws {
        try save(configuration, now: Date())
    }

    /// now は控えの日時と「1時間に1回まで」の判断に使う（テストでは時計を渡す）
    func save(_ configuration: NonetConfiguration, now: Date) throws {
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
            // 変えている間、1時間に1回まで、変える前の設定を控えに残す
            makeAutomaticBackupIfDue(current, now: now)
        }

        do {
            try data.write(to: writeURL, options: .atomic)
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
        /// 読めたが、この版では読めない中身（新しい版の種類のマス・多すぎるページなど）を落としたプロファイルの数
        public var incompleteCount: Int

        public init(profiles: [Profile], unreadableCount: Int = 0, incompleteCount: Int = 0) {
            self.profiles = profiles
            self.unreadableCount = unreadableCount
            self.incompleteCount = incompleteCount
        }
    }
}

// MARK: - 以前の設定の控え

/// 以前の設定の控え（Backups フォルダの configuration-<UTC の日時>-<理由>.json。中身は configuration.json と同じ書式）
public struct ConfigurationBackup: Equatable, Identifiable, Sendable {
    /// 控えを残した理由。ファイル名に入れる
    public enum Reason: String, CaseIterable, Sendable {
        /// 設定を変えている間に、1時間に1回まで（変える前の設定）
        case automatic = "auto"
        case beforeDeletingProfile = "delete-profile"
        case beforeDeletingPage = "delete-page"
        case beforeImport = "import"
        case beforeResettingProfile = "reset-profile"
        /// 以前の設定に戻す前（戻したことも元に戻せるように）
        case beforeRestoring = "restore"
    }

    public var url: URL
    public var date: Date
    public var reason: Reason

    public init(url: URL, date: Date, reason: Reason) {
        self.url = url
        self.date = date
        self.reason = reason
    }

    public var id: String { url.lastPathComponent }
}

extension ConfigurationStore {
    /// 残す控えの数
    public static let maxBackups = 10
    /// 変えている間に自動で控えを残す間隔
    public static let automaticBackupInterval: TimeInterval = 60 * 60

    /// ~/Library/Application Support/Nonet/Backups
    public var backupsDirectory: URL {
        directory.appending(path: "Backups", directoryHint: .isDirectory)
    }

    /// 残っている控え。新しいものから。同じ秒の控えは、ファイル名の番号の大きい（後から作った）ものから
    public func backups() -> [ConfigurationBackup] {
        let fileManager = FileManager.default
        let names = (try? fileManager.contentsOfDirectory(atPath: backupsDirectory.path(percentEncoded: false))) ?? []
        return names.compactMap { name -> (backup: ConfigurationBackup, sequence: Int)? in
            let url = backupsDirectory.appending(path: name, directoryHint: .notDirectory)
            guard let parsed = Self.parseBackupName(name) else { return nil }
            let date = parsed.date
                ?? (try? fileManager.attributesOfItem(atPath: url.path(percentEncoded: false))[.modificationDate] as? Date)
                ?? .distantPast
            return (ConfigurationBackup(url: url, date: date, reason: parsed.reason), parsed.sequence)
        }
        .sorted { lhs, rhs in
            if lhs.backup.date != rhs.backup.date { return lhs.backup.date > rhs.backup.date }
            if lhs.sequence != rhs.sequence { return lhs.sequence > rhs.sequence }
            return lhs.backup.id > rhs.backup.id
        }
        .map(\.backup)
    }

    /// 設定を控えに残す（削除や読み込みの前など）。いちばん新しい控えと同じ中身なら、新しく書かずにそれを返す。
    /// 書けなければ nil（控えが作れなくても、続く操作は止めない）
    /// alsoKeeping の控え（戻すときの、戻す控え）は、数を減らすときに消さない
    @discardableResult
    public func makeBackup(of configuration: NonetConfiguration, reason: ConfigurationBackup.Reason, alsoKeeping kept: ConfigurationBackup? = nil) -> ConfigurationBackup? {
        makeBackup(of: configuration, reason: reason, now: Date(), alsoKeeping: kept)
    }

    @discardableResult
    func makeBackup(of configuration: NonetConfiguration, reason: ConfigurationBackup.Reason, now: Date, alsoKeeping kept: ConfigurationBackup? = nil) -> ConfigurationBackup? {
        guard let data = try? ModelJSON.makeEncoder().encode(configuration.validated()) else {
            modelLogger.error("控えに残す設定を JSON にできない")
            return nil
        }
        return writeBackup(data, reason: reason, now: now, alsoKeeping: kept?.url)
    }

    /// 控えの設定。古い版のものは移行し、validated() してから返す。
    /// preservingOriginal なら（戻すとき）、版の違う控えや、この版では失う値のある控えの原本を、設定のフォルダに残す
    /// （load() と同じ。戻した後の保存と控えの整理で、原本が消えないように）
    public func loadBackup(_ backup: ConfigurationBackup, preservingOriginal: Bool = false) throws -> NonetConfiguration {
        let data: Data
        do {
            data = try Data(contentsOf: backup.url)
        } catch {
            throw ConfigurationStoreError.readFailed(reason: error.localizedDescription)
        }
        let decoded: (configuration: NonetConfiguration, fileVersion: Int)
        do {
            decoded = try Self.decodeConfiguration(from: data)
        } catch {
            throw ConfigurationStoreError.corrupted(movedTo: nil, reason: Self.describe(error))
        }
        let configuration = decoded.configuration.validated()
        if preservingOriginal {
            if decoded.fileVersion != NonetConfiguration.currentVersion {
                preserveOriginal(data, family: "configuration.v\(decoded.fileVersion)", preferPlainName: true)
            } else if Self.losesContent(data, whenSaving: configuration) {
                preserveOriginal(data, family: "configuration.lossy", preferPlainName: false)
            }
        }
        return configuration
    }

    /// save() で今のファイル（変える前の設定）を控えに残す。いちばん新しい控えから automaticBackupInterval 経っていなければ残さない
    /// （時計が戻っていたら残す）
    /// 日時が now より後の控え（時計を進めていた間のもの）は数えない。数えると、時計を戻した後は保存のたびに控えを残し、
    /// 数を減らすときに本当の控えから消していく
    func makeAutomaticBackupIfDue(_ current: Data, now: Date) {
        if let newest = backups().first(where: { $0.date <= now }), now.timeIntervalSince(newest.date) < Self.automaticBackupInterval {
            return
        }
        writeBackup(current, reason: .automatic, now: now)
    }

    @discardableResult
    private func writeBackup(_ data: Data, reason: ConfigurationBackup.Reason, now: Date, alsoKeeping kept: URL? = nil) -> ConfigurationBackup? {
        let existing = backups()
        if let newest = existing.first, (try? Data(contentsOf: newest.url)) == data {
            return newest
        }
        do {
            try FileManager.default.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
            let stamp = Self.backupTimestamp(for: now)
            let base = "configuration-\(stamp)-\(reason.rawValue)"
            // 同じ秒の控えがあれば、理由が違っても、それより大きい番号を付ける（番号で作った順に並べるため）
            let sameSecond = existing.compactMap { backup -> Int? in
                guard backup.id.hasPrefix("configuration-\(stamp)-") else { return nil }
                return Self.parseBackupName(backup.id)?.sequence
            }
            var suffix = (sameSecond.max() ?? 0) + 1
            var url = backupsDirectory.appending(path: suffix == 1 ? "\(base).json" : "\(base)-\(suffix).json", directoryHint: .notDirectory)
            while FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                suffix += 1
                url = backupsDirectory.appending(path: "\(base)-\(suffix).json", directoryHint: .notDirectory)
            }
            try data.write(to: url, options: .atomic)
            modelLogger.info("設定の控えを残した: \(url.lastPathComponent, privacy: .public)")
            pruneBackups(keeping: [url] + (kept.map { [$0] } ?? []), now: now)
            return ConfigurationBackup(url: url, date: Self.parseBackupName(url.lastPathComponent)?.date ?? now, reason: reason)
        } catch {
            modelLogger.error("設定の控えを残せない: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// 古い控えを消し、maxBackups 個にする。kept（いま書いた控えと、戻す控え）は消さない（時計が進んでいた間の控えがあると、
    /// 日時で並べたときにいま書いた控えが古い方に回り、書いたそばから消してしまうため）。
    /// 日時が now より後の控えは、本当の控えより先に消す（時計を戻した後に、本当の履歴から消していかないように）
    private func pruneBackups(keeping kept: [URL], now: Date) {
        let keptPaths = Set(kept.map(\.standardizedFileURL.path))
        let others = backups().filter { !keptPaths.contains($0.url.standardizedFileURL.path) }
        let ordered = others.filter { $0.date <= now } + others.filter { $0.date > now }
        for old in ordered.dropFirst(max(0, Self.maxBackups - keptPaths.count)) {
            do {
                try FileManager.default.removeItem(at: old.url)
            } catch {
                modelLogger.error("古い控えを消せない: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// 控えのファイル名に入れる日時（UTC。時刻帯を変えても並びが変わらないように）
    static func backupTimestamp(for date: Date) -> String {
        backupDateFormatter().string(from: date)
    }

    private static func backupDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter
    }

    /// configuration-<日時>-<理由>[-<番号>].json の日時と理由と番号（無ければ 1。同じ秒に作った順）。
    /// 控えのファイルでなければ nil。日時が読めなければ date は nil
    static func parseBackupName(_ name: String) -> (date: Date?, reason: ConfigurationBackup.Reason, sequence: Int)? {
        let prefix = "configuration-"
        guard name.hasPrefix(prefix), name.hasSuffix(".json") else { return nil }
        let body = name.dropFirst(prefix.count).dropLast(".json".count)
        let stamp = body.prefix(16)
        let rest = body.dropFirst(stamp.count)
        // 長い名前から比べる（"delete-profile" を "delete-page" などと取り違えないように）
        let reasons = ConfigurationBackup.Reason.allCases.sorted { $0.rawValue.count > $1.rawValue.count }
        for reason in reasons {
            let tag = "-\(reason.rawValue)"
            guard rest.hasPrefix(tag) else { continue }
            let tail = rest.dropFirst(tag.count)
            let sequence: Int
            if tail.isEmpty {
                sequence = 1
            } else if tail.hasPrefix("-"), let number = Int(tail.dropFirst()) {
                sequence = number
            } else {
                continue
            }
            return (backupDateFormatter().date(from: String(stamp)), reason, sequence)
        }
        return nil
    }
}

// MARK: - 内部

extension ConfigurationStore {
    func load(currentVersion: Int, steps: [Int: ConfigurationMigration.Step]) throws -> NonetConfiguration? {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch CocoaError.fileReadNoSuchFile, CocoaError.fileNoSuchFile {
            // 指す先の無いシンボリックリンク（外付けのディスクがまだつながっていないなど）は、初めての起動ではない。
            // 初回の設定で置き換えないよう、読めないものとして扱う
            if Self.isSymbolicLink(fileURL) {
                modelLogger.error("設定ファイルのシンボリックリンクの指す先がない")
                throw ConfigurationStoreError.readFailed(reason: "symbolic link target is missing")
            }
            return nil
        } catch {
            modelLogger.error("設定ファイルを読めない: \(error.localizedDescription, privacy: .public)")
            throw ConfigurationStoreError.readFailed(reason: error.localizedDescription)
        }

        let decoded: (configuration: NonetConfiguration, fileVersion: Int)
        do {
            decoded = try Self.decodeConfiguration(from: data, currentVersion: currentVersion, steps: steps)
        } catch {
            // 新しい版の Nonet で書いたファイルは、壊れているのではない。その版に戻したときに使えるよう残し、
            // この版では保存しない（初期の設定で置き換えない）
            if let version = try? ConfigurationMigration.version(of: data), version > currentVersion {
                preserveOriginal(data, family: "configuration.v\(version)", preferPlainName: true)
                modelLogger.error("新しい版（\(version)）の設定ファイルで、この版では読めない")
                throw ConfigurationStoreError.writtenByNewerVersion(version)
            }
            let reason = Self.describe(error)
            let movedTo = moveCorruptFileAside()
            modelLogger.error("設定ファイルが壊れている（\(reason, privacy: .public)）。退避先: \(movedTo?.lastPathComponent ?? "なし", privacy: .public)")
            throw ConfigurationStoreError.corrupted(movedTo: movedTo, reason: reason)
        }

        let configuration = decoded.configuration.validated()
        // 次の save() で原本は configuration.backup.json に移り、その次の save() で消える。
        // 原本にしか無い値が消えないよう、ここで別の名前で残す
        var kept: URL?
        var wroteNew = false
        if decoded.fileVersion != currentVersion {
            // 版の違う Nonet で書いたファイル。その版に戻したときに使えるように
            kept = preserveOriginal(data, family: "configuration.v\(decoded.fileVersion)", preferPlainName: true, isNew: &wroteNew)
            // 古い版からの移行は、ふつうのこと。新しい版のもの（この版では残せない値があるかもしれない）だけ知らせる
            if decoded.fileVersion < currentVersion { kept = nil }
        } else if Self.losesContent(data, whenSaving: configuration) {
            kept = preserveOriginal(data, family: "configuration.lossy", preferPlainName: false, isNew: &wroteNew)
        }
        let notice = wroteNew ? kept : nil
        Self.preservedOriginal.withLock { $0 = notice }
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
        return !JSONContent.isPreserved(GlobalSettings.removingRetiredKeys(from: original), in: savedObject)
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
        var isNew = false
        return preserveOriginal(data, family: family, preferPlainName: preferPlainName, isNew: &isNew)
    }

    /// isNew は、新しく書いたら true（同じ中身の写しがすでにあれば false）
    @discardableResult
    func preserveOriginal(_ data: Data, family: String, preferPlainName: Bool, isNew: inout Bool) -> URL? {
        isNew = false
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
            isNew = true
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
    /// 新しい版の Nonet で書いた設定ファイルで、この版では読めない。ファイルには手を付けず、写しも残した
    case writtenByNewerVersion(Int)
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
            String(localized: "設定ファイルが壊れていたため読み込めませんでした。元のファイルは「\(movedTo.lastPathComponent)」として残しています。", bundle: .module)
        case .corrupted(nil, _):
            String(localized: "設定ファイルが壊れていたため読み込めませんでした", bundle: .module)
        case .writtenByNewerVersion:
            String(localized: "新しい版の Nonet で保存した設定のため、読み込めませんでした。Nonet をアップデートしてください", bundle: .module)
        case .writeFailed:
            String(localized: "設定を保存できませんでした", bundle: .module)
        case .exportFailed:
            String(localized: "プロファイルを書き出せませんでした", bundle: .module)
        case .notAProfileDocument:
            String(localized: "Nonet のプロファイルのファイルではありません", bundle: .module)
        case .unsupportedProfileDocumentVersion:
            String(localized: "新しい版の Nonet で書き出されたファイルです。Nonet をアップデートしてください。", bundle: .module)
        case .invalidProfileDocument:
            String(localized: "プロファイルのファイルが壊れています", bundle: .module)
        case .noProfiles:
            String(localized: "プロファイルが入っていません", bundle: .module)
        }
    }
}
