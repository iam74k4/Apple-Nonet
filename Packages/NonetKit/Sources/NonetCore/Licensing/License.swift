// 担当: keys-license（公開 API は契約）
// ライセンスキーは「base64url(ペイロードの JSON).base64url(Ed25519 署名)」。サーバー無しで検証できる
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
        fatalError("未実装: keys-license")
    }
}

public struct LicenseVerifier: Sendable {
    public init(publicKeyBase64: String) throws {
        fatalError("未実装: keys-license")
    }

    public func verify(_ licenseKey: String) throws -> LicenseInfo {
        fatalError("未実装: keys-license")
    }
}

/// 発行側（nonet-license ツール）で使う
public struct LicenseSigner: Sendable {
    public init(privateKeyBase64: String) throws {
        fatalError("未実装: keys-license")
    }

    public func sign(_ info: LicenseInfo) throws -> String {
        fatalError("未実装: keys-license")
    }

    public static func generateKeyPair() -> (privateKeyBase64: String, publicKeyBase64: String) {
        fatalError("未実装: keys-license")
    }
}
