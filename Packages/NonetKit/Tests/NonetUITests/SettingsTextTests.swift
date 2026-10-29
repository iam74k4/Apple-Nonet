// 担当: ui-settings
import Foundation
import NonetCore
@testable import NonetUI
import Testing

@Suite struct SettingsTextTests {
    /// docs/user-guide.md の「設定」の表と同じ選択肢の名前
    @Test func choiceNamesMatchTheUserGuide() {
        #expect(SettingsText.name(FireMode.onTriggerRelease) == L10n.ui("キーを離したとき"))
        #expect(SettingsText.name(FireMode.onFingerLift) == L10n.ui("指を離したとき"))
        #expect(SettingsText.name(HUDPosition.screenCenter) == L10n.ui("画面の中央"))
        #expect(SettingsText.name(HUDPosition.nearCursor) == L10n.ui("カーソルの近く"))
        #expect(HapticStrength.allCases.map(SettingsText.name) == [L10n.ui("オフ"), L10n.ui("弱"), L10n.ui("中"), L10n.ui("強")])
        #expect(CursorLockMethod.allCases.map(SettingsText.name) == [L10n.ui("自動"), L10n.ui("移動を捨てる"), L10n.ui("カーソルを切り離す"), L10n.ui("固定しない")])
        #expect(SettingsText.name(ScriptRunMode.background) == L10n.ui("裏で実行"))
        #expect(SettingsText.name(ScriptRunMode.terminal) == L10n.ui("ターミナルで実行"))
        #expect(AIOutput.allCases.map(SettingsText.name) == [L10n.ui("選択範囲を置き換える"), L10n.ui("クリップボードにコピー"), L10n.ui("画面に表示")])
        #expect(Set(TriggerKey.allCases.map(SettingsText.name)).count == TriggerKey.allCases.count)
        #expect(Set(CursorLockMethod.allCases.map(SettingsText.detail)).count == CursorLockMethod.allCases.count)
    }

    @Test func tabTitles() {
        #expect(SettingsTab.allCases.map(\.title) == [L10n.ui("プロファイル"), L10n.ui("一般"), L10n.ui("ライセンス"), L10n.ui("情報")])
    }

    @Test(arguments: [
        (TriggerKey.rightOption, true, true),
        (.rightOption, false, false),
        (.rightCommand, true, false),
        (.rightShift, true, false),
        (.function, true, false),
    ])
    func jisWarningOnlyForRightOption(trigger: TriggerKey, isJIS: Bool, warns: Bool) {
        #expect((SettingsText.triggerWarning(trigger: trigger, isJISKeyboard: isJIS) != nil) == warns)
    }

    @Test func secondsHaveTwoDecimals() {
        // 数は渡したロケールの書き方、単位はカタログの「%@秒」
        #expect(SettingsText.seconds(0.3, locale: Locale(identifier: "ja_JP")) == L10n.ui("\("0.30")秒"))
        #expect(SettingsText.seconds(0.15, locale: Locale(identifier: "ja_JP")) == L10n.ui("\("0.15")秒"))
        #expect(SettingsText.seconds(0.8, locale: Locale(identifier: "ja_JP")) == L10n.ui("\("0.80")秒"))
    }

