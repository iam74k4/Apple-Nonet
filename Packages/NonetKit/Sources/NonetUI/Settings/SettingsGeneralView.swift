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
                Toggle(isOn: binding(\.adaptiveHUDInk)) {
                    Text(SettingsText.adaptiveInkTitle)
                    Text(SettingsText.adaptiveInkDetail)
                }
                if model.settings.adaptiveHUDInk {
                    SettingsScreenCaptureRow(model: model)
                }
            } header: {
                Text("開き方と HUD", bundle: .module)
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

/// 「背景に合わせて色を変える」の下の、画面収録の許可の知らせとボタン。許可があればそう言うだけ
private struct SettingsScreenCaptureRow: View {
    let model: SettingsModel

    var body: some View {
        if model.isScreenCaptureGranted {
            SettingsNote(text: SettingsText.screenCaptureGranted, symbol: "checkmark.circle")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                SettingsNote(text: SettingsText.screenCaptureNeeded, symbol: "info.circle")
                HStack(spacing: 8) {
                    Button { model.requestScreenCapture() } label: { Text(SettingsText.screenCaptureRequestButton) }
                    Button { model.openScreenCaptureSettings() } label: { Text(SettingsText.screenCaptureSettingsButton) }
                }
            }
        }
    }
}

/// 「開き方とやめ方」の小さな図。トラックパッドと、上の縁から下への矢印。
/// 説明は横の文が言うので、VoiceOver には読ませない
struct SettingsOpenGestureFigure: View {
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
                RoundedRectangle(cornerRadius: 7, style: .continuous)
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
