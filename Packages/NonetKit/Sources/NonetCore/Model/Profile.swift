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

/// ページのボタン（マス）の1つ
public struct Cell: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var icon: CellIcon
    public var action: Action
    /// 少し長く止めてから実行する（送信・録画など、押し間違えると困るマス）。このマスで指を離して実行するには、
    /// ふつうより長く（SessionConfiguration.holdDwell）止める（SessionConfiguration.holdCells）。
    /// 設定ファイルの名前は前の版と同じ requiresHUD で、true のときだけ書く
    public var requiresHold: Bool

    public init(id: UUID = UUID(), title: String, icon: CellIcon, action: Action, requiresHold: Bool = false) {
        self.id = id
        self.title = title
        self.icon = icon
        self.action = action
        self.requiresHold = requiresHold
    }
}

extension Cell {
    /// HUD・トースト・結果のパネル・最近の実行に出す名前。表示名が空（空白だけを含む）なら、アクションの説明
    /// （利用ガイドの「表示名が空のときは、中身から自動で付けた名前を使います」。設定画面は SettingsGrid.displayTitle）
    public var displayTitle: String {
        title.trimmedNonEmpty == nil ? action.summary : title
    }
}

/// 1ページに並べるボタンの数（HUD の円に並ぶ鍵の数）。9 は円に8つと真ん中に1つ、ほかは円に並べるだけで、
/// 真ん中は空き（離すとやめる）。ページごとに選べる。設定ファイルには 9 以外のときだけ buttons として書く
public enum PageLayout: Int, Codable, CaseIterable, Sendable {
    case four = 4
    case six = 6
    case eight = 8
    case nine = 9
    case twelve = 12

    /// ボタンの数
    public var slotCount: Int { rawValue }

    /// 円の上の鍵の並び: 上から時計回りに、マスの番号。9 は設定画面の 3×3 と同じ向き（左上のマスは左上の鍵）、
    /// ほかはマスの番号の順に上から時計回り
    public var ringCells: [Int] {
        self == .nine ? [1, 2, 5, 8, 7, 6, 3, 0] : Array(0..<slotCount)
    }

    /// 真ん中のマス。9 だけ（ほかは真ん中が空きで、離すとやめる）
    public var centerCell: Int? {
        self == .nine ? 4 : nil
    }

    /// 上から時計回りに並べたマスの番号（真ん中は最後）。数を変えるときは、この順に詰め直す（Page.resized(to:)）
    public var clockwiseCells: [Int] {
        ringCells + (centerCell.map { [$0] } ?? [])
    }

    /// トラックパッドの位置で選ぶとき（ポインタが読めないとき）と、エンジンが使う並び。マスの数と同じだけの升目
    public var gridShape: GridShape {
        switch self {
        case .four: GridShape(columns: 2, rows: 2)
        case .six: GridShape(columns: 3, rows: 2)
        case .eight: GridShape(columns: 4, rows: 2)
        case .nine: GridShape(columns: 3, rows: 3)
        case .twelve: GridShape(columns: 4, rows: 3)
        }
    }

    /// 選べない数は、いちばん近い数（同じだけ離れていれば多いほう）
    public init(nearest count: Int) {
        self = Self.allCases.min { a, b in
            let da = abs(a.rawValue - count), db = abs(b.rawValue - count)
            return da == db ? a.rawValue > b.rawValue : da < db
        } ?? .nine
    }
}

/// 1ページ。cells は常に layout のボタンの数だけあり、9 なら 3×3 を左上から右へ、上の行から、ほかは上から時計回りに並ぶ。nil は空きマス
public struct Page: Codable, Equatable, Sendable {
    /// 9マス（標準のボタンの数）。ほかの数は PageLayout
    public static let cellCount = 9
    /// ボタンの数の上限（PageLayout.twelve）
    public static let maxCellCount = 12
    /// ページの名前の長さの上限（文字数）。HUD の題名に添えるので短くする
    public static let maxNameLength = 24

    public var cells: [Cell?]
    /// ページの名前（「デバッグ」など）。無ければ nil で、画面では「ページ 2」と出す。HUD の題名にも添える（ResolvedPage.title）
    public var name: String?
    /// ボタンの数
    public var layout: PageLayout

