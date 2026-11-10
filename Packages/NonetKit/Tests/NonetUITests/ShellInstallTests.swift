// 担当: ui-shell
import Foundation
@testable import NonetUI
import Testing

/// 一時的な名前（.Nonet-…）から入れ替えるときだけ失敗する FileManager
private final class ShellFailingFileManager: FileManager {
    struct Failure: Error {}

    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        if srcURL.lastPathComponent.hasPrefix(".") {
            throw Failure()
        }
        try super.moveItem(at: srcURL, to: dstURL)
    }
}

@Suite("2つ目の起動と、アプリケーションフォルダへの移動")
@MainActor
struct ShellInstallTests {
    nonisolated static let own: Int32 = 500
    nonisolated static let installed = URL(fileURLWithPath: "/Applications/Nonet.app")
    nonisolated static let diskImage = URL(fileURLWithPath: "/Volumes/Nonet/Nonet.app")

    /// 動いている（起動し終えた）もの
    nonisolated static func instance(
        _ pid: Int32,
        _ url: URL? = installed,
        terminated: Bool = false,
        finished: Bool = true,
        quitting: Bool = false,
        launched: Date? = nil,
        location: ShellInstallLocation = .installed,
        version: String? = nil
    ) -> ShellRunningInstance {
        ShellRunningInstance(
            processID: pid,
            bundleURL: url,
            isTerminated: terminated,
            isFinishedLaunching: finished,
            isQuitting: quitting,
            launchDate: launched,
            location: location,
            bundleVersion: version
        )
    }

    /// 起動の途中の自分（調べている途中）
    nonisolated static func me(
        _ pid: Int32 = own,
        location: ShellInstallLocation = .installed,
        launched: Date? = nil,
        version: String? = nil
    ) -> ShellRunningInstance {
        instance(pid, location == .installed ? installed : diskImage, finished: false, launched: launched, location: location, version: version)
    }

    static func decide(_ running: [ShellRunningInstance], own: ShellRunningInstance = me(), waited: TimeInterval) -> ShellInstanceDecision {
        ShellInstanceGuard.decide(running: running, own: own, waited: waited, allowsMultiple: false)
    }

    // MARK: - 2つ目の起動

    @Test("ほかに動いていなければそのまま起動する（一覧に自分しかいない・終わったものだけ）")
    func launchesAlone() {
        #expect(Self.decide([], waited: 0) == .launch)
        #expect(Self.decide([Self.me()], waited: 0) == .launch)
        #expect(Self.decide([Self.me(), Self.instance(42, terminated: true)], waited: 0) == .launch)
    }

    @Test("起動し終えて動いているものがあれば、待たずにそちらに任せて終わる（もう一度開いたらすぐに設定が開く）")
    func handsOffImmediately() {
        let own = Self.me(location: .temporary)
        // ディスクイメージなどから開いたこちらは、アプリケーションフォルダのものに任せる前に、そのことを伝える
        #expect(Self.decide([own, Self.instance(42)], own: own, waited: 0) == .explainAndHandOff(Self.instance(42)))
        // 同じ場所のものでも同じ（起動し終えた方を残す）。こちらは伝えずに任せる
        #expect(Self.decide([Self.me(), Self.instance(42)], waited: 0) == .handOff(Self.instance(42)))
        let temporary = Self.instance(42, Self.diskImage, location: .temporary)
        #expect(Self.decide([own, temporary], own: own, waited: 0) == .handOff(temporary))
    }

    @Test("終わりかけのもの（終了した直後に開き直した）は、終わるのを待ってから起動する。任せない")
    func waitsWhileQuitting() {
        let quitting = Self.instance(42, quitting: true)
        #expect(Self.decide([Self.instance(42, quitting: true), Self.me()], waited: 0.1) == .wait)
        #expect(Self.decide([quitting, Self.me()], waited: ShellInstanceGuard.shutdownGrace + 1) == .wait)
        #expect(Self.decide([Self.instance(42, terminated: true, quitting: true), Self.me()], waited: 0.2) == .launch)
        // 終わりきらなくても、もう入力は見ていないので、待ちすぎたら起動する（どちらも動かない、にはしない）
        #expect(Self.decide([quitting, Self.me()], waited: ShellInstanceGuard.takeOverTimeout) == .launch)
        // 終わりかけのものと動いているものがあれば、動いている方に任せる
        #expect(Self.decide([quitting, Self.instance(43), Self.me()], waited: 0) == .handOff(Self.instance(43)))
    }

