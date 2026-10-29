// 担当: presets
import Foundation
import Testing
@testable import NonetCore

/// グローバル（ランチャー）の候補と makeGlobalProfile
@Suite struct PresetLauncherTests {
    static let candidates = PresetLibrary.launcherCandidates
    static let capacity = Page.cellCount * Profile.maxPages

    /// 新しい版があると並ばない候補（ChatGPT Classic）を除いた候補。新旧の両方が入っていても、並ぶのはこの順
    static let primaryEntries = PresetData.launcherEntries.filter { $0.supersededBy == nil }
    static let primaryCandidates = primaryEntries.map(\.app)

    static let chatGPT = "com.openai.codex"
    static let chatGPTClassic = "com.openai.chat"

    /// 担当の指示にあった候補（Arc は提供終了のため Dia に置き換えた）
    static let requiredBundleIDs = [
        "com.apple.mail", "com.apple.iCal", "com.apple.Notes", "com.apple.Safari", "com.google.Chrome",
        "com.anthropic.claudefordesktop", "com.openai.codex", "com.openai.chat", "com.tinyspeck.slackmacgap", "notion.id",
        "com.figma.Desktop", "com.apple.Terminal", "com.apple.finder", "com.apple.MobileSMS", "com.apple.Music",
        "com.apple.dt.Xcode", "com.microsoft.VSCode", "us.zoom.xos", "com.microsoft.teams2",
        "com.apple.reminders", "com.apple.Photos", "com.apple.systempreferences", "com.spotify.client",
        "jp.naver.line.mac", "com.hnc.Discord", "md.obsidian", "company.thebrowser.dia",
    ]

    /// 優先順で先頭から count 個のアプリが入っている Mac
    static func bundleIDs(_ count: Int) -> Set<String> {
        Set(primaryCandidates.prefix(count).map(\.bundleID))
    }

    static func filledCells(_ profile: Profile) -> [Cell] {
        profile.pages.flatMap(\.cells).compactMap { $0 }
    }

    // MARK: - 候補

    @Test func candidatesAreUniqueAndNamed() {
        let lowercased = Self.candidates.map { $0.bundleID.lowercased() }
        #expect(Set(lowercased).count == lowercased.count)
        for app in Self.candidates {
            #expect(!app.bundleID.isEmpty)
            #expect(!app.name.isEmpty)
            #expect(!app.bundleID.contains(" "))
        }
    }

    @Test func candidatesFillThreePages() {
        // 新旧の両方が入っていても3ページ埋まる
        #expect(Self.primaryCandidates.count >= Self.capacity)
        #expect(Self.candidates.count <= 40)
    }

    @Test func candidatesIncludeRequestedAppsInPriorityOrder() throws {
        let ids = Self.candidates.map(\.bundleID)
        for required in Self.requiredBundleIDs {
            #expect(ids.contains(required), "候補にない: \(required)")
        }
        // よく使うものが先頭（メール・カレンダー・メモ）
        #expect(Array(ids.prefix(3)) == ["com.apple.mail", "com.apple.iCal", "com.apple.Notes"])
        let safari = try #require(ids.firstIndex(of: "com.apple.Safari"))
        let systemSettings = try #require(ids.firstIndex(of: "com.apple.systempreferences"))
        #expect(safari < systemSettings)
    }

    @Test func arcIsReplacedByDia() {
        // Arc は 2026年12月22日に動かなくなる
        let ids = Self.candidates.map(\.bundleID)
        #expect(!ids.contains("company.thebrowser.Browser"))
        #expect(ids.contains("company.thebrowser.dia"))
    }

    @Test func candidateTitlesFitInHUDCell() {
        for entry in PresetData.launcherEntries {
            #expect(!entry.title.isEmpty)
            #expect(PresetTestSupport.displayWidth(entry.title) <= PresetTestSupport.maxTitleWidth, "長すぎる: \(entry.title)")
        }
    }

    @Test func candidatesMatchEntries() {
        #expect(Self.candidates == PresetData.launcherEntries.map(\.app))
    }

    // MARK: - makeGlobalProfile

    @Test func noInstalledAppsGivesOneEmptyPage() {
        let profile = PresetLibrary.makeGlobalProfile(installedBundleIDs: [])
        #expect(profile.kind == .global)
        #expect(profile.isEnabled)
        #expect(profile.pages.count == 1)
        #expect(profile.pages[0].cells.count == Page.cellCount)
        #expect(profile.pages[0].cells.allSatisfy { $0 == nil })
    }

    @Test func unknownAppsAreIgnored() {
        let profile = PresetLibrary.makeGlobalProfile(installedBundleIDs: ["com.example.a", "com.example.b", ""])
        #expect(profile.pages.count == 1)
        #expect(Self.filledCells(profile).isEmpty)
    }

