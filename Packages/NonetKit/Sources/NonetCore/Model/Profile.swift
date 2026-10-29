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

    public init(id: UUID = UUID(), title: String, icon: CellIcon, action: Action) {
        self.id = id
        self.title = title
        self.icon = icon
        self.action = action
    }
}

/// 3×3 の1ページ。cells は常に9個で、左上から右へ、上の行から並ぶ。nil は空きマス
public struct Page: Codable, Equatable, Sendable {
    public static let cellCount = 9

    public var cells: [Cell?]

    /// 9個に満たなければ空きマスで埋め、多ければ切り捨てる
    public init(cells: [Cell?] = []) {
        var normalized = Array(cells.prefix(Page.cellCount))
        normalized += Array(repeating: nil, count: Page.cellCount - normalized.count)
        self.cells = normalized
    }

    public static var empty: Page { Page() }
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
    public var isEnabled: Bool

    public init(id: UUID = UUID(), kind: ProfileKind, pages: [Page] = [.empty], isEnabled: Bool = true) {
        self.id = id
        self.kind = kind
        self.pages = pages.isEmpty ? [.empty] : Array(pages.prefix(Profile.maxPages))
        self.isEnabled = isEnabled
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
        fatalError("未実装: core-model")
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
