// 担当: core-model。NonetConfiguration の編集 API と、その不変条件
import Foundation
@testable import NonetCore
import Testing

@Suite("設定の編集: プロファイル")
struct ConfigurationProfileEditingTests {
    @Test("globalProfile は先頭のグローバル。無いときも同じ値を返す")
    func globalProfile() {
        let configuration = ModelFixtures.configuration()
        #expect(configuration.globalProfile == configuration.profiles[0])

        let empty = NonetConfiguration(profiles: [])
        #expect(empty.globalProfile.isGlobal)
        #expect(empty.globalProfile == empty.globalProfile)
    }

    @Test("id でプロファイルを引く")
    func profileByID() {
        let configuration = ModelFixtures.configuration()
        for profile in configuration.profiles {
            #expect(configuration.profile(id: profile.id) == profile)
        }
        #expect(configuration.profile(id: UUID()) == nil)
    }

    @Test("appProfile は有効なものだけ。bundleID の大文字と小文字は区別しない")
    func appProfileLookup() {
        var configuration = ModelFixtures.configuration()
        #expect(configuration.appProfile(forBundleID: "com.apple.Safari")?.app == ModelFixtures.safari)
        #expect(configuration.appProfile(forBundleID: "COM.APPLE.SAFARI")?.app == ModelFixtures.safari)
        #expect(configuration.appProfile(forBundleID: "com.apple.Notes") == nil)
        #expect(configuration.appProfile(forBundleID: "") == nil)

        let safariID = configuration.profiles[1].id
        configuration.updateProfile(id: safariID) { $0.isEnabled = false }
        #expect(configuration.appProfile(forBundleID: "com.apple.Safari") == nil)
    }

    @Test("アプリのプロファイルを加える。preset があればその中身で、マスの id は新しい")
    func addAppProfileWithPreset() throws {
        var configuration = ModelFixtures.configuration()
        let presetPage = ModelFixtures.page(["共有", nil, "検索"])
        let preset = AppPreset(app: ModelFixtures.figma, category: "デザイン", summary: "", pages: [presetPage, ModelFixtures.page(["2"])])
        let id = configuration.addAppProfile(for: ModelFixtures.figma, preset: preset)

        let profile = try #require(configuration.profile(id: id))
        #expect(configuration.profiles.last?.id == id)
        #expect(profile.kind == .app(ModelFixtures.figma))
        #expect(profile.isEnabled)
        #expect(profile.modelTitles == [presetPage.cells.map { $0?.title }, ModelFixtures.page(["2"]).cells.map { $0?.title }])
        let presetIDs = Set(preset.pages.flatMap { $0.cells.compactMap { $0?.id } })
        let profileIDs = Set(profile.pages.flatMap { $0.cells.compactMap { $0?.id } })
        #expect(profileIDs.isDisjoint(with: presetIDs))
        #expect(Set(configuration.modelCellIDs).count == configuration.modelCellIDs.count)
    }

    @Test("preset が無ければ空のページ1枚")
    func addAppProfileWithoutPreset() throws {
        var configuration = ModelFixtures.configuration()
        let id = configuration.addAppProfile(for: ModelFixtures.slack, preset: nil)
        let profile = try #require(configuration.profile(id: id))
        #expect(profile.pages == [.empty])
    }

    @Test("すでにあれば何もせず、そのプロファイルの id を返す（無効でも、大文字と小文字が違っても）")
    func addExistingAppProfile() {
        var configuration = ModelFixtures.configuration()
        let safariID = configuration.profiles[1].id
        configuration.updateProfile(id: safariID) { $0.isEnabled = false }
        let before = configuration

        let id = configuration.addAppProfile(for: AppReference(bundleID: "com.apple.safari", name: "safari"), preset: nil)
        #expect(id == safariID)
        #expect(configuration == before)
    }

