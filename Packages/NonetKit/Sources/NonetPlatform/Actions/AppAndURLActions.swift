// 担当: platform-actions
import AppKit
import NonetCore

/// URL アクションの文字列を開ける URL にする
enum URLNormalizer {
    /// スキームが無ければ https://（localhost だけは http://）を付ける。/ や ~ で始まればファイルの場所として扱う。
    /// 開けない形なら nil
    static func normalize(_ raw: String) -> URL? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        // "//example.com" はスキームを省いた URL
        if text.hasPrefix("//") {
            return normalize("https:" + text)
        }
        if text.hasPrefix("/") || text.hasPrefix("~") {
            return URL(fileURLWithPath: (text as NSString).expandingTildeInPath)
        }
        let candidate = hasScheme(text) ? text : defaultScheme(for: text) + "://" + text
        guard let url = URL(string: candidate), let scheme = url.scheme, !scheme.isEmpty else { return nil }
        if ["http", "https"].contains(scheme.lowercased()) {
            guard let host = url.host(percentEncoded: false), isValidHost(host) else { return nil }
        }
        return url
    }

    /// "mailto:" や "https://" はスキームあり。"example.com:8080" や "localhost:3000" のような「ホスト:ポート」は無し
    static func hasScheme(_ text: String) -> Bool {
        guard let colon = text.firstIndex(of: ":") else { return false }
        let scheme = text[..<colon]
        guard let first = scheme.unicodeScalars.first, first.isASCII, first.properties.isAlphabetic else { return false }
        let allowed = scheme.unicodeScalars.allSatisfy {
            $0.isASCII && ($0.properties.isAlphabetic || ("0" ... "9").contains($0) || "+-.".unicodeScalars.contains($0))
        }
        guard allowed else { return false }
        let rest = text[text.index(after: colon)...]
        if rest.hasPrefix("//") { return true }
        // ポート番号が続き、ホスト名らしい（ドットを含むか localhost）なら「ホスト:ポート」。"tel:0312…" はスキーム
        if let next = rest.unicodeScalars.first, ("0" ... "9").contains(next),
           scheme.contains(".") || scheme.lowercased() == "localhost" {
            return false
        }
        return true
    }

    /// 手元のサーバー（localhost・127.0.0.1・[::1]）は http、ほかは https。IPv6 の [ ] の中の「:」はポートの区切りではない
    private static func defaultScheme(for text: String) -> String {
        let host: String
        if text.hasPrefix("["), let close = text.firstIndex(of: "]") {
            host = String(text[...close])
        } else {
            host = String(text.prefix { !"/:?#".contains($0) })
        }
        return ["localhost", "127.0.0.1", "[::1]"].contains(host.lowercased()) ? "http" : "https"
    }

    private static func isValidHost(_ host: String) -> Bool {
        !host.isEmpty && !host.contains(where: \.isWhitespace)
    }

    @MainActor
    static func open(_ raw: String) async throws {
        guard let url = normalize(raw) else {
            throw NonetError.actionFailed(String(localized: "URL が正しくありません", bundle: .nonetActions))
        }
        do {
            _ = try await NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration())
        } catch {
            ActionLog.logger.error("URL を開けませんでした: \(error.localizedDescription)")
            throw NonetError.actionFailed(String(localized: "URL を開けませんでした", bundle: .nonetActions))
        }
    }
}

/// アプリ起動アクション
enum AppLauncher {
    enum Plan: Equatable {
        /// 前面にあるので隠す
        case hide
        /// 起動する、または前面に出す（Dock のアイコンを押したときと同じく、ウィンドウが無ければ開かせる）
        case open
    }

    static func plan(hideIfFrontmost: Bool, isRunning: Bool, isFrontmost: Bool) -> Plan {
        hideIfFrontmost && isRunning && isFrontmost ? .hide : .open
    }

    @MainActor
    static func launch(_ action: LaunchAppAction) async throws {
        let bundleID = action.app.bundleID
        let name = action.app.name.isEmpty ? bundleID : action.app.name
        guard !bundleID.isEmpty else { throw NonetError.appNotFound(name) }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first { !$0.isTerminated }
        let isFrontmost = running.map {
            $0.isActive || NSWorkspace.shared.frontmostApplication?.processIdentifier == $0.processIdentifier
        } ?? false

        switch plan(hideIfFrontmost: action.hideIfFrontmost, isRunning: running != nil, isFrontmost: isFrontmost) {
        case .hide:
            if running?.hide() != true {
                ActionLog.logger.notice("アプリを隠せませんでした")
            }
        case .open:
            guard let url = running?.bundleURL ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                if let running, running.activate() { return }
                throw NonetError.appNotFound(name)
            }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            do {
                _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            } catch {
                ActionLog.logger.error("アプリを開けませんでした: \(error.localizedDescription)")
                if let running {
                    running.unhide()
                    if running.activate() { return }
                }
                throw NonetError.actionFailed(String(localized: "\(name) を開けませんでした", bundle: .nonetActions))
            }
        }
    }
}
