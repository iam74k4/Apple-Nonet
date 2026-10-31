// 担当: engine。指・キーボード・時計の偽物から NonetController を動かし、開く → 選ぶ → 離して実行 / やめる までを確かめる。
// 既定: 前面は Safari（ページは Safari 2枚＋グローバル1枚）。使い始めの案内は出し終えている（ControllerHarness）。
// h.open() は上の縁（y 0.98）で触れて 0.05 秒で 0.06 下へ滑らせる。開いた後の指は上の外枠にいる
import Foundation
import Testing
@testable import NonetCore

@MainActor
@Suite struct ControllerSessionTests {
    typealias F = ControllerFixtures

    /// 失敗のトーストの見出し（どのプロファイルのどのマスか）
    private func failureTitle(_ cell: Cell, profile: String, page: Int = 0, index: Int, pages: Int) -> String {
        ControllerPresentation.failureTitle(ControllerTarget(cell: cell, profileName: profile, address: CellAddress(page: page, index: index), profilePageCount: pages))
    }

    // MARK: 開く

    /// 上の縁から滑らせると開く: ポインタの位置を覚え、抑止を始め、HUD をすぐに出し（指は外枠なので「離すとやめる」）、軽い触覚
    @Test func slidingInFromTheTopEdgeOpensTheGrid() throws {
        let h = try ControllerHarness()
        h.start()
        h.recorder.clear()
        h.touch(x: 0.5, y: ControllerHarness.edgeY)
        // 上の縁で触れ始めたときにポインタの位置を覚える（開いたらそこへ戻す）
        #expect(h.recorder.events == ["pointer:remember"])
        #expect(!h.keyboard.isSuppressingPointer)
        h.advance(0.05)
        h.touch(x: 0.5, y: ControllerHarness.slidY)
        // 見分けてから entryConfirmDelay は待つ（2本指のスクロールの2本目が遅れて触れても、開かないように）
        #expect(h.recorder.events == ["pointer:remember"])
        h.advance(EdgeSlideRecognizer.entryConfirmDelay)
        #expect(h.recorder.events == ["pointer:remember", "suppress:on", "hud:show", "haptic:activation"])
        let model = try #require(h.hud.current)
        #expect(model.title == "Safari")
        #expect(model.isFingerInFrame)
        #expect(model.highlightedIndex == nil)
        #expect(model.hint == ControllerPresentation.hint(isPracticeMode: false))
        #expect(h.haptics.plays == [.init(event: .activation, strength: .medium)])
    }

    /// ポインタの抑止は、待ち（entryConfirmDelay）が終わった呼び出しの中で始まり、そこで触れ始めた位置へ戻す
    @Test func suppressionStartsWhenTheConfirmDelayEnds() throws {
        let h = try ControllerHarness()
        h.start()
        h.touch(x: 0.5, y: ControllerHarness.edgeY)
        h.advance(0.05)
        h.touch(x: 0.5, y: ControllerHarness.slidY)
        h.advance(EdgeSlideRecognizer.entryConfirmDelay - 0.01)
        #expect(!h.keyboard.isSuppressingPointer)
        h.advance(0.01)
        #expect(h.keyboard.isSuppressingPointer)
    }

    /// 見分けてから待つ間に2本目の指が触れたら（2本指のスクロールの2本目が遅れて触れた）、開かない
    @Test func aSecondFingerDuringTheConfirmDelayCancelsOpening() throws {
        let h = try ControllerHarness()
        h.start()
        h.touch(x: 0.5, y: ControllerHarness.edgeY)
        h.advance(0.03)
        h.touch(x: 0.5, y: ControllerHarness.slidY)
        h.advance(EdgeSlideRecognizer.entryConfirmDelay / 2)
        h.touch(2, x: 0.6, y: 0.9)
        h.advance(0.2)
        #expect(!h.keyboard.isSuppressingPointer)
        #expect(h.hud.shown.isEmpty)
        #expect(h.haptics.plays.isEmpty)
    }