    @Test("プロファイルを消す。グローバルと知らない id は何もしない")
    func removeProfile() {
        var configuration = ModelFixtures.configuration()
        let before = configuration
        configuration.removeProfile(id: configuration.globalProfile.id)
        #expect(configuration == before)
        configuration.removeProfile(id: UUID())
        #expect(configuration == before)

        configuration.removeProfile(id: before.profiles[1].id)
        #expect(configuration.profiles.map(\.id) == [before.profiles[0].id, before.profiles[2].id])
    }

    @Test("アプリのプロファイルの並べ替え", arguments: [
        // (動かす位置, 移動先, 結果の並び) アプリのプロファイル A B C D の並びで
        ([0], 2, "BACD"),
        ([0], 4, "BCDA"),
        ([3], 0, "DABC"),
        ([1, 2], 0, "BCAD"),
        ([0, 2], 4, "BDAC"),
        ([0, 3], 2, "BADC"),
        ([1], 1, "ABCD"),
        ([1], 2, "ABCD"),
        ([2], 99, "ABDC"),
        ([2], -5, "CABD"),
        ([9], 0, "ABCD"),
        ([], 0, "ABCD"),
    ])
    func moveAppProfiles(_ offsets: [Int], _ destination: Int, _ expected: String) {
        let apps = ["A", "B", "C", "D"].map { name in
            ModelFixtures.profile(AppReference(bundleID: "app.\(name)", name: name))
        }
        var configuration = NonetConfiguration(profiles: [ModelFixtures.globalProfile()] + apps)
        configuration.moveAppProfiles(fromOffsets: IndexSet(offsets), toOffset: destination)
        #expect(configuration.profiles.first?.isGlobal == true)
        #expect(configuration.modelAppProfiles.map(\.name).joined() == expected)
    }

    @Test("並べ替えてもグローバルは先頭に残る（グローバルが先頭でなかったときも）")
    func moveKeepsGlobalFirst() {
        let a = ModelFixtures.profile(AppReference(bundleID: "app.A", name: "A"))
        let b = ModelFixtures.profile(AppReference(bundleID: "app.B", name: "B"))
        var configuration = NonetConfiguration(profiles: [a, ModelFixtures.globalProfile(), b])
        configuration.moveAppProfiles(fromOffsets: [1], toOffset: 0)
        #expect(configuration.profiles.map(\.name) == ["グローバル", "B", "A"])
    }

    @Test("updateProfile で中身を書き換える")
    func updateProfile() throws {
        var configuration = ModelFixtures.configuration()
        let safariID = configuration.profiles[1].id
        configuration.updateProfile(id: safariID) { profile in
            profile.isEnabled = false
            profile.pages.append(ModelFixtures.page(["新しい"]))
            profile.kind = .app(AppReference(bundleID: "com.apple.Safari", name: "Safari（改名）"))
        }
        let updated = try #require(configuration.profile(id: safariID))
        #expect(!updated.isEnabled)
        #expect(updated.pages.count == 2)
        #expect(updated.name == "Safari（改名）")
        #expect(configuration.profiles[1].id == safariID)
    }

    @Test("updateProfile: id・グローバルかどうか・ほかと重なる bundleID・空の bundleID への変更は元に戻す")
    func updateProfileGuards() throws {
        var configuration = ModelFixtures.configuration()
        let globalID = configuration.profiles[0].id
        let safariID = configuration.profiles[1].id

        configuration.updateProfile(id: safariID) { $0.id = UUID() }
        #expect(configuration.profile(id: safariID) != nil)

        configuration.updateProfile(id: globalID) { $0.kind = .app(ModelFixtures.figma) }
        #expect(configuration.profile(id: globalID)?.isGlobal == true)

        configuration.updateProfile(id: safariID) { $0.kind = .global }
        #expect(configuration.profile(id: safariID)?.app == ModelFixtures.safari)

        configuration.updateProfile(id: safariID) { $0.kind = .app(AppReference(bundleID: "COM.apple.dt.xcode", name: "X")) }
        #expect(configuration.profile(id: safariID)?.app == ModelFixtures.safari)

        configuration.updateProfile(id: safariID) { $0.kind = .app(AppReference(bundleID: "  ", name: "X")) }
        #expect(configuration.profile(id: safariID)?.app == ModelFixtures.safari)

        configuration.updateProfile(id: safariID) { $0.kind = .app(ModelFixtures.figma) }
        #expect(configuration.profile(id: safariID)?.app == ModelFixtures.figma)
        #expect(configuration.profiles.count == 3)
    }

