// 担当: ui-settings
// アイコンの候補。SF Symbols は macOS 14 にあるものだけを選んである（SettingsIconLibraryTests が確かめる）
import AppKit
import NonetCore

enum SettingsIconLibrary {
    struct Group: Identifiable {
        var id: String { name }
        var name: String
        var symbols: [String]
    }

    static var groups: [Group] {
        [
            Group(name: String(localized: "よく使う", bundle: .module), symbols: [
                "star", "heart", "bolt", "flag", "bookmark", "tag", "bell", "pin", "paperclip", "link",
                "globe", "house", "gearshape", "magnifyingglass", "info.circle", "questionmark.circle",
                "checkmark.circle", "xmark.circle", "plus.circle", "power", "lock", "key", "person", "person.2",
            ]),
            Group(name: String(localized: "編集", bundle: .module), symbols: [
                "doc", "doc.on.doc", "doc.text", "doc.badge.plus", "folder", "folder.badge.plus", "tray", "tray.full",
                "archivebox", "trash", "pencil", "square.and.pencil", "scissors", "paintbrush", "eraser",
                "textformat", "textformat.size.larger", "bold", "italic", "underline", "text.alignleft",
                "list.bullet", "checklist", "arrow.uturn.backward", "arrow.uturn.forward",
                "square.and.arrow.up", "square.and.arrow.down", "printer",
            ]),
            Group(name: String(localized: "開発", bundle: .module), symbols: [
                "hammer", "wrench.and.screwdriver", "terminal", "apple.terminal",
                "chevron.left.forwardslash.chevron.right", "curlybraces", "play.fill", "stop.fill", "ant",
                "ladybug", "arrow.triangle.branch", "shippingbox", "cpu", "server.rack", "externaldrive",
                "checkmark.diamond", "command", "keyboard",
            ]),
            Group(name: String(localized: "画面と操作", bundle: .module), symbols: [
                "arrow.left", "arrow.right", "arrow.up", "arrow.down", "arrow.clockwise", "arrow.counterclockwise",
                "chevron.backward", "chevron.forward", "arrow.up.left.and.arrow.down.right",
                "arrow.down.right.and.arrow.up.left", "sidebar.left", "sidebar.right", "macwindow",
                "macwindow.badge.plus", "rectangle.split.2x1", "rectangle.split.1x2", "square.grid.2x2",
                "square.grid.3x3", "rectangle.on.rectangle", "display", "cursorarrow", "eye", "eye.slash",
                "filemenu.and.selection", "menubar.dock.rectangle",
            ]),
            Group(name: String(localized: "メディアと連絡", bundle: .module), symbols: [
                "play", "pause", "playpause", "backward", "forward", "speaker.wave.2", "speaker.slash",
                "mic", "mic.slash", "video", "video.slash", "camera", "camera.viewfinder", "photo",
                "music.note", "headphones", "envelope", "paperplane", "bubble.left", "bubble.left.and.bubble.right",
                "phone", "at", "calendar", "clock", "timer",
            ]),
            Group(name: String(localized: "AI と文章", bundle: .module), symbols: [
                "sparkles", "wand.and.stars", "brain", "text.bubble", "character.bubble", "text.magnifyingglass",
                "text.badge.checkmark", "quote.bubble", "lightbulb", "book", "graduationcap", "character.book.closed",
            ]),
        ]
    }

    /// 候補のすべて（重なりなし）
    static var allSymbols: [String] {
        var seen = Set<String>()
        return groups.flatMap(\.symbols).filter { seen.insert($0).inserted }
    }

    /// 検索。英語の名前の一部で探す（"arrow" など）
    static func filter(_ query: String) -> [Group] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return groups }
        return groups.compactMap { group in
            let symbols = group.symbols.filter { symbol in words.allSatisfy { symbol.contains($0) } }
            return symbols.isEmpty ? nil : Group(name: group.name, symbols: symbols)
        }
    }

    /// この Mac で表示できる SF Symbols の名前か
    @MainActor
    static func isAvailable(_ symbol: String) -> Bool {
        NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil
    }

    /// アイコンの種類（ピッカーのタブ）。前の版の「文字」のアイコンは HUD に出るが、新しくは作れない
    enum Kind: String, CaseIterable, Identifiable {
        case symbol, app
        var id: String { rawValue }

        init(_ icon: CellIcon) {
            switch icon {
            case .symbol, .text: self = .symbol
            case .app: self = .app
            }
        }

        var name: String {
            switch self {
            case .symbol: String(localized: "記号", bundle: .module)
            case .app: String(localized: "アプリ", bundle: .module)
            }
        }
    }

    /// アプリのアイコンを使うときのアプリ。アプリ起動ならそのアプリ、アプリのプロファイルならそのアプリ
    static func suggestedApp(for action: Action, profile: Profile) -> String? {
        if case .launchApp(let launch) = action, !launch.app.bundleID.isEmpty {
            return launch.app.bundleID
        }
        if case .menuItem(let menu) = action, let app = menu.app, !app.bundleID.isEmpty {
            return app.bundleID
        }
        return profile.app?.bundleID
    }
}
