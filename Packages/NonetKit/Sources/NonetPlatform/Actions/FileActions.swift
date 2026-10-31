// 担当: platform-actions
// Finder で選んでいるファイルを、開く・ゴミ箱に入れる・名前を変える・複製する・移す。
// Finder の選択を読むのも、動かすのも Finder に頼む（AppleScript）。そうすると、デスクトップ・書類・外付けのディスクなど
// アクセスに許可が要る場所のファイルも、Nonet が「Finder を操作する許可」だけで扱える（Nonet 自身はファイルの場所を調べない）。
// ゴミ箱に入れるのも Finder の「ゴミ箱に入れる」と同じなので、ゴミ箱から元の場所へ戻せる。完全な削除はしない。
// 名前の変更は、Finder が前面なので、Finder の名前の変更（Return）を始めるだけにする（名前の入力は Finder が受ける）
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
    /// 初めて使うときは、macOS の「Finder を操作しようとしています」の確認が出ている間も待つ（確認に答えるまでは、Finder に届かない）
    static let readTimeout: TimeInterval = 30

    /// 選んでいるファイルの URL を JSON の配列で返す。上限を超えたことが分かるよう、1つ多く読む
    static let readScript = """
    JSON.stringify(Application('\(bundleID)').selection().slice(0, \(limit + 1)).map(item => item.url()));
    """

    /// readScript の出力（file:// の URL の JSON の配列）をパスにする。1つでもファイルの URL でなければ（検索結果や AirDrop などの項目）、
    /// 一部だけを動かしてしまわないよう、全体を読めなかったことにする（nil）
    static func parse(_ output: String) -> [String]? {
        guard let data = output.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
              let urls = try? JSONDecoder().decode([String?].self, from: data) else { return nil }
        var paths: [String] = []
        for text in urls {
            guard let text, let url = URL(string: text), url.isFileURL, !url.path.isEmpty else { return nil }
            paths.append(url.path)
        }
        return paths
    }
}

// MARK: - 決まり（Finder に頼む前に確かめる）

enum FilePlan {
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

    /// 丸ごと動かしてはいけない場所（ホーム・ホームの標準のフォルダ・ディスクの一番上・システムのフォルダ・ほかの利用者のホーム・クラウドの置き場）
    static let protectedPaths: Set<String> = ["/Users", "/Applications", "/Library", "/System", "/Volumes", "/private", "/usr", "/bin", "/sbin", "/opt"]
    static let protectedHomeFolders: Set<String> = [
        "Desktop", "Documents", "Downloads", "Library", "Movies", "Music", "Pictures", "Public", "Applications", "Library/CloudStorage",
    ]

    static func isProtected(_ path: String, home: String) -> Bool {
        let components = path.split(separator: "/")
        if components.isEmpty || path == home || protectedPaths.contains(path) { return true }
        // /Volumes/<ディスク>・/Users/<利用者> そのもの
        if components.count == 2, components[0] == "Volumes" || components[0] == "Users" { return true }
        if path.hasPrefix(home + "/") {
            let relative = String(path.dropFirst(home.count + 1))
            if protectedHomeFolders.contains(relative) { return true }
            // ~/Library/CloudStorage/<サービス>（iCloud 以外のクラウドの置き場）そのもの
            if relative.hasPrefix("Library/CloudStorage/"), relative.split(separator: "/").count == 3 { return true }
        }
        return false
    }

    /// 移す先。"~" を直し、前後の空白と末尾の "/" を除いた絶対パス。絶対パスにならない・ゴミ箱の中なら nil
    /// （フォルダかどうかは Finder に頼む AppleScript が確かめる。Nonet は場所を調べない）
    static func destination(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var path = (trimmed as NSString).expandingTildeInPath
        guard path.hasPrefix("/") else { return nil }
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return isInTrash(path) ? nil : path
    }
}

// MARK: - 実行

@MainActor
final class FileActionRunner {
    /// 開く・ゴミ箱に入れる・名前の変更の制限時間
    static let actionTimeout: TimeInterval = 60
    /// 複製と移動は、大きなファイルやほかのディスクとの間で長く掛かる
    static let copyTimeout: TimeInterval = 600

    private let osascript: any OsascriptRunning
    private let keys: any KeySending
    private let home: String
    private let frontmostBundleID: () -> String?

    init(
        keys: any KeySending,
        osascript: any OsascriptRunning = Osascript(),
        home: String = FileManager.default.homeDirectoryForCurrentUser.path,
        frontmostBundleID: @escaping () -> String? = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
    ) {
        self.keys = keys
        self.osascript = osascript
        self.home = home
        self.frontmostBundleID = frontmostBundleID
    }

    func run(_ action: FileAction) async throws {
        // 9マスを開いたときの前面アプリではなく、今の前面アプリで確かめる（待っている間に変わることがある）。
        // 別のアプリが前面のとき、Finder の裏のウインドウで選んだままのファイルを動かさない
        try requireFinderInFront()
        var destination: String?
        if action.operation == .move {
            guard let path = FilePlan.destination(action.destination) else {
                throw NonetError.actionFailed(String(localized: "移動先のフォルダが見つかりません", bundle: .nonetActions))
            }
            destination = path
        }
        let paths = try await selection()
        try FilePlan.check(action.operation, paths: paths, home: home)
        // 選択を読んでいる間に、前面が変わっていないことも確かめる
        try requireFinderInFront()
        switch action.operation {
        case .open:
            try await perform(FileScripts.open, paths, timeout: Self.actionTimeout)
        case .trash:
            try await perform(FileScripts.trash, paths, timeout: Self.actionTimeout)
        case .duplicate:
            try await perform(FileScripts.duplicate, paths, timeout: Self.copyTimeout)
        case .move:
            try await perform(FileScripts.move, [destination ?? ""] + paths, timeout: Self.copyTimeout)
        case .rename:
            // Finder で選んだ1つのファイルの名前を、その場で書き換えられる状態にする（Return と同じ）
            try await keys.send(KeySequence([KeyChord(.special(.returnKey))]))
        }
    }

