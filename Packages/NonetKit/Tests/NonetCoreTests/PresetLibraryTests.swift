// 担当: presets
import AppKit
import Foundation
import Testing
@testable import NonetCore

/// アプリ別プリセットの中身を確かめる（AI も Claude Code も使える Mac のもの。使えない Mac は PresetCapabilitiesTests）。
/// KeySequence.displayString などほかの担当の未実装部分は呼ばない
@Suite struct PresetLibraryTests {
    static let bundleIDs = PresetLibrary.apps.map(\.app.bundleID)

    /// 依頼されたアプリ（docs/feature-plan.md と担当の指示）
    static let requiredBundleIDs: Set<String> = [
        "com.apple.dt.Xcode", "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "com.figma.Desktop",
        "us.zoom.xos", "com.tinyspeck.slackmacgap", "com.microsoft.teams2", "com.apple.Safari",
        "com.google.Chrome", "company.thebrowser.Browser", "com.apple.finder", "notion.id",
        "com.apple.Terminal", "com.apple.mail", "com.apple.Notes",
    ]

    /// 中央が AI（選択中のテキストを扱う）のアプリ
    static let aiCenterBundleIDs: Set<String> = [
        "com.apple.Safari", "com.google.Chrome", "company.thebrowser.Browser", "com.apple.mail",
        "com.apple.Notes", "com.tinyspeck.slackmacgap", "notion.id", "com.microsoft.teams2",
    ]

    /// Claude Code が外側のマスにある開発アプリ。中央はそのアプリでいちばん使うキー
    static let claudeCodeBundleIDs: Set<String> = [
        "com.apple.dt.Xcode", "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "com.apple.Terminal",
    ]

    /// 選択範囲を置き換えてよいアプリ（自分で書いた文章を選ぶ場所）。それ以外は結果を表示するだけ
    static let replaceSelectionBundleIDs: Set<String> = ["com.apple.Notes", "notion.id"]

    /// ⌘⌃⌥ なしで送るキー。Figma のキャンバス用ショートカットは既定が ⇧ だけ
    static let shiftOnlyExceptions: Set<String> = [
        "com.figma.Desktop:a",
        "com.figma.Desktop:1",
    ]

    /// US でも JIS でも修飾キーなしで入力できる文字。.character はこの範囲でないと JIS で送れない
    static let layoutIndependentCharacters = Set("abcdefghijklmnopqrstuvwxyz0123456789-,./;[]")

    static func preset(_ bundleID: String) throws -> AppPreset {
        try #require(PresetLibrary.apps.first { $0.app.bundleID == bundleID })
    }

    static func cells(of preset: AppPreset) -> [Cell] {
        preset.pages.flatMap(\.cells).compactMap { $0 }
    }

    // MARK: - 一覧

    @Test func coversRequiredApps() {
        let ids = Set(Self.bundleIDs)
        for required in Self.requiredBundleIDs.sorted() {
            #expect(ids.contains(required), "プリセットがない: \(required)")
        }
    }

    @Test func bundleIDsAreUnique() {
        let lowercased = Self.bundleIDs.map { $0.lowercased() }
        #expect(Set(lowercased).count == lowercased.count)
        #expect(Set(PresetLibrary.apps.map(\.id)).count == PresetLibrary.apps.count)
    }

    @Test func idIsBundleID() {
        for preset in PresetLibrary.apps {
            #expect(preset.id == preset.app.bundleID)
        }
    }

    @Test func lookupByBundleID() throws {
        for bundleID in Self.bundleIDs {
            let found = try #require(PresetLibrary.preset(forBundleID: bundleID))
            #expect(found.app.bundleID == bundleID)
        }
    }

    @Test func lookupIgnoresCase() throws {
        let found = try #require(PresetLibrary.preset(forBundleID: "COM.APPLE.SAFARI"))
        #expect(found.app.bundleID == "com.apple.Safari")
    }

    @Test func lookupUnknownReturnsNil() {
        #expect(PresetLibrary.preset(forBundleID: "com.example.unknown") == nil)
        #expect(PresetLibrary.preset(forBundleID: "") == nil)
        // 前方一致では見つけない
        #expect(PresetLibrary.preset(forBundleID: "com.apple") == nil)
    }

