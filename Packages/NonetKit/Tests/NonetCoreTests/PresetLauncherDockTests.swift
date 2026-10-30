// 担当: presets
import Foundation
import Testing
@testable import NonetCore

/// グローバル（ランチャー）を Dock の並びから始める
@Suite struct PresetLauncherDockTests {
    static let capacity = Page.cellCount * Profile.maxPages
    static let blender = AppReference(bundleID: "org.blenderfoundation.blender", name: "Blender")
    static let unityHub = AppReference(bundleID: "com.unity3d.unityhub", name: "Unity Hub")
    static let chatGPT = "com.openai.codex"
    static let chatGPTClassic = "com.openai.chat"

    static func launched(_ profile: Profile) -> [String] {
        profile.pages.flatMap(\.cells).compactMap { cell -> String? in
            guard case .launchApp(let launch)? = cell?.action else { return nil }
            return launch.app.bundleID
        }
    }

    static func app(_ bundleID: String, _ name: String = "") -> AppReference {
        AppReference(bundleID: bundleID, name: name)
    }

    @Test func dockAppsComeFirstInDockOrderThenCandidates() {
        let dock = [Self.blender, Self.app("com.apple.dt.Xcode", "Xcode"), Self.app("com.microsoft.VSCode", "Visual Studio Code")]
        let installed: Set<String> = ["com.apple.mail", "com.apple.Safari", "com.apple.dt.Xcode", "com.microsoft.VSCode"]
        let profile = PresetLibrary.makeGlobalProfile(installedBundleIDs: installed, dockApps: dock)
        // Dock の順のあと、候補の優先順（メール・Safari）。Dock にあった Xcode と VS Code は2回並べない
        #expect(Self.launched(profile) == [
            "org.blenderfoundation.blender", "com.apple.dt.Xcode", "com.microsoft.VSCode", "com.apple.mail", "com.apple.Safari",
        ])
    }

    @Test func emptyDockFallsBackToTheCandidateOrder() {
        let installed = Set(PresetLibrary.launcherCandidates.prefix(12).map(\.bundleID))
        let withoutDock = PresetLibrary.makeGlobalProfile(installedBundleIDs: installed)
        let emptyDock = PresetLibrary.makeGlobalProfile(installedBundleIDs: installed, dockApps: [])
        #expect(Self.launched(emptyDock) == Self.launched(withoutDock))
        #expect(Self.launched(emptyDock).first == "com.apple.mail")
    }

    @Test func candidateAppsUseTheShortCandidateTitle() throws {
        // 候補にあるアプリは候補の名前（短い名前・表示用の名前）、候補に無いアプリは Dock から来た名前
        let dock = [Self.app("com.microsoft.VSCode", "Visual Studio Code"), Self.unityHub]
        let profile = PresetLibrary.makeGlobalProfile(installedBundleIDs: [], dockApps: dock)
        let cells = profile.pages[0].cells.compactMap { $0 }
        #expect(cells.map(\.title) == ["VS Code", "Unity Hub"])
        #expect(cells[0].action == .launchApp(LaunchAppAction(app: KnownApp.vsCode)))
        #expect(cells[1].action == .launchApp(LaunchAppAction(app: Self.unityHub)))
        #expect(cells[1].icon == .app(bundleID: Self.unityHub.bundleID))
    }

    @Test func appWithoutANameUsesItsBundleID() throws {
        let profile = PresetLibrary.makeGlobalProfile(installedBundleIDs: [], dockApps: [Self.app("com.example.noname", "  ")])
        #expect(profile.pages[0].cells[0]?.title == "com.example.noname")
    }

    @Test func duplicatesAndEmptyIDsAreSkippedIgnoringCase() {
        let dock = [Self.blender, Self.app("ORG.BLENDERFOUNDATION.BLENDER", "Blender"), Self.app("", "空")]
        let profile = PresetLibrary.makeGlobalProfile(installedBundleIDs: ["COM.APPLE.MAIL"], dockApps: dock)
        #expect(Self.launched(profile) == ["org.blenderfoundation.blender", "com.apple.mail"])
    }

    @Test func dockWinsBetweenTheNewAndOldChatGPT() {
        // 以前の ChatGPT を Dock に置いている人には、そちらだけ（新しいほうを足して2マスにしない）
        let classicInDock = PresetLibrary.makeGlobalProfile(
            installedBundleIDs: [Self.chatGPT, Self.chatGPTClassic],
            dockApps: [Self.app(Self.chatGPTClassic, "ChatGPT Classic")]
        )
        #expect(Self.launched(classicInDock) == [Self.chatGPTClassic])
        let newInDock = PresetLibrary.makeGlobalProfile(
            installedBundleIDs: [Self.chatGPT, Self.chatGPTClassic],
            dockApps: [Self.app(Self.chatGPT, "ChatGPT")]
        )
        #expect(Self.launched(newInDock) == [Self.chatGPT])
    }

    @Test func cappedAtThreePages() {
        let dock = (0..<20).map { Self.app("com.example.dock\($0)", "Dock \($0)") }
        let installed = Set(PresetLibrary.launcherCandidates.map(\.bundleID))
        let profile = PresetLibrary.makeGlobalProfile(installedBundleIDs: installed, dockApps: dock)
        let launched = Self.launched(profile)
        #expect(profile.pages.count == Profile.maxPages)
        #expect(launched.count == Self.capacity)
        #expect(Array(launched.prefix(20)) == dock.map(\.bundleID))
        // 残りの7マスは候補の優先順
        #expect(launched.dropFirst(20).first == "com.apple.mail")
    }
}
