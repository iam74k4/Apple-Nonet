// 担当: ui-shell
import Foundation
import NonetCore

/// メニューの「◯◯のボタンを編集…」で開くもの。メニューを開いたときの前面のアプリで決める
enum MenuBarEditTarget: Equatable {
    /// 前面のアプリのプロファイルがある（無効にしたものも含む）。name はプロファイルの名前
    case app(AppReference, name: String)
    /// 前面のアプリのプロファイルが無い。選ぶと作る
    case newApp(AppReference)
    /// 前面のアプリが分からない・プロファイルを自動で切り替えない設定
    case global

    /// 開くアプリ。グローバルなら nil
    var app: AppReference? {
        switch self {
        case .app(let app, _), .newApp(let app): app
        case .global: nil
        }
    }

    var title: String {
        switch self {
        case .app(_, let name):
            String(localized: "\(name) のマスを編集…", bundle: .module)
        case .newApp(let app):
            String(localized: "\(Self.displayName(app)) のマスを作る…", bundle: .module)
        case .global:
            String(localized: "グローバルのマスを編集…", bundle: .module)
        }
    }

    /// frontApp は Nonet を数えない前面のアプリ（メニューを開いても Nonet は前面にならない）
    static func resolve(frontApp: AppReference?, configuration: NonetConfiguration) -> MenuBarEditTarget {
        guard let frontApp,
              !frontApp.bundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .global }
        if let profile = OnboardingModel.profile(forBundleID: frontApp.bundleID, in: configuration.profiles) {
            return .app(frontApp, name: profile.name)
        }
        return .newApp(frontApp)
    }

    /// 名前が空なら bundle ID（プロファイルの名前と同じ決め方）
    static func displayName(_ app: AppReference) -> String {
        let name = app.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? app.bundleID : name
    }
}

/// メニューバーに出すものを決める材料（NonetController と LicenseManager から集める）
struct MenuBarState: Equatable {
    var status: ControllerStatus
    var isEnabled: Bool
    var activeProfileName: String?
    /// activeProfileName がグローバルのプロファイル
    var isGlobalProfileActive: Bool
    var notice: String?
    var entitlement: Entitlement
    var canCheckForUpdates: Bool
    /// 定期の確認で見つかったアップデートを、まだ見せていない（Sparkle の控えめな知らせ）
    var isUpdateAvailable: Bool
    /// 「◯◯のボタンを編集…」
    var editTarget: MenuBarEditTarget
    /// 前面のアプリで Nonet を使わない設定にしている（メニューの「このアプリでは使わない」の印）
    var isTurnedOffInFrontApp: Bool
    /// 購入ページがある（無ければ「Nonet を購入…」を出さない）
    var canPurchase: Bool
    /// 利用ガイドのページがある
    var hasGuide: Bool
    /// 最近実行したボタン（新しい順。メニューの「最近の実行」）
    var recentRuns: [ExecutionRecord] = []
    /// 実行中の、止められるボタン（始めた順。メニューの「実行中の「◯◯」を止める」）
    var runningActions: [RunningAction] = []
    /// メニューの先頭の早見表（前面のアプリで9マスを開いたときに出るマス）。nil なら出さない
    var cheatSheet: MenuBarCheatSheet?

    init(
        status: ControllerStatus,
        isEnabled: Bool,
        activeProfileName: String? = nil,
        isGlobalProfileActive: Bool = false,
        notice: String? = nil,
        entitlement: Entitlement,
        canCheckForUpdates: Bool = false,
        isUpdateAvailable: Bool = false,
        editTarget: MenuBarEditTarget = .global,
        isTurnedOffInFrontApp: Bool = false,
        canPurchase: Bool = false,
        hasGuide: Bool = false
    ) {
        self.status = status
        self.isEnabled = isEnabled
        self.activeProfileName = activeProfileName
        self.isGlobalProfileActive = isGlobalProfileActive
        self.notice = notice
        self.entitlement = entitlement
        self.canCheckForUpdates = canCheckForUpdates
        self.isUpdateAvailable = isUpdateAvailable
        self.editTarget = editTarget
        self.isTurnedOffInFrontApp = isTurnedOffInFrontApp
        self.canPurchase = canPurchase
        self.hasGuide = hasGuide
    }

