// 担当: ui-settings
import Foundation
import NonetCore
@testable import NonetUI
import Testing

enum SettingsMenuSamples {
    static let figma = RunningAppInfo(app: SettingsFixtures.figma, processID: 101)
    static let notes = RunningAppInfo(app: SettingsFixtures.notes, processID: 202)

    /// モックのボード「メニューから選ぶ設定」の Figma のメニュー
    static var figmaMenus: [MenuItemNode] {
        [
            MenuItemNode(title: "編集", path: ["編集"], children: [
                MenuItemNode(title: "元に戻す", path: ["編集", "元に戻す"], keyEquivalent: .key("z", .command)),
                MenuItemNode(title: "複製", path: ["編集", "複製"], keyEquivalent: .key("d", .command), isEnabled: false),
                MenuItemNode(title: "すべてを選択", path: ["編集", "すべてを選択"], keyEquivalent: .key("a", .command)),
            ]),
            MenuItemNode(title: "オブジェクト", path: ["オブジェクト"], children: [
                MenuItemNode(title: "選択範囲をフレームで囲む", path: ["オブジェクト", "選択範囲をフレームで囲む"], keyEquivalent: .key("g", [.option, .command])),
                MenuItemNode(title: "自動レイアウトを追加", path: ["オブジェクト", "自動レイアウトを追加"], keyEquivalent: .key("a", .shift)),
                MenuItemNode(title: "整列", path: ["オブジェクト", "整列"], children: [
                    MenuItemNode(title: "左揃え", path: ["オブジェクト", "整列", "左揃え"], keyEquivalent: .key("a", .option)),
                    MenuItemNode(title: "", path: ["オブジェクト", "整列", ""]),
                ]),
            ]),
            MenuItemNode(title: "表示", path: ["表示"], children: [
                MenuItemNode(title: "UIを表示/非表示", path: ["表示", "UIを表示/非表示"], keyEquivalent: .key("\\", .command)),
                MenuItemNode(title: "UIを表示/非表示", path: ["表示", "UIを表示/非表示"]),
            ]),
            MenuItemNode(title: "空のメニュー", path: ["空のメニュー"], children: []),
            MenuItemNode(title: "ヘルプ", path: ["ヘルプ"], children: [
                MenuItemNode(title: "", path: ["ヘルプ", ""]),
            ]),
        ]
    }
}

@Suite struct SettingsMenuIndexTests {
    @Test func flattensLeafItemsPerTopMenu() {
        let sections = SettingsMenuIndex.sections(from: SettingsMenuSamples.figmaMenus)
        #expect(sections.map(\.title) == ["編集", "オブジェクト", "表示", "空のメニュー"])
        #expect(sections[0].entries.map(\.node.title) == ["元に戻す", "複製", "すべてを選択"])
        #expect(sections[1].entries.map(\.node.title) == ["選択範囲をフレームで囲む", "自動レイアウトを追加", "左揃え"])
        #expect(sections[1].entries[2].location == "整列")
        #expect(sections[1].entries[0].location == "")
        // 同じパスは1つだけ
        #expect(sections[2].entries.count == 1)
        // サブメニューの無いトップのメニューは、それ自体を押せる
        #expect(sections[3].entries.map(\.node.path) == [["空のメニュー"]])
    }

    @Test func filterMatchesTitlesPathsAndKeys() {
        let sections = SettingsMenuIndex.sections(from: SettingsMenuSamples.figmaMenus)
        #expect(SettingsMenuIndex.filter(sections, query: "自動").flatMap(\.entries).map(\.node.title) == ["自動レイアウトを追加"])
        #expect(SettingsMenuIndex.filter(sections, query: "整列").flatMap(\.entries).map(\.node.title) == ["左揃え"])
        #expect(SettingsMenuIndex.filter(sections, query: "オブジェクト 左").flatMap(\.entries).map(\.node.title) == ["左揃え"])
        #expect(SettingsMenuIndex.filter(sections, query: "⌥⌘G").flatMap(\.entries).map(\.node.title) == ["選択範囲をフレームで囲む"])
        #expect(SettingsMenuIndex.filter(sections, query: "ｕｉ").flatMap(\.entries).map(\.node.title) == ["UIを表示/非表示"])
        #expect(SettingsMenuIndex.filter(sections, query: "  ") == sections)
        #expect(SettingsMenuIndex.filter(sections, query: "存在しない").isEmpty)
    }

    @Test func findsEntriesByID() {
        let sections = SettingsMenuIndex.sections(from: SettingsMenuSamples.figmaMenus)
        let id = MenuItemNode(title: "左揃え", path: ["オブジェクト", "整列", "左揃え"]).id
        #expect(SettingsMenuIndex.entry(id: id, in: sections)?.node.keyEquivalent == .key("a", .option))
        #expect(SettingsMenuIndex.entry(id: "nope", in: sections) == nil)
    }
}

