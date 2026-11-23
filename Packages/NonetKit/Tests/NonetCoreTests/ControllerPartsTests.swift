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
        let model = ControllerPresentation.hudModel(pages: pages, state: SessionHUDState(page: 1, highlightedCell: 0), banner: "帯")
        #expect(model.title == "Safari")
        // ページの番号と数は、いまの層（Safari の 2 ページ）の中で数える
        #expect(model.pageIndex == 1)
        #expect(model.pageCount == 2)
        #expect(model.cells.count == Page.cellCount)
        #expect(model.cells[0]?.title == F.reload.title)
        #expect(model.cells[1...].allSatisfy { $0 == nil })
        #expect(model.highlightedIndex == 0)
        #expect(model.banner == "帯")

        // 範囲外は最後のページ（グローバルの層の 1 ページ目）に寄せる
        let beyond = ControllerPresentation.hudModel(pages: pages, state: SessionHUDState(page: 9, highlightedCell: 12), banner: nil)
        #expect(beyond.pageIndex == 0)
        #expect(beyond.layer == .global)
        #expect(beyond.title == ModelFixtures.globalName)
        #expect(beyond.highlightedIndex == nil)
        #expect(ControllerPresentation.hudModel(pages: pages, state: SessionHUDState(page: -1, highlightedCell: -1), banner: nil).pageIndex == 0)
    }

    @Test func hudModelWithoutPagesIsEmptyButValid() {
        let model = ControllerPresentation.hudModel(pages: [], state: SessionHUDState(page: 0, highlightedCell: nil), banner: nil)
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

    /// 表示名の無いマス（「画面に置く」「ファイル」は作ったとき空のまま。消すこともできる）は、HUD・トースト・結果のパネルで
    /// アクションの説明を名前にする（利用ガイドの「表示名」。「」・「、中央」と出さない）
    @Test(arguments: ["", "  "])
    func cellsWithoutANameUseTheActionSummary(title: String) {
        let place = Cell(title: title, icon: .symbol("macwindow"), action: .placeWindow(PlaceWindowAction(region: .maximize)))
        let name = WindowRegion.maximize.title
        #expect(place.displayTitle == name)
        #expect(ControllerPresentation.hudCell(place).title == name)
        #expect(ControllerPresentation.successToast(place).title == name)
        #expect(ControllerPresentation.runningToast(place).title.contains(name))
        #expect(ControllerPresentation.result(place, output: "x").title == name)
        let target = ControllerTarget(cell: place, profileName: "Safari", address: CellAddress(page: 0, index: 4))
        #expect(ControllerPresentation.failureTitle(target).hasSuffix(name))

        // キー入力のマスは名前が送るキーそのものになるので、VoiceOver 用のキーは重ねない
        let keys = KeySequence.sequence(.key("b", [.command]))
        let bold = Cell(title: title, icon: .symbol("bold"), action: .keystroke(keys))
        #expect(ControllerPresentation.hudCell(bold) == HUDCell(title: keys.displayString, icon: .symbol("bold"), detail: nil))

        // 名前があればそのまま
        #expect(Cell(title: "全画面", icon: .symbol("macwindow"), action: place.action).displayTitle == "全画面")
    }

    /// 試用期間が終わった後の HUD の帯は短く（1行の帯に収まるように）、次にすること（メニューバーの Nonet から購入・登録）は
    /// トーストと実行しなかったときの理由が言う。メニューバーのアイコンが見えないときは、アプリケーションフォルダから開き直すことを言う
    @Test func trialTexts() {
        let ended = ModelFixtures.text("試用期間が終了しました。メニューバーの Nonet から購入・登録できます。")
        #expect(ControllerPresentation.trialEndedBanner == ModelFixtures.text("試用期間が終了しました"))
        #expect(NonetError.licenseRequired.localizedDescription == ended)
        #expect(ControllerPresentation.licenseRequiredMessage(isMenuBarIconVisible: true) == ended)
        #expect(ControllerPresentation.licenseRequiredMessage(isMenuBarIconVisible: false)
            == ModelFixtures.text("試用期間が終了しました。アプリケーションフォルダから Nonet を開くと、設定で購入・登録できます。"))
        #expect(ControllerPresentation.trialReminderBanner(daysLeft: 3) == String(localized: "試用期間は残り\(3)日です", bundle: .nonetCore, locale: ControllerPresentation.textLocale))
        #expect(ControllerPresentation.trialReminderBanner(daysLeft: 1) == String(localized: "試用期間は残り\(1)日です", bundle: .nonetCore, locale: ControllerPresentation.textLocale))
        #expect(ControllerPresentation.trialEndedToast() == ToastModel(
            title: ModelFixtures.text("試用期間が終了しました"),
            detail: ModelFixtures.text("メニューバーの Nonet から購入・登録できます"),
            style: .failure
        ))
        #expect(ControllerPresentation.trialEndedToast(isMenuBarIconVisible: false) == ToastModel(
            title: ModelFixtures.text("試用期間が終了しました"),
            detail: ModelFixtures.text("アプリケーションフォルダから Nonet を開くと、設定で購入・登録できます"),
            style: .failure
        ))
    }

    /// 開けない理由のトーストは、どこで直すかを言う。メニューバーのアイコンが見えないときは、システム設定の場所だけ
    @Test func refusalTexts() {
        let visible = ControllerPresentation.accessibilityNeededToast(isMenuBarIconVisible: true)
        #expect(visible.title == ModelFixtures.text("アクセシビリティの許可が必要です"))
        #expect(visible.detail == ModelFixtures.text("メニューバーの Nonet の「アクセシビリティを許可…」か、システム設定 › プライバシーとセキュリティ › アクセシビリティで Nonet をオンにしてください"))
        #expect(visible.style == .failure)
        let hidden = ControllerPresentation.accessibilityNeededToast(isMenuBarIconVisible: false)
        #expect(hidden.detail == ModelFixtures.text("システム設定 › プライバシーとセキュリティ › アクセシビリティで Nonet をオンにしてください"))
        #expect(ControllerPresentation.secureInputToast.title == ModelFixtures.text("パスワードの入力中は開きません"))
        #expect(ControllerPresentation.secureInputToast.style == .failure)
        #expect(ControllerPresentation.sensitivityHintToast.style == .info)
        #expect(ControllerPresentation.sensitivityHintToast.detail?.isEmpty == false)
    }

    /// アプリのページとグローバルのページは別の層。HUD のページの番号と数は、いまの層の中で数える
    @Test func layersSplitWhereTheProfileChanges() {
        let all = pages(frontmost: F.safari)
        #expect(ControllerPresentation.globalPagesStart(all) == 2)
        #expect(ControllerPresentation.globalPagesStart(pages(frontmost: nil)) == nil)
        #expect(ControllerPresentation.globalPagesStart([]) == nil)
        let app = ControllerPresentation.hudModel(pages: all, state: SessionHUDState(page: 1, highlightedCell: nil), banner: nil)
        #expect(app.layer == .app)
        #expect(app.pageIndex == 1)
        #expect(app.pageCount == 2)
        let global = ControllerPresentation.hudModel(pages: all, state: SessionHUDState(page: 2, highlightedCell: nil, lastTurn: .down), banner: nil)
        #expect(global.layer == .global)
        #expect(global.pageIndex == 0)
        #expect(global.pageCount == all.count - 2)
        #expect(global.lastTurn == .down)
        // アプリのプロファイルが無ければ層は1つ
        let globalOnly = pages(frontmost: nil)
        let only = ControllerPresentation.hudModel(pages: globalOnly, state: SessionHUDState(page: 0, highlightedCell: nil), banner: nil)
        #expect(only.layer == nil)
        #expect(only.pageCount == globalOnly.count)
        // 隣のページの端をのぞかせるのは、同じ層の左右だけ（上下は無い）。層の端からは、同じ層の反対の端のページ
        // （アプリの層の最後のページの右は、グローバルの層ではなくアプリの層の最初のページの左の列）
        let firstPageLeftColumn = [0, 3, 6].map { Page(cells: all[0].cells).cells[$0].map(ControllerPresentation.hudCell) }
        #expect(ControllerPresentation.edgePeek(pages: all, page: 0, edge: .right) != nil)
        #expect(ControllerPresentation.edgePeek(pages: all, page: 1, edge: .right) == firstPageLeftColumn)
        #expect(ControllerPresentation.edgePeek(pages: all, page: 0, edge: .down) == nil)
        // ページが1つの層では、のぞかせる隣のページが無い
        #expect(ControllerPresentation.edgePeek(pages: Array(all.prefix(1)), page: 0, edge: .right) == nil)
    }

    /// 層が1つのときの上下の案内: 前面のアプリのプロファイルが無ければ「まだありません」、「グローバルのページを使う」にしていればそのこと。
    /// 層が2つ・前面のアプリが分からなければ無い。HUD に渡すのは、外枠でエンジンが案内するときだけ
    @Test func theLayerHintSaysWhyThereIsNoOtherLayer() throws {
        let configuration = F.configuration()
        let safari = F.safari.bundleID
        #expect(ControllerPresentation.layerHint(configuration: configuration, pages: pages(frontmost: F.safari), frontmostBundleID: safari) == nil)
        let unknown = "com.example.no-profile"
        #expect(ControllerPresentation.layerHint(configuration: configuration, pages: configuration.resolvedPages(frontmostBundleID: unknown), frontmostBundleID: unknown)
            == ModelFixtures.text("このアプリのページはまだありません"))
        var globalMode = configuration
        let index = try #require(globalMode.appProfileIndex(forBundleID: safari))
        globalMode.profiles[index].mode = .global
        #expect(ControllerPresentation.layerHint(configuration: globalMode, pages: globalMode.resolvedPages(frontmostBundleID: safari), frontmostBundleID: safari)
            == ModelFixtures.text("このアプリはグローバルのページを使います"))
        #expect(ControllerPresentation.layerHint(configuration: configuration, pages: pages(frontmost: nil), frontmostBundleID: nil) == nil)
        // 「このアプリでは使わない」（練習でだけ開く）: ページが無いのではないので言わない
        var offMode = configuration
        offMode.profiles[index].mode = .off
        #expect(ControllerPresentation.layerHint(configuration: offMode, pages: offMode.resolvedPages(frontmostBundleID: safari), frontmostBundleID: safari) == nil)

        // 上下はこの案内、左右（ページが1つの層）は送るページが無いこと
        let below = SessionHUDState(page: 0, highlightedCell: nil, isInFrame: true, edgeHint: .down)
        #expect(ControllerPresentation.hudModel(pages: pages(frontmost: nil), state: below, banner: nil, layerHint: "案内").edgeHint == "案内")
        let beside = SessionHUDState(page: 0, highlightedCell: nil, isInFrame: true, edgeHint: .left)
        #expect(ControllerPresentation.hudModel(pages: pages(frontmost: nil), state: beside, banner: nil, layerHint: "案内").edgeHint
            == ModelFixtures.text("左右に送るページはありません"))
        let plain = SessionHUDState(page: 0, highlightedCell: nil, isInFrame: true)
        #expect(ControllerPresentation.hudModel(pages: pages(frontmost: nil), state: plain, banner: nil, layerHint: "案内").edgeHint == nil)
    }

    /// 外枠と進み具合をそのまま渡す。進み具合は光っているマスのものだけ
    @Test func theHUDModelCarriesTheFrameAndTheHold() {
        let all = pages(frontmost: F.safari)
        let inFrame = ControllerPresentation.hudModel(pages: all, state: SessionHUDState(page: 0, highlightedCell: nil, isInFrame: true), banner: nil)
        #expect(inFrame.isFingerInFrame)
        #expect(inFrame.highlightedIndex == nil)
        let hold = SessionHold(cell: 2, since: 5, duration: 0.6, isReady: false)
        let holding = ControllerPresentation.hudModel(pages: all, state: SessionHUDState(page: 0, highlightedCell: 2, hold: hold), banner: nil)
        #expect(holding.hold == HUDHold(cellIndex: 2, since: 5, duration: 0.6, isReady: false))
        #expect(!holding.isFingerInFrame)
        let elsewhere = ControllerPresentation.hudModel(pages: all, state: SessionHUDState(page: 0, highlightedCell: 4, hold: hold), banner: nil)
        #expect(elsewhere.hold == nil)
    }

    @Test func toastsAndResultsCarryTheCell() {
        #expect(ControllerPresentation.successToast(F.newTab) == ToastModel(title: F.newTab.title, icon: F.newTab.icon, style: .success))
        #expect(ControllerPresentation.result(F.summarize, output: "文") == ResultModel(title: F.summarize.title, text: "文", icon: F.summarize.icon))
        #expect(ControllerPresentation.runningToast(F.summarize) == ToastModel(
            title: ModelFixtures.text("「\(F.summarize.title)」を実行中…"),
            icon: F.summarize.icon,
            style: .running
        ))
        // 止められるマスは、メニューバーで止められることを添える
        #expect(ControllerPresentation.runningToast(F.summarize, stopHint: true).detail == ModelFixtures.text("メニューバーの Nonet から止められます"))
        #expect(ControllerPresentation.stoppedToast(F.summarize) == ToastModel(
            title: ModelFixtures.text("「\(F.summarize.title)」を止めました"),
            icon: F.summarize.icon,
            style: .info
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
        // 中身のあるマスも渡す（空きマスで離したらやめる）。少し長く止めるマスは無い
        let occupied: [Set<Int>] = [[0, 2, 4, 8], [0], [0, 8]]
        // グローバルの層は 3 ページ目から
        // どのページも 9 のボタン（3×3 の升目）
        #expect(session.engineConfiguration == SessionConfiguration(
            pageCount: 3, layerStart: 2, occupiedCells: occupied, holdCells: [[], [], []], pageShapes: [.nine, .nine, .nine]
        ))

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
        let session = ControllerSession(configuration: F.configuration(), frontmostApp: F.safariApp)
        let model = session.hudModel(SessionHUDState(page: 0, highlightedCell: 4), isPracticeMode: false, isTrialEnded: true)
        #expect(model.banner == ControllerPresentation.trialEndedBanner)
        #expect(model.bannerStyle == .warning)
        #expect(model.highlightedIndex == 4)
        #expect(model.scale == 1)
        #expect(model.layer == .app)
        // 下で止めるとグローバルの層へ移れるよう、エンジンに層の境目を渡す
        #expect(session.engineConfiguration.layerStart == 2)
        #expect(session.hudModel(SessionHUDState(page: 0, highlightedCell: nil), isPracticeMode: true, isTrialEnded: false).banner == nil)
    }

    /// 試用期間の残り日数（知らせの見た目）・HUD の大きさは、セッションで決めたとおりに出す
    @Test func theHUDModelCarriesTheGuidanceAndTheScale() {
        let settings = F.settings { $0.hudScale = .extraLarge }
        var session = ControllerSession(configuration: F.configuration(settings: settings), frontmostApp: F.safariApp)
        session.trialReminderDays = 2
        let model = session.hudModel(SessionHUDState(page: 0, highlightedCell: nil), isPracticeMode: false, isTrialEnded: false)
        #expect(model.banner == ControllerPresentation.trialReminderBanner(daysLeft: 2))
        #expect(model.bannerStyle == .info)
        #expect(model.scale == 1.5)
        // 試用期間が終わっていれば、終わった帯を出す
        #expect(session.hudModel(SessionHUDState(page: 0, highlightedCell: nil), isPracticeMode: false, isTrialEnded: true).banner == ControllerPresentation.trialEndedBanner)
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

    /// 中身で見分けられる設定（variant ごとに HUD の大きさ・触覚の強さの組が違う）
    private func configuration(variant: Double) -> NonetConfiguration {
        let scales = HUDScale.allCases
        let strengths = HapticStrength.allCases
        let step = Int((variant * 10).rounded())
        return NonetConfiguration(settings: GlobalSettings(haptics: strengths[step % strengths.count], hudScale: scales[step / strengths.count % scales.count]), profiles: [])
    }

    @Test func writesTheLatestConfigurationOnceAfterTheInterval() {
        let scheduler = ControllerFakeScheduler()
        let writes = Writes()
        let saver = makeSaver(writes, scheduler: scheduler)
        saver.schedule(configuration(variant: 0.2))
        scheduler.advance(by: 0.3)
        saver.schedule(configuration(variant: 0.4))
        #expect(saver.hasPendingSave)
        #expect(writes.saved.isEmpty)
        scheduler.advance(by: 0.2)
        #expect(writes.saved == [configuration(variant: 0.4)])
        #expect(!saver.hasPendingSave)
        #expect(scheduler.pending.isEmpty)
    }

    @Test func flushAndSaveNowWriteImmediately() {
        let scheduler = ControllerFakeScheduler()
        let writes = Writes()
        let saver = makeSaver(writes, scheduler: scheduler)
        saver.schedule(configuration(variant: 0.2))
        saver.flush()
        #expect(writes.saved == [configuration(variant: 0.2)])
        #expect(scheduler.pending.isEmpty)
        saver.flush()
        #expect(writes.saved.count == 1)
        saver.saveNow(configuration(variant: 0.5))
        #expect(writes.saved.count == 2)
    }

    @Test func reportsResults() {
        let scheduler = ControllerFakeScheduler()
        let writes = Writes()
        let saver = makeSaver(writes, scheduler: scheduler)
        var results: [Bool] = []
        saver.onResult = { results.append((try? $0.get()) != nil) }
        saver.saveNow(configuration(variant: 0.2))
        writes.error = ConfigurationStoreError.writeFailed(reason: "x")
        saver.saveNow(configuration(variant: 0.3))
        #expect(results == [true, false])
        // 失敗しても、次の変更でまた書こうとする
        writes.error = nil
        saver.schedule(configuration(variant: 0.4))
        scheduler.advance(by: 1)
        #expect(results == [true, false, true])
    }

    /// 書けなかった設定は捨てず、間を空けて書き直す。終了時の flush（stop()）でも書き直す
    @Test func aFailedSaveIsKeptAndRetried() {
        let scheduler = ControllerFakeScheduler()
        let writes = Writes()
        let saver = makeSaver(writes, scheduler: scheduler)
        writes.error = ConfigurationStoreError.writeFailed(reason: "disk full")
        saver.schedule(configuration(variant: 0.2))
        scheduler.advance(by: 0.5)
        #expect(saver.hasPendingSave)
        #expect(saver.failureCount == 1)
        // 失敗が続くと、書き直すまでの間を延ばす（2秒・4秒…1分まで）
        scheduler.advance(by: ControllerConfigurationSaver.firstRetryInterval)
        #expect(saver.failureCount == 2)
        #expect(saver.retryInterval == ControllerConfigurationSaver.firstRetryInterval * 2)
        #expect(scheduler.pending.map(\.delay) == [ControllerConfigurationSaver.firstRetryInterval * 2])
        // 空きができたら、次の書き直しで書ける
        writes.error = nil
        scheduler.advance(by: ControllerConfigurationSaver.firstRetryInterval * 2)
        #expect(writes.saved == [configuration(variant: 0.2)])
        #expect(!saver.hasPendingSave)
        #expect(saver.failureCount == 0)
        #expect(scheduler.pending.isEmpty)
    }

    /// 書き直しを待たずに終了しても（flush）、待っている設定を書く。書き直しを待つ間の変更は、いつもの間で書く
    @Test func aFailedSaveIsWrittenByTheNextFlush() {
        let scheduler = ControllerFakeScheduler()
        let writes = Writes()
        let saver = makeSaver(writes, scheduler: scheduler)
        writes.error = ConfigurationStoreError.writeFailed(reason: "disk full")
        saver.saveNow(configuration(variant: 0.2))
        writes.error = nil
        // アプリの終了（NonetController.stop()）と同じ
        saver.flush()
        #expect(writes.saved == [configuration(variant: 0.2)])

        writes.error = ConfigurationStoreError.writeFailed(reason: "disk full")
        saver.saveNow(configuration(variant: 0.3))
        writes.error = nil
        saver.schedule(configuration(variant: 0.4))
        scheduler.advance(by: ControllerConfigurationSaver.defaultInterval)
        #expect(writes.saved == [configuration(variant: 0.2), configuration(variant: 0.4)])
        #expect(scheduler.pending.isEmpty)
    }

    @Test func retryIntervalIsCapped() {
        let scheduler = ControllerFakeScheduler()
        let writes = Writes()
        writes.error = ConfigurationStoreError.writeFailed(reason: "disk full")
        let saver = makeSaver(writes, scheduler: scheduler)
        saver.saveNow(configuration(variant: 0.2))
        for _ in 0..<10 {
            saver.flush()
        }
        #expect(saver.retryInterval == ControllerConfigurationSaver.maxRetryInterval)
        // 読めないファイルを守るために止めたら、待っている設定も書き直しも捨てる
        saver.isEnabled = false
        #expect(!saver.hasPendingSave)
        #expect(scheduler.pending.isEmpty)
    }

    @Test func aDisabledSaverDropsEverything() {
        let scheduler = ControllerFakeScheduler()
        let writes = Writes()
        let saver = makeSaver(writes, scheduler: scheduler)
        saver.schedule(configuration(variant: 0.2))
        saver.isEnabled = false
        #expect(!saver.hasPendingSave)
        saver.schedule(configuration(variant: 0.3))
        saver.saveNow(configuration(variant: 0.4))
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

    /// 後から長い時間を頼んでも、前に決めた時間より遅くはしない（テスト実行の前面に出す待ちと実行の待ちで、holdLimit を超えて待たせない）
    @Test func aLaterCallNeverPushesTheDeadlineBack() async {
        let queue = ControllerExecutionQueue(scheduler: scheduler)
        let latch = ControllerFakeLatch()
        var started: [String] = []
        queue.enqueue { turn in
            started.append("a")
            turn.pass(after: 1)
            turn.pass(after: 5)
            await latch.wait()
        }
        queue.enqueue { _ in
            started.append("b")
        }
        await controllerWaitUntil { started == ["a"] }
        scheduler.advance(by: 1)
        await controllerWaitUntil { started.count > 1 }
        #expect(started == ["a", "b"])
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
