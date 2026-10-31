// 担当: engine。キーボード・指・時計の偽物から NonetController を動かし、HUD・触覚・実行までを確かめる。
// 既定: トリガーは右⌥、hudDelay 0.3秒（指を置かなければ placementWindow 0.6秒で HUD）、onTriggerRelease、
// 前面は Safari（ページは Safari 2枚＋グローバル1枚）。使い始めの案内は出し終えている（ControllerHarness）
import Foundation
import Testing
@testable import NonetCore

@MainActor
@Suite struct ControllerSessionTests {
    typealias F = ControllerFixtures

    /// 指を置かずに HUD が出るまで待つ（仕様 4 (a)）
    private static let placementWindow = SessionConfiguration.defaultPlacementWindow

    /// 失敗のトーストの見出し（どのプロファイルのどのマスか）
    private func failureTitle(_ cell: Cell, profile: String, page: Int = 0, index: Int, pages: Int) -> String {
        ControllerPresentation.failureTitle(ControllerTarget(cell: cell, profileName: profile, address: CellAddress(page: page, index: index), profilePageCount: pages))
    }

    private func detail(_ cell: Cell) -> String? {
        guard case .keystroke(let keys) = cell.action else { return nil }
        return keys.displayString
    }

    // MARK: 速押し

    @Test func fastTapExecutesTheCellOfTheProfileOfTheAppFrontmostAtTriggerDown() async throws {
        let h = try ControllerHarness()
        h.start()
        h.pressTrigger()
        // トリガーを押した後に前面が変わっても、押したときのアプリのページとアプリに向けて実行する
        h.frontmost.activate(F.notesApp)
        h.tap(2)
        h.releaseTrigger()
        await h.settle()

        #expect(h.performer.actions == [F.closeTab.action])
        #expect(h.performer.calls.first?.frontmostApp == F.safariApp)
        #expect(h.hud.shown.isEmpty)
        #expect(h.haptics.plays == [.init(event: .execute, strength: .medium)])
        #expect(h.hud.toasts == [ToastModel(title: F.closeTab.title, icon: F.closeTab.icon, style: .success)])
        let record = try #require(h.controller.lastExecution)
        #expect(record.cellTitle == F.closeTab.title)
        #expect(record.profileName == "Safari")
        #expect(record.address == CellAddress(page: 0, index: 2))
        #expect(record.succeeded)
        #expect(record.message == nil)
        #expect(record.wasFastTap)
    }

    @Test func fastTapUsesTheGlobalPagesWhenTheFrontmostAppHasNoProfile() async throws {
        let h = try ControllerHarness(frontmost: F.notesApp)
        h.start()
        h.fastTap(8)
        await h.settle()

        #expect(h.performer.actions == [F.docs.action])
        #expect(h.performer.calls.first?.frontmostApp == F.notesApp)
        #expect(h.controller.lastExecution?.profileName == ModelFixtures.globalName)
        #expect(h.controller.lastExecution?.address == CellAddress(page: 0, index: 8))
    }

    @Test func aFingerRestingBeforeTheTriggerIsNotAFastTap() async throws {
        let h = try ControllerHarness()
        h.start()
        // セッションの外のフレームもエンジンに渡しているので、トリガーより前から置いていた指だと分かる
        h.touch(on: 2)
        h.advance(1)
        h.pressTrigger()
        h.advance(0.05)
        h.lift()
        h.advance(0.05)
        h.releaseTrigger()
        await h.settle()

        #expect(h.performer.calls.isEmpty)
        #expect(h.haptics.plays.isEmpty)
        #expect(h.controller.lastExecution == nil)
    }

