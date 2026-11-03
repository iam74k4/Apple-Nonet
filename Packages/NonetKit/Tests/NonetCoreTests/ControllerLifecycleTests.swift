// 担当: engine。NonetController の開始・停止、権限・トラックパッド・セキュア入力の状態と、設定の反映
import Foundation
import Testing
@testable import NonetCore

@MainActor
@Suite struct ControllerLifecycleTests {
    typealias F = ControllerFixtures

    private var hasPoll: (ControllerHarness) -> Bool {
        { $0.scheduler.hasPending(delay: NonetController.pollInterval) }
    }

    // MARK: 開始と停止

    @Test func startLoadsTheConfigurationAndStartsEverything() throws {
        let h = try ControllerHarness()
        #expect(h.controller.status == .stopped)
        h.start()

        #expect(h.controller.status == .running)
        #expect(h.controller.configuration == (try h.savedConfiguration()))
        #expect(h.controller.configuration.appProfile(forBundleID: F.safari.bundleID)?.pages.first?.cells.first??.id == F.newTab.id)
        #expect(!h.controller.isFirstLaunch)
        #expect(h.controller.notice == nil)
        #expect(h.keyboard.isRunning)
        #expect(h.touchSource.isRunning)
        #expect(h.frontmost.isRunning)
        #expect(h.controller.activeProfileName == "Safari")
        #expect(hasPoll(h))
    }

    @Test func startingTwiceDoesNothingMore() throws {
        let h = try ControllerHarness()
        h.start()
        h.start()
        #expect(h.keyboard.startCount == 1)
        #expect(h.touchSource.startCount == 1)
        #expect(h.scheduler.pending.count == 1)
    }

    @Test func stopEndsTheSessionAndStopsEverything() async throws {
        let h = try ControllerHarness()
        h.start()
        h.open()
        h.advance(0.3)
        h.touch(on: 4)
        #expect(h.hud.isVisible)
        h.controller.stop()

        #expect(h.controller.status == .stopped)
        #expect(!h.hud.isVisible)
        #expect(!h.keyboard.isSuppressingPointer)
        #expect(!h.keyboard.isRunning)
        #expect(!h.touchSource.isRunning)
        #expect(!h.frontmost.isRunning)
        #expect(h.keyboard.onEvent == nil)
        #expect(h.touchSource.onFrame == nil)
        #expect(h.scheduler.pending.isEmpty)
        await h.settle()
        #expect(h.performer.calls.isEmpty)
    }

    @Test func itCanStartAgainAfterStopping() async throws {
        let h = try ControllerHarness()
        h.start()
        h.controller.stop()
        h.start()
        #expect(h.controller.status == .running)
        h.run(2)
        await h.settle()
        #expect(h.performer.actions == [F.closeTab.action])
    }

    @Test func keysAreIgnoredBeforeStart() throws {
        let h = try ControllerHarness()
        h.controller.refreshPermissions()
        #expect(h.controller.status == .stopped)
        #expect(!h.keyboard.isRunning)
        #expect(h.scheduler.pending.isEmpty)
    }

    // MARK: アクセシビリティ

    @Test func withoutAccessibilityItWaitsAndStartsTheMonitorOnceGranted() throws {
        let h = try ControllerHarness()
        h.permissions.isAccessibilityGranted = false
        h.start()
        #expect(h.controller.status == .needsAccessibility)
        #expect(!h.keyboard.isRunning)
        // 指の位置は権限が無くても読めるが、セッションを始められないので読まない（指が触れるたびにメインスレッドを起こさない）
        #expect(!h.touchSource.isRunning)

        h.advance(NonetController.pollInterval)
        #expect(h.controller.status == .needsAccessibility)
        #expect(h.touchSource.startCount == 0)
        h.permissions.isAccessibilityGranted = true
        h.advance(NonetController.pollInterval)
        #expect(h.controller.status == .running)
        #expect(h.keyboard.isRunning)
        #expect(h.touchSource.isRunning)
    }