    @Test("並べて動かしてよいときは調べない")
    func allowsMultiple() {
        #expect(ShellInstanceGuard.decide(running: [Self.instance(42)], own: Self.me(), waited: 0, allowsMultiple: true) == .launch)
    }

    @Test("同時に開かれたら、先に開かれた方だけが起動する（もう一方は相手を待たずに任せて終わる）")
    func simultaneousLaunchKeepsOne() {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let first = Self.me(41, launched: start)
        let second = Self.me(42, launched: start.addingTimeInterval(0.2))
        let running = [first, second]
        let grace = ShellInstanceGuard.shutdownGrace
        // 先の方は、後の方が譲って終わるのを待つ
        #expect(Self.decide(running, own: first, waited: grace) == .wait)
        // 後の方は、先の方が起動の途中でも任せて終わる（どちらも相手を待ち続けない）
        #expect(Self.decide(running, own: second, waited: grace) == .handOff(first))
        #expect(Self.decide([first], own: first, waited: grace + 0.1) == .launch)
        // 開かれた時刻が分からなければ、プロセス番号の小さい方
        let noDates = [Self.me(41), Self.me(42)]
        #expect(Self.decide(noDates, own: Self.me(41), waited: grace) == .wait)
        #expect(Self.decide(noDates, own: Self.me(42), waited: grace) == .handOff(Self.me(41)))
    }

    @Test("アプリケーションフォルダのものを開いたら、ディスクイメージなどから開いたままのものに終わってもらい、代わりに動く")
    func installedReplacesTemporary() {
        let temporary = Self.instance(42, Self.diskImage, location: .temporary)
        let running = [Self.me(), temporary]
        // 待たずに終わってもらう
        #expect(Self.decide(running, waited: 0) == .replace(temporary))
        #expect(Self.decide(running, waited: ShellInstanceGuard.takeOverTimeout - 0.1) == .replace(temporary))
        #expect(Self.decide([Self.me(), Self.instance(42, Self.diskImage, terminated: true, location: .temporary)], waited: 1) == .launch)
        // 終わってくれなければ（尋ねる画面を出している など）、そちらに任せる。2つは動かさない
        #expect(Self.decide(running, waited: ShellInstanceGuard.takeOverTimeout) == .handOff(temporary))

        // 逆に、一時的な場所から開いたものは、アプリケーションフォルダのものに任せる（起動の途中でも）
        let own = Self.me(location: .temporary)
        #expect(Self.decide([own, Self.instance(42)], own: own, waited: ShellInstanceGuard.shutdownGrace) == .explainAndHandOff(Self.instance(42)))
        // 起動の途中のもの（同時に開かれた）は、こちらが終わるのを待っているので、伝えずにすぐ終わる
        let launching = Self.me(42)
        #expect(Self.decide([own, launching], own: own, waited: ShellInstanceGuard.shutdownGrace) == .handOff(launching))
    }

    @Test("新しい DMG から開いたら、アプリケーションフォルダで動いている古い方に終わってもらってから起動する（その後で置き換えるかを尋ねる）")
    func newerTemporaryReplacesOlderInstalled() {
        let own = Self.me(location: .temporary, version: "11")
        let old = Self.instance(42, version: "10")
        let running = [own, old]
        // 待たずに終わってもらう（任せて終わらない）
        #expect(Self.decide(running, own: own, waited: 0) == .replace(old))
        #expect(Self.decide(running, own: own, waited: ShellInstanceGuard.takeOverTimeout - 0.1) == .replace(old))
        // 終わり始めたら、終わるのを待ってから起動する（2つが同時にトリガーキーを見ないように）
        let quitting = Self.instance(42, quitting: true, version: "10")
        #expect(Self.decide([own, quitting], own: own, waited: 1) == .wait)
        #expect(Self.decide([own, Self.instance(42, terminated: true, version: "10")], own: own, waited: 1) == .launch)
        // 終わってくれなければ（尋ねる画面を出している など）、伝えてからそちらに任せる。2つは動かさない
        #expect(Self.decide(running, own: own, waited: ShellInstanceGuard.takeOverTimeout) == .explainAndHandOff(old))
        // ビルド番号は数として比べる（"9" より "10" が新しい）
        let nine = Self.instance(42, version: "9")
        #expect(Self.decide([own, nine], own: Self.me(location: .temporary, version: "10"), waited: 0) == .replace(nine))
    }