    @Test func importSummaryListsEachChange() {
        let result = NonetConfiguration.ImportResult(added: 2, replaced: 1, replacedGlobal: true, skipped: 3)
        let lines = SettingsText.importSummary(result, containsScripts: false).components(separatedBy: "\n")
        #expect(lines == [
            L10n.ui("\(2)個のプロファイルを追加しました。"),
            L10n.ui("\(1)個のプロファイルを同じアプリのものと置き換えました。"),
            L10n.ui("グローバルのページを置き換えました。"),
            L10n.ui("\(3)個は重なっていたか読めなかったため、読み込みませんでした。"),
        ])
    }

    @Test func importSummaryWhenNothingWasApplied() {
        let text = SettingsText.importSummary(NonetConfiguration.ImportResult(skipped: 2), containsScripts: true)
        #expect(text == L10n.ui("読み込めるプロファイルがありませんでした。") + "\n" + L10n.ui("\(2)個は重なっていたか読めなかったため、読み込みませんでした。"))
    }

    @Test func importSummaryWarnsAboutScripts() {
        let text = SettingsText.importSummary(NonetConfiguration.ImportResult(added: 1), containsScripts: true)
        #expect(text.hasSuffix(L10n.ui("スクリプトを含むマスがあります。実行する前に中身を確かめてください。")))
    }

    @Test func fileErrorsUseTheStoreDescription() {
        #expect(SettingsText.fileError(ConfigurationStoreError.notAProfileDocument, reading: true) == L10n.core("Nonet のプロファイルのファイルではありません"))
        #expect(SettingsText.fileError(CocoaError(.fileReadNoPermission), reading: true) == L10n.ui("ファイルを読み込めませんでした"))
        #expect(SettingsText.fileError(CocoaError(.fileWriteNoPermission), reading: false) == L10n.ui("ファイルを書き出せませんでした"))
    }

    @Test func entitlementSummaries() {
        let trial = SettingsText.summary(.trial(daysLeft: 3))
        #expect(trial.title == L10n.ui("試用期間中（残り \(3) 日）"))
        #expect(!trial.isProblem)
        let expired = SettingsText.summary(.expired)
        #expect(expired.title == L10n.ui("試用期間が終了しました"))
        #expect(expired.isProblem)
        let info = LicenseInfo(licenseID: "L-1", licensee: "山田 太郎", email: "taro@example.com", issuedAt: Date(timeIntervalSince1970: 0))
        let licensed = SettingsText.summary(.licensed(info))
        #expect(licensed.title == L10n.ui("登録済み"))
        #expect(licensed.detail == L10n.ui("登録者: \("山田 太郎")（\("taro@example.com")）"))
        var noEmail = info
        noEmail.email = " "
        #expect(SettingsText.licenseeLine(noEmail) == L10n.ui("登録者: \("山田 太郎")"))
    }

    @Test func versionText() {
        #expect(SettingsText.version(short: "1.2", build: "34") == L10n.ui("バージョン \("1.2")（\("34")）"))
        #expect(SettingsText.version(short: "1.2", build: "1.2") == L10n.ui("バージョン \("1.2")"))
        #expect(SettingsText.version(short: "1.2", build: nil) == L10n.ui("バージョン \("1.2")"))
        #expect(SettingsText.version(short: " ", build: "34") == L10n.ui("バージョン \("34")"))
        #expect(SettingsText.version(short: nil, build: nil) == nil)
    }

    @Test func testResultText() {
        let ok = ExecutionRecord(cellTitle: "a", profileName: "b", address: CellAddress(page: 0, index: 0), succeeded: true, message: nil, wasFastTap: false, date: Date())
        #expect(SettingsText.testResult(ok) == L10n.ui("実行しました"))
        var failed = ok
        failed.succeeded = false
        failed.message = "Xcode が見つかりません"
        #expect(SettingsText.testResult(failed) == "Xcode が見つかりません")
        failed.message = ""
        #expect(SettingsText.testResult(failed) == L10n.ui("実行できませんでした"))
    }

    @Test func statusBanners() {
        #expect(SettingsStatusBanner(status: .running) == nil)
        #expect(SettingsStatusBanner(status: .stopped) == nil)
        let accessibility = SettingsStatusBanner(status: .needsAccessibility)
        #expect(accessibility?.buttons.map(\.action) == [.requestAccessibility, .openAccessibilitySettings])
        #expect(SettingsStatusBanner(status: .noTrackpad)?.buttons.map(\.action) == [.recheck])
        #expect(SettingsStatusBanner(status: .secureInputActive)?.buttons.map(\.action) == [.recheck])
        #expect(SettingsStatusBanner(status: .disabled)?.buttons.map(\.action) == [.enable])
    }
}
