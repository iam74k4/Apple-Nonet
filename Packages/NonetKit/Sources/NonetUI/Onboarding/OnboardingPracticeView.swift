// 担当: ui-shell
// 3. 試してみる: HUD から選ぶ → すぐにタップ の2つの課題と、その後の角の長押しの紹介
import NonetCore
import SwiftUI

struct OnboardingPracticeStep: View {
    let model: OnboardingModel

    var body: some View {
        let page = model.practicePage
        let blocker = model.practiceBlocker
        VStack(alignment: .leading, spacing: 16) {
            // 上の段の「試してみる」（Try It Out）とは別の文言（見出しは sentence case）
            Text("試してみましょう", bundle: .module)
                .font(.system(size: 22, weight: .bold))
                .onboardingHeading()
            HStack(alignment: .top, spacing: 28) {
                OnboardingTrackpadFigure(page: page, state: model.practice, feedback: model.practiceFeedback)
                    .frame(width: 312, height: 204)
                Group {
                    if let blocker {
                        OnboardingNotice(text: blocker.message) {
                            if let remedy = blocker.remedy {
                                Button { model.resolve(remedy) } label: { Text(remedy.title) }
                            }
                        }
                    } else if let page {
                        OnboardingPracticeTasks(model: model, page: page)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            if blocker == nil, let trial = model.cornerTrial {
                OnboardingCornerCard(model: model, trial: trial)
            }
        }
        .padding(.horizontal, OnboardingLayout.horizontalPadding)
        .padding(.top, 6)
    }
}

/// 2つの課題。いまの課題だけ手順を出し、済んだ課題にはできたことを書く
struct OnboardingPracticeTasks: View {
    let model: OnboardingModel
    let page: OnboardingPracticePage

    var body: some View {
        let state = model.practice
        let quickTapDetail: String? = switch state {
        case .hud: nil
        case .quickTap: ShellText.practiceQuickTapInstruction(trigger: model.trigger, target: page.quickTapTarget)
        case .succeeded: ShellText.practiceQuickTapDone(page.quickTapTarget)
        }
        VStack(alignment: .leading, spacing: 14) {
            OnboardingTaskRow(
                number: 1,
                // この画面で HUD と言うのはここが最初
                title: Text("HUD（9マスの一覧）から選ぶ", bundle: .module),
                status: state == .hud ? .current : .done,
                detail: state == .hud
                    ? ShellText.practiceHUDInstruction(trigger: model.trigger, fireMode: model.fireMode, target: page.hudTarget)
                    : ShellText.practiceHUDDone
            )
            OnboardingTaskRow(
                number: 2,
                title: Text("すぐにタップ", bundle: .module),
                status: state == .hud ? .upcoming : state == .quickTap ? .current : .done,
                detail: quickTapDetail
            )
            if let feedback = model.practiceFeedback, let text = Self.text(for: feedback, state: state, page: page) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "arrow.uturn.backward.circle")
                        .font(.system(size: 15))
                        .accessibilityHidden(true)
                    Text(text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 12))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.secondary.opacity(0.4)))
                .accessibilityElement(children: .combine)
            }
        }
    }

    static func text(for feedback: OnboardingPracticeFeedback, state: OnboardingPracticeState, page: OnboardingPracticePage) -> String? {
        switch feedback {
        case .wrongCell(let index, let title):
            switch state {
            case .hud: ShellText.practiceWrongCell(index: index, title: title, target: page.hudTarget)
            case .quickTap: ShellText.practiceWrongCell(index: index, title: title, target: page.quickTapTarget)
            case .succeeded: nil
            }
        case .tooQuick: ShellText.practiceTooQuick
        case .usedHUD: ShellText.practiceUsedHUD
        }
    }
}

enum OnboardingTaskStatus: Equatable {
    case current
    case done
    case upcoming
}