    /// 親指を手前に休めたままトリガーを押し、何もせずに離しても、親指の下のマスは実行しない（仕様 9・11）
    @Test func aRestingThumbIsNotRunWhenTheTriggerIsReleased() async throws {
        let h = try ControllerHarness()
        h.start()
        // 親指をトラックパッドの手前の右（マス 8: リーダー）に休めている
        h.touch(1, x: 0.85, y: 0.05)
        h.advance(2)
        h.pressTrigger()
        // hudDelay は過ぎたが、休めている指では HUD を出さない
        h.advance(0.4)
        #expect(h.hud.shown.isEmpty)
        h.releaseTrigger()
        await h.settle()

        #expect(h.performer.calls.isEmpty)
        #expect(h.controller.lastExecution == nil)
        #expect(h.haptics.plays.isEmpty)
    }

    /// 「指を離したとき」でも、休めていた親指を離すだけでは実行しない
    @Test func liftingARestingThumbRunsNothingOnFingerLift() async throws {
        let h = try ControllerHarness(configuration: F.configuration(settings: F.settings { $0.fireMode = .onFingerLift }))
        h.start()
        h.touch(1, x: 0.85, y: 0.05)
        h.advance(2)
        h.pressTrigger()
        h.advance(0.4)
        h.lift(1)
        await h.settle()

        #expect(h.performer.calls.isEmpty)
        #expect(h.controller.lastExecution == nil)
    }

    @Test func repeatedFastTapsRunOneAtATimeInOrder() async throws {
        let h = try ControllerHarness()
        h.performer.holds = true
        h.start()
        h.pressTrigger()
        h.tap(0)
        h.tap(2)
        h.tap(8)
        h.releaseTrigger()

        // 触覚は実行を頼んだときに鳴る。実行は前のものが終わるまで始まらない
        #expect(h.haptics.events == [.execute, .execute, .execute])
        await h.waitUntil { h.performer.calls.count == 1 }
        await h.waitUntil { h.performer.calls.count > 1 }
        #expect(h.performer.actions == [F.newTab.action])
        h.performer.releaseOne()
        await h.waitUntil { h.performer.calls.count == 2 }
        await h.waitUntil { h.performer.calls.count > 2 }
        #expect(h.performer.calls.count == 2)
        h.performer.releaseOne()
        await h.waitUntil { h.performer.calls.count == 3 }
        h.performer.releaseOne()
        await h.settle()

        #expect(h.performer.actions == [F.newTab.action, F.closeTab.action, F.reader.action])
        #expect(h.performer.finished == [F.newTab.action, F.closeTab.action, F.reader.action])
        #expect(h.performer.maxRunning == 1)
        #expect(h.hud.toasts.map(\.title) == [F.newTab.title, F.closeTab.title, F.reader.title])
        #expect(h.controller.lastExecution?.cellTitle == F.reader.title)
    }

    /// 何も実行しないが、すぐにタップしたことは届いたと触覚で知らせる
    @Test func anEmptyCellRunsNothingButBuzzes() async throws {
        let h = try ControllerHarness()
        h.start()
        h.fastTap(1)
        await h.settle()

        #expect(h.performer.calls.isEmpty)
        #expect(h.haptics.events == [.rejected])
        #expect(h.hud.toasts.isEmpty)
        #expect(h.controller.lastExecution == nil)
    }

    @Test func anEmptyCellTapStillLetsTheHUDAppearWhenHesitating() async throws {
        let h = try ControllerHarness()
        h.start()
        h.pressTrigger()
        h.tap(1)
        #expect(!h.hud.isVisible)
        // 何も実行していないので、指を置かずに迷っていれば (a) の HUD を出す
        h.advance(Self.placementWindow - 0.15)
        #expect(h.hud.isVisible)
        #expect(h.hud.current?.highlightedIndex == nil)
        h.releaseTrigger()
        await h.settle()
        #expect(h.performer.calls.isEmpty)
        #expect(h.haptics.events == [.rejected])
    }

    // MARK: Nonet 自身が前面のとき

