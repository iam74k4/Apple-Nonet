// 担当: ui-shell
import Foundation
import NonetCore
import Observation
import os

private let logger = Logger(subsystem: "com.iam74k4.Nonet", category: "ui-shell")

enum OnboardingStep: Int, CaseIterable, Comparable {
    /// ようこそ＋アクセシビリティの許可
    case welcome
    /// プリセットのあるアプリを選ぶ
    case apps
    /// 練習モードで試す
    case practice
    case done

    static func < (lhs: OnboardingStep, rhs: OnboardingStep) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// 案内をどうして開いたか
public enum OnboardingPurpose: Equatable, Sendable {
    /// 初回起動・メニューの「初回の案内をもう一度」
    case guide
    /// アクセシビリティの許可を求める（起動したときに許可が無い・メニューの「アクセシビリティを許可…」）。
    /// 最初の画面の見出しを変える。remindsAtLaunch なら「今後表示しない」を出す
    case permission(remindsAtLaunch: Bool)
}

/// 「アプリを選ぶ」の1行
struct OnboardingAppChoice: Identifiable, Equatable {
    var app: AppReference
    var category: String
    var summary: String
    var isSelected: Bool
    /// もうプロファイルがある（無効にしたものも含む。足すだけのとき）。そのまま残すので選び直せない
    var isConfigured: Bool
    /// あるプロファイルが無効になっている（案内では有効に戻さない）
    var isProfileDisabled = false

    var id: String { app.bundleID }
}

/// 練習の進み具合。HUD から選ぶ → すぐにタップ の順に進む
enum OnboardingPracticeState: Equatable {
    /// 1つ目: HUD を出し、指を滑らせて目標のマスに合わせて実行する（HUD のマスをタップしてもよい）
    case hud
    /// 2つ目: 目標の角をすぐにタップする
    case quickTap
    case succeeded
}

/// 練習でうまくいかなかったときの知らせ
enum OnboardingPracticeFeedback: Equatable {
    /// 違うマスを押した（位置と、そのマスの名前）
    case wrongCell(index: Int, title: String)
    /// HUD の課題で、HUD が出る前に実行された
    case tooQuick
    /// すぐにタップの課題で、HUD から実行した
    case usedHUD
}

/// 練習で押してもらうマス
struct OnboardingPracticeTarget: Equatable {
    var index: Int
    var title: String
}

/// 練習に使うページ。練習の HUD に出るもの（前面のアプリのプロファイルの最初のページ）なので、本物のボタンの名前で案内できる
struct OnboardingPracticePage: Equatable {
    /// すぐにタップしてもらうマス。角を優先する（右上から）
    static let quickTapPreference = [2, 0, 8, 6, 4, 1, 3, 5, 7]
    /// HUD で選んでもらうマス。すぐにタップの右上から離れたところを優先する
    static let hudPreference = [6, 4, 8, 0, 3, 5, 7, 1, 2]

    var profileName: String
    /// 9マスの名前。空きマスは nil
    var titles: [String?]
    var hudTarget: OnboardingPracticeTarget
    var quickTapTarget: OnboardingPracticeTarget

    /// 中身のあるマスが無ければ nil（空きマスは押しても何も記録されないので、練習にならない）
    init?(_ page: ResolvedPage?) {
        guard let page else { return nil }
        let titles = (0..<Page.cellCount).map { index in
            page.cells.indices.contains(index) ? page.cells[index]?.title : nil
        }
        let occupied = Set(titles.indices.filter { titles[$0] != nil })
        guard let quick = Self.quickTapPreference.first(where: occupied.contains) else { return nil }
        // 中身のあるマスが1つしか無ければ、同じマスを違うやり方で押してもらう
        let hud = Self.hudPreference.first { occupied.contains($0) && $0 != quick } ?? quick
        profileName = page.profileName
        self.titles = titles
        hudTarget = OnboardingPracticeTarget(index: hud, title: titles[hud] ?? "")
        quickTapTarget = OnboardingPracticeTarget(index: quick, title: titles[quick] ?? "")
    }
}

/// 練習の後に試してもらう「トラックパッドだけで呼び出す」（角の長押し）
enum OnboardingCornerTrial: Equatable {
    /// 紹介している（まだ試していない）
    case offered
    /// 設定をオンにして、試すのを待っている
    case trying(TouchActivation)
    case succeeded(TouchActivation)
}

/// 練習できない理由。文言とボタンを同じ値から選ぶ
enum OnboardingPracticeBlocker: Equatable {
    /// Nonet を無効にしている
    case disabled
    case needsAccessibility
    case noTrackpad
    case secureInput
    /// いま使うページに中身のあるマスが無い
    case noButtons
    /// 試用期間が終わっていて、練習のタップも実行されなかった
    case licenseRequired

