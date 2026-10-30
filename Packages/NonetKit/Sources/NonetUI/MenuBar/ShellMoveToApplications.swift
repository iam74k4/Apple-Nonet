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

    /// bundleURL のアプリの場所（自分のものも、ほかに動いている Nonet のものも）
    public static func of(bundleURL: URL) -> ShellInstallLocation {
        let readOnly = (try? bundleURL.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly ?? false
        return classify(bundlePath: bundleURL.path, isTranslocated: isTranslocated(bundleURL), isReadOnlyVolume: readOnly)
    }

    static func isTranslocated(_ url: URL) -> Bool {
        translocationStatus(url) ?? false
    }

    /// Security.framework の SecTranslocateIsTranslocatedURL（ヘッダーが公開されていないので dlsym で引く）の答え。
    /// 関数が見つからない・答えられなかったときは nil（そのときはパスの /AppTranslocation/ だけで見分ける）
    static func translocationStatus(_ url: URL) -> Bool? {
        typealias IsTranslocated = @convention(c) (CFURL, UnsafeMutablePointer<Bool>, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> DarwinBoolean
        guard let handle = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_NOW),
              let symbol = dlsym(handle, "SecTranslocateIsTranslocatedURL") else {
            return nil
        }
        let function = unsafeBitCast(symbol, to: IsTranslocated.self)
        var translocated = false
        guard function(url as CFURL, &translocated, nil).boolValue else { return nil }
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
        /// 移す先に書き込めないので、移すかを尋ねずに、自分で移す方法を伝える
        case explain
    }

    static let applicationsDirectory = URL(fileURLWithPath: "/Applications", isDirectory: true)

    /// 移して開き直すことにしたら true。呼んだ側はそのまま終わる（開き直した方は、このプロセスが終わるのを待ってから起動する）
    public static func offerIfNeeded(bundle: Bundle = .main) -> Bool {
        let source = bundle.bundleURL
        guard ShellInstallLocation.of(bundleURL: source) == .temporary else { return false }
        logger.notice("一時的な場所から開かれています: \(source.path, privacy: .private)")
        let fileManager = FileManager.default
        let directory = targetDirectory(
            isSystemWritable: fileManager.isWritableFile(atPath: applicationsDirectory.path),
            home: fileManager.homeDirectoryForCurrentUser
        )
        let destination = destination(for: source, in: directory)
        let plan = plan(
            destinationExists: fileManager.fileExists(atPath: destination.path),
            directoryWritable: isWritable(directory)
        )
        // 移せないと分かっているなら、移すかを尋ねてから失敗を伝えることはしない
        guard plan != .explain else {
            explainManualMove()
            return false
        }
        guard ask(
            String(localized: "Nonet をアプリケーションフォルダに移しますか？", bundle: .module),
            String(localized: "ディスクイメージやダウンロードしたままの場所から開いているため、アップデートを入れられません。アプリケーションフォルダに移して開き直します。", bundle: .module),
            buttons: [
                String(localized: "アプリケーションフォルダに移す", bundle: .module),
                String(localized: "今は移さない", bundle: .module),
            ]
        ) else { return false }

        if plan == .confirmReplace {
            guard ask(
                String(localized: "アプリケーションフォルダの Nonet を置き換えますか？", bundle: .module),
                String(localized: "アプリケーションフォルダにある Nonet（\(versionText(of: destination))）をゴミ箱に入れ、この Nonet（\(versionText(of: source))）に置き換えます。", bundle: .module),
                buttons: [String(localized: "置き換える", bundle: .module), String(localized: "キャンセル", bundle: .module)]
            ) else { return false }
        }

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try install(from: source, to: destination) { existing in
                var trashed: NSURL?
                try FileManager.default.trashItem(at: existing, resultingItemURL: &trashed)
                return trashed as URL?
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

    /// 移す先のフォルダ。/Applications に書き込めない（管理者でない）ときは、ホームの「アプリケーション」
    /// （Sparkle もそこならアップデートを入れられる）
    static func targetDirectory(isSystemWritable: Bool, home: URL) -> URL {
        isSystemWritable ? applicationsDirectory : home.appendingPathComponent("Applications", isDirectory: true)
    }

    /// directory に書き込めるか。まだ無ければ、作る場所に書き込めるか
    static func isWritable(_ directory: URL, fileManager: FileManager = .default) -> Bool {
        guard fileManager.fileExists(atPath: directory.path) else {
            return fileManager.isWritableFile(atPath: directory.deletingLastPathComponent().path)
        }
        return fileManager.isWritableFile(atPath: directory.path)
    }

    static func destination(for source: URL, in applications: URL) -> URL {
        applications.appendingPathComponent(source.lastPathComponent, isDirectory: true)
    }

    static func plan(destinationExists: Bool, directoryWritable: Bool) -> Plan {
        guard directoryWritable else { return .explain }
        return destinationExists ? .confirmReplace : .copy
    }

    /// 同じフォルダの一時的な名前に写してから入れ替える。すでにあったものは moveExistingAside で退け（ゴミ箱へ。退けた先を返す）、
    /// 入れ替えられなかったら元の場所に戻す。失敗したときは、写しかけの一時的なものも残さない
    static func install(
        from source: URL,
        to destination: URL,
        fileManager: FileManager = .default,
        moveExistingAside: (URL) throws -> URL?
    ) throws {
        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.deletingPathExtension().lastPathComponent)-\(UUID().uuidString).\(destination.pathExtension)", isDirectory: true)
        var movedAside: URL?
        do {
            try fileManager.copyItem(at: source, to: staging)
            removeQuarantine(at: staging)
            if fileManager.fileExists(atPath: destination.path) {
                movedAside = try moveExistingAside(destination)
            }
            try fileManager.moveItem(at: staging, to: destination)
        } catch {
            try? fileManager.removeItem(at: staging)
            if let movedAside, !fileManager.fileExists(atPath: destination.path) {
                do {
                    try fileManager.moveItem(at: movedAside, to: destination)
                } catch {
                    logger.error("ゴミ箱に入れた Nonet を戻せません: \(error.localizedDescription, privacy: .public)")
                }
            }
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