    @Test func buttonsForTheFrontAppDoNotRunWhileANonetWindowIsKey() async throws {
        let h = try ControllerHarness()
        h.start()
        // 設定ウィンドウがキー。前面アプリ（current）は直前の Safari のまま
        h.frontmost.isOwnWindowKey = true
        h.fastTap(2)
        await h.settle()

        // セッションは始まる（タップがクリックとして設定ウィンドウに届かない）が、キーは送らずに知らせる
        #expect(h.keyboard.suppressionChanges == [true, false])
        #expect(h.performer.calls.isEmpty)
        // 実行しなかったことを触覚でも知らせる
        #expect(h.haptics.events == [.rejected])
        let message = ModelFixtures.text("Nonet のウィンドウが前面にあるので実行しませんでした。設定では「このマスをテスト実行」で試せます")
        let title = failureTitle(F.closeTab, profile: "Safari", index: 2, pages: 2)
        #expect(h.hud.toasts == [ToastModel(title: title, detail: message, icon: F.closeTab.icon, style: .failure)])
        let record = try #require(h.controller.lastExecution)
        #expect(record.cellTitle == F.closeTab.title)
        #expect(!record.succeeded)
        #expect(record.message == message)

        // 別のアプリに戻れば使える
        h.frontmost.isOwnWindowKey = false
        h.fastTap(2)
        await h.settle()
        #expect(h.performer.actions == [F.closeTab.action])
    }

    @Test func openAppAndURLButtonsRunWhileANonetWindowIsKey() async throws {
        // 前面アプリに働きかけないマスは、設定ウィンドウがキーでも実行する
        let h = try ControllerHarness(frontmost: F.notesApp)
        h.start()
        h.frontmost.isOwnWindowKey = true
        h.fastTap(0)
        h.fastTap(8)
        await h.settle()

        #expect(h.performer.actions == [F.openNotes.action, F.docs.action])
        #expect(h.hud.toasts.allSatisfy { $0.style == .success })
    }

    @Test func buttonsRunWhileNonetIsActiveWithoutAKeyWindow() async throws {
        // 設定ウィンドウを閉じた後・Finder から開いた直後は Nonet が前面に残るが、キーのウィンドウは無い
        let h = try ControllerHarness()
        h.start()
        h.frontmost.isOwnWindowKey = false
        h.fastTap(2)
        h.fastTap(8)
        await h.settle()

        #expect(h.performer.actions == [F.closeTab.action, F.reader.action])
        #expect(h.hud.toasts.allSatisfy { $0.style == .success })
    }

    @Test func practiceModeRecordsEvenWhileANonetWindowIsKey() async throws {
        // 初回起動の練習は、案内のウィンドウをキーにしたまま行う（何も実行しない）
        let h = try ControllerHarness()
        h.start()
        h.controller.isPracticeMode = true
        h.frontmost.isOwnWindowKey = true
        h.fastTap(2)
        await h.settle()

        #expect(h.performer.calls.isEmpty)
        #expect(h.hud.toasts.isEmpty)
        #expect(h.controller.lastExecution?.cellTitle == F.closeTab.title)
        #expect(h.controller.lastExecution?.succeeded == true)
    }

    // MARK: トラックパッドの確かめ直し

    @Test func startingASessionAsksTheTouchSourceToRevalidate() throws {
        let h = try ControllerHarness()
        h.start()
        h.pressTrigger()
        #expect(h.touchSource.revalidateCount == 1)
        h.releaseTrigger()
        h.pressTrigger()
        #expect(h.touchSource.revalidateCount == 2)
    }

    // MARK: HUD

