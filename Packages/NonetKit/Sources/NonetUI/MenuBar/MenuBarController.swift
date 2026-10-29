// 担当: ui-shell（クラス名・init は契約）
import AppKit
import NonetCore
import SwiftUI

/// メニューバーのアイコンとメニュー
@MainActor
public final class MenuBarController {
    public init(
        controller: NonetController,
        license: LicenseManager,
        onOpenSettings: @escaping (SettingsTab) -> Void,
        onOpenOnboarding: @escaping () -> Void,
        onCheckForUpdates: (() -> Void)?
    ) {}
}
