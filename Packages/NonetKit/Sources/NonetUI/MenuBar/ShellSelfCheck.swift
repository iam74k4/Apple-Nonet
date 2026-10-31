// 担当: ui-shell
// `Nonet --self-check` の中身。画面もイベントタップも使わずに、配布したアプリが動く状態かを確かめて JSON で出す。
// App から本物のサービスを渡して使う。テストできるように NonetUI に置く
import Foundation
import NonetCore

public enum ShellSelfCheck {
    /// MultitouchSupport を読めたか
    public struct Multitouch: Equatable, Sendable {
        public var loaded: Bool
        /// MultitouchSupport が見つけたデバイスの数（トラックパッド以外を含むことがある）
        public var deviceCount: Int
        /// 使えるトラックパッドがある
        public var trackpadAvailable: Bool
        public var error: String?

        public init(loaded: Bool, deviceCount: Int, trackpadAvailable: Bool, error: String? = nil) {
            self.loaded = loaded
            self.deviceCount = deviceCount
            self.trackpadAvailable = trackpadAvailable
            self.error = error
        }
    }

    public struct Report: Equatable, Sendable {
        public var version: String
        public var presetCount: Int
        public var launcherCandidateCount: Int
        public var installedLauncherCandidateCount: Int
        /// 設定の保存と読み直し。成功なら nil、失敗なら理由
        public var configurationRoundTripError: String?
        public var multitouch: Multitouch
        public var accessibilityGranted: Bool
        public var entitlement: Entitlement

        public init(
            version: String,
            presetCount: Int,
            launcherCandidateCount: Int,
            installedLauncherCandidateCount: Int,
            configurationRoundTripError: String?,
            multitouch: Multitouch,
            accessibilityGranted: Bool,
            entitlement: Entitlement
        ) {
            self.version = version
            self.presetCount = presetCount
            self.launcherCandidateCount = launcherCandidateCount
            self.installedLauncherCandidateCount = installedLauncherCandidateCount
            self.configurationRoundTripError = configurationRoundTripError
            self.multitouch = multitouch
            self.accessibilityGranted = accessibilityGranted
            self.entitlement = entitlement
        }

        /// 失敗とみなすもの。権限・トラックパッドの有無・試用の状態は Mac によるので失敗にしない
        public var failures: [String] {
            var failures: [String] = []
            if version.isEmpty || version == "?" { failures.append("version") }
            if presetCount == 0 { failures.append("presets") }
            if launcherCandidateCount == 0 { failures.append("launcherCandidates") }
            if configurationRoundTripError != nil { failures.append("configurationRoundTrip") }
            if !multitouch.loaded { failures.append("multitouch") }
            return failures
        }

        public var isSuccess: Bool { failures.isEmpty }

        public var jsonObject: [String: Any] {
            var roundTrip: [String: Any] = ["ok": configurationRoundTripError == nil]
            roundTrip["error"] = configurationRoundTripError
            var multitouchObject: [String: Any] = [
                "loaded": multitouch.loaded,
                "devices": multitouch.deviceCount,
                "trackpadAvailable": multitouch.trackpadAvailable,
            ]
            multitouchObject["error"] = multitouch.error
            return [
                "ok": isSuccess,
                "failures": failures,
                "version": version,
                "presets": presetCount,
                "launcherCandidates": launcherCandidateCount,
                "installedLauncherCandidates": installedLauncherCandidateCount,
                "configurationRoundTrip": roundTrip,
                "multitouch": multitouchObject,
                "accessibilityGranted": accessibilityGranted,
                "license": Self.licenseObject(entitlement),
            ]
        }

        /// 1行の JSON（キーは並べ替える）
        public func jsonData() throws -> Data {
            try JSONSerialization.data(withJSONObject: jsonObject, options: [.sortedKeys, .withoutEscapingSlashes])
        }

        /// 購入者の名前などは出さない
        static func licenseObject(_ entitlement: Entitlement) -> [String: Any] {
            switch entitlement {
            case .trial(let daysLeft): ["state": "trial", "daysLeft": daysLeft]
            case .licensed: ["state": "licensed"]
            case .expired: ["state": "expired"]
            }
        }
    }

