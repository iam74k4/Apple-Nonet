// 担当: ui-shell
import NonetCore
import SwiftUI

enum OnboardingLayout {
    static let windowSize = CGSize(width: 760, height: 600)
    static let horizontalPadding: CGFloat = 40
}

/// 初回起動の画面。モックのボード「初回起動」に合わせた白黒の見た目
struct OnboardingView: View {
    let model: OnboardingModel
    /// 「設定を開く」。nil ならボタンを出さない
    let onOpenSettings: (() -> Void)?
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            OnboardingStepIndicator(step: model.step, isAccessibilityGranted: model.isAccessibilityGranted)
                .padding(.horizontal, OnboardingLayout.horizontalPadding)
                .padding(.top, 22)
                .padding(.bottom, 18)
            Group {
                switch model.step {
                case .welcome: OnboardingWelcomeStep(model: model)
                case .practice: OnboardingPracticeStep(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider()
            footer
                .padding(.horizontal, OnboardingLayout.horizontalPadding)
                .frame(height: 64)
        }
        .frame(width: OnboardingLayout.windowSize.width, height: OnboardingLayout.windowSize.height)
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 10) {
            footerNote
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            footerButtons
        }
    }

    @ViewBuilder
    private var footerNote: some View {
        switch model.step {
        case .welcome:
            if model.purpose == .permission(remindsAtLaunch: true), !model.isAccessibilityGranted {
                // 起動するたびに開かないようにできる
                Toggle(isOn: Binding(get: { model.hidesReminder }, set: { model.setHidesReminder($0) })) {
                    Text("今後表示しない", bundle: .module)
                }
                .toggleStyle(.checkbox)
            } else if model.isAccessibilityGranted {
                // 「許可されています」はカードの印に出ているので繰り返さない
                Text("次へ進んでください", bundle: .module)
            } else {
                Text("許可すると、自動で次へ進みます", bundle: .module)
            }
        case .practice:
            Text("練習中は、何も実行されません", bundle: .module)
        }
    }

    @ViewBuilder
    private var footerButtons: some View {
        switch model.step {
        case .welcome:
            if model.isAccessibilityGranted {
                Button { model.next() } label: { Text("次へ", bundle: .module) }
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            } else {
                Button { model.next() } label: { Text("あとで許可する", bundle: .module) }
                    .buttonStyle(OnboardingSecondaryButtonStyle())
                Button { model.requestAccessibility() } label: { Text("システム設定を開く", bundle: .module) }
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        case .practice:
            // 練習が最後の画面。できたら「完了」、まだなら「スキップ」で閉じる（どちらもメニューバーのアイコンの場所を見せる）
            Button { model.back() } label: { Text("戻る", bundle: .module) }
                .buttonStyle(OnboardingSecondaryButtonStyle())
            if let onOpenSettings {
                Button(action: onOpenSettings) { Text("設定を開く", bundle: .module) }
                    .buttonStyle(OnboardingSecondaryButtonStyle())
            }
            if model.practice == .succeeded {
                Button(action: onFinish) { Text("完了", bundle: .module) }
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(action: onFinish) { Text("スキップ", bundle: .module) }
                    .buttonStyle(OnboardingSecondaryButtonStyle())
            }
        }
    }
}

// MARK: - 上の段の進み具合

/// 上の段の印
enum OnboardingStepMark: Equatable {
    case current
    case done
    /// 通り過ぎたが済んでいない（アクセシビリティを「あとで許可する」にした）
    case skipped
    case upcoming

    static func mark(for step: OnboardingStep, current: OnboardingStep, isAccessibilityGranted: Bool) -> OnboardingStepMark {
        if step == current { return .current }
        guard step < current else { return .upcoming }
        return step == .welcome && !isAccessibilityGranted ? .skipped : .done
    }
}

struct OnboardingStepIndicator: View {
    let step: OnboardingStep
    let isAccessibilityGranted: Bool

