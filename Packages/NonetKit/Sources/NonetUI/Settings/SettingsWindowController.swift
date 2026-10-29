// 担当: ui-settings（クラス名・init・show は契約。App が使う）
import AppKit
import NonetCore
import SwiftUI

public enum SettingsTab: String, CaseIterable, Sendable {
    /// プロファイルと9マスの編集
    case profiles
    /// トリガーや HUD など全体の設定
    case general
    case license
    case about
}

/// 設定ウィンドウ
@MainActor
public final class SettingsWindowController {
    /// purchaseURL: 購入ページ。onCheckForUpdates: アップデートの確認（無ければボタンを出さない）
    public init(
        controller: NonetController,
        license: LicenseManager,
        services: NonetServices,
        purchaseURL: URL?,
        onCheckForUpdates: (() -> Void)?
    ) {}

    public func show(tab: SettingsTab = .profiles) {}
}
