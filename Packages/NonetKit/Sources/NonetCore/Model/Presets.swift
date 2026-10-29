// 担当: presets（公開 API は契約）
import Foundation

/// 初回起動で用意するアプリ別の9マス
public struct AppPreset: Identifiable, Sendable {
    public var app: AppReference
    /// 「開発」「デザイン」など（ローカライズ済み）
    public var category: String
    /// 「ビルド、テスト、Claude Code など9個」のような説明（ローカライズ済み）
    public var summary: String
    public var pages: [Page]

    public init(app: AppReference, category: String, summary: String, pages: [Page]) {
        self.app = app
        self.category = category
        self.summary = summary
        self.pages = pages
    }

    public var id: String { app.bundleID }

    /// このプリセットからプロファイルを作る。マスの id は毎回振り直す
    public func makeProfile() -> Profile {
        let pages = pages.map { page in
            Page(cells: page.cells.map { cell in
                cell.map { Cell(title: $0.title, icon: $0.icon, action: $0.action) }
            })
        }
        return Profile(kind: .app(app), pages: pages)
    }
}

public enum PresetLibrary {
    /// 用意しているアプリのプリセット
    public static var apps: [AppPreset] {
        fatalError("未実装: presets")
    }

    public static func preset(forBundleID bundleID: String) -> AppPreset? {
        apps.first { $0.app.bundleID == bundleID }
    }

    /// グローバル（ランチャー）に並べるアプリの候補。優先順
    public static var launcherCandidates: [AppReference] {
        fatalError("未実装: presets")
    }

    /// インストール済みの候補を最大9個並べたグローバルのプロファイル
    public static func makeGlobalProfile(installedBundleIDs: Set<String>) -> Profile {
        fatalError("未実装: presets")
    }
}
