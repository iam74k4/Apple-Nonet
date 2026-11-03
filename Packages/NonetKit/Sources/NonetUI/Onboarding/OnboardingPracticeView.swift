// 担当: ui-shell
// 2. 試してみる: 上の縁から開いてマスで離す → 外枠で離してやめる の2つの課題。閉じる前に、ログイン時に起動を選ぶ
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
            Spacer(minLength: 0)
            OnboardingClosingOptions(model: model)
        }
        .padding(.horizontal, OnboardingLayout.horizontalPadding)
        .padding(.top, 6)
        .padding(.bottom, 18)
    }
}

/// 案内を閉じる前に決めておくこと: ログイン時に起動（初回起動では選んでおく）と、メニューバーのアイコンが見えないときの見つけ方
struct OnboardingClosingOptions: View {
    let model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !model.isStatusItemVisible {
                // ノッチの陰などで見えないときは、「3×3 のアイコン」と言っても見つけられない
                OnboardingNote(
                    symbol: "menubar.rectangle",
                    text: String(localized: "メニューバーにアイコンが見えないときは、アプリケーションフォルダから Nonet を開くと設定が開きます", bundle: .module)
                )
            }
            Toggle(isOn: Binding(get: { model.opensAtLogin }, set: { model.opensAtLogin = $0 })) {
                Text("Mac にログインしたら Nonet を自動で起動する", bundle: .module)
                    .font(.system(size: 13))
            }
            .toggleStyle(.checkbox)
            if let message = model.loginItemMessage {
                OnboardingNote(symbol: "exclamationmark.triangle", text: message)
            }
        }
    }
}

/// 練習の画面の下の短い一行
struct OnboardingNote: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
    }
}

/// 2つの課題。いまの課題だけ手順を出し、済んだ課題にはできたことを書く
struct OnboardingPracticeTasks: View {
    let model: OnboardingModel
    let page: OnboardingPracticePage

    var body: some View {
        let state = model.practice
        let cancelDetail: String? = switch state {
        case .run: nil
        case .cancel: ShellText.practiceCancelInstruction
        case .succeeded: ShellText.practiceCancelDone
        }
        VStack(alignment: .leading, spacing: 14) {
            OnboardingTaskRow(
                number: 1,
                // この画面で HUD と言うのは手順が最初（「HUD（9マスの一覧）」）
                title: Text("開いて、マスで離す", bundle: .module),
                status: state == .run ? .current : .done,
                detail: state == .run ? ShellText.practiceRunInstruction(page.runTarget) : ShellText.practiceRunDone
            )
            OnboardingTaskRow(
                number: 2,
                title: Text("外枠で離して、やめる", bundle: .module),
                status: state == .run ? .upcoming : state == .cancel ? .current : .done,
                detail: cancelDetail
            )
            if let feedback = model.practiceFeedback {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "arrow.uturn.backward.circle")
                        .font(.system(size: 15))
                        .accessibilityHidden(true)
                    Text(Self.text(for: feedback, page: page))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 12))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.secondary.opacity(0.4)))
                .accessibilityElement(children: .combine)
            }
            if state == .run {
                Text(ShellText.practiceOpenHint)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    static func text(for feedback: OnboardingPracticeFeedback, page: OnboardingPracticePage) -> String {
        switch feedback {
        case .wrongCell(let index, let title): ShellText.practiceWrongCell(index: index, title: title, target: page.runTarget)
        case .ranInsteadOfCancelling(let title): ShellText.practiceRanInsteadOfCancelling(title)
        case .notRun(let reason, let whileCancelling):
            ShellText.practiceNotRun(reason, target: page.runTarget, whileCancelling: whileCancelling)
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

/// トラックパッドを上から見た図。外枠（やめる場所）と、その内側の9マスにいま HUD に出るページのボタンの名前を並べる。
/// 上の縁の矢印は開き方（上の縁から下へ滑らせる）。いまの課題の場所（マスか外枠）に印を付ける
struct OnboardingTrackpadFigure: View {
    let page: OnboardingPracticePage?
    let state: OnboardingPracticeState
    let feedback: OnboardingPracticeFeedback?

    /// 外枠の幅（図の幅・高さに対する割合）。トラックパッドの外枠（GridInsets.cancelFrame）と同じ割合で描く
    private static let frame = GridInsets.cancelFrame

    private var currentTarget: OnboardingPracticeTarget? {
        state == .run ? page?.runTarget : nil
    }

    private var isFrameTarget: Bool { state == .cancel }

    private var doneIndices: Set<Int> {
        guard let page, state != .run else { return [] }
        return [page.runTarget.index]
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let inner = CGRect(
                x: width * Self.frame.left,
                y: height * Self.frame.top,
                width: width * (1 - Self.frame.left - Self.frame.right),
                height: height * (1 - Self.frame.top - Self.frame.bottom)
            )
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isFrameTarget ? Color.primary.opacity(0.12) : Color.primary.opacity(0.04))
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isFrameTarget ? Color.primary.opacity(0.8) : Color.secondary.opacity(0.45), lineWidth: isFrameTarget ? 1.5 : 1)
                // 9マス（外枠の内側）
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .frame(width: inner.width, height: inner.height)
                    .offset(x: inner.minX, y: inner.minY)
                Path { path in
                    for line in 1...2 {
                        let x = inner.minX + inner.width * CGFloat(line) / 3
                        let y = inner.minY + inner.height * CGFloat(line) / 3
                        path.move(to: CGPoint(x: x, y: inner.minY + 4))
                        path.addLine(to: CGPoint(x: x, y: inner.maxY - 4))
                        path.move(to: CGPoint(x: inner.minX + 4, y: y))
                        path.addLine(to: CGPoint(x: inner.maxX - 4, y: y))
                    }
                }
                .stroke(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                ForEach(0..<Page.cellCount, id: \.self) { index in
                    cell(index)
                        .opacity(isFrameTarget ? 0.45 : 1)
                        .frame(width: inner.width / 3, height: inner.height / 3)
                        .offset(x: inner.minX + CGFloat(index % 3) * inner.width / 3, y: inner.minY + CGFloat(index / 3) * inner.height / 3)
                }
                // 開き方: 上の縁から下へ
                Image(systemName: "arrow.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: width, height: inner.minY)
                if isFrameTarget {
                    Text("外枠で離す", bundle: .module)
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: width, height: height * Self.frame.bottom)
                        .offset(y: inner.maxY)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: Text {
        if let currentTarget {
            Text(ShellText.practiceFigureLabel(currentTarget))
        } else if isFrameTarget {
            Text(ShellText.practiceFigureCancelLabel)
        } else {
            Text("トラックパッドの図", bundle: .module)
        }
    }

    private func cell(_ index: Int) -> some View {
        let title = page?.titles[index]
        let isTarget = currentTarget?.index == index
        let isDone = doneIndices.contains(index)
        let isWrong = feedback == .wrongCell(index: index, title: Self.title(of: feedback))
        return VStack(spacing: 3) {
            marker(isTarget: isTarget, isDone: isDone, isWrong: isWrong)
                .frame(height: 20)
            if let title {
                Text(title)
                    .font(.system(size: 10, weight: isTarget ? .bold : .regular))
                    .foregroundStyle(isTarget || isDone ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 4)
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
                    .frame(width: 20, height: 20)
                Circle()
                    .fill(Color.primary)
                    .frame(width: 11, height: 11)
            }
        } else if isDone {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
        } else if isWrong {
            Circle()
                .strokeBorder(Color.secondary, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                .frame(width: 16, height: 16)
        } else {
            Color.clear.frame(width: 20, height: 20)
        }
    }
}
