// 担当: presets
import Foundation
import Testing
@testable import NonetCore

/// この Mac でできること（AI・Claude Code）に合わせたプリセット
@Suite struct PresetCapabilitiesTests {
    static let noAI = PresetCapabilities(appleIntelligence: false, claudeCode: true)
    static let noClaude = PresetCapabilities(appleIntelligence: true, claudeCode: false)
    static let center = PresetBuilder.centerIndex

    /// AI を使えない Mac で中央に移すマス（どれも同じプリセットの外側にあったもの）
    static let aiFallbacks: [(bundleID: String, center: KeySequence)] = [
        ("com.apple.Safari", .key("f", .command)),
        ("com.google.Chrome", .key("f", .command)),
        ("company.thebrowser.Browser", .key("f", .command)),
        ("com.apple.mail", .key("a", [.control, .command])),
        ("com.microsoft.teams2", .key("m", [.shift, .command])),
        ("com.tinyspeck.slackmacgap", .key("k", .command)),
        ("notion.id", .key("p", .command)),
        ("com.apple.Notes", .key("l", [.shift, .command])),
        ("com.microsoft.Outlook", .key("e", .control)),
        ("com.microsoft.Word", .key("h", .control)),
        ("com.apple.iWork.Pages", .key("w", [.shift, .command])),
        ("md.obsidian", .key("o", .command)),
    ]

    /// Claude Code が無くても変わらない中央
    static let developmentCenters: [(bundleID: String, center: KeySequence)] = [
        ("com.apple.dt.Xcode", .key("o", [.shift, .command])),
        ("com.microsoft.VSCode", .key("p", [.shift, .command])),
        ("com.todesktop.230313mzl4w4u92", .key("p", [.shift, .command])),
        ("com.apple.Terminal", .key("t", .command)),
    ]

    static func preset(_ bundleID: String, _ capabilities: PresetCapabilities) throws -> AppPreset {
        try #require(PresetLibrary.preset(forBundleID: bundleID, capabilities: capabilities))
    }

    static func filled(_ preset: AppPreset) -> [Cell] {
        preset.pages.flatMap(\.cells).compactMap { $0 }
    }

    static func usesTerminal(_ cell: Cell) -> Bool {
        guard case .script(let script) = cell.action else { return false }
        return script.runMode == .terminal
    }

    // MARK: - 形

    @Test(arguments: PresetCapabilities.allCombinations)
    func sameAppsInTheSameOrder(capabilities: PresetCapabilities) {
        #expect(PresetLibrary.apps(for: capabilities).map(\.app) == PresetLibrary.apps.map(\.app))
    }

    @Test func defaultListIsTheFullOne() {
        // 引数の無い apps は AI も Claude Code も使える Mac のもの（設定の往復の確かめなど）
        let full = PresetLibrary.apps(for: .all)
        #expect(PresetLibrary.apps.map { Self.filled($0).map(\.action) } == full.map { Self.filled($0).map(\.action) })
        #expect(PresetLibrary.preset(forBundleID: "com.apple.Safari")?.summary == full.first { $0.app.bundleID == "com.apple.Safari" }?.summary)
    }

    @Test(arguments: PresetCapabilities.allCombinations)
    func centerIsNeverEmptyAndPagesKeepNineSlots(capabilities: PresetCapabilities) {
        for preset in PresetLibrary.apps(for: capabilities) {
            #expect(preset.pages.allSatisfy { $0.cells.count == Page.cellCount })
            #expect(preset.pages[0].cells[Self.center] != nil, "\(preset.app.bundleID) の中央が空")
        }
    }

    @Test(arguments: PresetCapabilities.allCombinations)
    func unavailableActionsAreLeftOut(capabilities: PresetCapabilities) {
        for preset in PresetLibrary.apps(for: capabilities) {
            for cell in Self.filled(preset) {
                if !capabilities.appleIntelligence {
                    #expect(cell.action.kind != .ai, "\(preset.app.bundleID): \(cell.title)")
                }
                if !capabilities.claudeCode {
                    #expect(!Self.usesTerminal(cell), "\(preset.app.bundleID): \(cell.title)")
                }
            }
        }
    }

