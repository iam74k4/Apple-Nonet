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
}

/// UserDefaults に保存し、試用の記録は Application Support のファイルにも写す。
/// 2か所の値が食い違ったら試用に厳しい方を使う（UserDefaults を消すだけで試用をやり直せないようにする）
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
        /// 食い違ったら小さい方（早い日付）を使う。false なら大きい方
        var keepsSmaller: Bool
    }

    private static let startSlot = Slot(key: trialStartKey, fileName: mirrorFileName, isDate: true, keepsSmaller: true)
    // 最後に数えた時刻が遅いほど、次に数える時間が短くなる
    private static let lastSeenSlot = Slot(key: trialLastSeenKey, fileName: lastSeenFileName, isDate: true, keepsSmaller: true)
    private static let usedSlot = Slot(key: trialUsedKey, fileName: usedFileName, isDate: false, keepsSmaller: false)

    private let defaults: UserDefaults
    private let supportDirectory: URL?

    public convenience init(defaults: UserDefaults = .standard) {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Nonet", isDirectory: true)
        self.init(defaults: defaults, supportDirectory: directory)
    }

    /// supportDirectory は試用の記録を写すフォルダ（テスト用）。nil なら写さない
    public init(defaults: UserDefaults, supportDirectory: URL?) {
        self.defaults = defaults
        self.supportDirectory = supportDirectory
    }

    public var trialStartDate: Date? {
        get { value(Self.startSlot).map(Date.init(timeIntervalSinceReferenceDate:)) }
        set { setValue(newValue?.timeIntervalSinceReferenceDate, Self.startSlot) }
    }

    public var trialLastSeenDate: Date? {
        get { value(Self.lastSeenSlot).map(Date.init(timeIntervalSinceReferenceDate:)) }
        set { setValue(newValue?.timeIntervalSinceReferenceDate, Self.lastSeenSlot) }
    }

    public var trialUsedTime: TimeInterval? {
        get { value(Self.usedSlot) }
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

    // MARK: - 2か所の値

    private func value(_ slot: Slot) -> Double? {
        let stored = defaultsValue(slot)
        let mirrored = readMirror(slot)
        let candidates = [stored, mirrored].compactMap { $0 }
        guard let chosen = slot.keepsSmaller ? candidates.min() : candidates.max() else { return nil }
        // 片方が消された・書き換えられたときは、両方をそろえておく
        if stored != chosen {
            setDefaults(chosen, slot)
        }
        if mirrored != chosen {
            writeMirror(chosen, slot)
        }
        return chosen
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

    /// 検証してから保存する。失敗したら LicenseError を投げ、保存済みのキーはそのまま
    @discardableResult
    public func activate(licenseKey: String) throws -> LicenseInfo {
        guard let verifier else { throw LicenseError.invalidPublicKey }
        let key = LicenseCoding.compactLicenseKey(licenseKey)
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
