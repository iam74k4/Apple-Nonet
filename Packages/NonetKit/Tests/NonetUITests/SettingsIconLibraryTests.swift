// 担当: ui-settings
import AppKit
import Foundation
import NonetCore
@testable import NonetUI
import Testing

@Suite @MainActor struct SettingsIconLibraryTests {
    /// 設定画面で使う SF Symbols のすべて（候補・種類の既定・画面の部品）
    private var symbolsInUse: [String] {
        SettingsIconLibrary.allSymbols
            + ActionKind.allCases.map(SettingsActionKinds.symbol)
            + WindowRegion.allCases.map(\.symbol)
            + MediaKey.allCases.map(\.symbol)
            + SettingsTab.allCases.map(\.symbol)
            + [
                "plus", "minus", "xmark", "questionmark.circle", "exclamationmark.triangle", "exclamationmark.shield",
                "checkmark.circle", "xmark.octagon", "play.fill", "record.circle", "keyboard", "delete.left",
                "app.dashed", "chevron.up.chevron.down", "list.bullet", "arrow.clockwise", "line.3.horizontal",
                "lock.shield", "hand.point.up.left", "lock", "pause.circle", "clock", "checkmark.seal", "key",
                "book", "hand.raised", "magnifyingglass", "filemenu.and.selection", "square.grid.3x3",
            ]
    }

    @Test func everySymbolExistsOnThisMac() {
        for symbol in symbolsInUse {
            #expect(SettingsIconLibrary.isAvailable(symbol), "\(symbol) が見つからない")
        }
    }

    /// macOS 14.0 で使えるか。システムの SF Symbols の一覧（初出の版）で確かめる
    @Test func everySymbolExistsOnMacOS14() throws {
        let url = URL(fileURLWithPath: "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/name_availability.plist")
        guard let data = try? Data(contentsOf: url),
              let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let symbols = plist["symbols"] as? [String: String],
              let releases = plist["year_to_release"] as? [String: [String: String]] else {
            // 一覧の無い macOS ではこのテストを飛ばす
            return
        }
        for symbol in Set(symbolsInUse) {
            let release = try #require(symbols[symbol].flatMap { releases[$0] }?["macOS"], "\(symbol) の初出が分からない")
            let parts = release.split(separator: ".").compactMap { Int($0) }
            let isOldEnough = parts.lexicographicallyPrecedes([14, 0, 1])
            #expect(isOldEnough, "\(symbol) は macOS \(release) から")
        }
    }

    @Test func groupsHaveNoDuplicatesAndAreNotEmpty() {
        for group in SettingsIconLibrary.groups {
            #expect(!group.symbols.isEmpty)
            #expect(Set(group.symbols).count == group.symbols.count, "\(group.name) に同じ記号がある")
        }
        #expect(SettingsIconLibrary.allSymbols.count == Set(SettingsIconLibrary.allSymbols).count)
    }

    @Test func filterMatchesAllWords() {
        let arrows = SettingsIconLibrary.filter("arrow")
        #expect(!arrows.isEmpty)
        #expect(arrows.allSatisfy { $0.symbols.allSatisfy { $0.contains("arrow") } })
        let both = SettingsIconLibrary.filter("arrow  down")
        #expect(both.flatMap(\.symbols).allSatisfy { $0.contains("arrow") && $0.contains("down") })
        #expect(SettingsIconLibrary.filter("").count == SettingsIconLibrary.groups.count)
        #expect(SettingsIconLibrary.filter("zzzz-none").isEmpty)
        #expect(!SettingsIconLibrary.filter("HAMMER").isEmpty)
    }

    @Test func suggestedAppForTheIcon() {
        let global = Profile(kind: .global)
        let xcode = Profile(kind: .app(SettingsFixtures.xcode))
        let launch = Action.launchApp(LaunchAppAction(app: SettingsFixtures.figma))
        #expect(SettingsIconLibrary.suggestedApp(for: launch, profile: xcode) == SettingsFixtures.figma.bundleID)
        #expect(SettingsIconLibrary.suggestedApp(for: .keystroke(.key("b", .command)), profile: xcode) == SettingsFixtures.xcode.bundleID)
        #expect(SettingsIconLibrary.suggestedApp(for: .keystroke(.key("b", .command)), profile: global) == nil)
        let menu = Action.menuItem(MenuItemAction(app: SettingsFixtures.notes, path: ["編集"]))
        #expect(SettingsIconLibrary.suggestedApp(for: menu, profile: global) == SettingsFixtures.notes.bundleID)
    }

    @Test func iconKindFollowsTheIcon() {
        #expect(SettingsIconLibrary.Kind(.symbol("star")) == .symbol)
        #expect(SettingsIconLibrary.Kind(.app(bundleID: "a")) == .app)
        // 前の版の「文字」のアイコンは、記号のタブで開く（新しくは作れない）
        #expect(SettingsIconLibrary.Kind(.text("AB")) == .symbol)
        #expect(SettingsIconLibrary.Kind.allCases == [.symbol, .app])
    }
}
