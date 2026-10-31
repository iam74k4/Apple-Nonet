// 担当: engine。HUD で選んだときだけ実行するマス（Cell.requiresHUD）と境界の帯を、NonetController を通して確かめる。
// 既定: トリガーは右⌥、hudDelay 0.3秒、onTriggerRelease、前面は Safari（ControllerHarness）
import Foundation
import Testing
@testable import NonetCore

@MainActor
@Suite struct ControllerHUDOnlyTests {
    typealias F = ControllerFixtures

    /// Safari の1ページ目の「タブを閉じる」（マス 2）を HUD で選ぶマスにした設定
    static func configuration() -> NonetConfiguration {
        var configuration = F.configuration()
        let safari = configuration.appProfile(forBundleID: F.safari.bundleID)
        if let id = safari?.id {
            var closeTab = F.closeTab
            closeTab.requiresHUD = true
            configuration.setCell(closeTab, at: CellAddress(page: 0, index: 2), profileID: id)
        }
        return configuration
    }

    @Test func theSessionPassesTheHUDOnlyCellsOfEveryPage() throws {
        let session = ControllerSession(configuration: Self.configuration(), frontmostApp: F.safariApp)
        #expect(session.engineConfiguration.hudOnlyCells == [[2], [], []])
        // HUD のマスにも印を付ける
        let model = session.hudModel(page: 0, highlightedCell: nil, isPracticeMode: false, isTrialEnded: false)
        #expect(model.cells.map { $0?.requiresHUD } == [false, nil, true, nil, false, nil, nil, nil, false])
    }

    @Test func aFastTapOnAHUDOnlyCellShowsTheHUDInsteadOfRunning() async throws {
        let h = try ControllerHarness(configuration: Self.configuration())
        h.start()
        h.pressTrigger()
        h.tap(2)
        await h.settle()

        #expect(h.performer.calls.isEmpty)
        #expect(h.controller.lastExecution == nil)
        #expect(h.haptics.events == [.rejected])
        #expect(h.hud.isVisible)
        #expect(h.hud.shown.count == 1)
        #expect(h.hud.current?.highlightedIndex == 2)
        #expect(h.hud.current?.cells[2]?.requiresHUD == true)
        #expect(h.hud.toasts.isEmpty)

        // もう一度タップすると実行する（HUD から実行したので、成功のトーストは出さない）
        h.tap(2)
        await h.settle()
        #expect(h.performer.actions == [F.closeTab.action])
        #expect(h.haptics.events == [.rejected, .execute])
        #expect(!h.hud.isVisible)
        #expect(h.controller.lastExecution?.wasFastTap == false)
        #expect(h.hud.toasts.isEmpty)
        h.releaseTrigger()
    }

    @Test func releasingTheTriggerAfterTheFastTapRunsNothing() async throws {
        let h = try ControllerHarness(configuration: Self.configuration())
        h.start()
        h.fastTap(2)
        await h.settle()

        #expect(h.performer.calls.isEmpty)
        #expect(h.haptics.events == [.rejected])
        #expect(!h.hud.isVisible)
        #expect(!h.keyboard.isSuppressingPointer)
    }

    /// 境界の帯に落ちた速押しは、どちらのマスも実行しない
    @Test func aFastTapOnALineRunsNothing() async throws {
        let h = try ControllerHarness()
        h.start()
        h.pressTrigger()
        h.advance(0.05)
        // タブを閉じる（2）と空きマス（5）の間の横の線
        h.touch(x: 5.0 / 6, y: 2.0 / 3)
        h.advance(0.05)
        h.lift()
        h.advance(0.05)
        h.releaseTrigger()
        await h.settle()

        #expect(h.performer.calls.isEmpty)
        #expect(h.haptics.events == [.rejected])
        #expect(h.hud.shown.isEmpty)
    }
}