    @Test("updateProfile: グローバルは無効にできない")
    func updateProfileKeepsGlobalEnabled() {
        var configuration = ModelFixtures.configuration()
        configuration.updateProfile(id: configuration.globalProfile.id) { $0.isEnabled = false }
        #expect(configuration.globalProfile.isEnabled)
    }

    @Test("updateProfile: ページ数とマス数を揃え、複製したマスの id を振り直す")
    func updateProfileRepairs() throws {
        var configuration = ModelFixtures.configuration()
        let xcodeID = configuration.profiles[2].id
        configuration.updateProfile(id: xcodeID) { profile in
            profile.pages += [.empty, .empty, .empty]
            profile.pages[0].cells = [profile.pages[0].cells[0], profile.pages[0].cells[0]]
        }
        let profile = try #require(configuration.profile(id: xcodeID))
        #expect(profile.pages.count == Profile.maxPages)
        #expect(profile.pages.allSatisfy { $0.cells.count == Page.cellCount })
        let first = try #require(profile.pages[0].cells[0])
        let copy = try #require(profile.pages[0].cells[1])
        #expect(first.title == copy.title)
        #expect(first.id != copy.id)

        configuration.updateProfile(id: xcodeID) { $0.pages = [] }
        #expect(configuration.profile(id: xcodeID)?.pages == [.empty])
    }

    @Test("updateProfile: 知らない id は何もしない")
    func updateUnknownProfile() {
        var configuration = ModelFixtures.configuration()
        let before = configuration
        configuration.updateProfile(id: UUID()) { $0.isEnabled = false }
        #expect(configuration == before)
    }
}

@Suite("設定の編集: マスとページ")
struct ConfigurationCellEditingTests {
    @Test("マスを置く・空にする")
    func setCell() throws {
        var configuration = ModelFixtures.configuration()
        let safariID = configuration.profiles[1].id
        let cell = ModelFixtures.cell("新しい")
        configuration.setCell(cell, at: CellAddress(page: 0, index: 8), profileID: safariID)
        #expect(configuration.profile(id: safariID)?.pages[0].cells[8] == cell)

        configuration.setCell(nil, at: CellAddress(page: 0, index: 8), profileID: safariID)
        #expect(configuration.profile(id: safariID)?.pages[0].cells[8] == nil)
    }

    @Test("同じ場所のマスを書き換えるときは id を保つ")
    func setCellKeepsIDInPlace() throws {
        var configuration = ModelFixtures.configuration()
        let safariID = configuration.profiles[1].id
        var cell = try #require(configuration.profiles[1].pages[0].cells[0])
        cell.title = "改名"
        configuration.setCell(cell, at: CellAddress(page: 0, index: 0), profileID: safariID)
        #expect(configuration.profile(id: safariID)?.pages[0].cells[0] == cell)
    }

    @Test("ほかの場所と同じ id のマス（複製）は新しい id にする")
    func setCellDuplicatesGetNewID() throws {
        var configuration = ModelFixtures.configuration()
        let safariID = configuration.profiles[1].id
        let globalCell = try #require(configuration.profiles[0].pages[0].cells[0])
        configuration.setCell(globalCell, at: CellAddress(page: 0, index: 4), profileID: safariID)
        let copy = try #require(configuration.profile(id: safariID)?.pages[0].cells[4])
        #expect(copy.title == globalCell.title)
        #expect(copy.action == globalCell.action)
        #expect(copy.id != globalCell.id)
        #expect(Set(configuration.modelCellIDs).count == configuration.modelCellIDs.count)
    }

