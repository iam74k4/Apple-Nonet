// 担当: ui-shell
import NonetCore
import SwiftUI

enum OnboardingLayout {
    static let windowSize = CGSize(width: 760, height: 540)
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
            OnboardingStepIndicator(step: model.step)
                .padding(.horizontal, OnboardingLayout.horizontalPadding)
                .padding(.top, 22)
                .padding(.bottom, 18)
            Group {
                switch model.step {
                case .welcome: OnboardingWelcomeStep(model: model)
                case .apps: OnboardingAppsStep(model: model)
                case .practice: OnboardingPracticeStep(model: model)
                case .done: OnboardingDoneStep()
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
            if model.isAccessibilityGranted {
                Text("許可されています。次へ進んでください", bundle: .module)
            } else {
                Text("許可すると、自動で次へ進みます", bundle: .module)
            }
        case .apps:
            if model.choices.isEmpty {
                EmptyView()
            } else if model.replacesProfiles {
                Text("\(model.choices.count)個中\(model.selectedCount)個を選択中", bundle: .module)
            } else if model.additionCount > 0 {
                Text("\(model.additionCount)個のアプリのプロファイルを追加します", bundle: .module)
            } else {
                Text("追加するアプリはありません", bundle: .module)
            }
        case .practice:
            Text("練習中は、マスを押しても何も実行されません", bundle: .module)
        case .done:
            Text("この案内は、メニューバーの Nonet ›「初回の案内をもう一度」でまた見られます", bundle: .module)
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
        case .apps:
            Button { model.back() } label: { Text("戻る", bundle: .module) }
                .buttonStyle(OnboardingSecondaryButtonStyle())
            Button { model.skipSelection() } label: { Text("あとで設定する", bundle: .module) }
                .buttonStyle(OnboardingSecondaryButtonStyle())
            Button { model.applySelection() } label: { Text("次へ：試してみる", bundle: .module) }
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
        case .practice:
            Button { model.back() } label: { Text("戻る", bundle: .module) }
                .buttonStyle(OnboardingSecondaryButtonStyle())
            if model.practice == .succeeded {
                Button { model.next() } label: { Text("次へ", bundle: .module) }
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            } else {
                Button { model.next() } label: { Text("スキップ", bundle: .module) }
                    .buttonStyle(OnboardingSecondaryButtonStyle())
            }
        case .done:
            if let onOpenSettings {
                Button(action: onOpenSettings) { Text("設定を開く", bundle: .module) }
                    .buttonStyle(OnboardingSecondaryButtonStyle())
            }
            Button(action: onFinish) { Text("完了", bundle: .module) }
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
        }
    }
}

// MARK: - 上の段の進み具合

struct OnboardingStepIndicator: View {
    let step: OnboardingStep

    private static let steps: [(OnboardingStep, LocalizedStringKey)] = [
        (.welcome, "アクセシビリティ"),
        (.apps, "アプリを選ぶ"),
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
        let isCurrent = step == self.step
        let isDone = step < self.step
        return HStack(spacing: 8) {
            ZStack {
                if isCurrent {
                    Circle().fill(Color.primary)
                    Text(verbatim: "\(number)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                } else if isDone {
                    Circle().strokeBorder(Color.primary, lineWidth: 1)
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                } else {
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
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                OnboardingLogo(size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nonet へようこそ", bundle: .module)
                        .font(.system(size: 24, weight: .bold))
                    Text("キーを押している間だけ、トラックパッドがアプリごとに変わる9つのボタンになります", bundle: .module)
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
                    OnboardingBullet(Text("トリガーキーが押された・離されたことを知る", bundle: .module))
                    OnboardingBullet(Text("トリガーキーを押している間、カーソルの移動とクリックを前面のアプリに渡さない", bundle: .module))
                    OnboardingBullet(Text("設定したキー入力を送る・メニュー項目を押す・選択中のテキストを読む", bundle: .module))
                }
                Text("入力した文字の内容は記録も送信もしません。設定は Mac の中だけに保存します。", bundle: .module)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !model.isAccessibilityGranted {
                    Text("「システム設定を開く」を押し、プライバシーとセキュリティ › アクセシビリティ で Nonet をオンにしてください。", bundle: .module)
                        .font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.secondary.opacity(0.3)))
        }
        .padding(.horizontal, OnboardingLayout.horizontalPadding)
        .padding(.top, 6)
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

// MARK: - 2. アプリを選ぶ

struct OnboardingAppsStep: View {
    let model: OnboardingModel

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Mac にあるアプリから、9マスを用意しました", bundle: .module)
                    .font(.system(size: 22, weight: .bold))
                if !model.choices.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            if model.replacesProfiles {
                                Text("使うものを選ぶだけ。中身はあとから自由に変えられます。", bundle: .module)
                                Text("グローバルには、よく使うアプリを並べたランチャーを用意します。", bundle: .module)
                            } else {
                                Text("選んだアプリのプロファイルを追加します。設定済みのアプリはそのまま残ります。", bundle: .module)
                            }
                        }
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        if model.choices.contains(where: { !$0.isConfigured }) {
                            selectAllButton
                        }
                    }
                }
            }
            .padding(.horizontal, OnboardingLayout.horizontalPadding)
            if model.choices.isEmpty {
                OnboardingEmptyApps()
                    .padding(.horizontal, OnboardingLayout.horizontalPadding)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(model.choices) { choice in
                            OnboardingAppCard(choice: choice) { model.toggle(choice.id) }
                        }
                    }
                    .padding(.horizontal, OnboardingLayout.horizontalPadding)
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(.top, 2)
    }

    /// 選べるものが全部選ばれていれば「すべて外す」、そうでなければ「すべて選ぶ」
    private var selectAllButton: some View {
        let allSelected = model.choices.filter { !$0.isConfigured }.allSatisfy(\.isSelected)
        return Button {
            model.setAllSelected(!allSelected)
        } label: {
            allSelected ? Text("すべて外す", bundle: .module) : Text("すべて選ぶ", bundle: .module)
        }
        .buttonStyle(.plain)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(Color.primary.opacity(0.8))
        .fixedSize()
    }
}