    @Test func aFingerRestingWhileAccessibilityIsRevokedIsForgotten() async throws {
        let h = try ControllerHarness()
        h.start()
        h.touch(on: 2)
        h.permissions.isAccessibilityGranted = false
        h.advance(NonetController.pollInterval)
        #expect(!h.touchSource.isRunning)
        // 止めている間に離した（フレームは届かない）
        h.lift()
        h.permissions.isAccessibilityGranted = true
        h.advance(NonetController.pollInterval)
        #expect(h.touchSource.isRunning)
        // 止めたときに離れたことにしてあるので、次に置いた指は新しいタッチ（上の縁から開ける）
        h.open()
        h.choose(2)
        h.closeIfOpen()
        await h.settle()
        #expect(h.performer.actions == [F.closeTab.action])
    }

    @Test func refreshPermissionsChecksImmediately() throws {
        let h = try ControllerHarness()
        h.permissions.isAccessibilityGranted = false
        h.start()
        h.permissions.isAccessibilityGranted = true
        h.controller.refreshPermissions()
        #expect(h.controller.status == .running)
        #expect(h.keyboard.isRunning)
        // 確かめ直しのタイマーは1つのまま
        #expect(h.scheduler.pending.filter { $0.delay == NonetController.pollInterval }.count == 1)
    }

    @Test func revokingAccessibilityStopsTheMonitorAndEndsTheSession() throws {
        let h = try ControllerHarness()
        h.start()
        h.open()
        h.advance(0.3)
        h.permissions.isAccessibilityGranted = false
        h.advance(NonetController.pollInterval)

        #expect(h.controller.status == .needsAccessibility)
        #expect(!h.keyboard.isRunning)
        #expect(!h.touchSource.isRunning)
        #expect(!h.hud.isVisible)
        #expect(!h.keyboard.isSuppressingPointer)
    }

    @Test func aMonitorThatCannotStartCountsAsMissingAccessibility() throws {
        let h = try ControllerHarness()
        h.keyboard.startError = NonetError.permissionDenied("アクセシビリティ")
        h.start()
        #expect(h.controller.status == .needsAccessibility)
        // 許可はあるので、トラックパッドは止めたり始めたりしない
        #expect(h.touchSource.isRunning)
        h.advance(NonetController.pollInterval)
        #expect(h.touchSource.startCount == 1)
        h.keyboard.startError = nil
        h.advance(NonetController.pollInterval)
        #expect(h.controller.status == .running)
    }

    // MARK: トラックパッド

    @Test func noMultitouchSupportMeansNoTrackpad() throws {
        let h = try ControllerHarness()
        h.touchSource.startError = NonetError.unavailable("なし")
        h.start()
        #expect(h.controller.status == .noTrackpad)
        // 開くことも無いので、イベントタップも作らない
        #expect(!h.keyboard.isRunning)
        h.advance(NonetController.pollInterval)
        #expect(h.touchSource.startCount == 2)

        h.touchSource.startError = nil
        h.advance(NonetController.pollInterval)
        #expect(h.controller.status == .running)
        #expect(h.keyboard.isRunning)
    }

    @Test func aTrackpadThatComesAndGoesIsFollowedByPolling() throws {
        let h = try ControllerHarness()
        h.touchSource.isAvailable = false
        h.start()
        #expect(h.controller.status == .noTrackpad)
        h.touchSource.isAvailable = true
        h.advance(NonetController.pollInterval)
        #expect(h.controller.status == .running)

        h.open()
        h.advance(0.3)
        h.touchSource.isAvailable = false
        h.advance(NonetController.pollInterval)
        #expect(h.controller.status == .noTrackpad)
        #expect(!h.hud.isVisible)
        #expect(!h.keyboard.isSuppressingPointer)
        #expect(!h.keyboard.isRunning)
        #expect(h.touchSource.startCount == 1)
    }

    // MARK: セキュア入力

