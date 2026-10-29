// 担当: engine。設定画面の「テスト実行」（NonetController.testRun）
import Foundation
import Testing
@testable import NonetCore

@MainActor
@Suite struct ControllerTestRunTests {
    typealias F = ControllerFixtures

    private let activateSafari = Action.launchApp(LaunchAppAction(app: F.safari, hideIfFrontmost: false))
    private let safariAfterLaunch = RunningAppInfo(app: F.safari, processID: 42)

    /// アプリを起動するアクションで、そのアプリが前面になったことにする
    private func activatesLaunchedApps(_ h: ControllerHarness) {
        let frontmost = h.frontmost
        let pid = safariAfterLaunch.processID
        h.performer.onPerform = { action in
            if case .launchApp(let launch) = action {
                frontmost.activate(RunningAppInfo(app: launch.app, processID: pid))
            }
        }
    }

    @Test func anAppProfileCellBringsTheAppToTheFrontFirst() async throws {
        let h = try ControllerHarness(frontmost: F.notesApp)
        activatesLaunchedApps(h)
        h.start()
        let safariID = try h.profileID(F.safari)
        let run = Task { await h.controller.testRun(F.closeTab, profileID: safariID) }

        await h.waitUntil { h.scheduler.hasPending(delay: NonetController.activationDelay) }
        // 前面に出してから少し待つ。マスはまだ実行しない
        #expect(h.performer.actions == [activateSafari])
        h.advance(NonetController.activationDelay)
        let record = await run.value

        #expect(h.performer.actions == [activateSafari, F.closeTab.action])
        #expect(h.performer.calls.last?.frontmostApp == safariAfterLaunch)
        #expect(record.succeeded)
        #expect(record.cellTitle == F.closeTab.title)
        #expect(record.profileName == "Safari")
        #expect(record.address == CellAddress(page: 0, index: 2))
        #expect(!record.wasFastTap)
        #expect(h.controller.lastExecution == record)
        #expect(h.hud.toasts.isEmpty)
        #expect(!h.scheduler.requestedDelays.contains(NonetController.activationRetryInterval))
    }

    @Test func aSlowAppGetsMoreTimeButTheCellRunsAnyway() async throws {
        let h = try ControllerHarness(frontmost: F.notesApp)
        h.start()
        let safariID = try h.profileID(F.safari)
        let run = Task { await h.controller.testRun(F.newTab, profileID: safariID) }

        for _ in 0...NonetController.activationRetryCount {
            await h.waitUntil {
                h.scheduler.hasPending(delay: NonetController.activationDelay) || h.scheduler.hasPending(delay: NonetController.activationRetryInterval)
            }
            h.advance(NonetController.activationDelay)
        }
        let record = await run.value

        #expect(h.scheduler.requestedDelays.filter { $0 == NonetController.activationRetryInterval }.count == NonetController.activationRetryCount)
        #expect(h.performer.actions == [activateSafari, F.newTab.action])
        #expect(record.succeeded)
    }

    @Test func itStopsWaitingOnceTheAppIsFrontmost() async throws {
        let h = try ControllerHarness(frontmost: F.notesApp)
        h.start()
        let safariID = try h.profileID(F.safari)
        let run = Task { await h.controller.testRun(F.newTab, profileID: safariID) }

        await h.waitUntil { h.scheduler.hasPending(delay: NonetController.activationDelay) }
        h.advance(NonetController.activationDelay)
        await h.waitUntil { h.scheduler.hasPending(delay: NonetController.activationRetryInterval) }
        h.frontmost.activate(safariAfterLaunch)
        h.advance(NonetController.activationRetryInterval)
        _ = await run.value

        #expect(h.scheduler.requestedDelays.filter { $0 == NonetController.activationRetryInterval }.count == 1)
        #expect(h.performer.calls.last?.frontmostApp == safariAfterLaunch)
    }

    @Test func aGlobalCellRunsRightAway() async throws {
        let h = try ControllerHarness(frontmost: F.notesApp)
        h.start()
        let record = await h.controller.testRun(F.docs, profileID: h.controller.configuration.globalProfile.id)

        #expect(h.performer.actions == [F.docs.action])
        #expect(h.performer.calls.first?.frontmostApp == F.notesApp)
        #expect(record.profileName == "グローバル")
        #expect(record.address == CellAddress(page: 0, index: 8))
        #expect(record.succeeded)
    }