    var message: String {
        switch self {
        case .disabled:
            String(localized: "Nonet が無効になっています。有効にすると試せます", bundle: .module)
        case .needsAccessibility:
            String(localized: "アクセシビリティが許可されていないため、まだ試せません", bundle: .module)
        case .noTrackpad:
            OnboardingModel.noTrackpadMessage
        case .secureInput:
            String(localized: "パスワードの入力中は試せません。パスワード欄から離れてください", bundle: .module)
        case .noButtons:
            String(localized: "いま使うページにボタンがありません。設定でボタンを追加すると試せます", bundle: .module)
        case .licenseRequired:
            String(localized: "試用期間が終了しているため、試せません。ライセンスキーを登録すると試せます", bundle: .module)
        }
    }

    /// その場で直せるならその方法
    var remedy: OnboardingPracticeRemedy? {
        switch self {
        case .disabled: .enableNonet
        case .needsAccessibility: .openAccessibilitySettings
        case .noTrackpad: .recheck
        case .noButtons: .openProfiles
        case .licenseRequired: .openLicense
        case .secureInput: nil
        }
    }
}

enum OnboardingPracticeRemedy: Equatable {
    case enableNonet
    case openAccessibilitySettings
    /// トラックパッドをもう一度探す
    case recheck
    /// 設定の「プロファイル」を開く
    case openProfiles
    /// 設定の「ライセンス」を開く
    case openLicense

    var title: String {
        switch self {
        case .enableNonet: String(localized: "Nonet を有効にする", bundle: .module)
        case .openAccessibilitySettings: String(localized: "システム設定を開く", bundle: .module)
        case .recheck: String(localized: "もう一度確かめる", bundle: .module)
        case .openProfiles: String(localized: "設定を開く", bundle: .module)
        case .openLicense: String(localized: "ライセンスキーを入力…", bundle: .module)
        }
    }
}

/// 「今後表示しない」（起動したときの許可の案内）を覚える。テストと見た目の確認では UserDefaults に書かない
@MainActor
public final class OnboardingReminderPreference {
    static let key = "NonetHidesPermissionReminder"

    private let defaults: UserDefaults?
    private var memory = false

    /// defaults が nil なら、このプロセスの間だけ覚える
    public init(defaults: UserDefaults?) {
        self.defaults = defaults
    }

    public var isHidden: Bool {
        get { defaults?.bool(forKey: Self.key) ?? memory }
        set {
            if let defaults {
                defaults.set(newValue, forKey: Self.key)
            } else {
                memory = newValue
            }
        }
    }
}

/// 起動したときに案内を開くか
public enum OnboardingLaunchGuide: Equatable, Sendable {
    case none
    /// 保存された設定が無かった（初回起動）
    case firstRun
    /// Nonet は有効なのにアクセシビリティが許可されていない。許可の画面で開き直す（「今後表示しない」を選んでいなければ）
    case permissionReminder

