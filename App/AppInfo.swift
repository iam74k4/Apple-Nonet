import Foundation

/// Info.plist に入れた販売用の値（Config/Nonet.xcconfig で設定する）
enum AppInfo {
    static var purchaseURL: URL? {
        string("NonetPurchaseURL").flatMap(URL.init(string:))
    }

    static var supportURL: URL? {
        string("NonetSupportURL").flatMap(URL.init(string:))
    }

    static var privacyURL: URL? {
        string("NonetPrivacyURL").flatMap(URL.init(string:))
    }

    static var licensePublicKey: String? {
        string("NonetLicensePublicKey")
    }

    /// お問い合わせのメールの宛先（設定の「お問い合わせ…」。メールアドレスの形でなければ、設定がボタンを出さない）
    static var supportEmail: String? {
        string("NonetSupportEmail")
    }

    /// アップデートの配信先が設定されているか
    static var hasUpdateFeed: Bool {
        string("SUFeedURL") != nil && string("SUPublicEDKey") != nil
    }

    static var version: String {
        string("CFBundleShortVersionString") ?? "?"
    }

    static var build: String? {
        string("CFBundleVersion")
    }

    /// 「1.0.0 (1)」
    static var fullVersion: String {
        guard let build, build != version else { return version }
        return "\(version) (\(build))"
    }

    private static func string(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}
