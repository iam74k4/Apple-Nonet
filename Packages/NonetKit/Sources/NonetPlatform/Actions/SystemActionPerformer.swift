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
        // 前に起動していたときに開かれずに残ったターミナル用のファイル（選択テキストなどが入っている）を消す
        TerminalCommandFile.removeStaleFilesInBackground()
        // 裏のスクリプトに渡す PATH を、最初のスクリプトより前に調べ始めておく（起動ごとに1回）
        UserShell.shared.start()
    }

    public func perform(_ action: Action, context: ActionContext) async throws {
        if let text = try await performReturningOutput(action, context: context) {
            // 「画面に表示」を HUD に出す口がまだ無いので、クリップボードに入れておく
            PasteboardWriter.write(text, to: .general)
        }
    }

    /// perform と同じだが、結果の出し方が「画面に表示」の AI・裏のスクリプト・ショートカットの結果を返す（ほかは nil）。
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
            return try await runScript(script, frontmost: frontmost)
        case .shortcut(let shortcut):
            return try await runShortcut(shortcut, frontmost: frontmost)
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

    private func runScript(_ script: ScriptAction, frontmost: RunningAppInfo?) async throws -> String? {
        try ScriptRunner.validate(source: script.source)
        let reading = await contextReader.read(.forScript(source: script.source), app: frontmost)
        var info = reading.info
        if let text = info.selectedText, text.count > ContextReader.scriptSelectedTextLimit {
            info.selectedText = String(text.prefix(ContextReader.scriptSelectedTextLimit))
        }
        // 書類がネットワークの場所にあると、フォルダを調べるだけで長く止まることがあるので、メインスレッドの外で短く調べる
        let location = await ScriptLocation.find(documentPath: info.documentPath, home: FileManager.default.homeDirectoryForCurrentUser)
        let variables = ScriptEnvironment.variables(for: info, projectDirectory: location.projectDirectory)
        let workingDirectory = location.workingDirectory
        switch script.runMode {
        case .background:
            // ターミナルと同じ PATH（起動時に調べ始めたもの。まだなら終わるまで待つ。調べられなければ今までどおり）
            let shellPath = await UserShell.shared.info()?.path
            let output = try await ScriptRunner.runInBackground(
                source: script.source,
                environment: ScriptRunner.environment(base: ProcessInfo.processInfo.environment, context: variables, shellPath: shellPath),
                workingDirectory: workingDirectory,
                timeout: ScriptRunner.effectiveTimeout(script.timeout),
                shellPath: shellPath
            )
            guard let destination = script.output else { return nil }
            return try await deliver(output, to: destination, selection: reading.selectionSource, frontmost: frontmost)
        case .terminal:
            // 出力はターミナルのウインドウに出るので、結果の出し方は使わない
            try await TerminalCommandFile.open(source: script.source, variables: variables, workingDirectory: workingDirectory.path)
            return nil
        }
    }

    // MARK: - ショートカット

    private func runShortcut(_ shortcut: ShortcutAction, frontmost: RunningAppInfo?) async throws -> String? {
        var reading: ContextReading?
        if shortcut.passSelectedText {
            reading = await contextReader.read(.forShortcut(shortcut), app: frontmost)
        }
        let output = try await ShortcutRunner.run(
            name: shortcut.name,
            input: reading?.info.selectedText,
            wantsTextOutput: shortcut.output != nil
        )
        guard let destination = shortcut.output else { return nil }
        return try await deliver(output, to: destination, selection: reading?.selectionSource, frontmost: frontmost)
    }

    // MARK: - 結果の出し方

    /// スクリプトとショートカットの出力を、選んだ出し方で使う。出力が空なら何もしない
    private func deliver(_ output: ProcessOutput, to destination: AIOutput, selection: SelectionSource?, frontmost: RunningAppInfo?) async throws -> String? {
        guard let text = try CommandOutput.text(from: output) else { return nil }
        return try await deliver(text, to: destination, selection: selection, frontmost: frontmost)
    }

    /// 結果を選んだ出し方で使う。画面に出すものを返す（置き換えた・コピーしたなら nil）
    private func deliver(_ text: String, to destination: AIOutput, selection: SelectionSource?, frontmost: RunningAppInfo?) async throws -> String? {
        switch destination {
        case .replaceSelection:
            // アクセシビリティが「選択なし」と答えていたなら、貼り付けると選択の置き換えではなくカーソルの位置への挿入になる。
            // クリップボードの中身を保てないときも貼り付けない。どちらも結果のパネルに出す（利用者がコピーできる）
            guard ReplacePlan.canPaste(over: selection) else {
                ActionLog.logger.notice("選択があるか確かめられないので、置き換えずに結果を表示します")
                return text
            }
            return try await replaceSelection(with: text, in: frontmost) ? nil : text
        case .copyToClipboard:
            PasteboardWriter.write(text, to: .general)
            return nil
        case .showResult:
            return text
        }
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
        let keyEquivalent = action.keyEquivalent
        try await Task.detached(priority: .userInitiated) {
            try MenuItemPresser.press(path: path, keyEquivalent: keyEquivalent, pid: pid, appName: name)
        }.value
    }

    // MARK: - AI

    private func runAI(_ ai: AIAction, frontmost: RunningAppInfo?) async throws -> String? {
        // 使えないなら、⌘C などを送る前に知らせる
        try OnDeviceAI.checkAvailability()
        let reading = await contextReader.read(.forAI, app: frontmost)
        guard let text = reading.info.selectedText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NonetError.actionFailed(SelectionMessage.noSelection(reading))
        }
        let result = try await OnDeviceAI.respond(instruction: ai.prompt, text: text)
        return try await deliver(result, to: ai.output, selection: reading.selectionSource, frontmost: frontmost)
    }

    /// クリップボード経由で ⌘V し、相手が読み終えてから元のクリップボードに戻す。
    /// クリップボードの中身を保てない（大きすぎる・読む許可が無いなど）ときは貼り付けずに false
    private func replaceSelection(with text: String, in app: RunningAppInfo?) async throws -> Bool {
        let pasteboard = NSPasteboard.general
        // AI の処理中や、クリップボードを写している間にほかのアプリへ移っていたら、そこへは貼らない
        func frontmostChanged() -> Bool {
            guard let app else { return false }
            return NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processID
        }
        do {
            if frontmostChanged() { throw FrontmostAppChanged() }
            let keySender = keySender
            let outcome = try await ClipboardPaste.paste(text, to: pasteboard) {
                if frontmostChanged() { throw FrontmostAppChanged() }
                try await keySender.send(.key("v", .command))
            }
            return outcome == .pasted
        } catch is FrontmostAppChanged {
            PasteboardWriter.write(text, to: pasteboard)
            throw NonetError.actionFailed(String(localized: "前面のアプリが変わったため、結果をクリップボードにコピーしました", bundle: .nonetActions))
        }
    }

    private struct FrontmostAppChanged: Error {}
}

