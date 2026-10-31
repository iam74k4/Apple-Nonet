// 担当: keys-license
// 無効にしたライセンスの一覧。返金したキーや公開されてしまったキーを、次のリリースから受け付けないようにする。
// キーはサーバー無しで確かめるので、一覧はアプリに入れて配る（Resources/RevokedLicenses.txt。nonet-license revoke で足す）
import CryptoKit
import Foundation
import os

private let logger = Logger(subsystem: "com.iam74k4.Nonet", category: "keys-license")

/// 無効にしたライセンス ID の一覧。ID そのものではなく SHA-256（16 進の小文字）を持つ
/// （一覧はリポジトリとアプリに入るので、ID を並べない）
public struct LicenseRevocationList: Equatable, Sendable {
    /// アプリに入れる一覧のファイル（NonetCore の Resources）
    public static let resourceName = "RevokedLicenses"
    public static let resourceExtension = "txt"

    public private(set) var hashes: Set<String>

    public init(hashes: Set<String> = []) {
        self.hashes = Set(hashes.map { $0.lowercased() })
    }

    /// 一覧のファイルの中身を読む。1行に1つの SHA-256。「#」から後ろはコメント。SHA-256 の形でない行は無視する
    public init(text: String) {
        var hashes = Set<String>()
        for line in text.split(whereSeparator: \.isNewline) {
            let body = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
            guard let token = body.split(whereSeparator: \.isWhitespace).first, Self.isHash(token) else { continue }
            hashes.insert(token.lowercased())
        }
        self.hashes = hashes
    }

    public static let empty = LicenseRevocationList()

    /// アプリに入っている一覧。読めなければ空（ログに残す。キーの検証は続ける）
    public static let bundled: LicenseRevocationList = {
        guard let url = bundledURL else {
            logger.fault("無効にしたライセンスの一覧がアプリに入っていません")
            return .empty
        }
        do {
            return LicenseRevocationList(text: try String(contentsOf: url, encoding: .utf8))
        } catch {
            logger.fault("無効にしたライセンスの一覧を読めません: \(error.localizedDescription, privacy: .public)")
            return .empty
        }
    }()

    static var bundledURL: URL? {
        Bundle.module.url(forResource: resourceName, withExtension: resourceExtension)
    }

    public func isRevoked(_ licenseID: String) -> Bool {
        !hashes.isEmpty && hashes.contains(Self.hash(of: licenseID))
    }

    /// ライセンス ID の SHA-256（前後の空白を除いた UTF-8）。16 進の小文字 64 文字
    public static func hash(of licenseID: String) -> String {
        let digest = SHA256.hash(data: Data(licenseID.trimmingCharacters(in: .whitespacesAndNewlines).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func isHash<S: StringProtocol>(_ text: S) -> Bool {
        text.utf8.count == 64 && text.unicodeScalars.allSatisfy { $0.properties.isASCIIHexDigit }
    }
}