    @Test func fiveInstalledAppsFillTheFirstCells() {
        let profile = PresetLibrary.makeGlobalProfile(installedBundleIDs: Self.bundleIDs(5))
        #expect(profile.pages.count == 1)
        let cells = profile.pages[0].cells
        #expect(cells.prefix(5).allSatisfy { $0 != nil })
        #expect(cells.suffix(4).allSatisfy { $0 == nil })
        #expect(cells.prefix(5).compactMap { $0?.icon } == Self.primaryCandidates.prefix(5).map { .app(bundleID: $0.bundleID) })
    }

    @Test func nineInstalledAppsFillOnePage() {
        let profile = PresetLibrary.makeGlobalProfile(installedBundleIDs: Self.bundleIDs(9))
        #expect(profile.pages.count == 1)
        #expect(profile.pages[0].cells.allSatisfy { $0 != nil })
    }

    @Test func twentyInstalledAppsUseThreePages() {
        let profile = PresetLibrary.makeGlobalProfile(installedBundleIDs: Self.bundleIDs(20))
        #expect(profile.pages.count == 3)
        #expect(profile.pages[0].cells.allSatisfy { $0 != nil })
        #expect(profile.pages[1].cells.allSatisfy { $0 != nil })
        #expect(profile.pages[2].cells.prefix(2).allSatisfy { $0 != nil })
        #expect(profile.pages[2].cells.suffix(7).allSatisfy { $0 == nil })
        #expect(Self.filledCells(profile).map(\.icon) == Self.primaryCandidates.prefix(20).map { .app(bundleID: $0.bundleID) })
    }

    @Test func fortyInstalledAppsStopAtMaxPages() {
        // 候補すべて（ChatGPT の新旧の両方を含む）と、候補にないアプリを合わせて40個
        var installed = Set(Self.candidates.map(\.bundleID))
        var extra = 0
        while installed.count < 40 {
            installed.insert("com.example.extra\(extra)")
            extra += 1
        }
        let profile = PresetLibrary.makeGlobalProfile(installedBundleIDs: installed)
        #expect(profile.pages.count == Profile.maxPages)
        #expect(profile.pages.allSatisfy { $0.cells.allSatisfy { $0 != nil } })
        #expect(Self.filledCells(profile).map(\.icon) == Self.primaryCandidates.prefix(Self.capacity).map { .app(bundleID: $0.bundleID) })
    }

    @Test func orderFollowsPriorityNotInput() {
        // 優先順の低いものだけを渡しても、候補の順に詰める
        let lowPriority = Array(Self.primaryCandidates.suffix(6))
        let profile = PresetLibrary.makeGlobalProfile(installedBundleIDs: Set(lowPriority.map(\.bundleID)))
        #expect(Self.filledCells(profile).map(\.icon) == lowPriority.map { .app(bundleID: $0.bundleID) })
    }

    @Test func bundleIDsMatchIgnoringCase() {
        let installed = Set(Self.primaryCandidates.prefix(3).map { $0.bundleID.uppercased() })
        let profile = PresetLibrary.makeGlobalProfile(installedBundleIDs: installed)
        // 中のアクションとアイコンは候補の正しい表記のまま
        #expect(Self.filledCells(profile).map(\.icon) == Self.primaryCandidates.prefix(3).map { .app(bundleID: $0.bundleID) })
    }

    @Test func cellsLaunchTheirApps() throws {
        let profile = PresetLibrary.makeGlobalProfile(installedBundleIDs: Self.bundleIDs(Self.capacity))
        let entries = Self.primaryEntries.prefix(Self.capacity)
        let cells = Self.filledCells(profile)
        #expect(cells.count == entries.count)
        for (cell, entry) in zip(cells, entries) {
            #expect(cell.title == entry.title)
            #expect(cell.icon == .app(bundleID: entry.app.bundleID))
            #expect(cell.action == .launchApp(LaunchAppAction(app: entry.app)))
        }
        #expect(Set(cells.map(\.id)).count == cells.count)
    }

    @Test func shortTitlesForLongProductNames() throws {
        let vsCode = try #require(PresetData.launcherEntries.first { $0.app.bundleID == "com.microsoft.VSCode" })
        #expect(vsCode.title == "VS Code")
        #expect(vsCode.app.name == "Visual Studio Code")
        let safari = try #require(PresetData.launcherEntries.first { $0.app.bundleID == "com.apple.Safari" })
        #expect(safari.title == safari.app.name)
    }

    @Test func eachCallMakesNewIDs() {
        let installed = Self.bundleIDs(9)
        let first = PresetLibrary.makeGlobalProfile(installedBundleIDs: installed)
        let second = PresetLibrary.makeGlobalProfile(installedBundleIDs: installed)
        #expect(first.id != second.id)
        #expect(Set(Self.filledCells(first).map(\.id)).isDisjoint(with: Self.filledCells(second).map(\.id)))
    }

    // MARK: - ChatGPT と ChatGPT Classic

    static func chatGPTCells(_ profile: Profile) -> [Cell] {
        filledCells(profile).filter {
            guard case .launchApp(let launch) = $0.action else { return false }
            return [chatGPT, chatGPTClassic].contains(launch.app.bundleID)
        }
    }