    public static func decide(isFirstLaunch: Bool, isEnabled: Bool, isAccessibilityGranted: Bool, isReminderHidden: Bool) -> OnboardingLaunchGuide {
        if isFirstLaunch { return .firstRun }
        guard isEnabled, !isAccessibilityGranted, !isReminderHidden else { return .none }
        return .permissionReminder
    }
}

/// 初回起動の流れ。AppKit に触れないので、偽のサービスでテストできる
@MainActor
@Observable
final class OnboardingModel {
    /// macOS の許可の確認を出してから、出なかったとみなすまでの秒数（ウィンドウがキーのままなら、確認は出ていない）
    static let promptFallbackDelay: TimeInterval = 1.5

    nonisolated static var noTrackpadMessage: String {
        String(localized: "トラックパッドが見つかりません。Magic Trackpad の電源を入れてつなぐと、自動で見つけます（10秒ほど）", bundle: .module)
    }

    private(set) var step: OnboardingStep = .welcome
    private(set) var isAccessibilityGranted: Bool
    private(set) var practice: OnboardingPracticeState = .hud
    /// 練習でうまくいかなかったときの知らせ。課題が進んだら消す
    private(set) var practiceFeedback: OnboardingPracticeFeedback?
    /// 練習ができた後の「キーを使わない方法もあります」。練習ができるまでは nil
    private(set) var cornerTrial: OnboardingCornerTrial?
    /// 角の長押しで試す角
    var cornerChoice: TouchActivation = .topRight
    /// ウィンドウがほかのウィンドウに隠れていない（しまった・画面のロック中も隠れている）
    private(set) var isWindowVisible = true
    /// ウィンドウがキーウィンドウ。ほかのアプリを使っている間は false
    private(set) var isWindowKey = true
    /// 初回起動の案内として開いた。選んだアプリだけのプロファイルで作り直してよい
    let isFirstLaunchGuide: Bool
    /// 案内をどうして開いたか（最初の画面の見出しと「今後表示しない」）
    var purpose: OnboardingPurpose = .guide
    /// 練習のタップが試用期間の終了で断られた（もう一度押して実行されれば消える）。
    /// 知らせは、ライセンスを登録して実行できるようになった時点で出さなくなる（practiceBlocker）
    private(set) var isPracticeRefusedForLicense = false
    /// トラックパッドが見つからない（最初の画面で知らせる。許可より前に分かる）
    private(set) var isTrackpadMissing = false
    /// 完了の画面の「Mac にログインしたら Nonet を自動で起動する」
    var opensAtLogin = true
    /// ログイン時に起動を変えられなかった（システム設定での許可待ちを含む）ときの知らせ
    private(set) var loginItemMessage: String?
    /// メニューバーのアイコンが見えている（完了の画面に入ったときに確かめる）。見えなければ、見つけ方を文で伝える
    private(set) var isStatusItemVisible = true
    /// 「今後表示しない」
    private(set) var hidesReminder = false
    /// 設定を開く（ライセンスの登録など）。ウィンドウの側が入れる
    @ObservationIgnored var onOpenSettings: ((SettingsTab) -> Void)?
    /// VoiceOver に読ませる（テストでは数える）
    @ObservationIgnored var announce: (String) -> Void = { HUDAccessibility.announce($0) }
    /// 少し後に行う（テストでは手で進める）
    @ObservationIgnored var scheduleAfter: (TimeInterval, @escaping @MainActor () -> Void) -> Void = { delay, action in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            MainActor.assumeIsolated { action() }
        }
    }
    /// メニューバーのアイコンが見えているか。ウィンドウの側が入れる
    @ObservationIgnored var statusItemVisibility: () -> Bool = { true }
    /// 「今後表示しない」を覚える場所。nil なら覚えない
    @ObservationIgnored var reminder: OnboardingReminderPreference? {
        didSet { hidesReminder = reminder?.isHidden ?? false }
    }