    /// 使えない Mac のプリセットは、全部入りのマスを動かしたか除いたか、AI の代わりに空いた位置へ1つ足しただけ
    /// （キーの決まりは PresetLibraryTests で確かめている）
    @Test(arguments: PresetCapabilities.allCombinations)
    func reducedPresetsOnlyMoveDropOrFillCells(capabilities: PresetCapabilities) throws {
        for preset in PresetLibrary.apps(for: capabilities) {
            let full = try Self.preset(preset.app.bundleID, .all)
            let fullActions = Self.filled(full).map(\.action)
            let actions = Self.filled(preset).map(\.action)
            let aiCount = fullActions.filter { $0.kind == .ai }.count
            // AI のマスがあったプリセットだけ、AI を使えない Mac で1つ（空いた位置を埋めるマス）を足す
            let added = actions.filter { !fullActions.contains($0) }
            #expect(added.count == (capabilities.appleIntelligence ? 0 : aiCount), "\(preset.app.bundleID): \(added)")
            #expect(added.allSatisfy { $0.kind != .ai })
            #expect(Set(Self.filled(preset).map(\.title)).count == actions.count)
            let missing = (capabilities.appleIntelligence ? 0 : aiCount)
                + (capabilities.claudeCode ? 0 : Self.filled(full).filter(Self.usesTerminal).count)
            #expect(actions.count == fullActions.count - missing + added.count, "\(preset.app.bundleID)")
        }
    }

    // MARK: - AI を使えない Mac

    @Test(arguments: aiFallbacks.map(\.bundleID))
    func withoutAIOuterCellMovesToTheCenter(bundleID: String) throws {
        let expected = try #require(Self.aiFallbacks.first { $0.bundleID == bundleID }).center
        let full = try Self.preset(bundleID, .all).pages[0].cells
        let reduced = try Self.preset(bundleID, Self.noAI).pages[0].cells
        #expect(reduced[Self.center]?.action == .keystroke(expected))
        // 移したマスの元の位置には、AI を使える Mac には無い別のマスが入り（9マスのまま）、ほかのマスは同じ位置のまま
        let from = try #require(full.firstIndex { $0?.action == .keystroke(expected) })
        #expect(from != Self.center)
        let filler = try #require(reduced[from], "\(bundleID) の \(from) が空")
        #expect(filler.action.kind != .ai)
        let fullActions = full.compactMap { $0?.action }
        #expect(!fullActions.contains(filler.action), "\(bundleID): \(filler.title) は AI を使える Mac にもある")
        #expect(reduced.allSatisfy { $0 != nil }, "\(bundleID) に空きマスがある")
        for index in full.indices where index != from && index != Self.center {
            #expect(reduced[index]?.action == full[index]?.action, "\(bundleID) の \(index)")
        }
    }

    @Test(arguments: aiFallbacks.map(\.bundleID))
    func withAIOnlyTheCenterIsAI(bundleID: String) throws {
        let cells = try Self.preset(bundleID, .all).pages[0].cells
        #expect(cells[Self.center]?.action.kind == .ai)
        #expect(cells.compactMap { $0 }.filter { $0.action.kind == .ai }.count == 1)
    }

    // MARK: - Claude Code が無い Mac

    @Test(arguments: developmentCenters.map(\.bundleID))
    func developmentCenterDoesNotDependOnClaudeCode(bundleID: String) throws {
        let expected = try #require(Self.developmentCenters.first { $0.bundleID == bundleID }).center
        let full = try Self.preset(bundleID, .all).pages[0].cells
        let reduced = try Self.preset(bundleID, Self.noClaude).pages[0].cells
        #expect(full[Self.center]?.action == .keystroke(expected))
        #expect(reduced[Self.center]?.action == .keystroke(expected))
        // Claude Code のあった外側のマスだけが空く
        let claude = try #require(full.firstIndex { $0.map(Self.usesTerminal) ?? false })
        #expect(claude != Self.center)
        #expect(reduced[claude] == nil)
        for index in full.indices where index != claude {
            #expect(reduced[index]?.action == full[index]?.action, "\(bundleID) の \(index)")
        }
    }

    // MARK: - 説明（初回の案内のアプリのカード）

    @Test(arguments: PresetCapabilities.allCombinations)
    func summaryCountsTheFilledCells(capabilities: PresetCapabilities) {
        for preset in PresetLibrary.apps(for: capabilities) {
            #expect(preset.summary.contains("\(Self.filled(preset).count)"), "\(preset.app.bundleID): \(preset.summary)")
        }
    }

    @Test(arguments: PresetCapabilities.allCombinations)
    func summaryNamesOnlyButtonsThatAreThere(capabilities: PresetCapabilities) {
        let aiNames = ["要約", "翻訳", "校正"].map { ModelFixtures.text(String.LocalizationValue($0)) }
        for preset in PresetLibrary.apps(for: capabilities) {
            if !capabilities.appleIntelligence {
                for name in aiNames {
                    #expect(!preset.summary.contains(name), "\(preset.app.bundleID): \(preset.summary)")
                }
            }
            if !capabilities.claudeCode {
                #expect(!preset.summary.contains("Claude Code"), "\(preset.app.bundleID): \(preset.summary)")
            }
        }
    }

