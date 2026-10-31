// 担当: core-model（公開 API は契約）
import Foundation

public enum HUDPosition: String, Codable, CaseIterable, Sendable {
    case screenCenter
    case nearCursor
}

public enum HapticStrength: String, Codable, CaseIterable, Sendable {
    case off, light, medium, strong
}

/// 9マスを開いている間、ポインタが動かないようにする方法
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

/// HUD とトーストの大きさ（文字の小さい HUD を読みにくい人のため）
public enum HUDScale: String, Codable, CaseIterable, Sendable {
    case standard
    case large
    case extraLarge

    /// HUD とトーストの寸法と文字に掛ける倍率
    public var factor: Double {
        switch self {
        case .standard: 1
        case .large: 1.25
        case .extraLarge: 1.5
        }
    }
}

public struct GlobalSettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var hudPosition: HUDPosition
    /// 前面アプリのプロファイルに自動で切り替える。false なら常にグローバル
    public var autoSwitchProfiles: Bool
    /// アプリのページの後ろにグローバルのページをつなげ、2本指スワイプで行けるようにする
    public var appendGlobalPages: Bool
    public var haptics: HapticStrength
    /// 時間の掛かるマスが終わったときに、実行したマスを一瞬表示する
    public var showExecutionToast: Bool
    public var cursorLock: CursorLockMethod
    /// HUD とトーストの大きさ。既定は標準
    public var hudScale: HUDScale

    public init(
        isEnabled: Bool = true,
        hudPosition: HUDPosition = .screenCenter,
        autoSwitchProfiles: Bool = true,
        appendGlobalPages: Bool = true,
        haptics: HapticStrength = .medium,
        showExecutionToast: Bool = true,
        cursorLock: CursorLockMethod = .automatic,
        hudScale: HUDScale = .standard
    ) {
        self.isEnabled = isEnabled
        self.hudPosition = hudPosition
        self.autoSwitchProfiles = autoSwitchProfiles
        self.appendGlobalPages = appendGlobalPages
        self.haptics = haptics
        self.showExecutionToast = showExecutionToast
        self.cursorLock = cursorLock
        self.hudScale = hudScale
    }
}

// MARK: - Codable
// 無い項目や知らない値は既定値にする（版の違う Nonet で書いた設定も読めるように）。
// トリガーキーで開いていた版の項目（trigger・fireMode・hudDelay・passTriggerToApps・touchActivation）は、
// 書いてあっても読み飛ばし、もう書かない（前の版はそれらが無ければ既定値で読む）

extension GlobalSettings {
    /// トリガーキーで開いていた版の項目。読み飛ばし、もう書かない
    static let retiredKeys: Set<String> = ["trigger", "fireMode", "hudDelay", "passTriggerToApps", "touchActivation"]

    /// 設定ファイル（JSONSerialization で読んだもの）から、settings の retiredKeys を除いたもの。
    /// 読み飛ばした項目を、保存すると失われる中身とみなさない（その原本を configuration.lossy-… に残さない）
    static func removingRetiredKeys(from object: Any) -> Any {
        guard var root = object as? [String: Any], let settings = root["settings"] as? [String: Any] else { return object }
        root["settings"] = settings.filter { !retiredKeys.contains($0.key) }
        return root
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled, hudPosition, autoSwitchProfiles, appendGlobalPages, haptics, showExecutionToast, cursorLock, hudScale
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = GlobalSettings()
        self.init(
            isEnabled: container.decodeLossy(Bool.self, forKey: .isEnabled, default: defaults.isEnabled),
            hudPosition: container.decodeLossy(HUDPosition.self, forKey: .hudPosition, default: defaults.hudPosition),
            autoSwitchProfiles: container.decodeLossy(Bool.self, forKey: .autoSwitchProfiles, default: defaults.autoSwitchProfiles),
            appendGlobalPages: container.decodeLossy(Bool.self, forKey: .appendGlobalPages, default: defaults.appendGlobalPages),
            haptics: container.decodeLossy(HapticStrength.self, forKey: .haptics, default: defaults.haptics),
            showExecutionToast: container.decodeLossy(Bool.self, forKey: .showExecutionToast, default: defaults.showExecutionToast),
            cursorLock: container.decodeLossy(CursorLockMethod.self, forKey: .cursorLock, default: defaults.cursorLock),
            hudScale: container.decodeLossy(HUDScale.self, forKey: .hudScale, default: defaults.hudScale)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(hudPosition, forKey: .hudPosition)
        try container.encode(autoSwitchProfiles, forKey: .autoSwitchProfiles)
        try container.encode(appendGlobalPages, forKey: .appendGlobalPages)
        try container.encode(haptics, forKey: .haptics)
        try container.encode(showExecutionToast, forKey: .showExecutionToast)
        try container.encode(cursorLock, forKey: .cursorLock)
        // 標準（既定）なら書かない。この設定より前の版と同じ書式のままにする（無ければ標準として読む）
        if hudScale != .standard {
            try container.encode(hudScale, forKey: .hudScale)
        }
    }
}
