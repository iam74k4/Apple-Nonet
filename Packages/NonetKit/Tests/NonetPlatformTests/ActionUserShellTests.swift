import Foundation
import NonetCore
@testable import NonetPlatform
import Testing

/// 利用者のシェルの PATH と claude を、起動ごとに1回調べる。
/// 本物の /bin/zsh で動かすが、HOME と ZDOTDIR を一時フォルダにして、その中の .zshrc だけを読ませる
@Suite("利用者のシェル")
struct ActionUserShellTests {
    private func probe(zshrc: String, timeout: TimeInterval = 20) async throws -> (UserShellInfo?, ActionTemporaryDirectory) {
        let directory = try ActionTemporaryDirectory()
        try zshrc.write(to: directory.url.appendingPathComponent(".zshrc"), atomically: true, encoding: .utf8)
        let info = await UserShellProbe.run(environment: directory.isolatedEnvironment, home: directory.url, timeout: timeout)
        return (info, directory)
    }

    @Test("~/.zshrc で足した PATH と、関数やエイリアスの claude も見つける")
    func readsZshrc() async throws {
        let (info, _) = try await probe(zshrc: """
            path=(/nonet/test/bin $path)
            claude() { echo fake; }
            """)
        let found = try #require(info)
        #expect(found.path.hasPrefix("/nonet/test/bin:"))
        #expect(found.hasClaudeCode)

        let (alias, _) = try await probe(zshrc: "alias claude=/nonet/test/bin/claude")
        #expect(alias?.hasClaudeCode == true)
    }

    @Test("claude が無ければ見つからない")
    func noClaude() async throws {
        let (info, _) = try await probe(zshrc: "PATH=/usr/bin:/bin")
        #expect(info == UserShellInfo(path: "/usr/bin:/bin", hasClaudeCode: false))
    }

    @Test("~/.zshrc が何かを表示しても読み違えない")
    func ignoresZshrcOutput() async throws {
        let (info, _) = try await probe(zshrc: """
            echo "Welcome \(UserShellProbe.beginMarker)1:/wrong\(UserShellProbe.endMarker)"
            echo "to stderr" >&2
            PATH=/usr/bin:/bin
            """)
        #expect(info == UserShellInfo(path: "/usr/bin:/bin", hasClaudeCode: false))
    }

    @Test("止まる ~/.zshrc は時間切れで諦める（裏のスクリプトは今までどおりの PATH で動く）")
    func timesOut() async throws {
        var info: UserShellInfo?
        let elapsed = try await actionElapsedSeconds {
            (info, _) = try await probe(zshrc: "sleep 30", timeout: 0.5)
        }
        #expect(info == nil)
        #expect(elapsed < 5)
    }

    @Test("対話シェルとして ~/.zshrc を読む（ログインシェルでもある）")
    func arguments() {
        #expect(UserShellProbe.arguments() == ["-l", "-i", "-c", UserShellProbe.script])
        #expect(UserShellProbe.timeout == 3)
    }

    @Test("印の組を読む。最後の組を使い、印が足りない・中身がおかしいものは読まない")
    func parse() {
        let begin = UserShellProbe.beginMarker
        let end = UserShellProbe.endMarker
        #expect(UserShellProbe.parse("\(begin)1:/a:/b\(end)") == UserShellInfo(path: "/a:/b", hasClaudeCode: true))
        #expect(UserShellProbe.parse("noise \(begin)0:/x\(end) \(begin)1:/a\(end)") == UserShellInfo(path: "/a", hasClaudeCode: true))
        #expect(UserShellProbe.parse("") == nil)
        #expect(UserShellProbe.parse("\(begin)1:/a") == nil)
        #expect(UserShellProbe.parse("\(begin)2:/a\(end)") == nil)
        #expect(UserShellProbe.parse("\(begin)1:\(end)") == nil)
        #expect(UserShellProbe.parse("\(begin)/a\(end)") == nil)
    }

    @Test("何度聞いても1回だけ調べ、終わったら待たずに結果を返す")
    func probesOnce() async {
        let counter = ActionCallCounter()
        let shell = UserShell {
            counter.increment()
            return UserShellInfo(path: "/p", hasClaudeCode: true)
        }
        #expect(shell.finishedInfo == nil)
        shell.start()
        shell.start()
        let first = await shell.info()
        let second = await shell.info()
        #expect(first == UserShellInfo(path: "/p", hasClaudeCode: true))
        #expect(second == first)
        #expect(counter.count == 1)
        #expect(shell.finishedInfo == .some(first))
    }

    @Test("調べられなかったことも覚える")
    func remembersFailure() async {
        let shell = UserShell { nil }
        #expect(await shell.info() == nil)
        let finished = shell.finishedInfo
        #expect(finished != nil)
        #expect(finished == .some(nil))
    }
}

/// 呼ばれた回数（別のスレッドから数える）
final class ActionCallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }
}

@Suite("プリセットのための Mac の状態")
@MainActor
struct ActionPresetEnvironmentTests {
    @Test("claude はシェルを調べ終えて見つかったときだけ使える扱い")
    func capabilitiesFromShell() {
        #expect(SystemPresetEnvironment.capabilities(aiUsable: true, shell: nil) == PresetCapabilities(appleIntelligence: true, claudeCode: false))
        let found = UserShellInfo(path: "/p", hasClaudeCode: true)
        #expect(SystemPresetEnvironment.capabilities(aiUsable: false, shell: found) == PresetCapabilities(appleIntelligence: false, claudeCode: true))
        let missing = UserShellInfo(path: "/p", hasClaudeCode: false)
        #expect(SystemPresetEnvironment.capabilities(aiUsable: true, shell: missing).claudeCode == false)
    }

    @Test("resolvedCapabilities はシェルを調べ終えるのを待つ。capabilities は待たない")
    func resolvedWaitsForTheShell() async {
        let gate = ActionGate()
        let shell = UserShell {
            await gate.wait()
            return UserShellInfo(path: "/p", hasClaudeCode: true)
        }
        let environment = SystemPresetEnvironment(shell: shell)
        // まだ調べている間は、見つからない扱い
        #expect(environment.capabilities.claudeCode == false)
        #expect(environment.capabilities.appleIntelligence == OnDeviceAI.isUsableForPresets)
        await gate.open()
        let resolved = await environment.resolvedCapabilities()
        #expect(resolved.claudeCode)
        #expect(environment.capabilities.claudeCode)
    }

    @Test("AI はモデルの準備中なら置き、対応していない・オフなら置かない")
    func aiForPresets() {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            #expect(OnDeviceAI.isUsableForPresets(.available))
            #expect(OnDeviceAI.isUsableForPresets(.unavailable(.modelNotReady)))
            #expect(!OnDeviceAI.isUsableForPresets(.unavailable(.deviceNotEligible)))
            #expect(!OnDeviceAI.isUsableForPresets(.unavailable(.appleIntelligenceNotEnabled)))
        }
        #endif
    }
}

/// 開くまで待たせる
actor ActionGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        for waiter in waiters { waiter.resume() }
        waiters = []
    }
}
