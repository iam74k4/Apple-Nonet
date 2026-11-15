// 担当: keys-license
// 試用の記録の3つ目の置き場所。環境設定と Application Support/Nonet を消す（アンインストールツールなど）だけで試用をやり直せないようにする。
// NonetCore で Security と LocalAuthentication を使うのはこのファイルだけ（docs/architecture.md「ライセンス」の例外）。
// 2つ目の印（machineMarker）の名前を作るために、IOKit で Mac の識別子（IOPlatformUUID）も読む（ハッシュにして使い、そのものは保存しない）
import CryptoKit
import Foundation
import IOKit
import LocalAuthentication
import os
import Security

private let logger = Logger(subsystem: "com.iam74k4.Nonet", category: "keys-license")

/// 項目を読んだ結果。項目が無いのと、今は読めない（キーチェーンがロックされているなど）のとを分ける
public enum TrialRecordReading: Equatable, Sendable {
    case found(Data)
    case notFound
    /// 今は読めない。試用は残りの置き場所で数え、後で読み直す。読めるまでは書かない
    /// （書くと、読んでいない前の記録を、新しい記録で上書きして消してしまう）
    case unavailable

    var data: Data? {
        if case .found(let data) = self { return data }
        return nil
    }
}

/// 試用の記録（開始日・最後に数えた時刻・使った時間をまとめた1つのデータ）を置く場所。
/// 書けないときは何もしない（試用は残りの置き場所で数える）
public protocol TrialRecordKeychain: AnyObject {
    func readTrialRecord() -> TrialRecordReading
    func writeTrialRecord(_ data: Data)
}

/// ログインキーチェーンの汎用パスワードの項目（サービス com.iam74k4.Nonet.license.trial）。
/// - Developer ID で署名した Nonet 本体でだけ使う。署名なし・アドホック・開発用の署名のビルドは、署名の身元が配布版と違い、
///   項目を作ったのと別の身元で読むとキーチェーンが「許可しますか」と聞いてくるため、何もしない（テストも同じ）
/// - 聞かずに失敗させる指定（interactionNotAllowed）を付ける。読めなければ unavailable（後で読み直し、読めるまでは書かない）
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
    /// 項目のサービスとアカウント（ふつうは service・account。machineMarker は目立たない名前）
    let itemService: String
    let itemAccount: String
    /// キーチェーンアクセスに出る名前。nil ならサービスの名前が出る
    let itemLabel: String?

    public convenience init() {
        self.init(isEnabled: Self.isDistributedApp())
    }

    init(isEnabled: Bool, service: String = SystemTrialRecordKeychain.service, account: String = SystemTrialRecordKeychain.account, label: String? = "Nonet") {
        self.isEnabled = isEnabled
        itemService = service
        itemAccount = account
        itemLabel = label
    }

    /// 2つ目の置き場所（同じ記録を写す印）。サービスの名前は、この Mac の識別子とアプリの bundle ID から作った SHA-256 で、
    /// 名前から Nonet のものとは分からない。キーチェーンアクセスで com.iam74k4.Nonet.license.trial を消しても、こちらが残れば試用は続きから数える
    /// （UserDefaultsLicenseStorage の marker）。Mac の識別子を読めなければ使わない。Developer ID で署名した Nonet 本体でだけ動くのは同じ
    public static func machineMarker(bundleID: String = Bundle.main.bundleIdentifier ?? LicenseInfo.productID) -> SystemTrialRecordKeychain {
        guard let platformUUID = platformUUID() else {
            return SystemTrialRecordKeychain(isEnabled: false)
        }
        let name = markerName(platformUUID: platformUUID, bundleID: bundleID)
        return SystemTrialRecordKeychain(isEnabled: isDistributedApp(), service: name, account: String(name.prefix(16)), label: nil)
    }

    /// SHA-256(IOPlatformUUID + 改行 + bundle ID) の 16 進（小文字 64 文字）。同じ Mac と同じアプリなら毎回同じ
    static func markerName(platformUUID: String, bundleID: String) -> String {
        let digest = SHA256.hash(data: Data((platformUUID.uppercased() + "\n" + bundleID.lowercased()).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// この Mac の IOPlatformUUID。読めなければ nil
    static func platformUUID() -> String? {
        let entry = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        let value = IORegistryEntryCreateCFProperty(entry, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        guard let uuid = value as? String, !uuid.isEmpty else { return nil }
        return uuid
    }

    public func readTrialRecord() -> TrialRecordReading {
        guard isEnabled else { return .notFound }
        var result: CFTypeRef?
        let status = perform { query in
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            return SecItemCopyMatching(query as CFDictionary, &result)
        }
        switch status {
        case errSecSuccess:
            // 中身がデータでなければ、壊れた記録として扱う（空のデータは読めない記録になる）
            return .found(result as? Data ?? Data())
        case errSecItemNotFound:
            return .notFound
        default:
            logger.error("キーチェーンの試用の記録を読めません: \(status, privacy: .public)")
            return .unavailable
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
                if let label = itemLabel {
                    query[kSecAttrLabel as String] = label
                }
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
            kSecAttrService as String: itemService,
            kSecAttrAccount as String: itemAccount,
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