struct OnboardingEmptyApps: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "square.grid.3x3")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("プリセットのあるアプリは見つかりませんでした", bundle: .module)
                .font(.system(size: 15, weight: .semibold))
            Text("グローバルには、Mac にあるよく使うアプリを並べたランチャーを用意します。アプリのプロファイルは、あとから設定で追加できます。", bundle: .module)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.secondary.opacity(0.3)))
    }
}

struct OnboardingAppCard: View {
    let choice: OnboardingAppChoice
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    CellIconView(.app(bundleID: choice.app.bundleID), size: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(choice.app.name)
                            .font(.system(size: 13, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .truncationMode(.tail)
                        Text(choice.category)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    checkmark
                }
                Text(choice.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        choice.isSelected && !choice.isConfigured ? Color.primary : Color.secondary.opacity(0.3),
                        lineWidth: choice.isSelected && !choice.isConfigured ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(choice.isConfigured)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(choice.app.name)、\(choice.category)、\(choice.summary)", bundle: .module))
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(choice.isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var accessibilityValue: Text {
        if choice.isConfigured {
            Text("設定済み", bundle: .module)
        } else if choice.isSelected {
            Text("選択中", bundle: .module)
        } else {
            Text("未選択", bundle: .module)
        }
    }

    @ViewBuilder
    private var checkmark: some View {
        if choice.isConfigured {
            Text("設定済み", bundle: .module)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().strokeBorder(Color.secondary.opacity(0.5)))
        } else if choice.isSelected {
            ZStack {
                Circle().fill(Color.primary)
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(nsColor: .windowBackgroundColor))
            }
            .frame(width: 20, height: 20)
        } else {
            Circle()
                .strokeBorder(Color.secondary.opacity(0.6), lineWidth: 1)
                .frame(width: 20, height: 20)
        }
    }
}

// MARK: - 3. 試してみる

struct OnboardingPracticeStep: View {
    let model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("試してみる", bundle: .module)
                    .font(.system(size: 22, weight: .bold))
                Text(ShellText.practiceInstruction(model.trigger))
                    .font(.system(size: 17, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("すぐにタップすると、その場で実行されます。迷ったら指を置いたまま止めると、9マスの一覧（HUD）が出ます。", bundle: .module)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .top, spacing: 28) {
                OnboardingTrackpadFigure(state: model.practice)
                    .frame(width: 312, height: 204)
                Group {
                    if let blocker = model.practiceBlocker {
                        OnboardingNotice(text: blocker) {
                            if !model.isAccessibilityGranted {
                                Button { model.requestAccessibility() } label: { Text("システム設定を開く", bundle: .module) }
                            } else if !model.isNonetEnabled {
                                Button { model.enableNonet() } label: { Text("有効にする", bundle: .module) }
                            }
                        }
                    } else {
                        OnboardingPracticeFeedback(state: model.practice)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding(.horizontal, OnboardingLayout.horizontalPadding)
        .padding(.top, 6)
    }
}

struct OnboardingPracticeFeedback: View {
    let state: OnboardingPracticeState

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            switch state {
            case .waiting:
                ProgressView()
                    .controlSize(.small)
                Text("タップを待っています…", bundle: .module)
                    .foregroundStyle(.secondary)
            case .wrongCell(let index):
                Image(systemName: "arrow.up.right.circle")
                    .font(.system(size: 18))
                Text("いまのは「\(HUDAnnouncement.positionName(index))」のマスです。右上をタップしてみてください", bundle: .module)
                    .fixedSize(horizontal: false, vertical: true)
            case .succeeded:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                VStack(alignment: .leading, spacing: 2) {
                    Text("できました！", bundle: .module)
                        .font(.system(size: 15, weight: .bold))
                    Text("右上のマスを押せました。実際に使うときは、ここで実行されます", bundle: .module)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(.system(size: 13))
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(state == .succeeded ? Color.primary : Color.secondary.opacity(0.3), lineWidth: state == .succeeded ? 2 : 1)
        )
        .accessibilityElement(children: .combine)
    }
}

/// 練習できないときの知らせ
struct OnboardingNotice<Actions: View>: View {
    let text: String
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
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

/// トラックパッドを上から見た図。右上が押してほしいマス
struct OnboardingTrackpadFigure: View {
    let state: OnboardingPracticeState

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.45))
                Path { path in
                    for line in 1...2 {
                        let x = width * CGFloat(line) / 3
                        let y = height * CGFloat(line) / 3
                        path.move(to: CGPoint(x: x, y: 6))
                        path.addLine(to: CGPoint(x: x, y: height - 6))
                        path.move(to: CGPoint(x: 6, y: y))
                        path.addLine(to: CGPoint(x: width - 6, y: y))
                    }
                }
                .stroke(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                ForEach(0..<9, id: \.self) { index in
                    marker(for: index)
                        .frame(width: width / 3, height: height / 3)
                        .offset(x: CGFloat(index % 3) * width / 3, y: CGFloat(index / 3) * height / 3)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("トラックパッドの図。右上のマスが目標です", bundle: .module))
    }

    @ViewBuilder
    private func marker(for index: Int) -> some View {
        if index == OnboardingModel.practiceTargetIndex {
            ZStack {
                Circle()
                    .strokeBorder(Color.primary.opacity(0.25), lineWidth: 1)
                    .frame(width: 46, height: 46)
                Circle()
                    .fill(Color.primary)
                    .frame(width: 26, height: 26)
                if state == .succeeded {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(nsColor: .controlBackgroundColor))
                }
            }
        } else if case .wrongCell(let wrong) = state, wrong == index {
            Circle()
                .strokeBorder(Color.secondary, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                .frame(width: 26, height: 26)
        }
    }
}

// MARK: - 4. 完了

struct OnboardingDoneStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                OnboardingLogo(size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text("準備ができました", bundle: .module)
                        .font(.system(size: 24, weight: .bold))
                    Text("使いながら覚えられるように、こつを3つだけ。", bundle: .module)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 14) {
                OnboardingTip(
                    symbol: "hand.raised",
                    title: Text("迷ったら、指を止める", bundle: .module),
                    detail: Text("キーを押したまま指を置いて止めると、9マスの一覧（HUD）が出ます。慣れたら、すぐにタップするだけで実行できます。", bundle: .module)
                )
                OnboardingTip(
                    symbol: "hand.draw",
                    title: Text("2本指で左右にスワイプ", bundle: .module),
                    detail: Text("キーを押したまま2本指でスワイプすると、ページが切り替わります。1つのアプリに最大3ページ置けます。", bundle: .module)
                )
                OnboardingTip(
                    symbol: "square.grid.3x3.middle.filled",
                    title: Text("メニューバーのアイコン", bundle: .module),
                    detail: Text("メニューバーの 3×3 のアイコンから、設定を開いたり、Nonet を有効・無効にしたりできます。", bundle: .module)
                )
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.secondary.opacity(0.3)))
        }
        .padding(.horizontal, OnboardingLayout.horizontalPadding)
        .padding(.top, 6)
    }
}

struct OnboardingTip: View {
    let symbol: String
    let title: Text
    let detail: Text

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 3) {
                title
                    .font(.system(size: 14, weight: .semibold))
                detail
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 部品

/// ロゴ（角の丸い 3×3、中央が塗り）。メニューバーのアイコンと同じ形
struct OnboardingLogo: View {
    let size: CGFloat

    var body: some View {
        let geometry = MenuBarIconGeometry.self
        let scale = size / geometry.canvas.width
        ZStack(alignment: .topLeading) {
            ForEach(Array(geometry.cellRects().enumerated()), id: \.offset) { index, rect in
                let shape = RoundedRectangle(cornerRadius: geometry.cornerRadius * scale, style: .continuous)
                Group {
                    if index == geometry.centerIndex {
                        shape.fill(Color.primary)
                    } else {
                        shape.strokeBorder(Color.primary, lineWidth: geometry.lineWidth * scale)
                    }
                }
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