    @ObservationIgnored private let controller: NonetController
    /// 実行できるか（ライセンス・試用）を見る。@Observable なので、登録すると練習の画面も変わる
    @ObservationIgnored private let license: LicenseManager?
    @ObservationIgnored private let permissions: any PermissionsProviding
    /// この Mac でできることに合わせたプリセット（インストール済みのアプリのもの）。「アプリを選ぶ」で調べ直す
    private var presets: [AppPreset]
    @ObservationIgnored private let installedApps: any InstalledAppsProviding
    @ObservationIgnored private let presetEnvironment: any PresetEnvironmentProviding
    @ObservationIgnored private let frontmostApp: (any FrontmostAppObserving)?
    @ObservationIgnored private let touchSource: (any TouchSource)?
    @ObservationIgnored private let loginItem: (any LoginItemControlling)?
    @ObservationIgnored private let installedLauncherIDs: Set<String>
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var practiceStartedAt: Date?
    /// 練習を始めたときにすでにあった記録（これは数えない）
    @ObservationIgnored private var practiceBaseline: ExecutionRecord?
    /// このウィンドウで macOS の許可の確認を出した。2回目からはシステム設定の欄だけを開く
    @ObservationIgnored private var hasPromptedAccessibility = false
    /// 知らせを出したときに選んでいた「ログイン時に起動」。同じ選択のまま押し直したら閉じる
    @ObservationIgnored private var loginAttempt: Bool?
    /// 選んでいるアプリ（bundleID）。設定済みのものはここに無くても選ばれている扱い
    private var selectedIDs: Set<String>
    /// 案内を開いたとき（作り直した後は作り直したとき）のプロファイル。
    /// ここから変わっていれば利用者が編集したので、作り直さずに足すだけにする
    private var profilesSnapshot: [Profile]

    /// license が nil なら、断られた後は次に実行されるまで知らせを出し続ける。
    /// frontmostApp が nil なら、練習はグローバルのページで案内する。touchSource が nil ならトラックパッドを確かめない。
    /// loginItem が nil なら「ログイン時に起動」を反映しない
    init(
        controller: NonetController,
        license: LicenseManager? = nil,
        permissions: any PermissionsProviding,
        installedApps: any InstalledAppsProviding,
        presetEnvironment: any PresetEnvironmentProviding = FixedPresetEnvironment(),
        frontmostApp: (any FrontmostAppObserving)? = nil,
        touchSource: (any TouchSource)? = nil,
        loginItem: (any LoginItemControlling)? = nil,
        isFirstLaunchGuide: Bool,
        now: @escaping () -> Date = Date.init
    ) {
        self.controller = controller
        self.license = license
        self.permissions = permissions
        self.installedApps = installedApps
        self.presetEnvironment = presetEnvironment
        self.frontmostApp = frontmostApp
        self.touchSource = touchSource
        self.loginItem = loginItem
        self.isFirstLaunchGuide = isFirstLaunchGuide
        self.now = now
        isAccessibilityGranted = permissions.isAccessibilityGranted
        let available = PresetLibrary.apps(for: presetEnvironment.capabilities)
            .filter { installedApps.isInstalled(bundleID: $0.app.bundleID) }
        presets = available
        installedLauncherIDs = Set(
            PresetLibrary.launcherCandidates.map(\.bundleID).filter { installedApps.isInstalled(bundleID: $0) }
        )
        selectedIDs = Set(available.map(\.app.bundleID))
        profilesSnapshot = controller.configuration.profiles
        refreshTrackpad()
    }

    var trigger: TriggerKey {
        controller.configuration.settings.trigger
    }

    var fireMode: FireMode {
        controller.configuration.settings.fireMode
    }

    /// 選んだアプリだけのプロファイルで作り直すか。そうでなければ足りないものを足すだけ。
    /// 初回の案内でも、開いてからプロファイルが変わっていたら（設定で編集したなど）作り直さない
    var replacesProfiles: Bool {
        isFirstLaunchGuide && controller.configuration.profiles == profilesSnapshot
    }

