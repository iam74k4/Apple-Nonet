// 担当: engine
// NonetController が HUD・トースト・結果のパネルに渡すものを作る純粋な関数
import Foundation

/// trialEndedBanner・trialReminderBanner・layerHint だけ公開する（App の見た目の確認でも、実際と同じ文言を出す）
public enum ControllerPresentation {
    /// page は resolvedPages での位置。範囲外は端に寄せる。HUD のページの番号と数は、いまの層（アプリかグローバル）の中で数える。
    /// layerHint は上下の帯の案内（layerHint(configuration:pages:frontmostBundleID:)）。左右の帯の案内は sidePageHint
    static func hudModel(
        pages: [ResolvedPage],
        state: SessionHUDState,
        frontmostApp: AppReference? = nil,
        isPractice: Bool = false,
        banner: String?,
        bannerStyle: HUDBannerStyle = .warning,
        scale: Double = 1,
        isWaitingAtCenter: Bool = false,
        layerHint: String? = nil
    ) -> HUDModel {
        let index = pages.isEmpty ? 0 : min(max(state.page, 0), pages.count - 1)
        let resolved = pages.indices.contains(index) ? pages[index] : nil
        let cells = Page(cells: resolved?.cells ?? []).cells.map { $0.map(hudCell) }
        let highlight = state.highlightedCell.flatMap { (0..<Page.cellCount).contains($0) ? $0 : nil }
        let hold = state.hold.flatMap { hold in
            hold.cell == highlight ? HUDHold(cellIndex: hold.cell, since: hold.since, duration: hold.duration, isReady: hold.isReady) : nil
        }
        let layers = layers(of: pages, at: index)
        return HUDModel(
            title: resolved?.title ?? "",
            pageIndex: index - layers.range.lowerBound,
            pageCount: max(layers.range.count, 1),
            cells: cells,
            highlightedIndex: highlight,
            isFingerInFrame: state.isInFrame,
            hold: hold,
            edgePaging: state.isInFrame ? state.edgePaging.map { HUDEdgePaging(edge: $0.edge, since: $0.since, duration: $0.duration) } : nil,
            isHighlightOnBoundary: highlight != nil && state.isOnBoundary,
            context: context(of: resolved, frontmostApp: frontmostApp),
            edgePeek: state.isInFrame ? edgePeek(pages: pages, page: index, edge: state.edgePaging?.edge) : nil,
            isPractice: isPractice,
            banner: banner,
            bannerStyle: bannerStyle,
            layer: layers.layer,
            lastTurn: state.lastTurn,
            scale: scale,
            isWaitingAtCenter: state.isInFrame && isWaitingAtCenter,
            edgeHint: state.isInFrame ? state.edgeHint.flatMap { $0 == .left || $0 == .right ? sidePageHint : layerHint } : nil
        )
    }

    /// ページが1つの層で、左右の帯に止めたら出す案内
    static var sidePageHint: String {
        String(localized: "左右に送るページはありません", bundle: .module)
    }

    /// 層が1つ（グローバルのページだけ）のときに、上下の帯に止めたら出す案内。前面のアプリにプロファイルが無ければ「ページはまだありません」、
    /// プロファイルを「グローバルのページを使う」にしていればそのこと。層が2つ・前面のアプリが分からなければ nil
    public static func layerHint(configuration: NonetConfiguration, pages: [ResolvedPage], frontmostBundleID: String?) -> String? {
        guard globalPagesStart(pages) == nil, let bundleID = frontmostBundleID?.trimmedNonEmpty else { return nil }
        if let index = configuration.appProfileIndex(forBundleID: bundleID) {
            switch configuration.profiles[index].mode {
            case .global:
                return String(localized: "このアプリはグローバルのページを使います", bundle: .module)
            case .off:
                // 「このアプリでは使わない」（ふだんは開かない。初回の案内の練習でだけ開く）: ページが無いのではないので、何も言わない
                return nil
            case .profile:
                break
            }
        }
        return String(localized: "このアプリのページはまだありません", bundle: .module)
    }

    /// index のページがある層と、その層のページの範囲（resolvedPages での位置）。アプリのプロファイルが無く層が1つなら、layer は nil で範囲はすべて
    static func layers(of pages: [ResolvedPage], at index: Int) -> (layer: HUDLayer?, range: Range<Int>) {
        guard let start = globalPagesStart(pages) else { return (nil, 0..<max(pages.count, 1)) }
        return index < start ? (.app, 0..<start) : (.global, start..<pages.count)
    }

