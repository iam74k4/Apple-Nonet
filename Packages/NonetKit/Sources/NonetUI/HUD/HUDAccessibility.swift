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
}