    var choices: [OnboardingAppChoice] {
        let replaces = replacesProfiles
        let profiles = controller.configuration.profiles
        return presets.map { preset in
            let existing = replaces ? nil : Self.profile(forBundleID: preset.app.bundleID, in: profiles)
            return OnboardingAppChoice(
                app: preset.app,
                category: preset.category,
                summary: preset.summary,
                isSelected: existing != nil || selectedIDs.contains(preset.app.bundleID),
                isConfigured: existing != nil,
                isProfileDisabled: existing.map { !$0.isEnabled } ?? false
            )
        }
    }

    var selectedCount: Int {
        choices.filter(\.isSelected).count
    }

    /// もう一度見ているときに、新しく足すアプリの数
    var additionCount: Int {
        choices.filter { $0.isSelected && !$0.isConfigured }.count
    }

    /// 練習の HUD に出るページ。前面のアプリが変わったら描き直すよう、activeProfileName を読んでおく
    var practicePage: OnboardingPracticePage? {
        _ = controller.activeProfileName
        let pages = controller.configuration.resolvedPages(frontmostBundleID: frontmostApp?.current?.app.bundleID)
        return OnboardingPracticePage(pages.first)
    }

    /// 練習できない理由。練習できるなら nil。自分で無効にしているなら、ほかの理由より先に出す
    var practiceBlocker: OnboardingPracticeBlocker? {
        if !controller.configuration.settings.isEnabled {
            return .disabled
        }
        switch controller.status {
        case .needsAccessibility: return .needsAccessibility
        case .noTrackpad: return .noTrackpad
        case .secureInputActive: return .secureInput
        case .running, .disabled, .stopped: break
        }
        if practicePage == nil {
            return .noButtons
        }
        // 断られた後でも、ライセンスキーを登録して実行できるようになっていれば、もう知らせない
        guard isPracticeRefusedForLicense, license?.canExecuteActions != true else { return nil }
        return .licenseRequired
    }

    /// 練習モードにしてよいか。見えていても、ほかのアプリを使っている間は本物を実行する
    var isWindowAttended: Bool {
        isWindowVisible && isWindowKey
    }

    // MARK: - 完了の画面

    /// メニューの「◯◯のボタンを編集…」と同じ文言（完了の画面のこつで、どこから変えるかを伝える）
    var editButtonsTitle: String {
        _ = controller.activeProfileName
        return MenuBarEditTarget.resolve(frontApp: frontmostApp?.current?.app, configuration: controller.configuration).title
    }

    /// 試用期間中なら残りの日数
    var trialDaysLeft: Int? {
        guard case .trial(let daysLeft)? = license?.entitlement else { return nil }
        return daysLeft
    }

    var cornerActivation: TouchActivation {
        controller.configuration.settings.touchActivation
    }

    // MARK: - アクセシビリティ

    /// 1秒ごとに呼ぶ。許可されたらコントローラーに知らせ、最初の画面なら次へ進む。
    /// いま許可されたなら true（ウィンドウはシステム設定の後ろにあるので、呼んだ側が前に出す）
    @discardableResult
    func pollPermission() -> Bool {
        if step == .welcome, isTrackpadMissing {
            refreshTrackpad()
        }
        let granted = permissions.isAccessibilityGranted
        guard granted != isAccessibilityGranted else { return false }
        isAccessibilityGranted = granted
        controller.refreshPermissions()
        if granted, step == .welcome {
            logger.info("アクセシビリティが許可されたので次へ進む")
            announce(String(localized: "アクセシビリティが許可されました。次へ進みます", bundle: .module))
            go(to: .apps)
        } else if granted {
            announce(String(localized: "アクセシビリティが許可されました", bundle: .module))
        }
        return granted
    }

