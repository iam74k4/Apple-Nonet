// 担当: ui-settings
// ライセンスのタブ・購入のメールのリンク・試用期間が終わったときのウィンドウ・お問い合わせ・アンインストール
import AppKit
import Foundation
import NonetCore
@testable import NonetUI
import Testing

/// 署名したキーと、それを確かめる鍵
private struct SignedLicense {
    let key: String
    let info: LicenseInfo
    let verifier: LicenseVerifier
    private let signer: LicenseSigner

    init(name: String = "Taro Yamada", email: String? = "taro@example.com", licenseID: String = "NONET-2026-000123") throws {
        let pair = LicenseSigner.generateKeyPair()
        signer = try LicenseSigner(privateKeyBase64: pair.privateKeyBase64)
        info = LicenseInfo(licenseID: licenseID, licensee: name, email: email, issuedAt: Date(timeIntervalSince1970: 1_800_000_000))
        key = try signer.sign(info)
        verifier = try LicenseVerifier(publicKeyBase64: pair.publicKeyBase64)
    }

    /// 同じ鍵で署名した、別の人のキー
    func other(name: String, licenseID: String) throws -> (key: String, info: LicenseInfo) {
        let info = LicenseInfo(licenseID: licenseID, licensee: name, email: nil, issuedAt: Date(timeIntervalSince1970: 1_800_000_000))
        return (try signer.sign(info), info)
    }
}

/// 試用期間が終わった LicenseManager（20日以上前に始めた）
@MainActor
private func expiredLicense(verifier: LicenseVerifier? = nil) -> (LicenseManager, SettingsFakeLicenseStorage) {
    let storage = SettingsFakeLicenseStorage()
    storage.trialStartDate = Date(timeIntervalSinceReferenceDate: 700_000_000)
    return (LicenseManager(verifier: verifier, storage: storage, now: { Date(timeIntervalSinceReferenceDate: 800_000_000) }), storage)
}

// MARK: - 文言

@Suite struct SettingsLicenseTextTests {
    /// 「ずっと使えます」ではなく、何をすれば試用期間のあとも使えるかを言う
    @Test func trialDescriptionSaysWhatKeepsWorking() {
        let trial = SettingsText.summary(.trial(daysLeft: 5))
        #expect(trial.detail == L10n.ui("試用期間中はすべての機能を使えます。購入してライセンスキーを登録すると、試用期間のあとも使い続けられます。"))
    }

    /// 残り日数に、終わる日を文言の言語で添える
    @Test func trialTitleShowsTheEndDate() {
        let end = Date(timeIntervalSince1970: 1_794_614_400) // 2026-11-14T00:00:00Z
        let english = Locale(identifier: "en_US")
        let day = SettingsText.trialEndDay(end, locale: english)
        #expect(day == end.formatted(.dateTime.month(.wide).day().locale(english)))
        #expect(day.contains("November"))
        let summary = SettingsText.summary(.trial(daysLeft: 14), trialEnd: end, locale: english)
        #expect(summary.title == L10n.uiCounted("試用期間中（残り\(14)日・\(day)まで）"))
        #expect(summary.title.contains(day))
        // 終わる日が分からなければ、日数だけ
        #expect(SettingsText.summary(.trial(daysLeft: 14)).title == L10n.uiCounted("試用期間中（残り\(14)日）"))
    }

    /// エラーには次にすることを書く。公開鍵の無いビルドでは開発者の言葉を使わない
    @Test func licenseErrorsSayWhatToDoNext() {
        #expect(SettingsText.licenseError(LicenseError.invalidSignature, input: "eyJx.y") == L10n.ui("ライセンスキーを確かめられませんでした。購入時のメールからキー全体をもう一度コピーしてください。それでも登録できないときは、お問い合わせください。"))
        #expect(SettingsText.licenseError(LicenseError.malformed, input: "abc") == L10n.ui("ライセンスキーの形式が正しくありません。購入時のメールから、キー全体をもう一度コピーしてください。それでも登録できないときは、お問い合わせください。"))
        #expect(SettingsText.licenseError(LicenseError.wrongProduct, input: "eyJx.y") == L10n.ui("このライセンスキーは Nonet のものではありません。購入時のメールにある、Nonet のライセンスキーを貼り付けてください。"))
        let noKey = L10n.ui("この Nonet ではライセンスキーを確かめられません。最新の Nonet をダウンロードし直してください。")
        #expect(SettingsText.licenseError(LicenseError.invalidPublicKey, input: "eyJx.y") == noKey)
        // ライセンス ID を貼り付けても、まず確かめられないことを言う
        #expect(SettingsText.licenseError(LicenseError.invalidPublicKey, input: "NONET-2026-000123") == noKey)
        #expect(!noKey.contains(L10n.core("ライセンスを検証する公開鍵が設定されていないか、正しくありません")))
    }