    @Test("範囲外の位置・知らないプロファイルには置かない", arguments: [
        CellAddress(page: 1, index: 0),
        CellAddress(page: -1, index: 0),
        CellAddress(page: 0, index: 9),
        CellAddress(page: 0, index: -1),
    ])
    func setCellOutOfRange(_ address: CellAddress) {
        var configuration = ModelFixtures.configuration()
        let before = configuration
        configuration.setCell(ModelFixtures.cell("x"), at: address, profileID: before.profiles[1].id)
        #expect(configuration == before)
        configuration.setCell(ModelFixtures.cell("x"), at: CellAddress(page: 0, index: 0), profileID: UUID())
        #expect(configuration == before)
    }

    @Test("マス数が狂ったページでも9マスに直してから置く")
    func setCellOnBrokenPage() throws {
        var configuration = ModelFixtures.configuration()
        configuration.profiles[1].pages[0].cells = []
        let safariID = configuration.profiles[1].id
        configuration.setCell(ModelFixtures.cell("x"), at: CellAddress(page: 0, index: 7), profileID: safariID)
        let cells = try #require(configuration.profile(id: safariID)?.pages[0].cells)
        #expect(cells.count == 9)
        #expect(cells[7]?.title == "x")
    }

    @Test("2つのマスを入れ替える。ページをまたいでも、片方が空きなら移動になる")
    func swapCells() throws {
        var configuration = ModelFixtures.configuration()
        let xcodeID = configuration.profiles[2].id
        // Xcode: 1ページ目 [Xcode-0, nil...]、2ページ目 [Xcode-1, nil, Xcode-1b, nil...]
        configuration.swapCells(CellAddress(page: 0, index: 0), CellAddress(page: 1, index: 2), profileID: xcodeID)
        var titles = try #require(configuration.profile(id: xcodeID)?.modelTitles)
        #expect(titles[0][0] == "Xcode-1b")
        #expect(titles[1][2] == "Xcode-0")

        configuration.swapCells(CellAddress(page: 1, index: 0), CellAddress(page: 1, index: 8), profileID: xcodeID)
        titles = try #require(configuration.profile(id: xcodeID)?.modelTitles)
        #expect(titles[1][0] == nil)
        #expect(titles[1][8] == "Xcode-1")
    }

    @Test("範囲外・同じ位置・知らないプロファイルの入れ替えは何もしない")
    func swapCellsInvalid() {
        var configuration = ModelFixtures.configuration()
        let before = configuration
        let xcodeID = before.profiles[2].id
        configuration.swapCells(CellAddress(page: 0, index: 0), CellAddress(page: 2, index: 0), profileID: xcodeID)
        configuration.swapCells(CellAddress(page: 0, index: 9), CellAddress(page: 0, index: 0), profileID: xcodeID)
        configuration.swapCells(CellAddress(page: 0, index: 0), CellAddress(page: 0, index: 0), profileID: xcodeID)
        configuration.swapCells(CellAddress(page: 0, index: 0), CellAddress(page: 0, index: 1), profileID: UUID())
        #expect(configuration == before)
    }

    @Test("ページを加える。上限なら nil")
    func addPage() {
        var configuration = ModelFixtures.configuration()
        let safariID = configuration.profiles[1].id
        #expect(configuration.addPage(profileID: safariID) == 1)
        #expect(configuration.addPage(profileID: safariID) == 2)
        #expect(configuration.addPage(profileID: safariID) == nil)
        #expect(configuration.profile(id: safariID)?.pages.count == Profile.maxPages)
        #expect(configuration.profile(id: safariID)?.pages[2] == .empty)
        #expect(configuration.addPage(profileID: UUID()) == nil)
    }

