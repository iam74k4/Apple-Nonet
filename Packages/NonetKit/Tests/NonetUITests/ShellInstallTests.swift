// 担当: ui-shell
import Foundation
@testable import NonetUI
import Testing

@Suite("2つ目の起動と、アプリケーションフォルダへの移動")
@MainActor
struct ShellInstallTests {
    static let own: Int32 = 500
    static let installed = URL(fileURLWithPath: "/Applications/Nonet.app")

    static func instance(_ pid: Int32, _ url: URL? = installed, terminated: Bool = false) -> ShellRunningInstance {
        ShellRunningInstance(processID: pid, bundleURL: url, isTerminated: terminated)
    }

    // MARK: - 2つ目の起動

    @Test("ほかに動いていなければそのまま起動する（一覧に自分しかいない・終わったものだけ）")
    func launchesAlone() {
        #expect(ShellInstanceGuard.decide(running: [], ownProcessID: Self.own, waited: 0, allowsMultiple: false) == .launch)
        #expect(ShellInstanceGuard.decide(running: [Self.instance(Self.own)], ownProcessID: Self.own, waited: 0, allowsMultiple: false) == .launch)
        let finished = [Self.instance(Self.own), Self.instance(42, terminated: true)]
        #expect(ShellInstanceGuard.decide(running: finished, ownProcessID: Self.own, waited: 0, allowsMultiple: false) == .launch)
    }

    @Test("ほかに動いていれば、終わるのを3秒まで待ち、まだ動いていればそちらに任せて終わる")
    func handsOffAfterGrace() {
        let running = [Self.instance(Self.own, URL(fileURLWithPath: "/Volumes/Nonet/Nonet.app")), Self.instance(42)]
        #expect(ShellInstanceGuard.decide(running: running, ownProcessID: Self.own, waited: 0, allowsMultiple: false) == .wait)
        #expect(ShellInstanceGuard.decide(running: running, ownProcessID: Self.own, waited: 2.9, allowsMultiple: false) == .wait)
        #expect(ShellInstanceGuard.decide(running: running, ownProcessID: Self.own, waited: ShellInstanceGuard.shutdownGrace, allowsMultiple: false)
            == .handOff(Self.instance(42)))
    }

    @Test("待っている間に前のものが終われば（アップデートの後の再起動）、そのまま起動する")
    func launchesAfterShutdown() {
        let shuttingDown = [Self.instance(42), Self.instance(Self.own)]
        #expect(ShellInstanceGuard.decide(running: shuttingDown, ownProcessID: Self.own, waited: 0.1, allowsMultiple: false) == .wait)
        let finished = [Self.instance(42, terminated: true), Self.instance(Self.own)]
        #expect(ShellInstanceGuard.decide(running: finished, ownProcessID: Self.own, waited: 0.2, allowsMultiple: false) == .launch)
    }

    @Test("場所の分かるものに任せる。並べて動かしてよいときは調べない")
    func prefersReachableInstanceAndAllowsMultiple() {
        let running = [Self.instance(41, nil), Self.instance(42)]
        #expect(ShellInstanceGuard.decide(running: running, ownProcessID: Self.own, waited: 5, allowsMultiple: false) == .handOff(Self.instance(42)))
        #expect(ShellInstanceGuard.decide(running: [Self.instance(41, nil)], ownProcessID: Self.own, waited: 5, allowsMultiple: false)
            == .handOff(Self.instance(41, nil)))
        #expect(ShellInstanceGuard.decide(running: running, ownProcessID: Self.own, waited: 0, allowsMultiple: true) == .launch)
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

    @Test("ふつうの場所は App Translocation ではない")
    func notTranslocated() {
        #expect(!ShellInstallLocation.isTranslocated(FileManager.default.temporaryDirectory))
    }

    @Test("書き込めなければ説明だけ、すでにあれば置き換えてよいか尋ねる")
    func plan() {
        #expect(ShellMoveToApplications.plan(destinationExists: false, applicationsWritable: true) == .copy)
        #expect(ShellMoveToApplications.plan(destinationExists: true, applicationsWritable: true) == .confirmReplace)
        #expect(ShellMoveToApplications.plan(destinationExists: false, applicationsWritable: false) == .explain)
        #expect(ShellMoveToApplications.destination(for: URL(fileURLWithPath: "/Volumes/Nonet/Nonet.app"), in: ShellMoveToApplications.applicationsDirectory).path
            == "/Applications/Nonet.app")
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

    @Test("開き直しは、このプロセスが終わるのを待ってから open する（パスは引数で渡す）")
    func relaunchArguments() {
        let arguments = ShellMoveToApplications.relaunchArguments(processID: 1234, appPath: "/Applications/Nonet \"β\".app")
        #expect(arguments.count == 4)
        #expect(arguments[0] == "-c")
        #expect(arguments[1].contains("/bin/kill -0 1234"))
        #expect(arguments[1].hasSuffix("/usr/bin/open \"$1\""))
        #expect(arguments[3] == "/Applications/Nonet \"β\".app")
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
