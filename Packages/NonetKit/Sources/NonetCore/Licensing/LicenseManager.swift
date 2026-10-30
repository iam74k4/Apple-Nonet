// 担当: keys-license（公開 API は契約）
import Foundation
import Observation
import os

private let logger = Logger(subsystem: "com.iam74k4.Nonet", category: "keys-license")

public enum Entitlement: Equatable, Sendable {
    case trial(daysLeft: Int)
    case licensed(LicenseInfo)
    case expired
}

/// 試用の記録とライセンスキーの保存先
public protocol LicenseStorage: AnyObject {
    var trialStartDate: Date? { get set }
    var licenseKey: String? { get set }
    /// 最後に試用の経過を数えたときの時計
    var trialLastSeenDate: Date? { get set }
    /// 数えた試用の時間（秒）。時計を戻しても減らない
    var trialUsedTime: TimeInterval? { get set }
    /// refresh で試用の記録を書き終えたときに呼ぶ。まとめて写す置き場所（キーチェーン）のため
    func didSaveTrialProgress()
}

extension LicenseStorage {
    /// 経過を保存しない実装の既定。起動し直すと開始日から数え直し、時計が開始日より前なら期限切れとみなす
    public var trialLastSeenDate: Date? {
        get { nil }
        set {}
    }

    public var trialUsedTime: TimeInterval? {
        get { nil }
        set {}
    }

    public func didSaveTrialProgress() {}
}

/// 1つの置き場所にある試用の記録。値は timeIntervalSinceReferenceDate（日付）と秒（使った時間）
struct TrialRecord: Codable, Equatable, Sendable {
    var start: Double?
    var lastSeen: Double?
    var used: Double?

    /// 最後に数えた時刻と使った時間がそろっている
    var hasUsage: Bool {
        lastSeen != nil && used != nil
    }

    var isEmpty: Bool {
        start == nil && lastSeen == nil && used == nil
    }

    /// 置き場所ごとの記録を1つにまとめる。どれかが古い・消された・書き換えられたときに、試用を延ばしも縮めもしないための決まり:
    /// - 開始日: いちばん早いもの。どこにも無ければ、使った時間から逆算した日（下の V）
    /// - 最後に数えた時刻（lastSeen）と使った時間（used）は、置き場所ごとに組で扱う。次に起動したとき now までに使った時間は
    ///   used + max(0, now - lastSeen) で、これは max(used, now - (lastSeen - used)) と同じ。
    ///   そのため置き場所のうち最も厳しい（大きい）ものは max(U, now - V)（U = used の最大、V = lastSeen - used の最小）になり、
    ///   組 (U, V + U) を返せば、時計がどこにあっても、最も厳しい置き場所とちょうど同じだけ数える。
    ///   - 古い記録（バックアップから戻したフォルダ・書けなくなったファイル）は、その後の時間を「起動していなかった間」として数えるので、
    ///     ほかの置き場所と同じ量になり、二重には数えない（used の最大と lastSeen の最小を別々に取ると、同じ時間を二度数えてしまう）
    ///   - 1か所だけ lastSeen を先に進めたり used を減らしたりしても、ほかの置き場所がその分を数えるので延びない
    ///   - 時計を戻すと now - V が小さくなるだけで、U は減らない（試用はやり直しにならず、戻した分は数えない）
    /// - used だけの置き場所は U にだけ加える（数えた量の下限になる）。lastSeen だけの置き場所は使わない
    static func reconciled(_ records: [TrialRecord]) -> TrialRecord {
        let pairs = records.compactMap { record -> (lastSeen: Double, used: Double)? in
            guard let lastSeen = record.lastSeen, let used = record.used else { return nil }
            return (lastSeen, used)
        }
        let used = records.compactMap(\.used).max()
        let virtualStart = pairs.map { $0.lastSeen - $0.used }.min()
        var result = TrialRecord(start: records.compactMap(\.start).min() ?? virtualStart, used: used)
        if let used, let virtualStart {
            // ふつうはすべて同じ組。そのときは計算し直さずにその値を返す（足し引きで最後の桁が変わらないように）
            let exact = pairs.first { $0.used == used && $0.lastSeen - $0.used == virtualStart }
            result.lastSeen = exact?.lastSeen ?? virtualStart + used
        }
        return result
    }
}

