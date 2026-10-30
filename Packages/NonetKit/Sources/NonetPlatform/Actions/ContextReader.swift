// 担当: platform-actions
import AppKit
import NonetCore

/// アクションに渡す文脈のうち、読むもの
struct ContextNeeds: OptionSet, Sendable {
    let rawValue: Int

    /// アクセシビリティ API で選択中のテキストを読む（副作用なし）
    static let selectedText = ContextNeeds(rawValue: 1 << 0)
    /// アクセシビリティで選択を読めないアプリ（Electron など）では ⌘C でクリップボード経由で取る（クリップボードは元に戻す）
    static let copyFallback = ContextNeeds(rawValue: 1 << 1)
    static let documentPath = ContextNeeds(rawValue: 1 << 2)
    /// 前面が対応しているブラウザなら AppleScript で聞く（初回はオートメーションの確認が出る）
    static let browserURL = ContextNeeds(rawValue: 1 << 3)
    /// アクセシビリティが「選択なし」と答えても ⌘C を試す。選択があるのに空と答えるアプリもあるので、
    /// 選択テキストを処理するためのアクション（AI・ショートカット）で使う
    static let copyWhenEmpty = ContextNeeds(rawValue: 1 << 4)

    /// スクリプトのソースに書かれている変数の文脈だけを読む。
    /// 選択テキスト（⌘C を送ることがある）とブラウザの URL（オートメーションの確認が出る）は副作用があるので、
    /// 使わないスクリプトでは読まない。外部のファイルに渡したいときは、ソースのどこか（コメントでもよい）に変数名を書く。
    /// 書類の場所は副作用が無く、プロジェクトのフォルダ（作業フォルダ）を決めるのに使うので、いつも読む。
    /// 選択が空と読めたときは ⌘C を送らない（送っても多くのアプリで警告音が鳴るだけ）
    static func forScript(source: String) -> ContextNeeds {
        var needs: ContextNeeds = [.documentPath]
        if source.contains(ScriptVariableName.selectedText) {
            needs.formUnion([.selectedText, .copyFallback])
        }
        if source.contains(ScriptVariableName.browserURL) {
            needs.insert(.browserURL)
        }
        return needs
    }

    static func forShortcut(_ action: ShortcutAction) -> ContextNeeds {
        action.passSelectedText ? [.selectedText, .copyFallback, .copyWhenEmpty] : []
    }

    static let forAI: ContextNeeds = [.selectedText, .copyFallback, .copyWhenEmpty]

    /// アクセシビリティで読んだ選択のあとに ⌘C を送るか
    func needsCopy(after selection: AXSelection) -> Bool {
        switch selection {
        case .text: false
        case .empty: contains(.copyWhenEmpty)
        case .unreadable: contains(.copyFallback) || contains(.copyWhenEmpty)
        }
    }

    /// ブラウザに問い合わせるか。対応していないアプリには osascript を起動しない
    func asksBrowser(bundleID: String) -> Bool {
        contains(.browserURL) && BrowserURLReader.script(forBundleID: bundleID) != nil
    }
}

/// 副作用のある文脈を渡す環境変数の名前（ScriptEnvironment.variables と同じ）
enum ScriptVariableName {
    static let selectedText = "NONET_SELECTED_TEXT"
    static let browserURL = "NONET_BROWSER_URL"
}

/// 選択テキストをどこから取ったか
enum SelectionSource: Equatable, Sendable {
    case accessibility
    /// アクセシビリティでは読めず、⌘C で取った
    case copyAfterUnreadable
    /// アクセシビリティは「選択なし」と答えたが、⌘C で取れた。選択が本当にあるかは分からない
    case copyAfterEmpty
}

/// 読んだ文脈
struct ContextReading: Equatable, Sendable {
    var info: ScriptContextInfo
    var selectionSource: SelectionSource?
    /// クリップボードの中身を保てない（大きすぎる・読む許可が無いなど）ので、⌘C を送らなかった
    var skippedCopy = false
}

/// アクセシビリティ API で読んだ、前面の要素の選択
enum AXSelection: Equatable, Sendable {
    case text(String)
    /// 選択テキストを持つ要素で、選択が空
    case empty
    /// 読めない（前面の要素が無い・属性が無い・応答しない）。選択があるかどうか分からない
    case unreadable

    init(error: AXError, value: CFTypeRef?) {
        guard error == .success, let text = value as? String else {
            self = .unreadable
            return
        }
        self = text.isEmpty ? .empty : .text(text)
    }
}

/// 前面アプリの文脈（選択中のテキスト・書類・ブラウザの URL）を読む
@MainActor
final class ContextReader {
    /// 環境変数の大きさには上限（ARG_MAX）があるので、スクリプトに渡す選択テキストはここで切る
    static let scriptSelectedTextLimit = 50_000

