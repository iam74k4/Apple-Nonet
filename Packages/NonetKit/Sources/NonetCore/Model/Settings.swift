// 担当: core-model（公開 API は契約）
import Foundation

/// トラックパッドを 9 マスに切り替えるキー。どれも右側のキーだけに反応する
public enum TriggerKey: String, Codable, CaseIterable, Sendable {
    case rightCommand
    case rightOption
    case rightShift
    /// fn（🌐）。左右の区別が無い
    case function

    /// JIS 配列には右⌥が無いので右⌘、それ以外は右⌥
    public static func defaultKey(isJIS: Bool) -> TriggerKey {
        isJIS ? .rightCommand : .rightOption
    }

    /// "⌘" など。HUD の「⌘を離して実行」に使う
    public var symbol: String {
        switch self {
        case .rightCommand: "⌘"
        case .rightOption: "⌥"
        case .rightShift: "⇧"
        case .function: "fn"
        }
    }
}

public enum FireMode: String, Codable, CaseIterable, Sendable {
    /// HUD を見ながら選び、トリガーキーを離したときに実行する
    case onTriggerRelease
    /// HUD を見ながら選び、マスから指を離したときに実行する
    case onFingerLift
}

public enum HUDPosition: String, Codable, CaseIterable, Sendable {
    case screenCenter
    case nearCursor
}

public enum HapticStrength: String, Codable, CaseIterable, Sendable {
    case off, light, medium, strong
}

/// トリガーを押している間、カーソルが動かないようにする方法
public enum CursorLockMethod: String, Codable, CaseIterable, Sendable {
    /// 移動イベントを捨て、それでもずれたら元の位置に戻す
    case automatic
    /// 移動イベントを捨てるだけ
    case dropEvents
    /// カーソルとマウスの動きを切り離す（CGAssociateMouseAndMouseCursorPosition）
    case decouple
    /// 何もしない（カーソルは動く）
    case none
}

public struct GlobalSettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var trigger: TriggerKey
    public var fireMode: FireMode
    /// トリガーを押してから HUD を出すまでの秒数。速押しの判定にも使う（0.15〜0.8）
    public var hudDelay: Double
    public var hudPosition: HUDPosition
    /// 前面アプリのプロファイルに自動で切り替える。false なら常にグローバル
    public var autoSwitchProfiles: Bool
    /// アプリのページの後ろにグローバルのページをつなげ、2本指スワイプで行けるようにする
    public var appendGlobalPages: Bool
    public var haptics: HapticStrength
    /// false ならトリガーキーのイベントを前面アプリに渡さない
    public var passTriggerToApps: Bool
    /// HUD を出さずに実行したとき、実行したマスを一瞬表示する
    public var showExecutionToast: Bool
    public var cursorLock: CursorLockMethod

    public init(
        isEnabled: Bool = true,
        trigger: TriggerKey = .rightCommand,
        fireMode: FireMode = .onTriggerRelease,
        hudDelay: Double = 0.3,
        hudPosition: HUDPosition = .screenCenter,
        autoSwitchProfiles: Bool = true,
        appendGlobalPages: Bool = true,
        haptics: HapticStrength = .medium,
        passTriggerToApps: Bool = true,
        showExecutionToast: Bool = true,
        cursorLock: CursorLockMethod = .automatic
    ) {
        self.isEnabled = isEnabled
        self.trigger = trigger
        self.fireMode = fireMode
        self.hudDelay = hudDelay
        self.hudPosition = hudPosition
        self.autoSwitchProfiles = autoSwitchProfiles
        self.appendGlobalPages = appendGlobalPages
        self.haptics = haptics
        self.passTriggerToApps = passTriggerToApps
        self.showExecutionToast = showExecutionToast
        self.cursorLock = cursorLock
    }

    public static let hudDelayRange: ClosedRange<Double> = 0.15...0.8
}

// MARK: - Codable
// 無い項目や知らない値は既定値にする（版の違う Nonet で書いた設定も読めるように）

extension GlobalSettings {
    private enum CodingKeys: String, CodingKey {
        case isEnabled, trigger, fireMode, hudDelay, hudPosition, autoSwitchProfiles
        case appendGlobalPages, haptics, passTriggerToApps, showExecutionToast, cursorLock
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = GlobalSettings()
        self.init(
            isEnabled: container.decodeLossy(Bool.self, forKey: .isEnabled, default: defaults.isEnabled),
            trigger: container.decodeLossy(TriggerKey.self, forKey: .trigger, default: defaults.trigger),
            fireMode: container.decodeLossy(FireMode.self, forKey: .fireMode, default: defaults.fireMode),
            hudDelay: container.decodeLossy(Double.self, forKey: .hudDelay, default: defaults.hudDelay),
            hudPosition: container.decodeLossy(HUDPosition.self, forKey: .hudPosition, default: defaults.hudPosition),
            autoSwitchProfiles: container.decodeLossy(Bool.self, forKey: .autoSwitchProfiles, default: defaults.autoSwitchProfiles),
            appendGlobalPages: container.decodeLossy(Bool.self, forKey: .appendGlobalPages, default: defaults.appendGlobalPages),
            haptics: container.decodeLossy(HapticStrength.self, forKey: .haptics, default: defaults.haptics),
            passTriggerToApps: container.decodeLossy(Bool.self, forKey: .passTriggerToApps, default: defaults.passTriggerToApps),
            showExecutionToast: container.decodeLossy(Bool.self, forKey: .showExecutionToast, default: defaults.showExecutionToast),
            cursorLock: container.decodeLossy(CursorLockMethod.self, forKey: .cursorLock, default: defaults.cursorLock)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(trigger, forKey: .trigger)
        try container.encode(fireMode, forKey: .fireMode)
        try container.encode(hudDelay, forKey: .hudDelay)
        try container.encode(hudPosition, forKey: .hudPosition)
        try container.encode(autoSwitchProfiles, forKey: .autoSwitchProfiles)
        try container.encode(appendGlobalPages, forKey: .appendGlobalPages)
        try container.encode(haptics, forKey: .haptics)
        try container.encode(passTriggerToApps, forKey: .passTriggerToApps)
        try container.encode(showExecutionToast, forKey: .showExecutionToast)
        try container.encode(cursorLock, forKey: .cursorLock)
    }

    /// 範囲外の値を直したもの
    func validated() -> GlobalSettings {
        var settings = self
        let range = GlobalSettings.hudDelayRange
        settings.hudDelay = hudDelay.isFinite
            ? min(max(hudDelay, range.lowerBound), range.upperBound)
            : GlobalSettings().hudDelay
        return settings
    }
}
