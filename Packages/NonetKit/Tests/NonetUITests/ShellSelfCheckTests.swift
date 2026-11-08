// 担当: ui-shell
import Foundation
import NonetCore
@testable import NonetUI
import Testing

@Suite("自己診断と起動引数")
@MainActor
struct ShellSelfCheckTests {
    static func report(
        version: String = "1.0.0 (1)",
        roundTripError: String? = nil,
        multitouch: ShellSelfCheck.Multitouch = .init(loaded: true, deviceCount: 1, trackpadAvailable: true),
        entitlement: Entitlement = .trial(daysLeft: 9)
    ) -> ShellSelfCheck.Report {
        ShellSelfCheck.Report(
            version: version,
            presetCount: 15,
            launcherCandidateCount: 38,
            installedLauncherCandidateCount: 12,
            configurationRoundTripError: roundTripError,
            multitouch: multitouch,
            accessibilityGranted: false,
            entitlement: entitlement
        )
    }

    static func decode(_ report: ShellSelfCheck.Report) throws -> [String: Any] {
        let data = try report.jsonData()
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }

    @Test("成功の JSON は1行で、決めたキーをすべて持つ")
    func successJSON() throws {
        let report = Self.report()
        #expect(report.isSuccess)
        let data = try report.jsonData()
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(!text.contains("\n"))
        let json = try Self.decode(report)
        #expect(Set(json.keys) == [
            "ok", "failures", "version", "presets", "launcherCandidates", "installedLauncherCandidates",
            "configurationRoundTrip", "multitouch", "accessibilityGranted", "license",
        ])
        #expect(json["ok"] as? Bool == true)
        #expect((json["failures"] as? [String])?.isEmpty == true)
        #expect(json["version"] as? String == "1.0.0 (1)")
        #expect(json["presets"] as? Int == 15)
        #expect(json["launcherCandidates"] as? Int == 38)
        #expect(json["installedLauncherCandidates"] as? Int == 12)
        #expect(json["accessibilityGranted"] as? Bool == false)
        let roundTrip = try #require(json["configurationRoundTrip"] as? [String: Any])
        #expect(roundTrip["ok"] as? Bool == true)
        #expect(roundTrip["error"] == nil)
        let multitouch = try #require(json["multitouch"] as? [String: Any])
        #expect(multitouch["loaded"] as? Bool == true)
        #expect(multitouch["devices"] as? Int == 1)
        #expect(multitouch["trackpadAvailable"] as? Bool == true)
        let license = try #require(json["license"] as? [String: Any])
        #expect(license["state"] as? String == "trial")
        #expect(license["daysLeft"] as? Int == 9)
    }

    @Test("失敗: 設定の往復・MultitouchSupport・版がおかしい")
    func failures() throws {
        let report = Self.report(
            version: "?",
            roundTripError: "disk full",
            multitouch: .init(loaded: false, deviceCount: 0, trackpadAvailable: false, error: "dlopen failed")
        )
        #expect(!report.isSuccess)
        #expect(report.failures == ["version", "configurationRoundTrip", "multitouch"])
        let json = try Self.decode(report)
        #expect(json["ok"] as? Bool == false)
        let roundTrip = try #require(json["configurationRoundTrip"] as? [String: Any])
        #expect(roundTrip["error"] as? String == "disk full")
        let multitouch = try #require(json["multitouch"] as? [String: Any])
        #expect(multitouch["error"] as? String == "dlopen failed")
        // 版（CFBundleShortVersionString）が無くビルド番号だけあると、AppInfo は「? (42)」になる
        #expect(Self.report(version: "? (42)").failures == ["version"])
        #expect(Self.report(version: "1.2.0 (42)").failures.isEmpty)
    }

    @Test("トラックパッドが無い・許可が無い・試用切れは失敗にしない（Mac による）")
    func environmentIsNotFailure() {
        let report = Self.report(multitouch: .init(loaded: true, deviceCount: 0, trackpadAvailable: false), entitlement: .expired)
        #expect(report.isSuccess)
    }

    @Test("ライセンスは状態だけを出し、購入者の名前は出さない")
    func licenseObject() throws {
        let info = LicenseInfo(licenseID: "L-1", licensee: "山田太郎", email: "taro@example.com", issuedAt: Date(timeIntervalSince1970: 0))
        let json = try Self.decode(Self.report(entitlement: .licensed(info)))
        let license = try #require(json["license"] as? [String: Any])
        #expect(license["state"] as? String == "licensed")
        #expect(license.count == 1)
        let text = try #require(String(data: try Self.report(entitlement: .licensed(info)).jsonData(), encoding: .utf8))
        #expect(!text.contains("山田"))
        #expect(!text.contains("example.com"))
        #expect(ShellSelfCheck.Report.licenseObject(.expired)["state"] as? String == "expired")
    }

    @Test("設定の往復: 一時フォルダに保存して読み直すと同じ")
    func roundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("nonet-shell-roundtrip-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(ShellSelfCheck.configurationRoundTrip(in: directory) == nil)
        #expect(FileManager.default.fileExists(atPath: ConfigurationStore(directory: directory).fileURL.path))
    }

    @Test("設定の往復: 書けない場所なら理由を返す")
    func roundTripFailure() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("nonet-shell-file-\(UUID().uuidString)")
        try Data("x".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        // ファイルの下にはフォルダを作れない
        let error = ShellSelfCheck.configurationRoundTrip(in: file.appendingPathComponent("sub"))
        #expect(error != nil)
        #expect(error?.isEmpty == false)
    }

    @Test("run は渡したサービスから集め、一時フォルダを片付ける")
    func run() throws {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("nonet-shell-run-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let harness = ShellControllerHarness(installed: [ShellFixtures.safari, ShellFixtures.finder, "com.example.other"], accessibilityGranted: true)
        let report = ShellSelfCheck.run(
            version: "2.0",
            permissions: harness.permissions,
            installedApps: harness.installedApps,
            multitouch: .init(loaded: true, deviceCount: 2, trackpadAvailable: true),
            license: harness.license,
            workDirectory: work
        )
        #expect(report.isSuccess)
        #expect(report.version == "2.0")
        #expect(report.presetCount == PresetLibrary.apps.count)
        #expect(report.launcherCandidateCount == PresetLibrary.launcherCandidates.count)
        #expect(report.installedLauncherCandidateCount == 2)
        #expect(report.accessibilityGranted)
        #expect(report.entitlement == .trial(daysLeft: 14))
        #expect(report.configurationRoundTripError == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: work.path).isEmpty)
    }

    // MARK: - 起動引数

    @Test("自己診断の試用の記録: 本物から読むだけで、数えても、写しが消えていても、どこにも書かない")
    func licenseSnapshotWritesNothing() throws {
        let suiteName = "com.iam74k4.Nonet.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("nonet-self-check-\(UUID().uuidString)", isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }
        let day: TimeInterval = 24 * 60 * 60
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        // アプリが書いた記録（UserDefaults と Application Support の両方）
        let app = UserDefaultsLicenseStorage(defaults: defaults, supportDirectory: directory)
        app.trialStartDate = start
        app.trialLastSeenDate = start.addingTimeInterval(3 * day)
        app.trialUsedTime = 3 * day
        app.licenseKey = "not-a-valid-key"
        // 利用ガイドのとおりに Application Support/Nonet を消してから自己診断を動かす
        try FileManager.default.removeItem(at: directory)
        let before = defaults.persistentDomain(forName: suiteName) as NSDictionary?

        let snapshot = ShellSelfCheck.LicenseSnapshot(defaults: defaults, supportDirectory: directory)
        #expect(snapshot.trialStartDate == start)
        #expect(snapshot.trialUsedTime == 3 * day)
        let now = start.addingTimeInterval(4 * day)
        let license = LicenseManager(verifier: nil, storage: snapshot, now: { now })
        license.refresh()
        #expect(license.entitlement == .trial(daysLeft: 10))
        // 数えた分はメモリの中だけ
        #expect(snapshot.trialUsedTime == 4 * day)

        #expect(defaults.persistentDomain(forName: suiteName) as NSDictionary? == before)
        #expect(!FileManager.default.fileExists(atPath: directory.path))

        // 比べるため: 写しを読むふつうの読み方は、読むだけでフォルダを作り直す（これまでの --self-check）
        _ = UserDefaultsLicenseStorage(defaults: defaults, supportDirectory: directory).trialStartDate
        #expect(FileManager.default.fileExists(atPath: directory.path))
    }

    @Test("自己診断の試用の記録: UserDefaults が消されていても、Application Support の写しから試用に厳しい方を読む（アプリと同じ状態を出す）")
    func licenseSnapshotReadsMirror() throws {
        let suiteName = "com.iam74k4.Nonet.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("nonet-self-check-\(UUID().uuidString)", isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }
        let day: TimeInterval = 24 * 60 * 60
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let start = now.addingTimeInterval(-21 * day)
        // アプリが書いた記録: 21日前に始めて、15日使った
        let app = UserDefaultsLicenseStorage(defaults: defaults, supportDirectory: directory)
        app.trialStartDate = start
        app.trialLastSeenDate = now
        app.trialUsedTime = 15 * day
        // 試用をやり直そうとして UserDefaults だけを消した
        defaults.removePersistentDomain(forName: suiteName)
        let mirror = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        // 写しのファイルの名前は NonetCore のものと同じ
        #expect(mirror == [
            ShellSelfCheck.LicenseSnapshot.startFileName,
            ShellSelfCheck.LicenseSnapshot.lastSeenFileName,
            ShellSelfCheck.LicenseSnapshot.usedFileName,
        ].sorted())
        let files = try mirror.map { try Data(contentsOf: directory.appendingPathComponent($0)) }

        let snapshot = ShellSelfCheck.LicenseSnapshot(defaults: defaults, supportDirectory: directory)
        #expect(snapshot.trialStartDate == start)
        #expect(snapshot.trialLastSeenDate == now)
        #expect(snapshot.trialUsedTime == 15 * day)
        let license = LicenseManager(verifier: nil, storage: snapshot, now: { now })
        #expect(license.entitlement == .expired)
        // UserDefaults にも写しにも書き戻さない
        #expect(defaults.persistentDomain(forName: suiteName)?.isEmpty ?? true)
        #expect(try mirror.map { try Data(contentsOf: directory.appendingPathComponent($0)) } == files)

        // 2か所が食い違うときも、開始日と数えた時刻は早い方、使った時間は長い方
        defaults.set(now.addingTimeInterval(-2 * day), forKey: "com.iam74k4.Nonet.license.trialStart")
        defaults.set(3 * day, forKey: "com.iam74k4.Nonet.license.trialUsed")
        defaults.set(now.addingTimeInterval(-1 * day), forKey: "com.iam74k4.Nonet.license.trialLastSeen")
        let mixed = ShellSelfCheck.LicenseSnapshot(defaults: defaults, supportDirectory: directory)
        #expect(mixed.trialStartDate == start)
        #expect(mixed.trialLastSeenDate == now.addingTimeInterval(-1 * day))
        #expect(mixed.trialUsedTime == 15 * day)
    }

    @Test("起動引数: 何も無ければすべて既定")
    func noArguments() {
        #expect(ShellLaunchOptions.parse(["/Applications/Nonet.app/Contents/MacOS/Nonet"]) == ShellLaunchOptions())
        #expect(ShellLaunchOptions.parse([]) == ShellLaunchOptions())
    }

    @Test("起動引数: すべて読み、知らないものは無視する")
    func allArguments() {
        let options = ShellLaunchOptions.parse([
            "Nonet", "-NSDocumentRevisionsDebugMode", "YES",
            "--config-dir", "/tmp/nonet config",
            "--show-settings", "license",
            "--show-onboarding", "--preview-hud", "--preview-app", "com.apple.dt.Xcode",
            "--preview-backdrop", "/tmp/backdrop.png", "--preview-toast", "--preview-result",
            "--demo-script", "--demo-app", "us.zoom.xos", "--demo-backdrop", "/tmp/demo.png", "--demo-start-file", "/tmp/go",
            "--simulate-expired-trial", "--self-check", "--snapshot", "/tmp/shots",
        ])
        #expect(options.configDirectory?.path == "/tmp/nonet config")
        #expect(options.settingsTab == .license)
        #expect(options.showOnboarding)
        #expect(options.previewHUD)
        #expect(options.previewBundleID == "com.apple.dt.Xcode")
        #expect(options.previewBackdrop?.path == "/tmp/backdrop.png")
        #expect(options.demo)
        #expect(options.demoScript)
        #expect(options.demoBundleID == "us.zoom.xos")
        #expect(options.demoBackdrop?.path == "/tmp/demo.png")
        #expect(options.demoStartFile?.path == "/tmp/go")
        #expect(options.previewToast)
        #expect(options.previewResult)
        #expect(options.simulateExpiredTrial)
        #expect(options.selfCheck)
        #expect(options.snapshotDirectory?.path == "/tmp/shots")
    }

    @Test("起動引数: --show-settings のタブは省ける（プロファイル）。知らないタブも同じ")
    func settingsTabDefault() {
        #expect(ShellLaunchOptions.parse(["Nonet", "--show-settings"]).settingsTab == .profiles)
        let unknown = ShellLaunchOptions.parse(["Nonet", "--show-settings", "--preview-hud"])
        #expect(unknown.settingsTab == .profiles)
        #expect(unknown.previewHUD)
        #expect(ShellLaunchOptions.parse(["Nonet", "--show-settings", "about"]).settingsTab == .profiles)
        #expect(ShellLaunchOptions.parse(["Nonet", "--show-settings", "general"]).settingsTab == .general)
    }

    @Test("起動引数: --onboarding-step は初回の案内をその画面で開く（--show-onboarding も兼ねる）。値が無ければ使わない")
    func onboardingStep() {
        let options = ShellLaunchOptions.parse(["Nonet", "--onboarding-step", "practice"])
        #expect(options.onboardingStep == "practice")
        #expect(options.showOnboarding)
        let missing = ShellLaunchOptions.parse(["Nonet", "--onboarding-step", "--preview-hud"])
        #expect(missing.onboardingStep == nil)
        #expect(!missing.showOnboarding)
        #expect(missing.previewHUD)
    }

    @Test("起動引数: --config-dir の値が無ければ使わない。~ は展開する")
    func configDirectory() {
        #expect(ShellLaunchOptions.parse(["Nonet", "--config-dir"]).configDirectory == nil)
        let next = ShellLaunchOptions.parse(["Nonet", "--config-dir", "--preview-hud"])
        #expect(next.configDirectory == nil)
        #expect(next.previewHUD)
        let home = ShellLaunchOptions.parse(["Nonet", "--config-dir", "~/nonet-test"])
        #expect(home.configDirectory?.path == (NSHomeDirectory() as NSString).appendingPathComponent("nonet-test"))
        #expect(ShellLaunchOptions.parse(["Nonet", "--snapshot"]).snapshotDirectory == nil)
    }
}
