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
    /// もうプロファイルがある（案内をもう一度見ているとき）。そのまま残すので選び直せない
    var isConfigured: Bool

    var id: String { app.bundleID }
}

enum OnboardingPracticeState: Equatable {
    case waiting
    /// 違うマスをタップした（マスの番号）
    case wrongCell(Int)
    case succeeded
}

/// 初回起動の流れ。AppKit に触れないので、偽のサービスでテストできる
@MainActor
@Observable
final class OnboardingModel {
    /// 練習で押してもらうマス（右上）
    static let practiceTargetIndex = 2

    private(set) var step: OnboardingStep = .welcome
    private(set) var isAccessibilityGranted: Bool
    private(set) var choices: [OnboardingAppChoice]
    private(set) var practice: OnboardingPracticeState = .waiting
    /// ウィンドウが見えているか。隠れている間は練習モードにしない（置き忘れたウィンドウで実行が止まらないように）
    private(set) var isWindowVisible = true
    /// 初回起動: 選んだアプリだけのプロファイルで作り直す。もう一度見ているとき: 足りないものを足すだけ
    let replacesProfiles: Bool

    /// 「次へ」で選んだアプリを反映したとき
    @ObservationIgnored var onSelectionApplied: (() -> Void)?

    @ObservationIgnored private let controller: NonetController
    @ObservationIgnored private let permissions: any PermissionsProviding
    @ObservationIgnored private let presets: [AppPreset]
    @ObservationIgnored private let installedLauncherIDs: Set<String>
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var practiceStartedAt: Date?
    /// 練習を始めたときにすでにあった記録（これは数えない）
    @ObservationIgnored private var practiceBaseline: ExecutionRecord?

    init(
        controller: NonetController,
        permissions: any PermissionsProviding,
        installedApps: any InstalledAppsProviding,
        replacesProfiles: Bool,
        now: @escaping () -> Date = Date.init
    ) {
        self.controller = controller
        self.permissions = permissions
        self.replacesProfiles = replacesProfiles
        self.now = now
        isAccessibilityGranted = permissions.isAccessibilityGranted
        presets = PresetLibrary.apps.filter { installedApps.isInstalled(bundleID: $0.app.bundleID) }
        installedLauncherIDs = Set(
            PresetLibrary.launcherCandidates.map(\.bundleID).filter { installedApps.isInstalled(bundleID: $0) }
        )
        let configuration = controller.configuration
        choices = presets.map { preset in
            let configured = !replacesProfiles && configuration.appProfile(forBundleID: preset.app.bundleID) != nil
            return OnboardingAppChoice(
                app: preset.app,
                category: preset.category,
                summary: preset.summary,
                isSelected: true,
                isConfigured: configured
            )
        }
    }

    var trigger: TriggerKey {
        controller.configuration.settings.trigger
    }

    var selectedCount: Int {
        choices.filter(\.isSelected).count
    }

    /// もう一度見ているときに、新しく足すアプリの数
    var additionCount: Int {
        choices.filter { $0.isSelected && !$0.isConfigured }.count
    }

    var isNonetEnabled: Bool {
        controller.configuration.settings.isEnabled
    }

    /// 練習できない理由。練習できるなら nil
    var practiceBlocker: String? {
        if !controller.configuration.settings.isEnabled {
            return String(localized: "Nonet が無効になっています。有効にすると試せます", bundle: .module)
        }
        switch controller.status {
        case .needsAccessibility:
            return String(localized: "アクセシビリティが許可されていないため、まだ試せません", bundle: .module)
        case .noTrackpad:
            return String(localized: "トラックパッドが見つからないため、試せません", bundle: .module)
        case .secureInputActive:
            return String(localized: "パスワードの入力中は試せません。パスワード欄から離れてください", bundle: .module)
        case .running, .disabled, .stopped:
            return nil
        }
    }

    // MARK: - アクセシビリティ

    /// 1秒ごとに呼ぶ。許可されたらコントローラーに知らせ、最初の画面なら次へ進む
    func pollPermission() {
        let granted = permissions.isAccessibilityGranted
        guard granted != isAccessibilityGranted else { return }
        isAccessibilityGranted = granted
        controller.refreshPermissions()
        if granted, step == .welcome {
            logger.info("アクセシビリティが許可されたので次へ進む")
            go(to: .apps)
        }
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

    /// ウィンドウが隠れた（ほかのウィンドウの後ろ・しまった）・また見えた
    func setWindowVisible(_ visible: Bool) {
        guard visible != isWindowVisible else { return }
        isWindowVisible = visible
        guard step == .practice else { return }
        controller.isPracticeMode = visible
        if visible {
            // 隠れている間の実行は本物なので、練習には数えない
            practiceBaseline = controller.lastExecution
            practiceStartedAt = now()
        }
    }

    /// ウィンドウを閉じるとき。練習モードは必ず戻す
    func close() {
        controller.isPracticeMode = false
        practiceStartedAt = nil
    }

    // MARK: - アプリを選ぶ

    func toggle(_ id: OnboardingAppChoice.ID) {
        guard let index = choices.firstIndex(where: { $0.id == id }), !choices[index].isConfigured else { return }
        choices[index].isSelected.toggle()
    }

    func setAllSelected(_ selected: Bool) {
        for index in choices.indices where !choices[index].isConfigured {
            choices[index].isSelected = selected
        }
    }

    /// 選んだアプリを反映して、試してみるへ。全体の設定（トリガーなど）は変えない
    func applySelection() {
        guard step == .apps else { return }
        let selectedIDs = Set(choices.filter { $0.isSelected && !$0.isConfigured }.map(\.id))
        let selected = presets.filter { selectedIDs.contains($0.id) }
        if replacesProfiles {
            let settings = controller.configuration.settings
            var configuration = NonetConfiguration.initial(
                trigger: settings.trigger,
                appPresets: selected,
                installedBundleIDs: installedLauncherIDs
            )
            configuration.settings = settings
            controller.replaceConfiguration(configuration)
        } else if !selected.isEmpty {
            controller.update { configuration in
                for preset in selected {
                    configuration.addAppProfile(for: preset.app, preset: preset)
                }
            }
        }
        logger.info("初回の案内で \(selected.count) 個のアプリのプロファイルを反映した")
        onSelectionApplied?()
        go(to: .practice)
    }

    // MARK: - 練習

    /// controller.lastExecution が変わったら呼ぶ。練習を始めてからの記録だけを数える
    func handleExecution(_ record: ExecutionRecord?) {
        guard step == .practice, isWindowVisible, let record, let startedAt = practiceStartedAt,
              record != practiceBaseline, record.date >= startedAt else { return }
        practiceBaseline = record
        if record.address.index == Self.practiceTargetIndex {
            practice = .succeeded
        } else if practice != .succeeded {
            practice = .wrongCell(record.address.index)
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
            practiceBaseline = controller.lastExecution
            practiceStartedAt = now()
            controller.isPracticeMode = isWindowVisible
        }
    }
}
