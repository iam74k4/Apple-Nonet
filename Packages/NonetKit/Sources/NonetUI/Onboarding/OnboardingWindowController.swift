// 担当: ui-shell（クラス名・init・show は契約）
import AppKit
import NonetCore
import SwiftUI

/// 初回起動のウィンドウ（権限 → アプリを選ぶ → 試してみる）
@MainActor
public final class OnboardingWindowController {
    /// onFinish: 完了または「あとで設定する」で閉じたとき
    public init(controller: NonetController, services: NonetServices, onFinish: @escaping () -> Void) {}

    public func show() {}
}
