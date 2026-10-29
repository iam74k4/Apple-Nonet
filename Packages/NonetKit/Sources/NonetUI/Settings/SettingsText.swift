// 担当: ui-settings
// 設定画面の文言。項目名は docs/user-guide.md に合わせる
import Foundation
import NonetCore

enum SettingsText {
    // MARK: 選択肢の名前

    static func name(_ trigger: TriggerKey) -> String {
        switch trigger {
        case .rightCommand: String(localized: "右⌘（Command）", bundle: .module)
        case .rightOption: String(localized: "右⌥（Option）", bundle: .module)
        case .rightShift: String(localized: "右⇧（Shift）", bundle: .module)
        case .function: String(localized: "fn（地球儀）", bundle: .module)
        }
    }

    static func name(_ mode: FireMode) -> String {
        switch mode {
        case .onTriggerRelease: String(localized: "キーを離したとき", bundle: .module)
        case .onFingerLift: String(localized: "指を離したとき", bundle: .module)
        }
    }

    static func name(_ position: HUDPosition) -> String {
        switch position {
        case .screenCenter: String(localized: "画面の中央", bundle: .module)
        case .nearCursor: String(localized: "カーソルの近く", bundle: .module)
        }
    }

    static func name(_ strength: HapticStrength) -> String {
        switch strength {
        case .off: String(localized: "オフ", bundle: .module)
        case .light: String(localized: "弱", bundle: .module)
        case .medium: String(localized: "中", bundle: .module)
        case .strong: String(localized: "強", bundle: .module)
        }
    }

    static func name(_ method: CursorLockMethod) -> String {
        switch method {
        case .automatic: String(localized: "自動", bundle: .module)
        case .dropEvents: String(localized: "移動を捨てる", bundle: .module)
        case .decouple: String(localized: "カーソルを切り離す", bundle: .module)
        case .none: String(localized: "固定しない", bundle: .module)
        }
    }

    static func detail(_ method: CursorLockMethod) -> String {
        switch method {
        case .automatic: String(localized: "移動を捨て、ずれたら元の位置に戻します", bundle: .module)
        case .dropEvents: String(localized: "カーソルの移動イベントを捨てるだけです", bundle: .module)
        case .decouple: String(localized: "カーソルとトラックパッドの動きを切り離します", bundle: .module)
        case .none: String(localized: "カーソルは指に合わせて動きます", bundle: .module)
        }
    }

    static func name(_ mode: ScriptRunMode) -> String {
        switch mode {
        case .background: String(localized: "裏で実行", bundle: .module)
        case .terminal: String(localized: "ターミナルで実行", bundle: .module)
        }
    }

    static func name(_ output: AIOutput) -> String {
        switch output {
        case .replaceSelection: String(localized: "選択範囲を置き換える", bundle: .module)
        case .copyToClipboard: String(localized: "クリップボードにコピー", bundle: .module)
        case .showResult: String(localized: "画面に表示", bundle: .module)
        }
    }

    // MARK: 一般

    /// JIS 配列には右⌥が無い
    static func triggerWarning(trigger: TriggerKey, isJISKeyboard: Bool) -> String? {
        guard isJISKeyboard, trigger == .rightOption else { return nil }
        return String(localized: "JIS 配列のキーボードには右⌥がありません。右⌘・右⇧・fn のどれかにしてください", bundle: .module)
    }

    /// 「0.30秒」
    static func seconds(_ value: Double, locale: Locale = .current) -> String {
        let number = value.formatted(.number.precision(.fractionLength(2)).locale(locale))
        return String(localized: "\(number)秒", bundle: .module)
    }

    /// 読み込みの結果（1行に1つ）
    static func importSummary(_ result: NonetConfiguration.ImportResult, containsScripts: Bool) -> String {
        var lines: [String] = []
        if result.added > 0 {
            lines.append(String(localized: "\(result.added)個のプロファイルを追加しました。", bundle: .module))
        }
        if result.replaced > 0 {
            lines.append(String(localized: "\(result.replaced)個のプロファイルを同じアプリのものと置き換えました。", bundle: .module))
        }
        if result.replacedGlobal {
            lines.append(String(localized: "グローバルのページを置き換えました。", bundle: .module))
        }
        if result.appliedCount == 0 {
            lines.append(String(localized: "読み込めるプロファイルがありませんでした。", bundle: .module))
        }
        if result.skipped > 0 {
            lines.append(String(localized: "\(result.skipped)個は重なっていたか読めなかったため、読み込みませんでした。", bundle: .module))
        }
        if containsScripts, result.appliedCount > 0 {
            lines.append(String(localized: "スクリプトを含むマスがあります。実行する前に中身を確かめてください。", bundle: .module))
        }
        return lines.joined(separator: "\n")
    }

    /// 確かめるときに名前を並べる数（多いときは残りを数で伝える）
    static let importConfirmationNameLimit = 6

    /// 読み込むと置き換わるものを確かめる文
    static func importConfirmation(_ plan: SettingsImportPlan) -> String {
        var targets: [String] = []
        if plan.result.replacedGlobal {
            targets.append(String(localized: "グローバルのページ", bundle: .module))
        }
        targets += plan.replacedNames
        var lines = [String(localized: "次の設定が、ファイルの中身で置き換わります。元に戻せません。", bundle: .module)]
        lines += targets.prefix(importConfirmationNameLimit).map { "・\($0)" }
        let rest = targets.count - importConfirmationNameLimit
        if rest > 0 {
            lines.append(String(localized: "ほか\(rest)個", bundle: .module))
        }
        if plan.result.added > 0 {
            lines.append(String(localized: "ほかに\(plan.result.added)個のプロファイルを新しく追加します。", bundle: .module))
        }
        return lines.joined(separator: "\n")
    }

