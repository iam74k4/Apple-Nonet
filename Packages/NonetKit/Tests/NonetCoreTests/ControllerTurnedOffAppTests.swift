// 担当: engine（ui-settings が足した確かめ）。「このアプリでは Nonet を使わない」（ProfileMode.off）のアプリが前面のとき、
// 強く押し込んでも9マスを開かず（クリックも預からず）、ポインタも止めないか。既定: 前面は Safari
import Foundation
import Testing
@testable import NonetCore

@MainActor
@Suite struct ControllerTurnedOffAppTests {
    typealias F = ControllerFixtures

    /// Safari を「使わない」にした設定
    private func harness(frontmost: RunningAppInfo? = F.safariApp, trialEnded: Bool = false) throws -> ControllerHarness {
        var configuration = F.configuration()
        configuration.setAppMode(.off, for: F.safari)
        return try ControllerHarness(configuration: configuration, trialEnded: trialEnded, frontmost: frontmost)
    }

    private func expectNoSession(_ h: ControllerHarness) {
        #expect(!h.keyboard.isSuppressingPointer)
        #expect(h.keyboard.suppressionChanges.isEmpty)
        #expect(h.hud.shown.isEmpty)
        #expect(h.haptics.plays.isEmpty)
        #expect(h.performer.calls.isEmpty)
        #expect(h.controller.lastExecution == nil)
    }

    @Test func forcePressingDoesNothingInAnAppWhereNonetIsOff() async throws {
        let h = try harness()
        h.start()
        h.run(2)
        h.open()
        h.advance(1)
        h.touch(on: 4)
        h.advance(0.2)
        h.lift()
        await h.settle()
        expectNoSession(h)
    }

    /// 初回の案内の練習は、案内のウィンドウの上で試すので、その前に使っていたアプリを「使わない」にしていても開く（グローバルのページ）
    @Test func practiceOpensEvenIfThePreviousAppIsOff() throws {
        let h = try harness()
        h.start()
        h.controller.isPracticeMode = true
        h.open()
        #expect(h.keyboard.isSuppressingPointer)
        #expect(h.hud.shown.count == 1)
        h.liftAndClose()
    }

    /// 試用期間が終わっていても、Nonet を使わないアプリでは何も知らせない（トーストも触覚も出さない）
    @Test func anEndedTrialSaysNothingInAnAppWhereNonetIsOff() async throws {
        let h = try harness(trialEnded: true)
        h.start()
        h.open()
        h.advance(0.3)
        h.lift()
        await h.settle()
        expectNoSession(h)
        #expect(h.hud.toasts.isEmpty)
    }

    /// 前面が別のアプリになれば、いつもどおり開く
    @Test func otherAppsStillWork() async throws {
        let h = try harness()
        h.start()
        h.frontmost.activate(F.notesApp)
        h.run(8)
        await h.settle()
        #expect(h.performer.actions == [F.docs.action])
    }

    /// プロファイルを「グローバルを使う」にしただけなら、グローバルのページで開く（使わないのは off だけ）
    @Test func usingGlobalStillStartsASession() async throws {
        var configuration = F.configuration()
        configuration.setAppMode(.global, for: F.safari)
        let h = try ControllerHarness(configuration: configuration)
        h.start()
        h.run(8)
        await h.settle()
        #expect(h.performer.actions == [F.docs.action])
        #expect(h.controller.lastExecution?.profileName == ModelFixtures.globalName)
    }

    /// 設定画面などで「使わない」に変えたら、次から開かない
    @Test func turningAppOffTakesEffectNextTime() async throws {
        let h = try ControllerHarness()
        h.start()
        h.run(0)
        await h.settle()
        #expect(h.performer.actions == [F.newTab.action])

        h.controller.update { $0.setAppMode(.off, for: F.safari) }
        h.run(2)
        await h.settle()
        #expect(h.performer.actions == [F.newTab.action])
        #expect(h.keyboard.suppressionChanges == [true, false])
    }
}
