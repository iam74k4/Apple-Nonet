// 担当: ui-shell
import Foundation
import NonetCore
import Observation
import os

private let logger = Logger(subsystem: "com.iam74k4.Nonet", category: "ui-shell")

enum OnboardingStep: Int, CaseIterable, Comparable {
    /// ようこそ＋アクセシビリティの許可
    case welcome
    /// 練習モードで試す
    case practice

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

/// 練習の進み具合。マスで離して実行する → 外枠で離してやめる の順に進む
enum OnboardingPracticeState: Equatable {
    /// 1つ目: 上の縁から指を滑らせて開き、目標のマスまで滑らせて離す
    case run
    /// 2つ目: もう一度開き、外枠まで滑らせて離す（何も実行しない）
    case cancel
    case succeeded
}

/// 練習でうまくいかなかったときの知らせ
enum OnboardingPracticeFeedback: Equatable {
    /// 違うマスを実行した（位置と、そのマスの名前）
    case wrongCell(index: Int, title: String)
    /// やめる課題で、マスを実行した
    case ranInsteadOfCancelling(title: String)
    /// 開いて離したが、何も実行されなかった（理由別に、どうすればよいかを知らせる）。whileCancelling は、やめる課題の途中
    case notRun(SessionCancellation, whileCancelling: Bool)
}

/// 練習で選んでもらうマス
struct OnboardingPracticeTarget: Equatable {
    var index: Int
    var title: String
    /// 少し長く止めてから実行するマス。そればかりのページでは、これを練習に使うので、止める手順も案内する
    var requiresHold = false
}

/// 練習に使うページ。練習の HUD に出るもの（前面のアプリのプロファイルの最初のページ）なので、本物のボタンの名前で案内できる
struct OnboardingPracticePage: Equatable {
    /// 選んでもらうマス。開くとポインタは真ん中にあり、上の縁から入ってきた指をそのまま下へ滑らせると届く下の鍵を最初に、
    /// 斜め下・横・上の順。真ん中の鍵は、一度外へ出てから戻す必要があるので最後
    static let runPreference = [7, 8, 6, 5, 3, 1, 2, 0, 4]

    var profileName: String
    /// 9マスの名前。空きマスは nil
    var titles: [String?]
    var runTarget: OnboardingPracticeTarget

    /// 中身のあるマスが無ければ nil（空きマスで離しても何も記録されないので、練習にならない）
    init?(_ page: ResolvedPage?) {
        guard let page else { return nil }
        // 表示名の無いマスは、アクションの説明（設定の格子と同じ。練習の文や図に「」と出さない）
        let titles = (0..<Page.cellCount).map { index in
            page.cells.indices.contains(index) ? page.cells[index].map(SettingsGrid.displayTitle(for:)) : nil
        }
        let occupied = Set(titles.indices.filter { titles[$0] != nil })
        // 少し長く止めてから実行するマス（Cell.requiresHold）は、最初の練習には使わない（そればかりなら使う）
        let ordinary = occupied.filter { page.cells.indices.contains($0) && page.cells[$0]?.requiresHold != true }
        guard let run = Self.runPreference.first(where: (ordinary.isEmpty ? occupied : ordinary).contains) else { return nil }
        profileName = page.profileName
        self.titles = titles
        runTarget = OnboardingPracticeTarget(
            index: run,
            title: titles[run] ?? "",
            requiresHold: page.cells.indices.contains(run) && page.cells[run]?.requiresHold == true
        )
    }
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
    /// 試用期間が終わっていて、9マスが開かない
    case licenseRequired
    /// 案内のウィンドウを使っていない（キーでない・隠れている）。練習モードにならず、開くとマスを本当に実行する
    /// （許可した後のシステム設定が前面のままのときなど）
    case notAttended

