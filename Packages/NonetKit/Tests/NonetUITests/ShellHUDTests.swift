// 担当: ui-shell
import CoreGraphics
import NonetCore
@testable import NonetUI
import Testing

@Suite("HUD・トースト・結果のパネル")
@MainActor
struct ShellHUDTests {
    static func model(highlighted: Int? = 4, pageIndex: Int = 0, pageCount: Int = 1, banner: String? = nil, title: String = "Xcode") -> HUDModel {
        let cells: [HUDCell?] = [
            HUDCell(title: "ビルド", icon: .symbol("play.fill"), detail: "⌘B"),
            HUDCell(title: "テスト", icon: .symbol("checkmark.circle")),
            nil,
            HUDCell(title: "ターミナル", icon: .app(bundleID: "com.apple.Terminal")),
            HUDCell(title: "Claude Code", icon: .symbol("sparkles")),
            nil, nil, nil,
            HUDCell(title: "スクショ", icon: .text("S"), detail: "⇧⌘4"),
        ]
        return HUDModel(title: title, pageIndex: pageIndex, pageCount: pageCount, cells: cells, highlightedIndex: highlighted, banner: banner)
    }

    @Test("地図は画面いっぱい: 外枠の帯は実物と同じ割合（左右 11%・奥 17%・手前 15%）で、その内側を 3×3 に等分する")
    func screenLayout() {
        let layout = HUDScreenLayout(size: CGSize(width: 1440, height: 900))
        let frame = GridInsets.cancelFrame
        #expect(layout.bandLeft == 1440 * frame.left && layout.bandRight == 1440 * frame.right)
        #expect(layout.bandTop == 900 * frame.top && layout.bandBottom == 900 * frame.bottom)
        #expect(layout.gridRect == CGRect(x: layout.bandLeft, y: layout.bandTop, width: 1440 - layout.bandLeft - layout.bandRight, height: 900 - layout.bandTop - layout.bandBottom))
        #expect(layout.cellRect(0).origin == layout.gridRect.origin)
        #expect(abs(layout.cellRect(8).maxX - layout.gridRect.maxX) < 1e-9 && abs(layout.cellRect(8).maxY - layout.gridRect.maxY) < 1e-9)
        #expect(abs(layout.cellCenter(4).x - 720) < 1e-9 && abs(layout.cellCenter(4).y - layout.gridRect.midY) < 1e-9)
        // 左右の帯は9マスの段の横（角は含まない）
        #expect(layout.leftBand == CGRect(x: 0, y: layout.gridRect.minY, width: layout.bandLeft, height: layout.gridRect.height))
        #expect(layout.rightBand.maxX == 1440 && layout.rightBand.minY == layout.gridRect.minY)
        #expect(layout.topBand.height == layout.bandTop && layout.bottomBand.maxY == 900)
    }

    @Test("指の位置: トラックパッドの奥（y = 1）が画面の上、左が左。範囲の外は縁に収める")
    func fingerMapsToTheScreen() {
        let layout = HUDScreenLayout(size: CGSize(width: 1000, height: 500))
        #expect(layout.point(for: HUDFinger(x: 0, y: 1)) == .zero)
        #expect(layout.point(for: HUDFinger(x: 1, y: 0)) == CGPoint(x: 1000, y: 500))
        #expect(layout.point(for: HUDFinger(x: 0.5, y: 0.5)) == CGPoint(x: 500, y: 250))
        #expect(layout.point(for: HUDFinger(x: -1, y: 2)) == .zero)
    }

