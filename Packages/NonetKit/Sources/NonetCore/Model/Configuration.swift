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
        initial(
            trigger: trigger,
            appPresets: appPresets,
            globalProfile: PresetLibrary.makeGlobalProfile(installedBundleIDs: installedBundleIDs)
        )
    }

    static func initial(trigger: TriggerKey, appPresets: [AppPreset], globalProfile: Profile) -> NonetConfiguration {
        let global = Profile(id: globalProfile.id, kind: .global, pages: globalProfile.pages)
        var configuration = NonetConfiguration(settings: GlobalSettings(trigger: trigger), profiles: [global])
        for preset in appPresets {
            configuration.addAppProfile(for: preset.app, preset: preset)
        }
        return configuration.validated()
    }

    public var globalProfile: Profile {
        // validated() を通っていれば必ずある。無いときも毎回同じ値を返す
        profiles.first(where: \.isGlobal) ?? Profile(id: Self.placeholderGlobalProfileID, kind: .global)
    }

    static let placeholderGlobalProfileID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    public func profile(id: UUID) -> Profile? {
        profiles.first { $0.id == id }
    }

    /// 有効なアプリのプロファイル
    public func appProfile(forBundleID bundleID: String) -> Profile? {
        let key = Self.bundleIDKey(bundleID)
        guard !key.isEmpty else { return nil }
        return profiles.first { profile in
            profile.isEnabled && profile.app.map { Self.bundleIDKey($0.bundleID) == key } == true
        }
    }

    /// すでにあればそのプロファイルの id を返す。preset があればその中身で作る
    @discardableResult
    public mutating func addAppProfile(for app: AppReference, preset: AppPreset?) -> UUID {
        if let index = appProfileIndex(forBundleID: app.bundleID) {
            return profiles[index].id
        }
        // makeProfile() はマスの id を振り直すので、ほかのプロファイルと重ならない
        var profile = Profile(kind: .app(app), pages: preset?.makeProfile().pages ?? [.empty])
        profile.normalizePages()
        profiles.append(profile)
        return profile.id
    }

    /// グローバルは消せない（何もしない）
    public mutating func removeProfile(id: UUID) {
        profiles.removeAll { $0.id == id && !$0.isGlobal }
    }

    /// アプリのプロファイルの並べ替え。offsets と destination はアプリのプロファイルだけの並びでの位置
    public mutating func moveAppProfiles(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        var apps = profiles.filter { !$0.isGlobal }
        let sources = offsets.filter { apps.indices.contains($0) }
        guard !sources.isEmpty else { return }
        let target = min(max(destination, 0), apps.count)
        let moving = sources.map { apps[$0] }
        for index in sources.reversed() {
            apps.remove(at: index)
        }
        let insertAt = target - sources.filter { $0 < target }.count
        apps.insert(contentsOf: moving, at: insertAt)
        profiles = profiles.filter(\.isGlobal) + apps
    }

    /// プロファイルを書き換える。id・グローバルかどうか・ほかと重なる bundleID への変更は受け付けず、元に戻す
    public mutating func updateProfile(id: UUID, _ transform: (inout Profile) -> Void) {
        guard let index = profileIndex(id: id) else { return }
        let original = profiles[index]
        var updated = original
        transform(&updated)
        updated.id = original.id
        if updated.isGlobal != original.isGlobal {
            updated.kind = original.kind
        } else if let app = updated.app, Self.bundleIDKey(app.bundleID) != original.app.map({ Self.bundleIDKey($0.bundleID) }) {
            let taken = profiles.indices.contains { other in
                other != index && profiles[other].app.map { Self.bundleIDKey($0.bundleID) } == Self.bundleIDKey(app.bundleID)
            }
            if taken || app.bundleID.trimmedNonEmpty == nil {
                updated.kind = original.kind
            }
        }
        profiles[index] = updated
        // ページ数・マス数・マスの id の重なり（複製したマスなど）を直す
        self = validated()
    }

    public mutating func setCell(_ cell: Cell?, at address: CellAddress, profileID: UUID) {
        guard let index = profileIndex(id: profileID) else { return }
        profiles[index].normalizePages()
        guard Self.contains(address, in: profiles[index]) else { return }
        var cell = cell
        // 別の場所のマスと id が同じなら（複製など）、新しい id にする
        if let id = cell?.id, containsCell(id: id, except: (index, address)) {
            cell?.id = UUID()
        }
        profiles[index].pages[address.page].cells[address.index] = cell
    }

    /// 2つのマスを入れ替える（片方が空きマスなら移動になる）
    public mutating func swapCells(_ a: CellAddress, _ b: CellAddress, profileID: UUID) {
        guard let index = profileIndex(id: profileID) else { return }
        profiles[index].normalizePages()
        let profile = profiles[index]
        guard Self.contains(a, in: profile), Self.contains(b, in: profile), a != b else { return }
        profiles[index].pages[a.page].cells[a.index] = profile.pages[b.page].cells[b.index]
        profiles[index].pages[b.page].cells[b.index] = profile.pages[a.page].cells[a.index]
    }

    /// 追加したページの番号。上限なら nil
    @discardableResult
    public mutating func addPage(profileID: UUID) -> Int? {
        guard let index = profileIndex(id: profileID), profiles[index].pages.count < Profile.maxPages else { return nil }
        profiles[index].pages.append(.empty)
        return profiles[index].pages.count - 1
    }

    /// 最後の1ページは消せない
    public mutating func removePage(at pageIndex: Int, profileID: UUID) {
        guard let index = profileIndex(id: profileID),
              profiles[index].pages.count > 1,
              profiles[index].pages.indices.contains(pageIndex) else { return }
        profiles[index].pages.remove(at: pageIndex)
    }

    /// 前面アプリで使うページの並び。
    /// autoSwitchProfiles が true でアプリのプロファイルがあればそのページ、appendGlobalPages ならその後ろにグローバルのページ。
    /// それ以外はグローバルのページだけ
    public func resolvedPages(frontmostBundleID: String?) -> [ResolvedPage] {
        let globalPages = Self.resolve(globalProfile)
        guard settings.autoSwitchProfiles,
              let bundleID = frontmostBundleID,
              let appProfile = appProfile(forBundleID: bundleID) else {
            return globalPages
        }
        let appPages = Self.resolve(appProfile)
        return settings.appendGlobalPages ? appPages + globalPages : appPages
    }

    /// 壊れた設定を直したもの（グローバルが先頭に1つ、ページ数、マス数、重複 id、hudDelay の範囲など）
    public func validated() -> NonetConfiguration {
        var usedProfileIDs = Set<UUID>()
        var usedCellIDs = Set<UUID>()
        var seenBundleIDs = Set<String>()
        var global: Profile?
        var apps: [Profile] = []

        for var profile in profiles {
            switch profile.kind {
            case .global:
                guard global == nil else {
                    modelLogger.warning("グローバルのプロファイルが2つ以上あったので、2つ目以降を外した")
                    continue
                }
                // グローバルは無効にできない（アプリのプロファイルが無いときに使うページが無くなる）
                profile.isEnabled = true
            case .app(let app):
                guard seenBundleIDs.insert(Self.bundleIDKey(app.bundleID)).inserted else {
                    modelLogger.warning("同じアプリのプロファイルが2つ以上あったので、2つ目以降を外した")
                    continue
                }
            }
            if !usedProfileIDs.insert(profile.id).inserted {
                profile.id = Self.uniqueID(avoiding: usedProfileIDs)
                usedProfileIDs.insert(profile.id)
            }
            profile.normalizePages()
            for page in profile.pages.indices {
                for slot in profile.pages[page].cells.indices {
                    guard var cell = profile.pages[page].cells[slot] else { continue }
                    if !usedCellIDs.insert(cell.id).inserted {
                        cell.id = Self.uniqueID(avoiding: usedCellIDs)
                        usedCellIDs.insert(cell.id)
                    }
                    cell.action = cell.action.validated()
                    profile.pages[page].cells[slot] = cell
                }
            }
            if profile.isGlobal {
                global = profile
            } else {
                apps.append(profile)
            }
        }

        let globalProfile = global ?? Profile(id: Self.uniqueID(avoiding: usedProfileIDs), kind: .global)
        if global == nil {
            modelLogger.warning("グローバルのプロファイルが無かったので、空のものを加えた")
        }
        return NonetConfiguration(version: Self.currentVersion, settings: settings.validated(), profiles: [globalProfile] + apps)
    }
}

