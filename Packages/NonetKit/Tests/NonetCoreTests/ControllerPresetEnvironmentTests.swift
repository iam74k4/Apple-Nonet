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
        // ランチャーは「画面に置く」「ユーティリティ」の次のページ
        let global = h.controller.configuration.globalProfile.pages[2].cells.compactMap { $0 }
        #expect(global.first?.action == .launchApp(LaunchAppAction(app: Self.figma)))
        #expect(global.dropFirst().first?.icon == .app(bundleID: "com.apple.mail"))
    }

    /// 初回の設定は claude を調べ終える前に作る。調べ終えて見つかったら、何も変えていなければ Claude Code のマスを入れて作り直す
    @Test func firstLaunchAddsClaudeCodeOnceTheShellCheckFinishes() async throws {
        let environment = LatePresetEnvironment()
        let h = try ControllerHarness(configuration: nil, installed: [Self.xcode.bundleID], presetEnvironment: environment)
        h.start()
        h.controller.update { $0.settings.hudScale = .large }
        #expect(!Self.hasClaudeCode(h, in: Self.xcode))
        await h.waitUntil { environment.isWaiting }
        environment.finish(.all)
        await h.waitUntil { Self.hasClaudeCode(h, in: Self.xcode) }
        #expect(Self.hasClaudeCode(h, in: Self.xcode))
        // 全体の設定はそのまま
        #expect(h.controller.configuration.settings.hudScale == .large)
    }

    /// 調べ終える前にプロファイルを変えていたら、作り直さない（変えたものを消さない）
    @Test func firstLaunchKeepsEditsMadeBeforeTheShellCheckFinishes() async throws {
        let environment = LatePresetEnvironment()
        let h = try ControllerHarness(configuration: nil, installed: [Self.xcode.bundleID], presetEnvironment: environment)
        h.start()
        let xcodeID = try h.profileID(Self.xcode)
        h.controller.update { $0.setCell(nil, at: CellAddress(page: 0, index: 0), profileID: xcodeID) }
        let edited = h.controller.configuration
        await h.waitUntil { environment.isWaiting }
        environment.finish(.all)
        for _ in 0..<20 { await Task.yield() }
        #expect(h.controller.configuration == edited)
    }

    static func hasClaudeCode(_ h: ControllerHarness, in app: AppReference) -> Bool {
        guard let profile = h.controller.configuration.appProfile(forBundleID: app.bundleID) else { return false }
        return profile.pages.flatMap(\.cells).contains { cell in
            if case .script(let script)? = cell?.action { script.runMode == .terminal } else { false }
        }
    }

    @Test func aTestRunKeepsTheResultForTheInspector() async throws {
        let h = try ControllerHarness(frontmost: ControllerFixtures.notesApp)
        h.performer.output = { _ in "out" }
        h.start()
        let record = await h.controller.testRun(ControllerFixtures.docs, profileID: h.controller.configuration.globalProfile.id)
        #expect(record.succeeded)
        #expect(record.output == "out")
    }

    @Test func scriptsAndShortcutsNeverSendInput() {
        #expect(!ControllerExecutionPolicy.sendsInputToFrontmostApp(.script(ScriptAction(source: "x"))))
        #expect(!ControllerExecutionPolicy.sendsInputToFrontmostApp(.shortcut(ShortcutAction(name: "s", passSelectedText: true))))
    }
}

/// すぐに返す capabilities は claude を調べ終える前（見つからない扱い）で、resolvedCapabilities は finish まで待つ
@MainActor
final class LatePresetEnvironment: PresetEnvironmentProviding {
    private(set) var capabilities = PresetCapabilities(appleIntelligence: true, claudeCode: false)
    private var waiters: [CheckedContinuation<PresetCapabilities, Never>] = []

    var isWaiting: Bool { !waiters.isEmpty }

    func resolvedCapabilities() async -> PresetCapabilities {
        await withCheckedContinuation { waiters.append($0) }
    }

    func finish(_ resolved: PresetCapabilities) {
        capabilities = resolved
        let pending = waiters
        waiters = []
        for waiter in pending {
            waiter.resume(returning: resolved)
        }
    }

    func dockApps() -> [AppReference] { [] }
}
