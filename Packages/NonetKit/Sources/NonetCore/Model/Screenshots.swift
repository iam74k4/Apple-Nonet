// 担当: core-model
// 最近のスクリーンショットを探す（「最近のスクショ」のトレイ。docs/architecture.md §6「最近のスクショ」）。
// 画面（NonetUI）が呼ぶ。ファイルの一覧と印を読むだけで、中身は読まない
import Darwin
import Foundation

/// 見つけたスクリーンショット1枚
public struct ScreenshotItem: Equatable, Sendable, Identifiable {
    public var url: URL
    /// 撮った時刻（ファイルを作った時刻。読めなければ変更した時刻）
    public var date: Date

    public var id: URL { url }

    public init(url: URL, date: Date) {
        self.url = url
        self.date = date
    }
}

/// 探した結果
public enum ScreenshotListing: Equatable, Sendable {
    /// 新しい順（空なら、保存先にスクリーンショットが無い）
    case found([ScreenshotItem], folder: URL)
    /// 保存先のフォルダを読む許可が無い（システム設定 › プライバシーとセキュリティ › ファイルとフォルダ）
    case notPermitted(folder: URL)
    /// 保存先のフォルダが無い
    case missingFolder(URL)

    public var folder: URL {
        switch self {
        case .found(_, let folder), .notPermitted(let folder), .missingFolder(let folder): folder
        }
    }
}

public enum ScreenshotFolder {
    /// macOS のスクリーンショットの設定（⇧⌘5 の「オプション」の保存先は location、ファイル名の頭は name）
    public static let defaultsDomain = "com.apple.screencapture"
    /// トレイに並べる数
    public static let trayLimit = 5
    /// macOS が撮ったスクリーンショットに付ける印（拡張属性。Spotlight の kMDItemIsScreenCapture）
    static let screenCaptureAttribute = "com.apple.metadata:kMDItemIsScreenCapture"
    /// 画像として並べる拡張子（収録した動画 .mov は並べない）
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tif", "tiff", "gif", "bmp"]
    /// ファイル名の頭（name を変えていないときの既定。macOS の言語で変わる。印が無いファイルを見分けるのに使う）
    public static let defaultNamePrefixes = ["Screenshot", "Screen Shot", "スクリーンショット"]

    /// 保存先。設定が無い・空・「クリップボード」（場所ではない）ならデスクトップ。~ はホームに置き換える
    public static func location(defaults: UserDefaults? = UserDefaults(suiteName: defaultsDomain), home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        let desktop = home.appending(path: "Desktop", directoryHint: .isDirectory)
        guard let raw = defaults?.string(forKey: "location")?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return desktop
        }
        let expanded: String
        if raw == "~" {
            expanded = home.path(percentEncoded: false)
        } else if raw.hasPrefix("~/") {
            expanded = home.appending(path: String(raw.dropFirst(2))).path(percentEncoded: false)
        } else {
            expanded = raw
        }
        guard expanded.hasPrefix("/") else { return desktop }
        return URL(filePath: expanded, directoryHint: .isDirectory)
    }

    /// ファイル名の頭として見分けに使うもの（設定の name があれば、それも）
    public static func namePrefixes(defaults: UserDefaults? = UserDefaults(suiteName: defaultsDomain)) -> [String] {
        var prefixes = defaultNamePrefixes
        if let custom = defaults?.string(forKey: "name")?.trimmingCharacters(in: .whitespaces), !custom.isEmpty, !prefixes.contains(custom) {
            prefixes.insert(custom, at: 0)
        }
        return prefixes
    }

    /// 保存先の最近のスクリーンショットを新しい順に limit 枚まで。
    /// スクリーンショットとみなすのは、画像の拡張子で、macOS の印（isScreenCapture）があるか、ファイル名が namePrefixes で始まるもの。
    /// 隠しファイルと、書き終わっていない一時ファイル（名前が . で始まる）は外す
    public static func recent(
        in folder: URL,
        limit: Int = trayLimit,
        namePrefixes: [String] = defaultNamePrefixes,
        fileManager: FileManager = .default,
        isScreenCapture: (URL) -> Bool = hasScreenCaptureMark
    ) -> ScreenshotListing {
        let keys: [URLResourceKey] = [.isRegularFileKey, .creationDateKey, .contentModificationDateKey]
        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        } catch {
            return listing(for: error, folder: folder, fileManager: fileManager)
        }
        var items: [ScreenshotItem] = []
        for url in contents {
            guard imageExtensions.contains(url.pathExtension.lowercased()) else { continue }
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile ?? false else { continue }
            let name = url.lastPathComponent
            guard isScreenCapture(url) || namePrefixes.contains(where: { name.hasPrefix($0) }) else { continue }
            let date = values?.creationDate ?? values?.contentModificationDate ?? .distantPast
            items.append(ScreenshotItem(url: url, date: date))
        }
        items.sort { $0.date != $1.date ? $0.date > $1.date : $0.url.lastPathComponent > $1.url.lastPathComponent }
        return .found(Array(items.prefix(max(limit, 0))), folder: folder)
    }

    /// 読めなかった理由。許可が無い（ファイルとフォルダの許可を拒んだ）か、フォルダが無いか
    static func listing(for error: any Error, folder: URL, fileManager: FileManager) -> ScreenshotListing {
        let nsError = error as NSError
        let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        let posix = [nsError, underlying].compactMap { $0 }.first { $0.domain == NSPOSIXErrorDomain }?.code
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileReadNoPermissionError || posix == Int(EPERM) || posix == Int(EACCES) {
            return .notPermitted(folder: folder)
        }
        var isDirectory: ObjCBool = false
        if !fileManager.fileExists(atPath: folder.path(percentEncoded: false), isDirectory: &isDirectory) || !isDirectory.boolValue {
            return .missingFolder(folder)
        }
        return .notPermitted(folder: folder)
    }

    /// macOS のスクリーンショットの印があるか（拡張属性を読むだけで、ファイルの中身は読まない）
    public static func hasScreenCaptureMark(_ url: URL) -> Bool {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return false }
            return getxattr(path, screenCaptureAttribute, nil, 0, 0, XATTR_NOFOLLOW) >= 0
        }
    }
}
