// 担当: keys-license
// 無効にしたライセンスの一覧（返金したキー・公開されてしまったキー）と、nonet-license revoke
import Foundation
import Testing
@testable import NonetCore

/// 開始日とキーだけの保存先
private final class RevocationTestStorage: LicenseStorage {
    var trialStartDate: Date?
    var licenseKey: String?
}

/// メモリ上のファイルと標準出力（revoke 用）
private final class RevokeToolEnvironment {
    var currentDirectory = "/work/repo/Packages/NonetKit"
    var files: [String: String] = [:]
    var output = ""
    var errorOutput = ""
    var writes = 0

    static let listPath = "/work/repo/" + LicenseTool.revocationListPath

    var io: LicenseToolIO {
        LicenseToolIO(
            currentDirectory: { self.currentDirectory },
            fileExists: { self.files[$0] != nil },
            readFile: { path in
                guard let file = self.files[path] else { throw CocoaError(.fileReadNoSuchFile) }
                return file
            },
            createDirectory: { _ in },
            createNewFile: { _, _, _ in throw POSIXError(.EPERM) },
            standardOutput: { self.output += $0 },
            standardError: { self.errorOutput += $0 },
            // 2026-10-31T12:00:00Z
            now: { Date(timeIntervalSince1970: 1_793_448_000) },
            makeLicenseID: { "UNUSED" },
            replaceFile: { path, contents in
                self.writes += 1
                self.files[path] = contents
            }
        )
    }

    func run(_ arguments: [String]) -> Int32 {
        output = ""
        errorOutput = ""
        return LicenseTool.run(arguments, io: io)
    }
}

@Suite struct LicenseRevocationListTests {
    /// printf 'NONET-0001' | shasum -a 256
    static let hashOfFixtureID = "f434188d4a80c4d5a3bce31be0f40e181f4a1a2d891e94cb4d3a65e8721e50f6"

    @Test func hashesTheTrimmedLicenseID() {
        #expect(LicenseRevocationList.hash(of: "NONET-0001") == Self.hashOfFixtureID)
        #expect(LicenseRevocationList.hash(of: "  NONET-0001\n") == Self.hashOfFixtureID)
        #expect(LicenseRevocationList.hash(of: "nonet-0001") != Self.hashOfFixtureID)
    }

    @Test func readsHashesAndSkipsCommentsAndBrokenLines() {
        let list = LicenseRevocationList(text: """
        # 無効にしたライセンス
        \(Self.hashOfFixtureID.uppercased())  # 2026-10-31

          abc
        NONET-0002
        # \(String(repeating: "a", count: 64))
        \(String(repeating: "b", count: 64))
        """)
        #expect(list.hashes == [Self.hashOfFixtureID, String(repeating: "b", count: 64)])
        #expect(list.isRevoked("NONET-0001"))
        // ID をそのまま書いた行は数えない（一覧には SHA-256 だけを書く）
        #expect(!list.isRevoked("NONET-0002"))
        #expect(!LicenseRevocationList.empty.isRevoked("NONET-0001"))
    }

    /// アプリに入る一覧があり、ID ではなく SHA-256 だけが並んでいる
    @Test func theBundledListShipsWithTheApp() throws {
        let url = try #require(LicenseRevocationList.bundledURL)
        let text = try String(contentsOf: url, encoding: .utf8)
        for line in text.split(whereSeparator: \.isNewline) where !line.hasPrefix("#") {
            let token = line.split(separator: "#").first?.trimmingCharacters(in: .whitespaces) ?? ""
            #expect(LicenseRevocationList.isHash(token), "SHA-256 でない行: \(line)")
        }
        #expect(LicenseRevocationList.bundled == LicenseRevocationList(text: text))
        // テストのキー（NONET-0001）は無効にしていない
        #expect(!LicenseRevocationList.bundled.isRevoked("NONET-0001"))
    }
}

