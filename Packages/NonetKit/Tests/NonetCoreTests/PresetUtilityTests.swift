// 担当: presets。グローバルの「ユーティリティ」のページと、「ページを追加」の型
import AppKit
import Foundation
import Testing
@testable import NonetCore

@Suite struct PresetUtilityTests {
    static var cells: [Cell] {
        PresetLibrary.makeUtilityPage().cells.compactMap { $0 }
    }

    static func cell(_ title: String.LocalizationValue) throws -> Cell {
        try #require(cells.first { $0.title == PresetBuilder.text(title) })
    }

    @Test func nineFilledCellsWithANameThatFitTheHUD() {
        let page = PresetLibrary.makeUtilityPage()
        #expect(page.name == PresetBuilder.text("ユーティリティ"))
        #expect(page.cells.count == Page.cellCount)
        #expect(page.cells.allSatisfy { $0 != nil }, "空きマスがある")
        let titles = Self.cells.map(\.title)
        #expect(Set(titles).count == titles.count)
        for title in titles {
            #expect(PresetTestSupport.displayWidth(title) <= PresetTestSupport.maxTitleWidth, "長すぎる: \(title)")
        }
        let actions = Self.cells.map(\.action)
        for (index, action) in actions.enumerated() {
            #expect(!actions[(index + 1)...].contains(action), "同じアクションが2つある: \(action)")
        }
    }

    /// 撮影と収録は上の段、中央は撮ってすぐ貼れる「撮影してコピー」
    @Test func capturesAreOnTopAndCaptureToCopyIsInTheCenter() {
        let actions = PresetLibrary.makeUtilityPage().cells.map { $0?.action }
        #expect(actions[0] == .keystroke(.key("4", [.shift, .command])))
        #expect(actions[1] == .keystroke(.key("5", [.shift, .command])))
        #expect(actions[2] == .keystroke(.special(.escape, [.control, .command])))
        #expect(actions[PresetBuilder.centerIndex] == .keystroke(.key("4", [.control, .shift, .command])))
    }

    /// 中の段の右は Spotlight。強制終了 ⌥⌘Esc は、アプリが送ったキーでは macOS が「アプリケーションの強制終了」を
    /// 開かないので置かない（PresetData+Utilities.swift の「入れないもの」）
    @Test func spotlightSitsWhereForceQuitWouldNotWork() throws {
        #expect(PresetLibrary.makeUtilityPage().cells[5]?.title == PresetBuilder.text("Spotlight"))
        #expect(try Self.cell("Spotlight").action == .keystroke(.special(.space, [.command])))
        #expect(!Self.cells.contains { $0.action == .keystroke(.special(.escape, [.option, .command])) })
    }

    /// プリセットのキーの決まり（US と JIS で送れる文字・⌘⌃⌥ を付ける）を守る
    @Test func keystrokesFollowThePresetRules() {
        let commandLike: ModifierSet = [.command, .control, .option]
        for cell in Self.cells {
            guard case .keystroke(let sequence) = cell.action else { continue }
            #expect(sequence.chords.count == 1, "\(cell.title)")
            for chord in sequence.chords {
                #expect(!chord.modifiers.isDisjoint(with: commandLike), "\(cell.title)")
                switch chord.key {
                case .character(let text):
                    #expect(text.allSatisfy { PresetLibraryTests.layoutIndependentCharacters.contains($0) }, "\(cell.title): \(text)")
                case .special:
                    break
                case .keyCode:
                    Issue.record("プリセットでは仮想キーコードを使わない: \(cell.title)")
                }
            }
        }
    }

    /// スクリプトは許可の要らないコマンドだけ。選択中のテキストとブラウザの URL を使わないので、
    /// 実行の前に ⌘C を送ることも、オートメーションの確認を出すことも無い（NonetPlatform の ContextNeeds.forScript）
    @Test func scriptsRunInTheBackgroundWithoutReadingTheFrontApp() throws {
        let scripts = Self.cells.compactMap { cell -> ScriptAction? in
            if case .script(let script) = cell.action { script } else { nil }
        }
        #expect(scripts.count == 2)
        for script in scripts {
            #expect(script.runMode == .background)
            // ScriptEnvironment.variables の名前（NonetPlatform の ScriptVariableName と同じ）
            #expect(!script.source.contains("NONET_SELECTED_TEXT"))
            #expect(!script.source.contains("NONET_BROWSER_URL"))
            // System Events や Finder に頼まない（オートメーションの許可が要る）
            #expect(!script.source.contains("tell application"))
        }
        #expect(try Self.cell("画面を消す").action == .script(ScriptAction(source: "pmset displaysleepnow")))
        #expect(try Self.cell("消音の切り替え").action == .script(ScriptAction(source: PresetData.muteToggleScript)))
    }

