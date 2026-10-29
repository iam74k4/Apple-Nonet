// 担当: keys-license（公開 API は契約）
import Foundation

/// スクリプトや AI アクションに渡す、実行時の前面アプリの情報
public struct ScriptContextInfo: Equatable, Sendable {
    public var app: AppReference?
    /// 前面ウィンドウの書類（Xcode なら .xcodeproj / .xcworkspace）
    public var documentPath: String?
    /// ブラウザで表示中のページ
    public var browserURL: String?
    public var selectedText: String?

    public init(app: AppReference? = nil, documentPath: String? = nil, browserURL: String? = nil, selectedText: String? = nil) {
        self.app = app
        self.documentPath = documentPath
        self.browserURL = browserURL
        self.selectedText = selectedText
    }
}

public enum ScriptEnvironment {
    /// 1つの値の上限（UTF-8 のバイト数）。環境変数と引数の合計が ARG_MAX（1 MB）を超えるとプロセスを起動できないため、超えた分は切り捨てる
    public static let maximumValueLength = 128 * 1024

    /// プロジェクトとみなすフォルダの印
    static let projectMarkers = [".git", "Package.swift"]
    /// それ自体がプロジェクトの書類になるバンドル。親のフォルダをプロジェクトとする
    static let projectBundleExtensions = [".xcodeproj", ".xcworkspace", ".playground"]
    /// ちょうど「.swiftpm」ならパッケージの中に SwiftPM / Xcode が作るフォルダ（親がパッケージ）。
    /// 「Name.swiftpm」は Swift Playgrounds のアプリで、Package.swift を含むパッケージそのもの
    static let swiftPackageExtension = ".swiftpm"

    /// スクリプトに渡す環境変数。値の無いものは含めない。
    /// NONET_APP_BUNDLE_ID, NONET_APP_NAME, NONET_DOCUMENT_PATH, NONET_PROJECT_DIR, NONET_BROWSER_URL, NONET_SELECTED_TEXT,
    /// それと PROJECT_DIR（NONET_PROJECT_DIR と同じ。モックの `cd $PROJECT_DIR` 用）
    public static func variables(for info: ScriptContextInfo, projectDirectory: String?) -> [String: String] {
        var variables: [String: String] = [:]
        func set(_ name: String, _ value: String?) {
            if let value = sanitized(value) {
                variables[name] = value
            }
        }
        set("NONET_APP_BUNDLE_ID", info.app?.bundleID)
        set("NONET_APP_NAME", info.app?.name)
        set("NONET_DOCUMENT_PATH", info.documentPath.map(normalizedPath))
        set("NONET_BROWSER_URL", info.browserURL)
        set("NONET_SELECTED_TEXT", info.selectedText)
        let project = projectDirectory.map(normalizedPath)
        set("NONET_PROJECT_DIR", project)
        set("PROJECT_DIR", project)
        return variables
    }

    /// 書類の場所からプロジェクトのフォルダを決める。
    /// .xcodeproj / .xcworkspace / .playground とパッケージの中の .swiftpm はその親、Swift Playgrounds の Name.swiftpm はそれ自体、
    /// ファイルは上にたどって .git か Package.swift のあるフォルダ、見つからなければファイルのあるフォルダ
    public static func projectDirectory(forDocumentPath path: String, fileExists: (String) -> Bool) -> String {
        projectDirectory(forDocumentPath: path, homeDirectory: NSHomeDirectory(), fileExists: fileExists)
    }

    /// homeDirectory より上（とルート）はプロジェクトとみなさない。ホームの dotfiles の .git を拾わないため
    /// 空のパスには空を返す
    public static func projectDirectory(forDocumentPath path: String, homeDirectory: String, fileExists: (String) -> Bool) -> String {
        let normalized = normalizedPath(path)
        guard !normalized.isEmpty else { return "" }
        let document = PathComponents(normalized)
        // 中の書類（App.xcodeproj/project.xcworkspace や .swiftpm/xcode/package.xcworkspace）でも、いちばん外側のバンドルで決める
        for (index, part) in document.parts.enumerated() {
            if isPackageBundle(part) {
                return document.path(prefixCount: index + 1)
            }
            if isProjectBundle(part) {
                return document.path(prefixCount: index)
            }
        }
        let home = normalizedPath(homeDirectory)
        // 書類そのものがフォルダのこともあるので、書類の場所から調べる
        for count in stride(from: document.parts.count, through: 1, by: -1) {
            let directory = document.path(prefixCount: count)
            if directory == home {
                break
            }
            if projectMarkers.contains(where: { fileExists(directory + "/" + $0) }) {
                return directory
            }
        }
        return document.path(prefixCount: max(document.parts.count - 1, 0))
    }

    // MARK: - 内部

    /// file:// の URL をパスにし、末尾や重複した「/」と「.」「..」を整える。「~」は展開しない。空なら空のまま
    static func normalizedPath(_ path: String) -> String {
        guard !path.isEmpty else { return "" }
        var path = path
        if path.lowercased().hasPrefix("file://") {
            path = URL(string: path)?.path(percentEncoded: false)
                ?? String(path.dropFirst("file://".count)).removingPercentEncoding
                ?? path
        }
        return PathComponents(path).path(prefixCount: nil)
    }

    /// 親のフォルダをプロジェクトとするバンドル（パッケージの中の .swiftpm も含む）
    static func isProjectBundle(_ name: String) -> Bool {
        let lowercased = name.lowercased()
        return lowercased == swiftPackageExtension || projectBundleExtensions.contains { lowercased.hasSuffix($0) }
    }

    /// それ自体がプロジェクトのフォルダになる Name.swiftpm
    static func isPackageBundle(_ name: String) -> Bool {
        let lowercased = name.lowercased()
        return lowercased.hasSuffix(swiftPackageExtension) && lowercased != swiftPackageExtension
    }

    /// NUL を取り除き、長すぎる値を切り詰める。空なら nil
    static func sanitized(_ value: String?) -> String? {
        guard var value, !value.isEmpty else { return nil }
        if value.contains("\0") {
            value.removeAll { $0 == "\0" }
        }
        if value.utf8.count > maximumValueLength {
            var truncated = ""
            var length = 0
            for character in value {
                length += character.utf8.count
                if length > maximumValueLength {
                    break
                }
                truncated.append(character)
            }
            value = truncated
        }
        return value.isEmpty ? nil : value
    }
}

/// パスを「/」で分けたもの
private struct PathComponents {
    var isAbsolute: Bool
    var parts: [String]

    init(_ path: String) {
        isAbsolute = path.hasPrefix("/")
        var parts: [String] = []
        for part in path.split(separator: "/") where part != "." {
            if part == "..", let last = parts.last, last != ".." {
                parts.removeLast()
            } else if part == ".." && isAbsolute {
                // ルートより上には行かない
                continue
            } else {
                parts.append(String(part))
            }
        }
        self.parts = parts
    }

    /// 先頭から prefixCount 個（nil ならすべて）をつないだパス
    func path(prefixCount: Int?) -> String {
        let joined = parts.prefix(prefixCount ?? parts.count).joined(separator: "/")
        if isAbsolute {
            return "/" + joined
        }
        return joined.isEmpty ? "." : joined
    }
}
