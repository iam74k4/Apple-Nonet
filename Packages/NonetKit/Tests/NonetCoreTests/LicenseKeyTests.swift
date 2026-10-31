import CryptoKit
import Foundation
import Testing
@testable import NonetCore

/// ライセンスのテストで共有する鍵と中身
enum LicenseTestFixtures {
    /// テストの鍵は毎回作るので、base64 が「//」を含まないものに限る（約1%）。
    /// 含むと、xcconfig にそのまま書くテストで「//」から後ろがコメントになり、ときどき落ちていた
    static let keys = keyPairWithoutDoubleSlash()
    static let otherKeys = keyPairWithoutDoubleSlash()

    static func keyPairWithoutDoubleSlash() -> (privateKeyBase64: String, publicKeyBase64: String) {
        var keys = LicenseSigner.generateKeyPair()
        while keys.publicKeyBase64.contains("//") { keys = LicenseSigner.generateKeyPair() }
        return keys
    }
    /// 2026-10-30T00:00:00Z
    static let issuedAt = Date(timeIntervalSince1970: 1_793_318_400)

    static func info(licensee: String = "山田 太郎", email: String? = "taro@example.com", product: String = LicenseInfo.productID) -> LicenseInfo {
        LicenseInfo(licenseID: "NONET-0001", product: product, licensee: licensee, email: email, edition: "standard", issuedAt: issuedAt)
    }

    static func signer() throws -> LicenseSigner {
        try LicenseSigner(privateKeyBase64: keys.privateKeyBase64)
    }

    static func verifier() throws -> LicenseVerifier {
        try LicenseVerifier(publicKeyBase64: keys.publicKeyBase64)
    }

    static func licenseKey(_ info: LicenseInfo = info()) throws -> String {
        try signer().sign(info)
    }

    /// 任意のバイト列に正しい署名を付けたキー
    static func signedKey(payload: Data, privateKeyBase64: String = keys.privateKeyBase64) throws -> String {
        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: try #require(Data(base64Encoded: privateKeyBase64)))
        let signature = try privateKey.signature(for: payload)
        return LicenseCoding.base64URLEncoded(payload) + "." + LicenseCoding.base64URLEncoded(signature)
    }
}

@Suite struct LicenseKeyTests {
    typealias Fixtures = LicenseTestFixtures

    // MARK: - 署名と検証

    @Test func signAndVerifyRoundTrip() throws {
        let verifier = try Fixtures.verifier()
        for info in [Fixtures.info(), Fixtures.info(email: nil), Fixtures.info(licensee: "Jane \"JJ\" O'Neil / ACME, Inc. 🎉")] {
            let key = try Fixtures.licenseKey(info)
            #expect(try verifier.verify(key) == info)
        }
    }

    @Test func keyIsBase64URLOfCanonicalJSONAndSignature() throws {
        let key = try Fixtures.licenseKey()
        #expect(key.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) })
        let parts = key.split(separator: ".")
        try #require(parts.count == 2)
        let payload = try #require(LicenseCoding.base64URLDecoded(parts[0]))
        let json = try #require(String(data: payload, encoding: .utf8))
        #expect(json == #"{"edition":"standard","email":"taro@example.com","issuedAt":"2026-10-30T00:00:00Z","licenseID":"NONET-0001","licensee":"山田 太郎","product":"com.iam74k4.Nonet"}"#)

        // 署名は JSON のバイト列そのものに対するもの
        let signature = try #require(LicenseCoding.base64URLDecoded(parts[1]))
        #expect(signature.count == 64)
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: try #require(Data(base64Encoded: Fixtures.keys.publicKeyBase64)))
        #expect(publicKey.isValidSignature(signature, for: payload))
    }

    @Test func omitsMissingEmailFromPayload() throws {
        let key = try Fixtures.licenseKey(Fixtures.info(email: nil))
        let encodedPayload = try #require(key.split(separator: ".").first)
        let payload = try #require(LicenseCoding.base64URLDecoded(encodedPayload))
        #expect(String(decoding: payload, as: UTF8.self).contains("email") == false)
    }

