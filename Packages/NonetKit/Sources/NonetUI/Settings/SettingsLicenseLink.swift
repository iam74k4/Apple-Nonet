// 担当: ui-settings（SettingsWindowController に足した public のものは App が使う）
// 購入のメールの「Nonet に登録する」（nonet://register?key=…）と、添付の .nonetlicense のファイル。
// 開くとライセンスのタブにキーを入れ、登録者を見せて登録してよいか尋ねる（黙って登録しない）
import AppKit
import Foundation
import NonetCore

enum SettingsLicenseLink {
    static let scheme = "nonet"
    static let registerAction = "register"
    static let keyParameter = "key"
    static let fileExtension = "nonetlicense"
    /// 受け付けるキーの文の長さ。正しいキーは数百文字（NonetCore の貼り付けの上限と同じ 8 KiB）
    static let maximumTextLength = 8 * 1024
    /// 受け付ける URL の長さ（キーを % で符号にしても収まる長さ）
    static let maximumURLLength = 3 * maximumTextLength
    /// 読むファイルの大きさの上限。前後に説明の文が付いていても足りる
    static let maximumFileSize = 64 * 1024

    enum Content: Equatable {
        /// キーの文（前後に「License key:」などが付いていてもよい。検証で取り出す）
        case text(String)
        /// Nonet のリンクやファイルだが、キーを読み取れなかった（長すぎる・空・文字でない）
        case unreadable
    }

    /// 開かれた URL の中身。Nonet のライセンスのリンクでもファイルでもなければ nil（何もしない）
    static func content(of url: URL, readFile: (URL) throws -> Data = SettingsLicenseLink.readLicenseFile) -> Content? {
        if url.isFileURL {
            guard url.pathExtension.lowercased() == fileExtension else { return nil }
            guard let data = try? readFile(url), data.count <= maximumFileSize,
                  let text = String(data: data, encoding: .utf8) else {
                return .unreadable
            }
            return checked(text)
        }
        guard url.scheme?.lowercased() == scheme else { return nil }
        guard url.absoluteString.utf8.count <= maximumURLLength,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return .unreadable
        }
        // nonet://register?key=… の register はホスト。nonet:register?key=… と書かれていれば path になる
        let action = (components.host ?? components.path).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard action.lowercased() == registerAction else { return nil }
        guard let key = components.queryItems?.first(where: { $0.name == keyParameter })?.value else {
            return .unreadable
        }
        return checked(key)
    }

    /// 空や長すぎる文は受け付けない。入力欄に入れるので、見えない制御文字は除く（改行とタブは残す）
    private static func checked(_ text: String) -> Content {
        let cleaned = String(String.UnicodeScalarView(text.unicodeScalars.filter { scalar in
            scalar == "\n" || scalar == "\t" || scalar.properties.generalCategory != .control
        })).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.utf8.count <= maximumTextLength else { return .unreadable }
        return .text(cleaned)
    }

    /// 普通のファイルだけを、上限より少し多く読む（大きなファイルを全部読まない）
    static func readLicenseFile(_ url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, (values.fileSize ?? 0) <= maximumFileSize else {
            throw CocoaError(.fileReadTooLarge)
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try handle.read(upToCount: maximumFileSize + 1) ?? Data()
    }
}

extension AppLinks {
    /// サイトのよくある質問の「ライセンスキーが見つからないときは」の節
    static let licenseKeyHelpAnchor = "faq-license-key"

    /// 「ライセンスキーが見つからないときは」のリンク。よくある質問は利用ガイドと同じ場所のトップページにあるので、
    /// 利用ガイドの URL から作る（https://nonet.astlog.dev/guide.html → https://nonet.astlog.dev/#faq-license-key）。
    /// 利用ガイドを英語のページにしていれば（localized(language:)）、英語のページ（/en/#faq-license-key）になる
    var licenseKeyHelp: URL? {
        guard let support, let scheme = support.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        return URL(string: "./#\(Self.licenseKeyHelpAnchor)", relativeTo: support)?.absoluteURL
    }
}

extension SettingsWindowController {
    /// お問い合わせのメールの宛先（Info.plist の NonetSupportEmail）。nil なら「お問い合わせ…」を出さない
    public var supportEmail: String? {
        get { model.supportEmail }
        set { model.supportEmail = newValue.flatMap { SettingsSupportMail.isValidAddress($0) ? $0 : nil } }
    }

    /// ライセンスのタブを開き、ライセンスキーの欄に入力できるようにする（試用期間が終わったときのウィンドウ・メニュー）
    public func showLicenseKeyEntry() {
        show(tab: .license)
        model.showLicenseKeyEntry()
    }

    /// nonet://register?key=… か .nonetlicense のファイルなら、ライセンスのタブを開いてキーを入れ、登録してよいか尋ねる。
    /// どちらでもなければ false を返し、何もしない
    @discardableResult
    public func openLicenseLink(_ url: URL) -> Bool {
        guard let content = SettingsLicenseLink.content(of: url) else { return false }
        show(tab: .license)
        model.openLicenseLink(content)
        return true
    }
}
