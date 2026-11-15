// 担当: platform-actions
import AppKit
import NonetCore

/// スクリプトアクション（/bin/zsh -l -c）。PATH は利用者の対話シェルのもの（UserShell）
enum ScriptRunner {
    static let shell = URL(fileURLWithPath: "/bin/zsh")
    static let defaultTimeout: TimeInterval = 60
    static let maximumTimeout: TimeInterval = 24 * 60 * 60
    static let outputLimit = 64 * 1024

    /// スクリプトの出力の始まりの印。ログインシェルの設定ファイル（~/.zprofile の ssh-agent など）が出す文字を、
    /// スクリプトの出力（結果のパネルに出す）に混ぜないよう、スクリプトの前に出し、これより後ろだけを出力とする
    static let outputMarker = "\u{1E}NONET-OUTPUT\u{1E}"

    /// ソースは引数の1つとして渡す。"--" で、"-" で始まるソースもオプションと間違えさせない。
    /// 先頭で outputMarker を出す。shellPath（~/.zshrc まで読んだ対話シェルの PATH）があれば、ログインシェルの設定ファイルを読んだ後に PATH をそれにする。
    /// 環境変数で渡すだけでは、/etc/zprofile の path_helper が順番を入れ替えて、ターミナルと別のコマンドが見つかることがある。
    /// どちらもソースと同じ行の先頭に置くので、エラーの行番号は変わらない
    static func arguments(source: String, shellPath: String? = nil) -> [String] {
        let start = "print -rn -- \(TerminalCommandFile.shellQuoted(outputMarker)); "
        guard let shellPath, !shellPath.isEmpty else { return ["-l", "-c", "--", start + source] }
        return ["-l", "-c", "--", "\(start)export PATH=\(TerminalCommandFile.shellQuoted(shellPath)); \(source)"]
    }

    /// 標準出力から、outputMarker より前（ログインシェルの設定ファイルが出したもの）を除く。
    /// 印が残っていれば、その後ろ（スクリプトの出力）は切れていない。印が無ければ（スクリプトの出力が長すぎて先頭が切れた）そのまま
    static func strippingStartupOutput(_ output: ProcessOutput) -> ProcessOutput {
        guard let marker = output.stdout.range(of: outputMarker) else { return output }
        var output = output
        output.stdout = String(output.stdout[marker.upperBound...])
        output.stdoutTruncated = false
        return output
    }

    static func effectiveTimeout(_ timeout: Double) -> TimeInterval {
        guard timeout.isFinite, timeout > 0 else { return defaultTimeout }
        return min(timeout, maximumTimeout)
    }

    /// Nonet の環境変数に文脈の変数を重ねる。前に残った NONET_* は消す。
    /// Finder から起動したアプリには LANG が無く、pbcopy などが UTF-8 を化けさせるので LC_CTYPE を補う。
    /// shellPath があれば PATH をそれにする（ログインシェルの設定ファイルも、そのコマンドを使える）
    static func environment(base: [String: String], context: [String: String], shellPath: String? = nil) -> [String: String] {
        var environment = base.filter { key, _ in !key.hasPrefix("NONET_") && key != "PROJECT_DIR" }
        environment.merge(context) { _, new in new }
        if let shellPath, !shellPath.isEmpty {
            environment["PATH"] = shellPath
        }
        if environment["LANG"] == nil, environment["LC_ALL"] == nil, environment["LC_CTYPE"] == nil {
            environment["LC_CTYPE"] = "UTF-8"
        }
        return environment
    }

    /// プロジェクトのフォルダがあればそこ、無ければホーム
    static func workingDirectory(projectDirectory: String?, home: URL, isDirectory: (String) -> Bool) -> URL {
        if let projectDirectory, !projectDirectory.isEmpty, isDirectory(projectDirectory) {
            return URL(fileURLWithPath: projectDirectory, isDirectory: true)
        }
        return home
    }