    /// 待つ間に指が離れたら（短くなぞっただけ）、開かない
    @Test func liftingDuringTheConfirmDelayCancelsOpening() throws {
        let h = try ControllerHarness()
        h.start()
        h.touch(x: 0.5, y: ControllerHarness.edgeY)
        h.advance(0.03)
        h.touch(x: 0.5, y: ControllerHarness.slidY)
        h.lift()
        h.advance(0.2)
        #expect(!h.keyboard.isSuppressingPointer)
        #expect(h.hud.shown.isEmpty)
    }

    /// 帯の外で触れ始めた・遅い・横に滑らせた・2本目の指・手のひら では開かない（ポインタはそのまま）
    @Test func ordinaryTouchesDoNotOpen() throws {
        let h = try ControllerHarness()
        h.start()
        // 帯の外で触れ始めた
        h.touch(x: 0.5, y: 0.88)
        h.advance(0.05)
        h.touch(x: 0.5, y: 0.6)
        h.lift()
        // 遅い
        h.touch(x: 0.5, y: 0.98)
        h.advance(0.7)
        h.touch(x: 0.5, y: 0.8)
        h.lift()
        // 横に滑らせた
        h.touch(x: 0.3, y: 0.98)
        h.advance(0.05)
        h.touch(x: 0.45, y: 0.9)
        h.lift()
        // 2本目の指
        h.touch(1, x: 0.5, y: 0.98)
        h.touch(2, x: 0.2, y: 0.2)
        h.advance(0.05)
        h.touch(1, x: 0.5, y: 0.85)
        h.lift(1)
        h.lift(2)
        // 手のひら
        h.majorAxes[1] = 40
        h.touch(x: 0.5, y: 0.98)
        h.advance(0.05)
        h.touch(x: 0.5, y: 0.85)
        h.lift()
        #expect(h.hud.shown.isEmpty)
        #expect(h.keyboard.suppressionChanges.isEmpty)
        #expect(h.haptics.plays.isEmpty)
    }

    /// マウスやトラックパッドのボタンを押し込んだまま（クリックしたままドラッグを始めるところ）なら開かない
    @Test func aPhysicallyPressedButtonKeepsItClosed() throws {
        let h = try ControllerHarness()
        h.start()
        h.keyboard.isMouseButtonDown = true
        h.open()
        #expect(h.hud.shown.isEmpty)
        #expect(!h.keyboard.isSuppressingPointer)
        #expect(h.haptics.plays.isEmpty)
    }

    /// 「このアプリでは Nonet を使わない」アプリが前面なら開かない（試用期間が終わっていても知らせない）
    @Test(arguments: [false, true])
    func aTurnedOffAppKeepsItClosed(trialEnded: Bool) throws {
        let h = try ControllerHarness(trialEnded: trialEnded)
        h.start()
        h.controller.update { _ = $0.setAppMode(.off, for: F.safari) }
        h.open()
        #expect(h.hud.shown.isEmpty)
        #expect(!h.keyboard.isSuppressingPointer)
        #expect(h.haptics.plays.isEmpty)
        #expect(h.hud.toasts.isEmpty)
    }

    /// 無効・アクセシビリティなし・セキュア入力中は開かない
    @Test func itDoesNotOpenUnlessRunning() throws {
        let disabled = try ControllerHarness(configuration: F.configuration(settings: F.settings { $0.isEnabled = false }))
        disabled.start()
        disabled.open()
        #expect(disabled.hud.shown.isEmpty)

        let secure = try ControllerHarness()
        secure.start()
        secure.permissions.isSecureInputActive = true
        secure.open()
        #expect(secure.hud.shown.isEmpty)
        #expect(secure.controller.status == .secureInputActive)
        // パスワード欄から離れたら、すぐに使える
        secure.lift()
        secure.permissions.isSecureInputActive = false
        secure.open()
        #expect(secure.hud.shown.count == 1)

        let noPermission = try ControllerHarness()
        noPermission.permissions.isAccessibilityGranted = false
        noPermission.start()
        noPermission.open()
        #expect(noPermission.hud.shown.isEmpty)
    }