    // MARK: - 形

    @Test(arguments: bundleIDs)
    func pagesHaveNineFilledCells(bundleID: String) throws {
        let preset = try Self.preset(bundleID)
        #expect((1...Profile.maxPages).contains(preset.pages.count))
        for page in preset.pages {
            #expect(page.cells.count == Page.cellCount)
            #expect(page.cells.allSatisfy { $0 != nil }, "空きマスがある")
        }
    }

    @Test(arguments: bundleIDs)
    func appCategoryAndSummaryAreFilled(bundleID: String) throws {
        let preset = try Self.preset(bundleID)
        #expect(!preset.app.name.isEmpty)
        #expect(!preset.category.isEmpty)
        #expect(!preset.summary.isEmpty)
        // 説明の「など9個」は実際のマスの数と合っている
        #expect(preset.summary.contains("\(Self.cells(of: preset).count)"))
    }

    @Test(arguments: bundleIDs)
    func titlesFitInHUDCell(bundleID: String) throws {
        let preset = try Self.preset(bundleID)
        for page in preset.pages {
            let titles = page.cells.compactMap { $0?.title }
            #expect(Set(titles).count == titles.count, "同じページに同じ名前がある: \(titles)")
            for title in titles {
                #expect(!title.trimmingCharacters(in: .whitespaces).isEmpty)
                #expect(PresetTestSupport.displayWidth(title) <= PresetTestSupport.maxTitleWidth, "長すぎる: \(title)")
            }
        }
    }

    @Test func displayWidthCountsFullWidthAsTwo() {
        #expect(PresetTestSupport.displayWidth("Claude Code") == 11)
        #expect(PresetTestSupport.displayWidth("コンポーネント化") == 16)
        #expect(PresetTestSupport.displayWidth("PNGでコピー") == 11)
    }

    @Test(arguments: bundleIDs)
    func actionsAreNotDuplicated(bundleID: String) throws {
        let actions = Self.cells(of: try Self.preset(bundleID)).map(\.action)
        for (index, action) in actions.enumerated() {
            #expect(!actions[(index + 1)...].contains(action), "同じアクションが2つある: \(action)")
        }
    }