    @Test("DMG から開いた方が新しくなければ（同じ・古い・分からない）、アプリケーションフォルダで動いている方に、伝えてから任せる", arguments: [
        "10", "9", nil,
    ] as [String?])
    func notNewerTemporaryExplains(ownVersion: String?) {
        let own = Self.me(location: .temporary, version: ownVersion)
        let installedRunning = Self.instance(42, version: "10")
        #expect(Self.decide([own, installedRunning], own: own, waited: 0) == .explainAndHandOff(installedRunning))
        // 動いている方の版が分からなくても、置き換えない
        let unknown = Self.instance(42)
        #expect(Self.decide([own, unknown], own: Self.me(location: .temporary, version: "99"), waited: 0) == .explainAndHandOff(unknown))
    }

    @Test("新しい DMG から開いたものが動いているときに、アプリケーションフォルダの古い方を開いたら、新しい方に任せる（どのプロセスから見ても同じものを残す）")
    func olderInstalledDefersToNewerTemporary() {
        let newer = Self.instance(42, Self.diskImage, location: .temporary, version: "11")
        let own = Self.me(version: "10")
        #expect(Self.decide([own, newer], own: own, waited: 0) == .handOff(newer))
        // 同じ版なら、これまでどおりアプリケーションフォルダの方が代わりに動く
        let same = Self.instance(42, Self.diskImage, location: .temporary, version: "10")
        #expect(Self.decide([own, same], own: own, waited: 0) == .replace(same))
    }

    @Test("任せる前に伝える文は、動いている方とこちらの版を言い、入れ替え方を伝える")
    func alreadyRunningMessage() {
        let message = ShellMoveToApplications.alreadyRunningMessage(running: "1.0.0 (1)", own: "1.0.1 (2)")
        #expect(message.contains("1.0.0 (1)"))
        #expect(message.contains("1.0.1 (2)"))
        #expect(message == L10n.ui("アプリケーションフォルダの Nonet（\("1.0.0 (1)")）が動いているので、そちらを使います。この Nonet（\("1.0.1 (2)")）は終了します。入れ替えるときは、動いている Nonet を終了してから、もう一度開いてください。"))
    }

    /// 同じ bundle ID のプロセスを時間を進めて動かし、最後に動いているものを返す。
    /// launching は at の時刻に開かれるもの（それぞれが ShellInstanceGuard で調べる）、
    /// running は前から動いているもの（終わってと頼まれたら終わる）。起動したものは launchTime の後に起動し終える
    static func simulate(
        launching: [(instance: ShellRunningInstance, at: TimeInterval)],
        running: [ShellRunningInstance] = [],
        launchTime: TimeInterval = 0.5
    ) -> [Int32] {
        struct Process {
            var instance: ShellRunningInstance
            var startsAt: TimeInterval
            /// 調べている途中（main.swift）
            var isGuarding: Bool
            var finishesLaunchingAt: TimeInterval?
            var askedToQuit = false
        }
        var processes = running.map { Process(instance: $0, startsAt: 0, isGuarding: false) }
            + launching.map { Process(instance: $0.instance, startsAt: $0.at, isGuarding: true) }
        let step = ShellInstanceGuard.pollInterval
        var now: TimeInterval = 0
        while now < 30, processes.contains(where: { $0.isGuarding || $0.askedToQuit || $0.finishesLaunchingAt != nil }) {
            // 終わってと頼まれたものは終わり、起動したものは起動し終える
            processes.removeAll(where: \.askedToQuit)
            for index in processes.indices where (processes[index].finishesLaunchingAt ?? .infinity) <= now {
                processes[index].instance.isFinishedLaunching = true
                processes[index].finishesLaunchingAt = nil
            }
            for index in processes.indices.reversed() where processes[index].isGuarding && processes[index].startsAt <= now {
                let visible = processes.filter { $0.startsAt <= now }.map(\.instance)
                let me = processes[index]
                switch ShellInstanceGuard.decide(running: visible, own: me.instance, waited: now - me.startsAt, allowsMultiple: false) {
                case .launch:
                    processes[index].isGuarding = false
                    processes[index].finishesLaunchingAt = now + launchTime
                case .wait:
                    break
                case .replace(let other):
                    if let target = processes.firstIndex(where: { $0.instance.processID == other.processID }) {
                        processes[target].askedToQuit = true
                    }
                case .handOff, .explainAndHandOff:
                    processes.remove(at: index)
                }
            }
            now += step
        }
        return processes.map(\.instance.processID).sorted()
    }

