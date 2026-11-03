// 担当: ui-settings
// 設定ウィンドウの状態と操作。設定の変更はすべて NonetController.update を通す（その場で保存・反映される）
import AppKit
import NonetCore
import Observation

/// 画面に一時的に出す知らせ（読み込みの結果・ライセンスの登録など）
struct SettingsMessage: Equatable {
    var text: String
    var isError: Bool
}

/// 元に戻すときに覚えておく、マスの場所と中身
struct SettingsCellSnapshot: Equatable {
    var address: CellAddress
    var cell: Cell?
}

/// グリッドの下に出す「元に戻す」の知らせ（マスを空にした・置き換えたとき）。
/// 編集メニューが無くても、ここから戻せるようにする
struct SettingsUndoNotice: Equatable {
    var text: String
    /// 戻す操作の名前。いちばん上の取り消しがこれのときだけ戻す
    var actionName: String
}

/// 元に戻す操作の受け手。プロファイルごとに分け、読み込みでプロファイルを置き換えたときにそのプロファイルの分だけ忘れる
final class SettingsUndoTarget {}

/// インスペクタでの変更を、マスごとに1つの取り消しにまとめたもの。after は変えるたびに新しくする
final class SettingsCellEditGroup {
    let cellID: UUID
    let profileID: UUID
    let before: SettingsCellSnapshot
    var after: SettingsCellSnapshot
    /// undoManager に登録した（文字の欄を打っている間は、打ち終わるまで登録を待つ）
    var isRegistered = false

    init(cellID: UUID, profileID: UUID, before: SettingsCellSnapshot, after: SettingsCellSnapshot) {
        self.cellID = cellID
        self.profileID = profileID
        self.before = before
        self.after = after
    }
}

/// 書き出し・読み込みのファイルを選ぶ（テストでは偽物にする）
@MainActor
protocol SettingsFileChoosing: AnyObject {
    func chooseExportDestination(suggestedName: String) async -> URL?
    func chooseImportSource() async -> URL?
    /// 一覧に無いアプリを選ぶ
    func chooseApplication() async -> URL?
}

@MainActor
@Observable
final class SettingsModel {
    enum RightPanel: Equatable {
        case inspector
        /// メニューから割り当て
        case menus
    }

    /// 確かめてから行う操作
    enum Confirmation: Identifiable, Equatable {
        case deleteProfile(id: UUID, name: String)
        case removePage(profileID: UUID, index: Int)
        case deactivateLicense
        /// 読み込むと今のプロファイルやグローバルのページが置き換わるか、何かを実行するマス（スクリプト・キー入力・メニュー項目・AI・ファイルを開く URL）を含む
        case importProfiles(SettingsImportPlan)
        /// プロファイルの中身をプリセットに戻す
        case resetProfile(id: UUID, name: String)
        /// Finder で今選んでいるファイルを変える操作（ゴミ箱に入れる・名前の変更・複製・移動）のテスト実行。設定の画面からは、何を選んでいるかが見えない
        case testRunFile(cellID: UUID, operation: String)

        var id: String {
            switch self {
            case .deleteProfile(let id, _): "profile-\(id)"
            case .removePage(let id, let index): "page-\(id)-\(index)"
            case .deactivateLicense: "license"
            case .importProfiles(let plan): "import-\(plan.id)"
            case .resetProfile(let id, _): "reset-\(id)"
            case .testRunFile(let id, _): "test-\(id)"
            }
        }
    }

    /// 「このマスをテスト実行」の結果。record が nil の間は実行中
    struct TestRun: Equatable {
        var cellID: UUID
        var record: ExecutionRecord?
    }