    /// 無効にしたライセンス（返金・公開されたキー）は、登録できない理由と、次にすることを言う
    @Test func aRevokedLicenseSaysWhy() {
        #expect(SettingsText.licenseError(LicenseError.revoked, input: "eyJx.y") == L10n.ui("このライセンスキーは無効になっています（返金したライセンスや、公開されてしまったキーは使えません）。心当たりがないときは、お問い合わせください。"))
        let info = LicenseInfo(licenseID: "NONET-2026-000123", licensee: "Taro", email: nil, issuedAt: Date(timeIntervalSince1970: 1_800_000_000))
        let notice = SettingsText.revokedLicenseNotice(info)
        #expect(notice == L10n.ui("登録してあったライセンスキー（ライセンス ID: \("NONET-2026-000123")）は無効になっているため、使えません。新しいキーを登録するか、心当たりがないときはお問い合わせください。"))
    }

    @Test func aPastedLicenseIDIsRecognized() {
        let idMessage = L10n.ui("これはライセンス ID です。メールにある長いライセンスキーを貼り付けてください。")
        for input in ["NONET-2026-000123", "  nonet-2026-000123\n", "License ID: NONET-2026-000123", "3F2504E0-4F89-11D3-9A0C-0305E82C3301"] {
            #expect(SettingsText.looksLikeLicenseID(input), "\(input)")
            #expect(SettingsText.licenseError(LicenseError.malformed, input: input) == idMessage)
        }
        for input in ["", "abc", "eyJsaWNlbnNlSUQiOiJOT05FVC0yMDI2LTAwMDEyMyJ9.sig", String(repeating: "NONET-2026-000123 ", count: 10)] {
            #expect(!SettingsText.looksLikeLicenseID(input), "\(input)")
        }
    }

    @Test func uninstallTextsSayWhatIsKept() {
        let confirmation = SettingsText.uninstallConfirmation
        #expect(confirmation.contains(L10n.ui("ライセンスキーは残すので、入れ直せば登録し直さずに使えます。試用期間もやり直しにはなりません。ゴミ箱を空にするまでは元に戻せます。")))
        let finished = SettingsText.uninstallFinished(SettingsUninstallResult())
        #expect(finished == L10n.ui("最後に、システム設定 › プライバシーとセキュリティ › アクセシビリティ の一覧で Nonet を選び、「−」で外してください。"))
        let partial = SettingsText.uninstallFinished(
            SettingsUninstallResult(leftovers: [URL(fileURLWithPath: "/Users/someone/Library/Caches/com.iam74k4.Nonet")], loginItemFailed: true),
            home: "/Users/someone"
        )
        #expect(partial.contains(L10n.ui("ログイン時の起動を止められませんでした。システム設定 › 一般 › ログイン項目 で Nonet を外してください。")))
        #expect(partial.contains(L10n.ui("・\("~/Library/Caches/com.iam74k4.Nonet")")))
    }
}

// MARK: - ライセンスのタブ

@Suite @MainActor struct SettingsLicenseTabTests {
    @Test func aPastedLicenseIDGetsItsOwnMessage() throws {
        let signed = try SignedLicense()
        let h = try SettingsHarness(verifier: signed.verifier)
        h.model.licenseKeyInput = "NONET-2026-000123"
        h.model.activateLicense()
        #expect(h.model.licenseMessage == SettingsMessage(text: L10n.ui("これはライセンス ID です。メールにある長いライセンスキーを貼り付けてください。"), isError: true))
    }

    /// 登録済み: キーの欄は隠し、キーのコピーと別のキーの登録を出す
    @Test func registeredStateCopiesTheKeyAndRevealsTheFieldOnRequest() throws {
        let signed = try SignedLicense()
        let h = try SettingsHarness(verifier: signed.verifier)
        #expect(h.model.showsLicenseKeyField)
        h.model.licenseKeyInput = signed.key
        h.model.activateLicense()
        #expect(h.model.isLicensed)
        #expect(!h.model.showsLicenseKeyField)

        var copied: [String] = []
        h.model.copyToPasteboard = { copied.append($0) }
        h.model.copyLicenseKey()
        #expect(copied == [signed.key])
        #expect(h.model.licenseMessage == SettingsMessage(text: L10n.ui("ライセンスキーをコピーしました"), isError: false))

        h.model.setEnteringAnotherKey(true)
        #expect(h.model.showsLicenseKeyField)
        #expect(h.model.wantsLicenseKeyFocus)
        #expect(h.model.licenseMessage == nil)
        h.model.setEnteringAnotherKey(false)
        #expect(!h.model.showsLicenseKeyField)
    }

