// 担当: keys-license
// 試用の記録の3つ目の置き場所。環境設定と Application Support/Nonet を消す（アンインストールツールなど）だけで試用をやり直せないようにする
import Foundation
import LocalAuthentication
import os
import Security

private let logger = Logger(subsystem: "com.iam74k4.Nonet", category: "keys-license")

/// 試用の記録（開始日・最後に数えた時刻・使った時間をまとめた1つのデータ）を置く場所。
/// 読めない・書けないときは nil を返す・何もしない（試用は残りの置き場所で数える）
public protocol TrialRecordKeychain: AnyObject {
    func readTrialRecord() -> Data?
    func writeTrialRecord(_ data: Data)
}

/// ログインキーチェーンの汎用パスワードの項目（サービス com.iam74k4.Nonet.license.trial）。
/// - Developer ID で署名した Nonet 本体でだけ使う。署名なし・アドホック・開発用の署名のビルドは、署名の身元が配布版と違い、
///   項目を作ったのと別の身元で読むとキーチェーンが「許可しますか」と聞いてくるため、何もしない（テストも同じ）
/// - 聞かずに失敗させる指定（interactionNotAllowed）を付け、失敗したら記録が無いものとして扱う
/// - iCloud キーチェーンとは同期しない（ファイルベースのキーチェーンの項目は同期されず、この Mac のログインキーチェーンにだけある。
///   kSecAttrAccessible の ThisDeviceOnly はデータ保護キーチェーンの指定で、それにはアプリに無い entitlement が要る）
public final class SystemTrialRecordKeychain: TrialRecordKeychain {
    static let service = "com.iam74k4.Nonet.license.trial"
    static let account = "trial"
    /// Developer ID Application の証明書で署名した Nonet
    static let distributedAppRequirement =
        #"identifier "\#(LicenseInfo.productID)" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"#

    /// 使うか（Developer ID で署名した Nonet 本体か）
    let isEnabled: Bool

    public convenience init() {
        self.init(isEnabled: Self.isDistributedApp())
    }

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    public func readTrialRecord() -> Data? {
        guard isEnabled else { return nil }
        var result: CFTypeRef?
        let status = perform { query in
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            return SecItemCopyMatching(query as CFDictionary, &result)
        }
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            logger.error("キーチェーンの試用の記録を読めません: \(status, privacy: .public)")
            return nil
        }
    }

    public func writeTrialRecord(_ data: Data) {
        guard isEnabled else { return }
        var status = perform { query in
            SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        }
        if status == errSecItemNotFound {
            status = perform { query in
                query[kSecValueData as String] = data
                query[kSecAttrLabel as String] = "Nonet"
                return SecItemAdd(query as CFDictionary, nil)
            }
        }
        if status != errSecSuccess {
            logger.error("キーチェーンに試用の記録を書けません: \(status, privacy: .public)")
        }
    }

    /// 項目を指す問い合わせで実行する。聞かずに失敗させる指定を受け付けないキーチェーンでは、指定を外してもう一度
    private func perform(_ operation: (inout [String: Any]) -> OSStatus) -> OSStatus {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
        ]
        var withoutInteraction = query
        let context = LAContext()
        context.interactionNotAllowed = true
        withoutInteraction[kSecUseAuthenticationContext as String] = context
        let status = operation(&withoutInteraction)
        guard status == errSecParam else { return status }
        return operation(&query)
    }

    /// 動いているのが Developer ID で署名した Nonet 本体か
    static func isDistributedApp() -> Bool {
        var code: SecCode?
        var requirement: SecRequirement?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(distributedAppRequirement as CFString, [], &requirement) == errSecSuccess,
              let requirement else {
            return false
        }
        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }
}