/// 課題の1行。番号（済んだらチェック）・見出し・手順かできたこと
struct OnboardingTaskRow: View {
    let number: Int
    let title: Text
    let status: OnboardingTaskStatus
    let detail: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                switch status {
                case .current:
                    Circle().fill(Color.primary)
                    Text(verbatim: "\(number)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                case .done:
                    Circle().strokeBorder(Color.primary, lineWidth: 1)
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                case .upcoming:
                    Circle().strokeBorder(Color.secondary.opacity(0.6), lineWidth: 1)
                    Text(verbatim: "\(number)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 20, height: 20)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                title
                    .font(.system(size: 14, weight: status == .current ? .bold : .semibold))
                    .foregroundStyle(status == .upcoming ? Color.secondary : Color.primary)
                if let detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(status == .done ? Color.secondary : Color.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: Text {
        switch status {
        case .current: Text("いまの課題", bundle: .module)
        case .done: Text("済み", bundle: .module)
        case .upcoming: Text("この後の課題", bundle: .module)
        }
    }
}

/// 練習ができた後の「キーを使わない方法もあります」。選んだ角で設定をオンにして、その場で試してもらう
struct OnboardingCornerCard: View {
    let model: OnboardingModel
    let trial: OnboardingCornerTrial

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "hand.point.up.left")
                .font(.system(size: 18))
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text("キーを使わない方法もあります", bundle: .module)
                    .font(.system(size: 14, weight: .semibold))
                switch trial {
                case .offered:
                    Text("トラックパッドの左上か右上の角を押したまま少し待つと、HUD が出ます", bundle: .module)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        Picker(selection: Binding(get: { model.cornerChoice }, set: { model.cornerChoice = $0 })) {
                            Text("左上の角", bundle: .module).tag(TouchActivation.topLeft)
                            Text("右上の角", bundle: .module).tag(TouchActivation.topRight)
                        } label: {
                            Text("トラックパッドだけで呼び出す", bundle: .module)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                        Button { model.tryCornerActivation() } label: { Text("試してみる", bundle: .module) }
                    }
                    .controlSize(.small)
                case .trying(let corner):
                    Text(ShellText.cornerTrialInstruction(corner))
                        .font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)
                    Button { model.turnOffCornerActivation() } label: { Text("オフに戻す", bundle: .module) }
                        .controlSize(.small)
                case .succeeded:
                    Label {
                        Text(ShellText.cornerTrialDone)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    .font(.system(size: 12))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.secondary.opacity(0.3)))
    }
}

/// トラックパッドを上から見た図。いま HUD に出るページのボタンの名前を並べ、いまの課題のマスに印を付ける
struct OnboardingTrackpadFigure: View {
    let page: OnboardingPracticePage?
    let state: OnboardingPracticeState
    let feedback: OnboardingPracticeFeedback?

    private var currentTarget: OnboardingPracticeTarget? {
        switch state {
        case .hud: page?.hudTarget
        case .quickTap: page?.quickTapTarget
        case .succeeded: nil
        }
    }

    private var doneIndices: Set<Int> {
        guard let page else { return [] }
        switch state {
        case .hud: return []
        case .quickTap: return [page.hudTarget.index]
        case .succeeded: return [page.hudTarget.index, page.quickTapTarget.index]
        }
    }

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
                ForEach(0..<Page.cellCount, id: \.self) { index in
                    cell(index)
                        .frame(width: width / 3, height: height / 3)
                        .offset(x: CGFloat(index % 3) * width / 3, y: CGFloat(index / 3) * height / 3)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: Text {
        if let currentTarget {
            Text(ShellText.practiceFigureLabel(currentTarget))
        } else {
            Text("トラックパッドの図", bundle: .module)
        }
    }

    private func cell(_ index: Int) -> some View {
        let title = page?.titles[index]
        let isTarget = currentTarget?.index == index
        let isDone = doneIndices.contains(index)
        let isWrong = feedback == .wrongCell(index: index, title: Self.title(of: feedback))
        return VStack(spacing: 4) {
            marker(isTarget: isTarget, isDone: isDone, isWrong: isWrong)
                .frame(height: 22)
            if let title {
                Text(title)
                    .font(.system(size: 10, weight: isTarget ? .bold : .regular))
                    .foregroundStyle(isTarget || isDone ? Color.primary : Color.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 6)
            }
        }
    }

    /// 違うマスの知らせに入っている名前（位置だけを比べるため）
    private static func title(of feedback: OnboardingPracticeFeedback?) -> String {
        guard case .wrongCell(_, let title)? = feedback else { return "" }
        return title
    }

    @ViewBuilder
    private func marker(isTarget: Bool, isDone: Bool, isWrong: Bool) -> some View {
        if isTarget {
            ZStack {
                Circle()
                    .strokeBorder(Color.primary.opacity(0.25), lineWidth: 1)
                    .frame(width: 22, height: 22)
                Circle()
                    .fill(Color.primary)
                    .frame(width: 12, height: 12)
            }
        } else if isDone {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15))
        } else if isWrong {
            Circle()
                .strokeBorder(Color.secondary, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                .frame(width: 18, height: 18)
        } else {
            Color.clear.frame(width: 22, height: 22)
        }
    }
}
