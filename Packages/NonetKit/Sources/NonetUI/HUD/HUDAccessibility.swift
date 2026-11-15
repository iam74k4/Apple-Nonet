// 担当: ui-shell
import AppKit

/// VoiceOver への読み上げの依頼。VoiceOver が動いていなければ何もしない
@MainActor
enum HUDAccessibility {
    static func announce(_ text: String) {
        guard !text.isEmpty, NSWorkspace.shared.isVoiceOverEnabled else { return }
        // Nonet は前面にならないので、アプリ全体の要素から読ませる
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [
                .announcement: text,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }

    static func toastAnnouncement(title: String, detail: String?) -> String {
        guard let detail, !detail.isEmpty else { return title }
        return String(localized: "\(title)、\(detail)", bundle: .module)
    }

    /// 結果のパネルを開いたときに読む文の、結果の文字数の上限（スクリプトや AI の長い出力をすべて読ませない）
    static let resultExcerptLimit = 200

    /// 結果のパネルを開いたとき。名前と、結果の始めの resultExcerptLimit 文字まで。長ければ、続きはパネルで読めることを添える
    static func resultAnnouncement(title: String, text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > resultExcerptLimit else { return toastAnnouncement(title: title, detail: trimmed) }
        let excerpt = String(trimmed.prefix(resultExcerptLimit))
        return String(localized: "\(title)、\(excerpt)…（続きは結果のパネルで読めます）", bundle: .module)
    }
}