    /// 押し間違えるとパスワードを打ち直すことになる「画面をロック」だけ、少し長く止めてから実行する
    @Test func onlyLockingTheScreenNeedsAHold() throws {
        #expect(Self.cells.filter(\.requiresHold).map(\.title) == [PresetBuilder.text("画面をロック")])
        #expect(try Self.cell("画面をロック").action == .keystroke(.key("q", [.control, .command])))
    }

    @Test func iconsAreExistingSymbols() {
        for cell in Self.cells {
            guard case .symbol(let name) = cell.icon else {
                Issue.record("SF Symbols ではないアイコン: \(cell.title)")
                continue
            }
            #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "無い記号: \(name)")
        }
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: PresetSymbolAvailability.path)))
    func iconsExistOnMacOS14() throws {
        let availability = try PresetSymbolAvailability()
        for cell in Self.cells {
            guard case .symbol(let name) = cell.icon else { continue }
            let version = try #require(availability.macOSVersion(of: name), "記号の情報が無い: \(name)")
            #expect(version.lexicographicallyPrecedes([14, 0, 1]), "\(name) は macOS \(version) から")
        }
    }

    @Test func eachCallMakesNewIDs() {
        let first = Set(PresetLibrary.makeUtilityPage().cells.compactMap { $0?.id })
        let second = Set(PresetLibrary.makeUtilityPage().cells.compactMap { $0?.id })
        #expect(first.count == Page.cellCount)
        #expect(first.isDisjoint(with: second))
    }
}

@Suite struct PageTemplateTests {
    @Test func templatesMakeTheirPages() {
        #expect(PageTemplate.allCases == [.empty, .windowPlacement, .utilities])
        #expect(PageTemplate.empty.makePage() == .empty)
        #expect(PageTemplate.windowPlacement.makePage().cells.map { $0?.action } == PresetLibrary.makeWindowPlacementPage().cells.map { $0?.action })
        #expect(PageTemplate.utilities.makePage().cells.map { $0?.action } == PresetLibrary.makeUtilityPage().cells.map { $0?.action })
        // メニューの名前は、型のページの名前
        #expect(PageTemplate.empty.title == PresetBuilder.text("空のページ"))
        #expect(PageTemplate.windowPlacement.title == PresetBuilder.text("画面に置く"))
        #expect(PageTemplate.utilities.title == PresetBuilder.text("ユーティリティ"))
    }

    /// 型のページを足すと、名前ごと入る（下のページの手前）。上限なら足さない。
    /// 「ユーティリティ」は下のページとして作るが、グローバルにもう下のページがあれば、ふつうのページになる
    @Test func addingATemplatePageKeepsItsNameAndStopsAtTheLimit() throws {
        var configuration = NonetConfiguration.initial(appPresets: [], installedBundleIDs: [])
        let globalID = configuration.globalProfile.id
        #expect(configuration.globalProfile.pages.count == 2)
        let page = PageTemplate.utilities.makePage()
        #expect(page.isBelow)
        let added = configuration.addPage(page, profileID: globalID)
        // 下のページはいつも最後なので、その手前に入る
        #expect(added == 1)
        var ordinary = page
        ordinary.isBelow = false
        #expect(configuration.globalProfile.pages[1] == ordinary)
        #expect(configuration.globalProfile.pages.map(\.isBelow) == [false, false, true])
        let overLimit = configuration.addPage(profileID: globalID)
        #expect(overLimit == nil)
        #expect(configuration.globalProfile.pages.count == Profile.maxPages)
    }

    /// 同じマスの id がほかにあれば振り直す（同じページを2回足しても、マスの id が重ならない）
    @Test func addingAPageWithUsedCellIDsGivesNewIDs() throws {
        var configuration = NonetConfiguration.initial(appPresets: [], installedBundleIDs: [])
        let globalID = configuration.globalProfile.id
        let used = configuration.globalProfile.pages[1]
        let result = configuration.addPage(used, profileID: globalID)
        let added = try #require(result)
        let ids = configuration.globalProfile.pages.flatMap(\.cells).compactMap { $0?.id }
        #expect(Set(ids).count == ids.count)
        #expect(configuration.globalProfile.pages[added].cells.map { $0?.action } == used.cells.map { $0?.action })
    }
}