    /// 「システム設定を開く」。最初の1回だけ macOS の確認を出し（一覧に Nonet が載る）、2回目からはシステム設定の欄だけを開く。
    /// 確認とシステム設定を同時に出すと、システム設定の上に「拒否」のある確認が重なる。
    /// 前に確認を出したことがあると macOS はもう出さないので、少し待っても案内のウィンドウがキーのまま（確認に移っていない）なら、
    /// そのときだけシステム設定を開く
    func requestAccessibility() {
        guard !hasPromptedAccessibility else {
            permissions.openAccessibilitySettings()
            return
        }
        hasPromptedAccessibility = true
        permissions.requestAccessibility()
        scheduleAfter(Self.promptFallbackDelay) { [weak self] in
            guard let self, self.isWindowKey, !self.permissions.isAccessibilityGranted else { return }
            logger.info("macOS の確認が出なかったので、システム設定を開く")
            self.permissions.openAccessibilitySettings()
        }
    }

    /// トラックパッドを探し直す（「もう一度確かめる」）
    func recheckTrackpad() {
        controller.refreshPermissions()
        refreshTrackpad()
    }

    private func refreshTrackpad() {
        isTrackpadMissing = touchSource.map { !$0.isAvailable } ?? false
    }

    func setHidesReminder(_ hides: Bool) {
        hidesReminder = hides
        reminder?.isHidden = hides
    }

    // MARK: - 進む・戻る

    func next() {
        switch step {
        case .welcome: go(to: .apps)
        case .apps: applySelection()
        case .practice: go(to: .done)
        case .done: break
        }
    }

    func back() {
        switch step {
        case .welcome: break
        case .apps: go(to: .welcome)
        case .practice: go(to: .apps)
        case .done: go(to: .practice)
        }
    }

    func enableNonet() {
        controller.update { $0.settings.isEnabled = true }
    }

    func resolve(_ remedy: OnboardingPracticeRemedy) {
        switch remedy {
        case .enableNonet: enableNonet()
        case .openAccessibilitySettings: requestAccessibility()
        case .recheck: recheckTrackpad()
        case .openProfiles: onOpenSettings?(.profiles)
        case .openLicense: onOpenSettings?(.license)
        }
    }

    /// ウィンドウが隠れた（ほかのウィンドウの後ろ・しまった）・また見えた
    func setWindowVisible(_ visible: Bool) {
        let wasAttended = isWindowAttended
        isWindowVisible = visible
        attentionChanged(from: wasAttended)
    }

    /// ウィンドウがキーになった・キーでなくなった（ほかのアプリに切り替えたときも）
    func setWindowKey(_ isKey: Bool) {
        let wasAttended = isWindowAttended
        isWindowKey = isKey
        attentionChanged(from: wasAttended)
    }

    /// ウィンドウを閉じるとき。練習モードは必ず戻す
    func close() {
        controller.isPracticeMode = false
        practiceStartedAt = nil
    }

    /// 完了の画面の「完了」「設定を開く」。「ログイン時に起動」の選択を反映し、閉じてよければ true。
    /// システム設定での許可が要る・変えられなかったときは知らせを出して開いたままにする（同じ選択のまま押し直せば閉じる）
    func finish() -> Bool {
        guard step == .done, let loginItem else { return true }
        if let loginAttempt, loginAttempt == opensAtLogin { return true }
        loginAttempt = nil
        guard loginItem.isEnabled != opensAtLogin else {
            loginItemMessage = nil
            return true
        }
        let enabled = opensAtLogin
        do {
            try loginItem.setEnabled(enabled)
            loginItemMessage = nil
            logger.info("案内でログイン時に起動を\(enabled ? "オン" : "オフ", privacy: .public)にした")
            return true
        } catch NonetError.permissionDenied where enabled {
            // 登録はできたが、システム設定の「ログイン項目」で許可されるまで動かない（システム設定はサービスが開く）。設定の一般と同じ文言
            loginItemMessage = String(localized: "システム設定の「ログイン項目」で Nonet を許可すると、ログイン時に起動するようになります", bundle: .module)
        } catch {
            logger.error("ログイン時に起動を変えられませんでした: \(error.localizedDescription, privacy: .public)")
            let reason = error.localizedDescription
            loginItemMessage = enabled
                ? String(localized: "ログイン時に起動するように設定できませんでした（\(reason)）", bundle: .module)
                : String(localized: "ログイン時に起動しないように設定できませんでした（\(reason)）", bundle: .module)
        }
        loginAttempt = enabled
        if let loginItemMessage {
            announce(loginItemMessage)
        }
        return false
    }

