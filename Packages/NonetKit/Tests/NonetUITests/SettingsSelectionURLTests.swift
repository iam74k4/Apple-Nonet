// 担当: ui-settings。URL の {selection}: 欄の確かめと、ひな形の名前
import Foundation
import NonetCore
@testable import NonetUI
import Testing

@Suite struct SettingsSelectionURLTests {
    /// {selection} は置き換えた後の形で確かめる（URL に使えない文字として「形が正しくない」と言わない）
    @Test func thePlaceholderIsAValidPartOfTheURL() {
        #expect(SettingsURLCheck("https://www.google.com/search?q={selection}") == .valid)
        #expect(SettingsURLCheck("google.com/search?q={selection}") == .addsScheme("https"))
        #expect(SettingsURLCheck("https://{selection} x") == .invalid)
    }

    @Test func everyTemplateHasAName() {
        for template in URLSelectionTemplate.allCases {
            #expect(!SettingsURLEditor.title(template).isEmpty)
            #expect(SettingsURLCheck(template.url(languageCode: SettingsURLEditor.languageCode)) == .valid)
        }
    }
}