    @Test("どの組み合わせで開いても、ちょうど1つだけが動き続ける")
    func exactlyOneSurvives() {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let a = Self.me(41, launched: start)
        let b = Self.me(42, launched: start.addingTimeInterval(0.1))
        // 2つを同時に・少しずらして（別の場所のものを含む）
        #expect(Self.simulate(launching: [(a, 0), (b, 0)]) == [41])
        #expect(Self.simulate(launching: [(a, 0), (b, 1)]) == [41])
        #expect(Self.simulate(launching: [(Self.me(41), 0), (Self.me(42), 0)]) == [41])
        #expect(Self.simulate(launching: [(Self.me(41, location: .temporary, launched: start), 0), (b, 0)]) == [42])
        // 起動に時間がかかっても
        #expect(Self.simulate(launching: [(a, 0), (b, 2)], launchTime: 5) == [41])
        // 前から動いているものがあるとき
        let installedRunning = Self.instance(40)
        #expect(Self.simulate(launching: [(b, 0)], running: [installedRunning]) == [40])
        #expect(Self.simulate(launching: [(Self.me(42, location: .temporary), 0)], running: [installedRunning]) == [40])
        let temporaryRunning = Self.instance(40, Self.diskImage, location: .temporary)
        #expect(Self.simulate(launching: [(b, 0)], running: [temporaryRunning]) == [42])
        #expect(Self.simulate(launching: [(a, 0), (b, 0)], running: [temporaryRunning]) == [41])
        // 新しい DMG から開いたとき: アプリケーションフォルダで動いている古い方が終わり、新しい方が残る
        let oldInstalled = Self.instance(40, version: "10")
        #expect(Self.simulate(launching: [(Self.me(42, location: .temporary, version: "11"), 0)], running: [oldInstalled]) == [42])
        #expect(Self.simulate(launching: [(Self.me(42, location: .temporary, version: "10"), 0)], running: [oldInstalled]) == [40])
        // 古いアプリケーションフォルダのものと新しい DMG のものを同時に・ずらして開いても1つだけ
        let newTemporary = Self.me(41, location: .temporary, launched: start, version: "11")
        let oldInstalledLaunching = Self.me(42, launched: start.addingTimeInterval(0.1), version: "10")
        #expect(Self.simulate(launching: [(newTemporary, 0), (oldInstalledLaunching, 0)]) == [41])
        #expect(Self.simulate(launching: [(newTemporary, 0), (oldInstalledLaunching, 1)]) == [41])
        #expect(Self.simulate(launching: [(oldInstalledLaunching, 0), (newTemporary, 1)]) == [41])
        // アプリケーションフォルダのもの2つ（違う版）と DMG のものが重なっても、1つだけ
        let installedA = Self.me(43, launched: start, version: "9")
        let installedB = Self.me(44, launched: start.addingTimeInterval(0.1), version: "12")
        let survivors = Self.simulate(launching: [(installedA, 0), (installedB, 0), (newTemporary, 0)])
        #expect(survivors.count == 1)
    }

    // MARK: - 終わり始めた印

