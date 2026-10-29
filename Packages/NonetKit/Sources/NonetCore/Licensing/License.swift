// 担当: keys-license（公開 API は契約）
// ライセンスキーは「base64url(ペイロードの JSON).base64url(Ed25519 署名)」。サーバー無しで検証できる
import CryptoKit
import Foundation

public struct LicenseInfo: Codable, Equatable, Sendable {
    public static let productID = "com.iam74k4.Nonet"

    public var licenseID: String
    public var product: String
    /// 購入者の名前
    public var licensee: String
    public var email: String?
    /// "standard" など
    public var edition: String
    /// キーには秒の精度で入る
    public var issuedAt: Date

    public init(licenseID: String, product: String = LicenseInfo.productID, licensee: String, email: String?, edition: String = "standard", issuedAt: Date) {
        self.licenseID = licenseID
        self.product = product
        self.licensee = licensee
        self.email = email
        self.edition = edition
        self.issuedAt = issuedAt
    }
}

public enum LicenseError: Error, Equatable, LocalizedError, Sendable {
    case malformed
    case invalidSignature
    case wrongProduct
    case invalidPublicKey
    case invalidPrivateKey

    public var errorDescription: String? {
        switch self {
        case .malformed:
            String(localized: "ライセンスキーの形式が正しくありません。購入時のメールからキー全体をコピーしてください", bundle: .module)
        case .invalidSignature:
            String(localized: "ライセンスキーが正しくありません", bundle: .module)
        case .wrongProduct:
            String(localized: "このライセンスキーは Nonet のものではありません", bundle: .module)
        case .invalidPublicKey:
            String(localized: "ライセンスを検証する公開鍵が設定されていないか、正しくありません", bundle: .module)
        case .invalidPrivateKey:
            String(localized: "ライセンスに署名する秘密鍵が正しくありません", bundle: .module)
        }
    }
}

public struct LicenseVerifier: Sendable {
    private let publicKey: Curve25519.Signing.PublicKey

    /// 公開鍵は rawRepresentation（32 バイト）の base64
    public init(publicKeyBase64: String) throws {
        guard let data = LicenseCoding.decodeKeyMaterial(publicKeyBase64), data.count == LicenseCoding.keyLength,
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: data) else {
            throw LicenseError.invalidPublicKey
        }
        self.publicKey = publicKey
    }

    /// 前後や途中の空白・改行は無視する。失敗したら LicenseError
    public func verify(_ licenseKey: String) throws -> LicenseInfo {
        let compact = LicenseCoding.compactLicenseKey(licenseKey)
        guard compact.utf8.count <= LicenseCoding.maximumKeyLength else { throw LicenseError.malformed }
        let parts = compact.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let payload = LicenseCoding.base64URLDecoded(parts[0]),
              let signature = LicenseCoding.base64URLDecoded(parts[1]),
              signature.count == LicenseCoding.signatureLength else {
            throw LicenseError.malformed
        }
        guard publicKey.isValidSignature(signature, for: payload) else {
            throw LicenseError.invalidSignature
        }
        guard let info = try? LicenseCoding.decode(payload) else {
            throw LicenseError.malformed
        }
        guard info.product == LicenseInfo.productID else {
            throw LicenseError.wrongProduct
        }
        return info
    }
}

/// 発行側（nonet-license ツール）で使う
public struct LicenseSigner: Sendable {
    private let privateKey: Curve25519.Signing.PrivateKey

    /// 秘密鍵は rawRepresentation（32 バイト）の base64
    public init(privateKeyBase64: String) throws {
        guard let data = LicenseCoding.decodeKeyMaterial(privateKeyBase64), data.count == LicenseCoding.keyLength,
              let privateKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: data) else {
            throw LicenseError.invalidPrivateKey
        }
        self.privateKey = privateKey
    }

    /// この秘密鍵に対応する公開鍵（base64）
    public var publicKeyBase64: String {
        privateKey.publicKey.rawRepresentation.base64EncodedString()
    }

    /// 署名は JSON のバイト列そのものに対して行う。検証側は同じバイト列を検証してから読む
    public func sign(_ info: LicenseInfo) throws -> String {
        let payload = try LicenseCoding.encode(info)
        let signature = try privateKey.signature(for: payload)
        return LicenseCoding.base64URLEncoded(payload) + "." + LicenseCoding.base64URLEncoded(signature)
    }

    public static func generateKeyPair() -> (privateKeyBase64: String, publicKeyBase64: String) {
        let privateKey = Curve25519.Signing.PrivateKey()
        return (privateKey.rawRepresentation.base64EncodedString(), privateKey.publicKey.rawRepresentation.base64EncodedString())
    }
}

/// キーの書式
enum LicenseCoding {
    static let keyLength = 32
    static let signatureLength = 64
    /// 貼り付けの上限。正しいキーは数百文字
    static let maximumKeyLength = 8 * 1024

    /// 正規の JSON: キーを並べ替え、日付は ISO 8601（秒まで）
    static func encode(_ info: LicenseInfo) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(info)
    }

    /// 秒の小数を含む ISO 8601 も読む
    static func decode(_ data: Data) throws -> LicenseInfo {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            if let date = try? Date(text, strategy: .iso8601) {
                return date
            }
            if let date = try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "ISO 8601 の日付ではありません")
        }
        return try decoder.decode(LicenseInfo.self, from: data)
    }

    static func base64URLEncoded(_ data: Data) -> String {
        var text = data.base64EncodedString()
        text = text.replacingOccurrences(of: "+", with: "-")
        text = text.replacingOccurrences(of: "/", with: "_")
        return text.replacingOccurrences(of: "=", with: "")
    }

    /// パディングなしの base64url。それ以外の文字があれば nil
    static func base64URLDecoded(_ text: Substring) -> Data? {
        guard !text.isEmpty, text.unicodeScalars.allSatisfy(isBase64URLScalar) else { return nil }
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        switch base64.count % 4 {
        case 1: return nil
        case 2: base64 += "=="
        case 3: base64 += "="
        default: break
        }
        return Data(base64Encoded: base64)
    }

    /// 貼り付けで混ざる空白・改行・ゼロ幅の文字を除き、標準の base64 の文字（+ / =）も base64url にそろえる
    static func compactLicenseKey(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars where !isIgnorable(scalar) {
            switch scalar {
            case "+": scalars.append("-")
            case "/": scalars.append("_")
            case "=": continue
            default: scalars.append(scalar)
            }
        }
        return String(scalars)
    }

    /// 鍵の base64。標準の base64 でも base64url でもよく、空白・改行は無視する
    static func decodeKeyMaterial(_ text: String) -> Data? {
        let compact = compactLicenseKey(text)
        guard compact.utf8.count <= maximumKeyLength else { return nil }
        return base64URLDecoded(Substring(compact))
    }

    private static func isIgnorable(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.properties.isWhitespace {
            return true
        }
        switch scalar.value {
        // ゼロ幅スペース・ゼロ幅（非）接合子・単語結合子・BOM・ソフトハイフン
        case 0x200B, 0x200C, 0x200D, 0x2060, 0xFEFF, 0x00AD: return true
        default: return false
        }
    }

    private static func isBase64URLScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "A"..."Z", "a"..."z", "0"..."9", "-", "_": true
        default: false
        }
    }
}
