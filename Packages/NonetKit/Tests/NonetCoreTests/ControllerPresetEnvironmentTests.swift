// 担当: engine。この Mac でできることに合わせた初回の設定と、テスト実行の結果
import Foundation
import Testing
@testable import NonetCore

@MainActor
@Suite struct ControllerPresetEnvironmentTests {
    static let xcode = AppReference(bundleID: "com.apple.dt.Xcode", name: "Xcode")
    static let figma = AppReference(bundleID: "com.figma.Desktop", name: "Figma")

    @Test func firstLaunchBuildsPresetsForThisMacAndStartsTheLauncherWithTheDock() throws {
        let environment = FixedPresetEnvironment(capabilities: .none, dockApps: [Self.figma])
        let h = try ControllerHarness(configuration: nil, installed: [Self.xcode.bundleID, "com.apple.mail"], presetEnvironment: environment)
        h.start()
        let xcode = try #require(h.controller.configuration.appProfile(forBundleID: Self.xcode.bundleID))
        let cells = xcode.pages[0].cells.compactMap { $0 }
        #expect(cells.count == 8)
        #expect(!cells.contains { if case .script(let script) = $0.action { script.runMode == .terminal } else { false } })
        let global = h.controller.configuration.globalProfile.pages[0].cells.compactMap { $0 }
        #expect(global.first?.action == .launchApp(LaunchAppAction(app: Self.figma)))
        #expect(global.dropFirst().first?.icon == .app(bundleID: "com.apple.mail"))
    }

    @Test func aTestRunKeepsTheResultForTheInspector() async throws {
        let h = try ControllerHarness(frontmost: ControllerFixtures.notesApp)
        h.performer.output = { _ in "out" }
        h.start()
        let record = await h.controller.testRun(ControllerFixtures.docs, profileID: h.controller.configuration.globalProfile.id)
        #expect(record.succeeded)
        #expect(record.output == "out")
    }

    @Test func scriptsAndShortcutsThatReplaceTheSelectionSendInput() {
        #expect(ControllerExecutionPolicy.sendsInputToFrontmostApp(.script(ScriptAction(source: "x", output: .replaceSelection))))
        #expect(!ControllerExecutionPolicy.sendsInputToFrontmostApp(.script(ScriptAction(source: "x", runMode: .terminal, output: .replaceSelection))))
        #expect(!ControllerExecutionPolicy.sendsInputToFrontmostApp(.script(ScriptAction(source: "x", output: .copyToClipboard))))
        #expect(ControllerExecutionPolicy.sendsInputToFrontmostApp(.shortcut(ShortcutAction(name: "s", output: .replaceSelection))))
        #expect(!ControllerExecutionPolicy.sendsInputToFrontmostApp(.shortcut(ShortcutAction(name: "s"))))
    }
}
