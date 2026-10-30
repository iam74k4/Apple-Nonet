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
                    Text("オフにするとトリガーキーに反応しません", bundle: .module)
                }
                Picker(selection: binding(\.trigger)) {
                    ForEach(TriggerKey.allCases, id: \.self) { key in
                        Text(SettingsText.name(key)).tag(key)
                    }
                } label: {
                    Text("トリガーキー", bundle: .module)
                    Text("右側のキーだけに反応します。左の⌘や⌥はいつもどおり使えます", bundle: .module)
                }
                if let warning = model.triggerWarning {
                    SettingsNote(text: warning, symbol: "exclamationmark.triangle", isWarning: true)
                }
                Picker(selection: binding(\.touchActivation)) {
                    ForEach(TouchActivation.allCases, id: \.self) { activation in
                        Text(SettingsText.name(activation)).tag(activation)
                    }
                } label: {
                    Text("トラックパッドだけで呼び出す", bundle: .module)
                    Text("角に指を置いて少し待つと9マスが出ます。指を滑らせて選び、離すと実行します", bundle: .module)
                }
                Picker(selection: binding(\.fireMode)) {
                    ForEach(FireMode.allCases, id: \.self) { mode in
                        Text(SettingsText.name(mode)).tag(mode)
                    }
                } label: {
                    Text("実行のタイミング", bundle: .module)
                    Text(SettingsText.detail(model.settings.fireMode))
                }
                LabeledContent {
                    HStack(spacing: 10) {
                        Slider(value: binding(\.hudDelay), in: GlobalSettings.hudDelayRange, step: 0.05) {
                            Text(SettingsText.hudDelayTitle)
                        }
                        .labelsHidden()
                        .frame(minWidth: 160, maxWidth: 240)
                        Text(SettingsText.seconds(model.settings.hudDelay))
                            .monospacedDigit()
                            .frame(minWidth: 52, alignment: .trailing)
                    }
                } label: {
                    // 指を置かないときに HUD が出るまでの時間は別（少し長い。SessionConfiguration.placementWindow）
                    Text(SettingsText.hudDelayTitle)
                    Text(SettingsText.hudDelayDetail)
                }
                Picker(selection: binding(\.hudPosition)) {
                    ForEach(HUDPosition.allCases, id: \.self) { position in
                        Text(SettingsText.name(position)).tag(position)
                    }
                } label: {
                    Text("HUD の位置", bundle: .module)
                    Text("カーソルのあるディスプレイに出ます", bundle: .module)
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
                Text("トリガーと HUD", bundle: .module)
            }

            Section {
                Toggle(isOn: binding(\.autoSwitchProfiles)) {
                    Text("前面のアプリで切り替える", bundle: .module)
                    Text("オフにすると、いつもグローバルのプロファイルを使います", bundle: .module)
                }
                Toggle(isOn: binding(\.appendGlobalPages)) {
                    Text("グローバルのページをつなげる", bundle: .module)
                    Text("アプリのページの後ろにグローバルのページをつなげ、2本指スワイプで行けるようにします", bundle: .module)
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
                    Text("実行を知らせる", bundle: .module)
                    Text(SettingsText.executionToastDetail)
                }
            } header: {
                Text("知らせ", bundle: .module)
            }

            Section {
                Toggle(isOn: binding(\.passTriggerToApps)) {
                    Text("トリガーキーを前面のアプリに渡す", bundle: .module)
                    Text("オフにすると、トリガーキーそのものを前面のアプリやほかのツールに渡しません", bundle: .module)
                }
                Picker(selection: binding(\.cursorLock)) {
                    ForEach(CursorLockMethod.allCases, id: \.self) { method in
                        Text(SettingsText.name(method)).tag(method)
                    }
                } label: {
                    // 「詳細」の見出しの中なので、名前に「（詳細）」は付けない
                    Text("カーソルの固定方法", bundle: .module)
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
                            Task { await model.exportProfiles(model.configuration.profiles, suggestedName: defaultExportName) }
                        } label: {
                            Text("書き出す…", bundle: .module)
                        }
                        Button {
                            Task { await model.importProfiles() }
                        } label: {
                            Text("読み込む…", bundle: .module)
                        }
                    }
                } label: {
                    Text("プロファイルの書き出し / 読み込み", bundle: .module)
                    Text("すべてのプロファイルを .\(ConfigurationStore.profileDocumentExtension) のファイルに書き出します。1つだけ書き出すときは、プロファイルの一覧で右クリックします", bundle: .module)
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
