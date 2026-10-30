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

    init(configuration: NonetConfiguration, frontmostApp: RunningAppInfo?) {
        pages = configuration.resolvedPages(frontmostBundleID: frontmostApp?.app.bundleID)
        self.frontmostApp = frontmostApp
        settings = configuration.settings
    }

    var engineConfiguration: SessionConfiguration {
        // 空きマスの速押しで 6 の (a) の HUD が止まらないように、中身のあるマスを渡す
        let occupied = pages.map { page in Set(page.cells.indices.filter { page.cells[$0] != nil }) }
        return SessionConfiguration(settings: settings, pageCount: pages.count, occupiedCells: occupied)
    }

    /// page（resolvedPages での位置）の cell 番目のマス。範囲外と空きマスは nil
    func target(page: Int, cell: Int) -> ControllerTarget? {
        guard pages.indices.contains(page) else { return nil }
        let resolved = pages[page]
        guard resolved.cells.indices.contains(cell), let found = resolved.cells[cell] else { return nil }
        return ControllerTarget(cell: found, profileName: resolved.profileName, address: CellAddress(page: resolved.pageIndex, index: cell))
    }

    func hudModel(page: Int, highlightedCell: Int?, isPracticeMode: Bool, isTrialEnded: Bool) -> HUDModel {
        ControllerPresentation.hudModel(
            pages: pages,
            page: page,
            highlightedCell: highlightedCell,
            hint: ControllerPresentation.hint(fireMode: settings.fireMode, trigger: settings.trigger, isPracticeMode: isPracticeMode),
            banner: isTrialEnded ? ControllerPresentation.trialEndedBanner : nil
        )
    }
}

/// 実行するマスと、ExecutionRecord に残す場所
struct ControllerTarget: Equatable, Sendable {
    var cell: Cell
    var profileName: String
    /// プロファイル内での位置
    var address: CellAddress
}
