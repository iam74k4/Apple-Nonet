// 担当: platform-actions
// クラス名・public init・protocol への準拠は契約（NonetServices.live() が使う）
import AppKit
import NonetCore

/// Action を実行する（キー送出・アプリ起動・URL・スクリプト・ショートカット・メニュー・AI・ファイル）
@MainActor
public final class SystemActionPerformer: ActionPerforming {
    private let keySender: KeySender
    private let contextReader: ContextReader
    private let fileRunner: FileActionRunner
    private let windowPlacer: any WindowPlacing

    /// windowPlacer は NonetServices.windowPlacer と同じもの（置く枠のプレビューと実行で、同じウインドウを見る）
    public init(windowPlacer: any WindowPlacing = AXWindowPlacer()) {
        self.windowPlacer = windowPlacer
        keySender = KeySender()
        fileRunner = FileActionRunner(keys: keySender)
        contextReader = ContextReader(keySender: keySender)
        // 前に起動していたときに開かれずに残ったターミナル用のファイル（選択テキストなどが入っている）を消す
        TerminalCommandFile.removeStaleFilesInBackground()
        // 裏のスクリプトに渡す PATH を、最初のスクリプトより前に調べ始めておく（起動ごとに1回）
        UserShell.shared.start()
    }

    public func perform(_ action: Action, context: ActionContext) async throws {
        if let text = try await performReturningOutput(action, context: context) {
            // 「画面に表示」を HUD に出す口がまだ無いので、クリップボードに入れておく
            await PasteboardWriter.writeAfterOtherOperations(text, to: .general)
        }
    }

