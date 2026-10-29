// 担当: platform-actions
// クラス名・public init・protocol への準拠は契約（NonetServices.live() が使う）
import AppKit
import NonetCore

/// Action を実行する（キー送出・アプリ起動・URL・スクリプト・ショートカット・メニュー・AI）
@MainActor
public final class SystemActionPerformer: ActionPerforming {
    private let keySender: KeySender
    private let contextReader: ContextReader

    public init() {
        keySender = KeySender()
        contextReader = ContextReader(keySender: keySender)
    }

    public func perform(_ action: Action, context: ActionContext) async throws {
        if let text = try await performReturningOutput(action, context: context) {
            // AI の showResult を HUD に出す口がまだ無いので、クリップボードに入れておく
            PasteboardWriter.write(text, to: .general)
        }
    }

    /// perform と同じだが、AI の showResult の結果を返す（ほかのアクションは nil）。
    /// 呼び出し側が結果を表示できるときはこちらを使う
    public func performReturningOutput(_ action: Action, context: ActionContext) async throws -> String? {
        do {
            return try await run(action, frontmost: context.frontmostApp ?? Self.currentFrontmostApp())
        } catch let error as NonetError {
            ActionLog.logger.error("アクション \(action.kind.rawValue, privacy: .public) に失敗しました: \(error.localizedDescription)")
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            ActionLog.logger.error("アクション \(action.kind.rawValue, privacy: .public) に失敗しました: \(String(describing: error))")
            throw NonetError.actionFailed(error.localizedDescription)
        }
    }

    private func run(_ action: Action, frontmost: RunningAppInfo?) async throws -> String? {
        switch action {
        case .keystroke(let keys):
            try await keySender.send(keys)
        case .launchApp(let launch):
            try await AppLauncher.launch(launch)
        case .openURL(let url):
            try await URLNormalizer.open(url.url)
        case .script(let script):
            try await runScript(script, frontmost: frontmost)
        case .shortcut(let shortcut):
            try await runShortcut(shortcut, frontmost: frontmost)
        case .menuItem(let menuItem):
            try await pressMenuItem(menuItem, frontmost: frontmost)
        case .ai(let ai):
            return try await runAI(ai, frontmost: frontmost)
        }
        return nil
    }

    private static func currentFrontmostApp() -> RunningAppInfo? {
        guard let app = NSWorkspace.shared.frontmostApplication, let bundleID = app.bundleIdentifier else { return nil }
        return RunningAppInfo(app: AppReference(bundleID: bundleID, name: app.localizedName ?? bundleID), processID: app.processIdentifier)
    }

    // MARK: - スクリプト

    private func runScript(_ script: ScriptAction, frontmost: RunningAppInfo?) async throws {
        try ScriptRunner.validate(source: script.source)
        var info = await contextReader.read(.forScript, app: frontmost)
        if let text = info.selectedText, text.count > ContextReader.scriptSelectedTextLimit {
            info.selectedText = String(text.prefix(ContextReader.scriptSelectedTextLimit))
        }
        let projectDirectory = info.documentPath.map { path in
            ScriptEnvironment.projectDirectory(forDocumentPath: path) { FileManager.default.fileExists(atPath: $0) }
        }
        let variables = ScriptEnvironment.variables(for: info, projectDirectory: projectDirectory)
        let workingDirectory = ScriptRunner.workingDirectory(
            projectDirectory: projectDirectory,
            home: FileManager.default.homeDirectoryForCurrentUser,
            isDirectory: ScriptRunner.isDirectory
        )
        switch script.runMode {
        case .background:
            try await ScriptRunner.runInBackground(
                source: script.source,
                environment: ScriptRunner.environment(base: ProcessInfo.processInfo.environment, context: variables),
                workingDirectory: workingDirectory,
                timeout: ScriptRunner.effectiveTimeout(script.timeout)
            )
        case .terminal:
            try await TerminalCommandFile.open(source: script.source, variables: variables, workingDirectory: workingDirectory.path)
        }
    }

    // MARK: - ショートカット

