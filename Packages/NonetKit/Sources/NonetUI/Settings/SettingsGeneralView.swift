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
                    Text("オフにすると、トラックパッドの上の縁から指を滑らせても、9つのアイコン（HUD）が開きません", bundle: .module)
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
                Picker(selection: binding(\.openSensitivity)) {
                    ForEach(OpenSensitivity.allCases, id: \.self) { sensitivity in
                        Text(SettingsText.name(sensitivity)).tag(sensitivity)
                    }
                } label: {
                    Text(SettingsText.openSensitivityTitle)
                    Text(SettingsText.openSensitivityDetail(model.settings.openSensitivity))
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

/// 「開き方とやめ方」の小さな図。トラックパッドと、上の縁から下への矢印。
/// 説明は横の文が言うので、VoiceOver には読ませない
struct SettingsOpenGestureFigure: View {
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: SettingsMetrics.smallRadius, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
                RoundedRectangle(cornerRadius: SettingsMetrics.smallRadius, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.6), lineWidth: 1)
                // 上の縁から下へ滑らせる
                Path { path in
                    let x = size.width / 2
                    path.move(to: CGPoint(x: x, y: 1))
                    path.addLine(to: CGPoint(x: x, y: size.height * 0.55))
                }
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(Color.accentColor)
                    .position(x: size.width / 2, y: size.height * 0.55)
            }
        }
        .accessibilityHidden(true)
    }
}
