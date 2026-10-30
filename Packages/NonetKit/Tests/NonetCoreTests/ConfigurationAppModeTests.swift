// 担当: core-model。アプリごとの使い方（ProfileMode）・ページの名前・プロファイルの複製とプリセットに戻す・消したものを元に戻す
import Foundation
@testable import NonetCore
import Testing

@Suite("アプリごとの使い方（ProfileMode）")
struct ConfigurationAppModeTests {
    @Test("isEnabled は mode の見方。false にするとグローバルを使う")
    func isEnabledMapsToMode() {
        var profile = Profile(kind: .app(ModelFixtures.safari))
        #expect(profile.mode == .profile)
        profile.isEnabled = false
        #expect(profile.mode == .global)
        profile.mode = .off
        #expect(!profile.isEnabled)
        #expect(Profile(kind: .app(ModelFixtures.safari), isEnabled: false).mode == .global)
    }

    @Test("前の版の設定（isEnabled だけ）を読める")
    func decodesOldProfiles() throws {
        let enabled = try ModelFixtures.decode(Profile.self, #"{"kind": {"type": "app", "app": {"bundleID": "a", "name": "A"}}, "isEnabled": true}"#)
        let disabled = try ModelFixtures.decode(Profile.self, #"{"kind": {"type": "app", "app": {"bundleID": "a", "name": "A"}}, "isEnabled": false}"#)
        #expect(enabled.mode == .profile)
        #expect(disabled.mode == .global)
    }

    @Test("off のときだけ mode を書き、isEnabled は false にする（前の版はグローバルを使うと読む）")
    func encodesModeOnlyWhenOff() throws {
        let app = Profile(kind: .app(ModelFixtures.safari), mode: .profile)
        #expect(try ModelFixtures.jsonObject(app)["mode"] == nil)
        #expect(try ModelFixtures.jsonObject(app)["isEnabled"] as? Bool == true)
        let global = Profile(kind: .app(ModelFixtures.safari), mode: .global)
        #expect(try ModelFixtures.jsonObject(global)["mode"] == nil)
        #expect(try ModelFixtures.jsonObject(global)["isEnabled"] as? Bool == false)
        let off = Profile(kind: .app(ModelFixtures.safari), mode: .off)
        #expect(try ModelFixtures.jsonObject(off)["mode"] as? String == "off")
        #expect(try ModelFixtures.jsonObject(off)["isEnabled"] as? Bool == false)
        #expect(try ModelFixtures.roundTrip(off) == off)
    }

    @Test("知らない mode は isEnabled で読む。mode が isEnabled と食い違えば mode を使う")
    func unknownModeFallsBackToIsEnabled() throws {
        let future = try ModelFixtures.decode(Profile.self, #"{"kind": {"type": "global"}, "isEnabled": false, "mode": "pause"}"#)
        #expect(future.mode == .global)
        let off = try ModelFixtures.decode(Profile.self, #"{"kind": {"type": "app", "app": {"bundleID": "a", "name": "A"}}, "isEnabled": true, "mode": "off"}"#)
        #expect(off.mode == .off)
    }

    @Test("グローバルはいつもこのプロファイルを使う")
    func globalIsAlwaysUsed() {
        var global = ModelFixtures.globalProfile()
        global.mode = .off
        let configuration = NonetConfiguration(profiles: [global]).validated()
        #expect(configuration.globalProfile.mode == .profile)
    }

    @Test("使わないアプリ: isTurnedOff は bundleID の大文字小文字を区別せず、ほかの使い方では false")
    func isTurnedOff() {
        var configuration = ModelFixtures.configuration()
        #expect(!configuration.isTurnedOff(forBundleID: ModelFixtures.safari.bundleID))
        #expect(!configuration.isTurnedOff(forBundleID: nil))
        #expect(!configuration.isTurnedOff(forBundleID: ""))
        configuration.setAppMode(.off, for: ModelFixtures.safari)
        #expect(configuration.isTurnedOff(forBundleID: "COM.apple.safari"))
        #expect(configuration.appMode(forBundleID: ModelFixtures.safari.bundleID) == .off)
        #expect(configuration.appProfile(forBundleID: ModelFixtures.safari.bundleID) == nil)
        // 前面のアプリで切り替えない設定でも使わない
        configuration.settings.autoSwitchProfiles = false
        #expect(configuration.isTurnedOff(forBundleID: ModelFixtures.safari.bundleID))
        configuration.setAppMode(.global, for: ModelFixtures.safari)
        #expect(!configuration.isTurnedOff(forBundleID: ModelFixtures.safari.bundleID))
    }

    @Test("プロファイルの無いアプリを使わないにすると、プリセットの中身でプロファイルを作る")
    func setAppModeCreatesAProfile() throws {
        var configuration = NonetConfiguration(profiles: [ModelFixtures.globalProfile()]).validated()
        let preset = try #require(PresetLibrary.preset(forBundleID: ModelFixtures.xcode.bundleID))
        let created = configuration.setAppMode(.off, for: ModelFixtures.xcode, preset: preset)
        let id = try #require(created)
        let profile = try #require(configuration.profile(id: id))
        #expect(profile.mode == .off)
        #expect(profile.pages.map { $0.cells.map { $0?.title } } == preset.pages.map { $0.cells.map { $0?.title } })
        // 2回目は同じプロファイルを変える
        let again = configuration.setAppMode(.profile, for: ModelFixtures.xcode)
        #expect(again == id)
        #expect(configuration.modelAppProfiles.count == 1)
        let empty = configuration.setAppMode(.off, for: AppReference(bundleID: " ", name: "空"))
        #expect(empty == nil)
    }

    @Test("使わないアプリの設定は保存して読み直しても同じ")
    func storeRoundTrip() throws {
        try ModelFixtures.withTemporaryDirectory { directory throws in
            let store = ConfigurationStore(directory: directory)
            var configuration = ModelFixtures.configuration()
            configuration.setAppMode(.off, for: ModelFixtures.xcode)
            try store.save(configuration)
            #expect(try store.load()?.isTurnedOff(forBundleID: ModelFixtures.xcode.bundleID) == true)
        }
    }
}

@Suite("ページの名前")
struct PageNameTests {
    @Test("名前は前後の空白を除き、改行は空白にし、長ければ切る。空なら nil")
    func normalizedName() {
        #expect(Page.normalizedName("  デバッグ \n") == "デバッグ")
        #expect(Page.normalizedName("ビルド\nと実行") == "ビルド と実行")
        #expect(Page.normalizedName("   ") == nil)
        #expect(Page.normalizedName(nil) == nil)
        let long = String(repeating: "あ", count: Page.maxNameLength + 5)
        #expect(Page.normalizedName(long)?.count == Page.maxNameLength)
        #expect(Page(name: " Git ").name == "Git")
    }

    @Test("名前の無いページは name を書かない（前の版と同じ書式）。あれば書いて読める")
    func coding() throws {
        #expect(try ModelFixtures.jsonObject(Page.empty)["name"] == nil)
        let named = Page(cells: [ModelFixtures.cell("ビルド")], name: "ビルド")
        #expect(try ModelFixtures.jsonObject(named)["name"] as? String == "ビルド")
        #expect(try ModelFixtures.roundTrip(named) == named)
        // 読めない名前は無いものとする
        let broken = try ModelFixtures.decode(Page.self, #"{"cells": [], "name": 3}"#)
        #expect(broken.name == nil)
    }

    @Test("ページの名前を変える・外す。ページ数を直しても名前は残る")
    func rename() throws {
        var configuration = ModelFixtures.configuration()
        let xcodeID = configuration.profiles[2].id
        configuration.renamePage(at: 1, profileID: xcodeID, to: "  デバッグ ")
        #expect(configuration.profile(id: xcodeID)?.pages[1].name == "デバッグ")
        configuration.profiles[2].pages[1].cells.removeLast(3)
        configuration = configuration.validated()
        #expect(configuration.profile(id: xcodeID)?.pages[1].name == "デバッグ")
        configuration.renamePage(at: 1, profileID: xcodeID, to: "")
        #expect(configuration.profile(id: xcodeID)?.pages[1].name == nil)
        // 無いページは何もしない
        let before = configuration
        configuration.renamePage(at: 5, profileID: xcodeID, to: "x")
        #expect(configuration == before)
    }

    @Test("HUD の題名: 名前のあるページは「プロファイル · ページ」")
    func resolvedTitle() throws {
        var configuration = ModelFixtures.configuration()
        let xcodeID = configuration.profiles[2].id
        configuration.renamePage(at: 1, profileID: xcodeID, to: "デバッグ")
        let pages = configuration.resolvedPages(frontmostBundleID: ModelFixtures.xcode.bundleID)
        #expect(pages.map(\.pageName) == [nil, "デバッグ", nil])
        #expect(pages.map(\.title) == ["Xcode", "Xcode · デバッグ", ModelFixtures.globalName])
    }
}

@Suite("プロファイルの複製・プリセットに戻す・元に戻す")
struct ConfigurationProfileCopyTests {
    @Test("複製: ページと名前を写し、マスの id は新しく、元のアプリのメニュー項目は新しいアプリに向ける")
    func duplicate() throws {
        let vscode = AppReference(bundleID: "com.microsoft.VSCode", name: "Visual Studio Code")
        let cursor = AppReference(bundleID: "com.todesktop.230313mzl4w4u92", name: "Cursor")
        var configuration = NonetConfiguration(profiles: [ModelFixtures.globalProfile()])
        let sourceID = configuration.addAppProfile(for: vscode, preset: nil)
        let palette = Cell(title: "コマンド", icon: .symbol("command"), action: .menuItem(MenuItemAction(app: vscode, path: ["表示", "コマンドパレット…"])))
        let finderMenu = Cell(title: "Finder", icon: .symbol("folder"), action: .menuItem(MenuItemAction(app: ModelFixtures.figma, path: ["ファイル"])))
        let frontMenu = Cell(title: "コピー", icon: .symbol("doc.on.doc"), action: .menuItem(MenuItemAction(path: ["編集", "コピー"])))
        configuration.setCell(palette, at: CellAddress(page: 0, index: 0), profileID: sourceID)
        configuration.setCell(finderMenu, at: CellAddress(page: 0, index: 1), profileID: sourceID)
        configuration.setCell(frontMenu, at: CellAddress(page: 0, index: 2), profileID: sourceID)
        configuration.addPage(profileID: sourceID)
        configuration.renamePage(at: 1, profileID: sourceID, to: "Git")
        configuration.updateProfile(id: sourceID) { $0.mode = .global }

        let duplicated = configuration.duplicateProfile(id: sourceID, for: cursor)
        let copyID = try #require(duplicated)
        let copy = try #require(configuration.profile(id: copyID))
        let source = try #require(configuration.profile(id: sourceID))
        #expect(copy.app == cursor)
        #expect(copy.mode == .profile)
        #expect(copy.pages.map(\.name) == [nil, "Git"])
        let copyIDs = Set(copy.pages.flatMap(\.cells).compactMap { $0?.id })
        let sourceIDs = Set(source.pages.flatMap(\.cells).compactMap { $0?.id })
        #expect(copyIDs.count == 3)
        #expect(copyIDs.isDisjoint(with: sourceIDs))
        #expect(copy.pages[0].cells[0]?.action == .menuItem(MenuItemAction(app: cursor, path: ["表示", "コマンドパレット…"])))
        #expect(copy.pages[0].cells[1]?.action == finderMenu.action)
        #expect(copy.pages[0].cells[2]?.action == frontMenu.action)
        #expect(configuration.modelAppProfiles.last?.id == copyID)

        // すでにプロファイルのあるアプリや、無いプロファイルには作らない
        let taken = configuration.duplicateProfile(id: sourceID, for: cursor)
        let missing = configuration.duplicateProfile(id: UUID(), for: ModelFixtures.slack)
        #expect(taken == nil)
        #expect(missing == nil)
        // グローバルからも作れる
        let globalID = configuration.globalProfile.id
        let fromGlobal = configuration.duplicateProfile(id: globalID, for: ModelFixtures.slack)
        #expect(fromGlobal != nil)
    }

    @Test("プリセットに戻す: ページだけ置き換え、id と使い方は保つ")
    func resetToPreset() throws {
        var configuration = ModelFixtures.configuration()
        let xcodeID = configuration.profiles[2].id
        configuration.updateProfile(id: xcodeID) { $0.mode = .off }
        let preset = try #require(PresetLibrary.preset(forBundleID: ModelFixtures.xcode.bundleID))
        configuration.resetProfile(id: xcodeID, to: preset)
        let profile = try #require(configuration.profile(id: xcodeID))
        #expect(profile.mode == .off)
        #expect(profile.pages.map { $0.cells.map { $0?.title } } == preset.pages.map { $0.cells.map { $0?.title } })
        #expect(configuration.profiles[2].id == xcodeID)
    }

    @Test("消したプロファイルを元の位置に戻す。同じアプリがもうあれば戻さない")
    func restoreProfile() throws {
        var configuration = ModelFixtures.configuration()
        let safari = configuration.profiles[1]
        configuration.removeProfile(id: safari.id)
        let restored = configuration.restoreAppProfile(safari, at: 0)
        #expect(restored)
        #expect(configuration.modelAppProfiles.map(\.id) == [safari.id, configuration.profiles[2].id])
        #expect(configuration.profile(id: safari.id) == safari)

        configuration.removeProfile(id: safari.id)
        configuration.addAppProfile(for: ModelFixtures.safari, preset: nil)
        let duplicate = configuration.restoreAppProfile(safari, at: 0)
        let global = configuration.globalProfile
        let restoredGlobal = configuration.restoreAppProfile(global, at: 0)
        #expect(!duplicate)
        #expect(!restoredGlobal)
    }

    @Test("消したページを元の位置に戻す。3ページなら戻さない")
    func insertPage() throws {
        var configuration = ModelFixtures.configuration()
        let xcodeID = configuration.profiles[2].id
        let removed = try #require(configuration.profile(id: xcodeID)?.pages[0])
        configuration.removePage(at: 0, profileID: xcodeID)
        let inserted = configuration.insertPage(removed, at: 0, profileID: xcodeID)
        #expect(inserted)
        #expect(configuration.profile(id: xcodeID)?.pages.first == removed)
        configuration.addPage(profileID: xcodeID)
        let full = configuration.insertPage(.empty, at: 0, profileID: xcodeID)
        let unknown = configuration.insertPage(.empty, at: 0, profileID: UUID())
        #expect(!full)
        #expect(!unknown)
    }
}
