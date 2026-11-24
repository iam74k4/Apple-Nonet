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
                    // この画面で最初に出す呼び方は「9つのアイコン（HUD）」、次からは「HUD」
                    Text("オフにすると、トラックパッドを強く押し込んでも、9つのアイコン（HUD）が開きません（ふつうのクリックになります）", bundle: .module)
                }
                LabeledContent {
                    SettingsOpenGestureFigure()
                        .frame(width: 92, height: 62)
                } label: {
                    Text(SettingsText.openGestureTitle)
                    Text(SettingsText.openGestureDetail)
                    // くわしい使い方（Nonet のウインドウが前面では開かないことなど）は利用ガイドに任せる
                    if let guide = model.links.support {
                        Button {
                            model.openURL(guide)
                        } label: {
                            Text("くわしくは利用ガイドへ", bundle: .module)
                        }
                        .buttonStyle(.link)
                    }
                }
                Picker(selection: binding(\.openGesture)) {
                    ForEach(OpenGesture.allCases, id: \.self) { gesture in
                        Text(SettingsText.name(gesture)).tag(gesture)
                    }
                } label: {
                    Text(SettingsText.openGestureChoiceTitle)
                    Text(SettingsText.detail(model.settings.openGesture))
                }
                .pickerStyle(.segmented)
                if model.settings.openGesture.usesForcePress, TrackpadForceClick.isOff() {
                    LabeledContent {
                        VStack(alignment: .trailing, spacing: 6) {
                            Button {
                                model.openURL(TrackpadForceClick.settingsURL)
                            } label: {
                                Text(SettingsText.openTrackpadSettings)
                            }
                            if model.settings.openGesture == .forcePress {
                                Button {
                                    model.setSetting(\.openGesture, .edgeSlide)
                                } label: {
                                    Text(SettingsText.useEdgeSlide)
                                }
                            }
                        }
                    } label: {
                        Label {
                            Text(SettingsText.forceClickOffTitle)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                        Text(SettingsText.forceClickOffDetail)
                    }
                }
                Picker(selection: binding(\.openSensitivity)) {
                    ForEach(OpenSensitivity.allCases, id: \.self) { sensitivity in
                        Text(SettingsText.name(sensitivity)).tag(sensitivity)
                    }
                } label: {
                    Text(SettingsText.openSensitivityTitle)
                    Text(SettingsText.openSensitivityDetail(model.settings.openSensitivity, gesture: model.settings.openGesture))
                }
                .pickerStyle(.segmented)
                // 前の版の「特大」は、大きく表示のオンとして見せる（オフにすると標準に戻る）
                Toggle(isOn: Binding(get: { model.settings.hudScale != .standard }, set: { model.setSetting(\.hudScale, $0 ? .large : .standard) })) {
                    Text(SettingsText.hudLargeTitle)
                    Text(SettingsText.hudLargeDetail)
                }
                // 前の版の「弱」「強」は、オンとして見せる（オフにするとオフ、オンにすると中）
                Toggle(isOn: Binding(get: { model.settings.haptics != .off }, set: { model.setSetting(\.haptics, $0 ? .medium : .off) })) {
                    Text("触覚", bundle: .module)
                    Text(SettingsText.hapticsDetail)
                }
            } header: {
                Text("開き方と HUD", bundle: .module)
            }

            // iTerm2 が入っているときだけ出す（選べるのがターミナルだけなら、選ぶものが無い）。
            // 選んだ後に iTerm2 を消したときは、選んだまま見せる（実行はターミナルで開く）
            let terminals = SettingsText.terminalChoices(current: model.settings.terminalApp) { model.services.installedApps.isInstalled(bundleID: $0) }
            if terminals.count > 1 {
                Section {
                    Picker(selection: binding(\.terminalApp)) {
                        ForEach(terminals, id: \.self) { app in
                            Text(SettingsText.name(app)).tag(app)
                        }
                    } label: {
                        Text(SettingsText.terminalAppTitle)
                        Text(SettingsText.terminalAppDetail)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("スクリプト", bundle: .module)
                }
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
        }
        .formStyle(.grouped)
    }

    private func binding<Value: Equatable>(_ keyPath: WritableKeyPath<GlobalSettings, Value>) -> Binding<Value> {
        Binding(get: { model.settings[keyPath: keyPath] }, set: { model.setSetting(keyPath, $0) })
    }
}

/// 「開き方とやめ方」の小さな図。トラックパッドと、その真ん中で強く押し込む指（指の点と、押し込みを表す2重の輪）。
/// 説明は横の文が言うので、VoiceOver には読ませない
struct SettingsOpenGestureFigure: View {
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: SettingsMetrics.smallRadius, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
                RoundedRectangle(cornerRadius: SettingsMetrics.smallRadius, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.6), lineWidth: 1)
                // 強く押し込む指
                Circle()
                    .strokeBorder(Color.accentColor.opacity(0.4), lineWidth: 1.5)
                    .frame(width: 34, height: 34)
                    .position(center)
                Circle()
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .frame(width: 22, height: 22)
                    .position(center)
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 10, height: 10)
                    .position(center)
            }
        }
        .accessibilityHidden(true)
    }
}

/// macOS の「強めのクリックと触覚フィードバック」（グローバルの設定 com.apple.trackpad.forceClick）。
/// オフだと強めのクリックの2段目が来ないので、強く押し込んでも開かない。値が無ければ（既定のまま）オン
enum TrackpadForceClick {
    static let key = "com.apple.trackpad.forceClick"
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension")!

    static func isOff(defaults: UserDefaults = .standard) -> Bool {
        (defaults.object(forKey: key) as? Bool) == false
    }
}