    /// perform と同じだが、結果の出し方が「画面に表示」の AI と、裏のスクリプト・ショートカットの出力を返す（ほかは nil）。
    /// 呼び出し側が結果を表示できるときはこちらを使う
    public func performReturningOutput(_ action: Action, context: ActionContext) async throws -> String? {
        do {
            return try await run(
                action,
                frontmost: context.frontmostApp ?? Self.currentFrontmostApp(),
                didReadContext: context.didReadContext ?? {},
                terminalApp: context.terminalApp
            )
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

    /// didReadContext: 長く掛かるアクションが前面アプリの文脈を読み終えたら呼ぶ（後の実行に順番を譲る）。
    /// terminalApp: 「ターミナルで実行」のスクリプトを開くアプリ
    private func run(_ action: Action, frontmost: RunningAppInfo?, didReadContext: @MainActor () -> Void, terminalApp: TerminalApp) async throws -> String? {
        switch action {
        case .keystroke(let keys):
            try KeyTarget.check(expected: frontmost, frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier)
            if try await pressMenuItemForUntypableShortcut(keys, frontmost: frontmost) { return nil }
            try await keySender.send(keys)
        case .launchApp(let launch):
            try await AppLauncher.launch(launch)
        case .openURL(let url):
            try await openURL(url, frontmost: frontmost, didReadContext: didReadContext)
        case .script(let script):
            return try await runScript(script, frontmost: frontmost, didReadContext: didReadContext, terminalApp: terminalApp)
        case .shortcut(let shortcut):
            return try await runShortcut(shortcut, frontmost: frontmost, didReadContext: didReadContext)
        case .menuItem(let menuItem):
            try await pressMenuItem(menuItem, frontmost: frontmost)
        case .ai(let ai):
            return try await runAI(ai, frontmost: frontmost, didReadContext: didReadContext)
        case .placeWindow(let place):
            try await windowPlacer.place(place.region, app: frontmost)
        case .file(let file):
            try await fileRunner.run(file, didReadSelection: didReadContext)
        case .screenshots:
            // トレイは画面（HUDPresenting.showScreenshotTray）が出す。NonetController が performer に渡す前に受け持つ
            break
        case .media(let media):
            try MediaKeySender.send(media.key)
        case .pasteText(let paste):
            try await pasteText(paste.expanded(), frontmost: frontmost)
        }
        return nil
    }

    private static func currentFrontmostApp() -> RunningAppInfo? {
        guard let app = NSWorkspace.shared.frontmostApplication, let bundleID = app.bundleIdentifier else { return nil }
        return RunningAppInfo(app: AppReference(bundleID: bundleID, name: app.localizedName ?? bundleID), processID: app.processIdentifier)
    }

    // MARK: - スクリプト

    private func runScript(
        _ script: ScriptAction,
        frontmost: RunningAppInfo?,
        didReadContext: @MainActor () -> Void,
        terminalApp: TerminalApp
    ) async throws -> String? {
        try ScriptRunner.validate(source: script.source)
        let reading = await contextReader.read(.forScript(source: script.source), app: frontmost)
        didReadContext()
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
            // 出力があれば結果のパネルに出す（空なら何も出さない）
            return CommandOutput.text(from: output)
        case .terminal:
            // 出力はターミナル（設定で選んだアプリ）のウインドウに出る
            try await TerminalCommandFile.open(source: script.source, variables: variables, workingDirectory: workingDirectory.path, app: terminalApp)
            return nil
        }
    }

    // MARK: - ショートカット

    private func runShortcut(_ shortcut: ShortcutAction, frontmost: RunningAppInfo?, didReadContext: @MainActor () -> Void) async throws -> String? {
        var reading: ContextReading?
        if shortcut.passSelectedText {
            reading = await contextReader.read(.forShortcut(shortcut), app: frontmost)
        }
        didReadContext()
        let output = try await ShortcutRunner.run(name: shortcut.name, input: reading?.info.selectedText)
        // テキストを返したら結果のパネルに出す（何も返さない・テキストでなければ何も出さない）
        return CommandOutput.text(from: output)
    }

    // MARK: - AI の結果の出し方

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
            await PasteboardWriter.writeAfterOtherOperations(text, to: .general)
            return nil
        case .showResult:
            return text
        }
    }

    // MARK: - メニュー項目

    /// 今のキー配列で打てない1打のショートカット（ドイツ語・フランス語の配列の ⌘[ など）は、前面のアプリのメニューに
    /// 同じショートカットの項目があれば、それを押す（使えない項目なら「今は使えません」と知らせる）。押したら true。
    /// 打てる・項目が無い・許可が無ければ false（キーを送る。打てなければ、これまでどおり「今のキー配列では入力できません」になる）
    private func pressMenuItemForUntypableShortcut(_ keys: KeySequence, frontmost: RunningAppInfo?) async throws -> Bool {
        guard keys.chords.count == 1, let frontmost, AXIsProcessTrusted(),
              (try? keySender.strokes(for: keys, keyboardType: KeyboardLayoutResolver.currentKeyboardType())) == nil else { return false }
        let pid = frontmost.processID
        let path = await Task.detached(priority: .userInitiated) { () -> [String]? in
            guard let nodes = try? MenuTreeBuilder.build(AXMenuTree(pid: pid)) else { return nil }
            return MenuShortcutSearch.path(for: keys, in: nodes)
        }.value
        guard let path else { return false }
        ActionLog.logger.notice("今のキー配列で打てないショートカットなので、同じショートカットのメニュー項目を押します")
        let name = frontmost.app.name
        try await Task.detached(priority: .userInitiated) {
            try MenuItemPresser.press(path: path, keyEquivalent: keys, pid: pid, appName: name)
        }.value
        return true
    }

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
        // 保存したショートカットは、アプリのメニューにあるその項目のショートカットと同じときだけ送る。
        // 読み込んだファイルのマスが、項目とは別のキー（⌥⇧⌘⌫ など）を送れないように
        var shortcutInMenu: KeySequence?
        if isFrontmost, let keys = action.keyEquivalent, !keys.chords.isEmpty, AXIsProcessTrusted() {
            let pid = target.processIdentifier
            let path = action.path
            shortcutInMenu = await Task.detached(priority: .userInitiated) {
                MenuItemPresser.shortcut(path: path, pid: pid)
            }.value
        }
        // メニューを読む間（最長 5 秒）に前面が変わっていたら、キーは送らずにメニューを押す（メニューはそのアプリに押せる）
        let isStillFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier
        if isStillFrontmost,
           MenuActionPlan.decide(isTargetFrontmost: isFrontmost, keyEquivalent: action.keyEquivalent, shortcutInMenu: shortcutInMenu) == .sendKeys,
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

    private func runAI(_ ai: AIAction, frontmost: RunningAppInfo?, didReadContext: @MainActor () -> Void) async throws -> String? {
        // 使えないなら、⌘C などを送る前に知らせる
        try OnDeviceAI.checkAvailability()
        let reading = await contextReader.read(.forAI, app: frontmost)
        didReadContext()
        guard let text = reading.info.selectedText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NonetError.actionFailed(SelectionMessage.noSelection(reading))
        }
        let result = try await OnDeviceAI.respond(instruction: ai.prompt, text: text)
        // メニューの「止める」で止めた後に返ってきた結果は、貼り付けもコピーもしない
        try Task.checkCancellation()
        return try await deliver(result, to: ai.output, selection: reading.selectionSource, frontmost: frontmost)
    }

    /// URL を開く。{selection} があれば、前面のアプリの選択（読めなければ ⌘C で取る）に置き換える。選択が無ければ開かずに知らせる
    private func openURL(_ url: URLAction, frontmost: RunningAppInfo?, didReadContext: @MainActor () -> Void) async throws {
        guard url.usesSelection else {
            try await URLNormalizer.open(url.url)
            return
        }
        let reading = await contextReader.read(.forAI, app: frontmost)
        didReadContext()
        guard let text = reading.info.selectedText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NonetError.actionFailed(SelectionMessage.noSelection(reading))
        }
        try await URLNormalizer.open(url.url(withSelection: text))
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
            await PasteboardWriter.writeAfterOtherOperations(text, to: pasteboard)
            throw NonetError.actionFailed(String(localized: "前面のアプリが変わったため、結果をクリップボードにコピーしました", bundle: .nonetActions))
        }
    }

    private struct FrontmostAppChanged: Error {}

    /// 「テキストを貼る」。⌘V で貼り、元のクリップボードに戻す。クリップボードの中身を保てないときは貼らずにコピーして知らせる
    private func pasteText(_ text: String, frontmost: RunningAppInfo?) async throws {
        try KeyTarget.check(expected: frontmost, frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier)
        guard try await replaceSelection(with: text, in: frontmost) else {
            await PasteboardWriter.writeAfterOtherOperations(text, to: .general)
            throw NonetError.actionFailed(String(localized: "今のクリップボードを保てないため、貼り付けずにコピーしました。⌘V で貼り付けてください", bundle: .nonetActions))
        }
    }
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