    /// 自己診断で使う試用の記録。本物の記録から読んだ値をメモリに写して使い、どこにも書かない
    /// （LicenseManager が試用を数えて書くのも、このメモリの中だけ）。
    /// アプリと同じく、UserDefaults と Application Support の写し（.install など）で食い違えば試用に厳しい方を使う。
    /// UserDefaultsLicenseStorage は食い違うと読むだけでもそろえるために書くので、UserDefaults は写しの無い置き方
    /// （supportDirectory: nil）で読み、写しのファイルはここで読むだけにする
    public final class LicenseSnapshot: LicenseStorage {
        /// 写しのファイルの名前（NonetCore の UserDefaultsLicenseStorage と同じ。テストで本物が書いたものを読めるか確かめる）
        static let startFileName = ".install"
        static let lastSeenFileName = ".install-seen"
        static let usedFileName = ".install-used"

        public var trialStartDate: Date?
        public var licenseKey: String?
        public var trialLastSeenDate: Date?
        public var trialUsedTime: TimeInterval?

        /// アプリが使う本物の記録（UserDefaults.standard と ~/Library/Application Support/Nonet）
        public convenience init() {
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("Nonet", isDirectory: true)
            self.init(defaults: .standard, supportDirectory: directory)
        }

        /// supportDirectory は写しのあるフォルダ。無ければ UserDefaults だけを読む
        public init(defaults: UserDefaults, supportDirectory: URL?) {
            let stored = UserDefaultsLicenseStorage(defaults: defaults, supportDirectory: nil)
            func mirrored(_ name: String) -> Double? {
                guard let url = supportDirectory?.appendingPathComponent(name, isDirectory: false),
                      let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8),
                      let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)), value.isFinite else {
                    return nil
                }
                return value
            }
            // 開始日と最後に数えた時刻は早い方、使った時間は長い方（アプリと同じ）
            trialStartDate = Self.stricter(stored.trialStartDate?.timeIntervalSinceReferenceDate, mirrored(Self.startFileName), keepsSmaller: true)
                .map(Date.init(timeIntervalSinceReferenceDate:))
            trialLastSeenDate = Self.stricter(stored.trialLastSeenDate?.timeIntervalSinceReferenceDate, mirrored(Self.lastSeenFileName), keepsSmaller: true)
                .map(Date.init(timeIntervalSinceReferenceDate:))
            trialUsedTime = Self.stricter(stored.trialUsedTime, mirrored(Self.usedFileName).flatMap { $0 >= 0 ? $0 : nil }, keepsSmaller: false)
            licenseKey = stored.licenseKey
        }

        static func stricter(_ stored: Double?, _ mirrored: Double?, keepsSmaller: Bool) -> Double? {
            let candidates = [stored, mirrored].compactMap { $0 }
            return keepsSmaller ? candidates.min() : candidates.max()
        }
    }

    /// 確かめて結果をまとめる。workDirectory の下に一時フォルダを作り、終わったら消す
    @MainActor
    public static func run(
        version: String,
        permissions: any PermissionsProviding,
        installedApps: any InstalledAppsProviding,
        multitouch: Multitouch,
        license: LicenseManager,
        workDirectory: URL = FileManager.default.temporaryDirectory
    ) -> Report {
        let candidates = PresetLibrary.launcherCandidates
        let directory = workDirectory.appendingPathComponent("nonet-self-check-\(UUID().uuidString)", isDirectory: true)
        let roundTripError = configurationRoundTrip(in: directory)
        try? FileManager.default.removeItem(at: directory)
        return Report(
            version: version,
            presetCount: PresetLibrary.apps.count,
            launcherCandidateCount: candidates.count,
            installedLauncherCandidateCount: candidates.filter { installedApps.isInstalled(bundleID: $0.bundleID) }.count,
            configurationRoundTripError: roundTripError,
            multitouch: multitouch,
            accessibilityGranted: permissions.isAccessibilityGranted,
            entitlement: license.entitlement
        )
    }

    /// プリセットをすべて入れた設定を directory に保存して読み直し、同じかを確かめる。成功なら nil
    public static func configurationRoundTrip(in directory: URL) -> String? {
        let configuration = NonetConfiguration.initial(
            appPresets: PresetLibrary.apps,
            installedBundleIDs: Set(PresetLibrary.launcherCandidates.map(\.bundleID))
        )
        let store = ConfigurationStore(directory: directory)
        do {
            try store.save(configuration)
            guard let loaded = try store.load() else {
                return "saved configuration was not found"
            }
            guard loaded == configuration else {
                return "reloaded configuration differs from the saved one"
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
