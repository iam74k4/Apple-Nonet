// 担当: platform-actions
// サイトごとのボタン: ブラウザの前面のウインドウで見ているページの URL を、アクセシビリティで読む（オートメーションの許可は要らない）。
// 9マスを開くときに1回だけ読む。止まりかけたブラウザでも開くのを遅らせないよう、短い制限時間と、たどる数の上限を付ける
import AppKit
import ApplicationServices

@MainActor
enum BrowserSiteReader {
    /// ブラウザに聞く1回の制限時間（秒）。超えたら分からないことにして、ブラウザのボタンを使う
    static let messagingTimeout: Float = 0.08
    /// たどる要素の上限（ウェブの中身の要素は数えきれないので、見つからなければあきらめる）
    static let maxVisited = 400
    /// Chromium 系にアクセシビリティの木を作らせた pid（1つのプロセスに1回だけ頼む）
    private static var enabledChromiumPIDs: Set<pid_t> = []

    /// 前面のブラウザで見ているページのホスト名。対応していないアプリ・読めないときは nil
    static func host(bundleID: String, processID: pid_t) -> String? {
        guard BrowserURLReader.isSupported(bundleID: bundleID) else { return nil }
        let application = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(application, messagingTimeout)
        if BrowserURLReader.isChromium(bundleID: bundleID), enabledChromiumPIDs.insert(processID).inserted {
            // Chromium 系は、支援技術が使われていないとウェブの中身の木を作らない。作るよう頼む（VoiceOver と同じ頼み方）
            AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        }
        guard let window = element(application, kAXFocusedWindowAttribute), let url = webAreaURL(in: window) else { return nil }
        return url.host
    }

    /// ウインドウの中の、いちばん外側のウェブの中身（AXWebArea）の AXURL。幅優先でたどる
    static func webAreaURL(in window: AXUIElement) -> URL? {
        var queue: [AXUIElement] = [window]
        var visited = 0
        while !queue.isEmpty, visited < maxVisited {
            let current = queue.removeFirst()
            visited += 1
            AXUIElementSetMessagingTimeout(current, messagingTimeout)
            if string(current, kAXRoleAttribute) == "AXWebArea" {
                if let url = url(current, "AXURL") { return url }
                continue
            }
            queue += children(of: current)
        }
        return nil
    }

    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func url(_ element: AXUIElement, _ attribute: String) -> URL? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value else { return nil }
        if let url = value as? URL { return url }
        if let text = value as? String { return URL(string: text) }
        return nil
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement] else { return [] }
        return children
    }
}
