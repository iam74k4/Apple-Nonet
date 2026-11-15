// 担当: engine。実行の順番: 頼まれた順に始め、キー入力などは前の実行が終わるまで待つが、
// 長く掛かるアクション（裏のスクリプト・ショートカット・AI）は後のマスを終わるまで待たせない
import Foundation
import Testing
@testable import NonetCore

@MainActor
@Suite struct ControllerExecutionOrderTests {
    typealias F = ControllerFixtures
    typealias P = ControllerExecutionPolicy

    nonisolated static let build = Cell(title: "ビルド", icon: .symbol("hammer"), action: .script(ScriptAction(source: "make", runMode: .background)))
    nonisolated static let longRunning: [Action] = [
        build.action,
        .shortcut(ShortcutAction(name: "日記", passSelectedText: true)),
        .ai(AIAction(prompt: "要約して", output: .showResult)),
        .ai(AIAction(prompt: "直して", output: .replaceSelection)),
        .file(FileAction(operation: .duplicate)),
    ]
    nonisolated static let serial: [Action] = [
        .keystroke(.key("s", [.command])),
        .menuItem(MenuItemAction(path: ["ファイル", "保存"])),
        .launchApp(LaunchAppAction(app: F.notes)),
        .openURL(URLAction(url: "https://example.com")),
        .script(ScriptAction(source: "claude", runMode: .terminal)),
        .file(FileAction(operation: .rename)),
        .file(FileAction(operation: .trash)),
    ]

    /// Safari の1ページ目: [first, 新しいタブ, タブを閉じる, 空…]
    private func configuration(first: Cell) -> NonetConfiguration {
        let global = Profile(kind: .global, pages: [Page(cells: [F.docs])])
        let safari = Profile(kind: .app(F.safari), pages: [Page(cells: [first, F.newTab, F.closeTab])])
        return NonetConfiguration(settings: GlobalSettings(), profiles: [global, safari]).validated()
    }

    /// 1つ目のマスが action。その実行は release まで終わらない
    private func harness(first action: Action) throws -> ControllerHarness {
        let h = try ControllerHarness(configuration: configuration(first: Cell(title: "先", icon: .symbol("1.circle"), action: action)))
        h.performer.holdsAction = { $0 == action }
        return h
    }

    // MARK: 長く掛かるアクション

    @Test func aRunningBackgroundScriptDoesNotHoldBackALaterTap() async throws {
        let h = try ControllerHarness(configuration: configuration(first: Self.build))
        h.performer.holdsAction = { $0 == Self.build.action }
        h.start()
        h.run(0)
        await h.waitUntil { h.performer.calls.count == 1 }
        // 数秒後に、別のセッションで ⌘T を速押しする（ビルドはまだ終わっていない）
        h.advance(3)
        h.run(1)
        await h.waitUntil { h.performer.finished.count == 1 }

        #expect(h.performer.actions == [Self.build.action, F.newTab.action])
        #expect(h.performer.finished == [F.newTab.action])
        #expect(h.performer.calls.last?.frontmostApp == F.safariApp)
        // ビルドが終わらないうちは「実行中」のトーストを出したまま（後のマスは HUD から実行したので、成功のトーストは出さない）
        let running = ControllerPresentation.runningToast(Self.build, stopHint: true)
        #expect(h.hud.toasts.map(\.title) == [running.title])
        #expect(h.controller.lastExecution?.cellTitle == F.newTab.title)

        // ビルドの結果は、終わったときに知らせる
        h.performer.release(Self.build.action)
        await h.settle()
        #expect(h.hud.toasts.map(\.title) == [running.title, Self.build.title])
        #expect(h.controller.lastExecution?.cellTitle == Self.build.title)
        #expect(h.controller.lastExecution?.succeeded == true)
    }

    @Test(arguments: longRunning)
    func aLongRunningActionHoldsLaterTapsOnlyBriefly(_ action: Action) async throws {
        let h = try harness(first: action)
        h.start()
        h.open()
        h.choose(0)
        await h.waitUntil { h.performer.calls.count == 1 }
        h.choose(1)
        // 始めに前面アプリの選択などを読むので、少しの間は後のキー入力を送らない
        await h.waitUntil { h.performer.calls.count > 1 }
        #expect(h.performer.actions == [action])
        h.advance(P.longRunningHold)
        await h.waitUntil { h.performer.calls.count == 2 }
        #expect(h.performer.actions == [action, F.newTab.action])
        #expect(h.performer.waitingActions == [action])
        h.closeIfOpen()

        h.performer.release(action)
        await h.settle()
        #expect(h.performer.finished == [F.newTab.action, action])
    }

    /// 長く掛かるマスが文脈を読み終えたと知らせたら、上限（longRunningHold）を待たずに、始めてから
    /// longRunningMinimumHold で後のマスを始める。知らせる口を渡すのは長く掛かるマスだけ（ほかは終わるまで順番を持つ）
    @Test(arguments: longRunning)
    func aLongRunningActionPassesItsTurnOnceItHasReadTheContext(_ action: Action) async throws {
        let h = try harness(first: action)
        h.performer.readsContextFirst = true
        h.start()
        h.open()
        h.choose(0)
        await h.waitUntil { h.performer.calls.count == 1 }
        h.choose(1)
        await h.waitUntil { h.performer.calls.count > 1 }
        #expect(h.performer.actions == [action])
        h.advance(P.longRunningMinimumHold)
        await h.waitUntil { h.performer.calls.count == 2 }
        #expect(h.performer.actions == [action, F.newTab.action])
        #expect(h.performer.waitingActions == [action])
        #expect(h.performer.calls.map(\.canReportContextRead) == [true, false])
        h.closeIfOpen()

        h.performer.release(action)
        await h.settle()
        #expect(h.performer.finished == [F.newTab.action, action])
    }