    @Test("ページを消す。最後の1ページと範囲外は消さない")
    func removePage() throws {
        var configuration = ModelFixtures.configuration()
        let xcodeID = configuration.profiles[2].id
        configuration.removePage(at: 5, profileID: xcodeID)
        configuration.removePage(at: -1, profileID: xcodeID)
        #expect(configuration.profile(id: xcodeID)?.pages.count == 2)

        configuration.removePage(at: 0, profileID: xcodeID)
        let titles = try #require(configuration.profile(id: xcodeID)?.modelTitles)
        #expect(titles.count == 1)
        #expect(titles[0][0] == "Xcode-1")

        configuration.removePage(at: 0, profileID: xcodeID)
        #expect(configuration.profile(id: xcodeID)?.pages.count == 1)
    }
}

@Suite("初回の設定")
struct ConfigurationInitialTests {
    @Test("グローバルは渡したランチャー、アプリのプロファイルはプリセットから作る")
    func initialConfiguration() throws {
        let launcher = Profile(kind: .global, pages: [ModelFixtures.page(["Safari", "Mail"])])
        let presets = [
            AppPreset(app: ModelFixtures.xcode, category: "開発", summary: "", pages: [ModelFixtures.page(["ビルド", "テスト"])]),
            AppPreset(app: ModelFixtures.figma, category: "デザイン", summary: "", pages: [ModelFixtures.page(["共有"]), ModelFixtures.page(["2"])]),
            // 同じアプリのプリセットが2つあっても、プロファイルは1つ
            AppPreset(app: ModelFixtures.xcode, category: "開発", summary: "", pages: [ModelFixtures.page(["別"])]),
        ]
        let configuration = NonetConfiguration.initial(trigger: .rightOption, appPresets: presets, globalProfile: launcher)

        #expect(configuration.version == NonetConfiguration.currentVersion)
        #expect(configuration.settings == GlobalSettings(trigger: .rightOption))
        #expect(configuration.profiles.map(\.name) == ["グローバル", "Xcode", "Figma"])
        #expect(configuration.globalProfile.modelTitles == launcher.modelTitles)
        #expect(configuration.profiles[1].modelTitles[0][0...1] == ["ビルド", "テスト"])
        #expect(configuration.profiles[2].pages.count == 2)
        #expect(Set(configuration.modelCellIDs).count == configuration.modelCellIDs.count)
        #expect(configuration == configuration.validated())
    }

    @Test("グローバルとして渡したものがアプリのプロファイルでも、グローバルとして使う")
    func initialForcesGlobalKind() {
        let notGlobal = Profile(kind: .app(ModelFixtures.safari), pages: [ModelFixtures.page(["a"])])
        let configuration = NonetConfiguration.initial(trigger: .rightCommand, appPresets: [], globalProfile: notGlobal)
        #expect(configuration.profiles.count == 1)
        #expect(configuration.globalProfile.isGlobal)
        #expect(configuration.globalProfile.modelTitles == notGlobal.modelTitles)
    }
}

@Suite("プロファイルの読み込み（設定への反映）")
struct ConfigurationImportTests {
    @Test("同じアプリは置き換え（位置と id は保つ）、無ければ後ろに加える")
    func importAppProfiles() throws {
        var configuration = ModelFixtures.configuration()
        let safariID = configuration.profiles[1].id
        let importedSafari = ModelFixtures.profile(ModelFixtures.safari, pageCount: 3, isEnabled: false, prefix: "読み込んだ")
        let importedFigma = ModelFixtures.profile(ModelFixtures.figma)

        let result = configuration.importProfiles([importedSafari, importedFigma])

        #expect(result == NonetConfiguration.ImportResult(added: 1, replaced: 1, replacedGlobal: false, skipped: 0))
        #expect(result.appliedCount == 2)
        #expect(configuration.profiles.map(\.name) == ["グローバル", "Safari", "Xcode", "Figma"])
        let safari = try #require(configuration.profile(id: safariID))
        #expect(safari.modelTitles == importedSafari.modelTitles)
        #expect(!safari.isEnabled)
        #expect(configuration.profiles[3].modelTitles == importedFigma.modelTitles)
    }

