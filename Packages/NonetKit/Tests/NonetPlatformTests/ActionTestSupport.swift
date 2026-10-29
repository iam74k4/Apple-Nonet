import Foundation

/// テストごとの一時フォルダ。終わったら消す
final class ActionTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("NonetActionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func subdirectory(_ name: String) throws -> URL {
        let directory = url.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// 利用者の ~/.zprofile などを読まないよう、HOME と ZDOTDIR をこのフォルダにした環境
    var isolatedEnvironment: [String: String] {
        [
            "HOME": url.path,
            "ZDOTDIR": url.path,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "LC_CTYPE": "UTF-8",
        ]
    }
}

/// シンボリックリンクを解いた実際の場所（`pwd -P` と同じ。/var は /private/var になる）
func actionRealPath(_ url: URL) -> String {
    guard let resolved = realpath(url.path, nil) else { return url.path }
    defer { free(resolved) }
    return String(cString: resolved)
}

/// 処理にかかった秒数
func actionElapsedSeconds(_ body: () async throws -> Void) async rethrows -> Double {
    let start = ContinuousClock.now
    try await body()
    let (seconds, attoseconds) = (ContinuousClock.now - start).components
    return Double(seconds) + Double(attoseconds) / 1e18
}

/// LMGetKbdType が返すキーボードの種類の例（KBGetLayoutType でそれぞれ ANSI / ISO / JIS）
enum ActionKeyboardType {
    static let ansi: UInt32 = 40
    static let iso: UInt32 = 41
    static let jis: UInt32 = 42
    static let all = [ansi, iso, jis]
}
