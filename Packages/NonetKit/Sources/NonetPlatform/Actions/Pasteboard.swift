// 担当: platform-actions
import AppKit

/// クリップボードの中身の写し。⌘C / ⌘V で一時的に使った後に元へ戻す
struct PasteboardSnapshot {
    private let items: [[(NSPasteboard.PasteboardType, Data)]]

    @MainActor
    init(_ pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
    }

    var isEmpty: Bool { items.isEmpty }

    @MainActor
    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restored = items.compactMap { pairs -> NSPasteboardItem? in
            guard !pairs.isEmpty else { return nil }
            let item = NSPasteboardItem()
            for (type, data) in pairs { item.setData(data, forType: type) }
            return item
        }
        if !restored.isEmpty { pasteboard.writeObjects(restored) }
    }
}

enum PasteboardWriter {
    /// クリップボード履歴のアプリに残さないための印（nspasteboard.org の取り決め）
    static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    /// 文字列を書き、書いた後の changeCount を返す
    @MainActor
    @discardableResult
    static func write(_ text: String, to pasteboard: NSPasteboard, transient: Bool = false) -> Int {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        if transient { item.setData(Data(), forType: transientType) }
        pasteboard.writeObjects([item])
        return pasteboard.changeCount
    }
}
