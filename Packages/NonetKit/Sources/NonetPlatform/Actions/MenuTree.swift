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
        path.joined(separator: " › ")
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
    /// タイトルの並びをたどった先の項目。Apple メニューは見ない。見つからなければ nil。
    /// 状態でタイトルが変わる項目（「再生」⇄「一時停止」、「ツールバーを表示」⇄「ツールバーを非表示」）は、
    /// 対になるタイトルでも探す。最後の項目は、それでも無ければ同じショートカットの項目（同じメニューに1つだけのとき）
    static func resolve<Tree: MenuTree>(_ path: [String], keyEquivalent: KeySequence? = nil, in tree: Tree) throws -> Tree.Node? {
        guard !path.isEmpty else { return nil }
        var candidates = Array(try tree.menuBarItems().dropFirst())
        var found: Tree.Node?
        for (level, title) in path.enumerated() {
            if level > 0, let parent = found {
                candidates = tree.submenuItems(of: parent)
            }
            let attributes = candidates.map { tree.attributes(of: $0) }
            let titles = attributes.map(\.title)
            let isLast = level == path.count - 1
            if let index = MenuTitleMatcher.index(of: title, in: titles)
                ?? MenuToggleTitles.alternates(of: title).lazy.compactMap({ MenuTitleMatcher.index(of: $0, in: titles) }).first
                ?? (isLast ? uniqueIndex(of: keyEquivalent, in: attributes) : nil) {
                found = candidates[index]
            } else {
                return nil
            }
        }
        return found
    }

    /// そのショートカットを持つ項目が1つだけならその位置
    private static func uniqueIndex(of keyEquivalent: KeySequence?, in attributes: [MenuEntryAttributes]) -> Int? {
        guard let keyEquivalent, !keyEquivalent.chords.isEmpty else { return nil }
        let matches = attributes.indices.filter { !attributes[$0].trimmedTitle.isEmpty && attributes[$0].keyEquivalent == keyEquivalent }
        return matches.count == 1 ? matches[0] : nil
    }
}

/// 状態で入れ替わるメニュー項目のタイトルの対
enum MenuToggleTitles {
    /// 先頭が入れ替わるもの（英語）。後ろに空白か終わりが続くときだけ
    private static let prefixPairs = [
        ("Show", "Hide"), ("Enter", "Exit"), ("Play", "Pause"), ("Mute", "Unmute"),
        ("Start", "Stop"), ("Turn On", "Turn Off"), ("Enable", "Disable"), ("Lock", "Unlock"),
    ]
    /// 末尾が入れ替わるもの（日本語）
    private static let suffixPairs = [
        ("を非表示", "を表示"), ("にする", "を解除"), ("を開始", "を停止"), ("をオン", "をオフ"),
    ]
    /// 全体が入れ替わるもの
    private static let wholePairs = [
        ("再生", "一時停止"), ("消音", "消音を解除"), ("表示", "非表示"),
    ]

    /// 対になるタイトル。無ければ空
    static func alternates(of title: String) -> [String] {
        let text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var result: [String] = []
        for (a, b) in wholePairs {
            if text == a { result.append(b) }
            if text == b { result.append(a) }
        }
        for (a, b) in prefixPairs {
            for (from, to) in [(a, b), (b, a)] where text == from || text.hasPrefix(from + " ") {
                result.append(to + String(text.dropFirst(from.count)))
            }
        }
        for (a, b) in suffixPairs {
            for (from, to) in [(a, b), (b, a)] where text.hasSuffix(from) && text.count > from.count {
                result.append(String(text.dropLast(from.count)) + to)
            }
        }
        return result
    }
}
