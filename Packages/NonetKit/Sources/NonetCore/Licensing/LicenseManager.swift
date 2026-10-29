// 担当: keys-license（公開 API は契約）
import Foundation
import Observation

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

public final class UserDefaultsLicenseStorage: LicenseStorage {
    public init(defaults: UserDefaults = .standard) {
        fatalError("未実装: keys-license")
    }

    public var trialStartDate: Date? {
        get { fatalError("未実装: keys-license") }
        set { fatalError("未実装: keys-license") }
    }

    public var licenseKey: String? {
        get { fatalError("未実装: keys-license") }
        set { fatalError("未実装: keys-license") }
    }
}

/// 14日間の試用と、買い切りライセンスの状態
@MainActor
@Observable
public final class LicenseManager {
    public static let trialDays = 14

    public private(set) var entitlement: Entitlement = .expired

    /// 初めて使ったときに試用を始める。保存されたキーがあれば検証する
    public init(verifier: LicenseVerifier?, storage: any LicenseStorage, now: @escaping @Sendable () -> Date = { Date() }) {
        fatalError("未実装: keys-license")
    }

    /// 試用期間が終わっていなければ、またはライセンスがあれば true
    public var canExecuteActions: Bool {
        fatalError("未実装: keys-license")
    }

    /// 日付の変化を反映する
    public func refresh() {
        fatalError("未実装: keys-license")
    }

    @discardableResult
    public func activate(licenseKey: String) throws -> LicenseInfo {
        fatalError("未実装: keys-license")
    }

    public func deactivate() {
        fatalError("未実装: keys-license")
    }
}
