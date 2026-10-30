// 担当: platform-actions
import Foundation
import NonetCore

/// 利用者のシェルで調べたこと
struct UserShellInfo: Equatable, Sendable {
    /// ~/.zshrc まで読んだ対話シェルの PATH（ターミナルで使っているのと同じもの）
    var path: String
    /// claude コマンド（Claude Code）が見つかる。エイリアスや関数でもよい
    var hasClaudeCode: Bool
}

/// 利用者のシェル（/bin/zsh -l -i）を1回だけ起動して、PATH と claude の有無を調べる。
/// nvm・pyenv・mise などは ~/.zshrc で PATH を足すので、ログインシェル（zsh -l）だけでは見つからない。
/// ~/.zshrc が何かを表示しても読み違えないよう、印で挟んで書かせる
enum UserShellProbe {
    /// 調べる時間の上限。遅い ~/.zshrc でも、裏のスクリプトや初回の設定をこれより長く待たせない
    static let timeout: TimeInterval = 3
    static let beginMarker = "__NONET_SHELL_BEGIN__"
    static let endMarker = "__NONET_SHELL_END__"

    /// command -v はエイリアスと関数も見つける（ターミナルで実行するときは ~/.zshrc を読むので使える）
    static var script: String {
        """
        command -v claude >/dev/null 2>&1 && __nonet_claude=1 || __nonet_claude=0
        print -rn -- "\(beginMarker)${__nonet_claude}:${PATH}\(endMarker)"
        """
    }

    static func arguments() -> [String] {
        ["-l", "-i", "-c", script]
    }

    /// 最後の印の組の中を読む。印が無い・PATH が空なら nil
    static func parse(_ stdout: String) -> UserShellInfo? {
        guard let begin = stdout.range(of: beginMarker, options: .backwards) else { return nil }
        let rest = stdout[begin.upperBound...]
        guard let end = rest.range(of: endMarker) else { return nil }
        let body = rest[..<end.lowerBound]
        guard let colon = body.firstIndex(of: ":") else { return nil }
        let flag = body[..<colon]
        let path = String(body[body.index(after: colon)...])
        guard flag == "0" || flag == "1", !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return UserShellInfo(path: path, hasClaudeCode: flag == "1")
    }

    /// 調べる。時間切れ・失敗なら nil（裏のスクリプトは今までどおりの PATH で動く）
    static func run(environment: [String: String], home: URL, timeout: TimeInterval = timeout) async -> UserShellInfo? {
        do {
            let output = try await ProcessRunner.run(ProcessRequest(
                executable: ScriptRunner.shell,
                arguments: arguments(),
                environment: environment,
                currentDirectory: home,
                timeout: timeout,
                outputLimit: 256 * 1024,
                // 止まった ~/.zshrc を長く待たない
                killGracePeriod: 0.5
            ))
            guard !output.timedOut, let info = parse(output.stdout) else {
                ActionLog.logger.notice("シェルの PATH を調べられませんでした（終了コード \(output.status)、時間切れ \(output.timedOut)）")
                return nil
            }
            return info
        } catch {
            ActionLog.logger.error("シェルを起動できませんでした: \(error.localizedDescription)")
            return nil
        }
    }
}

/// 起動ごとに1回だけ、利用者のシェルを調べる（メインスレッドの外で、長くても数秒）
final class UserShell: @unchecked Sendable {
    static let shared = UserShell {
        await UserShellProbe.run(
            environment: ScriptRunner.environment(base: ProcessInfo.processInfo.environment, context: [:]),
            home: FileManager.default.homeDirectoryForCurrentUser
        )
    }

    private let probe: @Sendable () async -> UserShellInfo?
    private let lock = NSLock()
    private var task: Task<UserShellInfo?, Never>?
    /// 調べ終えたら入る（調べられなかったときは .some(nil)）
    private var finished: UserShellInfo??

    init(probe: @escaping @Sendable () async -> UserShellInfo?) {
        self.probe = probe
    }

    /// 調べ始める。もう始めていれば何もしない
    func start() {
        _ = currentTask()
    }

    /// 調べた結果。まだなら終わるまで待つ。調べられなければ nil
    func info() async -> UserShellInfo? {
        await currentTask().value
    }

    /// 調べ終えていれば、その結果（調べられなかったときは .some(nil)）。まだなら nil
    var finishedInfo: UserShellInfo?? {
        lock.lock()
        defer { lock.unlock() }
        return finished
    }

    private func currentTask() -> Task<UserShellInfo?, Never> {
        lock.lock()
        defer { lock.unlock() }
        if let task { return task }
        let probe = probe
        let task = Task.detached(priority: .utility) { [weak self] () -> UserShellInfo? in
            let info = await probe()
            self?.finish(info)
            return info
        }
        self.task = task
        return task
    }

    private func finish(_ info: UserShellInfo?) {
        lock.lock()
        finished = .some(info)
        lock.unlock()
    }
}