    var message: String {
        switch self {
        case .disabled:
            String(localized: "Nonet が無効になっています。有効にすると試せます。", bundle: .module)
        case .needsAccessibility:
            String(localized: "アクセシビリティが許可されていないため、まだ試せません", bundle: .module)
        case .noTrackpad:
            OnboardingModel.noTrackpadMessage
        case .secureInput:
            String(localized: "パスワードの入力中は試せません。パスワード欄から離れてください。", bundle: .module)
        case .noButtons:
            String(localized: "いま使うページのマスはすべて空いています。設定でマスにアクションを入れると試せます。", bundle: .module)
        case .licenseRequired:
            String(localized: "試用期間が終了しているため、試せません。ライセンスキーを登録すると試せます。", bundle: .module)
        case .notAttended:
            String(localized: "このウィンドウをクリックすると練習を始めます。ほかのアプリを使っている間は、マスを本当に実行します。", bundle: .module)
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
        case .secureInput, .notAttended: nil
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

/// 初回起動の流れ（許可 → 練習）。プロファイルは起動時に入れたプリセットのまま（要らないものは設定で消す）。
/// AppKit に触れないので、偽のサービスでテストできる
@MainActor
@Observable
final class OnboardingModel {
    /// macOS の許可の確認を出してから、出なかったとみなすまでの秒数（ウィンドウがキーのままなら、確認は出ていない）
    static let promptFallbackDelay: TimeInterval = 1.5

    nonisolated static var noTrackpadMessage: String {
        String(localized: "トラックパッドが見つかりません。Magic Trackpad の電源を入れてつなぐと、自動で見つけます（10秒ほど）。", bundle: .module)
    }

    private(set) var step: OnboardingStep = .welcome
    private(set) var isAccessibilityGranted: Bool
    private(set) var practice: OnboardingPracticeState = .run
    /// 練習でうまくいかなかったときの知らせ。課題が進んだら消す
    private(set) var practiceFeedback: OnboardingPracticeFeedback?
    /// ウィンドウがほかのウィンドウに隠れていない（しまった・画面のロック中も隠れている）
    private(set) var isWindowVisible = true
    /// ウィンドウがキーウィンドウ。ほかのアプリを使っている間は false
    private(set) var isWindowKey = true
    /// 案内をどうして開いたか（最初の画面の見出しと「今後表示しない」）
    var purpose: OnboardingPurpose = .guide
    /// トラックパッドが見つからない（最初の画面で知らせる。許可より前に分かる）
    private(set) var isTrackpadMissing = false
    /// 練習の画面の「Mac にログインしたら Nonet を自動で起動する」。初回起動では最初から選んでおき、案内を閉じるときに反映する
    var opensAtLogin: Bool {
        didSet { hasChosenLoginItem = true }
    }
    /// 案内の中で「ログイン時に起動」を選び直した。選び直さず、初回起動の勧めでもなければ、閉じるときに変えない
    /// （案内を開いている間に設定の「一般」で変えたものを戻さない）
    private var hasChosenLoginItem = false
    /// 初回起動で「ログイン時に起動」を勧めている（選んだ状態で始める）。同じ起動で開き直した案内では勧めない
    private let recommendsLoginItem: Bool
    /// ディスクイメージなどの一時的な場所から動いているか（テストでは決める）
    private let isTemporaryCopy: () -> Bool
    /// ログイン時に起動を変えられなかった（システム設定での許可待ちを含む）ときの知らせ
    private(set) var loginItemMessage: String?
    /// メニューバーのアイコンが見えている（練習の画面に入ったときに確かめる）。見えなければ、見つけ方を文で伝える
    private(set) var isStatusItemVisible = true
    /// 「今後表示しない」
    private(set) var hidesReminder = false
    /// 設定を開く（ライセンスの登録など）。ウィンドウの側が入れる
    @ObservationIgnored var onOpenSettings: ((SettingsTab) -> Void)?
    /// VoiceOver に読ませる（テストでは数える）
    @ObservationIgnored var announce: (String) -> Void = { HUDAccessibility.announce($0) }
    /// メニューバーのアイコンが見えているか。ウィンドウの側が入れる
    @ObservationIgnored var statusItemVisibility: () -> Bool = { true }
    /// 少し後に行う（テストでは手で進める）
    @ObservationIgnored var scheduleAfter: (TimeInterval, @escaping @MainActor () -> Void) -> Void = { delay, action in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            MainActor.assumeIsolated { action() }
        }
    }
    /// 「今後表示しない」を覚える場所。nil なら覚えない
    @ObservationIgnored var reminder: OnboardingReminderPreference? {
        didSet { hidesReminder = reminder?.isHidden ?? false }
    }

    @ObservationIgnored private let controller: NonetController
    /// 実行できるか（ライセンス・試用）を見る。@Observable なので、登録すると練習の画面も変わる
    @ObservationIgnored private let license: LicenseManager?
    @ObservationIgnored private let permissions: any PermissionsProviding
    @ObservationIgnored private let frontmostApp: (any FrontmostAppObserving)?
    @ObservationIgnored private let touchSource: (any TouchSource)?
    @ObservationIgnored private let loginItem: (any LoginItemControlling)?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var practiceStartedAt: Date?
    /// 練習を始めたときにすでにあった記録（これは数えない）
    @ObservationIgnored private var practiceBaseline: ExecutionRecord?
    @ObservationIgnored private var cancellationBaseline: CancellationRecord?
    /// このウィンドウで macOS の許可の確認を出した。2回目からはシステム設定の欄だけを開く
    @ObservationIgnored private var hasPromptedAccessibility = false
    /// 知らせを出したときに選んでいた「ログイン時に起動」。同じ選択のまま押し直したら閉じる
    @ObservationIgnored private var loginAttempt: Bool?

    /// license が nil なら、試用期間の終了では練習を止めない。
    /// frontmostApp が nil なら、練習はグローバルのページで案内する。touchSource が nil ならトラックパッドを確かめない。
    /// loginItem が nil なら「ログイン時に起動」を反映しない
    init(
        controller: NonetController,
        license: LicenseManager? = nil,
        permissions: any PermissionsProviding,
        frontmostApp: (any FrontmostAppObserving)? = nil,
        touchSource: (any TouchSource)? = nil,
        loginItem: (any LoginItemControlling)? = nil,
        now: @escaping () -> Date = Date.init,
        isTemporaryCopy: @escaping () -> Bool = { ShellInstallLocation.current == .temporary }
    ) {
        self.isTemporaryCopy = isTemporaryCopy
        self.controller = controller
        self.license = license
        self.permissions = permissions
        self.frontmostApp = frontmostApp
        self.touchSource = touchSource
        self.loginItem = loginItem
        self.now = now
        isAccessibilityGranted = permissions.isAccessibilityGranted
        // 初回起動では勧める（選んだままにしておく）。もう一度見るときは、いまの状態から（設定の「一般」で外したものを戻さない）。
        // 勧めるのは起動して最初の案内だけ（同じ起動の中で開き直した案内で、外したものをまた選ばない）
        // ディスクイメージなどから動いているときは勧めない（そこを指すログイン項目は、取り出すと動かない）
        let recommended = controller.takeLoginItemRecommendation()
        recommendsLoginItem = recommended && !isTemporaryCopy()
        opensAtLogin = recommendsLoginItem || (loginItem?.isEnabled ?? !isTemporaryCopy())
        refreshTrackpad()
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
        // 試用期間が終わっていると9マスが開かない。ライセンスキーを登録すれば（@Observable なので）知らせは消える
        if license?.canExecuteActions == false {
            return .licenseRequired
        }
        // 練習モードは、このウィンドウを使っている間だけ。そうでなければ「何も実行されません」とは言えない
        if !isWindowAttended {
            return .notAttended
        }
        return nil
    }

    /// 練習モードにしてよいか。見えていても、ほかのアプリを使っている間は本物を実行する
    var isWindowAttended: Bool {
        isWindowVisible && isWindowKey
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
            announce(String(localized: "アクセシビリティが許可されました。次へ進みます。", bundle: .module))
            go(to: .practice)
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

    /// 練習の画面が最後（「完了」「スキップ」はウィンドウが閉じる）
    func next() {
        switch step {
        case .welcome: go(to: .practice)
        case .practice: break
        }
    }

    func back() {
        switch step {
        case .welcome: break
        case .practice: go(to: .welcome)
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

    /// 練習の画面を閉じるとき（「完了」「スキップ」「設定を開く」・閉じるボタン）。「ログイン時に起動」の選択を反映し、閉じてよければ true。
    /// システム設定での許可が要る・変えられなかったときは知らせを出して false（同じ選択のまま押し直せば閉じる）。
    /// 最初の画面では、まだ選択を見せていないので何もしない
    func finish() -> Bool {
        guard step == .practice, let loginItem else { return true }
        // 選び直していない（初回起動の勧めでもない）なら、いまの状態のまま（開いている間に設定で変えたものも戻さない）
        guard hasChosenLoginItem || recommendsLoginItem else { return true }
        if let loginAttempt, loginAttempt == opensAtLogin { return true }
        loginAttempt = nil
        // 外すときは、許可待ち（登録したが、システム設定でまだ許可していない）も外す。isEnabled だけを見ると、
        // 許可待ちのまま残り、後でシステム設定で許可したときにログイン時に開いてしまう
        let current = opensAtLogin ? loginItem.isEnabled : loginItem.isRegistered
        guard current != opensAtLogin else {
            loginItemMessage = nil
            return true
        }
        let enabled = opensAtLogin
        if enabled, isTemporaryCopy() {
            loginItemMessage = ShellInstallLocation.temporaryCopyLoginItemMessage
            return false
        }
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

    // MARK: - 練習

    /// controller.lastExecution が変わったら呼ぶ。練習を始めてからの記録だけを数える。
    /// 実行されなかったもの（Nonet のウィンドウで断られた など）は実行できたことにしない。
    /// どのページでも、目標と同じ位置のマスなら実行できたことにする（2本指でページを替えてしまっても、やり方は合っている）
    func handleExecution(_ record: ExecutionRecord?) {
        guard step == .practice, isWindowAttended, let record, let startedAt = practiceStartedAt,
              record != practiceBaseline, record.date >= startedAt else { return }
        practiceBaseline = record
        guard record.succeeded else { return }
        switch practice {
        case .run:
            guard let target = practicePage?.runTarget else { return }
            guard record.address.index == target.index else {
                practiceFeedback = .wrongCell(index: record.address.index, title: record.cellTitle)
                announce(ShellText.practiceWrongCell(index: record.address.index, title: record.cellTitle, target: target))
                return
            }
            practice = .cancel
            practiceFeedback = nil
            announce(ShellText.practiceRunDone)
        case .cancel:
            practiceFeedback = .ranInsteadOfCancelling(title: record.cellTitle)
            announce(ShellText.practiceRanInsteadOfCancelling(record.cellTitle))
        case .succeeded:
            break
        }
    }

    /// controller.lastCancellation が変わったら呼ぶ。やめる課題で、外枠で指を離して閉じたらできたことにする
    /// （止める時間が足りなかった・境界で離した などで実行しなかったものは、やめる操作とは数えない）。
    /// できなかった離し方には、理由別に、どうすればよいかを知らせる（何も起きない練習は、壊れて見える）
    func handleCancellation(_ record: CancellationRecord?) {
        guard step == .practice, isWindowAttended, let record, let startedAt = practiceStartedAt,
              record != cancellationBaseline, record.date >= startedAt else { return }
        cancellationBaseline = record
        switch practice {
        case .run:
            practiceFeedback = .notRun(record.reason, whileCancelling: false)
            announce(ShellText.practiceNotRun(record.reason, target: practicePage?.runTarget, whileCancelling: false))
        case .cancel:
            // 開いてすぐ（ポインタを真ん中から出さずに）離したのは、外枠まで動かしてやめたことにしない
            if record.reason == .liftedInFrame, !record.liftedBeforeMoving {
                practice = .succeeded
                practiceFeedback = nil
                announce(ShellText.practiceCancelDone)
            } else {
                practiceFeedback = .notRun(record.reason, whileCancelling: true)
                announce(ShellText.practiceNotRun(record.reason, target: practicePage?.runTarget, whileCancelling: true))
            }
        case .succeeded:
            break
        }
    }

    private func attentionChanged(from wasAttended: Bool) {
        let attended = isWindowAttended
        guard attended != wasAttended, step == .practice else { return }
        controller.isPracticeMode = attended
        if attended {
            // 離れている間の実行は本物なので、練習には数えない
            practiceBaseline = controller.lastExecution
            cancellationBaseline = controller.lastCancellation
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
            isStatusItemVisible = statusItemVisibility()
            practice = .run
            practiceFeedback = nil
            practiceBaseline = controller.lastExecution
            cancellationBaseline = controller.lastCancellation
            practiceStartedAt = now()
            controller.isPracticeMode = isWindowAttended
        case .welcome:
            refreshTrackpad()
        }
    }

    #if DEBUG
    /// 見た目の確認用（App の --onboarding-step）
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