    @ObservationIgnored let controller: NonetController
    @ObservationIgnored let license: LicenseManager
    @ObservationIgnored let services: NonetServices
    let links: AppLinks
    @ObservationIgnored let onCheckForUpdates: (() -> Void)?
    @ObservationIgnored weak var files: (any SettingsFileChoosing)?
    @ObservationIgnored var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }

    /// 変えるときは selectTab(_:)（打ちかけの確定とキーの記録の終わりをそこで行う）
    private(set) var tab: SettingsTab = .profiles
    /// タブが変わったとき（ウィンドウの題名とツールバーの選択を合わせる。SettingsWindowController が入れる）
    @ObservationIgnored var onTabChange: ((SettingsTab) -> Void)?

    // MARK: プロファイルの選択
    private(set) var selectedProfileID: UUID?
    private(set) var selectedPage = 0
    private(set) var selectedIndex: Int? = 0
    var rightPanel: RightPanel = .inspector
    /// プロファイルを追加するシート。閉じたら複製の元も忘れる
    var isAddingProfile = false {
        didSet {
            if !isAddingProfile { duplicatingProfileID = nil }
        }
    }
    /// プロファイルを追加するシートで、このプロファイルのページを写す（「複製して別のアプリに使う…」）。nil なら普通の追加
    var duplicatingProfileID: UUID?
    /// 名前を変えているページ（ページの見出しのダブルクリック）
    var renamingPage: Int?
    var confirmation: Confirmation?
    /// 読み込む前の確認で、マスの中身の欄を最後までスクロールして見た。見るまでは読み込めない（canConfirmImport）。確認を出すたびに false に戻す
    private(set) var importReviewReachedEnd = false
    /// 読み込むキー入力が、今のキー配列で Return と同じ働きをするかを調べる（テストでは偽物）
    @ObservationIgnored var keyCharacters: any SettingsKeyCharacterTranslating = SettingsLayoutKeyTranslator()
    private(set) var lastTestRun: TestRun?
    /// グリッドの下に出す短い知らせ（「空いているマスがありません」など）
    var gridMessage: String?
    /// 書き出し・読み込みの結果
    var fileMessage: SettingsMessage?

    // MARK: 絞り込みとキーボード
    /// プロファイルの一覧の絞り込み（プロファイルの名前と、どのプロファイルのボタンの名前・キーでも）
    var profileQuery = ""
    /// ⌘F で絞り込みの欄を出した（アプリのプロファイルが少なくても出す）
    var isFilterRequested = false
    /// 絞り込みの欄に移るたびに増やす（⌘F）
    var filterFocusRequest = 0
    /// 表示名の欄に移るたびに増やす（グリッドで Return）
    var nameFieldFocusRequest = 0

    // MARK: 以前の設定に戻す
    var isShowingBackups = false
    /// 「以前の設定に戻す」の一覧（シートを開いたときに読む）
    var backupEntries: [SettingsBackupEntry] = []
    @ObservationIgnored private var explicitBackupStore: ConfigurationStore?
    /// 「プリセットに戻す」で使う、claude を調べ終えた後のこの Mac でできること（確かめるシートを出したときに調べ始める）。
    /// 調べ終える前は presetEnvironment.capabilities（今わかっている分）を使う
    @ObservationIgnored var resolvedPresetCapabilities: PresetCapabilities?
    @ObservationIgnored var presetCapabilitiesTask: Task<Void, Never>?

    // MARK: キーの記録
    private(set) var recorder = SettingsKeyRecorder()
    private(set) var recordingCellID: UUID?
    @ObservationIgnored private let keyMonitor = SettingsKeyEventMonitor()

    // MARK: 元に戻す
    /// マスを空にする・入れ替える・作る・メニュー項目を割り当てるなどを元に戻す（設定ウィンドウの undoManager。⌘Z）
    @ObservationIgnored let undoManager = UndoManager()
    /// 元に戻す操作の受け手（プロファイルの id ごと）。undoManager は受け手を強く持たないので、ここで持っておく
    @ObservationIgnored private var undoTargets: [UUID: SettingsUndoTarget] = [:]
    /// グリッドの下の「元に戻す」。マスを空にしたとき・中身のあるマスを置き換えたとき・プロファイルやページを消したときなどに出す
    var undoNotice: SettingsUndoNotice?
    /// インスペクタでの変更のまとまり（選んでいるマスを変えている間）。別のマスを選ぶ・ほかの操作を元に戻せるようにする・元に戻すと閉じる
    @ObservationIgnored var editGroup: SettingsCellEditGroup?
    /// 文字の欄を打っている最中か。打っている間の変更は、打ち終わってから1つの取り消しにする
    /// （欄の打ち込みの取り消しより上に積むと、⌘Z で欄の中身だけ先に戻り、欄の取り消しが食い違う）
    @ObservationIgnored var isEditingText: () -> Bool = {
        NSApp?.keyWindow?.firstResponder is NSText
    }
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    /// 元に戻している最中に、マスの取り消しを忘れると決めたプロファイル。戻し終えてから忘れる
    /// （最中に undoManager から消すと、名前の無い空の取り消しが残る）
    @ObservationIgnored private var profilesToForgetAfterUndo: [UUID] = []

    // MARK: 一般
    private(set) var loginItemEnabled = false
    /// ログイン時に起動を変えられなかったとき（システム設定での許可待ちを含む）の知らせ
    private(set) var loginItemError: String?
    /// loginItemError を出したときに望んでいた状態。そうなったら知らせを消す
    @ObservationIgnored private var loginItemWanted: Bool?

    // MARK: ライセンス
    var licenseKeyInput = ""
    var licenseMessage: SettingsMessage?
    /// 登録済みのときに「別のキーを登録…」で、ライセンスキーの欄を出している
    var isEnteringAnotherKey = false
    /// リンクやファイルから開いた、検証済みのキー。登録してよいか尋ねている間だけ入る（黙って登録しない）
    var pendingLicense: VerifiedLicense?
    /// ライセンスキーの欄に入力できるようにしてほしい（帯の「ライセンスキーを入力…」など。欄が受け取ったら false に戻す）
    var wantsLicenseKeyFocus = false
    /// コピーする（テストでは偽物にする）
    @ObservationIgnored var copyToPasteboard: (String) -> Void = SettingsModel.copyConcealed

    // MARK: 情報
    /// お問い合わせのメールの宛先（Info.plist の NonetSupportEmail）。nil なら「お問い合わせ…」を出さない
    var supportEmail: String?
    /// 「Nonet をアンインストール…」の確認と、その後の知らせ
    var uninstallStep: SettingsUninstallStep?
    /// ゴミ箱に入れるもの（テストでは偽物にする）
    @ObservationIgnored var uninstaller = SettingsUninstaller(trash: SettingsFileTrash(), targets: .current())
    /// アンインストールの最後に終了する（テストでは数える）
    @ObservationIgnored var terminate: () -> Void = { NSApplication.shared.terminate(nil) }

    // MARK: 状態の帯
    /// アクセシビリティの帯の「システム設定を開く」で、macOS の許可のダイアログをもう出した（このプロセスで）
    @ObservationIgnored private var hasRequestedAccessibility = false

    // MARK: 読み込みに時間のかかる一覧
    let menuBrowser: SettingsMenuBrowser
    let shortcutList: SettingsShortcutList
    private(set) var installedApps: [AppReference] = []
    @ObservationIgnored private var installedAppsLoaded = false
    /// 種類を切り替える前の中身（マスの id ごと）。戻したときに失わないように
    @ObservationIgnored private var rememberedActions: [UUID: [ActionKind: Action]] = [:]
    @ObservationIgnored private var testTask: Task<Void, Never>?
    /// 確定を待っている入力欄（種類やタブを変える前に確定させる）
    @ObservationIgnored let pendingEdits = SettingsPendingEdits()

    init(controller: NonetController, license: LicenseManager, services: NonetServices, links: AppLinks, onCheckForUpdates: (() -> Void)?) {
        self.controller = controller
        self.license = license
        self.services = services
        self.links = links
        self.onCheckForUpdates = onCheckForUpdates
        menuBrowser = SettingsMenuBrowser(menus: services.menus)
        shortcutList = SettingsShortcutList(shortcuts: services.shortcuts)
        loginItemEnabled = services.loginItem.isEnabled
        observeUndoAndTextEditing()
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// 文字の欄を打ち終えたら、待っていたインスペクタの変更を取り消しに積む。元に戻す・やり直すと、まとまりを閉じる
    private func observeUndoAndTextEditing() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSText.didEndEditingNotification, object: nil, queue: .main) { [weak self] _ in
            // 欄の確定（SwiftUI の onChange）が先に届くよう、次の回りで行う
            Task { @MainActor in self?.textEditingDidEnd() }
        })
        for name in [Notification.Name.NSUndoManagerWillUndoChange, .NSUndoManagerWillRedoChange] {
            observers.append(center.addObserver(forName: name, object: undoManager, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated { self?.undoManagerWillChange() }
            })
        }
        for name in [Notification.Name.NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange] {
            observers.append(center.addObserver(forName: name, object: undoManager, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated { self?.forgetCellUndoAfterUndoing() }
            })
        }
    }

    /// 控えの読み書き先。決めていなければ、NonetController が読み込んだ設定の場所（ConfigurationStore.lastLoadedDirectory）。
    /// どちらも無ければ控えは使わない（テストで本物の場所に書かないように）
    var backupStore: ConfigurationStore? {
        get { explicitBackupStore ?? ConfigurationStore.lastLoadedDirectory.map { ConfigurationStore(directory: $0) } }
        set { explicitBackupStore = newValue }
    }

    // MARK: - 見ているもの

    var configuration: NonetConfiguration { controller.configuration }
    var settings: GlobalSettings { configuration.settings }
    var appProfiles: [Profile] { configuration.profiles.filter { !$0.isGlobal } }

    /// 選んでいるプロファイル。消えていればグローバル
    var selectedProfile: Profile {
        selectedProfileID.flatMap(configuration.profile(id:)) ?? configuration.globalProfile
    }

    var pageIndex: Int {
        min(max(selectedPage, 0), max(selectedProfile.pages.count - 1, 0))
    }

    var currentPage: Page {
        let pages = selectedProfile.pages
        return pages.indices.contains(pageIndex) ? pages[pageIndex] : .empty
    }

    var selectedAddress: CellAddress? {
        selectedIndex.map { CellAddress(page: pageIndex, index: $0) }
    }

    /// 選んでいるマス
    var selectedCell: Cell? {
        guard let address = selectedAddress else { return nil }
        return SettingsGrid.cell(at: address, in: selectedProfile)
    }

    var canAddPage: Bool { selectedProfile.pages.count < Profile.maxPages }
    var canRemovePage: Bool { selectedProfile.pages.count > 1 }

    // MARK: - タブ

    func selectTab(_ tab: SettingsTab) {
        guard tab != self.tab else { return }
        // 記録中のまま離れると、ほかのタブで打ったキー（ライセンスキーの貼り付けなど）が記録に入ってしまう
        pendingEdits.flushAll()
        finishRecording()
        closeEditGroup()
        self.tab = tab
        undoNotice = nil
        if tab == .license {
            license.refresh()
        }
        onTabChange?(tab)
    }

    // MARK: - プロファイル

    func selectProfile(_ id: UUID?) {
        let id = id ?? configuration.globalProfile.id
        guard id != selectedProfile.id || selectedProfileID == nil else { return }
        finishRecording()
        closeEditGroup()
        selectedProfileID = id
        selectedPage = 0
        selectedIndex = 0
        gridMessage = nil
        undoNotice = nil
        renamingPage = nil
        if rightPanel == .menus {
            menuBrowser.refreshApps(preferredBundleID: selectedProfile.app?.bundleID)
        }
    }

    /// メニューバーの「◯◯のボタンを編集…」から。プロファイルのタブでそのプロファイルを選び、address があればそのページとマスを選ぶ
    func showProfile(id: UUID, at address: CellAddress?) {
        if tab != .profiles {
            selectTab(.profiles)
        }
        selectProfile(id)
        guard let address, selectedProfile.id == id, selectedProfile.pages.indices.contains(address.page) else { return }
        finishRecording()
        selectedPage = address.page
        selectedIndex = min(max(address.index, 0), Page.cellCount - 1)
        gridMessage = nil
        undoNotice = nil
    }

    /// 前面のアプリでいま使われるプロファイル（サイドバーの「使用中」）。設定のウィンドウは Nonet を数えないので、その前に使っていたアプリ。
    /// 前面のアプリが変わったら描き直すよう、activeProfileName を読んでおく
    var inUseProfileID: UUID? {
        _ = controller.activeProfileName
        return configuration.resolvedPages(frontmostBundleID: services.frontmostApp.current?.app.bundleID).first?.profileID
    }

    /// プロファイルを追加するシートでアプリを選んだ。「複製して別のアプリに使う…」から開いたときは、元のプロファイルを写す
    func addProfile(for app: AppReference) {
        if let source = duplicatingProfileID {
            isAddingProfile = false
            duplicateProfile(source, for: app)
            return
        }
        var added: UUID?
        let preset = PresetLibrary.preset(forBundleID: app.bundleID, capabilities: services.presetEnvironment.capabilities)
        controller.update { added = $0.addAppProfile(for: app, preset: preset) }
        isAddingProfile = false
        if let added {
            selectProfile(added)
        }
    }

    func requestDeleteProfile(_ id: UUID) {
        guard let profile = configuration.profile(id: id), !profile.isGlobal else { return }
        confirmation = .deleteProfile(id: id, name: profile.name)
    }

    /// プロファイルを消す。消す前の設定を控えに残し、元に戻せるようにする（そのプロファイルのマスの変更も、戻した後なら戻せる）
    func deleteProfile(_ id: UUID, actionName: String? = nil, makesBackup: Bool = true) {
        let before = appProfiles
        guard let position = before.firstIndex(where: { $0.id == id }) else { return }
        let removed = before[position]
        let actionName = actionName ?? String(localized: "プロファイルの削除", bundle: .module)
        pendingEdits.flushAll()
        finishRecording()
        closeEditGroup()
        if makesBackup {
            backupStore?.makeBackup(of: configuration, reason: .beforeDeletingProfile)
        }
        let wasSelected = selectedProfile.id == id
        controller.update { $0.removeProfile(id: id) }
        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: undoTarget(for: id)) { [weak self] _ in
            self?.restoreProfile(removed, at: position, actionName: actionName)
        }
        undoManager.setActionName(actionName)
        undoManager.endUndoGrouping()
        if wasSelected {
            let remaining = appProfiles
            let next = remaining.isEmpty ? nil : remaining[min(position, remaining.count - 1)]
            selectedProfileID = nil
            selectProfile(next?.id)
        }
        undoNotice = SettingsUndoNotice(
            text: String(localized: "「\(removed.name)」のプロファイルを削除しました", bundle: .module),
            actionName: actionName
        )
    }

    /// 消したプロファイルを元の位置に戻す（元に戻す）。同じアプリのプロファイルをその後に作っていれば戻さずに知らせる
    private func restoreProfile(_ profile: Profile, at position: Int, actionName: String) {
        pendingEdits.flushAll()
        finishRecording()
        undoNotice = nil
        var restored = false
        controller.update { restored = $0.restoreAppProfile(profile, at: position) }
        guard restored else {
            gridMessage = String(localized: "「\(profile.name)」のプロファイルがすでにあるため、元に戻せませんでした", bundle: .module)
            return
        }
        undoManager.registerUndo(withTarget: undoTarget(for: profile.id)) { [weak self] _ in
            self?.deleteProfile(profile.id, actionName: actionName, makesBackup: false)
        }
        undoManager.setActionName(actionName)
        if tab != .profiles {
            selectTab(.profiles)
        }
        selectProfile(profile.id)
    }

    /// 前面にあるときの使い方（このプロファイル・グローバルを使う・このアプリでは Nonet を使わない）
    func setProfileMode(_ id: UUID, _ mode: ProfileMode) {
        guard configuration.profile(id: id)?.isGlobal == false else { return }
        controller.update { $0.updateProfile(id: id) { $0.mode = mode } }
    }

    /// 選択を初めに戻す（グローバルの1ページ目の左上。以前の設定に戻したときなど）
    func resetSelection() {
        finishRecording()
        closeEditGroup()
        selectedProfileID = nil
        selectedPage = 0
        selectedIndex = 0
        gridMessage = nil
        renamingPage = nil
    }

    func moveProfiles(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        controller.update { $0.moveAppProfiles(fromOffsets: offsets, toOffset: destination) }
    }

    // MARK: - ページ

    func selectPage(_ index: Int) {
        guard selectedProfile.pages.indices.contains(index), index != pageIndex else { return }
        finishRecording()
        closeEditGroup()
        selectedPage = index
        gridMessage = nil
        undoNotice = nil
    }

    /// ページを足す。元に戻せる（戻すと足したページを消す。その下に積んだページの削除の取り消しが、上限で戻せなくならないように）
    func addPage() {
        let profileID = selectedProfile.id
        guard canAddPage else { return }
        pendingEdits.flushAll()
        finishRecording()
        closeEditGroup()
        var added: Int?
        controller.update { added = $0.addPage(profileID: profileID) }
        guard let added else { return }
        registerUndoOfAddingPage(at: added, profileID: profileID)
        selectedPage = added
        selectedIndex = 0
        gridMessage = nil
        undoNotice = nil
    }

    private func registerUndoOfAddingPage(at index: Int, profileID: UUID) {
        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: undoTarget(for: profileID)) { [weak self] _ in
            self?.removeAddedPage(at: index, profileID: profileID)
        }
        undoManager.setActionName(String(localized: "ページを追加", bundle: .module))
        undoManager.endUndoGrouping()
    }

    /// 足したページを消す（元に戻す）。その後にマスを置いていれば（取り消しに積まれない変更で）消さずに知らせる
    private func removeAddedPage(at index: Int, profileID: UUID) {
        pendingEdits.flushAll()
        finishRecording()
        undoNotice = nil
        guard let profile = configuration.profile(id: profileID), profile.pages.count > 1,
              profile.pages.indices.contains(index) else { return }
        guard profile.pages[index].cells.allSatisfy({ $0 == nil }) else {
            reveal(CellAddress(page: index, index: selectedIndex ?? 0), profileID: profileID)
            gridMessage = String(localized: "マスがその後に変わったため、元に戻せませんでした", bundle: .module)
            return
        }
        controller.update { $0.removePage(at: index, profileID: profileID) }
        // やり直すと、また同じ場所に足す
        undoManager.registerUndo(withTarget: undoTarget(for: profileID)) { [weak self] _ in
            self?.insertAddedPage(at: index, profileID: profileID)
        }
        undoManager.setActionName(String(localized: "ページを追加", bundle: .module))
        reveal(CellAddress(page: max(index - 1, 0), index: selectedIndex ?? 0), profileID: profileID)
    }

    /// 足したページをもう一度足す（やり直す）
    private func insertAddedPage(at index: Int, profileID: UUID) {
        pendingEdits.flushAll()
        finishRecording()
        undoNotice = nil
        guard let count = configuration.profile(id: profileID)?.pages.count else { return }
        let position = min(index, count)
        var inserted = false
        controller.update { inserted = $0.insertPage(.empty, at: position, profileID: profileID) }
        guard inserted else {
            gridMessage = String(localized: "ページが \(Profile.maxPages) 枚あるため、消したページを元に戻せませんでした", bundle: .module)
            return
        }
        registerUndoOfAddingPage(at: position, profileID: profileID)
        reveal(CellAddress(page: position, index: 0), profileID: profileID)
    }

    /// 空のページはすぐ消す。マスがあれば確かめる
    func requestRemovePage(_ index: Int) {
        let profile = selectedProfile
        guard profile.pages.count > 1, profile.pages.indices.contains(index) else { return }
        if profile.pages[index].cells.allSatisfy({ $0 == nil }) {
            removePage(index, profileID: profile.id)
        } else {
            confirmation = .removePage(profileID: profile.id, index: index)
        }
    }

    /// ページを消す。マスがあれば消す前の設定を控えに残す。元に戻せるようにする
    func removePage(_ index: Int, profileID: UUID, makesBackup: Bool = true) {
        guard let profile = configuration.profile(id: profileID), profile.pages.count > 1,
              profile.pages.indices.contains(index) else { return }
        let removed = profile.pages[index]
        let actionName = String(localized: "ページの削除", bundle: .module)
        pendingEdits.flushAll()
        finishRecording()
        closeEditGroup()
        if makesBackup, removed.cells.contains(where: { $0 != nil }) {
            backupStore?.makeBackup(of: configuration, reason: .beforeDeletingPage)
        }
        controller.update { $0.removePage(at: index, profileID: profileID) }
        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: undoTarget(for: profileID)) { [weak self] _ in
            self?.restorePage(removed, at: index, profileID: profileID)
        }
        undoManager.setActionName(actionName)
        undoManager.endUndoGrouping()
        renamingPage = nil
        if profileID == selectedProfile.id, selectedPage > index || selectedPage >= selectedProfile.pages.count {
            selectedPage = max(selectedPage - 1, 0)
        }
        undoNotice = SettingsUndoNotice(
            text: String(localized: "「\(SettingsText.pageTitle(index: index, name: removed.name))」を削除しました", bundle: .module),
            actionName: actionName
        )
    }

    /// 消したページを元の位置に戻す（元に戻す）。その後にページを足して上限なら戻さずに知らせる
    private func restorePage(_ page: Page, at index: Int, profileID: UUID) {
        pendingEdits.flushAll()
        finishRecording()
        undoNotice = nil
        var restored = false
        controller.update { restored = $0.insertPage(page, at: index, profileID: profileID) }
        guard restored else {
            // その下に積んだマスの取り消しは、このページがあるものとして場所を覚えている。
            // 戻すと番号のずれた別のページに入るので、このプロファイルの分は（戻し終えてから）忘れる
            if undoManager.isUndoing || undoManager.isRedoing {
                profilesToForgetAfterUndo.append(profileID)
            } else {
                discardCellUndo(forProfiles: [profileID])
            }
            gridMessage = String(localized: "ページが \(Profile.maxPages) 枚あるため、消したページを元に戻せませんでした", bundle: .module)
            return
        }
        undoManager.registerUndo(withTarget: undoTarget(for: profileID)) { [weak self] _ in
            self?.removePage(index, profileID: profileID, makesBackup: false)
        }
        undoManager.setActionName(String(localized: "ページの削除", bundle: .module))
        reveal(CellAddress(page: index, index: selectedIndex ?? 0), profileID: profileID)
    }

    // MARK: - マス

    func selectCell(_ index: Int?) {
        let index = index.map { min(max($0, 0), Page.cellCount - 1) }
        guard index != selectedIndex else { return }
        finishRecording()
        closeEditGroup()
        selectedIndex = index
        gridMessage = nil
        undoNotice = nil
    }

    func moveSelection(_ direction: SettingsGridDirection) {
        guard let current = selectedIndex else {
            selectCell(0)
            return
        }
        selectCell(SettingsGrid.neighbor(of: current, direction))
    }

    /// マスを空にする（確かめずに消すので、元に戻せるようにする）
    func clearCell(at index: Int) {
        let profileID = selectedProfile.id
        let address = CellAddress(page: pageIndex, index: index)
        guard let cell = SettingsGrid.cell(at: address, in: selectedProfile) else { return }
        if recordingCellID == cell.id {
            cancelRecording()
        }
        changeCells(
            String(localized: "マスを空にする", bundle: .module),
            notice: String(localized: "「\(SettingsGrid.displayTitle(for: cell))」を空にしました", bundle: .module),
            profileID: profileID,
            at: [address]
        ) {
            $0.setCell(nil, at: address, profileID: profileID)
        }
    }

    /// 次の空きマスに写す。空きが無ければ知らせる
    func duplicateCell(at index: Int) {
        let profile = selectedProfile
        let address = CellAddress(page: pageIndex, index: index)
        guard var copy = SettingsGrid.cell(at: address, in: profile) else { return }
        guard let target = SettingsGrid.nextEmptyAddress(after: address, in: profile) else {
            gridMessage = String(localized: "空いているマスがありません。マスを空けるか、ページを追加してください。", bundle: .module)
            return
        }
        copy.id = UUID()
        changeCells(String(localized: "複製", bundle: .module), profileID: profile.id, at: [target]) {
            $0.setCell(copy, at: target, profileID: profile.id)
        }
        finishRecording()
        selectedPage = target.page
        selectedIndex = target.index
    }

    /// 空きマスに種類を選んでマスを作る
    func createCell(kind: ActionKind, at index: Int) {
        let profileID = selectedProfile.id
        let address = CellAddress(page: pageIndex, index: index)
        guard SettingsGrid.isEmpty(address, in: selectedProfile) else { return }
        // 右クリックで作るときも、記録中のマスから離れるので記録を終える
        finishRecording()
        let cell = SettingsCellEditing.newCell(kind: kind)
        changeCells(String(localized: "アクションを追加", bundle: .module), profileID: profileID, at: [address]) {
            $0.setCell(cell, at: address, profileID: profileID)
        }
        selectedIndex = index
        gridMessage = nil
    }

    /// ドラッグで落とされたもの。受け取れたら true
    @discardableResult
    func handleDrop(_ payload: SettingsDragPayload, onto index: Int) -> Bool {
        let target = CellAddress(page: pageIndex, index: index)
        switch payload {
        case .cell(let profileID, let source) where profileID == selectedProfile.id:
            guard source != target else { return false }
            swapCells(source, target)
            return true
        case .menuItem(let id):
            guard let entry = menuBrowser.entry(id: id) else { return false }
            assignMenuItem(entry.node, to: target)
            return true
        default:
            return false
        }
    }

    /// ページの見出しに落とされたマスを、そのページの最初の空きマスへ移す。受け取れたら true
    @discardableResult
    func handleDrop(_ payload: SettingsDragPayload, ontoPage page: Int) -> Bool {
        let profile = selectedProfile
        guard case .cell(let profileID, let source) = payload, profileID == profile.id, source.page != page,
              profile.pages.indices.contains(page),
              let empty = SettingsGrid.firstEmptyIndex(in: profile.pages[page]) else { return false }
        swapCells(source, CellAddress(page: page, index: empty))
        return true
    }

    func swapCells(_ source: CellAddress, _ destination: CellAddress) {
        let profileID = selectedProfile.id
        let actionName = SettingsGrid.isEmpty(destination, in: selectedProfile)
            ? String(localized: "マスの移動", bundle: .module)
            : String(localized: "マスの入れ替え", bundle: .module)
        changeCells(actionName, profileID: profileID, at: [source, destination]) {
            $0.swapCells(source, destination, profileID: profileID)
        }
        finishRecording()
        selectedPage = destination.page
        selectedIndex = destination.index
    }

    /// メニュー項目を割り当てる。address が nil なら選んでいる空きマスか、最初の空きマス
    func assignMenuItem(_ item: MenuItemNode, to address: CellAddress? = nil) {
        let profile = selectedProfile
        guard let target = address
            ?? SettingsGrid.assignmentTarget(selected: selectedAddress, currentPage: pageIndex, in: profile) else {
            gridMessage = String(localized: "空いているマスがありません。マスを空けるか、ページを追加してください。", bundle: .module)
            return
        }
        let existing = SettingsGrid.cell(at: target, in: profile)
        if let existing, existing.id == recordingCellID {
            cancelRecording()
        }
        let cell = SettingsCellEditing.assigningMenuItem(item, app: menuBrowser.selectedApp?.app, to: existing)
        // 中身のあるマスに落とすと置き換わるので、元に戻せるようにし、グリッドの下でも戻せるようにする
        changeCells(
            String(localized: "メニュー項目の割り当て", bundle: .module),
            notice: existing == nil ? nil : String(localized: "マスの中身をメニュー項目で置き換えました", bundle: .module),
            profileID: profile.id,
            at: [target]
        ) {
            $0.setCell(cell, at: target, profileID: profile.id)
        }
        selectedPage = target.page
        selectedIndex = target.index
        gridMessage = nil
    }

    // MARK: - 元に戻す

    /// マスを変え、元に戻せるようにする。addresses は change で中身が変わる場所（変える前と後の中身を覚える）。
    /// notice があれば、グリッドの下に「元に戻す」と一緒に出す
    func changeCells(
        _ actionName: String,
        notice: String? = nil,
        profileID: UUID,
        at addresses: [CellAddress],
        _ change: (inout NonetConfiguration) -> Void
    ) {
        // インスペクタの変更のまとまりは、ここで閉じる（先に変えたものが下に積まれるように）
        closeEditGroup()
        let before = cellSnapshots(at: addresses, profileID: profileID)
        controller.update(change)
        let after = cellSnapshots(at: addresses, profileID: profileID)
        undoNotice = nil
        guard before != after else { return }
        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: undoTarget(for: profileID)) { [weak self] _ in
            self?.restoreCells(before, expecting: after, profileID: profileID, actionName: actionName)
        }
        undoManager.setActionName(actionName)
        undoManager.endUndoGrouping()
        undoNotice = notice.map { SettingsUndoNotice(text: $0, actionName: actionName) }
    }

    /// 覚えておいた中身に戻す（元に戻す・やり直す）。今の中身が変えた後のものと違えば（間にほかの変更があれば）戻さずに知らせる。
    /// 入れ替えで別の場所へ動いたマスは今の中身を使い、その後にインスペクタで変えたものを失わない。
    /// 戻すと消えたり上書きされたりするマスは、変えた後のままのときだけ戻す（作ったマスに書き足したスクリプトなどを消さない）
    func restoreCells(_ snapshots: [SettingsCellSnapshot], expecting expected: [SettingsCellSnapshot], profileID: UUID, actionName: String) {
        // 打ちかけの欄と記録中のキーを先に保存してから、今の中身を読む
        pendingEdits.flushAll()
        finishRecording()
        undoNotice = nil
        guard configuration.profile(id: profileID) != nil else { return }
        let addresses = snapshots.map(\.address)
        let current = cellSnapshots(at: addresses, profileID: profileID)
        let restored = snapshots.map { snapshot in
            guard let id = snapshot.cell?.id,
                  let moved = current.first(where: { $0.address != snapshot.address && $0.cell?.id == id })?.cell else { return snapshot }
            return SettingsCellSnapshot(address: snapshot.address, cell: moved)
        }
        let isUnchanged = current.map(\.cell?.id) == expected.map(\.cell?.id) && zip(current, expected).allSatisfy { now, then in
            guard let cell = now.cell else { return true }
            let isMoved = restored.contains { $0.address != now.address && $0.cell?.id == cell.id }
            return isMoved || cell == then.cell
        }
        guard isUnchanged else {
            if let address = addresses.first {
                reveal(address, profileID: profileID)
            }
            gridMessage = String(localized: "マスがその後に変わったため、元に戻せませんでした", bundle: .module)
            return
        }
        // 元に戻している間に登録したものは、やり直しになる
        changeCells(actionName, profileID: profileID, at: addresses) { configuration in
            // 先にすべて空けてから入れる（入れ替えた2つの id が途中で重なって、振り直されないように）
            for snapshot in restored {
                configuration.setCell(nil, at: snapshot.address, profileID: profileID)
            }
            for snapshot in restored {
                configuration.setCell(snapshot.cell, at: snapshot.address, profileID: profileID)
            }
        }
        if let address = addresses.first {
            reveal(address, profileID: profileID)
        }
    }

    func cellSnapshots(at addresses: [CellAddress], profileID: UUID) -> [SettingsCellSnapshot] {
        guard let profile = configuration.profile(id: profileID) else { return [] }
        return addresses.map { SettingsCellSnapshot(address: $0, cell: SettingsGrid.cell(at: $0, in: profile)) }
    }

    /// 元に戻したマスを選んで見せる。ほかのタブにいれば、プロファイルのタブに移る（見えないところで変わらないように）
    func reveal(_ address: CellAddress, profileID: UUID) {
        if tab != .profiles {
            selectTab(.profiles)
        }
        if selectedProfile.id != profileID {
            selectProfile(profileID)
        }
        selectedPage = address.page
        selectedIndex = address.index
        gridMessage = nil
    }

    /// グリッドの下の「元に戻す」。いちばん上の取り消しがその操作のときだけ戻す
    /// （間に文字の入力などの取り消しが積まれていれば、そちらを戻してしまうため）
    func undoFromNotice() {
        guard let notice = undoNotice else { return }
        undoNotice = nil
        guard undoManager.canUndo, undoManager.undoActionName == notice.actionName else { return }
        undoManager.undo()
    }

    private func forgetCellUndoAfterUndoing() {
        guard !profilesToForgetAfterUndo.isEmpty else { return }
        let profileIDs = profilesToForgetAfterUndo
        profilesToForgetAfterUndo = []
        discardCellUndo(forProfiles: profileIDs)
    }

    func undoTarget(for profileID: UUID) -> SettingsUndoTarget {
        if let target = undoTargets[profileID] {
            return target
        }
        let target = SettingsUndoTarget()
        undoTargets[profileID] = target
        return target
    }

    /// 読み込みでプロファイルを置き換えた後は、覚えた中身が合わなくなるので、
    /// そのプロファイルのマスの変更だけ元に戻せなくする（ほかのプロファイルの変更は残す）。
    /// プロファイルやページを消したとき・足したときは、それも元に戻せるので忘れない（取り消しは積んだ順に戻るので、場所はずれない）。
    /// 消したページを戻せなかったとき（取り消しに積まれない変更でページが上限になっていた）は、場所がずれるので忘れる
    func discardCellUndo(forProfiles profileIDs: [UUID]) {
        if let group = editGroup, profileIDs.contains(group.profileID) {
            editGroup = nil
        }
        for id in profileIDs {
            guard let target = undoTargets.removeValue(forKey: id) else { continue }
            undoManager.removeAllActions(withTarget: target)
        }
        undoNotice = nil
    }

    // MARK: - インスペクタ

    /// id のマスを書き換える（入れ替えた後でも同じマスに届くよう、場所ではなく id で探す）
    func updateCell(id: UUID, _ transform: (inout Cell) -> Void) {
        for profile in configuration.profiles {
            guard let address = SettingsGrid.address(ofCell: id, in: profile),
                  var cell = SettingsGrid.cell(at: address, in: profile) else { continue }
            let original = cell
            transform(&cell)
            cell.id = original.id
            guard cell != original else { return }
            controller.update { $0.setCell(cell, at: address, profileID: profile.id) }
            // 書き足した後に知らせから戻すと、その分まで消えるように見えるので知らせは閉じる（⌘Z では確かめてから戻す）
            undoNotice = nil
            recordInspectorEdit(cellID: id, profileID: profile.id, address: address, before: original)
            return
        }
    }

    func changeKind(ofCell id: UUID, to kind: ActionKind) {
        // 打ちかけを先に確定させ、切り替える前の中身として覚えておく
        pendingEdits.flushAll()
        guard let cell = cell(id: id), cell.action.kind != kind else { return }
        if recordingCellID == id {
            cancelRecording()
        }
        rememberedActions[id, default: [:]][cell.action.kind] = cell.action
        let remembered = rememberedActions[id]?[kind]
        updateCell(id: id) { $0 = SettingsCellEditing.changingKind(of: $0, to: kind, remembered: remembered) }
    }

    /// アクションを差し替える（自動で付いた名前とアイコンは合わせる）
    func replaceAction(ofCell id: UUID, with action: Action) {
        updateCell(id: id) { $0 = SettingsCellEditing.replacingAction(action, in: $0) }
    }

    /// 今の中身を読んで、その一部だけを書き換える。種類が変わっていれば何もしない。
    /// 入力欄の確定は少し遅れて届くので、描画したときの中身を丸ごと書き戻すと、その間に変えた設定や種類を戻してしまう
    func updateAction<Content: SettingsActionContent>(ofCell id: UUID, as type: Content.Type, _ transform: (inout Content) -> Void) {
        updateCell(id: id) { cell in
            if let updated = SettingsCellEditing.updatingContent(of: cell, as: type, transform) {
                cell = updated
            }
        }
    }

    func chooseApp(_ app: AppReference, forCell id: UUID) {
        updateCell(id: id) { $0 = SettingsCellEditing.choosingApp(app, in: $0) }
    }

    /// ファイルの操作を選ぶ。ゴミ箱に入れるは、押し間違えを防ぐため「少し長く止めてから実行」にする（あとで外せる）
    func chooseFileOperation(_ operation: FileOperation, forCell id: UUID) {
        updateCell(id: id) { cell in
            guard let updated = SettingsCellEditing.updatingContent(of: cell, as: FileAction.self, { $0.operation = operation }) else { return }
            let wasTrash = FileAction.content(of: cell.action)?.operation == .trash
            cell = updated
            if operation == .trash, !wasTrash {
                cell.requiresHold = true
            }
        }
    }

    /// 「画面に置く」の場所を選ぶ。名前とアイコンは場所に合わせて変わる（自分で付けたものは残る）
    func choosePlaceWindowRegion(_ region: WindowRegion, forCell id: UUID) {
        updateCell(id: id) { cell in
            guard let updated = SettingsCellEditing.updatingContent(of: cell, as: PlaceWindowAction.self, { $0.region = region }) else { return }
            cell = updated
        }
    }

    func cell(id: UUID) -> Cell? {
        for profile in configuration.profiles {
            if let address = SettingsGrid.address(ofCell: id, in: profile) {
                return SettingsGrid.cell(at: address, in: profile)
            }
        }
        return nil
    }

    private func location(ofCell id: UUID) -> (profile: Profile, cell: Cell)? {
        for profile in configuration.profiles {
            if let address = SettingsGrid.address(ofCell: id, in: profile), let cell = SettingsGrid.cell(at: address, in: profile) {
                return (profile, cell)
            }
        }
        return nil
    }

    // MARK: - テスト実行

    func startTestRun(cellID: UUID) {
        // ファイルの操作は、今 Finder で選んでいるファイルに実際に働くので、確かめてから行う
        if case .file(let file)? = cell(id: cellID)?.action {
            confirmation = .testRunFile(cellID: cellID, operation: file.operation.title)
            return
        }
        beginTestRun(cellID: cellID)
    }

    private func beginTestRun(cellID: UUID) {
        testTask?.cancel()
        testTask = Task { [weak self] in
            await self?.runTest(cellID: cellID)
        }
    }

    func runTest(cellID: UUID) async {
        guard let (profile, cell) = location(ofCell: cellID) else { return }
        lastTestRun = TestRun(cellID: cellID, record: nil)
        let record = await controller.testRun(cell, profileID: profile.id)
        // 結果を待つ間に別のマスを試していたら、古い結果は出さない
        guard lastTestRun?.cellID == cellID else { return }
        lastTestRun = TestRun(cellID: cellID, record: record)
    }

    func testRun(for cellID: UUID) -> TestRun? {
        lastTestRun?.cellID == cellID ? lastTestRun : nil
    }

    // MARK: - キーの記録

    var isRecording: Bool { recorder.isRecording }

    /// 記録欄とそのボタンのある場所。ここの外をクリックしたら記録を終える
    var recorderArea: NSView? {
        get { keyMonitor.recorderArea }
        set { keyMonitor.recorderArea = newValue }
    }

    func beginRecording(cellID: UUID) {
        finishRecording()
        guard cell(id: cellID) != nil else { return }
        recorder.start()
        recordingCellID = cellID
        controller.isRecordingKeys = true
        keyMonitor.start(
            keyDown: { [weak self] keyCode, characters, flags in
                self?.handleKeyDown(keyCode: keyCode, characters: characters, flags: flags)
            },
            flagsChanged: { [weak self] flags in
                self?.handleFlagsChanged(flags)
            },
            click: { [weak self] insideRecorder in
                self?.handleClick(insideRecorder: insideRecorder)
            }
        )
    }

    /// 記録中のクリック。記録欄の外（ほかの欄・ボタン・別のウィンドウ）なら、押したキーを保存して記録を終える。
    /// 続けると、ほかの欄に打つ文字まで記録に入ってしまう
    func handleClick(insideRecorder: Bool) {
        guard !insideRecorder else { return }
        finishRecording()
    }

    func handleKeyDown(keyCode: UInt16, characters: String?, flags: NSEvent.ModifierFlags) {
        apply(recorder.keyDown(keyCode: keyCode, characters: characters, flags: flags))
    }

    func handleFlagsChanged(_ flags: NSEvent.ModifierFlags) {
        recorder.flagsChanged(flags)
    }

    func appendEscapeToRecording() {
        apply(recorder.appendEscape())
    }

    func removeLastRecordedChord() {
        recorder.removeLast()
    }

    /// 記録を終え、押したキーがあれば保存する
    func finishRecording() {
        guard recorder.isRecording else { return }
        apply(recorder.finish())
    }

    /// 何も変えずに記録をやめる
    func cancelRecording() {
        guard recorder.isRecording || recordingCellID != nil else { return }
        recorder.cancel()
        endRecording()
    }

    private func apply(_ outcome: SettingsKeyRecorder.Outcome) {
        switch outcome {
        case .recording:
            break
        case .finished(let keys):
            if let id = recordingCellID {
                updateAction(ofCell: id, as: KeySequence.self) { $0 = keys }
            }
            endRecording()
        case .cancelled:
            endRecording()
        }
    }

    private func endRecording() {
        keyMonitor.stop()
        recordingCellID = nil
        controller.isRecordingKeys = false
    }

    // MARK: - 一般

    func setSetting<Value: Equatable>(_ keyPath: WritableKeyPath<GlobalSettings, Value>, _ value: Value) {
        guard settings[keyPath: keyPath] != value else { return }
        controller.update { $0.settings[keyPath: keyPath] = value }
    }

    /// システム設定から戻ったときなど。望んでいた状態になっていれば、前の知らせは消す
    /// （システム設定の「ログイン項目」で許可されたのに、できなかったと出し続けないように）
    func refreshLoginItem() {
        loginItemEnabled = services.loginItem.isEnabled
        if let wanted = loginItemWanted, wanted == loginItemEnabled {
            loginItemError = nil
            loginItemWanted = nil
        }
    }

    func setLoginItemEnabled(_ enabled: Bool) {
        do {
            try services.loginItem.setEnabled(enabled)
            loginItemError = nil
            loginItemWanted = nil
        } catch NonetError.permissionDenied where enabled {
            // 登録はできたが、システム設定の「ログイン項目」で許可されるまで動かない（システム設定はサービスが開く）
            settingsLog.info("ログイン時に起動するには、システム設定での許可が要ります")
            loginItemError = String(localized: "システム設定の「ログイン項目」で Nonet を許可すると、ログイン時に起動するようになります", bundle: .module)
            loginItemWanted = enabled
        } catch {
            settingsLog.error("ログイン時に起動を変えられませんでした: \(error.localizedDescription, privacy: .public)")
            let reason = error.localizedDescription
            loginItemError = enabled
                ? String(localized: "ログイン時に起動するように設定できませんでした（\(reason)）", bundle: .module)
                : String(localized: "ログイン時に起動しないように設定できませんでした（\(reason)）", bundle: .module)
            loginItemWanted = enabled
        }
        loginItemEnabled = services.loginItem.isEnabled
    }

    // MARK: - 状態の帯

    var statusBanner: SettingsStatusBanner? {
        SettingsStatusBanner(status: controller.status)
    }

    func perform(_ action: SettingsStatusBanner.Action) {
        switch action {
        case .openAccessibilitySettings:
            // 最初はダイアログだけ（一覧に Nonet が載り、ダイアログの「システム設定を開く」で開ける）。
            // ダイアログとシステム設定を同時に出すと、システム設定の上に「拒否」のあるダイアログが重なる
            if hasRequestedAccessibility {
                services.permissions.openAccessibilitySettings()
            } else {
                hasRequestedAccessibility = true
                services.permissions.requestAccessibility()
            }
        case .recheck:
            break
        case .enable:
            setSetting(\.isEnabled, true)
        }
        controller.refreshPermissions()
    }

    // MARK: - 書き出しと読み込み

    func exportProfiles(_ profiles: [Profile], suggestedName: String) async {
        guard let files, let url = await files.chooseExportDestination(suggestedName: suggestedName) else { return }
        exportProfiles(profiles, to: url)
    }

    /// すべての書き出し
    func exportAllProfiles(suggestedName: String) async {
        await exportProfiles(configuration.profiles, suggestedName: suggestedName)
    }

    func exportProfiles(_ profiles: [Profile], to url: URL) {
        do {
            let data = try ConfigurationStore.exportData(profiles: profiles)
            try data.write(to: url, options: .atomic)
            fileMessage = SettingsMessage(
                text: String(localized: "\(profiles.count)個のプロファイルを「\(url.lastPathComponent)」に書き出しました。", bundle: .module, locale: .nonetUI),
                isError: false
            )
        } catch {
            settingsLog.error("プロファイルを書き出せませんでした: \(error.localizedDescription, privacy: .public)")
            fileMessage = SettingsMessage(text: SettingsText.fileError(error, reading: false), isError: true)
        }
    }

    func importProfiles() async {
        guard let files, let url = await files.chooseImportSource() else { return }
        importProfiles(from: url)
    }

    /// ファイルを読み、今のプロファイルやグローバルのページが置き換わるなら先に確かめる（元に戻せないため）。
    /// 何かを実行するマス（スクリプト・キー入力・メニュー項目・AI・ファイルを開く URL）があるときも、何も置き換わらなくても中身をすべて見せて先に確かめる（読み込むとすぐ、あなたの権限で動かせるため）
    static let maxImportFileSize = 20 * 1024 * 1024

    func importProfiles(from url: URL) {
        let document: ConfigurationStore.ImportedProfiles
        do {
            // 書き出したファイルは、大きくても数百 KB。巨大なファイルは、読み込む前に断る
            if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > Self.maxImportFileSize {
                throw CocoaError(.fileReadTooLarge)
            }
            let data = try Data(contentsOf: url)
            document = try ConfigurationStore.importDocument(from: data)
        } catch {
            settingsLog.error("プロファイルを読み込めませんでした: \(error.localizedDescription, privacy: .public)")
            fileMessage = SettingsMessage(text: SettingsText.fileError(error, reading: true), isError: true)
            return
        }
        let plan = SettingsImportPlan(document: document, configuration: configuration, fileName: url.lastPathComponent, keys: keyCharacters)
        if plan.needsConfirmation {
            importReviewReachedEnd = false
            confirmation = .importProfiles(plan)
        } else {
            // plan.document はメニュー項目の長いショートカットを除いたもの
            applyImport(plan.document)
        }
    }

    /// 読み込む前の確認で、読み込んでよいか。何かを実行するマスがあれば、その中身を最後まで見てから
    func canConfirmImport(_ plan: SettingsImportPlan) -> Bool {
        !plan.hasReviewedCells || importReviewReachedEnd
    }

    /// 確認の欄を最後までスクロールした（SettingsImportReviewSheet）
    func markImportReviewRead() {
        if !importReviewReachedEnd {
            importReviewReachedEnd = true
        }
    }

    /// 置き換えるものは読まず、新しいアプリのプロファイルだけ加える。マスの中身を最後まで見ていなければ何もしない
    func importNewProfilesOnly(_ plan: SettingsImportPlan) {
        guard canConfirmImport(plan) else { return }
        confirmation = nil
        applyImport(plan.newProfilesOnly(in: configuration))
    }

    private func applyImport(_ document: ConfigurationStore.ImportedProfiles) {
        pendingEdits.flushAll()
        finishRecording()
        closeEditGroup()
        backupStore?.makeBackup(of: configuration, reason: .beforeImport)
        let before = configuration.profiles
        var result = NonetConfiguration.ImportResult()
        controller.update { result = $0.importProfiles(document) }
        // 置き換わったプロファイルの分だけ忘れる。新しいプロファイルを加えただけなら、ほかの変更は戻せるままにする
        let replacedIDs = before.filter { configuration.profile(id: $0.id)?.pages != $0.pages }.map(\.id)
        discardCellUndo(forProfiles: replacedIDs)
        fileMessage = SettingsMessage(
            // 重なっていて読み込まなかったプロファイルのスクリプトは数えない（読み込む前の確認と同じ決まり）
            text: SettingsText.importSummary(result, containsScripts: SettingsImportPlan.containsScripts(in: document)),
            isError: result.appliedCount == 0
        )
    }

    // MARK: - アプリの一覧

    func loadInstalledAppsIfNeeded() {
        guard !installedAppsLoaded else { return }
        installedApps = services.installedApps.installedApps()
        installedAppsLoaded = true
    }

    /// 一覧を出すたびに読み直す（Nonet は何週間も動き続けるので、後で入れたアプリも出す）。
    /// 実際のサービスは30秒覚えているので、続けて開いても重くない
    func reloadInstalledApps() {
        installedAppsLoaded = false
        loadInstalledAppsIfNeeded()
    }

    // MARK: - メニューから割り当て

    func showMenus(_ show: Bool) {
        if show {
            finishRecording()
            rightPanel = .menus
            menuBrowser.refreshApps(preferredBundleID: selectedProfile.app?.bundleID)
        } else {
            rightPanel = .inspector
        }
    }

    // MARK: - ライセンス

    var isLicensed: Bool {
        if case .licensed = license.entitlement { return true }
        return false
    }

    /// ライセンスキーの欄を出すか（登録していないとき、または「別のキーを登録…」を押したとき）
    var showsLicenseKeyField: Bool {
        !isLicensed || isEnteringAnotherKey
    }

    /// どのタブでも上に出す「試用期間が終了しました」の帯。ライセンスのタブには同じことが書いてあるので出さない
    var showsExpiredBanner: Bool {
        license.entitlement == .expired && tab != .license
    }

    func activateLicense() {
        let input = licenseKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        do {
            try license.activate(licenseKey: input)
            licenseKeyInput = ""
            isEnteringAnotherKey = false
            pendingLicense = nil
            licenseMessage = SettingsMessage(text: String(localized: "登録しました。ご購入ありがとうございます。", bundle: .module), isError: false)
        } catch {
            licenseMessage = SettingsMessage(text: SettingsText.licenseError(error, input: input), isError: true)
        }
    }

    func deactivateLicense() {
        license.deactivate()
        isEnteringAnotherKey = false
        licenseMessage = SettingsMessage(text: String(localized: "この Mac から登録を消しました", bundle: .module), isError: false)
    }

    /// 登録済みのキーをコピーする（同じキーを、自分のほかの Mac にも登録できる）
    func copyLicenseKey() {
        guard let key = license.registeredLicenseKey else { return }
        copyToPasteboard(key)
        licenseMessage = SettingsMessage(text: String(localized: "ライセンスキーをコピーしました", bundle: .module), isError: false)
    }

    /// 「別のキーを登録…」と、そのやめる
    func setEnteringAnotherKey(_ entering: Bool) {
        isEnteringAnotherKey = entering
        licenseKeyInput = ""
        licenseMessage = nil
        wantsLicenseKeyFocus = entering
    }

    /// ライセンスのタブに移り、ライセンスキーの欄に入力できるようにする
    func showLicenseKeyEntry() {
        selectTab(.license)
        if isLicensed {
            isEnteringAnotherKey = true
        }
        wantsLicenseKeyFocus = true
    }

    /// リンクやファイルから開いたキー。欄に入れて検証し、正しければ登録者を見せて尋ねる（pendingLicense）。
    /// 正しくなければ、手で貼り付けたときと同じ理由を出す
    func openLicenseLink(_ content: SettingsLicenseLink.Content) {
        selectTab(.license)
        pendingLicense = nil
        guard case .text(let text) = content else {
            licenseMessage = SettingsMessage(
                text: String(localized: "リンクからライセンスキーを読み取れませんでした。購入時のメールからキーをコピーして、ここに貼り付けてください。", bundle: .module),
                isError: true
            )
            return
        }
        if isLicensed {
            isEnteringAnotherKey = true
        }
        licenseKeyInput = text
        do {
            let verified = try license.verify(licenseKey: text)
            licenseKeyInput = verified.key
            if verified.key == license.registeredLicenseKey {
                licenseKeyInput = ""
                isEnteringAnotherKey = false
                licenseMessage = SettingsMessage(text: String(localized: "このライセンスキーは登録済みです", bundle: .module), isError: false)
                return
            }
            licenseMessage = nil
            pendingLicense = verified
        } catch {
            licenseMessage = SettingsMessage(text: SettingsText.licenseError(error, input: text), isError: true)
        }
    }

    /// 尋ねたキーを登録する
    func confirmPendingLicense() {
        guard let pending = pendingLicense else { return }
        pendingLicense = nil
        licenseKeyInput = pending.key
        activateLicense()
    }

    /// 登録しない。キーは欄に残すので、後から「登録」を押せる
    func cancelPendingLicense() {
        pendingLicense = nil
    }

    /// クリップボードの履歴を残すアプリに覚えさせない印を付けて、文字としてコピーする（ライセンスキーには名前とメールアドレスが入る）
    static func copyConcealed(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        pasteboard.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
    }

    // MARK: - お問い合わせ

    /// 「お問い合わせ…」のメール。宛先が無ければ nil
    var supportMail: SettingsSupportMail? {
        guard let supportEmail else { return nil }
        return SettingsSupportMail(
            address: supportEmail,
            details: SettingsSupportMail.currentDetails()
        )
    }

    /// メールのアプリで、宛先・件名・本文を入れたメールを開く
    func contactSupport() {
        guard let url = supportMail?.url else { return }
        openURL(url)
    }

    // MARK: - アンインストール

    func requestUninstall() {
        uninstallStep = .confirm
    }

    /// 確かめた後。ゴミ箱に入れ終えたら、最後にすること（アクセシビリティの許可を外す）を伝える
    func uninstall() {
        pendingEdits.flushAll()
        finishRecording()
        do {
            let result = try uninstaller.run(loginItem: services.loginItem) { controller.stop() }
            uninstallStep = .finished(result)
        } catch {
            uninstallStep = .failed
        }
    }

    /// アクセシビリティの欄を開いて終了する（ゴミ箱に入れた後の知らせを閉じたとき）
    func finishUninstall() {
        uninstallStep = nil
        services.permissions.openAccessibilitySettings()
        terminate()
    }

    // MARK: - 確認

    func confirm(_ confirmation: Confirmation) {
        // 読み込むマスの中身を最後まで見ていなければ、確認を出したままにする
        if case .importProfiles(let plan) = confirmation, !canConfirmImport(plan) { return }
        self.confirmation = nil
        switch confirmation {
        case .deleteProfile(let id, _):
            deleteProfile(id)
        case .removePage(let profileID, let index):
            removePage(index, profileID: profileID)
        case .deactivateLicense:
            deactivateLicense()
        case .importProfiles(let plan):
            applyImport(plan.document)
        case .resetProfile(let id, _):
            resetProfileToPreset(id)
        case .testRunFile(let cellID, _):
            beginTestRun(cellID: cellID)
        }
    }

    // MARK: - ウィンドウ

    /// 開き直したときや、ほかのアプリから戻ったとき。閉じるときに止めた読み込みを続け、古くなった一覧を読み直す
    /// （使い回すウィンドウでは onAppear がもう一度呼ばれないため、ここで行う）
    func windowDidBecomeKey() {
        controller.refreshPermissions()
        refreshLoginItem()
        license.refresh()
        // ショートカット.app で作ってから戻ってきたときに、見つからないと言わないように
        shortcutList.markStale()
        if case .shortcut? = selectedCell?.action {
            shortcutList.loadIfNeeded()
        }
        if rightPanel == .menus {
            menuBrowser.resume(preferredBundleID: selectedProfile.app?.bundleID)
        }
    }

    /// ほかのアプリに移ったら記録を終える（記録中は9マスが開かないため）
    func windowDidResignKey() {
        finishRecording()
        closeEditGroup()
    }

    /// アプリを終える前（NonetController.stop() で待っている保存を書くより先に）。打ちかけの欄と記録中のキーを確定させる。
    /// 終了ではウィンドウが閉じないので windowWillClose() は来ない
    func applicationWillTerminate() {
        pendingEdits.flushAll()
        finishRecording()
    }

    func windowWillClose() {
        pendingEdits.flushAll()
        finishRecording()
        cancelRecording()
        menuBrowser.cancel()
        shortcutList.cancel()
        confirmation = nil
        isAddingProfile = false
        isShowingBackups = false
        renamingPage = nil
        closeEditGroup()
    }
}

