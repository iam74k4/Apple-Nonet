// 担当: ui-settings
// 設定ウィンドウの中身。上に知らせの帯、その下に選んだタブ
import NonetCore
import SwiftUI

extension SettingsTab {
    var title: String {
        switch self {
        case .profiles: String(localized: "プロファイル", bundle: .module)
        case .general: String(localized: "一般", bundle: .module)
        case .license: String(localized: "ライセンス", bundle: .module)
        case .about: String(localized: "情報", bundle: .module)
        }
    }

    var symbol: String {
        switch self {
        case .profiles: "square.grid.3x3"
        case .general: "gearshape"
        case .license: "key"
        case .about: "info.circle"
        }
    }
}

struct SettingsRootView: View {
    @Bindable var model: SettingsModel

    var body: some View {
        VStack(spacing: 0) {
            SettingsBannerStack(model: model)
            Group {
                switch model.tab {
                case .profiles: SettingsProfilesView(model: model)
                case .general: SettingsGeneralView(model: model)
                case .license: SettingsLicenseView(model: model)
                case .about: SettingsAboutView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 860, minHeight: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.settingsPendingEdits, model.pendingEdits)
        .alert(
            confirmationTitle,
            isPresented: Binding(get: { model.confirmation != nil }, set: { if !$0 { model.confirmation = nil } }),
            presenting: model.confirmation
        ) { confirmation in
            Button(role: .destructive) {
                model.confirm(confirmation)
            } label: {
                Text(confirmationButton(confirmation))
            }
            if case .importProfiles(let plan) = confirmation, plan.addsProfiles {
                Button {
                    model.importNewProfilesOnly(plan)
                } label: {
                    Text("新しいプロファイルだけ追加", bundle: .module)
                }
            }
            Button(role: .cancel) {
                model.confirmation = nil
            } label: {
                Text("キャンセル", bundle: .module)
            }
        } message: { confirmation in
            Text(confirmationMessage(confirmation))
        }
    }

    private var confirmationTitle: String {
        switch model.confirmation {
        case .deleteProfile(_, let name)?:
            String(localized: "「\(name)」のプロファイルを削除しますか？", bundle: .module)
        case .removePage(_, let index)?:
            String(localized: "ページ \(index + 1) を削除しますか？", bundle: .module)
        case .deactivateLicense?:
            String(localized: "ライセンスの登録を解除しますか？", bundle: .module)
        case .importProfiles(let plan)?:
            String(localized: "「\(plan.fileName)」を読み込みますか？", bundle: .module)
        case nil:
            ""
        }
    }

    private func confirmationMessage(_ confirmation: SettingsModel.Confirmation) -> String {
        switch confirmation {
        case .deleteProfile:
            String(localized: "このプロファイルの9マスはすべて消えます。元に戻せません。", bundle: .module)
        case .removePage:
            String(localized: "このページのマスはすべて消えます。元に戻せません。", bundle: .module)
        case .deactivateLicense:
            String(localized: "この Mac でのライセンスの登録を外します。ライセンスキーを控えておけば、また登録できます。", bundle: .module)
        case .importProfiles(let plan):
            SettingsText.importConfirmation(plan)
        }
    }

    private func confirmationButton(_ confirmation: SettingsModel.Confirmation) -> String {
        switch confirmation {
        case .deleteProfile, .removePage: String(localized: "削除", bundle: .module)
        case .deactivateLicense: String(localized: "登録を解除", bundle: .module)
        case .importProfiles: String(localized: "置き換えて読み込む", bundle: .module)
        }
    }
}

/// どのタブでも上に出す帯: 設定の問題（notice）・権限などの状態・書き出しと読み込みの結果
struct SettingsBannerStack: View {
    let model: SettingsModel

    var body: some View {
        VStack(spacing: 0) {
            if let notice = model.controller.notice {
                SettingsBanner(
                    symbol: "exclamationmark.triangle",
                    title: notice,
                    message: nil,
                    onClose: { model.controller.dismissNotice() }
                ) { EmptyView() }
            }
            if let banner = model.statusBanner {
                SettingsBanner(symbol: banner.symbol, title: banner.title, message: banner.message) {
                    HStack(spacing: 8) {
                        ForEach(banner.buttons, id: \.title) { button in
                            Button(button.title) { model.perform(button.action) }
                        }
                    }
                }
            }
            if let message = model.fileMessage {
                SettingsBanner(
                    symbol: message.isError ? "exclamationmark.triangle" : "checkmark.circle",
                    title: message.isError
                        ? String(localized: "書き出し・読み込みに失敗しました", bundle: .module)
                        : String(localized: "書き出し・読み込み", bundle: .module),
                    message: message.text,
                    isWarning: message.isError,
                    onClose: { model.fileMessage = nil }
                ) { EmptyView() }
            }
        }
    }
}
