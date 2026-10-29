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

/// 販売サイトのページ。Info.plist の値（未設定なら nil で、そのリンクは出さない）
public struct AppLinks: Equatable, Sendable {
    /// 購入ページ
    public var purchase: URL?
    /// 利用ガイドとサポート
    public var support: URL?
    /// プライバシーポリシー
    public var privacy: URL?

    public init(purchase: URL? = nil, support: URL? = nil, privacy: URL? = nil) {
        self.purchase = purchase
        self.support = support
        self.privacy = privacy
    }
}

/// 設定ウィンドウ
@MainActor
public final class SettingsWindowController {
    /// onCheckForUpdates: アップデートの確認（無ければボタンを出さない）
    public init(
        controller: NonetController,
        license: LicenseManager,
        services: NonetServices,
        links: AppLinks,
        onCheckForUpdates: (() -> Void)?
    ) {}

    public func show(tab: SettingsTab = .profiles) {}
}
