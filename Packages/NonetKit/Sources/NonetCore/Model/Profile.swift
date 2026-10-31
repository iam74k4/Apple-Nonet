// 担当: core-model（公開 API は契約）
import Foundation

public enum CellIcon: Codable, Hashable, Sendable {
    /// SF Symbols の名前
    case symbol(String)
    /// アプリのアイコン
    case app(bundleID: String)
    /// 1〜2文字のテキスト
    case text(String)
}

/// 9マスのうちの1つ
public struct Cell: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var icon: CellIcon
    public var action: Action
    /// HUD で選んだときだけ実行する（送信・録画など、押し間違えると困るマス）。すぐにタップ（速押し）では実行せず、
    /// このマスを光らせた HUD を出す（SessionConfiguration.hudOnlyCells）。設定ファイルには true のときだけ書く
    public var requiresHUD: Bool

    public init(id: UUID = UUID(), title: String, icon: CellIcon, action: Action, requiresHUD: Bool = false) {
        self.id = id
        self.title = title
        self.icon = icon
        self.action = action
        self.requiresHUD = requiresHUD
    }
}

/// 3×3 の1ページ。cells は常に9個で、左上から右へ、上の行から並ぶ。nil は空きマス
public struct Page: Codable, Equatable, Sendable {
    public static let cellCount = 9
    /// ページの名前の長さの上限（文字数）。HUD の題名に添えるので短くする
    public static let maxNameLength = 24

    public var cells: [Cell?]
    /// ページの名前（「デバッグ」など）。無ければ nil で、画面では「ページ 2」と出す。HUD の題名にも添える（ResolvedPage.title）
    public var name: String?

    /// 9個に満たなければ空きマスで埋め、多ければ切り捨てる。name は normalizedName(_:) で揃える
    public init(cells: [Cell?] = [], name: String? = nil) {
        var normalized = Array(cells.prefix(Page.cellCount))
        normalized += Array(repeating: nil, count: Page.cellCount - normalized.count)
        self.cells = normalized
        self.name = Page.normalizedName(name)
    }

    public static var empty: Page { Page() }

    /// 前後の空白を除き、改行は空白にし、maxNameLength 文字までにした名前。空なら nil
    public static func normalizedName(_ name: String?) -> String? {
        guard let name else { return nil }
        let singleLine = name.components(separatedBy: .newlines).joined(separator: " ")
        let trimmed = singleLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxNameLength)).trimmingCharacters(in: .whitespaces)
    }
}

/// アプリのプロファイルを、そのアプリが前面にあるときにどう使うか。グローバルのプロファイルはいつも profile
public enum ProfileMode: String, Codable, CaseIterable, Sendable {
    /// このプロファイルのページを使う
    case profile
    /// このプロファイルは使わず、グローバルのページを使う（中身は残す。以前の「無効」）
    case global
    /// このアプリでは Nonet を使わない。トリガーキーでも角の長押しでもセッションを始めず、
    /// キーとポインタはそのまま前面アプリに届く（NonetConfiguration.isTurnedOff(forBundleID:)）
    case off
}

public enum ProfileKind: Codable, Hashable, Sendable {
    /// どのアプリでも使う。設定に必ず1つだけある
    case global
    /// 特定のアプリが前面にあるときに使う
    case app(AppReference)
}

public struct Profile: Codable, Equatable, Identifiable, Sendable {
    public static let maxPages = 3

    public var id: UUID
    public var kind: ProfileKind
    /// 1〜maxPages ページ
    public var pages: [Page]
    /// 前面にあるときの使い方。グローバルは validated() でいつも profile にする
    public var mode: ProfileMode

    /// このプロファイルのページを使う（mode == .profile）。false にすると .global（グローバルを使う）
    public var isEnabled: Bool {
        get { mode == .profile }
        set { mode = newValue ? .profile : .global }
    }

    public init(id: UUID = UUID(), kind: ProfileKind, pages: [Page] = [.empty], isEnabled: Bool = true) {
        self.init(id: id, kind: kind, pages: pages, mode: isEnabled ? .profile : .global)
    }

    public init(id: UUID = UUID(), kind: ProfileKind, pages: [Page] = [.empty], mode: ProfileMode) {
        self.id = id
        self.kind = kind
        self.pages = pages.isEmpty ? [.empty] : Array(pages.prefix(Profile.maxPages))
        self.mode = mode
    }

    public var isGlobal: Bool {
        if case .global = kind { return true }
        return false
    }

    public var app: AppReference? {
        if case .app(let app) = kind { return app }
        return nil
    }

    /// 表示名。グローバルは「グローバル」（ローカライズ済み）、アプリはアプリ名
    public var name: String {
        switch kind {
        case .global: String(localized: "グローバル", bundle: .module)
        case .app(let app): app.nameOrBundleID
        }
    }
}

/// プロファイル内のマスの位置
public struct CellAddress: Codable, Hashable, Sendable {
    public var page: Int
    /// 0〜8。左上から右へ、上の行から
    public var index: Int

    public init(page: Int, index: Int) {
        self.page = page
        self.index = index
    }
}

