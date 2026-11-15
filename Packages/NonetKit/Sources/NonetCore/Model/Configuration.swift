// 担当: core-model（公開 API は契約）
import Foundation

/// 保存される設定のすべて
public struct NonetConfiguration: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var settings: GlobalSettings
    /// 先頭は必ずグローバルのプロファイル。アプリのプロファイルは bundleID ごとに1つまで
    public var profiles: [Profile]

    public init(
        version: Int = NonetConfiguration.currentVersion,
        settings: GlobalSettings = GlobalSettings(),
        profiles: [Profile]
    ) {
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
    /// ページの名前（Page.name）。無ければ nil
    public var pageName: String?

    public init(profileID: UUID, profileName: String, pageIndex: Int, cells: [Cell?], pageName: String? = nil) {
        self.profileID = profileID
        self.profileName = profileName
        self.pageIndex = pageIndex
        self.cells = cells
        self.pageName = pageName
    }

    /// HUD の題名。ページに名前があれば「Xcode · デバッグ」、無ければプロファイルの名前だけ
    public var title: String {
        guard let name = Page.normalizedName(pageName) else { return profileName }
        return "\(profileName) · \(name)"
    }
}

extension NonetConfiguration {
    /// 初回起動時の設定。グローバルは Dock のアプリ（Dock の順）とインストール済みの候補を並べたランチャー、
    /// アプリのプロファイルは渡されたプリセットから作る
    public static func initial(
        appPresets: [AppPreset],
        installedBundleIDs: Set<String>,
        dockApps: [AppReference] = []
    ) -> NonetConfiguration {
        // グローバルの最初のページは「画面に置く」。ランチャーはその後ろ（ページ数の上限に収める）
        var global = PresetLibrary.makeGlobalProfile(installedBundleIDs: installedBundleIDs, dockApps: dockApps)
        var pages = Array(global.pages.prefix(Profile.maxPages - 1))
        if pages.count == 1, pages[0].cells.allSatisfy({ $0 == nil }) {
            pages = []
        }
        global.pages = [PresetLibrary.makeWindowPlacementPage()] + pages
        return initial(appPresets: appPresets, globalProfile: global)
    }