/// ショートカット.app のショートカットの名前（読むのに時間がかかる）
@MainActor
@Observable
final class SettingsShortcutList {
    enum State: Equatable {
        case idle
        case loading
        case loaded([String])
    }

    private(set) var state: State = .idle
    /// 読み込んだ一覧を出したまま、読み直している
    private(set) var isRefreshing = false
    @ObservationIgnored private let shortcuts: any ShortcutsProviding
    @ObservationIgnored private var task: Task<Void, Never>?
    /// 読み込んだ一覧が古いかもしれない（ウィンドウに戻ってきたとき）
    @ObservationIgnored private var isStale = false

    init(shortcuts: any ShortcutsProviding) {
        self.shortcuts = shortcuts
    }

    /// まだ読んでいないか、古くなっていれば読む
    func loadIfNeeded() {
        switch state {
        case .idle:
            reload()
        case .loaded where isStale && !isRefreshing:
            reload()
        case .loaded, .loading:
            break
        }
    }

    func markStale() {
        isStale = true
    }

    /// 読み直す。読み込んだ一覧があれば、読み終わるまでそれを出しておく（見つからないという注意がちらつかないよう）
    func reload() {
        task?.cancel()
        isStale = false
        if case .loaded = state {
            isRefreshing = true
        } else {
            state = .loading
        }
        task = Task { [weak self, shortcuts] in
            let names = await shortcuts.shortcutNames()
            guard !Task.isCancelled, let self else { return }
            var seen = Set<String>()
            self.state = .loaded(names.filter { !$0.isEmpty && seen.insert($0).inserted }
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending })
            self.isRefreshing = false
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        if state == .loading {
            state = .idle
        }
        if isRefreshing {
            isRefreshing = false
            isStale = true
        }
    }

