// 担当: ui-settings。「サイトを追加…」
import Foundation
import NonetCore
@testable import NonetUI
import Testing

@Suite @MainActor struct SettingsSiteProfileTests {
    @Test func addingASiteSelectsItAndUsesItsPreset() throws {
        let h = try SettingsHarness()
        #expect(h.model.addSiteProfile("https://www.youtube.com/watch?v=1"))
        let site = try #require(h.model.configuration.profiles.first { $0.site != nil })
        #expect(site.site?.host == "youtube.com")
        #expect(h.model.selectedProfile.id == site.id)
        let preset = try #require(SitePresets.pages(forHost: "youtube.com"))
        #expect(site.pages.map { $0.cells.map { $0?.action } } == preset.map { $0.cells.map { $0?.action } })
        #expect(!h.model.addSiteProfile("not a site"))
    }

    /// 開くと、直前に使っていたブラウザで見ていたサイトを候補に出す（もうプロファイルがあれば出さない）
    @Test func theSiteYouWereViewingIsSuggested() throws {
        let h = try SettingsHarness()
        h.frontmost.siteHost = "www.github.com"
        h.model.isAddingSite = true
        #expect(h.model.suggestedRecentSite == "github.com")
        h.model.addSiteProfile("github.com")
        h.model.isAddingSite = true
        #expect(h.model.suggestedRecentSite == nil)
    }
}