    @Test func aLongRunningActionThatFinishesQuicklyDoesNotHoldAnything() async throws {
        let h = try ControllerHarness(configuration: configuration(first: Self.build))
        h.start()
        h.open()
        h.choose(0)
        h.choose(1)
        await h.settle()
        #expect(h.performer.actions == [Self.build.action, F.newTab.action])
        #expect(h.scheduler.pending.allSatisfy { $0.delay != P.longRunningHold })
    }

    @Test func aTestRunIsNotHeldBackByARunningBackgroundScript() async throws {
        let h = try ControllerHarness(configuration: configuration(first: Self.build))
        h.performer.holdsAction = { $0 == Self.build.action }
        h.start()
        h.run(0)
        await h.waitUntil { h.performer.calls.count == 1 }
        h.advance(P.longRunningHold)

        let globalID = h.controller.configuration.globalProfile.id
        var record: ExecutionRecord?
        let run = Task {
            record = await h.controller.testRun(F.docs, profileID: globalID)
        }
        await h.waitUntil { record != nil }
        #expect(record?.succeeded == true)
        #expect(h.performer.actions == [Self.build.action, F.docs.action])
        #expect(h.performer.waitingActions == [Self.build.action])

        // 失敗しても止まったままにならないよう、ビルドを終わらせてから待つ
        h.performer.release(Self.build.action)
        await run.value
        await h.settle()
    }

    @Test func aLongRunningFailureIsShownWhenItFinishes() async throws {
        let h = try ControllerHarness(configuration: configuration(first: Self.build))
        h.performer.holdsAction = { $0 == Self.build.action }
        h.performer.failure = { $0 == Self.build.action ? NonetError.timedOut : nil }
        h.start()
        h.run(0)
        await h.waitUntil { h.performer.calls.count == 1 }
        h.advance(P.longRunningHold)
        h.run(1)
        await h.waitUntil { h.performer.finished.count == 1 }
        h.performer.release(Self.build.action)
        await h.settle()

        let message = try #require(NonetError.timedOut.errorDescription)
        let title = ControllerPresentation.failureTitle(ControllerTarget(cell: Self.build, profileName: "Safari", address: CellAddress(page: 0, index: 0)))
        #expect(h.hud.toasts == [
            ControllerPresentation.runningToast(Self.build, stopHint: true),
            ToastModel(title: title, detail: message, icon: Self.build.icon, style: .failure),
        ])
        let record = try #require(h.controller.lastExecution)
        #expect(record.cellTitle == Self.build.title)
        #expect(!record.succeeded)
        #expect(record.message == message)
        #expect(record.address == CellAddress(page: 0, index: 0))
    }

    @Test func aResultArrivesWhenTheModelFinishes() async throws {
        let summarize = Cell(title: "要約", icon: .symbol("sparkles"), action: .ai(AIAction(prompt: "要約して", output: .showResult)))
        let h = try ControllerHarness(configuration: configuration(first: summarize))
        h.performer.holdsAction = { $0 == summarize.action }
        h.performer.output = { $0 == summarize.action ? "要約です" : nil }
        h.start()
        h.run(0)
        await h.waitUntil { h.performer.calls.count == 1 }
        h.advance(P.longRunningHold)
        h.run(2)
        await h.waitUntil { h.performer.finished.count == 1 }
        #expect(h.hud.results.isEmpty)

        h.performer.release(summarize.action)
        await h.settle()
        #expect(h.hud.results == [ResultModel(title: summarize.title, text: "要約です", icon: summarize.icon)])
        #expect(h.hud.toasts.map(\.title) == [ControllerPresentation.runningToast(summarize).title])
    }

    // MARK: 1つずつ実行するアクション

    @Test(arguments: serial)
    func otherActionsHoldLaterTapsUntilTheyFinish(_ action: Action) async throws {
        let h = try harness(first: action)
        h.start()
        h.run(0)
        await h.waitUntil { h.performer.calls.count == 1 }
        h.advance(P.longRunningHold)
        h.run(1)
        await h.waitUntil { h.performer.calls.count > 1 }
        #expect(h.performer.actions == [action])

        h.performer.release(action)
        await h.waitUntil { h.performer.calls.count == 2 }
        await h.settle()
        #expect(h.performer.actions == [action, F.newTab.action])
        #expect(h.performer.maxRunning == 1)
    }

    @Test func aStuckActionHoldsLaterTapsOnlyUpToTheLimit() async throws {
        let h = try harness(first: .keystroke(.key("s", [.command])))
        h.start()
        h.run(0)
        await h.waitUntil { h.performer.calls.count == 1 }
        let started = h.scheduler.now
        h.run(1)
        h.scheduler.advance(to: started + P.holdLimit - 0.01)
        await h.waitUntil { h.performer.calls.count > 1 }
        #expect(h.performer.calls.count == 1)

        h.scheduler.advance(to: started + P.holdLimit)
        await h.waitUntil { h.performer.calls.count == 2 }
        #expect(h.performer.actions.last == F.newTab.action)
        h.performer.releaseOne()
        await h.settle()
    }
}