    private func requireFinderInFront() throws {
        guard frontmostBundleID() == FinderSelection.bundleID else {
            throw NonetError.actionFailed(String(localized: "Finder を前面にして、ファイルを選んでから使ってください", bundle: .nonetActions))
        }
    }

    private func selection() async throws -> [String] {
        let output = try await runScript(.javaScript, FinderSelection.readScript, [], FinderSelection.readTimeout)
        guard let paths = FinderSelection.parse(output.stdout) else {
            ActionLog.logger.error("Finder の選択を読めませんでした")
            throw NonetError.actionFailed(String(localized: "Finder で選んでいるファイルを読めませんでした", bundle: .nonetActions))
        }
        return paths
    }

    private func perform(_ script: String, _ arguments: [String], timeout: TimeInterval) async throws {
        _ = try await runScript(.appleScript, script, arguments, timeout)
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

/// Finder に頼む AppleScript。ファイルのパスは、文に埋め込まず argv で渡す（引用符などで壊れない）。
/// パスを alias にすると、シンボリックリンクはリンク先に置き換わり、Finder がリンク先を動かしてしまう。
/// だから、動かす操作では alias のパスが元のパスと同じか確かめ、違えば動かさない（error 1002）
enum FileScripts {
    /// Finder に頼むときの独自のエラー番号
    enum ErrorNumber {
        /// 移す先のフォルダが無い・フォルダではない
        static let destination = 1001
        /// シンボリックリンクなど、パスの指す先が違うもの
        static let link = 1002
        /// ゴミ箱の無いディスク（ネットワーク上の場所など）
        static let noTrash = 1004
    }

    private static let handlers = """
    on aliasList(paths, strict)
        set items_ to {}
        repeat with p in paths
            set thePath to contents of p
            set a to (POSIX file thePath) as alias
            if strict and not my samePath(POSIX path of a, thePath) then error "link" number \(ErrorNumber.link)
            set end of items_ to a
        end repeat
        return items_
    end aliasList

    on samePath(a, b)
        return (my normalizedPath(a)) is (my normalizedPath(b))
    end samePath

    on normalizedPath(t)
        set t to t as text
        repeat while t ends with "/" and (length of t) > 1
            set t to text 1 thru -2 of t
        end repeat
        if t starts with "/private/" then set t to text 9 thru -1 of t
        return t
    end normalizedPath

    """

    /// 開くのは、シンボリックリンクならリンク先を開く（ダブルクリックと同じ）
    static let open = handlers + """
    on run argv
        set targets to aliasList(argv, false)
        tell application "Finder" to open targets
    end run
    """

    static let trash = handlers + """
    on run argv
        set targets to aliasList(argv, true)
        repeat with a in targets
            tell application "Finder" to set isLocal to local volume of (disk of (item a))
            if not isLocal then error "no trash" number \(ErrorNumber.noTrash)
        end repeat
        tell application "Finder" to delete targets
    end run
    """

    static let duplicate = handlers + """
    on run argv
        set targets to aliasList(argv, true)
        tell application "Finder" to duplicate targets
    end run
    """

    /// argv の最初が移す先のフォルダ、残りが移すファイル。同じ名前があれば上書きせずに失敗する
    static let move = handlers + """
    on run argv
        try
            set destination to (POSIX file (item 1 of argv)) as alias
            tell application "Finder" to set destinationClass to (class of (item destination)) as text
        on error
            error "destination" number \(ErrorNumber.destination)
        end try
        if destinationClass is not in {"folder", "disk"} then error "destination" number \(ErrorNumber.destination)
        set targets to aliasList(rest of argv, true)
        tell application "Finder" to move targets to destination
    end run
    """
}

enum FinderScriptFailure {
    static func error(for output: ProcessOutput) -> NonetError? {
        if output.timedOut {
            // 時間内に返事が無かっただけで、Finder の作業は続いていることがある
            return .actionFailed(String(localized: "Finder が時間内に終わりませんでした。Finder の作業は続いていることがあるので、確かめてください", bundle: .nonetActions))
        }
        guard !output.succeeded else { return nil }
        switch errorNumber(in: output.stderr) {
        case -1743:
            // 「Nonet が Finder を操作しようとしています」を許可していない
            return .permissionDenied(ActionText.finderAutomation)
        case -600, -609:
            return .actionFailed(String(localized: "Finder が起動していません", bundle: .nonetActions))
        case -48, -15267:
            return .actionFailed(String(localized: "同じ名前のファイルがあります", bundle: .nonetActions))
        case FileScripts.ErrorNumber.destination:
            return .actionFailed(String(localized: "移動先のフォルダが見つかりません", bundle: .nonetActions))
        case FileScripts.ErrorNumber.link:
            return .actionFailed(String(localized: "シンボリックリンクは、ここでは動かせません（リンク先を動かしてしまうため）", bundle: .nonetActions))
        case FileScripts.ErrorNumber.noTrash:
            return .actionFailed(String(localized: "ゴミ箱の無い場所（ネットワーク上のファイルなど）は、ここでは削除しません", bundle: .nonetActions))
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