    private func runShortcut(_ shortcut: ShortcutAction, frontmost: RunningAppInfo?) async throws {
        var input: String?
        if shortcut.passSelectedText {
            input = await contextReader.read(.forShortcut(shortcut), app: frontmost).selectedText
        }
        try await ShortcutRunner.run(name: shortcut.name, input: input)
    }

    // MARK: - メニュー項目

    private func pressMenuItem(_ action: MenuItemAction, frontmost: RunningAppInfo?) async throws {
        let target: NSRunningApplication
        let name: String
        if let app = action.app {
            name = app.name.isEmpty ? app.bundleID : app.name
            guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).first(where: { !$0.isTerminated }) else {
                throw NonetError.actionFailed(String(localized: "\(name) が起動していません", bundle: .nonetActions))
            }
            target = running
        } else {
            guard let frontmost, let running = NSRunningApplication(processIdentifier: frontmost.processID) else {
                throw NonetError.actionFailed(String(localized: "前面のアプリが見つかりません", bundle: .nonetActions))
            }
            name = frontmost.app.name
            target = running
        }
        let isFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier
        if MenuActionPlan.decide(isTargetFrontmost: isFrontmost, keyEquivalent: action.keyEquivalent) == .sendKeys,
           let keys = action.keyEquivalent {
            do {
                try await keySender.send(keys)
                return
            } catch NonetError.permissionDenied(let permission) {
                throw NonetError.permissionDenied(permission)
            } catch {
                // 今のキー配列で打てないショートカットなどは、メニューを押す方法に切り替える
                ActionLog.logger.notice("ショートカットを送れなかったので、メニューを押します")
            }
        }
        guard AXIsProcessTrusted() else { throw NonetError.permissionDenied(ActionText.accessibility) }
        let pid = target.processIdentifier
        let path = action.path
        try await Task.detached(priority: .userInitiated) {
            try MenuItemPresser.press(path: path, pid: pid, appName: name)
        }.value
    }

    // MARK: - AI

    private func runAI(_ ai: AIAction, frontmost: RunningAppInfo?) async throws -> String? {
        // 使えないなら、⌘C などを送る前に知らせる
        try OnDeviceAI.checkAvailability()
        let info = await contextReader.read(.forAI, app: frontmost)
        guard let text = info.selectedText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NonetError.actionFailed(String(localized: "テキストを選択してから実行してください", bundle: .nonetActions))
        }
        let result = try await OnDeviceAI.respond(instruction: ai.prompt, text: text)
        switch ai.output {
        case .replaceSelection:
            try await replaceSelection(with: result, in: frontmost)
            return nil
        case .copyToClipboard:
            PasteboardWriter.write(result, to: .general)
            return nil
        case .showResult:
            return result
        }
    }

    /// クリップボード経由で ⌘V し、少し待ってから元のクリップボードに戻す
    private func replaceSelection(with text: String, in app: RunningAppInfo?) async throws {
        let pasteboard = NSPasteboard.general
        // AI の処理中にほかのアプリへ移っていたら、そこへは貼らない
        if let app, NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processID {
            PasteboardWriter.write(text, to: pasteboard)
            throw NonetError.actionFailed(String(localized: "前面のアプリが変わったため、結果をクリップボードにコピーしました", bundle: .nonetActions))
        }
        let snapshot = PasteboardSnapshot(pasteboard)
        let changeCount = PasteboardWriter.write(text, to: pasteboard, transient: true)
        do {
            try await keySender.send(.key("v", .command))
        } catch {
            snapshot.restore(to: pasteboard)
            throw error
        }
        Task { @MainActor in
            // アプリがクリップボードを読み終えるのを待つ。その間に利用者がコピーしたものは消さない
            try? await Task.sleep(for: .milliseconds(600))
            if pasteboard.changeCount == changeCount { snapshot.restore(to: pasteboard) }
        }
    }
}

enum MenuActionPlan: Equatable {
    case sendKeys
    case pressMenu

    /// 対象アプリが前面にあり、ショートカットが分かっていればキーを送る（速い）。ほかはメニューを押す
    static func decide(isTargetFrontmost: Bool, keyEquivalent: KeySequence?) -> MenuActionPlan {
        guard isTargetFrontmost, let keyEquivalent, !keyEquivalent.chords.isEmpty else { return .pressMenu }
        return .sendKeys
    }
}
