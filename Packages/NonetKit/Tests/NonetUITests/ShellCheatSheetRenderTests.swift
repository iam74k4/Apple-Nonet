// 担当: ui-shell。見た目の確認用。NONET_RENDER_SHOTS=<フォルダ> のときだけ、メニューの早見表を PNG に書き出す（普段の swift test では動かない）
import AppKit
import Foundation
import NonetCore
@testable import NonetUI
import Testing

private let shotsDirectory = ProcessInfo.processInfo.environment["NONET_RENDER_SHOTS"]

@Suite("メニューの早見表の書き出し（NONET_RENDER_SHOTS）", .enabled(if: shotsDirectory != nil))
@MainActor
struct ShellCheatSheetRenderTests {
    /// 実際の初回の設定に近いもの（Xcode のプリセット、グローバルはランチャー、グローバルのページをつなげる）
    static func configuration() throws -> NonetConfiguration {
        let candidates = Set(PresetLibrary.launcherCandidates.map(\.bundleID))
        let xcode = try #require(PresetLibrary.preset(forBundleID: ShellFixtures.xcode))
        var configuration = NonetConfiguration.initial(appPresets: [xcode], installedBundleIDs: candidates)
        let id = try #require(configuration.appProfile(forBundleID: ShellFixtures.xcode)?.id)
        if (configuration.profile(id: id)?.pages.count ?? 0) < 2 {
            _ = configuration.addPage(profileID: id)
        }
        configuration.renamePage(at: 1, profileID: id, to: "デバッグ")
        return configuration
    }

    @Test("早見表")
    func cheatSheet() throws {
        let configuration = try Self.configuration()
        let xcode = AppReference(bundleID: ShellFixtures.xcode, name: "Xcode")
        let notes = AppReference(bundleID: "com.apple.Notes", name: "Notes")
        let xcodeSheet = MenuBarCheatSheet(frontApp: xcode, configuration: configuration)
        var debugPage = xcodeSheet
        debugPage.showNextPage()
        var globalPage = xcodeSheet
        globalPage.showPage(xcodeSheet.globalPagesStart ?? 0)
        let fallback = MenuBarCheatSheet(frontApp: notes, configuration: configuration)
        var sparse = configuration
        sparse.updateProfile(id: sparse.globalProfile.id) { profile in
            profile.pages = [Page(cells: Array(profile.pages[0].cells.prefix(3)) + [nil, nil, nil, nil, nil, nil])]
        }
        let sparseSheet = MenuBarCheatSheet(frontApp: nil, configuration: sparse)

        struct Shot {
            var name: String
            var sheet: MenuBarCheatSheet
            var density: MenuBarCheatSheetLayout.Density = .regular
            var increasedContrast = false
            var hovered: MenuBarCheatSheetControl?
            var keyboard = false
            var width = MenuBarCheatSheetLayout.preferredWidth
        }
        let shots = [
            Shot(name: "cheatsheet-xcode", sheet: xcodeSheet, hovered: .cell(4)),
            Shot(name: "cheatsheet-xcode-debug-page", sheet: debugPage, hovered: .nextPage),
            Shot(name: "cheatsheet-global-page", sheet: globalPage),
            Shot(name: "cheatsheet-fallback-global", sheet: fallback),
            Shot(name: "cheatsheet-sparse-hover-empty", sheet: sparseSheet, hovered: .cell(5)),
            Shot(name: "cheatsheet-keyboard", sheet: xcodeSheet, keyboard: true),
            Shot(name: "cheatsheet-compact", sheet: xcodeSheet, density: .compact),
            Shot(name: "cheatsheet-contrast", sheet: sparseSheet, increasedContrast: true),
            Shot(name: "cheatsheet-wide-menu", sheet: xcodeSheet, width: 340),
        ]
        for (suffix, appearance) in ShellRenderTests.appearances {
            for shot in shots {
                let view = MenuBarCheatSheetView(sheet: shot.sheet, density: shot.density, increasedContrast: shot.increasedContrast)
                view.setFrameSize(NSSize(width: shot.width, height: view.frame.height))
                view.store.hovered = shot.hovered
                view.store.isKeyboardHighlighted = shot.keyboard
                try Self.render(view, appearance: appearance, name: "\(shot.name)-\(suffix)")
            }
        }
    }

    /// メニューの地の色（ウィンドウの背景に近い）の上に置き、本物の AppKit と SwiftUI で描く
    static func render(_ view: NSView, appearance: NSAppearance.Name, name: String) throws {
        let frame = CGRect(origin: .zero, size: view.frame.size)
        let background = MenuBackgroundView(frame: frame)
        background.addSubview(view)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        window.contentView = background
        background.layoutSubtreeIfNeeded()
        // SwiftUI の更新（アプリのアイコンの読み込みなど）を流す
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        background.layoutSubtreeIfNeeded()
        let rep = try #require(background.bitmapImageRepForCachingDisplay(in: background.bounds))
        background.cacheDisplay(in: background.bounds, to: rep)
        let data = try #require(rep.representation(using: .png, properties: [:]))
        try data.write(to: try ShellRenderTests.url(name))
    }
}

private final class MenuBackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
    }
}