enum SelectionMessage {
    /// 選択テキストを読めなかったときの説明。⌘C を送れなかった理由や、エディタの行のコピーを無視したことが分かれば、それを伝える
    static func noSelection(_ reading: ContextReading) -> String {
        switch reading.copyUnavailable {
        case .denied?:
            return String(
                localized: "Nonet がクリップボードを読むことが許可されていないため、選択テキストを読めませんでした。システム設定の「プライバシーとセキュリティ」で許可してください。",
                bundle: .nonetActions
            )
        case .some:
            return String(
                localized: "クリップボードの中身を保てないため、選択テキストを読めませんでした。選択したテキストを ⌘C でコピーしてから、もう一度実行してください。",
                bundle: .nonetActions
            )
        case nil:
            break
        }
        if reading.ignoredLineCopy {
            return String(localized: "テキストを選択してから実行してください。1行だけを使うときは、行末の改行を含めずに選択してください。", bundle: .nonetActions)
        }
        return String(localized: "テキストを選択してから実行してください", bundle: .nonetActions)
    }
}

/// スクリプトとショートカットの出力を、結果として使う形にする
enum CommandOutput {
    /// 末尾の改行を1つだけ除いた標準出力（"echo" の改行を貼り付けない）。空なら nil（貼り付けもコピーもしない）。
    /// 上限を超えて先頭が切れていたら、途中から始まる文字を貼り付けたりコピーしたりしないよう NonetError
    static func text(from output: ProcessOutput) throws -> String? {
        if output.stdoutTruncated {
            let limit = ScriptRunner.outputLimit / 1024
            throw NonetError.actionFailed(String(localized: "出力が大きすぎるため、使えませんでした（\(limit) KB まで）", bundle: .nonetActions))
        }
        var text = output.stdout
        // "\r\n" は Swift では1文字なので、最後の1文字が改行かで見る
        if let last = text.last, last.isNewline {
            text.removeLast()
        }
        return text.isEmpty ? nil : text
    }
}

enum ReplacePlan {
    /// 選択範囲を貼り付けで置き換えてよいか。⌘C で取れても、アクセシビリティが「選択なし」と答えていたなら置き換えない
    static func canPaste(over source: SelectionSource?) -> Bool {
        source != .copyAfterEmpty
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