    /// layout の数に満たなければ空きマスで埋め、多ければ切り捨てる。name は normalizedName(_:) で揃える
    public init(cells: [Cell?] = [], name: String? = nil, layout: PageLayout = .nine) {
        var normalized = Array(cells.prefix(layout.slotCount))
        normalized += Array(repeating: nil, count: layout.slotCount - normalized.count)
        self.cells = normalized
        self.name = Page.normalizedName(name)
        self.layout = layout
    }

    /// 中身のあるマスの数
    public var filledCount: Int { cells.lazy.filter { $0 != nil }.count }

    /// その数に変えても、中身のあるマスが全部残る
    public func canResize(to layout: PageLayout) -> Bool {
        filledCount <= layout.slotCount
    }

    /// 中身のあるマスが入りきらない数にするときの、残すページと、入りきらない分を並べたページ。
    /// 中身のあるマスを上から時計回りの順に並べ、前から layout の数だけ残し、残りは今の数のページに同じ順で並べる。
    /// 入りきるなら overflow は nil（resized(to:) と同じ）
    public func split(to layout: PageLayout) -> (page: Page, overflow: Page?) {
        guard !canResize(to: layout) else { return (resized(to: layout), nil) }
        let filled = self.layout.clockwiseCells.compactMap { cells.indices.contains($0) ? cells[$0] : nil }
        func placed(_ cells: ArraySlice<Cell>, in layout: PageLayout, name: String?) -> Page {
            var result = Array<Cell?>(repeating: nil, count: layout.slotCount)
            for (position, cell) in zip(layout.clockwiseCells, cells) {
                result[position] = cell
            }
            return Page(cells: result, name: name, layout: layout)
        }
        return (
            placed(filled.prefix(layout.slotCount), in: layout, name: name),
            placed(filled.dropFirst(layout.slotCount), in: self.layout, name: nil)
        )
    }

    /// ボタンの数を変えたページ。上から時計回りの順（PageLayout.clockwiseCells）を保って詰め直す:
    /// 入りきらなければ、後ろの空きマスから減らす。中身のあるマスが入りきらなければ（canResize が false）、後ろのマスを切り捨てる
    public func resized(to layout: PageLayout) -> Page {
        guard layout != self.layout else { return self }
        var ordered = self.layout.clockwiseCells.map { cells.indices.contains($0) ? cells[$0] : nil }
        while ordered.count > layout.slotCount, let index = ordered.lastIndex(where: { $0 == nil }) {
            ordered.remove(at: index)
        }
        ordered = Array(ordered.prefix(layout.slotCount))
        var result = Array<Cell?>(repeating: nil, count: layout.slotCount)
        for (position, cell) in zip(layout.clockwiseCells, ordered) {
            result[position] = cell
        }
        return Page(cells: result, name: name, layout: layout)
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
    /// このアプリでは Nonet を使わない。トラックパッドを強く押し込んでも9マスを開かず（クリックも預からず）、
    /// ポインタはそのまま前面アプリに届く（NonetConfiguration.isTurnedOff(forBundleID:)）
    case off
}

public enum ProfileKind: Codable, Hashable, Sendable {
    /// どのアプリでも使う。設定に必ず1つだけある
    case global
    /// 特定のアプリが前面にあるときに使う
    case app(AppReference)
    /// ブラウザで特定のサイトを見ているときに使う（そのブラウザのプロファイルより先）
    case site(SiteReference)
}

/// サイト（ホスト名）。www. を除いた小文字で持ち、サブドメインにも合う（youtube.com は m.youtube.com にも合う）
public struct SiteReference: Codable, Hashable, Sendable {
    public var host: String

    /// host は SiteReference.normalizedHost で整えたもの
    public init(host: String) {
        self.host = Self.normalizedHost(host) ?? host.lowercased()
    }