    private static let steps: [(OnboardingStep, LocalizedStringKey)] = [
        (.welcome, "アクセシビリティ"),
        (.practice, "試してみる"),
    ]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(Self.steps.enumerated()), id: \.offset) { offset, item in
                if offset > 0 {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.35))
                        .frame(width: 36, height: 1)
                }
                stepLabel(number: offset + 1, step: item.0, title: item.1)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 13))
        .accessibilityElement(children: .combine)
    }

    private func stepLabel(number: Int, step: OnboardingStep, title: LocalizedStringKey) -> some View {
        let mark = OnboardingStepMark.mark(for: step, current: self.step, isAccessibilityGranted: isAccessibilityGranted)
        let isCurrent = mark == .current
        return HStack(spacing: 8) {
            ZStack {
                switch mark {
                case .current:
                    Circle().fill(Color.primary)
                    Text(verbatim: "\(number)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                case .done:
                    Circle().strokeBorder(Color.primary, lineWidth: 1)
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                case .skipped:
                    // 許可しないまま進んだ。済んだように見せない
                    Circle().strokeBorder(Color.orange, lineWidth: 1)
                    Image(systemName: "exclamationmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.orange)
                        .accessibilityLabel(Text("許可されていません", bundle: .module))
                case .upcoming:
                    Circle().strokeBorder(Color.secondary.opacity(0.6), lineWidth: 1)
                    Text(verbatim: "\(number)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 24, height: 24)
            Text(title, bundle: .module)
                .fontWeight(isCurrent ? .bold : .regular)
                .foregroundStyle(isCurrent ? Color.primary : Color.secondary)
        }
    }
}

// MARK: - 1. ようこそ

struct OnboardingWelcomeStep: View {
    let model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                OnboardingLogo(size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Group {
                        if case .permission = model.purpose {
                            Text("Nonet を使うには、あと1つ許可が必要です", bundle: .module)
                        } else {
                            Text("Nonet へようこそ", bundle: .module)
                        }
                    }
                    .font(.system(size: 24, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .onboardingHeading()
                    Text(ShellText.welcomeSubtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("アクセシビリティの許可", bundle: .module)
                        .font(.system(size: 15, weight: .bold))
                    Spacer()
                    OnboardingPermissionBadge(isGranted: model.isAccessibilityGranted)
                }
                Text("macOS では、ほかのアプリを使っている間のキーボードやポインタを扱うのにこの許可が要ります。Nonet は次のことにだけ使います。", bundle: .module)
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 6) {
                    OnboardingBullet(Text("9マスを開いている間、ポインタの移動とクリックを前面のアプリに渡さない", bundle: .module))
                    OnboardingBullet(Text("9マスを開いている間だけ、キーが押されたことを知る（押されたら閉じる）", bundle: .module))
                    OnboardingBullet(Text("設定したキー入力を送る・メニュー項目を押す・選択中のテキストを読む", bundle: .module))
                }
                Text("入力した文字の内容は記録も送信もしません。設定は Mac の中だけに保存します。", bundle: .module)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !model.isAccessibilityGranted {
                    Divider()
                    OnboardingPermissionSteps()
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.secondary.opacity(0.3)))
            if model.isTrackpadMissing {
                // 許可より前に分かる。許可しても、トラックパッドが無ければ使えない
                OnboardingNotice(text: OnboardingModel.noTrackpadMessage) {
                    Button { model.recheckTrackpad() } label: { Text(OnboardingPracticeRemedy.recheck.title) }
                }
            }
        }
        .padding(.horizontal, OnboardingLayout.horizontalPadding)
        .padding(.top, 6)
    }
}

/// 許可の手順。macOS がパスワードか Touch ID を求めることも先に伝える
struct OnboardingPermissionSteps: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            OnboardingNumberedLine(number: 1, text: Text("「システム設定を開く」を押す", bundle: .module))
            OnboardingNumberedLine(number: 2, text: Text("一覧の Nonet をオンにする（パスワードか Touch ID を求められます）", bundle: .module))
            OnboardingNumberedLine(number: 3, text: Text("この画面に自動で戻ります", bundle: .module))
        }
    }
}

struct OnboardingNumberedLine: View {
    let number: Int
    let text: Text

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: "\(number).")
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .frame(width: 18, alignment: .trailing)
            text
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

struct OnboardingPermissionBadge: View {
    let isGranted: Bool

    var body: some View {
        HStack(spacing: 6) {
            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                Text("許可されています", bundle: .module)
            } else {
                ProgressView()
                    .controlSize(.small)
                Text("許可を待っています", bundle: .module)
            }
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(isGranted ? Color.primary : Color.secondary)
        .accessibilityElement(children: .combine)
    }
}

struct OnboardingBullet: View {
    let text: Text

    init(_ text: Text) {
        self.text = text
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(Color.primary)
                .frame(width: 4, height: 4)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 1 }
            text
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - 部品

extension View {
    /// 画面の見出し。画面が変わったら、VoiceOver の場所をここに移す
    func onboardingHeading() -> some View {
        modifier(OnboardingHeading())
    }
}

private struct OnboardingHeading: ViewModifier {
    @AccessibilityFocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .accessibilityAddTraits(.isHeader)
            .accessibilityFocused($isFocused)
            .onAppear {
                // 画面が入れ替わってから移す（すぐだと、消える前の画面の要素に戻されることがある）
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    isFocused = true
                }
            }
    }
}

/// 知らせ（練習できない理由・トラックパッドが無い）。actions にその場で直すボタンを置く
struct OnboardingNotice<Actions: View>: View {
    let text: String
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .accessibilityHidden(true)
                Text(text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            actions()
                .controlSize(.small)
        }
        .font(.system(size: 13))
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.secondary.opacity(0.4)))
    }
}

/// ロゴ（輪に並んだ8つの点と真ん中の点）。メニューバーのアイコンと同じ形
struct OnboardingLogo: View {
    let size: CGFloat

    var body: some View {
        let geometry = MenuBarIconGeometry.self
        let scale = size / geometry.canvas.width
        ZStack(alignment: .topLeading) {
            ForEach(Array((geometry.ringDotRects() + [geometry.centerDotRect]).enumerated()), id: \.offset) { _, rect in
                Circle()
                    .fill(Color.primary)
                    .frame(width: rect.width * scale, height: rect.height * scale)
                    .offset(x: rect.minX * scale, y: rect.minY * scale)
            }
        }
        .frame(width: size, height: size, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}

/// 黒い角丸のボタン（暗い表示では白）
struct OnboardingPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color(nsColor: .windowBackgroundColor))
            .padding(.horizontal, 18)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.75 : 1))
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

struct OnboardingSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundStyle(Color.primary.opacity(configuration.isPressed ? 0.5 : 0.8))
            .padding(.horizontal, 12)
            .frame(height: 34)
            .contentShape(Rectangle())
    }
}
