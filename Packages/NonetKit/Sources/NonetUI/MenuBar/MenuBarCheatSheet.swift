// 担当: ui-shell
// メニューの先頭の早見表（前面のアプリで9マスを開いたときに出るマス）の中身と寸法。AppKit に触れない
import CoreGraphics
import Foundation
import NonetCore

/// 早見表で押したマスの場所。設定の「プロファイル」でそのプロファイルのページとマスを選ぶ
struct MenuBarCellLocation: Equatable, Sendable {
    var profileID: UUID
    /// プロファイル内での位置
    var address: CellAddress
}

/// メニューの先頭の早見表。NonetController が9マスを開いたときと同じ決め方（NonetConfiguration.resolvedPages）で、
/// 前面のアプリのページを並べる。HUD と同じく最初のページから見せ、‹ › でほかのページも見られる
struct MenuBarCheatSheet: Equatable {
    /// 前面のアプリで使うページ（resolvedPages の並び）。アプリのページの後ろにグローバルのページが続くこともある
    var pages: [ResolvedPage]
    var globalProfileID: UUID
    /// 前面のアプリで Nonet を使わない設定にしているなら、そのアプリの名前。マスの代わりに短い1行を出す
    var turnedOffAppName: String?
    /// 見ているページ（pages での位置）
    private(set) var pageIndex = 0

    init(pages: [ResolvedPage], globalProfileID: UUID, turnedOffAppName: String? = nil) {
        self.pages = pages
        self.globalProfileID = globalProfileID
        self.turnedOffAppName = turnedOffAppName
    }

    /// frontApp は Nonet を数えない前面のアプリ（分からなければ nil でグローバル）。
    /// 「このアプリでは使わない」アプリでは9マスが開かないので、マスの代わりにそう言う
    init(frontApp: AppReference?, configuration: NonetConfiguration) {
        let globalID = configuration.globalProfile.id
        if let frontApp, configuration.isTurnedOff(forBundleID: frontApp.bundleID) {
            let name = OnboardingModel.profile(forBundleID: frontApp.bundleID, in: configuration.profiles)?.name
                ?? MenuBarEditTarget.displayName(frontApp)
            self.init(pages: [], globalProfileID: globalID, turnedOffAppName: name)
            return
        }
        self.init(pages: configuration.resolvedPages(frontmostBundleID: frontApp?.bundleID), globalProfileID: globalID)
    }

    // MARK: - 文言

    /// マスの代わりに出す1行（「このアプリでは使わない」のとき）。それ以外は nil
    var turnedOffText: String? {
        turnedOffAppName.map { String(localized: "\($0) では Nonet を使いません", bundle: .module) }
    }

    /// 見出し。「Xcode のマス」「グローバルのマス」。ページに名前があれば「Xcode のマス · デバッグ」
    var title: String {
        guard let page = currentPage else { return String(localized: "グローバルのマス", bundle: .module) }
        let base = page.profileID == globalProfileID
            ? String(localized: "グローバルのマス", bundle: .module)
            : String(localized: "\(page.profileName) のマス", bundle: .module)
        guard let name = Page.normalizedName(page.pageName) else { return base }
        // 区切りの「 · 」は言語によらない（HUD の題名と同じ）
        return "\(base) · \(name)"
    }

    /// 「3 ページ中 1 ページ目」（HUD のページの点と同じ文）
    var pageDescription: String {
        HUDAnnouncement.pageDescription(pageIndex: pageIndex, pageCount: max(pageCount, 1))
    }

    /// 早見表のまとまりの VoiceOver の名前。ページが複数なら何ページ目かも言う
    var accessibilityLabel: String {
        pageCount > 1 ? String(localized: "\(title)、\(pageDescription)", bundle: .module) : title
    }

    /// マスの名前（表示名が空ならアクションの説明。設定のグリッドと同じ）。空きマスは nil
    func cellTitle(at index: Int) -> String? {
        cell(at: index).map(SettingsGrid.displayTitle(for:))
    }

    /// マスにポインタを重ねたときのヘルプ。押すと実行ではなく、設定で開くことを伝える
    func cellTooltip(at index: Int) -> String {
        guard let title = cellTitle(at: index) else {
            return String(localized: "空きマスです。クリックすると、設定でアクションを入れられます", bundle: .module)
        }
        return String(localized: "クリックすると、設定で「\(title)」を開いて編集します。⌥クリックで、前面のアプリに向けて実行します", bundle: .module)
    }

    /// マスの VoiceOver の名前。位置とマスの名前（設定のグリッドと同じ読み方）
    func accessibilityLabel(ofCell index: Int) -> String {
        SettingsGrid.accessibilityLabel(index: index, cell: cell(at: index))
    }