    @Test func copyingDoesNothingWithoutALicense() throws {
        let h = try SettingsHarness()
        var copied: [String] = []
        h.model.copyToPasteboard = { copied.append($0) }
        h.model.copyLicenseKey()
        #expect(copied.isEmpty)
        #expect(h.model.licenseMessage == nil)
    }

    /// 試用期間が終わったら、ライセンスのタブ以外の上に帯を出す
    @Test func expiredBannerShowsOutsideTheLicenseTab() throws {
        let h = try SettingsHarness()
        #expect(!h.model.showsExpiredBanner)
        let (expired, _) = expiredLicense()
        let model = SettingsModel(controller: h.controller, license: expired, services: h.services, links: AppLinks(), onCheckForUpdates: nil)
        #expect(model.showsExpiredBanner)
        model.showLicenseKeyEntry()
        #expect(model.tab == .license)
        #expect(model.wantsLicenseKeyFocus)
        #expect(!model.showsExpiredBanner)
        model.selectTab(.general)
        #expect(model.showsExpiredBanner)
    }

    @Test func licenseKeyHelpPointsAtTheFAQInTheUILanguage() {
        let links = AppLinks(support: URL(string: "https://nonet.astlog.dev/guide.html"))
        #expect(links.licenseKeyHelp?.absoluteString == "https://nonet.astlog.dev/#faq-license-key")
        #expect(links.localized(language: "en").licenseKeyHelp?.absoluteString == "https://nonet.astlog.dev/en/#faq-license-key")
        #expect(links.localized(language: "ja").licenseKeyHelp?.absoluteString == "https://nonet.astlog.dev/#faq-license-key")
        #expect(AppLinks().licenseKeyHelp == nil)
        #expect(AppLinks(support: URL(fileURLWithPath: "/tmp/guide.html")).licenseKeyHelp == nil)
    }
}

// MARK: - 購入のメールのリンクとファイル

@Suite @MainActor struct SettingsLicenseLinkTests {
    @Test func parsesTheRegisterLink() throws {
        let url = try #require(URL(string: "nonet://register?key=eyJabc.def"))
        #expect(SettingsLicenseLink.content(of: url) == .text("eyJabc.def"))
        #expect(SettingsLicenseLink.content(of: try #require(URL(string: "NONET://Register?key=eyJabc.def"))) == .text("eyJabc.def"))
        #expect(SettingsLicenseLink.content(of: try #require(URL(string: "nonet:register?key=eyJabc.def"))) == .text("eyJabc.def"))
        // % で符号にした改行や空白は、欄に入れる前に前後だけ除く
        #expect(SettingsLicenseLink.content(of: try #require(URL(string: "nonet://register?key=%20eyJabc%0A.def%0A"))) == .text("eyJabc\n.def"))
        // 見えない制御文字は除く
        #expect(SettingsLicenseLink.content(of: try #require(URL(string: "nonet://register?key=eyJ%07abc.def"))) == .text("eyJabc.def"))
    }

    @Test func rejectsOtherOrBrokenLinks() throws {
        #expect(SettingsLicenseLink.content(of: try #require(URL(string: "https://example.com/register?key=x"))) == nil)
        #expect(SettingsLicenseLink.content(of: try #require(URL(string: "nonet://settings"))) == nil)
        #expect(SettingsLicenseLink.content(of: try #require(URL(string: "nonet://register"))) == .unreadable)
        #expect(SettingsLicenseLink.content(of: try #require(URL(string: "nonet://register?key="))) == .unreadable)
        let long = String(repeating: "A", count: SettingsLicenseLink.maximumTextLength + 1)
        #expect(SettingsLicenseLink.content(of: try #require(URL(string: "nonet://register?key=\(long)"))) == .unreadable)
        let huge = String(repeating: "A", count: SettingsLicenseLink.maximumURLLength)
        #expect(SettingsLicenseLink.content(of: try #require(URL(string: "nonet://register?key=x&pad=\(huge)"))) == .unreadable)
    }

    @Test func readsALicenseFile() throws {
        let file = URL(fileURLWithPath: "/tmp/Nonet.nonetlicense")
        #expect(SettingsLicenseLink.content(of: file) { _ in Data("License key:\neyJabc.def\n".utf8) } == .text("License key:\neyJabc.def"))
        #expect(SettingsLicenseLink.content(of: URL(fileURLWithPath: "/tmp/Nonet.NONETLICENSE")) { _ in Data("eyJ".utf8) } == .text("eyJ"))
        // ほかの種類のファイルは扱わない（読まない）
        #expect(SettingsLicenseLink.content(of: URL(fileURLWithPath: "/tmp/a.nonetprofile")) { _ in Issue.record("読んだ"); return Data() } == nil)
        // 大きすぎる・文字でない・読めない
        #expect(SettingsLicenseLink.content(of: file) { _ in Data(count: SettingsLicenseLink.maximumFileSize + 1) } == .unreadable)
        #expect(SettingsLicenseLink.content(of: file) { _ in Data([0xFF, 0xFE, 0x00]) } == .unreadable)
        #expect(SettingsLicenseLink.content(of: file) { _ in throw CocoaError(.fileReadNoPermission) } == .unreadable)
    }

