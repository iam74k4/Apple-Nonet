// 担当: core-model。前面アプリで使うページの並び（docs/architecture.md「プロファイルとページ」）
import Foundation
@testable import NonetCore
import Testing

@Suite("resolvedPages")
struct ConfigurationResolvedPagesTests {
    enum Frontmost: String, CaseIterable, Sendable {
        /// 有効なプロファイルのあるアプリ（Xcode、2ページ）
        case enabledProfile
        /// 無効にしたプロファイルのあるアプリ（Safari）
        case disabledProfile
        /// プロファイルの無いアプリ
        case noProfile
        /// 前面アプリが分からない
        case unknown

        var bundleID: String? {
            switch self {
            case .enabledProfile: "com.apple.dt.Xcode"
            case .disabledProfile: "com.apple.Safari"
            case .noProfile: "com.apple.Notes"
            case .unknown: nil
            }
        }
    }

    static func configuration(autoSwitch: Bool, append: Bool) -> NonetConfiguration {
        NonetConfiguration(
            settings: GlobalSettings(autoSwitchProfiles: autoSwitch, appendGlobalPages: append),
            profiles: [
                ModelFixtures.globalProfile(pageCount: 3),
                ModelFixtures.profile(ModelFixtures.safari, isEnabled: false),
                ModelFixtures.profile(ModelFixtures.xcode, pageCount: 2),
            ]
        )
    }

    @Test("設定と前面アプリのすべての組み合わせ", arguments: [true, false], [true, false])
    func allCombinations(autoSwitch: Bool, append: Bool) {
        let configuration = Self.configuration(autoSwitch: autoSwitch, append: append)
        let global = configuration.profiles[0]
        let xcode = configuration.profiles[2]

        for frontmost in Frontmost.allCases {
            let pages = configuration.resolvedPages(frontmostBundleID: frontmost.bundleID)
            let usesApp = autoSwitch && frontmost == .enabledProfile
            let expectedProfiles: [(UUID, Int)] = if usesApp {
                [(xcode.id, 0), (xcode.id, 1)] + (append ? [(global.id, 0), (global.id, 1), (global.id, 2)] : [])
            } else {
                [(global.id, 0), (global.id, 1), (global.id, 2)]
            }
            #expect(pages.map(\.profileID) == expectedProfiles.map(\.0), "\(frontmost)")
            #expect(pages.map(\.pageIndex) == expectedProfiles.map(\.1), "\(frontmost)")
        }
    }

    @Test("ページの中身・プロファイル名・マス数")
    func pageContents() {
        let configuration = Self.configuration(autoSwitch: true, append: true)
        let pages = configuration.resolvedPages(frontmostBundleID: "com.apple.dt.Xcode")
        #expect(pages.map(\.profileName) == ["Xcode", "Xcode", ModelFixtures.globalName, ModelFixtures.globalName, ModelFixtures.globalName])
        #expect(pages[0].cells == configuration.profiles[2].pages[0].cells)
        #expect(pages[3].cells == configuration.profiles[0].pages[1].cells)
        #expect(pages.allSatisfy { $0.cells.count == Page.cellCount })
    }

    @Test("bundleID の大文字と小文字は区別しない")
    func caseInsensitiveBundleID() {
        let configuration = Self.configuration(autoSwitch: true, append: false)
        let pages = configuration.resolvedPages(frontmostBundleID: "COM.APPLE.DT.XCODE")
        #expect(pages.map(\.profileName) == ["Xcode", "Xcode"])
    }

    @Test("マス数が狂ったページも9マスで返す")
    func normalizesBrokenPages() {
        var configuration = Self.configuration(autoSwitch: true, append: true)
        configuration.profiles[0].pages[0].cells = [nil]
        configuration.profiles[2].pages[1].cells += [nil, nil]
        let pages = configuration.resolvedPages(frontmostBundleID: "com.apple.dt.Xcode")
        #expect(pages.allSatisfy { $0.cells.count == Page.cellCount })
    }

    @Test("グローバルのプロファイルが無い設定でも空のページ1枚を返す")
    func withoutGlobalProfile() {
        let configuration = NonetConfiguration(profiles: [])
        let pages = configuration.resolvedPages(frontmostBundleID: nil)
        #expect(pages.count == 1)
        #expect(pages[0].cells == Page.empty.cells)
        #expect(pages[0].profileName == ModelFixtures.globalName)
    }
}
