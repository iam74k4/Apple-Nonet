// 担当: core-model（公開 API は契約）
import Foundation

/// 保存される設定のすべて
public struct NonetConfiguration: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var settings: GlobalSettings
    /// 先頭は必ずグローバルのプロファイル。アプリのプロファイルは bundleID ごとに1つまで
    public var profiles: [Profile]

    public init(version: Int = NonetConfiguration.currentVersion, settings: GlobalSettings = GlobalSettings(), profiles: [Profile]) {
        self.version = version
        self.settings = settings
        self.profiles = profiles
    }
}

/// 前面アプリで使うページ1枚分（HUD に出すもの）
public struct ResolvedPage: Equatable, Sendable {
    public var profileID: UUID
    public var profileName: String
    /// プロファイル内でのページ番号
    public var pageIndex: Int
    public var cells: [Cell?]

    public init(profileID: UUID, profileName: String, pageIndex: Int, cells: [Cell?]) {
        self.profileID = profileID
        self.profileName = profileName
        self.pageIndex = pageIndex
        self.cells = cells
    }
}

extension NonetConfiguration {
    /// 初回起動時の設定。グローバルはインストール済みのアプリを並べたランチャー、アプリのプロファイルは渡されたプリセットから作る
    public static func initial(trigger: TriggerKey, appPresets: [AppPreset], installedBundleIDs: Set<String>) -> NonetConfiguration {
        fatalError("未実装: core-model")
    }

    public var globalProfile: Profile {
        fatalError("未実装: core-model")
    }

    public func profile(id: UUID) -> Profile? {
        fatalError("未実装: core-model")
    }

    /// 有効なアプリのプロファイル
    public func appProfile(forBundleID bundleID: String) -> Profile? {
        fatalError("未実装: core-model")
    }

    /// すでにあればそのプロファイルの id を返す。preset があればその中身で作る
    @discardableResult
    public mutating func addAppProfile(for app: AppReference, preset: AppPreset?) -> UUID {
        fatalError("未実装: core-model")
    }

    /// グローバルは消せない（何もしない）
    public mutating func removeProfile(id: UUID) {
        fatalError("未実装: core-model")
    }

    /// アプリのプロファイルの並べ替え。offsets と destination はアプリのプロファイルだけの並びでの位置
    public mutating func moveAppProfiles(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        fatalError("未実装: core-model")
    }

    public mutating func updateProfile(id: UUID, _ transform: (inout Profile) -> Void) {
        fatalError("未実装: core-model")
    }

    public mutating func setCell(_ cell: Cell?, at address: CellAddress, profileID: UUID) {
        fatalError("未実装: core-model")
    }

    /// 2つのマスを入れ替える（片方が空きマスなら移動になる）
    public mutating func swapCells(_ a: CellAddress, _ b: CellAddress, profileID: UUID) {
        fatalError("未実装: core-model")
    }

    /// 追加したページの番号。上限なら nil
    @discardableResult
    public mutating func addPage(profileID: UUID) -> Int? {
        fatalError("未実装: core-model")
    }

    /// 最後の1ページは消せない
    public mutating func removePage(at index: Int, profileID: UUID) {
        fatalError("未実装: core-model")
    }

    /// 前面アプリで使うページの並び。
    /// autoSwitchProfiles が true でアプリのプロファイルがあればそのページ、appendGlobalPages ならその後ろにグローバルのページ。
    /// それ以外はグローバルのページだけ
    public func resolvedPages(frontmostBundleID: String?) -> [ResolvedPage] {
        fatalError("未実装: core-model")
    }

    /// 壊れた設定を直したもの（グローバルが先頭に1つ、ページ数、マス数、重複 id、hudDelay の範囲など）
    public func validated() -> NonetConfiguration {
        fatalError("未実装: core-model")
    }
}
