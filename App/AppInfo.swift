import Foundation

/// Info.plist に入れた販売用の値（Config/Nonet.xcconfig で設定する）
enum AppInfo {
    static var purchaseURL: URL? {
        string("NonetPurchaseURL").flatMap(URL.init(string:))
    }

    static var licensePublicKey: String? {
        string("NonetLicensePublicKey")
    }

    /// アップデートの配信先が設定されているか
    static var hasUpdateFeed: Bool {
        string("SUFeedURL") != nil && string("SUPublicEDKey") != nil
    }

    static var version: String {
        string("CFBundleShortVersionString") ?? "?"
    }

    private static func string(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}
