import Darwin
import Foundation
import NonetCore
import NonetPlatform
import NonetUI

/// `Nonet --self-check`: 画面を出さず、イベントタップも始めずに、動く状態かを確かめて JSON を1行出す。
/// 成功なら 0、失敗なら 1 を返す
@MainActor
enum SelfCheck {
    static func run() -> Int32 {
        let license = LicenseManager(
            verifier: AppInfo.licensePublicKey.flatMap { try? LicenseVerifier(publicKeyBase64: $0) },
            storage: ReadOnlyLicenseStorage(base: UserDefaultsLicenseStorage())
        )
        let report = ShellSelfCheck.run(
            version: AppInfo.fullVersion,
            permissions: SystemPermissions(),
            installedApps: WorkspaceInstalledApps(),
            isJISKeyboard: KeyboardLayout.isJIS,
            multitouch: MultitouchProbe.check(),
            license: license
        )
        var output: Data
        do {
            output = try report.jsonData()
        } catch {
            output = Data(#"{"ok":false,"failures":["json"]}"#.utf8)
        }
        output.append(0x0A)
        FileHandle.standardOutput.write(output)
        return report.isSuccess ? 0 : 1
    }
}

/// 試用の記録を読むだけで書かない（確認のために試用を始めたり、時間を数えたりしない）
private final class ReadOnlyLicenseStorage: LicenseStorage {
    private let base: any LicenseStorage

    init(base: any LicenseStorage) {
        self.base = base
    }

    var trialStartDate: Date? {
        get { base.trialStartDate }
        set {}
    }

    var licenseKey: String? {
        get { base.licenseKey }
        set {}
    }

    var trialLastSeenDate: Date? {
        get { base.trialLastSeenDate }
        set {}
    }

    var trialUsedTime: TimeInterval? {
        get { base.trialUsedTime }
        set {}
    }
}

/// MultitouchSupport.framework を読めるか、デバイスがいくつあるかを、デバイスを開始せずに調べる
@MainActor
enum MultitouchProbe {
    private static let frameworkPath = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"

    static func check() -> ShellSelfCheck.Multitouch {
        guard let handle = dlopen(frameworkPath, RTLD_NOW) else {
            let reason = dlerror().map { String(cString: $0) } ?? "dlopen failed"
            return ShellSelfCheck.Multitouch(loaded: false, deviceCount: 0, trackpadAvailable: false, error: reason)
        }
        // CMultitouch も同じフレームワークを読むので閉じない
        guard let symbol = dlsym(handle, "MTDeviceCreateList") else {
            return ShellSelfCheck.Multitouch(loaded: false, deviceCount: 0, trackpadAvailable: false, error: "MTDeviceCreateList not found")
        }
        typealias CreateList = @convention(c) () -> Unmanaged<CFMutableArray>?
        let createList = unsafeBitCast(symbol, to: CreateList.self)
        // 呼ぶたびに新しい配列（+1）を返す
        let count = createList().map { CFArrayGetCount($0.takeRetainedValue()) } ?? 0
        return ShellSelfCheck.Multitouch(
            loaded: true,
            deviceCount: count,
            trackpadAvailable: MultitouchTouchSource().isAvailable
        )
    }
}
