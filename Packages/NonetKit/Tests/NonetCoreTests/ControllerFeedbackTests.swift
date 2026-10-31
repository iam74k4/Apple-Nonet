// 担当: engine。実行の知らせ（最近の実行・実行中のトースト・触覚）と、
// HUD の使い始めの案内・試用期間の知らせ・HUD の大きさ・トラックパッドに触れているかの知らせ
import Foundation
import Testing
@testable import NonetCore

@MainActor
@Suite struct ControllerFeedbackTests {
    typealias F = ControllerFixtures

    nonisolated static let build = Cell(title: "ビルド", icon: .symbol("hammer"), action: .script(ScriptAction(source: "make", runMode: .background)))

    /// Safari の1ページ目: [ビルド, 新しいタブ, タブを閉じる, 空…]
    private func buildConfiguration(_ transform: (inout GlobalSettings) -> Void = { _ in }) -> NonetConfiguration {
        let global = Profile(kind: .global, pages: [Page(cells: [F.docs])])
        let safari = Profile(kind: .app(F.safari), pages: [Page(cells: [Self.build, F.newTab, F.closeTab])])
        return NonetConfiguration(settings: F.settings(transform), profiles: [global, safari]).validated()
    }

    /// 開いて、cell で止めてから離して実行する
    private func runFromTheHUD(_ h: ControllerHarness, cell: Int) {
        h.run(cell, dwell: 0.4)
    }

    // MARK: 最近の実行

    @Test func recentExecutionsKeepTheLastTenNewestFirst() async throws {
        let h = try ControllerHarness()
        h.performer.failure = { $0 == F.newTab.action ? NonetError.timedOut : nil }
        h.start()
        for index in 0..<12 {
            h.run(index.isMultiple(of: 2) ? 2 : 0)
        }
        await h.settle()

        let recent = h.controller.recentExecutions
        #expect(recent.count == NonetController.recentExecutionLimit)
        #expect(recent.first == h.controller.lastExecution)
        // 新しい順。失敗も残す
        #expect(recent.map(\.cellTitle) == Array(repeating: [F.newTab.title, F.closeTab.title], count: 5).flatMap { $0 })
        #expect(recent.filter { !$0.succeeded }.allSatisfy { $0.message == NonetError.timedOut.errorDescription })
        // 設定でそのマスを開けるよう、プロファイルを持つ
        let safariID = try h.profileID(F.safari)
        #expect(recent.allSatisfy { $0.profileID == safariID })
    }

    /// 実行しなかったもの（開いている間に Nonet のウィンドウがキーになった）も残す
    @Test func refusedRunsAreRecentToo() async throws {
        let h = try ControllerHarness()
        h.start()
        h.open()
        h.frontmost.isOwnWindowKey = true
        h.choose(2)
        await h.settle()
        #expect(h.controller.recentExecutions.map(\.succeeded) == [false])
    }

    // MARK: 実行中のトースト

