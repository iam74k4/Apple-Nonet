// 担当: engine
// NonetController が HUD・トースト・結果のパネルに渡すものを作る純粋な関数
import Foundation

/// hint・trialEndedBanner・trialReminderBanner・beginnerFootnote だけ公開する（App の見た目の確認でも、実際と同じ文言を出す）
public enum ControllerPresentation {
    /// page は resolvedPages での位置。範囲外は端に寄せる
    static func hudModel(
        pages: [ResolvedPage],
        page: Int,
        highlightedCell: Int?,
        hint: String,
        banner: String?,
        bannerStyle: HUDBannerStyle = .warning,
        footnote: String? = nil,
        scale: Double = 1
    ) -> HUDModel {
        let index = pages.isEmpty ? 0 : min(max(page, 0), pages.count - 1)
        let resolved = pages.indices.contains(index) ? pages[index] : nil
        let cells = Page(cells: resolved?.cells ?? []).cells.map { $0.map(hudCell) }
        let highlight = highlightedCell.flatMap { (0..<Page.cellCount).contains($0) ? $0 : nil }
        return HUDModel(
            title: resolved?.title ?? "",
            pageIndex: index,
            pageCount: max(pages.count, 1),
            cells: cells,
            highlightedIndex: highlight,
            hint: hint,
            banner: banner,
            bannerStyle: bannerStyle,
            footnote: footnote,
            globalPagesStart: globalPagesStart(pages),
            scale: scale
        )
    }

    /// アプリのページの後ろにつなげたグローバルのページの、最初の位置（resolvedPages の先頭と別のプロファイルの最初のページ）
    static func globalPagesStart(_ pages: [ResolvedPage]) -> Int? {
        guard let first = pages.first else { return nil }
        return pages.firstIndex { $0.profileID != first.profileID }
    }

    static func hudCell(_ cell: Cell) -> HUDCell {
        HUDCell(title: cell.title, icon: cell.icon, detail: detail(for: cell.action))
    }

    /// キー入力のマスだけ「⌘B」のように送るキーを添える
    static func detail(for action: Action) -> String? {
        guard case .keystroke(let keys) = action else { return nil }
        let text = keys.displayString
        return text.isEmpty ? nil : text
    }

    /// HUD の右上の案内。どのキーかまで言う（JIS 配列には⌘が2つある）。「キーを離したとき」でも、短いタップはその場で実行する
    public static func hint(fireMode: FireMode, trigger: TriggerKey, isPracticeMode: Bool) -> String {
        let base = switch fireMode {
        case .onTriggerRelease:
            String(localized: "タップか、\(trigger.localizedName)を離して実行", bundle: .module)
        case .onFingerLift:
            String(localized: "指を離して実行", bundle: .module)
        }
        guard isPracticeMode else { return base }
        return String(localized: "練習中 · \(base)", bundle: .module)
    }

    /// 使い始めの数回（HUDGuidance.beginnerSessionLimit）だけ、9マスの下に出す案内。選び方とやめ方、ページが複数ならページの変え方
    public static func beginnerFootnote(fireMode: FireMode, activation: SessionActivation, trigger: TriggerKey, pageCount: Int) -> String {
        var parts = [String(localized: "指を滑らせて選ぶ", bundle: .module)]
        switch (activation, fireMode) {
        case (.cornerHold, _):
            parts.append(String(localized: "滑らせずに離すとやめる", bundle: .module))
        case (.triggerKey, .onTriggerRelease):
            parts.append(String(localized: "先に指を離してから\(trigger.localizedName)を離すとやめる", bundle: .module))
        case (.triggerKey, .onFingerLift):
            parts.append(String(localized: "やめるときは指を置いたまま左の⇧を押す", bundle: .module))
        }
        if pageCount > 1 {
            parts.append(String(localized: "2本指のスワイプでページを切り替え", bundle: .module))
        }
        // 区切りの「 · 」は言語によらない（HUD の「練習中 · …」と同じ）
        return parts.joined(separator: " · ")
    }

    /// 試用期間が終わった後の帯と、実行しなかったときのトーストの説明。HUD は押せないので、次にする場所を言う
    public static var trialEndedBanner: String {
        NonetError.licenseRequired.localizedDescription
    }

    /// 試用期間の残りが少ないときの帯（注意ではなく知らせ）
    public static func trialReminderBanner(daysLeft: Int) -> String {
        String(localized: "試用期間は残り\(daysLeft)日です", bundle: .module, locale: textLocale)
    }

    /// 試用期間が終わった後に角を長押ししたとき（HUD は出さない）
    static var trialEndedToast: ToastModel {
        ToastModel(
            title: String(localized: "試用期間が終了しました", bundle: .module),
            detail: String(localized: "メニューバーの Nonet から購入・登録できます", bundle: .module),
            style: .failure
        )
    }

    static func successToast(_ cell: Cell) -> ToastModel {
        ToastModel(title: cell.title, icon: cell.icon, style: .success)
    }

    /// 何を実行しようとしたか（どのプロファイルのどのマスか）と、なぜ失敗したか（message）
    static func failureToast(_ target: ControllerTarget, message: String) -> ToastModel {
        ToastModel(title: failureTitle(target), detail: message, icon: target.cell.icon, style: .failure)
    }

    /// 「Safari › 新しいタブ」。プロファイルのページが複数なら「Safari › 再読み込み（2ページ目）」
    static func failureTitle(_ target: ControllerTarget) -> String {
        let profile = target.profileName
        let cell = target.cell.title
        guard !profile.isEmpty else { return cell }
        guard target.profilePageCount > 1 else {
            return String(localized: "\(profile) › \(cell)", bundle: .module)
        }
        return String(localized: "\(profile) › \(cell)（\(target.address.page + 1)ページ目）", bundle: .module, locale: textLocale)
    }

    /// 長く掛かるマスを実行している間のトースト
    static func runningToast(_ cell: Cell) -> ToastModel {
        ToastModel(title: String(localized: "「\(cell.title)」を実行中…", bundle: .module), icon: cell.icon, style: .running)
    }

    static func result(_ cell: Cell, output: String) -> ResultModel {
        ResultModel(title: cell.title, text: output, icon: cell.icon)
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
