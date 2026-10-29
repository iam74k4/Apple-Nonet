// 担当: core-model。設定ファイルの版の移行（内部用）
import Foundation

/// 古い版の設定ファイルを今の版の形に直す。
/// 版を上げるときは NonetConfiguration.currentVersion を上げ、steps に「その版 → 次の版」の手順を足す。
/// 手順は今の型に頼らず JSON のまま書き換える（型は版とともに変わるので）
enum ConfigurationMigration {
    typealias JSONObject = [String: Any]
    typealias Step = @Sendable (JSONObject) throws -> JSONObject

    /// キーは移行元の版。v1 が最初の版なので、まだ手順は無い
    static let steps: [Int: Step] = [:]

    enum Failure: Error, Equatable, CustomStringConvertible {
        /// JSON のオブジェクトではない、または版が整数でない
        case unreadable
        /// 1 未満の版
        case invalidVersion(Int)
        /// その版から次の版への手順が無い
        case missingStep(from: Int)

        var description: String {
            switch self {
            case .unreadable: "JSON のオブジェクトとして読めない"
            case .invalidVersion(let version): "版 \(version) は無い"
            case .missingStep(let version): "版 \(version) からの移行手順が無い"
            }
        }
    }

    /// ファイルに書かれた版。書かれていなければ最初の版（1）
    static func version(of data: Data) throws -> Int {
        let probe: VersionProbe
        do {
            probe = try JSONDecoder().decode(VersionProbe.self, from: data)
        } catch {
            throw Failure.unreadable
        }
        let version = probe.version ?? 1
        guard version >= 1 else { throw Failure.invalidVersion(version) }
        return version
    }

    /// data を target の版まで1つずつ上げる。target 以上の版ならそのまま返す
    static func upgrade(_ data: Data, from version: Int, to target: Int, steps: [Int: Step] = steps) throws -> Data {
        guard version < target else { return data }
        guard var object = (try? JSONSerialization.jsonObject(with: data)) as? JSONObject else {
            throw Failure.unreadable
        }
        for from in version..<target {
            guard let step = steps[from] else { throw Failure.missingStep(from: from) }
            object = try step(object)
            object["version"] = from + 1
        }
        return try JSONSerialization.data(withJSONObject: object)
    }

    private struct VersionProbe: Decodable {
        var version: Int?
    }
}
