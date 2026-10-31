// 担当: platform-actions
// Finder で選んでいるファイルを、開く・ゴミ箱に入れる・名前を変える・複製する・移す。
// Finder の選択を読むのも、動かすのも Finder に頼む（AppleScript）。そうすると、デスクトップ・書類・外付けのディスクなど
// アクセスに許可が要る場所のファイルも、Nonet が「Finder を操作する許可」だけで扱える。ゴミ箱に入れるのも Finder の
// 「ゴミ箱に入れる」と同じなので、ゴミ箱から元の場所へ戻せる。完全な削除はしない
import AppKit
import NonetCore

// MARK: - osascript

/// osascript を動かす（テストでは偽物にする）
protocol OsascriptRunning: Sendable {
    /// source を動かす。arguments は AppleScript の run ハンドラの argv（JavaScript なら run の引数）
    func run(_ language: OsascriptLanguage, source: String, arguments: [String], timeout: TimeInterval) async throws -> ProcessOutput
}

enum OsascriptLanguage: Sendable {
    case appleScript
    case javaScript
}

struct Osascript: OsascriptRunning {
    func run(_ language: OsascriptLanguage, source: String, arguments: [String], timeout: TimeInterval) async throws -> ProcessOutput {
        var options: [String] = []
        if language == .javaScript { options += ["-l", "JavaScript"] }
        // "--" の後ろは、"-" で始まる名前もオプションと間違えずに引数として渡る
        let arguments = options + ["-e", source] + (arguments.isEmpty ? [] : ["--"] + arguments)
        return try await ProcessRunner.run(ProcessRequest(
            executable: URL(fileURLWithPath: "/usr/bin/osascript"),
            arguments: arguments,
            environment: nil,
            currentDirectory: nil,
            timeout: timeout,
            outputLimit: 256 * 1024
        ))
    }
}

// MARK: - Finder の選択

enum FinderSelection {
    static let bundleID = "com.apple.finder"
    /// 一度に扱うファイルの数の上限。デスクトップを全部選んだまま、ゴミ箱に入れてしまわないように
    static let limit = 500
    /// 開くファイルの数の上限（アプリやウインドウが何百も開かないように）
    static let openLimit = 20
    static let readTimeout: TimeInterval = 5

    /// 選んでいるファイルの URL を JSON の配列で返す。上限を超えたことが分かるよう、1つ多く読む
    static let readScript = """
    JSON.stringify(Application('\(bundleID)').selection().slice(0, \(limit + 1)).map(item => item.url()));
    """

    /// readScript の出力（file:// の URL の JSON の配列）をパスにする。ファイルの URL でないものは捨てる
    static func parse(_ output: String) -> [String]? {
        guard let data = output.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
              let urls = try? JSONDecoder().decode([String?].self, from: data) else { return nil }
        return urls.compactMap { text in
            guard let text, let url = URL(string: text), url.isFileURL else { return nil }
            let path = url.path
            return path.isEmpty ? nil : path
        }
    }
}

// MARK: - 決まり（Finder に頼む前に確かめる）

enum FilePlan {
    /// 名前に使えない文字（/ は区切り、: は Finder が使えなくしている）
    static let forbiddenNameCharacters: Set<Character> = ["/", ":"]

    /// 選んでいるファイルに、この操作をしてよいか。だめならその理由
    static func check(_ operation: FileOperation, paths: [String], home: String) throws {
        guard !paths.isEmpty else {
            throw NonetError.actionFailed(String(localized: "Finder でファイルを選んでから使ってください", bundle: .nonetActions))
        }
        guard paths.count <= FinderSelection.limit else {
            throw NonetError.actionFailed(String(localized: "選んでいるファイルが多すぎます（\(FinderSelection.limit)個まで）", bundle: .nonetActions))
        }
        switch operation {
        case .open:
            guard paths.count <= FinderSelection.openLimit else {
                throw NonetError.actionFailed(String(localized: "一度に開けるのは\(FinderSelection.openLimit)個までです", bundle: .nonetActions))
            }
        case .rename:
            guard paths.count == 1 else {
                throw NonetError.actionFailed(String(localized: "名前を変えるときは、ファイルを1つだけ選んでください", bundle: .nonetActions))
            }
        case .trash:
            // ゴミ箱の中のファイルに Finder の delete を使うと、元に戻せなくなることがある。ここでは完全には削除しない
            if paths.contains(where: isInTrash) {
                throw NonetError.actionFailed(String(localized: "ゴミ箱の中のファイルは、ここでは削除しません", bundle: .nonetActions))
            }
        case .duplicate, .move:
            break
        }
        if operation.changesFiles, paths.contains(where: { isProtected($0, home: home) }) {
            throw NonetError.actionFailed(String(localized: "このフォルダは、ここでは動かせません", bundle: .nonetActions))
        }
    }