    @Test func hudShowsUpdatesAndHidesWithTheResolvedPages() async throws {
        let h = try ControllerHarness(configuration: F.configuration(settings: F.settings { $0.hudPosition = .nearCursor }))
        h.start()
        h.pressTrigger()
        h.advance(Self.placementWindow)

        let expectedCells: [HUDCell?] = [
            HUDCell(title: F.newTab.title, icon: F.newTab.icon, detail: detail(F.newTab)),
            nil,
            HUDCell(title: F.closeTab.title, icon: F.closeTab.icon, detail: detail(F.closeTab)),
            nil,
            HUDCell(title: F.summarize.title, icon: F.summarize.icon),
            nil, nil, nil,
            HUDCell(title: F.reader.title, icon: F.reader.icon),
        ]
        let hint = ModelFixtures.text("タップか \(TriggerKey.rightOption.localizedName)を離して実行")
        // グローバルのページは 3枚目から（ページの点をそこで離す）
        let shown = HUDModel(title: "Safari", pageIndex: 0, pageCount: 3, cells: expectedCells, highlightedIndex: nil, hint: hint, globalPagesStart: 2)
        #expect(h.hud.shown == [ControllerFakeHUD.Shown(model: shown, position: .nearCursor)])
        #expect(detail(F.newTab)?.isEmpty == false)

        h.touch(on: 4)
        #expect(h.hud.current?.highlightedIndex == 4)
        h.advance(0.1)
        h.touch(on: 8)
        #expect(h.hud.updates.map(\.highlightedIndex) == [4, 8])
        #expect(h.hud.updates.last == HUDModel(title: "Safari", pageIndex: 0, pageCount: 3, cells: expectedCells, highlightedIndex: 8, hint: hint, globalPagesStart: 2))
        #expect(h.haptics.events == [.boundary])

        h.advance(0.3)
        h.releaseTrigger()
        await h.settle()

        #expect(!h.hud.isVisible)
        #expect(h.hud.hideCount == 1)
        #expect(h.performer.actions == [F.reader.action])
        #expect(h.haptics.events == [.boundary, .execute])
        // HUD から実行したときは、成功のトーストを出さない
        #expect(h.hud.toasts.isEmpty)
        #expect(h.controller.lastExecution?.wasFastTap == false)
        #expect(h.controller.lastExecution?.address == CellAddress(page: 0, index: 8))
    }

    @Test func liftingTheFingerBeforeReleasingCancels() async throws {
        let h = try ControllerHarness()
        h.start()
        h.pressTrigger()
        h.advance(0.3)
        h.touch(on: 4)
        h.advance(0.4)
        h.lift()
        #expect(h.hud.current?.highlightedIndex == nil)
        h.advance(0.1)
        h.releaseTrigger()
        await h.settle()

        #expect(!h.hud.isVisible)
        #expect(h.performer.calls.isEmpty)
        #expect(!h.haptics.events.contains(.execute))
        #expect(!h.keyboard.isSuppressingPointer)
    }

    @Test func onFingerLiftExecutesWhenTheFingerLeaves() async throws {
        let h = try ControllerHarness(configuration: F.configuration(settings: F.settings { $0.fireMode = .onFingerLift }))
        h.start()
        h.pressTrigger()
        h.advance(Self.placementWindow)
        #expect(h.hud.current?.hint == ModelFixtures.text("指を離して実行"))
        h.touch(on: 0)
        h.advance(0.4)
        h.lift()
        #expect(!h.hud.isVisible)
        // トリガーを押したまま。実行はもう頼んである
        #expect(h.keyboard.isSuppressingPointer)
        h.releaseTrigger()
        await h.settle()

        #expect(h.performer.actions == [F.newTab.action])
        #expect(h.controller.lastExecution?.wasFastTap == false)
        #expect(h.hud.toasts.isEmpty)
        #expect(!h.keyboard.isSuppressingPointer)
    }

    @Test func anotherKeyInterruptsWithoutExecuting() async throws {
        let h = try ControllerHarness()
        h.start()
        h.pressTrigger()
        h.advance(Self.placementWindow)
        h.touch(on: 4)
        h.interrupt()
        #expect(!h.hud.isVisible)
        #expect(!h.keyboard.isSuppressingPointer)
        h.advance(0.5)
        h.releaseTrigger()
        await h.settle()

        #expect(h.performer.calls.isEmpty)
        #expect(h.hud.shown.count == 1)
    }