    static func isDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    static func validate(source: String) throws {
        if source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw NonetError.actionFailed(String(localized: "スクリプトが空です", bundle: .nonetActions))
        }
    }

    /// 裏で実行し、終わるまで待つ。失敗したら標準エラーの末尾を添えた NonetError。成功したら出力を返す
    @discardableResult
    static func runInBackground(
        source: String,
        environment: [String: String],
        workingDirectory: URL,
        timeout: TimeInterval,
        shellPath: String? = nil
    ) async throws -> ProcessOutput {
        try validate(source: source)
        var output: ProcessOutput
        do {
            output = try await ProcessRunner.run(ProcessRequest(
                executable: shell,
                arguments: arguments(source: source, shellPath: shellPath),
                environment: environment,
                currentDirectory: workingDirectory,
                timeout: timeout,
                outputLimit: outputLimit
            ))
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as NonetError {
            // 始める前に断った理由（NUL の入ったスクリプトなど）は、そのまま知らせる
            throw error
        } catch {
            ActionLog.logger.error("スクリプトを起動できませんでした: \(error.localizedDescription)")
            throw NonetError.actionFailed(String(localized: "スクリプトを実行できませんでした", bundle: .nonetActions))
        }
        output = strippingStartupOutput(output)
        if let failure = failure(for: output) { throw failure }
        return output
    }

    /// シェルが「コマンドが見つからない」ときの終了コード
    static let commandNotFoundStatus: Int32 = 127

    static func failure(for output: ProcessOutput) -> NonetError? {
        if output.timedOut { return .timedOut }
        if output.wasSignaled {
            let headline = String(localized: "スクリプトが中断されました（シグナル \(output.status)）", bundle: .nonetActions)
            return .actionFailed(ActionText.message(headline, detail: output.stderr))
        }
        if output.status == commandNotFoundStatus {
            // 知らせは4行までしか出ないので、確かめ方を標準エラーより先に置く
            let headline = String(localized: "スクリプトが失敗しました（終了コード \(output.status)）", bundle: .nonetActions)
            let hint = commandNotFoundHint(command: missingCommand(in: output.stderr))
            return .actionFailed(ActionText.message("\(headline)\n\(hint)", detail: output.stderr, lineCount: 2))
        }
        if output.status != 0 {
            let headline = String(localized: "スクリプトが失敗しました（終了コード \(output.status)）", bundle: .nonetActions)
            // エラーを標準出力に出すスクリプト（echo "…"; exit 1）もあるので、標準エラーが空なら標準出力を添える
            return .actionFailed(ActionText.message(headline, detail: output.stderr.isEmpty ? output.stdout : output.stderr))
        }
        return nil
    }

    /// 終了コード 127 のときの確かめ方。コマンドの名前が分かれば添える
    static func commandNotFoundHint(command: String?) -> String {
        if let command {
            return String(
                localized: "コマンドが見つかりません。インストールされているか、ターミナルで command -v \(command) を確かめてください。",
                bundle: .nonetActions
            )
        }
        return String(localized: "コマンドが見つかりません。インストールされているか、ターミナルで確かめてください。", bundle: .nonetActions)
    }

    /// 標準エラーの最後の「コマンドが見つからない」から、コマンドの名前を読む。
    /// zsh（"zsh:1: command not found: foo"）・bash と sh（"foo: command not found"）・env（"env: foo: No such file or directory"）
    static func missingCommand(in stderr: String) -> String? {
        let patterns = [
            #"command not found: (\S+)\s*$"#,
            #"(?:^|: )([^\s:]+): command not found\s*$"#,
            #"^env: ([^\s:]+): No such file or directory\s*$"#,
        ]
        let lines = stderr.split(whereSeparator: \.isNewline).map(String.init)
        for line in lines.reversed() {
            for pattern in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern),
                      let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                      let range = Range(match.range(at: 1), in: line)
                else { continue }
                let name = String(line[range])
                if !name.isEmpty { return name }
            }
        }
        return nil
    }
}

/// 書類の場所から決める、プロジェクトのフォルダと作業フォルダ
struct ScriptLocation: Equatable, Sendable {
    var projectDirectory: String?
    var workingDirectory: URL

    /// 調べる時間の上限。過ぎたら（眠ったネットワークの場所など）プロジェクトのフォルダは無しで、作業フォルダはホーム
    static let timeout: TimeInterval = 0.3
    /// ホームの外で、.git などを探して上にたどるフォルダの数の上限（書類のフォルダを含む）。
    /// ホームの中ではホームで止まるので上限は無い（Maven・Gradle・Android のように、ソースがルートから10段以上深いこともある）
    static let maxSearchLevels = 32
    /// これより浅いフォルダ（/ や /Volumes、/Users）では探さない
    static let minSearchDepth = 2

    /// メインスレッドの外で、短い制限時間で調べる
    static func find(documentPath: String?, home: URL, timeout: TimeInterval = timeout) async -> ScriptLocation {
        let fallback = ScriptLocation(projectDirectory: nil, workingDirectory: home)
        guard let documentPath, !documentPath.isEmpty else { return fallback }
        return await BlockingCall.run(timeout: timeout, fallback: fallback) {
            resolve(
                documentPath: documentPath,
                home: home,
                fileExists: { FileManager.default.fileExists(atPath: $0) },
                isLocalVolume: isLocalVolume,
                isDirectory: ScriptRunner.isDirectory
            )
        }
    }