    @MainActor
    init(
        controller: NonetController,
        license: LicenseManager,
        canCheckForUpdates: Bool,
        isUpdateAvailable: Bool = false,
        frontApp: AppReference? = nil,
        links: AppLinks = AppLinks()
    ) {
        let active = controller.activeProfileName
        defer {
            recentRuns = controller.recentExecutions
            runningActions = controller.runningActions
            // 許可が無い・無効にしているときも出す（何が入っているかを見るだけなので）
            cheatSheet = MenuBarCheatSheet(frontApp: frontApp, configuration: controller.configuration)
        }
        self.init(
            status: controller.status,
            isEnabled: controller.configuration.settings.isEnabled,
            activeProfileName: active,
            isGlobalProfileActive: active != nil && active == controller.configuration.globalProfile.name,
            notice: controller.notice,
            entitlement: license.entitlement,
            canCheckForUpdates: canCheckForUpdates,
            isUpdateAvailable: isUpdateAvailable,
            editTarget: MenuBarEditTarget.resolve(frontApp: frontApp, configuration: controller.configuration),
            isTurnedOffInFrontApp: controller.configuration.isTurnedOff(forBundleID: frontApp?.bundleID),
            canPurchase: links.purchase != nil,
            hasGuide: links.support != nil
        )
    }
}

/// アイコンの見た目
enum MenuBarIconState: Equatable, CaseIterable {
    case normal
    /// 無効にしている・止まっている
    case disabled
    /// 権限が無い・トラックパッドが無い・パスワード入力中・試用終了（間近を含む）・知らせたい問題がある
    case attention
    /// 普段どおり動いていて、定期の確認で見つかったアップデートがある（メニューバーのアイコンだけ。メニューの状態の行には使わない）
    case updateAvailable
}

/// メニューの先頭の行に出す状態。理由ごとに分け、文とアイコンを同じ値から選ぶ
enum MenuBarStatus: Equatable {
    /// 自分で無効にしている
    case off
    case stopped
    case needsAccessibility
    case noTrackpad
    case secureInput
    case trialEnded
    /// 試用期間の終わりが近い（MenuBarModel.trialWarningDays 日以内）
    case trialEnding(daysLeft: Int)
    case running
}

/// メニューの1行
enum MenuBarEntry: Equatable {
    case status(String, MenuBarIconState)
    /// 前面のアプリで9マスを開いたときに出るマスの早見表。押したマスを設定で開く。
    /// 「このアプリでは使わない」アプリでは、マスの代わりにそう言う1行
    case cheatSheet(MenuBarCheatSheet)
    case notice(String)
    case dismissNotice
    case requestAccessibility
    /// 実行中のボタン（裏で実行するスクリプト・ショートカット・AI）を止める
    case stopRunning(RunningAction)
    case separator
    case toggleEnabled(isOn: Bool)
    case openSettings
    /// 「Xcode のボタンを編集…」「Pages のボタンを作る…」「グローバルのボタンを編集…」
    case editButtons(MenuBarEditTarget)
    /// 前面のアプリでだけ Nonet を使わない（押すと切り替える）。アプリが分からないときは出さない
    case turnOffInApp(AppReference, isOn: Bool)
    case showOnboarding
    /// 最近実行したボタン（新しい順）。選ぶと設定でそのボタンを開く
    case recentRuns([ExecutionRecord])
    /// 利用ガイドのページを開く
    case userGuide
    /// 登録済みのとき。選ぶと設定の「ライセンス」を開く
    case license(String)
    /// 試用中・試用の終了の知らせ（押せない行）。すぐ下の「ライセンスキーを入力…」と同じことをする項目を2つ並べない
    case trialInfo(String)
    /// 購入ページを開く
    case purchase
    /// 設定の「ライセンス」を開く
    case enterLicenseKey
    case checkForUpdates
    /// 見つかったアップデートを見せる（「アップデートを確認」の代わり）
    case updateAvailable
    case quit

    /// メニューに出す文字
    var title: String {
        switch self {
        case .status(let text, _): text
        case .cheatSheet(let sheet): sheet.turnedOffText ?? sheet.title
        case .notice(let text): text
        case .dismissNotice: String(localized: "この知らせを消す", bundle: .module)
        case .requestAccessibility: String(localized: "アクセシビリティを許可…", bundle: .module)
        case .stopRunning(let running):
            String(localized: "実行中の「\(SettingsText.singleLine(running.cellTitle, limit: MenuBarModel.runningTitleLimit))」を止める", bundle: .module)
        case .separator: ""
        case .toggleEnabled: String(localized: "Nonet を有効にする", bundle: .module)
        case .openSettings: String(localized: "設定…", bundle: .module)
        case .editButtons(let target): target.title
        case .turnOffInApp: String(localized: "このアプリでは使わない", bundle: .module)
        case .showOnboarding: String(localized: "初回の案内をもう一度", bundle: .module)
        case .recentRuns: String(localized: "最近の実行", bundle: .module)
        case .userGuide: String(localized: "利用ガイド", bundle: .module)
        case .license(let text): text
        case .trialInfo(let text): text
        case .purchase: String(localized: "Nonet を購入…", bundle: .module)
        case .enterLicenseKey: String(localized: "ライセンスキーを入力…", bundle: .module)
        case .checkForUpdates: String(localized: "アップデートを確認", bundle: .module)
        case .updateAvailable: String(localized: "アップデートがあります…", bundle: .module)
        case .quit: String(localized: "終了", bundle: .module)
        }
    }
}