    @Test func aSessionThatOutlastsTheLimitEnds() async throws {
        let h = try ControllerHarness()
        h.start()
        h.pressTrigger()
        h.advance(0.3)
        h.touch(on: 4)
        h.advance(SessionConfiguration.defaultMaxDuration)
        #expect(!h.hud.isVisible)
        #expect(!h.keyboard.isSuppressingPointer)
        // 時間切れの後に離しても何も起きない。タイマーは確かめ直しの1つだけ
        h.releaseTrigger()
        await h.settle()
        #expect(h.performer.calls.isEmpty)
        #expect(h.scheduler.pending.map(\.delay) == [NonetController.pollInterval])
    }

    @Test func twoFingerSwipesTurnPagesAcrossTheAppAndGlobalPages() async throws {
        let h = try ControllerHarness()
        h.start()
        h.pressTrigger()
        h.advance(0.3)

        // 2本の指を左へ動かすと次のページ
        h.touch(1, x: 0.6, y: 0.5)
        h.touch(2, x: 0.7, y: 0.5)
        h.touch(1, x: 0.4, y: 0.5)
        h.touch(2, x: 0.5, y: 0.5)
        #expect(h.hud.current?.pageIndex == 1)
        #expect(h.hud.current?.title == "Safari")
        #expect(h.hud.current?.cells.first??.title == F.reload.title)
        #expect(h.haptics.events == [.pageChange])
        h.lift(1)
        h.lift(2)

        h.touch(1, x: 0.6, y: 0.5)
        h.touch(2, x: 0.7, y: 0.5)
        h.touch(1, x: 0.4, y: 0.5)
        h.touch(2, x: 0.5, y: 0.5)
        #expect(h.hud.current?.pageIndex == 2)
        #expect(h.hud.current?.title == ModelFixtures.globalName)
        h.lift(1)
        h.lift(2)

        h.touch(on: 8)
        h.advance(0.4)
        h.releaseTrigger()
        await h.settle()

        #expect(h.performer.actions == [F.docs.action])
        // 記録はプロファイル内での位置
        #expect(h.controller.lastExecution?.profileName == ModelFixtures.globalName)
        #expect(h.controller.lastExecution?.address == CellAddress(page: 0, index: 8))
    }

    @Test func theSessionKeepsThePagesItStartedWith() async throws {
        let h = try ControllerHarness()
        h.start()
        h.pressTrigger()
        let safariID = try h.profileID(F.safari)
        h.controller.update { configuration in
            configuration.updateProfile(id: safariID) { $0.pages[0].cells[0]?.title = "変えた" }
        }
        h.advance(Self.placementWindow)
        #expect(h.hud.current?.cells.first??.title == F.newTab.title)
        h.releaseTrigger()

        h.pressTrigger()
        h.advance(Self.placementWindow)
        #expect(h.hud.current?.cells.first??.title == "変えた")
    }

    @Test func aTriggerDownWhileTheLastSessionIsDrainingStartsAFreshSession() async throws {
        let h = try ControllerHarness()
        h.start()
        h.pressTrigger()
        h.advance(0.05)
        h.touch(on: 2)
        // 置いたばかりの指が残っているので、前のセッションは指が離れるのを待っている
        h.releaseTrigger()
        h.frontmost.activate(F.notesApp)
        h.advance(0.05)
        h.pressTrigger()
        #expect(h.keyboard.suppressionChanges == [true, false, true])

        // 新しいセッションは押したときの前面アプリ（メモ → グローバル）を使い、残っていた指は速押しにしない
        h.lift()
        h.advance(Self.placementWindow)
        #expect(h.hud.current?.title == ModelFixtures.globalName)
        h.releaseTrigger()
        await h.settle()
        #expect(h.performer.calls.isEmpty)
        #expect(!h.keyboard.isSuppressingPointer)
    }

