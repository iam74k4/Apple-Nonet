// 担当: ui-settings
// 9マスの位置・選択の移動・複製先・ドラッグの中身など、画面に依存しない決まり
import CoreTransferable
import Foundation
import NonetCore
import os
import UniformTypeIdentifiers

let settingsLog = Logger(subsystem: "com.iam74k4.Nonet", category: "ui-settings")

enum SettingsGridDirection: Hashable, Sendable {
    case up, down, left, right
}

enum SettingsGrid {
    static let columns = 3
    /// 隣と入れ替えるメニュー・VoiceOver の並び
    static let swapDirections: [SettingsGridDirection] = [.up, .down, .left, .right]

    /// 矢印キーで移る先。端では止まる
    static func neighbor(of index: Int, _ direction: SettingsGridDirection) -> Int {
        let index = min(max(index, 0), Page.cellCount - 1)
        let row = index / columns
        let column = index % columns
        switch direction {
        case .left: return row * columns + max(column - 1, 0)
        case .right: return row * columns + min(column + 1, columns - 1)
        case .up: return max(row - 1, 0) * columns + column
        case .down: return min(row + 1, columns - 1) * columns + column
        }
    }

    /// 複製の置き場所。同じページの次のマスから順に（折り返して）探し、無ければほかのページを前から探す
    static func nextEmptyAddress(after address: CellAddress, in profile: Profile) -> CellAddress? {
        var candidates: [CellAddress] = []
        if profile.pages.indices.contains(address.page) {
            for offset in 1..<Page.cellCount {
                candidates.append(CellAddress(page: address.page, index: (address.index + offset) % Page.cellCount))
            }
        }
        for page in profile.pages.indices where page != address.page {
            for index in 0..<Page.cellCount {
                candidates.append(CellAddress(page: page, index: index))
            }
        }
        return candidates.first { isEmpty($0, in: profile) }
    }

    /// メニュー項目をダブルクリックしたときの置き場所。
    /// 選んでいるマスが空きかメニュー項目のマス（インスペクタの「メニューから選ぶ…」から来た・割り当て直す）ならそこ、
    /// 無ければ今のページの最初の空き、それも無ければほかのページの空き
    static func assignmentTarget(selected: CellAddress?, currentPage: Int, in profile: Profile) -> CellAddress? {
        if let selected, isEmpty(selected, in: profile) || isMenuItem(selected, in: profile) {
            return selected
        }
        if profile.pages.indices.contains(currentPage), let index = firstEmptyIndex(in: profile.pages[currentPage]) {
            return CellAddress(page: currentPage, index: index)
        }
        for page in profile.pages.indices where page != currentPage {
            if let index = firstEmptyIndex(in: profile.pages[page]) {
                return CellAddress(page: page, index: index)
            }
        }
        return nil
    }

    /// そのページで最初の空きマス
    static func firstEmptyIndex(in page: Page) -> Int? {
        page.cells.firstIndex { $0 == nil }
    }

    static func isEmpty(_ address: CellAddress, in profile: Profile) -> Bool {
        guard profile.pages.indices.contains(address.page) else { return false }
        let cells = profile.pages[address.page].cells
        guard cells.indices.contains(address.index) else { return false }
        return cells[address.index] == nil
    }

    /// プロファイルの中でそのマスがある場所
    static func address(ofCell id: UUID, in profile: Profile) -> CellAddress? {
        for (pageIndex, page) in profile.pages.enumerated() {
            if let index = page.cells.firstIndex(where: { $0?.id == id }) {
                return CellAddress(page: pageIndex, index: index)
            }
        }
        return nil
    }

    /// メニュー項目のマス（項目を選ぶ前のものも）
    static func isMenuItem(_ address: CellAddress, in profile: Profile) -> Bool {
        if case .menuItem? = cell(at: address, in: profile)?.action { return true }
        return false
    }

    static func cell(at address: CellAddress, in profile: Profile) -> Cell? {
        guard profile.pages.indices.contains(address.page),
              profile.pages[address.page].cells.indices.contains(address.index) else { return nil }
        return profile.pages[address.page].cells[address.index]
    }

    /// トラックパッド上の位置の名前
    static func positionName(_ index: Int) -> String {
        switch index {
        case 0: String(localized: "左上", bundle: .module)
        case 1: String(localized: "上", bundle: .module)
        case 2: String(localized: "右上", bundle: .module)
        case 3: String(localized: "左", bundle: .module)
        case 4: String(localized: "中央", bundle: .module)
        case 5: String(localized: "右", bundle: .module)
        case 6: String(localized: "左下", bundle: .module)
        case 7: String(localized: "下", bundle: .module)
        default: String(localized: "右下", bundle: .module)
        }
    }

    /// 「マス 5（中央）」
    static func cellName(_ index: Int) -> String {
        String(localized: "マス \(index + 1)（\(positionName(index))）", bundle: .module)
    }

    /// マスに出す説明（"⌘B" など）。中身が未設定なら「未設定」。名前と同じになるときは種類の名前
    static func subtitle(for cell: Cell) -> String {
        subtitleContent(for: cell).text
    }