    @Test func classicOnlyGetsAChatGPTCell() throws {
        // 新しい ChatGPT を入れていない Mac でも ChatGPT のマスが出る
        let profile = PresetLibrary.makeGlobalProfile(
            installedBundleIDs: ["com.anthropic.claudefordesktop", Self.chatGPTClassic, "com.tinyspeck.slackmacgap"]
        )
        let cells = Self.filledCells(profile)
        #expect(cells.map(\.icon) == [
            .app(bundleID: "com.anthropic.claudefordesktop"),
            .app(bundleID: Self.chatGPTClassic),
            .app(bundleID: "com.tinyspeck.slackmacgap"),
        ])
        let classic = try #require(Self.chatGPTCells(profile).first)
        #expect(classic.title == "ChatGPT")
        #expect(classic.action == .launchApp(LaunchAppAction(app: KnownApp.chatGPTClassic)))
    }

    @Test func newChatGPTOnlyGetsAChatGPTCell() throws {
        let profile = PresetLibrary.makeGlobalProfile(installedBundleIDs: [Self.chatGPT])
        let cell = try #require(Self.chatGPTCells(profile).first)
        #expect(Self.filledCells(profile).count == 1)
        #expect(cell.title == "ChatGPT")
        #expect(cell.action == .launchApp(LaunchAppAction(app: KnownApp.chatGPT)))
    }

    @Test(arguments: [false, true])
    func bothChatGPTAppsGiveOneCellForTheNewApp(uppercased: Bool) throws {
        // 両方入っていれば新しい方だけ。bundleID の大文字・小文字は区別しない
        let ids = ["com.anthropic.claudefordesktop", Self.chatGPT, Self.chatGPTClassic, "com.tinyspeck.slackmacgap"]
        let profile = PresetLibrary.makeGlobalProfile(installedBundleIDs: Set(ids.map { uppercased ? $0.uppercased() : $0 }))
        let chatGPTCells = Self.chatGPTCells(profile)
        #expect(chatGPTCells.count == 1)
        let cell = try #require(chatGPTCells.first)
        #expect(cell.action == .launchApp(LaunchAppAction(app: KnownApp.chatGPT)))
        #expect(Self.filledCells(profile).map(\.icon) == [
            .app(bundleID: "com.anthropic.claudefordesktop"),
            .app(bundleID: Self.chatGPT),
            .app(bundleID: "com.tinyspeck.slackmacgap"),
        ])
    }

    @Test func classicTakesTheSamePlaceAsTheNewApp() {
        // 9個入っている Mac で、ChatGPT が新旧のどちらでも同じ位置に同じ数だけ並ぶ
        let withNew = Self.bundleIDs(9)
        #expect(withNew.contains(Self.chatGPT))
        var withClassic = withNew
        withClassic.remove(Self.chatGPT)
        withClassic.insert(Self.chatGPTClassic)

        let newCells = Self.filledCells(PresetLibrary.makeGlobalProfile(installedBundleIDs: withNew))
        let classicCells = Self.filledCells(PresetLibrary.makeGlobalProfile(installedBundleIDs: withClassic))
        #expect(newCells.count == 9)
        #expect(classicCells.count == 9)
        #expect(newCells.map(\.title) == classicCells.map(\.title))
        #expect(newCells.firstIndex { $0.icon == .app(bundleID: Self.chatGPT) }
            == classicCells.firstIndex { $0.icon == .app(bundleID: Self.chatGPTClassic) })
    }

    @Test func supersedingAppsAreEarlierPrimaryCandidates() throws {
        // 置き換える側は候補の中で前にあり、それ自身は置き換えられない（置き換え先が無いと二度と並ばなくなる）
        let entries = PresetData.launcherEntries
        let superseded = entries.filter { $0.supersededBy != nil }
        #expect(superseded.map(\.app.bundleID) == [Self.chatGPTClassic])
        for entry in superseded {
            let newer = try #require(entry.supersededBy)
            let newerIndex = try #require(entries.firstIndex { $0.app.bundleID == newer }, "置き換える側が候補にない: \(newer)")
            let index = try #require(entries.firstIndex { $0.app.bundleID == entry.app.bundleID })
            #expect(newerIndex < index)
            #expect(entries[newerIndex].supersededBy == nil)
            #expect(newer.caseInsensitiveCompare(entry.app.bundleID) != .orderedSame)
        }
    }

    @Test func installedLauncherEntriesKeepPriorityOrder() {
        let installed: Set<String> = [Self.chatGPTClassic, "com.apple.mail", "com.example.unknown", "COM.APPLE.SAFARI"]
        let entries = PresetData.installedLauncherEntries(installed)
        #expect(entries.map(\.app.bundleID) == ["com.apple.mail", "com.apple.Safari", Self.chatGPTClassic])
        #expect(PresetData.installedLauncherEntries([]).isEmpty)
    }
}