    @Test("終わり始めた印: 書いたプロセスだけが終わりかけ。開いた時刻より前の印（同じ番号の前のプロセス）は数えない。起動したら消す")
    func quitMarker() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("nonet-quit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let launched = Date().addingTimeInterval(-60)
        #expect(!ShellQuitMarker.isQuitting(processID: 42, launchDate: launched, in: directory))
        ShellQuitMarker.mark(processID: 42, in: directory)
        #expect(ShellQuitMarker.isQuitting(processID: 42, launchDate: launched, in: directory))
        #expect(ShellQuitMarker.isQuitting(processID: 42, launchDate: nil, in: directory))
        #expect(!ShellQuitMarker.isQuitting(processID: 43, launchDate: launched, in: directory))
        // 印より後に開かれた（同じ番号を使い回した）プロセスは終わりかけではない
        #expect(!ShellQuitMarker.isQuitting(processID: 42, launchDate: Date().addingTimeInterval(60), in: directory))

        let other = directory.appendingPathComponent("keep.txt")
        try Data().write(to: other)
        ShellQuitMarker.removeAll(in: directory)
        #expect(!ShellQuitMarker.isQuitting(processID: 42, launchDate: nil, in: directory))
        #expect(FileManager.default.fileExists(atPath: other.path))
    }

    // MARK: - どこから開かれたか

    @Test("App Translocation と読み取り専用のディスクイメージは一時的な場所", arguments: [
        ("/private/var/folders/xy/T/AppTranslocation/1234/d/Nonet.app", false, false, ShellInstallLocation.temporary),
        ("/Users/me/Downloads/Nonet.app", true, false, .temporary),
        ("/Volumes/Nonet/Nonet.app", false, true, .temporary),
        // 外付けのディスクに自分で置いたもの（書き込める）
        ("/Volumes/Work/Apps/Nonet.app", false, false, .installed),
        ("/Applications/Nonet.app", false, false, .installed),
        ("/Users/me/Applications/Nonet.app", false, false, .installed),
    ])
    func classify(path: String, translocated: Bool, readOnly: Bool, expected: ShellInstallLocation) {
        #expect(ShellInstallLocation.classify(bundlePath: path, isTranslocated: translocated, isReadOnlyVolume: readOnly) == expected)
    }

    @Test("ふつうの場所は App Translocation ではない（Security の関数を引けて、答えが返る）")
    func notTranslocated() {
        // 関数を引けない・呼び方が違うと nil になり、パスの /AppTranslocation/ だけで見分けることになる
        #expect(ShellInstallLocation.translocationStatus(FileManager.default.temporaryDirectory) == false)
        #expect(ShellInstallLocation.translocationStatus(URL(fileURLWithPath: "/Applications")) == false)
        #expect(!ShellInstallLocation.isTranslocated(FileManager.default.temporaryDirectory))
        #expect(ShellInstallLocation.of(bundleURL: FileManager.default.temporaryDirectory) == .installed)
    }

