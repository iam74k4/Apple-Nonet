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

enum OnboardingPracticeState: Equatable {
    case waiting
    /// 違うマスをタップした（マスの番号）
    case wrongCell(Int)
    case succeeded
}

/// 練習できない理由。文言とボタンを同じ値から選ぶ
enum OnboardingPracticeBlocker: Equatable {
    /// Nonet を無効にしている
    case disabled
    case needsAccessibility
    case noTrackpad
    case secureInput
    /// 試用期間が終わっていて、練習のタップも実行されなかった
    case licenseRequired

    var message: String {
        switch self {
        case .disabled:
            String(localized: "Nonet が無効になっています。有効にすると試せます", bundle: .module)
        case .needsAccessibility:
            String(localized: "アクセシビリティが許可されていないため、まだ試せません", bundle: .module)
        case .noTrackpad:
            String(localized: "トラックパッドが見つからないため、試せません", bundle: .module)
        case .secureInput:
            String(localized: "パスワードの入力中は試せません。パスワード欄から離れてください", bundle: .module)
        case .licenseRequired:
            String(localized: "試用期間が終了しているため、試せません。ライセンスキーを登録すると試せます", bundle: .module)
        }
    }

    /// その場で直せるならその方法
    var remedy: OnboardingPracticeRemedy? {
        switch self {
        case .disabled: .enableNonet
        case .needsAccessibility: .openAccessibilitySettings
        case .licenseRequired: .openLicense
        case .noTrackpad, .secureInput: nil
        }
    }
}

enum OnboardingPracticeRemedy: Equatable {
    case enableNonet
    case openAccessibilitySettings
    /// 設定の「ライセンス」を開く
    case openLicense

    var title: String {
        switch self {
        case .enableNonet: String(localized: "Nonet を有効にする", bundle: .module)
        case .openAccessibilitySettings: String(localized: "システム設定を開く", bundle: .module)
        case .openLicense: String(localized: "ライセンスキーを入力…", bundle: .module)
        }
    }
}

/// 初回起動の流れ。AppKit に触れないので、偽のサービスでテストできる
@MainActor
@Observable
final class OnboardingModel {
    /// 練習で押してもらうマス（右上）
    static let practiceTargetIndex = 2

    private(set) var step: OnboardingStep = .welcome
    private(set) var isAccessibilityGranted: Bool
    private(set) var practice: OnboardingPracticeState = .waiting
    /// ウィンドウがほかのウィンドウに隠れていない（しまった・画面のロック中も隠れている）
    private(set) var isWindowVisible = true
    /// ウィンドウがキーウィンドウ。ほかのアプリを使っている間は false
    private(set) var isWindowKey = true
    /// 初回起動の案内として開いた。選んだアプリだけのプロファイルで作り直してよい
    let isFirstLaunchGuide: Bool
    /// 練習のタップが試用期間の終了で断られた（ライセンスを登録して、もう一度押せば消える）
    private(set) var isPracticeRefusedForLicense = false
    /// 設定を開く（ライセンスの登録など）。ウィンドウの側が入れる
    @ObservationIgnored var onOpenSettings: ((SettingsTab) -> Void)?

    @ObservationIgnored private let controller: NonetController
    @ObservationIgnored private let permissions: any PermissionsProviding
    @ObservationIgnored private let presets: [AppPreset]
    @ObservationIgnored private let installedLauncherIDs: Set<String>
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var practiceStartedAt: Date?
    /// 練習を始めたときにすでにあった記録（これは数えない）
    @ObservationIgnored private var practiceBaseline: ExecutionRecord?
    /// 選んでいるアプリ（bundleID）。設定済みのものはここに無くても選ばれている扱い
    private var selectedIDs: Set<String>
    /// 案内を開いたとき（作り直した後は作り直したとき）のプロファイル。
    /// ここから変わっていれば利用者が編集したので、作り直さずに足すだけにする
    private var profilesSnapshot: [Profile]

    init(
        controller: NonetController,
        permissions: any PermissionsProviding,
        installedApps: any InstalledAppsProviding,
        isFirstLaunchGuide: Bool,
        now: @escaping () -> Date = Date.init
    ) {
        self.controller = controller
        self.permissions = permissions
        self.isFirstLaunchGuide = isFirstLaunchGuide
        self.now = now
        isAccessibilityGranted = permissions.isAccessibilityGranted
        presets = PresetLibrary.apps.filter { installedApps.isInstalled(bundleID: $0.app.bundleID) }
        installedLauncherIDs = Set(
            PresetLibrary.launcherCandidates.map(\.bundleID).filter { installedApps.isInstalled(bundleID: $0) }
        )
        selectedIDs = Set(presets.map(\.app.bundleID))
        profilesSnapshot = controller.configuration.profiles
    }

    var trigger: TriggerKey {
        controller.configuration.settings.trigger
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
        return isPracticeRefusedForLicense ? .licenseRequired : nil
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
        let granted = permissions.isAccessibilityGranted
        guard granted != isAccessibilityGranted else { return false }
        isAccessibilityGranted = granted
        controller.refreshPermissions()
        if granted, step == .welcome {
            logger.info("アクセシビリティが許可されたので次へ進む")
            go(to: .apps)
        }
        return granted
    }

    /// 許可のダイアログを出し（一覧に Nonet が載る）、設定アプリの欄を開く
    func requestAccessibility() {
        permissions.requestAccessibility()
        permissions.openAccessibilitySettings()
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

    /// 「あとで設定する」: 今の設定のまま試してみるへ
    func skipSelection() {
        guard step == .apps else { return }
        go(to: .practice)
    }

    func enableNonet() {
        controller.update { $0.settings.isEnabled = true }
    }

    func resolve(_ remedy: OnboardingPracticeRemedy) {
        switch remedy {
        case .enableNonet: enableNonet()
        case .openAccessibilitySettings: requestAccessibility()
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

    /// 選んだアプリを反映して、試してみるへ。全体の設定（トリガーなど）は変えない
    func applySelection() {
        guard step == .apps else { return }
        let addedIDs = Set(choices.filter { $0.isSelected && !$0.isConfigured }.map(\.id))
        let selected = presets.filter { addedIDs.contains($0.app.bundleID) }
        if replacesProfiles {
            let settings = controller.configuration.settings
            var configuration = NonetConfiguration.initial(
                trigger: settings.trigger,
                appPresets: selected,
                installedBundleIDs: installedLauncherIDs
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
    /// 実行されなかったもの（試用期間の終了で断られた）は押せたことにしない
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
        if record.address.index == Self.practiceTargetIndex {
            practice = .succeeded
        } else if practice != .succeeded {
            practice = .wrongCell(record.address.index)
        }
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
        if newStep == .practice {
            practice = .waiting
            isPracticeRefusedForLicense = false
            practiceBaseline = controller.lastExecution
            practiceStartedAt = now()
            controller.isPracticeMode = isWindowAttended
        }
    }

    /// 有効・無効にかかわらず、そのアプリのプロファイル（NonetConfiguration.addAppProfile と同じ探し方）
    static func profile(forBundleID bundleID: String, in profiles: [Profile]) -> Profile? {
        let key = bundleIDKey(bundleID)
        guard !key.isEmpty else { return nil }
        return profiles.first { profile in
            profile.app.map { bundleIDKey($0.bundleID) == key } == true
        }
    }

    private static func bundleIDKey(_ bundleID: String) -> String {
        bundleID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
