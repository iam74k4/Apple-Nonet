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

    @Test("HUD の大きさ: 円を囲む正方形（直径 268）だけ。帯は枠の外に描くので、ページ・帯・外枠・進み具合では変わらない（枠が動かない）")
    func hudSize() {
        let side = RadialLayout.outerRadius * 2
        #expect(HUDLayout.size(for: Self.model()) == CGSize(width: side, height: side))
        #expect(HUDLayout.size(for: Self.model(pageCount: 3)) == HUDLayout.size(for: Self.model()))
        #expect(HUDLayout.size(for: Self.model(pageCount: 2, banner: "試用期間が終了しました")) == HUDLayout.size(for: Self.model()))
        var inFrame = Self.model()
        inFrame.isFingerInFrame = true
        inFrame.hold = HUDHold(cellIndex: 0, duration: 0.6, isReady: false)
        #expect(HUDLayout.size(for: inFrame) == HUDLayout.size(for: Self.model()))
    }

    @Test("向けたまま止めると名前: 中身のあるマスを向けているときだけ。外枠・開いた直後・空きマスでは出さない。待ちは離す判定より長く、少し長く止めるマスより後")
    func dwellLabel() {
        let center = Self.model(highlighted: 4)
        #expect(HUDView.labelCandidate(center) == 4)
        #expect(HUDView.labelText(center, index: 4) == "Claude Code")
        #expect(HUDView.labelCandidate(Self.model(highlighted: 5)) == nil, "空きマス")
        #expect(HUDView.labelCandidate(Self.model(highlighted: nil)) == nil)
        var inFrame = Self.model(highlighted: nil)
        inFrame.isFingerInFrame = true
        #expect(HUDView.labelCandidate(inFrame) == nil)
        var waiting = inFrame
        waiting.isWaitingAtCenter = true
        #expect(HUDView.labelCandidate(waiting) == nil)
        // 別のアイコンへ移った・ページが替わったら数え直す。同じアイコンのままなら目印は変わらない
        #expect(HUDView.labelTimerID(center) == HUDView.labelTimerID(center))
        #expect(HUDView.labelTimerID(center) != HUDView.labelTimerID(Self.model(highlighted: 8)))
        #expect(HUDView.labelTimerID(Self.model(highlighted: 4, pageIndex: 1, pageCount: 2)) != HUDView.labelTimerID(center))
        #expect(HUDLayout.labelDelay > SessionConfiguration.defaultLiftDwell)
        #expect(HUDLayout.labelDelay > SessionConfiguration.defaultHoldDwell)
        // 名前は白い円のすぐ下。下の鍵でも枠の余白（shadowMargin）に収まる
        let metrics = HUDMetrics(scale: 1)
        let bottom = metrics.labelPosition(ofCell: 7)
        #expect(bottom.y + metrics.labelHeight / 2 <= metrics.circleSide + HUDLayout.shadowMargin)
        #expect(bottom.y > metrics.position(ofCell: 7).y + metrics.selectionRadius)
        // 円の下の帯に重なるのは下の鍵だけ。そのときは白い円のすぐ上に出す
        for scale in [1.0, 1.25, 1.5] {
            let scaled = HUDMetrics(scale: scale)
            #expect(scaled.labelOverlapsPillBelow(ofCell: 7))
            #expect((0..<9).filter { scaled.labelOverlapsPillBelow(ofCell: $0) } == [7])
            let above = scaled.labelPosition(ofCell: 7, above: true)
            #expect(above.y + scaled.labelHeight / 2 < scaled.position(ofCell: 7).y - scaled.selectionRadius)
            #expect(above.y - scaled.labelHeight / 2 > scaled.pageDotsPosition.y)
        }
        // 長い名前の幅の上限: 左右の鍵ではパネルの端まで（余白の中）、真ん中ではもっと広い
        let side = metrics.labelMaxWidth(centeredAt: metrics.position(ofCell: 5).x)
        #expect(metrics.position(ofCell: 5).x + side / 2 <= metrics.circleSide + metrics.shadowMargin)
        #expect(metrics.labelMaxWidth(centeredAt: metrics.center.x) > side)
    }

    @Test("層の名前は、真ん中の鍵の下にページの点・案内・真ん中の鍵の名前が出たら、そちらに譲る")
    func theLayerNameGivesWayUnderTheCenter() {
        var model = Self.model(highlighted: nil, pageCount: 2)
        #expect(!HUDView.isSpotUnderCenterTaken(model, inFrame: true, keyLabel: nil))
        model.edgePaging = HUDEdgePaging(edge: .right, since: 1, duration: 0.5)
        #expect(HUDView.isSpotUnderCenterTaken(model, inFrame: true, keyLabel: nil))
        // 上下の帯ではページの点を出さないので、譲らない
        model.edgePaging = HUDEdgePaging(edge: .down, since: 1, duration: 0.5)
        #expect(!HUDView.isSpotUnderCenterTaken(model, inFrame: true, keyLabel: nil))
        model.edgePaging = nil
        model.edgeHint = "案内"
        #expect(HUDView.isSpotUnderCenterTaken(model, inFrame: true, keyLabel: nil))
        model.edgeHint = nil
        #expect(HUDView.isSpotUnderCenterTaken(model, inFrame: false, keyLabel: 4))
        #expect(!HUDView.isSpotUnderCenterTaken(model, inFrame: false, keyLabel: 5))
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
        // ポインタで選ぶ開き方（真ん中から出る前）は、外枠扱いでも「離すとやめる」を言わず、鍵も薄くしない。出てから外枠に入れば言う
        var waiting = inFrame
        waiting.isWaitingAtCenter = true
        #expect(HUDAnnouncement.announcement(from: nil, to: waiting) == "Xcode")
        #expect(HUDAnnouncement.announcement(from: waiting, to: inFrame) == L10n.ui("離すとやめる"))
        #expect(HUDAnnouncement.announcement(from: waiting, to: center) == L10n.ui("\("Claude Code")、\(L10n.ui("中央"))"))
        #expect(!HUDView.dimsKeys(waiting))
        #expect(HUDView.dimsKeys(inFrame))
        #expect(HUDView.dimsKeys(Self.model(highlighted: nil)))
        #expect(!HUDView.dimsKeys(center))

        var holding = Self.model(highlighted: 4)
        holding.hold = HUDHold(cellIndex: 4, since: 1, duration: 0.6, isReady: false)
        var ready = holding
        ready.hold?.isReady = true
        #expect(HUDAnnouncement.announcement(from: holding, to: ready) == L10n.ui("離すと実行"))
        #expect(HUDAnnouncement.announcement(from: ready, to: ready) == nil)
    }

    @Test("読み上げ: 左右の外枠でページを切り替えられるときは「止めると次のページ」も言う。外枠の中で帯に入ったなら、その一言だけ。切り替えたらページから読み直す")
    func edgePagingAnnouncements() {
        var inFrame = Self.model(highlighted: nil, pageCount: 3)
        inFrame.isFingerInFrame = true
        var onRight = inFrame
        onRight.edgePaging = HUDEdgePaging(edge: .right, since: 1, duration: 0.5)
        let separator = L10n.ui("、")
        // 外枠の中から帯に入った:「離すとやめる」はもう読んだので、増えた一言だけ。帯を出て外枠に残っただけなら読まない
        #expect(HUDAnnouncement.announcement(from: inFrame, to: onRight) == L10n.ui("止めると次のページ"))
        #expect(HUDAnnouncement.announcement(from: onRight, to: inFrame) == nil)
        // マスから直に帯に入ったら、続けて読む
        #expect(HUDAnnouncement.announcement(from: Self.model(highlighted: 5, pageCount: 3), to: onRight)
            == [L10n.ui("離すとやめる"), L10n.ui("止めると次のページ")].joined(separator: separator))
        // 切り替える先が無いことの案内も同じ: 出たときにその案内だけを読む
        var hinted = inFrame
        hinted.edgeHint = "案内"
        #expect(HUDAnnouncement.announcement(from: inFrame, to: hinted) == "案内")
        #expect(HUDAnnouncement.announcement(from: hinted, to: inFrame) == nil)
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

    @Test("鍵の位置: 真ん中の鍵は円の中心、8つの鍵は半径 108 の円の上に HUD と同じ並び。倍率を掛けても同じ向き")
    func keyPositions() {
        for scale in [1.0, 1.25] {
            let metrics = HUDMetrics(scale: scale)
            let center = metrics.center
            #expect(center == CGPoint(x: 134 * scale, y: 134 * scale))
            #expect(metrics.position(ofCell: 4) == center)
            let up = metrics.position(ofCell: 1)
            #expect(abs(up.x - center.x) < 1e-9 && abs(up.y - (center.y - 108 * scale)) < 1e-9)
            let right = metrics.position(ofCell: 5)
            #expect(abs(right.x - (center.x + 108 * scale)) < 1e-9 && abs(right.y - center.y) < 1e-9)
            let bottomLeft = metrics.position(ofCell: 6)
            #expect(bottomLeft.x < center.x && bottomLeft.y > center.y)
            #expect(metrics.position(ofCell: 9) == center)
            // 矢印は円の縁の内側、ページの点は真ん中の鍵の下
            #expect(metrics.pageArrowPosition(.right).x + metrics.pageArrowRadius <= metrics.circleSide)
            #expect(metrics.pageArrowPosition(.left).x - metrics.pageArrowRadius >= 0)
            #expect(metrics.pageDotsPosition.y > center.y)
        }
    }

    @Test("出す場所: 開いたときのポインタが円の中心に来る。show は円を囲む正方形の枠（主画面の左上が原点）を返す")
    func shownNextToThePointer() throws {
        let main = HUDScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: CGRect(x: 0, y: 70, width: 1440, height: 805))
        let hud = HUDWindowController(screens: { [main] }, mouseLocation: { CGPoint(x: 700, y: 450) })
        let map = try #require(hud.show(Self.model()))
        #expect(hud.isShowingHUD)
        #expect(hud.mapFrame == map)
        let side = RadialLayout.outerRadius * 2
        #expect(map.size == CGSize(width: side, height: side))
        #expect(abs(map.midX - 700) <= 0.5)
        // 円の中心がポインタ（y は下向きなので 900 − 450）
        #expect(abs(map.midY - (900 - 450)) <= 0.5)
        // 表示中にもう一度 show しても同じ枠
        #expect(hud.show(Self.model(highlighted: 1)) == map)
        hud.hide()
        #expect(hud.mapFrame == nil)
    }

    @Test("帯が付いても大きさは変わらないので、update は枠を返さず、円は動かない")
    func bannersKeepTheFrame() throws {
        let main = HUDScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: CGRect(x: 0, y: 70, width: 1440, height: 805))
        let hud = HUDWindowController(screens: { [main] }, mouseLocation: { CGPoint(x: 700, y: 450) })
        let map = try #require(hud.show(Self.model()))
        #expect(hud.update(Self.model(highlighted: 1)) == nil)
        #expect(hud.update(Self.model(highlighted: 1, banner: "帯")) == nil)
        #expect(hud.mapFrame == map)
        hud.hide()
    }

    @Test("円の下の帯: 試用期間の注意書きがあればそれ、無ければ練習中だけ「練習中」。ふだんは文字を出さない")
    func pillContent() {
        #expect(HUDPillContent.content(for: Self.model()) == nil)
        var practice = Self.model()
        practice.isPractice = true
        #expect(HUDPillContent.content(for: practice) == .practice(L10n.ui("練習中")))
        var banner = practice
        banner.banner = "帯"
        banner.bannerStyle = .info
        #expect(HUDPillContent.content(for: banner) == .banner("帯", .info))
        #expect(HUDPillContent.banner("帯", .warning).symbol == "exclamationmark.triangle.fill")
        #expect(HUDPillContent.banner("帯", .info).symbol == "clock")
        #expect(HUDPillContent.practice("練習中").symbol == nil)
        #expect(HUDPillContent.banner("帯", .info).text == "帯")
        // 何に対する操作かは HUD 全体の呼び方に入れる（文では出さない）
        var context = Self.model()
        context.context = "Safari のウインドウ"
        #expect(HUDAnnouncement.frameTitle(for: context) == ["Xcode", "Safari のウインドウ"].joined(separator: L10n.ui("、")))
        #expect(HUDAnnouncement.frameTitle(for: Self.model()) == "Xcode")
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

    @Test("円の下の一言: 練習中だけ「練習中」。少し長く止めるマスを止めていても、文は出さない（円の縁の線が見せる）")
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

    @Test("トーストの表示時間: 成功は一瞬、実行中は時間では消さない", arguments: [
        (ToastModel.Style.success, 0.8 as Double?),
        (.running, nil),
    ])
    func toastDuration(style: ToastModel.Style, seconds: Double?) {
        #expect(HUDToastLayout.duration(for: ToastModel(title: "ビルド", detail: String(repeating: "あ", count: 200), style: style)) == seconds)
    }

    /// 案内は、説明が無ければ一瞬、説明があれば失敗と同じく読めるだけ（文字数で 3〜8秒）出す。説明は2行まで
    @Test("説明のある案内のトーストは、読めるだけ出す")
    func infoToastWithADetailStaysLongEnoughToRead() {
        #expect(HUDToastLayout.duration(for: ToastModel(title: "ビルド", style: .info)) == HUDToastLayout.briefDuration)
        #expect(HUDToastLayout.duration(for: ToastModel(title: "ビルド", detail: "", style: .info)) == HUDToastLayout.briefDuration)
        let detail = String(repeating: "あ", count: 40)
        let info = HUDToastLayout.duration(for: ToastModel(title: "ビルド", detail: detail, style: .info))
        #expect(info == HUDToastLayout.duration(for: ToastModel(title: "ビルド", detail: detail, style: .failure)))
        #expect((info ?? 0) >= 3)
        #expect(HUDToastLayout.duration(for: ToastModel(title: "A", detail: String(repeating: "b", count: 500), style: .info)) == 8)
        #expect(HUDToastLayout.detailLineLimit(for: .info) == 2)
        #expect(HUDToastLayout.detailLineLimit(for: .failure) == 4)
        #expect(HUDToastLayout.detailLineLimit(for: .success) == 1)
    }

    /// 結果のパネルを開いたときの読み上げは、名前と結果の始めだけ（長い出力をすべて読ませない）
    @Test("結果のパネルの読み上げは、名前と始めの200文字まで")
    func resultAnnouncementIsShort() {
        #expect(HUDAccessibility.resultAnnouncement(title: "要約", text: " 短い結果 \n") == HUDAccessibility.toastAnnouncement(title: "要約", detail: "短い結果"))
        #expect(HUDAccessibility.resultAnnouncement(title: "要約", text: "") == "要約")
        let long = String(repeating: "あ", count: 5000)
        let spoken = HUDAccessibility.resultAnnouncement(title: "要約", text: long)
        let excerpt = String(repeating: "あ", count: HUDAccessibility.resultExcerptLimit)
        #expect(spoken == L10n.ui("\("要約")、\(excerpt)…（続きは結果のパネルで読めます）"))
        #expect(spoken.count < 300)
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