/// メニューバーの状態の文言・アイコン・メニューの並び。AppKit に触れない
enum MenuBarModel {
    /// 「最近の実行」の1行の文字数の上限（長い理由やボタンの名前で、メニューを画面の幅まで広げない）
    static let recentRunTitleLimit = 80
    /// 「実行中の「◯◯」を止める」の◯◯の文字数の上限
    static let runningTitleLimit = 40

    /// 「最近の実行」の1行。「✓ Xcode › ビルド」。失敗なら「✗」と理由の1行目、止めたものは「■」と「止めました」を添える。
    /// 1行にまとめ、recentRunTitleLimit 文字で切る（理由の全文は、選ぶと結果のパネルに出る）
    static func recentRunTitle(_ record: ExecutionRecord, in configuration: NonetConfiguration? = nil) -> String {
        let mark = record.succeeded ? "✓" : record.wasStopped ? "■" : "✗"
        let base = String(localized: "\(mark) \(record.profileName) › \(cellTitle(of: record, in: configuration))", bundle: .module)
        guard !record.succeeded,
              let reason = record.message?.split(separator: "\n").first.map(String.init),
              !reason.isEmpty else { return SettingsText.singleLine(base, limit: recentRunTitleLimit) }
        return SettingsText.singleLine(String(localized: "\(base) — \(reason)", bundle: .module), limit: recentRunTitleLimit)
    }

    /// 試用期間の残りがこの日数以下なら、アイコンに印を付けて状態の行で知らせる
    static let trialWarningDays = 3

    /// 状態の行に出す理由。自分で無効にしているなら、ほかの問題より「無効」を見せる。
    /// 動けない理由（許可・トラックパッド・パスワード入力中）は、試用期間より先に見せる（直さないと試せない）
    static func status(for state: MenuBarState) -> MenuBarStatus {
        if !state.isEnabled { return .off }
        switch state.status {
        case .disabled: return .off
        case .stopped: return .stopped
        case .needsAccessibility: return .needsAccessibility
        case .noTrackpad: return .noTrackpad
        case .secureInputActive: return .secureInput
        case .running: break
        }
        switch state.entitlement {
        case .expired:
            return .trialEnded
        case .trial(let daysLeft) where daysLeft <= trialWarningDays:
            return .trialEnding(daysLeft: daysLeft)
        case .trial, .licensed:
            return .running
        }
    }

    static func iconState(for state: MenuBarState) -> MenuBarIconState {
        switch status(for: state) {
        case .off, .stopped:
            .disabled
        case .needsAccessibility, .noTrackpad, .secureInput, .trialEnded, .trialEnding:
            .attention
        case .running:
            state.notice == nil ? .normal : .attention
        }
    }

    /// メニューの先頭に出す状態の文。確かめてほしいことがあれば、その理由
    static func statusText(for state: MenuBarState) -> String {
        switch status(for: state) {
        case .off:
            return String(localized: "Nonet は無効です", bundle: .module)
        case .stopped:
            return String(localized: "停止しています", bundle: .module)
        case .needsAccessibility:
            return String(localized: "アクセシビリティの許可が必要です", bundle: .module)
        case .noTrackpad:
            return String(localized: "トラックパッドが見つかりません", bundle: .module)
        case .secureInput:
            return String(localized: "パスワード入力中は使えません", bundle: .module)
        case .trialEnded:
            return String(localized: "試用期間が終了しました", bundle: .module)
        case .trialEnding(let daysLeft):
            // 数で文が変わる（1 day / 2 days）ので、文言の言語の規則で選ぶ
            return String(localized: "試用期間は残り\(daysLeft)日です", bundle: .module, locale: .nonetUI)
        case .running:
            guard let name = state.activeProfileName, !name.isEmpty else {
                return String(localized: "動作中", bundle: .module)
            }
            // 「このアプリでは使わない」アプリが前面: どのプロファイルも使っていない（ページの一覧はグローバルに戻っているが、開かない）
            if state.isTurnedOffInFrontApp {
                return String(localized: "このアプリでは使いません", bundle: .module)
            }
            return state.isGlobalProfileActive
                ? String(localized: "グローバルのプロファイル", bundle: .module)
                : String(localized: "\(name) のプロファイル", bundle: .module)
        }
    }