    static func isInTrash(_ path: String) -> Bool {
        path.split(separator: "/").contains { $0 == ".Trash" || $0 == ".Trashes" }
    }

    /// 丸ごと動かしてはいけない場所（ホーム・ディスクの一番上・システムのフォルダ）
    static let protectedPaths: Set<String> = ["/Users", "/Applications", "/Library", "/System", "/Volumes", "/private", "/usr", "/bin", "/sbin", "/opt"]

    static func isProtected(_ path: String, home: String) -> Bool {
        let components = path.split(separator: "/")
        if components.isEmpty || path == home || protectedPaths.contains(path) { return true }
        // /Volumes/<ディスク> そのもの
        return components.count == 2 && components[0] == "Volumes"
    }

    /// 移す先。"~" を直し、存在するフォルダでなければ nil
    static func destination(_ text: String, fileExists: (String) -> Bool = directoryExists) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var path = (trimmed as NSString).expandingTildeInPath
        guard path.hasPrefix("/") else { return nil }
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return fileExists(path) ? path : nil
    }

    static func directoryExists(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    /// 入力された新しい名前を確かめて、使える名前を返す（前後の空白は除く）。使えなければ理由
    static func validatedName(_ input: String) -> Result<String, NonetError> {
        let name = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name == "." || name == ".." {
            return .failure(.actionFailed(String(localized: "名前を入力してください", bundle: .nonetActions)))
        }
        if name.contains(where: { forbiddenNameCharacters.contains($0) || $0.isNewline }) {
            return .failure(.actionFailed(String(localized: "名前に「/」「:」と改行は使えません", bundle: .nonetActions)))
        }
        if name.utf8.count > 255 {
            return .failure(.actionFailed(String(localized: "名前が長すぎます", bundle: .nonetActions)))
        }
        return .success(name)
    }
}

// MARK: - 名前を入力するダイアログ

@MainActor
protocol RenamePrompting {
    /// 新しい名前を尋ねる。やめたら nil
    func requestName(currentName: String) async -> String?
}

@MainActor
struct AlertRenamePrompt: RenamePrompting {
    func requestName(currentName: String) async -> String? {
        let previous = NSWorkspace.shared.frontmostApplication
        let alert = NSAlert()
        alert.messageText = String(localized: "名前を変更", bundle: .nonetActions)
        alert.informativeText = String(localized: "「\(currentName)」の新しい名前を入力してください", bundle: .nonetActions)
        alert.addButton(withTitle: String(localized: "変更", bundle: .nonetActions))
        alert.addButton(withTitle: String(localized: "キャンセル", bundle: .nonetActions))
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.stringValue = currentName
        field.setAccessibilityLabel(String(localized: "新しい名前", bundle: .nonetActions))
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        NSApplication.shared.activate()
        // 拡張子の前までを選んでおく（Finder の名前の変更と同じ）
        let baseLength = (currentName as NSString).deletingPathExtension.utf16.count
        DispatchQueue.main.async {
            field.currentEditor()?.selectedRange = NSRange(location: 0, length: baseLength)
        }
        let response = alert.runModal()
        // 入力のあと、Finder へ戻す（Nonet に残ったままだと、続けてキーを打てない）
        if let previous, !previous.isTerminated, previous.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previous.activate()
        }
        return response == .alertFirstButtonReturn ? field.stringValue : nil
    }
}

// MARK: - 実行

@MainActor
final class FileActionRunner {
    static let actionTimeout: TimeInterval = 60

    private let osascript: any OsascriptRunning
    private let prompt: any RenamePrompting
    private let home: String
    private let directoryExists: (String) -> Bool

    init(
        osascript: any OsascriptRunning = Osascript(),
        prompt: (any RenamePrompting)? = nil,
        home: String = FileManager.default.homeDirectoryForCurrentUser.path,
        directoryExists: @escaping (String) -> Bool = FilePlan.directoryExists
    ) {
        self.osascript = osascript
        self.prompt = prompt ?? AlertRenamePrompt()
        self.home = home
        self.directoryExists = directoryExists
    }

    func run(_ action: FileAction, frontmost: RunningAppInfo?) async throws {
        // 別のアプリが前面のとき、Finder の裏のウインドウで選んだままのファイルを動かさない
        guard frontmost?.app.bundleID == FinderSelection.bundleID else {
            throw NonetError.actionFailed(String(localized: "Finder を前面にして、ファイルを選んでから使ってください", bundle: .nonetActions))
        }
        // 移す先は、選択を読む前に確かめる
        var destination: String?
        if action.operation == .move {
            guard let path = FilePlan.destination(action.destination, fileExists: directoryExists) else {
                throw NonetError.actionFailed(String(localized: "移動先のフォルダが見つかりません", bundle: .nonetActions))
            }
            destination = path
        }
        let paths = try await selection()
        try FilePlan.check(action.operation, paths: paths, home: home)
        switch action.operation {
        case .open:
            try await perform(FileScripts.open, paths)
        case .trash:
            try await perform(FileScripts.trash, paths)
        case .duplicate:
            try await perform(FileScripts.duplicate, paths)
        case .move:
            try await perform(FileScripts.move, [destination ?? ""] + paths)
        case .rename:
            try await rename(paths[0])
        }
    }

