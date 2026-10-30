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
        #expect(beyond.title == ModelFixtures.globalName)
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

    /// どのキーか（右⌘ など。JIS 配列には⌘が2つある）まで言い、「キーを離したとき」でもタップで実行できることを言う
    @Test func hintsNameTheTriggerKeyAndSayTappingWorks() {
        let release = { (trigger: TriggerKey) in ModelFixtures.text("タップか \(trigger.localizedName)を離して実行") }
        #expect(ControllerPresentation.hint(fireMode: .onTriggerRelease, trigger: .rightCommand, isPracticeMode: false) == release(.rightCommand))
        #expect(ControllerPresentation.hint(fireMode: .onTriggerRelease, trigger: .function, isPracticeMode: false) == release(.function))
        #expect(ControllerPresentation.hint(fireMode: .onFingerLift, trigger: .rightCommand, isPracticeMode: false) == ModelFixtures.text("指を離して実行"))
        #expect(ControllerPresentation.hint(fireMode: .onTriggerRelease, trigger: .rightOption, isPracticeMode: true) == ModelFixtures.text("練習中 · \(release(.rightOption))"))
        #expect(TriggerKey.allCases.map(\.localizedName) == [
            ModelFixtures.text("右⌘"), ModelFixtures.text("右⌥"), ModelFixtures.text("右⇧"), ModelFixtures.text("fn"),
        ])
    }

    /// 試用期間が終わった後の帯は、次にすること（メニューバーの Nonet から購入・登録）まで言う。トーストの説明と同じ文
    @Test func trialTexts() {
        let ended = ModelFixtures.text("試用期間が終了しました。メニューバーの Nonet から購入・登録できます")
        #expect(ControllerPresentation.trialEndedBanner == ended)
        #expect(NonetError.licenseRequired.localizedDescription == ended)
        #expect(ControllerPresentation.trialReminderBanner(daysLeft: 3) == String(localized: "試用期間は残り\(3)日です", bundle: .nonetCore, locale: ControllerPresentation.textLocale))
        #expect(ControllerPresentation.trialReminderBanner(daysLeft: 1) == String(localized: "試用期間は残り\(1)日です", bundle: .nonetCore, locale: ControllerPresentation.textLocale))
        #expect(ControllerPresentation.trialEndedToast == ToastModel(
            title: ModelFixtures.text("試用期間が終了しました"),
            detail: ModelFixtures.text("メニューバーの Nonet から購入・登録できます"),
            style: .failure
        ))
    }

    @Test func beginnerFootnotesExplainChoosingCancellingAndPages() {
        let choose = ModelFixtures.text("指を滑らせて選ぶ")
        let pages = ModelFixtures.text("2本指のスワイプでページを切り替え")
        let release = ModelFixtures.text("先に指を離してから\(TriggerKey.rightCommand.localizedName)を離すとやめる")
        #expect(ControllerPresentation.beginnerFootnote(fireMode: .onTriggerRelease, activation: .triggerKey, trigger: .rightCommand, pageCount: 1)
            == [choose, release].joined(separator: " · "))
        #expect(ControllerPresentation.beginnerFootnote(fireMode: .onTriggerRelease, activation: .triggerKey, trigger: .rightCommand, pageCount: 3)
            == [choose, release, pages].joined(separator: " · "))
        #expect(ControllerPresentation.beginnerFootnote(fireMode: .onFingerLift, activation: .triggerKey, trigger: .rightCommand, pageCount: 1)
            == [choose, ModelFixtures.text("やめるときは指を置いたまま左の⇧を押す")].joined(separator: " · "))
        // 角の長押しは、実行のタイミングの設定に関係なく、滑らせずに離すとやめる
        #expect(ControllerPresentation.beginnerFootnote(fireMode: .onTriggerRelease, activation: .cornerHold, trigger: .rightCommand, pageCount: 2)
            == [choose, ModelFixtures.text("滑らせずに離すとやめる"), pages].joined(separator: " · "))
    }

    /// アプリのページの後ろにつなげたグローバルのページの位置（ページの点をそこで離す）
    @Test func globalPagesStartWhereTheProfileChanges() {
        #expect(ControllerPresentation.globalPagesStart(pages(frontmost: F.safari)) == 2)
        #expect(ControllerPresentation.globalPagesStart(pages(frontmost: nil)) == nil)
        #expect(ControllerPresentation.globalPagesStart([]) == nil)
        let model = ControllerPresentation.hudModel(pages: pages(frontmost: F.safari), page: 0, highlightedCell: nil, hint: "", banner: nil)
        #expect(model.globalPagesStart == 2)
    }

    @Test func toastsAndResultsCarryTheCell() {
        #expect(ControllerPresentation.successToast(F.newTab) == ToastModel(title: F.newTab.title, icon: F.newTab.icon, style: .success))
        #expect(ControllerPresentation.result(F.summarize, output: "文") == ResultModel(title: F.summarize.title, text: "文", icon: F.summarize.icon))
        #expect(ControllerPresentation.runningToast(F.summarize) == ToastModel(
            title: ModelFixtures.text("「\(F.summarize.title)」を実行中…"),
            icon: F.summarize.icon,
            style: .running
        ))
    }

    /// 失敗の見出しは、どのプロファイルのどのマスか。ページが複数のプロファイルならページも言う
    @Test func failureToastsSayWhereTheCellIs() {
        let onePage = ControllerTarget(cell: F.docs, profileName: ModelFixtures.globalName, address: CellAddress(page: 0, index: 8))
        #expect(ControllerPresentation.failureToast(onePage, message: "だめ") == ToastModel(
            title: ModelFixtures.text("\(ModelFixtures.globalName) › \(F.docs.title)"),
            detail: "だめ",
            icon: F.docs.icon,
            style: .failure
        ))
        let secondPage = ControllerTarget(cell: F.reload, profileName: "Safari", address: CellAddress(page: 1, index: 0), profilePageCount: 2)
        #expect(ControllerPresentation.failureTitle(secondPage) == String(
            localized: "\("Safari") › \(F.reload.title)（\(2)ページ目）",
            bundle: .nonetCore,
            locale: ControllerPresentation.textLocale
        ))
        // プロファイルの名前が分からなければ、マスの名前だけ
        #expect(ControllerPresentation.failureTitle(ControllerTarget(cell: F.newTab, profileName: "", address: CellAddress(page: 0, index: 0))) == F.newTab.title)
    }
}