    /// 最近の実行の項目の VoiceOver の読み上げ。✓・✗ の記号ではなく、成功・失敗を言葉で言う（記号の名前を読ませない）
    static func recentRunAccessibilityLabel(_ record: ExecutionRecord, in configuration: NonetConfiguration? = nil) -> String {
        let title = cellTitle(of: record, in: configuration)
        if record.wasStopped {
            return String(localized: "止めました: \(record.profileName) › \(title)", bundle: .module)
        }
        let base = record.succeeded
            ? String(localized: "成功: \(record.profileName) › \(title)", bundle: .module)
            : String(localized: "失敗: \(record.profileName) › \(title)", bundle: .module)
        guard !record.succeeded,
              let reason = record.message?.split(separator: "\n").first.map(String.init),
              !reason.isEmpty else { return base }
        return String(localized: "\(base) — \(reason)", bundle: .module)
    }

    /// 実行したマスの名前。表示名の無いマスは、いまの設定のそのマスのアクションの説明（設定の格子・早見表と同じ。「」と出さない）
    static func cellTitle(of record: ExecutionRecord, in configuration: NonetConfiguration?) -> String {
        guard record.cellTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let configuration, let id = record.profileID, let profile = configuration.profile(id: id),
              let cell = SettingsGrid.cell(at: record.address, in: profile) else { return record.cellTitle }
        return SettingsGrid.displayTitle(for: cell)
    }

    static func licenseText(for entitlement: Entitlement) -> String {
        switch entitlement {
        case .trial(let daysLeft):
            // 数で文が変わる（1 day / 2 days）ので、文言の言語の規則で選ぶ
            String(localized: "試用期間：残り\(daysLeft)日", bundle: .module, locale: .nonetUI)
        case .licensed:
            String(localized: "登録済み", bundle: .module)
        case .expired:
            String(localized: "試用期間が終了しました", bundle: .module)
        }
    }

    /// メニューバーのアイコン。普段どおりのときだけ、見つかったアップデートを印で知らせる
    /// （Nonet は前に出ないので、Sparkle の画面の代わりにここで気づいてもらう。問題や無効の見た目の方を優先する）
    static func buttonIconState(for state: MenuBarState) -> MenuBarIconState {
        let base = iconState(for: state)
        return base == .normal && state.canCheckForUpdates && state.isUpdateAvailable ? .updateAvailable : base
    }

    /// アイコンの説明（VoiceOver とツールチップ）
    static func accessibilityDescription(for state: MenuBarState) -> String {
        switch buttonIconState(for: state) {
        case .normal: String(localized: "Nonet", bundle: .module)
        case .disabled: String(localized: "Nonet（無効）", bundle: .module)
        case .attention: String(localized: "Nonet（確認が必要）", bundle: .module)
        case .updateAvailable: String(localized: "Nonet（アップデートがあります）", bundle: .module)
        }
    }

    static func entries(for state: MenuBarState) -> [MenuBarEntry] {
        let status = status(for: state)
        var entries: [MenuBarEntry] = [.status(statusText(for: state), iconState(for: state))]
        if status == .needsAccessibility {
            entries.append(.requestAccessibility)
        }
        if let notice = state.notice, !notice.isEmpty {
            entries += [.notice(notice), .dismissNotice]
        }
        // 実行中のボタンを止める項目は、状態の行のすぐ下（長く掛かっているときに、すぐ見つかるように）
        entries += state.runningActions.map(MenuBarEntry.stopRunning)
        // 早見表は状態の行（と、その下の許可・知らせ）のすぐ下。直すことのある行を押し下げない
        if let sheet = state.cheatSheet {
            entries += [.separator, .cheatSheet(sheet)]
        }
        entries += [
            .separator,
            .toggleEnabled(isOn: state.isEnabled),
            .separator,
            .openSettings,
            .editButtons(state.editTarget),
        ]
        if let app = state.editTarget.app {
            entries.append(.turnOffInApp(app, isOn: state.isTurnedOffInFrontApp))
        }
        if !state.recentRuns.isEmpty {
            entries.append(.recentRuns(state.recentRuns))
        }
        entries.append(.showOnboarding)
        if state.hasGuide {
            entries.append(.userGuide)
        }
        entries.append(.separator)
        entries += licenseEntries(for: state, status: status)
        if state.canCheckForUpdates {
            entries.append(state.isUpdateAvailable ? .updateAvailable : .checkForUpdates)
        }
        entries += [.separator, .quit]
        return entries
    }

    /// 試用中と試用の終了後は、購入とライセンスキーの入力をすぐに選べるようにする。
    /// 状態の行がもう試用期間のことを言っていれば、同じ知らせは繰り返さない
    private static func licenseEntries(for state: MenuBarState, status: MenuBarStatus) -> [MenuBarEntry] {
        if case .licensed = state.entitlement {
            return [.license(licenseText(for: state.entitlement))]
        }
        var entries: [MenuBarEntry] = []
        switch status {
        case .trialEnded, .trialEnding:
            break
        default:
            entries.append(.trialInfo(licenseText(for: state.entitlement)))
        }
        if state.canPurchase {
            entries.append(.purchase)
        }
        entries.append(.enterLicenseKey)
        return entries
    }
}