    @Test func secureInputBlocksSessionsUntilItEnds() throws {
        let h = try ControllerHarness()
        h.permissions.isSecureInputActive = true
        h.start()
        #expect(h.controller.status == .secureInputActive)
        // キーボードは動かしたまま（終わったらすぐ使えるように）。指の位置も読み続ける
        #expect(h.keyboard.isRunning)
        #expect(h.touchSource.isRunning)
        h.open()
        #expect(h.keyboard.suppressionChanges.isEmpty)
        h.closeIfOpen()

        h.permissions.isSecureInputActive = false
        h.advance(NonetController.pollInterval)
        #expect(h.controller.status == .running)
    }

    @Test func openingRechecksSecureInputBeforeThePollDoes() throws {
        let h = try ControllerHarness()
        h.permissions.isSecureInputActive = true
        h.start()
        h.permissions.isSecureInputActive = false
        h.open()
        #expect(h.controller.status == .running)
        #expect(h.keyboard.isSuppressingPointer)
    }

    @Test func openingNoticesSecureInputThatBeganSinceTheLastPoll() async throws {
        let h = try ControllerHarness()
        h.start()
        // パスワード欄に入ってすぐ（次の確かめ直しより前に）上の縁から滑らせる
        h.permissions.isSecureInputActive = true
        h.advance(NonetController.pollInterval / 4)
        #expect(h.controller.status == .running)
        h.open()

        #expect(h.controller.status == .secureInputActive)
        #expect(h.keyboard.suppressionChanges.isEmpty)
        h.choose(2)
        h.advance(1)
        h.touch(on: 0)
        h.advance(1)
        h.closeIfOpen()
        await h.settle()
        #expect(h.hud.shown.isEmpty)
        #expect(h.performer.calls.isEmpty)
        #expect(h.haptics.plays.isEmpty)
        #expect(h.controller.lastExecution == nil)
    }

    @Test func secureInputDuringASessionEndsIt() throws {
        let h = try ControllerHarness()
        h.start()
        h.open()
        h.advance(0.3)
        h.permissions.isSecureInputActive = true
        h.advance(NonetController.pollInterval)
        #expect(h.controller.status == .secureInputActive)
        #expect(!h.hud.isVisible)
        #expect(!h.keyboard.isSuppressingPointer)
    }

    // MARK: 状態の優先順

    @Test func statusPriority() {
        typealias S = ControllerStatus
        #expect(S.resolve(isEnabled: false, isAccessibilityGranted: false, isTrackpadAvailable: false, isSecureInputActive: true) == .disabled)
        #expect(S.resolve(isEnabled: true, isAccessibilityGranted: false, isTrackpadAvailable: false, isSecureInputActive: true) == .needsAccessibility)
        #expect(S.resolve(isEnabled: true, isAccessibilityGranted: true, isTrackpadAvailable: false, isSecureInputActive: true) == .noTrackpad)
        #expect(S.resolve(isEnabled: true, isAccessibilityGranted: true, isTrackpadAvailable: true, isSecureInputActive: true) == .secureInputActive)
        #expect(S.resolve(isEnabled: true, isAccessibilityGranted: true, isTrackpadAvailable: true, isSecureInputActive: false) == .running)
        for granted in [false, true] {
            for trackpad in [false, true] {
                for secure in [false, true] {
                    #expect(S.resolve(isEnabled: false, isAccessibilityGranted: granted, isTrackpadAvailable: trackpad, isSecureInputActive: secure) == .disabled)
                }
            }
        }
    }

    @Test func disabledWinsOverMissingPermissions() throws {
        let h = try ControllerHarness(configuration: F.configuration(settings: F.settings { $0.isEnabled = false }))
        h.permissions.isAccessibilityGranted = false
        h.touchSource.isAvailable = false
        h.start()
        #expect(h.controller.status == .disabled)
    }

    // MARK: 有効・無効

    @Test func disablingStopsTheMonitorsAndEnablingRestartsThem() throws {
        let h = try ControllerHarness()
        h.start()
        h.controller.update { $0.settings.isEnabled = false }

        #expect(h.controller.status == .disabled)
        // 無効の間は、イベントタップも指の位置も止める
        #expect(!h.keyboard.isRunning)
        #expect(!h.touchSource.isRunning)
        #expect(!hasPoll(h))
        h.advance(10)
        #expect(h.keyboard.startCount == 1)

        h.controller.update { $0.settings.isEnabled = true }
        #expect(h.controller.status == .running)
        #expect(h.keyboard.isRunning)
        #expect(h.touchSource.isRunning)
        #expect(hasPoll(h))
    }