    @Test func aMissedTriggerUpEndsTheOldSessionBeforeTheNewOne() async throws {
        let h = try ControllerHarness()
        h.start()
        h.pressTrigger()
        h.advance(Self.placementWindow)
        h.touch(on: 4)
        // 離したイベントを取りこぼしたまま、もう一度押された
        h.pressTrigger()
        #expect(!h.hud.isVisible)
        #expect(h.keyboard.isSuppressingPointer)
        #expect(Array(h.recorder.events.suffix(3)) == ["hud:hide", "suppress:off", "suppress:on"])
        h.lift()
        h.advance(Self.placementWindow)
        #expect(h.hud.shown.count == 2)
        h.releaseTrigger()
        await h.settle()
        #expect(h.performer.calls.isEmpty)
    }

    // MARK: ポインタの抑止

    @Test func pointerSuppressionStartsInsideTheTriggerDownCallback() throws {
        let h = try ControllerHarness()
        h.start()
        h.pressTrigger()
        #expect(h.keyboard.suppressionAfterEvent == [true])
        #expect(h.recorder.events.first == "suppress:on")
        h.releaseTrigger()
        #expect(h.keyboard.suppressionChanges == [true, false])
    }

    @Test func suppressionLastsUntilAJustPlacedFingerLeaves() async throws {
        let h = try ControllerHarness()
        h.start()
        h.pressTrigger()
        h.advance(0.05)
        h.touch(on: 2)
        h.advance(0.05)
        // 置いたばかりの指が残っているので、その指が離れるまで抑止を続ける
        h.releaseTrigger()
        #expect(h.keyboard.isSuppressingPointer)
        h.advance(0.05)
        h.lift()
        #expect(!h.keyboard.isSuppressingPointer)
        await h.settle()

        #expect(h.performer.actions == [F.closeTab.action])
        #expect(h.recorder.events.prefix(4) == ["suppress:on", "haptic:execute", "suppress:off", "perform:keystroke"])
    }

    @Test func suppressionEndsWhenAJustPlacedFingerStaysTooLong() async throws {
        let h = try ControllerHarness()
        h.start()
        h.pressTrigger()
        h.advance(0.05)
        h.touch(on: 2)
        h.releaseTrigger()
        #expect(h.keyboard.isSuppressingPointer)
        h.advance(0.3)
        #expect(!h.keyboard.isSuppressingPointer)
        h.lift()
        await h.settle()
        #expect(h.performer.calls.isEmpty)
    }

    @Test func onlyOneTickIsPendingAtATime() throws {
        let h = try ControllerHarness()
        h.start()
        h.pressTrigger()
        h.advance(0.05)
        h.touch(on: 2)
        h.advance(0.05)
        h.touch(on: 5)
        let ticks = { h.scheduler.pending.filter { $0.delay != NonetController.pollInterval } }
        #expect(ticks().count == 1)
        h.lift()
        h.releaseTrigger()
        #expect(ticks().isEmpty)
    }

    @Test func endingRightAfterALiftAsksTheKeyboardToDropLateClicks() async throws {
        let h = try ControllerHarness()
        h.start()
        // 速押しで指を離してからトリガーを離した
        h.fastTap(2)
        // トリガーを指より少し先に離した（指を離したフレームで終わる）
        h.pressTrigger()
        h.advance(0.05)
        h.touch(on: 2)
        h.advance(0.05)
        h.releaseTrigger()
        h.advance(0.03)
        h.lift()
        await h.settle()

        #expect(h.keyboard.lateClickGraces == [true, true])
        #expect(h.performer.actions == [F.closeTab.action, F.closeTab.action])
    }

    @Test func endingWithoutARecentTouchLetsClicksThrough() throws {
        let h = try ControllerHarness()
        h.start()
        // トリガーをほかのキーと組み合わせただけ（右⌘＋C など）
        h.pressTrigger()
        h.advance(0.1)
        h.interrupt()
        h.releaseTrigger()
        // HUD で指を長く置いて離し、しばらくしてからトリガーを離した
        h.pressTrigger()
        h.touch(on: 4)
        h.advance(1)
        h.lift()
        h.advance(1)
        h.releaseTrigger()

        #expect(h.keyboard.lateClickGraces == [false, false])
        #expect(h.keyboard.suppressionChanges == [true, false, true, false])
    }

