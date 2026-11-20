// 担当: core-model（設定に足した「ターミナルで実行」のアプリ。GlobalSettings.terminalApp）の保存と読み込みと、空きマスだけのプロファイルの扱い
import Foundation
@testable import NonetCore
import Testing

@Suite("モデル: ターミナルのアプリと、空きマスだけのプロファイル")
struct ModelTerminalAppCodingTests {
    @Test func theDefaultIsTerminal() {
        #expect(GlobalSettings().terminalApp == .terminal)
        #expect(TerminalApp.allCases == [.terminal, .iTerm2])
        #expect(TerminalApp.terminal.bundleID == "com.apple.Terminal")
        #expect(TerminalApp.iTerm2.bundleID == "com.googlecode.iterm2")
    }

    @Test("すべての値が往復する", arguments: TerminalApp.allCases)
    func everyValueRoundTrips(_ app: TerminalApp) throws {
        let settings = GlobalSettings(openSensitivity: .low, terminalApp: app)
        #expect(try ModelFixtures.roundTrip(settings) == settings)
    }

    /// ターミナル（既定）なら書かない。この設定より前の版と同じ書式のまま
    @Test func terminalIsNotWrittenAndITerm2Is() throws {
        #expect(try ModelFixtures.jsonObject(GlobalSettings())["terminalApp"] == nil)
        #expect(try ModelFixtures.jsonObject(GlobalSettings(terminalApp: .iTerm2))["terminalApp"] as? String == "iTerm2")
    }

    @Test func anOldFileOrAnUnknownValueReadsAsTerminal() throws {
        let old = #"{"isEnabled": true, "haptics": "light"}"#
        #expect(try ModelFixtures.decode(GlobalSettings.self, old).terminalApp == .terminal)
        let unknown = try ModelFixtures.decode(GlobalSettings.self, #"{"terminalApp": "ghostty", "haptics": "strong"}"#)
        #expect(unknown.terminalApp == .terminal)
        #expect(unknown.haptics == .strong)
    }

    // MARK: 空きマスだけのプロファイル

    /// 「◯◯ のマスを作る…」で作ったばかりのプロファイル（空きマスだけ）は、無いものとしてグローバルのページだけを出す
    @Test func anAppProfileWithNoButtonsFallsBackToGlobal() {
        let global = ModelFixtures.globalProfile(pageCount: 2)
        var configuration = NonetConfiguration(profiles: [global])
        let id = configuration.addAppProfile(for: ModelFixtures.figma, preset: nil)
        #expect(configuration.profile(id: id)?.hasButtons == false)

        let pages = configuration.resolvedPages(frontmostBundleID: ModelFixtures.figma.bundleID)
        #expect(pages.map(\.profileID) == [global.id, global.id])
        #expect(ControllerPresentation.globalPagesStart(pages) == nil)
        #expect(!ControllerPresentation.hasAppLayer(pages))
    }

    /// どこかのページにマスが1つでもあれば、そのプロファイルのページを先に出す（空きの1ページ目も含めて）
    @Test func aButtonOnAnyPageKeepsTheAppPages() throws {
        let global = ModelFixtures.globalProfile()
        var configuration = NonetConfiguration(profiles: [global])
        let id = configuration.addAppProfile(for: ModelFixtures.figma, preset: nil)
        configuration.updateProfile(id: id) { profile in
            profile.pages = [.empty, ModelFixtures.page(["後"])]
        }
        #expect(configuration.profile(id: id)?.hasButtons == true)
        let pages = configuration.resolvedPages(frontmostBundleID: ModelFixtures.figma.bundleID)
        #expect(pages.map(\.profileID) == [id, id, global.id])
    }
}
