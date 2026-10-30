// 担当: ui-settings
// 「お問い合わせ…」のメール。件名に版を、本文には調べるのに要る最小限の情報だけを入れる
// （ライセンスキー・登録者・プロファイルの中身は入れない。docs/privacy.md「お問い合わせ」）
import Carbon
import Foundation
import NonetCore

struct SettingsSupportMail: Equatable {
    /// 本文に入れる情報。これ以外は入れない
    struct Details: Equatable {
        /// 「1.0.0」（件名に使う）
        var version: String
        /// 「1」。版と同じか分からなければ nil
        var build: String?
        /// 「26.1 (25B78)」
        var macOSVersion: String
        /// 「Mac14,2」
        var macModel: String
        var trigger: TriggerKey
        /// JIS / ANSI / ISO
        var keyboardType: String
    }

    var address: String
    var details: Details

    /// 「Nonet 1.0.0 のお問い合わせ」
    var subject: String {
        String(localized: "Nonet \(details.version) のお問い合わせ", bundle: .module)
    }

    /// 書いてもらう場所を空けて、その下に情報を並べる
    var body: String {
        let version = details.build.map { $0 == details.version ? details.version : "\(details.version) (\($0))" } ?? details.version
        let lines = [
            "",
            "",
            String(localized: "下の情報は、調べるためだけに使います。", bundle: .module),
            "Nonet: \(version)",
            "macOS: \(details.macOSVersion)",
            "Mac: \(details.macModel)",
            String(localized: "トリガーキー: \(SettingsText.name(details.trigger))", bundle: .module),
            String(localized: "キーボード: \(details.keyboardType)", bundle: .module),
        ]
        return lines.joined(separator: "\n")
    }

    /// mailto: の URL。宛先がメールアドレスの形でなければ nil（Info.plist の値の書き間違いで、別の宛先や件名を作らない）
    var url: URL? {
        guard Self.isValidAddress(address) else { return nil }
        return URL(string: "mailto:\(address)?subject=\(Self.encode(subject))&body=\(Self.encode(body))")
    }

    /// 「name@example.com」の形か（scripts/release.sh の確かめ方と同じ）
    static func isValidAddress(_ address: String) -> Bool {
        address.wholeMatch(of: #/[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}/#) != nil
    }

    /// URL の予約されていない文字（RFC 3986）だけを残す。& = ? + も符号にし、件名や本文が宛先の項目を作らないようにする
    private static func encode(_ text: String) -> String {
        var allowed = CharacterSet()
        allowed.insert(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    // MARK: - この Mac の情報

    /// 今の Mac とアプリの情報。trigger は設定のトリガーキー、isJISKeyboard は NonetServices の値（ほかの画面と同じ判定）
    static func currentDetails(trigger: TriggerKey, isJISKeyboard: Bool, bundle: Bundle = .main) -> Details {
        let info = bundle.infoDictionary ?? [:]
        let os = ProcessInfo.processInfo.operatingSystemVersion
        var macOS = "\(os.majorVersion).\(os.minorVersion)"
        if os.patchVersion > 0 {
            macOS += ".\(os.patchVersion)"
        }
        if let build = sysctlString("kern.osversion") {
            macOS += " (\(build))"
        }
        return Details(
            version: (info["CFBundleShortVersionString"] as? String) ?? "?",
            build: info["CFBundleVersion"] as? String,
            macOSVersion: macOS,
            macModel: sysctlString("hw.model") ?? "?",
            trigger: trigger,
            keyboardType: isJISKeyboard ? "JIS" : keyboardType()
        )
    }

    /// 最後に使ったキーボードの配列の種類
    private static func keyboardType() -> String {
        switch Int(KBGetLayoutType(Int16(LMGetKbdType()))) {
        case kKeyboardJIS: "JIS"
        case kKeyboardISO: "ISO"
        case kKeyboardANSI: "ANSI"
        default: "?"
        }
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let text = String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }
}
