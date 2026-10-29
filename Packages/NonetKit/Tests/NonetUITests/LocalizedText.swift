// テストの期待値の文言。テストの実行環境では英語が選ばれるので、日本語をそのまま比べず、各モジュールのカタログから引く
import Foundation
import NonetCore
import NonetUI

enum L10n {
    /// NonetUI の文言
    static func ui(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .nonetUI)
    }

    /// NonetCore の文言（エラーの説明、プリセットのマスの名前、グローバルなど）
    static func core(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .nonetCore)
    }

    static var globalName: String { core("グローバル") }
}
