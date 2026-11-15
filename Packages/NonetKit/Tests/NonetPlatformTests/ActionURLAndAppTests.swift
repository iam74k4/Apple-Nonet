import Foundation
@testable import NonetPlatform
import Testing

@Suite("URL の補い方")
struct ActionURLTests {
    @Test("スキームが無ければ https を付ける", arguments: [
        ("example.com", "https://example.com"),
        ("  example.com/path?q=1  ", "https://example.com/path?q=1"),
        ("www.apple.com/jp/", "https://www.apple.com/jp/"),
        ("example.com:8080/x", "https://example.com:8080/x"),
        ("github.com/user/repo#readme", "https://github.com/user/repo#readme"),
        ("//example.com/x", "https://example.com/x"),
    ])
    func addsHTTPS(input: String, expected: String) {
        #expect(URLNormalizer.normalize(input)?.absoluteString == expected)
    }

    @Test("localhost は http")
    func localhostUsesHTTP() {
        #expect(URLNormalizer.normalize("localhost:3000")?.absoluteString == "http://localhost:3000")
        #expect(URLNormalizer.normalize("127.0.0.1:8080/api")?.absoluteString == "http://127.0.0.1:8080/api")
        // IPv6 の手元のアドレス（[ ] の中の「:」はポートの区切りではない）
        #expect(URLNormalizer.normalize("[::1]:3000")?.absoluteString == "http://[::1]:3000")
        #expect(URLNormalizer.normalize("[::1]/api")?.absoluteString == "http://[::1]/api")
        #expect(URLNormalizer.normalize("LOCALHOST/x")?.absoluteString == "http://LOCALHOST/x")
    }

    @Test("スキームがあればそのまま", arguments: [
        "https://example.com/a",
        "http://example.com",
        "mailto:someone@example.com",
        "tel:0312345678",
        "x-apple.systempreferences:com.apple.preference.security",
        "shortcuts://run-shortcut?name=Test",
        "slack://open",
        "file:///Applications/",
    ])
    func keepsSchemes(input: String) {
        #expect(URLNormalizer.normalize(input)?.absoluteString == input)
    }

    @Test("日本語やスペースは符号化する")
    func encodesCharacters() throws {
        let url = try #require(URLNormalizer.normalize("example.com/検索 結果?q=テスト"))
        #expect(url.host() == "example.com")
        #expect(url.absoluteString.hasPrefix("https://example.com/"))
        #expect(!url.absoluteString.contains(" "))
        let idn = try #require(URLNormalizer.normalize("日本語.jp"))
        #expect(idn.scheme == "https")
    }

    @Test("/ や ~ で始まればファイル")
    func filePaths() {
        #expect(URLNormalizer.normalize("/Applications")?.isFileURL == true)
        #expect(URLNormalizer.normalize("/Applications")?.path == "/Applications")
        let home = URLNormalizer.normalize("~/Documents")
        #expect(home?.isFileURL == true)
        #expect(home?.path.hasPrefix("/") == true)
        #expect(home?.path.hasSuffix("/Documents") == true)
    }

    @Test("開けない形は nil", arguments: ["", "   ", "https://", "http:// example.com", "not a url", "https://exa mple.com"])
    func rejectsInvalid(input: String) {
        #expect(URLNormalizer.normalize(input) == nil)
    }

    @Test("スキームの見分け方")
    func schemeDetection() {
        #expect(URLNormalizer.hasScheme("https://a"))
        #expect(URLNormalizer.hasScheme("mailto:a@b.c"))
        #expect(URLNormalizer.hasScheme("x-apple.systempreferences:abc"))
        #expect(URLNormalizer.hasScheme("tel:0312345678"))
        #expect(!URLNormalizer.hasScheme("example.com"))
        #expect(!URLNormalizer.hasScheme("example.com:443"))
        #expect(!URLNormalizer.hasScheme("localhost:3000"))
        #expect(!URLNormalizer.hasScheme("1http://x"))
        #expect(!URLNormalizer.hasScheme("日本:abc"))
    }
}

@Suite("アプリ起動")
struct ActionAppLauncherTests {
    @Test("隠すのは hideIfFrontmost で、起動中かつ前面のときだけ")
    func plan() {
        #expect(AppLauncher.plan(hideIfFrontmost: true, isRunning: true, isFrontmost: true) == .hide)
        #expect(AppLauncher.plan(hideIfFrontmost: true, isRunning: true, isFrontmost: false) == .open)
        #expect(AppLauncher.plan(hideIfFrontmost: true, isRunning: false, isFrontmost: false) == .open)
        #expect(AppLauncher.plan(hideIfFrontmost: false, isRunning: true, isFrontmost: true) == .open)
    }
}