    // MARK: ライセンス・練習モード

    @Test func anExpiredTrialShowsTheBannerAndRefusesToExecute() async throws {
        let h = try ControllerHarness(trialEnded: true)
        h.start()
        h.pressTrigger()
        h.advance(Self.placementWindow)
        #expect(h.hud.current?.banner == ModelFixtures.text("試用期間が終了しました。メニューバーの Nonet から購入・登録できます"))
        #expect(h.hud.current?.bannerStyle == .warning)
        h.touch(on: 4)
        h.advance(0.4)
        h.releaseTrigger()
        await h.settle()

        let message = NonetError.licenseRequired.errorDescription
        #expect(h.performer.calls.isEmpty)
        #expect(h.haptics.events == [.rejected])
        let title = failureTitle(F.summarize, profile: "Safari", index: 4, pages: 2)
        #expect(h.hud.toasts == [ToastModel(title: title, detail: message, icon: F.summarize.icon, style: .failure)])
        #expect(h.controller.lastExecution?.succeeded == false)
        #expect(h.controller.lastExecution?.message == message)
        #expect(h.controller.lastExecution?.cellTitle == F.summarize.title)
    }

    @Test func anExpiredTrialRefusesFastTapsToo() async throws {
        let h = try ControllerHarness(trialEnded: true)
        h.start()
        h.fastTap(2)
        await h.settle()

        #expect(h.performer.calls.isEmpty)
        #expect(h.hud.toasts.map(\.style) == [.failure])
        #expect(h.controller.lastExecution?.wasFastTap == true)
    }

    @Test func pressingTheTriggerRefreshesTheLicense() async throws {
        let h = try ControllerHarness()
        h.start()
        #expect(h.license.entitlement == .trial(daysLeft: LicenseManager.trialDays))
        h.clock.advance(days: 15)
        // 実行してよいかはいつでも正しい。表示用の entitlement はセッションの開始で新しくなる
        #expect(!h.license.canExecuteActions)
        #expect(h.license.entitlement != .expired)
        h.pressTrigger()
        h.advance(0.01)
        #expect(h.license.entitlement == .expired)
    }

    @Test func theTriggerRefreshesTheLicenseAtMostOncePerInterval() async throws {
        let h = try ControllerHarness()
        h.start()
        let initial = h.licenseStorage.trialWrites
        // ふつうのショートカットでもトリガーの押下は届く。そのたびに試用の記録を書かない
        for _ in 0..<5 {
            h.pressTrigger()
            h.advance(0.5)
            h.releaseTrigger()
            h.advance(0.5)
        }
        #expect(h.licenseStorage.trialWrites == initial + 1)
        h.advance(NonetController.licenseRefreshInterval)
        h.pressTrigger()
        h.advance(0.01)
        #expect(h.licenseStorage.trialWrites == initial + 2)
    }

    @Test func aLicensedTriggerDoesNotRefreshTheTrial() async throws {
        let h = try ControllerHarness(licensed: true)
        guard case .licensed = h.license.entitlement else {
            Issue.record("ライセンスが登録されていない: \(h.license.entitlement)")
            return
        }
        h.start()
        let initial = h.licenseStorage.trialWrites
        h.fastTap(2)
        h.advance(1)
        await h.settle()
        #expect(h.licenseStorage.trialWrites == initial)
        #expect(h.performer.actions == [F.closeTab.action])
    }

    @Test func practiceModeRecordsWithoutPerforming() async throws {
        let h = try ControllerHarness()
        h.start()
        h.controller.isPracticeMode = true
        h.pressTrigger()
        h.advance(Self.placementWindow)
        #expect(h.hud.current?.hint == ModelFixtures.text("練習中 · \(ModelFixtures.text("タップか \(TriggerKey.rightOption.localizedName)を離して実行"))"))
        h.releaseTrigger()
        h.fastTap(2)
        await h.settle()

        #expect(h.performer.calls.isEmpty)
        #expect(h.haptics.events == [.execute])
        #expect(h.hud.toasts.isEmpty)
        let record = try #require(h.controller.lastExecution)
        #expect(record.succeeded)
        #expect(record.cellTitle == F.closeTab.title)
        #expect(record.wasFastTap)
        // 実際には実行していないので、最近の実行には入れない
        #expect(h.controller.recentExecutions.isEmpty)
    }

