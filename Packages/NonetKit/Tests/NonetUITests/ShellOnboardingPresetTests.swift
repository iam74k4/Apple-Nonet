// 担当: ui-shell。初回の案内の「アプリを選ぶ」で、この Mac でできることを調べ直す
import Foundation
import NonetCore
@testable import NonetUI
import Testing

@Suite("初回の案内のプリセット")
@MainActor
struct ShellOnboardingPresetTests {
    static let installed: Set<String> = [ShellFixtures.xcode, ShellFixtures.safari]

    @Test("「アプリを選ぶ」で調べ直した結果でカードの説明と作り直す設定を決め、グローバルは Dock から始める")
    func choosingAppsUsesResolvedCapabilities() async throws {
        let environment = FixedPresetEnvironment(capabilities: .none, dockApps: [AppReference(bundleID: "com.figma.Desktop", name: "Figma")])
        let harness = ShellControllerHarness(installed: Self.installed, accessibilityGranted: true)
        harness.controller.start()
        let model = OnboardingModel(
            controller: harness.controller,
            permissions: harness.permissions,
            installedApps: harness.installedApps,
            presetEnvironment: environment,
            isFirstLaunchGuide: true
        )
        let xcodeWithoutClaude = try #require(PresetLibrary.preset(forBundleID: ShellFixtures.xcode, capabilities: .none))
        #expect(model.choices.first { $0.id == ShellFixtures.xcode }?.summary == xcodeWithoutClaude.summary)

        // claude を調べ終えたら見つかった
        environment.capabilities = .all
        model.next()
        for _ in 0..<50 where model.choices.first(where: { $0.id == ShellFixtures.xcode })?.summary == xcodeWithoutClaude.summary {
            try await Task.sleep(for: .milliseconds(10))
        }
        let xcodeFull = try #require(PresetLibrary.preset(forBundleID: ShellFixtures.xcode, capabilities: .all))
        #expect(model.choices.first { $0.id == ShellFixtures.xcode }?.summary == xcodeFull.summary)

        model.applySelection()
        let configuration = harness.controller.configuration
        let xcode = try #require(configuration.appProfile(forBundleID: ShellFixtures.xcode))
        #expect(xcode.pages[0].cells.compactMap { $0 }.count == 9)
        let first = configuration.globalProfile.pages[0].cells[0]
        #expect(first?.icon == .app(bundleID: "com.figma.Desktop"))
    }
}