    @Test func aCellThatIsNotSavedYetStillRuns() async throws {
        let h = try ControllerHarness()
        h.start()
        let cell = Cell(title: "新しいマス", icon: .symbol("star"), action: .openURL(URLAction(url: "https://example.com")))
        let record = await h.controller.testRun(cell, profileID: UUID())
        #expect(h.performer.actions == [cell.action])
        #expect(record.profileName == "")
        #expect(record.address == CellAddress(page: 0, index: 0))
    }

    @Test func aFailedActivationDoesNotRunTheCell() async throws {
        let h = try ControllerHarness(frontmost: F.notesApp)
        let error = NonetError.appNotFound("Safari")
        h.performer.failure = { action in
            if case .launchApp = action { return error }
            return nil
        }
        h.start()
        let record = await h.controller.testRun(F.closeTab, profileID: try h.profileID(F.safari))

        #expect(h.performer.actions == [activateSafari])
        #expect(!record.succeeded)
        #expect(record.message == error.errorDescription)
        #expect(h.hud.toasts.map(\.style) == [.failure])
    }

    @Test func failuresAreRecordedAndShown() async throws {
        let h = try ControllerHarness()
        let error = NonetError.actionFailed("うまくいかない")
        h.performer.failure = { _ in error }
        h.start()
        let record = await h.controller.testRun(F.docs, profileID: h.controller.configuration.globalProfile.id)
        #expect(!record.succeeded)
        #expect(record.message == "うまくいかない")
        #expect(h.hud.toasts == [ToastModel(title: F.docs.title, detail: "うまくいかない", icon: F.docs.icon, style: .failure)])
        #expect(h.controller.lastExecution == record)
    }

    @Test func outputIsShownInTheResultPanel() async throws {
        let h = try ControllerHarness(frontmost: F.safariApp)
        h.performer.output = { action in
            if case .ai = action { return "結果" }
            return nil
        }
        h.start()
        let run = Task { await h.controller.testRun(F.summarize, profileID: try h.profileID(F.safari)) }
        await h.waitUntil { h.scheduler.hasPending(delay: NonetController.activationDelay) }
        h.advance(NonetController.activationDelay)
        _ = try await run.value
        #expect(h.hud.results == [ResultModel(title: F.summarize.title, text: "結果", icon: F.summarize.icon)])
    }

    @Test func anExpiredTrialRefusesTestRuns() async throws {
        let h = try ControllerHarness(trialEnded: true)
        h.start()
        let record = await h.controller.testRun(F.closeTab, profileID: try h.profileID(F.safari))

        #expect(h.performer.calls.isEmpty)
        #expect(!record.succeeded)
        #expect(record.message == NonetError.licenseRequired.errorDescription)
        #expect(h.hud.toasts.map(\.style) == [.failure])
    }

    @Test func practiceModeDoesNotStopTestRuns() async throws {
        let h = try ControllerHarness()
        h.start()
        h.controller.isPracticeMode = true
        let record = await h.controller.testRun(F.docs, profileID: h.controller.configuration.globalProfile.id)
        #expect(h.performer.actions == [F.docs.action])
        #expect(record.succeeded)
    }

    @Test func testRunsWaitForExecutionsAlreadyRunning() async throws {
        let h = try ControllerHarness()
        h.performer.holds = true
        h.start()
        h.fastTap(2)
        await h.waitUntil { h.performer.calls.count == 1 }
        let run = Task { await h.controller.testRun(F.docs, profileID: h.controller.configuration.globalProfile.id) }
        await h.waitUntil { h.performer.calls.count > 1 }
        #expect(h.performer.calls.count == 1)
        h.performer.releaseOne()
        await h.waitUntil { h.performer.calls.count == 2 }
        h.performer.releaseOne()
        _ = await run.value
        #expect(h.performer.actions == [F.closeTab.action, F.docs.action])
        #expect(h.performer.maxRunning == 1)
    }
}