    /// ネットワークの場所の書類では .git などを探さない（書類のフォルダをプロジェクトとする）。
    /// ホームより上と浅いフォルダは調べない。ホームの外では、書類から上へ maxLevels 個までしか調べない
    static func resolve(
        documentPath: String,
        home: URL,
        maxLevels: Int = maxSearchLevels,
        fileExists: (String) -> Bool,
        isLocalVolume: (String) -> Bool,
        isDirectory: (String) -> Bool
    ) -> ScriptLocation {
        let searches = isLocalVolume(documentPath)
        let limitsLevels = !isInside(documentPath, home: home)
        var directories: [String] = []
        let project = ScriptEnvironment.projectDirectory(forDocumentPath: documentPath, homeDirectory: home.path) { candidate in
            guard searches else { return false }
            let directory = (candidate as NSString).deletingLastPathComponent
            if directories.last != directory { directories.append(directory) }
            let depth = directory.split(separator: "/").count
            guard !limitsLevels || directories.count <= maxLevels, depth >= minSearchDepth else { return false }
            return fileExists(candidate)
        }
        let workingDirectory = ScriptRunner.workingDirectory(projectDirectory: project, home: home, isDirectory: isDirectory)
        return ScriptLocation(projectDirectory: project.isEmpty ? nil : project, workingDirectory: workingDirectory)
    }

    /// path がホームの中か（ホームそのものも含む）。ディスクは見ない
    static func isInside(_ path: String, home: URL) -> Bool {
        let path = URL(fileURLWithPath: path, isDirectory: false).standardizedFileURL.path
        let home = home.standardizedFileURL.path
        return path == home || path.hasPrefix(home.hasSuffix("/") ? home : home + "/")
    }

    /// 内蔵や外付けのディスクなら true。分からなければ探さない
    static func isLocalVolume(_ path: String) -> Bool {
        let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.volumeIsLocalKey])
        return values?.volumeIsLocal ?? false
    }
}

/// ターミナルで実行するための一時的な .command ファイル。
/// 利用者ごとの一時フォルダ（$TMPDIR）の中の、本人だけが入れるフォルダに、本人だけが読み書き・実行できるファイルとして書く。
/// 実行が始まると自分を消す。開かれずに残ったものは、次のターミナルでの実行・次の起動・一定時間の後に消す。
/// 開くアプリは設定で選ぶ（ターミナルか iTerm2。どちらも、開いた .command を新しいウィンドウでそのまま実行する）
enum TerminalCommandFile {
    static let terminalBundleID = TerminalApp.terminal.bundleID
    static let filePrefix = "nonet-"
    static let fileExtension = "command"
    /// 開かれずに残ったファイルを消すまでの時間。ターミナルのシェルの起動（.zshrc）が遅くても、これより早く消さない
    static let staleAge: TimeInterval = 5 * 60

    static var directory: URL {
        perUserTemporaryDirectory
            .appendingPathComponent("Nonet", isDirectory: true)
            .appendingPathComponent("Terminal", isDirectory: true)
    }