/// UserDefaults に保存し、試用の記録は Application Support のファイルにも写す（keychain を渡せば、キーチェーンにも）。
/// 置き場所ごとの記録が食い違ったら TrialRecord.reconciled でまとめる（UserDefaults やフォルダを消すだけで試用をやり直せないようにする）
public final class UserDefaultsLicenseStorage: LicenseStorage {
    static let trialStartKey = "com.iam74k4.Nonet.license.trialStart"
    static let trialLastSeenKey = "com.iam74k4.Nonet.license.trialLastSeen"
    static let trialUsedKey = "com.iam74k4.Nonet.license.trialUsed"
    static let licenseKeyKey = "com.iam74k4.Nonet.license.key"
    static let mirrorFileName = ".install"
    static let lastSeenFileName = ".install-seen"
    static let usedFileName = ".install-used"

    /// 1つの値の置き場所
    private struct Slot {
        var key: String
        var fileName: String
        var isDate: Bool
        var field: WritableKeyPath<TrialRecord, Double?> & Sendable
    }

    private static let startSlot = Slot(key: trialStartKey, fileName: mirrorFileName, isDate: true, field: \.start)
    private static let lastSeenSlot = Slot(key: trialLastSeenKey, fileName: lastSeenFileName, isDate: true, field: \.lastSeen)
    private static let usedSlot = Slot(key: trialUsedKey, fileName: usedFileName, isDate: false, field: \.used)
    private static let slots = [startSlot, lastSeenSlot, usedSlot]

    /// 使った時間がこれだけ増えたら、キーチェーンに書き直す（起動したままの日が続いても、キーチェーンの記録を古くしない）
    static let keychainWriteInterval: TimeInterval = 60 * 60

    private let defaults: UserDefaults
    private let supportDirectory: URL?
    private let keychain: (any TrialRecordKeychain)?
    /// キーチェーンから読んだ記録（書いたあとは、書いた記録）。書くのはこのプロセスだけなので、読むのは起動ごとに一度でよい
    private var keychainRecord: TrialRecord?
    private var hasReadKeychain = false
    /// この起動でキーチェーンに最後に書いた記録
    private var lastKeychainWrite: TrialRecord?

    public convenience init(defaults: UserDefaults = .standard) {
        self.init(defaults: defaults, supportDirectory: Self.defaultSupportDirectory)
    }

    /// 試用の記録をキーチェーンにも写す（アプリ本体だけ。--self-check や Debug の --config-dir では使わない）
    public convenience init(defaults: UserDefaults = .standard, keychain: (any TrialRecordKeychain)?) {
        self.init(defaults: defaults, supportDirectory: Self.defaultSupportDirectory, keychain: keychain)
    }

    /// supportDirectory は試用の記録を写すフォルダ（テスト用）。nil なら写さない。
    /// keychain は3つ目の置き場所。起動ごとに一度だけ読み、起動したときと、使った時間が keychainWriteInterval 増えたとき・
    /// 時計が変わったときに書く（キーチェーンを何度も読み書きしない）。まとめ方は current() を参照
    public init(defaults: UserDefaults, supportDirectory: URL?, keychain: (any TrialRecordKeychain)? = nil) {
        self.defaults = defaults
        self.supportDirectory = supportDirectory
        self.keychain = keychain
    }

