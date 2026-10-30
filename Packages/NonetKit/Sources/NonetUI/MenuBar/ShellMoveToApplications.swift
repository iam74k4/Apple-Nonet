// 担当: ui-shell
// ディスクイメージやダウンロードしたままの場所（App Translocation）から開かれたときに、アプリケーションフォルダへ移して開き直す。
// そのままだと Sparkle がアップデートを入れられず、アプリケーションフォルダにも入れると2つ動いてしまう
import AppKit
import os

private let logger = Logger(subsystem: "com.iam74k4.Nonet", category: "ui-shell")

/// アプリがどこから開かれたか
public enum ShellInstallLocation: Equatable, Sendable {
    /// そのまま使ってよい
    case installed
    /// App Translocation か、読み取り専用のディスクイメージ。Sparkle も同じ条件でアップデートを止める
    case temporary

    /// isTranslocated は SecTranslocateIsTranslocatedURL の答え。isReadOnlyVolume はアプリのあるボリュームが読み取り専用か
    public static func classify(bundlePath: String, isTranslocated: Bool, isReadOnlyVolume: Bool) -> ShellInstallLocation {
        if isTranslocated || bundlePath.contains("/AppTranslocation/") {
            return .temporary
        }
        // 外付けのディスクに自分で置いたもの（書き込める）はそのまま使う
        if bundlePath.hasPrefix("/Volumes/"), isReadOnlyVolume {
            return .temporary
        }
        return .installed
    }

    /// 今動いているアプリの場所
    public static func current(bundleURL: URL) -> ShellInstallLocation {
        let readOnly = (try? bundleURL.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly ?? false
        return classify(bundlePath: bundleURL.path, isTranslocated: isTranslocated(bundleURL), isReadOnlyVolume: readOnly)
    }

    /// Security.framework の SecTranslocateIsTranslocatedURL（ヘッダーが公開されていないので dlsym で引く）
    static func isTranslocated(_ url: URL) -> Bool {
        typealias IsTranslocated = @convention(c) (CFURL, UnsafeMutablePointer<Bool>, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> DarwinBoolean
        guard let handle = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_NOW),
              let symbol = dlsym(handle, "SecTranslocateIsTranslocatedURL") else {
            return false
        }
        let function = unsafeBitCast(symbol, to: IsTranslocated.self)
        var translocated = false
        guard function(url as CFURL, &translocated, nil).boolValue else { return false }
        return translocated
    }
}

/// アプリケーションフォルダへ移して開き直す
@MainActor
public enum ShellMoveToApplications {
    enum Plan: Equatable {
        /// そのまま写す
        case copy
        /// すでにあるものを置き換えてよいか尋ねてから写す
        case confirmReplace
        /// アプリケーションフォルダに書き込めないので、自分で移す方法を伝える
        case explain
    }

    static let applicationsDirectory = URL(fileURLWithPath: "/Applications", isDirectory: true)

    /// 移して開き直すことにしたら true。呼んだ側はそのまま終わる（開き直した方は、このプロセスが終わるのを待ってから起動する）
    public static func offerIfNeeded(bundle: Bundle = .main) -> Bool {
        let source = bundle.bundleURL
        guard ShellInstallLocation.current(bundleURL: source) == .temporary else { return false }
        logger.notice("一時的な場所から開かれています: \(source.path, privacy: .private)")
        NSApplication.shared.activate()
        guard ask(
            String(localized: "Nonet をアプリケーションフォルダに移しますか？", bundle: .module),
            String(localized: "ディスクイメージやダウンロードしたままの場所から開いているため、アップデートを入れられません。アプリケーションフォルダに移して開き直します。", bundle: .module),
            buttons: [
                String(localized: "アプリケーションフォルダに移す", bundle: .module),
                String(localized: "今は移さない", bundle: .module),
            ]
        ) else { return false }

        let destination = destination(for: source, in: applicationsDirectory)
        let fileManager = FileManager.default
        switch plan(
            destinationExists: fileManager.fileExists(atPath: destination.path),
            applicationsWritable: fileManager.isWritableFile(atPath: applicationsDirectory.path)
        ) {
        case .explain:
            explainManualMove()
            return false
        case .confirmReplace:
            guard ask(
                String(localized: "アプリケーションフォルダの Nonet を置き換えますか？", bundle: .module),
                String(localized: "アプリケーションフォルダにある Nonet（\(versionText(of: destination))）をゴミ箱に入れ、この Nonet（\(versionText(of: source))）に置き換えます。", bundle: .module),
                buttons: [String(localized: "置き換える", bundle: .module), String(localized: "キャンセル", bundle: .module)]
            ) else { return false }
        case .copy:
            break
        }

        do {
            try install(from: source, to: destination) { existing in
                try FileManager.default.trashItem(at: existing, resultingItemURL: nil)
            }
            try relaunch(destination)
            logger.info("アプリケーションフォルダに移したので開き直す")
            return true
        } catch {
            logger.error("アプリケーションフォルダに移せません: \(error.localizedDescription, privacy: .public)")
            explainManualMove()
            return false
        }
    }

