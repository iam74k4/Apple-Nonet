// 担当: core-model。サイトごとのボタン（ProfileKind.site）
import Foundation
import Testing
@testable import NonetCore

@Suite struct ModelSiteProfileTests {
    typealias F = ControllerFixtures

    @Test func hostsAreNormalized() {
        #expect(SiteReference.normalizedHost("https://www.YouTube.com/watch?v=1") == "youtube.com")
        #expect(SiteReference.normalizedHost("github.com") == "github.com")
        #expect(SiteReference.normalizedHost("  mail.google.com/  ") == "mail.google.com")
        #expect(SiteReference.normalizedHost("localhost:3000") == "localhost")
        #expect(SiteReference.normalizedHost("") == nil)
        #expect(SiteReference.normalizedHost("not a site") == nil)
        #expect(SiteReference.normalizedHost("intranet") == nil)
    }

    @Test func aSiteMatchesItsSubdomains() {
        let site = SiteReference(host: "youtube.com")
        #expect(site.matches(host: "youtube.com"))
        #expect(site.matches(host: "www.youtube.com"))
        #expect(site.matches(host: "m.youtube.com"))
        #expect(!site.matches(host: "notyoutube.com"))
        #expect(!site.matches(host: "youtube.com.evil.example"))
    }

    private func configuration() -> NonetConfiguration {
        var configuration = F.configuration()
        configuration.addSiteProfile(host: "https://www.youtube.com/", pages: [Page(cells: [F.reload], name: nil)])
        return configuration
    }

    /// ブラウザで見ているサイトのプロファイルがあれば、ブラウザのプロファイルより先に使う（その後ろにグローバル）
    @Test func aSiteComesBeforeTheBrowser() throws {
        let configuration = configuration()
        let site = try #require(configuration.profiles.first { $0.site != nil })
        #expect(site.site?.host == "youtube.com")
        #expect(site.name == "youtube.com")
        let onYouTube = configuration.resolvedPages(frontmostBundleID: F.safari.bundleID, host: "m.youtube.com")
        #expect(onYouTube.first?.profileID == site.id)
        #expect(onYouTube.last?.profileID == configuration.globalProfile.id)
        let elsewhere = configuration.resolvedPages(frontmostBundleID: F.safari.bundleID, host: "example.com")
        #expect(elsewhere.first?.profileID == configuration.profiles.first { $0.app == F.safari }?.id)
    }

    /// 「このサイトでは使わない」なら開かない。「グローバルを使う」・空のサイトはブラウザのボタン
    @Test func modesApplyToSites() throws {
        var configuration = configuration()
        let id = try #require(configuration.profiles.first { $0.site != nil }?.id)
        configuration.updateProfile(id: id) { $0.mode = .off }
        #expect(configuration.isTurnedOff(forBundleID: F.safari.bundleID, host: "youtube.com"))
        #expect(!configuration.isTurnedOff(forBundleID: F.safari.bundleID, host: "example.com"))
        configuration.updateProfile(id: id) { $0.mode = .global }
        #expect(configuration.resolvedPages(frontmostBundleID: F.safari.bundleID, host: "youtube.com").first?.profileID != id)
    }

    @Test func sitesRoundTripAndStayUnique() throws {
        var configuration = configuration()
        // 同じサイトをもう一度足しても増えない
        let again = configuration.addSiteProfile(host: "youtube.com")
        #expect(again == configuration.profiles.first { $0.site != nil }?.id)
        #expect(configuration.profiles.filter { $0.site != nil }.count == 1)
        #expect(configuration.addSiteProfile(host: "not a site") == nil)
        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(NonetConfiguration.self, from: data)
        #expect(decoded.profiles.first { $0.site != nil }?.site == SiteReference(host: "youtube.com"))
        // 読み込みは同じサイトを置き換える
        let incoming = Profile(kind: .site(SiteReference(host: "www.youtube.com")), pages: [.empty])
        let result = configuration.importProfiles([incoming])
        #expect(result.replaced == 1)
        #expect(configuration.profiles.filter { $0.site != nil }.count == 1)
    }

    /// 消したサイトのプロファイルも元に戻せる
    @Test func aDeletedSiteCanBeRestored() throws {
        var configuration = configuration()
        let site = try #require(configuration.profiles.first { $0.site != nil })
        configuration.profiles.removeAll { $0.id == site.id }
        #expect(configuration.restoreAppProfile(site, at: 0))
        #expect(configuration.profiles.contains { $0.id == site.id })
        #expect(!configuration.restoreAppProfile(site, at: 0))
    }

    @Test func youTubeHasAPreset() throws {
        let page = try #require(SitePresets.pages(forHost: "www.youtube.com")?.first)
        #expect(page.cells[4]?.action == .keystroke(.key("k", [])))
        #expect(page.cells.allSatisfy { $0 != nil })
        #expect(SitePresets.pages(forHost: "example.com") == nil)
        #expect(SitePresets.suggestedHosts.allSatisfy { SitePresets.pages(forHost: $0) != nil })
    }
}

@MainActor
@Suite struct ControllerSiteProfileTests {
    typealias F = ControllerFixtures

    @Test func openingOnASiteUsesItsButtons() async throws {
        var configuration = F.configuration()
        configuration.addSiteProfile(host: "youtube.com", pages: [Page(cells: [nil, nil, F.reload], name: nil)])
        let h = try ControllerHarness(configuration: configuration)
        h.frontmost.siteHost = "www.youtube.com"
        h.start()
        h.open()
        #expect(h.hud.current?.title == "youtube.com")
        h.choose(2)
        await h.settle()
        #expect(h.performer.actions == [F.reload.action])
    }

    @Test func aTurnedOffSiteGivesTheClickBack() throws {
        var configuration = F.configuration()
        let id = try #require(configuration.addSiteProfile(host: "youtube.com"))
        configuration.updateProfile(id: id) { $0.mode = .off }
        let h = try ControllerHarness(configuration: configuration)
        h.frontmost.siteHost = "youtube.com"
        h.start()
        h.open()
        #expect(h.hud.shown.isEmpty)
        #expect(h.keyboard.forcePressAnswers == [false])
    }
}
