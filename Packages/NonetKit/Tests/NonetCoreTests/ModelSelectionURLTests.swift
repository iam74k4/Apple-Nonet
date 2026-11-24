// 担当: core-model。URL の {selection}（選んだ言葉で検索）
import Foundation
import Testing
@testable import NonetCore

@Suite struct ModelSelectionURLTests {
    private let search = URLAction(url: "https://www.google.com/search?q={selection}")

    @Test func theSelectionIsEncodedIntoTheURL() {
        #expect(search.usesSelection)
        #expect(!URLAction(url: "https://example.com").usesSelection)
        #expect(search.url(withSelection: "Swift 6") == "https://www.google.com/search?q=Swift%206")
        // URL を崩す文字・日本語もエンコードする
        #expect(search.url(withSelection: "a&b=c?#") == "https://www.google.com/search?q=a%26b%3Dc%3F%23")
        #expect(search.url(withSelection: "猫") == "https://www.google.com/search?q=%E7%8C%AB")
        // 前後の空白を除き、改行やタブは空白1つにまとめる
        #expect(search.url(withSelection: "  one\n\ttwo  \n") == "https://www.google.com/search?q=one%20two")
        // 長い選択は先頭だけ
        let long = String(repeating: "a", count: URLAction.maxSelectionLength + 50)
        #expect(search.url(withSelection: long) == "https://www.google.com/search?q=" + String(repeating: "a", count: URLAction.maxSelectionLength))
        // いくつあっても全部置き換える
        #expect(URLAction(url: "x://{selection}/{selection}").url(withSelection: "k") == "x://k/k")
    }

    @Test func theSummarySaysWhereItSearches() {
        #expect(Action.openURL(search).summary == ModelFixtures.text("\("google.com") で検索"))
        #expect(Action.openURL(URLAction(url: "https://www.youtube.com")).summary == "youtube.com")
    }

    @Test func templatesUseTheLanguage() {
        for template in URLSelectionTemplate.allCases {
            #expect(URLAction(url: template.url(languageCode: "ja")).usesSelection)
        }
        #expect(URLSelectionTemplate.googleTranslate.url(languageCode: "fr").contains("tl=fr"))
        #expect(URLSelectionTemplate.wikipedia.url(languageCode: "").hasPrefix("https://en.wikipedia.org"))
    }

    /// 選択を読む URL は前面のアプリに向けて実行する（テスト実行で前のアプリを前面に戻す）
    @Test func aSelectionURLDependsOnTheFrontApp() {
        #expect(ControllerExecutionPolicy.dependsOnFrontmostApp(.openURL(search)))
        #expect(!ControllerExecutionPolicy.dependsOnFrontmostApp(.openURL(URLAction(url: "https://example.com"))))
    }
}
