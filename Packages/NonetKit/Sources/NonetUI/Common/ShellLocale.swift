// 担当: ui-shell
import Foundation

extension Locale {
    /// NonetUI の文言に実際に使われている言語（Bundle.module が選んだもの）に、今の地域を合わせたロケール。
    /// 複数形（1 day / 2 days）はロケールの言語の規則で選ばれる。地域が日本でアプリだけ英語にしているときに
    /// Locale.current（ja_JP）のまま選ぶと、英語の文が「1 days」になる
    static var nonetUI: Locale {
        localization(Bundle.module.preferredLocalizations.first, region: Locale.current.region)
    }

    static func localization(_ language: String?, region: Locale.Region?) -> Locale {
        guard let language, !language.isEmpty else { return .current }
        var components = Locale.Components(identifier: language)
        if components.region == nil {
            components.region = region
        }
        return Locale(components: components)
    }
}