    // MARK: - アプリを選ぶ

    func toggle(_ id: OnboardingAppChoice.ID) {
        guard let choice = choices.first(where: { $0.id == id }), !choice.isConfigured else { return }
        if choice.isSelected {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    func setAllSelected(_ selected: Bool) {
        for choice in choices where !choice.isConfigured {
            if selected {
                selectedIDs.insert(choice.id)
            } else {
                selectedIDs.remove(choice.id)
            }
        }
    }

    /// 選んだアプリを反映して、試してみるへ。全体の設定（トリガーなど）は変えない。
    /// どのカードも最初は選ばれているので、そのまま進めばおすすめのまま使うことになる（別の「飛ばす」ボタンは置かない）
    func applySelection() {
        guard step == .apps else { return }
        let addedIDs = Set(choices.filter { $0.isSelected && !$0.isConfigured }.map(\.id))
        let selected = presets.filter { addedIDs.contains($0.app.bundleID) }
        if replacesProfiles {
            let settings = controller.configuration.settings
            var configuration = NonetConfiguration.initial(
                trigger: settings.trigger,
                appPresets: selected,
                installedBundleIDs: installedLauncherIDs,
                dockApps: presetEnvironment.dockApps()
            )
            configuration.settings = settings
            controller.replaceConfiguration(configuration)
            // 戻って選び直すのはよいが、この後に設定で編集したものは消さない
            profilesSnapshot = controller.configuration.profiles
            logger.info("初回の案内で、選んだ \(selected.count) 個のアプリのプロファイルで作り直した")
        } else if !selected.isEmpty {
            controller.update { configuration in
                for preset in selected {
                    configuration.addAppProfile(for: preset.app, preset: preset)
                }
            }
            logger.info("案内で \(selected.count) 個のアプリのプロファイルを足した")
        }
        go(to: .practice)
    }

    // MARK: - 練習

    /// controller.lastExecution が変わったら呼ぶ。練習を始めてからの記録だけを数える。
    /// 実行されなかったもの（試用期間の終了で断られた）は押せたことにしない。
    /// どのページでも、目標と同じ位置のマスなら押せたことにする（2本指でページを替えてしまっても、やり方は合っている）
    func handleExecution(_ record: ExecutionRecord?) {
        guard step == .practice, isWindowAttended, let record, let startedAt = practiceStartedAt,
              record != practiceBaseline, record.date >= startedAt else { return }
        practiceBaseline = record
        guard record.succeeded else {
            if record.message == NonetError.licenseRequired.localizedDescription {
                isPracticeRefusedForLicense = true
            }
            return
        }
        isPracticeRefusedForLicense = false
        switch practice {
        case .hud: handleHUDTask(record)
        case .quickTap: handleQuickTapTask(record)
        case .succeeded: handleCornerTrial(record)
        }
    }

    /// 1つ目: HUD を出してから実行した（wasFastTap が false。HUD のマスをタップしたときも）
    private func handleHUDTask(_ record: ExecutionRecord) {
        guard let target = practicePage?.hudTarget else { return }
        guard record.address.index == target.index else {
            showWrongCell(record, target: target)
            return
        }
        guard !record.wasFastTap else {
            practiceFeedback = .tooQuick
            announce(ShellText.practiceTooQuick)
            return
        }
        practice = .quickTap
        practiceFeedback = nil
        announce(ShellText.practiceHUDDone)
    }

    /// 2つ目: HUD を出さずにすぐ実行した（wasFastTap が true）
    private func handleQuickTapTask(_ record: ExecutionRecord) {
        guard let target = practicePage?.quickTapTarget else { return }
        guard record.address.index == target.index else {
            showWrongCell(record, target: target)
            return
        }
        guard record.wasFastTap else {
            practiceFeedback = .usedHUD
            announce(ShellText.practiceUsedHUD)
            return
        }
        practice = .succeeded
        practiceFeedback = nil
        let current = controller.configuration.settings.touchActivation
        cornerChoice = current == .off ? .topRight : current
        cornerTrial = .offered
        announce(ShellText.practiceQuickTapDone(target))
    }

    private func showWrongCell(_ record: ExecutionRecord, target: OnboardingPracticeTarget) {
        practiceFeedback = .wrongCell(index: record.address.index, title: record.cellTitle)
        announce(ShellText.practiceWrongCell(index: record.address.index, title: record.cellTitle, target: target))
    }

    /// 角の長押しで HUD を出して実行した。記録にはどちらで出したかが無いので、HUD から実行したものを数える
    private func handleCornerTrial(_ record: ExecutionRecord) {
        guard case .trying(let corner) = cornerTrial, !record.wasFastTap else { return }
        cornerTrial = .succeeded(corner)
        announce(ShellText.cornerTrialDone)
    }

    /// 「試してみる」: 選んだ角で「トラックパッドだけで呼び出す」をオンにして、試すのを待つ
    func tryCornerActivation() {
        guard cornerTrial != nil else { return }
        let corner = cornerChoice == .off ? .topRight : cornerChoice
        controller.update { $0.settings.touchActivation = corner }
        cornerTrial = .trying(corner)
        logger.info("案内で、トラックパッドだけで呼び出す設定をオンにした（\(String(describing: corner), privacy: .public)）")
    }

    /// 「オフに戻す」
    func turnOffCornerActivation() {
        guard cornerTrial != nil else { return }
        controller.update { $0.settings.touchActivation = .off }
        cornerTrial = .offered
    }

    private func attentionChanged(from wasAttended: Bool) {
        let attended = isWindowAttended
        guard attended != wasAttended, step == .practice else { return }
        controller.isPracticeMode = attended
        if attended {
            // 離れている間の実行は本物なので、練習には数えない
            practiceBaseline = controller.lastExecution
            practiceStartedAt = now()
        }
    }

    private func go(to newStep: OnboardingStep) {
        guard newStep != step else { return }
        if step == .practice {
            controller.isPracticeMode = false
            practiceStartedAt = nil
        }
        step = newStep
        switch newStep {
        case .practice:
            practice = .hud
            practiceFeedback = nil
            cornerTrial = nil
            isPracticeRefusedForLicense = false
            practiceBaseline = controller.lastExecution
            practiceStartedAt = now()
            controller.isPracticeMode = isWindowAttended
        case .done:
            isStatusItemVisible = statusItemVisibility()
        case .welcome:
            refreshTrackpad()
        case .apps:
            refreshPresets()
        }
    }

    /// claude を調べ終えてから、この Mac でできることに合わせてプリセットを作り直す（カードの説明も変わる）
    private func refreshPresets() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let capabilities = await presetEnvironment.resolvedCapabilities()
            presets = PresetLibrary.apps(for: capabilities).filter { self.installedApps.isInstalled(bundleID: $0.app.bundleID) }
        }
    }

    #if DEBUG
    /// 見た目の確認用（App の --onboarding-step）。アプリを選ぶは今の選択のまま反映する
    func preview(_ target: OnboardingStep) {
        while step < target {
            next()
        }
    }
    #endif

    /// 有効・無効にかかわらず、そのアプリのプロファイル（NonetConfiguration.addAppProfile と同じ探し方）
    nonisolated static func profile(forBundleID bundleID: String, in profiles: [Profile]) -> Profile? {
        let key = bundleIDKey(bundleID)
        guard !key.isEmpty else { return nil }
        return profiles.first { profile in
            profile.app.map { bundleIDKey($0.bundleID) == key } == true
        }
    }

    private nonisolated static func bundleIDKey(_ bundleID: String) -> String {
        bundleID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
