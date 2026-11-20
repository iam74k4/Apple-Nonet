// 担当: engine
// 試用期間の残り日数の知らせと、開きやすさの案内を、いつ出すか
import Foundation

/// 試用期間の知らせと開きやすさの案内をいつ出したかと、1回だけ行う設定の手直しを済ませたかの記録。アプリでは UserDefaults に置き、テストでは差し替える
@MainActor
public protocol HUDGuidanceStoring: AnyObject {
    /// 試用期間の残り日数の帯を最後に出した時刻
    var lastTrialReminder: Date? { get set }
    /// 開きやすさを「控えめ」にする案内（AccidentalOpenTracker）を出した（出すのは1回だけ）
    var hasShownSensitivityHint: Bool { get set }
    /// 下のページの無い設定の「ユーティリティ」を下のページにする手直し（NonetConfiguration.markUtilityPageBelow）を済ませた。
    /// 1回だけ行う（利用者が後で下のページを外しても、付け直さない）
    var hasMarkedUtilityPageBelow: Bool { get set }
}

/// UserDefaults に置く記録（アプリ本体）
@MainActor
public final class UserDefaultsHUDGuidanceStore: HUDGuidanceStoring {
    static let lastTrialReminderKey = "com.iam74k4.Nonet.guidance.lastTrialReminder"
    static let sensitivityHintKey = "com.iam74k4.Nonet.guidance.sensitivityHintShown"
    static let utilityPageAboveKey = "com.iam74k4.Nonet.migration.utilityPageAbove"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var lastTrialReminder: Date? {
        get { defaults.object(forKey: Self.lastTrialReminderKey) as? Date }
        set { defaults.set(newValue, forKey: Self.lastTrialReminderKey) }
    }

    public var hasShownSensitivityHint: Bool {
        get { defaults.bool(forKey: Self.sensitivityHintKey) }
        set { defaults.set(newValue, forKey: Self.sensitivityHintKey) }
    }

    public var hasMarkedUtilityPageBelow: Bool {
        get { defaults.bool(forKey: Self.utilityPageAboveKey) }
        set { defaults.set(newValue, forKey: Self.utilityPageAboveKey) }
    }
}

/// メモリだけに置く記録（Debug の --config-dir・自己診断・テスト）
@MainActor
public final class MemoryHUDGuidanceStore: HUDGuidanceStoring {
    public var lastTrialReminder: Date?
    public var hasShownSensitivityHint: Bool
    public var hasMarkedUtilityPageBelow: Bool

    public init(lastTrialReminder: Date? = nil, hasShownSensitivityHint: Bool = false, hasMarkedUtilityPageBelow: Bool = false) {
        self.lastTrialReminder = lastTrialReminder
        self.hasShownSensitivityHint = hasShownSensitivityHint
        self.hasMarkedUtilityPageBelow = hasMarkedUtilityPageBelow
    }
}

/// 開くつもりがないのに開いたらしい回数を数える。開いてすぐ、ポインタを真ん中から出さずに指を離して閉じた
/// （CancellationRecord.liftedBeforeMoving）のが、window の間に threshold 回になったら、開きやすさを下げる案内を出す
struct AccidentalOpenTracker {
    static let threshold = 3
    static let window: TimeInterval = 10 * 60

    /// 数えている閉じ方の時刻（Scheduler.now。古い順）
    private(set) var times: [TimeInterval] = []

    /// 開いてすぐ離して閉じた。window の中で threshold 回目になったら true（数え直す）
    mutating func record(at now: TimeInterval) -> Bool {
        // 時計が戻ったときの値（now より後）も捨てる
        times = times.filter { $0 <= now && now - $0 < Self.window }
        times.append(now)
        guard times.count >= Self.threshold else { return false }
        times.removeAll()
        return true
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
