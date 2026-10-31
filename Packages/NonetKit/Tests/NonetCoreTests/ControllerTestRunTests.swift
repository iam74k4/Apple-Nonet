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
        #expect(h.controller.lastExecution == record)
        #expect(h.hud.toasts.isEmpty)
        #expect(!h.scheduler.requestedDelays.contains(NonetController.activationRetryInterval))
    }

    /// アプリが前面に来ないまま、待てるだけ待つ
    private func waitOutTheActivation(_ h: ControllerHarness) async {
        for _ in 0...NonetController.activationRetryCount {
            await h.waitUntil {
                h.scheduler.hasPending(delay: NonetController.activationDelay) || h.scheduler.hasPending(delay: NonetController.activationRetryInterval)
            }
            h.advance(NonetController.activationDelay)
        }
    }

    @Test func aSlowAppGetsMoreTimeAndCellsThatSendNoKeysRunAnyway() async throws {
        let h = try ControllerHarness(frontmost: F.notesApp)
        h.start()
        let safariID = try h.profileID(F.safari)
        let run = Task { await h.controller.testRun(F.reader, profileID: safariID) }
        await waitOutTheActivation(h)
        let record = await run.value

        #expect(h.scheduler.requestedDelays.filter { $0 == NonetController.activationRetryInterval }.count == NonetController.activationRetryCount)
        #expect(h.performer.actions == [activateSafari, F.reader.action])
        #expect(record.succeeded)
    }

    nonisolated static let sendsInput: [Cell] = [
        F.newTab,
        Cell(title: "直す", icon: .symbol("wand.and.stars"), action: .ai(AIAction(prompt: "直して", output: .replaceSelection))),
    ]

    @Test(arguments: sendsInput)
    func keysAreNotSentWhenTheAppDoesNotComeToTheFront(_ cell: Cell) async throws {
        let h = try ControllerHarness(frontmost: F.notesApp)
        h.start()
        let safariID = try h.profileID(F.safari)
        let run = Task { await h.controller.testRun(cell, profileID: safariID) }
        await waitOutTheActivation(h)
        let record = await run.value

        // 送ると、いま前面にある設定ウィンドウに届く
        #expect(h.performer.actions == [activateSafari])
        #expect(!record.succeeded)
        let message = ModelFixtures.text("\("Safari") が前面になりませんでした")
        #expect(record.message == message)
        let title = ControllerPresentation.failureTitle(ControllerTarget(cell: cell, profileName: "Safari", address: CellAddress(page: 0, index: 0), profilePageCount: 2))
        #expect(h.hud.toasts == [ToastModel(title: title, detail: message, icon: cell.icon, style: .failure)])
        #expect(h.controller.lastExecution == record)
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

    @Test func aGlobalKeystrokeCellGoesToTheAppUsedBeforeTheSettingsWindow() async throws {
        let paste = Cell(title: "ペースト", icon: .symbol("doc.on.clipboard"), action: .keystroke(.key("v", [.command])))
        // frontmostApp は Nonet を数えないので、設定ウィンドウが前面でもメモを指す
        let h = try ControllerHarness(frontmost: F.notesApp)
        h.start()
        let globalID = h.controller.configuration.globalProfile.id
        let run = Task { await h.controller.testRun(paste, profileID: globalID) }

        await h.waitUntil { h.scheduler.hasPending(delay: NonetController.activationDelay) }
        #expect(h.performer.actions == [.launchApp(LaunchAppAction(app: F.notes, hideIfFrontmost: false))])
        h.advance(NonetController.activationDelay)
        let record = await run.value

        #expect(h.performer.actions == [.launchApp(LaunchAppAction(app: F.notes, hideIfFrontmost: false)), paste.action])
        #expect(h.performer.calls.last?.frontmostApp == F.notesApp)
        #expect(record.succeeded)
        #expect(record.profileName == ModelFixtures.globalName)
    }

    @Test func aGlobalKeystrokeCellIsRefusedWhenThereIsNoAppToSendTo() async throws {
        let h = try ControllerHarness(frontmost: nil)
        h.start()
        let record = await h.controller.testRun(F.closeTab, profileID: h.controller.configuration.globalProfile.id)

        #expect(h.performer.calls.isEmpty)
        #expect(!record.succeeded)
        #expect(h.hud.toasts.map(\.style) == [.failure])
    }

    @Test func aGlobalCellThatSendsNoKeysRunsWithoutAnApp() async throws {
        let h = try ControllerHarness(frontmost: nil)
        h.start()
        let save = Cell(title: "保存", icon: .symbol("square.and.arrow.down"), action: .menuItem(MenuItemAction(path: ["ファイル", "保存"])))
        let record = await h.controller.testRun(save, profileID: h.controller.configuration.globalProfile.id)
        #expect(h.performer.actions == [save.action])
        #expect(record.succeeded)
    }

    @Test func aGlobalLaunchCellDoesNotBringTheLastAppBackFirst() async throws {
        // 戻すと、「前面なら隠す」の起動がそのアプリを隠してしまう
        let toggleSafari = Cell(title: "Safari", icon: .app(bundleID: F.safari.bundleID), action: .launchApp(LaunchAppAction(app: F.safari, hideIfFrontmost: true)))
        let h = try ControllerHarness(frontmost: F.safariApp)
        h.start()
        let record = await h.controller.testRun(toggleSafari, profileID: h.controller.configuration.globalProfile.id)
        #expect(h.performer.actions == [toggleSafari.action])
        #expect(record.succeeded)
    }

    @Test func aGlobalCellRunsRightAway() async throws {
        let h = try ControllerHarness(frontmost: F.notesApp)
        h.start()
        let record = await h.controller.testRun(F.docs, profileID: h.controller.configuration.globalProfile.id)

        #expect(h.performer.actions == [F.docs.action])
        #expect(h.performer.calls.first?.frontmostApp == F.notesApp)
        #expect(record.profileName == ModelFixtures.globalName)
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
        let title = ControllerPresentation.failureTitle(ControllerTarget(cell: F.docs, profileName: ModelFixtures.globalName, address: CellAddress(page: 0, index: 8)))
        #expect(h.hud.toasts == [ToastModel(title: title, detail: "うまくいかない", icon: F.docs.icon, style: .failure)])
        // 設定のマスを開けるよう、プロファイルも記録する
        #expect(record.profileID == h.controller.configuration.globalProfile.id)
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
        h.run(2)
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
