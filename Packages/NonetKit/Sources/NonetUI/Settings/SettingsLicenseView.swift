// 担当: ui-settings
// ライセンスのタブ: 試用の残り日数・登録者・キーの入力・購入ページ
import NonetCore
import SwiftUI

struct SettingsLicenseView: View {
    @Bindable var model: SettingsModel

    private var isLicensed: Bool {
        if case .licensed = model.license.entitlement { return true }
        return false
    }

    var body: some View {
        let summary = SettingsText.summary(model.license.entitlement)
        Form {
            Section {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: summary.symbol)
                        .font(.system(size: 26))
                        .foregroundStyle(summary.isProblem ? Color.orange : Color.primary)
                        .frame(width: 36)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(summary.title)
                            .font(.system(size: 15, weight: .semibold))
                        Text(summary.detail)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
                if case .licensed(let info) = model.license.entitlement {
                    LabeledContent {
                        // 文言と同じ言語で出す（Locale.current のままだと、英語の画面で日付だけ日本語になることがある）
                        Text(SettingsText.issuedDate(info.issuedAt))
                    } label: {
                        Text("発行日", bundle: .module)
                    }
                    LabeledContent {
                        Text(info.licenseID)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                    } label: {
                        Text("ライセンス ID", bundle: .module)
                    }
                }
            } header: {
                Text("状態", bundle: .module)
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("購入時のメールに書かれたライセンスキーを貼り付けて「登録」を押します。キーはこの Mac の中で確かめるので、ネットワークもアカウントも要りません。", bundle: .module)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    TextEditor(text: $model.licenseKeyInput)
                        .font(.system(size: 11, design: .monospaced))
                        .autocorrectionDisabled()
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .frame(height: 76)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
                        .accessibilityLabel(String(localized: "ライセンスキー", bundle: .module))
                    HStack {
                        if let message = model.licenseMessage {
                            SettingsNote(
                                text: message.text,
                                symbol: message.isError ? "exclamationmark.triangle" : "checkmark.circle",
                                isWarning: message.isError
                            )
                        }
                        Spacer(minLength: 8)
                        Button {
                            model.activateLicense()
                        } label: {
                            Text("登録", bundle: .module)
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(model.licenseKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("ライセンスキー", bundle: .module)
            }

            Section {
                if case .licensed = model.license.entitlement {
                    LabeledContent {
                        Button {
                            model.confirmation = .deactivateLicense
                        } label: {
                            Text("登録を解除…", bundle: .module)
                        }
                    } label: {
                        Text("この Mac での登録を外す", bundle: .module)
                        Text("別の Mac に移すときなどに使います", bundle: .module)
                    }
                }
                if let purchase = model.links.purchase, !isLicensed {
                    LabeledContent {
                        Button {
                            model.openURL(purchase)
                        } label: {
                            Text("購入する", bundle: .module)
                        }
                    } label: {
                        Text("買い切りのライセンス", bundle: .module)
                        Text("購入すると、ライセンスキーがメールで届きます", bundle: .module)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { model.license.refresh() }
    }
}