    @Test func readsOnlyRegularFilesOfAReasonableSize() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "NonetLicenseLink-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let small = directory.appending(path: "a.nonetlicense")
        try Data("eyJabc.def".utf8).write(to: small)
        #expect(try SettingsLicenseLink.readLicenseFile(small) == Data("eyJabc.def".utf8))
        let large = directory.appending(path: "b.nonetlicense")
        try Data(count: SettingsLicenseLink.maximumFileSize + 1).write(to: large)
        #expect(throws: (any Error).self) { try SettingsLicenseLink.readLicenseFile(large) }
        let folder = directory.appending(path: "c.nonetlicense", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #expect(throws: (any Error).self) { try SettingsLicenseLink.readLicenseFile(folder) }
        #expect(SettingsLicenseLink.content(of: folder) == .unreadable)
    }

    /// リンクから開いても黙って登録しない。登録者を見せて尋ね、「登録」を押したときだけ登録する
    @Test func aLinkAsksBeforeRegistering() throws {
        let signed = try SignedLicense()
        let h = try SettingsHarness(verifier: signed.verifier)
        h.model.openLicenseLink(.text("License key: \(signed.key)"))
        #expect(h.model.tab == .license)
        #expect(h.model.pendingLicense == VerifiedLicense(key: signed.key, info: signed.info))
        #expect(h.model.licenseKeyInput == signed.key)
        #expect(h.license.entitlement == .trial(daysLeft: 14))
        #expect(h.licenseStorage.licenseKey == nil)

        // やめても、キーは欄に残る
        h.model.cancelPendingLicense()
        #expect(h.model.pendingLicense == nil)
        #expect(h.licenseStorage.licenseKey == nil)
        #expect(h.model.licenseKeyInput == signed.key)

        h.model.openLicenseLink(.text(signed.key))
        h.model.confirmPendingLicense()
        #expect(h.license.entitlement == .licensed(signed.info))
        #expect(h.licenseStorage.licenseKey == signed.key)
        #expect(h.model.pendingLicense == nil)
        #expect(h.model.licenseKeyInput.isEmpty)

        // 同じキーをもう一度開いたら、もう登録済みと伝える
        h.model.openLicenseLink(.text(signed.key))
        #expect(h.model.pendingLicense == nil)
        #expect(h.model.licenseMessage == SettingsMessage(text: L10n.ui("このライセンスキーは登録済みです"), isError: false))
        #expect(!h.model.showsLicenseKeyField)
    }

    @Test func aBrokenLinkShowsWhy() throws {
        let signed = try SignedLicense()
        let h = try SettingsHarness(verifier: signed.verifier)
        h.model.openLicenseLink(.unreadable)
        #expect(h.model.pendingLicense == nil)
        #expect(h.model.licenseMessage == SettingsMessage(text: L10n.ui("リンクからライセンスキーを読み取れませんでした。購入時のメールからキーをコピーして、ここに貼り付けてください。"), isError: true))

        // 別の鍵で署名したキー
        let other = try SignedLicense(name: "Someone Else")
        h.model.openLicenseLink(.text(other.key))
        #expect(h.model.pendingLicense == nil)
        #expect(h.model.licenseMessage == SettingsMessage(text: SettingsText.licenseError(LicenseError.invalidSignature, input: other.key), isError: true))
        #expect(h.model.licenseKeyInput == other.key)
        #expect(h.licenseStorage.licenseKey == nil)
    }

    /// 登録済みのときに別のキーのリンクを開いたら、別のキーの欄を出して尋ねる。「登録」で置き換わる
    @Test func aDifferentKeyWhileRegisteredIsAskedAbout() throws {
        let signed = try SignedLicense()
        let h = try SettingsHarness(verifier: signed.verifier)
        h.model.licenseKeyInput = signed.key
        h.model.activateLicense()
        let other = try signed.other(name: "Hanako Suzuki", licenseID: "NONET-2026-000124")
        h.model.openLicenseLink(.text(other.key))
        #expect(h.model.isEnteringAnotherKey)
        #expect(h.model.showsLicenseKeyField)
        #expect(h.model.pendingLicense == VerifiedLicense(key: other.key, info: other.info))
        #expect(h.license.entitlement == .licensed(signed.info))
        h.model.confirmPendingLicense()
        #expect(h.license.entitlement == .licensed(other.info))
        #expect(!h.model.isEnteringAnotherKey)
    }