@MainActor
@Suite struct LicenseRevocationManagerTests {
    private let now = Date(timeIntervalSinceReferenceDate: 815_000_000)
    private let revoked = LicenseRevocationList(hashes: [LicenseRevocationListTests.hashOfFixtureID])

    @Test func aRevokedStoredKeyCountsAsNotRegistered() throws {
        let storage = RevocationTestStorage()
        storage.trialStartDate = now.addingTimeInterval(-3 * 86_400)
        let key = try LicenseTestFixtures.licenseKey()
        storage.licenseKey = key
        let manager = LicenseManager(verifier: try LicenseTestFixtures.verifier(), storage: storage, now: { now }, revocations: revoked)
        #expect(manager.entitlement == .trial(daysLeft: 11))
        #expect(manager.revokedLicense == LicenseTestFixtures.info())
        #expect(manager.registeredLicenseKey == nil)
        // キーは消さない（一覧から外した版では、また使える）
        #expect(storage.licenseKey == key)

        // 同じキーでも、一覧に無ければ登録済み
        let accepted = LicenseManager(verifier: try LicenseTestFixtures.verifier(), storage: storage, now: { now }, revocations: .empty)
        #expect(accepted.entitlement == .licensed(LicenseTestFixtures.info()))
        #expect(accepted.revokedLicense == nil)
    }

    @Test func aRevokedKeyCannotBeVerifiedOrActivated() throws {
        let storage = RevocationTestStorage()
        let manager = LicenseManager(verifier: try LicenseTestFixtures.verifier(), storage: storage, now: { now }, revocations: revoked)
        let key = try LicenseTestFixtures.licenseKey()
        #expect(throws: LicenseError.revoked) { try manager.verify(licenseKey: key) }
        #expect(throws: LicenseError.revoked) { try manager.activate(licenseKey: "License key: \(key)") }
        #expect(storage.licenseKey == nil)
        #expect(manager.entitlement == .trial(daysLeft: 14))
        // 別の ID のキーは使える
        var other = LicenseTestFixtures.info()
        other.licenseID = "NONET-0002"
        let otherKey = try LicenseTestFixtures.licenseKey(other)
        #expect(try manager.activate(licenseKey: otherKey) == other)
        #expect(manager.revokedLicense == nil)
        #expect(LicenseError.revoked.errorDescription == String(localized: "このライセンスキーは無効にされています", bundle: .nonetCore))
    }

    /// 登録したあとで無効にされた（キーを入れ替えた）ら、次に確かめたときに外れ、理由が分かる
    @Test func swappingToARevokedKeyIsNoticedOnRefresh() throws {
        let storage = RevocationTestStorage()
        var good = LicenseTestFixtures.info()
        good.licenseID = "NONET-0002"
        storage.licenseKey = try LicenseTestFixtures.licenseKey(good)
        let manager = LicenseManager(verifier: try LicenseTestFixtures.verifier(), storage: storage, now: { now }, revocations: revoked)
        #expect(manager.entitlement == .licensed(good))
        storage.licenseKey = try LicenseTestFixtures.licenseKey()
        manager.refresh()
        #expect(manager.entitlement == .trial(daysLeft: 14))
        #expect(manager.revokedLicense?.licenseID == "NONET-0001")
        manager.deactivate()
        #expect(manager.revokedLicense == nil)
    }
}

@Suite struct LicenseRevokeToolTests {
    private let environment = RevokeToolEnvironment()
    private static let header = "# 無効にしたライセンス\n"