// MARK: - 読み込み（.nonetprofile）

extension NonetConfiguration {
    /// importProfiles の結果。設定画面で「2個追加、1個置き換え」のように知らせる
    public struct ImportResult: Equatable, Sendable {
        /// 新しく加えたアプリのプロファイルの数
        public var added: Int
        /// 同じアプリのプロファイルを置き換えた数
        public var replaced: Int
        /// グローバルのページを置き換えた
        public var replacedGlobal: Bool
        /// 同じアプリの重複などで使わなかった数
        public var skipped: Int

        public init(added: Int = 0, replaced: Int = 0, replacedGlobal: Bool = false, skipped: Int = 0) {
            self.added = added
            self.replaced = replaced
            self.replacedGlobal = replacedGlobal
            self.skipped = skipped
        }

        /// 設定に反映したプロファイルの数
        public var appliedCount: Int {
            added + replaced + (replacedGlobal ? 1 : 0)
        }
    }

    /// 読み込んだプロファイルを加える。アプリのプロファイルは同じ bundleID のものを置き換え（位置と id は保つ）、無ければ後ろに加える。
    /// グローバルのプロファイルはグローバルのページを置き換える。同じアプリやグローバルが2つ以上あれば最初のものだけ使う
    @discardableResult
    public mutating func importProfiles(_ imported: [Profile]) -> ImportResult {
        var result = ImportResult()
        var seenBundleIDs = Set<String>()
        var importedGlobal = false

        for var profile in imported {
            profile.normalizePages()
            switch profile.kind {
            case .global:
                guard !importedGlobal else {
                    result.skipped += 1
                    continue
                }
                importedGlobal = true
                if let index = profiles.firstIndex(where: \.isGlobal) {
                    profiles[index].pages = profile.pages
                } else {
                    profiles.insert(Profile(kind: .global, pages: profile.pages), at: 0)
                }
                result.replacedGlobal = true
            case .app(let app):
                let key = Self.bundleIDKey(app.bundleID)
                guard !key.isEmpty, seenBundleIDs.insert(key).inserted else {
                    result.skipped += 1
                    continue
                }
                if let index = appProfileIndex(forBundleID: app.bundleID) {
                    profile.id = profiles[index].id
                    profiles[index] = profile
                    result.replaced += 1
                } else {
                    if profiles.contains(where: { $0.id == profile.id }) {
                        profile.id = UUID()
                    }
                    profiles.append(profile)
                    result.added += 1
                }
            }
        }
        // 既存のマスと id が重なったものは振り直す
        self = validated()
        return result
    }
}