    static func initial(appPresets: [AppPreset], globalProfile: Profile) -> NonetConfiguration {
        let global = Profile(id: globalProfile.id, kind: .global, pages: globalProfile.pages)
        var configuration = NonetConfiguration(settings: GlobalSettings(), profiles: [global])
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

    /// 有効な（mode が .profile の）アプリのプロファイル
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
        if let id = cell?.id, containsCell(id: id, except: .profile(index, address)) {
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

    /// 消したページを pageIndex に戻す（元に戻す）。ページが上限なら何もしないで false
    @discardableResult
    public mutating func insertPage(_ page: Page, at pageIndex: Int, profileID: UUID) -> Bool {
        guard let index = profileIndex(id: profileID), profiles[index].pages.count < Profile.maxPages else { return false }
        profiles[index].normalizePages()
        let position = min(max(pageIndex, 0), profiles[index].pages.count)
        profiles[index].pages.insert(Page(cells: page.cells, name: page.name), at: position)
        // ほかで同じ id のマスが作られていれば振り直す
        self = validated()
        return true
    }

    /// ページの名前を変える。空や nil なら名前を外す（Page.normalizedName(_:) で揃える）
    public mutating func renamePage(at pageIndex: Int, profileID: UUID, to name: String?) {
        guard let index = profileIndex(id: profileID), profiles[index].pages.indices.contains(pageIndex) else { return }
        profiles[index].pages[pageIndex].name = Page.normalizedName(name)
    }

    // MARK: - アプリごとの使い方（ProfileMode）

    /// そのアプリのプロファイルの使い方。プロファイルが無ければ nil（グローバルを使う）
    public func appMode(forBundleID bundleID: String) -> ProfileMode? {
        appProfileIndex(forBundleID: bundleID).map { profiles[$0].mode }
    }

    /// このアプリでは Nonet を使わない（そのアプリのプロファイルが ProfileMode.off）。bundleID が nil や空なら false。
    public func isTurnedOff(forBundleID bundleID: String?) -> Bool {
        guard let bundleID, !Self.bundleIDKey(bundleID).isEmpty else { return false }
        return appMode(forBundleID: bundleID) == .off
    }

    /// アプリの使い方を変える。プロファイルが無ければ作る（preset があればその中身で。後で「このプロファイル」に戻したときに使える）。
    /// プロファイルの id を返す。bundleID が空なら何もしないで nil
    @discardableResult
    public mutating func setAppMode(_ mode: ProfileMode, for app: AppReference, preset: AppPreset? = nil) -> UUID? {
        guard !Self.bundleIDKey(app.bundleID).isEmpty else { return nil }
        let id = addAppProfile(for: app, preset: preset)
        updateProfile(id: id) { $0.mode = mode }
        return id
    }

    // MARK: - 複製・プリセット・元に戻す

    /// プロファイルのページ（名前を含む）を写した、別のアプリのプロファイルを後ろに作る。マスの id は新しくする。
    /// 元のアプリのメニュー項目を押すマスは、新しいアプリのメニューを押すようにする（VS Code → Cursor のように、同じメニューのアプリへ写すため）。
    /// 元が無い・app のプロファイルがすでにある・bundleID が空なら何もしないで nil
    @discardableResult
    public mutating func duplicateProfile(id: UUID, for app: AppReference) -> UUID? {
        guard let source = profile(id: id),
              !Self.bundleIDKey(app.bundleID).isEmpty,
              appProfileIndex(forBundleID: app.bundleID) == nil else { return nil }
        let sourceKey = source.app.map { Self.bundleIDKey($0.bundleID) }
        var copy = Profile(kind: .app(app), pages: source.pages, mode: .profile)
        copy.normalizePages()
        for page in copy.pages.indices {
            copy.pages[page].cells = copy.pages[page].cells.map { cell in
                cell.map { cell in
                    var cell = cell
                    cell.id = UUID()
                    if case .menuItem(var menu) = cell.action, let target = menu.app,
                       let sourceKey, Self.bundleIDKey(target.bundleID) == sourceKey {
                        menu.app = app
                        cell.action = .menuItem(menu)
                    }
                    return cell
                }
            }
        }
        profiles.append(copy)
        self = validated()
        return copy.id
    }

    /// プロファイルのページをプリセットの中身に戻す（ページの名前もプリセットのものにする）。id と使い方（mode）は変えない
    public mutating func resetProfile(id: UUID, to preset: AppPreset) {
        updateProfile(id: id) { profile in
            // makeProfile() はマスの id を振り直すので、ほかのプロファイルと重ならない
            profile.pages = preset.makeProfile().pages
        }
    }

    /// 消したアプリのプロファイルを、アプリのプロファイルの並びの position に戻す（元に戻す）。
    /// 同じアプリのプロファイルか同じ id のプロファイルがすでにある・グローバルなら、何もしないで false
    @discardableResult
    public mutating func restoreAppProfile(_ profile: Profile, at position: Int) -> Bool {
        guard let app = profile.app, !Self.bundleIDKey(app.bundleID).isEmpty,
              appProfileIndex(forBundleID: app.bundleID) == nil,
              profileIndex(id: profile.id) == nil else { return false }
        var apps = profiles.filter { !$0.isGlobal }
        apps.insert(profile, at: min(max(position, 0), apps.count))
        profiles = profiles.filter(\.isGlobal) + apps
        self = validated()
        return true
    }

    /// 前面アプリで使うページの並び。
    /// アプリのプロファイルがあればそのページ、その後ろにグローバルのページ。無ければグローバルのページだけ。使い方が global・off のプロファイルは使わない
    /// （off のアプリでは NonetController がセッションを始めないので、ここは呼ばれない）。
    /// マスが1つも無いアプリのプロファイル（「◯◯ のマスを作る…」で作ったばかり など）も無いものとし、グローバルのページを先に出す
    /// （空きマスだけのページが先に開いて、グローバルのマスが隠れないように）
    public func resolvedPages(frontmostBundleID: String?) -> [ResolvedPage] {
        let globalPages = Self.resolve(globalProfile)
        guard let bundleID = frontmostBundleID,
              let appProfile = appProfile(forBundleID: bundleID),
              appProfile.hasButtons else {
            return globalPages
        }
        return Self.resolve(appProfile) + globalPages
    }

    /// 壊れた設定を直したもの（グローバルが先頭に1つ、ページ数、マス数、重複 id など）
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
                // グローバルは無効にも「使わない」にもできない（アプリのプロファイルが無いときに使うページが無くなる）
                profile.mode = .profile
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
        return NonetConfiguration(
            version: Self.currentVersion,
            settings: settings,
            profiles: [globalProfile] + apps
        )
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
        /// 同じアプリの重複・bundleID の無いアプリ・読めなかったプロファイルなどで使わなかった数
        public var skipped: Int
        /// 読み込んだが、この版では読めない中身を落とした（知らない種類のマスを空きマスにした など）プロファイルの数
        public var incomplete: Int

        public init(added: Int = 0, replaced: Int = 0, replacedGlobal: Bool = false, skipped: Int = 0, incomplete: Int = 0) {
            self.added = added
            self.replaced = replaced
            self.replacedGlobal = replacedGlobal
            self.skipped = skipped
            self.incomplete = incomplete
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
        var applied = Set<Int>()
        return importProfiles(imported, applied: &applied)
    }

    /// applied に、反映したもの（imported での位置）を入れる
    mutating func importProfiles(_ imported: [Profile], applied: inout Set<Int>) -> ImportResult {
        var result = ImportResult()
        var seenBundleIDs = Set<String>()
        var importedGlobal = false

        for (position, original) in imported.enumerated() {
            var profile = original
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
                applied.insert(position)
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
                    applied.insert(position)
                } else {
                    if profiles.contains(where: { $0.id == profile.id }) {
                        profile.id = UUID()
                    }
                    profiles.append(profile)
                    result.added += 1
                    applied.insert(position)
                }
            }
        }
        // 既存のマスと id が重なったものは振り直す
        self = validated()
        return result
    }