    @Test("開いている間、ポインタは指の位置を画面に写す（主画面の左上が原点）。出していないとき・2本以上の指では動かさない")
    func pointerFollowsTheFinger() {
        let main = HUDScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: CGRect(x: 0, y: 70, width: 1440, height: 805))
        var moved: [CGPoint] = []
        let hud = HUDWindowController(screens: { [main] }, mouseLocation: { CGPoint(x: 10, y: 10) })
        hud.onMovePointer = { moved.append($0) }
        hud.updateFinger(HUDFinger(x: 0.5, y: 0.5))
        #expect(moved.isEmpty)
        hud.show(Self.model())
        hud.updateFinger(HUDFinger(x: 0.5, y: 0.5))
        #expect(moved == [CGPoint(x: 720, y: 450)])
        hud.updateFinger(HUDFinger(x: 0, y: 1))
        #expect(moved.last == .zero)
        hud.updateFinger(nil)
        #expect(moved.count == 2)
        hud.hide()
    }

    @Test("「大きく表示」の倍率は、光らせた札がマスに収まるところまで")
    func fittedScale() {
        #expect(HUDLayout.fittedScale(requested: 1.25, screenSize: CGSize(width: 1440, height: 900)) == 1.25)
        let small = CGSize(width: 800, height: 300)
        let room = HUDScreenLayout(size: small).cellHeight - 2 * HUDLayout.pillMargin
        let fitted = HUDLayout.fittedScale(requested: 1.5, screenSize: small)
        #expect(abs(fitted - min(1.5, room / HUDLayout.highlightedPillHeight)) < 1e-9, "fitted=\(fitted) room=\(room)")
        #expect(HUDLayout.fittedScale(requested: 1.5, screenSize: small) < 1.5)
        #expect(HUDLayout.fittedScale(requested: 0, screenSize: small) == 1)
        // 題名・帯・何に対する操作かの行は、あるぶんだけ高くなる
        let metrics = HUDMetrics(scale: 1)
        var both = Self.model(banner: "帯")
        both.context = "Safari のウインドウ"
        #expect(metrics.rowsHeight(for: both) == HUDLayout.titleHeight + HUDLayout.bannerHeight + HUDLayout.contextHeight + 2 * HUDLayout.rowSpacing)
    }

    @Test("マスの位置の呼び方")
    func positionNames() {
        #expect((0..<9).map(HUDAnnouncement.positionName) == [
            L10n.ui("左上"), L10n.ui("上"), L10n.ui("右上"),
            L10n.ui("左"), L10n.ui("中央"), L10n.ui("右"),
            L10n.ui("左下"), L10n.ui("下"), L10n.ui("右下"),
        ])
        #expect(HUDAnnouncement.positionName(9).isEmpty)
    }

    @Test("読み上げ: マスの名前・キー・位置。空きマスは空きマス")
    func cellDescription() {
        let model = Self.model()
        // マスの名前とキーはテストのデータ。区切りの「、」を含む文と位置の呼び方はカタログから引く
        #expect(HUDAnnouncement.cellDescription(model.cells[0], index: 0) == L10n.ui("\("ビルド")、\("⌘B")、\(L10n.ui("左上"))"))
        #expect(HUDAnnouncement.cellDescription(model.cells[1], index: 1) == L10n.ui("\("テスト")、\(L10n.ui("上"))"))
        #expect(HUDAnnouncement.cellDescription(nil, index: 2) == L10n.ui("空きマス、\(L10n.ui("右上"))"))
    }

    @Test("読み上げ: 最初はプロファイル名とハイライト中のマス")
    func firstAnnouncement() {
        let center = L10n.ui("\("Claude Code")、\(L10n.ui("中央"))")
        #expect(HUDAnnouncement.announcement(from: nil, to: Self.model()) == ["Xcode", center].joined(separator: L10n.ui("、")))
        #expect(HUDAnnouncement.announcement(from: nil, to: Self.model(highlighted: nil)) == "Xcode")
        #expect(HUDAnnouncement.announcement(from: nil, to: Self.model(highlighted: nil, pageCount: 2)) == L10n.ui("\("Xcode")、\(L10n.ui("\(2) ページ中 \(1) ページ目"))"))
    }

    @Test("読み上げ: ハイライトが変わったときだけ。指が離れたら読まない")
    func highlightChanges() {
        let center = Self.model(highlighted: 4)
        #expect(HUDAnnouncement.announcement(from: center, to: center) == nil)
        #expect(HUDAnnouncement.announcement(from: center, to: Self.model(highlighted: 8)) == L10n.ui("\("スクショ")、\("⇧⌘4")、\(L10n.ui("右下"))"))
        #expect(HUDAnnouncement.announcement(from: center, to: Self.model(highlighted: nil)) == nil)
        #expect(HUDAnnouncement.announcement(from: center, to: Self.model(highlighted: 5)) == L10n.ui("空きマス、\(L10n.ui("右"))"))
    }

    @Test("読み上げ: 外枠に入ったら「離すとやめる」、少し長く止めるマスを止め終えたら「離すと実行」")
    func frameAndHoldAnnouncements() {
        let center = Self.model(highlighted: 4)
        var inFrame = Self.model(highlighted: nil)
        inFrame.isFingerInFrame = true
        #expect(HUDAnnouncement.cancelLabel == L10n.ui("離すとやめる"))
        #expect(HUDAnnouncement.announcement(from: center, to: inFrame) == L10n.ui("離すとやめる"))
        // 外枠の中で動いても読み直さない。マスに戻れば、そのマスを読む
        #expect(HUDAnnouncement.announcement(from: inFrame, to: inFrame) == nil)
        #expect(HUDAnnouncement.announcement(from: inFrame, to: center) == L10n.ui("\("Claude Code")、\(L10n.ui("中央"))"))
        // 開いた直後（指は上の外枠）は、プロファイル名と「離すとやめる」
        #expect(HUDAnnouncement.announcement(from: nil, to: inFrame) == ["Xcode", L10n.ui("離すとやめる")].joined(separator: L10n.ui("、")))

        var holding = Self.model(highlighted: 4)
        holding.hold = HUDHold(cellIndex: 4, since: 1, duration: 0.6, isReady: false)
        var ready = holding
        ready.hold?.isReady = true
        #expect(HUDAnnouncement.announcement(from: holding, to: ready) == L10n.ui("離すと実行"))
        #expect(HUDAnnouncement.announcement(from: ready, to: ready) == nil)
    }

    @Test("読み上げ: 左右の外枠でページを切り替えられるときは「止めると次のページ」も言う。切り替えたらページから読み直す")
    func edgePagingAnnouncements() {
        var inFrame = Self.model(highlighted: nil, pageCount: 3)
        inFrame.isFingerInFrame = true
        var onRight = inFrame
        onRight.edgePaging = HUDEdgePaging(edge: .right, since: 1, duration: 0.5)
        let separator = L10n.ui("、")
        #expect(HUDAnnouncement.announcement(from: inFrame, to: onRight) == [L10n.ui("離すとやめる"), L10n.ui("止めると次のページ")].joined(separator: separator))
        var onLeft = onRight
        onLeft.edgePaging?.edge = .left
        #expect(HUDAnnouncement.frameLabel(in: onLeft) == [L10n.ui("離すとやめる"), L10n.ui("止めると前のページ")].joined(separator: separator))
        // 止めている間に進み具合が満ちていくだけなら読み直さない
        var later = onRight
        later.edgePaging?.since = 2
        #expect(HUDAnnouncement.announcement(from: onRight, to: later) == nil)
        // 切り替えたら、ページから読み直す
        var turned = later
        turned.pageIndex = 1
        #expect(HUDAnnouncement.announcement(from: later, to: turned)?.hasPrefix("Xcode") == true)
    }

    @Test("ページを切り替える線の進み具合: 止め始めてからの時間に比例し、0〜1に収まる")
    func pagingBarProgress() {
        #expect(HUDEdgePagingBar.progress(elapsed: 0, duration: 0.5) == 0)
        #expect(HUDEdgePagingBar.progress(elapsed: 0.25, duration: 0.5) == 0.5)
        #expect(HUDEdgePagingBar.progress(elapsed: 0.5, duration: 0.5) == 1)
        #expect(HUDEdgePagingBar.progress(elapsed: 3, duration: 0.5) == 1)
        // 時計が戻った・壊れた値でも、はみ出さない
        #expect(HUDEdgePagingBar.progress(elapsed: -1, duration: 0.5) == 0)
        #expect(HUDEdgePagingBar.progress(elapsed: .nan, duration: 0.5) == 0)
        #expect(HUDEdgePagingBar.progress(elapsed: 0.1, duration: .nan) == 0)
        // 待たない設定（0以下）なら、最初から満ちている
        #expect(HUDEdgePagingBar.progress(elapsed: 0, duration: 0) == 1)
    }

    @Test("ページを切り替える線は、反対側に移ったときと、ページを切り替えて数え直すときに作り直す（満ちたまま残らない）")
    func pagingBarRestartsEachTimeTheDwellStartsAgain() {
        let first = HUDEdgePaging(edge: .right, since: 1, duration: 0.5)
        // 進み具合が満ちていく間（同じ止め始め）は、同じ線のまま
        #expect(HUDEdgePagingBar.restartID(for: first) == HUDEdgePagingBar.restartID(for: HUDEdgePaging(edge: .right, since: 1, duration: 0.5)))
        // ページを切り替えて、次の1ページを数え始めた
        #expect(HUDEdgePagingBar.restartID(for: first) != HUDEdgePagingBar.restartID(for: HUDEdgePaging(edge: .right, since: 1.5, duration: 0.9)))
        // 反対側の外枠に移った
        #expect(HUDEdgePagingBar.restartID(for: first) != HUDEdgePagingBar.restartID(for: HUDEdgePaging(edge: .left, since: 1, duration: 0.5)))
    }

    @Test("題名の横の一言: 練習中だけ「練習中」。少し長く止めるマスを止めていても、文は出さない（マスの輪が見せる）")
    func topNotes() {
        var model = Self.model(highlighted: 4)
        #expect(HUDAnnouncement.topNote(for: model) == nil)
        model.hold = HUDHold(cellIndex: 4, since: 1, duration: 0.45, isReady: false)
        #expect(HUDAnnouncement.topNote(for: model) == nil)
        model.isPractice = true
        #expect(HUDAnnouncement.topNote(for: model) == L10n.ui("練習中"))
    }

    @Test("読み上げ: ページが変わったらページから読み直す")
    func pageChanges() {
        let first = Self.model(highlighted: 4, pageIndex: 0, pageCount: 3)
        let second = Self.model(highlighted: 4, pageIndex: 1, pageCount: 3, title: "グローバル")
        let page = L10n.ui("\("グローバル")、\(L10n.ui("\(3) ページ中 \(2) ページ目"))")
        let cell = L10n.ui("\("Claude Code")、\(L10n.ui("中央"))")
        #expect(HUDAnnouncement.announcement(from: first, to: second) == [page, cell].joined(separator: L10n.ui("、")))
    }

    @Test("ハイライトの番号が範囲外なら読まない")
    func outOfRangeHighlight() {
        #expect(HUDAnnouncement.highlighted(in: Self.model(highlighted: 12)) == nil)
        let short = HUDModel(title: "A", pageIndex: 0, pageCount: 1, cells: [], highlightedIndex: 3)
        #expect(HUDAnnouncement.highlighted(in: short) == L10n.ui("空きマス、\(L10n.ui("左"))"))
    }

    @Test("トーストの表示時間: 成功と案内は一瞬、実行中は時間では消さない", arguments: [
        (ToastModel.Style.success, 0.8 as Double?),
        (.info, 0.8),
        (.running, nil),
    ])
    func toastDuration(style: ToastModel.Style, seconds: Double?) {
        #expect(HUDToastLayout.duration(for: ToastModel(title: "ビルド", detail: String(repeating: "あ", count: 200), style: style)) == seconds)
    }

    /// 失敗は文字数で決める: 1.5秒＋1文字 0.06秒を、3〜8秒に収める（見出しと説明の文字を数える）
    @Test("失敗のトーストは、文が長いほど長く出す")
    func failureToastDurationFollowsTheLength() throws {
        func duration(title: String, detail: String?) throws -> Double {
            try #require(HUDToastLayout.duration(for: ToastModel(title: title, detail: detail, style: .failure)))
        }
        #expect(try duration(title: "A", detail: nil) == 3)
        // 10 + 40 文字 → 1.5 + 0.06 × 50 = 4.5秒
        let medium = try duration(title: String(repeating: "a", count: 10), detail: String(repeating: "b", count: 40))
        #expect(abs(medium - 4.5) < 1e-9)
        #expect(try duration(title: "A", detail: String(repeating: "b", count: 500)) == 8)
    }

    @Test("トーストは時間どおりに消す（失敗は読めるだけ長く）")
    func toastsHideOnTime() {
        let failure = ToastModel(title: "ビルド", detail: "だめ", style: .failure)
        var schedule = HUDToastSchedule()
        let hideAt = schedule.show(failure, at: 10)
        #expect(hideAt == Double(13))
        let beforeDeadline = schedule.deadlineReached(at: 12)
        let atDeadline = schedule.deadlineReached(at: 13)
        #expect(!beforeDeadline)
        #expect(atDeadline)
        var success = HUDToastSchedule()
        let successHideAt = success.show(ToastModel(title: "ビルド", style: .success), at: 0)
        #expect(successHideAt == 0.8)
        let successHides = success.deadlineReached(at: 0.8)
        #expect(successHides)
        success.hidden()
        #expect(success.hideAt == nil)
        // 実行中のトーストは時間では消さない
        var running = HUDToastSchedule()
        let runningHideAt = running.show(ToastModel(title: "要約", style: .running), at: 0)
        #expect(runningHideAt == nil)
        let runningHides = running.deadlineReached(at: 100)
        #expect(!runningHides)
    }

    @Test("トーストのアイコンが無いときの記号")
    func toastFallbackSymbol() {
        #expect(HUDToastLayout.fallbackSymbol(for: .running) == nil)
        #expect(HUDToastLayout.fallbackSymbol(for: .info) == nil)
        #expect(HUDToastLayout.fallbackSymbol(for: .success) == "checkmark.circle.fill")
        #expect(HUDToastLayout.fallbackSymbol(for: .failure) == "exclamationmark.triangle.fill")
    }

    @Test("トーストの読み上げ")
    func toastAnnouncement() {
        #expect(HUDAccessibility.toastAnnouncement(title: "ビルド", detail: "⌘B") == L10n.ui("\("ビルド")、\("⌘B")"))
        #expect(HUDAccessibility.toastAnnouncement(title: "ビルド", detail: nil) == "ビルド")
        #expect(HUDAccessibility.toastAnnouncement(title: "ビルド", detail: "") == "ビルド")
    }

    @Test("結果のパネル: 短い文は最小の高さ、長い文は画面の 3/4 か上限で止める")
    func resultPanelSize() {
        let screen = ShellHUDPlacementTests.main
        let short = HUDResultLayout.panelSize(textHeight: 16, screen: screen)
        #expect(short.width == HUDResultLayout.width)
        #expect(short.height == HUDResultLayout.chromeHeight + HUDResultLayout.minTextAreaHeight)

        let medium = HUDResultLayout.panelSize(textHeight: 200, screen: screen)
        #expect(medium.height == HUDResultLayout.chromeHeight + 200 + 2 * HUDResultLayout.textInset.height)

        let long = HUDResultLayout.panelSize(textHeight: 5000, screen: screen)
        #expect(long.height == HUDResultLayout.maxHeight)

        let small = HUDScreenGeometry(frame: CGRect(x: 0, y: 0, width: 800, height: 500), visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 470))
        let limited = HUDResultLayout.panelSize(textHeight: 5000, screen: small)
        #expect(limited.height == (470 - 2 * HUDPlacement.edgeMargin) * 0.75)
        #expect(limited.height < small.visibleFrame.height)
    }

    @Test("結果の文の高さは行が増えるほど高い")
    func resultTextHeight() {
        let one = HUDResultLayout.textHeight(of: "一行")
        let three = HUDResultLayout.textHeight(of: "一行\n二行\n三行")
        let wrapped = HUDResultLayout.textHeight(of: String(repeating: "とても長い文章です。", count: 40))
        #expect(one > 0)
        #expect(three > one * 2)
        #expect(wrapped > one * 3)
    }

    @Test("画面が無いときは HUD を出さず、update も無視する")
    func noScreens() {
        let hud = HUDWindowController(screens: { [] }, mouseLocation: { .zero })
        hud.show(Self.model())
        #expect(!hud.isShowingHUD)
        hud.update(Self.model(highlighted: 1))
        hud.hide()
        hud.showToast(ToastModel(title: "ビルド"))
        hud.showResult(ResultModel(title: "要約", text: "本文"))
        #expect(!hud.isShowingHUD)
    }

    @Test("視差効果を減らす: メニューバーのアイコンは点滅させず、一度だけ光らせたままにする")
    func calloutPulseRespectsReduceMotion() {
        #expect(MenuBarCallout.pulsePlan(reduceMotion: false) == MenuBarCallout.PulsePlan(steps: 6, interval: 0.25))
        // 2回の切り替え = 光って、steadyHighlightDuration の後に消える
        let steady = MenuBarCallout.pulsePlan(reduceMotion: true)
        #expect(steady == MenuBarCallout.PulsePlan(steps: 2, interval: MenuBarCallout.steadyHighlightDuration))
        #expect(steady.interval >= 1)
    }

    @Test("視差効果を減らす: HUD とトーストはフェードせずにすぐ隠す")
    func faderSkipsFadeWithReduceMotion() {
        let panel = HUDOverlayPanel()
        let fader = HUDPanelFader(panel: panel, reduceMotion: { true })
        fader.show()
        var hidden = false
        fader.hide { hidden = true }
        #expect(hidden)
        #expect(!fader.isShowing)
        #expect(!fader.isFading)
        #expect(!panel.isVisible)

        // ふだんは、見えているパネルを短くフェードしてから隠す
        let animated = HUDPanelFader(panel: HUDOverlayPanel(), reduceMotion: { false })
        animated.show()
        var animatedHidden = false
        let wasVisible = animated.panel.isVisible
        animated.hide { animatedHidden = true }
        if wasVisible {
            #expect(animated.isFading)
            #expect(!animatedHidden)
        }
        animated.hideImmediately()
        #expect(!animated.isFading)
    }

    @Test("出していない HUD の update と hide は何もしない")
    func updateBeforeShow() {
        let hud = HUDWindowController(screens: { [ShellHUDPlacementTests.main] }, mouseLocation: { CGPoint(x: 100, y: 100) })
        hud.update(Self.model())
        hud.hide()
        #expect(!hud.isShowingHUD)
    }

    @Test("結果のパネル: コピーは差し替えた書き込み先に全文を渡し、閉じると中身を消す")
    func resultCopyAndClose() {
        let result = HUDResultPanelController()
        var copied: [String] = []
        result.writeToPasteboard = { copied.append($0) }
        result.copyAll()
        #expect(copied.isEmpty)
        result.close()
        #expect(result.currentResult == nil)
        #expect(!result.isVisible)
    }
}
