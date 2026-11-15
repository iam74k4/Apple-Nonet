// 担当: ui-settings
import Foundation
import NonetCore
@testable import NonetUI
import Testing

@Suite struct SettingsAppCatalogTests {
    private let apps = [
        SettingsFixtures.figma,
        AppReference(bundleID: "com.example.Plain", name: "Plain"),
        SettingsFixtures.safari,
        AppReference(bundleID: "com.apple.safari", name: "Safari（重複）"),
        AppReference(bundleID: "", name: "名前だけ"),
        SettingsFixtures.xcode,
    ]

    @Test func presetsComeFirstWithoutAQuery() {
        let entries = SettingsAppCatalog.entries(apps: apps, query: "", existingBundleIDs: [], presetsFirst: true)
        #expect(entries.map(\.app.name) == ["Figma", "Safari", "Xcode", "Plain"])
        #expect(entries.map(\.hasPreset) == [true, true, true, false])
    }

    @Test func keepsTheGivenOrderWhenAsked() {
        let entries = SettingsAppCatalog.entries(apps: apps, query: "", existingBundleIDs: [], presetsFirst: false)
        #expect(entries.map(\.app.name) == ["Figma", "Plain", "Safari", "Xcode"])
    }

    @Test func searchesNamesAndBundleIDs() {
        #expect(SettingsAppCatalog.entries(apps: apps, query: "saf", existingBundleIDs: [], presetsFirst: true).map(\.app.name) == ["Safari"])
        #expect(SettingsAppCatalog.entries(apps: apps, query: "com.apple", existingBundleIDs: [], presetsFirst: true).map(\.app.name) == ["Safari", "Xcode"])
        #expect(SettingsAppCatalog.entries(apps: apps, query: "ＦＩＧ", existingBundleIDs: [], presetsFirst: true).map(\.app.name) == ["Figma"])
        #expect(SettingsAppCatalog.entries(apps: apps, query: "nothing", existingBundleIDs: [], presetsFirst: true).isEmpty)
    }

    @Test func marksAppsThatAlreadyHaveAProfile() {
        let entries = SettingsAppCatalog.entries(apps: apps, query: "", existingBundleIDs: ["COM.APPLE.DT.XCODE"], presetsFirst: true)
        #expect(entries.first { $0.app == SettingsFixtures.xcode }?.hasProfile == true)
        #expect(entries.first { $0.app == SettingsFixtures.figma }?.hasProfile == false)
    }

    @Test func readsABundleOnDisk() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "SettingsAppCatalogTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = directory.appending(path: "Sample.app")
        let contents = app.appending(path: "Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": "com.example.sample", "CFBundleName": "サンプル", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: contents.appending(path: "Info.plist"))
        #expect(SettingsAppCatalog.appReference(forBundleAt: app) == AppReference(bundleID: "com.example.sample", name: "サンプル"))

        let noID = directory.appending(path: "NoID.app")
        try FileManager.default.createDirectory(at: noID.appending(path: "Contents"), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleName": "x"], format: .xml, options: 0)
            .write(to: noID.appending(path: "Contents/Info.plist"))
        #expect(SettingsAppCatalog.appReference(forBundleAt: noID) == nil)
        #expect(SettingsAppCatalog.appReference(forBundleAt: directory.appending(path: "Missing.app")) == nil)
    }

    @Test func exportFileNamesAreSafe() {
        #expect(SettingsWindowCoordinator.fileName(for: "Xcode") == "Xcode.nonetprofile")
        #expect(SettingsWindowCoordinator.fileName(for: "a/b:c") == "a b c.nonetprofile")
        #expect(SettingsWindowCoordinator.fileName(for: "  ") == "Nonet.nonetprofile")
    }
}