    /// 書き出しや読み込みの失敗。ConfigurationStoreError はその説明、ほかはファイルの問題として伝える
    static func fileError(_ error: any Error, reading: Bool) -> String {
        if let storeError = error as? ConfigurationStoreError, let description = storeError.errorDescription {
            return description
        }
        return reading
            ? String(localized: "ファイルを読み込めませんでした", bundle: .module)
            : String(localized: "ファイルを書き出せませんでした", bundle: .module)
    }

    // MARK: ライセンス

    struct EntitlementSummary: Equatable {
        var symbol: String
        var title: String
        var detail: String
        var isProblem: Bool
    }

    static func summary(_ entitlement: Entitlement) -> EntitlementSummary {
        switch entitlement {
        case .trial(let daysLeft):
            EntitlementSummary(
                symbol: "clock",
                title: String(localized: "試用期間中（残り \(daysLeft) 日）", bundle: .module),
                detail: String(localized: "試用期間中はすべての機能を使えます。購入してライセンスキーを登録すると、ずっと使えます。", bundle: .module),
                isProblem: false
            )
        case .licensed(let info):
            EntitlementSummary(
                symbol: "checkmark.seal",
                title: String(localized: "登録済み", bundle: .module),
                detail: licenseeLine(info),
                isProblem: false
            )
        case .expired:
            EntitlementSummary(
                symbol: "exclamationmark.triangle",
                title: String(localized: "試用期間が終了しました", bundle: .module),
                detail: String(localized: "ライセンスキーを登録すると、また使えるようになります。設定はそのまま残っています。", bundle: .module),
                isProblem: true
            )
        }
    }

    /// 「山田 太郎（taro@example.com）」
    static func licenseeLine(_ info: LicenseInfo) -> String {
        let name = info.licensee.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let email = info.email?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty else {
            return String(localized: "登録者: \(name)", bundle: .module)
        }
        return String(localized: "登録者: \(name)（\(email)）", bundle: .module)
    }

    // MARK: 情報

    /// 「バージョン 1.2（34）」。版が分からなければ nil
    static func version(short: String?, build: String?) -> String? {
        let short = short?.trimmingCharacters(in: .whitespaces).nilIfEmpty
        let build = build?.trimmingCharacters(in: .whitespaces).nilIfEmpty
        switch (short, build) {
        case let (short?, build?) where short != build:
            return String(localized: "バージョン \(short)（\(build)）", bundle: .module)
        case let (short?, _):
            return String(localized: "バージョン \(short)", bundle: .module)
        case let (nil, build?):
            return String(localized: "バージョン \(build)", bundle: .module)
        case (nil, nil):
            return nil
        }
    }

    // MARK: テスト実行

    static func testResult(_ record: ExecutionRecord) -> String {
        if record.succeeded {
            return String(localized: "実行しました", bundle: .module)
        }
        return record.message?.nilIfEmpty ?? String(localized: "実行できませんでした", bundle: .module)
    }
}

/// 状態の帯（権限が無い・トラックパッドが無い など）
struct SettingsStatusBanner: Equatable {
    enum Action: Equatable {
        case requestAccessibility
        case openAccessibilitySettings
        case recheck
        case enable
    }

    struct Button: Equatable {
        var action: Action
        var title: String
    }

    var symbol: String
    var title: String
    var message: String
    var buttons: [Button]

    init?(status: ControllerStatus) {
        switch status {
        case .running, .stopped:
            return nil
        case .needsAccessibility:
            symbol = "lock.shield"
            title = String(localized: "アクセシビリティの許可が必要です", bundle: .module)
            message = String(localized: "システム設定 › プライバシーとセキュリティ › アクセシビリティ で Nonet をオンにしてください。許可されると自動で動き出します。", bundle: .module)
            buttons = [
                Button(action: .requestAccessibility, title: String(localized: "許可を求める", bundle: .module)),
                Button(action: .openAccessibilitySettings, title: String(localized: "システム設定を開く", bundle: .module)),
            ]
        case .noTrackpad:
            symbol = "hand.point.up.left"
            title = String(localized: "マルチタッチのトラックパッドが見つかりません", bundle: .module)
            message = String(localized: "MacBook の内蔵トラックパッドか Magic Trackpad が必要です。Magic Trackpad をつないでも反応しないときは、Nonet を終了して起動し直してください。", bundle: .module)
            buttons = [Button(action: .recheck, title: String(localized: "もう一度確かめる", bundle: .module))]
        case .secureInputActive:
            symbol = "lock"
            title = String(localized: "パスワードの入力中は動きません", bundle: .module)
            message = String(localized: "パスワード欄から離れるか、ターミナル › セキュアキーボード入力 をオフにしてください。", bundle: .module)
            buttons = [Button(action: .recheck, title: String(localized: "もう一度確かめる", bundle: .module))]
        case .disabled:
            symbol = "pause.circle"
            title = String(localized: "Nonet は無効になっています", bundle: .module)
            message = String(localized: "トリガーキーを押しても反応しません。", bundle: .module)
            buttons = [Button(action: .enable, title: String(localized: "有効にする", bundle: .module))]
        }
    }
}

fileprivate extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