    private static var defaultSupportDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Nonet", isDirectory: true)
    }

    public var trialStartDate: Date? {
        get { current().start.map(Date.init(timeIntervalSinceReferenceDate:)) }
        set { setValue(newValue?.timeIntervalSinceReferenceDate, Self.startSlot) }
    }

    public var trialLastSeenDate: Date? {
        get { current().lastSeen.map(Date.init(timeIntervalSinceReferenceDate:)) }
        set { setValue(newValue?.timeIntervalSinceReferenceDate, Self.lastSeenSlot) }
    }

    public var trialUsedTime: TimeInterval? {
        get { current().used }
        set { setValue(newValue, Self.usedSlot) }
    }

    public var licenseKey: String? {
        get {
            guard let key = defaults.string(forKey: Self.licenseKeyKey), !key.isEmpty else { return nil }
            return key
        }
        set {
            if let newValue, !newValue.isEmpty {
                defaults.set(newValue, forKey: Self.licenseKeyKey)
            } else {
                defaults.removeObject(forKey: Self.licenseKeyKey)
            }
        }
    }

    /// 試用の記録を書いたあとに、キーチェーンにも写す（UserDefaultsLicenseStorage.needsKeychainWrite のとき）。
    /// キーチェーンの記録は、記録を消しても消さない
    public func didSaveTrialProgress() {
        guard let keychain else { return }
        let record = current()
        guard !record.isEmpty, Self.needsKeychainWrite(record, after: lastKeychainWrite) else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            keychain.writeTrialRecord(try encoder.encode(record))
            lastKeychainWrite = record
            keychainRecord = record
            hasReadKeychain = true
        } catch {
            logger.error("試用の記録をキーチェーン用にまとめられません: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// キーチェーンに書くか: この起動でまだ書いていない・開始日が変わった・使った時間が keychainWriteInterval 以上増えた・
    /// 時計が変わった（最後に数えた時刻 − 使った時間 が動いた。ふつうは両方が同じだけ進むので動かない）
    static func needsKeychainWrite(_ record: TrialRecord, after previous: TrialRecord?) -> Bool {
        guard let previous else { return true }
        if record.start != previous.start || record.hasUsage != previous.hasUsage {
            return true
        }
        guard let used = record.used, let lastSeen = record.lastSeen,
              let previousUsed = previous.used, let previousLastSeen = previous.lastSeen else {
            return record != previous
        }
        return used - previousUsed >= keychainWriteInterval
            || abs((lastSeen - used) - (previousLastSeen - previousUsed)) > TrialProgress.clockTolerance
    }

    // MARK: - 置き場所をまとめる

    /// まとめた記録。食い違っていた置き場所は、まとめた値にそろえる。キーチェーンの記録は:
    /// - UserDefaults とフォルダのどちらにも使った時間の記録が無いとき（初回・アンインストールツールで消された）は、組のまま使う
    /// - どちらかにあるときは、使った時間だけを下限として使う（数えた量より減らさない。環境設定に「使った時間 0」と書き込んでも減らない）。
    ///   最後に数えた時刻は使わない。キーチェーンは毎回は書かないので、時計がずれていた起動の記録が残っていることがあり、
    ///   それを組で数えると、ずれた分を余計に数えてしまう。使った時間は数え終えた量なので、多く数えることはない
    private func current() -> TrialRecord {
        let stored = defaultsRecord()
        let mirrored = mirrorRecord()
        var records = [stored, mirrored]
        if let saved = readKeychain() {
            if records.contains(where: \.hasUsage) {
                records.append(TrialRecord(used: saved.used))
            } else {
                records.append(saved)
            }
        }
        let chosen = TrialRecord.reconciled(records)
        heal(stored, to: chosen) { value, slot in setDefaults(value, slot) }
        heal(mirrored, to: chosen) { value, slot in writeMirror(value, slot) }
        return chosen
    }

    /// 開始日はそのまま、使った時間は最後に数えた時刻と組で書く（片方だけ書くと、別の置き場所の値と組になって数え方が変わる）
    private func heal(_ record: TrialRecord, to chosen: TrialRecord, write: (Double, Slot) -> Void) {
        if let start = chosen.start, record.start != start {
            write(start, Self.startSlot)
        }
        guard let used = chosen.used else { return }
        if let lastSeen = chosen.lastSeen {
            if record.used != used || record.lastSeen != lastSeen {
                write(lastSeen, Self.lastSeenSlot)
                write(used, Self.usedSlot)
            }
        } else if record.lastSeen == nil, record.used != used {
            write(used, Self.usedSlot)
        }
    }

    private func setValue(_ value: Double?, _ slot: Slot) {
        if let value, Self.isValid(value, slot) {
            setDefaults(value, slot)
            writeMirror(value, slot)
        } else {
            defaults.removeObject(forKey: slot.key)
            removeMirror(slot)
        }
    }

    private static func isValid(_ value: Double, _ slot: Slot) -> Bool {
        value.isFinite && (slot.isDate || value >= 0)
    }

    // MARK: - UserDefaults

    private func defaultsRecord() -> TrialRecord {
        var record = TrialRecord()
        for slot in Self.slots {
            record[keyPath: slot.field] = defaultsValue(slot)
        }
        return record
    }

    private func defaultsValue(_ slot: Slot) -> Double? {
        let object = defaults.object(forKey: slot.key)
        let value = slot.isDate ? (object as? Date)?.timeIntervalSinceReferenceDate : (object as? NSNumber)?.doubleValue
        return value.flatMap { Self.isValid($0, slot) ? $0 : nil }
    }

    private func setDefaults(_ value: Double, _ slot: Slot) {
        if slot.isDate {
            defaults.set(Date(timeIntervalSinceReferenceDate: value), forKey: slot.key)
        } else {
            defaults.set(value, forKey: slot.key)
        }
    }

    // MARK: - ファイル

    private func mirrorRecord() -> TrialRecord {
        var record = TrialRecord()
        for slot in Self.slots {
            record[keyPath: slot.field] = readMirror(slot)
        }
        return record
    }

    private func mirrorURL(_ slot: Slot) -> URL? {
        supportDirectory?.appendingPathComponent(slot.fileName, isDirectory: false)
    }

    /// 中身は 10 進表記（日付は timeIntervalSinceReferenceDate）。Double をそのまま往復できる
    private func readMirror(_ slot: Slot) -> Double? {
        guard let url = mirrorURL(slot), let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8),
              let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)), Self.isValid(value, slot) else {
            return nil
        }
        return value
    }

    private func writeMirror(_ value: Double, _ slot: Slot) {
        guard let url = mirrorURL(slot) else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(String(value).utf8).write(to: url, options: .atomic)
        } catch {
            logger.error("試用の記録をファイルに保存できません: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func removeMirror(_ slot: Slot) {
        guard let url = mirrorURL(slot), FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            logger.error("試用の記録のファイルを削除できません: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - キーチェーン

    /// 読めない・壊れているときは nil（試用は残りの置き場所で数える）
    private func readKeychain() -> TrialRecord? {
        guard let keychain else { return nil }
        if !hasReadKeychain {
            hasReadKeychain = true
            keychainRecord = keychain.readTrialRecord().flatMap(Self.decodeKeychainRecord)
        }
        return keychainRecord
    }

    static func decodeKeychainRecord(_ data: Data) -> TrialRecord? {
        guard var record = try? JSONDecoder().decode(TrialRecord.self, from: data) else {
            logger.error("キーチェーンの試用の記録を読めないため無視します")
            return nil
        }
        // 不正な値は、無いものとして扱う
        for slot in slots {
            if let value = record[keyPath: slot.field], !isValid(value, slot) {
                record[keyPath: slot.field] = nil
            }
        }
        return record.isEmpty ? nil : record
    }
}

/// 試用で使った時間。時計を戻しても減らず、戻した分を数えもしない
struct TrialProgress: Equatable, Sendable {
    static let secondsPerDay: TimeInterval = 24 * 60 * 60
    static let duration = TimeInterval(LicenseManager.trialDays) * secondsPerDay
    /// これより小さい時計のずれ（NTP の補正など）は、時計の変更とみなさない
    static let clockTolerance: TimeInterval = 5 * 60

    /// 初めて起動した時刻
    var start: Date
    /// 最後に数えたときの時計
    var lastSeen: Date
    var used: TimeInterval

    /// 試用の終わりは使った時間がちょうど14日になったとき。残り日数は切り上げる
    var entitlement: Entitlement {
        let remaining = Self.duration - used
        guard remaining > 0 else { return .expired }
        return .trial(daysLeft: Int((remaining / Self.secondsPerDay).rounded(.up)))
    }

    var isActive: Bool {
        used < Self.duration
    }

    /// 保存された記録から now までを数える。初回なら now から始める。
    /// 使った時間の記録が無く（古い保存先や消された）、時計が開始日より前なら、どれだけ使ったか分からないので nil（期限切れ扱い）
    static func resumed(start: Date?, lastSeen: Date?, used: TimeInterval?, now: Date) -> TrialProgress? {
        guard let start else {
            return TrialProgress(start: now, lastSeen: now, used: 0)
        }
        guard let lastSeen, let used, used.isFinite, used >= 0 else {
            let sinceStart = now.timeIntervalSince(start)
            guard sinceStart >= -clockTolerance else { return nil }
            return TrialProgress(start: start, lastSeen: now, used: max(0, sinceStart))
        }
        return TrialProgress(start: start, lastSeen: lastSeen, used: used).advanced(to: now, realElapsed: nil)
    }

    /// 前回から now までの時計の進みを数える。戻っていたら数えない。
    /// realElapsed（同じプロセスの単調な時計で測った、実際に経った時間）と食い違うときは、時計が変えられたので realElapsed を数える
    func advanced(to now: Date, realElapsed: TimeInterval?) -> TrialProgress {
        var elapsed = now.timeIntervalSince(lastSeen)
        if let realElapsed, abs(elapsed - realElapsed) > Self.clockTolerance {
            elapsed = realElapsed
        }
        var next = self
        next.lastSeen = now
        next.used += max(0, elapsed)
        return next
    }
}

/// 14日間の試用と、買い切りライセンスの状態
@MainActor
@Observable
public final class LicenseManager {
    nonisolated public static let trialDays = 14

    public private(set) var entitlement: Entitlement = .expired

    @ObservationIgnored private let verifier: LicenseVerifier?
    @ObservationIgnored private let storage: any LicenseStorage
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let uptime: (@Sendable () -> TimeInterval)?
    /// 直近の refresh で数えた試用と、そのときの単調な時計
    @ObservationIgnored private var trial: (progress: TrialProgress, uptime: TimeInterval?)?
    /// 同じキーを何度も検証・ログしないための記録
    @ObservationIgnored private var checkedKey: (key: String, result: Result<LicenseInfo, LicenseError>)?

    /// 本物の時計で動かす。スリープ中も進む単調な時計と比べて、起動中に時計を変えても試用が延びも縮みもしないようにする
    public convenience init(verifier: LicenseVerifier?, storage: any LicenseStorage) {
        self.init(verifier: verifier, storage: storage, now: { Date() }, uptime: { LicenseManager.systemUptime() })
    }

    /// 初めて使ったときに試用を始める。保存されたキーがあれば検証する。
    /// uptime は単調な時計（秒）。now だけを差し替えたとき（テスト）は使わない。本物の単調な時計と比べると、偽の時計の進みを時計の変更とみなしてしまうため
    public init(
        verifier: LicenseVerifier?,
        storage: any LicenseStorage,
        now: @escaping @Sendable () -> Date,
        uptime: (@Sendable () -> TimeInterval)? = nil
    ) {
        self.verifier = verifier
        self.storage = storage
        self.now = now
        self.uptime = uptime
        refresh()
    }

    /// 試用期間が終わっていなければ、またはライセンスがあれば true
    public var canExecuteActions: Bool {
        switch entitlement {
        case .licensed:
            true
        case .expired:
            false
        case .trial:
            // refresh() が呼ばれないまま期限を過ぎても、実行はさせない
            trial.map { $0.progress.advanced(to: now(), realElapsed: Self.elapsed(from: $0.uptime, to: uptime?())).isActive } ?? false
        }
    }

    /// 日付の変化を反映する
    public func refresh() {
        let current = now()
        let currentUptime = uptime?()
        let progress = advancedTrial(now: current, uptime: currentUptime)
        if let progress {
            trial = (progress, currentUptime)
        }
        if let info = storedLicense() {
            update(.licensed(info))
        } else {
            update(progress?.entitlement ?? .expired)
        }
    }

    /// 検証してから保存する。失敗したら LicenseError を投げ、保存済みのキーはそのまま。
    /// 貼り付けた文に「License key:」などが付いていれば、キーの部分だけを保存する
    @discardableResult
    public func activate(licenseKey: String) throws -> LicenseInfo {
        guard let verifier else { throw LicenseError.invalidPublicKey }
        guard let key = LicenseCoding.licenseKey(in: licenseKey) else { throw LicenseError.malformed }
        let info = try verifier.verify(key)
        storage.licenseKey = key
        checkedKey = (key, .success(info))
        update(.licensed(info))
        logger.info("ライセンスを登録しました")
        return info
    }

    public func deactivate() {
        storage.licenseKey = nil
        checkedKey = nil
        refresh()
    }

    // MARK: - 内部

    /// スリープ中も進み、時計の変更の影響を受けない
    nonisolated static func systemUptime() -> TimeInterval {
        TimeInterval(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)) / 1_000_000_000
    }

    private static func elapsed(from start: TimeInterval?, to end: TimeInterval?) -> TimeInterval? {
        guard let start, let end else { return nil }
        return end - start
    }

    /// 試用を now まで数えて保存する。数えられなければ nil
    private func advancedTrial(now current: Date, uptime currentUptime: TimeInterval?) -> TrialProgress? {
        let storedStart = storage.trialStartDate
        let storedUsed = storage.trialUsedTime
        let progress: TrialProgress?
        if let trial {
            // このプロセスで数えてきた値を正とする。保存先が消されたり書き換えられたりしても、試用を延ばさない
            var base = trial.progress
            if let storedStart {
                base.start = min(base.start, storedStart)
            }
            if let storedUsed, storedUsed.isFinite {
                base.used = max(base.used, storedUsed)
            }
            progress = base.advanced(to: current, realElapsed: Self.elapsed(from: trial.uptime, to: currentUptime))
        } else {
            progress = TrialProgress.resumed(start: storedStart, lastSeen: storage.trialLastSeenDate, used: storedUsed, now: current)
            if progress == nil {
                logger.notice("時計が試用の開始日より前に戻されていて、使った時間の記録もありません")
            }
        }
        guard let progress else { return nil }
        // 開始日は無いときだけ書く（消されたものを戻すときも含む）
        if storedStart != progress.start {
            storage.trialStartDate = progress.start
        }
        storage.trialLastSeenDate = progress.lastSeen
        storage.trialUsedTime = progress.used
        storage.didSaveTrialProgress()
        return progress
    }

    private func storedLicense() -> LicenseInfo? {
        guard let key = storage.licenseKey, !key.isEmpty else {
            checkedKey = nil
            return nil
        }
        if let checkedKey, checkedKey.key == key {
            return try? checkedKey.result.get()
        }
        let result: Result<LicenseInfo, LicenseError>
        if let verifier {
            do {
                result = .success(try verifier.verify(key))
            } catch {
                result = .failure(error as? LicenseError ?? .malformed)
            }
        } else {
            result = .failure(.invalidPublicKey)
        }
        if case .failure(let error) = result {
            logger.error("保存されたライセンスキーを使えないため無視します: \(String(describing: error), privacy: .public)")
        }
        checkedKey = (key, result)
        return try? result.get()
    }

    /// 同じ値を入れ直して観測側を無駄に更新しない
    private func update(_ newValue: Entitlement) {
        if entitlement != newValue {
            entitlement = newValue
        }
    }
}
