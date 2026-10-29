// 担当: engine。NonetController の部品（HUD に渡すもの・セッションの文脈・保存のまとめ・実行の順番）
import Foundation
import Testing
@testable import NonetCore

@MainActor
@Suite struct ControllerPresentationTests {
    typealias F = ControllerFixtures

    private func pages(frontmost: AppReference?) -> [ResolvedPage] {
        F.configuration().resolvedPages(frontmostBundleID: frontmost?.bundleID)
    }

    @Test func hudModelMapsThePageAndClampsOutOfRangeValues() {
        let pages = pages(frontmost: F.safari)
        let model = ControllerPresentation.hudModel(pages: pages, page: 1, highlightedCell: 0, hint: "案内", banner: "帯")
        #expect(model.title == "Safari")
        #expect(model.pageIndex == 1)
        #expect(model.pageCount == 3)
        #expect(model.cells.count == Page.cellCount)
        #expect(model.cells[0]?.title == F.reload.title)
        #expect(model.cells[1...].allSatisfy { $0 == nil })
        #expect(model.highlightedIndex == 0)
        #expect(model.hint == "案内")
        #expect(model.banner == "帯")

        let beyond = ControllerPresentation.hudModel(pages: pages, page: 9, highlightedCell: 12, hint: "", banner: nil)
        #expect(beyond.pageIndex == 2)
        #expect(beyond.title == "グローバル")
        #expect(beyond.highlightedIndex == nil)
        #expect(ControllerPresentation.hudModel(pages: pages, page: -1, highlightedCell: -1, hint: "", banner: nil).pageIndex == 0)
    }

    @Test func hudModelWithoutPagesIsEmptyButValid() {
        let model = ControllerPresentation.hudModel(pages: [], page: 0, highlightedCell: nil, hint: "", banner: nil)
        #expect(model.title == "")
        #expect(model.pageCount == 1)
        #expect(model.cells == Array(repeating: nil, count: Page.cellCount))
    }

    @Test func onlyKeystrokesShowTheirKeys() {
        let keys = KeySequence.sequence(.key("l", [.command]), .key("c", [.command]))
        #expect(ControllerPresentation.detail(for: .keystroke(keys)) == keys.displayString)
        #expect(ControllerPresentation.detail(for: .keystroke(KeySequence([]))) == nil)
        #expect(ControllerPresentation.detail(for: F.docs.action) == nil)
        #expect(ControllerPresentation.hudCell(F.newTab) == HUDCell(title: F.newTab.title, icon: F.newTab.icon, detail: ControllerPresentation.detail(for: F.newTab.action)))
    }

    @Test func hintsFollowTheFireModeTriggerAndPracticeMode() {
        #expect(ControllerPresentation.hint(fireMode: .onTriggerRelease, trigger: .rightCommand, isPracticeMode: false) == "⌘を離して実行")
        #expect(ControllerPresentation.hint(fireMode: .onTriggerRelease, trigger: .function, isPracticeMode: false) == "fnを離して実行")
        #expect(ControllerPresentation.hint(fireMode: .onFingerLift, trigger: .rightCommand, isPracticeMode: false) == "指を離して実行")
        #expect(ControllerPresentation.hint(fireMode: .onTriggerRelease, trigger: .rightOption, isPracticeMode: true) == "練習中 · ⌥を離して実行")
        #expect(ControllerPresentation.trialEndedBanner == "試用期間が終了しました")
    }

    @Test func toastsAndResultsCarryTheCell() {
        #expect(ControllerPresentation.successToast(F.newTab) == ToastModel(title: F.newTab.title, icon: F.newTab.icon, style: .success))
        #expect(ControllerPresentation.failureToast(F.newTab, message: "だめ") == ToastModel(title: F.newTab.title, detail: "だめ", icon: F.newTab.icon, style: .failure))
        #expect(ControllerPresentation.result(F.summarize, output: "文") == ResultModel(title: F.summarize.title, text: "文", icon: F.summarize.icon))
    }
}

@MainActor
@Suite struct ControllerSessionContextTests {
    typealias F = ControllerFixtures

    @Test func theSessionResolvesPagesForTheFrontmostApp() {
        let session = ControllerSession(configuration: F.configuration(), frontmostApp: F.safariApp)
        #expect(session.pages.map(\.profileName) == ["Safari", "Safari", "グローバル"])
        #expect(session.engineConfiguration == SessionConfiguration(hudDelay: 0.3, fireMode: .onTriggerRelease, pageCount: 3))

        let other = ControllerSession(configuration: F.configuration(), frontmostApp: nil)
        #expect(other.pages.map(\.profileName) == ["グローバル"])
    }

    @Test func targetsUseTheAddressInsideTheProfile() {
        let session = ControllerSession(configuration: F.configuration(), frontmostApp: F.safariApp)
        #expect(session.target(page: 0, cell: 2) == ControllerTarget(cell: F.closeTab, profileName: "Safari", address: CellAddress(page: 0, index: 2)))
        #expect(session.target(page: 1, cell: 0)?.address == CellAddress(page: 1, index: 0))
        #expect(session.target(page: 2, cell: 8) == ControllerTarget(cell: F.docs, profileName: "グローバル", address: CellAddress(page: 0, index: 8)))
        // 空きマスと範囲外
        #expect(session.target(page: 0, cell: 1) == nil)
        #expect(session.target(page: 3, cell: 0) == nil)
        #expect(session.target(page: -1, cell: 0) == nil)
        #expect(session.target(page: 0, cell: 9) == nil)
    }

