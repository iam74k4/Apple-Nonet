import Foundation
import Testing
@testable import NonetCore

/// メモリ上のファイルと標準出力
private final class FakeToolEnvironment {
    struct File: Equatable {
        var contents: String
        var permissions: UInt16
    }

    var currentDirectory = "/work"
    var files: [String: File] = [:]
    var directories: Set<String> = ["/", "/work"]
    var output = ""
    var errorOutput = ""
    var now = Date(timeIntervalSince1970: 1_793_318_400.9)
    var nextID = "GENERATED-ID"

    var io: LicenseToolIO {
        LicenseToolIO(
            currentDirectory: { self.currentDirectory },
            fileExists: { self.files[$0] != nil || self.directories.contains($0) },
            readFile: { path in
                guard let file = self.files[path] else { throw CocoaError(.fileReadNoSuchFile) }
                return file.contents
            },
            createDirectory: { self.directories.insert($0) },
            createNewFile: { path, contents, permissions in
                guard self.files[path] == nil else { throw POSIXError(.EEXIST) }
                self.files[path] = File(contents: contents, permissions: permissions)
            },
            standardOutput: { self.output += $0 },
            standardError: { self.errorOutput += $0 },
            now: { self.now },
            makeLicenseID: { self.nextID }
        )
    }

    func run(_ arguments: [String]) -> Int32 {
        output = ""
        errorOutput = ""
        return LicenseTool.run(arguments, io: io)
    }
}

@Suite struct LicenseToolTests {
    private let environment = FakeToolEnvironment()

    private func issuedKey(_ output: String) throws -> String {
        try #require(output.split(separator: "\n").first.map(String.init))
    }

    private func installKeys() throws -> (privatePath: String, publicKey: String) {
        let keys = LicenseTestFixtures.keys
        environment.files["/keys/private"] = .init(contents: keys.privateKeyBase64 + "\n", permissions: 0o600)
        environment.files["/keys/public"] = .init(contents: keys.publicKeyBase64 + "\n", permissions: 0o644)
        return ("/keys/private", keys.publicKeyBase64)
    }

    // MARK: - 引数