    @Test func theWindowControllerIgnoresOtherURLs() throws {
        let h = try SettingsHarness()
        let controller = SettingsWindowController(controller: h.controller, license: h.license, services: h.services, links: AppLinks(), onCheckForUpdates: nil)
        #expect(!controller.openLicenseLink(try #require(URL(string: "https://example.com/"))))
        #expect(!controller.openLicenseLink(URL(fileURLWithPath: "/tmp/a.nonetprofile")))
        // 宛先はメールアドレスの形のときだけ
        controller.supportEmail = "support@nonet.test"
        #expect(controller.supportEmail == "support@nonet.test")
        controller.supportEmail = "support@nonet.test?bcc=x@evil.test"
        #expect(controller.supportEmail == nil)
        controller.supportEmail = ""
        #expect(controller.supportEmail == nil)
    }
}

// MARK: - お問い合わせ

@Suite @MainActor struct SettingsSupportMailTests {
    private let details = SettingsSupportMail.Details(
        version: "1.2.0", build: "34", macOSVersion: "26.1 (25B78)", macModel: "Mac14,2", keyboardType: "JIS"
    )

    @Test func subjectAndBodyHoldOnlyTheListedDetails() throws {
        let mail = SettingsSupportMail(address: "support@nonet.test", details: details)
        #expect(mail.subject == L10n.ui("Nonet \("1.2.0") のお問い合わせ"))
        #expect(mail.body.components(separatedBy: "\n") == [
            "",
            "",
            L10n.ui("下の情報は、調べるためだけに使います。"),
            "Nonet: 1.2.0 (34)",
            "macOS: 26.1 (25B78)",
            "Mac: Mac14,2",
            L10n.ui("キーボード: \("JIS")"),
        ])
        let url = try #require(mail.url)
        #expect(url.scheme == "mailto")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.path == "support@nonet.test")
        #expect(components.queryItems == [URLQueryItem(name: "subject", value: mail.subject), URLQueryItem(name: "body", value: mail.body)])
    }

    /// 件名や本文の & = ? は符号にし、宛先の項目（cc など）を作らない
    @Test func reservedCharactersAreEncoded() throws {
        var odd = details
        odd.version = "1&cc=x@evil.test?"
        odd.build = nil
        let mail = SettingsSupportMail(address: "support@nonet.test", details: odd)
        let url = try #require(mail.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.queryItems?.map(\.name) == ["subject", "body"])
        #expect(components.queryItems?.first?.value == mail.subject)
    }

    @Test func addressesAreChecked() {
        #expect(SettingsSupportMail.isValidAddress("support@nonet.test"))
        #expect(SettingsSupportMail.isValidAddress("first.last+nonet@mail.example.co.jp"))
        for bad in ["", "support", "mailto:support@nonet.test", "a b@nonet.test", "support@nonet.test?cc=x@y.z", "support@nonet"] {
            #expect(!SettingsSupportMail.isValidAddress(bad), "\(bad)")
            #expect(SettingsSupportMail(address: bad, details: details).url == nil)
        }
    }

    @Test func currentDetailsReadThisMac() {
        let current = SettingsSupportMail.currentDetails()
        #expect(!current.macOSVersion.isEmpty)
        #expect(current.macModel != "?")
        #expect(["ANSI", "ISO", "JIS", "?"].contains(current.keyboardType))
    }

    /// ライセンスキーも登録者も本文に入れない
    @Test func theModelOpensTheMailWithoutTheLicense() throws {
        let signed = try SignedLicense(name: "Hanako Suzuki", email: "hanako@example.com")
        let h = try SettingsHarness(verifier: signed.verifier)
        h.model.contactSupport()
        #expect(h.model.supportMail == nil)
        #expect(h.openedURLs.isEmpty)

        h.model.licenseKeyInput = signed.key
        h.model.activateLicense()
        h.model.supportEmail = "support@nonet.test"
        h.model.contactSupport()
        let url = try #require(h.openedURLs.last)
        #expect(url.scheme == "mailto")
        let body = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "body" }?.value)
        #expect(body.contains(L10n.ui("キーボード: \(SettingsSupportMail.currentDetails().keyboardType)")))
        for secret in [signed.key, "Hanako", "hanako@example.com", signed.info.licenseID] {
            #expect(!body.contains(secret), "\(secret)")
        }
    }
}

// MARK: - アンインストール

@MainActor
private final class FakeTrash: SettingsTrashing {
    var existing: Set<URL>
    var failing: Set<URL> = []
    private(set) var events: [String] = []

    init(existing: Set<URL>) {
        self.existing = existing
    }

    func exists(_ url: URL) -> Bool {
        existing.contains(url)
    }

