// 担当: ui-settings
// プロファイルの一覧の絞り込み（⌘F）。プロファイルの名前と、どのプロファイルのボタンの名前・説明・送るキーでも探す
import Foundation
import NonetCore

/// 絞り込みで見つかったボタン
struct SettingsCellMatch: Equatable, Identifiable {
    var profileID: UUID
    var profileName: String
    var address: CellAddress
    var pageName: String?
    var title: String
    /// マスに出す説明（"⌘B" など）
    var detail: String
    var detailIsKeys: Bool

    var id: String { "\(profileID.uuidString)-\(address.page)-\(address.index)" }

    /// 「Xcode › ページ 1 › ビルド」（ページに名前があればその名前）
    var path: String {
        let page = SettingsText.pageTitle(index: address.page, name: pageName)
        return "\(profileName) › \(page) › \(title)"
    }
}

struct SettingsSearchResults: Equatable {
    /// 名前が合ったプロファイル（一覧の並び）
    var profiles: [Profile] = []
    var cells: [SettingsCellMatch] = []

    var isEmpty: Bool { profiles.isEmpty && cells.isEmpty }
}

enum SettingsProfileSearch {
    /// ボタンの結果の上限（何百も並べない）
    static let cellLimit = 60

    /// query が空なら空の結果。大文字と小文字・全角と半角・かなの種類を区別しない。
    /// 修飾キーを含むキーの表記（⌘B、cmd+b など）なら、そのキーを送るボタンも探す
    static func results(for query: String, in configuration: NonetConfiguration) -> SettingsSearchResults {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return SettingsSearchResults() }
        let keys = keyQuery(query)
        var results = SettingsSearchResults()
        for profile in configuration.profiles {
            if matches(profile.name, query) {
                results.profiles.append(profile)
            }
            for (pageIndex, page) in profile.pages.enumerated() {
                for (index, cell) in page.cells.enumerated() {
                    guard let cell, results.cells.count < cellLimit else { continue }
                    let title = SettingsGrid.displayTitle(for: cell)
                    let subtitle = SettingsGrid.subtitleContent(for: cell)
                    let detail = SettingsGrid.detailContent(for: cell)
                    let sentKeys = sentKeys(of: cell)
                    // アプリ起動のマスは、グリッドに出さないアプリの名前でも見つける
                    let found = matches(title, query)
                        || matches(subtitle.text, query)
                        || matches(detail.text, query)
                        || (keys != nil && sentKeys == keys)
                    guard found else { continue }
                    results.cells.append(SettingsCellMatch(
                        profileID: profile.id,
                        profileName: profile.name,
                        address: CellAddress(page: pageIndex, index: index),
                        pageName: page.name,
                        title: title,
                        detail: subtitle.text,
                        detailIsKeys: subtitle.isKeys
                    ))
                }
            }
        }
        return results
    }

    static func matches(_ text: String, _ query: String) -> Bool {
        text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current) != nil
            || text.localizedStandardContains(query)
    }

    /// 修飾キーを含むキーの表記なら、その表記（"⌘B"）。文字だけ（"b"）はキーとみなさない
    static func keyQuery(_ query: String) -> String? {
        guard let sequence = KeySequence(parsing: query), !sequence.chords.isEmpty,
              sequence.chords.contains(where: { !$0.modifiers.isEmpty }) else { return nil }
        return sequence.displayString
    }

    /// ボタンが送るキー（キー入力と、ショートカットのあるメニュー項目）
    private static func sentKeys(of cell: Cell) -> String? {
        switch cell.action {
        case .keystroke(let keys): keys.displayString
        case .menuItem(let menu): menu.keyEquivalent?.displayString
        default: nil
        }
    }
}
