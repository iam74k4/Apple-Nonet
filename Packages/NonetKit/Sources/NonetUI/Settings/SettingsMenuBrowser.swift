// 担当: ui-settings
// 「メニューから割り当て」: 起動中のアプリのメニューを読み、検索できる一覧にする
import Foundation
import NonetCore
import Observation

/// 割り当てられるメニュー項目（サブメニューを持たないもの）
struct SettingsMenuEntry: Identifiable, Equatable {
    var node: MenuItemNode
    /// トップのメニューと項目の間のサブメニュー（「フォント › 書体」）。無ければ空
    var location: String

    var id: String { node.id }
}

/// トップのメニュー（「編集」など）ごとのまとまり
struct SettingsMenuSection: Identifiable, Equatable {
    var title: String
    var entries: [SettingsMenuEntry]

    var id: String { title }
}

enum SettingsMenuIndex {
    static let pathSeparator = " › "

    /// トップのメニューごとに、押せる項目を並べる。同じパスの項目は最初のものだけ
    static func sections(from roots: [MenuItemNode]) -> [SettingsMenuSection] {
        var seenIDs = Set<String>()
        var sections: [SettingsMenuSection] = []
        for root in roots {
            var entries: [SettingsMenuEntry] = []
            if root.children.isEmpty {
                append(root, location: [], to: &entries, seen: &seenIDs)
            } else {
                for child in root.children {
                    collect(child, location: [], into: &entries, seen: &seenIDs)
                }
            }
            guard !entries.isEmpty else { continue }
            if let index = sections.firstIndex(where: { $0.title == root.title }) {
                sections[index].entries += entries
            } else {
                sections.append(SettingsMenuSection(title: root.title, entries: entries))
            }
        }
        return sections
    }

    /// 検索。空白で区切った語がすべて、項目の名前・パス・キーのどこかに入っているもの（大文字小文字・全角半角を区別しない）
    static func filter(_ sections: [SettingsMenuSection], query: String) -> [SettingsMenuSection] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return sections }
        return sections.compactMap { section in
            let entries = section.entries.filter { entry in
                let haystack = ([section.title, entry.location, entry.node.title] + [entry.node.keyEquivalent?.displayString ?? ""])
                    .joined(separator: " ")
                return words.allSatisfy {
                    haystack.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) != nil
                }
            }
            return entries.isEmpty ? nil : SettingsMenuSection(title: section.title, entries: entries)
        }
    }

    static func entry(id: String, in sections: [SettingsMenuSection]) -> SettingsMenuEntry? {
        for section in sections {
            if let entry = section.entries.first(where: { $0.id == id }) {
                return entry
            }
        }
        return nil
    }

    private static func collect(_ node: MenuItemNode, location: [String], into entries: inout [SettingsMenuEntry], seen: inout Set<String>) {
        if node.children.isEmpty {
            append(node, location: location, to: &entries, seen: &seen)
            return
        }
        for child in node.children {
            collect(child, location: location + [node.title], into: &entries, seen: &seen)
        }
    }

    private static func append(_ node: MenuItemNode, location: [String], to entries: inout [SettingsMenuEntry], seen: inout Set<String>) {
        guard !node.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !node.path.isEmpty,
              seen.insert(node.id).inserted else { return }
        entries.append(SettingsMenuEntry(node: node, location: location.joined(separator: pathSeparator)))
    }
}

/// 起動中のアプリを選び、そのメニューを読む
@MainActor
@Observable
final class SettingsMenuBrowser {
    enum State: Equatable {
        case idle
        case loading
        case loaded([SettingsMenuSection])
        /// needsPermission はアクセシビリティの許可が無くて読めなかった
        case failed(message: String, needsPermission: Bool)
    }

    private(set) var runningApps: [RunningAppInfo] = []
    private(set) var selectedApp: RunningAppInfo?
    private(set) var state: State = .idle
    var query = ""

    @ObservationIgnored private let menus: any MenuReading
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    /// 選び直したときに、前の読み込みの結果を捨てるための番号
    @ObservationIgnored private var generation = 0

    init(menus: any MenuReading) {
        self.menus = menus
    }

    /// 起動中のアプリを読み直す。選んでいたアプリが無くなっていれば preferredBundleID のアプリ（あれば）にする
    func refreshApps(preferredBundleID: String?) {
        runningApps = menus.runningApps().sorted {
            $0.app.name.localizedStandardCompare($1.app.name) == .orderedAscending
        }
        if let selectedApp, runningApps.contains(where: { $0.processID == selectedApp.processID }) {
            return
        }
        let preferred = preferredBundleID.flatMap { bundleID in
            runningApps.first { $0.app.bundleID.caseInsensitiveCompare(bundleID) == .orderedSame }
        }
        select(preferred)
    }

    /// ウィンドウに戻ったとき。起動中のアプリを読み直し、閉じるときに止めた読み込みをやり直す
    func resume(preferredBundleID: String?) {
        refreshApps(preferredBundleID: preferredBundleID)
        if state == .idle, selectedApp != nil {
            reload()
        }
    }

    func select(_ app: RunningAppInfo?) {
        guard app != selectedApp || state == .idle else { return }
        selectedApp = app
        query = ""
        reload()
    }

    func reload() {
        loadTask?.cancel()
        generation += 1
        guard let app = selectedApp else {
            state = .idle
            return
        }
        let current = generation
        state = .loading
        loadTask = Task { [weak self, menus] in
            let result: State
            do {
                let items = try await menus.menuItems(for: app)
                result = .loaded(SettingsMenuIndex.sections(from: items))
            } catch is CancellationError {
                return
            } catch {
                let needsPermission: Bool
                if case NonetError.permissionDenied = error {
                    needsPermission = true
                } else {
                    needsPermission = false
                }
                settingsLog.error("メニューを読めませんでした: \(error.localizedDescription, privacy: .public)")
                result = .failed(message: error.localizedDescription, needsPermission: needsPermission)
            }
            guard let self, self.generation == current else { return }
            self.state = result
        }
    }

    /// ウィンドウを閉じたとき
    func cancel() {
        loadTask?.cancel()
        loadTask = nil
        generation += 1
        if state == .loading {
            state = .idle
        }
    }

    var sections: [SettingsMenuSection] {
        guard case .loaded(let sections) = state else { return [] }
        return sections
    }

    var visibleSections: [SettingsMenuSection] {
        SettingsMenuIndex.filter(sections, query: query)
    }

    func entry(id: String) -> SettingsMenuEntry? {
        SettingsMenuIndex.entry(id: id, in: sections)
    }

    /// 終わるまで待つ（テスト用）
    func waitUntilLoaded() async {
        await loadTask?.value
    }
}