    private func rename(_ path: String) async throws {
        let currentName = (path as NSString).lastPathComponent
        guard let input = await prompt.requestName(currentName: currentName) else { return }
        let name = try FilePlan.validatedName(input).get()
        guard name != currentName else { return }
        try await perform(FileScripts.rename, [path, name])
    }

    private func selection() async throws -> [String] {
        let output = try await runScript(.javaScript, FinderSelection.readScript, [], FinderSelection.readTimeout)
        guard let paths = FinderSelection.parse(output.stdout) else {
            ActionLog.logger.error("Finder の選択を読めませんでした")
            throw NonetError.actionFailed(String(localized: "Finder で選んでいるファイルを読めませんでした", bundle: .nonetActions))
        }
        return paths
    }

    private func perform(_ script: String, _ arguments: [String]) async throws {
        _ = try await runScript(.appleScript, script, arguments, Self.actionTimeout)
    }

    /// 動かして、失敗していれば NonetError にする
    private func runScript(_ language: OsascriptLanguage, _ source: String, _ arguments: [String], _ timeout: TimeInterval) async throws -> ProcessOutput {
        let output: ProcessOutput
        do {
            output = try await osascript.run(language, source: source, arguments: arguments, timeout: timeout)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            ActionLog.logger.error("osascript を起動できませんでした: \(error.localizedDescription)")
            throw NonetError.actionFailed(String(localized: "Finder を操作できませんでした", bundle: .nonetActions))
        }
        if let failure = FinderScriptFailure.error(for: output) {
            ActionLog.logger.notice("Finder への依頼が失敗しました（終了コード \(output.status)）")
            throw failure
        }
        return output
    }
}

/// Finder に頼む AppleScript。ファイルのパスや名前は、文に埋め込まず argv で渡す（引用符などで壊れない）
enum FileScripts {
    private static let aliasList = """
    on aliasList(paths)
        set items_ to {}
        repeat with p in paths
            set end of items_ to (POSIX file (contents of p)) as alias
        end repeat
        return items_
    end aliasList

    """

    static let open = aliasList + """
    on run argv
        set targets to aliasList(argv)
        tell application "Finder" to open targets
    end run
    """

    static let trash = aliasList + """
    on run argv
        set targets to aliasList(argv)
        tell application "Finder" to delete targets
    end run
    """

    static let duplicate = aliasList + """
    on run argv
        set targets to aliasList(argv)
        tell application "Finder" to duplicate targets
    end run
    """

    /// argv の最初が移す先のフォルダ、残りが移すファイル。同じ名前があれば上書きせずに失敗する
    static let move = aliasList + """
    on run argv
        set destination to (POSIX file (item 1 of argv)) as alias
        set targets to aliasList(rest of argv)
        tell application "Finder" to move targets to destination
    end run
    """

    /// argv は、名前を変えるファイルと新しい名前。Finder の用語（target など）と同じ名前の変数は使えない
    static let rename = """
    on run argv
        set theFile to (POSIX file (item 1 of argv)) as alias
        set newName to item 2 of argv
        tell application "Finder" to set name of theFile to newName
    end run
    """
}

enum FinderScriptFailure {
    static func error(for output: ProcessOutput) -> NonetError? {
        if output.timedOut { return .timedOut }
        guard !output.succeeded else { return nil }
        switch errorNumber(in: output.stderr) {
        case -1743:
            // 「Nonet が Finder を操作しようとしています」を許可していない
            return .permissionDenied(ActionText.finderAutomation)
        case -600, -609:
            return .actionFailed(String(localized: "Finder が起動していません", bundle: .nonetActions))
        case -48, -15267:
            return .actionFailed(String(localized: "同じ名前のファイルがあります", bundle: .nonetActions))
        case -1728, -1700, -43:
            return .actionFailed(String(localized: "ファイルが見つかりません。選び直してください", bundle: .nonetActions))
        default:
            let headline = String(localized: "ファイルの操作に失敗しました", bundle: .nonetActions)
            return .actionFailed(ActionText.message(headline, detail: output.stderr))
        }
    }

    /// osascript のエラーの終わりにある (-1743) のような番号
    static func errorNumber(in stderr: String) -> Int? {
        guard let line = stderr.split(whereSeparator: \.isNewline).last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return nil }
        let text = line.trimmingCharacters(in: .whitespaces)
        guard text.hasSuffix(")"), let open = text.lastIndex(of: "(") else { return nil }
        return Int(text[text.index(after: open)..<text.index(before: text.endIndex)])
    }
}