@Suite @MainActor struct SettingsMenuBrowserTests {
    @Test func picksThePreferredRunningAppAndLoadsItsMenus() async {
        let menus = SettingsFakeMenus()
        menus.apps = [SettingsMenuSamples.notes, SettingsMenuSamples.figma]
        menus.items = SettingsMenuSamples.figmaMenus
        let browser = SettingsMenuBrowser(menus: menus)
        browser.refreshApps(preferredBundleID: "COM.FIGMA.DESKTOP")
        #expect(browser.selectedApp == SettingsMenuSamples.figma)
        #expect(browser.state == .loading)
        await browser.waitUntilLoaded()
        #expect(browser.sections.count == 4)
        #expect(menus.requested == [SettingsMenuSamples.figma])
        // 名前順
        #expect(browser.runningApps.map(\.app.name) == ["Figma", "メモ"])
    }

    @Test func staysIdleWithoutAPreferredApp() {
        let menus = SettingsFakeMenus()
        menus.apps = [SettingsMenuSamples.notes]
        let browser = SettingsMenuBrowser(menus: menus)
        browser.refreshApps(preferredBundleID: nil)
        #expect(browser.selectedApp == nil)
        #expect(browser.state == .idle)
        #expect(menus.requested.isEmpty)
    }

    @Test func keepsTheSelectionWhileTheAppIsRunning() async {
        let menus = SettingsFakeMenus()
        menus.apps = [SettingsMenuSamples.notes, SettingsMenuSamples.figma]
        let browser = SettingsMenuBrowser(menus: menus)
        browser.select(SettingsMenuSamples.notes)
        await browser.waitUntilLoaded()
        browser.refreshApps(preferredBundleID: SettingsFixtures.figma.bundleID)
        #expect(browser.selectedApp == SettingsMenuSamples.notes)
        // 終了していたら選び直す
        menus.apps = [SettingsMenuSamples.figma]
        browser.refreshApps(preferredBundleID: SettingsFixtures.figma.bundleID)
        #expect(browser.selectedApp == SettingsMenuSamples.figma)
    }

    @Test func permissionErrorsAreRecognised() async {
        let menus = SettingsFakeMenus()
        menus.error = .permissionDenied("アクセシビリティ")
        let browser = SettingsMenuBrowser(menus: menus)
        browser.select(SettingsMenuSamples.figma)
        await browser.waitUntilLoaded()
        #expect(browser.state == .failed(message: "アクセシビリティの許可が必要です", needsPermission: true))
        menus.error = .appNotFound("Figma")
        browser.reload()
        await browser.waitUntilLoaded()
        #expect(browser.state == .failed(message: "Figma が見つかりません", needsPermission: false))
        #expect(browser.sections.isEmpty)
    }

    @Test func searchFiltersVisibleSectionsAndResetsOnAppChange() async {
        let menus = SettingsFakeMenus()
        menus.items = SettingsMenuSamples.figmaMenus
        let browser = SettingsMenuBrowser(menus: menus)
        browser.select(SettingsMenuSamples.figma)
        await browser.waitUntilLoaded()
        browser.query = "自動"
        #expect(browser.visibleSections.flatMap(\.entries).count == 1)
        browser.select(SettingsMenuSamples.notes)
        #expect(browser.query.isEmpty)
    }

    @Test func cancelDropsAnUnfinishedLoad() async {
        let menus = SettingsFakeMenus()
        menus.items = SettingsMenuSamples.figmaMenus
        let browser = SettingsMenuBrowser(menus: menus)
        browser.select(SettingsMenuSamples.figma)
        browser.cancel()
        #expect(browser.state == .idle)
        await browser.waitUntilLoaded()
        #expect(browser.state == .idle)
    }

    @Test func aSlowEarlierLoadDoesNotOverwriteALaterOne() async throws {
        let menus = SettingsFakeMenus()
        menus.itemsByProcess = [SettingsMenuSamples.figma.processID: SettingsMenuSamples.figmaMenus, SettingsMenuSamples.notes.processID: []]
        menus.delayByProcess = [SettingsMenuSamples.figma.processID: .milliseconds(40)]
        let browser = SettingsMenuBrowser(menus: menus)
        browser.select(SettingsMenuSamples.figma)
        await Task.yield()
        browser.select(SettingsMenuSamples.notes)
        await browser.waitUntilLoaded()
        #expect(browser.state == .loaded([]))
        // Figma の読み込みが後から終わっても、表示は変わらない
        try await Task.sleep(for: .milliseconds(200))
        #expect(browser.selectedApp == SettingsMenuSamples.notes)
        #expect(browser.state == .loaded([]))
    }
}