    /// 文脈を読む手段。テストでは偽物に差し替える
    struct Sources {
        var selection: @Sendable (pid_t) async -> AXSelection
        var documentPath: @Sendable (pid_t) async -> String?
        var browserURL: @Sendable (_ bundleID: String) async -> String?
        /// ⌘C を送ってクリップボードから読み、クリップボードを元に戻す
        var copySelection: @MainActor () async -> ClipboardCopy.Outcome

        static func live(keySender: KeySender) -> Sources {
            Sources(
                selection: { pid in
                    await Task.detached(priority: .userInitiated) { AXContext.selection(pid: pid) }.value
                },
                documentPath: { pid in
                    await Task.detached(priority: .userInitiated) { AXContext.documentPath(pid: pid) }.value
                },
                browserURL: { bundleID in await BrowserURLReader.read(bundleID: bundleID) },
                copySelection: {
                    await ClipboardCopy.copySelection(from: .general) {
                        try await keySender.send(.key("c", .command))
                    }
                }
            )
        }
    }

    /// 何も選択していないと ⌘C でカーソルのある行を丸ごとコピーするエディタ（VS Code 系の editor.emptySelectionClipboard、
    /// CodeMirror 6 の lineWiseCopyCut、JetBrains、Sublime Text）
    nonisolated static let lineCopyingEditorIDs: Set<String> = [
        "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.vscodium", "com.visualstudio.code.oss",
        "com.todesktop.230313mzl4w4u92", // Cursor
        "com.exafunction.windsurf",
        "md.obsidian",
        "com.sublimetext.4", "com.sublimetext.3",
        "com.google.android.studio",
    ]
    nonisolated static let lineCopyingEditorPrefixes = ["com.jetbrains."]

    nonisolated static func copiesLineWhenNothingSelected(bundleID: String) -> Bool {
        lineCopyingEditorIDs.contains(bundleID) || lineCopyingEditorPrefixes.contains { bundleID.hasPrefix($0) }
    }

    /// ⌘C で取った文字を選択テキストとして使うか。行を丸ごとコピーするエディタで、改行で終わる1行だけなら
    /// 何も選択していなかったとみなす（その行を選択とみなすと、AI の結果をカーソルの位置に貼り付けて行を壊す）
    nonisolated static func selectedText(fromCopy text: String, bundleID: String) -> String? {
        guard copiesLineWhenNothingSelected(bundleID: bundleID), text.hasSuffix("\n") else { return text }
        let body = text.dropLast()
        return body.contains(where: \.isNewline) ? text : nil
    }

    private let sources: Sources

    convenience init(keySender: KeySender) {
        self.init(sources: .live(keySender: keySender))
    }

    init(sources: Sources) {
        self.sources = sources
    }

    func read(_ needs: ContextNeeds, app: RunningAppInfo?) async -> ContextReading {
        var reading = ContextReading(info: ScriptContextInfo(app: app?.app))
        guard let app, !needs.isEmpty else { return reading }
        let pid = app.processID
        let bundleID = app.app.bundleID
        let asksBrowser = needs.asksBrowser(bundleID: bundleID)
        let readBrowserURL = sources.browserURL
        // ブラウザへの問い合わせ（別プロセスで最大2秒）は、アクセシビリティで読むのと並べて行う
        async let browserURL: String? = asksBrowser ? readBrowserURL(bundleID) : nil
        if needs.contains(.documentPath) {
            reading.info.documentPath = await sources.documentPath(pid)
        }
        if needs.contains(.selectedText) {
            let selection = await sources.selection(pid)
            if case .text(let text) = selection {
                reading.info.selectedText = text
                reading.selectionSource = .accessibility
            } else if needs.needsCopy(after: selection) {
                switch await sources.copySelection() {
                case .copied(let text):
                    if let text = Self.selectedText(fromCopy: text, bundleID: bundleID) {
                        reading.info.selectedText = text
                        reading.selectionSource = selection == .empty ? .copyAfterEmpty : .copyAfterUnreadable
                    }
                case .clipboardUnavailable:
                    reading.skippedCopy = true
                case .nothing, .failed:
                    break
                }
            }
        }
        reading.info.browserURL = await browserURL
        return reading
    }
}

/// アクセシビリティ API で読む文脈。応答しないアプリで長く待たないよう、メインスレッドの外で短い待ち時間で読む
enum AXContext {
    static let timeout: Float = 0.5

    static func selection(pid: pid_t) -> AXSelection {
        let application = AXRead.application(pid: pid, timeout: timeout)
        guard let focused = AXRead.element(application, kAXFocusedUIElementAttribute) else { return .unreadable }
        AXUIElementSetMessagingTimeout(focused, timeout)
        let (error, value) = AXRead.copy(focused, kAXSelectedTextAttribute)
        return AXSelection(error: error, value: value)
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
