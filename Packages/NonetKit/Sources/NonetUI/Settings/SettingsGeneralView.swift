// 担当: ui-settings
// 一般のタブ: 全体の設定（項目名は docs/user-guide.md の「設定（一般）」と同じ）
import NonetCore
import SwiftUI

struct SettingsGeneralView: View {
    let model: SettingsModel

    var body: some View {
        Form {
            Section {
                Toggle(isOn: binding(\.isEnabled)) {
                    Text("Nonet を有効にする", bundle: .module)
                    Text("オフにすると、トラックパッドの上の縁から指を滑らせても9マスが開きません", bundle: .module)
                }
                LabeledContent {
                    SettingsOpenGestureFigure()
                        .frame(width: 92, height: 62)
                } label: {
                    Text(SettingsText.openGestureTitle)
                    Text(SettingsText.openGestureDetail)
                }
                Picker(selection: binding(\.hudPosition)) {
                    ForEach(HUDPosition.allCases, id: \.self) { position in
                        Text(SettingsText.name(position)).tag(position)
                    }
                } label: {
                    Text("HUD の位置", bundle: .module)
                    Text("ポインタのあるディスプレイに出ます", bundle: .module)
                }
                .pickerStyle(.segmented)
                Picker(selection: binding(\.hudScale)) {
                    ForEach(HUDScale.allCases, id: \.self) { scale in
                        Text(SettingsText.name(scale)).tag(scale)
                    }
                } label: {
                    Text(SettingsText.hudScaleTitle)
                    Text(SettingsText.hudScaleDetail)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("開き方と HUD", bundle: .module)
            }

            Section {
                Toggle(isOn: binding(\.autoSwitchProfiles)) {
                    Text("前面のアプリで切り替える", bundle: .module)
                    Text("オフにすると、いつもグローバルのプロファイルを使います", bundle: .module)
                }
                Toggle(isOn: binding(\.appendGlobalPages)) {
                    Text("グローバルのページをつなげる", bundle: .module)
                    Text("アプリのページの後ろにグローバルのページをつなげ、ページを切り替えて行けるようにします", bundle: .module)
                }
                .disabled(!model.settings.autoSwitchProfiles)
            } header: {
                Text("プロファイル", bundle: .module)
            }

            Section {
                Picker(selection: binding(\.haptics)) {
                    ForEach(HapticStrength.allCases, id: \.self) { strength in
                        Text(SettingsText.name(strength)).tag(strength)
                    }
                } label: {
                    Text("触覚", bundle: .module)
                    Text(SettingsText.hapticsDetail)
                }
                .pickerStyle(.segmented)
                Toggle(isOn: binding(\.showExecutionToast)) {
                    Text("実行したことを表示", bundle: .module)
                    Text(SettingsText.executionToastDetail)
                }
            } header: {
                Text("フィードバック", bundle: .module)
            }

            Section {
                Picker(selection: binding(\.cursorLock)) {
                    ForEach(CursorLockMethod.allCases, id: \.self) { method in
                        Text(SettingsText.name(method)).tag(method)
                    }
                } label: {
                    // 「詳細」の見出しの中なので、名前に「（詳細）」は付けない
                    Text("ポインタの固定方法", bundle: .module)
                    Text(SettingsText.detail(model.settings.cursorLock))
                }
            } header: {
                Text("詳細", bundle: .module)
            }

            Section {
                Toggle(isOn: Binding(get: { model.loginItemEnabled }, set: { model.setLoginItemEnabled($0) })) {
                    Text("ログイン時に起動", bundle: .module)
                    Text("Mac にログインしたときに Nonet を起動します", bundle: .module)
                }
                if let error = model.loginItemError {
                    SettingsNote(text: error, symbol: "exclamationmark.triangle", isWarning: true)
                }
            } header: {
                Text("起動", bundle: .module)
            }

            Section {
                LabeledContent {
                    HStack(spacing: 8) {
                        Button {
                            Task { await model.exportAllProfiles(suggestedName: defaultExportName) }
                        } label: {
                            Text("書き出す…", bundle: .module)
                        }
                        Button {
                            Task { await model.importProfiles() }
                        } label: {
                            Text("読み込む…", bundle: .module)
                        }
                        SettingsRestoreBackupButton(model: model)
                    }
                } label: {
                    Text("プロファイルの書き出し / 読み込み", bundle: .module)
                    Text("すべてのプロファイルを .\(ConfigurationStore.profileDocumentExtension) のファイルに書き出します。1つだけ書き出すときは、プロファイルの一覧で右クリックします。", bundle: .module)
                }
                SettingsNote(
                    text: String(localized: "ほかの人から受け取ったプロファイルを読み込むときは、中のスクリプトを必ず確かめてください（スクリプトはあなたの権限で動きます）", bundle: .module),
                    symbol: "exclamationmark.shield"
                )
            } header: {
                Text("書き出しと読み込み", bundle: .module)
            }
        }
        .formStyle(.grouped)
    }

    private var defaultExportName: String {
        String(localized: "Nonet のプロファイル", bundle: .module)
    }

    private func binding<Value: Equatable>(_ keyPath: WritableKeyPath<GlobalSettings, Value>) -> Binding<Value> {
        Binding(get: { model.settings[keyPath: keyPath] }, set: { model.setSetting(keyPath, $0) })
    }
}

/// 「開き方とやめ方」の小さな図。トラックパッドの外枠（GridInsets.cancelFrame と同じ割合）と9マス、上の縁から下への矢印。
/// 説明は横の文が言うので、VoiceOver には読ませない
struct SettingsOpenGestureFigure: View {
    private static let frame = GridInsets.cancelFrame

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let inner = CGRect(
                x: size.width * Self.frame.left,
                y: size.height * Self.frame.top,
                width: size.width * (1 - Self.frame.left - Self.frame.right),
                height: size.height * (1 - Self.frame.top - Self.frame.bottom)
            )
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.6), lineWidth: 1)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .frame(width: inner.width, height: inner.height)
                    .offset(x: inner.minX, y: inner.minY)
                Path { path in
                    for line in 1...2 {
                        let x = inner.minX + inner.width * CGFloat(line) / 3
                        let y = inner.minY + inner.height * CGFloat(line) / 3
                        path.move(to: CGPoint(x: x, y: inner.minY))
                        path.addLine(to: CGPoint(x: x, y: inner.maxY))
                        path.move(to: CGPoint(x: inner.minX, y: y))
                        path.addLine(to: CGPoint(x: inner.maxX, y: y))
                    }
                }
                .stroke(Color.secondary.opacity(0.45), lineWidth: 0.5)
                // 上の縁から下へ滑らせる
                Path { path in
                    let x = size.width / 2
                    path.move(to: CGPoint(x: x, y: 1))
                    path.addLine(to: CGPoint(x: x, y: inner.minY + inner.height * 0.42))
                }
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(Color.accentColor)
                    .position(x: size.width / 2, y: inner.minY + inner.height * 0.42)
            }
        }
        .accessibilityHidden(true)
    }
}
