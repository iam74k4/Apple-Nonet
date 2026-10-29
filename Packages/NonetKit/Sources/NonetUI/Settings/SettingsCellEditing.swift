// 担当: ui-settings
// インスペクタでの編集をマスの値に直す決まり（種類の切り替え・既定の名前とアイコン・値の確かめ）
import Foundation
import NonetCore

enum SettingsActionKinds {
    /// インスペクタに並べる順
    static let ordered: [ActionKind] = [.keystroke, .launchApp, .openURL, .script, .shortcut, .menuItem, .ai]

    static func name(_ kind: ActionKind) -> String {
        switch kind {
        case .keystroke: String(localized: "キー入力", bundle: .module)
        case .launchApp: String(localized: "アプリ起動", bundle: .module)
        case .openURL: String(localized: "URL", bundle: .module)
        case .script: String(localized: "スクリプト", bundle: .module)
        case .shortcut: String(localized: "ショートカット", bundle: .module)
        case .menuItem: String(localized: "メニュー項目", bundle: .module)
        case .ai: String(localized: "AI", bundle: .module)
        }
    }

    /// 種類の既定のアイコン（macOS 14 にある SF Symbols）
    static func symbol(_ kind: ActionKind) -> String {
        switch kind {
        case .keystroke: "keyboard"
        case .launchApp: "macwindow"
        case .openURL: "link"
        case .script: "terminal"
        case .shortcut: "square.2.layers.3d"
        case .menuItem: "filemenu.and.selection"
        case .ai: "sparkles"
        }
    }
}

enum SettingsCellEditing {
    /// 種類を選んだときの中身。アプリやキーは後で決める
    static func defaultAction(for kind: ActionKind) -> Action {
        switch kind {
        case .keystroke: .keystroke(KeySequence([]))
        case .launchApp: .launchApp(LaunchAppAction(app: AppReference(bundleID: "", name: "")))
        case .openURL: .openURL(URLAction(url: ""))
        case .script: .script(ScriptAction(source: ""))
        case .shortcut: .shortcut(ShortcutAction(name: ""))
        case .menuItem: .menuItem(MenuItemAction(path: []))
        case .ai: .ai(AIAction(prompt: "", output: .showResult))
        }
    }

    /// 空きマスに種類を選んで作るマス
    static func newCell(kind: ActionKind) -> Cell {
        let action = defaultAction(for: kind)
        return Cell(title: "", icon: defaultIcon(for: action), action: action)
    }

    /// アクションに合うアイコン。アプリ起動はそのアプリのアイコン
    static func defaultIcon(for action: Action) -> CellIcon {
        if case .launchApp(let launch) = action, !launch.app.bundleID.isEmpty {
            return .app(bundleID: launch.app.bundleID)
        }
        return .symbol(SettingsActionKinds.symbol(action.kind))
    }

    /// 表示名が空のときに使う名前。中身が未設定なら種類の名前
    static func automaticTitle(for action: Action) -> String {
        isIncomplete(action) ? SettingsActionKinds.name(action.kind) : action.summary
    }

