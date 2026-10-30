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
        #expect(HUDLayout.size(for: Self.model()) == CGSize(width: 504, height: 315))
        #expect(HUDLayout.size(for: Self.model(pageCount: 3)) == CGSize(width: 504, height: 340))
        let both = HUDLayout.size(for: Self.model(pageCount: 2, banner: "試用期間が終了しました"))
        #expect(both == CGSize(width: 504, height: 380))
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

    @Test("失敗のトーストは、トリガーキーを押している間は消さず、離してから少しして消す")
    func failureToastWaitsForTheTriggerRelease() {
        let failure = ToastModel(title: "ビルド", detail: "だめ", style: .failure)
        var schedule = HUDToastSchedule()
        let hideAt = schedule.show(failure, at: 10)
        #expect(hideAt == Double(13))
        _ = schedule.setTriggerHeld(true, at: 11)
        let beforeDeadline = schedule.deadlineReached(at: 12)
        let atDeadlineWhileHeld = schedule.deadlineReached(at: 13)
        #expect(!beforeDeadline)
        #expect(!atDeadlineWhileHeld)
        #expect(schedule.waitsForRelease)
        let afterRelease = schedule.setTriggerHeld(false, at: 20)
        #expect(afterRelease == 20 + HUDToastSchedule.afterRelease)
        let hidesAfterRelease = schedule.deadlineReached(at: 21)
        #expect(hidesAfterRelease)

        // 押していなければ、時間どおりに消す。成功のトーストは押していても消す
        var plain = HUDToastSchedule()
        _ = plain.show(failure, at: 0)
        let plainHides = plain.deadlineReached(at: 3)
        #expect(plainHides)
        var success = HUDToastSchedule()
        _ = success.setTriggerHeld(true, at: 0)
        let successHideAt = success.show(ToastModel(title: "ビルド", style: .success), at: 0)
        #expect(successHideAt == 0.8)
        let successHides = success.deadlineReached(at: 0.8)
        #expect(successHides)
        let successRelease = success.setTriggerHeld(false, at: 1)
        #expect(successRelease == nil)
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
