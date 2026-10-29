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

/// 試用開始日とライセンスキーの保存先
public protocol LicenseStorage: AnyObject {
    var trialStartDate: Date? { get set }
    var licenseKey: String? { get set }
}

/// UserDefaults に保存する。試用開始日は Application Support のファイルにも写し、早い方を使う
/// （UserDefaults を消すだけで試用をやり直せないようにする）
public final class UserDefaultsLicenseStorage: LicenseStorage {
    static let trialStartKey = "com.iam74k4.Nonet.license.trialStart"
    static let licenseKeyKey = "com.iam74k4.Nonet.license.key"
    static let mirrorFileName = ".install"

    private let defaults: UserDefaults
    private let mirrorFileURL: URL?

    public convenience init(defaults: UserDefaults = .standard) {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Nonet", isDirectory: true)
        self.init(defaults: defaults, supportDirectory: directory)
    }

    /// supportDirectory は試用開始日を写すフォルダ（テスト用）。nil なら写さない
    public init(defaults: UserDefaults, supportDirectory: URL?) {
        self.defaults = defaults
        mirrorFileURL = supportDirectory?.appendingPathComponent(Self.mirrorFileName, isDirectory: false)
    }

    public var trialStartDate: Date? {
        get {
            let stored = defaults.object(forKey: Self.trialStartKey) as? Date
            let mirrored = readMirror()
            guard let earliest = [stored, mirrored].compactMap({ $0 }).min() else { return nil }
            // 片方が消された・書き換えられたときは、早い方に戻しておく
            if stored != earliest {
                defaults.set(earliest, forKey: Self.trialStartKey)
            }
            if mirrored != earliest {
                writeMirror(earliest)
            }
            return earliest
        }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Self.trialStartKey)
                writeMirror(newValue)
            } else {
                defaults.removeObject(forKey: Self.trialStartKey)
                removeMirror()
            }
        }
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

    // MARK: - ファイル

    /// 中身は timeIntervalSinceReferenceDate の10進表記（Double をそのまま往復できる）
    private func readMirror() -> Date? {
        guard let mirrorFileURL, let data = try? Data(contentsOf: mirrorFileURL),
              let text = String(data: data, encoding: .utf8),
              let interval = TimeInterval(text.trimmingCharacters(in: .whitespacesAndNewlines)), interval.isFinite else {
            return nil
        }
        return Date(timeIntervalSinceReferenceDate: interval)
    }

    private func writeMirror(_ date: Date) {
        guard let mirrorFileURL else { return }
        do {
            try FileManager.default.createDirectory(at: mirrorFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(String(date.timeIntervalSinceReferenceDate).utf8).write(to: mirrorFileURL, options: .atomic)
        } catch {
            logger.error("試用開始日をファイルに保存できません: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func removeMirror() {
        guard let mirrorFileURL, FileManager.default.fileExists(atPath: mirrorFileURL.path) else { return }
        do {
            try FileManager.default.removeItem(at: mirrorFileURL)
        } catch {
            logger.error("試用開始日のファイルを削除できません: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// 14日間の試用と、買い切りライセンスの状態
@MainActor
@Observable
public final class LicenseManager {
    public static let trialDays = 14
    static let secondsPerDay: TimeInterval = 24 * 60 * 60
    static let trialDuration = TimeInterval(trialDays) * secondsPerDay

    public private(set) var entitlement: Entitlement = .expired

    @ObservationIgnored private let verifier: LicenseVerifier?
    @ObservationIgnored private let storage: any LicenseStorage
    @ObservationIgnored private let now: @Sendable () -> Date
    /// 直近の refresh で決めた試用の終わり
    @ObservationIgnored private var trialEnd: Date?
    /// 同じキーを何度も検証・ログしないための記録
    @ObservationIgnored private var checkedKey: (key: String, result: Result<LicenseInfo, LicenseError>)?

    /// 初めて使ったときに試用を始める。保存されたキーがあれば検証する
    public init(verifier: LicenseVerifier?, storage: any LicenseStorage, now: @escaping @Sendable () -> Date = { Date() }) {
        self.verifier = verifier
        self.storage = storage
        self.now = now
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
            trialEnd.map { now() < $0 } ?? false
        }
    }

    /// 日付の変化を反映する
    public func refresh() {
        let current = now()
        let start = trialStart(at: current)
        trialEnd = start.addingTimeInterval(Self.trialDuration)
        if let info = storedLicense() {
            update(.licensed(info))
        } else {
            update(Self.trialEntitlement(start: start, now: current))
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

    /// 試用の残り。終わりは開始のちょうど14日後で、残り日数は切り上げる
    static func trialEntitlement(start: Date, now: Date) -> Entitlement {
        let remaining = min(start.addingTimeInterval(trialDuration).timeIntervalSince(now), trialDuration)
        guard remaining > 0 else { return .expired }
        return .trial(daysLeft: Int((remaining / secondsPerDay).rounded(.up)))
    }

    private func trialStart(at current: Date) -> Date {
        let stored = storage.trialStartDate
        if let stored, stored <= current {
            return stored
        }
        // 初回、または時計が開始日より前に戻された。今を開始日にして、試用が14日より延びないようにする
        if stored != nil {
            logger.notice("時計が試用の開始日より前に戻されました")
        }
        storage.trialStartDate = current
        return current
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
