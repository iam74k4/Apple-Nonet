// 担当: ui-settings
// ライセンスのタブ。試用中と試用期間の終了後は、状態の下に購入の行、その下に「購入済みの方」のライセンスキーの欄。
// 登録済みなら登録者と、キーのコピー・別のキーの登録・この Mac からの登録の削除
import NonetCore
import SwiftUI

struct SettingsLicenseView: View {
    @Bindable var model: SettingsModel
    @FocusState private var isKeyFieldFocused: Bool

    private var hasKeyInput: Bool {
        !model.licenseKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        let entitlement = model.license.entitlement
        Form {
            Section {
                statusCard(SettingsText.summary(entitlement, trialEnd: model.license.trialEndDate))
                if case .licensed(let info) = entitlement {
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
                } else if let purchase = model.links.purchase {
                    purchaseRow(purchase)
                }
            } header: {
                Text("状態", bundle: .module)
            }

            if model.showsLicenseKeyField {
                Section {
                    keyEntry
                } header: {
                    if model.isLicensed {
                        Text("別のライセンスキーを登録", bundle: .module)
                    } else {
                        Text("購入済みの方", bundle: .module)
                    }
                }
            } else {
                // 行の名前が「ライセンスキー」なので、見出しは付けない
                Section {
                    registeredKeyRow
                }
            }

            if model.isLicensed {
                Section {
                    LabeledContent {
                        Button {
                            model.confirmation = .deactivateLicense
                        } label: {
                            Text("登録を消す…", bundle: .module)
                        }
                    } label: {
                        Text("この Mac から登録を消す", bundle: .module)
                        Text("Mac を手放すときなどに使います。同じキーは、ほかの Mac でもそのまま使えます。", bundle: .module)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            model.license.refresh()
            focusKeyFieldIfWanted()
        }
        .onChange(of: model.wantsLicenseKeyFocus) { _, _ in focusKeyFieldIfWanted() }
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

    // MARK: - 状態

    private func statusCard(_ summary: SettingsText.EntitlementSummary) -> some View {
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
    }

    /// 買うことがいちばんの用事なので、キーを貼り付けるまでは「購入する」を目立たせる
    private func purchaseRow(_ purchase: URL) -> some View {
        LabeledContent {
            if hasKeyInput {
                purchaseButton(purchase)
            } else {
                purchaseButton(purchase)
                    .buttonStyle(.borderedProminent)
            }
        } label: {
            Text("買い切りのライセンス", bundle: .module)
            // 買う前に知りたいこと（台数・返金）もここで言う
            Text("購入すると、ライセンスキーがメールで届きます。1つのライセンスで、あなたが使うすべての Mac に使えます。30日以内なら全額を返金します。", bundle: .module)
        }
    }

    private func purchaseButton(_ purchase: URL) -> some View {
        Button {
            model.openURL(purchase)
        } label: {
            Text("購入する", bundle: .module)
        }
        .controlSize(.large)
    }

    // MARK: - ライセンスキー

    private var keyEntry: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("購入時のメールに書かれたライセンスキーを貼り付けて「登録」を押します。キーはこの Mac の中で確かめるので、ネットワークもアカウントも要りません。", bundle: .module)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ZStack(alignment: .topLeading) {
                TextEditor(text: $model.licenseKeyInput)
                    .font(.system(size: 11, design: .monospaced))
                    .autocorrectionDisabled()
                    .scrollContentBackground(.hidden)
                    .focused($isKeyFieldFocused)
                    .padding(6)
                    .accessibilityLabel(String(localized: "ライセンスキー", bundle: .module))
                if model.licenseKeyInput.isEmpty {
                    // TextEditor には placeholder が無いので重ねる（クリックは欄に通す）
                    Text("購入時のメールにあるライセンスキーを貼り付け", bundle: .module)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .frame(height: 76)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                messageNote
                Spacer(minLength: 8)
                if model.isEnteringAnotherKey {
                    Button {
                        model.setEnteringAnotherKey(false)
                    } label: {
                        Text("キャンセル", bundle: .module)
                    }
                }
                Button {
                    model.activateLicense()
                } label: {
                    Text("登録", bundle: .module)
                }
                // キーが入るまでは「購入する」を目立たせ、入ったら「登録」を既定のボタンにする
                .keyboardShortcut(hasKeyInput ? .defaultAction : nil)
                .disabled(!hasKeyInput)
            }
            if let help = model.links.licenseKeyHelp {
                Button {
                    model.openURL(help)
                } label: {
                    Text("ライセンスキーが見つからないときは", bundle: .module)
                }
                .buttonStyle(.link)
                .font(.system(size: 12))
            }
        }
        .padding(.vertical, 4)
    }

    /// 登録済み: キーは見せず、コピーと別のキーの登録だけ（コピーしたキーは、自分のほかの Mac に登録できる）
    private var registeredKeyRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent {
                HStack(spacing: 8) {
                    Button {
                        model.copyLicenseKey()
                    } label: {
                        Text("キーをコピー", bundle: .module)
                    }
                    Button {
                        model.setEnteringAnotherKey(true)
                    } label: {
                        Text("別のキーを登録…", bundle: .module)
                    }
                }
            } label: {
                Text("ライセンスキー", bundle: .module)
                Text("同じキーを、あなたが使うほかの Mac にも登録できます", bundle: .module)
            }
            if model.licenseMessage != nil {
                messageNote
            }
        }
    }

    /// 登録の結果。うまくいかなかったときは、その横に「お問い合わせ…」
    @ViewBuilder
    private var messageNote: some View {
        if let message = model.licenseMessage {
            SettingsNote(
                text: message.text,
                symbol: message.isError ? "exclamationmark.triangle" : "checkmark.circle",
                isWarning: message.isError
            )
            .textSelection(.enabled)
            if message.isError, model.supportEmail != nil {
                Button {
                    model.contactSupport()
                } label: {
                    Text("お問い合わせ…", bundle: .module)
                }
                .fixedSize()
            }
        }
    }

    private func focusKeyFieldIfWanted() {
        guard model.wantsLicenseKeyFocus else { return }
        model.wantsLicenseKeyFocus = false
        // タブを切り替えた直後は、欄がまだウィンドウに無いことがあるので、次の回で
        DispatchQueue.main.async {
            isKeyFieldFocused = true
        }
    }
}
