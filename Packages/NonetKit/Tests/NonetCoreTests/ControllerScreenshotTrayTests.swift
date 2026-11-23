// 担当: engine。「最近のスクショ」のマスは、前面のアプリに何も送らず、画面にトレイを出す
import Foundation
import Testing
@testable import NonetCore

@MainActor
@Suite struct ControllerScreenshotTrayTests {
    typealias F = ControllerFixtures

    static let tray = Cell(title: "最近のスクショ", icon: .symbol("photo.on.rectangle"), action: .screenshots(ScreenshotTrayAction()))

    private func harness() throws -> ControllerHarness {
        var configuration = F.configuration()
        configuration.update(cell: Self.tray, at: 1, page: 0, ofApp: F.safari)
        let h = try ControllerHarness(configuration: configuration)
        h.start()
        return h
    }

    @Test func runningTheCellShowsTheTrayWithoutTheActionPerformer() async throws {
        let h = try harness()
        h.run(1)
        await h.settle()
        #expect(h.hud.screenshotTrays == 1)
        #expect(h.performer.calls.isEmpty)
        #expect(h.controller.lastExecution?.succeeded == true)
        // トレイが出るので、成功のトーストは出さない
        #expect(h.hud.toasts.isEmpty)
    }

    /// Nonet のパネルなので、どのアプリが前面でも同じ（Nonet のウィンドウがキーでも出す）
    @Test func theTrayDoesNotDependOnTheFrontmostApp() {
        #expect(!ControllerExecutionPolicy.dependsOnFrontmostApp(Self.tray.action))
        #expect(!ControllerExecutionPolicy.isLongRunning(Self.tray.action))
        #expect(!ControllerExecutionPolicy.canStop(Self.tray.action))
        #expect(!ControllerExecutionPolicy.sendsInputToFrontmostApp(Self.tray.action))
    }
}

private extension NonetConfiguration {
    /// app のプロファイルの page の index にマスを置く
    mutating func update(cell: Cell, at index: Int, page: Int, ofApp app: AppReference) {
        guard let profile = profiles.firstIndex(where: { $0.kind == .app(app) }) else { return }
        profiles[profile].pages[page].cells[index] = cell
    }
}