    /// 終わるまで待つ（テスト用）
    func waitUntilLoaded() async {
        await task?.value
    }
}

/// 記録中だけ、このアプリに来たキーを横取りする（ほかの欄やメニューのショートカットに渡さない）。
/// クリックは横取りせず、記録欄の外かどうかを知らせる
@MainActor
final class SettingsKeyEventMonitor {
    private var monitor: Any?
    /// 記録欄とそのボタンのある場所（SwiftUI の背景に置いた NSView）
    weak var recorderArea: NSView?

    func start(
        keyDown: @escaping (UInt16, String?, NSEvent.ModifierFlags) -> Void,
        flagsChanged: @escaping (NSEvent.ModifierFlags) -> Void,
        click: @escaping (_ insideRecorder: Bool) -> Void
    ) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            switch event.type {
            case .keyDown:
                // 押しっぱなしで同じキーが何度も入らないように
                if !event.isARepeat {
                    let characters = event.characters(byApplyingModifiers: []) ?? event.charactersIgnoringModifiers
                    keyDown(event.keyCode, characters, event.modifierFlags)
                }
                return nil
            case .flagsChanged:
                flagsChanged(event.modifierFlags)
                return event
            case .leftMouseDown, .rightMouseDown, .otherMouseDown:
                click(Self.contains(self?.recorderArea, locationInWindow: event.locationInWindow, of: event.window))
                return event
            default:
                return event
            }
        }
    }

    /// window の locationInWindow が area の中か。area が別のウィンドウにあれば外
    static func contains(_ area: NSView?, locationInWindow: NSPoint, of window: NSWindow?) -> Bool {
        guard let area, let window, area.window === window else { return false }
        return area.bounds.contains(area.convert(locationInWindow, from: nil))
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }
}