    @Test(arguments: bundleIDs)
    func cellIDsAreUnique(bundleID: String) throws {
        let ids = Self.cells(of: try Self.preset(bundleID)).map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    // MARK: - アイコン

    @Test(arguments: bundleIDs)
    func iconsAreExistingSymbols(bundleID: String) throws {
        for cell in Self.cells(of: try Self.preset(bundleID)) {
            guard case .symbol(let name) = cell.icon else {
                Issue.record("SF Symbols ではないアイコン: \(cell.title)")
                continue
            }
            #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "無い記号: \(name)")
        }
    }

    /// SF Symbols の記号ごとの初出の OS を見て、macOS 14 で使えるものだけか確かめる
    @Test(.enabled(if: FileManager.default.fileExists(atPath: PresetSymbolAvailability.path)))
    func iconsExistOnMacOS14() throws {
        let availability = try PresetSymbolAvailability()
        for preset in PresetLibrary.apps {
            for cell in Self.cells(of: preset) {
                guard case .symbol(let name) = cell.icon else { continue }
                let version = try #require(availability.macOSVersion(of: name), "記号の情報が無い: \(name)")
                #expect(version.lexicographicallyPrecedes([14, 0, 1]), "\(name) は macOS \(version) から")
            }
        }
    }

    // MARK: - アクション

    @Test(arguments: bundleIDs)
    func keystrokesAreSendableOnUSAndJIS(bundleID: String) throws {
        for cell in Self.cells(of: try Self.preset(bundleID)) {
            guard case .keystroke(let sequence) = cell.action else { continue }
            #expect((1...3).contains(sequence.chords.count), "\(cell.title)")
            for chord in sequence.chords {
                switch chord.key {
                case .character(let text):
                    #expect(text.count == 1, "\(cell.title): \(text)")
                    #expect(text.allSatisfy { Self.layoutIndependentCharacters.contains($0) }, "\(cell.title): \(text)")
                case .special:
                    break
                case .keyCode:
                    Issue.record("プリセットでは仮想キーコードを使わない: \(cell.title)")
                }
            }
        }
    }

    /// 修飾キーなしの文字は入力欄に文字として入ってしまうので、⌘⌃⌥ か fn キーのどちらかを必ず付ける
    @Test(arguments: bundleIDs)
    func keystrokesHaveCommandLikeModifierOrFunctionKey(bundleID: String) throws {
        let commandLike: ModifierSet = [.command, .control, .option]
        for cell in Self.cells(of: try Self.preset(bundleID)) {
            guard case .keystroke(let sequence) = cell.action else { continue }
            for chord in sequence.chords where chord.modifiers.isDisjoint(with: commandLike) {
                switch chord.key {
                case .special(let key):
                    // F1〜F20 だけ。Return・Space・矢印などは入力欄でそのまま効いてしまう
                    #expect(key.rawValue.range(of: #"^f\d+$"#, options: .regularExpression) != nil, "\(cell.title): \(key)")
                case .character(let text):
                    #expect(chord.modifiers == .shift, "\(cell.title)")
                    #expect(Self.shiftOnlyExceptions.contains("\(bundleID):\(text)"), "修飾キーが ⇧ だけ: \(cell.title)")
                case .keyCode:
                    Issue.record("プリセットでは仮想キーコードを使わない: \(cell.title)")
                }
            }
        }
    }

    @Test func shiftOnlyExceptionsAreActuallyUsed() throws {
        let figma = try Self.preset("com.figma.Desktop")
        let used = Self.cells(of: figma).compactMap { cell -> String? in
            guard case .keystroke(let sequence) = cell.action,
                  let chord = sequence.chords.first, chord.modifiers == .shift,
                  case .character(let text) = chord.key else { return nil }
            return "com.figma.Desktop:\(text)"
        }
        #expect(Set(used) == Self.shiftOnlyExceptions)
    }

    /// ショートカット.app のショートカットはユーザーが作らないと存在しないので、プリセットには入れない
    @Test(arguments: bundleIDs)
    func noUserDefinedShortcuts(bundleID: String) throws {
        for cell in Self.cells(of: try Self.preset(bundleID)) {
            #expect(cell.action.kind != .shortcut, "\(cell.title)")
        }
    }

    @Test(arguments: bundleIDs)
    func launchAndScriptActionsAreValid(bundleID: String) throws {
        let preset = try Self.preset(bundleID)
        for cell in Self.cells(of: preset) {
            switch cell.action {
            case .launchApp(let launch):
                #expect(!launch.app.bundleID.isEmpty)
                #expect(!launch.app.name.isEmpty)
                #expect(launch.app.bundleID != preset.app.bundleID, "自分自身を起動しても意味がない")
            case .script(let script):
                #expect(!script.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                #expect(script.timeout > 0)
            case .menuItem(let item):
                #expect(!item.path.isEmpty)
            case .openURL(let url):
                #expect(!url.url.isEmpty)
            case .ai(let ai):
                #expect(!ai.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            case .file(let file):
                // 移動は先のフォルダを決める必要があるので、プリセットには入れない
                #expect(file.operation != .move)
            case .keystroke, .shortcut:
                break
            }
        }
    }

    // MARK: - 中央のマス

    @Test(arguments: bundleIDs)
    func centerCellMatchesAppKind(bundleID: String) throws {
        let preset = try Self.preset(bundleID)
        let center = try #require(preset.pages[0].cells[4], "中央が空")
        if Self.aiCenterBundleIDs.contains(bundleID) {
            guard case .ai(let ai) = center.action else {
                Issue.record("中央が AI ではない: \(center.title)")
                return
            }
            #expect(!ai.prompt.isEmpty)
            #expect((ai.output == .replaceSelection) == Self.replaceSelectionBundleIDs.contains(bundleID))
        } else {
            // 開発アプリ（押し間違えるとターミナルが開く Claude Code は外側）と、
            // Figma・Zoom・Finder（選択中のテキストが無い）は、そのアプリでいちばん使う操作
            #expect(center.action.kind == .keystroke, "\(center.title)")
        }
    }

    /// Claude Code は、プロジェクトのフォルダでターミナルを開く外側のマス
    @Test(arguments: claudeCodeBundleIDs.sorted())
    func claudeCodeIsAnOuterTerminalCell(bundleID: String) throws {
        let preset = try Self.preset(bundleID)
        let index = try #require(preset.pages[0].cells.firstIndex { cell in
            guard case .script(let script)? = cell?.action else { return false }
            return script.runMode == .terminal
        }, "Claude Code が無い")
        #expect(index != PresetBuilder.centerIndex)
        guard case .script(let script)? = preset.pages[0].cells[index]?.action else { return }
        #expect(script.source.contains("claude"))
        #expect(script.source.contains("PROJECT_DIR"))
    }

    @Test func noPresetPutsATerminalWindowInTheCenter() {
        for capabilities in PresetCapabilities.allCombinations {
            for preset in PresetLibrary.apps(for: capabilities) {
                guard case .script(let script)? = preset.pages[0].cells[PresetBuilder.centerIndex]?.action else { continue }
                #expect(script.runMode != .terminal, "\(preset.app.bundleID)")
            }
        }
    }

    @Test func everyAppHasAKnownCenterKind() {
        let classified = Self.aiCenterBundleIDs.union(Self.claudeCodeBundleIDs)
            .union(["com.figma.Desktop", "us.zoom.xos", "com.apple.finder"])
        for bundleID in Self.bundleIDs {
            #expect(classified.contains(bundleID), "中央の種類が決まっていない: \(bundleID)")
        }
    }

    @Test func aiPromptsDifferByTask() throws {
        let prompts = PresetLibrary.apps.compactMap { preset -> String? in
            guard case .ai(let ai) = preset.pages[0].cells[4]?.action else { return nil }
            return ai.prompt
        }
        // 要約・翻訳・校正の3種類をアプリに合わせて使い分けている
        #expect(Set(prompts).count == 3)
    }

    // MARK: - 個別の確認（モックからの変更点）
    // 名前はローカライズで変わるので、アクションで探す

    static func actions(of bundleID: String) throws -> [Action] {
        cells(of: try preset(bundleID)).map(\.action)
    }

    @Test func xcodeHasBuildTestAndCommit() throws {
        let actions = try Self.actions(of: "com.apple.dt.Xcode")
        #expect(actions.contains(.keystroke(.key("b", .command))))
        #expect(actions.contains(.keystroke(.key("u", .command))))
        // モックのとおり ⌥⌘C（Integrate > Commit…）
        #expect(actions.contains(.keystroke(.key("c", [.option, .command]))))
    }

    @Test func xcodeCentersOpenQuicklyInsteadOfLaunchingTerminal() throws {
        let xcode = try Self.preset("com.apple.dt.Xcode")
        // Open Quickly… は ⇧⌘O。ターミナルの起動はグローバルのランチャーにあるので入れない
        #expect(xcode.pages[0].cells[PresetBuilder.centerIndex]?.action == .keystroke(.key("o", [.shift, .command])))
        #expect(!Self.cells(of: xcode).contains { $0.action.kind == .launchApp })
    }

    @Test func slackJumpsToAConversationInsteadOfSettingStatus() throws {
        let actions = try Self.actions(of: "com.tinyspeck.slackmacgap")
        // Slack のヘルプ「Navigate Slack with your keyboard」の ⌘K（Mac）
        #expect(actions.contains(.keystroke(.key("k", .command))))
        #expect(!actions.contains(.keystroke(.key("y", [.shift, .command]))))
    }

    @Test func browsersFindOnPageInsteadOfReadingListOrBookmark() throws {
        let find = Action.keystroke(.key("f", .command))
        let safari = try Self.actions(of: "com.apple.Safari")
        #expect(safari.contains(find))
        #expect(!safari.contains(.keystroke(.key("d", [.shift, .command]))))
        let chrome = try Self.actions(of: "com.google.Chrome")
        #expect(chrome.contains(find))
        #expect(!chrome.contains(.keystroke(.key("d", .command))))
    }

    @Test func xcodeSimulatorOpensDeviceHubOrSimulator() throws {
        let scripts = try Self.actions(of: "com.apple.dt.Xcode").compactMap { action -> ScriptAction? in
            guard case .script(let script) = action, script.runMode == .background else { return nil }
            return script
        }
        let simulator = try #require(scripts.first)
        #expect(scripts.count == 1)
        // Xcode 27 は Device Hub、それより前は Simulator.app
        #expect(simulator.source.contains("open -b com.apple.dt.Devices"))
        #expect(simulator.source.contains("|| open -b com.apple.iphonesimulator"))
    }

    @Test func zoomHasNoLeaveShortcut() throws {
        let zoom = try Self.preset("us.zoom.xos")
        // macOS の Zoom で ⌘W は「ウインドウを閉じる」。退出の割り当ては公式の一覧に無い
        #expect(!Self.cells(of: zoom).contains { $0.action == .keystroke(.key("w", .command)) })
        let center = try #require(zoom.pages[0].cells[4])
        #expect(center.action == .keystroke(.key("a", [.shift, .command])))
    }

    @Test func figmaDropsLayoutDependentShowHideUI() throws {
        let figma = try Self.preset("com.figma.Desktop")
        // ⌘\ は日本語配列で ⌘゛に変わるので入れない
        for cell in Self.cells(of: figma) {
            guard case .keystroke(let sequence) = cell.action else { continue }
            #expect(!sequence.chords.contains { $0.key == .character("\\") })
        }
    }

    @Test func cursorNeverSendsLineCommentKey() throws {
        let actions = try Self.actions(of: "com.todesktop.230313mzl4w4u92")
        // Cursor の ⌘/ と ⌥⌘/ がモデルを切り替えるのはチャットの入力欄にフォーカスがあるときだけ。
        // エディタにフォーカスがあると ⌘/ は Toggle Line Comment になり、ユーザーのコードをコメントアウトしてしまう
        for action in actions {
            guard case .keystroke(let sequence) = action else { continue }
            #expect(!sequence.chords.contains { $0.key == .character("/") }, "\(action)")
        }
        #expect(!actions.contains(.keystroke(.key("/", .command))))
        // 代わりにフォーカスに関係なく効くサイドバーの切り替え
        #expect(actions.contains(.keystroke(.key("b", .command))))
    }

    /// 会議や通話を始める・抜ける・終えるキー。押し間違えると取り返しがつかないので、どのプリセットにも入れない
    static let callTogglingKeys: [(bundleID: String, keys: KeySequence, reason: String)] = [
        ("com.tinyspeck.slackmacgap", .key("h", [.shift, .command]), "ハドルの開始・参加・退出・終了"),
        ("com.microsoft.teams2", .key("h", [.shift, .command]), "通話の終了"),
        ("us.zoom.xos", .key("w", .command), "モックの「退出」。macOS では会議のウインドウを閉じる操作になる"),
    ]

    @Test func noCallTogglingKeys() throws {
        for (bundleID, keys, reason) in Self.callTogglingKeys {
            #expect(try !Self.actions(of: bundleID).contains(.keystroke(keys)), "\(bundleID): \(reason)")
        }
    }

    @Test func slackReplacesHuddleWithNextUnread() throws {
        let actions = try Self.actions(of: "com.tinyspeck.slackmacgap")
        // Mac の一覧の「次の未読チャンネルや DM に移動する」（⌥⇧↓）
        #expect(actions.contains(.keystroke(.special(.downArrow, [.option, .shift]))))
        let slack = try Self.preset("com.tinyspeck.slackmacgap")
        #expect(!slack.summary.contains("ハドル"))
    }

    @Test func browsersCopyLink() throws {
        let addressBarCopy = Action.keystroke(.sequence(.key("l", .command), .key("c", .command)))
        #expect(try Self.actions(of: "com.apple.Safari").contains(addressBarCopy))
        #expect(try Self.actions(of: "com.google.Chrome").contains(addressBarCopy))
        // Arc には URL をコピーする ⇧⌘C がある
        #expect(try Self.actions(of: "company.thebrowser.Browser").contains(.keystroke(.key("c", [.shift, .command]))))
    }

    @Test func safariMatchesMock() throws {
        let actions = try Self.actions(of: "com.apple.Safari")
        // モックの「あとで読む」⇧⌘D はページ内検索 ⌘F に替えた
        let expected: [KeySequence] = [
            .key("t", .command), .key("w", .command), .key("r", .command), .key("[", .command),
            .key("]", .command), .key("f", .command), .key("t", [.shift, .command]),
        ]
        for keys in expected {
            #expect(actions.contains(.keystroke(keys)))
        }
    }

    // MARK: - makeProfile

    @Test(arguments: bundleIDs)
    func makeProfileCopiesCellsWithNewIDs(bundleID: String) throws {
        let preset = try Self.preset(bundleID)
        let first = preset.makeProfile()
        let second = preset.makeProfile()

        #expect(first.kind == .app(preset.app))
        #expect(first.isEnabled)
        #expect(first.id != second.id)
        #expect(first.pages.count == preset.pages.count)

        let originalIDs = Set(Self.cells(of: preset).map(\.id))
        let firstIDs = Set(first.pages.flatMap(\.cells).compactMap { $0?.id })
        let secondIDs = Set(second.pages.flatMap(\.cells).compactMap { $0?.id })
        #expect(firstIDs.count == originalIDs.count)
        #expect(firstIDs.isDisjoint(with: originalIDs))
        #expect(firstIDs.isDisjoint(with: secondIDs))

        for (made, original) in zip(first.pages, preset.pages) {
            for (madeCell, originalCell) in zip(made.cells, original.cells) {
                #expect(madeCell?.title == originalCell?.title)
                #expect(madeCell?.icon == originalCell?.icon)
                #expect(madeCell?.action == originalCell?.action)
                #expect(madeCell?.requiresHold == originalCell?.requiresHold)
            }
        }
    }

    @Test func makeProfileKeepsEmptyCellsAndPages() {
        let cell = Cell(title: "A", icon: .text("A"), action: .openURL(URLAction(url: "example.com")))
        let preset = AppPreset(
            app: AppReference(bundleID: "com.example.app", name: "Example"),
            category: "c",
            summary: "s",
            pages: [Page(cells: [nil, cell]), .empty]
        )
        let profile = preset.makeProfile()
        #expect(profile.pages.count == 2)
        #expect(profile.pages[0].cells[0] == nil)
        #expect(profile.pages[0].cells[1]?.title == "A")
        #expect(profile.pages[0].cells[1]?.id != cell.id)
        #expect(profile.pages[1].cells.allSatisfy { $0 == nil })
    }
}

/// プリセットのテストで共有する道具。同じテストターゲットのほかの担当と名前がぶつからないようにまとめる
enum PresetTestSupport {
    /// HUD のマスに入る幅（全角8文字）
    static let maxTitleWidth = 16

    /// 全角は2、半角は1として数えた幅
    static func displayWidth(_ text: String) -> Int {
        text.reduce(0) { width, character in
            width + (character.unicodeScalars.allSatisfy(\.isASCII) ? 1 : 2)
        }
    }
}

/// SF Symbols の記号が使えるようになった OS の一覧（システムの CoreGlyphs にある）
struct PresetSymbolAvailability {
    static let path = "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/name_availability.plist"

    private let symbols: [String: String]
    private let releases: [String: [String: String]]

    init() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: Self.path))
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        symbols = try #require(plist["symbols"] as? [String: String])
        releases = try #require(plist["year_to_release"] as? [String: [String: String]])
    }

    /// [14, 0] のような macOS のバージョン
    func macOSVersion(of symbol: String) -> [Int]? {
        guard let year = symbols[symbol], let version = releases[year]?["macOS"] else { return nil }
        return version.split(separator: ".").compactMap { Int($0) }
    }
}
