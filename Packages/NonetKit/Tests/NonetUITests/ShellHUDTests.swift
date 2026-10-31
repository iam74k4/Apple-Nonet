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
        return HUDModel(title: title, pageIndex: pageIndex, pageCount: pageCount, cells: cells, highlightedIndex: highlighted, hint: "⌘を離して実行", banner: banner)
    }

    @Test("HUD の大きさはモックどおり。帯とページの点の分だけ高くなる")
    func hudSize() {
        // 9マスの周りの外枠（奥 14・手前 12）の分だけ、モックより高い
        #expect(HUDLayout.size(for: Self.model()) == CGSize(width: 504, height: 341))
        #expect(HUDLayout.size(for: Self.model(pageCount: 3)) == CGSize(width: 504, height: 366))
        let both = HUDLayout.size(for: Self.model(pageCount: 2, banner: "試用期間が終了しました"))
        #expect(both == CGSize(width: 504, height: 406))
        // 外枠に指があるか・進み具合では大きさは変わらない
        var inFrame = Self.model()
        inFrame.isFingerInFrame = true
        inFrame.hold = HUDHold(cellIndex: 0, duration: 0.6, isReady: false)
        #expect(HUDLayout.size(for: inFrame) == HUDLayout.size(for: Self.model()))
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
        let short = HUDModel(title: "A", pageIndex: 0, pageCount: 1, cells: [], highlightedIndex: 3, hint: "")
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
        hud.show(Self.model(), position: .screenCenter)
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