    /// 利用者ごとの一時フォルダ（/var/folders/…/T/、本人だけが入れる）。環境変数の TMPDIR が /tmp などに変えられていても、OS に聞いた場所を使う
    static var perUserTemporaryDirectory: URL {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        let length = confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, buffer.count)
        guard length > 0, length <= buffer.count else { return FileManager.default.temporaryDirectory }
        return URL(fileURLWithPath: String(cString: buffer), isDirectory: true)
    }

    /// シェルの単一引用符で囲む。中の ' は '\'' にする。NUL は環境変数にもシェルにも入らないので消す
    static func shellQuoted(_ text: String) -> String {
        let cleaned = text.replacingOccurrences(of: "\0", with: "")
        return "'" + cleaned.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func isValidVariableName(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first, first == "_" || (first.isASCII && first.properties.isAlphabetic) else {
            return false
        }
        return name.unicodeScalars.allSatisfy { $0 == "_" || ($0.isASCII && ($0.properties.isAlphabetic || ("0" ... "9").contains($0))) }
    }

    /// ~/.zshrc を読む行。.command はスクリプトとして（対話シェルではなく）動くので、nvm などで足す PATH・エイリアス・関数を読み込む。
    /// ZDOTDIR を変えている人は、そこにある .zshrc
    static let zshrcLine = #"[[ -r "${ZDOTDIR:-$HOME}/.zshrc" ]] && source "${ZDOTDIR:-$HOME}/.zshrc""#

    /// iTerm2 は、開いたファイルの実行が終わるとセッションを閉じる（既定のプロファイル）ので、出力が読めるよう、
    /// 終わった後に対話シェルを続ける行（ターミナルは終わってもウィンドウを残すので付けない）
    static let keepSessionLine = #"exec "${SHELL:-/bin/zsh}" -l"#

    /// 実行が始まったら自分を消し、~/.zshrc を読み、変数を export し、作業フォルダへ移ってからスクリプトを実行する。
    /// keepsSession なら、スクリプトが終わった後もウィンドウにシェルを残す（keepSessionLine）
    static func contents(source: String, variables: [String: String], workingDirectory: String, keepsSession: Bool = false) -> String {
        var lines = [
            "#!/bin/zsh -l",
            "# Nonet がターミナルで実行するために作った一時ファイル（実行が始まると消える）",
            "rm -f -- \"$0\"",
            // ~/.zshrc が cd や同じ名前の変数を使っても、後の export と cd が勝つ
            zshrcLine,
        ]
        for name in variables.keys.sorted() where isValidVariableName(name) {
            lines.append("export \(name)=\(shellQuoted(variables[name] ?? ""))")
        }
        lines.append("cd -- \(shellQuoted(workingDirectory)) || exit 1")
        lines.append(source)
        if keepsSession {
            // スクリプトの最後の行が \ で終わっていても、シェルを続ける行をスクリプトの続きとして読ませない
            lines.append("")
            lines.append(keepSessionLine)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// 本人だけが読み書き・実行できるファイルとして書く（ターミナルは実行できない .command を開かないので 0600 ではなく 0700）。
    /// フォルダが前からあっても本人だけのものにし、ファイルは新しく作る（既にあるファイルやリンクには書かない）
    static func write(_ contents: String, in directory: URL) throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let url = directory.appendingPathComponent("\(filePrefix)\(UUID().uuidString).\(fileExtension)", isDirectory: false)
        let descriptor = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o700)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: Data(contents.utf8))
            try handle.close()
        } catch {
            try? fileManager.removeItem(at: url)
            throw error
        }
        return url
    }

    /// 起動時に、前に残ったファイルを裏で消す
    static func removeStaleFilesInBackground() {
        let directory = directory
        DispatchQueue.global(qos: .utility).async {
            removeStaleFiles(in: directory, olderThan: staleAge)
        }
    }

    /// 開かれなかったなどで残った古いファイルを消す
    static func removeStaleFiles(in directory: URL, olderThan age: TimeInterval, now: Date = Date()) {
        let fileManager = FileManager.default
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        for url in urls where url.lastPathComponent.hasPrefix(filePrefix) && url.pathExtension == fileExtension {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, now.timeIntervalSince(modified) > age {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    /// 前に残った古いファイルを消してから、ターミナルに渡すファイルを書く
    static func prepare(source: String, variables: [String: String], workingDirectory: String, keepsSession: Bool = false) throws -> URL {
        let directory = directory
        removeStaleFiles(in: directory, olderThan: staleAge)
        return try write(
            contents(source: source, variables: variables, workingDirectory: workingDirectory, keepsSession: keepsSession),
            in: directory
        )
    }

    /// 開くアプリ。選んだアプリが無ければ（iTerm2 を消した など）ターミナル
    static func resolvedApp(_ app: TerminalApp, isInstalled: (String) -> Bool) -> TerminalApp {
        app == .terminal || isInstalled(app.bundleID) ? app : .terminal
    }

    /// 選んだアプリ（ターミナルか iTerm2）の新しいウィンドウで実行する
    @MainActor
    static func open(source: String, variables: [String: String], workingDirectory: String, app: TerminalApp = .terminal) async throws {
        try ScriptRunner.validate(source: source)
        let workspace = NSWorkspace.shared
        let app = resolvedApp(app) { workspace.urlForApplication(withBundleIdentifier: $0) != nil }
        let file: URL
        do {
            file = try prepare(source: source, variables: variables, workingDirectory: workingDirectory, keepsSession: app == .iTerm2)
        } catch {
            ActionLog.logger.error("一時ファイルを書けませんでした: \(error.localizedDescription)")
            throw NonetError.actionFailed(String(localized: "ターミナル用のファイルを作れませんでした", bundle: .nonetActions))
        }
        let terminal = workspace.urlForApplication(withBundleIdentifier: app.bundleID)
            ?? URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app", isDirectory: true)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            _ = try await workspace.open([file], withApplicationAt: terminal, configuration: configuration)
        } catch {
            try? FileManager.default.removeItem(at: file)
            ActionLog.logger.error("ターミナルを開けませんでした: \(error.localizedDescription)")
            throw NonetError.actionFailed(String(localized: "ターミナルを開けませんでした", bundle: .nonetActions))
        }
        // ターミナルが実行しないまま（ウィンドウを先に閉じたなど）でも、選択テキストなどを残し続けない
        removeLater(file, after: staleAge)
    }

    /// 一定時間の後に、まだ残っていれば消す
    static func removeLater(_ file: URL, after delay: TimeInterval) {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