// MARK: - Codable
// 関連値のある enum は {"type": "...", ...} で書く。マス・ページ・プロファイルは読めないところを既定値で埋め、
// 読めないマスは空きマスにする（知らないアクションの種類で設定全体が読めなくならないように）

extension CellIcon {
    private enum CodingKeys: String, CodingKey {
        case type, symbol, bundleID, text
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "symbol":
            self = .symbol(try container.decode(String.self, forKey: .symbol))
        case "app":
            self = .app(bundleID: try container.decode(String.self, forKey: .bundleID))
        case "text":
            self = .text(try container.decode(String.self, forKey: .text))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "未知のアイコンの種類")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .symbol(let name):
            try container.encode("symbol", forKey: .type)
            try container.encode(name, forKey: .symbol)
        case .app(let bundleID):
            try container.encode("app", forKey: .type)
            try container.encode(bundleID, forKey: .bundleID)
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        }
    }

    /// アイコンが読めなかったときに使う
    static func fallback(for action: Action) -> CellIcon {
        if case .launchApp(let launch) = action {
            return .app(bundleID: launch.app.bundleID)
        }
        return .symbol("questionmark.square.dashed")
    }
}

extension Cell {
    private enum CodingKeys: String, CodingKey {
        case id, title, icon, action, requiresHUD
    }

    /// requiresHUD が無い・読めなければ false（この設定より前の書式）
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let action = try container.decode(Action.self, forKey: .action)
        self.init(
            id: container.decodeLossy(UUID.self, forKey: .id, default: UUID()),
            title: container.decodeLossy(String.self, forKey: .title, default: ""),
            icon: container.decodeLossy(CellIcon.self, forKey: .icon, default: .fallback(for: action)),
            action: action,
            requiresHUD: container.decodeLossy(Bool.self, forKey: .requiresHUD, default: false)
        )
    }

    /// requiresHUD は true のときだけ書く（この設定より前の版と同じ書式のまま）
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(icon, forKey: .icon)
        try container.encode(action, forKey: .action)
        if requiresHUD {
            try container.encode(true, forKey: .requiresHUD)
        }
    }
}

extension Page {
    private enum CodingKeys: String, CodingKey {
        case cells, name
    }

    /// cells は 9 個に揃える。読めないマスは空きマス。名前が無い・読めなければ nil
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let cells = container.decodeLossy([LossyElement<Cell>].self, forKey: .cells, default: [])
        if cells.count != Page.cellCount {
            DecodingIssue.log("マスの数（\(cells.count)）", at: container.codingPath + [CodingKeys.cells])
        }
        self.init(cells: cells.map(\.value), name: container.decodeLossy(String?.self, forKey: .name, default: nil))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Page(cells: cells).cells, forKey: .cells)
        // 名前の無いページは書かない（名前を付けられるようになる前と同じ書式のまま）
        if let name = Page.normalizedName(name) {
            try container.encode(name, forKey: .name)
        }
    }
}

extension ProfileKind {
    private enum CodingKeys: String, CodingKey {
        case type, app
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "global":
            self = .global
        case "app":
            self = .app(try container.decode(AppReference.self, forKey: .app))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "未知のプロファイルの種類")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .global:
            try container.encode("global", forKey: .type)
        case .app(let app):
            try container.encode("app", forKey: .type)
            try container.encode(app, forKey: .app)
        }
    }
}

extension Profile {
    private enum CodingKeys: String, CodingKey {
        case id, kind, pages, isEnabled, mode
    }

    /// 使い方は isEnabled（true ならこのプロファイル、false ならグローバル）で読み、mode があればそちらを使う。
    /// 知らない mode（新しい版の Nonet の使い方）は isEnabled で読む
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // 読めないページは空きページにして、ページの位置を保つ
        let pages = container.decodeLossy([LossyElement<Page>].self, forKey: .pages, default: [])
        let isEnabled = container.decodeLossy(Bool.self, forKey: .isEnabled, default: true)
        let mode = container.decodeLossy(ProfileMode?.self, forKey: .mode, default: nil)
        self.init(
            id: container.decodeLossy(UUID.self, forKey: .id, default: UUID()),
            kind: try container.decode(ProfileKind.self, forKey: .kind),
            pages: pages.map { $0.value ?? .empty },
            mode: mode ?? (isEnabled ? .profile : .global)
        )
    }

    /// isEnabled はいつも書く（mode を知らない前の版の Nonet は、使わないアプリを「グローバルを使う」として読む）。
    /// mode は isEnabled で表せない off のときだけ書き、それ以外は前の版と同じ書式のままにする
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(pages, forKey: .pages)
        try container.encode(isEnabled, forKey: .isEnabled)
        if mode == .off {
            try container.encode(mode, forKey: .mode)
        }
    }
}

extension Profile {
    /// ページ数を 1〜maxPages、各ページを9マスに揃える
    mutating func normalizePages() {
        if pages.isEmpty {
            pages = [.empty]
        } else if pages.count > Profile.maxPages {
            pages = Array(pages.prefix(Profile.maxPages))
        }
        for index in pages.indices where pages[index].cells.count != Page.cellCount {
            pages[index] = Page(cells: pages[index].cells, name: pages[index].name)
        }
    }
}
