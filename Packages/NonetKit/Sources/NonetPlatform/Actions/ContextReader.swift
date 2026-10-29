// 担当: platform-actions
import AppKit
import NonetCore

/// アクションに渡す文脈のうち、読むもの
struct ContextNeeds: OptionSet, Sendable {
    let rawValue: Int

    /// アクセシビリティ API で選択中のテキストを読む（副作用なし）
    static let selectedText = ContextNeeds(rawValue: 1 << 0)
    /// 読めなければ ⌘C でクリップボード経由で取る（クリップボードは元に戻す）
    static let copyFallback = ContextNeeds(rawValue: 1 << 1)
    static let documentPath = ContextNeeds(rawValue: 1 << 2)
    /// ブラウザに AppleScript で聞く（初回はオートメーションの確認が出る）
    static let browserURL = ContextNeeds(rawValue: 1 << 3)

    /// スクリプトが何を使うかは分からないので、副作用の無いもの（書類・アクセシビリティでの選択テキスト）は常に読み、
    /// ⌘C とブラウザへの問い合わせは、その変数がソースに書かれているときだけ行う
    static func forScript(source: String) -> ContextNeeds {
        var needs: ContextNeeds = [.selectedText, .documentPath]
        if source.contains("NONET_SELECTED_TEXT") { needs.insert(.copyFallback) }
        if source.contains("NONET_BROWSER_URL") { needs.insert(.browserURL) }
        return needs
    }

    static func forShortcut(_ action: ShortcutAction) -> ContextNeeds {
        action.passSelectedText ? [.selectedText, .copyFallback] : []
    }

    static let forAI: ContextNeeds = [.selectedText, .copyFallback]
}

/// 前面アプリの文脈（選択中のテキスト・書類・ブラウザの URL）を読む
@MainActor
final class ContextReader {
    /// 環境変数の大きさには上限（ARG_MAX）があるので、スクリプトに渡す選択テキストはここで切る
    static let scriptSelectedTextLimit = 50_000

    private let keySender: KeySender

    init(keySender: KeySender) {
        self.keySender = keySender
    }

    func read(_ needs: ContextNeeds, app: RunningAppInfo?) async -> ScriptContextInfo {
        var info = ScriptContextInfo(app: app?.app)
        guard let app, !needs.isEmpty else { return info }
        let pid = app.processID
        if needs.contains(.documentPath) {
            info.documentPath = await Task.detached(priority: .userInitiated) {
                AXContext.documentPath(pid: pid)
            }.value
        }
        if needs.contains(.selectedText) {
            info.selectedText = await Task.detached(priority: .userInitiated) {
                AXContext.selectedText(pid: pid)
            }.value
            if info.selectedText == nil, needs.contains(.copyFallback) {
                info.selectedText = await copySelection()
            }
        }
        if needs.contains(.browserURL) {
            info.browserURL = await BrowserURLReader.read(bundleID: app.app.bundleID)
        }
        return info
    }

    /// ⌘C を送ってクリップボードから読み、クリップボードを元に戻す
    private func copySelection() async -> String? {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard)
        let before = pasteboard.changeCount
        do {
            try await keySender.send(.key("c", .command))
        } catch {
            ActionLog.logger.notice("選択テキストを ⌘C で取れませんでした: \(error.localizedDescription)")
            return nil
        }
        // アプリがクリップボードに書くのを待つ（最大 0.5 秒）
        var text: String?
        var copied = false
        for _ in 0 ..< 25 {
            try? await Task.sleep(for: .milliseconds(20))
            if pasteboard.changeCount != before {
                copied = true
                text = pasteboard.string(forType: .string)
                if text != nil { break }
            }
        }
        guard copied else { return nil }
        snapshot.restore(to: pasteboard)
        guard let text, !text.isEmpty else { return nil }
        return text
    }
}

/// アクセシビリティ API で読む文脈。応答しないアプリで長く待たないよう、メインスレッドの外で短い待ち時間で読む
enum AXContext {
    static let timeout: Float = 0.5

    static func selectedText(pid: pid_t) -> String? {
        let application = AXRead.application(pid: pid, timeout: timeout)
        guard let focused = AXRead.element(application, kAXFocusedUIElementAttribute) else { return nil }
        AXUIElementSetMessagingTimeout(focused, timeout)
        guard let text = AXRead.string(focused, kAXSelectedTextAttribute), !text.isEmpty else { return nil }
        return text
    }

    static func documentPath(pid: pid_t) -> String? {
        let application = AXRead.application(pid: pid, timeout: timeout)
        let window = AXRead.element(application, kAXFocusedWindowAttribute) ?? AXRead.element(application, kAXMainWindowAttribute)
        guard let window else { return nil }
        AXUIElementSetMessagingTimeout(window, timeout)
        return AXRead.string(window, kAXDocumentAttribute).flatMap(DocumentPathParser.path(fromAXDocument:))
    }
}

enum DocumentPathParser {
    /// kAXDocumentAttribute は "file:///…" の URL か、まれにパスそのもの。ファイル以外は nil
    static func path(fromAXDocument value: String) -> String? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("/") { return trimmingTrailingSlash(text) }
        guard let url = URL(string: text), url.isFileURL else { return nil }
        let path = url.path(percentEncoded: false)
        return path.isEmpty ? nil : trimmingTrailingSlash(path)
    }

    private static func trimmingTrailingSlash(_ path: String) -> String {
        var path = path
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }
}

/// ブラウザで表示中のページの URL。AppleScript は別プロセス（osascript）で、短い制限時間で聞く
enum BrowserURLReader {
    static let timeout: TimeInterval = 2

    private static let safariIDs: Set<String> = ["com.apple.Safari", "com.apple.SafariTechnologyPreview"]
    private static let chromiumIDs: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary",
        "company.thebrowser.Browser",
        "com.microsoft.edgemac", "com.microsoft.edgemac.Beta", "com.microsoft.edgemac.Dev", "com.microsoft.edgemac.Canary",
        "com.brave.Browser", "com.brave.Browser.beta", "com.brave.Browser.nightly",
    ]

    /// 対応するブラウザなら AppleScript。bundleID は上の決まった表からしか入らない
    static func script(forBundleID bundleID: String) -> String? {
        if safariIDs.contains(bundleID) {
            return "tell application id \"\(bundleID)\" to return URL of front document"
        }
        if chromiumIDs.contains(bundleID) {
            return "tell application id \"\(bundleID)\" to return URL of active tab of front window"
        }
        return nil
    }

    static func parse(_ output: String) -> String? {
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty || text == "missing value" ? nil : text
    }

    /// オートメーションが許可されていない・ウィンドウが無い・時間切れなら nil
    static func read(bundleID: String) async -> String? {
        guard let script = script(forBundleID: bundleID) else { return nil }
        do {
            let output = try await ProcessRunner.run(ProcessRequest(
                executable: URL(fileURLWithPath: "/usr/bin/osascript"),
                arguments: ["-e", script],
                environment: nil,
                currentDirectory: nil,
                timeout: timeout,
                outputLimit: 16 * 1024
            ))
            guard output.succeeded else {
                ActionLog.logger.notice("ブラウザの URL を取れませんでした（終了コード \(output.status)）")
                return nil
            }
            return parse(output.stdout)
        } catch {
            return nil
        }
    }
}
