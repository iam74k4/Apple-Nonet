// 担当: engine（ui-settings が足した確かめ）。「このアプリでは Nonet を使わない」（ProfileMode.off）のアプリが前面のとき、
// トリガーキーでも角の長押しでもセッションを始めず、ポインタも止めないか。既定: 前面は Safari、トリガーは右⌥
import Foundation
import Testing
@testable import NonetCore

@MainActor
@Suite struct ControllerTurnedOffAppTests {
    typealias F = ControllerFixtures

    /// Safari を「使わない」にした設定
    private func harness(
        frontmost: RunningAppInfo? = F.safariApp,
        _ transform: (inout GlobalSettings) -> Void = { _ in }
    ) throws -> ControllerHarness {
        var configuration = F.configuration(settings: F.settings(transform))
        configuration.setAppMode(.off, for: F.safari)
        return try ControllerHarness(configuration: configuration, frontmost: frontmost)
    }

    private func expectNoSession(_ h: ControllerHarness) {
        #expect(!h.keyboard.isSuppressingPointer)
        #expect(h.keyboard.suppressionChanges.isEmpty)
        #expect(h.hud.shown.isEmpty)
        #expect(h.haptics.plays.isEmpty)
        #expect(h.performer.calls.isEmpty)
        #expect(h.controller.lastExecution == nil)
    }

    @Test func theTriggerKeyDoesNothingInAnAppWhereNonetIsOff() async throws {
        let h = try harness()
        h.start()
        // 速押しも、HUD が出るまで押し続けるのも、どちらも始まらない
        h.fastTap(2)
        h.pressTrigger()
        h.advance(1)
        h.touch(on: 4)
        h.advance(0.2)
        h.lift()
        h.releaseTrigger()
        await h.settle()
        expectNoSession(h)
        // トリガーキーそのものは、いつもどおり前面アプリに渡す設定のまま
        #expect(h.keyboard.passTriggerToApps)
    }

    /// 「トリガーキーを前面のアプリに渡す」を切っていても、Nonet を使わないアプリではキーを飲み込まない。
    /// 前面のアプリが変わったら、その場で切り替える
    @Test func theTriggerKeyIsPassedThroughOnlyInAnAppWhereNonetIsOff() throws {
        let h = try harness { $0.passTriggerToApps = false }
        h.start()
        #expect(h.keyboard.passTriggerToApps)
        // Nonet を使うアプリに移ると、設定どおり渡さない
        h.frontmost.current = RunningAppInfo(app: ModelFixtures.xcode, processID: 502)
        h.frontmost.onChange?(h.frontmost.current)
        #expect(!h.keyboard.passTriggerToApps)
        // 戻ると、また渡す
        h.frontmost.current = F.safariApp
        h.frontmost.onChange?(h.frontmost.current)
        #expect(h.keyboard.passTriggerToApps)
    }

    @Test func aCornerLongPressDoesNothingInAnAppWhereNonetIsOff() async throws {
        let h = try harness { $0.touchActivation = .topLeft }
        h.start()
        h.touch(x: 0.05, y: 0.95)
        h.advance(CornerHoldRecognizer.holdDuration + 0.2)
        h.lift()
        await h.settle()
        expectNoSession(h)
        #expect(!h.keyboard.interruptsWithoutTrigger)
    }

    /// 前面が別のアプリになれば、いつもどおり始まる
    @Test func otherAppsStillWork() async throws {
        let h = try harness()
        h.start()
        h.frontmost.activate(F.notesApp)
        h.fastTap(8)
        await h.settle()
        #expect(h.performer.actions == [F.docs.action])
    }

    /// プロファイルを「グローバルを使う」にしただけなら、グローバルのページで始まる（使わないのは off だけ）
    @Test func usingGlobalStillStartsASession() async throws {
        var configuration = F.configuration()
        configuration.setAppMode(.global, for: F.safari)
        let h = try ControllerHarness(configuration: configuration)
        h.start()
        h.fastTap(8)
        await h.settle()
        #expect(h.performer.actions == [F.docs.action])
        #expect(h.controller.lastExecution?.profileName == ModelFixtures.globalName)
    }

    /// 設定画面などで「使わない」に変えたら、次のトリガーから始めない
    @Test func turningAppOffTakesEffectAtTheNextTrigger() async throws {
        let h = try ControllerHarness()
        h.start()
        h.fastTap(0)
        await h.settle()
        #expect(h.performer.actions == [F.newTab.action])

        h.controller.update { $0.setAppMode(.off, for: F.safari) }
        h.fastTap(2)
        await h.settle()
        #expect(h.performer.actions == [F.newTab.action])
        #expect(h.keyboard.suppressionChanges == [true, false])
    }
}
