// 担当: engine
// 試用期間の残り日数の知らせを、いつ出すか
import Foundation

/// 試用期間の知らせをいつ出したかの記録。アプリでは UserDefaults に置き、テストでは差し替える
@MainActor
public protocol HUDGuidanceStoring: AnyObject {
    /// 試用期間の残り日数の帯を最後に出した時刻
    var lastTrialReminder: Date? { get set }
}

/// UserDefaults に置く記録（アプリ本体）
@MainActor
public final class UserDefaultsHUDGuidanceStore: HUDGuidanceStoring {
    static let lastTrialReminderKey = "com.iam74k4.Nonet.guidance.lastTrialReminder"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var lastTrialReminder: Date? {
        get { defaults.object(forKey: Self.lastTrialReminderKey) as? Date }
        set { defaults.set(newValue, forKey: Self.lastTrialReminderKey) }
    }
}

/// メモリだけに置く記録（Debug の --config-dir・自己診断・テスト）
@MainActor
public final class MemoryHUDGuidanceStore: HUDGuidanceStoring {
    public var lastTrialReminder: Date?

    public init(lastTrialReminder: Date? = nil) {
        self.lastTrialReminder = lastTrialReminder
    }
}

/// いつ案内や知らせを出すか
public enum HUDGuidance {
    /// 試用期間の残りがこの日数以下になったら、HUD の帯で知らせる（1日に1回まで）
    public static let trialReminderDays = 3

    /// 試用期間の残り日数を、いま HUD の帯で知らせるか。残りが trialReminderDays 以下で、今日（暦の日）はまだ知らせていなければ true。
    /// 前に知らせた時刻が未来（時計を戻した）なら、今日はまだとみなす
    static func isTrialReminderDue(daysLeft: Int, lastShown: Date?, now: Date, calendar: Calendar = .current) -> Bool {
        guard daysLeft <= trialReminderDays else { return false }
        guard let lastShown, lastShown <= now else { return true }
        return !calendar.isDate(lastShown, inSameDayAs: now)
    }
}
