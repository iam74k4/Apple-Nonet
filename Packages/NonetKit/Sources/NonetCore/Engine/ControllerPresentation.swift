// 担当: engine
// NonetController が HUD・トースト・結果のパネルに渡すものを作る純粋な関数
import Foundation

enum ControllerPresentation {
    /// page は resolvedPages での位置。範囲外は端に寄せる
    static func hudModel(pages: [ResolvedPage], page: Int, highlightedCell: Int?, hint: String, banner: String?) -> HUDModel {
        let index = pages.isEmpty ? 0 : min(max(page, 0), pages.count - 1)
        let resolved = pages.indices.contains(index) ? pages[index] : nil
        let cells = Page(cells: resolved?.cells ?? []).cells.map { $0.map(hudCell) }
        let highlight = highlightedCell.flatMap { (0..<Page.cellCount).contains($0) ? $0 : nil }
        return HUDModel(
            title: resolved?.profileName ?? "",
            pageIndex: index,
            pageCount: max(pages.count, 1),
            cells: cells,
            highlightedIndex: highlight,
            hint: hint,
            banner: banner
        )
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

    /// HUD の右上の案内
    static func hint(fireMode: FireMode, trigger: TriggerKey, isPracticeMode: Bool) -> String {
        let base = switch fireMode {
        case .onTriggerRelease:
            String(localized: "\(trigger.symbol)を離して実行", bundle: .module)
        case .onFingerLift:
            String(localized: "指を離して実行", bundle: .module)
        }
        guard isPracticeMode else { return base }
        return String(localized: "練習中 · \(base)", bundle: .module)
    }

    static var trialEndedBanner: String {
        String(localized: "試用期間が終了しました", bundle: .module)
    }

    static func successToast(_ cell: Cell) -> ToastModel {
        ToastModel(title: cell.title, icon: cell.icon, style: .success)
    }

    /// 何を実行しようとしたか（マス）と、なぜ失敗したか（message）
    static func failureToast(_ cell: Cell, message: String) -> ToastModel {
        ToastModel(title: cell.title, detail: message, icon: cell.icon, style: .failure)
    }

    static func result(_ cell: Cell, output: String) -> ResultModel {
        ResultModel(title: cell.title, text: output, icon: cell.icon)
    }
}