    /// 試用期間が終わっていたら開かない。終わったことと次にすることをトースト1つと rejected の触覚で知らせる（1つのタッチで1回）
    @Test func anExpiredTrialShowsOneToastInsteadOfOpening() throws {
        let h = try ControllerHarness(trialEnded: true)
        h.start()
        h.open()
        h.advance(0.05)
        h.touch(x: 0.5, y: 0.5)
        #expect(h.hud.shown.isEmpty)
        #expect(!h.keyboard.isSuppressingPointer)
        #expect(h.haptics.events == [.rejected])
        #expect(h.hud.toasts == [ToastModel(
            title: ModelFixtures.text("試用期間が終了しました"),
            detail: ModelFixtures.text("メニューバーの Nonet から購入・登録できます"),
            style: .failure
        )])
        h.lift()
        h.open()
        #expect(h.hud.toasts.count == 2)
    }

    /// Nonet のウィンドウ（設定など）がキーなら開かない。練習モード（初回の案内のウィンドウの上で試す）なら開く
    @Test func aKeyNonetWindowKeepsItClosedExceptForPractice() async throws {
        let h = try ControllerHarness()
        h.start()
        h.frontmost.isOwnWindowKey = true
        h.open()
        #expect(h.hud.shown.isEmpty)
        #expect(!h.keyboard.isSuppressingPointer)
        h.lift()
        h.controller.isPracticeMode = true
        h.run(2)
        await h.settle()
        #expect(h.hud.shown.count == 1)
        #expect(h.performer.calls.isEmpty)
        #expect(h.controller.lastExecution?.cellTitle == F.closeTab.title)
    }

    /// キーを記録している間（設定画面）は開かない
    @Test func recordingKeysKeepsItClosed() throws {
        let h = try ControllerHarness()
        h.start()
        h.controller.isRecordingKeys = true
        h.open()
        #expect(h.hud.shown.isEmpty)
    }

    // MARK: 選んで離す

    /// マスで止めてから離すと、開いたときの前面アプリのページのマスを、そのアプリに向けて実行する
    @Test func liftingOnACellRunsItForTheAppThatWasInFront() async throws {
        let h = try ControllerHarness()
        h.start()
        h.open()
        // 開いた後に前面が変わっても、開いたときのアプリのページとアプリに向けて実行する
        h.frontmost.activate(F.notesApp)
        h.advance(0.05)
        h.touch(on: 2)
        #expect(h.hud.current?.highlightedIndex == 2)
        #expect(h.hud.current?.isFingerInFrame == false)
        #expect(h.haptics.events == [.activation, .boundary])
        h.advance(0.2)
        h.lift()
        await h.settle()

        #expect(h.performer.actions == [F.closeTab.action])
        #expect(h.performer.calls.first?.frontmostApp == F.safariApp)
        #expect(!h.hud.isVisible)
        #expect(!h.keyboard.isSuppressingPointer)
        #expect(h.haptics.events == [.activation, .boundary, .execute])
        // HUD から実行したので、成功のトーストは出さない（時間の掛かるマスだけ）
        #expect(h.hud.toasts.isEmpty)
        let record = try #require(h.controller.lastExecution)
        #expect(record.cellTitle == F.closeTab.title)
        #expect(record.profileName == "Safari")
        #expect(record.address == CellAddress(page: 0, index: 2))
        #expect(record.succeeded)
        #expect(h.controller.lastCancellation == nil)
    }

    @Test func theGlobalPagesAreUsedWhenTheFrontAppHasNoProfile() async throws {
        let h = try ControllerHarness(frontmost: F.notesApp)
        h.start()
        h.run(8)
        await h.settle()
        #expect(h.performer.actions == [F.docs.action])
        #expect(h.performer.calls.first?.frontmostApp == F.notesApp)
        #expect(h.controller.lastExecution?.profileName == ModelFixtures.globalName)
    }

    /// 外枠に出して離すとやめる: 何も実行せず、rejected の触覚。やめたことを記録する（練習で使う）
    @Test func liftingInTheFrameCancels() async throws {
        let h = try ControllerHarness()
        h.start()
        h.open()
        h.advance(0.05)
        h.touch(on: 4)
        h.advance(0.3)
        h.touch(x: 0.03, y: 0.5)
        #expect(h.hud.current?.isFingerInFrame == true)
        #expect(h.hud.current?.highlightedIndex == nil)
        h.advance(0.3)
        h.lift()
        await h.settle()

        #expect(h.performer.calls.isEmpty)
        #expect(!h.hud.isVisible)
        #expect(!h.keyboard.isSuppressingPointer)
        #expect(h.haptics.events == [.activation, .boundary, .boundary, .rejected])
        #expect(h.controller.lastExecution == nil)
        #expect(h.controller.lastCancellation?.reason == .liftedInFrame)
    }

    /// マスに留まる時間（0.1 秒）が足りないうちに離した・空きマスで離したら、実行せずに rejected
    @Test func liftingTooSoonOrOnAnEmptyCellRunsNothing() async throws {
        let h = try ControllerHarness()
        h.start()
        h.run(2, dwell: 0.05)
        h.run(1)
        await h.settle()
        #expect(h.performer.calls.isEmpty)
        #expect(h.haptics.events.filter { $0 == .rejected }.count == 2)
        #expect(h.controller.lastCancellation?.reason == .liftedOnEmptyCell)
        #expect(!h.haptics.events.contains(.execute))
    }

    /// 開いている間にキーを押したら、何も実行せずに閉じる（触覚も鳴らさない）
    @Test func aKeyClosesWithoutRunning() async throws {
        let h = try ControllerHarness()
        h.start()
        h.open()
        h.advance(0.05)
        h.touch(on: 2)
        h.advance(0.3)
        h.pressKey()
        #expect(!h.hud.isVisible)
        #expect(!h.keyboard.isSuppressingPointer)
        h.lift()
        await h.settle()
        #expect(h.performer.calls.isEmpty)
        #expect(h.haptics.events == [.activation, .boundary])
        // キーで閉じたのは、指を離してやめたのとは別
        #expect(h.controller.lastCancellation == nil)
        // 開いていない間のキーは何もしない
        h.pressKey()
        #expect(h.keyboard.suppressionAfterEvent == [false])
    }

    /// 2本指で横にスワイプするとページが変わり、残った指を滑らせて選べる（アプリのページの後ろにグローバルのページ）
    @Test func twoFingerSwipesTurnPagesAcrossTheAppAndGlobalPages() async throws {
        let h = try ControllerHarness()
        h.start()
        h.open()
        h.advance(0.05)
        for expected in [1, 2] {
            h.touch(1, x: 0.5, y: 0.5)
            h.touch(2, x: 0.7, y: 0.5)
            h.touch(1, x: 0.3, y: 0.5)
            h.touch(2, x: 0.5, y: 0.5)
            #expect(h.hud.current?.pageIndex == expected)
            h.lift(2)
        }
        #expect(h.hud.current?.title == ModelFixtures.globalName)
        #expect(h.haptics.events.filter { $0 == .pageChange }.count == 2)
        h.touch(on: 8)
        h.advance(0.3)
        h.lift()
        await h.settle()

        #expect(h.performer.actions == [F.docs.action])
        // 記録はプロファイル内での位置
        #expect(h.controller.lastExecution?.profileName == ModelFixtures.globalName)
        #expect(h.controller.lastExecution?.address == CellAddress(page: 0, index: 8))
    }

    /// 開いている間に設定が変わっても、開いたときのページを使い続ける
    @Test func theSessionKeepsThePagesItStartedWith() async throws {
        let h = try ControllerHarness()
        h.start()
        h.open()
        let safariID = try h.profileID(F.safari)
        h.controller.update { configuration in
            configuration.updateProfile(id: safariID) { $0.pages[0].cells[2] = nil }
        }
        h.advance(0.05)
        h.touch(on: 2)
        h.advance(0.3)
        h.lift()
        await h.settle()
        #expect(h.performer.actions == [F.closeTab.action])
    }

    /// 指が離れたフレームを取りこぼしても、maxDuration（20 秒）で閉じる
    @Test func aSessionThatOutlastsTheLimitEnds() async throws {
        let h = try ControllerHarness()
        h.start()
        h.open()
        h.advance(0.05)
        h.touch(on: 2)
        h.advance(SessionConfiguration.defaultMaxDuration)
        #expect(!h.hud.isVisible)
        #expect(!h.keyboard.isSuppressingPointer)
        h.lift()
        await h.settle()
        #expect(h.performer.calls.isEmpty)
        // タイマーは確かめ直しの1つだけ
        #expect(h.scheduler.pending.map(\.delay) == [NonetController.pollInterval])
    }

    /// 指を離して閉じたら、遅れて届くクリック（タップでクリック）を捨ててもらう
    @Test func closingByLiftingDropsLateClicks() async throws {
        let h = try ControllerHarness()
        h.start()
        h.run(2)
        await h.settle()
        #expect(h.keyboard.lateClickGraces == [true])
    }

    // MARK: 少し長く止めてから実行するマス

    /// 少し長く止めるマスは、holdDwell（0.6 秒）止めてから離したときだけ実行する。HUD は止め終えたことを見せる
    @Test func aHoldCellRunsOnlyAfterTheLongerDwell() async throws {
        var configuration = F.configuration()
        configuration.profiles[1].pages[0].cells[2]?.requiresHold = true
        let h = try ControllerHarness(configuration: configuration)
        h.start()
        h.run(2, dwell: 0.3)
        await h.settle()
        #expect(h.performer.calls.isEmpty)
        #expect(h.controller.lastCancellation?.reason == .liftedTooSoon)

        h.open()
        h.advance(0.05)
        h.touch(on: 2)
        let holding = try #require(h.hud.current?.hold)
        #expect(holding.cellIndex == 2)
        #expect(holding.duration == SessionConfiguration.defaultHoldDwell)
        #expect(!holding.isReady)
        h.advance(SessionConfiguration.defaultHoldDwell)
        #expect(h.hud.current?.hold?.isReady == true)
        h.lift()
        await h.settle()
        #expect(h.performer.actions == [F.closeTab.action])
    }

    // MARK: 試用期間・練習モード・Nonet のウィンドウ

    /// 開いたら（60 秒に1回まで）表示用のライセンスを新しくする。ライセンスがあれば数えない
    @Test func openingRefreshesTheLicenseAtMostOncePerInterval() async throws {
        let h = try ControllerHarness()
        h.start()
        let writes = h.licenseStorage.trialWrites
        h.run(2)
        h.advance(0)
        #expect(h.licenseStorage.trialWrites == writes + 1)
        h.run(2)
        h.advance(0)
        #expect(h.licenseStorage.trialWrites == writes + 1)
        h.advance(NonetController.licenseRefreshInterval)
        h.run(2)
        h.advance(0)
        #expect(h.licenseStorage.trialWrites == writes + 2)

        let licensed = try ControllerHarness(licensed: true)
        licensed.start()
        let licensedWrites = licensed.licenseStorage.trialWrites
        licensed.run(2)
        licensed.advance(0)
        #expect(licensed.licenseStorage.trialWrites == licensedWrites)
    }

    /// 設定などの Nonet のウィンドウが前面だと開かない。何も知らせないと壊れて見えるので、起動してから1回だけトーストで知らせる
    @Test func aNonetWindowInFrontExplainsItselfOnce() throws {
        let h = try ControllerHarness()
        h.frontmost.isOwnWindowKey = true
        h.start()
        h.open()
        #expect(h.hud.shown.isEmpty)
        #expect(!h.keyboard.isSuppressingPointer)
        #expect(h.hud.toasts == [ControllerPresentation.ownWindowToast])
        h.lift()
        h.advance(0.3)
        // 2回目からは知らせない（設定でマスをドラッグするたびに出ると邪魔）
        h.open()
        #expect(h.hud.toasts.count == 1)
        h.lift()
        h.advance(0.3)
        // 別のアプリが前面になれば、ふつうに開く
        h.frontmost.isOwnWindowKey = false
        h.open()
        #expect(h.hud.shown.count == 1)
    }

    /// 練習モードでは実行せず、lastExecution に記録だけする（recentExecutions には入れない）
    @Test func practiceModeRecordsWithoutPerforming() async throws {
        let h = try ControllerHarness()
        h.start()
        h.controller.isPracticeMode = true
        h.run(2)
        await h.settle()
        #expect(h.performer.calls.isEmpty)
        #expect(h.haptics.events.contains(.execute))
        #expect(h.controller.lastExecution?.cellTitle == F.closeTab.title)
        #expect(h.controller.recentExecutions.isEmpty)
        // 外枠でやめたことも記録する（練習の2つ目の課題）
        h.open()
        h.advance(0.1)
        h.liftAndClose()
        #expect(h.controller.lastCancellation?.reason == .liftedInFrame)
    }

    /// 開いている間に Nonet のウィンドウがキーになったら、前面アプリに働きかけるマスは実行しない（アプリを開く・URL は実行する）
    @Test func buttonsForTheFrontAppDoNotRunIfANonetWindowBecomesKey() async throws {
        let h = try ControllerHarness()
        h.start()
        h.open()
        h.frontmost.isOwnWindowKey = true
        h.advance(0.05)
        h.touch(on: 2)
        h.advance(0.3)
        h.lift()
        await h.settle()
        #expect(h.performer.calls.isEmpty)
        #expect(h.haptics.events.last == .rejected)
        let record = try #require(h.controller.lastExecution)
        #expect(!record.succeeded)
        #expect(h.hud.toasts.last?.style == .failure)

        let global = try ControllerHarness(frontmost: F.notesApp)
        global.start()
        global.open()
        global.frontmost.isOwnWindowKey = true
        global.advance(0.05)
        global.touch(on: 8)
        global.advance(0.3)
        global.lift()
        await global.settle()
        #expect(global.performer.actions == [F.docs.action])
    }

    // MARK: 結果と失敗

    @Test func aiOutputGoesToTheResultPanel() async throws {
        let h = try ControllerHarness()
        h.performer.output = { $0 == F.summarize.action ? "要約の結果" : nil }
        h.start()
        h.run(4)
        await h.settle()
        #expect(h.hud.results == [ResultModel(title: F.summarize.title, text: "要約の結果", icon: F.summarize.icon)])
    }

    @Test func failuresAlwaysShowAFailureToast() async throws {
        let h = try ControllerHarness(configuration: F.configuration(settings: F.settings { $0.showExecutionToast = false }))
        h.performer.failure = { $0 == F.closeTab.action ? NonetError.actionFailed("だめでした") : nil }
        h.start()
        h.run(2)
        await h.settle()
        #expect(h.hud.toasts == [ToastModel(
            title: failureTitle(F.closeTab, profile: "Safari", index: 2, pages: 2),
            detail: "だめでした",
            icon: F.closeTab.icon,
            style: .failure
        )])
        #expect(h.controller.lastExecution?.succeeded == false)
    }

    @Test func hapticsUseTheConfiguredStrengthAndCanBeTurnedOff() async throws {
        let strong = try ControllerHarness(configuration: F.configuration(settings: F.settings { $0.haptics = .strong }))
        strong.start()
        strong.run(2)
        await strong.settle()
        #expect(strong.haptics.plays.allSatisfy { $0.strength == .strong })
        #expect(strong.haptics.events == [.activation, .boundary, .execute])

        let off = try ControllerHarness(configuration: F.configuration(settings: F.settings { $0.haptics = .off }))
        off.start()
        off.run(2)
        await off.settle()
        #expect(off.haptics.plays.isEmpty)
        #expect(off.performer.actions == [F.closeTab.action])
    }
}
