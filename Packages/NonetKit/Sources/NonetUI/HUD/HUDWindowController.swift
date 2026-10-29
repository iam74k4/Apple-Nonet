// 担当: ui-shell（クラス名・init・HUDPresenting への準拠は契約）
import AppKit
import NonetCore
import SwiftUI

/// HUD とトースト。前面アプリからフォーカスを奪わない、最前面のパネルに出す
@MainActor
public final class HUDWindowController: HUDPresenting {
    public init() {}

    public func show(_ model: HUDModel, position: HUDPosition) {}

    public func update(_ model: HUDModel) {}

    public func hide() {}

    public func showToast(_ toast: ToastModel) {}

    public func showResult(_ result: ResultModel) {}
}
