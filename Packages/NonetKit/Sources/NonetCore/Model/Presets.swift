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
    /// 用意しているアプリのプリセット。初回起動の「アプリを選ぶ」に出す順
    public static var apps: [AppPreset] {
        [
            PresetData.xcode,
            PresetData.vsCode,
            PresetData.cursor,
            PresetData.terminal,
            PresetData.figma,
            PresetData.zoom,
            PresetData.slack,
            PresetData.teams,
            PresetData.safari,
            PresetData.chrome,
            PresetData.arc,
            PresetData.finder,
            PresetData.notion,
            PresetData.mail,
            PresetData.notes,
        ]
    }

    /// bundleID の大文字・小文字は区別しない（Launch Services と同じ）
    public static func preset(forBundleID bundleID: String) -> AppPreset? {
        apps.first { $0.app.bundleID.caseInsensitiveCompare(bundleID) == .orderedSame }
    }

    /// グローバル（ランチャー）に並べるアプリの候補。優先順
    public static var launcherCandidates: [AppReference] {
        PresetData.launcherEntries.map(\.app)
    }

    /// インストール済みの候補を優先順に9個ずつ並べたグローバルのプロファイル（最大 Profile.maxPages ページ）。
    /// 1つも無ければ空の1ページ
    public static func makeGlobalProfile(installedBundleIDs: Set<String>) -> Profile {
        let installed = Set(installedBundleIDs.map { $0.lowercased() })
        let cells = PresetData.launcherEntries
            .filter { installed.contains($0.app.bundleID.lowercased()) }
            .prefix(Page.cellCount * Profile.maxPages)
            .map { entry in
                Cell(
                    title: entry.title,
                    icon: .app(bundleID: entry.app.bundleID),
                    action: .launchApp(LaunchAppAction(app: entry.app))
                )
            }
        let pages = stride(from: 0, to: cells.count, by: Page.cellCount).map { start in
            Page(cells: Array(cells[start..<min(start + Page.cellCount, cells.count)]))
        }
        return Profile(kind: .global, pages: pages.isEmpty ? [.empty] : pages)
    }
}