    @Test func anExpiredTrialAlsoRefusesPracticeTaps() async throws {
        let h = try ControllerHarness(trialEnded: true)
        h.start()
        h.controller.isPracticeMode = true
        h.fastTap(2)
        await h.settle()

        #expect(h.haptics.events == [.rejected])
        #expect(h.hud.toasts.map(\.style) == [.failure])
        #expect(h.controller.lastExecution?.succeeded == false)
    }

    @Test func practiceTapsOnEmptyCellsAreNotRecorded() async throws {
        let h = try ControllerHarness()
        h.start()
        h.controller.isPracticeMode = true
        h.fastTap(1)
        await h.settle()
        #expect(h.controller.lastExecution == nil)
        #expect(h.haptics.events == [.rejected])
    }

    // MARK: 結果とトースト

    @Test func aiOutputGoesToTheResultPanel() async throws {
        let h = try ControllerHarness()
        h.performer.output = { action in
            if case .ai = action { return "要約です" }
            return nil
        }
        h.start()
        h.fastTap(4)
        await h.settle()

        #expect(h.hud.results == [ResultModel(title: F.summarize.title, text: "要約です", icon: F.summarize.icon)])
        #expect(h.hud.toasts.isEmpty)
        #expect(h.controller.lastExecution?.succeeded == true)
    }

    @Test func noSuccessToastWhenExecutionToastsAreOff() async throws {
        let h = try ControllerHarness(configuration: F.configuration(settings: F.settings { $0.showExecutionToast = false }))
        h.start()
        h.fastTap(2)
        await h.settle()

        #expect(h.performer.actions == [F.closeTab.action])
        #expect(h.hud.toasts.isEmpty)
    }

    @Test func failuresAlwaysShowAFailureToast() async throws {
        let h = try ControllerHarness(configuration: F.configuration(settings: F.settings { $0.showExecutionToast = false }))
        let error = NonetError.appNotFound("Safari")
        h.performer.failure = { _ in error }
        h.start()
        h.fastTap(2)
        h.pressTrigger()
        h.advance(0.3)
        h.touch(on: 0)
        h.advance(0.4)
        h.releaseTrigger()
        await h.settle()

        let message = error.errorDescription
        #expect(h.hud.toasts == [
            ToastModel(title: failureTitle(F.closeTab, profile: "Safari", index: 2, pages: 2), detail: message, icon: F.closeTab.icon, style: .failure),
            ToastModel(title: failureTitle(F.newTab, profile: "Safari", index: 0, pages: 2), detail: message, icon: F.newTab.icon, style: .failure),
        ])
        #expect(h.controller.lastExecution?.succeeded == false)
        #expect(h.controller.lastExecution?.message == message)
        #expect(h.controller.lastExecution?.wasFastTap == false)
    }

    // MARK: 触覚

    @Test func hapticsUseTheConfiguredStrengthAndCanBeTurnedOff() async throws {
        let strong = try ControllerHarness(configuration: F.configuration(settings: F.settings { $0.haptics = .strong }))
        strong.start()
        strong.fastTap(2)
        await strong.settle()
        #expect(strong.haptics.plays == [.init(event: .execute, strength: .strong)])

        let off = try ControllerHarness(configuration: F.configuration(settings: F.settings { $0.haptics = .off }))
        off.start()
        off.pressTrigger()
        off.advance(0.3)
        off.touch(on: 4)
        off.touch(on: 8)
        off.advance(0.4)
        off.releaseTrigger()
        await off.settle()
        #expect(off.haptics.plays.isEmpty)
        #expect(off.performer.actions == [F.reader.action])
    }
}
