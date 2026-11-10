// 担当: ui-settings
// 設定ウィンドウの中身。上に知らせの帯、その下に選んだタブ
import NonetCore
import SwiftUI

extension SettingsTab {
    var title: String {
        switch self {
        case .profiles: String(localized: "プロファイル", bundle: .module)
        case .general: String(localized: "一般", bundle: .module)
        case .license: "Nonet"
        }
    }

    var symbol: String {
        switch self {
        case .profiles: "square.grid.3x3"
        case .general: "gearshape"
        case .license: "info.circle"
        }
    }
}

struct SettingsRootView: View {
    @Bindable var model: SettingsModel

    var body: some View {
        VStack(spacing: 0) {
            SettingsBannerStack(model: model)
            // Group ではなく ZStack にする（Group に付けた .alert は、中のタブの画面に付き、タブが替わると消えてしまう）
            ZStack {
                switch model.tab {
                case .profiles: SettingsProfilesView(model: model)
                case .general: SettingsGeneralView(model: model)
                case .license: SettingsLicenseView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // 購入のメールのリンクなどで登録するかを尋ねる。どのタブにいても出したままにする（Nonet のタブに付けると、
            // メニューの「◯◯のマスを編集…」や案内の「設定を開く」でタブが替わったときに、尋ねたまま消えてしまう）
            .alert(
                String(localized: "このライセンスキーを登録しますか？", bundle: .module),
                isPresented: Binding(get: { model.pendingLicense != nil }, set: { if !$0 { model.cancelPendingLicense() } }),
                presenting: model.pendingLicense
            ) { _ in
                Button {
                    model.confirmPendingLicense()
                } label: {
                    Text("登録", bundle: .module)
                }
                .keyboardShortcut(.defaultAction)
                Button(role: .cancel) {
                    model.cancelPendingLicense()
                } label: {
                    Text("キャンセル", bundle: .module)
                }
            } message: { pending in
                // 署名を確かめたキーの中身なので、そのまま見せてよい（長すぎる名前だけ切る）
                Text(SettingsText.singleLine(SettingsText.licenseeLine(pending.info), limit: SettingsText.importContentLimit))
            }
        }
        .frame(minWidth: 860, minHeight: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.settingsPendingEdits, model.pendingEdits)
        // どのタブからでも開ける（Nonet のタブの「書き出しと読み込み」の「以前の設定に戻す…」）
        .sheet(isPresented: $model.isShowingBackups) {
            SettingsBackupsSheet(model: model)
        }
        // 読み込む前の確認は、マスの中身をすべて見せるシート（SettingsImportReviewSheet）。ほかはアラート
        .sheet(item: Binding(get: { importPlan }, set: { if $0 == nil { model.confirmation = nil } })) { plan in
            SettingsImportReviewSheet(model: model, plan: plan)
        }
        .alert(
            confirmationTitle,
            isPresented: Binding(get: { model.confirmation != nil && importPlan == nil }, set: { if !$0 { model.confirmation = nil } }),
            presenting: model.confirmation
        ) { confirmation in
            Button(role: confirmationRole(confirmation)) {
                model.confirm(confirmation)
            } label: {
                Text(confirmationButton(confirmation))
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

    /// 確かめている読み込み（シートで出す）
    private var importPlan: SettingsImportPlan? {
        if case .importProfiles(let plan)? = model.confirmation { return plan }
        return nil
    }

    static func pageTitle(model: SettingsModel, profileID: UUID, index: Int) -> String {
        let pages = model.configuration.profile(id: profileID)?.pages ?? []
        return SettingsText.pageTitle(index: index, name: pages.indices.contains(index) ? pages[index].name : nil)
    }

    private var confirmationTitle: String {
        switch model.confirmation {
        case .deleteProfile(_, let name)?:
            String(localized: "「\(name)」のプロファイルを削除しますか？", bundle: .module)
        case .removePage(let profileID, let index)?:
            // 名前を付けたページは、タブと同じ名前で聞く（どのページか取り違えない）
            String(localized: "「\(Self.pageTitle(model: model, profileID: profileID, index: index))」を削除しますか？", bundle: .module)
        case .deactivateLicense?:
            String(localized: "この Mac から登録を消しますか？", bundle: .module)
        case .importProfiles(let plan)?:
            String(localized: "「\(plan.fileName)」を読み込みますか？", bundle: .module)
        case .resetProfile(_, let name)?:
            String(localized: "「\(name)」をプリセットに戻しますか？", bundle: .module)
        case .testRunFile(_, let operation)?:
            String(localized: "Finder で選んでいるファイルに「\(operation)」を実行しますか？", bundle: .module)
        case nil:
            ""
        }
    }

    private func confirmationMessage(_ confirmation: SettingsModel.Confirmation) -> String {
        switch confirmation {
        case .deleteProfile:
            String(localized: "このプロファイルのマスもすべて削除します。⌘Z で元に戻せます。", bundle: .module)
        case .removePage:
            String(localized: "このページのマスもすべて削除します。⌘Z で元に戻せます。", bundle: .module)
        case .resetProfile:
            String(localized: "今のマスはすべて、プリセットの中身に置き換わります。⌘Z で元に戻せます。", bundle: .module)
        case .deactivateLicense:
            String(localized: "この Mac からライセンスキーを消します。キーはあとからいつでも登録し直せます。", bundle: .module)
        case .importProfiles(let plan):
            SettingsText.importConfirmation(plan)
        case .testRunFile:
            String(localized: "テスト実行は、今 Finder で選んでいるファイルに、実際に働きます。選んでいるファイルを確かめてから実行してください。", bundle: .module)
        }
    }

    private func confirmationButton(_ confirmation: SettingsModel.Confirmation) -> String {
        switch confirmation {
        case .deleteProfile, .removePage: String(localized: "削除", bundle: .module)
        case .deactivateLicense: String(localized: "登録を消す", bundle: .module)
        case .importProfiles(let plan): SettingsText.importConfirmationButton(plan)
        case .resetProfile: String(localized: "プリセットに戻す", bundle: .module)
        case .testRunFile: String(localized: "実行する", bundle: .module)
        }
    }

    /// 何も消さない読み込み（スクリプトを含むだけ）は、赤いボタンにしない
    private func confirmationRole(_ confirmation: SettingsModel.Confirmation) -> ButtonRole? {
        if case .importProfiles(let plan) = confirmation, !plan.replacesExisting {
            return nil
        }
        if case .testRunFile = confirmation {
            return nil
        }
        return .destructive
    }
}

/// どのタブでも上に出す帯: 設定の問題（notice）・権限などの状態・試用期間の終了・書き出しと読み込みの結果
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
            SettingsExpiredBanner(model: model)
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