    func moveToTrash(_ url: URL) throws {
        if failing.contains(url) {
            throw CocoaError(.fileWriteNoPermission)
        }
        existing.remove(url)
        events.append("trash \(url.lastPathComponent)")
    }

    func record(_ event: String) {
        events.append(event)
    }
}

@Suite @MainActor struct SettingsUninstallTests {
    private let targets = SettingsUninstallTargets(
        app: URL(fileURLWithPath: "/Applications/Nonet.app", isDirectory: true),
        settingsFolder: URL(fileURLWithPath: "/Users/someone/Library/Application Support/Nonet", isDirectory: true),
        caches: [
            URL(fileURLWithPath: "/Users/someone/Library/Caches/com.iam74k4.Nonet", isDirectory: true),
            URL(fileURLWithPath: "/Users/someone/Library/HTTPStorages/com.iam74k4.Nonet", isDirectory: true),
        ]
    )

    @Test func movesEverythingToTheTrashInOrder() throws {
        let trash = FakeTrash(existing: [targets.app, targets.settingsFolder, targets.caches[0]])
        let loginItem = SettingsFakeLoginItem()
        loginItem.isEnabled = true
        let result = try SettingsUninstaller(trash: trash, targets: targets).run(loginItem: loginItem) { trash.record("stop") }
        #expect(result == SettingsUninstallResult())
        #expect(!loginItem.isEnabled)
        // 保存を書き出してから設定をゴミ箱に入れる（後から書かれてフォルダが作り直されないように）。無いキャッシュは飛ばす
        #expect(trash.events == ["trash Nonet.app", "stop", "trash Nonet", "trash com.iam74k4.Nonet"])
    }

    /// システム設定で許可されていない（許可待ちの）ログイン項目も外す。ゴミ箱に入れた後のアプリの項目が残らないように
    @Test func removesALoginItemWaitingForApproval() throws {
        let trash = FakeTrash(existing: [targets.app])
        let loginItem = SettingsFakeLoginItem()
        loginItem.isWaitingForApproval = true
        let result = try SettingsUninstaller(trash: trash, targets: targets).run(loginItem: loginItem) {}
        #expect(result == SettingsUninstallResult())
        #expect(!loginItem.isWaitingForApproval)
    }

    /// ゴミ箱に入れた後に許可待ちのログイン項目を外せず、残ったら知らせる（システム設定の「ログイン項目」で外してもらう）
    @Test func reportsALoginItemWaitingForApprovalThatStays() throws {
        let trash = FakeTrash(existing: [targets.app])
        let loginItem = SettingsFakeLoginItem()
        loginItem.isWaitingForApproval = true
        loginItem.failure = SettingsFakeLoginError()
        let result = try SettingsUninstaller(trash: trash, targets: targets).run(loginItem: loginItem) {}
        #expect(result.loginItemFailed)
    }

