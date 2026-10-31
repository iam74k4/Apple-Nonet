// 担当: keys-license
// 試用の記録がすべて消えていても、この Mac で Nonet を使ったことが分かる跡。試用をやり直させないために使う
import Foundation

/// 以前にこの Mac で Nonet を使った跡（UserDefaultsLicenseStorage が、試用の記録がどこにも無いときだけ見る）
public protocol TrialUsageEvidence: AnyObject {
    /// 跡のうち、いちばん古いものの日時。跡が無ければ nil
    func earliestUse() -> Date?
}

/// Nonet が使っているうちに作るフォルダの作成日:
/// - `~/Library/Application Support/Nonet/Backups`（設定を変えると控えを残す）
/// - `~/Library/Caches/<bundle id>`（アップデートの確認などで作られる）
/// フォルダは中身を書き換えても作成日が変わらないので、試用を始めたのはその日より前と分かる
public final class FileTrialUsageEvidence: TrialUsageEvidence {
    let locations: [URL]

    public init(locations: [URL]) {
        self.locations = locations
    }

    /// アプリの本物の置き場所
    public static func standard(bundleID: String = Bundle.main.bundleIdentifier ?? LicenseInfo.productID) -> FileTrialUsageEvidence {
        FileTrialUsageEvidence(locations: [
            ConfigurationStore(directory: ConfigurationStore.defaultDirectory).backupsDirectory,
            URL.cachesDirectory.appending(path: bundleID, directoryHint: .isDirectory),
        ])
    }

    public func earliestUse() -> Date? {
        locations.compactMap { url in
            (try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)))?[.creationDate] as? Date
        }.min()
    }
}