    @Test func parsesTheRevokeCommand() throws {
        #expect(try LicenseTool.parse(["revoke", "NONET-0001"]) == .revoke(target: "NONET-0001", listPath: nil))
        #expect(try LicenseTool.parse(["revoke", "--list", "/x/list.txt", "NONET-0001"]) == .revoke(target: "NONET-0001", listPath: "/x/list.txt"))
        #expect(throws: LicenseToolUsageError.self) { try LicenseTool.parse(["revoke"]) }
        #expect(throws: LicenseToolUsageError.self) { try LicenseTool.parse(["revoke", " "]) }
        #expect(throws: LicenseToolUsageError.self) { try LicenseTool.parse(["revoke", "a", "b"]) }
        #expect(LicenseTool.usage.contains("nonet-license revoke"))
    }

    @Test func revokingAnIDAppendsItsHashToTheListInTheRepository() {
        environment.files[RevokeToolEnvironment.listPath] = Self.header
        #expect(environment.run(["revoke", "NONET-0001"]) == LicenseTool.exitSuccess)
        #expect(environment.files[RevokeToolEnvironment.listPath] == Self.header + "\(LicenseRevocationListTests.hashOfFixtureID)  # 2026-10-31\n")
        #expect(environment.output == LicenseRevocationListTests.hashOfFixtureID + "\n")
        #expect(environment.errorOutput.contains("NONET-0001"))
        #expect(environment.errorOutput.contains("次のリリース"))
        // ID そのものは一覧に書かない
        #expect(environment.files[RevokeToolEnvironment.listPath]?.contains("NONET-0001") == false)
        #expect(LicenseRevocationList(text: environment.files[RevokeToolEnvironment.listPath] ?? "").isRevoked("NONET-0001"))

        // もう一度無効にしても、一覧は変わらない
        #expect(environment.run(["revoke", "NONET-0001"]) == LicenseTool.exitSuccess)
        #expect(environment.writes == 1)
        #expect(environment.errorOutput.contains("すでに無効にしてあります"))
    }

    @Test func revokingAKeyUsesTheIDInsideIt() throws {
        environment.files[RevokeToolEnvironment.listPath] = "# 改行で終わらない"
        let key = try LicenseTestFixtures.licenseKey()
        #expect(environment.run(["revoke", "License key: \(key)."]) == LicenseTool.exitSuccess)
        #expect(environment.files[RevokeToolEnvironment.listPath] == "# 改行で終わらない\n\(LicenseRevocationListTests.hashOfFixtureID)  # 2026-10-31\n")
        #expect(environment.errorOutput.contains("NONET-0001"))
    }

    @Test func aBrokenKeyOrAMissingListStopsWithoutWriting() {
        environment.files[RevokeToolEnvironment.listPath] = Self.header
        #expect(environment.run(["revoke", "eyJhYmM.def"]) == LicenseTool.exitFailure)
        #expect(environment.errorOutput.contains("ライセンスキーを読めません"))
        environment.currentDirectory = "/elsewhere"
        #expect(environment.run(["revoke", "NONET-0001"]) == LicenseTool.exitFailure)
        #expect(environment.errorOutput.contains(LicenseTool.revocationListPath))
        // --list ならリポジトリの外でも書ける
        environment.files["/elsewhere/list.txt"] = ""
        #expect(environment.run(["revoke", "--list", "list.txt", "NONET-0001"]) == LicenseTool.exitSuccess)
        #expect(environment.files["/elsewhere/list.txt"] == "\(LicenseRevocationListTests.hashOfFixtureID)  # 2026-10-31\n")
        #expect(environment.files[RevokeToolEnvironment.listPath] == Self.header)
        #expect(environment.writes == 1)
    }

    /// 本物の io 以外は、既定ではファイルを書き換えない
    @Test func theDefaultIOCannotReplaceFiles() {
        let io = LicenseToolIO(
            currentDirectory: { "/" }, fileExists: { _ in false }, readFile: { _ in "" }, createDirectory: { _ in },
            createNewFile: { _, _, _ in }, standardOutput: { _ in }, standardError: { _ in }, now: { Date() }, makeLicenseID: { "" }
        )
        #expect(throws: (any Error).self) { try io.replaceFile("/tmp/never-written", "x") }
    }
}