    /// 書き出しファイルから読めたものを加える（ConfigurationStore.importDocument(from:) の結果）。
    /// 読めなかったプロファイルも skipped に数える
    @discardableResult
    public mutating func importProfiles(_ document: ConfigurationStore.ImportedProfiles) -> ImportResult {
        var applied = Set<Int>()
        var result = importProfiles(document.profiles, applied: &applied)
        result.skipped += max(document.unreadableCount, 0)
        // 中身を落としたもののうち、反映したものだけを数える（重なって使わなかったもの・新しいものだけ加えたときの既存のものは数えない）
        result.incomplete = applied.intersection(document.incompleteIndices).count
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

    /// containsCell(id:except:) で数えない場所（マスを置こうとしている場所）
    private enum CellSlot {
        case profile(Int, CellAddress)
    }

    private func containsCell(id: UUID, except excluded: CellSlot) -> Bool {
        for (profileIndex, profile) in profiles.enumerated() {
            for (pageIndex, page) in profile.pages.enumerated() {
                for (slot, cell) in page.cells.enumerated() where cell?.id == id {
                    if case .profile(let excludedProfile, let address) = excluded,
                       excludedProfile == profileIndex, address.page == pageIndex, address.index == slot {
                        continue
                    }
                    return true
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
            ResolvedPage(profileID: profile.id, profileName: name, pageIndex: pageIndex, cells: page.cells, pageName: page.name)
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
        // profiles が配列でなければ（null も）全体を読めないことにする（黙ってすべてのプロファイルを失うより、壊れたファイルとして退避する）。
        // decodeIfPresent は null を「無い」とみなすので使わない。読めないプロファイルだけは外す
        let profiles = container.contains(.profiles)
            ? try container.decode([LossyElement<Profile>].self, forKey: .profiles)
            : []
        // 前の版の共通マス（sharedCells）は読まない（原本は configuration.lossy-… に残る）
        self.init(version: version, settings: settings, profiles: profiles.compactMap(\.value))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(settings, forKey: .settings)
        try container.encode(profiles, forKey: .profiles)
    }
}
