// 担当: core-model（公開 API は契約）
import Foundation

public enum HUDPosition: String, Codable, CaseIterable, Sendable {
    case screenCenter
    case nearCursor
}

public enum HapticStrength: String, Codable, CaseIterable, Sendable {
    case off, light, medium, strong
}

/// 開きやすさ。上の縁からの滑り込みをどれだけ受け付けるか（帯の高さ・時間・動きの量。EdgeSlideRecognizer.Thresholds）
public enum OpenSensitivity: String, Codable, CaseIterable, Sendable {
    /// 奥の端のすぐ近くで、すばやく滑らせたときだけ（ふだんのポインタ操作で開いてしまう人向け）
    case low
    case standard
    /// 縁から少し離れて置いても、ゆっくりでも開く（縁から滑らせても開かないことがある人向け）
    case high
}

/// 9マスを開いている間、ポインタが動かないようにする方法（KeyboardMonitor の設定。利用者には見せず、自動だけを使う）
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
    /// 触覚。設定の画面ではオン（medium）とオフだけを選ぶ（前の版の light・strong はそのまま読む）
    public var haptics: HapticStrength
    /// HUD とトーストの大きさ。既定は標準
    public var hudScale: HUDScale
    /// 開きやすさ。既定は標準
    public var openSensitivity: OpenSensitivity

    public init(
        isEnabled: Bool = true,
        hudPosition: HUDPosition = .screenCenter,
        haptics: HapticStrength = .medium,
        hudScale: HUDScale = .standard,
        openSensitivity: OpenSensitivity = .standard
    ) {
        self.isEnabled = isEnabled
        self.hudPosition = hudPosition
        self.haptics = haptics
        self.hudScale = hudScale
        self.openSensitivity = openSensitivity
    }
}

// MARK: - Codable
// 無い項目や知らない値は既定値にする（版の違う Nonet で書いた設定も読めるように）。
// 前の版の項目（トリガーキーで開いていた版の trigger・fireMode・hudDelay・passTriggerToApps・touchActivation と、
// 設定から外した autoSwitchProfiles・appendGlobalPages・showExecutionToast・cursorLock）は、書いてあっても読み飛ばし、
// もう書かない（前の版はそれらが無ければ既定値で読む）

extension GlobalSettings {
    /// 前の版の項目。読み飛ばし、もう書かない
    static let retiredKeys: Set<String> = [
        "trigger", "fireMode", "hudDelay", "passTriggerToApps", "touchActivation",
        "autoSwitchProfiles", "appendGlobalPages", "showExecutionToast", "cursorLock",
    ]

    /// 設定ファイル（JSONSerialization で読んだもの）から、settings の retiredKeys を除いたもの。
    /// 読み飛ばした項目を、保存すると失われる中身とみなさない（その原本を configuration.lossy-… に残さない）
    static func removingRetiredKeys(from object: Any) -> Any {
        guard var root = object as? [String: Any], let settings = root["settings"] as? [String: Any] else { return object }
        root["settings"] = settings.filter { !retiredKeys.contains($0.key) }
        return root
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled, hudPosition, haptics, hudScale, openSensitivity
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = GlobalSettings()
        self.init(
            isEnabled: container.decodeLossy(Bool.self, forKey: .isEnabled, default: defaults.isEnabled),
            hudPosition: container.decodeLossy(HUDPosition.self, forKey: .hudPosition, default: defaults.hudPosition),
            haptics: container.decodeLossy(HapticStrength.self, forKey: .haptics, default: defaults.haptics),
            hudScale: container.decodeLossy(HUDScale.self, forKey: .hudScale, default: defaults.hudScale),
            openSensitivity: container.decodeLossy(OpenSensitivity.self, forKey: .openSensitivity, default: defaults.openSensitivity)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(hudPosition, forKey: .hudPosition)
        try container.encode(haptics, forKey: .haptics)
        // 標準（既定）なら書かない。この設定より前の版と同じ書式のままにする（無ければ標準として読む）
        if hudScale != .standard {
            try container.encode(hudScale, forKey: .hudScale)
        }
        if openSensitivity != .standard {
            try container.encode(openSensitivity, forKey: .openSensitivity)
        }
    }
}
