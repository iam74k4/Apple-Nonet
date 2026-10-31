// 担当: core-model。共通マス（すべてのアプリの同じ位置に出すマス）
import Foundation

/// 共通マス。位置（0〜8）ごとに1つまで置け、すべてのプロファイル（アプリのプロファイルとグローバル。ランチャーのページも）の
/// すべてのページで、その位置のマスの代わりに出る（NonetConfiguration.resolvedPages(frontmostBundleID:)）。
/// 代わりに出ている間も、プロファイルのその位置のマスは消さずに残し、共通マスを外すと元に戻る
public struct SharedCells: Equatable, Sendable {
    /// 設定画面で、共通マスを1ページのプロファイルのように選んで編集するときの id。
    /// NonetConfiguration.setCell(_:at:profileID:)・swapCells(_:_:profileID:) にこの id を渡すと共通マスを変える。
    /// 設定ファイルには書かず、プロファイルの id には使わない（NonetConfiguration.validated() が振り直す）
    public static let profileID = UUID(uuid: (0x5E, 0xA4, 0xED, 0xCE, 0x11, 0x5A, 0x40, 0x00, 0x80, 0x00, 0, 0, 0, 0, 0, 0x09))

    /// 置ける位置（左上から右へ、上の行から）
    public static let positions = 0..<Page.cellCount

    /// 常に Page.cellCount 個。nil はその位置に共通マスが無い
    public private(set) var cells: [Cell?]

    /// 9個に満たなければ nil で埋め、多ければ切り捨てる
    public init(cells: [Cell?] = []) {
        self.cells = Page(cells: cells).cells
    }

    public static var empty: SharedCells { SharedCells() }

    /// その位置の共通マス。範囲外は nil（入れても何もしない）
    public subscript(position: Int) -> Cell? {
        get { Self.positions.contains(position) ? cells[position] : nil }
        set {
            guard Self.positions.contains(position) else { return }
            cells[position] = newValue
        }
    }

    /// 共通マスが1つも無い
    public var isEmpty: Bool { cells.allSatisfy { $0 == nil } }

    /// 共通マスのある位置（小さい順）
    public var occupiedPositions: [Int] { cells.indices.filter { cells[$0] != nil } }

    public var count: Int { occupiedPositions.count }

    /// ページのマスに共通マスを重ねたもの（共通マスのある位置だけ置き換える）
    public func overlaying(_ cells: [Cell?]) -> [Cell?] {
        Page(cells: cells).cells.enumerated().map { position, cell in self[position] ?? cell }
    }

    /// 設定画面で1ページのプロファイルのように編集するときのページ
    public var page: Page { Page(cells: cells) }
}

// MARK: - Codable
// 位置とマスの組を位置の順に並べる: [{"position": 4, "cell": {...}}, ...]。
// 0〜8 でない位置・同じ位置の2つ目以降・読めないマスは、ログを残して外す（ほかの共通マスと設定全体は読む）

extension SharedCells: Codable {
    private struct Entry: Codable {
        var position: Int
        var cell: Cell
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let entries = try container.decode([LossyElement<Entry>].self)
        var cells = [Cell?](repeating: nil, count: Page.cellCount)
        for (offset, element) in entries.enumerated() {
            guard let entry = element.value else { continue }
            guard Self.positions.contains(entry.position) else {
                DecodingIssue.log("共通マスの位置（\(entry.position)）", at: decoder.codingPath)
                continue
            }
            guard cells[entry.position] == nil else {
                DecodingIssue.log("共通マスの位置の重なり（\(entry.position)、\(offset) 個目）", at: decoder.codingPath)
                continue
            }
            cells[entry.position] = entry.cell
        }
        self.init(cells: cells)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        let entries = occupiedPositions.compactMap { position in
            self[position].map { Entry(position: position, cell: $0) }
        }
        try container.encode(entries)
    }
}