    @Test func disablingDuringASessionEndsIt() async throws {
        let h = try ControllerHarness()
        h.start()
        h.open()
        h.advance(0.3)
        h.touch(on: 4)
        h.controller.update { $0.settings.isEnabled = false }
        #expect(!h.hud.isVisible)
        #expect(!h.keyboard.isSuppressingPointer)
        await h.settle()
        #expect(h.performer.calls.isEmpty)
    }

    @Test func aFingerRestingWhileDisabledIsForgotten() async throws {
        let h = try ControllerHarness()
        h.start()
        h.touch(on: 2)
        h.controller.update { $0.settings.isEnabled = false }
        h.controller.update { $0.settings.isEnabled = true }
        // 止めている間に指は離れたかもしれない。次に置いた指は新しいタッチ（上の縁から開ける）
        h.open()
        h.choose(2)
        h.closeIfOpen()
        await h.settle()
        #expect(h.performer.actions == [F.closeTab.action])
    }

    // MARK: 設定の反映

    @Test func otherChangesKeepTheSession() async throws {
        let h = try ControllerHarness()
        h.start()
        h.open()
        h.advance(0.3)
        h.touch(on: 4)
        h.controller.update { $0.settings.haptics = .strong }
        #expect(h.hud.isVisible)
        h.advance(0.4)
        h.closeIfOpen()
        await h.settle()
        #expect(h.performer.actions == [F.summarize.action])
    }

    @Test func newSessionsUseTheNewSettings() throws {
        let h = try ControllerHarness()
        h.start()
        // 「ためらったときだけ出す」は、次に開いたときから効く（開いてすぐは出さず、hesitationDelay の後に出す）
        h.controller.update { $0.settings.hudOnHesitation = true }
        h.open()
        #expect(h.hud.shown.isEmpty)
        h.advance(NonetController.hesitationDelay)
        #expect(h.hud.shown.count == 1)
    }

    // MARK: キーの記録

    @Test func recordingKeysBlocksSessions() throws {
        let h = try ControllerHarness()
        h.start()
        h.controller.isRecordingKeys = true
        h.open()
        h.advance(0.5)
        #expect(h.keyboard.suppressionChanges.isEmpty)
        #expect(h.hud.shown.isEmpty)
        h.closeIfOpen()

        h.controller.isRecordingKeys = false
        h.open()
        #expect(h.keyboard.isSuppressingPointer)
    }

    @Test func startingToRecordKeysEndsTheSession() async throws {
        let h = try ControllerHarness()
        h.start()
        h.open()
        h.advance(0.3)
        h.touch(on: 4)
        h.controller.isRecordingKeys = true
        #expect(!h.hud.isVisible)
        #expect(!h.keyboard.isSuppressingPointer)
        h.advance(0.4)
        h.closeIfOpen()
        await h.settle()
        #expect(h.performer.calls.isEmpty)
    }

    // MARK: 前面アプリのプロファイル

    @Test func activeProfileFollowsTheFrontmostAppAndTheSettings() throws {
        let h = try ControllerHarness()
        #expect(h.controller.activeProfileName == nil)
        h.start()
        #expect(h.controller.activeProfileName == "Safari")
        h.frontmost.activate(F.notesApp)
        #expect(h.controller.activeProfileName == ModelFixtures.globalName)
        h.frontmost.activate(nil)
        #expect(h.controller.activeProfileName == ModelFixtures.globalName)
        h.frontmost.activate(F.safariApp)
        #expect(h.controller.activeProfileName == "Safari")

        let safariID = try h.profileID(F.safari)
        h.controller.update { $0.updateProfile(id: safariID) { $0.isEnabled = false } }
        #expect(h.controller.activeProfileName == ModelFixtures.globalName)
    }
}