    @Test func parsesCommands() throws {
        #expect(try LicenseTool.parse(["keygen", "--out", "dir"]) == .keygen(outputDirectory: "dir"))
        #expect(try LicenseTool.parse(["keygen", "--out=dir"]) == .keygen(outputDirectory: "dir"))
        #expect(try LicenseTool.parse(["issue", "--key", "k", "--name", "Taro Yamada"])
            == .issue(privateKeyPath: "k", licensee: "Taro Yamada", email: nil, edition: nil, licenseID: nil, publicKey: nil))
        #expect(try LicenseTool.parse(["issue", "--name=A", "--id", "X", "--edition", "pro", "--email", "a@b.c", "--key", "k", "--public", "PK"])
            == .issue(privateKeyPath: "k", licensee: "A", email: "a@b.c", edition: "pro", licenseID: "X", publicKey: "PK"))
        #expect(try LicenseTool.parse(["verify", "--public", "PK", "KEY"]) == .verify(publicKey: "PK", licenseKey: "KEY"))
        #expect(try LicenseTool.parse(["verify", "KEY", "--public", "PK"]) == .verify(publicKey: "PK", licenseKey: "KEY"))
        #expect(try LicenseTool.parse(["verify", "--public", "PK", "--", "--KEY"]) == .verify(publicKey: "PK", licenseKey: "--KEY"))
        #expect(try LicenseTool.parse(["issue", "--key", "k", "--name", "-dash"])
            == .issue(privateKeyPath: "k", licensee: "-dash", email: nil, edition: nil, licenseID: nil, publicKey: nil))
        for help in [["help"], ["-h"], ["--help"], ["issue", "--help"], ["keygen", "-h"]] {
            #expect(try LicenseTool.parse(help) == .help)
        }
    }

    @Test(arguments: [
        ([], "コマンドを指定してください"),
        (["bogus"], "不明なコマンドです: bogus"),
        (["keygen"], "--out を指定してください"),
        (["keygen", "--out"], "--out の値を指定してください"),
        (["keygen", "--out", "--force"], "--out の値を指定してください"),
        (["keygen", "--out", "a", "--out", "b"], "--out が2回指定されています"),
        (["keygen", "--out", ""], "--out が空です"),
        (["keygen", "--out= "], "--out が空です"),
        (["keygen", "--out", "a", "extra"], "keygen には余分な引数があります: extra"),
        (["keygen", "--force", "x", "--out", "a"], "不明なオプションです: --force"),
        (["issue", "--key", "k"], "--name を指定してください"),
        (["issue", "--name", "A"], "--key を指定してください"),
        (["verify", "--public", "PK"], "検証するライセンスキーを指定してください"),
        (["verify", "KEY"], "--public を指定してください"),
        (["verify", "--public", "PK", "A", "B"], "verify には余分な引数があります: B"),
    ] as [([String], String)])
    func reportsUsageErrors(arguments: [String], message: String) {
        #expect(throws: LicenseToolUsageError(message)) {
            try LicenseTool.parse(arguments)
        }
        #expect(environment.run(arguments) == LicenseTool.exitUsage)
        #expect(environment.errorOutput.contains(message))
        #expect(environment.errorOutput.contains("使い方:"))
        #expect(environment.output.isEmpty)
    }

    @Test func printsHelp() {
        #expect(environment.run(["help"]) == LicenseTool.exitSuccess)
        #expect(environment.output == LicenseTool.usage)
        for command in ["keygen", "issue", "verify"] {
            #expect(LicenseTool.usage.contains("nonet-license \(command)"))
        }
    }

    // MARK: - keygen

    @Test func keygenWritesBothKeys() throws {
        #expect(environment.run(["keygen", "--out", "/secure/keys"]) == LicenseTool.exitSuccess)
        let privateFile = try #require(environment.files["/secure/keys/nonet-license.private-key"])
        let publicFile = try #require(environment.files["/secure/keys/nonet-license.public-key"])
        #expect(privateFile.permissions == 0o600)
        #expect(publicFile.permissions == 0o644)
        #expect(environment.directories.contains("/secure/keys"))

        let publicKey = publicFile.contents.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(environment.output == publicKey + "\n")
        #expect(try LicenseSigner(privateKeyBase64: privateFile.contents).publicKeyBase64 == publicKey)
        #expect(environment.errorOutput.contains("git にコミットしないでください"))
        #expect(environment.errorOutput.contains("警告") == false)
    }

    @Test func keygenRefusesToOverwrite() throws {
        #expect(environment.run(["keygen", "--out", "/keys"]) == LicenseTool.exitSuccess)
        let before = environment.files
        #expect(environment.run(["keygen", "--out", "/keys"]) == LicenseTool.exitFailure)
        #expect(environment.files == before)
        #expect(environment.errorOutput.contains("上書きしません"))
        #expect(environment.output.isEmpty)

        // 片方だけあっても作らない
        environment.files["/other/nonet-license.public-key"] = .init(contents: "x", permissions: 0o644)
        #expect(environment.run(["keygen", "--out", "/other"]) == LicenseTool.exitFailure)
        #expect(environment.files["/other/nonet-license.private-key"] == nil)
    }

    @Test func keygenResolvesRelativePathsAndWarnsInsideARepository() {
        environment.currentDirectory = "/work/repo/sub"
        environment.directories.insert("/work/repo/.git")
        #expect(environment.run(["keygen", "--out", "../keys/"]) == LicenseTool.exitSuccess)
        #expect(environment.files["/work/repo/keys/nonet-license.private-key"] != nil)
        #expect(environment.errorOutput.contains("警告: 秘密鍵を git リポジトリ（/work/repo）の中に作りました"))
    }

    /// base64 が「//」を含む公開鍵（0xFF が続く）
    private static let slashedPublicKey = Data(repeating: 0xFF, count: 32).base64EncodedString()

    @Test func keygenSkipsPublicKeysThatXcconfigWouldTruncate() throws {
        #expect(Self.slashedPublicKey.contains("//"))
        let good = LicenseSigner.generateKeyPair()
        var candidates = [
            (privateKeyBase64: LicenseTestFixtures.otherKeys.privateKeyBase64, publicKeyBase64: Self.slashedPublicKey),
            good,
        ]
        var io = environment.io
        io.generateKeyPair = { candidates.removeFirst() }
        #expect(LicenseTool.run(["keygen", "--out", "/keys"], io: io) == LicenseTool.exitSuccess)
        #expect(candidates.isEmpty)
        #expect(environment.output == good.publicKeyBase64 + "\n")
        #expect(environment.files["/keys/nonet-license.public-key"]?.contents == good.publicKeyBase64 + "\n")
        #expect(environment.files["/keys/nonet-license.private-key"]?.contents == good.privateKeyBase64 + "\n")
    }

    @Test func keygenGivesUpIfEveryPublicKeyContainsDoubleSlash() {
        var io = environment.io
        io.generateKeyPair = { (LicenseTestFixtures.keys.privateKeyBase64, Self.slashedPublicKey) }
        #expect(LicenseTool.run(["keygen", "--out", "/keys"], io: io) == LicenseTool.exitFailure)
        #expect(environment.files.isEmpty)
        #expect(environment.output.isEmpty)
    }

    @Test func generatedPublicKeysNeverContainDoubleSlash() throws {
        // 本物の鍵の約1%が「//」を含むので、1000回で何度かは選び直しを通る
        for _ in 0..<1000 {
            let keys = try #require(LicenseTool.configSafeKeyPair(io: .live))
            #expect(!keys.publicKeyBase64.contains("//"))
            #expect(try LicenseSigner(privateKeyBase64: keys.privateKeyBase64).publicKeyBase64 == keys.publicKeyBase64)
        }
    }

    @Test func keygenReportsWriteFailures() {
        let failing = environment.io
        var io = failing
        io.createNewFile = { _, _, _ in throw POSIXError(.EACCES) }
        environment.output = ""
        let code = LicenseTool.run(["keygen", "--out", "/ro"], io: io)
        #expect(code == LicenseTool.exitFailure)
        #expect(environment.errorOutput.contains("鍵を保存できません"))
        #expect(environment.output.isEmpty)
    }

    // MARK: - issue

    @Test func issuesAVerifiableKey() throws {
        let keys = try installKeys()
        let code = environment.run(["issue", "--key", keys.privatePath, "--name", "  山田 太郎 ", "--email", "taro@example.com"])
        #expect(code == LicenseTool.exitSuccess)
        let key = try issuedKey(environment.output)
        let info = try LicenseVerifier(publicKeyBase64: keys.publicKey).verify(key)
        #expect(info == LicenseInfo(
            licenseID: "GENERATED-ID",
            licensee: "山田 太郎",
            email: "taro@example.com",
            edition: "standard",
            issuedAt: Date(timeIntervalSince1970: 1_793_318_400)
        ))
        #expect(environment.errorOutput.contains("発行しました"))
    }

    @Test func issueUsesGivenIDAndEdition() throws {
        let keys = try installKeys()
        #expect(environment.run(["issue", "--key", keys.privatePath, "--name", "A", "--id", "ORDER-42", "--edition", "family"]) == LicenseTool.exitSuccess)
        let info = try LicenseVerifier(publicKeyBase64: keys.publicKey).verify(try issuedKey(environment.output))
        #expect(info.licenseID == "ORDER-42")
        #expect(info.edition == "family")
        #expect(info.email == nil)
    }

    @Test(arguments: [
        ["--name", "   "],
        ["--name", "A", "--email", "not-an-email"],
        ["--name", "A", "--email", ""],
        ["--name", "A", "--email", "a b@c.d"],
        ["--name", "A", "--edition", " "],
        ["--name", "A", "--id", ""],
    ])
    func issueRejectsInvalidValues(extra: [String]) throws {
        let keys = try installKeys()
        #expect(environment.run(["issue", "--key", keys.privatePath] + extra) == LicenseTool.exitUsage)
        #expect(environment.output.isEmpty)
    }

    /// keygen と同じ名前で置く
    private func installStandardKeys(in directory: String = "/keys") -> (privatePath: String, publicPath: String) {
        let keys = LicenseTestFixtures.keys
        let privatePath = directory + "/" + LicenseTool.privateKeyFileName
        let publicPath = directory + "/" + LicenseTool.publicKeyFileName
        environment.files[privatePath] = .init(contents: keys.privateKeyBase64 + "\n", permissions: 0o600)
        environment.files[publicPath] = .init(contents: keys.publicKeyBase64 + "\n", permissions: 0o644)
        return (privatePath, publicPath)
    }

    @Test func issueChecksTheKeyAgainstThePublicKeyNextToIt() throws {
        let paths = installStandardKeys()
        #expect(environment.run(["issue", "--key", paths.privatePath, "--name", "A"]) == LicenseTool.exitSuccess)
        _ = try LicenseVerifier(publicKeyBase64: LicenseTestFixtures.keys.publicKeyBase64).verify(try issuedKey(environment.output))
        #expect(environment.errorOutput.contains("警告") == false)

        // 相対パスでも同じフォルダを探す
        environment.currentDirectory = "/keys"
        #expect(environment.run(["issue", "--key", LicenseTool.privateKeyFileName, "--name", "A"]) == LicenseTool.exitSuccess)
        #expect(environment.errorOutput.contains("警告") == false)
    }

    @Test func issueRefusesThePublicKeyFileAsThePrivateKey() {
        // 32 バイトなら何でも秘密鍵として読めるので、公開鍵のファイルを渡すと別の鍵で署名してしまう
        let paths = installStandardKeys()
        #expect(environment.run(["issue", "--key", paths.publicPath, "--name", "A"]) == LicenseTool.exitFailure)
        #expect(environment.output.isEmpty)
        #expect(environment.errorOutput.contains("秘密鍵と公開鍵が対応していません"))
    }

    @Test func issueRefusesAPrivateKeyThatDoesNotMatchThePublicKey() {
        let paths = installStandardKeys()
        environment.files["/other/key"] = .init(contents: LicenseTestFixtures.otherKeys.privateKeyBase64, permissions: 0o600)
        // --public（ファイルでも base64 でも）と合わない
        for publicKey in [paths.publicPath, LicenseTestFixtures.keys.publicKeyBase64] {
            #expect(environment.run(["issue", "--key", "/other/key", "--name", "A", "--public", publicKey]) == LicenseTool.exitFailure)
            #expect(environment.output.isEmpty)
            #expect(environment.errorOutput.contains("秘密鍵と公開鍵が対応していません"))
        }
        // 同じフォルダの公開鍵と合わない
        environment.files["/keys/nonet-license.private-key"] = .init(contents: LicenseTestFixtures.otherKeys.privateKeyBase64, permissions: 0o600)
        #expect(environment.run(["issue", "--key", paths.privatePath, "--name", "A"]) == LicenseTool.exitFailure)
        #expect(environment.output.isEmpty)
    }

    @Test func issueUsesTheGivenPublicKey() throws {
        let keys = try installKeys()
        for publicKey in ["/keys/public", keys.publicKey] {
            #expect(environment.run(["issue", "--key", keys.privatePath, "--name", "A", "--public", publicKey]) == LicenseTool.exitSuccess)
            #expect(environment.errorOutput.contains("警告") == false)
            _ = try LicenseVerifier(publicKeyBase64: keys.publicKey).verify(try issuedKey(environment.output))
        }
        #expect(environment.run(["issue", "--key", keys.privatePath, "--name", "A", "--public", "not-a-key"]) == LicenseTool.exitFailure)
        #expect(environment.errorOutput.contains(LicenseTool.message(for: .invalidPublicKey)))
        #expect(environment.output.isEmpty)
    }

    @Test func issueWarnsWhenNoPublicKeyIsAvailable() throws {
        let keys = try installKeys()
        #expect(environment.run(["issue", "--key", keys.privatePath, "--name", "A"]) == LicenseTool.exitSuccess)
        #expect(environment.errorOutput.contains("警告: 公開鍵が見つからない"))
        _ = try LicenseVerifier(publicKeyBase64: keys.publicKey).verify(try issuedKey(environment.output))
    }

    @Test func issueReportsKeyProblems() {
        #expect(environment.run(["issue", "--key", "/missing", "--name", "A"]) == LicenseTool.exitFailure)
        #expect(environment.errorOutput.contains("秘密鍵を読めません"))

        environment.files["/bad"] = .init(contents: "not a key", permissions: 0o600)
        #expect(environment.run(["issue", "--key", "/bad", "--name", "A"]) == LicenseTool.exitFailure)
        #expect(environment.errorOutput.contains(LicenseTool.message(for: .invalidPrivateKey)))
        #expect(environment.output.isEmpty)
    }

    // MARK: - verify

    @Test func verifiesWithPublicKeyFileOrText() throws {
        let keys = try installKeys()
        let key = try LicenseTestFixtures.licenseKey()
        for publicKey in ["/keys/public", keys.publicKey] {
            #expect(environment.run(["verify", "--public", publicKey, key]) == LicenseTool.exitSuccess)
            #expect(environment.output.contains("有効なライセンスです"))
            #expect(environment.output.contains("購入者: 山田 太郎"))
            #expect(environment.output.contains("メール: taro@example.com"))
            #expect(environment.output.contains("2026-10-30T00:00:00Z"))
        }
    }

    @Test func verifyReportsInvalidKeys() throws {
        let keys = try installKeys()
        let forged = try LicenseSigner(privateKeyBase64: LicenseTestFixtures.otherKeys.privateKeyBase64).sign(LicenseTestFixtures.info())
        #expect(environment.run(["verify", "--public", keys.publicKey, forged]) == LicenseTool.exitFailure)
        #expect(environment.errorOutput.contains(LicenseTool.message(for: .invalidSignature)))
        #expect(environment.output.isEmpty)

        #expect(environment.run(["verify", "--public", keys.publicKey, "garbage"]) == LicenseTool.exitFailure)
        #expect(environment.errorOutput.contains(LicenseTool.message(for: .malformed)))

        #expect(environment.run(["verify", "--public", "not-a-key", try LicenseTestFixtures.licenseKey()]) == LicenseTool.exitFailure)
        #expect(environment.errorOutput.contains(LicenseTool.message(for: .invalidPublicKey)))
    }

    @Test func messagesAreDistinct() {
        let errors: [LicenseError] = [.malformed, .invalidSignature, .wrongProduct, .invalidPublicKey, .invalidPrivateKey]
        #expect(Set(errors.map(LicenseTool.message(for:))).count == errors.count)
    }

    // MARK: - 本物のファイル

    @Test func liveCreateNewFileUsesExclusivePermissions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("NonetLicenseToolTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("secret").path

        let io = LicenseToolIO.live
        try io.createNewFile(path, "秘密\n", 0o600)
        #expect(try String(contentsOfFile: path, encoding: .utf8) == "秘密\n")
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.uint16Value == 0o600)
        #expect(io.fileExists(path))
        #expect(try io.readFile(path) == "秘密\n")

        #expect(throws: POSIXError(.EEXIST)) {
            try io.createNewFile(path, "上書き", 0o600)
        }
        #expect(try String(contentsOfFile: path, encoding: .utf8) == "秘密\n")
    }

    @Test func liveKeygenEndToEnd() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("NonetLicenseToolTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        var io = LicenseToolIO.live
        var output = ""
        io.standardOutput = { output += $0 }
        io.standardError = { _ in }
        let keysDirectory = directory.appendingPathComponent("keys").path
        #expect(LicenseTool.run(["keygen", "--out", keysDirectory], io: io) == LicenseTool.exitSuccess)
        let privatePath = keysDirectory + "/" + LicenseTool.privateKeyFileName
        let attributes = try FileManager.default.attributesOfItem(atPath: privatePath)
        #expect((attributes[.posixPermissions] as? NSNumber)?.uint16Value == 0o600)
        #expect(LicenseTool.run(["keygen", "--out", keysDirectory], io: io) == LicenseTool.exitFailure)

        output = ""
        #expect(LicenseTool.run(["issue", "--key", privatePath, "--name", "Test"], io: io) == LicenseTool.exitSuccess)
        let key = output.trimmingCharacters(in: .whitespacesAndNewlines)
        output = ""
        let publicPath = keysDirectory + "/" + LicenseTool.publicKeyFileName
        #expect(LicenseTool.run(["verify", "--public", publicPath, key], io: io) == LicenseTool.exitSuccess)
        #expect(output.contains("購入者: Test"))

        // 公開鍵のファイルを秘密鍵として渡しても発行しない
        output = ""
        #expect(LicenseTool.run(["issue", "--key", publicPath, "--name", "Test"], io: io) == LicenseTool.exitFailure)
        #expect(output.isEmpty)
    }
}