    /// アプリをゴミ箱に入れられずにやめるときは、許可待ちのログイン項目もそのまま（先に外さない）
    @Test func keepsALoginItemWaitingForApprovalWhenTheAppStays() throws {
        let trash = FakeTrash(existing: [targets.app])
        trash.failing = [targets.app]
        let loginItem = SettingsFakeLoginItem()
        loginItem.isWaitingForApproval = true
        #expect(throws: SettingsUninstallError.appNotTrashed) {
            try SettingsUninstaller(trash: trash, targets: targets).run(loginItem: loginItem) {}
        }
        #expect(loginItem.isWaitingForApproval)
    }

    @Test func stopsWithoutChangesWhenTheAppCannotBeTrashed() throws {
        let trash = FakeTrash(existing: [targets.app, targets.settingsFolder])
        trash.failing = [targets.app]
        let loginItem = SettingsFakeLoginItem()
        loginItem.isEnabled = true
        #expect(throws: SettingsUninstallError.appNotTrashed) {
            try SettingsUninstaller(trash: trash, targets: targets).run(loginItem: loginItem) { trash.record("stop") }
        }
        #expect(loginItem.isEnabled)
        #expect(trash.events.isEmpty)
        #expect(trash.existing.contains(targets.settingsFolder))
    }

    @Test func reportsWhatCouldNotBeRemoved() throws {
        let trash = FakeTrash(existing: Set([targets.app, targets.settingsFolder] + targets.caches))
        trash.failing = [targets.caches[1]]
        let loginItem = SettingsFakeLoginItem()
        loginItem.isEnabled = true
        loginItem.failure = SettingsFakeLoginError()
        let result = try SettingsUninstaller(trash: trash, targets: targets).run(loginItem: loginItem) {}
        #expect(result == SettingsUninstallResult(leftovers: [targets.caches[1]], loginItemFailed: true))
    }

    @Test func refusesWhenNotRunningFromAnApp() {
        var notAnApp = targets
        notAnApp.app = URL(fileURLWithPath: "/usr/local/bin/xctest")
        let trash = FakeTrash(existing: [notAnApp.app])
        #expect(throws: SettingsUninstallError.notAnApp) {
            try SettingsUninstaller(trash: trash, targets: notAnApp).run(loginItem: SettingsFakeLoginItem()) {}
        }
        #expect(trash.events.isEmpty)
    }

    /// 確かめてから行い、最後にアクセシビリティの欄を開いて終了する。ライセンスキーと試用の記録には触れない
    @Test func theModelConfirmsTrashesAndQuits() throws {
        let signed = try SignedLicense()
        let h = try SettingsHarness(verifier: signed.verifier)
        h.model.licenseKeyInput = signed.key
        h.model.activateLicense()
        let trialStart = h.licenseStorage.trialStartDate
        let trash = FakeTrash(existing: [targets.app, targets.settingsFolder])
        h.model.uninstaller = SettingsUninstaller(trash: trash, targets: targets)
        var terminated = 0
        h.model.terminate = { terminated += 1 }

        h.model.requestUninstall()
        #expect(h.model.uninstallStep == .confirm)
        #expect(trash.events.isEmpty)
        h.model.uninstall()
        #expect(h.model.uninstallStep == .finished(SettingsUninstallResult()))
        #expect(trash.events == ["trash Nonet.app", "trash Nonet"])
        #expect(h.controller.status == .stopped)
        #expect(h.licenseStorage.licenseKey == signed.key)
        #expect(h.licenseStorage.trialStartDate == trialStart)
        #expect(terminated == 0)

        h.model.finishUninstall()
        #expect(h.permissions.openCount == 1)
        #expect(terminated == 1)
        #expect(h.model.uninstallStep == nil)
    }

    @Test func theModelKeepsRunningWhenTheAppCannotBeTrashed() throws {
        let h = try SettingsHarness()
        let trash = FakeTrash(existing: [targets.app])
        trash.failing = [targets.app]
        h.model.uninstaller = SettingsUninstaller(trash: trash, targets: targets)
        var terminated = 0
        h.model.terminate = { terminated += 1 }
        let status = h.controller.status
        h.model.uninstall()
        #expect(h.model.uninstallStep == .failed)
        #expect(h.controller.status == status)
        #expect(terminated == 0)
    }

    @Test func currentTargetsUseTheBundleAndSettingsFolder() {
        let current = SettingsUninstallTargets.current(arguments: ["Nonet"])
        #expect(current.app == Bundle.main.bundleURL)
        #expect(current.settingsFolder == ConfigurationStore.defaultDirectory)
        #expect(current.caches.map { $0.deletingLastPathComponent().lastPathComponent } == ["Caches", "HTTPStorages"])
        #if DEBUG
        // Debug で --config-dir を渡したときは、そのフォルダ（本物の設定をゴミ箱に入れない）
        let debug = SettingsUninstallTargets.current(arguments: ["Nonet", "--config-dir", "/tmp/nonet-preview"])
        #expect(debug.settingsFolder.path == "/tmp/nonet-preview")
        #endif
    }
}

// MARK: - 試用期間が終わったときのウィンドウ

@Suite(.serialized) @MainActor struct SettingsTrialEndedWindowTests {
    private let purchase = URL(string: "https://example.com/buy")!
    private let today = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func makeController(license: LicenseManager, defaults: UserDefaults? = nil, now: @escaping () -> Date, onRegister: @escaping () -> Void = {}) -> (TrialEndedWindowController, () -> Int) {
        _ = NSApplication.shared
        let controller = TrialEndedWindowController(license: license, purchaseURL: purchase, defaults: defaults, onRegister: onRegister)
        var presented = 0
        controller.present = { _ in presented += 1 }
        controller.now = now
        controller.calendar = calendar
        return (controller, { presented })
    }

    @Test func dueOncePerDay() {
        #expect(TrialEndedPromptRecord.isDue(now: today, lastShown: nil, calendar: calendar))
        #expect(!TrialEndedPromptRecord.isDue(now: today, lastShown: today.addingTimeInterval(-60), calendar: calendar))
        #expect(TrialEndedPromptRecord.isDue(now: today.addingTimeInterval(86_400), lastShown: today, calendar: calendar))
        // 時計を戻して、前に出した日時より前になった
        #expect(TrialEndedPromptRecord.isDue(now: today, lastShown: today.addingTimeInterval(3_600), calendar: calendar))
    }

