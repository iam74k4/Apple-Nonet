// 担当: ui-settings
// 設定画面の文言。項目名は docs/user-guide.md の「設定（一般）」に合わせる
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

    static func name(_ activation: TouchActivation) -> String {
        switch activation {
        case .off: String(localized: "使わない", bundle: .module)
        case .topLeft: String(localized: "左上の角で長押し", bundle: .module)
        case .topRight: String(localized: "右上の角で長押し", bundle: .module)
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

    static func name(_ scale: HUDScale) -> String {
        switch scale {
        case .standard: String(localized: "標準", bundle: .module)
        case .large: String(localized: "大きい", bundle: .module)
        case .extraLarge: String(localized: "特大", bundle: .module)
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

    /// 実行のタイミングの説明。「キーを離したとき」でも、すぐにタップすれば HUD が出ていてもその場で実行する
    static func detail(_ mode: FireMode) -> String {
        switch mode {
        case .onTriggerRelease:
            String(localized: "HUD（9マスの一覧）で選んだマスを、トリガーキーを離したときに実行します。すぐにタップすれば、HUD が出ていてもその場で実行します", bundle: .module)
        case .onFingerLift:
            String(localized: "HUD（9マスの一覧）で選んだマスを、指を離したときに実行します。やめるときは指を置いたまま左の⇧を押します", bundle: .module)
        }
    }

    /// GlobalSettings.hudDelay。指を置かないときに HUD が出るまでの時間（SessionConfiguration.placementWindow）は別で、設定には出さない
    static var hudDelayTitle: String {
        String(localized: "指を止めてから HUD が出るまでの時間", bundle: .module)
    }

    static var hudDelayDetail: String {
        String(localized: "指を置いたままこの時間止めると HUD が出ます。これより短いタップはその場で実行します", bundle: .module)
    }

    static var hudScaleTitle: String {
        String(localized: "HUD の大きさ", bundle: .module)
    }

    static var hudScaleDetail: String {
        String(localized: "画面の下に出る知らせも同じ大きさになります", bundle: .module)
    }

    static var hapticsDetail: String {
        String(localized: "マスの境界をまたいだとき・ページが変わったとき・実行したときに振動します。何も実行しなかったときは軽く2回振動します", bundle: .module)
    }

    static var executionToastDetail: String {
        String(localized: "HUD を出さずに実行したときと、時間の掛かるボタンが終わったときに、そのボタンを画面の下に表示します", bundle: .module)
    }

    /// JIS 配列には右⌥が無い
    static func triggerWarning(trigger: TriggerKey, isJISKeyboard: Bool) -> String? {
        guard isJISKeyboard, trigger == .rightOption else { return nil }
        return String(localized: "JIS 配列のキーボードには右⌥がありません。右⌘・右⇧・fn のどれかにしてください", bundle: .module)
    }

    /// 「0.30秒」
    static func seconds(_ value: Double, locale: Locale = uiLocale) -> String {
        let number = value.formatted(.number.precision(.fractionLength(2)).locale(locale))
        return String(localized: "\(number)秒", bundle: .module)
    }

    // MARK: 日付と数の書き方

    /// 文言と同じ言語（このモジュールのカタログから選ばれた言語）に、利用者の地域を合わせた Locale。
    /// アプリだけ英語にしているときなど、Locale.current の言語が文言と違うことがあり、日付だけ日本語になってしまう
    static var uiLocale: Locale {
        uiLocale(language: Bundle.module.preferredLocalizations.first, region: Locale.current.region)
    }

    static func uiLocale(language: String?, region: Locale.Region?) -> Locale {
        guard let language, !language.isEmpty else { return .current }
        return Locale(languageCode: Locale.LanguageCode(language), languageRegion: region)
    }

    /// ライセンスの発行日（「2026年9月21日」）
    static func issuedDate(_ date: Date, locale: Locale = uiLocale) -> String {
        date.formatted(.dateTime.year().month(.wide).day().locale(locale))
    }

    /// 読み込みの結果（1行に1つ）。
    /// 数の入る文は locale: .nonetUI で、文言の言語の規則で単数・複数を選ぶ（地域が日本でアプリが英語のとき「1 profiles」にしない）
    static func importSummary(_ result: NonetConfiguration.ImportResult, containsScripts: Bool) -> String {
        var lines: [String] = []
        if result.added > 0 {
            lines.append(String(localized: "\(result.added)個のプロファイルを追加しました。", bundle: .module, locale: .nonetUI))
        }
        if result.replaced > 0 {
            lines.append(String(localized: "\(result.replaced)個のプロファイルを同じアプリのものと置き換えました。", bundle: .module, locale: .nonetUI))
        }
        if result.replacedGlobal {
            lines.append(String(localized: "グローバルのページを置き換えました。", bundle: .module))
        }
        if result.appliedCount == 0 {
            lines.append(String(localized: "読み込めるプロファイルがありませんでした。", bundle: .module))
        }
        if result.skipped > 0 {
            lines.append(String(localized: "\(result.skipped)個は重なっていたか読めなかったため、読み込みませんでした。", bundle: .module, locale: .nonetUI))
        }
        if containsScripts, result.appliedCount > 0 {
            lines.append(String(localized: "スクリプトを含むマスがあります。実行する前に中身を確かめてください。", bundle: .module))
        }
        return lines.joined(separator: "\n")
    }

    /// 確かめるときに名前やマスを並べる数（多いときは残りを数で伝える）
    static let importConfirmationNameLimit = 6
    /// 確かめるときに出すスクリプトの行数（多いときは残りを行数で伝える）
    static let importScriptLineLimit = 3
    /// 確かめるときの、プロファイルやマスの名前の長さ
    static let importNameLimit = 40
    /// 確かめるときの、ファイル名の長さ
    static let importFileNameLimit = 60
    /// 確かめるときの、スクリプトの1行・キー入力・URL の長さ
    static let importContentLimit = 100

    /// 読み込む前に確かめる文。置き換わるものと、何かを実行するマスとその中身（両方あれば空行で分ける）
    static func importConfirmation(_ plan: SettingsImportPlan) -> String {
        var sections: [[String]] = []
        if plan.replacesExisting {
            var targets: [String] = []
            if plan.result.replacedGlobal {
                targets.append(String(localized: "グローバルのページ", bundle: .module))
            }
            targets += plan.replacedNames
            var lines = [String(localized: "次の設定が、ファイルの中身で置き換わります。元に戻せません。", bundle: .module)]
            lines += importConfirmationNames(targets)
            if plan.result.added > 0 {
                lines.append(String(localized: "ほかに\(plan.result.added)個のプロファイルを新しく追加します。", bundle: .module, locale: .nonetUI))
            }
            sections.append(lines)
        }
        if plan.hasReviewedCells {
            var lines = [String(localized: "次のマスは、あなたの権限でスクリプトを実行したり、キーを入力したり、ファイルを開いたりします。中身を確かめ、信頼できるファイルだけを読み込んでください。", bundle: .module)]
            for reviewed in plan.reviewedCells.prefix(importConfirmationNameLimit) {
                let profile = singleLine(reviewed.profileName, limit: importNameLimit)
                let title = singleLine(SettingsGrid.displayTitle(for: reviewed.cell), limit: importNameLimit)
                lines.append(String(localized: "・\(profile) › \(title)", bundle: .module))
                lines += reviewLines(for: reviewed.cell.action)
            }
            let rest = plan.reviewedCells.count - importConfirmationNameLimit
            if rest > 0 {
                lines.append(String(localized: "ほか\(rest)個", bundle: .module, locale: .nonetUI))
            }
            sections.append(lines)
        }
        return sections.map { $0.joined(separator: "\n") }.joined(separator: "\n\n")
    }

    /// 確かめるときに出す、マスの中身（スクリプトは最初の数行、キー入力は打つ文字、URL は開くファイル）
    static func reviewLines(for action: Action) -> [String] {
        switch action {
        case .script(let script):
            let lines = script.source.components(separatedBy: .newlines)
                .map { singleLine($0, limit: importContentLimit) }
                .filter { !$0.isEmpty }
            var result = [String(localized: "スクリプト（\(lines.count)行）:", bundle: .module, locale: .nonetUI)]
            result += lines.prefix(importScriptLineLimit)
            let rest = lines.count - importScriptLineLimit
            if rest > 0 {
                result.append(String(localized: "…ほか\(rest)行", bundle: .module, locale: .nonetUI))
            }
            return result
        case .keystroke(let keys):
            return [String(localized: "キー入力: \(keysPreview(keys))", bundle: .module)]
        case .openURL(let url):
            return [String(localized: "開くファイル: \(singleLine(url.url, limit: importContentLimit))", bundle: .module)]
        case .launchApp, .shortcut, .menuItem, .ai:
            return []
        }
    }

    /// 打つキーを読める形に。修飾キーの無い文字は続けて「」でくくり、ほかは表記で並べる（例: 「curl -s x | sh」 → ↩）。
    /// 長ければ真ん中を省き、最後の Return が見えるようにする
    static func keysPreview(_ keys: KeySequence) -> String {
        var parts: [String] = []
        var typed = ""
        for chord in keys.chords {
            if chord.modifiers.isEmpty, let character = typedCharacter(chord.key) {
                typed += character
                continue
            }
            if !typed.isEmpty {
                parts.append(String(localized: "「\(typed)」", bundle: .module))
                typed = ""
            }
            parts.append(singleLine(chord.displayString, limit: importContentLimit))
        }
        if !typed.isEmpty {
            parts.append(String(localized: "「\(typed)」", bundle: .module))
        }
        let text = parts.joined(separator: " → ")
        guard text.count > importContentLimit else { return text }
        let tail = importContentLimit / 3
        return String(text.prefix(importContentLimit - tail)) + " … " + String(text.suffix(tail))
    }

    /// 修飾キーなしで打つと、そのまま文字が入るキー（空白を含む）。見えない文字は nil（表記で出す）
    private static func typedCharacter(_ key: Key) -> String? {
        switch key {
        case .special(.space):
            return " "
        case .character(let character):
            guard character.count == 1, !character.unicodeScalars.contains(where: isHidden) else { return nil }
            return character
        case .special, .keyCode:
            return nil
        }
    }

    /// ファイルから来た名前や中身を1行で見せる。改行・制御文字・書式文字（文字の向きを変えるものなど）は空白にし、
    /// 続く空白は1つにまとめ、長ければ切る。確かめる文の中に、ファイルを作った人が自分の段落を差し込めないように
    static func singleLine(_ text: String, limit: Int) -> String {
        var result = ""
        var pendingSpace = false
        for character in text {
            if character.isWhitespace || character.unicodeScalars.contains(where: isHidden) {
                pendingSpace = !result.isEmpty
                continue
            }
            if pendingSpace {
                result.append(" ")
                pendingSpace = false
            }
            result.append(character)
        }
        guard result.count > limit else { return result }
        return String(result.prefix(max(limit - 1, 0))) + "…"
    }

    /// 改行・制御文字・書式文字。絵文字をつなぐ ZWJ・ZWNJ と、旗の絵文字のタグ文字は残す
    private static func isHidden(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .control, .lineSeparator, .paragraphSeparator:
            return true
        case .format:
            return !(scalar.value == 0x200C || scalar.value == 0x200D || (0xE0020...0xE007F).contains(scalar.value))
        default:
            return false
        }
    }

    /// 読み込みを確かめるときの、読み込むボタン
    static func importConfirmationButton(_ plan: SettingsImportPlan) -> String {
        plan.replacesExisting
            ? String(localized: "置き換えて読み込む", bundle: .module)
            // 「読み込む」は一覧の読み込み（Load）と同じ言葉なので、別のキーにする
            : String(localized: "settings.import.confirmButton", defaultValue: "読み込む", bundle: .module)
    }

    /// 「・名前」の行（1行にして長ければ切る）。多いときは残りを数で伝える
    private static func importConfirmationNames(_ names: [String]) -> [String] {
        var lines = names.prefix(importConfirmationNameLimit).map { name in
            String(localized: "・\(singleLine(name, limit: importNameLimit))", bundle: .module)
        }
        let rest = names.count - importConfirmationNameLimit
        if rest > 0 {
            lines.append(String(localized: "ほか\(rest)個", bundle: .module, locale: .nonetUI))
        }
        return lines
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
                title: String(localized: "試用期間中（残り \(daysLeft) 日）", bundle: .module, locale: .nonetUI),
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