    /// マスに出す説明と、それがキーの表記か（キーの表記だけ等幅で出す。言葉まで等幅にするとターミナルの出力のように見える）。
    /// アプリ起動はいつも種類の名前（同じグリッドで、アプリの名前と種類の名前が混ざらないように）。アプリの名前はインスペクタとヘルプに出す
    static func subtitleContent(for cell: Cell) -> (text: String, isKeys: Bool) {
        if case .launchApp = cell.action, !SettingsCellEditing.isIncomplete(cell.action) {
            return (SettingsActionKinds.name(cell.action.kind), false)
        }
        return detailContent(for: cell)
    }

    /// マスのヘルプ（ポインタを重ねたときの説明）。名前は切れていることがあるので、名前をそのまま1行目に、何をするか
    /// （送るキー・開くアプリなど。アプリ起動ならグリッドに出さない開くアプリの名前）を2行目に出す。空きマスは nil
    static func tooltip(for cell: Cell?) -> String? {
        guard let cell else { return nil }
        let title = displayTitle(for: cell).trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = detailContent(for: cell).text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !detail.isEmpty, detail != title else { return title }
        return title.isEmpty ? detail : "\(title)\n\(detail)"
    }

    /// マスの中身の説明（アプリ起動ならアプリの名前）。検索と VoiceOver とヘルプで使う
    static func detailContent(for cell: Cell) -> (text: String, isKeys: Bool) {
        if SettingsCellEditing.isIncomplete(cell.action) {
            return (String(localized: "未設定", bundle: .module), false)
        }
        var detail = cell.action.summary
        var isKeys = false
        if case .keystroke = cell.action {
            isKeys = true
        }
        if case .menuItem(let menu) = cell.action, let keys = menu.keyEquivalent, !keys.chords.isEmpty {
            detail = keys.displayString
            isKeys = true
        }
        let title = displayTitle(for: cell).trimmingCharacters(in: .whitespacesAndNewlines)
        if detail.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(title) == .orderedSame {
            return (SettingsActionKinds.name(cell.action.kind), false)
        }
        return (detail, isKeys)
    }

    /// マスに出す名前。表示名が空ならアクションの説明
    static func displayTitle(for cell: Cell) -> String {
        cell.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? SettingsCellEditing.automaticTitle(for: cell.action)
            : cell.title
    }

    /// VoiceOver の読み上げ（「5番目のマス（中央）：Claude Code、ターミナル」）
    static func accessibilityLabel(index: Int, cell: Cell?) -> String {
        let position = String(localized: "\(index + 1)番目のマス（\(positionName(index))）", bundle: .module)
        guard let cell else {
            return String(localized: "\(position)：空き", bundle: .module)
        }
        return String(localized: "\(position)：\(displayTitle(for: cell))、\(detailContent(for: cell).text)", bundle: .module)
    }
}

/// ドラッグで運ぶもの。中身は文字列にして SettingsDragItem で運び、受け取った側で元に戻す（同じウィンドウの中だけで使う）
enum SettingsDragPayload: Equatable, Sendable {
    /// グリッドのマス（入れ替え）
    case cell(profileID: UUID, address: CellAddress)
    /// メニューから割り当てるメニュー項目（MenuItemNode.id）
    case menuItem(id: String)

    private static let cellPrefix = "nonet-settings-cell|"
    private static let menuPrefix = "nonet-settings-menu|"

    var token: String {
        switch self {
        case .cell(let profileID, let address):
            "\(Self.cellPrefix)\(profileID.uuidString)|\(address.page)|\(address.index)"
        case .menuItem(let id):
            Self.menuPrefix + id
        }
    }

    init?(token: String) {
        if token.hasPrefix(Self.cellPrefix) {
            let parts = token.dropFirst(Self.cellPrefix.count).split(separator: "|", omittingEmptySubsequences: false)
            guard parts.count == 3, let id = UUID(uuidString: String(parts[0])),
                  let page = Int(parts[1]), let index = Int(parts[2]),
                  page >= 0, (0..<Page.cellCount).contains(index) else { return nil }
            self = .cell(profileID: id, address: CellAddress(page: page, index: index))
        } else if token.hasPrefix(Self.menuPrefix) {
            let id = String(token.dropFirst(Self.menuPrefix.count))
            guard !id.isEmpty else { return nil }
            self = .menuItem(id: id)
        } else {
            return nil
        }
    }
}

extension UTType {
    /// 設定画面の中のドラッグだけで使う種類。文字列として運ぶと、取り落としたときに
    /// スクリプトの欄やほかのアプリ（メモ・メール）に中身の文字が入ってしまう
    static let nonetSettingsDrag = UTType(exportedAs: "com.iam74k4.nonet.settings-drag", conformingTo: .data)
}

/// ドラッグで運ぶもの。文字列の種類を持たないので、テキストの欄やほかのアプリは受け取らない
struct SettingsDragItem: Transferable, Equatable, Sendable {
    var payload: SettingsDragPayload

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(contentType: .nonetSettingsDrag) { item in
            Data(item.payload.token.utf8)
        } importing: { data in
            guard let token = String(data: data, encoding: .utf8), let payload = SettingsDragPayload(token: token) else {
                throw CocoaError(.coderReadCorrupt)
            }
            return SettingsDragItem(payload: payload)
        }
    }
}
