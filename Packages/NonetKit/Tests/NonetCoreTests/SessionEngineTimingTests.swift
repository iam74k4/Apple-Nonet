// 時間の境目・tick の扱い・トリガーを指より先に離したときのテスト
import Testing
import NonetCore

@Suite struct SessionEngineTimingTests {
    // MARK: 期限ちょうど

    @Test func fingerLandingExactlyAtThePlacementWindowIsNotAFastTap() {
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        // 期限ちょうどは「過ぎた」とみなし、HUD を先に出してから指を受ける
        #expect(s.touch(on: 4, at: 0.6) == [
            .showHUD(page: 0, highlightedCell: nil),
            .updateHUD(page: 0, highlightedCell: 4),
            .requestTick(at: 20),
        ])
        // 速押しではなく、HUD でのタップ
        #expect(s.lift(at: 0.65) == [.hideHUD, .execute(page: 0, cell: 4, wasFastTap: false)])
    }

    @Test func fingerLiftingExactlyAtHudDelayShowsTheHUDInsteadOfTapping() {
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        s.touch(on: 4, at: 0.1)
        #expect(s.lift(at: 0.1 + 0.3) == [
            .showHUD(page: 0, highlightedCell: 4),
            .updateHUD(page: 0, highlightedCell: nil),
            .requestTick(at: 20),
        ])
        #expect(s.log.executions.isEmpty)
    }

    @Test func fingerLiftingExactlyAtHudDelayInOnFingerLiftModeSelectsFromTheHUD() {
        var s = SessionScenario(fireMode: .onFingerLift)
        s.pressTrigger(at: 0)
        s.touch(on: 4, at: 0.1)
        #expect(s.lift(at: 0.1 + 0.3).visible == [
            .showHUD(page: 0, highlightedCell: 4),
            .hideHUD,
            .execute(page: 0, cell: 4, wasFastTap: false),
        ])
    }

    @Test func zeroDelaysShowTheHUDImmediately() {
        var s = SessionScenario(SessionConfiguration(hudDelay: 0, placementWindow: 0))
        #expect(s.pressTrigger(at: 0) == [
            .beginPointerSuppression,
            .showHUD(page: 0, highlightedCell: nil),
            .requestTick(at: 20),
        ])
        // 速押しではないが、HUD でのタップ
        s.touch(on: 2, at: 0.01)
        #expect(s.lift(at: 0.02).executions == [.execute(page: 0, cell: 2, wasFastTap: false)])
    }

    /// hudDelay を 0 にしても、指を置かないときの placementWindow は別
    @Test func zeroHudDelayKeepsThePlacementWindow() {
        var s = SessionScenario(hudDelay: 0)
        #expect(s.pressTrigger(at: 0) == [.beginPointerSuppression, .requestTick(at: 0.6)])
    }

    /// hudDelay が 0 でも、トリガーより前から休めている指では HUD を出さない（(a) を待つ）。滑らせたらすぐに出す
    @Test func zeroHudDelayWaitsForARestingFingerToSlide() {
        var s = SessionScenario(hudDelay: 0)
        s.touch(on: 6, at: 0)
        #expect(s.pressTrigger(at: 1) == [.beginPointerSuppression, .requestTick(at: 1 + 0.6)])
        #expect(s.touch(on: 7, at: 1.1).visible == [.showHUD(page: 0, highlightedCell: 7)])
    }

    // MARK: ヒステリシス

    @Test func jitterAcrossABorderWithinHysteresisNeitherMovesTheHighlightNorBuzzes() {
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        s.touch(x: 0.32, y: 0.5, at: 0.1)
        s.tick(at: 0.4)
        #expect(s.engine.hud?.highlightedCell == 3)
        var time = 0.4
        for x in [0.34, 0.355, 0.31, 0.36, 0.335, 0.362] {
            time += 0.01
            #expect(s.touch(x: x, y: 0.5, at: time).isEmpty)
        }
        #expect(s.touch(x: 0.37, y: 0.5, at: 0.5) == [.updateHUD(page: 0, highlightedCell: 4), .haptic(.boundary)])
        // 戻るときも同じ余裕
        #expect(s.touch(x: 0.31, y: 0.5, at: 0.51).isEmpty)
        #expect(s.touch(x: 0.30, y: 0.5, at: 0.52) == [.updateHUD(page: 0, highlightedCell: 3), .haptic(.boundary)])
    }

    @Test func configuredHysteresisAndInsetsAreUsed() {
        var s = SessionScenario(SessionConfiguration(hysteresis: 0, edgeInsets: GridInsets(all: 0.1)))
        s.pressTrigger(at: 0)
        // 縁を除くと 0.35 は左の列
        s.touch(x: 0.35, y: 0.5, at: 0.1)
        s.tick(at: 0.4)
        #expect(s.engine.hud?.highlightedCell == 3)
        // ヒステリシス 0 なら境界を越えた途端に切り替わる
        #expect(s.touch(x: 0.1 + 0.8 / 3 + 0.001, y: 0.5, at: 0.5).visible == [
            .updateHUD(page: 0, highlightedCell: 4),
            .haptic(.boundary),
        ])
    }

    @Test func slidingWithLargeHysteresisAndInsetsHighlightsTheMiddleColumn() {
        // 縁 0.25 で使える幅が半分になっても、余裕はマスの半分まで。右へ滑らせると 3 → 4 → 5 と1つずつ進む
        var s = SessionScenario(SessionConfiguration(hysteresis: 1, edgeInsets: GridInsets(all: 0.25)))
        s.pressTrigger(at: 0)
        s.touch(x: 0.3, y: 0.5, at: 0.1)
        s.tick(at: 0.4)
        #expect(s.engine.hud?.highlightedCell == 3)
        var highlights: [Int] = []
        var time = 0.4
        for step in 0...40 {
            time += 0.01
            let effects = s.touch(x: 0.3 + Double(step) * 0.01, y: 0.5, at: time)
            for case .updateHUD(_, let cell?) in effects {
                highlights.append(cell)
            }
        }
        #expect(highlights == [4, 5])
        #expect(s.log.hapticEvents == [.boundary, .boundary])
    }

    @Test func fastTapNearABorderUsesTheCellUnderTheLandingPoint() {
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        s.touch(x: 1.0 / 3 + 0.001, y: 0.5, at: 0.05)
        #expect(s.lift(at: 0.1).executions == [.execute(page: 0, cell: 4, wasFastTap: true)])
    }

    // MARK: tick

    @Test func earlyTickRequestsTheSameDeadlineAgain() {
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        #expect(s.tick(at: 0.59) == [.requestTick(at: 0.6)])
        #expect(s.engine.hud == nil)
        #expect(s.tick(at: 0.6).showsHUD)
    }

    @Test func lateTickStillShowsTheHUD() {
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        #expect(s.tick(at: 0.9) == [.showHUD(page: 0, highlightedCell: nil), .requestTick(at: 20)])
    }

    @Test func tickRequestsAreOnlyRepeatedWhenTheDeadlineChanges() {
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        s.touch(on: 4, at: 0.1)
        s.tick(at: 0.4)
        var time = 0.4
        for cell in [4, 5, 5, 2, 1, 1] {
            time += 0.02
            #expect(s.touch(on: cell, at: time).tickRequests.isEmpty)
        }
        #expect(s.log.tickRequests == [0.6, 0.1 + 0.3, 20])
    }

    @Test func tickAfterTheSessionEndedDoesNothing() {
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        s.releaseTrigger(at: 0.1)
        #expect(s.tick(at: 0.3).isEmpty)
    }

    @Test func inputsThatGoBackInTimeAreTreatedAsNow() {
        var s = SessionScenario()
        s.pressTrigger(at: 1)
        // トリガーの後に届いたフレームは、時刻が少し前でもトリガーの後に置いた指として扱う
        s.touch(on: 4, at: 0.99)
        #expect(s.lift(at: 1.05).executions == [.execute(page: 0, cell: 4, wasFastTap: true)])
        // 時刻が戻った tick で、期限が早まることはない
        #expect(s.tick(at: 0.5) == [.requestTick(at: 21)])
    }

    @Test func nonFiniteTimestampsDoNotBreakTheSession() {
        var s = SessionScenario()
        s.pressTrigger(at: 1)
        s.tick(at: .nan)
        s.touch(on: 2, at: .infinity)
        #expect(s.lift(at: 1.1).executions == [.execute(page: 0, cell: 2, wasFastTap: true)])
        #expect(s.releaseTrigger(at: 1.2).endReason == .released)
    }

    @Test func triggerDownAsTheVeryFirstInputWithoutAFiniteTimeStartsAtZero() {
        var s = SessionScenario()
        #expect(s.send(.triggerDown(at: .nan, configuration: SessionConfiguration())) == [
            .beginPointerSuppression,
            .requestTick(at: 0.6),
        ])
    }

    // MARK: トリガーを指より先に離す

    @Test func releasingTheTriggerJustBeforeLiftingStillCountsAsAFastTap() {
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        s.touch(on: 6, at: 0.1)
        // 指が離れるまでセッション（ポインタの抑止）を続ける
        #expect(s.releaseTrigger(at: 0.15).isEmpty)
        #expect(s.engine.isInSession)
        #expect(!s.engine.isTriggerHeld)
        #expect(s.lift(at: 0.2) == [
            .execute(page: 0, cell: 6, wasFastTap: true),
            .endPointerSuppression(dropsLateClicks: true),
            .sessionEnded(.released),
        ])
        #expect(!s.log.showsHUD)
    }

    @Test func releasedTriggerWithAFingerThatKeepsRestingEndsAtHudDelayWithoutExecuting() {
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        s.touch(on: 6, at: 0.1)
        s.releaseTrigger(at: 0.15)
        // HUD は出さない（トリガーはもう離れている）
        #expect(s.tick(at: 0.1 + 0.3) == [.endPointerSuppression(dropsLateClicks: true), .sessionEnded(.released)])
        #expect(s.lift(at: 0.5).isEmpty)
        #expect(s.log.executions.isEmpty)
    }

    @Test func releasedTriggerWaitingForTheFingerIgnoresMovementAndSwipes() {
        var s = SessionScenario(pageCount: 3)
        s.pressTrigger(at: 0)
        s.touch(1, x: 0.6, y: 0.5, at: 0.1)
        s.releaseTrigger(at: 0.12)
        #expect(s.touch(1, x: 0.2, y: 0.5, at: 0.15).isEmpty)
        #expect(s.touch(2, x: 0.4, y: 0.5, at: 0.16).isEmpty)
        #expect(s.setFingers([(1, 0.0, 0.5), (2, 0.2, 0.5)], at: 0.18).isEmpty)
        // 2本目が触れたので実行しない。受け付けなかったことは触覚で知らせる
        #expect(s.liftAll(at: 0.2) == [.haptic(.rejected), .endPointerSuppression(dropsLateClicks: true), .sessionEnded(.released)])
    }

    @Test func secondTriggerReleaseWhileWaitingIsIgnored() {
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        s.touch(on: 1, at: 0.1)
        s.releaseTrigger(at: 0.15)
        #expect(s.releaseTrigger(at: 0.16).isEmpty)
        #expect(s.lift(at: 0.2).executions == [.execute(page: 0, cell: 1, wasFastTap: true)])
    }

    @Test func interruptionWhileWaitingForTheFingerDropsTheTap() {
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        s.touch(on: 1, at: 0.1)
        s.releaseTrigger(at: 0.15)
        #expect(s.interrupt(at: 0.17) == [.endPointerSuppression(dropsLateClicks: true), .sessionEnded(.interrupted)])
        #expect(s.lift(at: 0.2).isEmpty)
    }

    @Test func timeoutWhileWaitingForTheFingerEndsTheSession() {
        var s = SessionScenario(SessionConfiguration(maxDuration: 1))
        s.pressTrigger(at: 0)
        // 一度実行しておき、(a) の HUD を出さないようにする
        s.touch(on: 0, at: 0.05)
        s.lift(at: 0.1)
        s.touch(on: 1, at: 0.9)
        s.releaseTrigger(at: 0.95)
        #expect(s.tick(at: 1) == [.endPointerSuppression(dropsLateClicks: true), .sessionEnded(.timeout)])
        #expect(s.log.executions.count == 1)
    }

    @Test func releasingInTheHUDWithAJustPlacedFingerExecutesOnceAndWaitsForTheLift() {
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        s.tick(at: 0.6)
        s.touch(on: 4, at: 0.65)
        #expect(s.releaseTrigger(at: 0.7).visible == [.hideHUD, .execute(page: 0, cell: 4, wasFastTap: false)])
        // HUD でのタップとして2回目を実行しない
        #expect(s.lift(at: 0.75) == [.endPointerSuppression(dropsLateClicks: true), .sessionEnded(.released)])
        #expect(s.log.executions.count == 1)
    }

    @Test func cancellingInTheHUDWithAJustPlacedFingerKeepsTheCancelReason() {
        var s = SessionScenario(fireMode: .onFingerLift)
        s.pressTrigger(at: 0)
        s.tick(at: 0.6)
        s.touch(on: 4, at: 0.65)
        #expect(s.releaseTrigger(at: 0.7).visible == [.hideHUD])
        #expect(s.lift(at: 0.75) == [.endPointerSuppression(dropsLateClicks: true), .sessionEnded(.cancelled)])
        #expect(s.log.executions.isEmpty)
    }

    @Test func fingerRestingBeforeTheTriggerOnlyDelaysTheEndIfItWasJustPlaced() {
        var old = SessionScenario()
        old.touch(on: 4, at: 1)
        old.pressTrigger(at: 2)
        #expect(old.releaseTrigger(at: 2.1) == [.endPointerSuppression(dropsLateClicks: false), .sessionEnded(.released)])

        var fresh = SessionScenario()
        fresh.touch(on: 4, at: 1.95)
        fresh.pressTrigger(at: 2)
        #expect(fresh.releaseTrigger(at: 2.1) == [.requestTick(at: 1.95 + 0.3)])
        // トリガーより前に置いた指は速押しにならない
        #expect(fresh.lift(at: 2.15) == [.endPointerSuppression(dropsLateClicks: true), .sessionEnded(.released)])
    }

    // MARK: トリガーの押し直し

    @Test func rapidRePressStartsAFreshSession() {
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        s.touch(on: 0, at: 0.02)
        s.lift(at: 0.04)
        s.releaseTrigger(at: 0.05)
        #expect(s.pressTrigger(at: 0.1) == [.beginPointerSuppression, .requestTick(at: 0.1 + 0.6)])
        // 前のセッションで実行していても、新しいセッションでは (a) で HUD が出る
        #expect(s.tick(at: 0.1 + 0.6).visible == [.showHUD(page: 0, highlightedCell: nil)])
    }

    @Test func rapidRePressWhileTheFingerIsStillDownTreatsItAsAlreadyResting() {
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        s.touch(on: 4, at: 0.1)
        s.releaseTrigger(at: 0.15)
        #expect(s.pressTrigger(at: 0.2) == [
            .endPointerSuppression(dropsLateClicks: true),
            .sessionEnded(.released),
            .beginPointerSuppression,
            .requestTick(at: 0.2 + 0.6),
        ])
        // 速押しにしない。HUD は (a) の時刻に出す
        #expect(s.lift(at: 0.25).isEmpty)
        #expect(s.log.executions.isEmpty)
    }

    @Test func triggerDownWithoutAReleaseRestartsTheSession() {
        // 離したイベントを取りこぼした場合
        var s = SessionScenario(pageCount: 3)
        s.pressTrigger(at: 0)
        s.setFingers([(1, 0.6, 0.5), (2, 0.8, 0.5)], at: 0.05)
        s.setFingers([(1, 0.45, 0.5), (2, 0.65, 0.5)], at: 0.1)
        s.liftAll(at: 0.2)
        #expect(s.pressTrigger(at: 1) == [
            .hideHUD,
            .endPointerSuppression(dropsLateClicks: false),
            .sessionEnded(.interrupted),
            .beginPointerSuppression,
            .requestTick(at: 1 + 0.6),
        ])
        #expect(s.engine.pageIndex == 0)
        #expect(s.engine.hud == nil)
    }

    @Test func eachSessionUsesItsOwnConfiguration() {
        var s = SessionScenario(fireMode: .onTriggerRelease, pageCount: 1)
        s.pressTrigger(at: 0)
        s.releaseTrigger(at: 0.1)
        s.configuration = SessionConfiguration(hudDelay: 0.5, placementWindow: 0.7, fireMode: .onFingerLift, pageCount: 2)
        #expect(s.pressTrigger(at: 1).tickRequests == [1 + 0.7])
        s.touch(on: 3, at: 1.1)
        s.tick(at: 1.1 + 0.5)
        #expect(s.lift(at: 1.7).visible == [.hideHUD, .execute(page: 0, cell: 3, wasFastTap: false)])
    }

    // MARK: 遅れて届くクリック

    /// その出力の endPointerSuppression の dropsLateClicks
    private func dropsLateClicks(_ effects: [SessionEffect]) -> Bool? {
        effects.lazy.compactMap { effect -> Bool? in
            if case .endPointerSuppression(let drops) = effect { return drops }
            return nil
        }.first
    }

    @Test func aSessionWithoutATouchDoesNotDropLateClicks() {
        // トリガーをほかのキーと組み合わせただけ（右⌘＋C など）。直後のクリックは前面アプリに渡す
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        #expect(dropsLateClicks(s.interrupt(at: 0.1)) == false)
        s.releaseTrigger(at: 0.2)
        s.pressTrigger(at: 1)
        #expect(dropsLateClicks(s.releaseTrigger(at: 1.05)) == false)
        // 時間切れも同じ
        s.pressTrigger(at: 2)
        #expect(dropsLateClicks(s.tick(at: 22)) == false)
    }

    @Test func aLiftShortlyBeforeTheEndDropsLateClicks() {
        let window = SessionEngine.lateClickWindow
        // 速押しで指を離した直後にトリガーを離した。その指の「タップでクリック」はトリガーの後に届きうる
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        s.touch(on: 2, at: 0.05)
        s.lift(at: 0.1)
        #expect(dropsLateClicks(s.releaseTrigger(at: 0.1 + window - 0.01)) == true)
        // 離してから lateClickWindow 経っていれば、クリックはもう抑止の間に届いている
        s.pressTrigger(at: 2)
        s.touch(on: 2, at: 2.05)
        s.lift(at: 2.1)
        #expect(dropsLateClicks(s.releaseTrigger(at: 2.1 + window)) == false)
    }

    @Test func aFingerStillTouchingAtTheEndDropsLateClicksOnlyIfJustPlaced() {
        let window = SessionEngine.lateClickWindow
        // 親指を前から置いたまま、右⌘＋C を押した。長く置いた指はタップにならない
        var resting = SessionScenario()
        resting.touch(on: 7, at: 0)
        resting.pressTrigger(at: 1)
        #expect(dropsLateClicks(resting.interrupt(at: 1.1)) == false)

        // 置いたばかりの指が触れたまま中断した。離すとタップでクリックになりうる
        var fresh = SessionScenario()
        fresh.pressTrigger(at: 0)
        fresh.touch(on: 2, at: 0.05)
        #expect(dropsLateClicks(fresh.interrupt(at: 0.05 + window - 0.01)) == true)

        var long = SessionScenario()
        long.pressTrigger(at: 0)
        long.touch(on: 2, at: 0.05)
        #expect(dropsLateClicks(long.interrupt(at: 0.05 + window)) == false)
    }

    @Test func aDrainEndedByTheLiftDropsLateClicks() {
        // トリガーを指より少し先に離した速押し。セッションは指を離したフレームで終わる
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        s.touch(on: 4, at: 0.05)
        s.releaseTrigger(at: 0.08)
        #expect(dropsLateClicks(s.lift(at: 0.1)) == true)
    }
}
