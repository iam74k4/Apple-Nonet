// 担当: platform-actions
import Foundation
import NonetCore

/// メニューのタイトルの比べ方
enum MenuTitleMatcher {
    /// 前後の空白を除き、空白の並びを1つにし、末尾の「…」「...」を外し、大文字小文字・全角半角を区別しない
    static func normalized(_ title: String) -> String {
        var text = title
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        for suffix in ["…", "..."] where text.hasSuffix(suffix) {
            text = String(text.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
        }
        return text.folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)
    }

    /// 完全一致（前後の空白は除く）を優先し、無ければ normalized で比べる
    static func index(of wanted: String, in titles: [String?]) -> Int? {
        let trimmed = wanted.trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = titles.firstIndex(where: { $0?.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed }) {
            return exact
        }
        let key = normalized(wanted)
        guard !key.isEmpty else { return nil }
        return titles.firstIndex { $0.map(normalized) == key }
    }

    static func displayPath(_ path: [String]) -> String {
        path.joined(separator: " > ")
    }
}

/// メニュー項目から一度に読む値
struct MenuEntryAttributes: Equatable {
    var title: String?
    var isEnabled = true
    var cmdChar: String?
    var cmdModifiers: Int?
    var cmdVirtualKey: Int?
    var cmdGlyph: Int?

    var keyEquivalent: KeySequence? {
        MenuShortcutDecoder.keySequence(cmdChar: cmdChar, modifiers: cmdModifiers, virtualKey: cmdVirtualKey, glyph: cmdGlyph)
    }

    var trimmedTitle: String {
        (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// メニューバーの木。本物はアクセシビリティ API（AXMenuTree）、テストでは偽物
protocol MenuTree {
    associatedtype Node
    /// メニューバーの項目（先頭は Apple メニュー）
    func menuBarItems() throws -> [Node]
    func attributes(of node: Node) -> MenuEntryAttributes
    /// その項目が開くメニューの項目。無ければ空
    func submenuItems(of node: Node) -> [Node]
}

struct MenuTreeLimits {
    /// メニューバーの項目を 0 とした深さ
    var maxDepth = 5
    /// 履歴やブックマークのような巨大なメニューで止まらないように
    var maxItems = 3000

    static let standard = MenuTreeLimits()
}

enum MenuTreeBuilder {
    /// Apple メニューと区切り線（タイトルの無い項目）を除いた MenuItemNode の木
    static func build<Tree: MenuTree>(_ tree: Tree, limits: MenuTreeLimits = .standard) throws -> [MenuItemNode] {
        var remaining = limits.maxItems
        let barItems = try tree.menuBarItems().dropFirst()
        return nodes(for: Array(barItems), in: tree, parentPath: [], depth: 0, limits: limits, remaining: &remaining)
    }

    private static func nodes<Tree: MenuTree>(
        for items: [Tree.Node],
        in tree: Tree,
        parentPath: [String],
        depth: Int,
        limits: MenuTreeLimits,
        remaining: inout Int
    ) -> [MenuItemNode] {
        var result: [MenuItemNode] = []
        for item in items {
            guard remaining > 0 else { break }
            let attributes = tree.attributes(of: item)
            let title = attributes.trimmedTitle
            guard !title.isEmpty else { continue }
            remaining -= 1
            let path = parentPath + [title]
            let children = depth < limits.maxDepth
                ? nodes(for: tree.submenuItems(of: item), in: tree, parentPath: path, depth: depth + 1, limits: limits, remaining: &remaining)
                : []
            result.append(MenuItemNode(
                title: title,
                path: path,
                keyEquivalent: depth == 0 ? nil : attributes.keyEquivalent,
                isEnabled: attributes.isEnabled,
                children: children
            ))
        }
        return result
    }
}

enum MenuPathResolver {
    /// タイトルの並びをたどった先の項目。Apple メニューは見ない。見つからなければ nil
    static func resolve<Tree: MenuTree>(_ path: [String], in tree: Tree) throws -> Tree.Node? {
        guard !path.isEmpty else { return nil }
        var candidates = Array(try tree.menuBarItems().dropFirst())
        var found: Tree.Node?
        for (level, title) in path.enumerated() {
            if level > 0, let parent = found {
                candidates = tree.submenuItems(of: parent)
            }
            let titles = candidates.map { tree.attributes(of: $0).title }
            guard let index = MenuTitleMatcher.index(of: title, in: titles) else { return nil }
            found = candidates[index]
        }
        return found
    }
}