    @Test func summariesForTheFullPresetsAreUnchanged() throws {
        #expect(try Self.preset("com.apple.dt.Xcode", .all).summary == ModelFixtures.text("ビルド、テスト、Claude Code など\(9)個"))
        #expect(try Self.preset("com.apple.Safari", .all).summary == ModelFixtures.text("タブ、戻る・進む、要約など\(9)個"))
        #expect(try Self.preset("com.tinyspeck.slackmacgap", .all).summary == ModelFixtures.text("スレッド、翻訳、未読など\(9)個"))
    }

    @Test func summariesWithoutAI() throws {
        let expected: [(String, String.LocalizationValue)] = [
            // AI を使えない Mac でも、空いた位置に別のマスが入るので9個のまま
            ("com.apple.Safari", "タブ、戻る・進む、ページ内検索など\(9)個"),
            ("com.google.Chrome", "タブ、戻る・進む、ページ内検索など\(9)個"),
            ("company.thebrowser.Browser", "Little Arc、リンクをコピー、ページ内検索など\(9)個"),
            ("com.apple.mail", "返信、アーカイブ、転送など\(9)個"),
            ("com.microsoft.teams2", "ミュート、ビデオ、画面共有など\(9)個"),
            ("com.tinyspeck.slackmacgap", "スレッド、未読、会話へ移動など\(9)個"),
            ("notion.id", "新規ページ、検索、コメントなど\(9)個"),
            ("com.apple.Notes", "チェックリスト、表、見出しなど\(9)個"),
        ]
        for (bundleID, summary) in expected {
            #expect(try Self.preset(bundleID, .none).summary == ModelFixtures.text(summary), "\(bundleID)")
        }
    }

    @Test func summariesWithoutClaudeCode() throws {
        let expected: [(String, String.LocalizationValue)] = [
            ("com.apple.dt.Xcode", "ビルド、テスト、クイックオープンなど\(8)個"),
            ("com.microsoft.VSCode", "コマンド、検索、定義へ移動など\(8)個"),
            ("com.todesktop.230313mzl4w4u92", "AIチャット、エージェント、コマンドなど\(8)個"),
            ("com.apple.Terminal", "タブ、クリア、分割など\(8)個"),
        ]
        for (bundleID, summary) in expected {
            #expect(try Self.preset(bundleID, .none).summary == ModelFixtures.text(summary), "\(bundleID)")
        }
    }

    @Test func presetsWithoutOptionalActionsAreUnaffected() throws {
        // Figma・Zoom・Finder は AI も Claude Code も使わない
        for bundleID in ["com.figma.Desktop", "us.zoom.xos", "com.apple.finder"] {
            let full = try Self.preset(bundleID, .all)
            let reduced = try Self.preset(bundleID, .none)
            #expect(reduced.pages[0].cells.map { $0?.action } == full.pages[0].cells.map { $0?.action })
            #expect(reduced.summary == full.summary)
        }
    }

    @Test @MainActor func fixedEnvironmentReturnsWhatItWasGiven() async {
        let dock = [AppReference(bundleID: "com.apple.dt.Xcode", name: "Xcode")]
        let environment = FixedPresetEnvironment(capabilities: Self.noClaude, dockApps: dock)
        #expect(environment.capabilities == Self.noClaude)
        #expect(await environment.resolvedCapabilities() == Self.noClaude)
        #expect(environment.dockApps() == dock)
        // 既定は全部入り（今までのプリセットと同じ）
        #expect(FixedPresetEnvironment().capabilities == .all)
        #expect(FixedPresetEnvironment().dockApps().isEmpty)
    }

    // MARK: - プロファイルにする

    @Test func profileFromAReducedPresetStaysFull() throws {
        let preset = try Self.preset("com.apple.Safari", .none)
        let profile = preset.makeProfile()
        #expect(profile.pages[0].cells.count == Page.cellCount)
        #expect(profile.pages[0].cells.compactMap { $0 }.count == 9)
        #expect(profile.pages[0].cells[Self.center]?.action == .keystroke(.key("f", .command)))
    }

    @Test func configurationKeepsTheEmptySlotOfAReducedPreset() throws {
        var configuration = NonetConfiguration(profiles: [Profile(kind: .global)])
        let preset = try Self.preset("com.apple.dt.Xcode", .none)
        let id = configuration.addAppProfile(for: preset.app, preset: preset)
        let profile = try #require(configuration.validated().profile(id: id))
        #expect(profile.pages[0].cells.compactMap { $0 }.count == 8)
        #expect(!profile.pages[0].cells.compactMap { $0 }.contains(where: Self.usesTerminal))
    }
}