    @Test func issuedAtIsStoredWithSecondPrecision() throws {
        var info = Fixtures.info()
        info.issuedAt = Fixtures.issuedAt.addingTimeInterval(0.75)
        let verified = try Fixtures.verifier().verify(try Fixtures.licenseKey(info))
        #expect(verified.issuedAt == Fixtures.issuedAt)
    }

    @Test func acceptsFractionalSecondsAndUnknownFields() throws {
        // 将来の発行側が書くかもしれない形も読む
        let json = #"{"edition":"pro","future":[1,2],"issuedAt":"2026-10-30T00:00:00.500Z","licenseID":"X","licensee":"A","product":"com.iam74k4.Nonet"}"#
        let info = try Fixtures.verifier().verify(try Fixtures.signedKey(payload: Data(json.utf8)))
        #expect(info.edition == "pro")
        #expect(info.email == nil)
        #expect(info.issuedAt == Fixtures.issuedAt.addingTimeInterval(0.5))
    }

    // MARK: - 改ざん・誤り

    @Test func rejectsTamperedPayload() throws {
        let key = try Fixtures.licenseKey()
        let signature = try #require(key.split(separator: ".").last)
        var forged = Fixtures.info()
        forged.licensee = "別の人"
        let forgedPayload = LicenseCoding.base64URLEncoded(try LicenseCoding.encode(forged))
        #expect(throws: LicenseError.invalidSignature) {
            try Fixtures.verifier().verify(forgedPayload + "." + signature)
        }
        // 1文字だけ変える
        var characters = Array(key)
        characters[10] = characters[10] == "A" ? "B" : "A"
        #expect(throws: LicenseError.invalidSignature) {
            try Fixtures.verifier().verify(String(characters))
        }
    }

    @Test func rejectsTamperedSignature() throws {
        let key = try Fixtures.licenseKey()
        let dot = try #require(key.firstIndex(of: "."))
        var characters = Array(key)
        let index = key.distance(from: key.startIndex, to: dot) + 20
        characters[index] = characters[index] == "A" ? "B" : "A"
        #expect(throws: LicenseError.invalidSignature) {
            try Fixtures.verifier().verify(String(characters))
        }
        // 別の鍵の署名
        let other = try LicenseSigner(privateKeyBase64: Fixtures.otherKeys.privateKeyBase64).sign(Fixtures.info())
        #expect(throws: LicenseError.invalidSignature) {
            try Fixtures.verifier().verify(other)
        }
    }

    @Test func rejectsWrongProduct() throws {
        let key = try Fixtures.licenseKey(Fixtures.info(product: "com.example.Other"))
        #expect(throws: LicenseError.wrongProduct) {
            try Fixtures.verifier().verify(key)
        }
    }

    @Test(arguments: [
        "",
        "   ",
        "abc",
        ".",
        "..",
        "abc.",
        ".abc",
        "a.b.c",
        "eyJhIjoxfQ.eyJhIjoxfQ.eyJhIjoxfQ",
        "!!!.###",
        "eyJhIjoxfQ.AAAA",
        "eyJhIjoxfQ.A",
        "ライセンス.キー",
    ])
    func rejectsMalformedKeys(key: String) {
        #expect(throws: LicenseError.malformed) {
            try LicenseTestFixtures.verifier().verify(key)
        }
    }

    @Test func rejectsValidlySignedPayloadsThatAreNotLicenses() throws {
        for payload in ["not json", "[]", #"{"licensee":"A"}"#, #"{"edition":"s","issuedAt":"yesterday","licenseID":"X","licensee":"A","product":"com.iam74k4.Nonet"}"#] {
            let key = try Fixtures.signedKey(payload: Data(payload.utf8))
            #expect(throws: LicenseError.malformed) {
                try Fixtures.verifier().verify(key)
            }
        }
    }

    @Test func rejectsOversizedInput() throws {
        let key = try Fixtures.licenseKey()
        #expect(throws: LicenseError.malformed) {
            try Fixtures.verifier().verify(key + String(repeating: "A", count: 10_000))
        }
    }

    // MARK: - 貼り付けへの寛容さ

    @Test func toleratesWhitespaceAndLineBreaks() throws {
        let key = try Fixtures.licenseKey()
        let verifier = try Fixtures.verifier()
        let wrapped = stride(from: 0, to: key.count, by: 40).map { offset -> String in
            let start = key.index(key.startIndex, offsetBy: offset)
            let end = key.index(start, offsetBy: 40, limitedBy: key.endIndex) ?? key.endIndex
            return String(key[start..<end])
        }
        let variants = [
            "  \(key)  ",
            "\n\(key)\n",
            "\t\(key)\r\n",
            wrapped.joined(separator: "\n"),
            wrapped.joined(separator: "\r\n  "),
            wrapped.joined(separator: " "),
            "\u{FEFF}\(key)\u{200B}",
            "\u{00A0}\(key)\u{3000}",
        ]
        for variant in variants {
            #expect(try verifier.verify(variant) == Fixtures.info())
        }
    }

    @Test func extractsTheKeyFromPastedText() throws {
        let key = try Fixtures.licenseKey()
        let verifier = try Fixtures.verifier()
        let half = key.index(key.startIndex, offsetBy: key.count / 2)
        let variants = [
            "License key: \(key)",
            "ライセンスキー: \(key)",
            "ライセンスキー：\(key)。",
            "“\(key)”",
            "「\(key)」",
            "<\(key)>",
            "\"\(key)\"",
            "\(key).",
            "> \(key)",
            // メールの返信で、折り返したキーの行頭に引用の印が付いた
            "> ライセンスキーは次のとおりです。\n> \(key[..<half])\n> \(key[half...])\n>\n> よろしくお願いします。",
            "Your license key:\n\n\(key)\n\nThanks for buying Nonet!",
            key.replacingOccurrences(of: ".", with: "．"),
            // 同じキーが2回あっても、どれのことかは分かる
            "\(key)\n(\(key))",
            // 「:」の無い英数字だけの見出し。空白を除くとキーの前にくっつく（HTML のメールの見出しとキーの枠を一緒に選んだ）
            "License key \(key)",
            "Your license key\n\(key)",
            "License Key\n\n\(key)",
            "Key \(key)",
            "KEY\n\(key)",
            "Nonet license key\n\(key)\n",
            "Serial \(key)",
            "ライセンスキー\n\(key)",
        ]
        for variant in variants {
            #expect(try verifier.verify(variant) == Fixtures.info(), "\(variant)")
            #expect(LicenseCoding.licenseKey(in: variant) == key, "\(variant)")
        }
    }

    @Test func ignoresOtherTokensThatLookLikeAKey() throws {
        let key = try Fixtures.licenseKey()
        // 購入のメールのダウンロードのリンクに、JWT（eyJ… で始まる）が入っている
        let header = LicenseCoding.base64URLEncoded(Data(#"{"alg":"HS256","typ":"JWT"}"#.utf8))
        let claims = LicenseCoding.base64URLEncoded(Data(#"{"sub":"download","order":"NONET-ORDER-12345","scope":"nonet-dmg","exp":1893456000}"#.utf8))
        let jwt = "\(header).\(claims).\(String(repeating: "s", count: 43))"
        let mail = "Download Nonet: https://store.example.com/d?token=\(jwt)\n\nLicense Key\n\(key)\n"
        #expect(LicenseCoding.licenseKey(in: mail) == key)
        #expect(try Fixtures.verifier().verify(mail) == Fixtures.info())
    }

    @Test func refusesTextWithTwoDifferentKeys() throws {
        let first = try Fixtures.licenseKey()
        var other = Fixtures.info()
        other.licenseID = "NONET-0002"
        let second = try Fixtures.licenseKey(other)
        #expect(throws: LicenseError.malformed) {
            try Fixtures.verifier().verify("1: \(first)\n2: \(second)")
        }
    }

    @Test func aDamagedKeyInsideTextIsStillRejected() throws {
        let key = try Fixtures.licenseKey()
        // 署名が欠けている
        #expect(throws: LicenseError.malformed) {
            try Fixtures.verifier().verify("License key: \(key.dropLast(5))")
        }
        // 1文字変わっている
        var characters = Array(key)
        characters[20] = characters[20] == "A" ? "B" : "A"
        #expect(throws: LicenseError.invalidSignature) {
            try Fixtures.verifier().verify("License key: \(String(characters))")
        }
    }

    @Test func toleratesStandardBase64Alphabet() throws {
        // メールなどで base64url が標準の base64 に変わっても読める
        var found = false
        for index in 0..<50 {
            var info = Fixtures.info()
            info.licenseID = "ID-\(index)"
            let key = try Fixtures.licenseKey(info)
            guard key.contains("-") || key.contains("_") else { continue }
            found = true
            let standard = key.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            #expect(try Fixtures.verifier().verify(standard) == info)
        }
        #expect(found)
    }

    // MARK: - 鍵

    @Test func generatesDistinctKeyPairs() throws {
        let first = LicenseSigner.generateKeyPair()
        let second = LicenseSigner.generateKeyPair()
        #expect(first.privateKeyBase64 != second.privateKeyBase64)
        #expect(first.publicKeyBase64 != second.publicKeyBase64)
        #expect(Data(base64Encoded: first.privateKeyBase64)?.count == 32)
        #expect(Data(base64Encoded: first.publicKeyBase64)?.count == 32)
        #expect(try LicenseSigner(privateKeyBase64: first.privateKeyBase64).publicKeyBase64 == first.publicKeyBase64)
    }

    @Test func keysTolerateWhitespaceAndBase64URL() throws {
        let publicKey = Fixtures.keys.publicKeyBase64
        let urlForm = LicenseCoding.base64URLEncoded(try #require(Data(base64Encoded: publicKey)))
        for text in ["\(publicKey)\n", "  \(publicKey)", urlForm] {
            let key = try Fixtures.licenseKey()
            #expect(try LicenseVerifier(publicKeyBase64: text).verify(key) == Fixtures.info())
        }
        #expect(try LicenseSigner(privateKeyBase64: Fixtures.keys.privateKeyBase64 + "\n").publicKeyBase64 == publicKey)
    }

    @Test(arguments: ["", "  ", "abc", "!!!!", Data(count: 31).base64EncodedString(), Data(count: 33).base64EncodedString(), Data(count: 64).base64EncodedString()])
    func rejectsInvalidPublicKeys(text: String) {
        #expect(throws: LicenseError.invalidPublicKey) {
            try LicenseVerifier(publicKeyBase64: text)
        }
    }

    @Test(arguments: ["", "abc", Data(count: 31).base64EncodedString(), Data(count: 64).base64EncodedString()])
    func rejectsInvalidPrivateKeys(text: String) {
        #expect(throws: LicenseError.invalidPrivateKey) {
            try LicenseSigner(privateKeyBase64: text)
        }
    }

    @Test func errorsHaveDistinctDescriptions() throws {
        let errors: [LicenseError] = [.malformed, .invalidSignature, .wrongProduct, .invalidPublicKey, .invalidPrivateKey]
        let descriptions = try errors.map { try #require($0.errorDescription) }
        #expect(descriptions.allSatisfy { !$0.isEmpty })
        #expect(Set(descriptions).count == errors.count)
        #expect(LicenseError.wrongProduct.localizedDescription == LicenseError.wrongProduct.errorDescription)
    }
}