    /// まだ実行できる中身が無い（キー・アプリ・URL などが空）
    static func isIncomplete(_ action: Action) -> Bool {
        switch action {
        case .keystroke(let keys): keys.chords.isEmpty
        case .launchApp(let launch): launch.app.bundleID.trimmingCharacters(in: .whitespaces).isEmpty
        case .openURL(let url): url.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .script(let script): script.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .shortcut(let shortcut): shortcut.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .menuItem(let menu): menu.path.isEmpty
        case .ai(let ai): ai.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// 表示名を利用者が付けていない（空か、自動で付いた名前のまま）
    static func hasAutomaticTitle(_ cell: Cell) -> Bool {
        let title = cell.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty || title == cell.action.summary || title == SettingsActionKinds.name(cell.action.kind)
    }

    /// アクションを差し替える。自動で付いた名前とアイコンは新しいアクションに合わせ、利用者が付けたものは残す
    static func replacingAction(_ action: Action, in cell: Cell) -> Cell {
        var updated = cell
        if hasAutomaticTitle(cell) {
            updated.title = isIncomplete(action) ? "" : action.summary
        }
        if cell.icon == defaultIcon(for: cell.action) {
            updated.icon = defaultIcon(for: action)
        }
        updated.action = action
        return updated
    }

    /// 種類を切り替える。remembered はこのマスで前にその種類だったときの中身（戻したときに失わないように）
    static func changingKind(of cell: Cell, to kind: ActionKind, remembered: Action? = nil) -> Cell {
        guard cell.action.kind != kind else { return cell }
        let action = remembered.flatMap { $0.kind == kind ? $0 : nil } ?? defaultAction(for: kind)
        return replacingAction(action, in: cell)
    }

    /// アプリ起動のアプリを選ぶ
    static func choosingApp(_ app: AppReference, in cell: Cell) -> Cell {
        var launch = LaunchAppAction(app: app)
        if case .launchApp(let current) = cell.action {
            launch.hideIfFrontmost = current.hideIfFrontmost
        }
        return replacingAction(.launchApp(launch), in: cell)
    }

    /// メニュー項目を割り当てたマス。表示名は項目の名前にする
    static func assigningMenuItem(_ item: MenuItemNode, app: AppReference?, to cell: Cell?) -> Cell {
        let action = Action.menuItem(MenuItemAction(app: app, path: item.path, keyEquivalent: item.keyEquivalent))
        var updated = cell.map { replacingAction(action, in: $0) }
            ?? Cell(title: "", icon: defaultIcon(for: action), action: action)
        updated.title = item.title
        return updated
    }

    /// スクリプトの制限時間を受け付ける範囲に収める
    static func clampedTimeout(_ seconds: Double) -> Double {
        let range = ScriptAction.timeoutRange
        guard seconds.isFinite else { return ScriptAction.defaultTimeout }
        return min(max(seconds.rounded(), range.lowerBound), range.upperBound)
    }
}

/// URL 欄の確かめ。開くときの決まり（スキームが無ければ https、localhost は http、/ や ~ はファイル）に合わせる
enum SettingsURLCheck: Equatable {
    case empty
    /// そのまま開ける
    case valid
    /// 開くときにスキームを補う（値は補うスキーム）
    case addsScheme(String)
    /// ファイルやフォルダの場所として開く
    case file
    case invalid

    init(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            self = .empty
            return
        }
        // "//example.com" はスキームを省いた URL。ほかの / や ~ で始まるものはファイルの場所
        if (text.hasPrefix("/") && !text.hasPrefix("//")) || text.hasPrefix("~") {
            self = .file
            return
        }
        let schemeText = text.hasPrefix("//") ? "https:" + text : text
        let hasScheme = Self.hasScheme(schemeText)
        let added = hasScheme ? nil : Self.defaultScheme(for: schemeText)
        let candidate = added.map { "\($0)://\(schemeText)" } ?? schemeText
        guard !text.contains(where: \.isWhitespace),
              let url = URL(string: candidate), let scheme = url.scheme, !scheme.isEmpty else {
            self = .invalid
            return
        }
        if ["http", "https"].contains(scheme.lowercased()) {
            guard let host = url.host(percentEncoded: false), !host.isEmpty else {
                self = .invalid
                return
            }
        }
        if text.hasPrefix("//") {
            self = .addsScheme("https")
        } else {
            self = added.map(SettingsURLCheck.addsScheme) ?? .valid
        }
    }

    var message: String? {
        switch self {
        case .empty, .valid: nil
        case .addsScheme(let scheme): String(localized: "開くときに \(scheme):// を補います", bundle: .module)
        case .file: String(localized: "ファイルやフォルダとして開きます", bundle: .module)
        case .invalid: String(localized: "URL の形が正しくありません", bundle: .module)
        }
    }

    var isProblem: Bool { self == .invalid }

    /// "mailto:" や "https://" はスキームあり。"example.com:8080" や "localhost:3000" は「ホスト:ポート」
    static func hasScheme(_ text: String) -> Bool {
        guard let colon = text.firstIndex(of: ":") else { return false }
        let scheme = text[..<colon]
        guard let first = scheme.unicodeScalars.first, first.isASCII, first.properties.isAlphabetic else { return false }
        let allowed = scheme.unicodeScalars.allSatisfy {
            $0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains($0) || "+-.".unicodeScalars.contains($0))
        }
        guard allowed else { return false }
        let rest = text[text.index(after: colon)...]
        if rest.hasPrefix("//") { return true }
        if let next = rest.unicodeScalars.first, ("0"..."9").contains(next),
           scheme.contains(".") || scheme.lowercased() == "localhost" {
            return false
        }
        return true
    }

    private static func defaultScheme(for text: String) -> String {
        let host = text.prefix { !"/:?#".contains($0) }.lowercased()
        return ["localhost", "127.0.0.1", "[::1]"].contains(host) ? "http" : "https"
    }
}