    @Test func aLongRunningCellShowsARunningToastUntilItFinishes() async throws {
        let h = try ControllerHarness(configuration: buildConfiguration())
        h.performer.holdsAction = { $0 == Self.build.action }
        h.start()
        runFromTheHUD(h, cell: 0)
        await h.waitUntil { h.performer.calls.count == 1 }
        // 0.5秒で終わらなければ、終わるまで出す
        h.advance(NonetController.runningToastDelay - 0.41)
        #expect(h.hud.toasts.isEmpty)
        h.advance(0.01 + 0.4)
        #expect(h.hud.toasts == [ControllerPresentation.runningToast(Self.build)])
        h.advance(30)
        #expect(h.hud.toasts.count == 1)

        // 終わったら、実行を知らせる設定なら成功のトーストで置き換える（HUD から実行しても）
        h.performer.release(Self.build.action)
        await h.settle()
        #expect(h.hud.toasts == [
            ControllerPresentation.runningToast(Self.build),
            ControllerPresentation.successToast(Self.build),
        ])
        #expect(h.hud.toastHides == 0)
    }

    @Test func theRunningToastIsHiddenWhenThereIsNothingElseToShow() async throws {
        let h = try ControllerHarness(configuration: buildConfiguration { $0.showExecutionToast = false })
        h.performer.holdsAction = { $0 == Self.build.action }
        h.start()
        h.run(0)
        await h.waitUntil { h.performer.calls.count == 1 }
        h.advance(1)
        #expect(h.hud.toasts.map(\.style) == [.running])
        h.performer.release(Self.build.action)
        await h.settle()
        #expect(h.hud.toasts.map(\.style) == [.running])
        #expect(h.hud.toastHides == 1)
    }

    @Test func aFailureReplacesTheRunningToast() async throws {
        let h = try ControllerHarness(configuration: buildConfiguration())
        h.performer.holdsAction = { $0 == Self.build.action }
        h.performer.failure = { $0 == Self.build.action ? NonetError.timedOut : nil }
        h.start()
        h.run(0)
        await h.waitUntil { h.performer.calls.count == 1 }
        h.advance(1)
        h.performer.release(Self.build.action)
        await h.settle()
        #expect(h.hud.toasts.map(\.style) == [.running, .failure])
        #expect(h.hud.toastHides == 0)
    }

    @Test func aResultPanelHidesTheRunningToast() async throws {
        let h = try ControllerHarness()
        h.performer.holdsAction = { $0 == F.summarize.action }
        h.performer.output = { $0 == F.summarize.action ? "要約です" : nil }
        h.start()
        h.run(4)
        await h.waitUntil { h.performer.calls.count == 1 }
        h.advance(1)
        h.performer.release(F.summarize.action)
        await h.settle()
        #expect(h.hud.toasts.map(\.style) == [.running])
        #expect(h.hud.toastHides == 1)
        #expect(h.hud.results.count == 1)
    }

    /// すぐに終わった長く掛かるマスは「実行中」も成功も出さない（HUD から実行したので、見れば分かる）
    @Test func aQuickLongRunningCellShowsNoRunningToast() async throws {
        let h = try ControllerHarness(configuration: buildConfiguration())
        h.start()
        h.run(0)
        await h.settle()
        h.advance(1)
        #expect(h.hud.toasts.isEmpty)
        #expect(h.hud.toastHides == 0)
    }

    @Test func keystrokesNeverShowARunningToast() async throws {
        let h = try ControllerHarness(configuration: buildConfiguration { $0.showExecutionToast = false })
        h.performer.holdsAction = { $0 == F.newTab.action }
        h.start()
        h.run(1)
        await h.waitUntil { h.performer.calls.count == 1 }
        h.advance(1)
        #expect(h.hud.toasts.isEmpty)
        h.performer.release(F.newTab.action)
        await h.settle()
    }

    // MARK: 触覚

    /// 実行を断ったとき（開いている間に Nonet のウィンドウがキーになった）は、execute の代わりに rejected
    @Test func aRefusedRunBuzzesInsteadOfTheExecuteHaptic() async throws {
        let h = try ControllerHarness()
        h.start()
        h.open()
        h.advance(0.05)
        h.touch(on: 2)
        h.advance(0.3)
        h.frontmost.isOwnWindowKey = true
        h.lift()
        await h.settle()
        #expect(h.haptics.events == [.activation, .boundary, .rejected])
        #expect(h.performer.calls.isEmpty)
    }

    // MARK: トラックパッドに触れているか

    @Test func theKeyboardMonitorIsToldWhetherTheTrackpadIsTouched() throws {
        let h = try ControllerHarness()
        h.start()
        // モニターを始めたときに、まだ触れていないことを知らせる
        #expect(h.keyboard.trackpadTouchReports == [false])
        h.touch(on: 4)
        h.touch(on: 5)
        h.lift()
        #expect(h.keyboard.trackpadTouchReports == [false, true, false])
    }

    // MARK: 使い始めの案内

    @Test func beginnersSeeAFootnoteForTheFirstHUDSessions() async throws {
        let h = try ControllerHarness()
        h.guidance.hudSessionCount = HUDGuidance.beginnerSessionLimit - 2
        h.start()
        let footnote = ControllerPresentation.beginnerFootnote(pageCount: 3)

        h.open()
        #expect(h.hud.current?.footnote == footnote)
        // HUD の中身が変わっても、1つのセッションでは1回だけ数える
        h.touch(on: 4)
        h.touch(on: 5)
        #expect(h.hud.current?.footnote == footnote)
        #expect(h.guidance.hudSessionCount == HUDGuidance.beginnerSessionLimit - 1)
        h.closeIfOpen()

        // 開かなかった（試しに上の縁から横へ滑らせた）ものは数えない
        h.touch(x: 0.3, y: ControllerHarness.edgeY)
        h.advance(0.05)
        h.touch(x: 0.5, y: ControllerHarness.edgeY)
        h.lift()
        #expect(h.guidance.hudSessionCount == HUDGuidance.beginnerSessionLimit - 1)

        h.open()
        #expect(h.hud.current?.footnote == footnote)
        #expect(h.guidance.hudSessionCount == HUDGuidance.beginnerSessionLimit)
        h.closeIfOpen()

        // 出し終えたら出さず、もう数えない
        h.open()
        #expect(h.hud.isVisible)
        #expect(h.hud.current?.footnote == nil)
        #expect(h.guidance.hudSessionCount == HUDGuidance.beginnerSessionLimit)
        h.closeIfOpen()
        await h.settle()
    }

    // MARK: 試用期間の残り日数

    @Test func theLastDaysOfTheTrialAreShownOnceADay() throws {
        let h = try ControllerHarness(trialDaysUsed: Double(LicenseManager.trialDays - HUDGuidance.trialReminderDays) + 0.5)
        let today = Date(timeIntervalSinceReferenceDate: 815_000_000)
        h.controller.currentDate = { today }
        h.start()
        #expect(h.license.entitlement == .trial(daysLeft: HUDGuidance.trialReminderDays))

        h.open()
        #expect(h.hud.current?.banner == ControllerPresentation.trialReminderBanner(daysLeft: HUDGuidance.trialReminderDays))
        #expect(h.hud.current?.bannerStyle == .info)
        #expect(h.guidance.lastTrialReminder == today)
        // セッションの間は出したまま
        h.touch(on: 4)
        #expect(h.hud.current?.banner != nil)
        h.advance(0.3)
        h.closeIfOpen()

        // 同じ日はもう出さない
        h.open()
        #expect(h.hud.current?.banner == nil)
        h.closeIfOpen()

        // 次の日はまた出す
        h.controller.currentDate = { today.addingTimeInterval(86_400) }
        h.open()
        #expect(h.hud.current?.bannerStyle == .info)
        #expect(h.hud.current?.banner != nil)
        h.closeIfOpen()
    }

    @Test func theTrialIsNotMentionedBeforeTheLastDays() throws {
        let h = try ControllerHarness(trialDaysUsed: Double(LicenseManager.trialDays - HUDGuidance.trialReminderDays) - 1)
        h.start()
        h.open()
        #expect(h.hud.isVisible)
        #expect(h.hud.current?.banner == nil)
        #expect(h.guidance.lastTrialReminder == nil)
    }

    @Test func aLicenseNeverShowsTheTrialBanner() throws {
        let h = try ControllerHarness(licensed: true)
        h.start()
        h.open()
        #expect(h.hud.current?.banner == nil)
    }

    // MARK: HUD の大きさ

    @Test func theHUDAndToastsUseTheChosenSize() async throws {
        let h = try ControllerHarness(configuration: F.configuration(settings: F.settings { $0.hudScale = .large }))
        h.performer.failure = { _ in NonetError.timedOut }
        h.start()
        h.open()
        #expect(h.hud.current?.scale == HUDScale.large.factor)
        h.closeIfOpen()
        h.run(2)
        await h.settle()
        #expect(h.hud.toasts.map(\.scale) == [HUDScale.large.factor])
    }
}