    @Test("グローバルはページだけ置き換える（id は保つ）")
    func importGlobal() {
        var configuration = ModelFixtures.configuration()
        let globalID = configuration.globalProfile.id
        let imported = ModelFixtures.globalProfile(pageCount: 3)
        let result = configuration.importProfiles([imported])
        #expect(result == NonetConfiguration.ImportResult(replacedGlobal: true))
        #expect(result.appliedCount == 1)
        #expect(configuration.globalProfile.id == globalID)
        #expect(configuration.globalProfile.modelTitles == imported.modelTitles)
    }

    @Test("2つ目以降のグローバル・同じアプリ・bundleID の無いアプリは使わない")
    func importSkipsDuplicates() {
        var configuration = ModelFixtures.configuration()
        let result = configuration.importProfiles([
            ModelFixtures.globalProfile(),
            ModelFixtures.globalProfile(pageCount: 2),
            ModelFixtures.profile(ModelFixtures.figma),
            ModelFixtures.profile(AppReference(bundleID: "COM.FIGMA.DESKTOP", name: "Figma 2")),
            ModelFixtures.profile(AppReference(bundleID: "", name: "名無し")),
        ])
        #expect(result == NonetConfiguration.ImportResult(added: 1, replaced: 0, replacedGlobal: true, skipped: 3))
        #expect(configuration.globalProfile.pages.count == 1)
        #expect(configuration.modelAppProfiles.map(\.name) == ["Safari", "Xcode", "Figma"])
    }

    @Test("既存のマスやプロファイルと id が重なっても、すべての id は重ならない")
    func importKeepsIDsUnique() {
        var configuration = ModelFixtures.configuration()
        // 書き出した設定をそのまま読み込み直したような場合
        let copyOfXcode = configuration.profiles[2]
        var figma = ModelFixtures.profile(ModelFixtures.figma)
        figma.id = configuration.profiles[1].id
        figma.pages = configuration.profiles[1].pages
        configuration.importProfiles([copyOfXcode, figma])

        #expect(Set(configuration.modelCellIDs).count == configuration.modelCellIDs.count)
        #expect(Set(configuration.profiles.map(\.id)).count == configuration.profiles.count)
        #expect(configuration.profiles.count == 4)
    }

    @Test("グローバルが無い設定に読み込んでも、グローバルが先頭にできる")
    func importIntoConfigurationWithoutGlobal() {
        var configuration = NonetConfiguration(profiles: [ModelFixtures.profile(ModelFixtures.safari)])
        configuration.importProfiles([ModelFixtures.globalProfile(pageCount: 2)])
        #expect(configuration.profiles.first?.isGlobal == true)
        #expect(configuration.globalProfile.pages.count == 2)
        #expect(configuration.profiles.count == 2)
    }

    @Test("書き出しファイルから読めたものを加えると、読めなかったプロファイルも skipped に数える")
    func importDocumentCountsUnreadable() {
        var configuration = ModelFixtures.configuration()
        let document = ConfigurationStore.ImportedProfiles(
            profiles: [ModelFixtures.profile(ModelFixtures.figma), ModelFixtures.profile(ModelFixtures.figma, prefix: "2つ目")],
            unreadableCount: 2
        )
        #expect(configuration.importProfiles(document) == NonetConfiguration.ImportResult(added: 1, skipped: 3))
        #expect(configuration.modelAppProfiles.map(\.name) == ["Safari", "Xcode", "Figma"])

        // 何も読めなかったときは数えるだけ
        let before = configuration
        let empty = ConfigurationStore.ImportedProfiles(profiles: [], unreadableCount: 1)
        #expect(configuration.importProfiles(empty) == NonetConfiguration.ImportResult(skipped: 1))
        #expect(configuration == before)
    }

    @Test("空の読み込みは何も変えない")
    func importNothing() {
        var configuration = ModelFixtures.configuration()
        let before = configuration
        #expect(configuration.importProfiles([]) == NonetConfiguration.ImportResult())
        #expect(configuration == before)
    }
}
