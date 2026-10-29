// 担当: platform-actions
// クラス名・public init・protocol への準拠は契約（NonetServices.live() が使う）。
// 中身は担当が書き換え、必要ならファイルを分けてよい（Actions/ 以下）。
import AppKit
import NonetCore

/// Action を実行する（キー送出・アプリ起動・URL・スクリプト・ショートカット・メニュー・AI）
@MainActor
public final class SystemActionPerformer: ActionPerforming {
    public init() {}

    public func perform(_ action: Action, context: ActionContext) async throws {
        throw NonetError.unavailable("未実装")
    }
}

/// アクセシビリティ API でアプリのメニューを読む
@MainActor
public final class AccessibilityMenuReader: MenuReading {
    public init() {}

    public func runningApps() -> [RunningAppInfo] { [] }

    public func menuItems(for app: RunningAppInfo) throws -> [MenuItemNode] { [] }
}

@MainActor
public final class WorkspaceInstalledApps: InstalledAppsProviding {
    public init() {}

    public func installedApps() -> [AppReference] { [] }

    public func isInstalled(bundleID: String) -> Bool { false }
}

/// `shortcuts list` でショートカットの名前を得る
@MainActor
public final class ShortcutsCLI: ShortcutsProviding {
    public init() {}

    public func shortcutNames() async -> [String] { [] }
}

/// SMAppService でログイン時に起動する
@MainActor
public final class SMAppServiceLoginItem: LoginItemControlling {
    public init() {}

    public var isEnabled: Bool { false }

    public func setEnabled(_ enabled: Bool) throws {}
}
