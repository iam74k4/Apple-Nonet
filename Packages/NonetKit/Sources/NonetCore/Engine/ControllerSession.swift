// 担当: engine
import Foundation

/// 1回のセッションで使うもの。トリガーを押したときに決め、セッションが終わるまで変えない
/// （途中で前面アプリや設定が変わっても、HUD のマスと実行するマスが食い違わないように）
struct ControllerSession: Equatable, Sendable {
    /// 前面アプリで使うページの並び（resolvedPages）
    let pages: [ResolvedPage]
    /// トリガーを押したときに前面にあったアプリ。アクションはこのアプリに向けて実行する
    let frontmostApp: RunningAppInfo?
    let settings: GlobalSettings
    /// トリガーキーで始めたか、トラックパッドの角の長押しで始めたか
    let activation: SessionActivation
    /// このセッションで HUD を出した（使い始めの案内と試用期間の知らせは、最初に出したときに決める）
    var hasShownHUD = false
    /// 9マスの下に使い始めの案内を出す
    var showsBeginnerHint = false
    /// 試用期間の残り日数を帯で知らせる（そのセッションの間は出したまま）
    var trialReminderDays: Int?

    init(configuration: NonetConfiguration, frontmostApp: RunningAppInfo?, activation: SessionActivation = .triggerKey) {
        pages = configuration.resolvedPages(frontmostBundleID: frontmostApp?.app.bundleID)
        self.frontmostApp = frontmostApp
        settings = configuration.settings
        self.activation = activation
    }

    var engineConfiguration: SessionConfiguration {
        // 空きマスの速押しで 6 の (a) の HUD が止まらないように、中身のあるマスを渡す
        let occupied = pages.map { page in Set(page.cells.indices.filter { page.cells[$0] != nil }) }
        var configuration = SessionConfiguration(settings: settings, pageCount: pages.count, occupiedCells: occupied)
        configuration.activation = activation
        return configuration
    }

    /// page（resolvedPages での位置）の cell 番目のマス。範囲外と空きマスは nil
    func target(page: Int, cell: Int) -> ControllerTarget? {
        guard pages.indices.contains(page) else { return nil }
        let resolved = pages[page]
        guard resolved.cells.indices.contains(cell), let found = resolved.cells[cell] else { return nil }
        return ControllerTarget(
            cell: found,
            profileName: resolved.profileName,
            address: CellAddress(page: resolved.pageIndex, index: cell),
            profileID: resolved.profileID,
            profilePageCount: pages.filter { $0.profileID == resolved.profileID }.count
        )
    }

    /// 角の長押しのセッションは、実行のタイミングの設定に関係なく指を離して実行する
    private var effectiveFireMode: FireMode {
        activation == .cornerHold ? .onFingerLift : settings.fireMode
    }

    func hudModel(page: Int, highlightedCell: Int?, isPracticeMode: Bool, isTrialEnded: Bool) -> HUDModel {
        let banner: (text: String, style: HUDBannerStyle)? = if isTrialEnded {
            (ControllerPresentation.trialEndedBanner, .warning)
        } else if let days = trialReminderDays {
            (ControllerPresentation.trialReminderBanner(daysLeft: days), .info)
        } else {
            nil
        }
        let footnote = showsBeginnerHint
            ? ControllerPresentation.beginnerFootnote(fireMode: effectiveFireMode, activation: activation, trigger: settings.trigger, pageCount: pages.count)
            : nil
        return ControllerPresentation.hudModel(
            pages: pages,
            page: page,
            highlightedCell: highlightedCell,
            hint: ControllerPresentation.hint(fireMode: effectiveFireMode, trigger: settings.trigger, isPracticeMode: isPracticeMode),
            banner: banner?.text,
            bannerStyle: banner?.style ?? .warning,
            footnote: footnote,
            scale: settings.hudScale.factor
        )
    }
}

/// 実行するマスと、ExecutionRecord に残す場所
struct ControllerTarget: Equatable, Sendable {
    var cell: Cell
    var profileName: String
    /// プロファイル内での位置
    var address: CellAddress
    var profileID: UUID?
    /// そのプロファイルのページの数（失敗のトーストで、複数ならページも言う）
    var profilePageCount = 1
}