@MainActor
@Suite struct ControllerSessionContextTests {
    typealias F = ControllerFixtures

    @Test func theSessionResolvesPagesForTheFrontmostApp() {
        let session = ControllerSession(configuration: F.configuration(), frontmostApp: F.safariApp)
        #expect(session.pages.map(\.profileName) == ["Safari", "Safari", ModelFixtures.globalName])
        // 中身のあるマスも渡す（空きマスの速押しで HUD を止めないため）
        let occupied: [Set<Int>] = [[0, 2, 4, 8], [0], [0, 8]]
        #expect(session.engineConfiguration == SessionConfiguration(hudDelay: 0.3, fireMode: .onTriggerRelease, pageCount: 3, occupiedCells: occupied))

        let other = ControllerSession(configuration: F.configuration(), frontmostApp: nil)
        #expect(other.pages.map(\.profileName) == [ModelFixtures.globalName])
    }

    @Test func targetsUseTheAddressInsideTheProfile() {
        let session = ControllerSession(configuration: F.configuration(), frontmostApp: F.safariApp)
        let safariID = session.pages[0].profileID
        let globalID = session.pages[2].profileID
        #expect(session.target(page: 0, cell: 2) == ControllerTarget(
            cell: F.closeTab,
            profileName: "Safari",
            address: CellAddress(page: 0, index: 2),
            profileID: safariID,
            profilePageCount: 2
        ))
        #expect(session.target(page: 1, cell: 0)?.address == CellAddress(page: 1, index: 0))
        #expect(session.target(page: 2, cell: 8) == ControllerTarget(
            cell: F.docs,
            profileName: ModelFixtures.globalName,
            address: CellAddress(page: 0, index: 8),
            profileID: globalID,
            profilePageCount: 1
        ))
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
        #expect(model.hint == ModelFixtures.text("指を離して実行"))
        #expect(model.banner == ControllerPresentation.trialEndedBanner)
        #expect(model.bannerStyle == .warning)
        #expect(model.highlightedIndex == 4)
        #expect(model.footnote == nil)
        #expect(model.scale == 1)
        #expect(model.globalPagesStart == 2)
        #expect(session.hudModel(page: 0, highlightedCell: nil, isPracticeMode: true, isTrialEnded: false).banner == nil)
    }

    /// 使い始めの案内・試用期間の残り日数（知らせの見た目）・HUD の大きさは、セッションで決めたとおりに出す
    @Test func theHUDModelCarriesTheGuidanceAndTheScale() {
        let settings = F.settings { $0.hudScale = .extraLarge }
        var session = ControllerSession(configuration: F.configuration(settings: settings), frontmostApp: F.safariApp)
        session.showsBeginnerHint = true
        session.trialReminderDays = 2
        let model = session.hudModel(page: 0, highlightedCell: nil, isPracticeMode: false, isTrialEnded: false)
        #expect(model.banner == ControllerPresentation.trialReminderBanner(daysLeft: 2))
        #expect(model.bannerStyle == .info)
        #expect(model.footnote == ControllerPresentation.beginnerFootnote(fireMode: .onTriggerRelease, activation: .triggerKey, trigger: .rightOption, pageCount: 3))
        #expect(model.scale == 1.5)
        // 試用期間が終わっていれば、終わった帯を出す
        #expect(session.hudModel(page: 0, highlightedCell: nil, isPracticeMode: false, isTrialEnded: true).banner == ControllerPresentation.trialEndedBanner)
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
    private let scheduler = ControllerFakeScheduler()

    @Test func jobsRunOneAtATimeInOrder() async {
        let queue = ControllerExecutionQueue(scheduler: scheduler)
        var log: [String] = []
        for name in ["a", "b", "c"] {
            queue.enqueue { _ in
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
        let queue = ControllerExecutionQueue(scheduler: scheduler)
        let first = queue.enqueue { _ in 1 }
        let second = queue.enqueue { _ in "二" }
        #expect(await first.value == 1)
        #expect(await second.value == "二")
    }

    @Test func waitUntilIdleIncludesJobsAddedWhileWaiting() async {
        let queue = ControllerExecutionQueue(scheduler: scheduler)
        var done: [Int] = []
        queue.enqueue { _ in
            await Task.yield()
            done.append(1)
            queue.enqueue { _ in
                await Task.yield()
                done.append(2)
            }
        }
        await queue.waitUntilIdle()
        #expect(done == [1, 2])
    }

    @Test func anIdleQueueReturnsAtOnce() async {
        await ControllerExecutionQueue(scheduler: scheduler).waitUntilIdle()
    }

    @Test func aJobThatPassesItsTurnLetsTheNextStartWhileItKeepsRunning() async {
        let queue = ControllerExecutionQueue(scheduler: scheduler)
        let latch = ControllerFakeLatch()
        var log: [String] = []
        queue.enqueue { turn in
            log.append("a>")
            turn.pass()
            await latch.wait()
            log.append("<a")
        }
        queue.enqueue { _ in
            log.append("b>")
            log.append("<b")
        }
        await controllerWaitUntil { log.contains("<b") }
        #expect(log == ["a>", "b>", "<b"])

        // 順番を譲った実行も、終わるまでは「実行中」
        var isIdle = false
        let idle = Task {
            await queue.waitUntilIdle()
            isIdle = true
        }
        await controllerWaitUntil { isIdle }
        #expect(!isIdle)
        latch.open()
        await idle.value
        #expect(log == ["a>", "b>", "<b", "<a"])
    }

    @Test func aTurnPassesWhenItsTimeRunsOut() async {
        let queue = ControllerExecutionQueue(scheduler: scheduler)
        let latch = ControllerFakeLatch()
        var started: [String] = []
        queue.enqueue { turn in
            started.append("a")
            turn.pass(after: 1)
            await latch.wait()
        }
        queue.enqueue { _ in
            started.append("b")
        }
        await controllerWaitUntil { started.count > 1 }
        #expect(started == ["a"])
        scheduler.advance(by: 0.9)
        await controllerWaitUntil { started.count > 1 }
        #expect(started == ["a"])
        scheduler.advance(by: 0.1)
        await controllerWaitUntil { started.count > 1 }
        #expect(started == ["a", "b"])
        latch.open()
        await queue.waitUntilIdle()
    }

    @Test func aLaterDeadlineReplacesTheEarlierOne() async {
        let queue = ControllerExecutionQueue(scheduler: scheduler)
        let latch = ControllerFakeLatch()
        var started: [String] = []
        queue.enqueue { turn in
            started.append("a")
            turn.pass(after: 5)
            turn.pass(after: 1)
            await latch.wait()
        }
        queue.enqueue { _ in
            started.append("b")
        }
        await controllerWaitUntil { started == ["a"] }
        scheduler.advance(by: 1)
        await controllerWaitUntil { started.count > 1 }
        #expect(started == ["a", "b"])
        #expect(scheduler.pending.isEmpty)
        latch.open()
        await queue.waitUntilIdle()
    }

    @Test func finishingCancelsTheDeadline() async {
        let queue = ControllerExecutionQueue(scheduler: scheduler)
        queue.enqueue { turn in
            turn.pass(after: 5)
        }
        await queue.waitUntilIdle()
        #expect(scheduler.pending.isEmpty)
    }

    @Test func jobsStillStartInTheOrderTheyWereAddedWhenTurnsPassEarly() async {
        let queue = ControllerExecutionQueue(scheduler: scheduler)
        let latch = ControllerFakeLatch()
        var started: [String] = []
        queue.enqueue { turn in
            started.append("a")
            turn.pass(after: 2)
            await latch.wait()
        }
        queue.enqueue { turn in
            started.append("b")
            turn.pass()
            await latch.wait()
        }
        queue.enqueue { _ in
            started.append("c")
        }
        await controllerWaitUntil { started.count > 1 }
        #expect(started == ["a"])
        scheduler.advance(by: 2)
        await controllerWaitUntil { started.count == 3 }
        #expect(started == ["a", "b", "c"])
        latch.open()
        await queue.waitUntilIdle()
    }
}

@Suite struct ControllerExecutionPolicyTests {
    typealias P = ControllerExecutionPolicy

    private let background = Action.script(ScriptAction(source: "make", runMode: .background))
    private let terminal = Action.script(ScriptAction(source: "claude", runMode: .terminal))
    private let shortcut = Action.shortcut(ShortcutAction(name: "日記"))
    private let showResult = Action.ai(AIAction(prompt: "要約して", output: .showResult))
    private let replace = Action.ai(AIAction(prompt: "直して", output: .replaceSelection))
    private let copy = Action.ai(AIAction(prompt: "訳して", output: .copyToClipboard))
    private let keystroke = Action.keystroke(.key("w", [.command]))
    private let launch = Action.launchApp(LaunchAppAction(app: ControllerFixtures.notes))
    private let url = Action.openURL(URLAction(url: "https://example.com"))
    private let menu = Action.menuItem(MenuItemAction(path: ["ファイル", "保存"]))

    @Test func scriptsShortcutsAndAIDoNotHoldLaterExecutionsUntilTheyFinish() {
        for action in [background, shortcut, showResult, replace, copy] {
            #expect(P.isLongRunning(action))
            #expect(P.hold(for: action) == P.longRunningHold)
        }
        for action in [terminal, keystroke, launch, url, menu] {
            #expect(!P.isLongRunning(action))
            #expect(P.hold(for: action) == P.holdLimit)
        }
        #expect(P.longRunningHold < P.holdLimit)
    }

    @Test func onlyKeysAndPastingGoToTheFrontmostApp() {
        #expect(P.sendsInputToFrontmostApp(keystroke))
        #expect(P.sendsInputToFrontmostApp(replace))
        for action in [background, terminal, shortcut, showResult, copy, launch, url, menu] {
            #expect(!P.sendsInputToFrontmostApp(action))
        }
    }

    @Test func launchingAppsAndOpeningURLsDoNotDependOnTheFrontmostApp() {
        #expect(!P.dependsOnFrontmostApp(launch))
        #expect(!P.dependsOnFrontmostApp(url))
        for action in [background, terminal, shortcut, showResult, replace, copy, keystroke, menu] {
            #expect(P.dependsOnFrontmostApp(action))
        }
    }
}