    /// URL・ホスト名・「www.」付きのどれからでも、ホスト名を取り出す（https://www.YouTube.com/watch → youtube.com）。
    /// 取り出せなければ nil（空・空白を含む・点の無い名前（localhost を除く））
    public static func normalizedHost(_ input: String) -> String? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return nil }
        if !text.contains("://") {
            text = "https://" + text
        }
        guard let host = URLComponents(string: text)?.host, !host.isEmpty, !host.contains(" ") else { return nil }
        let trimmed = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        guard trimmed.contains(".") || trimmed == "localhost" else { return nil }
        return trimmed.hasSuffix(".") ? String(trimmed.dropLast()) : trimmed
    }

    /// 見ているページのホスト名（www. 付きでもよい）が、このサイトかそのサブドメインか
    public func matches(host other: String) -> Bool {
        guard let other = Self.normalizedHost(other) else { return false }
        return other == host || other.hasSuffix("." + host)
    }
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

    public var site: SiteReference? {
        if case .site(let site) = kind { return site }
        return nil
    }

    /// どこかのページにマスが1つでもある（空きマスだけのアプリのプロファイルは、9マスでも早見表でも無いものとして扱う）
    public var hasButtons: Bool {
        pages.contains { page in page.cells.contains { $0 != nil } }
    }

    /// 表示名。グローバルは「グローバル」（ローカライズ済み）、アプリはアプリ名
    public var name: String {
        switch kind {
        case .global: String(localized: "グローバル", bundle: .module)
        case .app(let app): app.nameOrBundleID
        case .site(let site): site.host
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
        case id, title, icon, action
        /// 前の版（HUD で選んだときだけ実行する）と同じ名前のまま読み書きする
        case requiresHold = "requiresHUD"
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
            requiresHold: container.decodeLossy(Bool.self, forKey: .requiresHold, default: false)
        )
    }

    /// requiresHUD は true のときだけ書く（この設定より前の版と同じ書式のまま）
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(icon, forKey: .icon)
        try container.encode(action, forKey: .action)
        if requiresHold {
            try container.encode(true, forKey: .requiresHold)
        }
    }
}

extension Page {
    private enum CodingKeys: String, CodingKey {
        case cells, name, buttons
    }

    /// cells はボタンの数（buttons。無ければ 9、選べない数は近い数）に揃える。読めないマスは空きマス。名前が無い・読めなければ nil
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let cells = container.decodeLossy([LossyElement<Cell>].self, forKey: .cells, default: [])
        let layout = container.decodeLossy(Int?.self, forKey: .buttons, default: nil).map(PageLayout.init(nearest:)) ?? .nine
        if cells.count != layout.slotCount {
            DecodingIssue.log("マスの数（\(cells.count)）", at: container.codingPath + [CodingKeys.cells])
        }
        self.init(cells: cells.map(\.value), name: container.decodeLossy(String?.self, forKey: .name, default: nil), layout: layout)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Page(cells: cells, layout: layout).cells, forKey: .cells)
        // 9 のページは書かない（数を選べるようになる前と同じ書式のまま）
        if layout != .nine {
            try container.encode(layout.slotCount, forKey: .buttons)
        }
        // 名前の無いページは書かない（名前を付けられるようになる前と同じ書式のまま）
        if let name = Page.normalizedName(name) {
            try container.encode(name, forKey: .name)
        }
    }
}

extension ProfileKind {
    private enum CodingKeys: String, CodingKey {
        case type, app, site
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "global":
            self = .global
        case "app":
            self = .app(try container.decode(AppReference.self, forKey: .app))
        case "site":
            self = .site(try container.decode(SiteReference.self, forKey: .site))
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
        case .site(let site):
            try container.encode("site", forKey: .type)
            try container.encode(site, forKey: .site)
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
    /// ページ数を 1〜maxPages、各ページをボタンの数に揃える
    mutating func normalizePages() {
        if pages.isEmpty {
            pages = [.empty]
        } else if pages.count > Profile.maxPages {
            pages = Array(pages.prefix(Profile.maxPages))
        }
        for index in pages.indices where pages[index].cells.count != pages[index].layout.slotCount {
            pages[index] = Page(cells: pages[index].cells, name: pages[index].name, layout: pages[index].layout)
        }
    }
}
