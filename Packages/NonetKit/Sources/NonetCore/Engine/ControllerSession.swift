// 担当: engine
import Foundation

/// 1回のセッションで使うもの。9マスを開いたときに決め、セッションが終わるまで変えない
/// （途中で前面アプリや設定が変わっても、HUD のマスと実行するマスが食い違わないように）
struct ControllerSession: Equatable, Sendable {
    /// 前面アプリで使うページの並び（resolvedPages）
    let pages: [ResolvedPage]
    /// 開いたときに前面にあったアプリ。アクションはこのアプリに向けて実行する
    let frontmostApp: RunningAppInfo?
    let settings: GlobalSettings
    /// このセッションで HUD を出した（使い始めの案内と試用期間の知らせは、最初に出したときに決める）
    var hasShownHUD = false
    /// 試用期間の残り日数を帯で知らせる（そのセッションの間は出したまま）
    var trialReminderDays: Int?
    /// 層が1つのときに、上下の帯に止めたら出す案内（ControllerPresentation.layerHint）。左右の帯の案内は前面のアプリによらない
    let layerHint: String?

    /// host は、前面がブラウザなら見ているページのホスト名（そのサイトのプロファイルがあれば、そのページを先に使う）
    init(configuration: NonetConfiguration, frontmostApp: RunningAppInfo?, host: String? = nil) {
        pages = configuration.resolvedPages(frontmostBundleID: frontmostApp?.app.bundleID, host: host)
        self.frontmostApp = frontmostApp
        settings = configuration.settings
        layerHint = ControllerPresentation.layerHint(configuration: configuration, pages: pages, frontmostBundleID: frontmostApp?.app.bundleID)
    }

    var engineConfiguration: SessionConfiguration {
        // 空きマスで指を離したら実行せずにやめる（rejected の触覚）ように、中身のあるマスを渡す
        let occupied = pages.map { page in Set(page.cells.indices.filter { page.cells[$0] != nil }) }
        // 少し長く止めてから実行するマス
        let holds = pages.map { page in Set(page.cells.indices.filter { page.cells[$0]?.requiresHold == true }) }
        // 下で止めるとグローバルのページの層へ、上でアプリのページの層へ戻る
        return SessionConfiguration(
            pageCount: pages.count,
            layerStart: ControllerPresentation.globalPagesStart(pages),
            occupiedCells: occupied,
            holdCells: holds,
            pageShapes: pages.map(\.layout.gridShape)
        )
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

    /// page（resolvedPages での位置）のボタンの数。範囲外は 9
    func layout(ofPage page: Int) -> PageLayout {
        pages.indices.contains(page) ? pages[page].layout : .nine
    }

    func hudModel(_ state: SessionHUDState, isPracticeMode: Bool, isTrialEnded: Bool, isWaitingAtCenter: Bool = false) -> HUDModel {
        let banner: (text: String, style: HUDBannerStyle)? = if isTrialEnded {
            (ControllerPresentation.trialEndedBanner, .warning)
        } else if let days = trialReminderDays {
            (ControllerPresentation.trialReminderBanner(daysLeft: days), .info)
        } else {
            nil
        }
        return ControllerPresentation.hudModel(
            pages: pages,
            state: state,
            frontmostApp: frontmostApp?.app,
            isPractice: isPracticeMode,
            banner: banner?.text,
            bannerStyle: banner?.style ?? .warning,
            scale: settings.hudScale.factor,
            isWaitingAtCenter: isWaitingAtCenter,
            layerHint: layerHint
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