    /// マスの VoiceOver のヒント
    static var cellHint: String {
        String(localized: "設定で開きます。操作の一覧の「前面のアプリで実行」で実行できます", bundle: .module)
    }

    /// 空きマスの VoiceOver のヒント
    static var emptyCellHint: String {
        String(localized: "設定で開きます", bundle: .module)
    }

    /// マスの VoiceOver の操作（⌥クリックと同じ）
    static var runActionName: String {
        String(localized: "前面のアプリで実行", bundle: .module)
    }

    static var previousPageTitle: String {
        String(localized: "前のページ", bundle: .module)
    }

    static var nextPageTitle: String {
        String(localized: "次のページ", bundle: .module)
    }

    // MARK: - ページ

    var pageCount: Int { pages.count }

    var currentPage: ResolvedPage? {
        pages.indices.contains(pageIndex) ? pages[pageIndex] : nil
    }

    var canShowPreviousPage: Bool { pageIndex > 0 }
    var canShowNextPage: Bool { pageIndex + 1 < pageCount }

    /// 範囲外は端に寄せる
    mutating func showPage(_ index: Int) {
        pageIndex = pages.isEmpty ? 0 : min(max(index, 0), pages.count - 1)
    }

    mutating func showPreviousPage() { showPage(pageIndex - 1) }
    mutating func showNextPage() { showPage(pageIndex + 1) }

    /// アプリのページの後ろにつなげたグローバルのページの、最初の位置（ページの点をそこで少し離す。HUD と同じ）
    var globalPagesStart: Int? {
        guard let first = pages.first else { return nil }
        return pages.firstIndex { $0.profileID != first.profileID }
    }

    // MARK: - マス

    /// 見ているページの index 番目のマス。空きマスと範囲外は nil
    func cell(at index: Int) -> Cell? {
        guard let page = currentPage, page.cells.indices.contains(index) else { return nil }
        return page.cells[index]
    }

    /// 見ているページの index 番目のマス（空きマスも）を設定で開くときの場所。ページが無い・範囲外なら nil
    func location(ofCell index: Int) -> MenuBarCellLocation? {
        guard let page = currentPage, (0..<Page.cellCount).contains(index) else { return nil }
        return MenuBarCellLocation(profileID: page.profileID, address: CellAddress(page: page.pageIndex, index: index))
    }

    /// キーボードで早見表の行を選んで Return を押したときに開く場所（見ているページの最初のマス）
    var pageLocation: MenuBarCellLocation? {
        location(ofCell: 0)
    }
}

/// 早見表の寸法。メニューに収まる大きさで、HUD のマスの並び（3×3、角の丸いマス、点線の空きマス）に合わせる。
/// 座標は左上が原点（ビューは isFlipped）
struct MenuBarCheatSheetLayout: Equatable {
    /// 画面が低いときは、マスを低くしてメニューの下の項目（設定・ライセンス・終了）を押し出さない
    enum Density: Equatable, Sendable {
        /// アイコンの下に名前（HUD と同じ並び）
        case regular
        /// アイコンの右に名前
        case compact
    }

    /// 知らせの行（MenuBarNoticeView）と同じ幅。メニューがもっと広ければ、マスを広げて合わせる
    static let preferredWidth: CGFloat = 280
    /// 見える部分の高さがこれより低い画面では compact にする（1280×800 の画面はまだ regular）
    static let compactScreenHeight: CGFloat = 700

    static let horizontalInset: CGFloat = 14
    static let topInset: CGFloat = 3
    static let headerHeight: CGFloat = 20
    static let headerGap: CGFloat = 3
    static let cellSpacing: CGFloat = 4
    /// キーボードで選んだときの枠（グリッドの 3pt 外）が切れない余白
    static let bottomInset: CGFloat = 7
    static let cellCornerRadius: CGFloat = 7
    /// ‹ › の押せる大きさ
    static let pageButtonSize: CGFloat = 18
    /// ‹ › と点の間（‹ › に乗ったときの丸が点に触れない）
    static let pageControlGap: CGFloat = 4
    /// 見出しとページの操作の間
    static let titleGap: CGFloat = 6
    /// ページの点の寸法（HUD の点の 0.75 倍）
    static let dotMetrics = HUDMetrics(scale: 0.75)

    var width: CGFloat
    var density: Density
    var pageCount: Int
    var globalPagesStart: Int?

