// 担当: core-model（公開 API は契約）
import Foundation

/// 設定を JSON で保存する。書き込みはアトミックで、直前の版を1つバックアップとして残す
public struct ConfigurationStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// ~/Library/Application Support/Nonet
    public static var defaultDirectory: URL {
        fatalError("未実装: core-model")
    }

    public var fileURL: URL {
        fatalError("未実装: core-model")
    }

    /// 保存された設定。ファイルが無ければ nil。古い版は移行し、validated() してから返す
    public func load() throws -> NonetConfiguration? {
        fatalError("未実装: core-model")
    }

    public func save(_ configuration: NonetConfiguration) throws {
        fatalError("未実装: core-model")
    }

    /// プロファイルの書き出し（.nonetprofile の中身）
    public static func exportData(profiles: [Profile]) throws -> Data {
        fatalError("未実装: core-model")
    }

    /// 読み込んだプロファイル。id は振り直す
    public static func importProfiles(from data: Data) throws -> [Profile] {
        fatalError("未実装: core-model")
    }
}