    @Test func showsAtLaunchWhenExpiredAndAtMostOnceADay() {
        let (license, _) = expiredLicense()
        var now = today
        let (controller, presented) = makeController(license: license, now: { now })
        controller.start()
        #expect(presented() == 1)
        #expect(controller.window != nil)
        #expect(controller.window?.title == L10n.ui("Nonet の試用期間が終了しました"))
        controller.close()
        #expect(controller.window == nil)
        controller.showIfDue()
        controller.entitlementDidChange(.expired)
        #expect(presented() == 1)
        now = today.addingTimeInterval(86_400)
        controller.showIfDue()
        #expect(presented() == 2)
        // 出ている間は重ねて出さない
        now = today.addingTimeInterval(2 * 86_400)
        controller.showIfDue()
        #expect(presented() == 2)
        controller.close()
    }

    @Test func remembersTheDayAcrossLaunches() throws {
        let suite = "NonetTrialEndedTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let (license, _) = expiredLicense()
        let (first, firstPresented) = makeController(license: license, defaults: defaults, now: { today })
        first.start()
        #expect(firstPresented() == 1)
        first.close()
        let (second, secondPresented) = makeController(license: license, defaults: defaults, now: { today.addingTimeInterval(3_600) })
        second.start()
        #expect(secondPresented() == 0)
    }

    @Test func notShownDuringTheTrial() throws {
        let h = try SettingsHarness()
        let (controller, presented) = makeController(license: h.license, now: { today })
        controller.start()
        controller.showIfDue()
        controller.entitlementDidChange(.trial(daysLeft: 1))
        #expect(presented() == 0)
    }

    @Test func buttonsBuyRegisterAndClose() throws {
        let (license, _) = expiredLicense()
        var registered = 0
        let (controller, presented) = makeController(license: license, now: { today }, onRegister: { registered += 1 })
        var opened: [URL] = []
        controller.openURL = { opened.append($0) }
        controller.showIfDue()
        controller.buy()
        #expect(opened == [purchase])
        #expect(controller.window == nil)

        controller.calendar = calendar
        controller.now = { today.addingTimeInterval(86_400) }
        controller.showIfDue()
        controller.register()
        #expect(registered == 1)
        #expect(controller.window == nil)
        #expect(presented() == 2)
    }

    /// ほかの所で登録したら閉じる
    @Test func closesWhenALicenseIsRegistered() throws {
        let signed = try SignedLicense()
        let (license, _) = expiredLicense(verifier: signed.verifier)
        let (controller, _) = makeController(license: license, now: { today })
        controller.showIfDue()
        #expect(controller.window != nil)
        try license.activate(licenseKey: signed.key)
        controller.entitlementDidChange(license.entitlement)
        #expect(controller.window == nil)
    }
}

// MARK: - Info.plist と販売用の値

@Suite("ライセンスのリンクとお問い合わせの Info.plist")
struct SettingsLicenseInfoPlistTests {
    private func infoPlist() throws -> [String: Any] {
        let data = try Data(contentsOf: ShellInfoPlistTests.repositoryRoot.appending(path: "App/Info.plist"))
        return try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    @Test("nonet:// の URL と .nonetlicense のファイルを開ける")
    func urlSchemeAndDocumentType() throws {
        let info = try infoPlist()
        let urlTypes = try #require(info["CFBundleURLTypes"] as? [[String: Any]])
        #expect(urlTypes.flatMap { ($0["CFBundleURLSchemes"] as? [String]) ?? [] } == [SettingsLicenseLink.scheme])

        let exported = try #require(info["UTExportedTypeDeclarations"] as? [[String: Any]])
        let licenseType = try #require(exported.first { $0["UTTypeIdentifier"] as? String == "com.iam74k4.nonet.license" })
        let tags = try #require(licenseType["UTTypeTagSpecification"] as? [String: Any])
        #expect(tags["public.filename-extension"] as? [String] == [SettingsLicenseLink.fileExtension])

        let documents = try #require(info["CFBundleDocumentTypes"] as? [[String: Any]])
        #expect(documents.contains { ($0["LSItemContentTypes"] as? [String]) == ["com.iam74k4.nonet.license"] })
    }

    @Test("お問い合わせの宛先は xcconfig の NONET_SUPPORT_EMAIL から")
    func supportEmailComesFromTheConfig() throws {
        #expect(try infoPlist()["NonetSupportEmail"] as? String == "$(NONET_SUPPORT_EMAIL)")
        let config = try String(contentsOf: ShellInfoPlistTests.repositoryRoot.appending(path: "Config/Nonet.xcconfig"), encoding: .utf8)
        #expect(config.components(separatedBy: .newlines).contains { $0.hasPrefix("NONET_SUPPORT_EMAIL =") })
        let project = try String(contentsOf: ShellInfoPlistTests.repositoryRoot.appending(path: "project.yml"), encoding: .utf8)
        #expect(project.contains("NonetSupportEmail: $(NONET_SUPPORT_EMAIL)"), "project.yml を変えたら xcodegen generate で Info.plist を作り直す")
    }
}