    init(width: CGFloat = Self.preferredWidth, density: Density = .regular, pageCount: Int = 1, globalPagesStart: Int? = nil) {
        self.width = max(width, Self.preferredWidth)
        self.density = density
        self.pageCount = max(pageCount, 1)
        self.globalPagesStart = globalPagesStart
    }

    init(sheet: MenuBarCheatSheet, width: CGFloat = Self.preferredWidth, density: Density) {
        self.init(width: width, density: density, pageCount: sheet.pageCount, globalPagesStart: sheet.globalPagesStart)
    }

    static func density(forVisibleScreenHeight height: CGFloat?) -> Density {
        guard let height, height > 0 else { return .regular }
        return height < compactScreenHeight ? .compact : .regular
    }

    var cellHeight: CGFloat {
        switch density {
        case .regular: 40
        case .compact: 26
        }
    }

    var height: CGFloat {
        Self.topInset + Self.headerHeight + Self.headerGap + gridFrame.height + Self.bottomInset
    }

    var size: CGSize { CGSize(width: width, height: height) }

    var gridFrame: CGRect {
        CGRect(
            x: Self.horizontalInset,
            y: Self.topInset + Self.headerHeight + Self.headerGap,
            width: width - Self.horizontalInset * 2,
            height: cellHeight * 3 + Self.cellSpacing * 2
        )
    }

    /// index 番目のマス（左上から右へ、上の行から）
    func cellFrame(_ index: Int) -> CGRect {
        let grid = gridFrame
        let cellWidth = (grid.width - Self.cellSpacing * 2) / 3
        let row = CGFloat(index / 3)
        let column = CGFloat(index % 3)
        return CGRect(
            x: grid.minX + column * (cellWidth + Self.cellSpacing),
            y: grid.minY + row * (cellHeight + Self.cellSpacing),
            width: cellWidth,
            height: cellHeight
        )
    }

    private var headerY: CGFloat { Self.topInset }

    /// ページが1枚なら ‹ › と点は出さない
    var hasPageControls: Bool { pageCount > 1 }

    /// 点の幅（HUD と同じく、グローバルの最初のページの前を少し空ける）
    var dotsWidth: CGFloat {
        dotOffsets.last.map { $0 + Self.dotMetrics.dotSize } ?? 0
    }

    /// 点の左端の位置（dotsFrame の左端から）
    var dotOffsets: [CGFloat] {
        var x: CGFloat = 0
        return (0..<pageCount).map { page in
            x += HUDPageDots.leadingSpace(before: page, globalPagesStart: globalPagesStart, metrics: Self.dotMetrics)
            defer { x += Self.dotMetrics.dotSize }
            return x
        }
    }

    var nextButtonFrame: CGRect? {
        guard hasPageControls else { return nil }
        return CGRect(
            x: gridFrame.maxX - Self.pageButtonSize,
            y: headerY + (Self.headerHeight - Self.pageButtonSize) / 2,
            width: Self.pageButtonSize,
            height: Self.pageButtonSize
        )
    }

    var dotsFrame: CGRect? {
        guard let next = nextButtonFrame else { return nil }
        return CGRect(x: next.minX - Self.pageControlGap - dotsWidth, y: headerY, width: dotsWidth, height: Self.headerHeight)
    }

    var previousButtonFrame: CGRect? {
        guard let dots = dotsFrame else { return nil }
        return CGRect(
            x: dots.minX - Self.pageControlGap - Self.pageButtonSize,
            y: headerY + (Self.headerHeight - Self.pageButtonSize) / 2,
            width: Self.pageButtonSize,
            height: Self.pageButtonSize
        )
    }

    /// 見出しの場所。ページの操作があれば、その左まで
    var titleFrame: CGRect {
        let maxX = previousButtonFrame.map { $0.minX - Self.titleGap } ?? gridFrame.maxX
        return CGRect(x: Self.horizontalInset, y: headerY, width: max(maxX - Self.horizontalInset, 0), height: Self.headerHeight)
    }
}

// MARK: - 設定で開く

extension SettingsWindowController {
    /// メニューの早見表で押したマス。設定の「プロファイル」でそのプロファイルのページとマスを選んで開く。
    /// プロファイルがもう無ければ、プロファイルのタブを開くだけ
    public func showCell(profileID: UUID, address: CellAddress) {
        _ = loadWindow()
        selectCell(profileID: profileID, address: address)
        show(tab: .profiles)
    }

    /// showCell の、ウィンドウを出さない部分（テストする）
    func selectCell(profileID: UUID, address: CellAddress) {
        select(.profiles)
        guard let profile = model.configuration.profile(id: profileID) else { return }
        model.showProfile(id: profile.id, at: profile.pages.indices.contains(address.page) ? address : nil)
    }
}