/// スクリプトとショートカットの出力を、結果のパネルに出す形にする（出すだけで、貼り付けもコピーもしない）
enum CommandOutput {
    /// 末尾の改行を1つだけ除いた標準出力。空白と改行だけ・テキストでない（画像などのバイト列）なら nil（パネルを出さない）。
    /// リッチテキスト（ショートカットのテキストが RTF で届く）は文字だけにする。
    /// 上限を超えて先頭が切れていたら、終わりの部分に、そうと分かる一行を添える（スクリプトは成功しているので、失敗にはしない）
    static func text(from output: ProcessOutput) -> String? {
        var text = output.stdout
        // "\r\n" は Swift では1文字なので、最後の1文字が改行かで見る
        if let last = text.last, last.isNewline {
            text.removeLast()
        }
        if text.contains("\u{0}") || text.contains("\u{FFFD}") { return nil }
        if text.hasPrefix("{\\rtf"), let plain = plainText(fromRTF: text) {
            text = plain
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard output.stdoutTruncated else { return text }
        let limit = ScriptRunner.outputLimit / 1024
        return String(localized: "（出力が長いため、終わりの \(limit) KB だけを表示しています）", bundle: .nonetActions) + "\n" + text
    }

    private static func plainText(fromRTF rtf: String) -> String? {
        guard let data = rtf.data(using: .utf8),
              let attributed = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
        else { return nil }
        return attributed.string
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

    /// 対象アプリが前面にあり、保存したショートカットが、アプリのメニューから読んだその項目のショートカット（shortcutInMenu）と
    /// 同じならキーを送る（速い）。ほかはメニューを押す（項目が無い・使えない・ショートカットが違う・読めない）
    static func decide(isTargetFrontmost: Bool, keyEquivalent: KeySequence?, shortcutInMenu: KeySequence?) -> MenuActionPlan {
        guard isTargetFrontmost, let keyEquivalent, !keyEquivalent.chords.isEmpty, keyEquivalent == shortcutInMenu else { return .pressMenu }
        return .sendKeys
    }
}
