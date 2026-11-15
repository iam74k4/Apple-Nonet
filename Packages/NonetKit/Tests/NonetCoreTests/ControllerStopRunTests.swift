// 担当: engine。実行中のマスをメニューから止める・失敗の理由の全文を結果のパネルに出す・「ターミナルで実行」のアプリを渡す
import Foundation
import Testing
@testable import NonetCore

@MainActor
@Suite struct ControllerStopRunTests {
    typealias F = ControllerFixtures

    nonisolated static let build = Cell(title: "ビルド", icon: .symbol("hammer"), action: .script(ScriptAction(source: "make", runMode: .background)))
    nonisolated static let console = Cell(title: "Claude", icon: .symbol("terminal"), action: .script(ScriptAction(source: "claude", runMode: .terminal)))

    /// Safari の1ページ目: [first, 新しいタブ, タブを閉じる]
    private func configuration(first: Cell, settings: GlobalSettings = GlobalSettings()) -> NonetConfiguration {
        let global = Profile(kind: .global, pages: [Page(cells: [F.docs])])
        let safari = Profile(kind: .app(F.safari), pages: [Page(cells: [first, F.newTab, F.closeTab])])
        return NonetConfiguration(settings: settings, profiles: [global, safari]).validated()
    }

    // MARK: 止める

    /// 裏で実行するスクリプトは、実行の間メニューに出し、止めると実行の Task を取り消して「止めました」と記録する（失敗にしない）
    @Test func aRunningScriptCanBeStopped() async throws {
        let h = try ControllerHarness(configuration: configuration(first: Self.build))
        h.performer.holdsAction = { $0 == Self.build.action }
        h.start()
        h.run(0)
        await h.waitUntil { h.performer.waitingCount == 1 }
        #expect(h.controller.runningActions.map(\.cellTitle) == [Self.build.title])
        #expect(h.controller.runningActions.map(\.profileName) == ["Safari"])
        h.advance(NonetController.runningToastDelay)

        let id = try #require(h.controller.runningActions.first?.id)
        h.controller.stopRunningAction(id: id)
        #expect(h.controller.runningActions.isEmpty)
        // 偽物は取り消しでは終わらないので、終わらせる（本物はプロセスを止めて CancellationError を投げる）
        h.performer.release(Self.build.action)
        await h.settle()

        #expect(h.performer.finishedCancelled == [true])
        let record = try #require(h.controller.lastExecution)
        #expect(record.wasStopped)
        #expect(!record.succeeded)
        #expect(record.message == ControllerPresentation.stoppedMessage)
        #expect(h.controller.recentExecutions.first == record)
        #expect(h.hud.toasts.last == ControllerPresentation.stoppedToast(Self.build))
        #expect(!h.hud.toasts.contains { $0.style == .failure })
    }

    /// 取り消しで投げても（本物のスクリプト）、止めたものとして記録する
    @Test func aStoppedRunThatThrowsIsStillStopped() async throws {
        let h = try ControllerHarness(configuration: configuration(first: Self.build))
        h.performer.holdsAction = { $0 == Self.build.action }
        h.performer.failure = { $0 == Self.build.action ? CancellationError() : nil }
        h.start()
        h.run(0)
        await h.waitUntil { h.performer.waitingCount == 1 }
        h.controller.stopRunningAction(id: try #require(h.controller.runningActions.first?.id))
        h.performer.release(Self.build.action)
        await h.settle()
        #expect(h.controller.lastExecution?.wasStopped == true)
        #expect(h.hud.toasts == [ControllerPresentation.stoppedToast(Self.build)])
    }

    /// 終わったら一覧から消え、止めても何も起きない
    @Test func aFinishedRunLeavesTheList() async throws {
        let h = try ControllerHarness(configuration: configuration(first: Self.build))
        h.performer.holdsAction = { $0 == Self.build.action }
        h.start()
        h.run(0)
        await h.waitUntil { h.performer.waitingCount == 1 }
        let id = try #require(h.controller.runningActions.first?.id)
        h.performer.release(Self.build.action)
        await h.settle()
        #expect(h.controller.runningActions.isEmpty)
        h.controller.stopRunningAction(id: id)
        #expect(h.controller.lastExecution?.succeeded == true)
        #expect(h.controller.lastExecution?.wasStopped == false)
    }

    /// 止められないもの（キー入力・ターミナルで実行・ファイルの複製）は出さない
    @Test func onlyStoppableActionsAreListed() async throws {
        typealias P = ControllerExecutionPolicy
        #expect(P.canStop(Self.build.action))
        #expect(P.canStop(.shortcut(ShortcutAction(name: "日記"))))
        #expect(P.canStop(F.summarize.action))
        #expect(!P.canStop(Self.console.action))
        #expect(!P.canStop(F.newTab.action))
        #expect(!P.canStop(.file(FileAction(operation: .duplicate))))

        let h = try ControllerHarness(configuration: configuration(first: Self.build))
        h.performer.holdsAction = { $0 == F.newTab.action }
        h.start()
        h.run(1)
        await h.waitUntil { h.performer.waitingCount == 1 }
        #expect(h.controller.runningActions.isEmpty)
        h.performer.releaseOne()
        await h.settle()
    }

    // MARK: 失敗の理由の全文

    /// 最近の実行で選んだ失敗は、理由の全文を結果のパネルに出す。成功・止めたものは出さない
    @Test func aFailedRunShowsItsWholeReason() async throws {
        let reason = "スクリプトが失敗しました\n1行目\n2行目\n3行目"
        let h = try ControllerHarness()
        h.performer.failure = { $0 == F.closeTab.action ? NonetError.actionFailed(reason) : nil }
        h.start()
        h.run(2)
        h.run(0)
        await h.settle()
        let failed = try #require(h.controller.recentExecutions.last)
        #expect(!failed.succeeded)
        h.controller.showFailureDetails(failed)
        #expect(h.hud.results == [ControllerPresentation.failureResult(failed, message: reason)])
        #expect(h.hud.results.first?.text == reason)
        #expect(h.hud.results.first?.title.contains(F.closeTab.title) == true)

        h.controller.showFailureDetails(try #require(h.controller.recentExecutions.first))
        var stopped = failed
        stopped.wasStopped = true
        h.controller.showFailureDetails(stopped)
        #expect(h.hud.results.count == 1)
    }

    // MARK: ターミナルで実行

    /// 「ターミナルで実行」のアプリは、設定のものを実行に渡す（HUD からも、テスト実行からも）
    @Test func theChosenTerminalAppIsPassedToTheAction() async throws {
        let settings = F.settings { $0.terminalApp = .iTerm2 }
        let h = try ControllerHarness(configuration: configuration(first: Self.console, settings: settings))
        h.start()
        h.run(0)
        await h.settle()
        #expect(h.performer.calls.map(\.terminalApp) == [.iTerm2])

        let safariID = try h.profileID(F.safari)
        let run = Task { await h.controller.testRun(Self.console, profileID: safariID) }
        // テスト実行は、先にアプリを前面に出して少し待つ
        await h.waitUntil { h.scheduler.hasPending(delay: NonetController.activationDelay) }
        h.advance(NonetController.activationDelay)
        _ = await run.value
        #expect(h.performer.calls.last?.action == Self.console.action)
        #expect(h.performer.calls.last?.terminalApp == .iTerm2)
    }
}