    // MARK: - 決め方と写し方（テストする）

    static func destination(for source: URL, in applications: URL) -> URL {
        applications.appendingPathComponent(source.lastPathComponent, isDirectory: true)
    }

    static func plan(destinationExists: Bool, applicationsWritable: Bool) -> Plan {
        guard applicationsWritable else { return .explain }
        return destinationExists ? .confirmReplace : .copy
    }

    /// 同じフォルダの一時的な名前に写してから入れ替える。写せなかったときは、すでにあったものを残す
    static func install(from source: URL, to destination: URL, removeExisting: (URL) throws -> Void) throws {
        let fileManager = FileManager.default
        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.deletingPathExtension().lastPathComponent)-\(UUID().uuidString).\(destination.pathExtension)", isDirectory: true)
        try fileManager.copyItem(at: source, to: staging)
        do {
            removeQuarantine(at: staging)
            if fileManager.fileExists(atPath: destination.path) {
                try removeExisting(destination)
            }
            try fileManager.moveItem(at: staging, to: destination)
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }

    /// ダウンロードした印（com.apple.quarantine）を外す。残すと、移した先から開いても App Translocation でまた別の場所から開かれる。
    /// このアプリはすでに Gatekeeper の確認を通って動いている（Finder で移したときと同じ扱いにする）
    static func removeQuarantine(at url: URL) {
        var paths = [url.path]
        if let enumerator = FileManager.default.enumerator(atPath: url.path) {
            for case let relative as String in enumerator {
                paths.append(url.appendingPathComponent(relative).path)
            }
        }
        for path in paths {
            removexattr(path, "com.apple.quarantine", XATTR_NOFOLLOW)
        }
    }

    /// このプロセスが終わるのを待ってから開く（先に開くと、同じ Nonet が動いているとみなされる）
    static func relaunchArguments(processID: Int32, appPath: String) -> [String] {
        [
            "-c",
            "while /bin/kill -0 \(processID) >/dev/null 2>&1; do /bin/sleep 0.1; done; /usr/bin/open \"$1\"",
            "nonet-relaunch",
            appPath,
        ]
    }

    static func versionText(of bundleURL: URL) -> String {
        let info = Bundle(url: bundleURL)?.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        guard let build = info?["CFBundleVersion"] as? String, build != version else { return version }
        return "\(version) (\(build))"
    }

    // MARK: - 画面

    private static func relaunch(_ app: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = relaunchArguments(processID: ProcessInfo.processInfo.processIdentifier, appPath: app.path)
        try process.run()
    }

    private static func explainManualMove() {
        _ = ask(
            String(localized: "アプリケーションフォルダに移せませんでした", bundle: .module),
            String(localized: "Finder で Nonet をアプリケーションフォルダにドラッグしてから、そこから開いてください。", bundle: .module),
            buttons: [String(localized: "OK", bundle: .module)]
        )
    }

    /// 最初のボタンなら true
    private static func ask(_ message: String, _ information: String, buttons: [String]) -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = information
        for title in buttons {
            alert.addButton(withTitle: title)
        }
        NSApplication.shared.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }
}