    @Test("書き込めなければ尋ねずに説明だけ、すでにあれば置き換えてよいか尋ねる")
    func plan() {
        #expect(ShellMoveToApplications.plan(destinationExists: false, directoryWritable: true) == .copy)
        #expect(ShellMoveToApplications.plan(destinationExists: true, directoryWritable: true) == .confirmReplace)
        #expect(ShellMoveToApplications.plan(destinationExists: false, directoryWritable: false) == .explain)
        #expect(ShellMoveToApplications.plan(destinationExists: true, directoryWritable: false) == .explain)
        #expect(ShellMoveToApplications.destination(for: Self.diskImage, in: ShellMoveToApplications.applicationsDirectory).path
            == "/Applications/Nonet.app")
    }

    @Test("移すかを尋ねる説明は、移さないとどうなるか（取り出すと使えない・アップデートが届かない）を言う")
    func moveMessage() {
        #expect(ShellMoveToApplications.moveMessage
            == L10n.ui("このままだと、ディスクイメージを取り出したり Mac を再起動したりすると Nonet が使えなくなり、アップデートも届きません。移すと自動で開き直します。"))
    }

    @Test("/Applications に書き込めない（管理者でない）ときは、ホームのアプリケーションフォルダに移す")
    func targetDirectory() throws {
        let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)
        #expect(ShellMoveToApplications.targetDirectory(isSystemWritable: true, home: home).path == "/Applications")
        #expect(ShellMoveToApplications.targetDirectory(isSystemWritable: false, home: home).path == "/Users/me/Applications")
        // すでに入っている Nonet があれば、そのフォルダ（別のフォルダに2つ目を入れない）。/Applications を先に見る
        let source = URL(fileURLWithPath: "/Volumes/Nonet/Nonet.app")
        let inSystem: Set<String> = ["/Applications/Nonet.app"]
        let inHome: Set<String> = ["/Users/me/Applications/Nonet.app"]
        #expect(ShellMoveToApplications.existingInstallDirectory(for: source, home: home, exists: inSystem.contains)?.path == "/Applications")
        #expect(ShellMoveToApplications.existingInstallDirectory(for: source, home: home, exists: inHome.contains)?.path == "/Users/me/Applications")
        #expect(ShellMoveToApplications.existingInstallDirectory(for: source, home: home, exists: inSystem.union(inHome).contains)?.path == "/Applications")
        #expect(ShellMoveToApplications.existingInstallDirectory(for: source, home: home, exists: { _ in false }) == nil)

        // まだ無いフォルダは、作る場所に書き込めれば書き込めるとみなす
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nonet-install-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
            try? FileManager.default.removeItem(at: root)
        }
        let applications = root.appendingPathComponent("Applications", isDirectory: true)
        #expect(ShellMoveToApplications.isWritable(applications))
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.path)
        #expect(!ShellMoveToApplications.isWritable(applications))
        #expect(!ShellMoveToApplications.isWritable(root))
    }

    @Test("写して、ダウンロードの印を外し、すでにあったものと入れ替える")
    func installReplacesAndClearsQuarantine() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nonet-install-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try Self.makeBundle(at: root.appendingPathComponent("dmg/Nonet.app"), marker: "new")
        let applications = root.appendingPathComponent("Applications", isDirectory: true)
        let destination = applications.appendingPathComponent("Nonet.app")
        _ = try Self.makeBundle(at: destination, marker: "old")
        let binary = source.appendingPathComponent("Contents/MacOS/Nonet").path
        #expect(setxattr(binary, "com.apple.quarantine", "0081;00000000;Safari;", 21, 0, 0) == 0)

        var removed: [URL] = []
        try ShellMoveToApplications.install(from: source, to: destination) { existing in
            removed.append(existing)
            try FileManager.default.removeItem(at: existing)
            return nil
        }
        #expect(removed == [destination])
        let installedBinary = destination.appendingPathComponent("Contents/MacOS/Nonet").path
        #expect(try String(contentsOfFile: installedBinary, encoding: .utf8) == "new")
        #expect(getxattr(installedBinary, "com.apple.quarantine", nil, 0, 0, 0) == -1)
        // 元の場所はそのまま。一時的な名前のものは残さない
        #expect(getxattr(binary, "com.apple.quarantine", nil, 0, 0, 0) > 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: applications.path) == ["Nonet.app"])
    }

    @Test("置き換えに失敗したら、すでにあったものを残し、一時的なものも残さない")
    func installFailureKeepsExisting() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nonet-install-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try Self.makeBundle(at: root.appendingPathComponent("dmg/Nonet.app"), marker: "new")
        let applications = root.appendingPathComponent("Applications", isDirectory: true)
        let destination = applications.appendingPathComponent("Nonet.app")
        _ = try Self.makeBundle(at: destination, marker: "old")
        struct Refused: Error {}
        #expect(throws: Refused.self) {
            try ShellMoveToApplications.install(from: source, to: destination) { _ in throw Refused() }
        }
        #expect(try String(contentsOfFile: destination.appendingPathComponent("Contents/MacOS/Nonet").path, encoding: .utf8) == "old")
        #expect(try FileManager.default.contentsOfDirectory(atPath: applications.path) == ["Nonet.app"])
    }

    @Test("ゴミ箱に入れた後で入れ替えに失敗したら、ゴミ箱から元の場所に戻す")
    func installRestoresExistingWhenFinalMoveFails() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nonet-install-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try Self.makeBundle(at: root.appendingPathComponent("dmg/Nonet.app"), marker: "new")
        let applications = root.appendingPathComponent("Applications", isDirectory: true)
        let destination = applications.appendingPathComponent("Nonet.app")
        _ = try Self.makeBundle(at: destination, marker: "old")
        let trash = root.appendingPathComponent("Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        #expect(throws: ShellFailingFileManager.Failure.self) {
            try ShellMoveToApplications.install(from: source, to: destination, fileManager: ShellFailingFileManager()) { existing in
                let trashed = trash.appendingPathComponent("Nonet.app")
                try FileManager.default.moveItem(at: existing, to: trashed)
                return trashed
            }
        }
        #expect(try String(contentsOfFile: destination.appendingPathComponent("Contents/MacOS/Nonet").path, encoding: .utf8) == "old")
        #expect(try FileManager.default.contentsOfDirectory(atPath: applications.path) == ["Nonet.app"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: trash.path).isEmpty)
    }

    @Test("写している途中で失敗したら（読めないファイル・ディスクがいっぱい）、写しかけのものを残さない")
    func installCleansUpPartialCopy() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nonet-install-\(UUID().uuidString)", isDirectory: true)
        let source = try Self.makeBundle(at: root.appendingPathComponent("dmg/Nonet.app"), marker: "new")
        let unreadable = source.appendingPathComponent("Contents/Resources/locked")
        try FileManager.default.createDirectory(at: unreadable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: unreadable)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: unreadable.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: unreadable.path)
            try? FileManager.default.removeItem(at: root)
        }
        let applications = root.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)
        let destination = applications.appendingPathComponent("Nonet.app")

        var movedAside = 0
        #expect(throws: (any Error).self) {
            try ShellMoveToApplications.install(from: source, to: destination) { _ in
                movedAside += 1
                return nil
            }
        }
        #expect(movedAside == 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: applications.path).isEmpty)
    }

    @Test("開き直しは、このプロセスが終わるのを待ってから open する（パスは引数で渡す）")
    func relaunchArguments() {
        let arguments = ShellMoveToApplications.relaunchArguments(processID: 1234, appPath: "/Applications/Nonet \"β\".app")
        #expect(arguments.count == 4)
        #expect(arguments[0] == "-c")
        #expect(arguments[1].contains("/bin/kill -0 1234"))
        #expect(arguments[1].contains("/usr/bin/open \"$app\""))
        #expect(arguments[3] == "/Applications/Nonet \"β\".app")
        // リンクやファイルで開かれていたら、開き直した Nonet でそれを開く（引数で渡す）
        let link = URL(string: "nonet://register?key=abc")!
        let file = URL(fileURLWithPath: "/Users/a/Downloads/My License.nonetlicense")
        let withItems = ShellMoveToApplications.relaunchArguments(
            processID: 1234, appPath: "/Applications/Nonet.app",
            items: [link, file].map(ShellMoveToApplications.openArgument(for:))
        )
        #expect(withItems.suffix(2) == ["nonet://register?key=abc", "/Users/a/Downloads/My License.nonetlicense"])
        #expect(withItems[1].contains("/usr/bin/open -a \"$app\" \"$@\""))
    }

    @Test("開き直しのコマンドは、渡したリンクとファイルを open -a に渡し、無ければアプリだけを開く（本物の sh で、open の代わりに echo）")
    func relaunchScriptPassesItems() async throws {
        func run(_ items: [String]) async throws -> String {
            var arguments = ShellMoveToApplications.relaunchArguments(processID: 999_999, appPath: "/Applications/Nonet.app", items: items)
            arguments[1] = arguments[1].replacingOccurrences(of: "/usr/bin/open", with: "echo")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            try process.run()
            process.waitUntilExit()
            return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        }
        #expect(try await run([]) == "/Applications/Nonet.app\n")
        #expect(try await run(["nonet://register?key=a b", "/tmp/x y.nonetlicense"]) == "-a /Applications/Nonet.app nonet://register?key=a b /tmp/x y.nonetlicense\n")
    }

    @Test("版の表記は Info.plist から")
    func versionText() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nonet-install-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = try Self.makeBundle(at: root.appendingPathComponent("Nonet.app"), marker: "x")
        #expect(ShellMoveToApplications.versionText(of: bundle) == "1.2.0 (7)")
        #expect(ShellMoveToApplications.versionText(of: root.appendingPathComponent("Missing.app")) == "?")
    }

    static func makeBundle(at url: URL, marker: String) throws -> URL {
        let macOS = url.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try Data(marker.utf8).write(to: macOS.appendingPathComponent("Nonet"))
        let info: [String: Any] = [
            "CFBundleIdentifier": "com.iam74k4.Nonet.tests",
            "CFBundleExecutable": "Nonet",
            "CFBundleShortVersionString": "1.2.0",
            "CFBundleVersion": "7",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: url.appendingPathComponent("Contents/Info.plist"))
        return url
    }
}