// MARK: - 内部

extension NonetConfiguration {
    /// bundleID は大文字と小文字を区別しない（Launch Services と同じ）
    static func bundleIDKey(_ bundleID: String) -> String {
        bundleID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func profileIndex(id: UUID) -> Int? {
        profiles.firstIndex { $0.id == id }
    }

    /// 有効・無効にかかわらず、そのアプリのプロファイルの位置
    func appProfileIndex(forBundleID bundleID: String) -> Int? {
        let key = Self.bundleIDKey(bundleID)
        return profiles.firstIndex { profile in
            profile.app.map { Self.bundleIDKey($0.bundleID) == key } == true
        }
    }

    static func contains(_ address: CellAddress, in profile: Profile) -> Bool {
        profile.pages.indices.contains(address.page)
            && profile.pages[address.page].cells.indices.contains(address.index)
    }

    private func containsCell(id: UUID, except excluded: (profile: Int, address: CellAddress)) -> Bool {
        for (profileIndex, profile) in profiles.enumerated() {
            for (pageIndex, page) in profile.pages.enumerated() {
                for (slot, cell) in page.cells.enumerated() where cell?.id == id {
                    let isExcluded = profileIndex == excluded.profile
                        && pageIndex == excluded.address.page
                        && slot == excluded.address.index
                    if !isExcluded { return true }
                }
            }
        }
        return false
    }

    private static func resolve(_ profile: Profile) -> [ResolvedPage] {
        var profile = profile
        profile.normalizePages()
        let name = profile.name
        return profile.pages.enumerated().map { pageIndex, page in
            ResolvedPage(profileID: profile.id, profileName: name, pageIndex: pageIndex, cells: page.cells)
        }
    }

    private static func uniqueID(avoiding used: Set<UUID>) -> UUID {
        var id = UUID()
        while used.contains(id) {
            id = UUID()
        }
        return id
    }
}

// MARK: - Codable

extension NonetConfiguration {
    private enum CodingKeys: String, CodingKey {
        case version, settings, profiles
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // 版の書かれていないファイルは最初の版とみなす
        let version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        let settings = container.decodeLossy(GlobalSettings.self, forKey: .settings, default: GlobalSettings())
        // profiles が配列でなければ全体を読めないことにする（黙ってすべてのプロファイルを失うより、壊れたファイルとして退避する）。
        // 読めないプロファイルだけは外す
        let profiles = try container.decodeIfPresent([LossyElement<Profile>].self, forKey: .profiles) ?? []
        self.init(version: version, settings: settings, profiles: profiles.compactMap(\.value))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(settings, forKey: .settings)
        try container.encode(profiles, forKey: .profiles)
    }
}