    /// 何に対する操作かの帯。「画面に置く」のページなら、前面のアプリのウインドウ
    static func context(of page: ResolvedPage?, frontmostApp: AppReference?) -> String? {
        guard let page, page.cells.contains(where: { if case .placeWindow? = $0?.action { true } else { false } }) else { return nil }
        guard let name = frontmostApp?.name.trimmedNonEmpty else {
            return String(localized: "前面のウインドウ", bundle: .module)
        }
        return String(localized: "\(name) のウインドウ", bundle: .module)
    }

    /// 左右の外枠に指を止めている側の、隣のページの端の列（右なら次のページの左の列、左なら前のページの右の列。上の段から）。
    /// 同じ層の中だけで、端のページからは反対の端のページ（PageEdge.neighbor）。上下（層の切り替え）・ページが1つの層は nil
    static func edgePeek(pages: [ResolvedPage], page: Int, edge: PageEdge?) -> [HUDCell?]? {
        guard let edge, let neighbor = edge.neighbor(of: page, in: layers(of: pages, at: page).range),
              pages.indices.contains(neighbor) else { return nil }
        let cells = Page(cells: pages[neighbor].cells).cells
        let column = edge == .right ? 0 : 2
        return [0, 1, 2].map { row in cells[row * 3 + column].map(hudCell) }
    }

    /// アプリのページの後ろにつなげたグローバルのページの、最初の位置（resolvedPages の先頭と別のプロファイルの最初のページ）。
    /// グローバルの層の始まり（SessionConfiguration.layerStart）
    static func globalPagesStart(_ pages: [ResolvedPage]) -> Int? {
        guard let first = pages.first else { return nil }
        return pages.firstIndex { $0.profileID != first.profileID }
    }

    static func hudCell(_ cell: Cell) -> HUDCell {
        let title = cell.displayTitle
        // 表示名が空のキー入力のマスは、名前が送るキーそのもの（「⌘B」）。VoiceOver で同じものを2回読ませない
        let keys = detail(for: cell.action).flatMap { $0 == title ? nil : $0 }
        return HUDCell(title: title, icon: cell.icon, detail: keys, requiresHold: cell.requiresHold)
    }

    /// キー入力のマスだけ「⌘B」のように送るキーを添える
    static func detail(for action: Action) -> String? {
        guard case .keystroke(let keys) = action else { return nil }
        let text = keys.displayString
        return text.isEmpty ? nil : text
    }



    /// HUD の上の帯（1行で、幅が狭い）。次にすることは、開かなかったときのトースト（trialEndedToast）が言う
    public static var trialEndedBanner: String {
        String(localized: "試用期間が終了しました", bundle: .module)
    }

    /// 試用期間が終わっていて実行しなかったときのトーストの説明と、その記録の理由。HUD は押せないので、次にする場所を言う。
    /// メニューバーのアイコンが見えない（ノッチの陰など）ときは、アプリケーションフォルダから開き直す（設定が開く）ことを言う
    static func licenseRequiredMessage(isMenuBarIconVisible: Bool) -> String {
        guard !isMenuBarIconVisible else { return NonetError.licenseRequired.localizedDescription }
        return String(localized: "試用期間が終了しました。アプリケーションフォルダから Nonet を開くと、設定で購入・登録できます。", bundle: .module)
    }

    /// 試用期間の残りが少ないときの帯（注意ではなく知らせ）
    public static func trialReminderBanner(daysLeft: Int) -> String {
        String(localized: "試用期間は残り\(daysLeft)日です", bundle: .module, locale: textLocale)
    }

    /// 設定や案内のウィンドウが前面のときに、上の縁から指を滑らせたとき（9マスは開かない。起動してから1回だけ知らせる）
    static var ownWindowToast: ToastModel {
        ToastModel(
            title: String(localized: "Nonet のウインドウが前面のときは、9マスは開きません", bundle: .module),
            detail: String(localized: "ほかのアプリの上で試してください", bundle: .module),
            style: .info
        )
    }

    /// 試用期間が終わった後に、上の縁から指を滑らせたとき（9マスは開かない）。
    /// メニューバーのアイコンが見えないときは、アプリケーションフォルダから開き直すことを言う
    static func trialEndedToast(isMenuBarIconVisible: Bool = true) -> ToastModel {
        ToastModel(
            title: String(localized: "試用期間が終了しました", bundle: .module),
            detail: isMenuBarIconVisible
                ? String(localized: "メニューバーの Nonet から購入・登録できます", bundle: .module)
                : String(localized: "アプリケーションフォルダから Nonet を開くと、設定で購入・登録できます", bundle: .module),
            style: .failure
        )
    }

