// 担当: ui-shell
// 4. 完了: 使い方のこつ・試用期間・メニューバーのアイコンの見つけ方・ログイン時に起動
import NonetCore
import SwiftUI

struct OnboardingDoneStep: View {
    let model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                OnboardingLogo(size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text("準備ができました", bundle: .module)
                        .font(.system(size: 24, weight: .bold))
                        .onboardingHeading()
                    Text("使いながら覚えられる、4つのこつ", bundle: .module)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                OnboardingTip(
                    symbol: "hand.raised",
                    title: Text("迷ったら、指を止める", bundle: .module),
                    detail: Text(ShellText.doneHUDTip(model.fireMode))
                )
                OnboardingTip(
                    symbol: "hand.draw",
                    title: Text("2本指で左右にスワイプ", bundle: .module),
                    detail: Text("キーを押したまま2本指でスワイプすると、ページが切り替わります。1つのアプリに最大3ページ置けます。", bundle: .module)
                )
                OnboardingTip(
                    symbol: "square.grid.3x3.middle.filled",
                    title: Text("マスを変える", bundle: .module),
                    detail: Text(ShellText.doneEditTip)
                )
                OnboardingTip(
                    symbol: "hand.point.up.left",
                    title: Text("片手で使うときは、角に指を置いて待つ", bundle: .module),
                    detail: Text(ShellText.doneCornerTip(model.cornerActivation))
                )
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.secondary.opacity(0.3)))
            VStack(alignment: .leading, spacing: 6) {
                if let days = model.trialDaysLeft {
                    OnboardingNote(symbol: "clock", text: ShellText.trialNote(daysLeft: days))
                }
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
                .padding(.top, 2)
                if let message = model.loginItemMessage {
                    OnboardingNote(symbol: "exclamationmark.triangle", text: message)
                }
            }
        }
        .padding(.horizontal, OnboardingLayout.horizontalPadding)
        .padding(.top, 6)
    }
}

/// 完了の画面の短い一行
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

struct OnboardingTip: View {
    let symbol: String
    let title: Text
    let detail: Text

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .frame(width: 28, height: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                title
                    .font(.system(size: 13, weight: .semibold))
                detail
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
