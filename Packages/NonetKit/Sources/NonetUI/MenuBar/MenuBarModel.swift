// 担当: ui-shell
import NonetCore

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

    init(
        status: ControllerStatus,
        isEnabled: Bool,
        activeProfileName: String? = nil,
        isGlobalProfileActive: Bool = false,
        notice: String? = nil,
        entitlement: Entitlement,
        canCheckForUpdates: Bool = false
    ) {
        self.status = status
        self.isEnabled = isEnabled
        self.activeProfileName = activeProfileName
        self.isGlobalProfileActive = isGlobalProfileActive
        self.notice = notice
        self.entitlement = entitlement
        self.canCheckForUpdates = canCheckForUpdates
    }

    @MainActor
    init(controller: NonetController, license: LicenseManager, canCheckForUpdates: Bool) {
        let active = controller.activeProfileName
        self.init(
            status: controller.status,
            isEnabled: controller.configuration.settings.isEnabled,
            activeProfileName: active,
            isGlobalProfileActive: active != nil && active == controller.configuration.globalProfile.name,
            notice: controller.notice,
            entitlement: license.entitlement,
            canCheckForUpdates: canCheckForUpdates
        )
    }
}

/// アイコンの見た目
enum MenuBarIconState: Equatable, CaseIterable {
    case normal
    /// 無効にしている・止まっている
    case disabled
    /// 権限が無い・トラックパッドが無い・パスワード入力中・試用終了・知らせたい問題がある
    case attention
}

/// メニューの1行
enum MenuBarEntry: Equatable {
    case status(String, MenuBarIconState)
    case notice(String)
    case dismissNotice
    case requestAccessibility
    case separator
    case toggleEnabled(isOn: Bool)
    case openSettings
    case editProfiles
    case showOnboarding
    case license(String)
    case checkForUpdates
    case quit

    /// メニューに出す文字
    var title: String {
        switch self {
        case .status(let text, _): text
        case .notice(let text): text
        case .dismissNotice: String(localized: "この知らせを消す", bundle: .module)
        case .requestAccessibility: String(localized: "アクセシビリティを許可…", bundle: .module)
        case .separator: ""
        case .toggleEnabled: String(localized: "Nonet を有効にする", bundle: .module)
        case .openSettings: String(localized: "設定…", bundle: .module)
        case .editProfiles: String(localized: "プロファイルを編集…", bundle: .module)
        case .showOnboarding: String(localized: "初回の案内をもう一度", bundle: .module)
        case .license(let text): text
        case .checkForUpdates: String(localized: "アップデートを確認", bundle: .module)
        case .quit: String(localized: "終了", bundle: .module)
        }
    }
}

/// メニューバーの状態の文言・アイコン・メニューの並び。AppKit に触れない
enum MenuBarModel {
    static func iconState(for state: MenuBarState) -> MenuBarIconState {
        // 自分で無効にしているなら、ほかの問題より「無効」を見せる
        if !state.isEnabled || state.status == .disabled || state.status == .stopped {
            return .disabled
        }
        switch state.status {
        case .needsAccessibility, .noTrackpad, .secureInputActive:
            return .attention
        case .running, .disabled, .stopped:
            break
        }
        if state.entitlement == .expired || state.notice != nil {
            return .attention
        }
        return .normal
    }

    /// メニューの先頭に出す状態の文
    static func statusText(for state: MenuBarState) -> String {
        if !state.isEnabled {
            return String(localized: "Nonet は無効です", bundle: .module)
        }
        switch state.status {
        case .running:
            guard let name = state.activeProfileName, !name.isEmpty else {
                return String(localized: "動作中", bundle: .module)
            }
            return state.isGlobalProfileActive
                ? String(localized: "グローバルのプロファイル", bundle: .module)
                : String(localized: "\(name) のプロファイル", bundle: .module)
        case .disabled:
            return String(localized: "Nonet は無効です", bundle: .module)
        case .stopped:
            return String(localized: "停止しています", bundle: .module)
        case .needsAccessibility:
            return String(localized: "アクセシビリティの許可が必要です", bundle: .module)
        case .noTrackpad:
            return String(localized: "トラックパッドが見つかりません", bundle: .module)
        case .secureInputActive:
            return String(localized: "パスワード入力中は使えません", bundle: .module)
        }
    }

    static func licenseText(for entitlement: Entitlement) -> String {
        switch entitlement {
        case .trial(let daysLeft):
            String(localized: "試用期間: 残り \(daysLeft) 日", bundle: .module)
        case .licensed:
            String(localized: "登録済み", bundle: .module)
        case .expired:
            String(localized: "試用期間が終了しました", bundle: .module)
        }
    }

    /// アイコンの説明（VoiceOver とツールチップ）
    static func accessibilityDescription(for state: MenuBarState) -> String {
        switch iconState(for: state) {
        case .normal: String(localized: "Nonet", bundle: .module)
        case .disabled: String(localized: "Nonet（無効）", bundle: .module)
        case .attention: String(localized: "Nonet（確認が必要）", bundle: .module)
        }
    }

    static func entries(for state: MenuBarState) -> [MenuBarEntry] {
        var entries: [MenuBarEntry] = [.status(statusText(for: state), iconState(for: state))]
        if state.isEnabled, state.status == .needsAccessibility {
            entries.append(.requestAccessibility)
        }
        if let notice = state.notice, !notice.isEmpty {
            entries += [.notice(notice), .dismissNotice]
        }
        entries += [
            .separator,
            .toggleEnabled(isOn: state.isEnabled),
            .separator,
            .openSettings,
            .editProfiles,
            .showOnboarding,
            .separator,
            .license(licenseText(for: state.entitlement)),
        ]
        if state.canCheckForUpdates {
            entries.append(.checkForUpdates)
        }
        entries += [.separator, .quit]
        return entries
    }
}