    /// アクセシビリティの許可が無いときに、上の縁から指を滑らせたとき（9マスは開かない）。どこでオンにするかを言う
    static func accessibilityNeededToast(isMenuBarIconVisible: Bool = true) -> ToastModel {
        ToastModel(
            title: String(localized: "アクセシビリティの許可が必要です", bundle: .module),
            detail: isMenuBarIconVisible
                ? String(localized: "メニューバーの Nonet の「アクセシビリティを許可…」か、システム設定 › プライバシーとセキュリティ › アクセシビリティで Nonet をオンにしてください", bundle: .module)
                : String(localized: "システム設定 › プライバシーとセキュリティ › アクセシビリティで Nonet をオンにしてください", bundle: .module),
            style: .failure
        )
    }

    /// パスワードの入力中（セキュア入力）に、上の縁から指を滑らせたとき（9マスは開かない）。
    /// どのアプリがセキュア入力にしているかは、macOS から分からないので言わない
    static var secureInputToast: ToastModel {
        ToastModel(
            title: String(localized: "パスワードの入力中は開きません", bundle: .module),
            detail: String(localized: "パスワード欄から離れるか、ターミナルの「セキュアキーボード入力」をオフにすると開きます", bundle: .module),
            style: .failure
        )
    }

    /// 開いてすぐ指を離して閉じることが続いたとき（AccidentalOpenTracker）に、1回だけ出す案内
    static var sensitivityHintToast: ToastModel {
        ToastModel(
            title: String(localized: "思わず開いてしまうときは", bundle: .module),
            detail: String(localized: "設定の「一般」›「開きやすさ」を「控えめ」にすると開きにくくなります", bundle: .module),
            style: .info
        )
    }

    static func successToast(_ cell: Cell) -> ToastModel {
        ToastModel(title: cell.displayTitle, icon: cell.icon, style: .success)
    }

    /// 何を実行しようとしたか（どのプロファイルのどのマスか）と、なぜ失敗したか（message）
    static func failureToast(_ target: ControllerTarget, message: String) -> ToastModel {
        ToastModel(title: failureTitle(target), detail: message, icon: target.cell.icon, style: .failure)
    }

    /// 「Safari › 新しいタブ」。プロファイルのページが複数なら「Safari › 再読み込み（2ページ目）」
    static func failureTitle(_ target: ControllerTarget) -> String {
        let profile = target.profileName
        let cell = target.cell.displayTitle
        guard !profile.isEmpty else { return cell }
        guard target.profilePageCount > 1 else {
            return String(localized: "\(profile) › \(cell)", bundle: .module)
        }
        return String(localized: "\(profile) › \(cell)（\(target.address.page + 1)ページ目）", bundle: .module, locale: textLocale)
    }

    /// 長く掛かるマスを実行している間のトースト。止められるマスで、メニューバーのアイコンが見えていれば、そこで止められることを添える
    static func runningToast(_ cell: Cell, stopHint: Bool = false) -> ToastModel {
        ToastModel(
            title: String(localized: "「\(cell.displayTitle)」を実行中…", bundle: .module),
            detail: stopHint ? String(localized: "メニューバーの Nonet から止められます", bundle: .module) : nil,
            icon: cell.icon,
            style: .running
        )
    }

    /// メニューの「実行中の「◯◯」を止める」で止めたとき
    static func stoppedToast(_ cell: Cell) -> ToastModel {
        ToastModel(title: String(localized: "「\(cell.displayTitle)」を止めました", bundle: .module), icon: cell.icon, style: .info)
    }

    /// 止めた実行の記録の理由（最近の実行・設定のテスト実行に出す）
    static var stoppedMessage: String {
        String(localized: "止めました", bundle: .module)
    }

    /// 最近の実行で選んだ、失敗した実行の理由の全文（結果のパネルに出す。選んでコピーできる）
    static func failureResult(_ record: ExecutionRecord, message: String) -> ResultModel {
        let title = record.profileName.isEmpty
            ? record.cellTitle
            : String(localized: "\(record.profileName) › \(record.cellTitle)", bundle: .module)
        return ResultModel(title: title, text: message, icon: .symbol("exclamationmark.triangle"))
    }

    static func result(_ cell: Cell, output: String) -> ResultModel {
        ResultModel(title: cell.displayTitle, text: output, icon: cell.icon)
    }

    /// NonetCore の文言に実際に使われている言語に、今の地域を合わせたロケール。数の入る文の単数・複数を、文言の言語の規則で選ぶ
    /// （地域が日本でアプリだけ英語のときに「1 days」にしない）
    static var textLocale: Locale {
        guard let language = Bundle.module.preferredLocalizations.first, !language.isEmpty else { return .current }
        var components = Locale.Components(identifier: language)
        if components.region == nil {
            components.region = Locale.current.region
        }
        return Locale(components: components)
    }
}