    @Test func theHUDModelUsesTheSessionSettings() {
        let settings = F.settings { $0.fireMode = .onFingerLift }
        let session = ControllerSession(configuration: F.configuration(settings: settings), frontmostApp: F.safariApp)
        let model = session.hudModel(page: 0, highlightedCell: 4, isPracticeMode: false, isTrialEnded: true)
        #expect(model.hint == "指を離して実行")
        #expect(model.banner == "試用期間が終了しました")
        #expect(model.highlightedIndex == 4)
        #expect(session.hudModel(page: 0, highlightedCell: nil, isPracticeMode: true, isTrialEnded: false).banner == nil)
    }
}

@MainActor
@Suite struct ControllerSaverTests {
    private final class Writes {
        var saved: [NonetConfiguration] = []
        var error: (any Error)?
    }

    private func makeSaver(_ writes: Writes, scheduler: ControllerFakeScheduler) -> ControllerConfigurationSaver {
        ControllerConfigurationSaver(scheduler: scheduler) { configuration in
            if let error = writes.error { throw error }
            writes.saved.append(configuration)
        }
    }

    private func configuration(hudDelay: Double) -> NonetConfiguration {
        NonetConfiguration(settings: GlobalSettings(hudDelay: hudDelay), profiles: [])
    }

    @Test func writesTheLatestConfigurationOnceAfterTheInterval() {
        let scheduler = ControllerFakeScheduler()
        let writes = Writes()
        let saver = makeSaver(writes, scheduler: scheduler)
        saver.schedule(configuration(hudDelay: 0.2))
        scheduler.advance(by: 0.3)
        saver.schedule(configuration(hudDelay: 0.4))
        #expect(saver.hasPendingSave)
        #expect(writes.saved.isEmpty)
        scheduler.advance(by: 0.2)
        #expect(writes.saved == [configuration(hudDelay: 0.4)])
        #expect(!saver.hasPendingSave)
        #expect(scheduler.pending.isEmpty)
    }

    @Test func flushAndSaveNowWriteImmediately() {
        let scheduler = ControllerFakeScheduler()
        let writes = Writes()
        let saver = makeSaver(writes, scheduler: scheduler)
        saver.schedule(configuration(hudDelay: 0.2))
        saver.flush()
        #expect(writes.saved == [configuration(hudDelay: 0.2)])
        #expect(scheduler.pending.isEmpty)
        saver.flush()
        #expect(writes.saved.count == 1)
        saver.saveNow(configuration(hudDelay: 0.5))
        #expect(writes.saved.count == 2)
    }

    @Test func reportsResults() {
        let scheduler = ControllerFakeScheduler()
        let writes = Writes()
        let saver = makeSaver(writes, scheduler: scheduler)
        var results: [Bool] = []
        saver.onResult = { results.append((try? $0.get()) != nil) }
        saver.saveNow(configuration(hudDelay: 0.2))
        writes.error = ConfigurationStoreError.writeFailed(reason: "x")
        saver.saveNow(configuration(hudDelay: 0.3))
        #expect(results == [true, false])
        // 失敗しても、次の変更でまた書こうとする
        writes.error = nil
        saver.schedule(configuration(hudDelay: 0.4))
        scheduler.advance(by: 1)
        #expect(results == [true, false, true])
    }

    @Test func aDisabledSaverDropsEverything() {
        let scheduler = ControllerFakeScheduler()
        let writes = Writes()
        let saver = makeSaver(writes, scheduler: scheduler)
        saver.schedule(configuration(hudDelay: 0.2))
        saver.isEnabled = false
        #expect(!saver.hasPendingSave)
        saver.schedule(configuration(hudDelay: 0.3))
        saver.saveNow(configuration(hudDelay: 0.4))
        scheduler.advance(by: 1)
        saver.flush()
        #expect(writes.saved.isEmpty)
    }
}

@MainActor
@Suite struct ControllerExecutionQueueTests {
    @Test func jobsRunOneAtATimeInOrder() async {
        let queue = ControllerExecutionQueue()
        var log: [String] = []
        for name in ["a", "b", "c"] {
            queue.enqueue {
                log.append("\(name)>")
                await Task.yield()
                await Task.yield()
                log.append("<\(name)")
            }
        }
        await queue.waitUntilIdle()
        #expect(log == ["a>", "<a", "b>", "<b", "c>", "<c"])
    }

    @Test func enqueueReturnsTheResult() async {
        let queue = ControllerExecutionQueue()
        let first = queue.enqueue { 1 }
        let second = queue.enqueue { "二" }
        #expect(await first.value == 1)
        #expect(await second.value == "二")
    }

    @Test func waitUntilIdleIncludesJobsAddedWhileWaiting() async {
        let queue = ControllerExecutionQueue()
        var done: [Int] = []
        queue.enqueue {
            await Task.yield()
            done.append(1)
            queue.enqueue {
                await Task.yield()
                done.append(2)
            }
        }
        await queue.waitUntilIdle()
        #expect(done == [1, 2])
    }

    @Test func anIdleQueueReturnsAtOnce() async {
        await ControllerExecutionQueue().waitUntilIdle()
    }
}
